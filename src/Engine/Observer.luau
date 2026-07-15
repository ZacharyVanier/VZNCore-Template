-- ECS observer registry for component lifecycle events
-- VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
-- GitHub-managed: do not modify in Roblox Studio.

--##========== TYPES ==========##--

type ObserverCallback = (entity: number, data: any) -> ()

type EventMap = {
	[string]: { ObserverCallback },
}

--##========== PUBLIC API ==========##--

local Observer = {}
Observer.__index = Observer

export type Observer = typeof(setmetatable(
	{} :: {
		onAdd: EventMap,
		onChange: EventMap,
		onRemove: EventMap,
		_empty: boolean,
	},
	Observer
))

function Observer.new(): Observer
	local self = setmetatable({}, Observer) :: Observer

	self.onAdd = {}
	self.onChange = {}
	self.onRemove = {}
	self._empty = true

	return self
end

function Observer.register(self: Observer, eventType: string, componentName: string, callback: ObserverCallback): ()
	local group = (self :: any)[eventType] :: EventMap?
	if not group then
		return
	end

	if not group[componentName] then
		group[componentName] = {}
	end

	table.insert(group[componentName], callback)

	self._empty = false
end

function Observer.fire(self: Observer, eventType: string, componentName: string, entity: number, data: any): ()
	local group = (self :: any)[eventType] :: EventMap?
	if not group then
		return
	end

	local callbacks = group[componentName]
	if not callbacks then
		return
	end

	for _, callback in callbacks do
		callback(entity, data)
	end
end

-- True if at least one callback is registered for this event + component. The
-- caller uses it to skip the pre-fetch and dispatch entirely on the common
-- zero-listener path (register only ever adds, so a non-nil bucket means >= 1).
function Observer.hasListeners(self: Observer, eventType: string, componentName: string): boolean
	local group = (self :: any)[eventType] :: EventMap?
	return group ~= nil and group[componentName] ~= nil
end

function Observer.clear(self: Observer): ()
	table.clear(self.onAdd)
	table.clear(self.onChange)
	table.clear(self.onRemove)
	self._empty = true
end

return Observer
