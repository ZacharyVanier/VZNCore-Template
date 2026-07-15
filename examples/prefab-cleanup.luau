-- Prefab construction with deterministic bound-resource cleanup.
local VZNCore = require("../src/_Facade")

local Example = {}

function Example.run()
	local Health = VZNCore.Component.define("ExamplePrefabHealth", { current = 100 })
	VZNCore.Prefab.define("ExampleGuard", {
		{ Health.name, { current = 150 } },
	})
	local prefab = VZNCore.Prefab.getDefinition("ExampleGuard")
	assert(prefab, "registered prefab should be available")

	local world = VZNCore.World.new()
	local entity = world:spawnPrefab(prefab)
	local destroyed = false
	world:bindInstance(entity, {
		Parent = true,
		Destroy = function()
			destroyed = true
		end,
	})
	local health = world:get(entity, Health)
	world:despawn(entity)
	local result = {
		health = health.current,
		destroyed = destroyed,
		alive = world:isAlive(entity),
	}
	world:destroy()
	return result
end

return Example
