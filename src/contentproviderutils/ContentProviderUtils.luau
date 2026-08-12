-- Type checking disabled due to dynamic loader pattern

--[=[
	Utilities for working with ContentProvider and preloading assets.

	@class ContentProviderUtils
]=]

local ContentProvider = game:GetService('ContentProvider')
local SoundService = game:GetService('SoundService')

const require = require("../Loader").load()

local AnimationUtils = require('AnimationUtils')
local Promise = require('Promise')
local RbxAssetUtils = require('RbxAssetUtils')
local SoundUtils = require('SoundUtils')

export type Promise = any

local ContentProviderUtils = {}

--[=[
	Preloads an array of assets using ContentProvider.

	@param assets {Instance | string} -- Array of instances or asset IDs to preload
	@return Promise -- Resolves when all assets are loaded
]=]
function ContentProviderUtils.promisePreload(assets: { Instance | string })
	return Promise.spawn(function(resolve, reject)
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(assets)
		end)

		if ok then
			resolve()
		else
			reject(err)
		end
	end)
end

--[=[
	Preloads an array of sound IDs by creating temporary Sound instances.
	Uses SoundUtils.promiseLoaded to ensure each sound is fully loaded.

	@param soundIds {string | number} -- Array of sound IDs to preload
	@return Promise -- Resolves when all sounds are loaded
]=]
function ContentProviderUtils.promisePreloadSoundIds(soundIds: { string | number })
	return Promise.new(function(resolve, reject)
		local sounds = {}
		local promises = {}

		for _, soundId in soundIds do
			soundId = RbxAssetUtils.toRbxAssetId(soundId)

			local sound = Instance.new('Sound')
			sound.SoundId = soundId :: string
			sound.Parent = SoundService

			table.insert(sounds, sound)
			table.insert(promises, SoundUtils.promiseLoaded(sound))
		end

		Promise.all(promises)
			:Then(function()
				for _, sound in sounds do
					sound:Destroy()
				end
				resolve()
			end)
			:Catch(function(err)
				for _, sound in sounds do
					sound:Destroy()
				end
				reject(err)
			end)
	end)
end

--[=[
	Preloads an array of animation IDs by creating temporary AnimationTracks,
	playing them briefly, and then destroying them. This ensures animations
	are cached by the engine.

	@param animationIds {string | number} -- Array of animation IDs to preload
	@return Promise -- Resolves when all animations are preloaded
]=]
function ContentProviderUtils.promisePreloadAnimations(animationIds: { string | number })
	return Promise.new(function(resolve)
		-- Create a temporary rig for loading animations
		local dummyModel = Instance.new('Model')
		local dummyHumanoid = Instance.new('Humanoid')
		dummyHumanoid.Parent = dummyModel

		local animator = AnimationUtils.getOrCreateAnimator(dummyHumanoid)
		local animationTracks = {}

		-- Load all animations
		for _, animationId in animationIds do
			local assetId = RbxAssetUtils.toRbxAssetId(animationId)
			local track = AnimationUtils.loadAnimationFromId(animator, assetId)

			if track then
				table.insert(animationTracks, track)
			end
		end

		-- Play and immediately stop each animation to cache it
		for _, track in animationTracks do
			track:Play()
			track:Stop()
		end

		-- Clean up
		for _, track in animationTracks do
			track:Destroy()
		end

		dummyModel:Destroy()

		resolve()
	end)
end

return ContentProviderUtils
