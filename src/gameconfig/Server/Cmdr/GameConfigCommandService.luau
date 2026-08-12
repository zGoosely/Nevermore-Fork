--!strict
--[=[
	Registers server Cmdr commands and game-config-backed argument types.

	@class GameConfigCommandService
	@server
]=]

const TeleportService = game:GetService("TeleportService")

const require = require("../../../Loader").load()

const BadgeUtils = require("BadgeUtils")
const CmdrService = require("CmdrService")
const GameConfigCmdrUtils = require("GameConfigCmdrUtils")
const GameConfigService = require("GameConfigService")
const Maid = require("Maid")
const PlayerUtils = require("PlayerUtils")
const ServiceBag = require("ServiceBag")

const GameConfigCommandService = {}
GameConfigCommandService.ServiceName = "GameConfigCommandService"
GameConfigCommandService.ServerOnly = true

export type GameConfigCommandService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: CmdrService.CmdrService,
		_gameConfigService: GameConfigService.GameConfigService,
	},
	{} :: typeof({ __index = GameConfigCommandService })
))

function GameConfigCommandService.Init(self: GameConfigCommandService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._cmdrService = self._serviceBag:GetService(CmdrService)
	self._gameConfigService = self._serviceBag:GetService(GameConfigService)
end

function GameConfigCommandService.Start(self: GameConfigCommandService): ()
	const picker = self._gameConfigService:GetConfigPicker()
	self._maid:GivePromise(self._cmdrService:PromiseCmdr()):Then(function(cmdr)
		GameConfigCmdrUtils.registerAssetTypes(cmdr, picker)
	end)

	self._cmdrService:RegisterCommand({
		Name = "give-badge",
		Aliases = { "award-badge" },
		Description = "Awards a configured badge to one or more players.",
		Group = "GameConfig",
		Args = {
			{
				Name = "targets",
				Type = "players",
				Description = "Players to award the badge to.",
			},
			{
				Name = "badges",
				Type = "badgeIds",
				Description = "Configured badge keys or numeric IDs.",
			},
		},
	}, function(_context, players: { Player }, badgeIds: { number })
		const awards = {}
		const failures = {}
		for _, player in players do
			for _, badgeId in badgeIds do
				const success, result = BadgeUtils.promiseAwardBadge(player, badgeId):Yield()
				if not success then
					table.insert(failures, `{PlayerUtils.formatName(player)} badge {badgeId}: {tostring(result)}`)
				else
					table.insert(awards, `{PlayerUtils.formatName(player)} badge {badgeId}`)
				end
			end
		end
		if #failures == 0 then
			return `Awarded: {table.concat(awards, ", ")}.`
		elseif #awards == 0 then
			return `Could not award any badges: {table.concat(failures, "; ")}.`
		end
		return `Awarded {#awards}; failed {#failures}: {table.concat(failures, "; ")}.`
	end)

	self._cmdrService:RegisterCommand({
		Name = "goto-place",
		Aliases = { "goto-named-place" },
		Description = "Teleports players to a configured place.",
		Group = "GameConfig",
		Args = {
			{
				Name = "players",
				Type = "players",
				Description = "Players to teleport.",
			},
			{
				Name = "place",
				Type = "place",
				Description = "Configured place key or numeric ID.",
			},
			{
				Name = "jobId",
				Type = "string",
				Description = "Optional destination server job ID.",
				Optional = true,
			},
		},
	}, function(_context, players: { Player }, placeId: number, jobId: string?)
		if type(placeId) ~= "number" or placeId <= 0 or placeId % 1 ~= 0 then
			return `Could not teleport: {tostring(placeId)} is not a valid place ID.`
		end

		if jobId and jobId ~= "" and jobId ~= "-" then
			local teleported = 0
			const failures = {}
			for _, player in players do
				const succeeded, result = pcall(function()
					TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
				end)
				if succeeded then
					teleported += 1
				else
					table.insert(failures, `{PlayerUtils.formatName(player)}: {tostring(result)}`)
				end
			end
			if #failures == 0 then
				return `Teleport requested for {teleported} player(s) to place {placeId}, server {jobId}.`
			elseif teleported == 0 then
				return `Could not teleport any players: {table.concat(failures, "; ")}.`
			end
			return `Teleport requested for {teleported}; failed {#failures}: {table.concat(failures, "; ")}.`
		else
			const succeeded, result = pcall(function()
				TeleportService:TeleportPartyAsync(placeId, players)
			end)
			if not succeeded then
				return `Could not teleport to place {placeId}: {tostring(result)}.`
			end
			return `Teleport requested for {#players} player(s) to place {placeId}.`
		end
	end)
end

function GameConfigCommandService.Destroy(self: GameConfigCommandService): ()
	self._maid:Destroy()
end

return GameConfigCommandService
