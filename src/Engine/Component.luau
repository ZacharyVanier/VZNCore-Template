-- Component definition registry, id-space and relationship pairs.
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

local ECSTypes = tryRequire(script and script.Parent and script.Parent.Types, "./Types")

--##========== TYPES ==========##--

type ComponentDefinition = ECSTypes.ComponentDefinition
type ComponentMetadata = ECSTypes.ComponentMetadata
type ComponentOptions = ECSTypes.ComponentOptions
type Component<T> = ECSTypes.Component<T>

--##========== CONSTANTS ==========##--

-- Pair packing mirrors jecs ecs_pair: the low 24 bits hold the target's slot,
-- the next 24 the relation's low id, and PAIR_OFFSET marks the value as a pair.
-- A pair strips the target's generation (% ENTITY_MASK); the live target is
-- recovered from the entity index when read (see World:target). Arithmetic (not
-- bit32) because pair ids exceed 32 bits but stay exact below 2^53.
local ENTITY_MASK = 2 ^ 24
local PAIR_OFFSET = 2 ^ 48

-- Builtins reserved high (jecs HI_COMPONENT_ID) so user components keep low ids
-- 1,2,3... These are fixed constants that survive _reset() and sit below
-- ENTITY_MASK so they pack cleanly as pair relations/targets.
local BUILTIN_BASE = 2 ^ 20

--##========== PRIVATE STATE ==========##--

local _definitions: { [string]: ComponentDefinition } = {}
local _handles: { [string]: Component<any> } = {}

-- The id space. Every component name is interned to a unique integer id the
-- moment it is first seen (whether via define/tag or a raw string reaching the
-- World boundary). Storage keys on these ids; observers/replication stay
-- name-keyed, so both maps are kept.
local _nameToId: { [string]: number } = {}
local _idToName: { [number]: string } = {}
local _tagIds: { [number]: boolean } = {}
local _sparseIds: { [number]: boolean } = {}
local _unboxedIds: { [number]: boolean } = {}
local _metadata: { [number]: ComponentMetadata } = {}
local _nextId: number = 0

--##========== PUBLIC API ==========##--

local Component = {}
Component.metadata = _metadata

-- Wildcard matches any relation or any target in a pair query. ChildOf is the
-- builtin hierarchy relation (a tag, so its pairs store no column).
Component.Wildcard = BUILTIN_BASE + 1
Component.ChildOf = BUILTIN_BASE + 2

--##========== PRIVATE FUNCTIONS ==========##--

local function _seedBuiltins(): ()
	_nameToId["Wildcard"] = Component.Wildcard
	_idToName[Component.Wildcard] = "Wildcard"
	_metadata[Component.Wildcard] = {
		name = `Wildcard`,
		isTag = false,
		isSparse = false,
		isPair = false,
	}

	_nameToId["ChildOf"] = Component.ChildOf
	_idToName[Component.ChildOf] = "ChildOf"
	_tagIds[Component.ChildOf] = true
	_metadata[Component.ChildOf] = {
		name = `ChildOf`,
		isTag = true,
		isSparse = false,
		isPair = false,
	}
end

local function _internName(name: string): number
	local existing = _nameToId[name]
	if existing then
		return existing
	end

	_nextId += 1
	_nameToId[name] = _nextId
	_idToName[_nextId] = name
	_metadata[_nextId] = {
		name = name,
		isTag = false,
		isSparse = false,
		isPair = false,
	}

	return _nextId
end

local function _refToId(ref: any): number
	local kind = type(ref)

	if kind == "number" then
		return ref :: number
	end

	if kind == "table" then
		return (ref :: any).id
	end

	return _internName(ref :: string)
end

local function _shallowCopy(source: { [string]: any }): { [string]: any }
	return table.clone(source)
end

local function _shallowMerge(base: { [string]: any }, overrides: { [string]: any }): { [string]: any }
	local merged = _shallowCopy(base)

	for key, value in overrides do
		merged[key] = value
	end

	return merged
end

local function _register(
	name: string,
	defaults: { [string]: any },
	options: ComponentOptions?,
	isTag: boolean
): Component<any>
	assert(not _definitions[name], `[Component] Component already defined: {name}`)

	local resolvedOptions = options or {}

	_definitions[name] = {
		name = name,
		defaults = defaults,
		singleton = resolvedOptions.singleton or false,
		replicated = resolvedOptions.replicated or false,
		isTag = isTag,
		sparse = resolvedOptions.sparse or false,
		unboxed = resolvedOptions.unboxed or false,
	}

	local id = _internName(name)
	local metadata = _metadata[id]
	metadata.isTag = isTag
	metadata.isSparse = resolvedOptions.sparse == true

	if isTag then
		_tagIds[id] = true

		for pairId, pairMetadata in _metadata do
			if pairMetadata.isPair and (pairId - PAIR_OFFSET) // ENTITY_MASK == id then
				pairMetadata.isTag = true
			end
		end
	end

	if resolvedOptions.sparse then
		_sparseIds[id] = true
	end

	if resolvedOptions.unboxed then
		_unboxedIds[id] = true
	end

	local handle = (table.freeze({
		id = id,
		name = name,
		isTag = isTag,
	}) :: any) :: Component<any>

	_handles[name] = handle

	return handle
end

--##========== ID SPACE ==========##--

-- Interns and returns the stable numeric id for a name. Called at the World
-- boundary so a raw string reaches storage as an id even if never define()d.
function Component.idOf(name: string): number
	return _nameToId[name] or _internName(name)
end

-- One-frame ref->id resolver for the hot write/read paths. Same result as
-- composing type-dispatch + idOf, but a string takes the _nameToId fast lookup
-- inline (no _internName frame on the interned case) and a number/handle returns
-- immediately. World's _resolveId aliases this; churn resolves twice per op.
function Component.toId(ref: any): number
	local kind = type(ref)

	if kind == "number" then
		return ref :: number
	end

	if kind == "string" then
		return _nameToId[ref] or _internName(ref)
	end

	return (ref :: any).id
end

function Component.assertRegisteredId(id: any): number
	if type(id) ~= `number` or id % 1 ~= 0 or id <= 0 then
		error(`[Component] Invalid component id {tostring(id)}`)
	end

	if not _metadata[id] then
		error(`[Component] Unregistered component id {id}`)
	end

	return id
end

-- Reverse of idOf. Returns nil for ids with no registered name (e.g. pairs),
-- which is how name-keyed layers (observers, replication) skip them.
function Component.nameOf(id: number): string?
	return _idToName[id]
end

-- Low 24 bits of an id: the slot of an entity, stripping any generation.
function Component.lowId(id: number): number
	return id % ENTITY_MASK
end

-- Allocates a fresh id from the single shared counter WITHOUT registering a
-- name. Entity slots and component ids draw from this one counter (jecs-style
-- unification), so a component id and an entity slot can never be the same
-- number. That disjointness is what makes an entity-as-relation pair
-- Pair(someEntity, x) sound: isTagId(slot) finds no component at that number
-- and so cannot reinterpret the entity's slot as a tag/data component.
function Component.newEntity(): number
	_nextId += 1
	return _nextId
end

--##========== PAIRS ==========##--

-- Packs a (relation, target) pair into one id. Relation/target may be a name,
-- a handle, or a raw id/entity; only the low 24 bits of each are stored.
function Component.Pair(relation: any, target: any): number
	local r = _refToId(relation) % ENTITY_MASK
	local t = _refToId(target) % ENTITY_MASK
	local pair = t + (r * ENTITY_MASK) + PAIR_OFFSET
	local relationMetadata = _metadata[r]

	if not _metadata[pair] then
		_metadata[pair] = {
			name = nil,
			isTag = relationMetadata ~= nil and relationMetadata.isTag,
			isSparse = false,
			isPair = true,
		}
	end

	return pair
end

function Component.isPair(id: number): boolean
	return id >= PAIR_OFFSET
end

-- The relation (predicate) low id of a pair.
function Component.pairFirst(id: number): number
	return (id - PAIR_OFFSET) // ENTITY_MASK
end

-- The target (object) slot of a pair.
function Component.pairSecond(id: number): number
	return (id - PAIR_OFFSET) % ENTITY_MASK
end

--##========== DEFINITION API ==========##--

function Component.define<T>(name: string, defaults: T, options: ComponentOptions?): Component<T>
	return (_register(name, defaults :: any, options, false) :: any) :: Component<T>
end

function Component.tag(name: string): Component<nil>
	return (_register(name, {}, nil, true) :: any) :: Component<nil>
end

function Component.getDefinition(name: string): ComponentDefinition?
	return _definitions[name]
end

function Component.getHandle(name: string): Component<any>?
	return _handles[name]
end

function Component.createInstance(name: string, overrides: any?): any
	local definition = _definitions[name]
	assert(definition, `[Component] Cannot create instance of undefined component: {name}`)

	-- Unboxed components carry a raw value, not a data table: the override IS the
	-- value, and the default is returned as-is (no clone/merge).
	if definition.unboxed then
		if overrides ~= nil then
			return overrides
		end
		return definition.defaults
	end

	if overrides then
		return _shallowMerge(definition.defaults, overrides)
	end

	return _shallowCopy(definition.defaults)
end

function Component.isDefined(name: string): boolean
	return _definitions[name] ~= nil
end

function Component.isTag(name: string): boolean
	local definition = _definitions[name]
	return definition ~= nil and definition.isTag == true
end

-- Id-keyed tag test for the storage layer. Tag membership is hoisted into a
-- flag map at define time so this is one lookup, not a name + definition walk.
-- A pair is a tag iff its relation is a tag (ChildOf), storing no column.
function Component.isTagId(id: number): boolean
	if id >= PAIR_OFFSET then
		return _tagIds[(id - PAIR_OFFSET) // ENTITY_MASK] == true
	end

	return _tagIds[id] == true
end

-- Every currently-defined replicated component name. Replication registers an
-- onAdd observer per name so prefab-applied replicated components reach
-- already-connected clients (they otherwise never mark dirty on add).
function Component.getReplicatedNames(): { string }
	local names: { string } = {}

	for name, definition in _definitions do
		if definition.replicated then
			table.insert(names, name)
		end
	end

	return names
end

function Component.isReplicated(name: string): boolean
	local definition = _definitions[name]
	if not definition then
		return false
	end

	return definition.replicated == true
end

function Component.isSparse(name: string): boolean
	local definition = _definitions[name]
	if not definition then
		return false
	end

	return definition.sparse == true
end

-- Id-keyed sparse test for the storage layer. A pair is NEVER sparse: it lives
-- in the archetype signature because wildcard matching, world:target and the
-- despawn cleanup traits all read pairs out of archetype types, so a sparse
-- relation still stores its pairs archetypally. Sparse applies only to plain
-- (non-pair) component ids.
function Component.isSparseId(id: number): boolean
	if id >= PAIR_OFFSET then
		return false
	end

	return _sparseIds[id] == true
end

-- Id-keyed unboxed test. An unboxed component stores its raw value directly in
-- the archetype column instead of a per-entity data table, so consumers read it
-- as the value (not a { field = value } table). Pairs are never unboxed. Opt in
-- via Component.define(name, default, { unboxed = true }).
function Component.isUnboxed(id: number): boolean
	if id >= PAIR_OFFSET then
		return false
	end

	return _unboxedIds[id] == true
end

-- Combined id classification for the write paths. Returns (isPair, isTag,
-- isSparse) in one call and one PAIR_OFFSET branch, versus three separate
-- isPair/isTagId/isSparseId calls. Semantics are identical to composing those
-- three: a pair is a tag iff its relation is a tag and is never sparse; a plain
-- id reads the tag and sparse flag maps directly. World's add/set paths (which
-- need all three) use this; single-bit read paths keep the individual predicate.
function Component.classify(id: number): (boolean, boolean, boolean)
	if id >= PAIR_OFFSET then
		return true, _tagIds[(id - PAIR_OFFSET) // ENTITY_MASK] == true, false
	end

	return false, _tagIds[id] == true, _sparseIds[id] == true
end

-- Resolve + classify in ONE frame for World's add/set hot paths: returns the id
-- plus the same (isPair, isTag, isSparse) as classify, so those paths make one
-- Component call instead of a toId call followed by a classify call. The two
-- flag-map lookups are irreducible; this only removes the extra call frame.
function Component.classifyRef(ref: any): (number, boolean, boolean, boolean)
	local kind = type(ref)
	local id: number

	if kind == "number" then
		id = ref
	elseif kind == "string" then
		id = _nameToId[ref] or _internName(ref)
	else
		id = (ref :: any).id
	end

	if id >= PAIR_OFFSET then
		return id, true, _tagIds[(id - PAIR_OFFSET) // ENTITY_MASK] == true, false
	end

	return id, false, _tagIds[id] == true, _sparseIds[id] == true
end

function Component.isSingleton(name: string): boolean
	local definition = _definitions[name]
	if not definition then
		return false
	end

	return definition.singleton == true
end

function Component._reset(): ()
	table.clear(_definitions)
	table.clear(_handles)
	table.clear(_nameToId)
	table.clear(_idToName)
	table.clear(_tagIds)
	table.clear(_sparseIds)
	table.clear(_unboxedIds)
	table.clear(_metadata)
	_nextId = 0

	_seedBuiltins()
end

_seedBuiltins()

return Component
