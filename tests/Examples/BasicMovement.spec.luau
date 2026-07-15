local Example = require("../../examples/basic-movement")
local result = Example.run()

assert(result.entityCount == 2, "movement example should update two entities")
assert(result.firstX == 4, "first entity should integrate velocity over two seconds")
assert(result.secondY == 9, "second entity should integrate its vertical velocity")
