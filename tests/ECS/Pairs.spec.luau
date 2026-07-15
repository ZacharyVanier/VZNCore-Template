-- Relationship pair tests: pairs, wildcards, exclusivity, pair-as-tag, target.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
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

local function setup(): ()
	Component._reset()
	Component.tag(`Marker`)
end

local Pair = Component.Pair
local ChildOf = Component.ChildOf
local Wildcard = Component.Wildcard

local function count(list: { number }): number
	return #list
end

print("")
print("Running Pair tests...")
print("")

test(`concrete pair: add / has / remove`, function()
	setup()
	local world = World.new()

	local parent = world:spawn()
	local child = world:spawn()

	assert(world:hasComponent(child, Pair(ChildOf, parent)) == false, `child should start without the pair`)

	world:addComponent(child, Pair(ChildOf, parent))
	assert(world:hasComponent(child, Pair(ChildOf, parent)) == true, `child should hold Pair(ChildOf, parent)`)
	assert(world:get(child, Pair(ChildOf, parent)) == nil, `a tag-relation pair stores no data`)

	world:removeComponent(child, Pair(ChildOf, parent))
	assert(world:hasComponent(child, Pair(ChildOf, parent)) == false, `pair should be gone after remove`)

	world:destroy()
end)

test(`data pair: a data relation stores per-pair data`, function()
	setup()
	local world = World.new()

	local eats = Component.define(`Eats`, { amount = 0 })
	local eater = world:spawn()
	local apple = world:spawn()

	world:addComponent(eater, Pair(eats, apple), { amount = 3 })

	local stored = world:get(eater, Pair(eats, apple))
	assert(stored ~= nil and stored.amount == 3, `data pair should return its stored data`)
	assert(Component.isTagId(Pair(eats, apple)) == false, `a data-relation pair is not a tag`)
	assert(Component.isTagId(Pair(ChildOf, apple)) == true, `a tag-relation pair is a tag`)

	world:destroy()
end)

test(`concrete pair query matches only holders of that exact pair`, function()
	setup()
	local world = World.new()

	local parentA = world:spawn()
	local parentB = world:spawn()
	local c1 = world:spawn()
	local c2 = world:spawn()
	local c3 = world:spawn()

	world:addComponent(c1, Pair(ChildOf, parentA))
	world:addComponent(c2, Pair(ChildOf, parentA))
	world:addComponent(c3, Pair(ChildOf, parentB))

	local ofA = world._entityStore:collectEntities(Query.all(Pair(ChildOf, parentA)))
	assert(count(ofA) == 2, `two children of parentA, got {count(ofA)}`)

	local ofB = world._entityStore:collectEntities(Query.all(Pair(ChildOf, parentB)))
	assert(count(ofB) == 1, `one child of parentB, got {count(ofB)}`)

	world:destroy()
end)

test(`wildcard query in the target position: Pair(ChildOf, Wildcard)`, function()
	setup()
	local world = World.new()

	local parentA = world:spawn()
	local parentB = world:spawn()
	local c1 = world:spawn()
	local c2 = world:spawn()
	local loner = world:spawn()

	world:addComponent(c1, Pair(ChildOf, parentA))
	world:addComponent(c2, Pair(ChildOf, parentB))
	world:addComponent(loner, `Marker`)

	local anyChild = world._entityStore:collectEntities(Query.all(Pair(ChildOf, Wildcard)))
	assert(count(anyChild) == 2, `both children match Pair(ChildOf, Wildcard), got {count(anyChild)}`)

	world:destroy()
end)

test(`wildcard query in the relation position: Pair(Wildcard, Target)`, function()
	setup()
	local world = World.new()

	local eats = Component.define(`Eats`, { amount = 0 })
	local target = world:spawn()
	local childOfTarget = world:spawn()
	local eaterOfTarget = world:spawn()
	local unrelated = world:spawn()

	world:addComponent(childOfTarget, Pair(ChildOf, target))
	world:addComponent(eaterOfTarget, Pair(eats, target), { amount = 1 })
	world:addComponent(unrelated, `Marker`)

	local related = world._entityStore:collectEntities(Query.all(Pair(Wildcard, target)))
	assert(count(related) == 2, `both relations to target match Pair(Wildcard, target), got {count(related)}`)

	world:destroy()
end)

test(`exclusive relation swaps the target: adding Pair(R, B) drops Pair(R, A)`, function()
	setup()
	local world = World.new()

	local child = world:spawn()
	local parentA = world:spawn()
	local parentB = world:spawn()

	world:addComponent(child, Pair(ChildOf, parentA))
	assert(world:hasComponent(child, Pair(ChildOf, parentA)) == true, `child starts under parentA`)

	world:addComponent(child, Pair(ChildOf, parentB))
	assert(world:hasComponent(child, Pair(ChildOf, parentB)) == true, `child should now be under parentB`)
	assert(world:hasComponent(child, Pair(ChildOf, parentA)) == false, `exclusive relation should drop parentA`)

	world:destroy()
end)

test(`world:target reads the live target entity of a relation`, function()
	setup()
	local world = World.new()

	local child = world:spawn()
	local parent = world:spawn()

	assert(world:target(child, ChildOf) == nil, `no target before the pair is added`)

	world:addComponent(child, Pair(ChildOf, parent))
	assert(world:target(child, ChildOf) == parent, `target should be the live parent entity`)
	assert(world:target(child, ChildOf, 2) == nil, `there is no second target`)

	world:destroy()
end)

test(`pair-as-tag: a tag-relation pair shares the frozen column (no per-entity data)`, function()
	setup()
	local world = World.new()

	local parent = world:spawn()
	local a = world:spawn()
	local b = world:spawn()

	world:addComponent(a, Pair(ChildOf, parent))
	world:addComponent(b, Pair(ChildOf, parent))

	local pairId = Pair(ChildOf, parent)
	local columnA = world._entityStore:recordOfAny(a).archetype.columnsMap[pairId]
	local columnB = world._entityStore:recordOfAny(b).archetype.columnsMap[pairId]

	assert(columnA ~= nil, `the pair should be present in the signature`)
	assert(columnA == columnB, `both holders should share the one frozen tag column`)
	assert(next(columnA) == nil, `the shared tag column stays empty`)

	world:destroy()
end)

test(`entity-as-relation pair is sound despite a colliding tag component (id-space unification)`, function()
	setup()
	local world = World.new()

	-- Marker is a tag component holding a low id. Under the old split counters
	-- an entity slot could equal a component id, and Pair(thatEntity, x) would
	-- read isTagId(slot) against the colliding component -- misclassifying the
	-- entity relation as a tag and silently dropping its data. Unification draws
	-- entity slots and component ids from one counter, so they are disjoint.
	local markerId = Component.idOf(`Marker`)

	local relationEntity = world:spawn()
	local target = world:spawn()
	local holder = world:spawn()

	assert(
		Component.lowId(relationEntity) ~= markerId,
		`entity slot must be disjoint from the tag component id, both were {markerId}`
	)

	local pair = Pair(relationEntity, target)
	assert(
		Component.isTagId(pair) == false,
		`an entity-relation pair must not inherit a tag component's tag classification`
	)

	world:addComponent(holder, pair, { charges = 5 })
	local stored = world:get(holder, pair)
	assert(
		stored ~= nil and stored.charges == 5,
		`entity-relation pair must store its data, got {stored and stored.charges}`
	)

	world:destroy()
end)

test(`compiled query projects exact and wildcard pair columns`, function()
	setup()
	local likes = Component.define(`Likes`, { amount = 0 })
	local target = 42
	local world = World.new()
	local holder = world:spawn()
	local concretePair = Pair(likes, target)
	local wildcardPair = Pair(Wildcard, target)

	world:add(holder, concretePair, { amount = 7 })

	local exact = world:compile(Query.all(concretePair):select(concretePair))
	local exactEntity, exactData = exact()
	assert(exactEntity == holder, `exact pair projection should yield its holder`)
	assert(exactData ~= nil and exactData.amount == 7, `exact pair projection should read the concrete pair column`)
	assert(exact() == nil, `exact pair projection should exhaust`)

	local wildcard = world:compile(Query.all(wildcardPair):select(wildcardPair))
	local wildcardEntity, wildcardData = wildcard()
	assert(wildcardEntity == holder, `wildcard pair projection should yield its holder`)
	assert(
		wildcardData ~= nil and wildcardData.amount == 7,
		`wildcard pair projection should resolve the matching concrete column`
	)
	assert(wildcard() == nil, `wildcard pair projection should exhaust`)

	world:destroy()
end)

test(`numeric operations route tag and data pairs`, function()
	setup()
	local world = World.new()
	local parent = world:spawn()
	local child = world:spawn()
	local eater = world:spawn()
	local apple = world:spawn()
	local eats = Component.define(`Eats`, { amount = 0 })
	local childOf = Pair(ChildOf, parent)
	local eatsApple = Pair(eats, apple)

	world:add(child, childOf, nil)
	assert(world:has(child, childOf) == true, `numeric tag-pair add should attach the pair`)
	assert(world:read(child, childOf) == nil, `numeric tag-pair read should return nil`)

	world:add(eater, eatsApple, { amount = 3 })
	assert(world:read(eater, eatsApple).amount == 3, `numeric data-pair read should return stored data`)
	world:write(eater, eatsApple, { amount = 7 })
	assert(world:read(eater, eatsApple).amount == 7, `numeric data-pair write should replace data`)

	world:remove(child, childOf)
	world:remove(eater, eatsApple)
	assert(world:has(child, childOf) == false, `numeric tag-pair remove should detach the pair`)
	assert(world:has(eater, eatsApple) == false, `numeric data-pair remove should detach the pair`)

	world:destroy()
end)

test(`compiled patch preserves exclusive pair replacement semantics`, function()
	setup()

	local world = World.new()
	local child = world:spawn()
	local firstParent = world:spawn()
	local secondParent = world:spawn()
	local firstPair = Pair(ChildOf, firstParent)
	local secondPair = Pair(ChildOf, secondParent)
	world:add(child, firstPair, nil)
	local conflictingOk = pcall(function()
		world:patch({ add = { firstPair, secondPair } })
	end)
	assert(conflictingOk == false, `patch should reject two targets for one exclusive relation`)
	assert(
		world:has(child, firstPair) == true and world:has(child, secondPair) == false,
		`rejected exclusive patch should preserve membership`
	)
	local patch = world:patch({ add = { secondPair } })

	world:mutate(child, patch)

	assert(world:has(child, firstPair) == false, `exclusive patch add should remove the prior target`)
	assert(world:has(child, secondPair) == true, `exclusive patch add should attach the new target`)
	assert(world:target(child, ChildOf) == secondParent, `target lookup should expose the replacement target`)
	assert(
		#world._entityStore:recordOfAny(child).archetype.entities == 1,
		`exclusive replacement should leave one live row in the final archetype`
	)

	world:destroy()
end)

test(`relation trait changes invalidate cached patch destinations`, function()
	setup()

	local follows = Component.tag(`Follows`)
	local worldA = World.new()
	local worldB = World.new()
	worldA:setRelationTrait(follows, { exclusive = false })
	local firstTarget = worldB:spawn()
	local secondTarget = worldB:spawn()
	local firstPair = Pair(follows, firstTarget)
	local secondPair = Pair(follows, secondTarget)
	local patch = worldB:patch({ add = { secondPair } })
	local firstHolder = worldB:spawn()
	worldB:add(firstHolder, firstPair, nil)
	worldB:mutate(firstHolder, patch)
	assert(
		worldB:has(firstHolder, firstPair) and worldB:has(firstHolder, secondPair),
		`non-exclusive patch should retain both targets`
	)

	local secondHolder = worldB:spawn()
	worldB:add(secondHolder, firstPair, nil)
	worldA:setRelationTrait(follows, { exclusive = true })
	worldB:mutate(secondHolder, patch)

	assert(
		worldB:has(secondHolder, firstPair) == false,
		`global trait change should invalidate another world's non-exclusive destination`
	)
	assert(worldB:has(secondHolder, secondPair) == true, `rebuilt exclusive destination should contain the new target`)
	assert(
		worldB:target(secondHolder, follows) == secondTarget,
		`target should resolve through the rebuilt exclusive transition`
	)

	worldA:destroy()
	worldB:destroy()
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
