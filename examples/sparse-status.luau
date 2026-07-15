-- Sparse status churn without archetype migration.
local VZNCore = require("../src/_Facade")

local Example = {}

function Example.run()
	local Stunned = VZNCore.Component.define("ExampleStunned", { active = true }, { sparse = true })
	local Attacking = VZNCore.Component.define("ExampleAttacking", { active = true }, { sparse = true })
	local IFrame = VZNCore.Component.define("ExampleIFrame", { active = true }, { sparse = true })
	local world = VZNCore.World.new()
	local entity = world:spawn()

	world:addComponent(entity, Stunned, { active = true })
	world:addComponent(entity, Attacking, { active = true })
	world:addComponent(entity, IFrame, { active = true })
	world:removeComponent(entity, Attacking)
	world:removeComponent(entity, Stunned)

	local result = {
		alive = world:isAlive(entity),
		stunned = world:hasComponent(entity, Stunned),
		iframe = world:hasComponent(entity, IFrame),
	}
	world:destroy()
	return result
end

return Example
