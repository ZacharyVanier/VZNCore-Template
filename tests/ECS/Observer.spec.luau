-- Observer (World observer system) dedicated tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require(`@lune/process`)

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Observer = require("../../src/Engine/Observer")

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

print("")
print("Running Observer tests...")
print("")

test(`observer representation is private and its public contract is methods-only`, function()
	local observer = Observer.new()

	assert(rawget(observer, "onAdd") == nil, `onAdd callback storage must remain private`)
	assert(rawget(observer, "onChange") == nil, `onChange callback storage must remain private`)
	assert(rawget(observer, "_empty") == nil, `listener state must remain private`)
	assert(type(observer.register) == "function", `observer should expose behavior through methods`)
end)

test(`onAdd fires when addComponent is called`, function()
	setup()

	local world = World.new()
	local firedEntity: number? = nil
	local firedData: any = nil

	world:onAdd(`Health`, function(entity: number, data: any)
		firedEntity = entity
		firedData = data
	end)

	local id = world:spawn()
	local healthData = { current = 100, max = 100 }

	world:addComponent(id, `Health`, healthData)

	assert(firedEntity == id, `onAdd entity should be {id}, got {tostring(firedEntity)}`)
	assert(firedData ~= nil, `onAdd should receive component data`)
	assert(firedData.current == 100, `onAdd data.current should be 100`)
	assert(firedData.max == 100, `onAdd data.max should be 100`)

	world:destroy()
end)

test(`onChange fires on set() and markDirty()`, function()
	setup()

	local world = World.new()
	local changeCount = 0
	local lastEntity: number? = nil
	local lastData: any = nil

	world:onChange(`Health`, function(entity: number, data: any)
		changeCount += 1
		lastEntity = entity
		lastData = data
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	world:set(id, `Health`, { current = 50, max = 100 })
	assert(changeCount == 1, `onChange should fire on set(), count = {changeCount}`)
	assert(lastEntity == id, `onChange entity should match`)
	assert(lastData.current == 50, `onChange data should reflect new value`)

	world:markDirty(id, `Health`)
	assert(changeCount == 2, `onChange should fire on markDirty(), count = {changeCount}`)

	world:destroy()
end)

test(`onRemove fires on removeComponent() and despawn()`, function()
	setup()

	local world = World.new()
	local removeLog: { { entity: number, name: string } } = {}

	world:onRemove(`Health`, function(entity: number, _data: any)
		table.insert(removeLog, { entity = entity, name = `Health` })
	end)

	world:onRemove(`Armor`, function(entity: number, _data: any)
		table.insert(removeLog, { entity = entity, name = `Armor` })
	end)

	local id1 = world:spawn()
	world:addComponent(id1, `Health`, { current = 100, max = 100 })

	world:removeComponent(id1, `Health`)
	assert(#removeLog == 1, `removeComponent should fire onRemove once, got {#removeLog}`)
	assert(removeLog[1].entity == id1, `removeComponent entity should match`)
	assert(removeLog[1].name == `Health`, `removeComponent name should be Health`)

	local id2 = world:spawn()
	world:addComponent(id2, `Health`, { current = 50, max = 50 })
	world:addComponent(id2, `Armor`, { value = 10 })

	world:despawn(id2)
	assert(#removeLog == 3, `despawn should fire onRemove for each component, got {#removeLog}`)

	world:destroy()
end)

test(`multiple observers on same component all fire`, function()
	setup()

	local world = World.new()
	local log: { string } = {}

	world:onAdd(`Health`, function(_entity: number, _data: any)
		table.insert(log, `observer1`)
	end)

	world:onAdd(`Health`, function(_entity: number, _data: any)
		table.insert(log, `observer2`)
	end)

	world:onAdd(`Health`, function(_entity: number, _data: any)
		table.insert(log, `observer3`)
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	assert(#log == 3, `all 3 observers should fire, got {#log}`)
	assert(log[1] == `observer1`, `first observer should fire first`)
	assert(log[2] == `observer2`, `second observer should fire second`)
	assert(log[3] == `observer3`, `third observer should fire third`)

	world:destroy()
end)

test(`observer callbacks receive (entity, componentData) arguments`, function()
	setup()

	local world = World.new()

	local addEntity: number? = nil
	local addData: any = nil
	local changeEntity: number? = nil
	local changeData: any = nil
	local removeEntity: number? = nil
	local removeData: any = nil

	world:onAdd(`Stats`, function(entity: number, data: any)
		addEntity = entity
		addData = data
	end)

	world:onChange(`Stats`, function(entity: number, data: any)
		changeEntity = entity
		changeData = data
	end)

	world:onRemove(`Stats`, function(entity: number, data: any)
		removeEntity = entity
		removeData = data
	end)

	local id = world:spawn()

	world:addComponent(id, `Stats`, { level = 1, xp = 0 })
	assert(addEntity == id, `onAdd entity should be {id}`)
	assert(addData.level == 1, `onAdd data.level should be 1`)
	assert(addData.xp == 0, `onAdd data.xp should be 0`)

	world:set(id, `Stats`, { level = 2, xp = 500 })
	assert(changeEntity == id, `onChange entity should be {id}`)
	assert(changeData.level == 2, `onChange data.level should be 2`)
	assert(changeData.xp == 500, `onChange data.xp should be 500`)

	world:removeComponent(id, `Stats`)
	assert(removeEntity == id, `onRemove entity should be {id}`)
	assert(removeData.level == 2, `onRemove data.level should be 2`)

	world:destroy()
end)

test(`spawnPrefab fires onAdd for each component`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Position`, { x = 0, y = 0, z = 0 })

	local world = World.new()
	local addedComponents: { string } = {}

	world:onAdd(`Health`, function(_entity: number, _data: any)
		table.insert(addedComponents, `Health`)
	end)

	world:onAdd(`Position`, function(_entity: number, _data: any)
		table.insert(addedComponents, `Position`)
	end)

	local prefab = {
		name = `Player`,
		components = {
			{ `Health`, { current = 200, max = 200 } },
			{ `Position`, { x = 10, y = 0, z = 5 } },
		},
	}

	local id = world:spawnPrefab(prefab)

	assert(id ~= nil, `spawnPrefab should return an entity id`)
	assert(#addedComponents == 2, `onAdd should fire for both components, got {#addedComponents}`)

	local hasHealth = false
	local hasPosition = false

	for _, name in addedComponents do
		if name == `Health` then
			hasHealth = true
		end
		if name == `Position` then
			hasPosition = true
		end
	end

	assert(hasHealth, `onAdd for Health should have fired`)
	assert(hasPosition, `onAdd for Position should have fired`)

	world:destroy()
end)

test(`onChange does not fire on addComponent`, function()
	setup()

	local world = World.new()
	local changeCount = 0

	world:onChange(`Health`, function(_entity: number, _data: any)
		changeCount += 1
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	assert(changeCount == 0, `onChange should not fire on addComponent, count = {changeCount}`)

	world:destroy()
end)

test(`onAdd does not fire on set() or markDirty()`, function()
	setup()

	local world = World.new()
	local addCount = 0

	world:onAdd(`Health`, function(_entity: number, _data: any)
		addCount += 1
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	assert(addCount == 1, `onAdd should fire once on addComponent`)

	world:set(id, `Health`, { current = 50, max = 100 })
	assert(addCount == 1, `onAdd should not fire on set()`)

	world:markDirty(id, `Health`)
	assert(addCount == 1, `onAdd should not fire on markDirty()`)

	world:destroy()
end)

test(`observers for unrelated components do not fire`, function()
	setup()

	local world = World.new()
	local healthAddCount = 0

	world:onAdd(`Health`, function(_entity: number, _data: any)
		healthAddCount += 1
	end)

	local id = world:spawn()
	world:addComponent(id, `Velocity`, { x = 1, y = 0, z = 0 })

	assert(healthAddCount == 0, `Health onAdd should not fire when adding Velocity, count = {healthAddCount}`)

	world:destroy()
end)

test(`multiple onChange observers all receive updated data`, function()
	setup()

	local world = World.new()
	local log: { number } = {}

	world:onChange(`Health`, function(_entity: number, data: any)
		table.insert(log, data.current)
	end)

	world:onChange(`Health`, function(_entity: number, data: any)
		table.insert(log, data.current * 2)
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	world:set(id, `Health`, { current = 75, max = 100 })

	assert(#log == 2, `both onChange observers should fire, got {#log}`)
	assert(log[1] == 75, `first observer should receive current = 75`)
	assert(log[2] == 150, `second observer should receive current * 2 = 150`)

	world:destroy()
end)

test(`onRemove still fires pre-remove data; zero-listener add/remove stays correct`, function()
	setup()

	local world = World.new()
	local removedData: any = nil

	world:onRemove(`Health`, function(_entity: number, data: any)
		removedData = data
	end)

	local watched = world:spawn()
	world:addComponent(watched, `Health`, { current = 42 })
	world:removeComponent(watched, `Health`)

	assert(removedData ~= nil, `onRemove should still fire when a listener is registered`)
	assert(removedData.current == 42, `onRemove should receive the pre-remove data`)

	local quiet = world:spawn()
	world:addComponent(quiet, `Mana`, { current = 7 })
	assert(world:hasComponent(quiet, `Mana`) == true, `zero-listener add should still attach`)

	world:removeComponent(quiet, `Mana`)
	assert(world:hasComponent(quiet, `Mana`) == false, `zero-listener remove should still detach`)

	world:destroy()
end)

test(`numeric operations preserve observer counts and payloads`, function()
	setup()
	local health = Component.define(`Health`, { current = 100 })
	local world = World.new()
	local id = world:spawn()
	local addCount = 0
	local changeCount = 0
	local removeCount = 0
	local addedCurrent = 0
	local changedCurrent = 0
	local removedCurrent = 0

	world:onAdd(`Health`, function(firedEntity: number, data: any)
		assert(firedEntity == id, `numeric onAdd entity should match`)
		addCount += 1
		addedCurrent = data.current
	end)
	world:onChange(`Health`, function(firedEntity: number, data: any)
		assert(firedEntity == id, `numeric onChange entity should match`)
		changeCount += 1
		changedCurrent = data.current
	end)
	world:onRemove(`Health`, function(firedEntity: number, data: any)
		assert(firedEntity == id, `numeric onRemove entity should match`)
		removeCount += 1
		removedCurrent = data.current
	end)

	world:add(id, health.id, { current = 80 })
	world:write(id, health.id, { current = 35 })
	world:remove(id, health.id)

	assert(addCount == 1 and addedCurrent == 80, `numeric add should fire once with added data`)
	assert(changeCount == 1 and changedCurrent == 35, `numeric write should fire once with updated data`)
	assert(removeCount == 1 and removedCurrent == 35, `numeric remove should fire once with pre-remove data`)

	world:destroy()
end)

test(`compiled patch observers fire in declaration order against final state`, function()
	setup()

	local firstRemoved = Component.define(`PatchObserverFirstRemoved`, { value = 0 })
	local secondRemoved = Component.define(`PatchObserverSecondRemoved`, { value = 0 })
	local firstAdded = Component.define(`PatchObserverFirstAdded`, { value = 0 })
	local secondAdded = Component.define(`PatchObserverSecondAdded`, { value = 0 })
	local world = World.new()
	local id = world:spawn()
	world:add(id, firstRemoved.id, { value = 1 })
	world:add(id, secondRemoved.id, { value = 2 })

	local events: { string } = {}
	local function observe(kind: string, componentId: number, expectedValue: number): (number, any) -> ()
		return function(entity: number, data: any): ()
			assert(entity == id, `patch observer should receive the mutated entity`)
			assert(data.value == expectedValue, `patch observer should receive declared component data`)
			assert(
				world:has(id, firstRemoved.id) == false and world:has(id, secondRemoved.id) == false,
				`observer should see all removals applied`
			)
			assert(
				world:has(id, firstAdded.id) == true and world:has(id, secondAdded.id) == true,
				`observer should see all additions applied`
			)
			table.insert(events, `{kind}:{componentId}`)
		end
	end

	world:onRemove(firstRemoved.name, observe(`remove`, firstRemoved.id, 1))
	world:onRemove(secondRemoved.name, observe(`remove`, secondRemoved.id, 2))
	world:onAdd(firstAdded.name, observe(`add`, firstAdded.id, 3))
	world:onAdd(secondAdded.name, observe(`add`, secondAdded.id, 4))
	local patch = world:patch({
		remove = { firstRemoved.id, secondRemoved.id },
		add = { firstAdded.id, secondAdded.id },
	})

	local invalidOk = pcall(function()
		world:mutate(id, patch, { value = 3 })
	end)
	assert(invalidOk == false and #events == 0, `invalid patch data should reject before observers`)

	world:mutate(id, patch, { value = 3 }, { value = 4 })

	assert(#events == 4, `patch should fire exactly one observer per declared operation`)
	assert(
		events[1] == `remove:{firstRemoved.id}` and events[2] == `remove:{secondRemoved.id}`,
		`remove observers should preserve declaration order`
	)
	assert(
		events[3] == `add:{firstAdded.id}` and events[4] == `add:{secondAdded.id}`,
		`add observers should preserve declaration order`
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
