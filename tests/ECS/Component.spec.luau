-- Component module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

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

local function resetComponent(): ()
	if Component._reset then
		Component._reset()
	end
end

print("")
print("Running Component tests...")
print("")

test(`define() registers a component`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })
	assert(Component.isDefined(`Health`), `Health should be defined after define()`)
end)

test(`getDefinition() returns definition with defaults`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	local def = Component.getDefinition(`Health`)

	assert(def ~= nil, `getDefinition should return the definition`)
	assert(def.name == `Health`, `definition name should be Health`)
	assert(def.defaults.current == 100, `defaults.current should be 100`)
	assert(def.defaults.max == 100, `defaults.max should be 100`)
end)

test(`define() with singleton flag`, function()
	resetComponent()
	Component.define(`GameState`, { phase = `Waiting` }, { singleton = true })

	assert(Component.isDefined(`GameState`), `GameState should be defined`)
	assert(Component.isSingleton(`GameState`) == true, `GameState should be singleton`)
	assert(Component.isReplicated(`GameState`) == false, `GameState should not be replicated`)
end)

test(`define() with replicated flag`, function()
	resetComponent()
	Component.define(`Position`, { x = 0, y = 0, z = 0 }, { replicated = true })

	assert(Component.isDefined(`Position`), `Position should be defined`)
	assert(Component.isReplicated(`Position`) == true, `Position should be replicated`)
	assert(Component.isSingleton(`Position`) == false, `Position should not be singleton`)
end)

test(`define() same name twice errors`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	local ok, err = pcall(function()
		Component.define(`Health`, { current = 50, max = 50 })
	end)

	assert(not ok, `Defining same component twice should error`)
	assert(type(err) == "string", `Error should be a string`)
end)

test(`getDefinition() returns nil for nonexistent`, function()
	resetComponent()

	local def = Component.getDefinition(`Nonexistent`)

	assert(def == nil, `getDefinition for nonexistent should return nil`)
end)

test(`createInstance() returns table with defaults`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	local instance = Component.createInstance(`Health`)

	assert(instance ~= nil, `createInstance should return a table`)
	assert(instance.current == 100, `instance.current should be 100`)
	assert(instance.max == 100, `instance.max should be 100`)
end)

test(`createInstance() merges overrides`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	local instance = Component.createInstance(`Health`, { current = 50 })

	assert(instance.current == 50, `overridden current should be 50`)
	assert(instance.max == 100, `non-overridden max should remain 100`)
end)

test(`createInstance() returns independent copies`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	local a = Component.createInstance(`Health`)
	local b = Component.createInstance(`Health`)

	a.current = 25

	assert(b.current == 100, `modifying one instance should not affect another`)
end)

test(`createInstance() errors for undefined component`, function()
	resetComponent()

	local ok, _ = pcall(function()
		Component.createInstance(`DoesNotExist`)
	end)

	assert(not ok, `createInstance for undefined component should error`)
end)

test(`isDefined() returns false for nonexistent`, function()
	resetComponent()

	assert(Component.isDefined(`Nope`) == false, `isDefined should return false for nonexistent`)
end)

test(`isReplicated() returns false for undefined component`, function()
	resetComponent()

	assert(Component.isReplicated(`Nope`) == false, `isReplicated should return false for undefined`)
end)

test(`isSingleton() returns false for undefined component`, function()
	resetComponent()

	assert(Component.isSingleton(`Nope`) == false, `isSingleton should return false for undefined`)
end)

test(`define() with no options defaults flags to false`, function()
	resetComponent()
	Component.define(`Velocity`, { x = 0, y = 0, z = 0 })

	assert(Component.isSingleton(`Velocity`) == false, `should not be singleton by default`)
	assert(Component.isReplicated(`Velocity`) == false, `should not be replicated by default`)
end)

test(`define() returns a typed handle carrying id and name`, function()
	resetComponent()
	local health = Component.define(`Health`, { current = 100, max = 100 })

	assert(type(health) == "table", `define() should return a handle table`)
	assert(health.name == `Health`, `handle name should be Health`)
	assert(type(health.id) == "number", `handle id should be a number`)
	assert(health.isTag == false, `data component handle should not be a tag`)
end)

test(`tag() registers a zero-data tag component`, function()
	resetComponent()
	local frozen = Component.tag(`Frozen`)

	assert(Component.isDefined(`Frozen`) == true, `tag should be defined`)
	assert(Component.isTag(`Frozen`) == true, `Frozen should report as a tag`)
	assert(frozen.isTag == true, `tag handle should carry isTag = true`)
	assert(frozen.name == `Frozen`, `tag handle name should be Frozen`)
end)

test(`getHandle() returns the registered handle, nil for unknown`, function()
	resetComponent()
	local health = Component.define(`Health`, { current = 100, max = 100 })

	assert(Component.getHandle(`Health`) == health, `getHandle should return the same handle instance`)
	assert(Component.getHandle(`Missing`) == nil, `getHandle should return nil for an unregistered name`)
end)

test(`isTag() is false for data components and undefined names`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	assert(Component.isTag(`Health`) == false, `data component should not be a tag`)
	assert(Component.isTag(`Nope`) == false, `undefined name should not be a tag`)
end)

test(`handles receive distinct incrementing ids`, function()
	resetComponent()
	local a = Component.define(`Alpha`, { value = 0 })
	local b = Component.tag(`Beta`)

	assert(a.id ~= b.id, `distinct components should have distinct ids`)
	assert(b.id == a.id + 1, `ids should increment in registration order, got {a.id} then {b.id}`)
end)

test(`_reset() clears handles and the id counter`, function()
	resetComponent()
	Component.define(`Health`, { current = 100, max = 100 })

	Component._reset()

	assert(Component.getHandle(`Health`) == nil, `handle should be gone after reset`)

	local fresh = Component.define(`Health`, { current = 1, max = 1 })
	assert(fresh.id == 1, `id counter should restart at 1 after reset, got {fresh.id}`)
end)

test(`idOf() interns names and nameOf() reverses`, function()
	resetComponent()

	local a = Component.idOf(`Alpha`)
	local b = Component.idOf(`Beta`)

	assert(a ~= b, `distinct names get distinct ids`)
	assert(Component.idOf(`Alpha`) == a, `idOf is stable for the same name`)
	assert(Component.nameOf(a) == `Alpha`, `nameOf reverses idOf`)
	assert(Component.nameOf(a + 1000000) == nil, `nameOf returns nil for an unknown id`)
end)

test(`assertRegisteredId rejects malformed and unknown numeric ids`, function()
	resetComponent()
	local health = Component.define(`Health`, { current = 100 })
	local malformedIds = { -1, 0, health.id + 0.5, health.id + 100000 }
	local rejected = 0

	for _, componentId in malformedIds do
		if not pcall(Component.assertRegisteredId, componentId) then
			rejected += 1
		end
	end

	assert(rejected == #malformedIds, `every malformed or unknown id should reject`)
	assert(Component.assertRegisteredId(health.id) == health.id, `registered component id should pass through`)
	assert(
		Component.assertRegisteredId(Component.Pair(Component.ChildOf, 7)) ~= nil,
		`registered pair id should pass through`
	)
end)

test(`newEntity() shares one counter with component ids so they never collide`, function()
	resetComponent()

	local healthId = Component.idOf(`Health`)
	local firstEntity = Component.newEntity()
	local poisonId = Component.idOf(`Poison`)
	local secondEntity = Component.newEntity()

	assert(firstEntity ~= healthId, `an entity id must never equal an existing component id`)
	assert(poisonId ~= firstEntity, `a later component id must never reuse an entity id`)
	assert(
		secondEntity ~= firstEntity and secondEntity ~= poisonId and secondEntity ~= healthId,
		`every id drawn from the shared counter is unique`
	)
	assert(firstEntity == healthId + 1, `ids advance monotonically from one counter, got {firstEntity}`)
end)

test(`Pair() packs and unpacks a relation and target`, function()
	resetComponent()

	local rel = Component.idOf(`Owns`)
	local target = 5
	local p = Component.Pair(rel, target)

	assert(Component.isPair(p) == true, `packed value should read as a pair`)
	assert(Component.isPair(rel) == false, `a plain id is not a pair`)
	assert(Component.pairFirst(p) == rel, `pairFirst should recover the relation`)
	assert(Component.pairSecond(p) == target, `pairSecond should recover the target slot`)
end)

test(`Pair() strips the target generation, keeping the slot`, function()
	resetComponent()

	local slot = 7
	local generationPacked = slot + 3 * (2 ^ 24)

	assert(
		Component.Pair(Component.ChildOf, generationPacked) == Component.Pair(Component.ChildOf, slot),
		`pair should key on the target slot only`
	)
	assert(Component.lowId(generationPacked) == slot, `lowId returns the slot`)
end)

test(`isTagId(): a pair is a tag iff its relation is a tag`, function()
	resetComponent()

	local frozen = Component.tag(`Frozen`)
	local health = Component.define(`Health`, { current = 1 })

	assert(Component.isTagId(frozen.id) == true, `a tag component id is a tag`)
	assert(Component.isTagId(health.id) == false, `a data component id is not a tag`)
	assert(Component.isTagId(Component.Pair(Component.ChildOf, 3)) == true, `a ChildOf (tag) pair is a tag`)
	assert(Component.isTagId(Component.Pair(health, 3)) == false, `a data-relation pair is not a tag`)
end)

test(`classify(): agrees with isPair/isTagId/isSparseId for every id shape`, function()
	resetComponent()

	local health = Component.define(`Health`, { current = 1 })
	local frozen = Component.tag(`Frozen`)
	local buff = Component.define(`Buff`, { stacks = 1 }, { sparse = true })

	local ids = {
		health.id,
		frozen.id,
		buff.id,
		Component.Pair(Component.ChildOf, 3),
		Component.Pair(health, 3),
	}

	for _, id in ids do
		local isPair, isTag, isSparse = Component.classify(id)
		assert(isPair == Component.isPair(id), `classify isPair mismatch for id {id}`)
		assert(isTag == Component.isTagId(id), `classify isTag mismatch for id {id}`)
		assert(isSparse == Component.isSparseId(id), `classify isSparse mismatch for id {id}`)
	end

	local sparsePair, sparseTag, sparseSparse = Component.classify(buff.id)
	assert(
		sparsePair == false and sparseTag == false and sparseSparse == true,
		`a sparse data component classifies as sparse-only`
	)
end)

test(`builtins have stable ids that survive _reset and reserve no user ids`, function()
	resetComponent()

	local childOf = Component.ChildOf
	local wildcard = Component.Wildcard

	assert(childOf ~= wildcard, `builtins have distinct ids`)
	assert(Component.isTagId(childOf) == true, `ChildOf is a tag relation`)

	Component._reset()
	assert(Component.ChildOf == childOf, `ChildOf id should be stable across reset`)

	local first = Component.define(`First`, { x = 0 })
	assert(first.id == 1, `user ids still start at 1 despite reserved builtins, got {first.id}`)
end)

test(`getReplicatedNames lists only replicated definitions`, function()
	resetComponent()

	Component.define(`RepA`, { v = 0 }, { replicated = true })
	Component.define(`RepB`, { v = 0 }, { replicated = true })
	Component.define(`LocalOnly`, { v = 0 })

	local names = Component.getReplicatedNames()

	local set: { [string]: boolean } = {}
	for _, name in names do
		set[name] = true
	end

	assert(#names == 2, `should list exactly 2 replicated components, got {#names}`)
	assert(set.RepA == true, `RepA should be listed`)
	assert(set.RepB == true, `RepB should be listed`)
	assert(set.LocalOnly ~= true, `non-replicated LocalOnly should not be listed`)
end)

test(`define() with unboxed flag: isUnboxed + createInstance returns raw values`, function()
	resetComponent()

	local level = Component.define(`Level`, 0, { unboxed = true })
	local health = Component.define(`Health`, { current = 100, max = 100 })

	assert(Component.isUnboxed(level.id) == true, `Level should report unboxed`)
	assert(Component.isUnboxed(health.id) == false, `boxed Health should not report unboxed`)
	assert(Component.isUnboxed(Component.Pair(Component.ChildOf, 3)) == false, `a pair is never unboxed`)

	assert(Component.createInstance(`Level`) == 0, `unboxed createInstance returns the raw default`)
	assert(Component.createInstance(`Level`, 5) == 5, `unboxed createInstance returns the raw override`)

	local boxed = Component.createInstance(`Health`)
	assert(type(boxed) == "table" and boxed.current == 100, `boxed createInstance stays a fresh table`)
end)

test(`metadata indexes name and routing facts by numeric id`, function()
	resetComponent()

	local health = Component.define(`Health`, { current = 100 })
	local frozen = Component.tag(`Frozen`)
	local buff = Component.define(`Buff`, { stacks = 1 }, { sparse = true })
	local frozenPair = Component.Pair(frozen, 42)

	assert(Component.metadata[health.id].name == `Health`, `data metadata should retain its name`)
	assert(Component.metadata[health.id].isTag == false, `data metadata should not be a tag`)
	assert(Component.metadata[frozen.id].isTag == true, `tag metadata should identify a tag`)
	assert(Component.metadata[buff.id].isSparse == true, `sparse metadata should identify sparse storage`)
	assert(Component.metadata[frozenPair].isPair == true, `pair metadata should identify a pair`)
	assert(Component.metadata[frozenPair].isTag == true, `tag-relation pair metadata should identify a tag`)
	assert(Component.metadata[frozenPair].name == nil, `pair metadata should not invent an observer name`)
end)

test(`metadata table identity survives registry reset`, function()
	local metadata = Component.metadata

	resetComponent()
	local health = Component.define(`Health`, { current = 100 })

	assert(Component.metadata == metadata, `reset should preserve aliases to the metadata table`)
	assert(metadata[health.id].name == `Health`, `preserved alias should see new registrations`)
	assert(metadata[Component.ChildOf].isTag == true, `preserved alias should see reseeded builtins`)
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
