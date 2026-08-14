--!strict
--[=[
	Owns avatar-catalog enforcement for one player humanoid through its binder lifetime.

	@class AvatarCatalogHumanoid
	@server
]=]

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")

const BaseObject = require("@game/ReplicatedStorage/Packages/BaseObject")
const t = require("@game/ReplicatedStorage/Packages/t")

const AvatarCatalogServiceInterface = require("../AvatarCatalogServiceInterface")

const AvatarCatalogHumanoid = setmetatable({}, BaseObject)
AvatarCatalogHumanoid.ClassName = "AvatarCatalogHumanoid"
AvatarCatalogHumanoid.__index = AvatarCatalogHumanoid

export type AvatarCatalogHumanoid =
	typeof(setmetatable(
		{} :: {
			_obj: Humanoid,
			_player: Player?,
			_avatarCatalogService: AvatarCatalogServiceInterface.AvatarCatalogServiceInterface,
		},
		{} :: typeof({ __index = AvatarCatalogHumanoid })
	))
	& BaseObject.BaseObject

function AvatarCatalogHumanoid.new(humanoid: Humanoid): AvatarCatalogHumanoid
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")

	const self = setmetatable(BaseObject.new(humanoid) :: any, AvatarCatalogHumanoid) :: AvatarCatalogHumanoid
	self._player = if humanoid.Parent then Players:GetPlayerFromCharacter(humanoid.Parent) else nil
	self._avatarCatalogService = AvatarCatalogServiceInterface.Server:Get(ReplicatedStorage)

	if self._player then
		self._maid:Add(self._player.CharacterAppearanceLoaded:Connect(function(character: Model)
			if character == self._obj.Parent then
				self:_update()
			end
		end))
	end
	self._maid:Add(self._avatarCatalogService:ObserveUpdateRequested():Subscribe(function()
		self:_update()
	end))

	return self
end

function AvatarCatalogHumanoid._update(self: AvatarCatalogHumanoid): ()
	if self._obj.Parent == nil then
		return
	end
	if self._player and (self._player.Character ~= self._obj.Parent or not self._player:HasAppearanceLoaded()) then
		return
	end

	const promise = self._avatarCatalogService:EnforceAsync(self._obj):Catch(function(err)
		warn(`[AvatarCatalogHumanoid] Could not enforce avatar replacements: {err}`)
	end)
	self._maid:GivePromise(promise)
end

function AvatarCatalogHumanoid.Destroy(self: AvatarCatalogHumanoid): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return AvatarCatalogHumanoid
