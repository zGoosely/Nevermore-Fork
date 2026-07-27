--!strict
--[=[
	@class BanService
]=]

const Players = game:GetService("Players")

const require = require("../Loader").load()

const BanServiceUtils = require("BanServiceUtils")
const CmdrService = require("CmdrService")
const Maid = require("Maid")
const PlayerDataStoreService = require("PlayerDataStoreService")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PERMANENT_DURATION = -1
const APPLY_TO_UNIVERSE = true
const EXCLUDE_ALT_ACCOUNTS = false
const APPLY_DEVICE_BLOCK = false
const DISPLAY_REASON = "You have been banned from this experience."
const PRIVATE_REASON = "Banned by an experience moderator."

type BanHistoryEntry = BanServiceUtils.BanHistoryEntry

const BanService = {}
BanService.ServiceName = "BanService"
BanService.ServerOnly = true

export type BanService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,

		_playerDataStoreService: PlayerDataStoreService.PlayerDataStoreService,
		_cmdrService: CmdrService.CmdrService,
	},
	{} :: typeof({ __index = BanService })
))

function BanService.Init(self: BanService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._playerDataStoreService = self._serviceBag:HasService(PlayerDataStoreService)
			and self._serviceBag:GetService(PlayerDataStoreService)
		or nil :: any
	self._cmdrService = self._serviceBag:GetService(CmdrService)

	self._cmdrService:RegisterCommand({
		Name = "ban-permenantly",
		Description = "Permanently bans a player.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "target",
				Description = "The player to ban.",
			},
		},
		Run = function(_, target: Player)
			const success, resultOrError = self:BanPermanentlyAsync(target):Yield()
			if not success then
				return `Could not permanently ban {target.Name}: {tostring(resultOrError)}.`
			end

			return `Permanently banned {target.Name}.`
		end,
	})

	self._cmdrService:RegisterCommand({
		Name = "ban-duration",
		Description = "Bans a player for a number of seconds.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "target",
				Description = "The player to ban.",
			},
			{
				Type = "positiveInteger",
				Name = "seconds",
				Description = "The ban duration in seconds.",
			},
		},
		Run = function(_, target: Player, seconds: number)
			const success, resultOrError = self:BanDurationAsync(target, seconds):Yield()
			if not success then
				return `Could not ban {target.Name} for {seconds} seconds: {tostring(resultOrError)}.`
			end

			return `Banned {target.Name} for {seconds} seconds.`
		end,
	})
end

--[=[
	Bans a player for a duration in seconds.

	@within BanService
	@param player Player
	@param seconds number
	@return Promise<()>
]=]
function BanService.BanDurationAsync(self: BanService, player: Player, seconds: number): Promise.Promise<()>
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.numberPositive(seconds), "Bad number")

	return self:_banAsync(player, seconds)
end

--[=[
	Permanently bans a player.

	@within BanService
	@param player Player
	@return Promise<()>
]=]
function BanService.BanPermanentlyAsync(self: BanService, player: Player): Promise.Promise<()>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self:_banAsync(player, PERMANENT_DURATION)
end

--[=[
	Unbans a player across the entire experience universe.

	@within BanService
	@param player Player
	@return Promise<()>
]=]
function BanService.UnbanAsync(self: BanService, player: Player): Promise.Promise<()>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._maid:GivePromise(Promise.new(function(resolve, reject)
		const success, resultOrError = (pcall :: any)(function()
			Players:UnbanAsync({
				UserIds = { player.UserId },
				ApplyToUniverse = APPLY_TO_UNIVERSE,
			})
		end)

		if success then
			resolve()
		else
			reject(resultOrError)
		end
	end))
end

--[=[
	Returns whether a player currently has an active universe-level ban.

	@within BanService
	@param player Player
	@return Promise<boolean>
	]=]
function BanService.IsBannedAsync(self: BanService, player: Player): Promise.Promise<boolean>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return self._maid:GivePromise(Promise.new(function(resolve, reject)
		local success, resultOrError = (pcall :: any)(function()
			const history = Players:GetBanHistoryAsync(player.UserId)
			const currentPage = history:GetCurrentPage()

			for _, entry in ipairs(currentPage) do
				const banEntry = entry :: BanHistoryEntry
				if banEntry.PlaceId == -1 then
					return BanServiceUtils.isActiveBan(banEntry)
				end
			end

			return false
		end)

		if success then
			resolve(resultOrError :: boolean)
		else
			reject(resultOrError)
		end
	end))
end

function BanService._banAsync(self: BanService, player: Player, duration: number): Promise.Promise<()>
	return self._maid:GivePromise(Promise.new(function(resolve, reject)
		if self._playerDataStoreService then
			-- Not required for banning, hence why it's optional
			self._playerDataStoreService:DeleteProfileAsync(player)
		end

		const success, resultOrError = pcall(function()
			Players:BanAsync({
				UserIds = { player.UserId },
				Duration = duration,
				DisplayReason = DISPLAY_REASON,
				PrivateReason = PRIVATE_REASON,
				ApplyToUniverse = APPLY_TO_UNIVERSE,
				ExcludeAltAccounts = EXCLUDE_ALT_ACCOUNTS,
				ApplyDeviceBlock = APPLY_DEVICE_BLOCK,
			})
		end)

		if success then
			resolve()
		else
			reject(resultOrError)
		end
	end))
end

return BanService
