--!strict
--[=[
	Shared server-side rules for identifying soft-shutdown waiting servers.

	@util SoftShutdownServiceUtils
	@server
]=]

const Players = game:GetService("Players")
const DataStore = require("@game/ReplicatedStorage/Packages/DataStore")
const PrivateServerDataStoreService = require("@game/ReplicatedStorage/Packages/PrivateServerDataStoreService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const SoftShutdownConstants = require("../Shared/SoftShutdownConstants")
const t = require("@game/ReplicatedStorage/Packages/t")

const LOBBY_CHECK_ATTEMPTS = 10
const LOBBY_CHECK_INTERVAL_SECONDS = 0.5

const SoftShutdownServiceUtils = {}

--[=[
	Returns whether this process is an ownerless reserved server.

	@within SoftShutdownServiceUtils
	@return boolean
]=]
function SoftShutdownServiceUtils.isReservedServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

--[=[
	Returns whether a player arrived through the soft-shutdown lobby teleport.

	@within SoftShutdownServiceUtils
	@param player Player
	@return boolean
]=]
function SoftShutdownServiceUtils.isLobbyTeleportPlayer(player: Player): boolean
	assert(t.instanceIsA("Player")(player), "Bad player")

	const success, joinData = pcall(player.GetJoinData, player)
	if not success or not t.table(joinData) or not t.table(joinData.TeleportData) then
		return false
	end

	return joinData.TeleportData[SoftShutdownConstants.IS_SOFT_SHUTDOWN_RESERVE_SERVER_TELEPORT_KEY] == true
end

--[=[
	Checks the private-server datastore marker and teleport metadata to determine
	whether this process is a soft-shutdown waiting server.

	The repeated uncached sync covers the short race between Roblox starting the
	reserved process and the source server receiving its private-server ID.

	@within SoftShutdownServiceUtils
	@param privateServerDataStoreService PrivateServerDataStoreService
	@return Promise<boolean>
]=]
function SoftShutdownServiceUtils.promiseIsLobby(
	privateServerDataStoreService: PrivateServerDataStoreService.PrivateServerDataStoreService
): Promise.Promise<boolean>
	assert(t.table(privateServerDataStoreService), "Bad privateServerDataStoreService")

	if not SoftShutdownServiceUtils.isReservedServer() then
		return Promise.resolved(false)
	end

	return Promise.spawn(function(resolve, reject)
		const resolvedDataStore, dataStoreOrError = privateServerDataStoreService:PromiseDataStore():Yield()
		if not resolvedDataStore then
			reject(dataStoreOrError)
			return
		end

		const dataStore = dataStoreOrError :: DataStore.DataStore
		local lastError = nil

		for attempt = 1, LOBBY_CHECK_ATTEMPTS do
			for _, player in Players:GetPlayers() do
				if SoftShutdownServiceUtils.isLobbyTeleportPlayer(player) then
					resolve(true)
					return
				end
			end

			if attempt > 1 then
				const synced, syncError = dataStore:Sync():Yield()
				if not synced then
					lastError = syncError
				end
			end

			const loaded, valueOrError =
				dataStore:Load(SoftShutdownConstants.IS_SOFT_SHUTDOWN_LOBBY_DATASTORE_KEY, false):Yield()
			if loaded then
				if valueOrError == true then
					resolve(true)
					return
				end
			else
				lastError = valueOrError
			end

			if attempt < LOBBY_CHECK_ATTEMPTS then
				task.wait(LOBBY_CHECK_INTERVAL_SECONDS)
			end
		end

		if lastError ~= nil then
			reject(lastError)
			return
		end

		resolve(false)
	end)
end

--[=[
	Returns whether a promise list contains at least one pending promise.

	@within SoftShutdownServiceUtils
	@param promises { Promise }
	@return boolean
]=]
function SoftShutdownServiceUtils.containsPending(promises: { any }): boolean
	assert(t.table(promises), "Bad promises")

	for _, promise in promises do
		if Promise.isPromise(promise) and promise:IsPending() then
			return true
		end
	end

	return false
end

return SoftShutdownServiceUtils
