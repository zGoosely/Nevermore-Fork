--!strict
--[=[
	Utilities for reading, observing, and encoding the input mode replicated on a
	Player attribute.

	@util PlayerInputModeUtils
]=]

const require = require("../../Loader").load()

const AttributeUtils = require("AttributeUtils")
const Observable = require("Observable")
const PlayerInputModeServiceConstants = require("PlayerInputModeServiceConstants")
const PlayerInputModeTypes = require("PlayerInputModeTypes")
const Promise = require("Promise")
const Rx = require("Rx")
const RxAttributeUtils = require("RxAttributeUtils")
const t = require("t")

const PlayerInputModeUtils = {}

export type PlayerInputModeType = PlayerInputModeTypes.PlayerInputModeType

--[=[
	Returns a player's currently replicated input mode.

	@within PlayerInputModeUtils
	@param player Player
	@return PlayerInputModeType?
]=]
function PlayerInputModeUtils.getPlayerInputModeType(player: Player): PlayerInputModeType?
	assert(t.instanceIsA("Player")(player), "Bad player")
	const value = player:GetAttribute(PlayerInputModeServiceConstants.INPUT_MODE_ATTRIBUTE)
	return if PlayerInputModeUtils.isInputModeType(value) then value :: PlayerInputModeType else nil
end

--[=[
	Observes a player's replicated input mode.

	@within PlayerInputModeUtils
	@param player Player
	@return Observable<PlayerInputModeType?>
]=]
function PlayerInputModeUtils.observePlayerInputModeType(player: Player): Observable.Observable<PlayerInputModeType?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return RxAttributeUtils.observeAttribute(player, PlayerInputModeServiceConstants.INPUT_MODE_ATTRIBUTE)
			:Pipe({
				Rx.map(function(value)
					return if PlayerInputModeUtils.isInputModeType(value) then value :: PlayerInputModeType else nil
				end) :: any,
				Rx.distinct() :: any,
			}) :: any
end

--[=[
	Resolves when a player has a valid replicated input mode.

	@within PlayerInputModeUtils
	@param player Player
	@param cancelToken CancelToken?
	@return Promise<PlayerInputModeType>
]=]
function PlayerInputModeUtils.getPlayerInputModeAsync(
	player: Player,
	cancelToken: any?
): Promise.Promise<PlayerInputModeType>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return AttributeUtils.promiseAttribute(
		player,
		PlayerInputModeServiceConstants.INPUT_MODE_ATTRIBUTE,
		PlayerInputModeUtils.isInputModeType,
		cancelToken
	) :: any
end

--[=[
	Returns whether a value is a supported public input mode.

	@within PlayerInputModeUtils
	@param playerInputModeType any
	@return boolean
]=]
function PlayerInputModeUtils.isInputModeType(playerInputModeType: any): boolean
	const isValue = PlayerInputModeTypes:IsValue(playerInputModeType)
	return isValue
end

--[=[
	Sets the authoritative Player input-mode attribute.

	@within PlayerInputModeUtils
	@param player Player
	@param playerInputModeType PlayerInputModeType
]=]
function PlayerInputModeUtils.setPlayerInputModeType(player: Player, playerInputModeType: PlayerInputModeType)
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(PlayerInputModeUtils.isInputModeType(playerInputModeType), "Bad playerInputModeType")
	player:SetAttribute(PlayerInputModeServiceConstants.INPUT_MODE_ATTRIBUTE, playerInputModeType)
end

--[=[
	Encodes an input mode into the uint8 used by ByteNet.

	@within PlayerInputModeUtils
	@param playerInputModeType PlayerInputModeType
	@return number
]=]
function PlayerInputModeUtils.toNetworkCode(playerInputModeType: PlayerInputModeType): number
	assert(PlayerInputModeUtils.isInputModeType(playerInputModeType), "Bad playerInputModeType")
	if playerInputModeType == PlayerInputModeTypes.GAMEPAD then
		return PlayerInputModeServiceConstants.GAMEPAD_NETWORK_CODE
	elseif playerInputModeType == PlayerInputModeTypes.KEYBOARD then
		return PlayerInputModeServiceConstants.KEYBOARD_NETWORK_CODE
	else
		return PlayerInputModeServiceConstants.TOUCH_NETWORK_CODE
	end
end

--[=[
	Decodes a ByteNet uint8 into a supported input mode.

	@within PlayerInputModeUtils
	@param networkCode number
	@return PlayerInputModeType?
]=]
function PlayerInputModeUtils.fromNetworkCode(networkCode: number): PlayerInputModeType?
	if networkCode == PlayerInputModeServiceConstants.GAMEPAD_NETWORK_CODE then
		return PlayerInputModeTypes.GAMEPAD
	elseif networkCode == PlayerInputModeServiceConstants.KEYBOARD_NETWORK_CODE then
		return PlayerInputModeTypes.KEYBOARD
	elseif networkCode == PlayerInputModeServiceConstants.TOUCH_NETWORK_CODE then
		return PlayerInputModeTypes.TOUCH
	else
		return nil
	end
end

return PlayerInputModeUtils
