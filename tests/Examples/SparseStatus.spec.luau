local Example = require("../../examples/sparse-status")
local result = Example.run()

assert(result.alive == true, "sparse churn must not despawn the entity")
assert(result.stunned == false, "removed sparse status should be absent")
assert(result.iframe == true, "remaining sparse status should stay attached")
