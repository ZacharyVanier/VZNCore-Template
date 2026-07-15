-- Archetype module tests
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

local process = require("@lune/process")

local Archetype = require("../../src/Engine/Archetype")
local Component = require("../../src/Engine/Component")
local Entity = require("../../src/Engine/Entity")
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

-- Signatures are numeric component ids after the id-space migration. These
-- stand-in ids (never registered as components) resolve as data columns.
local HEALTH = 1
local POSITION = 2

local function makeStore(): any
	local store = {
		_maxArchetypeId = 0,
		_archetypes = {},
		_archetypeIndex = {},
		_archetypeEdges = {},
		_cachedQueries = {},
		_queryCache = {},
	}

	store._root = Archetype.createRoot(store)

	return store
end

print("")
print("Running Archetype tests...")
print("")

test(`createRoot() registers an empty root archetype`, function()
	local store = makeStore()
	local root = store._root

	assert(root ~= nil, `root should exist`)
	assert(#root.types == 0, `root should have an empty signature`)
	assert(store._archetypes[root.id] == root, `root should be registered by id`)
	assert(store._archetypeIndex[""] == root, `root should be registered under the empty hash`)
end)

test(`traverseAdd() builds a single-component archetype keyed by numeric id`, function()
	local store = makeStore()

	local withHealth = Archetype.traverseAdd(store, store._root, HEALTH)

	assert(withHealth ~= store._root, `adding a component should yield a new archetype`)
	assert(withHealth.columnsMap[HEALTH] ~= nil, `destination should have a numeric-id column`)
	assert(withHealth.columnsMap[`Health`] == nil, `signature must not be keyed by the string name`)
	assert(#withHealth.types == 1 and withHealth.types[1] == HEALTH, `signature should hold the id`)

	local again = Archetype.traverseAdd(store, store._root, HEALTH)
	assert(again == withHealth, `edge should be cached: same destination object`)
end)

test(`signatures are canonical regardless of add order`, function()
	local store = makeStore()

	local healthThenPosition = Archetype.traverseAdd(store, Archetype.traverseAdd(store, store._root, HEALTH), POSITION)
	local positionThenHealth = Archetype.traverseAdd(store, Archetype.traverseAdd(store, store._root, POSITION), HEALTH)

	assert(healthThenPosition == positionThenHealth, `add order must not change archetype identity`)
	assert(
		healthThenPosition.types[1] == HEALTH and healthThenPosition.types[2] == POSITION,
		`types should be sorted by id`
	)
	assert(
		healthThenPosition.columnsMap[HEALTH] ~= nil and healthThenPosition.columnsMap[POSITION] ~= nil,
		`both component columns should exist`
	)
end)

test(`traverseRemove() returns the archetype without the component`, function()
	local store = makeStore()

	local both = Archetype.traverseAdd(store, Archetype.traverseAdd(store, store._root, HEALTH), POSITION)

	local withoutPosition = Archetype.traverseRemove(store, both, POSITION)
	assert(withoutPosition.columnsMap[POSITION] == nil, `removed component column should be gone`)
	assert(withoutPosition.columnsMap[HEALTH] ~= nil, `remaining component should stay`)
	assert(#withoutPosition.types == 1, `signature should shrink by one`)

	local backToRoot = Archetype.traverseRemove(store, withoutPosition, HEALTH)
	assert(backToRoot == store._root, `removing the last component should return to root`)
end)

test(`destroyEmpty() removes empty archetypes and updates cached queries`, function()
	local store = makeStore()

	local cached = Query.all(HEALTH):cached()
	store._queryCache[cached] = {}
	table.insert(store._cachedQueries, cached)

	local withHealth = Archetype.traverseAdd(store, store._root, HEALTH)
	assert(#store._queryCache[cached] == 1, `created archetype should register into the cached query`)
	assert(store._queryCache[cached][1] == withHealth, `cached query should hold the matching archetype`)

	local removed = Archetype.destroyEmpty(store)
	assert(removed == 1, `exactly one empty archetype should be destroyed, got {removed}`)
	assert(store._archetypeIndex[withHealth.type] == nil, `destroyed archetype should leave the index`)
	assert(#store._queryCache[cached] == 0, `cached query list should be updated on destroy`)
end)

-- moveEntity needs records and a recordOfAny hook; this mirrors the minimal
-- slice of EntityStore that moveEntity touches so the transfer plan (copy/drop
-- lists + swap-remove reindex) can be exercised in isolation.
local function makeMoveStore(): any
	local store = makeStore()
	store._entityIndex = { sparseArray = {} }
	store._records = store._entityIndex.sparseArray

	function store.recordOfAny(self: any, entity: number): any
		return self._entityIndex.sparseArray[entity]
	end

	return store
end

local function place(store: any, archetype: any, entity: number, data: { [number]: any }): any
	local row = Archetype.appendEntity(archetype, entity)

	for id, value in data do
		archetype.columnsMap[id][row] = value
	end

	local record = { archetype = archetype, row = row }
	store._records[entity] = record

	return record
end

test(`moveEntity() copies data columns to the destination on add (tail entity)`, function()
	local store = makeMoveStore()

	local archHealth = Archetype.traverseAdd(store, store._root, HEALTH)
	local record = place(store, archHealth, 1001, { [HEALTH] = 42 })

	local archBoth = Archetype.traverseAdd(store, archHealth, POSITION)
	Archetype.moveEntity(store, 1001, record, archBoth)

	assert(record.archetype == archBoth, `record should point at the destination archetype`)
	assert(archBoth.columnsMap[HEALTH][record.row] == 42, `HEALTH data should transfer to the destination column`)
	assert(#archHealth.entities == 0, `source archetype should be emptied`)
	assert(archHealth.columnsMap[HEALTH][1] == nil, `source column cell should be cleared`)
end)

test(`moveEntity() swap-removes and reindexes when moving a non-tail entity`, function()
	local store = makeMoveStore()

	local archHealth = Archetype.traverseAdd(store, store._root, HEALTH)
	local recordA = place(store, archHealth, 2001, { [HEALTH] = 10 })
	place(store, archHealth, 2002, { [HEALTH] = 20 })
	local recordC = place(store, archHealth, 2003, { [HEALTH] = 30 })

	local archBoth = Archetype.traverseAdd(store, archHealth, POSITION)
	Archetype.moveEntity(store, 2001, recordA, archBoth)

	assert(archBoth.columnsMap[HEALTH][recordA.row] == 10, `moved entity keeps its HEALTH data`)
	assert(#archHealth.entities == 2, `source archetype should have two entities left`)
	assert(archHealth.entities[1] == 2003, `last entity should be swapped into the vacated row`)
	assert(archHealth.columnsMap[HEALTH][1] == 30, `swapped entity's column cell should move with it`)
	assert(recordC.row == 1, `swapped entity's record row should be updated`)
end)

test(`moveEntity() drops the removed component column on remove`, function()
	local store = makeMoveStore()

	local archBoth = Archetype.traverseAdd(store, Archetype.traverseAdd(store, store._root, HEALTH), POSITION)
	local record = place(store, archBoth, 3001, { [HEALTH] = 7, [POSITION] = 99 })

	local archHealth = Archetype.traverseRemove(store, archBoth, POSITION)
	Archetype.moveEntity(store, 3001, record, archHealth)

	assert(record.archetype == archHealth, `record should point at the reduced archetype`)
	assert(archHealth.columnsMap[HEALTH][record.row] == 7, `retained HEALTH data should transfer`)
	assert(archHealth.columnsMap[POSITION] == nil, `destination should not have a POSITION column`)
	assert(archBoth.columnsMap[POSITION][1] == nil, `source POSITION cell should be cleared`)
end)

test(`moveEntity() caches the transfer plan on the source archetype edge`, function()
	local store = makeMoveStore()

	local archHealth = Archetype.traverseAdd(store, store._root, HEALTH)
	local archBoth = Archetype.traverseAdd(store, archHealth, POSITION)

	local recordA = place(store, archHealth, 4001, { [HEALTH] = 1 })
	Archetype.moveEntity(store, 4001, recordA, archBoth)

	local plan = archHealth.movePlans[archBoth.id]
	assert(plan ~= nil, `a move plan should be cached under the destination id`)
	assert(plan.copyCount == 1, `plan should record exactly one column to copy (HEALTH)`)

	local recordB = place(store, archHealth, 4002, { [HEALTH] = 2 })
	Archetype.moveEntity(store, 4002, recordB, archBoth)
	assert(archHealth.movePlans[archBoth.id] == plan, `second move should reuse the cached plan object`)
end)

test(`ensure() and appendEntity() support direct final-archetype placement`, function()
	local store = makeStore()
	local destination = Archetype.ensure(store, { HEALTH, POSITION })
	local entity = 5001

	local row = Archetype.appendEntity(destination, entity)
	destination.columnsMap[HEALTH][row] = 70
	destination.columnsMap[POSITION][row] = 90

	assert(#store._root.entities == 0, `direct placement should leave no entity in the root archetype`)
	assert(
		#destination.entities == 1 and destination.entities[1] == entity,
		`destination should contain the entity once`
	)
	assert(destination.columnsMap[HEALTH][row] == 70, `Health data should align with the appended row`)
	assert(destination.columnsMap[POSITION][row] == 90, `Position data should align with the appended row`)
end)

test(`compiled patch moves once to one final destination`, function()
	Component._reset()

	local a = Component.define(`PatchArchA`, { value = 0 })
	local b = Component.define(`PatchArchB`, { value = 0 })
	local c = Component.define(`PatchArchC`, { value = 0 })
	local d = Component.define(`PatchArchD`, { value = 0 })
	local store = Entity.new()
	local id = store:spawn()
	store:add(id, a.id, { value = 1 })
	store:add(id, b.id, { value = 2 })

	local source = store:recordOfAny(id).archetype
	local patch = store:patch({ remove = { b.id }, add = { c.id, d.id } })
	local moveCount = 0
	local originalMoveEntity = Archetype.moveEntity
	Archetype.moveEntity = function(...: any): ()
		moveCount += 1
		originalMoveEntity(...)
	end
	local mutateOk, mutateError = pcall(function()
		store:mutate(id, patch, { value = 3 }, { value = 4 })
	end)
	Archetype.moveEntity = originalMoveEntity
	assert(mutateOk, tostring(mutateError))
	local destination = store:recordOfAny(id).archetype

	assert(moveCount == 1, `compiled patch should call Archetype.moveEntity exactly once`)
	assert(destination ~= source, `patch should leave the source archetype`)
	assert(#source.entities == 0, `patch should remove the entity from its source once`)
	assert(
		#destination.entities == 1 and destination.entities[1] == id,
		`final destination should contain the entity once`
	)
	assert(destination.columnsMap[b.id] == nil, `final destination should omit removed components`)
	assert(
		destination.columnsMap[c.id] ~= nil and destination.columnsMap[d.id] ~= nil,
		`final destination should contain every addition`
	)
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
