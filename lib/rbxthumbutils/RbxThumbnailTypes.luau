--!strict
--[=[
	Canonical RbxThumbnailTypes
	@class RbxThumbnailTypes
]=]

const require = require("../Loader").load()

local Enums = require('Enums')

export type RbxThumbnailType =
	'Asset'
	| 'Avatar'
	| 'AvatarHeadShot'
	| 'BadgeIcon'
	| 'BundleThumbnail'
	| 'GameIcon'
	| 'GamePass'
	| 'GroupIcon'
	| 'Outfit'

return Enums.new({
	ASSET = 'Asset' :: 'Asset',
	AVATAR = 'Avatar' :: 'Avatar',
	AVATAR_HEAD_SHOT = 'AvatarHeadShot' :: 'AvatarHeadShot',
	BADGE = 'BadgeIcon' :: 'BadgeIcon',
	BUNDLE = 'BundleThumbnail' :: 'BundleThumbnail',
	GAME_ICON = 'GameIcon' :: 'GameIcon',
	GAME_PASS = 'GamePass' :: 'GamePass',
	GROUP_ICON = 'GroupIcon' :: 'GroupIcon',
	OUTFIT = 'Outfit' :: 'Outfit',
})
