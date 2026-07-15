-- Cleanup (instance binding and despawn cleanup) dedicated tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Cleanup = require("../../src/Engine/Cleanup")

local Pair = Component.Pair
local ChildOf = Component.ChildOf

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
end

local destroyLog: { string } = {}

local function makeMock(name: string): any
	return {
		Parent = true,
		Destroy = function(_self: any)
			table.insert(destroyLog, name)
		end,
	}
end

print("")
print("Running Cleanup tests...")
print("")

test(`world:bindInstance() tracks the binding`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local id = world:spawn()
	local mock = makeMock(`partA`)

	world:bindInstance(id, mock :: any)

	assert(#destroyLog == 0, `binding should not destroy the instance, got {#destroyLog}`)
	assert(world:isAlive(id) == true, `entity should still be alive after binding`)

	world:destroy()
end)

test(`multiple bindings per entity`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local id = world:spawn()

	local mockA = makeMock(`instanceA`)
	local mockB = makeMock(`instanceB`)
	local mockC = makeMock(`instanceC`)

	world:bindInstance(id, mockA :: any)
	world:bindInstance(id, mockB :: any)
	world:bindInstance(id, mockC :: any)

	assert(#destroyLog == 0, `no instances should be destroyed by binding alone`)

	world:despawn(id)

	assert(#destroyLog == 3, `all 3 bound instances should be destroyed, got {#destroyLog}`)

	local hasA = false
	local hasB = false
	local hasC = false

	for _, name in destroyLog do
		if name == `instanceA` then
			hasA = true
		end
		if name == `instanceB` then
			hasB = true
		end
		if name == `instanceC` then
			hasC = true
		end
	end

	assert(hasA, `instanceA should have been destroyed`)
	assert(hasB, `instanceB should have been destroyed`)
	assert(hasC, `instanceC should have been destroyed`)

	world:destroy()
end)

test(`world:despawn() calls Destroy on all bound instances`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local id = world:spawn()

	local mockX = makeMock(`partX`)
	local mockY = makeMock(`partY`)

	world:bindInstance(id, mockX :: any)
	world:bindInstance(id, mockY :: any)

	world:despawn(id)

	assert(#destroyLog == 2, `despawn should destroy 2 instances, got {#destroyLog}`)
	assert(world:isAlive(id) == false, `entity should not be alive after despawn`)

	world:destroy()
end)

test(`binding to non-alive entity errors`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local id = world:spawn()

	world:despawn(id)

	local mock = makeMock(`orphan`)

	local ok, _err = pcall(function()
		world:bindInstance(id, mock :: any)
	end)

	assert(not ok, `binding to despawned entity should error`)

	world:destroy()
end)

test(`despawn with no bindings does not error`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local id = world:spawn()

	world:despawn(id)

	assert(#destroyLog == 0, `no destroy calls should happen when no bindings exist`)
	assert(world:isAlive(id) == false, `entity should not be alive`)

	world:destroy()
end)

test(`bound instances with nil Parent are handled gracefully`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local id = world:spawn()

	local mockWithParent = makeMock(`hasParent`)
	local mockWithoutParent = {
		Parent = nil,
		Destroy = function(_self: any)
			table.insert(destroyLog, `noParent`)
		end,
	}

	world:bindInstance(id, mockWithParent :: any)
	world:bindInstance(id, mockWithoutParent :: any)

	world:despawn(id)

	assert(#destroyLog == 1, `only instance with Parent should be destroyed, got {#destroyLog}`)
	assert(destroyLog[1] == `hasParent`, `only hasParent mock should be destroyed`)

	world:destroy()
end)

test(`despawn triggers both instance cleanup and onRemove observers`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()
	local removedComponents: { string } = {}

	world:onRemove(`Health`, function(_entity: number, _data: any)
		table.insert(removedComponents, `Health`)
	end)

	local id = world:spawn()
	local mock = makeMock(`modelInstance`)

	world:addComponent(id, `Health`, { current = 100, max = 100 })
	world:bindInstance(id, mock :: any)

	world:despawn(id)

	assert(#destroyLog == 1, `bound instance should be destroyed on despawn`)
	assert(destroyLog[1] == `modelInstance`, `correct instance should be destroyed`)
	assert(#removedComponents == 1, `onRemove should fire for Health`)
	assert(removedComponents[1] == `Health`, `removed component should be Health`)

	world:destroy()
end)

test(`multiple entities with separate bindings are independent`, function()
	setup()
	table.clear(destroyLog)

	local world = World.new()

	local id1 = world:spawn()
	local id2 = world:spawn()

	local mock1 = makeMock(`entity1_part`)
	local mock2 = makeMock(`entity2_part`)

	world:bindInstance(id1, mock1 :: any)
	world:bindInstance(id2, mock2 :: any)

	world:despawn(id1)

	assert(#destroyLog == 1, `only entity1 instance should be destroyed, got {#destroyLog}`)
	assert(destroyLog[1] == `entity1_part`, `entity1_part should be destroyed`)
	assert(world:isAlive(id2) == true, `entity2 should still be alive`)

	world:despawn(id2)

	assert(#destroyLog == 2, `now both instances should be destroyed, got {#destroyLog}`)
	assert(destroyLog[2] == `entity2_part`, `entity2_part should be destroyed second`)

	world:destroy()
end)

test(`cleanup trait OnDeleteTarget=delete: despawning a parent cascades to ChildOf children`, function()
	Component._reset()
	Cleanup._resetTraits()

	local world = World.new()
	local parent = world:spawn()
	local childA = world:spawn()
	local childB = world:spawn()

	world:addComponent(childA, Pair(ChildOf, parent))
	world:addComponent(childB, Pair(ChildOf, parent))

	world:despawn(parent)

	assert(world:isAlive(parent) == false, `parent should be gone`)
	assert(world:isAlive(childA) == false, `childA should cascade-despawn (ChildOf default = delete)`)
	assert(world:isAlive(childB) == false, `childB should cascade-despawn`)

	world:destroy()
end)

test(`cleanup trait OnDeleteTarget=remove: despawning a target orphans holders`, function()
	Component._reset()
	Cleanup._resetTraits()

	local world = World.new()
	local livesIn = Component.tag(`LivesIn`)
	local place = world:spawn()
	local resident = world:spawn()

	world:addComponent(resident, Pair(livesIn, place))
	assert(world:hasComponent(resident, Pair(livesIn, place)) == true, `resident should hold the pair`)

	world:despawn(place)

	assert(world:isAlive(resident) == true, `resident should survive (default trait = remove)`)
	assert(world:hasComponent(resident, Pair(livesIn, place)) == false, `the pair should be removed`)

	world:destroy()
end)

test(`cleanup trait OnDelete=delete: despawning a relation entity cascades to holders`, function()
	Component._reset()
	Cleanup._resetTraits()

	local world = World.new()
	local relation = world:spawn()
	local target = world:spawn()
	local holder = world:spawn()

	world:setRelationTrait(relation, { onDelete = `delete` })
	world:addComponent(holder, Pair(relation, target))

	world:despawn(relation)

	assert(world:isAlive(relation) == false, `relation entity should be gone`)
	assert(world:isAlive(holder) == false, `holder should cascade-despawn on relation delete`)

	world:destroy()
end)

test(`cleanup trait OnDelete=remove (default): despawning a relation entity orphans holders`, function()
	Component._reset()
	Cleanup._resetTraits()

	local world = World.new()
	local relation = world:spawn()
	local target = world:spawn()
	local holder = world:spawn()

	world:addComponent(holder, Pair(relation, target))
	assert(world:hasComponent(holder, Pair(relation, target)) == true, `holder should hold the pair`)

	world:despawn(relation)

	assert(world:isAlive(holder) == true, `holder should survive (default onDelete = remove)`)
	assert(world:hasComponent(holder, Pair(relation, target)) == false, `the pair should be removed`)

	world:destroy()
end)

test(`cleanup cascade is recursive: a ChildOf chain despawns top-down`, function()
	Component._reset()
	Cleanup._resetTraits()

	local world = World.new()
	local grandparent = world:spawn()
	local parent = world:spawn()
	local child = world:spawn()

	world:addComponent(parent, Pair(ChildOf, grandparent))
	world:addComponent(child, Pair(ChildOf, parent))

	world:despawn(grandparent)

	assert(world:isAlive(grandparent) == false, `grandparent gone`)
	assert(world:isAlive(parent) == false, `parent cascades`)
	assert(world:isAlive(child) == false, `child cascades transitively`)

	world:destroy()
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
