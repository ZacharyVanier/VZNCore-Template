-- Entity storage: sparse-set entity index over archetype-backed component columns.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

--##========== DEPENDENCIES ==========##--

local function tryRequire(robloxPath: any, relativePath: any): any
	local ok, result = pcall(function()
		return require(robloxPath)
	end)
	if ok then
		return result
	end
	return require(relativePath)
end

local Cleanup = tryRequire(script and script.Parent and script.Parent.Cleanup, "./Cleanup")
local Archetype = tryRequire(script and script.Parent and script.Parent.Archetype, "./Archetype")
local Component = tryRequire(script and script.Parent and script.Parent.Component, "./Component")
local ECSTypes = tryRequire(script and script.Parent and script.Parent.Types, `./Types`)

local _traverseAdd = Archetype.traverseAdd
local _traverseRemove = Archetype.traverseRemove
local _moveEntity = Archetype.moveEntity
local _newEntity = Component.newEntity

--##========== TYPES ==========##--

type Entity = number
type ComponentMetadata = ECSTypes.ComponentMetadata
type SpawnBundle = ECSTypes.SpawnBundle
type StructuralPatch = ECSTypes.StructuralPatch
type StructuralPatchSpec = ECSTypes.StructuralPatchSpec
type CompiledArchetypePlan = ECSTypes.CompiledArchetypePlan

-- A component key is either a name (string, resolved to its id) or an already
-- resolved id (number: a plain component id or a packed pair). Storage keys on
-- the id; a string arriving from the string API is interned here.
type ComponentKey = string | number

type Record = {
	dense: number,
	row: number,
	archetype: any,
}

type EntityIndex = {
	sparseArray: { [number]: Record },
	denseArray: { [number]: Entity },
	aliveCount: number,
}

type DirtyEntry = {
	entity: Entity,
	name: string,
}

--##========== ENTITY ID PACKING ==========##--

local ENTITY_MASK = bit32.lshift(1, 24)
local GENERATION_MASK = bit32.lshift(1, 16)

local function _incrementGeneration(packed: Entity): Entity
	if packed > ENTITY_MASK then
		local slot = packed % ENTITY_MASK
		local generation = packed // ENTITY_MASK
		local nextGeneration = generation + 1

		if nextGeneration >= GENERATION_MASK then
			return slot
		end

		return slot + nextGeneration * ENTITY_MASK
	end

	return packed + ENTITY_MASK
end

--##========== COMPONENT KEY RESOLUTION ==========##--

-- Collapses a string name to its interned id; numbers (plain ids and pairs)
-- pass through. The World boundary already resolves handles, so only these two
-- shapes reach the store.
local function _keyOf(component: ComponentKey): number
	if type(component) == "string" then
		return Component.idOf(component)
	end

	return component :: number
end

--##========== ENTITY INDEX ==========##--

local function _indexTryGet(index: EntityIndex, entity: Entity): Record?
	local record = index.sparseArray[(entity % ENTITY_MASK)]
	if not record then
		return nil
	end

	if record.dense > index.aliveCount then
		return nil
	end

	if index.denseArray[record.dense] ~= entity then
		return nil
	end

	return record
end

local function _indexNewId(index: EntityIndex, archetype: any): (Entity, number)
	local denseArray = index.denseArray
	local id: Entity
	local record: Record

	if index.aliveCount ~= #denseArray then
		index.aliveCount += 1
		id = denseArray[index.aliveCount]
		record = index.sparseArray[(id % ENTITY_MASK)]
	else
		id = _newEntity()
		index.aliveCount += 1
		denseArray[index.aliveCount] = id

		record = {
			dense = index.aliveCount,
			row = 0,
			archetype = archetype,
		}
		index.sparseArray[id] = record
	end

	local entities = archetype.entities
	local row = #entities + 1
	entities[row] = id
	record.archetype = archetype
	record.row = row

	return id, row
end

local function _indexRemove(index: EntityIndex, entity: Entity): ()
	local sparseArray = index.sparseArray
	local denseArray = index.denseArray

	local record = sparseArray[(entity % ENTITY_MASK)]
	local removedDense = record.dense
	local lastDense = index.aliveCount
	local lastEntity = denseArray[lastDense]

	denseArray[removedDense] = lastEntity
	sparseArray[(lastEntity % ENTITY_MASK)].dense = removedDense

	denseArray[lastDense] = _incrementGeneration(entity)
	record.dense = lastDense

	index.aliveCount = lastDense - 1
end

--##========== PRIVATE HELPERS ==========##--

local function _flatten(archetypes: { any }): { Entity }
	local result: { Entity } = {}

	for _, archetype in archetypes do
		local entities = archetype.entities
		for row = 1, #entities do
			table.insert(result, entities[row])
		end
	end

	return result
end

-- Splits query terms into archetypal ids (held in archetype signatures) and
-- sparse ids (held outside them). Archetypal terms resolve per-archetype,
-- sparse terms per-entity.
local function _partitionBySparse(ids: { number }): ({ number }, { number })
	local archetypal: { number } = {}
	local sparse: { number } = {}

	for _, id in ids do
		if Component.isSparseId(id) then
			table.insert(sparse, id)
		else
			table.insert(archetypal, id)
		end
	end

	return archetypal, sparse
end

-- True if any all/any/none term references a sparse component. Non-sparse
-- queries keep the untouched archetype fast path (and its cache); sparse
-- support therefore costs nothing until a query actually mixes one in.
local function _queryTouchesSparse(query: any): boolean
	for _, id in query._all do
		if Component.isSparseId(id) then
			return true
		end
	end

	for _, id in query._any do
		if Component.isSparseId(id) then
			return true
		end
	end

	for _, id in query._none do
		if Component.isSparseId(id) then
			return true
		end
	end

	return false
end

local function _assertStructuralMutationAllowed(store: any): ()
	if (store._activeQueryStates or 0) > 0 then
		error(`[Entity] Structural mutation is not allowed during compiled query iteration`)
	end
end

local function _resolvePatchDestination(store: any, patch: StructuralPatch, source: any): any
	local destination = source

	for index, componentId in patch.removeIds do
		if not patch.removeMetadata[index].isSparse and destination.columnsMap[componentId] then
			destination = _traverseRemove(store, destination, componentId)
		end
	end

	for index, componentId in patch.addIds do
		local metadata = patch.addMetadata[index]
		if metadata.isPair then
			local relation = Component.pairFirst(componentId)
			if Cleanup.isExclusive(relation) then
				for _, existingId in destination.types do
					if
						existingId ~= componentId
						and Component.isPair(existingId)
						and Component.pairFirst(existingId) == relation
					then
						destination = _traverseRemove(store, destination, existingId)
						break
					end
				end
			end
		end

		if not metadata.isSparse then
			destination = _traverseAdd(store, destination, componentId)
		end
	end

	patch._transitions[source.id] = destination

	return destination
end

local function _mutatePatch(
	store: any,
	id: Entity,
	patch: StructuralPatch,
	captureRemovedData: boolean,
	...: any
): { any }?
	if patch._lifecycle.destroyed then
		error(`[Entity] Structural patch has been destroyed`)
	end

	if patch._entityStore ~= store then
		error(`[Entity] Structural patch belongs to a different entity store`)
	end

	local providedDataCount = select(`#`, ...)
	if providedDataCount ~= patch.dataCount then
		error(`[Entity] Structural patch expected {patch.dataCount} data values, got {providedDataCount}`)
	end

	local record = _indexTryGet(store._entityIndex, id)
	if not record then
		error(`[Entity] Cannot mutate non-alive entity {id}`)
	end

	if patch.operationCount == 0 then
		return if captureRemovedData then {} else nil
	end

	_assertStructuralMutationAllowed(store)

	local relationTraitRevision = Cleanup.relationTraitRevision()
	if store._relationTraitRevision ~= relationTraitRevision then
		for compiledPatch in store._compiledPatches do
			table.clear(compiledPatch._transitions)
		end
		store._relationTraitRevision = relationTraitRevision
	end

	local removedData: { any }? = if captureRemovedData then table.create(#patch.removeIds) else nil
	if removedData then
		local source = record.archetype
		for index, componentId in patch.removeIds do
			if patch.removeMetadata[index].isSparse then
				local sparseColumn = store._sparse[componentId]
				removedData[index] = if sparseColumn then sparseColumn[id] else nil
			else
				local column = source.columnsMap[componentId]
				removedData[index] = if column then column[record.row] else nil
			end
		end
	end

	local source = record.archetype
	local destination = patch._transitions[source.id]
	if not destination then
		destination = _resolvePatchDestination(store, patch, source)
	end

	if destination ~= source then
		Archetype.moveEntity(store, id, record, destination)
	end

	for index, componentId in patch.removeIds do
		if patch.removeMetadata[index].isSparse then
			local sparseColumn = store._sparse[componentId]
			if sparseColumn then
				sparseColumn[id] = nil
			end
		end
	end

	local columnsMap = record.archetype.columnsMap
	local row = record.row
	for index, componentId in patch.addIds do
		local dataPosition = patch.dataPositions[index]
		if dataPosition == 0 then
			continue
		end

		local data = select(dataPosition, ...)
		if patch.addMetadata[index].isSparse then
			local sparseColumn = store._sparse[componentId]
			if not sparseColumn then
				sparseColumn = {}
				store._sparse[componentId] = sparseColumn
			end
			sparseColumn[id] = data
		else
			columnsMap[componentId][row] = data
		end
	end

	return removedData
end

-- Drops pair ids no longer present in any live archetype from a pair index,
-- then removes buckets that become empty. sweep() calls this after empty
-- archetypes are destroyed, reclaiming the stale _pairsBy* entries they left.
local function _prunePairIndex(index: { [number]: { [number]: boolean } }, livePairs: { [number]: boolean }): ()
	for key, bucket in index do
		for pairId in bucket do
			if not livePairs[pairId] then
				bucket[pairId] = nil
			end
		end

		if next(bucket) == nil then
			index[key] = nil
		end
	end
end

--##========== QUERY ARCHETYPE RESOLUTION ==========##--

local EMPTY_ENTITIES: { Entity } = {}
local EMPTY_COLUMN: { any } = {}

-- The archetype list a query matches, cache-aware. A cached query stores its
-- matching archetypes in _queryCache and keeps that array live as archetypes are
-- created/destroyed (Archetype._registerCreated/_unregisterDestroyed edit it in
-- place), so collectEntities and the streaming iterator share one snapshot.
local function _matchingArchetypes(store: any, query: any): { any }
	if query._cached then
		local cached = store._queryCache[query]
		if cached then
			return cached
		end

		local matching: { any } = {}
		for _, archetype in store._archetypes do
			if Archetype.match(archetype, query) then
				table.insert(matching, archetype)
			end
		end

		store._queryCache[query] = matching
		table.insert(store._cachedQueries, query)

		return matching
	end

	local matching: { any } = {}
	for _, archetype in store._archetypes do
		if Archetype.match(archetype, query) then
			table.insert(matching, archetype)
		end
	end

	return matching
end

-- Column-streaming iterators, one per arity. Each walks a matched archetype's
-- dense entities and component columns directly by row index -- no per-entity
-- index resolve, no materialised id array. Upvalues are read into locals in the
-- hot path and only rewritten when advancing to the next archetype, mirroring
-- the jecs cached-query codegen.
local function _stream0(archetypes: { any }): () -> ...any
	local lastArch = 0
	local entitiesUp: { Entity } = EMPTY_ENTITIES
	local cursor = 0

	local first = archetypes[1]
	if first then
		entitiesUp = first.entities
		cursor = #entitiesUp
		lastArch = 1
	end

	return function(): ...any
		local entities = entitiesUp
		local entity = entities[cursor]

		while entity == nil do
			lastArch += 1
			local nextArch = archetypes[lastArch]
			if nextArch == nil then
				return nil
			end

			entities = nextArch.entities
			cursor = #entities
			if cursor == 0 then
				continue
			end

			entity = entities[cursor]
			entitiesUp = entities
		end

		cursor -= 1
		return entity
	end
end

local function _stream1(archetypes: { any }, id0: number): () -> ...any
	local lastArch = 0
	local entitiesUp: { Entity } = EMPTY_ENTITIES
	local cursor = 0
	local col0Up: { any } = EMPTY_COLUMN

	local first = archetypes[1]
	if first then
		entitiesUp = first.entities
		cursor = #entitiesUp
		col0Up = first.columnsMap[id0]
		lastArch = 1
	end

	return function(): ...any
		local entities = entitiesUp
		local entity = entities[cursor]
		local col0 = col0Up

		while entity == nil do
			lastArch += 1
			local nextArch = archetypes[lastArch]
			if nextArch == nil then
				return nil
			end

			entities = nextArch.entities
			cursor = #entities
			if cursor == 0 then
				continue
			end

			entity = entities[cursor]
			entitiesUp = entities
			col0 = nextArch.columnsMap[id0]
			col0Up = col0
		end

		local row = cursor
		cursor -= 1
		return entity, col0[row]
	end
end

local function _stream2(archetypes: { any }, id0: number, id1: number): () -> ...any
	local lastArch = 0
	local entitiesUp: { Entity } = EMPTY_ENTITIES
	local cursor = 0
	local col0Up: { any } = EMPTY_COLUMN
	local col1Up: { any } = EMPTY_COLUMN

	local first = archetypes[1]
	if first then
		entitiesUp = first.entities
		cursor = #entitiesUp
		col0Up = first.columnsMap[id0]
		col1Up = first.columnsMap[id1]
		lastArch = 1
	end

	return function(): ...any
		local entities = entitiesUp
		local entity = entities[cursor]
		local col0 = col0Up
		local col1 = col1Up

		while entity == nil do
			lastArch += 1
			local nextArch = archetypes[lastArch]
			if nextArch == nil then
				return nil
			end

			entities = nextArch.entities
			cursor = #entities
			if cursor == 0 then
				continue
			end

			entity = entities[cursor]
			entitiesUp = entities
			local cmap = nextArch.columnsMap
			col0 = cmap[id0]
			col1 = cmap[id1]
			col0Up = col0
			col1Up = col1
		end

		local row = cursor
		cursor -= 1
		return entity, col0[row], col1[row]
	end
end

local function _stream3(archetypes: { any }, id0: number, id1: number, id2: number): () -> ...any
	local lastArch = 0
	local entitiesUp: { Entity } = EMPTY_ENTITIES
	local cursor = 0
	local col0Up: { any } = EMPTY_COLUMN
	local col1Up: { any } = EMPTY_COLUMN
	local col2Up: { any } = EMPTY_COLUMN

	local first = archetypes[1]
	if first then
		entitiesUp = first.entities
		cursor = #entitiesUp
		local cmap = first.columnsMap
		col0Up = cmap[id0]
		col1Up = cmap[id1]
		col2Up = cmap[id2]
		lastArch = 1
	end

	return function(): ...any
		local entities = entitiesUp
		local entity = entities[cursor]
		local col0 = col0Up
		local col1 = col1Up
		local col2 = col2Up

		while entity == nil do
			lastArch += 1
			local nextArch = archetypes[lastArch]
			if nextArch == nil then
				return nil
			end

			entities = nextArch.entities
			cursor = #entities
			if cursor == 0 then
				continue
			end

			entity = entities[cursor]
			entitiesUp = entities
			local cmap = nextArch.columnsMap
			col0 = cmap[id0]
			col1 = cmap[id1]
			col2 = cmap[id2]
			col0Up = col0
			col1Up = col1
			col2Up = col2
		end

		local row = cursor
		cursor -= 1
		return entity, col0[row], col1[row], col2[row]
	end
end

local function _stream4(archetypes: { any }, id0: number, id1: number, id2: number, id3: number): () -> ...any
	local lastArch = 0
	local entitiesUp: { Entity } = EMPTY_ENTITIES
	local cursor = 0
	local col0Up: { any } = EMPTY_COLUMN
	local col1Up: { any } = EMPTY_COLUMN
	local col2Up: { any } = EMPTY_COLUMN
	local col3Up: { any } = EMPTY_COLUMN

	local first = archetypes[1]
	if first then
		entitiesUp = first.entities
		cursor = #entitiesUp
		local cmap = first.columnsMap
		col0Up = cmap[id0]
		col1Up = cmap[id1]
		col2Up = cmap[id2]
		col3Up = cmap[id3]
		lastArch = 1
	end

	return function(): ...any
		local entities = entitiesUp
		local entity = entities[cursor]
		local col0 = col0Up
		local col1 = col1Up
		local col2 = col2Up
		local col3 = col3Up

		while entity == nil do
			lastArch += 1
			local nextArch = archetypes[lastArch]
			if nextArch == nil then
				return nil
			end

			entities = nextArch.entities
			cursor = #entities
			if cursor == 0 then
				continue
			end

			entity = entities[cursor]
			entitiesUp = entities
			local cmap = nextArch.columnsMap
			col0 = cmap[id0]
			col1 = cmap[id1]
			col2 = cmap[id2]
			col3 = cmap[id3]
			col0Up = col0
			col1Up = col1
			col2Up = col2
			col3Up = col3
		end

		local row = cursor
		cursor -= 1
		return entity, col0[row], col1[row], col2[row], col3[row]
	end
end

-- Generic arity fallback (5+ all() terms): resolves the column set per archetype
-- and unpacks the row. Rare enough to trade the per-row loop for one code path.
local function _streamN(archetypes: { any }, ids: { number }): () -> ...any
	local count = #ids
	local lastArch = 0
	local entitiesUp: { Entity } = EMPTY_ENTITIES
	local cursor = 0
	local colsUp: { { any } } = {}
	local values = table.create(count)

	local first = archetypes[1]
	if first then
		entitiesUp = first.entities
		cursor = #entitiesUp
		local cmap = first.columnsMap
		for k = 1, count do
			colsUp[k] = cmap[ids[k]]
		end
		lastArch = 1
	end

	return function(): ...any
		local entities = entitiesUp
		local entity = entities[cursor]

		while entity == nil do
			lastArch += 1
			local nextArch = archetypes[lastArch]
			if nextArch == nil then
				return nil
			end

			entities = nextArch.entities
			cursor = #entities
			if cursor == 0 then
				continue
			end

			entity = entities[cursor]
			entitiesUp = entities
			local cmap = nextArch.columnsMap
			for k = 1, count do
				colsUp[k] = cmap[ids[k]]
			end
		end

		local row = cursor
		cursor -= 1
		for k = 1, count do
			values[k] = colsUp[k][row]
		end

		return entity, table.unpack(values, 1, count)
	end
end

--##========== COMPILED QUERY PLANS ==========##--

local EMPTY_COLUMNS: { { any } } = {}

local function _resolveProjectedColumn(archetype: any, projectedId: number): { any }
	local direct = archetype.columnsMap[projectedId]
	if direct then
		return direct
	end

	if not Component.isPair(projectedId) then
		return EMPTY_COLUMN
	end

	local projectedRelation = Component.pairFirst(projectedId)
	local projectedTarget = Component.pairSecond(projectedId)
	if projectedRelation ~= Component.Wildcard and projectedTarget ~= Component.Wildcard then
		return EMPTY_COLUMN
	end

	for _, concreteId in archetype.types do
		if not Component.isPair(concreteId) then
			continue
		end

		local relationMatches = projectedRelation == Component.Wildcard
			or Component.pairFirst(concreteId) == projectedRelation
		local targetMatches = projectedTarget == Component.Wildcard
			or Component.pairSecond(concreteId) == projectedTarget

		if relationMatches and targetMatches then
			return archetype.columnsMap[concreteId]
		end
	end

	return EMPTY_COLUMN
end

local function _closeCompiledState(state: any): ()
	if not state._active then
		return
	end

	state._active = false
	state._exhausted = true
	state._entities = EMPTY_ENTITIES
	state._columns = EMPTY_COLUMNS
	state._column0 = EMPTY_COLUMN
	state._column1 = EMPTY_COLUMN
	state._column2 = EMPTY_COLUMN
	state._column3 = EMPTY_COLUMN
	state._row = 0
	state._store._activeQueryStates -= 1
	state._compiled._activeStates -= 1
end

local function _beginCompiledState(state: any): ()
	if state._compiled._destroyed then
		error(`[Entity] Compiled query has been destroyed`)
	end

	if state._active then
		error(`[Entity] Compiled query default iterator is not reentrant; use cursor()`)
	end

	state._active = true
	state._exhausted = false
	state._planIndex = 0
	state._row = 0
	state._entities = EMPTY_ENTITIES
	state._columns = EMPTY_COLUMNS
	state._store._activeQueryStates += 1
	state._compiled._activeStates += 1
end

local function _compiled0(state: any): ...any
	local entities = state._entities
	local row = state._row
	local entity = entities[row]

	while entity == nil do
		local planIndex = state._planIndex + 1
		local plan = state._plans[planIndex]
		if not plan then
			_closeCompiledState(state)
			return nil
		end

		state._planIndex = planIndex
		entities = plan.entities
		row = #entities
		state._entities = entities
		state._columns = plan.columns
		entity = entities[row]
	end

	state._row = row - 1
	return entity
end

local function _compiled1(state: any): ...any
	local entities = state._entities
	local column0 = state._column0
	local row = state._row
	local entity = entities[row]

	while entity == nil do
		local planIndex = state._planIndex + 1
		local plan = state._plans[planIndex]
		if not plan then
			_closeCompiledState(state)
			return nil
		end

		state._planIndex = planIndex
		entities = plan.entities
		column0 = plan.columns[1]
		row = #entities
		state._entities = entities
		state._column0 = column0
		entity = entities[row]
	end

	state._row = row - 1
	return entity, column0[row]
end

local function _compiled2(state: any): ...any
	local entities = state._entities
	local column0 = state._column0
	local column1 = state._column1
	local row = state._row
	local entity = entities[row]

	while entity == nil do
		local planIndex = state._planIndex + 1
		local plan = state._plans[planIndex]
		if not plan then
			_closeCompiledState(state)
			return nil
		end

		state._planIndex = planIndex
		entities = plan.entities
		local columns = plan.columns
		column0 = columns[1]
		column1 = columns[2]
		row = #entities
		state._entities = entities
		state._column0 = column0
		state._column1 = column1
		entity = entities[row]
	end

	state._row = row - 1
	return entity, column0[row], column1[row]
end

local function _compiled3(state: any): ...any
	local entities = state._entities
	local column0 = state._column0
	local column1 = state._column1
	local column2 = state._column2
	local row = state._row
	local entity = entities[row]

	while entity == nil do
		local planIndex = state._planIndex + 1
		local plan = state._plans[planIndex]
		if not plan then
			_closeCompiledState(state)
			return nil
		end

		state._planIndex = planIndex
		entities = plan.entities
		local columns = plan.columns
		column0 = columns[1]
		column1 = columns[2]
		column2 = columns[3]
		row = #entities
		state._entities = entities
		state._column0 = column0
		state._column1 = column1
		state._column2 = column2
		entity = entities[row]
	end

	state._row = row - 1
	return entity, column0[row], column1[row], column2[row]
end

local function _compiled4(state: any): ...any
	local entities = state._entities
	local column0 = state._column0
	local column1 = state._column1
	local column2 = state._column2
	local column3 = state._column3
	local row = state._row
	local entity = entities[row]

	while entity == nil do
		local planIndex = state._planIndex + 1
		local plan = state._plans[planIndex]
		if not plan then
			_closeCompiledState(state)
			return nil
		end

		state._planIndex = planIndex
		entities = plan.entities
		local columns = plan.columns
		column0 = columns[1]
		column1 = columns[2]
		column2 = columns[3]
		column3 = columns[4]
		row = #entities
		state._entities = entities
		state._column0 = column0
		state._column1 = column1
		state._column2 = column2
		state._column3 = column3
		entity = entities[row]
	end

	state._row = row - 1
	return entity, column0[row], column1[row], column2[row], column3[row]
end

local function _compiledN(state: any): ...any
	local entities = state._entities
	local columns = state._columns
	local row = state._row
	local entity = entities[row]

	while entity == nil do
		local planIndex = state._planIndex + 1
		local plan = state._plans[planIndex]
		if not plan then
			_closeCompiledState(state)
			return nil
		end

		state._planIndex = planIndex
		entities = plan.entities
		columns = plan.columns
		row = #entities
		state._entities = entities
		state._columns = columns
		entity = entities[row]
	end

	state._row = row - 1
	local values = state._values
	for index = 1, state._projectionCount do
		values[index] = columns[index][row]
	end

	return entity, table.unpack(values, 1, state._projectionCount)
end

local function _iterateCompiledState(state: any): ...any
	if state._exhausted then
		return nil
	end

	if not state._active then
		_beginCompiledState(state)
	end

	return state._next(state)
end

local function _newCompiledState(compiled: any): any
	return {
		_compiled = compiled,
		_store = compiled._store,
		_plans = compiled._plans,
		_next = compiled._next,
		_projectionCount = compiled._projectionCount,
		_planIndex = 0,
		_row = 0,
		_entities = EMPTY_ENTITIES,
		_columns = EMPTY_COLUMNS,
		_column0 = EMPTY_COLUMN,
		_column1 = EMPTY_COLUMN,
		_column2 = EMPTY_COLUMN,
		_column3 = EMPTY_COLUMN,
		_values = table.create(compiled._projectionCount),
		_active = false,
		_exhausted = false,
	}
end

local CompiledCursor = {}
CompiledCursor.__index = CompiledCursor

function CompiledCursor.__call(self: any): ...any
	return _iterateCompiledState(self._state)
end

function CompiledCursor.__iter(self: any): (any, any, nil)
	return _iterateCompiledState, self._state, nil
end

function CompiledCursor.close(self: any): ()
	_closeCompiledState(self._state)
end

local CompiledQuery = {}
CompiledQuery.__index = CompiledQuery

function CompiledQuery.__call(self: any): ...any
	return _iterateCompiledState(self._defaultState)
end

function CompiledQuery.__iter(self: any): (any, any, nil)
	local state = self._defaultState
	if state._active then
		error(`[Entity] Compiled query default iterator is not reentrant; use cursor()`)
	end

	state._exhausted = false
	_beginCompiledState(state)

	return state._next, state, nil
end

function CompiledQuery.cursor(self: any): any
	if self._destroyed then
		error(`[Entity] Compiled query has been destroyed`)
	end

	local state = _newCompiledState(self)
	_beginCompiledState(state)

	return setmetatable({ _state = state }, CompiledCursor)
end

function CompiledQuery._register(self: any, archetype: any): ()
	if self._destroyed then
		return
	end

	if not Archetype.match(archetype, self._query) then
		return
	end

	local columns: { { any } } = table.create(self._projectionCount)
	for index, projectedId in self._projectedIds do
		columns[index] = _resolveProjectedColumn(archetype, projectedId)
	end

	table.insert(self._plans, {
		archetype = archetype,
		entities = archetype.entities,
		columns = columns,
	})
end

function CompiledQuery.destroy(self: any): ()
	if self._destroyed then
		return
	end

	if self._activeStates > 0 then
		error(`[Entity] Cannot destroy a compiled query with active cursors`)
	end

	self._store._compiledQueries[self] = nil
	table.clear(self._plans)
	self._defaultState._exhausted = false
	self._defaultState._entities = EMPTY_ENTITIES
	self._defaultState._columns = EMPTY_COLUMNS
	self._defaultState._column0 = EMPTY_COLUMN
	self._defaultState._column1 = EMPTY_COLUMN
	self._defaultState._column2 = EMPTY_COLUMN
	self._defaultState._column3 = EMPTY_COLUMN
	self._destroyed = true
end

function CompiledQuery._unregister(self: any, archetype: any): ()
	for index, plan in self._plans do
		if plan.archetype == archetype then
			table.remove(self._plans, index)
			return
		end
	end
end

local SpawnBundleMethods = {}
SpawnBundleMethods.__index = SpawnBundleMethods

function SpawnBundleMethods.destroy(self: any): ()
	if self._lifecycle.destroyed then
		return
	end

	self.archetype._bundlePins -= 1
	self._lifecycle.destroyed = true
end

local StructuralPatchMethods = {}
StructuralPatchMethods.__index = StructuralPatchMethods

function StructuralPatchMethods.destroy(self: any): ()
	if self._lifecycle.destroyed then
		return
	end

	self._entityStore._compiledPatches[self] = nil
	table.clear(self._transitions)
	self._lifecycle.destroyed = true
end

--##========== PUBLIC API ==========##--

local EntityStore = {}
EntityStore.__index = EntityStore

export type EntityStore = typeof(setmetatable(
	{} :: {
		_entityIndex: EntityIndex,
		_archetypes: { [number]: any },
		_archetypeIndex: { [string]: any },
		_archetypeEdges: { [number]: { [number]: any } },
		_maxArchetypeId: number,
		_root: any,
		_dirty: { DirtyEntry },
		_cleanup: any,
		_cachedQueries: { any },
		_queryCache: { [any]: { any } },
		_compiledQueries: { [any]: boolean },
		_compiledPatches: { [StructuralPatch]: boolean },
		_relationTraitRevision: number,
		_activeQueryStates: number,
		_pairsByTarget: { [number]: { [number]: boolean } },
		_pairsByRelation: { [number]: { [number]: boolean } },
		_sparse: { [number]: { [Entity]: any } },
		_componentMetadata: { [number]: ComponentMetadata },
	},
	EntityStore
))

function EntityStore.new(): EntityStore
	local self = setmetatable({}, EntityStore) :: EntityStore

	self._entityIndex = {
		sparseArray = {},
		denseArray = {},
		aliveCount = 0,
	}

	self._archetypes = {}
	self._archetypeIndex = {}
	self._archetypeEdges = {}
	self._maxArchetypeId = 0
	self._dirty = {}
	self._cleanup = Cleanup.new()
	self._cachedQueries = {}
	self._queryCache = {}
	self._compiledQueries = setmetatable({}, { __mode = `k` })
	self._compiledPatches = setmetatable({}, { __mode = `k` })
	self._relationTraitRevision = Cleanup.relationTraitRevision()
	self._activeQueryStates = 0
	self._pairsByTarget = {}
	self._pairsByRelation = {}
	self._sparse = {}
	self._componentMetadata = Component.metadata

	self._root = Archetype.createRoot(self)

	return self
end

function EntityStore.compile(self: EntityStore, query: any): any
	if _queryTouchesSparse(query) then
		error(`[Entity] Compiled queries do not support sparse filters`)
	end

	local projectedIds = query._select or {}
	for _, projectedId in projectedIds do
		if Component.isSparseId(projectedId) then
			error(`[Entity] Compiled queries do not support sparse projections`)
		end
	end

	local projectionCount = #projectedIds
	local nextRow = if projectionCount == 0
		then _compiled0
		elseif projectionCount == 1 then _compiled1
		elseif projectionCount == 2 then _compiled2
		elseif projectionCount == 3 then _compiled3
		elseif projectionCount == 4 then _compiled4
		else _compiledN

	local compiled = setmetatable({
		_store = self,
		_query = query,
		_projectedIds = projectedIds,
		_projectionCount = projectionCount,
		_plans = {} :: { CompiledArchetypePlan },
		_next = nextRow,
		_activeStates = 0,
		_destroyed = false,
	}, CompiledQuery)

	compiled._defaultState = _newCompiledState(compiled)

	for _, archetype in self._archetypes do
		compiled:_register(archetype)
	end

	self._compiledQueries[compiled] = true

	return compiled
end

function EntityStore.assertStructuralMutationAllowed(self: EntityStore): ()
	_assertStructuralMutationAllowed(self)
end

function EntityStore.bundle(self: EntityStore, ...: number): SpawnBundle
	local memberCount = select(`#`, ...)
	if memberCount == 0 then
		error(`[Entity] Bundle requires at least one component id`)
	end

	_assertStructuralMutationAllowed(self)

	local ids: { number } = table.create(memberCount)
	local metadata: { ComponentMetadata } = table.create(memberCount)
	local archetypeIds: { number } = {}
	local seen: { [number]: boolean } = {}

	for memberIndex = 1, memberCount do
		local componentId = select(memberIndex, ...)
		if type(componentId) ~= `number` or componentId % 1 ~= 0 then
			error(`[Entity] Invalid bundle component id at position {memberIndex}`)
		end
		if seen[componentId] then
			error(`[Entity] Duplicate bundle component id {componentId}`)
		end

		local componentMetadata = self._componentMetadata[componentId]
		if not componentMetadata then
			error(`[Entity] Unknown bundle component id {componentId}`)
		end

		seen[componentId] = true
		ids[memberIndex] = componentId
		metadata[memberIndex] = table.freeze({
			name = componentMetadata.name,
			isTag = componentMetadata.isTag,
			isSparse = componentMetadata.isSparse,
			isPair = componentMetadata.isPair,
		})

		if not componentMetadata.isSparse then
			archetypeIds[#archetypeIds + 1] = componentId
		end
	end

	table.sort(archetypeIds)

	local destination = Archetype.ensure(self, archetypeIds)
	destination._bundlePins += 1
	local columnPositions: { [number]: number } = {}
	for columnPosition, componentId in destination.types do
		columnPositions[componentId] = columnPosition
	end

	local dataPositions: { number } = table.create(memberCount, 0)
	local dataColumnPositions: { number } = {}
	local dataColumns: { { any } } = {}
	local denseDataPositions: { number } = {}
	local sparseIds: { number } = {}
	local sparseDataPositions: { number } = {}
	local dataCount = 0
	local denseCount = 0
	local sparseCount = 0

	for memberIndex = 1, memberCount do
		local componentMetadata = metadata[memberIndex]
		if componentMetadata.isTag then
			continue
		end

		dataCount += 1
		dataPositions[memberIndex] = dataCount

		if componentMetadata.isSparse then
			sparseCount += 1
			sparseIds[sparseCount] = ids[memberIndex]
			sparseDataPositions[sparseCount] = dataCount
		else
			denseCount += 1
			local columnPosition = columnPositions[ids[memberIndex]]
			assert(columnPosition, `[Entity] Missing bundle data column for component id {ids[memberIndex]}`)
			dataColumnPositions[denseCount] = columnPosition
			dataColumns[denseCount] = destination.columns[columnPosition]
			denseDataPositions[denseCount] = dataCount
		end
	end

	table.freeze(ids)
	table.freeze(metadata)
	table.freeze(dataPositions)
	table.freeze(dataColumnPositions)
	table.freeze(dataColumns)
	table.freeze(denseDataPositions)
	table.freeze(sparseIds)
	table.freeze(sparseDataPositions)

	return table.freeze(setmetatable({
		ids = ids,
		metadata = metadata,
		archetype = destination,
		dataPositions = dataPositions,
		dataColumnPositions = dataColumnPositions,
		dataColumns = dataColumns,
		denseDataPositions = denseDataPositions,
		sparseIds = sparseIds,
		sparseDataPositions = sparseDataPositions,
		memberCount = memberCount,
		dataCount = dataCount,
		denseCount = denseCount,
		sparseCount = sparseCount,
		_entityStore = self,
		_lifecycle = { destroyed = false },
	}, SpawnBundleMethods)) :: SpawnBundle
end

function EntityStore.patch(self: EntityStore, definition: StructuralPatchSpec): StructuralPatch
	if type(definition) ~= `table` then
		error(`[Entity] Structural patch definition must be a table`)
	end

	local addSource: any = definition.add
	local removeSource: any = definition.remove
	if addSource == nil then
		addSource = {}
	end
	if removeSource == nil then
		removeSource = {}
	end
	if type(addSource) ~= `table` or type(removeSource) ~= `table` then
		error(`[Entity] Structural patch add and remove fields must be arrays`)
	end

	local addIds: { number } = table.clone(addSource)
	local removeIds: { number } = table.clone(removeSource)
	local addMetadata: { ComponentMetadata } = table.create(#addIds)
	local removeMetadata: { ComponentMetadata } = table.create(#removeIds)
	local dataPositions: { number } = table.create(#addIds, 0)
	local seen: { [number]: string } = {}
	local exclusiveAdds: { [number]: boolean } = {}
	local dataCount = 0

	local function validateList(ids: { number }, metadata: { ComponentMetadata }, operation: string): ()
		local entryCount = 0
		for key in ids do
			entryCount += 1
			if type(key) ~= `number` or key % 1 ~= 0 or key < 1 or key > #ids then
				error(`[Entity] Structural patch {operation} must be a contiguous array`)
			end
		end
		if entryCount ~= #ids then
			error(`[Entity] Structural patch {operation} must be a contiguous array`)
		end

		for index, componentId in ids do
			if type(componentId) ~= `number` or componentId % 1 ~= 0 then
				error(`[Entity] Invalid structural patch component id at {operation} position {index}`)
			end

			local previous = seen[componentId]
			if previous then
				local reason = if previous == operation then `Duplicate` else `Conflicting`
				error(`[Entity] {reason} structural patch component id {componentId}`)
			end

			local componentMetadata = self._componentMetadata[componentId]
			if not componentMetadata then
				error(`[Entity] Unknown structural patch component id {componentId}`)
			end
			if operation == `add` and componentMetadata.isPair then
				local relation = Component.pairFirst(componentId)
				if Cleanup.isExclusive(relation) then
					if exclusiveAdds[relation] then
						error(`[Entity] Conflicting structural patch targets for exclusive relation {relation}`)
					end
					exclusiveAdds[relation] = true
				end
			end

			seen[componentId] = operation
			metadata[index] = table.freeze({
				name = componentMetadata.name,
				isTag = componentMetadata.isTag,
				isSparse = componentMetadata.isSparse,
				isPair = componentMetadata.isPair,
			})
		end
	end

	validateList(removeIds, removeMetadata, `remove`)
	validateList(addIds, addMetadata, `add`)

	for index, metadata in addMetadata do
		if not metadata.isTag then
			dataCount += 1
			dataPositions[index] = dataCount
		end
	end

	table.freeze(addIds)
	table.freeze(removeIds)
	table.freeze(addMetadata)
	table.freeze(removeMetadata)
	table.freeze(dataPositions)

	local patch = table.freeze(setmetatable({
		addIds = addIds,
		removeIds = removeIds,
		addMetadata = addMetadata,
		removeMetadata = removeMetadata,
		dataPositions = dataPositions,
		dataCount = dataCount,
		operationCount = #addIds + #removeIds,
		_transitions = {},
		_entityStore = self,
		_lifecycle = { destroyed = false },
	}, StructuralPatchMethods)) :: StructuralPatch

	self._compiledPatches[patch] = true

	return patch
end

function EntityStore.recordOfAny(self: EntityStore, entity: Entity): Record?
	return self._entityIndex.sparseArray[(entity % ENTITY_MASK)]
end

function EntityStore.spawn(self: EntityStore): Entity
	_assertStructuralMutationAllowed(self)

	local id = _indexNewId(self._entityIndex, self._root)
	return id
end

function EntityStore.spawnBundle(self: EntityStore, bundle: SpawnBundle, ...: any): Entity
	if bundle._lifecycle.destroyed then
		error(`[Entity] Spawn bundle has been destroyed`)
	end

	if bundle._entityStore ~= self then
		error(`[Entity] Spawn bundle belongs to a different entity store`)
	end

	local dataCount = bundle.dataCount
	local providedDataCount = select(`#`, ...)
	if providedDataCount ~= dataCount then
		error(`[Entity] Spawn bundle expected {dataCount} data values, got {providedDataCount}`)
	end

	if self._activeQueryStates > 0 then
		_assertStructuralMutationAllowed(self)
	end

	local destination = bundle.archetype
	local id, row = _indexNewId(self._entityIndex, destination)

	local dataColumns = bundle.dataColumns
	local denseDataPositions = bundle.denseDataPositions
	for denseIndex = 1, bundle.denseCount do
		dataColumns[denseIndex][row] = select(denseDataPositions[denseIndex], ...)
	end

	local sparseIds = bundle.sparseIds
	local sparseDataPositions = bundle.sparseDataPositions
	for sparseIndex = 1, bundle.sparseCount do
		local componentId = sparseIds[sparseIndex]
		local sparseColumn = self._sparse[componentId]
		if not sparseColumn then
			sparseColumn = {}
			self._sparse[componentId] = sparseColumn
		end

		sparseColumn[id] = select(sparseDataPositions[sparseIndex], ...)
	end

	return id
end

function EntityStore.despawn(self: EntityStore, id: Entity): ()
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		return
	end

	_assertStructuralMutationAllowed(self)

	Archetype.removeRow(self, record.archetype, record.row)

	for _, column in self._sparse do
		column[id] = nil
	end

	self._cleanup:unbindAll(id)

	_indexRemove(self._entityIndex, id)
end

function EntityStore.isAlive(self: EntityStore, id: Entity): boolean
	return _indexTryGet(self._entityIndex, id) ~= nil
end

function EntityStore.add(self: EntityStore, id: Entity, componentId: number, data: any): ()
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		error(`[Entity] Cannot add component to non-alive entity {id}`)
	end

	local metadata = self._componentMetadata[componentId]
	if metadata and metadata.isPair then
		local relation = Component.pairFirst(componentId)
		if Cleanup.isExclusive(relation) then
			local existing = EntityStore.findPair(self, id, relation)
			if existing and existing ~= componentId then
				EntityStore.remove(self, id, existing)
			end
		end
	end

	if metadata and metadata.isTag and data ~= nil then
		error(`[Entity] Cannot store data on tag {componentId}`)
	end

	if metadata and metadata.isSparse then
		local sparseColumn = self._sparse[componentId]
		if (not sparseColumn or sparseColumn[id] == nil) and self._activeQueryStates > 0 then
			_assertStructuralMutationAllowed(self)
		end

		if not sparseColumn then
			sparseColumn = {}
			self._sparse[componentId] = sparseColumn
		end

		sparseColumn[id] = data
		return
	end

	local from = record.archetype

	if from.columnsMap[componentId] then
		if not metadata or not metadata.isTag then
			from.columnsMap[componentId][record.row] = data
		end
		return
	end

	if self._activeQueryStates > 0 then
		_assertStructuralMutationAllowed(self)
	end

	local destination = self._archetypeEdges[from.id][componentId]
	if not destination then
		destination = _traverseAdd(self, from, componentId)
	end
	_moveEntity(self, id, record, destination)

	if not metadata or not metadata.isTag then
		destination.columnsMap[componentId][record.row] = data
	end
end

function EntityStore.addComponent(self: EntityStore, id: Entity, component: ComponentKey, data: { [string]: any }): ()
	EntityStore.add(self, id, _keyOf(component), data)
end

-- Tag = zero-data component. It joins the archetype signature (so queries and
-- hasComponent see it) but its column is the shared NULL_ARRAY, so no per-entity
-- data is written or moved. Compare addComponent, which writes a data column.
function EntityStore.addTag(self: EntityStore, id: Entity, component: ComponentKey): ()
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		error(`[Entity] Cannot add tag to non-alive entity {id}`)
	end

	local key = _keyOf(component)
	local from = record.archetype

	if from.columnsMap[key] then
		return
	end

	_assertStructuralMutationAllowed(self)

	local destination = _traverseAdd(self, from, key)
	_moveEntity(self, id, record, destination)
end

-- Bulk archetypal add: reaches the SINGLE destination archetype for all `count`
-- component ids in `keys` and does ONE moveEntity, versus addComponent's one move
-- per component. Passed as two parallel arrays (keys[k] / datas[k]) to avoid a
-- per-entry wrapper allocation. A nil datas[k] is a tag (joins the signature, no
-- column write); a non-nil datas[k] writes its column after the move. Sparse and
-- pair ids are NOT accepted here -- the World boundary routes those.
function EntityStore.addComponents(self: EntityStore, id: Entity, keys: { number }, datas: { any }, count: number): ()
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		error(`[Entity] Cannot add components to non-alive entity {id}`)
	end

	local from = record.archetype
	for k = 1, count do
		if not from.columnsMap[keys[k]] then
			_assertStructuralMutationAllowed(self)
			break
		end
	end

	-- Walk the cached archetype edge graph one component at a time (each step is an
	-- O(1) edge lookup, no signature hashing) to reach the final destination, then
	-- do ONE move. traverseAdd is a no-op for a key already present, so duplicate
	-- or already-owned keys collapse automatically.
	local destination = from
	for k = 1, count do
		destination = _traverseAdd(self, destination, keys[k])
	end

	if destination ~= from then
		_moveEntity(self, id, record, destination)
	end

	local columnsMap = record.archetype.columnsMap
	local row = record.row
	for k = 1, count do
		local data = datas[k]
		if data ~= nil then
			columnsMap[keys[k]][row] = data
		end
	end
end

function EntityStore.mutate(self: EntityStore, id: Entity, patch: StructuralPatch, ...: any): ()
	_mutatePatch(self, id, patch, false, ...)
end

function EntityStore.mutateObserved(self: EntityStore, id: Entity, patch: StructuralPatch, ...: any): { any }
	return _mutatePatch(self, id, patch, true, ...) :: { any }
end

function EntityStore.read(self: EntityStore, id: Entity, componentId: number): any
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		error(`[Entity] Cannot get component from non-alive entity {id}`)
	end

	local metadata = self._componentMetadata[componentId]
	if metadata and metadata.isSparse then
		local sparseColumn = self._sparse[componentId]
		return if sparseColumn then sparseColumn[id] else nil
	end

	local column = record.archetype.columnsMap[componentId]
	if not column then
		return nil
	end

	return column[record.row]
end

function EntityStore.get(self: EntityStore, id: Entity, component: ComponentKey): { [string]: any }?
	return EntityStore.read(self, id, _keyOf(component))
end

-- Reads several components in ONE entity resolve. The record is located once,
-- then each id is read straight from its column (or sparse map) by row, so N
-- components cost one _indexTryGet, not N. Ids arrive already resolved from the
-- World boundary; sparse and archetypal ids are both handled, in argument order.
function EntityStore.getMany(self: EntityStore, id: Entity, ...: number): ...any
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		error(`[Entity] Cannot get components from non-alive entity {id}`)
	end

	local columnsMap = record.archetype.columnsMap
	local row = record.row
	local count = select("#", ...)
	local results = table.create(count)

	for k = 1, count do
		local key = select(k, ...)
		if Component.isSparseId(key) then
			local column = self._sparse[key]
			results[k] = if column then column[id] else nil
		else
			local column = columnsMap[key]
			results[k] = if column then column[row] else nil
		end
	end

	return table.unpack(results, 1, count)
end

function EntityStore.write(self: EntityStore, id: Entity, componentId: number, data: any): ()
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		error(`[Entity] Cannot set component on non-alive entity {id}`)
	end

	local metadata = self._componentMetadata[componentId]
	if metadata and metadata.isTag then
		error(`[Entity] Cannot store data on tag {componentId}`)
	end

	if metadata and metadata.isSparse then
		local sparseColumn = self._sparse[componentId]
		if not sparseColumn or sparseColumn[id] == nil then
			_assertStructuralMutationAllowed(self)
		end

		if not sparseColumn then
			sparseColumn = {}
			self._sparse[componentId] = sparseColumn
		end

		sparseColumn[id] = data
		return
	end

	local column = record.archetype.columnsMap[componentId]
	if column then
		column[record.row] = data
		return
	end

	_assertStructuralMutationAllowed(self)

	local destination = _traverseAdd(self, record.archetype, componentId)
	_moveEntity(self, id, record, destination)
	destination.columnsMap[componentId][record.row] = data
end

function EntityStore.set(self: EntityStore, id: Entity, component: ComponentKey, data: { [string]: any }): ()
	EntityStore.write(self, id, _keyOf(component), data)
end

function EntityStore.remove(self: EntityStore, id: Entity, componentId: number): ()
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		return
	end

	local metadata = self._componentMetadata[componentId]
	if metadata and metadata.isSparse then
		local sparseColumn = self._sparse[componentId]
		if sparseColumn then
			if sparseColumn[id] ~= nil and self._activeQueryStates > 0 then
				_assertStructuralMutationAllowed(self)
			end
			sparseColumn[id] = nil
		end
		return
	end

	local from = record.archetype
	if not from.columnsMap[componentId] then
		return
	end

	if self._activeQueryStates > 0 then
		_assertStructuralMutationAllowed(self)
	end

	local destination = self._archetypeEdges[from.id][componentId]
	if not destination then
		destination = _traverseRemove(self, from, componentId)
	end
	_moveEntity(self, id, record, destination)
end

function EntityStore.removeComponent(self: EntityStore, id: Entity, component: ComponentKey): ()
	EntityStore.remove(self, id, _keyOf(component))
end

function EntityStore.has(self: EntityStore, id: Entity, componentId: number): boolean
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		return false
	end

	local metadata = self._componentMetadata[componentId]
	if metadata and metadata.isSparse then
		local sparseColumn = self._sparse[componentId]
		return sparseColumn ~= nil and sparseColumn[id] ~= nil
	end

	return record.archetype.columnsMap[componentId] ~= nil
end

function EntityStore.hasComponent(self: EntityStore, id: Entity, component: ComponentKey): boolean
	return EntityStore.has(self, id, _keyOf(component))
end

function EntityStore.markDirty(self: EntityStore, id: Entity, name: string): ()
	table.insert(self._dirty, { entity = id, name = name })
end

function EntityStore.flushDirty(self: EntityStore): { DirtyEntry }
	local copy = table.clone(self._dirty)

	table.clear(self._dirty)

	return copy
end

function EntityStore.getEntitiesWithComponent(self: EntityStore, component: ComponentKey): { Entity }
	local key = _keyOf(component)
	local result: { Entity } = {}

	for _, archetype in self._archetypes do
		if not archetype.columnsMap[key] then
			continue
		end

		local entities = archetype.entities
		for row = 1, #entities do
			table.insert(result, entities[row])
		end
	end

	return result
end

-- Name-keyed so observers, replication and despawn's onRemove pass keep working.
-- Pair ids have no registered name (nameOf returns nil) and are skipped -- they
-- carry no named-observer semantics.
function EntityStore.getAllComponents(self: EntityStore, id: Entity): { [string]: { [string]: any } }?
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		return nil
	end

	local result: { [string]: { [string]: any } } = {}

	for componentId, column in record.archetype.columnsMap do
		local name = Component.nameOf(componentId)
		if name then
			result[name] = column[record.row]
		end
	end

	for componentId, column in self._sparse do
		local data = column[id]
		if data ~= nil then
			local name = Component.nameOf(componentId)
			if name then
				result[name] = data
			end
		end
	end

	return result
end

function EntityStore.bindInstance(self: EntityStore, id: Entity, instance: any): ()
	if not _indexTryGet(self._entityIndex, id) then
		error(`[Entity] Cannot bind instance to non-alive entity {id}`)
	end

	self._cleanup:bind(id, instance)
end

function EntityStore.countAlive(self: EntityStore): number
	return self._entityIndex.aliveCount
end

-- Iterates the live entity ids (the dense array up to aliveCount). Snapshots
-- the count at creation, so callers must not spawn/despawn mid-iteration.
-- The read path replication uses to walk the live set without reaching into internals.
function EntityStore.eachAlive(self: EntityStore): () -> Entity?
	local dense = self._entityIndex.denseArray
	local count = self._entityIndex.aliveCount
	local cursor = 0

	return function(): Entity?
		cursor += 1
		if cursor > count then
			return nil
		end

		return dense[cursor]
	end
end

function EntityStore.collectEntities(self: EntityStore, query: any): { Entity }
	if _queryTouchesSparse(query) then
		return self:_collectSparseAware(query)
	end

	return _flatten(_matchingArchetypes(self, query))
end

-- Streaming query iterator: yields `entity, data0, data1, ...` for the query's
-- all() terms straight from archetype columns, walked by row. Use in a generic
-- for. This is the fast read path -- no materialised id array, no per-entity
-- index resolve. A sparse query falls back to a per-entity walk, since sparse
-- membership is not archetypal and carries no column to stream.
function EntityStore.iter(self: EntityStore, query: any): () -> ...any
	if _queryTouchesSparse(query) then
		local entities = self:_collectSparseAware(query)
		local ids = query._all
		local count = #ids
		local values = table.create(count)
		local index = 0

		return function(): ...any
			index += 1
			local entity = entities[index]
			if entity == nil then
				return nil
			end

			if count == 0 then
				return entity
			end

			for k = 1, count do
				local id = ids[k]
				values[k] = if Component.isSparseId(id) then self:getSparse(entity, id) else self:get(entity, id)
			end

			return entity, table.unpack(values, 1, count)
		end
	end

	local archetypes = _matchingArchetypes(self, query)
	local ids = query._all
	local count = #ids

	if count == 0 then
		return _stream0(archetypes)
	elseif count == 1 then
		return _stream1(archetypes, ids[1])
	elseif count == 2 then
		return _stream2(archetypes, ids[1], ids[2])
	elseif count == 3 then
		return _stream3(archetypes, ids[1], ids[2], ids[3])
	elseif count == 4 then
		return _stream4(archetypes, ids[1], ids[2], ids[3], ids[4])
	end

	return _streamN(archetypes, ids)
end

-- Sparse-aware iteration: match archetype candidates on their archetypal
-- terms, then filter each candidate entity by the sparse terms. The archetype
-- cache is intentionally bypassed -- a sparse add/remove changes an entity's
-- membership WITHOUT touching any archetype, so the per-entity filter must
-- re-run every call -- but the archetypal terms resolve exactly as the fast
-- path would.
function EntityStore._collectSparseAware(self: EntityStore, query: any): { Entity }
	local allArch, allSparse = _partitionBySparse(query._all)
	local anyArch, anySparse = _partitionBySparse(query._any)
	local noneArch, noneSparse = _partitionBySparse(query._none)

	local hasAnyGroup = #query._any > 0

	local result: { Entity } = {}

	for _, archetype in self._archetypes do
		local set = archetype.componentSet

		local candidate = true

		for _, id in allArch do
			if set[id] == nil then
				candidate = false
				break
			end
		end

		if candidate then
			for _, id in noneArch do
				if set[id] ~= nil then
					candidate = false
					break
				end
			end
		end

		local anySatisfiedByArchetype = not hasAnyGroup

		if candidate and hasAnyGroup then
			for _, id in anyArch do
				if set[id] ~= nil then
					anySatisfiedByArchetype = true
					break
				end
			end

			-- No archetypal any-term present and no sparse any-term to fall back
			-- on means no entity in this archetype can satisfy the any() group.
			if not anySatisfiedByArchetype and #anySparse == 0 then
				candidate = false
			end
		end

		if candidate then
			for _, entityId in archetype.entities do
				if self:_entityMatchesSparse(entityId, allSparse, noneSparse, anySparse, anySatisfiedByArchetype) then
					table.insert(result, entityId)
				end
			end
		end
	end

	return result
end

function EntityStore._entityMatchesSparse(
	self: EntityStore,
	entityId: Entity,
	allSparse: { number },
	noneSparse: { number },
	anySparse: { number },
	anySatisfied: boolean
): boolean
	for _, id in allSparse do
		if not self:hasSparse(entityId, id) then
			return false
		end
	end

	for _, id in noneSparse do
		if self:hasSparse(entityId, id) then
			return false
		end
	end

	if not anySatisfied then
		local found = false
		for _, id in anySparse do
			if self:hasSparse(entityId, id) then
				found = true
				break
			end
		end

		if not found then
			return false
		end
	end

	return true
end

--##========== SPARSE STORAGE ==========##--

-- A sparse component lives OUTSIDE archetype signatures: its data sits in a
-- per-component map keyed by entity id, so adding or removing it never moves
-- the entity between archetypes and never fragments the archetype graph. Keyed
-- by the packed entity id, a recycled slot's new id cannot read a prior
-- owner's data even before despawn cleanup runs.
function EntityStore.setSparse(self: EntityStore, id: Entity, compId: number, data: any): ()
	if not _indexTryGet(self._entityIndex, id) then
		error(`[Entity] Cannot set sparse component on non-alive entity {id}`)
	end

	local column = self._sparse[compId]
	if not column or column[id] == nil then
		_assertStructuralMutationAllowed(self)
	end

	if not column then
		column = {}
		self._sparse[compId] = column
	end

	column[id] = data
end

function EntityStore.getSparse(self: EntityStore, id: Entity, compId: number): any
	if not _indexTryGet(self._entityIndex, id) then
		error(`[Entity] Cannot get sparse component from non-alive entity {id}`)
	end

	local column = self._sparse[compId]
	if not column then
		return nil
	end

	return column[id]
end

function EntityStore.hasSparse(self: EntityStore, id: Entity, compId: number): boolean
	local column = self._sparse[compId]
	return column ~= nil and column[id] ~= nil
end

function EntityStore.removeSparse(self: EntityStore, id: Entity, compId: number): ()
	local column = self._sparse[compId]
	if not column then
		return
	end

	column[id] = nil
end

--##========== PAIR ACCESS ==========##--

-- The live packed entity currently occupying a slot, or nil if that slot is
-- unused. Recovers the generation a pair strips from its target (jecs
-- ecs_get_alive), so a pair target read here is the current entity.
function EntityStore.entityAtSlot(self: EntityStore, slot: number): Entity?
	local index = self._entityIndex
	local record = index.sparseArray[slot]
	if not record or record.dense == 0 or record.dense > index.aliveCount then
		return nil
	end

	return index.denseArray[record.dense]
end

-- The first pair on an entity whose relation matches, or nil. Used by exclusive
-- relations to find the pair being replaced.
function EntityStore.findPair(self: EntityStore, id: Entity, relationId: number): number?
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		return nil
	end

	for _, typeId in record.archetype.types do
		if Component.isPair(typeId) and Component.pairFirst(typeId) == relationId then
			return typeId
		end
	end

	return nil
end

-- The n-th target of a relation on an entity, as a live entity id, or nil.
function EntityStore.target(self: EntityStore, id: Entity, relationId: number, n: number): Entity?
	local record = _indexTryGet(self._entityIndex, id)
	if not record then
		return nil
	end

	local count = 0
	for _, typeId in record.archetype.types do
		if Component.isPair(typeId) and Component.pairFirst(typeId) == relationId then
			count += 1
			if count == n then
				return self:entityAtSlot(Component.pairSecond(typeId))
			end
		end
	end

	return nil
end

-- Manual fragmentation sweep (no automatic cadence -- game code decides when):
-- destroy empty archetypes, then prune the stale _pairsBy* buckets they left
-- behind. Returns the number of archetypes destroyed.
function EntityStore.sweep(self: EntityStore): number
	_assertStructuralMutationAllowed(self)

	local destroyed = Archetype.destroyEmpty(self)
	for patch in self._compiledPatches do
		for sourceId, destination in patch._transitions do
			if not self._archetypes[sourceId] or self._archetypes[destination.id] ~= destination then
				patch._transitions[sourceId] = nil
			end
		end
	end
	self:_pruneStalePairBuckets()
	return destroyed
end

function EntityStore._pruneStalePairBuckets(self: EntityStore): ()
	local livePairs: { [number]: boolean } = {}

	for _, archetype in self._archetypes do
		for _, id in archetype.types do
			if Component.isPair(id) then
				livePairs[id] = true
			end
		end
	end

	_prunePairIndex(self._pairsByRelation, livePairs)
	_prunePairIndex(self._pairsByTarget, livePairs)
end

return EntityStore
