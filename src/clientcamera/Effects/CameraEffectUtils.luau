--!strict
--[=[
	A CameraEffect is something that can be resolved into a CameraState providing source
	@class CameraEffectUtils
]=]

const require = require("../../Loader").load()

local CameraState = require('CameraState')

--[=[
	Represents an effect that can be used in combination with other effects.
	@interface CameraEffect
	.CameraState CameraState
	@within CameraEffectUtils
]=]
export type CameraEffect = {
	CameraState: CameraState.CameraState,
}

--[=[
	Something that is like a camera
	@type CameraLike CameraEffect | CameraState
	@within CameraEffectUtils
]=]
export type CameraLike = CameraEffect | CameraState.CameraState

return {}
