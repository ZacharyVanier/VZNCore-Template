# Public API

## Components and queries

- `Component.define(name, defaults, options?)` creates a typed data handle.
- `Component.tag(name)` creates a tag handle.
- Options support `replicated`, `singleton`, `sparse`, and `unboxed`.
- `Component.Pair(relation, target)` creates a packed relationship ID.
- `Query.all/any/none/select(...)` build immutable filters;
  `:cached()` caches archetype matches.

## Worlds

`World.new()` creates an isolated world. Core operations are `spawn`,
`despawn`, `isAlive`, `addComponent`, `get`, `set`,
`removeComponent`, `hasComponent`, `query`, `target`, and
`setRelationTrait`.

Worlds also own singletons, observers, prefabs, bound Instance cleanup, phased
systems, pause/resume, manual fragmentation sweeps, and lifecycle destruction.
Invalid entity/component operations fail with actionable assertions.

## Systems, prefabs, and debugging

`System.new(name, config)` validates a phase, optional priority/query, and run
callback. A system error is isolated; ten consecutive failures disable that
system until explicitly re-enabled.

`Prefab.define`, `getDefinition`, and `isDefined` manage reusable component
bundles. `world:spawnPrefab(definition)` constructs one.

`Debugger.enable()` activates runtime lints and timing collection. Inspection,
archetype census, and timing-report methods are read-only public diagnostics.
