local Harness = require("./harness")
local VZNCore = require("../src/_Facade")
local jecs = require("../DevPackages/_Index/ukendio_jecs@0.5.3/jecs/jecs")

local COUNT = 2_000
local unique = 0

local function vznPass()
	unique += 1
	return Harness.time(function()
		local Follows = VZNCore.Component.tag("BenchFollows" .. unique)
		local Marker = VZNCore.Component.define("BenchRelationMarker" .. unique, { value = 1 })
		local world = VZNCore.World.new()
		local target = world:spawn()
		for _ = 1, COUNT do
			local entity = world:spawn()
			world:addComponent(entity, Marker, { value = 1 })
			world:addComponent(entity, VZNCore.Component.Pair(Follows, target))
		end
		local query = VZNCore.Query.all(VZNCore.Component.Pair(Follows, VZNCore.Component.Wildcard)):select(Marker)
		local compiled = world:compile(query)
		local matches = 0
		for _entity in compiled do
			matches += 1
		end
		compiled:destroy()
		world:despawn(target)
		world:destroy()
		return matches
	end)
end

local function jecsPass()
	return Harness.time(function()
		local world = jecs.World.new()
		local follows = world:component()
		local marker = world:component()
		local target = world:entity()
		for _ = 1, COUNT do
			local entity = world:entity()
			world:set(entity, marker, { value = 1 })
			world:add(entity, jecs.pair(follows, target))
		end
		local query = world:query(marker):with(jecs.pair(follows, jecs.Wildcard)):cached()
		local matches = 0
		for _entity in query do
			matches += 1
		end
		world:delete(target)
		return matches
	end)
end

return { { name = "pair wildcard lookup and cleanup", vzn = vznPass, jecs = jecsPass } }
