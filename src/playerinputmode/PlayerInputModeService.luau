--!strict
--[=[
	Validates input-mode reports from each client and exposes the result through a
	replicated Player attribute.

	@server
	@class PlayerInputModeService
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const PlayerInputModeNetwork = require("PlayerInputModeNetwork")
const PlayerInputModeServiceConstants = require("PlayerInputModeServiceConstants")
const PlayerInputModeUtils = require("PlayerInputModeUtils")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PlayerInputModeService = {}
PlayerInputModeService.ServiceName = "PlayerInputModeService"
PlayerInputModeService.ServerOnly = true

export type PlayerInputModeService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_lastUpdateTimes: { [Player]: number },
	},
	{} :: typeof({ __index = PlayerInputModeService })
))

function PlayerInputModeService.Init(self: PlayerInputModeService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._lastUpdateTimes = setmetatable({}, { __mode = "k" }) :: any
end

function PlayerInputModeService.Start(self: PlayerInputModeService)
	PlayerInputModeNetwork.packets.inputModeChanged.listen(function(networkCode: number, player: Player?)
		if player then
			self:_handleInputModeChanged(player, networkCode)
		end
	end)
end

--[=[
	Returns a player's last validated input mode.

	@within PlayerInputModeService
	@param player Player
	@return PlayerInputModeType?
]=]
function PlayerInputModeService.GetPlayerInputModeType(
	_self: PlayerInputModeService,
	player: Player
): PlayerInputModeUtils.PlayerInputModeType?
	assert(t.instanceIsA("Player")(player), "Bad player")
	return PlayerInputModeUtils.getPlayerInputModeType(player)
end

--[=[
	Resolves when a player reports their first valid input mode.

	@within PlayerInputModeService
	@param player Player
	@param cancelToken CancelToken?
	@return Promise<PlayerInputModeType>
]=]
function PlayerInputModeService.GetPlayerInputModeAsync(
	_self: PlayerInputModeService,
	player: Player,
	cancelToken: any?
): Promise.Promise<PlayerInputModeUtils.PlayerInputModeType>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return PlayerInputModeUtils.getPlayerInputModeAsync(player, cancelToken)
end

--[=[
	Observes a player's validated input mode.

	@within PlayerInputModeService
	@param player Player
	@return Observable<PlayerInputModeType?>
]=]
function PlayerInputModeService.ObservePlayerInputType(
	_self: PlayerInputModeService,
	player: Player
): Observable.Observable<PlayerInputModeUtils.PlayerInputModeType?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return PlayerInputModeUtils.observePlayerInputModeType(player)
end

function PlayerInputModeService._handleInputModeChanged(
	self: PlayerInputModeService,
	player: Player,
	networkCode: number
)
	const playerInputModeType = PlayerInputModeUtils.fromNetworkCode(networkCode)
	if not playerInputModeType then
		return
	end
	if PlayerInputModeUtils.getPlayerInputModeType(player) == playerInputModeType then
		return
	end

	const now = os.clock()
	const lastUpdateTime = self._lastUpdateTimes[player]
	if lastUpdateTime and now - lastUpdateTime < PlayerInputModeServiceConstants.MIN_SERVER_UPDATE_INTERVAL then
		return
	end

	self._lastUpdateTimes[player] = now
	PlayerInputModeUtils.setPlayerInputModeType(player, playerInputModeType)
end

function PlayerInputModeService.Destroy(self: PlayerInputModeService)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return PlayerInputModeService
