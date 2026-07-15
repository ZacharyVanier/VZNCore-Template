local Harness = require("../../bench/harness")

local calls = 0
local samples = Harness.collect(function()
	calls += 1
	return calls
end, 2, 3)

assert(calls == 5, "collect should execute warm-up and measured passes")
assert(#samples == 3, "warm-up samples must be excluded")
assert(samples[1] == 3 and samples[3] == 5, "only post-warm-up samples should be retained")

local summary = Harness.summarize({ 9, 1, 5, 3, 7 })
assert(summary.median == 5, "median should be deterministic")
assert(summary.p95 == 9, "p95 should use the nearest-rank percentile")
assert(summary.raw[1] == 1 and summary.raw[5] == 9, "summary should preserve sorted raw samples")

local missingOk = pcall(function()
	Harness.compare({
		name = "missing",
		vzn = function()
			return 1
		end,
	}, 0, 1)
end)
assert(missingOk == false, "missing comparison implementation must fail closed")
