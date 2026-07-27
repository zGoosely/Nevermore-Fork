--!strict
--[=[
	Read-only client model for one replicated or locally predicted cooldown.

	@class CooldownClient
	@client
]=]

const require = require("../../Loader").load()

const CooldownBase = require("CooldownBase")
const CooldownServiceTypes = require("CooldownServiceTypes")

type Clock = CooldownServiceTypes.Clock

const CooldownClient = setmetatable({}, CooldownBase)
CooldownClient.ClassName = "CooldownClient"
CooldownClient.__index = CooldownClient

export type CooldownClient =
	typeof(setmetatable({} :: {}, {} :: typeof({ __index = CooldownClient })))
	& CooldownBase.CooldownBase

const modelsByFolder: { [Folder]: CooldownClient } = setmetatable({}, { __mode = "kv" }) :: any

function CooldownClient.new(folder: Folder, clock: Clock): CooldownClient
	const existing = modelsByFolder[folder]
	if existing then
		return existing
	end

	const self = setmetatable(CooldownBase.new(folder, clock) :: any, CooldownClient) :: CooldownClient
	modelsByFolder[folder] = self
	self._maid:Add(function()
		if modelsByFolder[folder] == self then
			modelsByFolder[folder] = nil
		end
	end)
	return self
end

return CooldownClient
