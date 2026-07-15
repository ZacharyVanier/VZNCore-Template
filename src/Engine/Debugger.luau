-- Debug logging, runtime lints and world inspection for ECS systems.
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

--##========== DEPENDENCIES ==========##--

local function tryRequire(robloxPath: any, relativePath: any): any
	local ok, result = pcall(function()
		return require(robloxPath)
	end)
	if ok then
		return result
	end
	return require(relativePath)
end

local Component = tryRequire(script and script.Parent and script.Parent.Component, "./Component")

--##========== TYPES ==========##--

type SystemLog = {
	name: string,
	executionTimeMs: number,
	entityCount: number,
}

export type SystemTiming = {
	name: string,
	totalMs: number,
	runs: number,
	maxMs: number,
	lastEntityCount: number,
}

export type EntityInspection = {
	id: number,
	alive: boolean,
	components: { [string]: any },
	tags: { string },
	pairs: { string },
	sparse: { [string]: any },
}

export type ArchetypeInfo = {
	id: number,
	signature: { string },
	entityCount: number,
}

export type ArchetypeCensus = {
	archetypeCount: number,
	entityCount: number,
	emptyCount: number,
	fragmentation: number,
	archetypes: { ArchetypeInfo },
}

--##========== PUBLIC API ==========##--

local Debugger = {}

Debugger._enabled = false
Debugger._systemLogs = {} :: { SystemLog }
Debugger._mutationCounts = {} :: { [string]: number }
Debugger._systemTimings = {} :: { [string]: SystemTiming }

function Debugger.enable(): ()
	Debugger._enabled = true
end

function Debugger.disable(): ()
	Debugger._enabled = false
end

function Debugger.isEnabled(): boolean
	return Debugger._enabled
end

-- Records one system run for both the per-frame flush and the cross-frame timing
-- report. Accumulation only happens in debug mode (the early return guards it).
function Debugger.logSystemRun(name: string, durationMs: number, entityCount: number): ()
	if not Debugger._enabled then
		return
	end

	table.insert(Debugger._systemLogs, {
		name = name,
		executionTimeMs = durationMs,
		entityCount = entityCount,
	})

	local timing = Debugger._systemTimings[name]
	if not timing then
		timing = { name = name, totalMs = 0, runs = 0, maxMs = 0, lastEntityCount = 0 }
		Debugger._systemTimings[name] = timing
	end

	timing.totalMs += durationMs
	timing.runs += 1
	timing.lastEntityCount = entityCount
	if durationMs > timing.maxMs then
		timing.maxMs = durationMs
	end
end

function Debugger.logMutation(componentName: string): ()
	if not Debugger._enabled then
		return
	end

	Debugger._mutationCounts[componentName] = (Debugger._mutationCounts[componentName] or 0) + 1
end

function Debugger.flush(frameNumber: number, systemCount: number, disabledCount: number, entityCount: number): ()
	if not Debugger._enabled then
		return
	end

	print(`[VZNCore Debug] Frame {frameNumber}`)
	print(`  Systems: {systemCount} active, {disabledCount} disabled`)
	print(`  Entities: {entityCount}`)

	for _, log in Debugger._systemLogs do
		print(`  [{log.name}] {string.format("%.2f", log.executionTimeMs)}ms | {log.entityCount} entities`)
	end

	for name, count in Debugger._mutationCounts do
		print(`  Mutations: {name} x{count}`)
	end

	table.clear(Debugger._systemLogs)
	table.clear(Debugger._mutationCounts)
end

--##========== RUNTIME LINTS ==========##--

-- Debug-mode guards that turn the storage layer's raw-id errors into readable,
-- name-based ones (the jecs runtime_lints spirit: names, never numeric ids).
-- World calls these ONLY behind `if Debugger._enabled`, so a disabled world
-- builds no strings and pays a single boolean check -- the guard is at the call
-- site, the cost is not.

-- Readable label for a component ref (name, handle, or packed id): a plain
-- component shows its registered name; a pair shows pair(Relation, Target) with
-- each side named where a name exists, else a slot/id fallback.
local function _describe(component: any): string
	local kind = type(component)

	local id: number
	if kind == "number" then
		id = component
	elseif kind == "table" then
		id = component.id
	else
		return component
	end

	if Component.isPair(id) then
		local relation = Component.pairFirst(id)
		local target = Component.pairSecond(id)
		local relationLabel = Component.nameOf(relation) or `id:{relation}`
		local targetLabel = Component.nameOf(target) or `entity:{target}`
		return `pair({relationLabel}, {targetLabel})`
	end

	return Component.nameOf(id) or `id:{id}`
end

function Debugger.describeComponent(component: any): string
	return _describe(component)
end

-- Raises a readable error if an accessed entity is not alive. A stale id means
-- its slot was recycled or its generation was bumped past the live value.
function Debugger.lintAlive(world: any, id: number, component: any, operation: string): ()
	if world:isAlive(id) then
		return
	end

	error(
		`[VZNCore Lint] {operation}("{_describe(component)}") on entity {id}, which is not alive (stale id -- its slot was recycled or its generation was bumped)`,
		3
	)
end

-- Raises if data is written to a tag component, naming the tag (or pair) rather
-- than the raw numeric id the storage-level assert would show.
function Debugger.lintTagWrite(component: any, componentId: number, data: any, operation: string): ()
	if data == nil then
		return
	end

	if not Component.isTagId(componentId) then
		return
	end

	error(`[VZNCore Lint] {operation}: "{_describe(component)}" is a tag and cannot store data`, 3)
end

-- Raises if a query carries zero component terms -- an empty query matches every
-- entity, almost always an accident. Names the owning system when known.
function Debugger.lintQuery(query: any, systemName: string?): ()
	if #query._all > 0 or #query._any > 0 or #query._none > 0 then
		return
	end

	local scope = if systemName then ` in system "{systemName}"` else ``
	error(`[VZNCore Lint] query{scope} has zero component terms and would match every entity`, 3)
end

--##========== WORLD INSPECTOR ==========##--

-- Shallow one-line rendering of a component data table for dumps.
local function _formatValue(value: any): string
	if type(value) ~= "table" then
		return tostring(value)
	end

	local parts: { string } = {}
	for key, inner in value do
		table.insert(parts, `{key}={tostring(inner)}`)
	end
	table.sort(parts)

	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Full component/tag/pair/sparse picture of one entity, names not ids. Reads the
-- store's public record surface, so it works anywhere -- Lune tests and the
-- Studio command bar alike.
function Debugger.inspectEntity(world: any, id: number): EntityInspection
	local store = world._entityStore

	local inspection: EntityInspection = {
		id = id,
		alive = world:isAlive(id),
		components = {},
		tags = {},
		pairs = {},
		sparse = {},
	}

	if not inspection.alive then
		return inspection
	end

	local record = store:recordOfAny(id)
	local archetype = record.archetype

	for _, typeId in archetype.types do
		if Component.isPair(typeId) then
			table.insert(inspection.pairs, _describe(typeId))
		elseif Component.isTagId(typeId) then
			table.insert(inspection.tags, Component.nameOf(typeId) or `id:{typeId}`)
		else
			local name = Component.nameOf(typeId)
			if name then
				inspection.components[name] = archetype.columnsMap[typeId][record.row]
			end
		end
	end

	for componentId, column in store._sparse do
		local data = column[id]
		if data ~= nil then
			local name = Component.nameOf(componentId)
			if name then
				inspection.sparse[name] = data
			end
		end
	end

	return inspection
end

function Debugger.dumpEntity(world: any, id: number): string
	local inspection = Debugger.inspectEntity(world, id)

	if not inspection.alive then
		return `Entity {id}: <not alive>`
	end

	local lines: { string } = { `Entity {id}:` }

	for name, value in inspection.components do
		table.insert(lines, `  {name} = {_formatValue(value)}`)
	end
	for _, tag in inspection.tags do
		table.insert(lines, `  [tag] {tag}`)
	end
	for _, pairLabel in inspection.pairs do
		table.insert(lines, `  [pair] {pairLabel}`)
	end
	for name, value in inspection.sparse do
		table.insert(lines, `  [sparse] {name} = {_formatValue(value)}`)
	end

	return table.concat(lines, "\n")
end

-- Per-archetype entity counts plus a fragmentation ratio (empty non-root
-- archetypes / total). Signatures are component names, pairs decoded.
function Debugger.archetypeCensus(world: any): ArchetypeCensus
	local store = world._entityStore

	local census: ArchetypeCensus = {
		archetypeCount = 0,
		entityCount = 0,
		emptyCount = 0,
		fragmentation = 0,
		archetypes = {},
	}

	for _, archetype in store._archetypes do
		local count = #archetype.entities

		local signature: { string } = {}
		for _, typeId in archetype.types do
			table.insert(signature, _describe(typeId))
		end

		table.insert(census.archetypes, {
			id = archetype.id,
			signature = signature,
			entityCount = count,
		})

		census.archetypeCount += 1
		census.entityCount += count

		if count == 0 and archetype ~= store._root then
			census.emptyCount += 1
		end
	end

	if census.archetypeCount > 0 then
		census.fragmentation = census.emptyCount / census.archetypeCount
	end

	return census
end

function Debugger.dumpArchetypes(world: any): string
	local census = Debugger.archetypeCensus(world)

	local header = string.format(
		"Archetype census: %d archetypes, %d entities, %d empty (fragmentation %.1f%%)",
		census.archetypeCount,
		census.entityCount,
		census.emptyCount,
		census.fragmentation * 100
	)

	local lines: { string } = { header }

	for _, info in census.archetypes do
		local label = if #info.signature > 0 then table.concat(info.signature, ", ") else "<root>"
		table.insert(lines, `  [{info.id}] {info.entityCount} ent | {label}`)
	end

	return table.concat(lines, "\n")
end

-- Accumulated per-system run timings since the last enable/_reset, sorted by
-- total time descending. Fed by Debugger.logSystemRun every World.step.
function Debugger.systemTimingReport(): { SystemTiming }
	local report: { SystemTiming } = {}

	for _, timing in Debugger._systemTimings do
		table.insert(report, timing)
	end

	table.sort(report, function(a: SystemTiming, b: SystemTiming): boolean
		return a.totalMs > b.totalMs
	end)

	return report
end

function Debugger.dumpSystemTimings(): string
	local report = Debugger.systemTimingReport()

	if #report == 0 then
		return `No system timings recorded (enable debug mode and step the world).`
	end

	local lines: { string } = { `System timing report (by total ms):` }

	for _, timing in report do
		local avg = if timing.runs > 0 then timing.totalMs / timing.runs else 0
		table.insert(
			lines,
			string.format(
				"  %-28s total %.2fms | avg %.4fms | max %.2fms | runs %d | last %d ent",
				timing.name,
				timing.totalMs,
				avg,
				timing.maxMs,
				timing.runs,
				timing.lastEntityCount
			)
		)
	end

	return table.concat(lines, "\n")
end

function Debugger._reset(): ()
	Debugger._enabled = false

	table.clear(Debugger._systemLogs)
	table.clear(Debugger._mutationCounts)
	table.clear(Debugger._systemTimings)
end

return Debugger
