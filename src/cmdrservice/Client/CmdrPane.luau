--!strict
--[=[
	Owns Cmdr's Blend interface and its responsive visibility transition.

	@class CmdrPane
	@client
]=]

const require = require("../../Loader").load()

const BasicPane = require("BasicPane")
const BasicPaneUtils = require("BasicPaneUtils")
const Blend = require("Blend")
const CmdrBlendGui = require("CmdrBlendGui")
const Observable = require("Observable")
const t = require("t")

const TRANSITION_SPEED = 42
const TRANSITION_DAMPER = 0.82

const CmdrPane = setmetatable({}, BasicPane)
CmdrPane.ClassName = "CmdrPane"
CmdrPane.__index = CmdrPane

export type CmdrPane =
	typeof(setmetatable(
		{} :: {
			_screenGui: ScreenGui,
		},
		{} :: typeof({ __index = CmdrPane })
	))
	& BasicPane.BasicPane

function CmdrPane.new(parent: PlayerGui): CmdrPane
	assert(t.instanceIsA("PlayerGui")(parent), "Bad parent")

	const self = setmetatable(BasicPane.new() :: any, CmdrPane) :: CmdrPane
	const percentVisible =
		Blend.Spring(BasicPaneUtils.observePercentVisible(self), TRANSITION_SPEED, TRANSITION_DAMPER) :: Observable.Observable<number>
	const guiMaid, screenGui = CmdrBlendGui.mount(parent, percentVisible, self:ObserveVisible() :: any)

	self._screenGui = screenGui
	self.Gui = screenGui :: any
	self._maid:Add(guiMaid)

	return self
end

--[=[
	Returns the mounted Cmdr ScreenGui.

	@within CmdrPane
	@return ScreenGui
]=]
function CmdrPane.GetScreenGui(self: CmdrPane): ScreenGui
	return self._screenGui
end

function CmdrPane.Destroy(self: CmdrPane): ()
	BasicPane.Destroy(self)
end

return CmdrPane
