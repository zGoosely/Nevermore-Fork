--!strict
--[=[
	@class TeleportServiceUtils
]=]

local TeleportService = game:GetService('TeleportService')
const require = require("../Loader").load()

local Promise = require('Promise')

local TeleportServiceUtils = {}

--[=[
	Wraps TeleportService:ReserveServer(placeId)
	@param placeId number
	@return Promise<string> -- Code
]=]
function TeleportServiceUtils.promiseReserveServer(placeId: number): Promise.Promise<number>
	assert(type(placeId) == 'number', 'Bad placeId')

	return Promise.new(function(resolve, reject)
		local accessCode
		local ok, err = pcall(function()
			accessCode = TeleportService:ReserveServer(placeId)
		end)
		if not ok then
			return reject(err)
		end

		return resolve(accessCode)
	end)
end

--[=[
	Wraps TeleportService:PromiseTeleport(placeId, players, teleportOptions)
	@param placeId number
	@param players { Player }
	@param teleportOptions TeleportOptions
	@return Promise<string> -- Code
]=]
function TeleportServiceUtils.promiseTeleport(
	placeId: number,
	players: { Player },
	teleportOptions: TeleportOptions?
): Promise.Promise<TeleportAsyncResult>
	assert(type(placeId) == 'number', 'Bad placeId')
	assert(type(players) == 'table', 'Bad players')
	assert(
		typeof(teleportOptions) == 'Instance' and teleportOptions:IsA('TeleportOptions') or teleportOptions == nil,
		'Bad options'
	)

	return Promise.new(function(resolve, reject)
		local teleportAsyncResult
		local ok, err = pcall(function()
			teleportAsyncResult = TeleportService:TeleportAsync(placeId, players, teleportOptions)
		end)
		if not ok then
			return reject(err)
		end

		return resolve(teleportAsyncResult)
	end)
end

--[=[
	Wraps TeleportService:TeleportToPlaceInstance(placeId, instanceId, player, spawnName, teleportData)
	@param placeId number
	@param instanceId string
	@param player Player
	@param spawnName string?
	@param teleportData any?
	@return Promise<()>
]=]
function TeleportServiceUtils.promiseTeleportToPlaceInstance(
	placeId: number,
	instanceId: string,
	player: Player,
	spawnName: string?,
	teleportData: any?
): Promise.Promise<()>
	assert(type(placeId) == 'number', 'Bad placeId')
	assert(type(instanceId) == 'string', 'Bad instanceId')
	assert(typeof(player) == 'Instance' and player:IsA('Player'), 'Bad player')

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			TeleportService:TeleportToPlaceInstance(placeId, instanceId, player, spawnName, teleportData)
		end)
		if not ok then
			return reject(err)
		end

		return resolve()
	end)
end

--[=[
	Wraps TeleportService:TeleportToPrivateServer(placeId, accessCode, players, spawnName, teleportData)
	@param placeId number
	@param accessCode string
	@param players { Player }
	@param spawnName string?
	@param teleportData any?
	@return Promise<()>
]=]
function TeleportServiceUtils.promiseTeleportToPrivateServer(
	placeId: number,
	accessCode: string,
	players: { Player },
	spawnName: string?,
	teleportData: any?
): Promise.Promise<()>
	assert(type(placeId) == 'number', 'Bad placeId')
	assert(type(accessCode) == 'string', 'Bad accessCode')
	assert(type(players) == 'table', 'Bad players')

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			TeleportService:TeleportToPrivateServer(placeId, accessCode, players, spawnName, teleportData)
		end)
		if not ok then
			return reject(err)
		end

		return resolve()
	end)
end

--[=[
	Wraps TeleportService:TeleportToSpawnByName(placeId, spawnName, player, teleportData)
	@param placeId number
	@param spawnName string
	@param player Player
	@param teleportData any?
	@return Promise<()>
]=]
function TeleportServiceUtils.promiseTeleportToSpawnByName(
	placeId: number,
	spawnName: string,
	player: Player,
	teleportData: any?
): Promise.Promise<()>
	assert(type(placeId) == 'number', 'Bad placeId')
	assert(type(spawnName) == 'string', 'Bad spawnName')
	assert(typeof(player) == 'Instance' and player:IsA('Player'), 'Bad player')

	return Promise.new(function(resolve, reject)
		local ok, err = pcall(function()
			TeleportService:TeleportToSpawnByName(placeId, spawnName, player, teleportData)
		end)
		if not ok then
			return reject(err)
		end

		return resolve()
	end)
end

return TeleportServiceUtils
