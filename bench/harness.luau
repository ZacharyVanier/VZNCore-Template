-- Shared, fail-closed comparison harness.
local Harness = {}

local function nearestRank(sorted, fraction)
	local index = math.max(1, math.ceil(#sorted * fraction))
	return sorted[index]
end

function Harness.collect(work, warmupCount, sampleCount)
	assert(type(work) == "function", "benchmark implementation is required")
	assert(sampleCount > 0, "sample count must be positive")
	local samples = {}
	for _ = 1, warmupCount do
		work()
	end
	for _ = 1, sampleCount do
		table.insert(samples, work())
	end
	return samples
end

function Harness.summarize(samples)
	assert(#samples > 0, "cannot summarize an empty sample set")
	local sorted = table.clone(samples)
	table.sort(sorted)
	return {
		raw = sorted,
		median = nearestRank(sorted, 0.5),
		p95 = nearestRank(sorted, 0.95),
	}
end

function Harness.time(work)
	local started = os.clock()
	local checksum = work()
	local elapsed = (os.clock() - started) * 1000
	assert(checksum ~= nil, "workload must return a checksum")
	return math.max(elapsed, 0.000001)
end

function Harness.compare(scenario, warmupCount, sampleCount)
	assert(type(scenario.name) == "string", "comparison name is required")
	assert(type(scenario.vzn) == "function", scenario.name .. ": VZNCore implementation is required")
	assert(type(scenario.jecs) == "function", scenario.name .. ": jecs implementation is required")
	local vzn = Harness.summarize(Harness.collect(scenario.vzn, warmupCount, sampleCount))
	local jecsSummary = Harness.summarize(Harness.collect(scenario.jecs, warmupCount, sampleCount))
	return {
		name = scenario.name,
		vzn = vzn,
		jecs = jecsSummary,
		ratio = jecsSummary.median / vzn.median,
	}
end

return Harness
