# ECS engine system

## Purpose

VZNCore provides one standalone, zero-runtime-dependency ECS engine for Roblox.
The public facade keeps storage internals replaceable while offering the
production features normally assembled around a smaller ECS core.

## Design rationale

Dense archetypes make stable query iteration predictable and cache-friendly.
Sparse storage avoids archetype migration for short-lived statuses. Packed pairs
give relationships the same membership/query path as components. The scheduler,
prefabs, debugger, observers, and cleanup bindings live beside the storage
engine so callers share one lifecycle and failure policy.

The engine supports Roblox ModuleScript paths and Lune-relative paths to keep
tests and benchmarks standalone. That compatibility adapter is also the reason
whole-source Luau LSP analysis cannot currently resolve imported type families.

## Gotchas

- Component and prefab registries are process-global; names must be unique.
- Sparse filters are evaluated per entity and cannot be compiled.
- Streaming a wildcard pair directly has no concrete data column; project a
  concrete component with a compiled query.
- Empty archetypes persist until `world:sweep()`.
- Bound resources are destroyed only when they still have a non-nil `Parent`.

## Current state

The canonical thirteen ECS specs, facade spec, five paired example specs, and
benchmark harness spec pass. Selene, StyLua, and Rojo build gates pass. The
comparison harness completes all six VZNCore/jecs 0.5.3 workloads and preserves
raw samples, median, and p95. Full-source `luau-lsp` analysis remains a known
dual-environment tooling limitation, so the project makes no `luau-lsp`-clean or
type-safety superiority claim. The publishable `main` history is one sanitized
root commit with no internal planning or proprietary framework paths.
