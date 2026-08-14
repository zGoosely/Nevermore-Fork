--!strict
--[=[
	Validates and persists client input-keymap binding requests through
	[PlayerDataStoreService].

	@class InputKeyMapDataStoreService
	@server
]=]

const Players = game:GetService("Players")
const InputKeyMapDataStoreServiceConstants = require("./Shared/InputKeyMapDataStoreServiceConstants")
const InputKeyMapDataStoreServiceNetwork = require("./Shared/InputKeyMapDataStoreServiceNetwork")
const InputKeyMapDataStoreServiceTypes = require("./Shared/InputKeyMapDataStoreServiceTypes")
const InputKeyMapDataStoreServiceUtils = require("./Shared/InputKeyMapDataStoreServiceUtils")
const InputKeyMapRegistryServiceShared = require("@game/ReplicatedStorage/Packages/InputKeyMapRegistryServiceShared")
const InputKeyMapService = require("@game/ReplicatedStorage/Packages/InputKeyMapService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerDataStoreService = require("@game/ServerStorage/ServerPackages/PlayerDataStoreService")
const PlayerDataStoreServiceProfile = require("@game/ReplicatedStorage/Packages/PlayerDataStoreServiceProfile")
const RateLimiter = require("@game/ReplicatedStorage/Packages/RateLimiter")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type BindingRequest = InputKeyMapDataStoreServiceTypes.BindingRequest
type Bindings = InputKeyMapDataStoreServiceTypes.Bindings

const InputKeyMapDataStoreService = {}
InputKeyMapDataStoreService.ServiceName = "InputKeyMapDataStoreService"
InputKeyMapDataStoreService.ServerOnly = true

export type InputKeyMapDataStoreService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_inputKeyMapService: InputKeyMapService.InputKeyMapService,
		_inputKeyMapRegistryService: InputKeyMapRegistryServiceShared.InputKeyMapRegistryServiceShared,
		_playerDataStoreService: PlayerDataStoreService.PlayerDataStoreService,
		_rateLimiters: { [Player]: RateLimiter.RateLimiter },
	},
	{} :: typeof({ __index = InputKeyMapDataStoreService })
))

function InputKeyMapDataStoreService.Init(self: InputKeyMapDataStoreService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._inputKeyMapService = self._serviceBag:GetService(InputKeyMapService)
	self._inputKeyMapRegistryService = self._serviceBag:GetService(InputKeyMapRegistryServiceShared)

	const profileDefinition = PlayerDataStoreServiceProfile.Get()
	assert(
		InputKeyMapDataStoreServiceUtils.isCompatibleProfileDefinition(profileDefinition),
		`{PlayerDataStoreServiceProfile.GetName()}.Template must contain an {InputKeyMapDataStoreServiceConstants.PROFILE_PATH} array`
	)

	self._playerDataStoreService = self._serviceBag:GetService(PlayerDataStoreService)
	self._rateLimiters = setmetatable({}, { __mode = "k" }) :: any
end

function InputKeyMapDataStoreService.Start(self: InputKeyMapDataStoreService): ()
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player)
		self._maid[player] = nil
		self._rateLimiters[player] = nil
	end))

	InputKeyMapDataStoreServiceNetwork.packets.bindingRequested.listen(
		function(request: BindingRequest, player: Player?)
			if player then
				self:_handleBindingRequested(player, request)
			end
		end
	)
end

function InputKeyMapDataStoreService._handleBindingRequested(
	self: InputKeyMapDataStoreService,
	player: Player,
	request: BindingRequest
): ()
	if not InputKeyMapDataStoreServiceUtils.isBindingRequest(request) then
		self:_replicateBindings(player)
		return
	end

	if not self:_getRateLimiter(player):TryConsume() then
		self:_replicateBindings(player)
		return
	end

	const profile = self._playerDataStoreService:GetProfile(player)
	if not profile or not profile:IsActive() then
		return
	end

	const provider = self._inputKeyMapRegistryService:GetProvider(request.ProviderName)
	const inputKeyMapList = if provider then provider:FindInputKeyMapList(request.ListName) else nil
	if not inputKeyMapList or not inputKeyMapList:IsUserRebindable() then
		self:_replicateBindings(player)
		return
	end

	const inputKeyMap = InputKeyMapDataStoreServiceUtils.findInputKeyMap(inputKeyMapList, request.InputModeName)
	if not inputKeyMap then
		self:_replicateBindings(player)
		return
	end

	if not request.Clear then
		const inputTypes = InputKeyMapDataStoreServiceUtils.deserializeInputTypes(request.InputTypes)
		if
			not inputTypes
			or not InputKeyMapDataStoreServiceUtils.areInputTypesValidForMode(
				inputKeyMap:GetInputModeType(),
				inputTypes
			)
		then
			self:_replicateBindings(player)
			return
		end
	end

	const bindings =
		self._playerDataStoreService:GetValue(player, InputKeyMapDataStoreServiceConstants.PROFILE_PATH) :: Bindings?
	if not InputKeyMapDataStoreServiceUtils.isBindings(bindings) then
		warn(`[InputKeyMapDataStoreService] - Player {player.UserId} has invalid persisted bindings`)
		return
	end

	const success, resultOrError = pcall(function()
		const updatedBindings = InputKeyMapDataStoreServiceUtils.applyBindingRequest(bindings :: Bindings, request)
		self._playerDataStoreService:SetValue(
			player,
			InputKeyMapDataStoreServiceConstants.PROFILE_PATH,
			updatedBindings
		)
	end)
	if not success then
		warn(`[InputKeyMapDataStoreService] - Rejected binding update for player {player.UserId}: {resultOrError}`)
		self:_replicateBindings(player)
	end
end

function InputKeyMapDataStoreService._getRateLimiter(
	self: InputKeyMapDataStoreService,
	player: Player
): RateLimiter.RateLimiter
	local rateLimiter = self._rateLimiters[player]
	if rateLimiter then
		return rateLimiter
	end

	rateLimiter = RateLimiter.new(
		InputKeyMapDataStoreServiceConstants.RATE_LIMIT_CAPACITY,
		InputKeyMapDataStoreServiceConstants.RATE_LIMIT_REFILL_RATE
	)
	self._rateLimiters[player] = rateLimiter
	self._maid[player] = rateLimiter
	return rateLimiter
end

function InputKeyMapDataStoreService._replicateBindings(self: InputKeyMapDataStoreService, player: Player): ()
	const profile = self._playerDataStoreService:GetProfile(player)
	if not profile or not profile:IsActive() then
		return
	end

	const bindings =
		self._playerDataStoreService:GetValue(player, InputKeyMapDataStoreServiceConstants.PROFILE_PATH) :: Bindings?
	if InputKeyMapDataStoreServiceUtils.isBindings(bindings) then
		self._playerDataStoreService:ReplicateValue(player, InputKeyMapDataStoreServiceConstants.PROFILE_PATH, bindings)
	end
end

function InputKeyMapDataStoreService.Destroy(self: InputKeyMapDataStoreService): ()
	self._maid:DoCleaning()
end

return InputKeyMapDataStoreService
