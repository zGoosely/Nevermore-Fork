--!strict
--[=[
	Unit tests for cancellable execution, lock contention, and dynamic lookup.

	@class ActionExecutionService.spec
]=]
const ActionExecutionService = require("./ActionExecutionService")
const ActionExecutionStatuses = require("./ActionExecutionStatuses")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const LockService = require("@game/ServerStorage/ServerPackages/LockService")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createServices(): (ActionExecutionService.ActionExecutionService, LockService.LockService)
	const lockService = setmetatable({}, { __index = LockService }) :: any
	lockService:Init({})

	const serviceBag = {
		GetService = function()
			return lockService
		end,
	}
	const actionExecutionService = setmetatable({}, { __index = ActionExecutionService }) :: any
	actionExecutionService:Init(serviceBag)

	return actionExecutionService, lockService
end

describe("ActionExecutionService", function()
	it("resolves successful work and releases its lock", function()
		const service, lockService = createServices()
		const actor = Instance.new("Folder")
		const secondActor = Instance.new("Folder")
		const config = {
			Actor = actor,
			Tags = { "MoveA" },
			Timeout = 5,
			Lock = {
				Key = "Shared",
			},
		}
		const execution = service:TryStart(config, function()
			return Promise.resolved("done")
		end)

		expect(execution).never.toEqual(nil)
		expect(service:TryStart({
			Actor = actor,
			Tags = { "MoveB" },
			Timeout = 5,
			Lock = {
				Key = "Shared",
			},
		}, function()
			return Promise.resolved()
		end)).toEqual(nil)
		expect(service:TryStart({
			Actor = secondActor,
			Timeout = 5,
			Lock = {
				Key = "Shared",
			},
		}, function()
			return Promise.resolved()
		end)).never.toEqual(nil)

		task.wait()

		expect((execution :: any):GetStatus()).toEqual(ActionExecutionStatuses.SUCCEEDED)
		expect(lockService:IsLocked(actor, "Shared")).toEqual(false)
		const succeeded, value = (execution :: any):GetPromise():GetResults()
		expect(succeeded).toEqual(true)
		expect(value).toEqual("done")

		service:Destroy()
		lockService:Destroy()
		actor:Destroy()
		secondActor:Destroy()
	end)

	it("holds a lock during cooperative cancellation", function()
		const service, lockService = createServices()
		const actor = Instance.new("Folder")
		const config = {
			Actor = actor,
			Tags = { "Combat" },
			Timeout = 5,
			Lock = {
				Key = "Shared",
			},
		}
		const execution = service:TryStart(config, function(cancelToken)
			return cancelToken.PromiseCancelled:Then(function()
				return Promise.delayed(0.02)
			end)
		end)

		task.wait()
		expect((execution :: any):Cancel("Stunned")).toEqual(true)
		expect((execution :: any):GetStatus()).toEqual(ActionExecutionStatuses.CANCELLING)
		expect(service:TryStart(config, function()
			return Promise.resolved()
		end)).toEqual(nil)

		task.wait(0.04)

		expect((execution :: any):GetStatus()).toEqual(ActionExecutionStatuses.CANCELLED)
		expect((execution :: any):GetCancelReason()).toEqual("Stunned")
		expect(lockService:IsLocked(actor, "Shared")).toEqual(false)

		service:Destroy()
		lockService:Destroy()
		actor:Destroy()
	end)

	it("cancels active work dynamically by actor tag", function()
		const service, lockService = createServices()
		const actor = Instance.new("Folder")
		const combat = service:TryStart({
			Actor = actor,
			Tags = { "Combat" },
			Timeout = 5,
		}, function(cancelToken)
			return cancelToken.PromiseCancelled:Then(function()
				return Promise.rejected(cancelToken:GetReason())
			end)
		end)
		const movement = service:TryStart({
			Actor = actor,
			Tags = { "Movement" },
			Timeout = 5,
		}, function(cancelToken)
			return cancelToken.PromiseCancelled:Then(function()
				return Promise.rejected(cancelToken:GetReason())
			end)
		end)

		task.wait()
		expect(service:CancelActorExecutionsByTag(actor, "Combat", "Stunned")).toEqual(1)
		expect((combat :: any):GetStatus()).toEqual(ActionExecutionStatuses.CANCELLED)
		expect((movement :: any):GetStatus()).toEqual(ActionExecutionStatuses.RUNNING)
		expect(#service:GetActorExecutions(actor)).toEqual(1)
		expect(service:CancelActorExecutions(actor, "Died")).toEqual(1)
		expect((movement :: any):GetStatus()).toEqual(ActionExecutionStatuses.CANCELLED)

		service:Destroy()
		lockService:Destroy()
		actor:Destroy()
	end)

	it("times out uncooperative work and releases its lock", function()
		const service, lockService = createServices()
		const actor = Instance.new("Folder")
		const execution = service:TryStart({
			Actor = actor,
			Timeout = 0.01,
			Lock = {
				Key = "Shared",
			},
		}, function()
			return Promise.new()
		end)

		task.wait(0.03)

		expect((execution :: any):GetStatus()).toEqual(ActionExecutionStatuses.TIMED_OUT)
		expect((execution :: any):GetCancelReason()).toEqual("Timeout")
		expect(lockService:IsLocked(actor, "Shared")).toEqual(false)

		service:Destroy()
		lockService:Destroy()
		actor:Destroy()
	end)

	it("preserves TimedOut when cooperative work rejects from cancellation", function()
		const service, lockService = createServices()
		const actor = Instance.new("Folder")
		const execution = service:TryStart({
			Actor = actor,
			Timeout = 0.01,
			Lock = {
				Key = "Shared",
			},
		}, function(cancelToken)
			return cancelToken.PromiseCancelled:Then(function()
				return Promise.rejected(cancelToken:GetReason())
			end)
		end)

		task.wait(0.03)

		expect((execution :: any):GetStatus()).toEqual(ActionExecutionStatuses.TIMED_OUT)
		expect((execution :: any):GetCancelReason()).toEqual("Timeout")
		expect(lockService:IsLocked(actor, "Shared")).toEqual(false)

		service:Destroy()
		lockService:Destroy()
		actor:Destroy()
	end)

	it("fails callbacks that throw or return a non-Promise", function()
		const service, lockService = createServices()
		const actor = Instance.new("Folder")
		const throwing = service:TryStart({
			Actor = actor,
			Timeout = 5,
		}, function()
			error("failed")
		end)
		const nonPromise = service:TryStart({
			Actor = actor,
			Timeout = 5,
		}, function()
			return nil :: any
		end)

		task.wait()

		expect((throwing :: any):GetStatus()).toEqual(ActionExecutionStatuses.FAILED)
		expect((nonPromise :: any):GetStatus()).toEqual(ActionExecutionStatuses.FAILED)

		service:Destroy()
		lockService:Destroy()
		actor:Destroy()
	end)
end)
