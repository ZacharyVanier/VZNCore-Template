-- Runtime lint + world inspector tests for the ECS Debugger.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Query = require("../../src/Engine/Query")
local Debugger = require("../../src/Engine/Debugger")

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

local Pair = Component.Pair
local ChildOf = Component.ChildOf

-- Health/Fire are archetype data components; Boss is a tag; Buff is sparse.
local function setup(): ()
	Component._reset()
	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Fire`, { damage = 10 })
	Component.tag(`Boss`)
	Component.define(`Buff`, { stacks = 1 }, { sparse = true })
end

print("")
print("Running Debugger tests...")
print("")

--##========== RUNTIME LINTS ==========##--

test(`lint: get on a dead entity errors with a readable name in debug mode`, function()
	setup()
	local world = World.new()
	Debugger.enable()

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 1, max = 1 })
	world:despawn(id)

	local ok, err = pcall(function()
		return world:get(id, `Health`)
	end)

	Debugger._reset()
	world:destroy()

	assert(ok == false, `get on a dead entity must raise under debug mode`)
	assert(string.find(tostring(err), `Health`, 1, true) ~= nil, `error should name the component, got: {err}`)
	assert(
		string.find(tostring(err), `not alive`, 1, true) ~= nil,
		`error should say the entity is not alive, got: {err}`
	)
end)

test(`lint: setting data on a tag names the tag in debug mode`, function()
	setup()
	local world = World.new()
	Debugger.enable()

	local id = world:spawn()

	local ok, err = pcall(function()
		world:addComponent(id, `Boss`, { level = 9 })
	end)

	Debugger._reset()
	world:destroy()

	assert(ok == false, `writing data to a tag must raise under debug mode`)
	assert(string.find(tostring(err), `Boss`, 1, true) ~= nil, `error should name the tag, got: {err}`)
	assert(string.find(tostring(err), `tag`, 1, true) ~= nil, `error should mention it is a tag, got: {err}`)
end)

test(`lint: a pair tag prints as pair(Relation, Target), not a raw id`, function()
	setup()
	local world = World.new()
	Debugger.enable()

	local parent = world:spawn()
	local child = world:spawn()

	local ok, err = pcall(function()
		-- ChildOf is a tag, so its pair stores no data; writing data must lint.
		world:addComponent(child, Pair(ChildOf, parent), { weight = 1 })
	end)

	Debugger._reset()
	world:destroy()

	assert(ok == false, `writing data to a tag pair must raise under debug mode`)
	assert(
		string.find(tostring(err), `pair(ChildOf`, 1, true) ~= nil,
		`error should describe the pair by name, got: {err}`
	)
end)

test(`lint: a zero-component query errors and names the system`, function()
	setup()
	Debugger.enable()

	local emptyQuery = Query.all()

	local ok, err = pcall(function()
		Debugger.lintQuery(emptyQuery, `PatrolSystem`)
	end)

	Debugger._reset()

	assert(ok == false, `a zero-term query must raise under debug mode`)
	assert(
		string.find(tostring(err), `zero component`, 1, true) ~= nil,
		`error should flag zero components, got: {err}`
	)
	assert(string.find(tostring(err), `PatrolSystem`, 1, true) ~= nil, `error should name the system, got: {err}`)
end)

test(`lint: a zero-component query is caught in world:step under debug mode`, function()
	setup()
	local world = World.new()
	Debugger.enable()

	world:addSystem({
		name = `EmptyQuerySystem`,
		phase = `Update`,
		priority = 1,
		enabled = true,
		query = Query.all(),
		run = function() end,
	})

	local ok = pcall(function()
		world:step(0)
	end)

	Debugger._reset()
	world:destroy()

	assert(ok == false, `an empty-query system must be caught during step under debug mode`)
end)

test(`lints are silent when debug mode is off`, function()
	setup()
	local world = World.new()

	assert(Debugger.isEnabled() == false, `debug must start disabled`)

	local a = world:spawn()
	world:addComponent(a, `Health`, { current = 1, max = 1 })
	local b = world:spawn()
	world:addComponent(b, `Health`, { current = 1, max = 1 })

	-- The same empty query that raises under debug silently matches everything.
	local matched = world._entityStore:collectEntities(Query.all())
	assert(#matched == 2, `a zero-term query returns all entities when lints are off, got {#matched}`)

	world:addSystem({
		name = `EmptyQuerySystem`,
		phase = `Update`,
		priority = 1,
		enabled = true,
		query = Query.all(),
		run = function() end,
	})

	local ok = pcall(function()
		world:step(0)
	end)
	assert(ok == true, `an empty-query system must not raise while lints are off`)

	world:destroy()
end)

--##========== WORLD INSPECTOR ==========##--

test(`inspector: inspectEntity reports components, tag, pair and sparse by name`, function()
	setup()
	local world = World.new()

	local parent = world:spawn()
	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 42, max = 100 })
	world:addComponent(id, `Boss`)
	world:addComponent(id, `Buff`, { stacks = 3 })
	world:addComponent(id, Pair(ChildOf, parent))

	local info = Debugger.inspectEntity(world, id)

	assert(info.alive == true, `entity should be alive`)
	assert(
		info.components.Health ~= nil and info.components.Health.current == 42,
		`Health should be reported with its value`
	)
	assert(table.find(info.tags, `Boss`) ~= nil, `Boss tag should be listed by name`)
	assert(info.sparse.Buff ~= nil and info.sparse.Buff.stacks == 3, `Buff should be reported from the sparse store`)

	local sawChildOf = false
	for _, pairLabel in info.pairs do
		if string.find(pairLabel, `pair(ChildOf`, 1, true) ~= nil then
			sawChildOf = true
		end
	end
	assert(sawChildOf, `the ChildOf pair should be described by name, got: {table.concat(info.pairs, ", ")}`)

	world:destroy()
end)

test(`inspector: a dead entity reports as not alive with no components`, function()
	setup()
	local world = World.new()

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 1, max = 1 })
	world:despawn(id)

	local info = Debugger.inspectEntity(world, id)

	assert(info.alive == false, `a despawned entity must report not alive`)
	assert(next(info.components) == nil, `a dead entity must report no components`)

	world:destroy()
end)

test(`inspector: archetypeCensus counts entities and flags empty archetypes`, function()
	setup()
	local world = World.new()

	local a = world:spawn()
	world:addComponent(a, `Health`, { current = 1, max = 1 })
	local b = world:spawn()
	world:addComponent(b, `Health`, { current = 1, max = 1 })

	-- Vacate a {Health, Fire} archetype so the census sees an empty one.
	world:addComponent(a, `Fire`, { damage = 1 })
	world:removeComponent(a, `Fire`)

	local census = Debugger.archetypeCensus(world)

	assert(census.entityCount == 2, `two live entities across archetypes, got {census.entityCount}`)
	assert(census.emptyCount >= 1, `the vacated archetype should count as empty, got {census.emptyCount}`)
	assert(census.fragmentation > 0, `fragmentation must be positive when an empty archetype exists`)

	local sawHealthSignature = false
	for _, arch in census.archetypes do
		for _, sig in arch.signature do
			if sig == `Health` then
				sawHealthSignature = true
			end
		end
	end
	assert(sawHealthSignature, `census signatures should be component names, not ids`)

	world:destroy()
end)

test(`inspector: systemTimingReport aggregates run timings by total`, function()
	setup()
	Debugger.enable()

	Debugger.logSystemRun(`Alpha`, 2.0, 5)
	Debugger.logSystemRun(`Alpha`, 4.0, 6)
	Debugger.logSystemRun(`Beta`, 1.0, 1)

	local report = Debugger.systemTimingReport()

	Debugger._reset()

	assert(#report == 2, `two distinct systems should be reported, got {#report}`)
	assert(report[1].name == `Alpha`, `the system with the highest total should sort first`)
	assert(report[1].totalMs == 6.0, `Alpha total should accumulate 2 + 4, got {report[1].totalMs}`)
	assert(report[1].runs == 2, `Alpha should record two runs, got {report[1].runs}`)
	assert(report[1].maxMs == 4.0, `Alpha max should be the largest sample, got {report[1].maxMs}`)
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
