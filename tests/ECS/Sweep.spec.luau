-- Fragmentation sweep tests: world:sweep() destroys empty archetypes and prunes
-- stale pair-index buckets while keeping live ones.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local World = require("../../src/Engine/World")
local Component = require("../../src/Engine/Component")
local Query = require(`../../src/Engine/Query`)

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

local function countEmptyArchetypes(store: any): number
	local n = 0
	for _, archetype in store._archetypes do
		if archetype ~= store._root and #archetype.entities == 0 then
			n += 1
		end
	end
	return n
end

print("")
print("Running Sweep tests...")
print("")

test(`sweep destroys empty archetypes and returns the count`, function()
	Component._reset()
	local world = World.new()

	local e = world:spawn()
	world:addComponent(e, `Health`, { current = 1, max = 1 })
	world:removeComponent(e, `Health`)

	local store = world._entityStore
	local emptyBefore = countEmptyArchetypes(store)
	assert(emptyBefore >= 1, `removing the last component should leave an empty archetype, got {emptyBefore}`)

	local destroyed = world:sweep()

	assert(destroyed == emptyBefore, `sweep should report the number destroyed, got {destroyed} vs {emptyBefore}`)
	assert(countEmptyArchetypes(store) == 0, `no empty archetypes should remain after sweep`)
	assert(world:isAlive(e) == true, `the surviving entity must be untouched by the sweep`)

	world:destroy()
end)

test(`sweep prunes stale pair buckets but keeps buckets for live pairs`, function()
	Component._reset()
	local world = World.new()

	local parentA = world:spawn()
	local parentB = world:spawn()
	local childA = world:spawn()
	local childB = world:spawn()

	world:addComponent(childA, Pair(ChildOf, parentA))
	world:addComponent(childB, Pair(ChildOf, parentB))

	local store = world._entityStore
	local pairA = Pair(ChildOf, parentA)
	local pairB = Pair(ChildOf, parentB)
	local slotA = Component.pairSecond(pairA)
	local slotB = Component.pairSecond(pairB)

	-- Drop childA's pair WITHOUT despawning anything: the {pairA} archetype goes
	-- empty but the pair-index buckets still hold pairA (the tracked leak).
	world:removeComponent(childA, pairA)

	assert(store._pairsByTarget[slotA][pairA] == true, `stale pair should still be bucketed by target before sweep`)
	assert(
		store._pairsByRelation[ChildOf][pairA] == true,
		`stale pair should still be bucketed by relation before sweep`
	)

	world:sweep()

	assert(store._pairsByTarget[slotA] == nil, `emptied target bucket should be removed after sweep`)
	assert(store._pairsByRelation[ChildOf][pairA] == nil, `stale pair should be pruned from the relation bucket`)
	assert(store._pairsByTarget[slotB][pairB] == true, `the live pair's target bucket must be retained`)
	assert(store._pairsByRelation[ChildOf][pairB] == true, `the live pair must be retained in the relation bucket`)
	assert(world:hasComponent(childB, pairB) == true, `the live pair holder must be unaffected`)

	world:destroy()
end)

test(`compiled bundle remains registered and reusable after its destination is swept empty`, function()
	Component._reset()
	local position = Component.define(`Position`, { x = 0 })
	local velocity = Component.define(`Velocity`, { x = 0 })
	local world = World.new()
	local bundle = world:bundle(position.id, velocity.id)
	local query = Query.all(position.id, velocity.id):cached()

	local first = world:spawn(bundle, { x = 10 }, { x = 20 })
	local initialMatchCount = 0
	for entity in world:query(query) do
		initialMatchCount += 1
		assert(entity == first, `registered cached query should initially yield the bundle entity`)
	end
	assert(initialMatchCount == 1, `registered cached query should initially have one match`)

	world:despawn(first)
	local destroyed = world:sweep()
	local second = world:spawn(bundle, { x = 30 }, { x = 40 })

	local matchCount = 0
	local matchedEntity: number? = nil
	for entity in world:query(query) do
		matchCount += 1
		matchedEntity = entity
	end

	local matchingSignatureCount = 0
	for _, archetype in world._entityStore._archetypes do
		if archetype.type == bundle.archetype.type then
			matchingSignatureCount += 1
		end
	end

	assert(destroyed == 0, `sweep should retain the compiled bundle destination`)
	assert(world:isAlive(second) == true, `bundle reuse after sweep should allocate a live entity`)
	assert(matchCount == 1 and matchedEntity == second, `cached query should see the reused bundle entity exactly once`)
	assert(
		world._entityStore._archetypeIndex[bundle.archetype.type] == bundle.archetype,
		`bundle destination should remain registered by signature`
	)
	assert(matchingSignatureCount == 1, `bundle reuse should not create a duplicate archetype signature`)

	world:destroy()
end)

test(`sweep unregisters compiled plans for unpinned archetypes and retains pinned plans`, function()
	Component._reset()
	local position = Component.define(`Position`, { x = 0 })
	local velocity = Component.define(`Velocity`, { x = 0 })
	local world = World.new()
	local compiled = world:compile(Query.all(position):select(position))

	local transient = world:spawn()
	world:add(transient, position.id, { x = 1 })
	world:remove(transient, position.id)
	assert(#compiled._plans == 1, `compiled query should register the transient matching archetype`)

	local destroyed = world:sweep()
	assert(destroyed == 1, `sweep should destroy the unpinned matching archetype`)
	assert(#compiled._plans == 0, `destroyed archetype should leave the compiled plan`)

	local bundle = world:bundle(position.id, velocity.id)
	local pinnedCompiled = world:compile(Query.all(position, velocity):select(position))
	local pinned = world:spawn(bundle, { x = 2 }, { x = 3 })
	world:despawn(pinned)

	assert(#pinnedCompiled._plans == 1, `compiled query should register the pinned bundle archetype`)
	assert(world:sweep() == 0, `sweep should retain an empty pinned archetype`)
	assert(#pinnedCompiled._plans == 1, `pinned archetype should remain in the compiled plan`)

	world:destroy()
end)

test(`bundle destroy reference-counts shared pins and permits one-signature sweep rebuild`, function()
	Component._reset()
	local position = Component.define(`BundleLifecyclePosition`, { x = 0 })
	local velocity = Component.define(`BundleLifecycleVelocity`, { x = 0 })
	local world = World.new()
	local first: any = world:bundle(position.id, velocity.id)
	local second: any = world:bundle(position.id, velocity.id)
	local destination = first.archetype

	assert(first.archetype == second.archetype, `equivalent bundles should share one destination signature`)
	assert(destination._bundlePins == 2, `each live bundle should own one destination pin`)
	first:destroy()
	first:destroy()
	assert(destination._bundlePins == 1, `idempotent destroy should release exactly one shared pin`)
	assert(world:sweep() == 0, `one remaining bundle pin should retain the empty destination`)

	second:destroy()
	local reuseOk = pcall(world.spawn, world, second, { x = 1 }, { x = 2 })
	assert(destination._bundlePins == 0, `last bundle destroy should release the destination pin`)
	assert(reuseOk == false, `destroyed bundle should reject spawn reuse`)
	assert(world:sweep() == 1, `released empty bundle destination should be swept`)

	local replacement: any = world:bundle(position.id, velocity.id)
	local replacementEntity = world:spawn(replacement, { x = 3 }, { x = 4 })
	local signatureCount = 0
	for _, archetype in world._entityStore._archetypes do
		if archetype.type == replacement.archetype.type then
			signatureCount += 1
		end
	end
	assert(replacement.archetype ~= destination, `released swept destination should rebuild on demand`)
	assert(signatureCount == 1, `replacement should register the rebuilt signature exactly once`)
	assert(world:isAlive(replacementEntity), `replacement bundle should remain usable after rebuild`)

	replacement:destroy()
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
