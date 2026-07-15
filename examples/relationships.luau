-- Pair lookup, wildcard matching, and cascading ChildOf cleanup.
local VZNCore = require("../src/_Facade")

local Example = {}

function Example.run()
	local Follows = VZNCore.Component.tag("ExampleFollows")
	local Identity = VZNCore.Component.define("ExampleRelationshipIdentity", { label = "" })
	local world = VZNCore.World.new()
	local target = world:spawn()
	local holder = world:spawn()
	local parent = world:spawn()
	local child = world:spawn()

	world:addComponent(holder, VZNCore.Component.Pair(Follows, target))
	world:addComponent(holder, Identity, { label = "holder" })
	world:addComponent(child, VZNCore.Component.Pair(VZNCore.Component.ChildOf, parent))

	local wildcardMatches = 0
	local wildcard = VZNCore.Query.all(VZNCore.Component.Pair(Follows, VZNCore.Component.Wildcard)):select(Identity)
	local compiled = world:compile(wildcard)
	for _entity, _identity in compiled do
		wildcardMatches += 1
	end
	compiled:destroy()

	local targetFound = world:target(holder, Follows) == target
	world:despawn(parent)
	local childCascaded = not world:isAlive(child)
	world:destroy()

	return {
		targetFound = targetFound,
		wildcardMatches = wildcardMatches,
		childCascaded = childCascaded,
	}
end

return Example
