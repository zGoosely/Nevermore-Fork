--!strict
--[=[
	Registers and secures Cmdr commands.

	Table-defined commands are converted into the same paired ModuleScripts Cmdr
	normally expects. A shared definition module is replicated by Cmdr for parsing
	and autocomplete, while a server execution module forwards back into the
	function retained by this service.

	@server
	@class CmdrService
]=]

const HttpService = game:GetService("HttpService")

const require = require("../Loader").load()

const CmdrServiceUtils = require("CmdrServiceUtils")
const CmdrTemplateProviderServer = require("CmdrTemplateProviderServer")
const Maid = require("Maid")
const PermissionService = require("PermissionService")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const t = require("t")

const CmdrService = {}
CmdrService.ServiceName = "CmdrService"
CmdrService.ServerOnly = true

export type CmdrService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_permissionService: PermissionService.PermissionService,
		_cmdrTemplateProviderServer: any,
		_serviceId: string,
		_promiseCmdr: Promise.Promise<any>,
		_definitionData: { [string]: CmdrServiceUtils.CommandDefinition },
		_executeData: { [string]: CmdrServiceUtils.CommandExecute },
		_commandIdsByName: { [string]: string },
		_registeredCommandIdsByName: { [string]: string },
		_commandScriptsByName: { [string]: ModuleScript },
		_commandServerScriptsByName: { [string]: ModuleScript },
	},
	{} :: typeof({ __index = CmdrService })
))

const GLOBAL_REGISTRY: { [string]: CmdrService } = setmetatable({}, {
	__mode = "v",
}) :: any

function CmdrService.Init(self: CmdrService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._permissionService = self._serviceBag:GetService(PermissionService)
	self._cmdrTemplateProviderServer = self._serviceBag:GetService(CmdrTemplateProviderServer)

	self._serviceId = HttpService:GenerateGUID(false)
	self._definitionData = {}
	self._executeData = {}
	self._commandIdsByName = {}
	self._registeredCommandIdsByName = {}
	self._commandScriptsByName = {}
	self._commandServerScriptsByName = {}
	GLOBAL_REGISTRY[self._serviceId] = self

	self._maid:Add(function()
		if GLOBAL_REGISTRY[self._serviceId] == self then
			GLOBAL_REGISTRY[self._serviceId] = nil
		end
	end)

	self._promiseCmdr = self._maid:GivePromise(Promise.spawn(function(resolve, reject)
		local cmdr = nil
		const success, resultOrError = pcall(function()
			cmdr = require("Cmdr")
		end)

		if success then
			resolve(cmdr)
		else
			reject(resultOrError)
		end
	end))
end

function CmdrService.Start(self: CmdrService)
	self:PromiseCmdr():Then(function(cmdr)
		CmdrServiceUtils.writeServiceBagInContext(cmdr.Registry, self._serviceBag)

		task.spawn(function()
			cmdr:RegisterDefaultCommands()
		end)

		cmdr.Registry:RegisterHook("BeforeRun", function(context)
			if not context.Executor then
				return nil
			end

			const permissionPromise = self._permissionService:PromiseIsAdmin(context.Executor)
			if permissionPromise:IsPending() then
				return "Still loading permissions"
			end

			const hasPermissionResult, isAdmin = permissionPromise:Yield()
			if not hasPermissionResult then
				return type(isAdmin) == "string" and isAdmin or "Failed to check admin permissions"
			end

			if not isAdmin then
				return "You don't have permission to run this command"
			end

			return nil
		end)
	end)
end

--[=[
	Registers every paired command module beneath a container.

	Cmdr moves each shared definition into its replicated `Commands` folder. The
	client service observes that folder, so commands registered after a client has
	loaded are registered there as well.

	```lua
	CmdrService:RegisterCommandsIn(ServerScriptService.Commands)
	```

	@within CmdrService
	@param container Instance
	@return Promise<()>
]=]
function CmdrService.RegisterCommandsIn(self: CmdrService, container: Instance): Promise.Promise<()>
	assert(typeof(container) == "Instance", "Bad container")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterCommandsIn(container)
	end)
end

--[=[
	Registers a command from a table and server execution function.

	Both forms below are supported. The two-argument form makes the replicated
	definition and server-only execution boundary explicit. The embedded `Run`
	form remains available for compatibility.

	```lua
	CmdrService:RegisterCommand({
		Name = "kill",
		Description = "Kills a player",
		Group = "Admin",
		Args = {
			{ Type = "player", Name = "target" },
		},
	}, function(context, target)
		target:BreakJoints()
		return `Killed {target.Name}`
	end)
	```

	```lua
	CmdrService:RegisterCommand({
		Name = "kill",
		Description = "Kills a player",
		Group = "Admin",
		Args = {
			{ Type = "player", Name = "target" },
		},
		Run = function(context, target)
			target:BreakJoints()
			return `Killed {target.Name}`
		end,
	})
	```

	The definition is JSON encoded into a generated ModuleScript. Consequently,
	all fields other than `Run` must be JSON-compatible. Use
	[CmdrService.RegisterCommandsIn] when a command needs function-valued argument
	types, defaults, `ClientRun`, or other module-only behavior.

	@within CmdrService
	@param definition CommandDefinition
	@param execute CommandExecute?
	@return Promise<()>
]=]
function CmdrService.RegisterCommand(
	self: CmdrService,
	definition: CmdrServiceUtils.CommandDefinition,
	execute: CmdrServiceUtils.CommandExecute?
): Promise.Promise<()>
	assert(self._promiseCmdr, "Not initialized")
	assert(type(definition) == "table", "Bad definition")
	assert(t.string(definition.Name) and definition.Name ~= "", "Bad definition.Name")
	assert(definition.Description == nil or t.string(definition.Description), "Bad definition.Description")
	assert(definition.Group == nil or t.string(definition.Group), "Bad definition.Group")
	assert(definition.Aliases == nil or t.array(t.string)(definition.Aliases), "Bad definition.Aliases")
	assert(definition.AutoExec == nil or t.array(t.string)(definition.AutoExec), "Bad definition.AutoExec")
	assert(definition.Args == nil or t.table(definition.Args), "Bad definition.Args")

	const commandExecute = execute or definition.Run
	assert(t.callback(commandExecute), "No command execution function")

	const commandData = table.clone(definition)
	commandData.Run = nil

	const encodedSuccessfully, encodedDataOrError = (pcall :: any)(HttpService.JSONEncode, HttpService, commandData)
	assert(
		encodedSuccessfully,
		`Command {definition.Name} contains data that cannot be replicated through its definition template: {tostring(
			encodedDataOrError
		)}`
	)

	const commandId = `{definition.Name}_{HttpService:GenerateGUID(false)}`
	const commandNameKey = string.lower(definition.Name)
	self._definitionData[commandId] = commandData
	self._executeData[commandId] = commandExecute :: CmdrServiceUtils.CommandExecute
	self._commandIdsByName[commandNameKey] = commandId

	const commandServerScript = self._cmdrTemplateProviderServer:CloneTemplate("CmdrExecutionTemplate")
	assert(commandServerScript:IsA("ModuleScript"), "CmdrExecutionTemplate must be a ModuleScript")
	commandServerScript.Name = `{commandId}Server`
	self._maid:Add(commandServerScript)

	const cmdrServiceTarget = Instance.new("ObjectValue")
	cmdrServiceTarget.Name = "CmdrServiceTarget"
	cmdrServiceTarget.Value = script
	cmdrServiceTarget.Parent = commandServerScript

	const cmdrServiceId = Instance.new("StringValue")
	cmdrServiceId.Name = "CmdrServiceId"
	cmdrServiceId.Value = self._serviceId
	cmdrServiceId.Parent = commandServerScript

	const cmdrCommandId = Instance.new("StringValue")
	cmdrCommandId.Name = "CmdrCommandId"
	cmdrCommandId.Value = commandId
	cmdrCommandId.Parent = commandServerScript

	const commandScript = self._cmdrTemplateProviderServer:CloneTemplate("CmdrCommandDefinitionTemplate")
	assert(commandScript:IsA("ModuleScript"), "CmdrCommandDefinitionTemplate must be a ModuleScript")
	commandScript.Name = commandId
	self._maid:Add(commandScript)

	const cmdrJsonCommandData = Instance.new("StringValue")
	cmdrJsonCommandData.Name = "CmdrJsonCommandData"
	cmdrJsonCommandData.Value = encodedDataOrError :: string
	cmdrJsonCommandData.Parent = commandScript

	return self:PromiseCmdr():Then(function(cmdr)
		if self._commandIdsByName[commandNameKey] ~= commandId then
			self._definitionData[commandId] = nil
			self._executeData[commandId] = nil
			commandScript:Destroy()
			commandServerScript:Destroy()
			return
		end

		cmdr.Registry:RegisterCommand(commandScript, commandServerScript)

		const oldCommandId = self._registeredCommandIdsByName[commandNameKey]
		const oldCommandScript = self._commandScriptsByName[commandNameKey]
		const oldCommandServerScript = self._commandServerScriptsByName[commandNameKey]
		self._registeredCommandIdsByName[commandNameKey] = commandId
		self._commandScriptsByName[commandNameKey] = commandScript
		self._commandServerScriptsByName[commandNameKey] = commandServerScript

		if oldCommandId and oldCommandId ~= commandId then
			self._definitionData[oldCommandId] = nil
			self._executeData[oldCommandId] = nil
		end
		if oldCommandScript and oldCommandScript ~= commandScript then
			oldCommandScript:Destroy()
		end
		if oldCommandServerScript and oldCommandServerScript ~= commandServerScript then
			oldCommandServerScript:Destroy()
		end
	end)
end

--[=[
	Registers every Cmdr type module beneath a container.

	@within CmdrService
	@param container Instance
	@return Promise<()>
]=]
function CmdrService.RegisterTypesIn(self: CmdrService, container: Instance): Promise.Promise<()>
	assert(typeof(container) == "Instance", "Bad container")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterTypesIn(container)
	end)
end

--[=[
	Registers a server-only Cmdr type object.

	Prefer [CmdrService.RegisterTypesIn] when clients must parse or autocomplete
	the type.

	@within CmdrService
	@param name string
	@param typeObject any
	@return Promise<()>
]=]
function CmdrService.RegisterType(self: CmdrService, name: string, typeObject: any): Promise.Promise<()>
	assert(t.string(name), "Bad name")
	assert(t.table(typeObject), "Bad typeObject")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterType(name, typeObject)
	end)
end

--[=[
	Registers every Cmdr hook module beneath a container.

	@within CmdrService
	@param container Instance
	@return Promise<()>
]=]
function CmdrService.RegisterHooksIn(self: CmdrService, container: Instance): Promise.Promise<()>
	assert(typeof(container) == "Instance", "Bad container")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterHooksIn(container)
	end)
end

--[=[
	Returns the promised server Cmdr instance.

	@within CmdrService
	@return Promise<any>
]=]
function CmdrService.PromiseCmdr(self: CmdrService): Promise.Promise<any>
	assert(self._promiseCmdr, "Not initialized")
	return self._promiseCmdr
end

function CmdrService.__executeCommand(self: CmdrService, cmdrCommandId: string, ...: any): ...any
	assert(type(cmdrCommandId) == "string", "Bad cmdrCommandId")
	assert(self._promiseCmdr, "CmdrService is not initialized")

	const execute = self._executeData[cmdrCommandId]
	if not execute then
		error(`[CmdrService] - No execution function for command id {cmdrCommandId}`)
	end

	return execute(...)
end

function CmdrService.__getServiceFromId(_self: CmdrService, cmdrServiceId: string): CmdrService?
	assert(type(cmdrServiceId) == "string", "Bad cmdrServiceId")
	return GLOBAL_REGISTRY[cmdrServiceId]
end

function CmdrService.Destroy(self: CmdrService)
	self._maid:Destroy()
end

return CmdrService
