--!strict
--[=[
	Selects the local player's active control family, reports it to the server over
	ByteNet, and exposes every player's replicated input-mode attribute.

	@client
	@class PlayerInputModeServiceClient
]=]

const Players = game:GetService("Players")

const require = require("../Loader").load()

const InputModeServiceClient = require("InputModeServiceClient")
const InputModeType = require("InputModeType")
const InputModeTypeSelector = require("InputModeTypeSelector")
const InputModeTypes = require("InputModeTypes")
const Maid = require("Maid")
const Observable = require("Observable")
const PlayerInputModeNetwork = require("PlayerInputModeNetwork")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const PlayerInputModeUtils = require("PlayerInputModeUtils")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerInputModeServiceClient = {}
PlayerInputModeServiceClient.ServiceName = "PlayerInputModeServiceClient"

export type PlayerInputModeServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_selector: InputModeTypeSelector.InputModeTypeSelector,
	},
	{} :: typeof({ __index = PlayerInputModeServiceClient })
))

function PlayerInputModeServiceClient.Init(self: PlayerInputModeServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._serviceBag:GetService(InputModeServiceClient)
end

function PlayerInputModeServiceClient.Start(self: PlayerInputModeServiceClient)
	self._selector = self._maid:Add(InputModeTypeSelector.new(self._serviceBag, {
		InputModeTypes.Gamepads,
		InputModeTypes.KeyboardAndMouse,
		InputModeTypes.Touch,
	}))

	self._maid:Add(self._selector
		:ObserveActiveInputType()
		:Pipe({
			Rx.throttleTime(1, { leading = true, trailing = true }),
		})
		:Subscribe(function(inputModeType)
			if not inputModeType then
				return
			end

			const playerInputModeType = self:_toPlayerInputModeType(inputModeType)
			PlayerInputModeUtils.setPlayerInputModeType(Players.LocalPlayer, playerInputModeType)
			PlayerInputModeNetwork.packets.inputModeChanged.send(
				PlayerInputModeUtils.toNetworkCode(playerInputModeType)
			)
		end))
end

--[=[
	Observes a player's current input mode. This works for the local player and
	other players because the server stores the validated mode as an attribute.

	@within PlayerInputModeServiceClient
	@param player Player
	@return Observable<PlayerInputModeType?>
]=]
function PlayerInputModeServiceClient.ObservePlayerInputType(
	_self: PlayerInputModeServiceClient,
	player: Player
): Observable.Observable<
	PlayerInputModeUtils.PlayerInputModeType?
>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return PlayerInputModeUtils.observePlayerInputModeType(player)
end

--[=[
	Returns a player's current input mode.

	@within PlayerInputModeServiceClient
	@param player Player
	@return PlayerInputModeType?
]=]
function PlayerInputModeServiceClient.GetPlayerInputModeType(
	_self: PlayerInputModeServiceClient,
	player: Player
): PlayerInputModeUtils.PlayerInputModeType?
	assert(t.instanceIsA("Player")(player), "Bad player")
	return PlayerInputModeUtils.getPlayerInputModeType(player)
end

--[=[
	Returns the selector used to classify the local player's active mode.

	@within PlayerInputModeServiceClient
	@return InputModeTypeSelector
]=]
function PlayerInputModeServiceClient.GetSelector(
	self: PlayerInputModeServiceClient
): InputModeTypeSelector.InputModeTypeSelector
	return self._selector
end

function PlayerInputModeServiceClient._toPlayerInputModeType(
	_self: PlayerInputModeServiceClient,
	inputModeType: InputModeType.InputModeType
): PlayerInputModeUtils.PlayerInputModeType
	if inputModeType == InputModeTypes.Gamepads then
		return PlayerInputModeTypes.GAMEPAD
	elseif inputModeType == InputModeTypes.KeyboardAndMouse then
		return PlayerInputModeTypes.KEYBOARD
	elseif inputModeType == InputModeTypes.Touch then
		return PlayerInputModeTypes.TOUCH
	else
		error(`Unsupported player input mode {inputModeType.Name}`)
	end
end

function PlayerInputModeServiceClient.Destroy(self: PlayerInputModeServiceClient)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return PlayerInputModeServiceClient
