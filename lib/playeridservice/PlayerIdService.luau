--!strict
--!optimize 2
--[=[
	Assigns stable, recycled uint8 IDs to current players. IDs replicate through a
	Player attribute and can be sent directly through compact network schemas.

	@class PlayerIdService
	@server
]=]

const Players = game:GetService("Players")

const require = require("../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const PlayerIdServiceConstants = require("PlayerIdServiceConstants")
const PlayerIdServiceInterface = require("PlayerIdServiceInterface")
const PlayerIdServiceUtils = require("PlayerIdServiceUtils")
const RxPlayerUtils = require("RxPlayerUtils")
const ServiceBag = require("ServiceBag")
const TableUtils = require("TableUtils")
const TieRealmService = require("TieRealmService")
const t = require("t")

export type IdAssignments = { [Player]: number }

const PlayerIdService = {}
PlayerIdService.ServiceName = "PlayerIdService"
PlayerIdService.ServerOnly = true

export type PlayerIdService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_idsByPlayer: { [Player]: number },
		_playersById: { [number]: Player },
		_random: Random,
	},
	{} :: typeof({ __index = PlayerIdService })
))

function PlayerIdService.Init(self: PlayerIdService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._idsByPlayer = {}
	self._playersById = {}
	self._random = Random.new()

	assert(
		Players.MaxPlayers <= PlayerIdServiceConstants.MAX_PLAYER_ID,
		`Players.MaxPlayers exceeds the uint8 limit ({PlayerIdServiceConstants.MAX_PLAYER_ID})`
	)

	self._serviceBag:GetService(TieRealmService)
	self._maid:Add((PlayerIdServiceInterface :: any).Server:Implement(Players, self))
end

function PlayerIdService.Start(self: PlayerIdService): ()
	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()
		self:_assignAvailableId(player)

		maid:Add(function()
			self:_releaseId(player)
		end)
	end))
end

--[=[
	Returns a player's current ID, or nil while unassigned.

	@within PlayerIdService
	@param player Player
	@return number?
]=]
function PlayerIdService.GetId(_self: PlayerIdService, player: Player): number?
	return PlayerIdServiceUtils.getId(player)
end

--[=[
	Observes a player's replicated ID with RxAttributeUtils.

	@within PlayerIdService
	@param player Player
	@return Observable<number?>
]=]
function PlayerIdService.Observe(_self: PlayerIdService, player: Player): Observable.Observable<number?>
	return PlayerIdServiceUtils.observeId(player)
end

PlayerIdService.ObserveId = PlayerIdService.Observe

--[=[
	Returns the current player owning an ID.

	@within PlayerIdService
	@param playerId number
	@return Player?
]=]
function PlayerIdService.GetPlayer(self: PlayerIdService, playerId: number): Player?
	assert(PlayerIdServiceUtils.isPlayerId(playerId), "Bad playerId")
	return self._playersById[playerId]
end

--[=[
	Randomly reassigns every current player a unique ID in the compact
	`1..Players.MaxPlayers` range.

	@within PlayerIdService
]=]
function PlayerIdService.RefreshIds(self: PlayerIdService): ()
	const players = Players:GetPlayers()
	const availableIds = self:_createAutomaticIdPool()
	const assignments: IdAssignments = {}

	for _, player in players do
		assignments[player] = self:_takeRandomId(availableIds)
	end

	self:_applyIds(assignments)
end

--[=[
	Applies a partial set of requested IDs. Requested assignments take priority;
	players displaced by collisions are automatically moved to unused compact
	IDs. Duplicate requested IDs and players outside the server are rejected.

	@within PlayerIdService
	@param requestedIds { [Player]: number }
]=]
function PlayerIdService.SetIds(self: PlayerIdService, requestedIds: IdAssignments): ()
	assert(type(requestedIds) == "table", "Bad requestedIds")
	const currentPlayers: { [Player]: true } = {}
	for _, player in Players:GetPlayers() do
		currentPlayers[player] = true
	end

	const assignments: IdAssignments = {}
	const usedIds: { [number]: true } = {}

	for player, playerId in requestedIds do
		assert(t.instanceIsA("Player")(player) and currentPlayers[player], "Player is not in this server")
		assert(PlayerIdServiceUtils.isPlayerId(playerId), "Bad playerId")
		assert(not usedIds[playerId], `Duplicate requested playerId {playerId}`)

		assignments[player] = playerId
		usedIds[playerId] = true
	end

	-- Keep unaffected players stable unless their ID was explicitly claimed.
	for player in currentPlayers do
		if assignments[player] then
			continue
		end

		const currentId = self._idsByPlayer[player]

		if currentId and not usedIds[currentId] then
			assignments[player] = currentId
			usedIds[currentId] = true
		end
	end

	const availableIds = self:_createAutomaticIdPool(usedIds)

	for player in currentPlayers do
		if not assignments[player] then
			assignments[player] = self:_takeRandomId(availableIds)
		end
	end

	self:_applyIds(assignments)
end

function PlayerIdService._assignAvailableId(self: PlayerIdService, player: Player): ()
	if self._idsByPlayer[player] then
		return
	end

	const availableIds = self:_createAutomaticIdPool()
	if #availableIds == 0 then
		warn(`[PlayerIdService] - No uint8 ID available for {player.Name}`)

		return
	end

	const playerId = self:_takeRandomId(availableIds)

	self._idsByPlayer[player] = playerId
	self._playersById[playerId] = player

	player:SetAttribute(PlayerIdServiceConstants.PLAYER_ID_ATTRIBUTE, playerId)
end

function PlayerIdService._releaseId(self: PlayerIdService, player: Player): ()
	const playerId = self._idsByPlayer[player]
	if not playerId then
		return
	end

	self._idsByPlayer[player] = nil
	if self._playersById[playerId] == player then
		self._playersById[playerId] = nil
	end

	player:SetAttribute(PlayerIdServiceConstants.PLAYER_ID_ATTRIBUTE, nil)
end

function PlayerIdService._createAutomaticIdPool(self: PlayerIdService, usedIds: { [number]: true }?): { number }
	const availableIds = table.create(Players.MaxPlayers)

	for playerId = PlayerIdServiceConstants.MIN_PLAYER_ID, Players.MaxPlayers do
		const isUsed = if usedIds then usedIds[playerId] == true else self._playersById[playerId] ~= nil

		if not isUsed then
			table.insert(availableIds, playerId)
		end
	end

	return availableIds
end

function PlayerIdService._takeRandomId(self: PlayerIdService, availableIds: { number }): number
	assert(#availableIds > 0, "No player ID available")

	const index = self._random:NextInteger(1, #availableIds)
	return assert(TableUtils.swapRemove(availableIds, index))
end

function PlayerIdService._applyIds(self: PlayerIdService, assignments: IdAssignments): ()
	table.clear(self._idsByPlayer)
	table.clear(self._playersById)

	for player, playerId in assignments do
		self._idsByPlayer[player] = playerId
		self._playersById[playerId] = player
	end

	for player, playerId in assignments do
		if PlayerIdServiceUtils.getId(player) ~= playerId then
			player:SetAttribute(PlayerIdServiceConstants.PLAYER_ID_ATTRIBUTE, playerId)
		end
	end
end

function PlayerIdService.Destroy(self: PlayerIdService): ()
	self._maid:Destroy()
	table.clear(self._idsByPlayer)
	table.clear(self._playersById)
end

return PlayerIdService
