# VZNCore

VZNCore is a batteries-included Entity Component System runtime for Roblox. It
combines archetype and sparse storage with cached queries, relationships,
prefabs, phased systems, failure isolation, debugging, observers, and
Instance-bound cleanup. The runtime has no external production dependency.

This repository is a standalone public template. It contains the ECS engine,
neutral examples, specifications, and a reproducible jecs comparison—not the
private client/server framework, utilities, networking, game code, or assets.

## Quick start

Install the pinned tools and development packages:

```sh
rokit install
wally install
```

Sync `default.project.json` with Rojo. In Roblox, import the package root:

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VZNCore = require(ReplicatedStorage.VZNCore)

local Position = VZNCore.Component.define("Position", { x = 0, y = 0 })
local Velocity = VZNCore.Component.define("Velocity", { x = 0, y = 0 })
local world = VZNCore.World.new()
local entity = world:spawn()

world:addComponent(entity, Position, { x = 10, y = 5 })
world:addComponent(entity, Velocity, { x = 2, y = 0 })

for _, position, velocity in world:query(VZNCore.Query.all(Position, Velocity):cached()) do
	position.x += velocity.x
	position.y += velocity.y
end
```

## Included examples

- `examples/basic-movement.luau`: cached movement iteration.
- `examples/sparse-status.luau`: sparse status churn.
- `examples/relationships.luau`: pairs, wildcard matching, and cleanup.
- `examples/scheduler-debugging.luau`: phases, pause/resume, circuit breaking,
  and timing.
- `examples/prefab-cleanup.luau`: prefab construction and bound-resource
  destruction.

Run `lune run tests/run-all.luau` for the full suite and
`lune run bench/run-all.luau` for the local comparison. See
[API](docs/api.md), [architecture](docs/architecture.md), and
[comparison methodology](docs/comparison-methodology.md).

## Positioning and limits

VZNCore is designed as a production-oriented, batteries-included ECS. jecs is
also a capable archetype ECS and already supports relationships, pairs, hooks,
cached queries, and cleanup traits. The checked-in harness reports
workload-specific results and does not establish that either runtime is
universally faster.

Whole-source `luau-lsp analyze` is a documented tooling limitation because the
dual Roblox/Lune require adapter prevents imported type-family resolution. It
does not block runtime publication, but VZNCore is not advertised as fully
`luau-lsp` clean or more type-safe than jecs. See
[static analysis status](docs/static-analysis.md).

## License

MIT. See [LICENSE](LICENSE).
