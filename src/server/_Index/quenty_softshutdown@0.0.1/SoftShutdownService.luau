--!strict
--[=[
	This service lets you shut down servers without losing players.
	When game.OnClose is called, players in the server are teleported into a reserved lobby server.
	When the reserved server starts up, it teleports everyone back into updated servers.

	@class SoftShutdownService
	@server
]=]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")
const Workspace = game:GetService("Workspace")
const BindToCloseService = require("@game/ReplicatedStorage/Packages/BindToCloseService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerDataStoreService = require("@game/ServerStorage/ServerPackages/PlayerDataStoreService")
const PrivateServerDataStoreService = require("@game/ServerStorage/ServerPackages/PrivateServerDataStoreService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const SoftShutdownConstants = require("./Shared/SoftShutdownConstants")
const SoftShutdownServiceUtils = require("./Server/SoftShutdownServiceUtils")
const SoftShutdownTranslator = require("./Shared/SoftShutdownTranslator")
const TeleportServiceUtils = require("@game/ReplicatedStorage/Packages/TeleportServiceUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

const SoftShutdownService = {}
SoftShutdownService.ServiceName = "SoftShutdownService"
SoftShutdownService.ServerOnly = true

export type SoftShutdownService = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_serviceBag: ServiceBag.ServiceBag,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_playerDataStoreService: PlayerDataStoreService.PlayerDataStoreService,
		_privateServerDataStoreService: PrivateServerDataStoreService.PrivateServerDataStoreService,
		_translator: any,
		_isLobby: boolean?,
	},
	{} :: typeof({ __index = SoftShutdownService })
))

--[=[
	Initialize the service. Should be done via [ServiceBag].

	@param serviceBag ServiceBag
]=]
function SoftShutdownService.Init(self: SoftShutdownService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")
	self._serviceBag = serviceBag
	self._maid = Maid.new()

	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService) :: any
	self._playerDataStoreService = self._serviceBag:GetService(PlayerDataStoreService)
	self._privateServerDataStoreService = self._serviceBag:GetService(PrivateServerDataStoreService)
	self._translator = self._serviceBag:GetService(SoftShutdownTranslator)
	self._isLobby = nil
end

function SoftShutdownService.Start(self: SoftShutdownService): ()
	const function handleLobbyStatus(isLobby: boolean)
		if self._isLobby == isLobby then
			return
		end
		self._isLobby = isLobby

		if not isLobby then
			(self._maid :: any)._shutdownRegistration = self._bindToCloseService:RegisterPromiseOnCloseCallback(
				function()
					return self:_promiseTeleportPlayersToLobby()
				end
			)

			if not SoftShutdownServiceUtils.isReservedServer() then
				return
			end

			(self._maid :: any)._lobbyPlayerAdded = Players.PlayerAdded:Connect(function(player: Player)
				if SoftShutdownServiceUtils.isLobbyTeleportPlayer(player) then
					handleLobbyStatus(true)
				end
			end)
			for _, player in Players:GetPlayers() do
				if SoftShutdownServiceUtils.isLobbyTeleportPlayer(player) then
					handleLobbyStatus(true)
					return
				end
			end

			return
		end

		(self._maid :: any)._shutdownRegistration = nil
		(self._maid :: any)._lobbyPlayerAdded = nil

		self._maid:GivePromise(self:_promiseRedirectAllPlayers()):Catch(function(errorMessage: any)
			warn(`[SoftShutdownService] - Failed to redirect waiting-server players: {errorMessage}`)
		end)
	end

	self._maid
		:GivePromise(SoftShutdownServiceUtils.promiseIsLobby(self._privateServerDataStoreService))
		:Then(handleLobbyStatus)
		:Catch(function(errorMessage: any)
			warn(`[SoftShutdownService] - Failed to check the waiting-server marker: {errorMessage}`)

			-- Ownerless reserved servers fail closed: loading ordinary server
			-- behavior there is riskier than redirecting a non-lobby reserve.
			handleLobbyStatus(SoftShutdownServiceUtils.isReservedServer())
		end)
end

function SoftShutdownService._promiseTeleportPlayersToLobby(self: SoftShutdownService): Promise.Promise<()>
	const players = Players:GetPlayers()
	if RunService:IsStudio() or #players == 0 or game.JobId == "" then
		return Promise.resolved()
	end

	Workspace:SetAttribute(SoftShutdownConstants.IS_SOFT_SHUTDOWN_UPDATING_ATTRIBUTE, true)

	return self._playerDataStoreService:SaveAllProfilesAsync():Then(function()
		const initialTeleportOptions = Instance.new("TeleportOptions")
		initialTeleportOptions.ShouldReserveServer = true
		initialTeleportOptions:SetTeleportData({
			[SoftShutdownConstants.IS_SOFT_SHUTDOWN_RESERVE_SERVER_TELEPORT_KEY] = true,
		})

		-- Collect any players remaining
		const remainingPlayers: { Player } = {}
		(self._maid :: any)._playerAddedCollector = Players.PlayerAdded:Connect(function(player: Player)
			table.insert(remainingPlayers, player)
		end)

		return Promise.spawn(function(resolve, _reject)
			-- Wait to let the teleport GUI be set
			task.delay(1, resolve)
		end)
			:Then(function()
				return TeleportServiceUtils.promiseTeleport(game.PlaceId, players, initialTeleportOptions)
			end)
			:Then(function(teleportResult: TeleportAsyncResult)
				(self._maid :: any)._playerAddedCollector = nil

				-- Construct new teleport options
				const newTeleportOptions = Instance.new("TeleportOptions")
				newTeleportOptions.ServerInstanceId = teleportResult.PrivateServerId
				newTeleportOptions.ReservedServerAccessCode = teleportResult.ReservedServerAccessCode
				newTeleportOptions:SetTeleportData({
					[SoftShutdownConstants.IS_SOFT_SHUTDOWN_RESERVE_SERVER_TELEPORT_KEY] = true,
				})

				-- Teleport any players that joined during initial teleport
				const promises = {}

				const markerPromise = self._privateServerDataStoreService
					:PromiseDataStoreForKey(teleportResult.PrivateServerId)
					:Then(function(dataStore)
						dataStore:Store(SoftShutdownConstants.IS_SOFT_SHUTDOWN_LOBBY_DATASTORE_KEY, true)
						return dataStore:Save()
					end)

				if #remainingPlayers > 0 then
					table.insert(
						promises,
						TeleportServiceUtils.promiseTeleport(game.PlaceId, remainingPlayers, newTeleportOptions)
					)
				end

				self._maid:GiveTask(Players.PlayerAdded:Connect(function(player: Player)
					table.insert(
						promises,
						TeleportServiceUtils.promiseTeleport(game.PlaceId, { player }, newTeleportOptions)
					)
				end))

				return Promise.spawn(function(resolve, reject)
					const markedLobby, markerError = markerPromise:Yield()

					while #Players:GetPlayers() > 0 and SoftShutdownServiceUtils.containsPending(promises) do
						task.wait(1)
					end

					if not markedLobby then
						reject(markerError)
						return
					end

					resolve()
				end)
			end)
	end)
end

function SoftShutdownService._promiseRedirectAllPlayers(self: SoftShutdownService): Promise.Promise<()>
	Workspace:SetAttribute(SoftShutdownConstants.IS_SOFT_SHUTDOWN_LOBBY_ATTRIBUTE, true)

	-- Wait for some players
	return Promise.spawn(function(resolve, reject)
		task.wait(1) -- Let the teleport GUI be set
		local players = Players:GetPlayers()
		while #players <= 0 do
			task.wait(1)
			players = Players:GetPlayers()
		end

		self._maid:GiveTask(reject)

		resolve(players)
	end):Then(function(players: { Player })
		const teleportOptions = Instance.new("TeleportOptions")
		teleportOptions:SetTeleportData({
			[SoftShutdownConstants.IS_SOFT_SHUTDOWN_UPDATED_SERVER_TELEPORT_KEY] = true,
		})

		-- Teleport all remaining players
		self._maid:GiveTask(Players.PlayerAdded:Connect(function(player: Player)
			task.wait(1) -- Let the teleport GUI be set
			TeleportServiceUtils.promiseTeleport(game.PlaceId, { player }, teleportOptions)
		end))

		-- Try to keep players in the same group
		return TeleportServiceUtils.promiseTeleport(game.PlaceId, players, teleportOptions)
	end)
end

function SoftShutdownService.Destroy(self: SoftShutdownService): ()
	self._maid:DoCleaning()
end

return SoftShutdownService
