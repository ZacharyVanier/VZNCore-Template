-- Phased scheduling, pause/resume, circuit breaking, and timing inspection.
local VZNCore = require("../src/_Facade")

local Example = {}

function Example.run()
	VZNCore.Debugger.enable()
	local world = VZNCore.World.new()
	local healthyRuns = 0
	local broken = VZNCore.System.new("ExampleBroken", {
		phase = "Update",
		priority = 1,
		run = function()
			error("intentional example failure")
		end,
	})
	local healthy = VZNCore.System.new("ExampleHealthy", {
		phase = "Update",
		priority = 2,
		run = function()
			healthyRuns += 1
		end,
	})
	world:addSystems({ broken, healthy })

	for _ = 1, 10 do
		world:step(1 / 60)
	end
	local brokenDisabled = not world:isSystemEnabled("ExampleBroken")
	world:pause()
	world:step(1 / 60)
	local pausedSkipped = healthyRuns == 10
	world:resume()
	world:step(1 / 60)
	world:step(1 / 60)
	local timingRows = #VZNCore.Debugger.systemTimingReport()
	world:destroy()
	VZNCore.Debugger.disable()

	return {
		healthyRuns = healthyRuns,
		brokenDisabled = brokenDisabled,
		pausedSkipped = pausedSkipped,
		timingRows = timingRows,
	}
end

return Example
