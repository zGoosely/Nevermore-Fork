--!strict
--[=[
	Helps plays back sounds in the Roblox engine.

	```lua
	SoundUtils.playFromId("rbxassetid://4255432837") -- Plays a wooshing sound
	```

	@class SoundUtils
]=]

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
const require = require("../Loader").load()

local InstanceTreeUtils = require("InstanceTreeUtils")
local RbxAssetUtils = require("RbxAssetUtils")
local SoundPromiseUtils = require("SoundPromiseUtils")

export type SoundOptions = {
	SoundId: number | string,
	[string]: any,
}

export type SoundId = RbxAssetUtils.RbxAssetIdConvertable | SoundOptions | Sound

local SoundUtils = {}
SoundUtils.soundService = SoundService
SoundUtils._propertyTemplates = {}

--[=[
	Promises that the sound is loaded.
]=]
function SoundUtils.promiseLoaded(sound: Sound)
	return SoundPromiseUtils.promiseLoaded(sound)
end

--[=[
	Plays back a template given asset id.

	```lua
	SoundUtils.playFromId("rbxassetid://4255432837") -- Plays a wooshing sound
	```

	:::tip
	The sound will be automatically cleaned up after the sound is played.
	:::

	@return Sound
]=]
function SoundUtils.playFromId(id: SoundId): Sound
	local sound = SoundUtils.createSoundFromId(id)

	if RunService:IsClient() then
		SoundService:PlayLocalSound(sound)
	else
		sound:Play()
	end

	SoundUtils.removeAfterTimeLength(sound)

	return sound
end

--[=[
	Creates a sound template from `baseId`, then applies the asset and properties
	from `overwriteId`.

	@within SoundUtils
	@param baseId SoundId
	@param overwriteId SoundId
	@return Sound
]=]
function SoundUtils.cloneMerge(baseId: SoundId, overwriteId: SoundId): Sound
	assert(SoundUtils.isConvertableToRbxAsset(baseId), "Bad baseId")
	assert(SoundUtils.isConvertableToRbxAsset(overwriteId), "Bad overwriteId")

	local soundId = assert(SoundUtils.toRbxAssetId(overwriteId), "Unable to convert overwriteId")
	local sound = SoundUtils.createSoundFromId(baseId)
	sound.SoundId = soundId
	SoundUtils.applyPropertiesFromId(sound, overwriteId)

	return sound
end

--[=[
	Creates a new sound object from the given id
]=]
function SoundUtils.createSoundFromId(id: SoundId): Sound
	if typeof(id) == "Instance" and id:IsA("Sound") then
		local copy = Instance.fromExisting(id)
		copy.Archivable = false

		for _, child in id:GetChildren() do
			if child:IsA("SoundEffect") then
				Instance.fromExisting(child).Parent = copy
			end
		end

		return copy
	end

	local soundId = SoundUtils.toRbxAssetId(id)
	assert(type(soundId) == "string", "Bad id")

	local sound = Instance.new("Sound")
	sound.Archivable = false

	SoundUtils.applyPropertiesFromId(sound, id)

	return sound
end

function SoundUtils.applyPropertiesFromId(sound: Sound, id: SoundId): ()
	local soundId = assert(SoundUtils.toRbxAssetId(id), "Unable to convert id to rbxassetid")

	sound.Name = string.format("Sound_%s", soundId)
	sound.SoundId = soundId
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.Volume = 0.25

	if type(id) == "table" then
		local properties = id :: any

		for property, value in properties do
			if property ~= "Parent" and property ~= "RollOffMinDistance" and property ~= "children" then
				(sound :: any)[property] = value
			end
		end

		if properties.RollOffMinDistance then
			sound.RollOffMinDistance = properties.RollOffMinDistance
		end

		-- Create children instances (like sound effects)
		if properties.children then
			for _, childTree in ipairs(properties.children) do
				local childInstance = InstanceTreeUtils.createInstanceTree(childTree)
				childInstance.Parent = sound
			end
		end

		if properties.Parent then
			sound.Parent = properties.Parent
		end
	elseif typeof(id) == "Instance" and id:IsA("Sound") then
		sound.Volume = id.Volume
	end
end

--[=[
	Plays back a template given asset id in the parent
]=]
function SoundUtils.playFromIdInParent(id: SoundId, parent: Instance): Sound
	assert(typeof(parent) == "Instance", "Bad parent")

	local sound = SoundUtils.createSoundFromId(id)
	sound.Parent = parent

	sound:Play()

	SoundUtils.removeAfterTimeLength(sound)

	return sound
end

--[=[
	Plays back a sound with custom properties in the parent
]=]
function SoundUtils.playFromIdInParentWithProperties(
	id: string | number,
	parent: Instance,
	properties: { [string]: any }
): Sound
	assert(typeof(parent) == "Instance", "Bad parent")

	local soundOptions = { SoundId = id }
	for prop, value in properties do
		soundOptions[prop] = value
	end

	local sound = SoundUtils.createSoundFromId(soundOptions)
	sound.Parent = parent

	sound:Play()

	SoundUtils.removeAfterTimeLength(sound)

	return sound
end

--[=[
	Plays a sound at a specific CFrame position
]=]
function SoundUtils.playAtCFrame(id: SoundId, cframe: CFrame): Sound
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = cframe
	part.Parent = workspace

	local sound = SoundUtils.createSoundFromId(id)
	sound.Parent = part
	sound:Play()

	SoundUtils.removeAfterTimeLength(sound)

	return sound
end

--[=[
	Plays a sound at a specific position
]=]
function SoundUtils.playAtPosition(id: SoundId, position: Vector3): Sound
	return SoundUtils.playAtCFrame(id, CFrame.new(position))
end

--[=[
	Stops all sounds in a parent instance
]=]
function SoundUtils.stopAllSounds(parent: Instance)
	for _, descendant in parent:GetDescendants() do
		if descendant:IsA("Sound") and descendant.IsPlaying then
			descendant:Stop()
		end
	end
end

--[=[
	Fades out a sound over a duration
]=]
function SoundUtils.fadeOut(sound: Sound, duration: number)
	local startVolume = sound.Volume
	local startTime = os.clock()

	while os.clock() - startTime < duration do
		local alpha = (os.clock() - startTime) / duration
		sound.Volume = startVolume * (1 - alpha)
		task.wait()
	end

	sound:Stop()
	sound.Volume = startVolume
end

--[=[
	Loads the sound and then cleans up the sound after load.

	@param sound Sound
]=]
function SoundUtils.removeAfterTimeLength(sound: Sound): ()
	SoundUtils.promiseLoaded(sound):Then(function()
		task.delay(sound.TimeLength + 0.05, function()
			sound:Destroy()
		end)
	end, function()
		sound:Destroy()
	end)
end

--[=[
	Plays back a template given the templateName.

	:::tip
	The sound will be automatically cleaned up after the sound is played.
	:::

	@param templates TemplateProvider
	@param templateName string
	@return Sound
]=]
function SoundUtils.playTemplate(templates, templateName: string): Sound
	assert(type(templates) == "table", "Bad templates")
	assert(type(templateName) == "string", "Bad templateName")

	local sound = templates:Clone(templateName)
	sound.Archivable = false

	SoundService:PlayLocalSound(sound)

	SoundUtils.removeAfterTimeLength(sound)

	return sound
end

--[=[
	Converts a string or number to a string for playback.

	@function toRbxAssetId
	@param id string? | number
	@return string?
	@within SoundUtils
]=]
function SoundUtils.toRbxAssetId(soundId: SoundId): string?
	if typeof(soundId) == "Instance" and soundId:IsA("Sound") then
		return soundId.SoundId
	elseif type(soundId) == "table" then
		return RbxAssetUtils.toRbxAssetId(soundId.SoundId)
	else
		return RbxAssetUtils.toRbxAssetId(soundId)
	end
end

function SoundUtils.isConvertableToRbxAsset(soundId: SoundId): boolean
	if typeof(soundId) == "Instance" and soundId:IsA("Sound") then
		return RbxAssetUtils.isConvertableToRbxAsset(soundId.SoundId)
	elseif type(soundId) == "table" then
		return RbxAssetUtils.isConvertableToRbxAsset(soundId.SoundId)
	else
		return RbxAssetUtils.isConvertableToRbxAsset(soundId)
	end
end

--[=[
	Creates a reusable property template for sounds.

	```lua
	SoundUtils.createPropertyTemplate('Quiet', { Volume = 0.3 })
	SoundUtils.createPropertyTemplate('Loud', { Volume = 1.0, RollOffMaxDistance = 100 })
	```

	@param templateName string
	@param properties table
]=]
function SoundUtils.createPropertyTemplate(templateName: string, properties: { [string]: any })
	assert(type(templateName) == "string", "Bad templateName")
	assert(type(properties) == "table", "Bad properties")

	SoundUtils._propertyTemplates[templateName] = properties

	return function()
		SoundUtils._propertyTemplates[templateName] = nil
	end
end

--[=[
	Applies properties from a template to a sound.

	```lua
	SoundUtils.createPropertyTemplate('Quiet', { Volume = 0.3 })
	local sound = Instance.new('Sound')
	SoundUtils.applyPropertiesFromTemplate(sound, 'Quiet')
	```

	@param sound Sound
	@param templateName string
]=]
function SoundUtils.applyPropertiesFromTemplate(sound: Sound, templateName: string)
	assert(typeof(sound) == "Instance" and sound:IsA("Sound"), "Bad sound")
	assert(type(templateName) == "string", "Bad templateName")

	local template = SoundUtils._propertyTemplates[templateName]
	assert(template, string.format("Template %q does not exist", templateName))

	for property, value in template do
		if property ~= "Parent" then
			(sound :: any)[property] = value
		end
	end

	if template.Parent then
		sound.Parent = template.Parent
	end
end

--[=[
	Gets a property template by name.

	@param templateName string
	@return table?
]=]
function SoundUtils.getPropertyTemplate(templateName: string): { [string]: any }?
	return SoundUtils._propertyTemplates[templateName]
end

--[=[
	Removes a property template.

	@param templateName string
]=]
function SoundUtils.removePropertyTemplate(templateName: string)
	SoundUtils._propertyTemplates[templateName] = nil
end

--[=[
	Plays back a sound template in a specific parent.

	:::tip
	The sound will be automatically cleaned up after the sound is played.
	:::

	@param templates TemplateProvider
	@param templateName string
	@param parent Instance
	@return Sound
]=]
function SoundUtils.playTemplateInParent(templates, templateName: string, parent: Instance): Sound
	local sound: Sound = templates:Clone(templateName)
	sound.Archivable = false
	sound.Parent = parent

	sound:Play()

	SoundUtils.removeAfterTimeLength(sound)

	return sound
end

return SoundUtils
