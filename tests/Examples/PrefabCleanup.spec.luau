local Example = require("../../examples/prefab-cleanup")
local result = Example.run()

assert(result.health == 150, "prefab overrides should be applied")
assert(result.destroyed == true, "despawn should destroy the bound resource")
assert(result.alive == false, "despawned prefab entity should be dead")
