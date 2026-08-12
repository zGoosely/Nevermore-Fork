--!strict
--[=[
	Promise helpers for Roblox sounds and video frames.

	@util SoundPromiseUtils
]=]

const require = require("../Loader").load()

local Maid = require("Maid")
local Promise = require("Promise")
local PromiseMaidUtils = require("PromiseMaidUtils")
local PromiseUtils = require("PromiseUtils")

export type LoadableMedia = Sound | VideoFrame

local SoundPromiseUtils = {}

--[=[
	Resolves once the media asset is loaded.

	@within SoundPromiseUtils
	@param media Sound | VideoFrame
	@return Promise<()>
]=]
function SoundPromiseUtils.promiseLoaded(media: LoadableMedia): Promise.Promise<()>
	assert(typeof(media) == "Instance" and (media:IsA("Sound") or media:IsA("VideoFrame")), "Bad media")

	if media.IsLoaded then
		return Promise.resolved()
	end

	local promise = Promise.new()
	PromiseMaidUtils.whilePromise(promise, function(maid: Maid.Maid)
		maid:GiveTask(media:GetPropertyChangedSignal("IsLoaded"):Connect(function()
			if media.IsLoaded then
				promise:Resolve()
			end
		end))

		maid:GiveTask(media.Loaded:Connect(function()
			if media.IsLoaded then
				promise:Resolve()
			end
		end))
		maid:GiveTask(media.Destroying:Connect(function()
			promise:Reject("Media was destroyed before it loaded")
		end))

		if media.IsLoaded then
			promise:Resolve()
		end
	end)

	return promise
end

--[=[
	Resolves after the media's remaining playback duration.

	@within SoundPromiseUtils
	@param media Sound | VideoFrame
	@return Promise<()>
]=]
function SoundPromiseUtils.promisePlayed(media: LoadableMedia): Promise.Promise<()>
	return SoundPromiseUtils.promiseLoaded(media):Then(function()
		return PromiseUtils.delayed(math.max(0, media.TimeLength - media.TimePosition))
	end)
end

--[=[
	Resolves the next time a looping Sound reaches its loop boundary.

	@within SoundPromiseUtils
	@param sound Sound
	@return Promise<()>
]=]
function SoundPromiseUtils.promiseLooped(sound: Sound): Promise.Promise<()>
	assert(typeof(sound) == "Instance" and sound:IsA("Sound"), "Bad sound")

	local promise = Promise.new()
	PromiseMaidUtils.whilePromise(promise, function(maid: Maid.Maid)
		maid:GiveTask(sound.DidLoop:Connect(function()
			promise:Resolve()
		end))
		maid:GiveTask(sound.Destroying:Connect(function()
			promise:Reject("Sound was destroyed before it looped")
		end))
	end)

	return promise
end

--[=[
	Resolves when every supplied media asset has loaded.

	@within SoundPromiseUtils
	@param mediaList { Sound | VideoFrame }
	@return Promise<()>
]=]
function SoundPromiseUtils.promiseAllSoundsLoaded(mediaList: { LoadableMedia }): Promise.Promise<()>
	assert(type(mediaList) == "table", "Bad mediaList")

	local promises = table.create(#mediaList)
	for _, media in mediaList do
		table.insert(promises, SoundPromiseUtils.promiseLoaded(media))
	end

	return PromiseUtils.all(promises)
end

return SoundPromiseUtils
