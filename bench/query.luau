-- Query-heavy comparisons with identical entity/component shapes.
local Harness = require("./harness")
local VZNCore = require("../src/_Facade")
local jecs = require("../DevPackages/_Index/ukendio_jecs@0.5.3/jecs/jecs")

local ENTITY_COUNT = 21_000
local ARCHETYPE_COUNT = 125
local unique = 0

local A = VZNCore.Component.define("BenchQueryA", { value = 1 })
local B = VZNCore.Component.define("BenchQueryB", { value = 2 })
local C = VZNCore.Component.define("BenchQueryC", { value = 3 })
local D = VZNCore.Component.define("BenchQueryD", { value = 4 })
local markers = {}
for index = 1, 7 do
	markers[index] = VZNCore.Component.tag("BenchQueryMarker" .. index)
end

local vWorld = VZNCore.World.new()
for index = 1, ENTITY_COUNT do
	local entity = vWorld:spawn()
	vWorld:addComponent(entity, A, { value = index })
	vWorld:addComponent(entity, B, { value = 2 })
	vWorld:addComponent(entity, C, { value = 3 })
	vWorld:addComponent(entity, D, { value = 4 })
	local shape = (index - 1) % ARCHETYPE_COUNT
	for bit = 1, 7 do
		if bit32.band(shape, bit32.lshift(1, bit - 1)) ~= 0 then
			vWorld:addComponent(entity, markers[bit])
		end
	end
end
local vQuery = VZNCore.Query.all(A, B, C, D):cached()

local jWorld = jecs.World.new()
local jA, jB, jC, jD = jWorld:component(), jWorld:component(), jWorld:component(), jWorld:component()
local jMarkers = {}
for index = 1, 7 do
	jMarkers[index] = jWorld:component()
end
for index = 1, ENTITY_COUNT do
	local entity = jWorld:entity()
	jWorld:set(entity, jA, { value = index })
	jWorld:set(entity, jB, { value = 2 })
	jWorld:set(entity, jC, { value = 3 })
	jWorld:set(entity, jD, { value = 4 })
	local shape = (index - 1) % ARCHETYPE_COUNT
	for bit = 1, 7 do
		if bit32.band(shape, bit32.lshift(1, bit - 1)) ~= 0 then
			jWorld:add(entity, jMarkers[bit])
		end
	end
end
local jQuery = jWorld:query(jA, jB, jC, jD):cached()

local function vznQuery()
	return Harness.time(function()
		local checksum = 0
		for _entity, a in vWorld:query(vQuery) do
			checksum += a.value
		end
		return checksum
	end)
end

local function jecsQuery()
	return Harness.time(function()
		local checksum = 0
		for _entity, a in jQuery do
			checksum += a.value
		end
		return checksum
	end)
end

local function vznInsertion()
	unique += 1
	return Harness.time(function()
		local world = VZNCore.World.new()
		local components = {}
		for index = 1, 8 do
			components[index] = VZNCore.Component.define("BenchInsertV" .. unique .. "_" .. index, { value = 0 })
		end
		local entity = world:spawn()
		for _, component in components do
			world:addComponent(entity, component, { value = 0 })
		end
		for update = 1, 50 do
			world:set(entity, components[(update - 1) % 8 + 1], { value = update })
		end
		local checksum = world:get(entity, components[2]).value
		world:destroy()
		return checksum
	end)
end

local function jecsInsertion()
	return Harness.time(function()
		local world = jecs.World.new()
		local components = {}
		for index = 1, 8 do
			components[index] = world:component()
		end
		local entity = world:entity()
		for _, component in components do
			world:set(entity, component, { value = 0 })
		end
		for update = 1, 50 do
			world:set(entity, components[(update - 1) % 8 + 1], { value = update })
		end
		return world:get(entity, components[2]).value
	end)
end

local function vznHot()
	return Harness.time(function()
		local checksum = 0
		for _ = 1, 20 do
			for _entity, a in vWorld:query(vQuery) do
				checksum += a.value
			end
		end
		return checksum
	end)
end

local function jecsHot()
	return Harness.time(function()
		local checksum = 0
		for _ = 1, 20 do
			for _entity, a in jQuery do
				checksum += a.value
			end
		end
		return checksum
	end)
end

return {
	{ name = "four-component query (21k / 125 archetypes)", vzn = vznQuery, jecs = jecsQuery },
	{ name = "eight-component insertion plus 50 updates", vzn = vznInsertion, jecs = jecsInsertion },
	{ name = "cached hot query (20 passes)", vzn = vznHot, jecs = jecsHot },
}
