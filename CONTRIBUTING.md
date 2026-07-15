# Contributing

Open an issue before a large API or storage change. Keep pull requests focused
on one concern, preserve the public/private module boundary, and add a paired
spec for every behavior change.

Before submitting:

```sh
wally install
stylua --check src tests examples bench
selene src tests examples bench
rojo build default.project.json -o build.rbxlx
lune run tests/run-all.luau
```

Benchmark changes must run both VZNCore and the exact locked jecs version through
equivalent workloads. Include raw samples and describe results per workload.
Do not commit generated packages, place files, source maps, or result JSON.
