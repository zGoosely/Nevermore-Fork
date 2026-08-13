--!strict
--[=[
	Starts cancellable server operations, coordinates optional keyed locks, and
	indexes active executions for dynamic interruption.

	@class ActionExecutionService
	@server
]=]
const ActionExecution = require("./ActionExecution")
const ActionExecutionTypes = require("./ActionExecutionTypes")
const ActionExecutionUtils = require("./ActionExecutionUtils")
const LockPermit = require("@game/ReplicatedStorage/Packages/LockPermit")
const LockService = require("@game/ReplicatedStorage/Packages/LockService")
const LockServiceUtils = require("@game/ReplicatedStorage/Packages/LockServiceUtils")
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")

type ExecutionCallback = ActionExecutionTypes.ExecutionCallback
type ExecutionConfig = ActionExecutionTypes.ExecutionConfig
type LockConfig = ActionExecutionTypes.LockConfig

const ActionExecutionService = {}
ActionExecutionService.ServiceName = "ActionExecutionService"
ActionExecutionService.ServerOnly = true

export type ActionExecutionService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_lockService: LockService.LockService,
		_executions: { [ActionExecution.ActionExecution]: true },
		_executionsByActor: { [Instance]: { [ActionExecution.ActionExecution]: true } },
		_executionByActorLock: { [Instance]: { [string]: ActionExecution.ActionExecution } },
		_lockConfigByExecution: { [ActionExecution.ActionExecution]: LockConfig },
		_destroyed: boolean,
	},
	{} :: typeof({ __index = ActionExecutionService })
))

function ActionExecutionService.Init(self: ActionExecutionService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._lockService = self._serviceBag:GetService(LockService)
	self._executions = {}
	self._executionsByActor = {}
	self._executionByActorLock = {}
	self._lockConfigByExecution = {}
	self._destroyed = false
end

--[=[
	Attempts to start cancellable work. Returns nil without invoking the callback
	when its optional lock is occupied.

	@within ActionExecutionService
	@param config ExecutionConfig
	@param callback ExecutionCallback
	@return ActionExecution?
]=]
function ActionExecutionService.TryStart(
	self: ActionExecutionService,
	config: ExecutionConfig,
	callback: ExecutionCallback
): ActionExecution.ActionExecution?
	assert(ActionExecutionUtils.isExecutionConfig(config), "Bad config")
	assert(t.callback(callback), "Bad callback")
	assert(not self._destroyed, "ActionExecutionService is destroyed")

	local lockPermit: LockPermit.LockPermit? = nil
	if config.Lock then
		lockPermit = self._lockService:TryAcquire({
			Owner = config.Actor,
			Key = config.Lock.Key,
			Holder = config.Actor,
			Timeout = config.Timeout,
		})
		if not lockPermit then
			return nil
		end
	end

	local execution: ActionExecution.ActionExecution? = nil
	const createdExecution = ActionExecution.new(config, lockPermit, callback, function()
		const completedExecution = execution
		if completedExecution then
			self:_unregisterExecution(completedExecution)
		end
	end)
	execution = createdExecution
	self:_registerExecution(createdExecution, config)

	return createdExecution
end

--[=[
	Returns a snapshot of active executions belonging to an actor.

	@within ActionExecutionService
	@param actor Instance
	@return { ActionExecution }
]=]
function ActionExecutionService.GetActorExecutions(
	self: ActionExecutionService,
	actor: Instance
): { ActionExecution.ActionExecution }
	assert(t.Instance(actor), "Bad actor")

	const result: { ActionExecution.ActionExecution } = {}
	const actorExecutions = self._executionsByActor[actor]
	if not actorExecutions then
		return result
	end

	for execution in actorExecutions do
		table.insert(result, execution)
	end
	return result
end

--[=[
	Requests cancellation of every active execution belonging to an actor.

	@within ActionExecutionService
	@param actor Instance
	@param reason string
	@return number
]=]
function ActionExecutionService.CancelActorExecutions(
	self: ActionExecutionService,
	actor: Instance,
	reason: string
): number
	assert(t.Instance(actor), "Bad actor")
	assert(ActionExecutionUtils.isCancellationReason(reason), "Bad reason")

	const actorExecutions = self._executionsByActor[actor]
	if not actorExecutions then
		return 0
	end

	local cancelled = 0
	for execution in table.clone(actorExecutions) do
		if execution:Cancel(reason) then
			cancelled += 1
		end
	end
	return cancelled
end

--[=[
	Requests cancellation of an actor's active executions carrying one runtime
	tag.

	@within ActionExecutionService
	@param actor Instance
	@param tag string
	@param reason string
	@return number
]=]
function ActionExecutionService.CancelActorExecutionsByTag(
	self: ActionExecutionService,
	actor: Instance,
	tag: string,
	reason: string
): number
	assert(t.Instance(actor), "Bad actor")
	assert(ActionExecutionUtils.isTag(tag), "Bad tag")
	assert(ActionExecutionUtils.isCancellationReason(reason), "Bad reason")

	const actorExecutions = self._executionsByActor[actor]
	if not actorExecutions then
		return 0
	end

	local cancelled = 0
	for execution in table.clone(actorExecutions) do
		if execution:HasTag(tag) and execution:Cancel(reason) then
			cancelled += 1
		end
	end
	return cancelled
end

--[=[
	Requests cancellation of the execution holding one of an actor's locks.

	@within ActionExecutionService
	@param actor Instance
	@param key string
	@param reason string
	@return boolean
]=]
function ActionExecutionService.CancelActorLockExecution(
	self: ActionExecutionService,
	actor: Instance,
	key: string,
	reason: string
): boolean
	assert(t.Instance(actor), "Bad actor")
	assert(LockServiceUtils.isLockKey(key), "Bad key")
	assert(ActionExecutionUtils.isCancellationReason(reason), "Bad reason")

	const executions = self._executionByActorLock[actor]
	const execution = if executions then executions[key] else nil
	return execution ~= nil and execution:Cancel(reason)
end

function ActionExecutionService._registerExecution(
	self: ActionExecutionService,
	execution: ActionExecution.ActionExecution,
	config: ExecutionConfig
): ()
	self._executions[execution] = true

	local actorExecutions = self._executionsByActor[config.Actor]
	if not actorExecutions then
		actorExecutions = {}
		self._executionsByActor[config.Actor] = actorExecutions
	end
	actorExecutions[execution] = true

	if config.Lock then
		self._lockConfigByExecution[execution] = {
			Key = config.Lock.Key,
		}

		local lockExecutions = self._executionByActorLock[config.Actor]
		if not lockExecutions then
			lockExecutions = {}
			self._executionByActorLock[config.Actor] = lockExecutions
		end
		lockExecutions[config.Lock.Key] = execution
	end
end

function ActionExecutionService._unregisterExecution(
	self: ActionExecutionService,
	execution: ActionExecution.ActionExecution
): ()
	if not self._executions[execution] then
		return
	end
	self._executions[execution] = nil

	const actor = execution:GetActor()
	const actorExecutions = self._executionsByActor[actor]
	if actorExecutions then
		actorExecutions[execution] = nil
		if next(actorExecutions) == nil then
			self._executionsByActor[actor] = nil
		end
	end

	const lockConfig = self._lockConfigByExecution[execution]
	self._lockConfigByExecution[execution] = nil
	if lockConfig then
		const lockExecutions = self._executionByActorLock[actor]
		if lockExecutions then
			if lockExecutions[lockConfig.Key] == execution then
				lockExecutions[lockConfig.Key] = nil
			end
			if next(lockExecutions) == nil then
				self._executionByActorLock[actor] = nil
			end
		end
	end
end

function ActionExecutionService.Destroy(self: ActionExecutionService): ()
	if self._destroyed then
		return
	end
	self._destroyed = true

	const executions: { ActionExecution.ActionExecution } = {}
	for execution in self._executions do
		table.insert(executions, execution)
	end
	for _, execution in executions do
		execution:Destroy()
	end

	table.clear(self._executions)
	table.clear(self._executionsByActor)
	table.clear(self._executionByActorLock)
	table.clear(self._lockConfigByExecution)
	self._maid:DoCleaning()
end

return ActionExecutionService
