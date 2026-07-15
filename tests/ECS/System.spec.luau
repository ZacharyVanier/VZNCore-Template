-- System module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local System = require("../../src/Engine/System")
local Query = require("../../src/Engine/Query")

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

print("")
print("Running System tests...")
print("")

test(`System.new() creates a system definition`, function()
	local q = Query.all(`Health`, `Position`)

	local sys = System.new(`TestSystem`, {
		phase = `Update`,
		priority = 10,
		query = q,
		run = function(_entities: { number }, _dt: number): () end,
	})

	assert(sys ~= nil, `System.new() should return a table`)
	assert(type(sys) == "table", `System.new() should return a table`)
end)

test(`System has name, phase, priority, query, run, enabled fields`, function()
	local q = Query.all(`Health`)

	local sys = System.new(`MovementSystem`, {
		phase = `Update`,
		priority = 5,
		query = q,
		run = function(_entities: { number }, _dt: number): () end,
	})

	assert(sys.name == `MovementSystem`, `name should be MovementSystem, got {sys.name}`)
	assert(sys.phase == `Update`, `phase should be Update, got {sys.phase}`)
	assert(sys.priority == 5, `priority should be 5, got {sys.priority}`)
	assert(sys.query == q, `query should be the same query object`)
	assert(type(sys.run) == "function", `run should be a function`)
	assert(sys.enabled == true, `enabled should default to true`)
end)

test(`Systems sort by phase order then priority`, function()
	local noop = function(_entities: { number }, _dt: number): () end

	local renderSys = System.new(`RenderSys`, {
		phase = `Render`,
		priority = 0,
		run = noop,
	})

	local updateLow = System.new(`UpdateLow`, {
		phase = `Update`,
		priority = 1,
		run = noop,
	})

	local updateHigh = System.new(`UpdateHigh`, {
		phase = `Update`,
		priority = 10,
		run = noop,
	})

	local preUpdateSys = System.new(`PreUpdateSys`, {
		phase = `PreUpdate`,
		priority = 5,
		run = noop,
	})

	local systems = { renderSys, updateHigh, preUpdateSys, updateLow }

	table.sort(systems, function(a: any, b: any): boolean
		local orderA = System.PHASE_ORDER[a.phase]
		local orderB = System.PHASE_ORDER[b.phase]
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a.priority < b.priority
	end)

	assert(systems[1].name == `PreUpdateSys`, `first should be PreUpdateSys, got {systems[1].name}`)
	assert(systems[2].name == `UpdateLow`, `second should be UpdateLow, got {systems[2].name}`)
	assert(systems[3].name == `UpdateHigh`, `third should be UpdateHigh, got {systems[3].name}`)
	assert(systems[4].name == `RenderSys`, `fourth should be RenderSys, got {systems[4].name}`)
end)

test(`system.enabled defaults to true`, function()
	local sys = System.new(`TestSys`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): () end,
	})

	assert(sys.enabled == true, `enabled should default to true, got {tostring(sys.enabled)}`)
end)

test(`valid phases are accepted without error`, function()
	local noop = function(_entities: { number }, _dt: number): () end
	local phases = { `PreUpdate`, `Update`, `PostUpdate`, `PreRender`, `Render`, `PostRender` }

	for _, phase in phases do
		local sys = System.new(`Test_{phase}`, {
			phase = phase,
			run = noop,
		})

		assert(sys.phase == phase, `phase should be {phase}, got {sys.phase}`)
	end
end)

test(`invalid phase errors`, function()
	local ok, err = pcall(function(): ()
		System.new(`BadSys`, {
			phase = `InvalidPhase`,
			run = function(_entities: { number }, _dt: number): () end,
		})
	end)

	assert(not ok, `invalid phase should error`)
	assert(type(err) == "string", `error should be a string`)
end)

test(`missing name errors`, function()
	local ok, _err = pcall(function(): ()
		System.new(nil :: any, {
			phase = `Update`,
			run = function(_entities: { number }, _dt: number): () end,
		})
	end)

	assert(not ok, `missing name should error`)
end)

test(`missing phase errors`, function()
	local ok, _err = pcall(function(): ()
		System.new(
			`TestSys`,
			{
				run = function(_entities: { number }, _dt: number): () end,
			} :: any
		)
	end)

	assert(not ok, `missing phase should error`)
end)

test(`missing run function errors`, function()
	local ok, _err = pcall(function(): ()
		System.new(
			`TestSys`,
			{
				phase = `Update`,
			} :: any
		)
	end)

	assert(not ok, `missing run function should error`)
end)

test(`priority defaults to 0 when not provided`, function()
	local sys = System.new(`DefaultPriority`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): () end,
	})

	assert(sys.priority == 0, `priority should default to 0, got {sys.priority}`)
end)

test(`query is nil when not provided`, function()
	local sys = System.new(`NoQuery`, {
		phase = `PostUpdate`,
		run = function(_entities: { number }, _dt: number): () end,
	})

	assert(sys.query == nil, `query should be nil when not provided`)
end)

test(`PHASE_ORDER maps all 6 phases to correct numeric order`, function()
	assert(System.PHASE_ORDER[`PreUpdate`] == 1, `PreUpdate should be 1`)
	assert(System.PHASE_ORDER[`Update`] == 2, `Update should be 2`)
	assert(System.PHASE_ORDER[`PostUpdate`] == 3, `PostUpdate should be 3`)
	assert(System.PHASE_ORDER[`PreRender`] == 4, `PreRender should be 4`)
	assert(System.PHASE_ORDER[`Render`] == 5, `Render should be 5`)
	assert(System.PHASE_ORDER[`PostRender`] == 6, `PostRender should be 6`)
end)

test(`isValidPhase() returns correct boolean`, function()
	assert(System.isValidPhase(`PreUpdate`) == true, `PreUpdate should be valid`)
	assert(System.isValidPhase(`Update`) == true, `Update should be valid`)
	assert(System.isValidPhase(`PostUpdate`) == true, `PostUpdate should be valid`)
	assert(System.isValidPhase(`PreRender`) == true, `PreRender should be valid`)
	assert(System.isValidPhase(`Render`) == true, `Render should be valid`)
	assert(System.isValidPhase(`PostRender`) == true, `PostRender should be valid`)
	assert(System.isValidPhase(`Fake`) == false, `Fake should not be valid`)
	assert(System.isValidPhase(``) == false, `empty string should not be valid`)
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
