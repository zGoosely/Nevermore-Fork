--!strict
--[=[
	Publishes this server and maintains one lazy, shared place-server directory cache.

	@class ServerListService
	@server
]=]

const Players = game:GetService("Players")
const BindToCloseService = require("@game/ReplicatedStorage/Packages/BindToCloseService")
const GameVersionUtils = require("@game/ReplicatedStorage/Packages/GameVersionUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const RateLimiter = require("@game/ReplicatedStorage/Packages/RateLimiter")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const ServerListConstants = require("./Shared/ServerListConstants")
const ServerListNameUtils = require("./Shared/ServerListNameUtils")
const ServerListNetwork = require("./Shared/ServerListNetwork")
const ServerListRegistry = require("./Server/ServerListRegistry")
const ServerListTypes = require("./Shared/ServerListTypes")
const ServerListUtils = require("./Shared/ServerListUtils")
const ServerRegionService = require("@game/ServerStorage/ServerPackages/ServerRegionService")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const TeleportServiceUtils = require("@game/ReplicatedStorage/Packages/TeleportServiceUtils")
const t = require("@game/ReplicatedStorage/Packages/t")

type RegionSource = ServerListTypes.RegionSource
type ServerMetadata = ServerListTypes.ServerMetadata
type ServerType = ServerListTypes.ServerType

const ServerListService = {}
ServerListService.ServiceName = "ServerListService"
ServerListService.ServerOnly = true

export type ServerListService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_serverRegionService: ServerRegionService.ServerRegionService,
		_registry: ServerListRegistry.ServerListRegistry,
		_cache: { ServerMetadata },
		_subscribers: { [Player]: true },
		_subscriberCount: number,
		_rateLimiters: { [Player]: RateLimiter.RateLimiter },
		_jobId: string,
		_name: string,
		_serverType: ServerType,
		_region: string?,
		_regionSource: RegionSource,
		_startedAt: number,
	},
	{} :: typeof({ __index = ServerListService })
))

function ServerListService.Init(self: ServerListService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService)
	self._serverRegionService = self._serviceBag:GetService(ServerRegionService)
	self._registry = self._maid:Add(ServerListRegistry.new(game.PlaceId))
	self._cache = ServerListUtils.createSnapshot({})
	self._subscribers = {}
	self._subscriberCount = 0
	self._rateLimiters = {}
	self._jobId = ServerListNameUtils.resolveJobId(game.JobId, game.PlaceId, game.PlaceVersion)
	self._name = ServerListNameUtils.generateName(self._jobId)
	self._serverType = GameVersionUtils.getServerType()
	self._region = nil
	self._regionSource = "unknown"
	self._startedAt = os.time()

	self._maid:Add(self._bindToCloseService:RegisterPromiseOnCloseCallback(function()
		if not ServerListUtils.isListedServerType(self._serverType) then
			return Promise.resolved()
		end
		return self._registry:RemoveAsync(self._jobId)
	end))
end

function ServerListService.Start(self: ServerListService): ()
	self:_listenToNetwork()

	self._maid:Add(self._serverRegionService:PromiseRegion():Then(function(region: string)
		self:SetRegion(region, "external")
		self:_publishAsync():Catch(function(errorMessage)
			warn(`[ServerListService] - Publish failed after region update ({errorMessage})`)
		end)
	end))

	self._maid:Add(Players.PlayerRemoving:Connect(function(player: Player)
		self:_setSubscribed(player, false)
		const rateLimiter = self._rateLimiters[player]
		if rateLimiter then
			self._rateLimiters[player] = nil
			rateLimiter:Destroy()
		end
	end))

	self._maid:Add(Rx.interval(ServerListConstants.PUBLISH_INTERVAL_SECONDS):Subscribe(function()
		self:_publishAsync():Catch(function(errorMessage)
			warn(`[ServerListService] - Publish failed ({errorMessage})`)
		end)
	end))
	self._maid:Add(Rx.interval(ServerListConstants.REFRESH_INTERVAL_SECONDS):Subscribe(function()
		if self._subscriberCount == 0 then
			return
		end
		self:_refreshAsync():Catch(function(errorMessage)
			warn(`[ServerListService] - Refresh failed; retaining previous cache ({errorMessage})`)
		end)
	end))
end

--[=[
	Sets honest optional region metadata. The source identifies who supplied the value;
	it does not imply physical-region inference.

	@within ServerListService
	@param region string?
	@param source RegionSource
]=]
function ServerListService.SetRegion(self: ServerListService, region: string?, source: RegionSource): ()
	assert(
		t.optional(t.string)(region)
			and (region == nil or (region ~= "" and #region <= ServerListConstants.MAX_REGION_LENGTH)),
		"Bad region"
	)
	assert(ServerListUtils.isRegionSource(source), "Bad source")
	assert(ServerListUtils.isRegionConfiguration(region, source), "Region and source do not agree")
	self._region = region
	self._regionSource = source
end

function ServerListService._listenToNetwork(self: ServerListService): ()
	const subscriptionChanged = ServerListNetwork.packets.subscriptionChanged
	const function handleSubscriptionChanged(isSubscribed: boolean, player: Player?)
		if not player or not self:_tryConsumeRequest(player) then
			return
		end
		self:_setSubscribed(player, isSubscribed)
	end
	subscriptionChanged.listen(handleSubscriptionChanged)
	self._maid:Add(function()
		ServerListUtils.removeNetworkListener(subscriptionChanged, handleSubscriptionChanged)
	end)

	const snapshotRequested = ServerListNetwork.packets.snapshotRequested
	const function handleSnapshotRequested(_value: nil, player: Player?)
		if not player or not self:_tryConsumeRequest(player) then
			return
		end
		self:_sendSnapshot(player)
	end
	snapshotRequested.listen(handleSnapshotRequested)
	self._maid:Add(function()
		ServerListUtils.removeNetworkListener(snapshotRequested, handleSnapshotRequested)
	end)

	const joinRequested = ServerListNetwork.packets.joinRequested
	const function handleJoinRequested(jobId: string, player: Player?)
		if not player or not self:_tryConsumeRequest(player) then
			return
		end

		self:_joinServerAsync(player, jobId):Catch(function() end)
	end
	joinRequested.listen(handleJoinRequested)
	self._maid:Add(function()
		ServerListUtils.removeNetworkListener(joinRequested, handleJoinRequested)
	end)
end

function ServerListService._publishAsync(self: ServerListService): Promise.Promise<()>
	if not ServerListUtils.isListedServerType(self._serverType) then
		return Promise.resolved()
	end

	const now = os.time()
	const metadata: ServerMetadata = {
		jobId = self._jobId,
		placeId = game.PlaceId,
		name = self._name,
		region = self._region,
		regionSource = self._regionSource,
		playerCount = Players.NumPlayers,
		maxPlayers = Players.MaxPlayers,
		serverType = self._serverType,
		placeVersion = game.PlaceVersion,
		startedAt = self._startedAt,
		updatedAt = now,
	}
	return self._registry:PublishAsync(metadata)
end

function ServerListService._refreshAsync(self: ServerListService): Promise.Promise<()>
	return self._registry:ListAsync():Then(function(servers: { ServerMetadata })
		self._cache = ServerListUtils.createSnapshot(servers)
		for player in self._subscribers do
			self:_sendSnapshot(player)
		end
	end)
end

function ServerListService._setSubscribed(self: ServerListService, player: Player, isSubscribed: boolean): ()
	if isSubscribed then
		if self._subscribers[player] then
			self:_sendSnapshot(player)
			return
		end

		self._subscribers[player] = true
		self._subscriberCount += 1
		self:_sendSnapshot(player)
		if self._subscriberCount == 1 then
			self:_refreshAsync():Catch(function(errorMessage)
				warn(`[ServerListService] - Initial refresh failed; retaining previous cache ({errorMessage})`)
			end)
		end
	elseif self._subscribers[player] then
		self._subscribers[player] = nil
		self._subscriberCount -= 1
	end
end

function ServerListService._sendSnapshot(self: ServerListService, player: Player): ()
	ServerListNetwork.packets.snapshot.sendTo(self._cache, player)
end

function ServerListService._tryConsumeRequest(self: ServerListService, player: Player): boolean
	local rateLimiter = self._rateLimiters[player]
	if not rateLimiter then
		rateLimiter = RateLimiter.new(
			ServerListConstants.REQUEST_RATE_LIMIT_CAPACITY,
			ServerListConstants.REQUEST_RATE_LIMIT_REFILL_RATE
		)
		self._rateLimiters[player] = rateLimiter
	end
	return rateLimiter:TryConsume()
end

function ServerListService._joinServerAsync(self: ServerListService, player: Player, jobId: string): Promise.Promise<()>
	if not (t.string(jobId) and jobId ~= "" and #jobId <= ServerListConstants.MAX_JOB_ID_LENGTH) then
		return Promise.rejected("Invalid job ID")
	end

	local selected: ServerMetadata? = nil
	for _, metadata in self._cache do
		if metadata.jobId == jobId then
			selected = metadata
			break
		end
	end

	if not selected or not ServerListUtils.isFresh(selected, os.time()) then
		return Promise.rejected("Server is unavailable or stale")
	end
	if selected.placeId ~= game.PlaceId then
		return Promise.rejected("Server belongs to another place")
	end
	if selected.jobId == self._jobId then
		return Promise.rejected("Already in this server")
	end
	if selected.serverType ~= "standard" then
		return Promise.rejected("Server is not public")
	end
	if selected.playerCount >= selected.maxPlayers then
		return Promise.rejected("Server is full")
	end

	const teleportPromise =
		TeleportServiceUtils.promiseTeleportToPlaceInstance(selected.placeId, selected.jobId, player, nil, nil)
	teleportPromise:Catch(function(errorMessage)
		warn(`[ServerListService] - Teleport request failed for {player} ({errorMessage})`)
	end)
	return teleportPromise
end

function ServerListService.Destroy(self: ServerListService): ()
	if ServerListUtils.isListedServerType(self._serverType) then
		self._registry:RemoveAsync(self._jobId):Catch(function(errorMessage)
			warn(`[ServerListService] - Registry removal failed ({errorMessage})`)
		end)
	end
	for player, rateLimiter in self._rateLimiters do
		self._rateLimiters[player] = nil
		rateLimiter:Destroy()
	end
	self._maid:DoCleaning()
end

return ServerListService
