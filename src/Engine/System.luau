--[[
	System -- validates and constructs phased ECS system definitions.
	VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» TYPE DEFINITIONS «--

type Phase = "PreUpdate" | "Update" | "PostUpdate" | "PreRender" | "Render" | "PostRender"

type SystemConfig = {
	phase: Phase,
	priority: number?,
	query: unknown?,
	run: (entities: { number }, dt: number) -> (),
}

type SystemDefinition = {
	name: string,
	phase: Phase,
	priority: number,
	query: unknown?,
	run: (entities: { number }, dt: number) -> (),
	enabled: boolean,
}

export type SystemModule = {
	PHASE_ORDER: { [Phase]: number },
	isValidPhase: (Phase | string) -> boolean,
	new: (string, SystemConfig) -> SystemDefinition,
}

--» DEPENDENCIES & VARIABLES «--

local System = {} :: SystemModule

System.PHASE_ORDER = {
	PreUpdate = 1,
	Update = 2,
	PostUpdate = 3,
	PreRender = 4,
	Render = 5,
	PostRender = 6,
}

--» PUBLIC FUNCTIONS «--

System.isValidPhase = function(PhaseName: Phase | string): boolean
	return System.PHASE_ORDER[PhaseName :: Phase] ~= nil
end

System.new = function(Name: string, Configuration: SystemConfig): SystemDefinition
	assert(type(Name) == "string" and Name ~= "", "[System] name must be a non-empty string")
	assert(type(Configuration) == "table", `[System] configuration is required for system "{Name}"`)
	assert(type(Configuration.phase) == "string", `[System] phase is required for system "{Name}"`)
	assert(
		System.isValidPhase(Configuration.phase),
		`[System] invalid phase "{Configuration.phase}" for system "{Name}"`
	)
	assert(type(Configuration.run) == "function", `[System] run function is required for system "{Name}"`)

	return {
		name = Name,
		phase = Configuration.phase,
		priority = Configuration.priority or 0,
		query = Configuration.query,
		run = Configuration.run,
		enabled = true,
	}
end

--» MODULE EXPORT «--

return System
