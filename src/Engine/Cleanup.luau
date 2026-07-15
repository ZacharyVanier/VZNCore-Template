--[[
	Cleanup -- owns relationship deletion traits and Instance cleanup.
	VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» DEPENDENCIES & VARIABLES «--

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

--» TYPE DEFINITIONS «--

type BindingMap = {
	[number]: { any },
}

export type CleanupAction = "delete" | "remove"

export type RelationTrait = {
	exclusive: boolean,
	onDelete: CleanupAction,
	onDeleteTarget: CleanupAction,
}

--» CONSTANTS «--

-- Defaults follow jecs: deleting a relation or a target Removes the affected
-- pairs (holders keep living). ChildOf overrides onDeleteTarget to Delete, so
-- despawning a parent cascades to its children, and is exclusive (one parent).
local DEFAULT_ON_DELETE: CleanupAction = "remove"
local DEFAULT_ON_DELETE_TARGET: CleanupAction = "remove"

--» MODULE-LEVEL STATE «--

-- Relation traits are global config keyed by relation id, like component
-- definitions -- not per-world. Seeded with the ChildOf hierarchy defaults.
local _relationTraits: { [number]: RelationTrait } = {}
local _relationTraitRevision: number = 0

--» PRIVATE FUNCTIONS «--

local function _seedRelationTraits(): ()
	_relationTraits[Component.ChildOf] = {
		exclusive = true,
		onDelete = "remove",
		onDeleteTarget = "delete",
	}
end

--» RELATION TRAITS «--

local Cleanup = {}
Cleanup.__index = Cleanup

Cleanup.setRelationTrait = function(
	relationId: number,
	traits: { exclusive: boolean?, onDelete: CleanupAction?, onDeleteTarget: CleanupAction? }
): ()
	local existing = _relationTraits[relationId]

	_relationTraits[relationId] = {
		exclusive = if traits.exclusive ~= nil then traits.exclusive elseif existing then existing.exclusive else false,
		onDelete = traits.onDelete or (existing and existing.onDelete) or DEFAULT_ON_DELETE,
		onDeleteTarget = traits.onDeleteTarget or (existing and existing.onDeleteTarget) or DEFAULT_ON_DELETE_TARGET,
	}
	_relationTraitRevision += 1
end

Cleanup.relationTraitRevision = function(): number
	return _relationTraitRevision
end

Cleanup.getRelationTrait = function(relationId: number): RelationTrait?
	return _relationTraits[relationId]
end

Cleanup.isExclusive = function(relationId: number): boolean
	local trait = _relationTraits[relationId]
	return trait ~= nil and trait.exclusive == true
end

Cleanup.onDelete = function(relationId: number): CleanupAction
	local trait = _relationTraits[relationId]
	return (trait and trait.onDelete) or DEFAULT_ON_DELETE
end

Cleanup.onDeleteTarget = function(relationId: number): CleanupAction
	local trait = _relationTraits[relationId]
	return (trait and trait.onDeleteTarget) or DEFAULT_ON_DELETE_TARGET
end

Cleanup._resetTraits = function(): ()
	table.clear(_relationTraits)
	_seedRelationTraits()
	_relationTraitRevision += 1
end

--» INSTANCE BINDING «--

export type Cleanup = typeof(setmetatable(
	{} :: {
		_bindings: BindingMap,
	},
	Cleanup
))

Cleanup.new = function(): Cleanup
	local self = setmetatable({}, Cleanup) :: Cleanup

	self._bindings = {}

	return self
end

Cleanup.bind = function(self: Cleanup, entityId: number, instance: any): ()
	if not self._bindings[entityId] then
		self._bindings[entityId] = {}
	end

	table.insert(self._bindings[entityId], instance)
end

Cleanup.unbindAll = function(self: Cleanup, entityId: number): ()
	local bound = self._bindings[entityId]
	if not bound then
		return
	end

	for _, instance in bound do
		if not instance or not instance.Parent then
			continue
		end
		instance:Destroy()
	end

	self._bindings[entityId] = nil
end

Cleanup.clear = function(self: Cleanup): ()
	table.clear(self._bindings)
end

_seedRelationTraits()

return Cleanup
