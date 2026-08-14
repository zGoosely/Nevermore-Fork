--!strict
--[=[
	Client entry point for the access package. The mirror of [AccessService]: brings up the shared
	[AccessDataService] plus whatever is client-only, so a game starts access the same way in both realms.

	```lua
	serviceBag:GetService(require("./AccessServiceClient"))
	```

	The client resolves its own facts rather than being told the verdict, which is what keeps a menu from
	rendering nothing while it waits on the server. Facts the client genuinely cannot resolve are the
	exception, and those replicate.

	@client
	@class AccessServiceClient
]=]
local Players = game:GetService("Players")

const AccessCommandServiceClient = require("./Commands/AccessCommandServiceClient")
const AccessDataService = require("../Shared/AccessDataService")
const AccessPlayerClient = require("./Binders/AccessPlayerClient")
const AccessPolicyService = require("../Shared/AccessPolicyService")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const PlayerMock = require("@game/ReplicatedStorage/Packages/PlayerMock")
const PermissionServiceClient = require("@game/ReplicatedStorage/Packages/PermissionServiceClient")
const PlayerIsAdminAccessFact = require("../Shared/Implementations/Facts/PlayerIsAdminAccessFact")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

const AccessServiceClient = {}
AccessServiceClient.ServiceName = "AccessServiceClient"

export type AccessServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_accessDataService: AccessDataService.AccessDataService,
		_accessPolicyService: AccessPolicyService.AccessPolicyService,
		_permissionServiceClient: PermissionServiceClient.PermissionServiceClient,
	},
	{} :: typeof({ __index = AccessServiceClient })
))

function AccessServiceClient.Init(self: AccessServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()

	self._accessDataService = self._serviceBag:GetService(AccessDataService) :: any
	self._accessPolicyService = self._serviceBag:GetService(AccessPolicyService) :: any
	self._permissionServiceClient = self._serviceBag:GetService(PermissionServiceClient)
	self._serviceBag:GetService(AccessCommandServiceClient)
	self._serviceBag:GetService(AccessPlayerClient)

	const playerIsAdminFact = self._maid:Add(PlayerIsAdminAccessFact.new(self._permissionServiceClient))
	self._maid:GiveTask(self._accessDataService:RegisterFact(playerIsAdminFact))
end

--[[
	The client half of what [AccessService] does on join: without this a client-realm policy is registered,
	enabled, listed by `access-policies` -- and never applied to anybody, because a policy only runs against
	a player somebody added.

	The local player and nobody else. Player instances replicate, so this realm can answer questions about
	everyone here, but a client-realm consequence is presentation *for the person at this client* -- adding
	the rest would raise this client's paywall on a stranger's verdict.

	Read once, matching production: `Players.LocalPlayer` exists before any LocalScript runs. A headless
	bag with no local player simply runs no client policies.
]]
function AccessServiceClient.Start(self: AccessServiceClient): ()
	local localPlayer = Players.LocalPlayer or PlayerMock.getMockedLocalPlayer()
	if localPlayer then
		self._maid:GiveTask(self._accessPolicyService:AddPlayer(localPlayer))
	end
end

--[=[
	The shared registry, for a game registering its facts and features.

	@return AccessDataService
]=]
function AccessServiceClient.GetAccessDataService(self: AccessServiceClient): AccessDataService.AccessDataService
	return self._accessDataService
end

--[=[
	The policy registry, for naming policies client-side.

	@return AccessPolicyService
]=]
function AccessServiceClient.GetAccessPolicyService(self: AccessServiceClient): AccessPolicyService.AccessPolicyService
	return self._accessPolicyService
end

function AccessServiceClient.Destroy(self: AccessServiceClient): ()
	self._maid:DoCleaning()
end

return AccessServiceClient
