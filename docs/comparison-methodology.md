# Comparison methodology

The benchmark suite compares VZNCore with exactly `ukendio/jecs@0.5.3` in the
same Lune process and on the same machine. Each scenario implements the same
entity count, component shape, and logical operation in both runtimes. Two
warm-up passes are discarded, followed by seven recorded passes. Results include
sorted raw samples, median, p95, environment metadata, and the median ratio.

Run `wally install`, then `lune run bench/run-all.luau`. The working result is
written to `bench/results/latest.json` and is intentionally ignored by Git.

The six workloads cover a four-component query over 21,000 entities and 125
archetypes, eight-component insertion plus 50 updates, a cached hot query,
sparse/tag churn, pair wildcard lookup and cleanup, and spawn/despawn recycling.
They do not establish universal superiority. A ratio above 1 means VZNCore was
faster only for that measured workload and environment; below 1 means jecs was
faster. Features shared by both runtimes are not presented as unique.
