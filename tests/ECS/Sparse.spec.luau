-- Sparse-set escape hatch tests: storage outside archetypes, mixed queries,
-- observers, despawn cleanup, prefabs.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Query = require("../../src/Engine/Query")
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

-- Health/Fire are ordinary archetype components; Buff is the sparse one.
local function setup(): ()
	Component._reset()
	Prefab._reset()
	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Fire`, { damage = 10 })
	Component.define(`Buff`, { stacks = 1 }, { sparse = true })
end

local function archetypeOf(world: any, id: number): any
	return world._entityStore:recordOfAny(id).archetype
end

print("")
print("Running Sparse tests...")
print("")

test(`adding a sparse component never moves the entity between archetypes`, function()
	setup()
	local world = World.new()

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 50, max = 100 })

	local before = archetypeOf(world, id)

	world:addComponent(id, `Buff`, { stacks = 3 })
	local afterAdd = archetypeOf(world, id)

	assert(afterAdd == before, `sparse add must not change the entity's archetype`)
	assert(world:hasComponent(id, `Buff`) == true, `entity should report the sparse component`)
	assert(afterAdd.columnsMap[Component.idOf(`Buff`)] == nil, `the sparse component must NOT own an archetype column`)

	world:removeComponent(id, `Buff`)
	local afterRemove = archetypeOf(world, id)

	assert(afterRemove == before, `sparse remove must not change the entity's archetype either`)
	assert(world:hasComponent(id, `Buff`) == false, `the sparse component should be gone after remove`)

	world:destroy()
end)

test(`sparse get / set / has behave like an archetype component`, function()
	setup()
	local world = World.new()

	local id = world:spawn()

	assert(world:hasComponent(id, `Buff`) == false, `no sparse component before adding`)
	assert(world:get(id, `Buff`) == nil, `get() is nil before adding`)

	world:addComponent(id, `Buff`, { stacks = 2 })
	local stored = world:get(id, `Buff`)
	assert(stored ~= nil and stored.stacks == 2, `get() returns the stored sparse data, got {stored and stored.stacks}`)

	world:set(id, `Buff`, { stacks = 9 })
	assert(world:get(id, `Buff`).stacks == 9, `set() replaces the sparse data`)
	assert(world:hasComponent(id, `Buff`) == true, `has() stays true after set`)

	world:destroy()
end)

test(`mixed all() query returns only entities holding both archetype and sparse`, function()
	setup()
	local world = World.new()

	local both = world:spawn()
	world:addComponent(both, `Health`, { current = 1, max = 1 })
	world:addComponent(both, `Buff`, { stacks = 1 })

	local onlyHealth = world:spawn()
	world:addComponent(onlyHealth, `Health`, { current = 1, max = 1 })

	local onlyBuff = world:spawn()
	world:addComponent(onlyBuff, `Buff`, { stacks = 1 })

	local matched = world._entityStore:collectEntities(Query.all(`Health`, `Buff`))
	assert(#matched == 1, `only the entity with both should match, got {#matched}`)
	assert(matched[1] == both, `the matched entity must be the one holding both`)

	-- Buff-holding entities as a whole:
	local buffed = world._entityStore:collectEntities(Query.all(`Buff`))
	assert(#buffed == 2, `both Buff holders should match a pure sparse query, got {#buffed}`)

	world:destroy()
end)

test(`mixed none() query excludes sparse holders`, function()
	setup()
	local world = World.new()

	local clean = world:spawn()
	world:addComponent(clean, `Health`, { current = 1, max = 1 })

	local buffed = world:spawn()
	world:addComponent(buffed, `Health`, { current = 1, max = 1 })
	world:addComponent(buffed, `Buff`, { stacks = 1 })

	local matched = world._entityStore:collectEntities(Query.all(`Health`):none(`Buff`))
	assert(#matched == 1, `only the un-buffed entity should match, got {#matched}`)
	assert(matched[1] == clean, `the matched entity must be the one without the sparse component`)

	-- Removing the sparse component makes the previously-excluded entity match,
	-- without any archetype change.
	world:removeComponent(buffed, `Buff`)
	local after = world._entityStore:collectEntities(Query.all(`Health`):none(`Buff`))
	assert(#after == 2, `both should match once the sparse component is removed, got {#after}`)

	world:destroy()
end)

test(`any() group mixing an archetype and a sparse term matches via either`, function()
	setup()
	local world = World.new()

	local viaSparse = world:spawn()
	world:addComponent(viaSparse, `Health`, { current = 1, max = 1 })
	world:addComponent(viaSparse, `Buff`, { stacks = 1 })

	local viaArchetype = world:spawn()
	world:addComponent(viaArchetype, `Health`, { current = 1, max = 1 })
	world:addComponent(viaArchetype, `Fire`, { damage = 5 })

	local neither = world:spawn()
	world:addComponent(neither, `Health`, { current = 1, max = 1 })

	local q = Query.all(`Health`):any(`Fire`, `Buff`)
	local matched = world._entityStore:collectEntities(q)

	assert(#matched == 2, `entities satisfying any() via sparse OR archetype should match, got {#matched}`)

	local hasSparse, hasArch, hasNeither = false, false, false
	for _, e in matched do
		if e == viaSparse then
			hasSparse = true
		end
		if e == viaArchetype then
			hasArch = true
		end
		if e == neither then
			hasNeither = true
		end
	end
	assert(hasSparse and hasArch, `both the sparse-satisfied and archetype-satisfied entities must match`)
	assert(hasNeither == false, `the entity satisfying neither any() term must NOT match`)

	world:destroy()
end)

test(`sparse observers fire on add, change, and remove`, function()
	setup()
	local world = World.new()

	local events: { string } = {}
	world:onAdd(`Buff`, function(_, data)
		table.insert(events, `add:{data.stacks}`)
	end)
	world:onChange(`Buff`, function(_, data)
		table.insert(events, `change:{data.stacks}`)
	end)
	world:onRemove(`Buff`, function(_, data)
		table.insert(events, `remove:{data.stacks}`)
	end)

	local id = world:spawn()
	world:addComponent(id, `Buff`, { stacks = 1 })
	world:set(id, `Buff`, { stacks = 4 })
	world:removeComponent(id, `Buff`)

	assert(#events == 3, `add + change + remove should each fire once, got {#events}`)
	assert(events[1] == `add:1`, `onAdd should carry the added data, got {events[1]}`)
	assert(events[2] == `change:4`, `onChange should carry the new data, got {events[2]}`)
	assert(events[3] == `remove:4`, `onRemove should carry the last data, got {events[3]}`)

	world:destroy()
end)

test(`despawn fires onRemove for a sparse component and clears its data`, function()
	setup()
	local world = World.new()

	local removed: { any } = {}
	world:onRemove(`Buff`, function(_, data)
		table.insert(removed, data)
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 1, max = 1 })
	world:addComponent(id, `Buff`, { stacks = 7 })

	world:despawn(id)

	assert(#removed == 1, `despawn should fire onRemove for the sparse component once, got {#removed}`)
	assert(removed[1].stacks == 7, `onRemove data should be the last sparse data, got {removed[1].stacks}`)
	assert(world._entityStore._sparse[Component.idOf(`Buff`)][id] == nil, `sparse data must be cleared on despawn`)

	world:destroy()
end)

test(`spawnPrefab stores a sparse component sparsely (no archetype column)`, function()
	setup()
	Prefab.define(`Buffed`, {
		{ `Health` },
		{ `Buff`, { stacks = 5 } },
	})

	local world = World.new()
	local id = world:spawnPrefab(Prefab.getDefinition(`Buffed`))

	assert(world:hasComponent(id, `Health`) == true, `prefab entity should have the archetype component`)
	assert(world:hasComponent(id, `Buff`) == true, `prefab entity should have the sparse component`)

	local stored = world:get(id, `Buff`)
	assert(stored ~= nil and stored.stacks == 5, `prefab sparse override should apply, got {stored and stored.stacks}`)
	assert(
		archetypeOf(world, id).columnsMap[Component.idOf(`Buff`)] == nil,
		`the sparse component must not be in the entity's archetype signature`
	)

	world:destroy()
end)

test(`numeric operations keep sparse data outside archetypes`, function()
	setup()
	local buff = Component.getHandle(`Buff`)
	local world = World.new()
	local id = world:spawn()
	local before = archetypeOf(world, id)

	world:add(id, buff.id, { stacks = 3 })
	assert(archetypeOf(world, id) == before, `numeric sparse add must not move the entity`)
	assert(world:has(id, buff.id) == true, `numeric sparse has should report presence`)
	assert(world:read(id, buff.id).stacks == 3, `numeric sparse read should return stored data`)

	world:write(id, buff.id, { stacks = 8 })
	assert(world:read(id, buff.id).stacks == 8, `numeric sparse write should replace data`)

	world:remove(id, buff.id)
	assert(archetypeOf(world, id) == before, `numeric sparse remove must not move the entity`)
	assert(world:has(id, buff.id) == false, `numeric sparse remove should clear presence`)

	world:destroy()
end)

test(`compiled patch mutates sparse members without archetype columns`, function()
	setup()

	local shield = Component.define(`Shield`, { strength = 0 }, { sparse = true })
	local buff = Component.getHandle(`Buff`)
	assert(buff ~= nil, `setup should define the sparse Buff component`)
	local world = World.new()
	local id = world:spawn()
	world:add(id, buff.id, { stacks = 5 })
	local before = archetypeOf(world, id)
	local patch = world:patch({ remove = { buff.id }, add = { shield.id } })

	world:mutate(id, patch, { strength = 9 })

	assert(archetypeOf(world, id) == before, `sparse-only patch should not move the entity`)
	assert(world:has(id, buff.id) == false, `sparse removal should clear old membership`)
	assert(world:read(id, shield.id).strength == 9, `sparse addition should store ordered data`)
	assert(
		before.columnsMap[buff.id] == nil and before.columnsMap[shield.id] == nil,
		`sparse patch members should never gain archetype columns`
	)

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
