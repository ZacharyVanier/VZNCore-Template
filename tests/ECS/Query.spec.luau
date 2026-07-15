-- Query module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local Query = require("../../src/Engine/Query")
local Component = require("../../src/Engine/Component")

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

-- Component sets are keyed by numeric id after the id-space migration. These
-- stand-in ids exercise all/any/none matching without registering components.
local HEALTH = 1
local POSITION = 2
local FIRE = 3
local ICE = 4
local DEAD = 5

print("")
print("Running Query tests...")
print("")

test(`Query.all() creates a query object`, function()
	local q = Query.all(HEALTH, POSITION)

	assert(q ~= nil, `Query.all() should return a table`)
	assert(type(q.matches) == "function", `query should have matches method`)
	assert(type(q.all) == "function", `query should have all method`)
	assert(type(q.any) == "function", `query should have any method`)
	assert(type(q.none) == "function", `query should have none method`)
end)

test(`Query.any() creates a query object`, function()
	local q = Query.any(FIRE, ICE)

	assert(q ~= nil, `Query.any() should return a table`)
	assert(type(q.matches) == "function", `query should have matches method`)
end)

test(`Query.all():none() chains correctly`, function()
	local q = Query.all(HEALTH):none(DEAD)

	assert(q ~= nil, `chained query should return a table`)
	assert(type(q.matches) == "function", `chained query should have matches method`)
end)

test(`Query.any():all() chains correctly`, function()
	local q = Query.any(FIRE, ICE):all(HEALTH)

	assert(q ~= nil, `chained query should return a table`)
	assert(type(q.matches) == "function", `chained query should have matches method`)
end)

test(`matches() returns true for valid component set`, function()
	local q = Query.all(HEALTH, POSITION):any(FIRE, ICE):none(DEAD)

	local componentSet = {
		[HEALTH] = { current = 100, max = 100 },
		[POSITION] = { x = 0, y = 0, z = 0 },
		[FIRE] = { damage = 10 },
	}

	assert(q:matches(componentSet) == true, `should match when all conditions met`)
end)

test(`matches() returns false when missing required component`, function()
	local q = Query.all(HEALTH, POSITION)

	local componentSet = {
		[HEALTH] = { current = 100, max = 100 },
	}

	assert(q:matches(componentSet) == false, `should not match when missing Position`)
end)

test(`matches() returns false when entity has excluded component`, function()
	local q = Query.all(HEALTH):none(DEAD)

	local componentSet = {
		[HEALTH] = { current = 100, max = 100 },
		[DEAD] = true,
	}

	assert(q:matches(componentSet) == false, `should not match when Dead is present`)
end)

test(`empty query matches everything`, function()
	local q = Query.all()

	local componentSet = {
		[HEALTH] = { current = 100, max = 100 },
		[POSITION] = { x = 0, y = 0, z = 0 },
	}

	assert(q:matches(componentSet) == true, `empty query should match any component set`)
	assert(q:matches({}) == true, `empty query should match empty component set`)
end)

test(`Query.none() returns true when excluded component absent`, function()
	local q = Query.none(DEAD)

	local componentSet = {
		[HEALTH] = { current = 100, max = 100 },
	}

	assert(q:matches(componentSet) == true, `should match when Dead is not present`)
end)

test(`Query.none() returns false when excluded component present`, function()
	local q = Query.none(DEAD)

	local componentSet = {
		[DEAD] = true,
	}

	assert(q:matches(componentSet) == false, `should not match when Dead is present`)
end)

test(`cached() returns a cacheable query that still matches`, function()
	local q = Query.all(HEALTH):cached()

	assert(type(q.matches) == "function", `cached query should retain matches method`)
	assert(q._cached == true, `cached query should carry the cached flag`)
	assert(q:matches({ [HEALTH] = { current = 1 } }) == true, `cached query should still match a valid set`)
	assert(q:matches({}) == false, `cached query should not match an empty set`)
end)

test(`select() records projections without changing filter membership`, function()
	local base = Query.all(HEALTH)
	local projected = base:select(POSITION, FIRE)

	assert(#base._select == 0, `select should clone instead of mutating the source query`)
	assert(#projected._all == 1 and projected._all[1] == HEALTH, `select should preserve all() filters`)
	assert(
		#projected._select == 2 and projected._select[1] == POSITION and projected._select[2] == FIRE,
		`select should record projected ids in argument order`
	)
	assert(projected:matches({ [HEALTH] = true }) == true, `missing projected components must not filter the entity`)
end)

test(`Query.all(handle) resolves the handle to its numeric id`, function()
	Component._reset()
	local health = Component.define(`Health`, { current = 100, max = 100 })

	local q = Query.all(health)

	assert(q._all[1] == health.id, `handle should resolve to its id in the query, got {tostring(q._all[1])}`)
	assert(q:matches({ [health.id] = { current = 1 } }) == true, `query should match a set containing the resolved id`)
	assert(q:matches({}) == false, `query should not match an empty set`)
end)

test(`mixed string and handle args both resolve to ids`, function()
	Component._reset()
	local position = Component.define(`Position`, { x = 0, y = 0, z = 0 })
	local healthId = Component.idOf(`Health`)

	local q = Query.all(`Health`, position)

	assert(
		q:matches({ [healthId] = { current = 1 }, [position.id] = { x = 0 } }) == true,
		`both required components present should match`
	)
	assert(
		q:matches({ [healthId] = { current = 1 } }) == false,
		`missing the handle-supplied component should not match`
	)
end)

test(`handles work through chained any() and none()`, function()
	Component._reset()
	local dead = Component.tag(`Dead`)
	local burning = Component.define(`Burning`, { stacks = 1 })
	local healthId = Component.idOf(`Health`)
	local poisonedId = Component.idOf(`Poisoned`)

	local q = Query.all(`Health`):any(burning, `Poisoned`):none(dead)

	assert(
		q:matches({ [healthId] = { current = 1 }, [burning.id] = { stacks = 1 } }) == true,
		`chained handle args should match`
	)
	assert(q:matches({ [healthId] = { current = 1 } }) == false, `missing the any() group should not match`)
	assert(
		q:matches({ [healthId] = { current = 1 }, [burning.id] = { stacks = 1 }, [dead.id] = true }) == false,
		`presence of the none() tag should exclude`
	)
	assert(poisonedId ~= nil, `Poisoned should resolve to an id`)
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
