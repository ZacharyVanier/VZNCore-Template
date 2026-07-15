local Example = require("../../examples/scheduler-debugging")
local result = Example.run()

assert(result.healthyRuns == 12, "healthy system should survive isolated failures")
assert(result.brokenDisabled == true, "circuit breaker should disable repeated failures")
assert(result.pausedSkipped == true, "paused worlds should skip systems")
assert(result.timingRows >= 1, "debugger should retain system timing data")
