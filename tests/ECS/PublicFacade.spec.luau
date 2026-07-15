-- Public facade contract tests.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local VZNCore = require("../../src/_Facade")

local PublicExports = {
	"World",
	"Component",
	"Query",
	"System",
	"Prefab",
	"Debugger",
}

local InternalExports = {
	"Archetype",
	"Entity",
	"Observer",
	"Cleanup",
}

for _, Name in PublicExports do
	assert(VZNCore[Name] ~= nil, `expected public export {Name}`)
end

for _, Name in InternalExports do
	assert(VZNCore[Name] == nil, `internal module {Name} must not be exported`)
end

assert(table.isfrozen(VZNCore), "public facade must be frozen")

print("PublicFacade.spec: PASS")
