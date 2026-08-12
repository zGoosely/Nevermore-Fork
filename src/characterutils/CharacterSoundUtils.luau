--!optimize 2
--[=[
	@class CharacterSoundUtils
	Utility for replacing default Roblox character sounds with custom sounds.

	Replaces sounds like:
	- Death
	- Running/Walking
	- Jumping
	- Landing
	- Swimming
	- Climbing
	- Falling
	- Getting Up
	- Splash
	- FreeFalling

	## Usage
	```lua
	-- Replace all default sounds
	CharacterSoundUtils.replaceAllSounds(character, customSounds)

	-- Replace specific sound
	CharacterSoundUtils.replaceSound(character, 'Died', deathSound)

	-- Restore default sounds
	CharacterSoundUtils.restoreDefaultSounds(character)
	```
]=]

local RunService = game:GetService('RunService')
const require = require("../Loader").load()

local Promise = require('Promise')

local CharacterSoundUtils = {}

local SOUND_NAMES = {
	'Died',
	'Running',
	'Jumping',
	'Landing',
	'Splash',
	'Swimming',
	'Climbing',
	'GettingUp',
	'FreeFalling',
}

-- Map of sound names to their default SoundIds (as backup reference)
local DEFAULT_SOUND_IDS = {
	Died = 'rbxasset://sounds/uuhhh.mp3',
	Running = 'rbxasset://sounds/action_footsteps_plastic.mp3',
	Jumping = 'rbxasset://sounds/action_jump.mp3',
	Landing = 'rbxasset://sounds/action_jump_land.mp3',
	Splash = 'rbxasset://sounds/impact_water.mp3',
	Swimming = 'rbxasset://sounds/action_swim.mp3',
	Climbing = 'rbxasset://sounds/action_footsteps_plastic.mp3',
	GettingUp = 'rbxasset://sounds/action_get_up.mp3',
	FreeFalling = 'rbxasset://sounds/action_falling.mp3',
}

--[=[
	Waits for all character sounds to be loaded in the HumanoidRootPart
	@param character Model -- The character model
	@param timeout number? -- Optional timeout in seconds (default: 10)
	@return Promise<boolean> -- Promise that resolves to true if all sounds loaded
]=]
function CharacterSoundUtils.waitForSoundsLoadedAsync(character: Model, timeout: number?)
	return Promise.new(function(resolve, reject)
		local humanoidRootPart = character:WaitForChild('HumanoidRootPart', timeout or 10)
		if not humanoidRootPart then
			reject('HumanoidRootPart not found')
			return
		end

		local startTime = os.clock()
		local maxTime = timeout or 10

		for _, soundName in SOUND_NAMES do
			local remainingTime = maxTime - (os.clock() - startTime)
			if remainingTime <= 0 then
				reject('Timeout waiting for sounds')
				return
			end

			local sound = humanoidRootPart:WaitForChild(soundName, remainingTime)
			if not sound or not sound:IsA('Sound') then
				reject(`Sound {soundName} not found or invalid`)
				return
			end
		end

		resolve(true)
	end)
end

--[=[
	Replaces a specific character sound with a custom sound
	@param character Model -- The character model
	@param soundName string -- Name of the sound to replace (e.g., 'Died', 'Running')
	@param newSoundId string | Sound -- Either a sound ID string or a Sound instance to clone
	@return Sound? -- The replaced sound instance, or nil if not found
]=]
function CharacterSoundUtils.replaceSound(character: Model, soundName: string, newSoundId: string | Sound): Sound?
	local humanoidRootPart = character:FindFirstChild('HumanoidRootPart')

	if not humanoidRootPart then
		warn(`[CharacterSoundUtils] HumanoidRootPart not found in {character.Name}`)
		return nil
	end

	-- Some sounds are in Head, others in HumanoidRootPart
	local searchPart = humanoidRootPart
	if not searchPart then
		warn(`[CharacterSoundUtils] Could not find part for sound '{soundName}' in {character.Name}`)
		return nil
	end

	-- Find the existing sound
	local existingSound = searchPart:WaitForChild(soundName)
	if not existingSound or not existingSound:IsA('Sound') then
		warn(`[CharacterSoundUtils] Sound '{soundName}' not found in {character.Name}`)
		return nil
	end

	-- Replace the SoundId
	if typeof(newSoundId) == 'string' then
		existingSound.SoundId = newSoundId
	elseif typeof(newSoundId) == 'Instance' and newSoundId:IsA('Sound') then
		-- Clone properties from the provided Sound instance
		existingSound.SoundId = newSoundId.SoundId
		existingSound.Volume = newSoundId.Volume
		existingSound.PlaybackSpeed = newSoundId.PlaybackSpeed
		existingSound.RollOffMaxDistance = newSoundId.RollOffMaxDistance
		existingSound.RollOffMinDistance = newSoundId.RollOffMinDistance
		existingSound.RollOffMode = newSoundId.RollOffMode
		existingSound.Looped = newSoundId.Looped

		-- Clear old effects
		for _, child in existingSound:GetChildren() do
			if child:IsA('SoundEffect') then
				child:Destroy()
			end
		end

		-- Copy effects if any
		for _, effect in newSoundId:GetChildren() do
			if effect:IsA('SoundEffect') then
				effect:Clone().Parent = existingSound
			end
		end
	else
		warn(`[CharacterSoundUtils] Invalid sound type provided for '{soundName}'`)
		return nil
	end

	return existingSound
end

--[=[
	Replaces multiple character sounds at once
	@param character Model -- The character model
	@param soundMap {[string]: string | Sound} -- Map of sound names to sound IDs or Sound instances
	@return {[string]: Sound} -- Map of sound names to the replaced Sound instances
]=]
function CharacterSoundUtils.replaceSounds(
	character: Model,
	soundMap: { [string]: string | Sound }
): { [string]: Sound }
	local replacedSounds = {}

	for soundName, newSound in soundMap do
		local sound = CharacterSoundUtils.replaceSound(character, soundName, newSound)
		if sound then
			replacedSounds[soundName] = sound
		end
	end

	return replacedSounds
end

--[=[
	Replaces all default character sounds with custom sounds from a folder or table
	@param character Model -- The character model
	@param customSounds Folder | {[string]: Sound} -- Either a folder containing Sound instances or a table map
]=]
function CharacterSoundUtils.replaceAllSounds(character: Model, customSounds: Folder | { [string]: Sound })
	local soundMap = {}

	if typeof(customSounds) == 'Instance' and customSounds:IsA('Folder') then
		-- Convert folder to map
		for _, sound in customSounds:GetChildren() do
			if sound:IsA('Sound') then
				soundMap[sound.Name] = sound
			end
		end
	elseif typeof(customSounds) == 'table' then
		soundMap = customSounds
	else
		warn('[CharacterSoundUtils] Invalid customSounds type provided')
		return
	end

	CharacterSoundUtils.replaceSounds(character, soundMap)
end

--[=[
	Restores default Roblox sounds to a character
	@param character Model -- The character model
]=]
function CharacterSoundUtils.restoreDefaultSounds(character: Model)
	CharacterSoundUtils.replaceSounds(character, DEFAULT_SOUND_IDS)
end

--[=[
	Removes a specific sound from the character
	@param character Model -- The character model
	@param soundName string -- Name of the sound to remove
]=]
function CharacterSoundUtils.removeSound(character: Model, soundName: string)
	local humanoidRootPart = character:FindFirstChild('HumanoidRootPart')
	if not humanoidRootPart then
		return
	end

	local sound = humanoidRootPart:FindFirstChild(soundName)
	if sound and sound:IsA('Sound') then
		sound:Destroy()
	end
end

--[=[
	Removes all character sounds
	@param character Model -- The character model
]=]
function CharacterSoundUtils.removeAllSounds(character: Model)
	for _, soundName in SOUND_NAMES do
		CharacterSoundUtils.removeSound(character, soundName)
	end
end

--[=[
	Mutes/unmutes a specific character sound
	@param character Model -- The character model
	@param soundName string -- Name of the sound to mute/unmute
	@param muted boolean -- True to mute, false to unmute
]=]
function CharacterSoundUtils.setMuted(character: Model, soundName: string, muted: boolean)
	local humanoidRootPart = character:FindFirstChild('HumanoidRootPart')
	if not humanoidRootPart then
		return
	end

	local sound = humanoidRootPart:FindFirstChild(soundName)
	if sound and sound:IsA('Sound') then
		sound.Volume = muted and 0 or 0.65 -- Default volume is 0.65
	end
end

--[=[
	Sets the volume for a specific character sound
	@param character Model -- The character model
	@param soundName string -- Name of the sound
	@param volume number -- Volume level (0-1)
]=]
function CharacterSoundUtils.setVolume(character: Model, soundName: string, volume: number)
	local humanoidRootPart = character:FindFirstChild('HumanoidRootPart')
	if not humanoidRootPart then
		return
	end

	local sound = humanoidRootPart:FindFirstChild(soundName)
	if sound and sound:IsA('Sound') then
		sound.Volume = math.clamp(volume, 0, 1)
	end
end

--[=[
	Gets all character sounds
	@param character Model -- The character model
	@return {[string]: Sound} -- Map of sound names to Sound instances
]=]
function CharacterSoundUtils.getAllSounds(character: Model): { [string]: Sound }
	local sounds = {}
	local humanoidRootPart = character:FindFirstChild('HumanoidRootPart')

	if not humanoidRootPart then
		return sounds
	end

	for _, soundName in SOUND_NAMES do
		local sound = humanoidRootPart:FindFirstChild(soundName)
		if sound and sound:IsA('Sound') then
			sounds[soundName] = sound
		end
	end

	return sounds
end

function CharacterSoundUtils._warnAboutServerUsage()
	warn(
		'[CharacterSoundUtils] Warning: CharacterSoundUtils is intended for client-side use. It will not work properly on the server.'
	)
end

if RunService:IsServer() then
	CharacterSoundUtils._warnAboutServerUsage()
end

return CharacterSoundUtils
