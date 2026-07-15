-- Cached movement query using only the supported VZNCore facade.
local VZNCore = require("../src/_Facade")

local Example = {}

function Example.run()
	local Position = VZNCore.Component.define("ExamplePosition", { x = 0, y = 0 })
	local Velocity = VZNCore.Component.define("ExampleVelocity", { x = 0, y = 0 })
	local world = VZNCore.World.new()
	local first = world:spawn()
	local second = world:spawn()

	world:addComponent(first, Position, { x = 0, y = 0 })
	world:addComponent(first, Velocity, { x = 2, y = 0 })
	world:addComponent(second, Position, { x = 1, y = 3 })
	world:addComponent(second, Velocity, { x = 0, y = 3 })

	local movement = VZNCore.Query.all(Position, Velocity):cached()
	local entityCount = 0
	for _entity, position, velocity in world:query(movement) do
		position.x += velocity.x * 2
		position.y += velocity.y * 2
		entityCount += 1
	end

	local firstPosition = world:get(first, Position)
	local secondPosition = world:get(second, Position)
	local result = {
		entityCount = entityCount,
		firstX = firstPosition.x,
		secondY = secondPosition.y,
	}
	world:destroy()
	return result
end

return Example
