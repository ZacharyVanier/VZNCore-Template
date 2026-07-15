--[[
	Query -- builds immutable component filters and projections.
	VZNCore | Copyright (c) 2026 Zachary Vanier | MIT License.
	GitHub-managed: do not modify in Roblox Studio.
]]

--» DEPENDENCIES & VARIABLES «--

local function tryRequire(robloxPath: any, relativePath: any): any
	local ok, result = pcall(function()
		return require(robloxPath)
	end)
	if ok then
		return result
	end
	return require(relativePath)
end

local ECSTypes = tryRequire(script and script.Parent and script.Parent.Types, "./Types")
local Component = tryRequire(script and script.Parent and script.Parent.Component, "./Component")

--» TYPE DEFINITIONS «--

type ComponentRef = ECSTypes.ComponentRef<unknown>

type ComponentHandle = {
	id: number,
}

--» PUBLIC FUNCTIONS «--

local Query = {}
Query.__index = Query

--» PRIVATE FUNCTIONS «--

-- A ref is a component name (string), a typed handle (table with .id), or an
-- already-packed id (number, e.g. a pair). All collapse to the numeric id the
-- archetype store keys on. Storage is id-keyed, so queries speak ids too.
local function _resolveId(component: ComponentRef): number
	local kind = type(component)

	if kind == "number" then
		return component :: number
	end

	if kind == "table" then
		local handle = (component :: unknown) :: ComponentHandle
		return handle.id
	end

	return Component.idOf(component :: string)
end

-- A query instance carries `_all`; a component handle carries `id`/`name` but no
-- `_all`. This lets all()/any()/none() tell a chained `q:all(...)` method call
-- apart from a static `Query.all(handle, ...)` construction.
local function _isQuery(value: any): boolean
	return type(value) == "table" and rawget(value, "_all") ~= nil
end

local function _isComponentRef(value: unknown): boolean
	local kind = type(value)

	if kind == "string" or kind == "number" then
		return true
	end

	if kind ~= "table" then
		return false
	end

	local handle = (value :: unknown) :: ComponentHandle
	return handle.id ~= nil
end

local function _clone(self: QueryImpl): QueryImpl
	local cloned = setmetatable({}, Query)

	cloned._all = table.clone(self._all)
	cloned._any = table.clone(self._any)
	cloned._none = table.clone(self._none)
	cloned._select = table.clone(self._select)
	cloned._cached = self._cached

	return cloned
end

local function _appendAll(target: { number }, ...: ComponentRef): ()
	local count = select("#", ...)

	for i = 1, count do
		table.insert(target, _resolveId(select(i, ...)))
	end
end

local function _createEmpty(): QueryImpl
	local self = setmetatable({}, Query)

	self._all = {}
	self._any = {}
	self._none = {}
	self._select = {}
	self._cached = false

	return self
end

Query.all = function(self: any, ...: ComponentRef): QueryImpl
	if _isQuery(self) then
		local cloned = _clone(self)
		_appendAll(cloned._all, ...)
		return cloned
	end

	local created = _createEmpty()

	if _isComponentRef(self) then
		table.insert(created._all, _resolveId(self))
	end

	_appendAll(created._all, ...)

	return created
end

Query.any = function(self: any, ...: ComponentRef): QueryImpl
	if _isQuery(self) then
		local cloned = _clone(self)
		_appendAll(cloned._any, ...)
		return cloned
	end

	local created = _createEmpty()

	if _isComponentRef(self) then
		table.insert(created._any, _resolveId(self))
	end

	_appendAll(created._any, ...)

	return created
end

Query.none = function(self: any, ...: ComponentRef): QueryImpl
	if _isQuery(self) then
		local cloned = _clone(self)
		_appendAll(cloned._none, ...)
		return cloned
	end

	local created = _createEmpty()

	if _isComponentRef(self) then
		table.insert(created._none, _resolveId(self))
	end

	_appendAll(created._none, ...)

	return created
end

Query.select = function(self: any, ...: ComponentRef): QueryImpl
	if _isQuery(self) then
		local cloned = _clone(self)
		_appendAll(cloned._select, ...)
		return cloned
	end

	local created = _createEmpty()

	if _isComponentRef(self) then
		table.insert(created._select, _resolveId(self))
	end

	_appendAll(created._select, ...)

	return created
end

Query.cached = function(self: QueryImpl): QueryImpl
	local q = _clone(self)

	q._cached = true

	return q
end

Query.matches = function(self: QueryImpl, componentSet: { [number]: any }): boolean
	for _, id in self._all do
		if componentSet[id] == nil then
			return false
		end
	end

	local found = #self._any == 0

	for _, id in self._any do
		if componentSet[id] ~= nil then
			found = true
			break
		end
	end

	if not found then
		return false
	end

	for _, id in self._none do
		if componentSet[id] ~= nil then
			return false
		end
	end

	return true
end

return Query
