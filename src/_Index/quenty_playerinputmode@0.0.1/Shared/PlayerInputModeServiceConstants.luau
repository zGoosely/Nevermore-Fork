--!strict
--[=[
	Constants shared by PlayerInputModeService and its client.

	@class PlayerInputModeServiceConstants
]=]

const PlayerInputModeServiceConstants = {}

PlayerInputModeServiceConstants.INPUT_MODE_ATTRIBUTE = "PlayerInputMode"
PlayerInputModeServiceConstants.MIN_SERVER_UPDATE_INTERVAL = 0.1
PlayerInputModeServiceConstants.GAMEPAD_NETWORK_CODE = 0
PlayerInputModeServiceConstants.KEYBOARD_NETWORK_CODE = 1
PlayerInputModeServiceConstants.TOUCH_NETWORK_CODE = 2

return table.freeze(PlayerInputModeServiceConstants)
