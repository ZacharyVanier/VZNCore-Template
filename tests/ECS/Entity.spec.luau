-- Entity module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local Entity = require("../../src/Engine/Entity")
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

print("")
print("Running Entity tests...")
print("")

test(`new() returns an EntityStore`, function()
	local store = Entity.new()

	assert(store ~= nil, `new() should return a table`)
	assert(type(store.spawn) == "function", `store should have spawn method`)
	assert(type(store.despawn) == "function", `store should have despawn method`)
	assert(type(store.isAlive) == "function", `store should have isAlive method`)
end)

test(`spawn() returns incrementing IDs starting at 1`, function()
	local store = Entity.new()

	local firstResult = table.pack(store:spawn())
	local id1 = firstResult[1]
	local id2 = store:spawn()
	local id3 = store:spawn()

	assert(firstResult.n == 1, `spawn should return exactly one value`)
	assert(id1 == 1, `first entity should be ID 1, got {id1}`)
	assert(id2 == 2, `second entity should be ID 2, got {id2}`)
	assert(id3 == 3, `third entity should be ID 3, got {id3}`)
end)

test(`despawn() removes an entity`, function()
	local store = Entity.new()

	local id = store:spawn()
	assert(store:isAlive(id) == true, `entity should be alive after spawn`)

	store:despawn(id)
	assert(store:isAlive(id) == false, `entity should not be alive after despawn`)
end)

test(`isAlive() returns correct boolean`, function()
	local store = Entity.new()

	local id1 = store:spawn()
	local id2 = store:spawn()

	assert(store:isAlive(id1) == true, `spawned entity should be alive`)
	assert(store:isAlive(id2) == true, `spawned entity should be alive`)
	assert(store:isAlive(999) == false, `non-existent entity should not be alive`)

	store:despawn(id1)

	assert(store:isAlive(id1) == false, `despawned entity should not be alive`)
	assert(store:isAlive(id2) == true, `other entity should still be alive`)
end)

test(`addComponent() stores data on an entity`, function()
	local store = Entity.new()

	local id = store:spawn()
	local healthData = { current = 100, max = 100 }

	store:addComponent(id, `Health`, healthData)

	local stored = store:get(id, `Health`)
	assert(stored ~= nil, `get() should return stored data`)
	assert(stored.current == 100, `stored current should be 100`)
	assert(stored.max == 100, `stored max should be 100`)
end)

test(`get() returns mutable reference to stored data`, function()
	local store = Entity.new()

	local id = store:spawn()
	local healthData = { current = 100, max = 100 }

	store:addComponent(id, `Health`, healthData)

	local ref = store:get(id, `Health`)
	ref.current = 50

	local refAgain = store:get(id, `Health`)
	assert(refAgain.current == 50, `mutation via get() should persist, got {refAgain.current}`)
end)

test(`set() replaces component data entirely`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })

	local newData = { current = 50, max = 200 }
	store:set(id, `Health`, newData)

	local stored = store:get(id, `Health`)
	assert(stored.current == 50, `set() should replace data, current should be 50`)
	assert(stored.max == 200, `set() should replace data, max should be 200`)
end)

test(`removeComponent() removes component from entity`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })

	assert(store:hasComponent(id, `Health`) == true, `should have Health before removal`)

	store:removeComponent(id, `Health`)

	assert(store:hasComponent(id, `Health`) == false, `should not have Health after removal`)
	assert(store:get(id, `Health`) == nil, `get() should return nil after removal`)
end)

test(`hasComponent() returns correct boolean`, function()
	local store = Entity.new()

	local id = store:spawn()
	assert(store:hasComponent(id, `Health`) == false, `should not have Health before adding`)

	store:addComponent(id, `Health`, { current = 100, max = 100 })
	assert(store:hasComponent(id, `Health`) == true, `should have Health after adding`)

	store:addComponent(id, `Velocity`, { x = 0, y = 0, z = 0 })
	assert(store:hasComponent(id, `Velocity`) == true, `should have Velocity`)
	assert(store:hasComponent(id, `Damage`) == false, `should not have Damage`)
end)

test(`despawn() removes all components from the entity`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })
	store:addComponent(id, `Velocity`, { x = 0, y = 0, z = 0 })
	store:addComponent(id, `Damage`, { amount = 10 })

	store:despawn(id)

	assert(store:isAlive(id) == false, `entity should not be alive`)

	local ok1, _ = pcall(function()
		store:get(id, `Health`)
	end)
	assert(not ok1, `get() on despawned entity should error`)
end)

test(`markDirty() adds entry to dirty queue`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })

	store:markDirty(id, `Health`)

	local dirty = store:flushDirty()
	assert(#dirty == 1, `should have 1 dirty entry, got {#dirty}`)
	assert(dirty[1].entity == id, `dirty entry entity should match`)
	assert(dirty[1].name == `Health`, `dirty entry name should be Health`)
end)

test(`flushDirty() returns entries and clears the queue`, function()
	local store = Entity.new()

	local id1 = store:spawn()
	local id2 = store:spawn()
	store:addComponent(id1, `Health`, { current = 100, max = 100 })
	store:addComponent(id2, `Velocity`, { x = 0, y = 0, z = 0 })

	store:markDirty(id1, `Health`)
	store:markDirty(id2, `Velocity`)

	local dirty1 = store:flushDirty()
	assert(#dirty1 == 2, `first flush should have 2 entries, got {#dirty1}`)

	local dirty2 = store:flushDirty()
	assert(#dirty2 == 0, `second flush should be empty, got {#dirty2}`)
end)

test(`getEntitiesWithComponent() returns correct entity list`, function()
	local store = Entity.new()

	local id1 = store:spawn()
	local id2 = store:spawn()
	local id3 = store:spawn()

	store:addComponent(id1, `Health`, { current = 100, max = 100 })
	store:addComponent(id2, `Health`, { current = 50, max = 50 })
	store:addComponent(id3, `Velocity`, { x = 1, y = 0, z = 0 })

	local healthEntities = store:getEntitiesWithComponent(`Health`)

	assert(#healthEntities == 2, `should have 2 entities with Health, got {#healthEntities}`)

	local hasId1 = false
	local hasId2 = false

	for _, entityId in healthEntities do
		if entityId == id1 then
			hasId1 = true
		end
		if entityId == id2 then
			hasId2 = true
		end
	end

	assert(hasId1, `entity id1 should be in the list`)
	assert(hasId2, `entity id2 should be in the list`)
end)

test(`addComponent() errors on non-alive entity`, function()
	local store = Entity.new()

	local ok, _ = pcall(function()
		store:addComponent(999, `Health`, { current = 100, max = 100 })
	end)

	assert(not ok, `addComponent on non-alive entity should error`)
end)

test(`get() errors on non-alive entity`, function()
	local store = Entity.new()

	local ok, _ = pcall(function()
		store:get(999, `Health`)
	end)

	assert(not ok, `get() on non-alive entity should error`)
end)

test(`set() errors on non-alive entity`, function()
	local store = Entity.new()

	local ok, _ = pcall(function()
		store:set(999, `Health`, { current = 50, max = 50 })
	end)

	assert(not ok, `set() on non-alive entity should error`)
end)

test(`getAllComponents() returns all components for an entity`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })
	store:addComponent(id, `Velocity`, { x = 1, y = 0, z = 0 })

	local all = store:getAllComponents(id)

	assert(all ~= nil, `getAllComponents should return a table`)
	assert(all.Health ~= nil, `should contain Health`)
	assert(all.Velocity ~= nil, `should contain Velocity`)
	assert(all.Health.current == 100, `Health.current should be 100`)
	assert(all.Velocity.x == 1, `Velocity.x should be 1`)
end)

test(`multiple EntityStores are independent`, function()
	local storeA = Entity.new()
	local storeB = Entity.new()

	local idA = storeA:spawn()
	local idB = storeB:spawn()

	storeA:addComponent(idA, `Health`, { current = 100, max = 100 })

	assert(storeA:hasComponent(idA, `Health`) == true, `storeA should have Health`)
	assert(storeB:hasComponent(idB, `Health`) == false, `storeB should not have Health`)
end)

test(`despawn recycles the slot with a bumped generation`, function()
	local store = Entity.new()

	local id1 = store:spawn()
	local id2 = store:spawn()

	store:despawn(id1)

	local id3 = store:spawn()

	assert(id3 ~= id1, `recycled id must differ from the stale id via generation bump, got {id3}`)
	assert(id3 % (2 ^ 24) == id1 % (2 ^ 24), `recycled id must reuse the same slot as id1`)
	assert(store:isAlive(id1) == false, `stale id1 must not be alive after slot reuse`)
	assert(store:isAlive(id2) == true, `untouched id2 must still be alive`)
	assert(store:isAlive(id3) == true, `recycled id3 must be alive`)
end)

test(`stale id fails isAlive and get after slot reuse`, function()
	local store = Entity.new()

	local staleId = store:spawn()
	store:addComponent(staleId, `Health`, { current = 100, max = 100 })

	store:despawn(staleId)

	local recycledId = store:spawn()
	assert(recycledId ~= staleId, `recycled id must differ from the stale id`)
	assert(store:isAlive(staleId) == false, `stale id must fail isAlive`)
	assert(store:isAlive(recycledId) == true, `recycled id must be alive`)

	local ok = pcall(function()
		store:get(staleId, `Health`)
	end)
	assert(not ok, `get() on a stale id must error`)
	assert(store:hasComponent(recycledId, `Health`) == false, `recycled entity must start with no components`)
end)

test(`freed slot future generation cannot alias a live swapped row before reuse`, function()
	Component._reset()
	local value = Component.define(`FutureGenerationValue`, { value = 0 })
	local store = Entity.new()
	local freed = store:spawn()
	local survivor = store:spawn()

	store:add(freed, value.id, { value = 1 })
	store:add(survivor, value.id, { value = 2 })
	store:despawn(freed)

	local futureGeneration = freed + 2 ^ 24
	local readOk = pcall(function()
		store:read(futureGeneration, value.id)
	end)
	local writeOk = pcall(function()
		store:write(futureGeneration, value.id, { value = 99 })
	end)

	assert(store:isAlive(futureGeneration) == false, `future generation must stay dead until the slot is respawned`)
	assert(readOk == false, `future generation must not read the survivor's swapped row`)
	assert(writeOk == false, `future generation must not write the survivor's swapped row`)
	assert(
		store:read(survivor, value.id).value == 2,
		`rejected future-generation access must leave survivor data unchanged`
	)
end)

test(`addComponent transitions archetype and preserves existing component data`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })
	store:addComponent(id, `Position`, { x = 10, y = 5, z = 0 })

	local health = store:get(id, `Health`)
	local position = store:get(id, `Position`)

	assert(health ~= nil and health.current == 100, `Health should survive the archetype transition`)
	assert(position ~= nil and position.x == 10, `Position should be present after transition`)
	assert(store:hasComponent(id, `Health`) == true, `entity should still have Health`)
	assert(store:hasComponent(id, `Position`) == true, `entity should now have Position`)
end)

test(`removeComponent transitions archetype and preserves remaining data`, function()
	local store = Entity.new()

	local id = store:spawn()
	store:addComponent(id, `Health`, { current = 100, max = 100 })
	store:addComponent(id, `Position`, { x = 10, y = 5, z = 0 })

	store:removeComponent(id, `Position`)

	assert(store:hasComponent(id, `Position`) == false, `Position should be gone after removal`)
	assert(store:hasComponent(id, `Health`) == true, `Health should remain after removing Position`)

	local health = store:get(id, `Health`)
	assert(
		health ~= nil and health.current == 100,
		`remaining Health data should be intact, got {health and health.current}`
	)
end)

test(`swap-remove keeps sibling rows intact after despawn`, function()
	local store = Entity.new()

	local first = store:spawn()
	local middle = store:spawn()
	local last = store:spawn()

	store:addComponent(first, `Health`, { current = 1, max = 100 })
	store:addComponent(middle, `Health`, { current = 2, max = 100 })
	store:addComponent(last, `Health`, { current = 3, max = 100 })

	store:despawn(middle)

	assert(store:isAlive(middle) == false, `despawned entity should not be alive`)
	assert(store:isAlive(first) == true, `first sibling should still be alive`)
	assert(store:isAlive(last) == true, `last sibling should still be alive`)

	local firstHealth = store:get(first, `Health`)
	local lastHealth = store:get(last, `Health`)
	assert(firstHealth.current == 1, `first sibling data should be intact, got {firstHealth.current}`)
	assert(lastHealth.current == 3, `swap-moved sibling data should be intact, got {lastHealth.current}`)
end)

test(`cached query stays correct across archetype churn`, function()
	local store = Entity.new()

	local cachedHealth = Query.all(`Health`):cached()

	local a = store:spawn()
	store:addComponent(a, `Health`, { value = 1 })

	local b = store:spawn()

	local first = store:collectEntities(cachedHealth)
	assert(#first == 1 and first[1] == a, `cached query should match only entity a initially, got {#first}`)

	store:addComponent(b, `Health`, { value = 2 })
	local second = store:collectEntities(cachedHealth)
	assert(#second == 2, `cached query should match a and b after b gains Health, got {#second}`)

	local c = store:spawn()
	store:addComponent(c, `Position`, { x = 0 })
	store:addComponent(c, `Health`, { value = 3 })
	local third = store:collectEntities(cachedHealth)
	assert(#third == 3, `newly created archetype must feed the cached query via the create hook, got {#third}`)

	store:removeComponent(a, `Health`)
	local fourth = store:collectEntities(cachedHealth)
	assert(#fourth == 2, `cached query should drop a after it loses Health, got {#fourth}`)
end)

test(`numeric churn rebuilds a swept cached edge`, function()
	Component._reset()
	local retained = Component.define(`SweptEdgeRetained`, { value = 0 })
	local churned = Component.define(`SweptEdgeChurned`, { value = 0 })
	local store = Entity.new()
	local id = store:spawn()
	local retainedData = { value = 10 }
	store:add(id, retained.id, retainedData)

	store:add(id, churned.id, { value = 20 })
	local firstDestination = store:recordOfAny(id).archetype
	store:remove(id, churned.id)
	assert(store:sweep() > 0, `sweep should remove the empty churn destination`)
	assert(store._archetypes[firstDestination.id] == nil, `swept destination should leave the live registry`)

	local churnedData = { value = 30 }
	store:add(id, churned.id, churnedData)
	local rebuiltDestination = store:recordOfAny(id).archetype

	assert(rebuiltDestination ~= firstDestination, `add should rebuild rather than reuse the swept edge`)
	assert(store._archetypes[rebuiltDestination.id] == rebuiltDestination, `rebuilt destination should be registered`)
	assert(store:read(id, retained.id) == retainedData, `rebuilt edge should preserve retained data`)
	assert(store:read(id, churned.id) == churnedData, `rebuilt edge should store added data`)
end)

test(`addTag() adds a zero-data tag that hasComponent reports`, function()
	Component._reset()
	Component.tag(`Frozen`)

	local store = Entity.new()
	local id = store:spawn()

	store:addTag(id, `Frozen`)

	assert(store:hasComponent(id, `Frozen`) == true, `entity should have the Frozen tag`)
	assert(store:get(id, `Frozen`) == nil, `a tag stores no data, so get() should be nil`)
	assert(store:isAlive(id) == true, `entity should still be alive`)
end)

test(`tags participate in archetype signatures for queries`, function()
	Component._reset()
	Component.tag(`Stunned`)

	local store = Entity.new()
	local a = store:spawn()
	local b = store:spawn()
	local c = store:spawn()

	store:addTag(a, `Stunned`)
	store:addTag(b, `Stunned`)

	local stunned = store:collectEntities(Query.all(`Stunned`))
	assert(#stunned == 2, `query should match the two tagged entities, got {#stunned}`)

	local hasC = false
	for _, entityId in stunned do
		if entityId == c then
			hasC = true
		end
	end
	assert(hasC == false, `untagged entity c should not match the tag query`)
end)

test(`writing data to a tag column errors, real components unaffected`, function()
	Component._reset()
	Component.tag(`Frozen`)

	local store = Entity.new()
	local id = store:spawn()
	store:addTag(id, `Frozen`)

	local ok = pcall(function()
		store:addComponent(id, `Frozen`, { value = 1 })
	end)
	assert(ok == false, `writing data to a tag column should error (frozen NULL_ARRAY)`)

	store:addComponent(id, `Health`, { current = 50, max = 50 })
	local health = store:get(id, `Health`)
	assert(health ~= nil and health.current == 50, `a real component alongside a tag should store data`)
end)

test(`tag and data component coexist; removing the tag keeps data`, function()
	Component._reset()
	Component.tag(`Frozen`)

	local store = Entity.new()
	local id = store:spawn()

	store:addComponent(id, `Health`, { current = 50, max = 100 })
	store:addTag(id, `Frozen`)

	assert(store:hasComponent(id, `Health`) == true, `entity should have Health`)
	assert(store:hasComponent(id, `Frozen`) == true, `entity should have the Frozen tag`)

	local before = store:get(id, `Health`)
	assert(before.current == 50, `Health data should survive gaining a tag, got {before.current}`)

	store:removeComponent(id, `Frozen`)

	assert(store:hasComponent(id, `Frozen`) == false, `tag should be gone after removal`)
	assert(store:hasComponent(id, `Health`) == true, `Health should remain after removing the tag`)

	local after = store:get(id, `Health`)
	assert(after.current == 50, `Health data should survive losing a tag, got {after.current}`)
end)

test(`despawn with a tagged sibling keeps the other row intact`, function()
	Component._reset()
	Component.tag(`Frozen`)

	local store = Entity.new()
	local first = store:spawn()
	local last = store:spawn()

	store:addComponent(first, `Health`, { current = 1, max = 100 })
	store:addTag(first, `Frozen`)
	store:addComponent(last, `Health`, { current = 3, max = 100 })
	store:addTag(last, `Frozen`)

	store:despawn(first)

	assert(store:isAlive(first) == false, `despawned entity should be gone`)
	assert(store:isAlive(last) == true, `sibling should still be alive`)

	local lastHealth = store:get(last, `Health`)
	assert(
		lastHealth.current == 3,
		`swap-moved sibling data should be intact through a tag column, got {lastHealth.current}`
	)
	assert(store:hasComponent(last, `Frozen`) == true, `sibling should keep its tag`)
end)

test(`migration: string API intact while storage is keyed by numeric ids`, function()
	Component._reset()
	local store = Entity.new()
	local id = store:spawn()

	store:addComponent(id, `Health`, { current = 100, max = 100 })

	local healthId = Component.idOf(`Health`)
	local archetype = store:recordOfAny(id).archetype

	assert(archetype.columnsMap[healthId] ~= nil, `archetype should key its column by the numeric id`)
	assert(archetype.columnsMap[`Health`] == nil, `archetype must not key by the string name`)
	assert(archetype.types[1] == healthId, `signature should hold the numeric id, not the name`)

	local stored = store:get(id, `Health`)
	assert(stored ~= nil and stored.current == 100, `string-API get() must still return the data`)
	assert(store:hasComponent(id, `Health`) == true, `string-API hasComponent() must still work`)

	local byId = store:get(id, healthId)
	assert(byId == stored, `id-keyed and name-keyed access must reach the same column`)
end)

test(`iter() streams entity + all() data straight from columns`, function()
	Component._reset()
	Component.define(`A`, { v = 0 })
	Component.define(`B`, { v = 0 })

	local store = Entity.new()
	local expected = 0
	for i = 1, 50 do
		local e = store:spawn()
		store:addComponent(e, `A`, { v = i })
		store:addComponent(e, `B`, { v = i * 2 })
		expected += i
	end

	local q = Query.all(`A`, `B`):cached()

	local sum, count = 0, 0
	for entity, a, b in store:iter(q) do
		assert(store:isAlive(entity), `streamed entity should be alive`)
		assert(b.v == a.v * 2, `second column should be the B data for the same row`)
		sum += a.v
		count += 1
	end

	assert(count == 50, `iter should visit every match, got {count}`)
	assert(sum == expected, `streamed A values should sum to {expected}, got {sum}`)
	assert(#store:collectEntities(q) == count, `iter and collectEntities must agree on match count`)
end)

test(`iter() crosses multiple archetypes yielding arity-1 data`, function()
	Component._reset()
	Component.define(`A`, { v = 0 })
	Component.define(`Extra`, { v = 0 })

	local store = Entity.new()
	for i = 1, 30 do
		local e = store:spawn()
		store:addComponent(e, `A`, { v = i })
		if i % 2 == 0 then
			store:addComponent(e, `Extra`, { v = i })
		end
	end

	local q = Query.all(`A`)

	local count = 0
	for _entity, a in store:iter(q) do
		assert(a ~= nil and a.v ~= nil, `arity-1 iter should yield the A data table`)
		count += 1
	end

	assert(count == 30, `iter must cross both archetypes (with/without Extra), got {count}`)
end)

test(`compile() streams zero through N projected columns`, function()
	Component._reset()
	local components = {}
	for index = 1, 5 do
		components[index] = Component.define(`Projected{index}`, { value = 0 })
	end

	local store = Entity.new()
	local entity = store:spawn()
	for index, component in components do
		store:add(entity, component.id, { value = index })
	end

	local zero = store:compile(Query.all(components[1]))
	local zeroEntity, zeroProjection = zero()
	assert(zeroEntity == entity and zeroProjection == nil, `zero projections should yield only the entity`)
	assert(zero() == nil, `zero-projection iterator should exhaust`)

	for arity = 1, 4 do
		local selected = table.create(arity)
		for index = 1, arity do
			selected[index] = components[index]
		end

		local compiled = store:compile(Query.all(components[1]):select(table.unpack(selected, 1, arity)))
		local yielded = table.pack(compiled())
		assert(yielded[1] == entity, `arity {arity} should yield the matching entity`)
		assert(yielded.n == arity + 1, `arity {arity} should yield {arity} projections`)
		for index = 1, arity do
			assert(yielded[index + 1].value == index, `arity {arity} projection {index} should align by row`)
		end
		assert(compiled() == nil, `arity {arity} iterator should exhaust`)
	end

	local many = store:compile(
		Query.all(components[1]):select(components[1], components[2], components[3], components[4], components[5])
	)
	local yielded = table.pack(many())
	assert(yielded.n == 6 and yielded[1] == entity, `N projections should yield entity plus every selected column`)
	for index = 1, 5 do
		assert(yielded[index + 1].value == index, `N projection {index} should align by row`)
	end
	assert(many() == nil, `N-projection iterator should exhaust`)
end)

test(`numeric operations route data tags sparse components and pairs`, function()
	Component._reset()
	local health = Component.define(`Health`, { current = 100 })
	local frozen = Component.tag(`Frozen`)
	local buff = Component.define(`Buff`, { stacks = 1 }, { sparse = true })
	local frozenPair = Component.Pair(frozen, 42)
	local store = Entity.new()
	local id = store:spawn()

	store:add(id, health.id, { current = 80 })
	store:add(id, frozen.id, nil)
	store:add(id, buff.id, { stacks = 2 })
	store:add(id, frozenPair, nil)

	assert(store:read(id, health.id).current == 80, `numeric data read should return stored data`)
	assert(store:has(id, frozen.id) == true, `numeric tag should be present`)
	assert(store:read(id, frozen.id) == nil, `numeric tag read should return nil`)
	assert(store:read(id, buff.id).stacks == 2, `numeric sparse read should return stored data`)
	assert(store:has(id, frozenPair) == true, `numeric pair should be present`)

	store:write(id, health.id, { current = 25 })
	store:write(id, buff.id, { stacks = 9 })
	assert(store:read(id, health.id).current == 25, `numeric data write should replace data`)
	assert(store:read(id, buff.id).stacks == 9, `numeric sparse write should replace data`)

	store:remove(id, frozen.id)
	store:remove(id, buff.id)
	store:remove(id, frozenPair)
	assert(store:has(id, frozen.id) == false, `numeric tag remove should detach the tag`)
	assert(store:has(id, buff.id) == false, `numeric sparse remove should clear sparse storage`)
	assert(store:has(id, frozenPair) == false, `numeric pair remove should detach the pair`)
end)

test(`numeric add enforces exclusive relation replacement inside the store`, function()
	Component._reset()
	local store = Entity.new()
	local firstParent = store:spawn()
	local secondParent = store:spawn()
	local child = store:spawn()
	local firstPair = Component.Pair(Component.ChildOf, firstParent)
	local secondPair = Component.Pair(Component.ChildOf, secondParent)

	store:add(child, firstPair, nil)
	assert(store:has(child, firstPair) == true, `first exclusive pair should be present before replacement`)

	store:add(child, secondPair, nil)
	assert(store:has(child, firstPair) == false, `new exclusive target should remove the previous pair`)
	assert(store:has(child, secondPair) == true, `new exclusive target should remain attached`)
end)

test(`numeric operations reject stale entity ids like compatibility methods`, function()
	Component._reset()
	local health = Component.define(`Health`, { current = 100 })
	local store = Entity.new()
	local stale = store:spawn()
	store:despawn(stale)
	local live = store:spawn()

	local addOk = pcall(function()
		store:add(stale, health.id, { current = 1 })
	end)
	local readOk = pcall(function()
		store:read(stale, health.id)
	end)
	local writeOk = pcall(function()
		store:write(stale, health.id, { current = 1 })
	end)

	assert(live ~= stale, `recycled slot should carry a new generation`)
	assert(addOk == false, `numeric add should reject a stale entity id`)
	assert(readOk == false, `numeric read should reject a stale entity id`)
	assert(writeOk == false, `numeric write should reject a stale entity id`)
	assert(store:has(stale, health.id) == false, `numeric has should be false for a stale entity id`)
	store:remove(stale, health.id)
	assert(store:isAlive(live) == true, `numeric stale remove should not affect the recycled entity`)
end)

test(`compatibility methods delegate to equivalent numeric behavior`, function()
	Component._reset()
	local health = Component.define(`Health`, { current = 100 })
	local store = Entity.new()
	local numeric = store:spawn()
	local legacy = store:spawn()

	store:add(numeric, health.id, { current = 70 })
	store:addComponent(legacy, `Health`, { current = 70 })
	assert(
		store:read(numeric, health.id).current == store:get(legacy, `Health`).current,
		`add/read should match addComponent/get`
	)

	store:write(numeric, health.id, { current = 30 })
	store:set(legacy, `Health`, { current = 30 })
	assert(store:read(numeric, health.id).current == store:get(legacy, `Health`).current, `write should match set`)

	store:remove(numeric, health.id)
	store:removeComponent(legacy, `Health`)
	assert(
		store:has(numeric, health.id) == store:hasComponent(legacy, `Health`),
		`remove/has should match compatibility methods`
	)
end)

test(`compiled bundle spawn appends directly to the final archetype with ordered data`, function()
	Component._reset()
	local position = Component.define(`Position`, { x = 0 })
	local velocity = Component.define(`Velocity`, { x = 0 })
	local store = Entity.new()
	local bundle = store:bundle(velocity.id, position.id)
	local velocityData = { x = 12 }
	local positionData = { x = 34 }

	local id = store:spawnBundle(bundle, velocityData, positionData)
	local record = store:recordOfAny(id)
	local archetypeCount = 0
	for _ in store._archetypes do
		archetypeCount += 1
	end

	assert(record.archetype == bundle.archetype, `spawn should place the entity in the compiled destination`)
	assert(#store._root.entities == 0, `compiled spawn should leave no root-archetype residue`)
	assert(#record.archetype.entities == 1 and record.archetype.entities[1] == id, `destination should append once`)
	assert(archetypeCount == 2, `bundle spawn should create no intermediate archetypes`)
	assert(store:read(id, velocity.id) == velocityData, `first data argument should follow bundle order`)
	assert(store:read(id, position.id) == positionData, `second data argument should follow bundle order`)
	assert(table.isfrozen(bundle) and table.isfrozen(bundle.ids), `compiled bundle and ordered ids should be immutable`)
	assert(
		table.isfrozen(bundle.metadata) and table.isfrozen(bundle.dataColumnPositions),
		`compiled metadata and column positions should be immutable`
	)
end)

test(`compiled bundle spawn writes tags and sparse members without data-column drift`, function()
	Component._reset()
	local health = Component.define(`Health`, { current = 0 })
	local frozen = Component.tag(`Frozen`)
	local buff = Component.define(`Buff`, { power = 0 }, { sparse = true })
	local store = Entity.new()
	local bundle = store:bundle(frozen.id, buff.id, health.id)
	local buffData = { power = 7 }
	local healthData = { current = 80 }

	local id = store:spawnBundle(bundle, buffData, healthData)
	local archetype = store:recordOfAny(id).archetype

	assert(store:has(id, frozen.id) == true, `tag should be present without consuming a data argument`)
	assert(store:read(id, buff.id) == buffData, `sparse member should store its ordered data argument`)
	assert(store:read(id, health.id) == healthData, `dense member should not drift after tag and sparse members`)
	assert(archetype.columnsMap[frozen.id] ~= nil, `tag should join the final archetype signature`)
	assert(archetype.columnsMap[buff.id] == nil, `sparse member should stay outside the archetype signature`)
end)

test(`failed compiled spawn is atomic and preserves recycled generation reuse`, function()
	Component._reset()
	local health = Component.define(`Health`, { current = 0 })
	local velocity = Component.define(`Velocity`, { x = 0 })
	local store = Entity.new()
	local stale = store:spawn()
	store:despawn(stale)
	local bundle = store:bundle(health.id, velocity.id)

	local missingOk = pcall(function()
		store:spawnBundle(bundle, { current = 10 })
	end)
	local extraOk = pcall(function()
		store:spawnBundle(bundle, { current = 10 }, { x = 2 }, { unexpected = true })
	end)

	assert(missingOk == false, `missing bundle data should error`)
	assert(extraOk == false, `extra bundle data should error`)
	assert(store:countAlive() == 0, `failed spawns must not allocate a live entity`)
	assert(#bundle.archetype.entities == 0, `failed spawns must not append to the destination`)

	local live = store:spawnBundle(bundle, { current = 10 }, { x = 2 })
	assert(live ~= stale, `valid spawn should reuse the slot with a bumped generation`)
	assert(live % (2 ^ 24) == stale % (2 ^ 24), `failed spawns must not consume the recycled slot`)
	assert(store:isAlive(live) == true, `valid spawn after failure should be alive`)
end)

test(`compiled patch preserves retained data and caches its final transition`, function()
	Component._reset()

	local retained = Component.define(`PatchRetained`, { value = 0 })
	local removed = Component.define(`PatchRemoved`, { value = 0 })
	local firstAdded = Component.define(`PatchFirstAdded`, { value = 0 })
	local secondAdded = Component.define(`PatchSecondAdded`, { value = 0 })
	local store = Entity.new()
	local first = store:spawn()
	local second = store:spawn()

	for index, id in { first, second } do
		store:add(id, retained.id, { value = index * 10 })
		store:add(id, removed.id, { value = index })
	end

	local source = store:recordOfAny(first).archetype
	local patch = store:patch({
		remove = { removed.id },
		add = { firstAdded.id, secondAdded.id },
	})

	store:mutate(first, patch, { value = 30 }, { value = 40 })
	local cachedDestination = patch._transitions[source.id]
	store:mutate(second, patch, { value = 31 }, { value = 41 })

	assert(table.isfrozen(patch) and table.isfrozen(patch.addIds), `compiled patch and ordered ids should be immutable`)
	assert(patch.removeIds[1] == removed.id, `remove ids should preserve declaration order`)
	assert(
		patch.addIds[1] == firstAdded.id and patch.addIds[2] == secondAdded.id,
		`add ids should preserve declaration order`
	)
	assert(patch.addMetadata[1].name == `PatchFirstAdded`, `patch should retain component metadata`)
	assert(
		cachedDestination ~= nil and patch._transitions[source.id] == cachedDestination,
		`later mutations should reuse the source transition`
	)
	assert(
		store:read(first, retained.id).value == 10 and store:read(second, retained.id).value == 20,
		`retained data should survive the fused move`
	)
	assert(
		store:has(first, removed.id) == false and store:has(second, removed.id) == false,
		`removed data should be absent`
	)
	assert(
		store:read(first, firstAdded.id).value == 30 and store:read(second, secondAdded.id).value == 41,
		`added data should follow patch order`
	)
end)

test(`compiled patch rejection is atomic before data or membership writes`, function()
	Component._reset()

	local retained = Component.define(`PatchAtomicRetained`, { value = 0 })
	local removed = Component.define(`PatchAtomicRemoved`, { value = 0 })
	local added = Component.define(`PatchAtomicAdded`, { value = 0 })
	local store = Entity.new()
	local id = store:spawn()
	local retainedData = { value = 10 }
	local removedData = { value = 20 }
	store:add(id, retained.id, retainedData)
	store:add(id, removed.id, removedData)

	local duplicateOk = pcall(function()
		store:patch({ add = { added.id, added.id } })
	end)
	local conflictOk = pcall(function()
		store:patch({ remove = { removed.id }, add = { removed.id } })
	end)
	local invalidOk = pcall(function()
		store:patch({ add = { 999999 } })
	end)
	local malformedAddOk = pcall(function()
		store:patch({ add = false } :: any)
	end)
	local malformedRemoveOk = pcall(function()
		store:patch({ remove = false } :: any)
	end)
	local patch = store:patch({ remove = { removed.id }, add = { added.id } })
	local arityOk = pcall(function()
		store:mutate(id, patch)
	end)
	local staleOk = pcall(function()
		store:mutate(999999, patch, { value = 30 })
	end)

	assert(
		duplicateOk == false and conflictOk == false and invalidOk == false,
		`invalid patch definitions should reject`
	)
	assert(malformedAddOk == false and malformedRemoveOk == false, `false patch fields should reject rather than omit`)
	assert(arityOk == false and staleOk == false, `invalid mutations should reject before storage writes`)
	assert(store:read(id, retained.id) == retainedData, `retained data should remain byte-identical after rejection`)
	assert(store:read(id, removed.id) == removedData, `removed data should remain present after rejection`)
	assert(store:has(id, added.id) == false, `addition should remain absent after rejection`)
end)

test(`empty compiled patch is an immutable no-op`, function()
	Component._reset()

	local retained = Component.define(`PatchNoopRetained`, { value = 0 })
	local store = Entity.new()
	local id = store:spawn()
	local data = { value = 7 }
	store:add(id, retained.id, data)
	local before = store:recordOfAny(id).archetype
	local patch = store:patch({})

	store:mutate(id, patch)

	assert(table.isfrozen(patch), `empty patch should still be immutable`)
	assert(store:recordOfAny(id).archetype == before, `empty patch should not move the entity`)
	assert(store:read(id, retained.id) == data, `empty patch should preserve retained data`)
	assert(#patch.addIds == 0 and #patch.removeIds == 0, `empty patch should contain no operations`)
end)

test(`compiled patch rebuilds a swept destination transition`, function()
	Component._reset()

	local retained = Component.define(`PatchSweepRetained`, { value = 0 })
	local swapped = Component.define(`PatchSweepSwapped`, { value = 0 })
	local added = Component.define(`PatchSweepAdded`, { value = 0 })
	local store = Entity.new()
	local id = store:spawn()
	store:add(id, retained.id, { value = 1 })
	store:add(id, swapped.id, { value = 2 })
	local forward = store:patch({ remove = { swapped.id }, add = { added.id } })
	local reverse = store:patch({ remove = { added.id }, add = { swapped.id } })

	store:mutate(id, forward, { value = 3 })
	local firstDestination = store:recordOfAny(id).archetype
	store:mutate(id, reverse, { value = 4 })
	assert(store:sweep() > 0, `sweep should destroy the now-empty patch destination`)
	assert(store._archetypes[firstDestination.id] == nil, `swept destination should leave the archetype registry`)

	store:mutate(id, forward, { value = 5 })
	local rebuiltDestination = store:recordOfAny(id).archetype

	assert(rebuiltDestination ~= firstDestination, `patch should rebuild rather than reuse a swept destination`)
	assert(store._archetypes[rebuiltDestination.id] == rebuiltDestination, `rebuilt destination should be registered`)
	assert(
		store:read(id, retained.id).value == 1 and store:read(id, added.id).value == 5,
		`rebuilt transition should preserve and add data`
	)
end)

test(`compiled patch destroy clears registration and cached transitions idempotently`, function()
	Component._reset()
	local retained = Component.define(`PatchLifecycleRetained`, { value = 0 })
	local removed = Component.define(`PatchLifecycleRemoved`, { value = 0 })
	local added = Component.define(`PatchLifecycleAdded`, { value = 0 })
	local store = Entity.new()
	local id = store:spawn()
	store:add(id, retained.id, { value = 1 })
	store:add(id, removed.id, { value = 2 })
	local patch: any = store:patch({ remove = { removed.id }, add = { added.id } })
	store:mutate(id, patch, { value = 3 })
	assert(next(patch._transitions) ~= nil, `used patch should cache a source transition`)

	patch:destroy()
	patch:destroy()
	local reuseOk = pcall(store.mutate, store, id, patch, { value = 4 })

	assert(getmetatable(store._compiledPatches).__mode == `k`, `compiled patch registry should use weak keys`)
	assert(store._compiledPatches[patch] == nil, `destroy should unregister the compiled patch`)
	assert(next(patch._transitions) == nil, `destroy should clear cached patch transitions`)
	assert(reuseOk == false, `destroyed compiled patch should reject reuse`)
	assert(store:read(id, added.id).value == 3, `rejected reuse should preserve the prior final state`)
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
