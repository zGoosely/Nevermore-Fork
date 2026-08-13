--!strict
--[=[
	@class CmdrServiceClient
]=]

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const require = require("../Loader").load()

const Maid = require("Maid")
const PermissionServiceClient = require("PermissionServiceClient")
const Promise = require("Promise")
const PromiseUtils = require("PromiseUtils")
const PromiseInstanceUtils = require("PromiseInstanceUtils")
const ServiceBag = require("ServiceBag")
const StringUtils = require("StringUtils")

const Player = Players.LocalPlayer

const CmdrServiceClient = {}
CmdrServiceClient.ServiceName = "CmdrServiceClient"

export type CmdrServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_permissionServiceClient: PermissionServiceClient.PermissionServiceClient,

		_cmdrPromise: Promise.Promise<any>,
		_cmdrBindingMaid: Maid.Maid?,
	},
	{} :: typeof({ __index = CmdrServiceClient })
))

function CmdrServiceClient.Init(self: CmdrServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._permissionServiceClient = self._serviceBag:GetService(PermissionServiceClient)

	self:PromiseCmdr():Then(function(cmdrClient)
		self:_watchReplicatedCommands(cmdrClient)

		local store = cmdrClient.Registry:GetStore("ServiceBag")
		store.ServiceBag = self._serviceBag

		cmdrClient.Registry:RegisterHook("BeforeRun", function(context)
			if not context.Executor then
				return
			end

			const permissionPromise = self._permissionServiceClient:PromiseIsAdmin(context.Executor)
			if permissionPromise:IsPending() then
				return "Still loading permissions"
			end

			const hasAdminPermission, isAdmin = permissionPromise:Yield()
			if not hasAdminPermission then
				return "Failed to check admin permissions"
			end

			if not isAdmin then
				return "You don't have permission to run this command"
			end

			return nil
		end)
	end)
end

function CmdrServiceClient.Start(self: CmdrServiceClient)
	task.spawn(function()
		PromiseUtils.all({
			self:PromiseCmdr(),
			self._permissionServiceClient:PromisePermissionProvider(),
		})
			:Then(function(cmdrClient, permissionProvider)
				self._maid:GiveTask(permissionProvider:ObserveIsAdmin():Subscribe(function(isAdmin)
					if isAdmin then
						self._setCmdrBindings(self, cmdrClient)
					else
						self._clearCmdrBindings(self, cmdrClient)
					end
				end))
			end)
			:Catch(error)
	end)
end

--[=[
	Returns the Cmdr client instance in a promise

	@within CmdrServiceClient
	@return Promise<any>
]=]
function CmdrServiceClient.PromiseCmdr(self: CmdrServiceClient)
	if self._cmdrPromise then
		return self._cmdrPromise
	end

	self._cmdrPromise = PromiseInstanceUtils.promiseChild(ReplicatedStorage, "CmdrClient")
		:Then(function(cmdrClient)
			return Promise.spawn(function(resolve)
				return resolve(require(cmdrClient))
			end)
		end)
		:Then(function(cmdrClient)
			return cmdrClient
		end)
		:Catch(error)

	return self._cmdrPromise :: Promise.Promise<any> | any
end

function CmdrServiceClient._setCmdrBindings(self: CmdrServiceClient, cmdrClient)
	if self._cmdrBindingMaid then
		return
	end

	const cmdrBindingMaid = Maid.new()
	self._cmdrBindingMaid = cmdrBindingMaid
	cmdrClient:SetActivationUnlocksMouse(true)
	cmdrClient:SetActivationKeys({ Enum.KeyCode.Semicolon })

	cmdrBindingMaid:GiveTask(Player.Chatted:Connect(function(message: string)
		if StringUtils.startsWith(message, "/cmdr") then
			cmdrClient:Show()
		end
	end))
end

function CmdrServiceClient._watchReplicatedCommands(self: CmdrServiceClient, cmdrClient)
	const commands = cmdrClient.ReplicatedRoot:WaitForChild("Commands")

	local function registerCommand(commandScript: Instance)
		if not commandScript:IsA("ModuleScript") then
			return
		end

		task.spawn(function()
			const definitionSuccess, definitionOrError = (pcall :: any)(require, commandScript)
			if not definitionSuccess then
				warn(`[CmdrServiceClient] - Failed to load command {commandScript.Name}: {definitionOrError}`)
				return
			end

			const definition = definitionOrError
			if type(definition) ~= "table" or type(definition.Name) ~= "string" then
				warn(`[CmdrServiceClient] - Command {commandScript.Name} returned an invalid definition`)
				return
			end

			-- Cmdr registers everything already present when its client module loads.
			-- Requiring a ModuleScript is cached, so identity tells us whether this
			-- exact definition has already been registered while still allowing a
			-- later module to replace a command with the same public name.
			if cmdrClient.Registry:GetCommand(definition.Name) == definition then
				return
			end

			const registerSuccess, registerError = pcall(function()
				cmdrClient.Registry:RegisterCommand(commandScript)
			end)
			if not registerSuccess then
				warn(`[CmdrServiceClient] - Failed to register command {definition.Name}: {registerError}`)
			end
		end)
	end

	self._maid:Add(commands.ChildAdded:Connect(registerCommand))
	for _, commandScript in commands:GetChildren() do
		registerCommand(commandScript)
	end
end

function CmdrServiceClient._clearCmdrBindings(self: CmdrServiceClient, cmdrClient)
	if self._cmdrBindingMaid then
		self._cmdrBindingMaid:DoCleaning()
		self._cmdrBindingMaid = nil
	end

	cmdrClient:SetActivationKeys({})
	cmdrClient:Hide()
end

function CmdrServiceClient.Destroy(self: CmdrServiceClient)
	self._maid:Destroy()
end

return CmdrServiceClient
