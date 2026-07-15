-- Prefab module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Prefab = require("../../src/Engine/Prefab")

local _passed: number = 0
local _failed: number = 0

local function test(name: string, fn: () -> ()): ()
	local ok, err = pcall(fn)

	if ok then
		_passed += 1
		print(`  PASS: {name}`)
	else
		_failed += 1
		print(`  FAIL: {name}`)
		print(`        {err}`)
	end
end

local function setup(): ()
	Component._reset()
	Prefab._reset()
end

print("")
print("Running Prefab tests...")
print("")

test(`Prefab.define() registers a prefab`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Stats`, { level = 1, xp = 0 })

	Prefab.define(`Player`, {
		{ `Health` },
		{ `Stats` },
	})

	assert(Prefab.isDefined(`Player`) == true, `Player prefab should be defined`)
end)

test(`Prefab.getDefinition() returns the definition`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Stats`, { level = 1, xp = 0 })

	Prefab.define(`Player`, {
		{ `Health` },
		{ `Stats` },
	})

	local def = Prefab.getDefinition(`Player`)

	assert(def ~= nil, `getDefinition should return the definition`)
	assert(def.name == `Player`, `definition name should be Player`)
	assert(#def.components == 2, `definition should have 2 components`)
end)

test(`Prefab.define() with overrides stores correctly`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Stats`, { level = 1, xp = 0 })

	Prefab.define(`BossEnemy`, {
		{ `Health`, { current = 500, max = 500 } },
		{ `Stats` },
	})

	local def = Prefab.getDefinition(`BossEnemy`)

	assert(def ~= nil, `BossEnemy definition should exist`)
	assert(def.name == `BossEnemy`, `definition name should be BossEnemy`)
	assert(#def.components == 2, `should have 2 component entries`)

	local healthEntry = def.components[1]
	assert(healthEntry[1] == `Health`, `first entry name should be Health`)
	assert(healthEntry[2] ~= nil, `first entry should have overrides`)
	assert(healthEntry[2].current == 500, `Health override current should be 500`)
end)

test(`Prefab.isDefined() returns true for defined prefab`, function()
	setup()

	Prefab.define(`TestPrefab`, {
		{ `SomeComponent` },
	})

	assert(Prefab.isDefined(`TestPrefab`) == true, `isDefined should return true for defined prefab`)
end)

test(`Prefab.isDefined() returns false for unknown prefab`, function()
	setup()

	assert(Prefab.isDefined(`Unknown`) == false, `isDefined should return false for unknown prefab`)
end)

test(`world:spawnPrefab() creates entity with all components using defaults`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Position`, { x = 0, y = 0, z = 0 })

	local world = World.new()

	local prefab = {
		name = `Player`,
		components = {
			{ `Health` },
			{ `Position` },
		},
	}

	local id = world:spawnPrefab(prefab)

	assert(world:isAlive(id) == true, `entity should be alive`)
	assert(world:hasComponent(id, `Health`) == true, `entity should have Health`)
	assert(world:hasComponent(id, `Position`) == true, `entity should have Position`)

	local health = world:get(id, `Health`)
	assert(health.current == 100, `Health.current should be default 100, got {health.current}`)
	assert(health.max == 100, `Health.max should be default 100`)

	local pos = world:get(id, `Position`)
	assert(pos.x == 0, `Position.x should be default 0`)
	assert(pos.y == 0, `Position.y should be default 0`)

	world:destroy()
end)

test(`world:spawnPrefab() creates entity with override values applied`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Position`, { x = 0, y = 0, z = 0 })

	local world = World.new()

	local prefab = {
		name = `Enemy`,
		components = {
			{ `Health`, { current = 500, max = 500 } },
			{ `Position`, { x = 50, y = 10, z = -20 } },
		},
	}

	local id = world:spawnPrefab(prefab)

	assert(world:isAlive(id) == true, `entity should be alive`)

	local health = world:get(id, `Health`)
	assert(health.current == 500, `Health.current should be overridden to 500, got {health.current}`)
	assert(health.max == 500, `Health.max should be overridden to 500`)

	local pos = world:get(id, `Position`)
	assert(pos.x == 50, `Position.x should be overridden to 50`)
	assert(pos.y == 10, `Position.y should be overridden to 10`)
	assert(pos.z == -20, `Position.z should be overridden to -20`)

	world:destroy()
end)

test(`Prefab.define() same name twice errors`, function()
	setup()

	Prefab.define(`Player`, {
		{ `Health` },
	})

	local ok, _err = pcall(function()
		Prefab.define(`Player`, {
			{ `Stats` },
		})
	end)

	assert(not ok, `Defining same prefab twice should error`)
end)

test(`Prefab.getDefinition() returns nil for nonexistent`, function()
	setup()

	local def = Prefab.getDefinition(`Nonexistent`)

	assert(def == nil, `getDefinition for nonexistent should return nil`)
end)

test(`Prefab._reset() clears all definitions`, function()
	setup()

	Prefab.define(`A`, { { `Health` } })
	Prefab.define(`B`, { { `Stats` } })

	assert(Prefab.isDefined(`A`) == true, `A should be defined before reset`)
	assert(Prefab.isDefined(`B`) == true, `B should be defined before reset`)

	Prefab._reset()

	assert(Prefab.isDefined(`A`) == false, `A should not be defined after reset`)
	assert(Prefab.isDefined(`B`) == false, `B should not be defined after reset`)
end)

print("")
print(`Results: {_passed} passed, {_failed} failed out of {_passed + _failed} tests`)

if _failed > 0 then
	print("")
	print(`SOME TESTS FAILED`)
	process.exit(1)
end

print("")
print(`ALL TESTS PASSED`)
