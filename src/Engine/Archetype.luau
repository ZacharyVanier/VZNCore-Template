-- Archetype graph: signature-hashed component storage with cached edge traversal.
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

local Component = tryRequire(script and script.Parent and script.Parent.Component, "./Component")

--##========== TYPES ==========##--

type Entity = number

type Column = { any }

-- A resolved column-transfer plan for one (from -> destination) archetype edge,
-- cached on the source archetype so moveEntity walks flat arrays of column
-- references instead of hashing destinationColumnsMap[type] per column per move.
-- copySrc[k]/copyDest[k] are the paired source/destination columns to copy;
-- drops[k] are source columns with no destination (removed components).
type MovePlan = {
	copySrc: { Column },
	copyDest: { Column },
	copyCount: number,
	drops: { Column },
	dropCount: number,
}

export type Archetype = {
	id: number,
	type: string,
	types: { number },
	entities: { Entity },
	columns: { Column },
	columnsMap: { [number]: Column },
	componentSet: { [number]: boolean },
	movePlans: { [number]: MovePlan },
	_bundlePins: number,
}

type Store = any

--##========== CONSTANTS ==========##--

-- Shared frozen column for tag components (zero data). A tag sits in an
-- archetype signature but allocates no per-entity storage: every tag column in
-- every archetype is this one frozen table, so entity moves skip it and any
-- attempt to write data to it errors (jecs ECS_ID_IS_TAG / NULL_ARRAY).
local NULL_ARRAY: Column = table.freeze({})

-- Low 24 bits of a packed entity id are its sparse-index slot (mirrors the entity
-- packing in Component/Entity). moveEntity/removeRow read the swapped entity's
-- record straight off the store's sparse array by slot, skipping a recordOfAny
-- metatable namecall on every swap-remove.
local ENTITY_MASK = 2 ^ 24

--##========== PRIVATE FUNCTIONS ==========##--

-- \0 join over the numeric signature. A bare number-join could collide across
-- distinct signatures ({1,23} vs {12,3}); "\0" separates them. Luau prints these
-- integers exactly (no scientific notation up to 2^53), so the hash stays
-- injective even for large pair ids.
local function _hash(types: { number }): string
	return table.concat(types, "\0")
end

local function _sortedInsertIndex(types: { number }, id: number): number
	for index, existing in types do
		if existing > id then
			return index
		end
	end

	return #types + 1
end

local function _matches(archetype: Archetype, query: any): boolean
	return query:matches(archetype.componentSet)
end

local function _registerCreated(store: Store, archetype: Archetype): ()
	for _, query in store._cachedQueries do
		if _matches(archetype, query) then
			table.insert(store._queryCache[query], archetype)
		end
	end

	for compiled in store._compiledQueries or {} do
		compiled:_register(archetype)
	end
end

local function _unregisterDestroyed(store: Store, archetype: Archetype): ()
	for _, query in store._cachedQueries do
		local matching = store._queryCache[query]

		local at = table.find(matching, archetype)
		if at then
			table.remove(matching, at)
		end
	end

	for compiled in store._compiledQueries or {} do
		compiled:_unregister(archetype)
	end
end

--##========== PUBLIC API ==========##--

local Archetype = {}

function Archetype.createRoot(store: Store): Archetype
	store._maxArchetypeId += 1

	local archetype: Archetype = {
		id = store._maxArchetypeId,
		type = "",
		types = {},
		entities = {},
		columns = {},
		columnsMap = {},
		componentSet = {},
		movePlans = {},
		_bundlePins = 0,
	}

	store._archetypes[archetype.id] = archetype
	store._archetypeIndex[archetype.type] = archetype
	store._archetypeEdges[archetype.id] = {}

	return archetype
end

-- A pair id also implies wildcard membership: injecting Pair(R, *), Pair(*, T)
-- and Pair(*, *) into the component set turns wildcard queries into ordinary
-- exact lookups, so Query needs no wildcard-specific matching. The record
-- indexes (_pairsByRelation / _pairsByTarget) let despawn find every holder of
-- a pair by its relation or target without scanning all archetypes.
local function _registerPair(store: Store, componentSet: { [number]: boolean }, id: number): ()
	local relation = Component.pairFirst(id)
	local target = Component.pairSecond(id)

	componentSet[Component.Pair(relation, Component.Wildcard)] = true
	componentSet[Component.Pair(Component.Wildcard, target)] = true
	componentSet[Component.Pair(Component.Wildcard, Component.Wildcard)] = true

	local byRelation = store._pairsByRelation[relation]
	if not byRelation then
		byRelation = {}
		store._pairsByRelation[relation] = byRelation
	end
	byRelation[id] = true

	local byTarget = store._pairsByTarget[target]
	if not byTarget then
		byTarget = {}
		store._pairsByTarget[target] = byTarget
	end
	byTarget[id] = true
end

local function _create(store: Store, types: { number }, hashKey: string): Archetype
	if (store._activeQueryStates or 0) > 0 then
		error(`[Archetype] Structural mutation is not allowed during compiled query iteration`)
	end

	store._maxArchetypeId += 1

	local columns: { Column } = {}
	local columnsMap: { [number]: Column } = {}
	local componentSet: { [number]: boolean } = {}

	for index, id in types do
		local column: Column = if Component.isTagId(id) then NULL_ARRAY else {}
		columns[index] = column
		columnsMap[id] = column
		componentSet[id] = true

		if Component.isPair(id) then
			_registerPair(store, componentSet, id)
		end
	end

	local archetype: Archetype = {
		id = store._maxArchetypeId,
		type = hashKey,
		types = types,
		entities = {},
		columns = columns,
		columnsMap = columnsMap,
		componentSet = componentSet,
		movePlans = {},
		_bundlePins = 0,
	}

	store._archetypes[archetype.id] = archetype
	store._archetypeIndex[hashKey] = archetype
	store._archetypeEdges[archetype.id] = {}

	_registerCreated(store, archetype)

	return archetype
end

function Archetype.ensure(store: Store, types: { number }): Archetype
	if #types < 1 then
		return store._root
	end

	local hashKey = _hash(types)

	local existing = store._archetypeIndex[hashKey]
	if existing then
		return existing
	end

	return _create(store, types, hashKey)
end

local function _findArchetypeWith(store: Store, from: Archetype, id: number): Archetype
	local destinationTypes = table.clone(from.types)

	local insertIndex = _sortedInsertIndex(from.types, id)
	table.insert(destinationTypes, insertIndex, id)

	return Archetype.ensure(store, destinationTypes)
end

local function _findArchetypeWithout(store: Store, from: Archetype, id: number): Archetype
	local at = table.find(from.types, id)
	if not at then
		return from
	end

	local destinationTypes = table.clone(from.types)
	table.remove(destinationTypes, at)

	return Archetype.ensure(store, destinationTypes)
end

function Archetype.traverseAdd(store: Store, from: Archetype, id: number): Archetype
	if from.columnsMap[id] then
		return from
	end

	local edge = store._archetypeEdges[from.id]

	local destination = edge[id]
	if not destination then
		destination = _findArchetypeWith(store, from, id)
		edge[id] = destination
		store._archetypeEdges[destination.id][id] = from
	end

	return destination
end

function Archetype.traverseRemove(store: Store, from: Archetype, id: number): Archetype
	local edge = store._archetypeEdges[from.id]

	local destination = edge[id]
	if not destination then
		destination = _findArchetypeWithout(store, from, id)
		edge[id] = destination
		store._archetypeEdges[destination.id][id] = from
	end

	return destination
end

function Archetype.appendEntity(archetype: Archetype, entity: Entity): number
	local entities = archetype.entities
	local row = #entities + 1
	entities[row] = entity

	return row
end

-- Resolve the (from -> destination) column-transfer plan once. The edge is
-- structurally invariant: the same source/destination column tables and the
-- same source-index -> destination mapping hold for every entity that ever
-- moves along it, so the per-column destinationColumnsMap hash is paid once
-- here instead of once per column per move.
local function _buildMovePlan(from: Archetype, destination: Archetype): MovePlan
	local sourceColumns = from.columns
	local sourceTypes = from.types
	local destinationColumnsMap = destination.columnsMap

	local copySrc: { Column } = {}
	local copyDest: { Column } = {}
	local drops: { Column } = {}
	local copyCount = 0
	local dropCount = 0

	for index, column in sourceColumns do
		if column == NULL_ARRAY then
			continue
		end

		local destinationColumn = destinationColumnsMap[sourceTypes[index]]
		if destinationColumn then
			copyCount += 1
			copySrc[copyCount] = column
			copyDest[copyCount] = destinationColumn
		else
			dropCount += 1
			drops[dropCount] = column
		end
	end

	return {
		copySrc = copySrc,
		copyDest = copyDest,
		copyCount = copyCount,
		drops = drops,
		dropCount = dropCount,
	}
end

function Archetype.moveEntity(store: Store, entity: Entity, record: any, destination: Archetype): ()
	local from = record.archetype
	local sourceRow = record.row

	local destinationEntities = destination.entities
	local destinationRow = #destinationEntities + 1
	destinationEntities[destinationRow] = entity

	local movePlans = from.movePlans
	local plan = movePlans[destination.id]
	if not plan then
		plan = _buildMovePlan(from, destination)
		movePlans[destination.id] = plan
	end

	local copySrc = plan.copySrc
	local copyDest = plan.copyDest
	local copyCount = plan.copyCount
	local drops = plan.drops
	local dropCount = plan.dropCount

	local sourceEntities = from.entities
	local lastRow = #sourceEntities

	if sourceRow ~= lastRow then
		for k = 1, copyCount do
			local sourceColumn = copySrc[k]
			copyDest[k][destinationRow] = sourceColumn[sourceRow]
			sourceColumn[sourceRow] = sourceColumn[lastRow]
			sourceColumn[lastRow] = nil
		end

		for k = 1, dropCount do
			local sourceColumn = drops[k]
			sourceColumn[sourceRow] = sourceColumn[lastRow]
			sourceColumn[lastRow] = nil
		end

		local movedEntity = sourceEntities[lastRow]
		sourceEntities[sourceRow] = movedEntity

		local movedRecord = store._entityIndex.sparseArray[movedEntity % ENTITY_MASK]
		movedRecord.row = sourceRow
	else
		for k = 1, copyCount do
			local sourceColumn = copySrc[k]
			copyDest[k][destinationRow] = sourceColumn[sourceRow]
			sourceColumn[lastRow] = nil
		end

		for k = 1, dropCount do
			drops[k][lastRow] = nil
		end
	end

	sourceEntities[lastRow] = nil

	record.archetype = destination
	record.row = destinationRow
end

function Archetype.removeRow(store: Store, archetype: Archetype, row: number): ()
	local entities = archetype.entities
	local columns = archetype.columns
	local lastRow = #entities

	if row ~= lastRow then
		local movedEntity = entities[lastRow]

		local movedRecord = store._entityIndex.sparseArray[movedEntity % ENTITY_MASK]
		if movedRecord then
			movedRecord.row = row
		end

		entities[row] = movedEntity

		for _, column in columns do
			if column == NULL_ARRAY then
				continue
			end

			column[row] = column[lastRow]
			column[lastRow] = nil
		end
	else
		for _, column in columns do
			if column == NULL_ARRAY then
				continue
			end

			column[lastRow] = nil
		end
	end

	entities[lastRow] = nil
end

function Archetype.match(archetype: Archetype, query: any): boolean
	return _matches(archetype, query)
end

function Archetype.destroyEmpty(store: Store): number
	local empties: { Archetype } = {}

	for _, archetype in store._archetypes do
		if archetype ~= store._root and archetype._bundlePins == 0 and #archetype.entities == 0 then
			table.insert(empties, archetype)
		end
	end

	for _, archetype in empties do
		local edges = store._archetypeEdges[archetype.id]
		for id, neighbour in edges do
			store._archetypeEdges[neighbour.id][id] = nil
			-- ponytail: prunes edge-adjacent move plans; bulk-add plans GC with their source archetype
			neighbour.movePlans[archetype.id] = nil
		end

		store._archetypeEdges[archetype.id] = nil
		store._archetypes[archetype.id] = nil
		store._archetypeIndex[archetype.type] = nil

		_unregisterDestroyed(store, archetype)
	end

	return #empties
end

return Archetype
