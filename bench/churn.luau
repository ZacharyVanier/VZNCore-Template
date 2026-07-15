local Harness = require("./harness")
local VZNCore = require("../src/_Facade")
local jecs = require("../DevPackages/_Index/ukendio_jecs@0.5.3/jecs/jecs")

local COUNT = 5_000
local Status = VZNCore.Component.define("BenchSparseStatus", { active = true }, { sparse = true })
local vWorld = VZNCore.World.new()
local vEntities = {}
for index = 1, COUNT do
	vEntities[index] = vWorld:spawn()
end

local jWorld = jecs.World.new()
local jStatus = jWorld:component()
local jEntities = {}
for index = 1, COUNT do
	jEntities[index] = jWorld:entity()
end

return {
	{
		name = "sparse/tag add-remove churn",
		vzn = function()
			return Harness.time(function()
				for _, entity in vEntities do
					vWorld:addComponent(entity, Status, { active = true })
					vWorld:removeComponent(entity, Status)
				end
				return #vEntities
			end)
		end,
		jecs = function()
			return Harness.time(function()
				for _, entity in jEntities do
					jWorld:add(entity, jStatus)
					jWorld:remove(entity, jStatus)
				end
				return #jEntities
			end)
		end,
	},
}
