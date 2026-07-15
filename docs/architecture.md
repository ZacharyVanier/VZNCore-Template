# Architecture

`src/init.luau` is the supported Roblox package entry point. It delegates to a
frozen facade exposing `World`, `Component`, `Query`, `System`, `Prefab`,
and `Debugger`. Archetype, entity storage, cleanup, and observers remain
implementation modules under `src/Engine`.

Components receive stable numeric IDs. Dense component sets identify archetypes,
whose columns store component data contiguously. Sparse components live outside
archetypes so status churn does not move entities. Queries resolve handles to
IDs, cache matching archetypes when requested, and stream rows without
materializing entity arrays.

Pairs pack relation and target IDs. Wildcards match either half, exclusive
relations replace prior targets, and cleanup traits remove or recursively delete
holders when relation/target entities disappear. The built-in `ChildOf`
relation cascades child deletion.

Worlds own entities, systems, observers, singletons, cleanup bindings, and query
plans. Destroy compiled queries when finished and call `world:destroy()` when
the world is no longer used. Despawning an entity destroys its bound Instances
and fires removal observers.
