--[[
	_Facade -- exposes the curated public VZNCore package boundary.
	VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» DEPENDENCIES & VARIABLES «--

local Engine = if script then script.Parent.Engine else nil
local WorldRuntime = require(if Engine then Engine.World else "./Engine/World")
local ComponentRuntime = require(if Engine then Engine.Component else "./Engine/Component")
local QueryRuntime = require(if Engine then Engine.Query else "./Engine/Query")
local SystemRuntime = require(if Engine then Engine.System else "./Engine/System")
local PrefabRuntime = require(if Engine then Engine.Prefab else "./Engine/Prefab")
local DebuggerRuntime = require(if Engine then Engine.Debugger else "./Engine/Debugger")
local ECSTypes = require(if Engine then Engine.Types else "./Engine/Types")

--» TYPE DEFINITIONS «--

export type Entity = ECSTypes.Entity
export type Phase = ECSTypes.Phase
export type Component<T> = ECSTypes.Component<T>
export type ComponentRef<T> = ECSTypes.ComponentRef<T>
export type ComponentOptions = ECSTypes.ComponentOptions
export type Query = ECSTypes.Query
export type PrefabEntry = ECSTypes.PrefabEntry
export type PrefabDefinition = ECSTypes.PrefabDefinition
export type SystemConfig = ECSTypes.SystemConfig
export type SystemDefinition = ECSTypes.SystemDefinition
export type RelationTrait = ECSTypes.RelationTrait
export type World = WorldRuntime.World

export type ComponentModule = {
	Wildcard: number,
	ChildOf: number,
	define: <T>(string, T, ComponentOptions?) -> Component<T>,
	tag: (string) -> Component<nil>,
	Pair: (ComponentRef<unknown>, ComponentRef<unknown>) -> number,
	isPair: (number) -> boolean,
	pairFirst: (number) -> number,
	pairSecond: (number) -> number,
	idOf: (string) -> number,
	toId: (ComponentRef<unknown>) -> number,
	nameOf: (number) -> string?,
	lowId: (number) -> number,
	getDefinition: (string) -> ECSTypes.ComponentDefinition?,
	getHandle: (string) -> Component<unknown>?,
	createInstance: (string, unknown?) -> unknown,
	isDefined: (string) -> boolean,
	isTag: (string) -> boolean,
	getReplicatedNames: () -> { string },
	isReplicated: (string) -> boolean,
	isSparse: (string) -> boolean,
	isUnboxed: (number) -> boolean,
	isSingleton: (string) -> boolean,
}

export type QueryModule = {
	all: (...ComponentRef<unknown>) -> Query,
	any: (...ComponentRef<unknown>) -> Query,
	none: (...ComponentRef<unknown>) -> Query,
	select: (...ComponentRef<unknown>) -> Query,
}

export type DebuggerModule = {
	enable: () -> (),
	disable: () -> (),
	isEnabled: () -> boolean,
	describeComponent: (ComponentRef<unknown>) -> string,
	inspectEntity: (World, Entity) -> DebuggerRuntime.EntityInspection,
	dumpEntity: (World, Entity) -> string,
	archetypeCensus: (World) -> DebuggerRuntime.ArchetypeCensus,
	dumpArchetypes: (World) -> string,
	systemTimingReport: () -> { DebuggerRuntime.SystemTiming },
	dumpSystemTimings: () -> string,
}

export type VZNCore = {
	World: WorldRuntime.WorldModule,
	Component: ComponentModule,
	Query: QueryModule,
	System: SystemRuntime.SystemModule,
	Prefab: PrefabRuntime.PrefabModule,
	Debugger: DebuggerModule,
}

--» PUBLIC FACADE «--

-- The wrappers prevent test-only resets and internal lints from becoming supported API.
local PublicComponent = (
	table.freeze({
		Wildcard = ComponentRuntime.Wildcard,
		ChildOf = ComponentRuntime.ChildOf,
		define = ComponentRuntime.define,
		tag = ComponentRuntime.tag,
		Pair = ComponentRuntime.Pair,
		isPair = ComponentRuntime.isPair,
		pairFirst = ComponentRuntime.pairFirst,
		pairSecond = ComponentRuntime.pairSecond,
		idOf = ComponentRuntime.idOf,
		toId = ComponentRuntime.toId,
		nameOf = ComponentRuntime.nameOf,
		lowId = ComponentRuntime.lowId,
		getDefinition = ComponentRuntime.getDefinition,
		getHandle = ComponentRuntime.getHandle,
		createInstance = ComponentRuntime.createInstance,
		isDefined = ComponentRuntime.isDefined,
		isTag = ComponentRuntime.isTag,
		getReplicatedNames = ComponentRuntime.getReplicatedNames,
		isReplicated = ComponentRuntime.isReplicated,
		isSparse = ComponentRuntime.isSparse,
		isUnboxed = ComponentRuntime.isUnboxed,
		isSingleton = ComponentRuntime.isSingleton,
	}) :: unknown
) :: ComponentModule

local PublicQuery = (
	table.freeze({
		all = QueryRuntime.all,
		any = QueryRuntime.any,
		none = QueryRuntime.none,
		select = QueryRuntime.select,
	}) :: unknown
) :: QueryModule

local PublicWorld = (
	table.freeze({
		Pair = WorldRuntime.Pair,
		ChildOf = WorldRuntime.ChildOf,
		Wildcard = WorldRuntime.Wildcard,
		new = WorldRuntime.new,
	}) :: unknown
) :: WorldRuntime.WorldModule

local PublicSystem = (
	table.freeze({
		PHASE_ORDER = table.freeze(table.clone(SystemRuntime.PHASE_ORDER)),
		isValidPhase = SystemRuntime.isValidPhase,
		new = SystemRuntime.new,
	}) :: unknown
) :: SystemRuntime.SystemModule

local PublicPrefab = (
	table.freeze({
		define = PrefabRuntime.define,
		getDefinition = PrefabRuntime.getDefinition,
		isDefined = PrefabRuntime.isDefined,
	}) :: unknown
) :: PrefabRuntime.PrefabModule

local PublicDebugger = (
	table.freeze({
		enable = DebuggerRuntime.enable,
		disable = DebuggerRuntime.disable,
		isEnabled = DebuggerRuntime.isEnabled,
		describeComponent = DebuggerRuntime.describeComponent,
		inspectEntity = DebuggerRuntime.inspectEntity,
		dumpEntity = DebuggerRuntime.dumpEntity,
		archetypeCensus = DebuggerRuntime.archetypeCensus,
		dumpArchetypes = DebuggerRuntime.dumpArchetypes,
		systemTimingReport = DebuggerRuntime.systemTimingReport,
		dumpSystemTimings = DebuggerRuntime.dumpSystemTimings,
	}) :: unknown
) :: DebuggerModule

local PublicFacade = table.freeze({
	World = PublicWorld,
	Component = PublicComponent,
	Query = PublicQuery,
	System = PublicSystem,
	Prefab = PublicPrefab,
	Debugger = PublicDebugger,
}) :: VZNCore

--» MODULE EXPORT «--

return PublicFacade
