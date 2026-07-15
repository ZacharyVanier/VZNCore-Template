local Harness = require("./harness")
local VZNCore = require("../src/_Facade")
local jecs = require("../DevPackages/_Index/ukendio_jecs@0.5.3/jecs/jecs")

local COUNT = 5_000

return {
	{
		name = "spawn/despawn recycling",
		vzn = function()
			return Harness.time(function()
				local world = VZNCore.World.new()
				local entities = {}
				for index = 1, COUNT do
					entities[index] = world:spawn()
				end
				for _, entity in entities do
					world:despawn(entity)
				end
				world:destroy()
				return #entities
			end)
		end,
		jecs = function()
			return Harness.time(function()
				local world = jecs.World.new()
				local entities = {}
				for index = 1, COUNT do
					entities[index] = world:entity()
				end
				for _, entity in entities do
					world:delete(entity)
				end
				return #entities
			end)
		end,
	},
}
