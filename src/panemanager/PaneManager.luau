--!strict
--[=[
	Provides a shared registry for panes, visibility categories, and close locks.

	Panes register themselves with the singleton after construction. The manager
	coordinates visibility requests but does not own or destroy the registered panes.

	@class PaneManager
	@client
]=]

const require = require("../Loader").load()

const BasicPane = require("BasicPane")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const Singleton = require("Singleton")
const Symbol = require("Symbol")
const t = require("t")

export type PaneSettings = {
	Categories: { string }?,
}

type CategoryState = {
	_showHandles: { [Symbol.Symbol]: true },
}

type PaneState = {
	_categories: { [string]: true },
	_closeLockCount: number,
	_pane: BasicPane.BasicPane,
	_showHandles: { [Symbol.Symbol]: true },
}

const isPaneSettings = t.strictInterface({
	Categories = t.optional(t.array(t.string)),
})

const PaneManager = {}
PaneManager.ClassName = "PaneManager"
PaneManager.__index = PaneManager

export type PaneManager = typeof(setmetatable(
	{} :: {
		_categoryStatesByName: { [string]: CategoryState },
		_paneStatesByName: { [string]: PaneState },
		_serviceBag: ServiceBag.ServiceBag,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = PaneManager })
))

local function newPaneManager(serviceBag: ServiceBag.ServiceBag): PaneManager
	assert(t.table(serviceBag), "Bad serviceBag")

	return setmetatable(
		{
			_categoryStatesByName = {},
			_paneStatesByName = {},
			_serviceBag = serviceBag,
			_destroyed = false,
		} :: any,
		PaneManager
	) :: PaneManager
end

--[=[
	Registers a constructed pane with its visibility categories.

	@within PaneManager
	@param name string
	@param pane BasicPane
	@param settings PaneSettings
	@return ()
]=]
function PaneManager.RegisterPane(
	self: PaneManager,
	name: string,
	pane: BasicPane.BasicPane,
	settings: PaneSettings
): ()
	assert(not self._destroyed, "PaneManager is destroyed")
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.table(pane) and BasicPane.isBasicPane(pane), "Bad pane")
	assert(isPaneSettings(settings), "Bad settings")
	assert(not self._paneStatesByName[name], "Pane is already registered")

	const categories: { [string]: true } = {}
	if settings.Categories then
		for _, category in settings.Categories do
			assert(category ~= "", "Bad settings.Categories")
			categories[category] = true

			if not self._categoryStatesByName[category] then
				self._categoryStatesByName[category] = {
					_showHandles = {},
				}
			end
		end
	end

	self._paneStatesByName[name] = {
		_categories = categories,
		_closeLockCount = 0,
		_pane = pane,
		_showHandles = {},
	}
end

--[=[
	Requests that a registered pane be shown until the returned handle is cleaned.

	@within PaneManager
	@param name string
	@param doNotAnimate boolean?
	@return MaidTask
]=]
function PaneManager.ShowPane(self: PaneManager, name: string, doNotAnimate: boolean?): Maid.MaidTask
	const state = self:_getPaneState(name)
	assert(t.optional(t.boolean)(doNotAnimate), "Bad doNotAnimate")

	const key = Symbol.named(name)
	state._showHandles[key] = true
	self:_updatePaneVisibility(state, doNotAnimate)

	return function()
		if self._destroyed or not state._showHandles[key] then
			return
		end

		state._showHandles[key] = nil
		self:_updatePaneVisibility(state)
	end
end

--[=[
	Requests that every pane in a registered category be shown until the returned
	handle is cleaned.

	@within PaneManager
	@param category string
	@param doNotAnimate boolean?
	@return MaidTask
]=]
function PaneManager.ShowCategory(self: PaneManager, category: string, doNotAnimate: boolean?): Maid.MaidTask
	const categoryState = self:_getCategoryState(category)
	assert(t.optional(t.boolean)(doNotAnimate), "Bad doNotAnimate")

	const key = Symbol.named(category)
	categoryState._showHandles[key] = true
	self:_updateCategoryVisibility(category, doNotAnimate)

	return function()
		if self._destroyed or not categoryState._showHandles[key] then
			return
		end

		categoryState._showHandles[key] = nil
		self:_updateCategoryVisibility(category)
	end
end

--[=[
	Releases all direct show requests for a pane. Category requests can still keep
	the pane visible.

	@within PaneManager
	@param name string
	@return ()
]=]
function PaneManager.HidePane(self: PaneManager, name: string): ()
	const state = self:_getPaneState(name)
	table.clear(state._showHandles)
	self:_updatePaneVisibility(state)
end

--[=[
	Releases all show requests for a category.

	@within PaneManager
	@param category string
	@return ()
]=]
function PaneManager.HideCategory(self: PaneManager, category: string): ()
	const categoryState = self:_getCategoryState(category)
	table.clear(categoryState._showHandles)
	self:_updateCategoryVisibility(category)
end

--[=[
	Prevents a visible pane from hiding until the returned lock is cleaned.

	@within PaneManager
	@param name string
	@return MaidTask
]=]
function PaneManager.CreateCloseLock(self: PaneManager, name: string): Maid.MaidTask
	const state = self:_getPaneState(name)
	state._closeLockCount += 1

	local released = false
	return function()
		if released then
			return
		end
		released = true

		if self._destroyed then
			return
		end

		state._closeLockCount -= 1
		self:_updatePaneVisibility(state)
	end
end

--[=[
	Returns whether a registered pane is currently visible.

	@within PaneManager
	@param name string
	@return boolean
]=]
function PaneManager.IsPaneVisible(self: PaneManager, name: string): boolean
	return self:_getPaneState(name)._pane:IsVisible()
end

--[=[
	Returns whether a registered pane currently has a close lock.

	@within PaneManager
	@param name string
	@return boolean
]=]
function PaneManager.IsPaneLocked(self: PaneManager, name: string): boolean
	return self:_getPaneState(name)._closeLockCount > 0
end

function PaneManager._getPaneState(self: PaneManager, name: string): PaneState
	assert(not self._destroyed, "PaneManager is destroyed")
	assert(t.string(name) and name ~= "", "Bad name")

	const state = self._paneStatesByName[name]
	assert(state, string.format("No pane registered with name %q", name))
	return state
end

function PaneManager._getCategoryState(self: PaneManager, category: string): CategoryState
	assert(not self._destroyed, "PaneManager is destroyed")
	assert(t.string(category) and category ~= "", "Bad category")

	const state = self._categoryStatesByName[category]
	assert(state, string.format("No category registered with name %q", category))
	return state
end

function PaneManager._updateCategoryVisibility(self: PaneManager, category: string, doNotAnimate: boolean?): ()
	for _, state in self._paneStatesByName do
		if state._categories[category] then
			self:_updatePaneVisibility(state, doNotAnimate)
		end
	end
end

function PaneManager._updatePaneVisibility(self: PaneManager, state: PaneState, doNotAnimate: boolean?): ()
	local requestedVisible = next(state._showHandles) ~= nil
	if not requestedVisible then
		for category in state._categories do
			const categoryState = self._categoryStatesByName[category]
			if categoryState and next(categoryState._showHandles) ~= nil then
				requestedVisible = true
				break
			end
		end
	end

	if requestedVisible then
		if not state._pane:IsVisible() then
			state._pane:Show(doNotAnimate)
		end
	elseif state._closeLockCount == 0 and state._pane:IsVisible() then
		state._pane:Hide()
	end
end

function PaneManager.Destroy(self: PaneManager): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	table.clear(self._categoryStatesByName)
	table.clear(self._paneStatesByName)
end

return Singleton.new("PaneManager", newPaneManager)
