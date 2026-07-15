local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Harness = require("./harness")

local WARMUPS = 2
local SAMPLES = 7
local scenarios = {}
for _, moduleName in { "query", "churn", "relationships", "lifecycle" } do
	for _, scenario in require("./" .. moduleName) do
		table.insert(scenarios, scenario)
	end
end
assert(#scenarios == 6, "all six approved workloads must be present")

local results = {}
print("VZNCore vs jecs 0.5.3 (milliseconds; lower is better)")
for _, scenario in scenarios do
	local result = Harness.compare(scenario, WARMUPS, SAMPLES)
	table.insert(results, result)
	print(
		string.format(
			"%-48s VZN %8.3f  jecs %8.3f  ratio %6.3fx",
			result.name,
			result.vzn.median,
			result.jecs.median,
			result.ratio
		)
	)
end

local luneVersion = process.exec("lune", { "--version" }).stdout:gsub("%s+$", "")
local payload = {
	metadata = {
		timestampUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		luneVersion = luneVersion,
		operatingSystem = process.env.OS or "unknown",
		cpu = process.env.PROCESSOR_IDENTIFIER or "unknown",
		sampleCount = SAMPLES,
		warmupCount = WARMUPS,
		gcPolicy = "runtime default; no explicit GC inside timed callbacks",
		entityCount = 21_000,
		archetypeCount = 125,
		jecsVersion = "0.5.3",
	},
	results = results,
}
fs.writeFile("bench/results/latest.json", serde.encode("json", payload, true))
print("Raw results written to bench/results/latest.json")
