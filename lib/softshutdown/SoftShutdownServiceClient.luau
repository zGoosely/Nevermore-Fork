--!strict
--[=[
	Client service for handling soft shutdown notifications and UI.

	@class SoftShutdownServiceClient
]=]

const TeleportService = game:GetService("TeleportService")
const Workspace = game:GetService("Workspace")

const require = require("../Loader").load()

const AttributeValue = require("AttributeValue")
const CoreGuiEnabler = require("CoreGuiEnabler")
const Maid = require("Maid")
const PlayerGuiUtils = require("PlayerGuiUtils")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")
const SoftShutdownConstants = require("SoftShutdownConstants")
const SoftShutdownTranslator = require("SoftShutdownTranslator")
const SoftShutdownUI = require("SoftShutdownUI")
const ValueObject = require("ValueObject")
const t = require("t")

const SoftShutdownServiceClient = {}
SoftShutdownServiceClient.ServiceName = "SoftShutdownServiceClient"

export type SoftShutdownServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_translator: any,
		_isLobby: AttributeValue.AttributeValue<boolean>,
		_isUpdating: AttributeValue.AttributeValue<boolean>,
		_localTeleportDataSaysIsLobby: ValueObject.ValueObject<boolean>,
		_isArrivingAfterShutdown: ValueObject.ValueObject<boolean>,
	},
	{} :: typeof({ __index = SoftShutdownServiceClient })
))

const DISABLE_CORE_GUI_TYPES = {
	Enum.CoreGuiType.PlayerList,
	Enum.CoreGuiType.Health,
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.Chat,
	Enum.CoreGuiType.EmotesMenu,
	Enum.CoreGuiType.All,
}

function SoftShutdownServiceClient.Init(self: SoftShutdownServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")
	self._serviceBag = serviceBag

	self._maid = Maid.new()
	self._translator = self._serviceBag:GetService(SoftShutdownTranslator)

	self._isLobby = AttributeValue.new(Workspace, SoftShutdownConstants.IS_SOFT_SHUTDOWN_LOBBY_ATTRIBUTE, false)
	self._isUpdating = AttributeValue.new(Workspace, SoftShutdownConstants.IS_SOFT_SHUTDOWN_UPDATING_ATTRIBUTE, false)

	self._localTeleportDataSaysIsLobby = self._maid:Add(ValueObject.new(false, "boolean"))
	self._isArrivingAfterShutdown = self._maid:Add(ValueObject.new(false, "boolean"))
end

function SoftShutdownServiceClient.Start(self: SoftShutdownServiceClient): ()
	task.spawn(function()
		if self:_queryLocalTeleportInfo() then
			self._localTeleportDataSaysIsLobby.Value = true
		end
		if self:_queryIsArrivingAfterShutdown() then
			self._isArrivingAfterShutdown.Value = true
		end
	end)

	self._maid:GiveTask(Rx.combineLatest({
		isLobby = self._isLobby:Observe(),
		isShuttingDown = self._isUpdating:Observe(),
		localTeleportDataSaysIsLobby = self._localTeleportDataSaysIsLobby:Observe(),
		isArrivingAfterShutdown = self._isArrivingAfterShutdown:Observe(),
	}):Subscribe(function(state: any)
		if state.isLobby or state.localTeleportDataSaysIsLobby then
			self._maid._shutdownUI = nil
			if not self._maid._lobbyUI then
				local screenGui
				self._maid._lobbyUI, screenGui =
					self:_showSoftShutdownUI("shutdown.lobby.title", "shutdown.lobby.subtitle", true)

				TeleportService:SetTeleportGui(screenGui)
			end
		elseif state.isShuttingDown then
			local screenGui
			self._maid._shutdownUI, screenGui =
				self:_showSoftShutdownUI("shutdown.restart.title", "shutdown.restart.subtitle")

			TeleportService:SetTeleportGui(screenGui)

			self._maid._lobbyUI = nil
		elseif state.isArrivingAfterShutdown then
			local maid = self:_showSoftShutdownUI("shutdown.complete.title", "shutdown.complete.subtitle", true)
			self._maid._shutdownUI = maid
			self._maid._lobbyUI = nil

			task.delay(1, function()
				if self._maid._shutdownUI == maid then
					self._maid._shutdownUI = nil
				end
			end)
		else
			self._maid._shutdownUI = nil
			self._maid._lobbyUI = nil
		end
	end))
end

function SoftShutdownServiceClient._queryIsArrivingAfterShutdown(_self: SoftShutdownServiceClient): boolean
	local data = TeleportService:GetLocalPlayerTeleportData()
	if type(data) == "table" and data.isSoftShutdownArrivingIntoUpdatedServer then
		return true
	else
		return false
	end
end

function SoftShutdownServiceClient._queryLocalTeleportInfo(_self: SoftShutdownServiceClient): boolean
	local data = TeleportService:GetLocalPlayerTeleportData()
	if type(data) == "table" and data.isSoftShutdownReserveServer then
		return true
	else
		return false
	end
end

function SoftShutdownServiceClient._showSoftShutdownUI(
	self: SoftShutdownServiceClient,
	titleKey: string,
	subtitleKey: string,
	doNotAnimateShow: boolean?
): (Maid.Maid, ScreenGui)
	assert(t.string(titleKey), "Bad titleKey")
	assert(t.string(subtitleKey), "Bad subtitleKey")

	local maid = Maid.new()
	local renderMaid = Maid.new()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SoftShutdownScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.AutoLocalize = false
	screenGui.IgnoreGuiInset = true
	screenGui.ClipToDeviceSafeArea = false
	screenGui.DisplayOrder = 1e9
	screenGui.Parent = PlayerGuiUtils.getPlayerGui()
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	renderMaid:GiveTask(screenGui)

	local softShutdownUI = SoftShutdownUI.new()
	renderMaid:GiveTask(softShutdownUI)

	maid:GiveTask(function()
		softShutdownUI:Hide()

		task.delay(1, function()
			renderMaid:Destroy()
		end)
	end)

	self:_hideCoreGuiUI(renderMaid, screenGui)

	maid:GiveTask(self._translator:ObserveFormatByKey(subtitleKey):Subscribe(function(subtitle: string)
		softShutdownUI:SetSubtitle(subtitle)
	end))

	maid:GiveTask(self._translator:ObserveFormatByKey(titleKey):Subscribe(function(title: string)
		softShutdownUI:SetTitle(title)
	end))

	softShutdownUI:Show(doNotAnimateShow)

	local gui = softShutdownUI.Gui :: GuiObject
	gui.Parent = screenGui

	return maid, screenGui
end

function SoftShutdownServiceClient._hideCoreGuiUI(
	_self: SoftShutdownServiceClient,
	maid: Maid.Maid,
	ignoreScreenGui: ScreenGui
): ()
	maid:GiveTask(CoreGuiEnabler:PushDisable("ModalEnabled"))

	local playerGui = PlayerGuiUtils.getPlayerGui()
	local enabledScreenGuis: { [ScreenGui]: ScreenGui } = {}

	local function handleChild(child: Instance)
		if child:IsA("ScreenGui") and child ~= ignoreScreenGui and child.Enabled then
			enabledScreenGuis[child] = child
			child.Enabled = false
		end
	end

	for _, child in playerGui:GetChildren() do
		handleChild(child)
	end

	maid:GiveTask(playerGui.ChildAdded:Connect(function(child: Instance)
		handleChild(child)
	end))

	maid:GiveTask(playerGui.ChildRemoved:Connect(function(child: Instance)
		enabledScreenGuis[child :: ScreenGui] = nil
	end))

	maid:GiveTask(function()
		for screenGui in enabledScreenGuis do
			screenGui.Enabled = true
		end
	end)

	for _, coreGuiType in DISABLE_CORE_GUI_TYPES do
		maid:GiveTask(CoreGuiEnabler:PushDisable(coreGuiType))
	end
end

function SoftShutdownServiceClient.Destroy(self: SoftShutdownServiceClient): ()
	self._maid:DoCleaning()
end

return SoftShutdownServiceClient
