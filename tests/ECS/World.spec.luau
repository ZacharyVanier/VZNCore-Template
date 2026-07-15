-- World module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require(`@lune/process`)

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Query = require("../../src/Engine/Query")
local System = require("../../src/Engine/System")
local ECSTypes = require("../../src/Engine/Types")

type CompiledQuery = ECSTypes.CompiledQuery
type CompiledQueryCursor = ECSTypes.CompiledQueryCursor

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
print("Running World tests...")
print("")

test(`World.new() creates a world`, function()
	setup()

	local world = World.new()

	assert(world ~= nil, `World.new() should return a table`)
	assert(type(world) == "table", `World should be a table`)
	assert(type(world.spawn) == "function", `world should have spawn method`)
	assert(type(world.despawn) == "function", `world should have despawn method`)
	assert(type(world.step) == "function", `world should have step method`)

	world:destroy()
end)

test(`world:spawn() returns incrementing entity IDs`, function()
	setup()

	local world = World.new()

	local id1 = world:spawn()
	local id2 = world:spawn()
	local id3 = world:spawn()

	assert(id1 == 1, `first entity should be 1, got {id1}`)
	assert(id2 == 2, `second entity should be 2, got {id2}`)
	assert(id3 == 3, `third entity should be 3, got {id3}`)

	world:destroy()
end)

test(`world:despawn() removes entity`, function()
	setup()

	local world = World.new()

	local id = world:spawn()
	assert(world:isAlive(id) == true, `entity should be alive after spawn`)

	world:despawn(id)
	assert(world:isAlive(id) == false, `entity should not be alive after despawn`)

	world:destroy()
end)

test(`world:addComponent() + world:get() stores and retrieves data`, function()
	setup()

	local world = World.new()

	local id = world:spawn()
	local healthData = { current = 100, max = 100 }

	world:addComponent(id, `Health`, healthData)

	local stored = world:get(id, `Health`)
	assert(stored ~= nil, `get() should return stored data`)
	assert(stored.current == 100, `current should be 100, got {stored.current}`)
	assert(stored.max == 100, `max should be 100, got {stored.max}`)

	world:destroy()
end)

test(`world:set() replaces component data`, function()
	setup()

	local world = World.new()

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	world:set(id, `Health`, { current = 50, max = 200 })

	local stored = world:get(id, `Health`)
	assert(stored.current == 50, `current should be 50 after set, got {stored.current}`)
	assert(stored.max == 200, `max should be 200 after set, got {stored.max}`)

	world:destroy()
end)

test(`world:markDirty() flags component for replication`, function()
	setup()

	local world = World.new()

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	world:markDirty(id, `Health`)

	local dirty = world:flushDirty()
	assert(#dirty == 1, `should have 1 dirty entry, got {#dirty}`)
	assert(dirty[1].entity == id, `dirty entry entity should match`)
	assert(dirty[1].name == `Health`, `dirty entry name should be Health`)

	world:destroy()
end)

test(`world:hasComponent() returns correct boolean`, function()
	setup()

	local world = World.new()

	local id = world:spawn()
	assert(world:hasComponent(id, `Health`) == false, `should not have Health before adding`)

	world:addComponent(id, `Health`, { current = 100, max = 100 })
	assert(world:hasComponent(id, `Health`) == true, `should have Health after adding`)

	world:destroy()
end)

test(`world:removeComponent() removes component from entity`, function()
	setup()

	local world = World.new()

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	assert(world:hasComponent(id, `Health`) == true, `should have Health before removal`)

	world:removeComponent(id, `Health`)

	assert(world:hasComponent(id, `Health`) == false, `should not have Health after removal`)

	world:destroy()
end)

test(`world:setSingleton() + world:getSingleton() stores and retrieves`, function()
	setup()

	local world = World.new()

	local gameState = { phase = `Lobby`, timer = 30 }
	world:setSingleton(`GameState`, gameState)

	local stored = world:getSingleton(`GameState`)
	assert(stored ~= nil, `getSingleton should return stored data`)
	assert(stored.phase == `Lobby`, `phase should be Lobby`)
	assert(stored.timer == 30, `timer should be 30`)

	world:destroy()
end)

test(`world:addSystem() registers a system definition`, function()
	setup()

	local world = World.new()

	local sys = System.new(`TestSys`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): () end,
	})

	world:addSystem(sys)

	assert(world:isSystemEnabled(`TestSys`) == true, `system should be enabled after registration`)

	world:destroy()
end)

test(`world:addSystems() batch registers multiple systems`, function()
	setup()

	local world = World.new()

	local noop = function(_entities: { number }, _dt: number): () end

	local sys1 = System.new(`Sys1`, { phase = `Update`, run = noop })
	local sys2 = System.new(`Sys2`, { phase = `Update`, run = noop })
	local sys3 = System.new(`Sys3`, { phase = `Update`, run = noop })

	world:addSystems({ sys1, sys2, sys3 })

	assert(world:isSystemEnabled(`Sys1`) == true, `Sys1 should be registered`)
	assert(world:isSystemEnabled(`Sys2`) == true, `Sys2 should be registered`)
	assert(world:isSystemEnabled(`Sys3`) == true, `Sys3 should be registered`)

	world:destroy()
end)

test(`world:step() runs systems in phase + priority order`, function()
	setup()

	local world = World.new()
	local log: { string } = {}

	local sysA = System.new(`RenderSys`, {
		phase = `Render`,
		priority = 0,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `RenderSys`)
		end,
	})

	local sysB = System.new(`UpdateHigh`, {
		phase = `Update`,
		priority = 10,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `UpdateHigh`)
		end,
	})

	local sysC = System.new(`PreUpdateSys`, {
		phase = `PreUpdate`,
		priority = 5,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `PreUpdateSys`)
		end,
	})

	local sysD = System.new(`UpdateLow`, {
		phase = `Update`,
		priority = 1,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `UpdateLow`)
		end,
	})

	world:addSystems({ sysA, sysB, sysC, sysD })

	world:step(0.016)

	assert(#log == 4, `should have 4 entries in log, got {#log}`)
	assert(log[1] == `PreUpdateSys`, `first should be PreUpdateSys, got {log[1]}`)
	assert(log[2] == `UpdateLow`, `second should be UpdateLow, got {log[2]}`)
	assert(log[3] == `UpdateHigh`, `third should be UpdateHigh, got {log[3]}`)
	assert(log[4] == `RenderSys`, `fourth should be RenderSys, got {log[4]}`)

	world:destroy()
end)

test(`world:pause() / resume() / isPaused() lifecycle`, function()
	setup()

	local world = World.new()
	local log: { string } = {}

	local sys = System.new(`Counter`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `ran`)
		end,
	})

	world:addSystem(sys)

	assert(world:isPaused() == false, `world should not be paused initially`)

	world:step(0.016)
	assert(#log == 1, `system should run once before pause`)

	world:pause()
	assert(world:isPaused() == true, `world should be paused after pause()`)

	world:step(0.016)
	assert(#log == 1, `system should NOT run while paused`)

	world:resume()
	assert(world:isPaused() == false, `world should not be paused after resume()`)

	world:step(0.016)
	assert(#log == 2, `system should run again after resume`)

	world:destroy()
end)

test(`world:enableSystem() / disableSystem() / isSystemEnabled()`, function()
	setup()

	local world = World.new()

	local sys = System.new(`Toggle`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): () end,
	})

	world:addSystem(sys)

	assert(world:isSystemEnabled(`Toggle`) == true, `system should be enabled by default`)

	world:disableSystem(`Toggle`)
	assert(world:isSystemEnabled(`Toggle`) == false, `system should be disabled after disableSystem()`)

	world:enableSystem(`Toggle`)
	assert(world:isSystemEnabled(`Toggle`) == true, `system should be enabled after enableSystem()`)

	world:destroy()
end)

test(`disabled systems are skipped during step()`, function()
	setup()

	local world = World.new()
	local log: { string } = {}

	local sysA = System.new(`EnabledSys`, {
		phase = `Update`,
		priority = 1,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `EnabledSys`)
		end,
	})

	local sysB = System.new(`DisabledSys`, {
		phase = `Update`,
		priority = 2,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `DisabledSys`)
		end,
	})

	world:addSystems({ sysA, sysB })

	world:disableSystem(`DisabledSys`)

	world:step(0.016)

	assert(#log == 1, `should have 1 log entry, got {#log}`)
	assert(log[1] == `EnabledSys`, `only EnabledSys should have run, got {log[1]}`)

	world:destroy()
end)

test(`system error isolation -- erroring system does not stop others`, function()
	setup()

	local world = World.new()
	local log: { string } = {}

	local brokenSys = System.new(`Broken`, {
		phase = `Update`,
		priority = 1,
		run = function(_entities: { number }, _dt: number): ()
			error(`boom`)
		end,
	})

	local goodSys = System.new(`Good`, {
		phase = `Update`,
		priority = 2,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `Good`)
		end,
	})

	world:addSystems({ brokenSys, goodSys })

	world:step(0.016)

	assert(#log == 1, `Good system should still run despite Broken erroring, got {#log}`)
	assert(log[1] == `Good`, `Good system should have run`)

	world:destroy()
end)

test(`circuit breaker auto-disables system after 10 consecutive errors`, function()
	setup()

	local world = World.new()

	local brokenSys = System.new(`Fragile`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): ()
			error(`repeated failure`)
		end,
	})

	world:addSystem(brokenSys)

	assert(world:isSystemEnabled(`Fragile`) == true, `system should start enabled`)

	for _ = 1, 10 do
		world:step(0.016)
	end

	assert(world:isSystemEnabled(`Fragile`) == false, `system should be auto-disabled after 10 errors`)

	world:destroy()
end)

test(`world:destroy() cleans up and disables further stepping`, function()
	setup()

	local world = World.new()
	local log: { string } = {}

	local sys = System.new(`Counter`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): ()
			table.insert(log, `ran`)
		end,
	})

	world:addSystem(sys)

	world:step(0.016)
	assert(#log == 1, `system should run before destroy`)

	world:destroy()

	assert(world:isPaused() == true, `world should be paused after destroy`)

	world:step(0.016)
	assert(#log == 1, `step should be a no-op after destroy`)
end)

test(`world:bindInstance() tracks bound instance`, function()
	setup()

	local world = World.new()
	local id = world:spawn()
	local destroyed = false

	local mockInstance = {
		Parent = true,
		Destroy = function(_self: any): ()
			destroyed = true
		end,
	}

	world:bindInstance(id, mockInstance :: any)

	assert(destroyed == false, `instance should not be destroyed yet`)

	world:destroy()
end)

test(`world:despawn() with bound instances calls Destroy on them`, function()
	setup()

	local world = World.new()
	local id = world:spawn()
	local destroyedA = false
	local destroyedB = false

	local mockA = {
		Parent = true,
		Destroy = function(_self: any): ()
			destroyedA = true
		end,
	}

	local mockB = {
		Parent = true,
		Destroy = function(_self: any): ()
			destroyedB = true
		end,
	}

	world:bindInstance(id, mockA :: any)
	world:bindInstance(id, mockB :: any)

	world:despawn(id)

	assert(destroyedA == true, `mockA:Destroy() should have been called`)
	assert(destroyedB == true, `mockB:Destroy() should have been called`)

	world:destroy()
end)

test(`world:onAdd() observer fires on addComponent`, function()
	setup()

	local world = World.new()

	local firedEntity: number? = nil
	local firedData: any = nil

	world:onAdd(`Health`, function(entity: number, data: any): ()
		firedEntity = entity
		firedData = data
	end)

	local id = world:spawn()
	local healthData = { current = 100, max = 100 }

	world:addComponent(id, `Health`, healthData)

	assert(firedEntity == id, `onAdd should receive entity id, got {tostring(firedEntity)}`)
	assert(firedData ~= nil, `onAdd should receive component data`)
	assert(firedData.current == 100, `onAdd data should contain current = 100`)

	world:destroy()
end)

test(`world:onChange() observer fires on set() and markDirty()`, function()
	setup()

	local world = World.new()
	local changeCount = 0

	world:onChange(`Health`, function(_entity: number, _data: any): ()
		changeCount += 1
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	world:set(id, `Health`, { current = 50, max = 100 })
	assert(changeCount == 1, `onChange should fire on set(), count = {changeCount}`)

	world:markDirty(id, `Health`)
	assert(changeCount == 2, `onChange should fire on markDirty(), count = {changeCount}`)

	world:destroy()
end)

test(`world:onRemove() observer fires on removeComponent()`, function()
	setup()

	local world = World.new()

	local removedEntity: number? = nil
	local removedData: any = nil

	world:onRemove(`Health`, function(entity: number, data: any): ()
		removedEntity = entity
		removedData = data
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })

	world:removeComponent(id, `Health`)

	assert(removedEntity == id, `onRemove should receive entity id`)
	assert(removedData ~= nil, `onRemove should receive component data`)
	assert(removedData.current == 100, `onRemove data should be the old data`)

	world:destroy()
end)

test(`world:onRemove() fires on despawn() for each component`, function()
	setup()

	local world = World.new()
	local removedComponents: { string } = {}

	world:onRemove(`Health`, function(_entity: number, _data: any): ()
		table.insert(removedComponents, `Health`)
	end)

	world:onRemove(`Velocity`, function(_entity: number, _data: any): ()
		table.insert(removedComponents, `Velocity`)
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 100, max = 100 })
	world:addComponent(id, `Velocity`, { x = 0, y = 0, z = 0 })

	world:despawn(id)

	assert(#removedComponents == 2, `should fire 2 onRemove callbacks, got {#removedComponents}`)

	local hasHealth = false
	local hasVelocity = false

	for _, name in removedComponents do
		if name == `Health` then
			hasHealth = true
		end
		if name == `Velocity` then
			hasVelocity = true
		end
	end

	assert(hasHealth, `onRemove for Health should have fired`)
	assert(hasVelocity, `onRemove for Velocity should have fired`)

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

	world:onAdd(`Health`, function(entity: number, data: any): ()
		addEntity = entity
		addData = data
	end)

	world:onChange(`Health`, function(entity: number, data: any): ()
		changeEntity = entity
		changeData = data
	end)

	world:onRemove(`Health`, function(entity: number, data: any): ()
		removeEntity = entity
		removeData = data
	end)

	local id = world:spawn()

	world:addComponent(id, `Health`, { current = 100, max = 100 })
	assert(addEntity == id, `onAdd entity should be {id}`)
	assert(addData.current == 100, `onAdd data.current should be 100`)

	world:set(id, `Health`, { current = 50, max = 100 })
	assert(changeEntity == id, `onChange entity should be {id}`)
	assert(changeData.current == 50, `onChange data.current should be 50`)

	world:removeComponent(id, `Health`)
	assert(removeEntity == id, `onRemove entity should be {id}`)
	assert(removeData.current == 50, `onRemove data.current should be 50`)

	world:destroy()
end)

test(`world:spawnPrefab() creates entity from prefab definition (minimal)`, function()
	setup()

	Component.define(`Health`, { current = 100, max = 100 })
	Component.define(`Position`, { x = 0, y = 0, z = 0 })

	local world = World.new()

	local prefab = {
		name = `Player`,
		components = {
			{ `Health`, { current = 200, max = 200 } },
			{ `Position`, { x = 10, y = 0, z = 5 } },
		},
	}

	local id = world:spawnPrefab(prefab)

	assert(id ~= nil, `spawnPrefab should return an entity id`)
	assert(world:isAlive(id) == true, `prefab entity should be alive`)
	assert(world:hasComponent(id, `Health`) == true, `entity should have Health`)
	assert(world:hasComponent(id, `Position`) == true, `entity should have Position`)

	local health = world:get(id, `Health`)
	assert(health.current == 200, `Health.current should be 200, got {health.current}`)
	assert(health.max == 200, `Health.max should be 200`)

	local pos = world:get(id, `Position`)
	assert(pos.x == 10, `Position.x should be 10`)
	assert(pos.z == 5, `Position.z should be 5`)

	world:destroy()
end)

test(`world:addComponent and world:get work with a typed handle`, function()
	setup()
	local Health = Component.define(`Health`, { current = 100, max = 100 })

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, Health, { current = 200, max = 200 })

	local stored = world:get(id, Health)
	assert(stored ~= nil, `get() with a handle should return data`)
	assert(stored.current == 200, `handle-stored current should be 200, got {stored.current}`)
	assert(world:hasComponent(id, Health) == true, `hasComponent with a handle should be true`)

	world:destroy()
end)

test(`a handle and its string name address the same component`, function()
	setup()
	local Health = Component.define(`Health`, { current = 100, max = 100 })

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, Health, { current = 77, max = 100 })

	local viaHandle = world:get(id, Health)
	local viaString = world:get(id, `Health`)

	assert(viaHandle == viaString, `handle and string should resolve to the same stored table`)
	assert(world:hasComponent(id, `Health`) == world:hasComponent(id, Health), `presence should agree across ref kinds`)

	world:destroy()
end)

test(`world tag: added, present, and get returns nil`, function()
	setup()
	local Frozen = Component.tag(`Frozen`)

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, Frozen)

	assert(world:hasComponent(id, Frozen) == true, `entity should have the tag via handle`)
	assert(world:hasComponent(id, `Frozen`) == true, `entity should have the tag via string`)
	assert(world:get(id, Frozen) == nil, `get() on a tag should return nil`)

	world:destroy()
end)

test(`world: setting data on a tag errors`, function()
	setup()
	local Frozen = Component.tag(`Frozen`)

	local world = World.new()
	local id = world:spawn()

	local addOk = pcall(function()
		world:addComponent(id, Frozen, { value = 1 })
	end)
	assert(addOk == false, `addComponent with data on a tag should error`)

	local setOk = pcall(function()
		world:set(id, Frozen, { value = 1 })
	end)
	assert(setOk == false, `set() on a tag should error`)

	world:destroy()
end)

test(`world:removeComponent removes a tag`, function()
	setup()
	local Frozen = Component.tag(`Frozen`)

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, Frozen)
	assert(world:hasComponent(id, Frozen) == true, `tag should be present before removal`)

	world:removeComponent(id, Frozen)
	assert(world:hasComponent(id, Frozen) == false, `tag should be gone after removal`)

	world:destroy()
end)

test(`world:onAdd fires for a tag with nil data`, function()
	setup()
	Component.tag(`Frozen`)

	local world = World.new()

	local firedEntity: number? = nil
	local firedData: any = false

	world:onAdd(`Frozen`, function(entity: number, data: any): ()
		firedEntity = entity
		firedData = data
	end)

	local id = world:spawn()
	world:addComponent(id, `Frozen`)

	assert(firedEntity == id, `onAdd should fire for the tagged entity`)
	assert(firedData == nil, `tag onAdd should carry nil data`)

	world:destroy()
end)

test(`world:spawnPrefab handles tag entries`, function()
	setup()
	Component.define(`Health`, { current = 100, max = 100 })
	Component.tag(`Boss`)

	local world = World.new()

	local prefab = {
		name = `Enemy`,
		components = {
			{ `Health`, { current = 500, max = 500 } },
			{ `Boss` },
		},
	}

	local id = world:spawnPrefab(prefab)

	assert(world:hasComponent(id, `Health`) == true, `prefab entity should have Health`)
	assert(world:hasComponent(id, `Boss`) == true, `prefab entity should have the Boss tag`)
	assert(world:get(id, `Boss`) == nil, `tag from prefab should store no data`)

	local health = world:get(id, `Health`)
	assert(health.current == 500, `Health override should apply, got {health.current}`)

	world:destroy()
end)

test(`world:query() streams matching component data by row`, function()
	setup()
	Component.define(`Health`, { current = 0 })
	Component.define(`Mana`, { current = 0 })

	local world = World.new()
	local expected = 0
	for i = 1, 40 do
		local id = world:spawn()
		world:addComponent(id, `Health`, { current = i })
		world:addComponent(id, `Mana`, { current = i })
		expected += i
	end

	local q = Query.all(`Health`, `Mana`):cached()

	local sum, count = 0, 0
	for id, health, mana in world:query(q) do
		assert(world:isAlive(id), `streamed id should be alive`)
		assert(mana.current == health.current, `parallel columns should align by row`)
		sum += health.current
		count += 1
	end

	assert(count == 40, `world:query should visit every match, got {count}`)
	assert(sum == expected, `streamed values should sum to {expected}, got {sum}`)
end)

test(`world:query() reflects despawns on the next pass`, function()
	setup()
	Component.define(`Health`, { current = 0 })

	local world = World.new()
	local ids = {}
	for i = 1, 10 do
		local id = world:spawn()
		world:addComponent(id, `Health`, { current = i })
		ids[i] = id
	end

	local q = Query.all(`Health`):cached()

	world:despawn(ids[3])
	world:despawn(ids[7])

	local count = 0
	for _id in world:query(q) do
		count += 1
	end

	assert(count == 8, `two despawns should leave 8 matches, got {count}`)
end)

test(`world:compile() keeps projections separate and registers later archetypes`, function()
	setup()
	local filtered = Component.define(`Filtered`, { value = 0 })
	local projected = Component.define(`Projected`, { value = 0 })
	local world = World.new()

	local first = world:spawn()
	world:add(first, filtered.id, { value = 1 })

	local compiled: CompiledQuery = world:compile(Query.all(filtered):select(projected))

	local second = world:spawn()
	world:add(second, filtered.id, { value = 2 })
	world:add(second, projected.id, { value = 20 })

	local seen: { [number]: any } = {}
	local seenEntities: { [number]: boolean } = {}
	for entity, data in compiled do
		seen[entity] = data
		seenEntities[entity] = true
	end

	assert(
		seenEntities[first] == true and seen[first] == nil,
		`missing projected data should yield nil without filtering the entity`
	)
	assert(seen[second] ~= nil and seen[second].value == 20, `later matching archetype should join the compiled plan`)
	assert(world:isAlive(first) and world:isAlive(second), `compiled iteration should not mutate matching entities`)

	world:destroy()
end)

test(`compiled cursor supports nested iteration and closes automatically on exhaustion`, function()
	setup()
	local value = Component.define(`Value`, { value = 0 })
	local world = World.new()

	for index = 1, 3 do
		local entity = world:spawn()
		world:add(entity, value.id, { value = index })
	end

	local compiled: CompiledQuery = world:compile(Query.all(value):select(value))
	local outer: CompiledQueryCursor = compiled:cursor()
	local outerEntity = outer()
	assert(outerEntity ~= nil, `outer cursor should yield its first row`)

	local innerCount = 0
	for _entity, data in compiled:cursor() do
		innerCount += 1
		assert(data.value >= 1 and data.value <= 3, `inner cursor should read aligned projected data`)
	end
	assert(innerCount == 3, `nested cursor should independently visit all rows`)

	local outerCount = 1
	for _entity in outer do
		outerCount += 1
	end
	assert(outerCount == 3, `outer cursor should resume after nested iteration`)

	local spawned = world:spawn()
	assert(world:isAlive(spawned), `automatic cursor close should release the structural mutation guard`)

	world:destroy()
end)

test(`closed compiled states release flattened columns before archetype sweep`, function()
	setup()
	local first = Component.define(`CloseFlatFirst`, { value = 0 })
	local second = Component.define(`CloseFlatSecond`, { value = 0 })
	local third = Component.define(`CloseFlatThird`, { value = 0 })
	local fourth = Component.define(`CloseFlatFourth`, { value = 0 })
	local world = World.new()
	local entity = world:spawn()
	world:add(entity, first.id, { value = 1 })
	world:add(entity, second.id, { value = 2 })
	world:add(entity, third.id, { value = 3 })
	world:add(entity, fourth.id, { value = 4 })

	local compiled: any = world:compile(Query.all(first, second, third, fourth):select(first, second, third, fourth))
	local archetype = world._entityStore:recordOfAny(entity).archetype
	local columns = archetype.columnsMap

	local exhaustedCount = 0
	for _entity in compiled do
		exhaustedCount += 1
	end
	local exhaustedState = compiled._defaultState

	assert(exhaustedCount == 1, `default iterator should exhaust its matching row`)
	assert(
		exhaustedState._column0 ~= columns[first.id] and exhaustedState._column1 ~= columns[second.id],
		`exhausted default state should release its first two flattened columns`
	)
	assert(
		exhaustedState._column2 ~= columns[third.id] and exhaustedState._column3 ~= columns[fourth.id],
		`exhausted default state should release its remaining flattened columns`
	)

	local cursor: any = compiled:cursor()
	assert(cursor() == entity, `cursor should populate flattened columns before explicit close`)
	local cursorState = cursor._state
	assert(cursorState._column0 == columns[first.id], `active cursor should hold its resolved first column`)
	cursor:close()
	assert(
		cursorState._column0 ~= columns[first.id] and cursorState._column1 ~= columns[second.id],
		`explicit close should release its first two flattened columns`
	)
	assert(
		cursorState._column2 ~= columns[third.id] and cursorState._column3 ~= columns[fourth.id],
		`explicit close should release its remaining flattened columns`
	)

	world:despawn(entity)
	assert(world._entityStore:sweep() > 0, `closed states should permit the empty matching archetype to sweep`)
	assert(world._entityStore._archetypes[archetype.id] == nil, `swept archetype should leave the live registry`)
	assert(#compiled._plans == 0, `sweep should unregister the destroyed archetype from the compiled query`)

	world:destroy()
end)

test(`closed compiled cursor cannot resume into later plans`, function()
	setup()
	local value = Component.define(`Value`, { value = 0 })
	local extra = Component.define(`Extra`, { value = 0 })
	local world = World.new()

	local first = world:spawn()
	world:add(first, value.id, { value = 1 })
	local second = world:spawn()
	world:add(second, value.id, { value = 2 })
	world:add(second, extra.id, { value = 3 })

	local compiled: CompiledQuery = world:compile(Query.all(value):select(value))
	local cursor: CompiledQueryCursor = compiled:cursor()
	assert(cursor() == first, `cursor should begin in the first matching plan`)
	cursor:close()

	local traversed = 0
	local unguardedMutation = false
	for _entity in cursor do
		traversed += 1
		unguardedMutation = pcall(function()
			world:spawn()
		end)
	end

	assert(traversed == 0, `closed cursor must not resume into a later plan`)
	assert(unguardedMutation == false, `closed cursor must not expose unguarded iteration`)
	local spawned = world:spawn()
	assert(world:isAlive(spawned), `normal structural mutation should remain available after close`)

	world:destroy()
end)

test(`compiled query destroy unregisters plans and rejects reuse after active cursors close`, function()
	setup()
	local value = Component.define(`CompiledLifecycleValue`, { value = 0 })
	local world = World.new()
	local entity = world:spawn()
	world:add(entity, value.id, { value = 1 })
	local compiled: any = world:compile(Query.all(value):select(value))
	local cursor = compiled:cursor()
	assert(cursor() == entity, `active lifecycle cursor should yield the matching entity`)

	local activeDestroyOk = pcall(compiled.destroy, compiled)
	assert(activeDestroyOk == false, `compiled destroy should reject while one of its cursors is active`)
	cursor:close()
	compiled:destroy()
	compiled:destroy()

	local callOk = pcall(compiled)
	local cursorOk = pcall(compiled.cursor, compiled)
	assert(getmetatable(world._entityStore._compiledQueries).__mode == `k`, `compiled registry should use weak keys`)
	assert(world._entityStore._compiledQueries[compiled] == nil, `destroy should unregister the compiled query`)
	assert(#compiled._plans == 0, `destroy should release every compiled archetype plan`)
	assert(callOk == false and cursorOk == false, `destroyed compiled queries should reject every reuse path`)
	assert(world._entityStore._activeQueryStates == 0, `cursor close and destroy should release the mutation guard`)

	local replacement: any = world:compile(Query.all(value):select(value))
	assert(#replacement._plans == 1, `replacement compilation should register the live signature exactly once`)
	replacement:destroy()
	world:destroy()
end)

test(`active compiled cursor rejects structural mutation until explicitly closed`, function()
	setup()
	local value = Component.define(`Value`, { value = 0 })
	local missing = Component.define(`Missing`, { value = 0 })
	local world = World.new()
	local entity = world:spawn()
	world:add(entity, value.id, { value = 1 })

	local compiled: CompiledQuery = world:compile(Query.all(value):select(value))
	local cursor: CompiledQueryCursor = compiled:cursor()
	assert(cursor() == entity, `cursor should yield before an early break`)

	local spawnOk = pcall(function()
		world:spawn()
	end)
	local removeOk = pcall(function()
		world:remove(entity, value.id)
	end)
	local updateOk = pcall(function()
		world:add(entity, value.id, { value = 2 })
	end)
	local absentRemoveOk = pcall(function()
		world:remove(entity, missing.id)
	end)
	local addOk = pcall(function()
		world:add(entity, missing.id, { value = 3 })
	end)

	assert(spawnOk == false, `spawn should reject while a compiled cursor is active`)
	assert(removeOk == false, `component removal should reject while a compiled cursor is active`)
	assert(updateOk == true, `existing component writes should remain allowed during compiled iteration`)
	assert(absentRemoveOk == true, `absent component removal should remain a no-op during compiled iteration`)
	assert(addOk == false, `component addition should reject while a compiled cursor is active`)
	assert(world:read(entity, value.id).value == 2, `allowed writes should update the existing column`)
	assert(world:has(entity, value.id) == true, `rejected removal must not change storage`)
	assert(world:has(entity, missing.id) == false, `rejected addition must not change storage`)
	assert(world._entityStore:countAlive() == 1, `rejected spawn must not allocate an entity`)

	cursor:close()
	cursor:close()
	world:remove(entity, value.id)
	assert(world:has(entity, value.id) == false, `explicit close should release the mutation guard`)

	world:destroy()
end)

test(`active compiled cursor rejects observed removal before dispatch`, function()
	setup()
	local value = Component.define(`ObservedGuardValue`, { value = 0 })
	local world = World.new()
	local entity = world:spawn()
	world:add(entity, value.id, { value = 1 })

	local observerCount = 0
	world:onRemove(value.name, function()
		observerCount += 1
	end)

	local compiled: CompiledQuery = world:compile(Query.all(value):select(value))
	local cursor: CompiledQueryCursor = compiled:cursor()
	assert(cursor() == entity, `cursor should be active before observed removal`)

	local removeOk = pcall(function()
		world:remove(entity, value.id)
	end)

	assert(removeOk == false, `observed structural removal should reject while the cursor is active`)
	assert(world:has(entity, value.id) == true, `rejected observed removal must leave storage unchanged`)
	assert(observerCount == 0, `rejected observed removal must not dispatch onRemove`)

	cursor:close()
	world:remove(entity, value.id)
	assert(observerCount == 1, `successful removal after close should dispatch onRemove once`)

	world:destroy()
end)

test(`addComponents allows value updates but rejects missing components during compiled iteration`, function()
	setup()
	local value = Component.define(`Value`, { value = 0 })
	local missing = Component.define(`Missing`, { value = 0 })
	local world = World.new()
	local entity = world:spawn()
	world:add(entity, value.id, { value = 1 })

	local compiled: CompiledQuery = world:compile(Query.all(value):select(value))
	local cursor: CompiledQueryCursor = compiled:cursor()
	assert(cursor() == entity, `cursor should be active before bulk updates`)

	local updateOk = pcall(function()
		world:addComponents(entity, { [value] = { value = 2 } })
	end)
	local structuralOk = pcall(function()
		world:addComponents(entity, { [missing] = { value = 3 } })
	end)

	assert(updateOk == true, `value-only addComponents update should remain allowed during iteration`)
	assert(world:read(entity, value.id).value == 2, `value-only update should write the existing column`)
	assert(structuralOk == false, `missing-component addComponents should reject during iteration`)
	assert(world:has(entity, missing.id) == false, `rejected structural add must not change storage`)

	cursor:close()
	world:destroy()
end)

test(`mixed addComponents preflights structural work before values and observers`, function()
	setup()
	local dense = Component.define(`DenseValue`, { value = 0 })
	local sparse = Component.define(`SparseValue`, { value = 0 }, { sparse = true })
	local relation = Component.define(`RelationValue`, { value = 0 })
	local missing = Component.define(`MissingValue`, { value = 0 })
	local world = World.new()
	local target = world:spawn()
	local entity = world:spawn()
	local pair = World.Pair(relation.id, target)

	world:add(entity, dense.id, { value = 1 })
	world:add(entity, sparse.id, { value = 1 })
	world:add(entity, pair, { value = 1 })

	local observerOrder: { string } = {}
	local finalStateObserverCount = 0
	local function observe(name: string): ()
		table.insert(observerOrder, name)
		if
			world:read(entity, dense.id).value == 3
			and world:read(entity, sparse.id).value == 3
			and world:read(entity, pair).value == 3
		then
			finalStateObserverCount += 1
		end
	end
	world:onAdd(`DenseValue`, function(): ()
		observe(`DenseValue`)
	end)
	world:onAdd(`SparseValue`, function(): ()
		observe(`SparseValue`)
	end)

	local function orderedBatch(entries: { { any } }): any
		return setmetatable({}, {
			__iter = function(): (any, nil, nil)
				local index = 0
				return function(): (any, any)
					index += 1
					local entry = entries[index]
					if not entry then
						return nil
					end

					return entry[1], entry[2]
				end,
					nil,
					nil
			end,
		})
	end

	local compiled: CompiledQuery = world:compile(Query.all(dense):select(dense))
	local cursor: CompiledQueryCursor = compiled:cursor()
	assert(cursor() == entity, `cursor should be active before the mixed batch`)

	local rejected = pcall(function()
		world:addComponents(
			entity,
			orderedBatch({
				{ sparse, { value = 2 } },
				{ pair, { value = 2 } },
				{ missing, { value = 2 } },
			})
		)
	end)

	assert(rejected == false, `mixed batch with a missing dense component should reject`)
	assert(world:read(entity, sparse.id).value == 1, `rejection must preserve the existing sparse value`)
	assert(world:read(entity, pair).value == 1, `rejection must preserve the existing pair value`)
	assert(world:has(entity, missing.id) == false, `rejection must not attach the missing dense component`)
	assert(#observerOrder == 0, `rejection must not fire observers before the structural guard`)

	local updated = pcall(function()
		world:addComponents(
			entity,
			orderedBatch({
				{ sparse, { value = 3 } },
				{ pair, { value = 3 } },
				{ dense, { value = 3 } },
			})
		)
	end)

	assert(updated == true, `fully value-only mixed batch should succeed during iteration`)
	assert(world:read(entity, sparse.id).value == 3, `value-only batch should update sparse data`)
	assert(world:read(entity, pair).value == 3, `value-only batch should update pair data`)
	assert(world:read(entity, dense.id).value == 3, `value-only batch should update dense data`)
	assert(#observerOrder == 2, `successful value-only batch should fire named observers once each`)
	assert(
		observerOrder[1] == `SparseValue` and observerOrder[2] == `DenseValue`,
		`mixed batch observers should preserve declaration order`
	)
	assert(finalStateObserverCount == 2, `every mixed batch observer should see the complete updated final state`)

	cursor:close()
	world:destroy()
end)

test(`world:eachAlive() iterates every live entity and skips despawned ones`, function()
	setup()

	local world = World.new()

	local a = world:spawn()
	local b = world:spawn()
	local c = world:spawn()

	world:despawn(b)

	local seen: { [number]: boolean } = {}
	local count = 0
	for id in world:eachAlive() do
		seen[id] = true
		count += 1
	end

	assert(count == 2, `eachAlive should visit 2 live entities, got {count}`)
	assert(seen[a] == true, `eachAlive should include a`)
	assert(seen[c] == true, `eachAlive should include c`)
	assert(seen[b] ~= true, `eachAlive should not include despawned b`)

	world:destroy()
end)

test(`world:getComponents() returns a name-keyed snapshot of an entity`, function()
	setup()

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, `Health`, { current = 30, max = 100 })
	world:addComponent(id, `Position`, { x = 1, y = 2, z = 3 })

	local components = world:getComponents(id)
	assert(components ~= nil, `getComponents should return a table`)
	assert(components.Health.current == 30, `snapshot should carry Health data`)
	assert(components.Position.z == 3, `snapshot should carry Position data`)

	world:destroy()
end)

test(`a tripped circuit breaker stays disabled and stops running`, function()
	setup()

	local world = World.new()
	local runs = 0

	local flaky = System.new(`Flaky`, {
		phase = `Update`,
		run = function(_entities: { number }, _dt: number): ()
			runs += 1
			error(`always fails`)
		end,
	})

	world:addSystem(flaky)

	for _ = 1, 10 do
		world:step(0.016)
	end

	assert(world:isSystemEnabled(`Flaky`) == false, `system should be disabled after threshold`)

	local runsAtTrip = runs
	world:step(0.016)
	world:step(0.016)

	assert(runs == runsAtTrip, `disabled system must not run again, ran {runs - runsAtTrip} more times`)

	world:destroy()
end)

test(`world:addComponents() bulk-adds multiple data components in one call`, function()
	setup()
	Component.define(`Health`, { current = 0, max = 0 })
	Component.define(`Velocity`, { x = 0, y = 0, z = 0 })

	local world = World.new()
	local id = world:spawn()

	world:addComponents(id, {
		Health = { current = 80, max = 100 },
		Velocity = { x = 1, y = 2, z = 3 },
	})

	assert(world:hasComponent(id, `Health`) == true, `Health should be present after bulk add`)
	assert(world:hasComponent(id, `Velocity`) == true, `Velocity should be present after bulk add`)
	assert(world:get(id, `Health`).current == 80, `Health data should be stored`)
	assert(world:get(id, `Velocity`).z == 3, `Velocity data should be stored`)
end)

test(`world:addComponents() handles a tag alongside data components`, function()
	setup()
	Component.define(`Health`, { current = 0, max = 0 })
	local Frozen = Component.tag(`Frozen`)

	local world = World.new()
	local id = world:spawn()

	world:addComponents(id, {
		Health = { current = 50, max = 50 },
		[Frozen] = true,
	})

	assert(world:hasComponent(id, `Health`) == true, `Health should be present`)
	assert(world:hasComponent(id, Frozen) == true, `Frozen tag should be present`)
	assert(world:get(id, Frozen) == nil, `tag get should return nil`)
	assert(world:get(id, `Health`).current == 50, `Health data should be stored alongside the tag`)
end)

test(`world:addComponents() fires onAdd per component and overwrites in place`, function()
	setup()
	Component.define(`Health`, { current = 0, max = 0 })
	Component.define(`Velocity`, { x = 0, y = 0, z = 0 })

	local world = World.new()

	local added: { [string]: boolean } = {}
	world:onAdd(`Health`, function()
		added.Health = true
	end)
	world:onAdd(`Velocity`, function()
		added.Velocity = true
	end)

	local id = world:spawn()
	world:addComponent(id, `Health`, { current = 10, max = 10 })

	world:addComponents(id, {
		Health = { current = 99, max = 100 },
		Velocity = { x = 5, y = 0, z = 0 },
	})

	assert(added.Velocity == true, `onAdd should fire for the newly added Velocity`)
	assert(world:get(id, `Health`).current == 99, `pre-existing Health should be overwritten in place`)
	assert(world:get(id, `Velocity`).x == 5, `Velocity should be added with its data`)
end)

test(`world:addComponents() routes a sparse component to sparse storage`, function()
	setup()
	Component.define(`Health`, { current = 0, max = 0 })
	local Buff = Component.define(`Buff`, { power = 0 }, { sparse = true })

	local world = World.new()
	local id = world:spawn()

	world:addComponents(id, {
		Health = { current = 30, max = 30 },
		[Buff] = { power = 7 },
	})

	assert(world:hasComponent(id, Buff) == true, `sparse Buff should be present`)
	assert(world:get(id, Buff).power == 7, `sparse Buff data should be retrievable`)
	assert(world:get(id, `Health`).current == 30, `archetypal Health should be stored alongside the sparse component`)
end)

test(`world:getMany() reads multiple components in one call`, function()
	setup()

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, `Health`, { current = 30, max = 100 })
	world:addComponent(id, `Mana`, { current = 15, max = 50 })
	world:addComponent(id, `Position`, { x = 1, y = 2, z = 3 })

	local health, mana, position = world:getMany(id, `Health`, `Mana`, `Position`)

	assert(health.current == 30, `getMany Health.current should be 30, got {health.current}`)
	assert(mana.current == 15, `getMany Mana.current should be 15, got {mana.current}`)
	assert(position.z == 3, `getMany Position.z should be 3, got {position.z}`)

	world:destroy()
end)

test(`world:getMany() agrees with single get and returns nil for absent components`, function()
	setup()

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, `Health`, { current = 77, max = 100 })

	local health, missing = world:getMany(id, `Health`, `Mana`)

	assert(health == world:get(id, `Health`), `getMany should return the same table as single get`)
	assert(missing == nil, `getMany should return nil for a component the entity lacks`)

	world:destroy()
end)

test(`world:getMany() works with typed handles`, function()
	setup()

	local Health = Component.define(`Health`, { current = 100, max = 100 })
	local Mana = Component.define(`Mana`, { current = 0, max = 0 })

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, Health, { current = 42, max = 100 })
	world:addComponent(id, Mana, { current = 9, max = 50 })

	local health, mana = world:getMany(id, Health, Mana)

	assert(health.current == 42, `handle getMany Health.current should be 42`)
	assert(mana.current == 9, `handle getMany Mana.current should be 9`)

	world:destroy()
end)

test(`world:getMany() reads a sparse component alongside archetypal ones`, function()
	setup()

	Component.define(`Health`, { current = 0 })
	Component.define(`Buff`, { v = 0 }, { sparse = true })

	local world = World.new()
	local id = world:spawn()

	world:addComponent(id, `Health`, { current = 5 })
	world:addComponent(id, `Buff`, { v = 99 })

	local health, buff = world:getMany(id, `Health`, `Buff`)

	assert(health.current == 5, `archetypal read should be 5`)
	assert(buff.v == 99, `sparse read should be 99, got {tostring(buff and buff.v)}`)

	world:destroy()
end)

test(`numeric world operations match legacy data behavior and dirty names`, function()
	setup()
	local health = Component.define(`Health`, { current = 100 })
	local world = World.new()
	local numeric = world:spawn()
	local legacy = world:spawn()

	assert(Component.metadataOf(health.id).name == `Health`, `world operations should use private component metadata`)

	world:add(numeric, health.id, { current = 70 })
	world:addComponent(legacy, health, { current = 70 })
	assert(
		world:read(numeric, health.id).current == world:get(legacy, health).current,
		`numeric add/read should match legacy methods`
	)
	assert(
		world:has(numeric, health.id) == world:hasComponent(legacy, health),
		`numeric has should match legacy hasComponent`
	)

	world:write(numeric, health.id, { current = 25 })
	world:set(legacy, health, { current = 25 })
	assert(
		world:read(numeric, health.id).current == world:get(legacy, health).current,
		`numeric write should match legacy set`
	)

	local dirty = world:flushDirty()
	assert(#dirty == 2, `numeric and legacy writes should each mark dirty, got {#dirty}`)
	assert(
		dirty[1].name == `Health` and dirty[2].name == `Health`,
		`numeric writes should preserve the registered dirty name`
	)

	world:remove(numeric, health.id)
	world:removeComponent(legacy, health)
	assert(world:has(numeric, health.id) == false, `numeric remove should detach data`)
	assert(world:hasComponent(legacy, health) == false, `legacy removeComponent should stay equivalent`)

	world:destroy()
end)

test(`numeric world operations preserve stale entity validation`, function()
	setup()
	local health = Component.define(`Health`, { current = 100 })
	local world = World.new()
	local stale = world:spawn()
	world:despawn(stale)
	local live = world:spawn()

	local addOk = pcall(function()
		world:add(stale, health.id, { current = 1 })
	end)
	local readOk = pcall(function()
		world:read(stale, health.id)
	end)
	local writeOk = pcall(function()
		world:write(stale, health.id, { current = 1 })
	end)

	assert(live ~= stale, `recycled slot should carry a new generation`)
	assert(addOk == false, `numeric world add should reject a stale entity id`)
	assert(readOk == false, `numeric world read should reject a stale entity id`)
	assert(writeOk == false, `numeric world write should reject a stale entity id`)
	assert(world:has(stale, health.id) == false, `numeric world has should be false for a stale id`)
	world:remove(stale, health.id)
	assert(world:isAlive(live) == true, `numeric stale remove should not affect the recycled entity`)

	world:destroy()
end)

test(`public numeric world operations reject every malformed component id before access`, function()
	setup()
	local health = Component.define(`Health`, { current = 100 })
	local world = World.new()
	local entity = world:spawn()
	local healthData = { current = 75 }
	world:add(entity, health.id, healthData)

	local observerCount = 0
	world:onAdd(`Health`, function(): ()
		observerCount += 1
	end)
	world:onChange(`Health`, function(): ()
		observerCount += 1
	end)
	world:onRemove(`Health`, function(): ()
		observerCount += 1
	end)

	local malformedIds = { -1, 0, health.id + 0.5, health.id + 100000 }
	local operations = {
		function(componentId: number): ()
			world:add(entity, componentId, { current = 1 })
		end,
		function(componentId: number): ()
			world:read(entity, componentId)
		end,
		function(componentId: number): ()
			world:write(entity, componentId, { current = 1 })
		end,
		function(componentId: number): ()
			world:remove(entity, componentId)
		end,
		function(componentId: number): ()
			world:has(entity, componentId)
		end,
	}
	local rejected = 0

	for _, componentId in malformedIds do
		for _, operation in operations do
			if not pcall(operation, componentId) then
				rejected += 1
			end
		end
	end

	assert(rejected == #malformedIds * #operations, `every direct malformed numeric operation should reject`)
	assert(world:read(entity, health.id) == healthData, `rejected operations should preserve registered storage`)
	assert(observerCount == 0, `rejected operations must not fire observers`)

	world:destroy()
end)

test(`numeric batch query bundle and patch entries reject atomically`, function()
	setup()
	local health = Component.define(`Health`, { current = 100 })
	local added = Component.define(`Added`, { value = 0 })
	local world = World.new()
	local entity = world:spawn()
	local healthData = { current = 75 }
	world:add(entity, health.id, healthData)

	local observerCount = 0
	world:onAdd(`Added`, function(): ()
		observerCount += 1
	end)

	local malformedIds = { -1, 0, health.id + 0.5, health.id + 100000 }
	local rejected = 0
	for _, componentId in malformedIds do
		local entries = { [added.id] = { value = 1 }, [componentId] = { value = 2 } }
		if not pcall(world.addComponents, world, entity, entries) then
			rejected += 1
		end
		if not pcall(world.getMany, world, entity, componentId) then
			rejected += 1
		end
		if not pcall(world.bundle, world, componentId) then
			rejected += 1
		end
		if not pcall(world.patch, world, { add = { componentId } }) then
			rejected += 1
		end

		for _, field in { `_all`, `_any`, `_none`, `_select` } do
			local invalidQuery = Query.all(health)
			invalidQuery[field] = { componentId }
			if not pcall(world.query, world, invalidQuery) then
				rejected += 1
			end
			if not pcall(world.compile, world, invalidQuery) then
				rejected += 1
			end
		end
	end

	assert(rejected == #malformedIds * 12, `every malformed numeric aggregate entry should reject`)
	assert(world:read(entity, health.id) == healthData and not world:has(entity, added.id), `failures must be atomic`)
	assert(observerCount == 0, `failed aggregate operations must not fire observers`)
	assert(world._entityStore:countAlive() == 1, `failed aggregate operations must not allocate entities`)

	world:destroy()
end)

test(`world:bundle rejects duplicate and invalid component ids before archetype creation`, function()
	setup()
	local health = Component.define(`Health`, { current = 0 })
	local world = World.new()
	assert(type(world.bundle) == `function`, `world should expose bundle compilation`)

	local duplicateOk = pcall(function()
		world:bundle(health.id, health.id)
	end)
	local invalidOk = pcall(function()
		world:bundle(health.id, 999999)
	end)
	local invalidTypeOk = pcall(function()
		world:bundle(health.id, `Health` :: any)
	end)
	local emptyOk = pcall(function()
		world:bundle()
	end)

	local archetypeCount = 0
	for _ in world._entityStore._archetypes do
		archetypeCount += 1
	end

	assert(duplicateOk == false, `duplicate component ids should be rejected`)
	assert(invalidOk == false, `unknown component ids should be rejected`)
	assert(invalidTypeOk == false, `non-numeric component ids should be rejected`)
	assert(emptyOk == false, `empty bundles should be rejected in favor of plain spawn`)
	assert(archetypeCount == 1, `failed bundle compilation should leave only the root archetype`)
	assert(world._entityStore:countAlive() == 0, `failed bundle compilation should not allocate entities`)

	world:destroy()
end)

test(`world:spawn(bundle) stores dense tag and sparse members and fires observers`, function()
	setup()
	local health = Component.define(`Health`, { current = 0 })
	local frozen = Component.tag(`Frozen`)
	local buff = Component.define(`Buff`, { power = 0 }, { sparse = true })
	local world = World.new()
	local observed: { [string]: any } = {}

	world:onAdd(`Health`, function(_entity: number, data: any): ()
		observed.Health = data
	end)
	world:onAdd(`Frozen`, function(_entity: number, data: any): ()
		observed.Frozen = if data == nil then true else false
	end)
	world:onAdd(`Buff`, function(_entity: number, data: any): ()
		observed.Buff = data
	end)

	local bundle = world:bundle(frozen.id, buff.id, health.id)
	local buffData = { power = 9 }
	local healthData = { current = 75 }
	local id = world:spawn(bundle, buffData, healthData)

	assert(world:has(id, frozen.id) == true, `bundle spawn should attach the tag`)
	assert(world:read(id, buff.id) == buffData, `bundle spawn should store sparse data`)
	assert(world:read(id, health.id) == healthData, `bundle spawn should store dense data`)
	assert(observed.Frozen == true, `tag observer should fire with nil data`)
	assert(observed.Buff == buffData and observed.Health == healthData, `data observers should receive stored values`)

	world:destroy()
end)

test(`world:spawn(bundle) validates ownership and arity before entity allocation`, function()
	setup()
	local health = Component.define(`Health`, { current = 0 })
	local owner = World.new()
	local other = World.new()
	local bundle = owner:bundle(health.id)

	local foreignOk = pcall(function()
		other:spawn(bundle, { current = 10 })
	end)
	local missingOk = pcall(function()
		owner:spawn(bundle)
	end)

	assert(foreignOk == false, `bundle should not spawn into a different world`)
	assert(missingOk == false, `missing data should be rejected before allocation`)
	assert(owner._entityStore:countAlive() == 0, `invalid arity should not allocate in the owner world`)
	assert(other._entityStore:countAlive() == 0, `foreign bundle failure should not allocate in the other world`)
	assert(#bundle.archetype.entities == 0, `failed spawns should leave the destination empty`)

	owner:destroy()
	other:destroy()
end)

test(`world patch mutates add and remove values against one final state`, function()
	setup()

	local retained = Component.define(`WorldPatchRetained`, { value = 0 })
	local removed = Component.define(`WorldPatchRemoved`, { value = 0 })
	local firstAdded = Component.define(`WorldPatchFirstAdded`, { value = 0 })
	local secondAdded = Component.define(`WorldPatchSecondAdded`, { value = 0 })
	local world = World.new()
	local id = world:spawn()
	local retainedData = { value = 10 }
	world:add(id, retained.id, retainedData)
	world:add(id, removed.id, { value = 20 })
	local patch = world:patch({
		remove = { removed.id },
		add = { firstAdded.id, secondAdded.id },
	})

	world:mutate(id, patch, { value = 30 }, { value = 40 })

	assert(world:read(id, retained.id) == retainedData, `retained data should preserve its reference`)
	assert(world:has(id, removed.id) == false, `removed component should be absent from the final state`)
	assert(world:read(id, firstAdded.id).value == 30, `first addition should receive the first data argument`)
	assert(world:read(id, secondAdded.id).value == 40, `second addition should receive the second data argument`)
	assert(
		type(world.patch) == `function` and type(world.mutate) == `function`,
		`world should expose compiled patch APIs`
	)

	world:destroy()
end)

test(`active compiled iterator rejects patch before any mutation`, function()
	setup()

	local retained = Component.define(`WorldPatchGuardRetained`, { value = 0 })
	local removed = Component.define(`WorldPatchGuardRemoved`, { value = 0 })
	local added = Component.define(`WorldPatchGuardAdded`, { value = 0 })
	local world = World.new()
	local id = world:spawn()
	local retainedData = { value = 1 }
	local removedData = { value = 2 }
	world:add(id, retained.id, retainedData)
	world:add(id, removed.id, removedData)
	local patch = world:patch({ remove = { removed.id }, add = { added.id } })
	local compiled: CompiledQuery = world:compile(Query.all(retained):select(retained))
	local cursor: CompiledQueryCursor = compiled:cursor()
	assert(cursor() == id, `cursor should activate on the patch target`)

	local mutationOk = pcall(function()
		world:mutate(id, patch, { value = 3 })
	end)

	assert(mutationOk == false, `structural patch should reject while a compiled cursor is active`)
	assert(world:read(id, retained.id) == retainedData, `rejected patch should preserve retained data`)
	assert(world:read(id, removed.id) == removedData, `rejected patch should preserve removed data`)
	assert(world:has(id, added.id) == false, `rejected patch should not write additions`)

	cursor:close()
	world:mutate(id, patch, { value = 3 })
	assert(
		world:has(id, removed.id) == false and world:read(id, added.id).value == 3,
		`patch should succeed after cursor close`
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
