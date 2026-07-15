# Static analysis status

`luau-lsp analyze` is not currently a release gate for this extraction. The
runtime supports both Roblox `ModuleScript` paths and Lune-relative paths through
a small dynamic require adapter. Luau LSP cannot resolve the imported type tables
through that adapter, so a whole-source analysis produces unresolved type-family
errors even though the runtime specifications pass.

The CI gate is intentionally limited to formatting, Selene, a Rojo build, and the
full Lune specification suite until the import boundary is made statically
resolvable in both environments. Do not describe the repository as fully
`luau-lsp` clean until that gate is restored and passing.
