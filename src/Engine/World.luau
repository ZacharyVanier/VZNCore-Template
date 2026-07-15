-- ECS world container.
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

local EntityStore = tryRequire(script and script.Parent and script.Parent.Entity, "./Entity")
local System = tryRequire(script and script.Parent and script.Parent.System, "./System")
local Component = tryRequire(script and script.Parent and script.Parent.Component, "./Component")
local Cleanup = tryRequire(script and script.Parent and script.Parent.Cleanup, "./Cleanup")
local ECSTypes = tryRequire(script and script.Parent and script.Parent.Types, "./Types")
local Observer = tryRequire(script and script.Parent and script.Parent.Observer, "./Observer")
local Debugger = tryRequire(script and script.Parent and script.Parent.Debugger, "./Debugger")

local _storeAdd = EntityStore.add
local _storeRemove = EntityStore.remove
local _storeSpawnBundle = EntityStore.spawnBundle

--##========== TYPES ==========##--

type Entity = number

type ObserverCallback = (entity: Entity, data: any) -> ()

type ObserverMap = ECSTypes.ObserverMap
type SystemDefinition = ECSTypes.SystemDefinition
type PrefabEntry = ECSTypes.PrefabEntry
type PrefabDefinition = ECSTypes.PrefabDefinition
type CleanupAction = ECSTypes.CleanupAction

type Component<T> = ECSTypes.Component<T>
type ComponentRef<T> = ECSTypes.ComponentRef<T>
type ComponentMetadata = ECSTypes.ComponentMetadata
type SpawnBundle = ECSTypes.SpawnBundle
type StructuralPatch = ECSTypes.StructuralPatch
type StructuralPatchSpec = ECSTypes.StructuralPatchSpec
type CompiledQuery = ECSTypes.CompiledQuery

export type World = {
	spawn: (World, SpawnBundle?, ...unknown) -> Entity,
	despawn: (World, Entity) -> (),
	isAlive: (World, Entity) -> boolean,
	bundle: (World, ...number) -> SpawnBundle,
	patch: (World, StructuralPatchSpec) -> StructuralPatch,
	mutate: (World, Entity, StructuralPatch, ...unknown) -> (),
	addComponent: <T>(World, Entity, Component<T>, T?) -> (),
	get: <T>(World, Entity, Component<T>) -> T?,
	set: <T>(World, Entity, Component<T>, T) -> (),
	removeComponent: (World, Entity, ComponentRef<unknown>) -> (),
	hasComponent: (World, Entity, ComponentRef<unknown>) -> boolean,
	query: (World, ECSTypes.Query) -> () -> ...unknown,
	target: (World, Entity, ComponentRef<unknown>, number?) -> Entity?,
	setRelationTrait: (World, ComponentRef<unknown>, ECSTypes.RelationTrait) -> (),
	markDirty: (World, Entity, ComponentRef<unknown>) -> (),
	setSingleton: <T>(World, string, T) -> (),
	getSingleton: <T>(World, string) -> T?,
	addSystem: (World, SystemDefinition) -> (),
	addSystems: (World, { SystemDefinition }) -> (),
	enableSystem: (World, string) -> (),
	disableSystem: (World, string) -> (),
	isSystemEnabled: (World, string) -> boolean,
	step: (World, number) -> (),
	pause: (World) -> (),
	resume: (World) -> (),
	isPaused: (World) -> boolean,
	bindInstance: (World, Entity, unknown) -> (),
	onAdd: (World, string, ECSTypes.ObserverCallback) -> (),
	onChange: (World, string, ECSTypes.ObserverCallback) -> (),
	onRemove: (World, string, ECSTypes.ObserverCallback) -> (),
	spawnPrefab: (World, PrefabDefinition) -> Entity,
	destroy: (World) -> (),
	sweep: (World) -> number,
	eachAlive: (World) -> () -> Entity?,
	getComponents: (World, Entity) -> { [string]: unknown }?,
}

export type WorldModule = {
	Pair: (ComponentRef<unknown>, ComponentRef<unknown>) -> number,
	ChildOf: number,
	Wildcard: number,
	new: () -> World,
}

type WorldSpawn = ((self: WorldImpl) -> Entity) & ((self: WorldImpl, bundle: SpawnBundle, ...any) -> Entity)

-- Overloaded so a typed handle infers `T` (typed data / return) while a raw
-- string name keeps the loose Phase-1 signature. Luau picks the handle overload
-- first; a plain string falls through to the string overload.
type WorldGet =
	(<T>(self: WorldImpl, id: Entity, component: Component<T>) -> T?)
	& ((self: WorldImpl, id: Entity, name: string) -> { [string]: any }?)

type WorldSet =
	(<T>(self: WorldImpl, id: Entity, component: Component<T>, data: T) -> ())
	& ((self: WorldImpl, id: Entity, name: string, data: { [string]: any }) -> ())

type WorldAdd =
	(<T>(self: WorldImpl, id: Entity, component: Component<T>, data: T?) -> ())
	& ((self: WorldImpl, id: Entity, name: string, data: { [string]: any }?) -> ())

type WorldImpl = typeof(setmetatable(
	{} :: {
		_entityStore: any,
		_systems: { SystemDefinition },
		_systemErrors: { [string]: number },
		_singletons: { [string]: any },
		_observers: ObserverMap,
		_paused: boolean,
		_destroyed: boolean,
		_despawning: { [number]: boolean },
		_frameNumber: number,
		_componentMetadata: { [number]: ComponentMetadata },
	},
	{} :: WorldMeta
))

type WorldMeta = {
	__index: WorldMeta,
	Pair: (relation: any, target: any) -> number,
	ChildOf: number,
	Wildcard: number,
	new: () -> WorldImpl,
	bundle: (self: WorldImpl, ...number) -> SpawnBundle,
	patch: (self: WorldImpl, definition: StructuralPatchSpec) -> StructuralPatch,
	spawn: WorldSpawn,
	despawn: (self: WorldImpl, id: Entity) -> (),
	isAlive: (self: WorldImpl, id: Entity) -> boolean,
	add: (self: WorldImpl, id: Entity, componentId: number, data: any?) -> (),
	read: (self: WorldImpl, id: Entity, componentId: number) -> any,
	write: (self: WorldImpl, id: Entity, componentId: number, data: any) -> (),
	remove: (self: WorldImpl, id: Entity, componentId: number) -> (),
	has: (self: WorldImpl, id: Entity, componentId: number) -> boolean,
	addComponent: WorldAdd,
	addComponents: (self: WorldImpl, id: Entity, components: { [any]: any }) -> (),
	mutate: (self: WorldImpl, id: Entity, patch: StructuralPatch, ...any) -> (),
	get: WorldGet,
	getMany: (self: WorldImpl, id: Entity, ...ComponentRef<any>) -> ...any,
	set: WorldSet,
	removeComponent: (self: WorldImpl, id: Entity, component: ComponentRef<any>) -> (),
	hasComponent: (self: WorldImpl, id: Entity, component: ComponentRef<any>) -> boolean,
	query: (self: WorldImpl, query: any) -> () -> ...any,
	compile: (self: WorldImpl, query: any) -> CompiledQuery,
	target: (self: WorldImpl, id: Entity, relation: ComponentRef<any>, index: number?) -> Entity?,
	setRelationTrait: (self: WorldImpl, relation: ComponentRef<any>, traits: any) -> (),
	markDirty: (self: WorldImpl, id: Entity, component: ComponentRef<any>) -> (),
	flushDirty: (self: WorldImpl) -> { any },
	setSingleton: (self: WorldImpl, name: string, data: any) -> (),
	getSingleton: (self: WorldImpl, name: string) -> any?,
	addSystem: (self: WorldImpl, systemDef: SystemDefinition) -> (),
	addSystems: (self: WorldImpl, list: { SystemDefinition }) -> (),
	enableSystem: (self: WorldImpl, name: string) -> (),
	disableSystem: (self: WorldImpl, name: string) -> (),
	isSystemEnabled: (self: WorldImpl, name: string) -> boolean,
	step: (self: WorldImpl, dt: number) -> (),
	pause: (self: WorldImpl) -> (),
	resume: (self: WorldImpl) -> (),
	isPaused: (self: WorldImpl) -> boolean,
	bindInstance: (self: WorldImpl, id: Entity, instance: any) -> (),
	getBoundInstances: (self: WorldImpl, id: Entity) -> { any }?,
	onAdd: (self: WorldImpl, name: string, callback: ObserverCallback) -> (),
	onChange: (self: WorldImpl, name: string, callback: ObserverCallback) -> (),
	onRemove: (self: WorldImpl, name: string, callback: ObserverCallback) -> (),
	spawnPrefab: (self: WorldImpl, prefab: PrefabDefinition) -> Entity,
	destroy: (self: WorldImpl) -> (),
	sweep: (self: WorldImpl) -> number,
	eachAlive: (self: WorldImpl) -> () -> Entity?,
	getComponents: (self: WorldImpl, id: Entity) -> { [string]: { [string]: any } }?,
	_cleanupPairs: (self: WorldImpl, slot: number) -> (),
}

--##========== PRIVATE STATE ==========##--

local CIRCUIT_BREAKER_THRESHOLD = 10

local World = {} :: WorldMeta
World.__index = World

-- Pair constructor + builtin relation ids, mirrored from Component so callers
-- holding a World do not need to import Component directly.
World.Pair = Component.Pair
World.ChildOf = Component.ChildOf
World.Wildcard = Component.Wildcard

--##========== PRIVATE FUNCTIONS ==========##--

local function _sortSystems(systems: { SystemDefinition }): ()
	table.sort(systems, function(a: SystemDefinition, b: SystemDefinition): boolean
		local orderA = System.PHASE_ORDER[a.phase]
		local orderB = System.PHASE_ORDER[b.phase]

		if orderA ~= orderB then
			return orderA < orderB
		end

		return a.priority < b.priority
	end)
end

local function _findSystem(systems: { SystemDefinition }, name: string): SystemDefinition?
	for _, sys in systems do
		if sys.name == name then
			return sys
		end
	end

	return nil
end

-- Component access accepts a raw name, a typed handle, or a packed pair id.
-- Storage keys on the id, so every access resolves the ref to its id here.
-- Aliased to Component.toId so a string resolve is a single frame with a direct
-- name->id lookup (the churn hot path resolves twice per op).
local _resolveId = Component.toId
local _assertRegisteredId = Component.assertRegisteredId

local function _validateQuery(query: any): ()
	for _, field in { `_all`, `_any`, `_none`, `_select` } do
		local ids = query[field]
		if type(ids) ~= `table` then
			error(`[World] Invalid query {field} field`)
		end

		for _, componentId in ids do
			_assertRegisteredId(componentId)
		end
	end
end

-- The name observers/replication key on, or nil for a pair (which carries no
-- named-observer semantics). A string is its own name; a handle carries one;
-- a bare id maps back through the registry (nil for pairs).
local function _nameOf(component: any): string?
	local kind = type(component)

	if kind == "string" then
		return component
	end

	if kind == "table" then
		return component.name
	end

	return Component.nameOf(component)
end

--##========== PUBLIC API ==========##--

function World.new(): WorldImpl
	local self = setmetatable({}, World) :: WorldImpl

	self._entityStore = EntityStore.new()
	self._systems = {}
	self._systemErrors = {}
	self._singletons = {}
	self._paused = false
	self._destroyed = false
	self._observers = Observer.new()
	self._frameNumber = 0
	self._despawning = {}
	self._componentMetadata = Component.metadata

	return self
end

function World.bundle(self: WorldImpl, ...: number): SpawnBundle
	return EntityStore.bundle(self._entityStore, ...)
end

function World.patch(self: WorldImpl, definition: StructuralPatchSpec): StructuralPatch
	return EntityStore.patch(self._entityStore, definition)
end

function World.spawn(self: WorldImpl, bundle: SpawnBundle?, ...: any): Entity
	if bundle == nil then
		return EntityStore.spawn(self._entityStore)
	end

	local observers = self._observers
	if observers._empty then
		return _storeSpawnBundle(self._entityStore, bundle, ...)
	end

	local id = _storeSpawnBundle(self._entityStore, bundle, ...)

	for memberIndex = 1, bundle.memberCount do
		local componentMetadata = bundle.metadata[memberIndex]
		local name = componentMetadata.name
		if not name or not observers:hasListeners(`onAdd`, name) then
			continue
		end

		local data = if componentMetadata.isTag then nil else select(bundle.dataPositions[memberIndex], ...)
		observers:fire(`onAdd`, name, id, data)
	end

	return id
end

-- Removes every holder of a pair whose target or relation is this entity, per
-- the relation's cleanup trait: "delete" cascades (despawn the holder), "remove"
-- orphans it (drop the pair, keep it alive). Both directions are snapshotted
-- before mutating, and recursion is guarded by _despawning against pair cycles.
function World._cleanupPairs(self: WorldImpl, slot: number): ()
	local store = self._entityStore

	local asTarget = store._pairsByTarget[slot]
	if asTarget then
		for pairId in asTarget do
			local action = Cleanup.onDeleteTarget(Component.pairFirst(pairId))
			for _, holder in store:getEntitiesWithComponent(pairId) do
				if action == "delete" then
					self:despawn(holder)
				else
					store:removeComponent(holder, pairId)
				end
			end
		end
		store._pairsByTarget[slot] = nil
	end

	local asRelation = store._pairsByRelation[slot]
	if asRelation then
		local action = Cleanup.onDelete(slot)
		for pairId in asRelation do
			for _, holder in store:getEntitiesWithComponent(pairId) do
				if action == "delete" then
					self:despawn(holder)
				else
					store:removeComponent(holder, pairId)
				end
			end
		end
		store._pairsByRelation[slot] = nil
	end
end

function World.despawn(self: WorldImpl, id: Entity): ()
	EntityStore.assertStructuralMutationAllowed(self._entityStore)

	local slot = Component.lowId(id)

	if self._despawning[slot] then
		return
	end
	self._despawning[slot] = true

	local components = EntityStore.getAllComponents(self._entityStore, id)

	if components then
		for name, data in components do
			self._observers:fire("onRemove", name, id, data)
		end
	end

	self:_cleanupPairs(slot)

	EntityStore.despawn(self._entityStore, id)

	self._despawning[slot] = nil
end

function World.isAlive(self: WorldImpl, id: Entity): boolean
	return EntityStore.isAlive(self._entityStore, id)
end

function World.add(self: WorldImpl, id: Entity, componentId: number, data: any?): ()
	local metadata = self._componentMetadata[componentId]
	if not metadata then
		_assertRegisteredId(componentId)
	end

	local observers = self._observers

	if not Debugger._enabled and observers._empty then
		_storeAdd(self._entityStore, id, componentId, data)
		return
	end

	if Debugger._enabled then
		Debugger.lintAlive(self, id, componentId, `add`)
		Debugger.lintTagWrite(componentId, componentId, data, `add`)
	end

	if metadata and metadata.isTag and data ~= nil then
		error(`[World] "{metadata.name or componentId}" is a tag and cannot store data`)
	end

	_storeAdd(self._entityStore, id, componentId, data)

	local name = if metadata then metadata.name else nil
	if not observers._empty and name and observers:hasListeners("onAdd", name) then
		observers:fire("onAdd", name, id, data)
	end
end

World.addComponent = (
	function(self: WorldImpl, id: Entity, component: any, data: any): ()
		World.add(self, id, _resolveId(component), data)
	end :: any
) :: WorldAdd

function World.read(self: WorldImpl, id: Entity, componentId: number): any
	if not self._componentMetadata[componentId] then
		_assertRegisteredId(componentId)
	end

	if Debugger._enabled then
		Debugger.lintAlive(self, id, componentId, `read`)
	end

	return EntityStore.read(self._entityStore, id, componentId)
end

World.get = (
	function(self: WorldImpl, id: Entity, component: any): any
		return World.read(self, id, _resolveId(component))
	end :: any
) :: WorldGet

function World.write(self: WorldImpl, id: Entity, componentId: number, data: any): ()
	local metadata = self._componentMetadata[componentId]
	if not metadata then
		_assertRegisteredId(componentId)
	end

	local name = if metadata then metadata.name else nil

	if Debugger._enabled then
		Debugger.lintAlive(self, id, componentId, `write`)
		Debugger.lintTagWrite(componentId, componentId, data, `write`)
	end

	if metadata and metadata.isTag then
		error(`[World] "{name or componentId}" is a tag and cannot store data`)
	end

	EntityStore.write(self._entityStore, id, componentId, data)

	if name then
		EntityStore.markDirty(self._entityStore, id, name)
		if not self._observers._empty and self._observers:hasListeners("onChange", name) then
			self._observers:fire("onChange", name, id, data)
		end
	end
end

World.set = (
	function(self: WorldImpl, id: Entity, component: any, data: any): ()
		World.write(self, id, _resolveId(component), data)
	end :: any
) :: WorldSet

-- Opt-in bulk add: applies several components in ONE archetype move instead of
-- addComponent's one-move-per-component. `components` maps a component ref (name,
-- handle, or id) to its data table; a tag ref maps to any truthy sentinel, whose
-- value is ignored (a map cannot hold a nil value). Sparse components keep the
-- per-entity store path and pairs keep exclusive-replacement semantics via the
-- single-add path -- only archetypal data/tag components share the batched move.
function World.addComponents(self: WorldImpl, id: Entity, components: { [any]: any }): ()
	local store = self._entityStore
	for component in components do
		local componentId = _resolveId(component)
		_assertRegisteredId(componentId)

		if store._activeQueryStates > 0 then
			if not EntityStore.has(store, id, componentId) then
				EntityStore.assertStructuralMutationAllowed(store)
			end
		end
	end

	local keys: { number } = {}
	local datas: { any } = {}
	local count = 0

	-- Observer fires are collected and flushed AFTER the batched move, so each
	-- onAdd sees the entity with every component present. Fire arrays stay nil on
	-- the common zero-listener path (no allocation until a listener is found).
	local fireNames: { string }? = nil
	local fireDatas: { any }? = nil
	local fireCount = 0

	for component, value in components do
		local compId = _resolveId(component)
		local name = _nameOf(component)
		local isPair, isTag, isSparse = Component.classify(compId)

		-- Pairs keep exclusive-replacement semantics; sparse keeps its per-entity
		-- store. Neither participates in the archetypal batched move.
		if isPair or isSparse then
			if isPair then
				_storeAdd(store, id, compId, value)
			else
				EntityStore.setSparse(store, id, compId, value)
			end

			if name and self._observers:hasListeners("onAdd", name) then
				if not fireNames then
					fireNames = {}
					fireDatas = {}
				end
				fireCount += 1
				local fn = fireNames :: { string }
				local fd = fireDatas :: { any }
				fn[fireCount] = name
				fd[fireCount] = value
			end
			continue
		end

		local data = if isTag then nil else value

		count += 1
		keys[count] = compId
		datas[count] = data

		if name and self._observers:hasListeners("onAdd", name) then
			if not fireNames then
				fireNames = {}
				fireDatas = {}
			end
			fireCount += 1
			local fn = fireNames :: { string }
			local fd = fireDatas :: { any }
			fn[fireCount] = name
			fd[fireCount] = data
		end
	end

	if count > 0 then
		EntityStore.addComponents(self._entityStore, id, keys, datas, count)
	end

	if fireCount > 0 then
		local fn = fireNames :: { string }
		local fd = fireDatas :: { any }
		for i = 1, fireCount do
			self._observers:fire("onAdd", fn[i], id, fd[i])
		end
	end
end

function World.mutate(self: WorldImpl, id: Entity, patch: StructuralPatch, ...: any): ()
	local observers = self._observers
	if observers._empty then
		EntityStore.mutate(self._entityStore, id, patch, ...)
		return
	end

	local removedData = EntityStore.mutateObserved(self._entityStore, id, patch, ...)
	for index, metadata in patch.removeMetadata do
		local name = metadata.name
		if name and observers:hasListeners(`onRemove`, name) then
			observers:fire(`onRemove`, name, id, removedData[index])
		end
	end

	for index, metadata in patch.addMetadata do
		local name = metadata.name
		if name and observers:hasListeners(`onAdd`, name) then
			local dataPosition = patch.dataPositions[index]
			local data = if dataPosition == 0 then nil else select(dataPosition, ...)
			observers:fire(`onAdd`, name, id, data)
		end
	end
end

-- Reads several components in ONE entity resolve, returned in argument order.
-- Equivalent to N single world:get calls but resolves the entity record once,
-- skipping the N-1 redundant lookups. Accepts names, handles, or ids; the
-- single-arg world:get is unchanged.
function World.getMany(self: WorldImpl, id: Entity, ...: any): ...any
	local count = select("#", ...)
	if count == 0 then
		return
	end

	if Debugger._enabled then
		Debugger.lintAlive(self, id, (...), `getMany`)
	end

	local ids = table.create(count)
	for k = 1, count do
		ids[k] = _assertRegisteredId(_resolveId(select(k, ...)))
	end

	return EntityStore.getMany(self._entityStore, id, table.unpack(ids, 1, count))
end

function World.remove(self: WorldImpl, id: Entity, componentId: number): ()
	if not self._componentMetadata[componentId] then
		_assertRegisteredId(componentId)
	end

	local observers = self._observers
	if observers._empty then
		_storeRemove(self._entityStore, id, componentId)
		return
	end

	local store = self._entityStore
	if EntityStore.has(store, id, componentId) then
		EntityStore.assertStructuralMutationAllowed(store)
	end

	local metadata = self._componentMetadata[componentId]
	local name = if metadata then metadata.name else nil
	if name and observers:hasListeners("onRemove", name) then
		observers:fire("onRemove", name, id, EntityStore.read(store, id, componentId))
	end

	_storeRemove(store, id, componentId)
end

function World.removeComponent(self: WorldImpl, id: Entity, component: ComponentRef<any>): ()
	World.remove(self, id, _resolveId(component))
end

function World.has(self: WorldImpl, id: Entity, componentId: number): boolean
	if not self._componentMetadata[componentId] then
		_assertRegisteredId(componentId)
	end

	return EntityStore.has(self._entityStore, id, componentId)
end

function World.hasComponent(self: WorldImpl, id: Entity, component: ComponentRef<any>): boolean
	return World.has(self, id, _resolveId(component))
end

-- Streaming query iterator for a generic for: `for entity, a, b in world:query(q)
-- do`. Yields the query's all() component data straight from archetype columns --
-- the fast read path with no per-entity resolve. A system opts into streaming by
-- calling this inside its run instead of walking the collected entity array.
function World.query(self: WorldImpl, query: any): () -> ...any
	_validateQuery(query)

	return EntityStore.iter(self._entityStore, query)
end

function World.compile(self: WorldImpl, query: any): CompiledQuery
	_validateQuery(query)

	return EntityStore.compile(self._entityStore, query)
end

-- The n-th (default 1) target entity of a relation on an entity, or nil.
function World.target(self: WorldImpl, id: Entity, relation: ComponentRef<any>, index: number?): Entity?
	return EntityStore.target(self._entityStore, id, _resolveId(relation), index or 1)
end

-- Traits key on the relation's low id, matching what a pair stores (pairFirst
-- and a despawned entity's slot are both low ids), so component and entity
-- relations resolve to the same trait key.
function World.setRelationTrait(_self: WorldImpl, relation: ComponentRef<any>, traits: any): ()
	Cleanup.setRelationTrait(Component.lowId(_resolveId(relation)), traits)
end

function World.markDirty(self: WorldImpl, id: Entity, component: ComponentRef<any>): ()
	local compId = _assertRegisteredId(_resolveId(component))
	local name = _nameOf(component)
	if not name then
		return
	end

	EntityStore.markDirty(self._entityStore, id, name)

	if not self._observers:hasListeners("onChange", name) then
		return
	end

	local data = if Component.isSparseId(compId)
		then EntityStore.getSparse(self._entityStore, id, compId)
		else EntityStore.get(self._entityStore, id, compId)

	self._observers:fire("onChange", name, id, data)
end

function World.flushDirty(self: WorldImpl): { any }
	return EntityStore.flushDirty(self._entityStore)
end

function World.setSingleton(self: WorldImpl, name: string, data: any): ()
	self._singletons[name] = data
end

function World.getSingleton(self: WorldImpl, name: string): any?
	return self._singletons[name]
end

function World.addSystem(self: WorldImpl, systemDef: SystemDefinition): ()
	if systemDef.query then
		_validateQuery(systemDef.query)
	end

	table.insert(self._systems, systemDef)
	self._systemErrors[systemDef.name] = 0

	_sortSystems(self._systems)
end

function World.addSystems(self: WorldImpl, list: { SystemDefinition }): ()
	for _, systemDef in list do
		if systemDef.query then
			_validateQuery(systemDef.query)
		end

		table.insert(self._systems, systemDef)
		self._systemErrors[systemDef.name] = 0
	end

	_sortSystems(self._systems)
end

function World.enableSystem(self: WorldImpl, name: string): ()
	local sys = _findSystem(self._systems, name)
	if not sys then
		return
	end

	sys.enabled = true
	self._systemErrors[name] = 0
end

function World.disableSystem(self: WorldImpl, name: string): ()
	local sys = _findSystem(self._systems, name)
	if not sys then
		return
	end

	sys.enabled = false
end

function World.isSystemEnabled(self: WorldImpl, name: string): boolean
	local sys = _findSystem(self._systems, name)
	if not sys then
		return false
	end

	return sys.enabled
end

function World.step(self: WorldImpl, dt: number): ()
	if self._paused or self._destroyed then
		return
	end

	self._frameNumber += 1

	local disabledCount = 0

	for _, sys in self._systems do
		if not sys.enabled then
			disabledCount += 1
			continue
		end

		local entities: { Entity } = {}

		if sys.query then
			if Debugger._enabled then
				Debugger.lintQuery(sys.query, sys.name)
			end

			entities = EntityStore.collectEntities(self._entityStore, sys.query)
		end

		local startTime = os.clock()
		local ok, err = pcall(sys.run, entities, dt)
		local duration = (os.clock() - startTime) * 1000

		if ok then
			self._systemErrors[sys.name] = 0
			Debugger.logSystemRun(sys.name, duration, #entities)
			continue
		end

		local errorCount = (self._systemErrors[sys.name] or 0) + 1
		self._systemErrors[sys.name] = errorCount

		warn(`[World] System "{sys.name}" errored: {err}`)

		if errorCount >= CIRCUIT_BREAKER_THRESHOLD then
			sys.enabled = false
			warn(
				`[World] CIRCUIT BREAKER: system "{sys.name}" DISABLED after {CIRCUIT_BREAKER_THRESHOLD} `
					.. `consecutive errors and will NOT run again until re-enabled -- last error: {err}`
			)
		end
	end

	local activeCount = #self._systems - disabledCount
	local entityCount = EntityStore.countAlive(self._entityStore)

	Debugger.flush(self._frameNumber, activeCount, disabledCount, entityCount)
end

function World.pause(self: WorldImpl): ()
	self._paused = true
end

function World.resume(self: WorldImpl): ()
	self._paused = false
end

function World.isPaused(self: WorldImpl): boolean
	return self._paused
end

function World.bindInstance(self: WorldImpl, id: Entity, instance: any): ()
	EntityStore.bindInstance(self._entityStore, id, instance)
end

function World.getBoundInstances(self: WorldImpl, id: Entity): { any }?
	return self._entityStore._cleanup._bindings[id]
end

function World.onAdd(self: WorldImpl, name: string, callback: ObserverCallback): ()
	self._observers:register("onAdd", name, callback)
end

function World.onChange(self: WorldImpl, name: string, callback: ObserverCallback): ()
	self._observers:register("onChange", name, callback)
end

function World.onRemove(self: WorldImpl, name: string, callback: ObserverCallback): ()
	self._observers:register("onRemove", name, callback)
end

function World.spawnPrefab(self: WorldImpl, prefab: PrefabDefinition): Entity
	local id = self:spawn()

	for _, entry in prefab.components do
		local componentName = entry[1] :: string
		local overrides = entry[2] :: { [string]: any }?

		if Component.isTag(componentName) then
			self:addComponent(id, componentName)
			continue
		end

		local data: { [string]: any }

		if Component.isDefined(componentName) then
			data = Component.createInstance(componentName, overrides)
		elseif overrides then
			data = overrides
		else
			data = {}
		end

		self:addComponent(id, componentName, data)
	end

	return id
end

function World.destroy(self: WorldImpl): ()
	self._destroyed = true
	self._paused = true

	table.clear(self._systems)
	table.clear(self._systemErrors)
	table.clear(self._singletons)

	self._observers:clear()
end

-- Manual fragmentation sweep: destroy empty archetypes and prune stale pair
-- index buckets. There is no automatic cadence -- game code calls this when it
-- makes sense (e.g. between waves). Returns the number of archetypes destroyed.
function World.sweep(self: WorldImpl): number
	return EntityStore.sweep(self._entityStore)
end

-- Public replication/iteration surface. Game code (e.g. replication) reads the
-- live entity set and a component snapshot through these instead of reaching
-- into the private entity store.
function World.eachAlive(self: WorldImpl): () -> Entity?
	return EntityStore.eachAlive(self._entityStore)
end

function World.getComponents(self: WorldImpl, id: Entity): { [string]: { [string]: any } }?
	return EntityStore.getAllComponents(self._entityStore, id)
end

return World
