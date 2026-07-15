--[[
	Prefab -- stores reusable component bundles for entity construction.
	VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» TYPE DEFINITIONS «--

type PrefabEntry = { string | { [string]: unknown } }

type PrefabDefinition = {
	name: string,
	components: { PrefabEntry },
}

export type PrefabModule = {
	define: (string, { PrefabEntry }) -> (),
	getDefinition: (string) -> PrefabDefinition?,
	isDefined: (string) -> boolean,
}

type PrefabInternal = PrefabModule & {
	_reset: () -> (),
}

--» DEPENDENCIES & VARIABLES «--

local Definitions: { [string]: PrefabDefinition } = {}
local Prefab = {} :: PrefabInternal

--» PUBLIC FUNCTIONS «--

Prefab.define = function(Name: string, ComponentList: { PrefabEntry }): ()
	assert(Name ~= "", "[Prefab] name must not be empty")
	assert(Definitions[Name] == nil, `[Prefab] prefab "{Name}" is already defined`)

	Definitions[Name] = {
		name = Name,
		components = ComponentList,
	}
end

Prefab.getDefinition = function(Name: string): PrefabDefinition?
	return Definitions[Name]
end

Prefab.isDefined = function(Name: string): boolean
	return Definitions[Name] ~= nil
end

-- Test-only reset keeps the process-global registry deterministic between specs.
Prefab._reset = function(): ()
	table.clear(Definitions)
end

--» MODULE EXPORT «--

return Prefab
