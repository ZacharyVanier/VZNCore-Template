local Example = require("../../examples/relationships")
local result = Example.run()

assert(result.targetFound == true, "relation target lookup should resolve the target")
assert(result.wildcardMatches == 1, "wildcard pair query should find the holder")
assert(result.childCascaded == true, "ChildOf cleanup should cascade on parent despawn")
