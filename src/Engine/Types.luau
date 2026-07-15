-- ECS framework type definitions
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

export type Entity = number

export type Phase = "PreUpdate" | "Update" | "PostUpdate" | "PreRender" | "Render" | "PostRender"

export type ComponentOptions = {
	replicated: boolean?,
	singleton: boolean?,
	sparse: boolean?,
	unboxed: boolean?,
}

export type ComponentDefinition = {
	name: string,
	defaults: unknown,
	replicated: boolean?,
	singleton: boolean?,
	isTag: boolean?,
	sparse: boolean?,
	unboxed: boolean?,
}

export type ComponentMetadata = {
	name: string?,
	isTag: boolean,
	isSparse: boolean,
	isPair: boolean,
}

-- A typed component handle. `T` is the shape of the component's data (nil for
-- tags). `__data` is a phantom field: it exists only to carry `T` for static
-- typing and is never materialised at runtime -- handles are built by casting.
export type Component<T> = {
	id: number,
	name: string,
	isTag: boolean,
	__data: T,
}

-- Either a raw component name (string API) or a typed handle (new API). Both
-- resolve to the same string-keyed archetype column internally.
export type ComponentRef<T> = string | number | Component<T>

export type QueryFilter = {
	all: { number }?,
	any: { number }?,
	none: { number }?,
}

export type Query = {
	filter: QueryFilter,
	all: (self: Query, ...ComponentRef<unknown>) -> Query,
	any: (self: Query, ...ComponentRef<unknown>) -> Query,
	none: (self: Query, ...ComponentRef<unknown>) -> Query,
	select: (self: Query, ...ComponentRef<unknown>) -> Query,
	cached: (self: Query) -> Query,
	matches: (self: Query, componentSet: { [number]: boolean }) -> boolean,
}

export type ObserverCallback = (entity: Entity, data: unknown) -> ()

export type ObserverType = "onAdd" | "onChange" | "onRemove"

export type Observer = {
	componentName: string,
	observerType: ObserverType,
	callback: ObserverCallback,
}

export type PrefabEntry = { string | { [string]: unknown } }

export type PrefabDefinition = {
	name: string,
	components: { PrefabEntry },
}

export type SystemConfig = {
	phase: Phase,
	priority: number?,
	query: Query?,
	run: (entities: { Entity }, dt: number) -> (),
}

export type SystemDefinition = {
	name: string,
	phase: Phase,
	priority: number,
	query: Query?,
	run: (entities: { Entity }, dt: number) -> (),
	enabled: boolean,
}

export type CleanupAction = "delete" | "remove"

export type RelationTrait = {
	exclusive: boolean?,
	onDelete: CleanupAction?,
	onDeleteTarget: CleanupAction?,
}

export type ObserverMap = {
	register: (self: ObserverMap, observerType: ObserverType, componentName: string, callback: ObserverCallback) -> (),
	fire: (self: ObserverMap, observerType: ObserverType, componentName: string, entity: Entity, data: unknown) -> (),
	hasListeners: (self: ObserverMap, observerType: ObserverType, componentName: string) -> boolean,
	clear: (self: ObserverMap) -> (),
}

export type CleanupBinding = {
	entity: Entity,
	instance: Instance,
}

export type Column = { any }

export type Archetype = {
	id: number,
	type: string,
	types: { number },
	entities: { Entity },
	columns: { Column },
	columnsMap: { [number]: Column },
	componentSet: { [number]: boolean },
	_bundlePins: number,
}

export type CompiledArchetypePlan = {
	archetype: Archetype,
	entities: { Entity },
	columns: { Column },
}

export type CompiledQueryCursor = (() -> ...any) & {
	close: (self: CompiledQueryCursor) -> (),
}

export type CompiledQuery = (() -> ...any) & {
	cursor: (self: CompiledQuery) -> CompiledQueryCursor,
	destroy: (self: CompiledQuery) -> (),
}

export type SpawnBundle = {
	ids: { number },
	metadata: { ComponentMetadata },
	archetype: Archetype,
	dataPositions: { number },
	dataColumnPositions: { number },
	dataColumns: { Column },
	denseDataPositions: { number },
	sparseIds: { number },
	sparseDataPositions: { number },
	memberCount: number,
	dataCount: number,
	denseCount: number,
	sparseCount: number,
	_entityStore: any,
	_lifecycle: { destroyed: boolean },
	destroy: (self: SpawnBundle) -> (),
}

export type StructuralPatchSpec = {
	add: { number }?,
	remove: { number }?,
}

export type StructuralPatch = {
	addIds: { number },
	removeIds: { number },
	addMetadata: { ComponentMetadata },
	removeMetadata: { ComponentMetadata },
	dataPositions: { number },
	dataCount: number,
	operationCount: number,
	_transitions: { [number]: Archetype },
	_entityStore: any,
	_lifecycle: { destroyed: boolean },
	destroy: (self: StructuralPatch) -> (),
}

export type EntityRecord = {
	dense: number,
	row: number,
	archetype: Archetype,
}

export type EntityIndex = {
	sparseArray: { [number]: EntityRecord },
	denseArray: { [number]: Entity },
	aliveCount: number,
}

export type DebugSystemInfo = {
	name: string,
	executionTimeMs: number,
	entityCount: number,
	enabled: boolean,
}

export type DebugFrameInfo = {
	frameNumber: number,
	activeSystems: number,
	disabledSystems: number,
	entityCount: number,
	systems: { DebugSystemInfo },
	mutatedComponents: { [string]: number },
}

export type WorldConfig = {
	debugEnabled: boolean?,
}

export type Optional<T> = T | nil
export type Dictionary<K, V> = { [K]: V }
export type Array<T> = { T }
export type Set<T> = { [T]: boolean }
export type Callback<T> = (value: T) -> ()
export type Predicate<T> = (value: T) -> boolean
export type Factory<T> = () -> T
export type Result<T> = { ok: true, value: T } | { ok: false, error: string }

return nil
