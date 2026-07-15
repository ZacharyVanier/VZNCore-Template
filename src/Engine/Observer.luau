--[[
	Observer -- registers component lifecycle callbacks for one World.
	VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» TYPE DEFINITIONS «--

export type ObserverEvent = "onAdd" | "onChange" | "onRemove"
export type ObserverCallback = (number, unknown) -> ()

export type Observer = {
	register: (Observer, ObserverEvent, string, ObserverCallback) -> (),
	fire: (Observer, ObserverEvent, string, number, unknown) -> (),
	hasListeners: (Observer, ObserverEvent, string) -> boolean,
	clear: (Observer) -> (),
}

type EventMap = {
	[string]: { ObserverCallback },
}

type ObserverState = {
	CallbacksByEvent: { [ObserverEvent]: EventMap },
}

type ObserverFactory = {
	__index: ObserverFactory,
	new: () -> Observer,
	register: (Observer, ObserverEvent, string, ObserverCallback) -> (),
	fire: (Observer, ObserverEvent, string, number, unknown) -> (),
	hasListeners: (Observer, ObserverEvent, string) -> boolean,
	clear: (Observer) -> (),
}

--» CLASS DEFINITION «--

local Observer = {} :: ObserverFactory
Observer.__index = Observer

-- Callback maps remain private so callers cannot mutate dispatch order or state.
local StateByObserver: { [Observer]: ObserverState } = {}

local GetState = function(self: Observer): ObserverState
	local State = StateByObserver[self]
	assert(State ~= nil, "Observer is not initialized")
	return State
end

--» CONSTRUCTOR «--

Observer.new = function(): Observer
	local self = (setmetatable({}, Observer) :: unknown) :: Observer
	StateByObserver[self] = {
		CallbacksByEvent = {
			onAdd = {},
			onChange = {},
			onRemove = {},
		},
	}

	return self
end

--» PUBLIC METHODS «--

-- Invalid event names are neutral fallbacks for compatibility with internal dynamic dispatch.
Observer.register = function(
	self: Observer,
	EventType: ObserverEvent,
	ComponentName: string,
	Callback: ObserverCallback
): ()
	local Group = GetState(self).CallbacksByEvent[EventType]
	if Group == nil then
		return
	end

	local Callbacks = Group[ComponentName]
	if Callbacks == nil then
		Callbacks = {}
		Group[ComponentName] = Callbacks
	end

	table.insert(Callbacks, Callback)
end

Observer.fire = function(
	self: Observer,
	EventType: ObserverEvent,
	ComponentName: string,
	Entity: number,
	Data: unknown
): ()
	local Group = GetState(self).CallbacksByEvent[EventType]
	if Group == nil then
		return
	end

	local Callbacks = Group[ComponentName]
	if Callbacks == nil then
		return
	end

	for _, Callback in Callbacks do
		Callback(Entity, Data)
	end
end

-- Returns false when no callback is registered for the exact event/component pair.
Observer.hasListeners = function(self: Observer, EventType: ObserverEvent, ComponentName: string): boolean
	local Group = GetState(self).CallbacksByEvent[EventType]
	return Group ~= nil and Group[ComponentName] ~= nil
end

Observer.clear = function(self: Observer): ()
	local State = GetState(self)
	for _, Group in State.CallbacksByEvent do
		table.clear(Group)
	end
end

--» MODULE EXPORT «--

return Observer
