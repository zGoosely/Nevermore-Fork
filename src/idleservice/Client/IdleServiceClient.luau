--!strict
--[=[
	Helps track whether or not a player is idle and, if so, can show UI
	or other idle-related effects.

	@client
	@class IdleServiceClient
]=]

local require = require("../../Loader").load()

local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local Maid = require("Maid")
local Observable = require("Observable")
local Rx = require("Rx")
local ServiceBag = require("ServiceBag")
local StateStack = require("StateStack")
local ValueObject = require("ValueObject")

local IdleServiceClient = {}
IdleServiceClient.ServiceName = "IdleServiceClient"

export type IdleServiceClient = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_serviceBag: ServiceBag.ServiceBag,
		_humanoidTracker: any,
		_disableStack: StateStack.StateStack<boolean>,
		_enabled: ValueObject.ValueObject<boolean>,
		_showIdleUI: ValueObject.ValueObject<boolean>,
		_humanoidIdle: ValueObject.ValueObject<boolean>,
		_lastPosition: ValueObject.ValueObject<Vector3?>,
	},
	{} :: typeof({ __index = IdleServiceClient })
))

local STANDING_TIME_REQUIRED = 0.5
local MOVE_SPEED_REQUIRED = 2.5
local MOVE_DISTANCE_REQUIRED = 2.5

--[=[
	Initializes the idle service on the client. Should be done via [ServiceBag].

	@param serviceBag ServiceBag
]=]
function IdleServiceClient.Init(self: IdleServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._maid, "Already initialized")

	self._maid = Maid.new()
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- External
	self._serviceBag:GetService(require("HumanoidTrackerService"))

	-- Configure
	self._disableStack = self._maid:Add(StateStack.new(false, "boolean"))
	self._enabled = self._maid:Add(ValueObject.new(true, "boolean"))
	self._showIdleUI = self._maid:Add(ValueObject.new(false, "boolean"))
	self._humanoidIdle = self._maid:Add(ValueObject.new(false, "boolean"))
	self._lastPosition = self._maid:Add(ValueObject.new(nil))
end

--[=[
	Starts the idle service on the client. Should be done via [ServiceBag].
]=]
function IdleServiceClient.Start(self: IdleServiceClient): ()
	self._maid:GiveTask(self._humanoidIdle.Changed:Connect(function()
		self:_updateShowIdleUI()
	end))

	self._maid:GiveTask(self._enabled.Changed:Connect(function()
		self:_updateShowIdleUI()
	end))

	self._humanoidTracker = (self._serviceBag:GetService(require("HumanoidTrackerService")) :: any):GetHumanoidTracker()

	if self._humanoidTracker then
		self._maid:GiveTask(self._humanoidTracker.AliveHumanoid.Changed:Connect(function()
			self:_handleAliveHumanoidChanged()
		end))

		self._maid:GiveTask(self._disableStack.Changed:Connect(function()
			self._enabled.Value = not self._disableStack:GetState()
		end))

		if self._humanoidTracker.AliveHumanoid.Value then
			self:_handleAliveHumanoidChanged()
		end
	end

	self:_updateShowIdleUI()
end

--[=[
	Observes the humanoid moving away from its current position after a
	minimum amount of time.

	This can be used to close idle UI after the humanoid moves too far.

	@param minimumTimeVisible number
	@return Observable<Vector3?>
]=]
function IdleServiceClient.ObserveHumanoidMoveFromCurrentPosition(
	self: IdleServiceClient,
	minimumTimeVisible: number
): Observable.Observable<Vector3?>
	assert(type(minimumTimeVisible) == "number", "Bad minimumTimeVisible")

	local rx = Rx :: any

	return rx.of(true):Pipe({
		rx.delay(minimumTimeVisible),

		rx.flatMap(function()
			return self._lastPosition:Observe()
		end),

		rx.where(function(position)
			return position ~= nil
		end),

		rx.first(),

		rx.flatMap(function(initialPosition: Vector3)
			return self._lastPosition:Observe():Pipe({
				rx.where(function(position: Vector3?)
					return position == nil or (initialPosition - position).Magnitude >= MOVE_DISTANCE_REQUIRED
				end),
			})
		end),

		rx.first(),
	})
end

--[=[
	Returns whether the humanoid is idle.

	@return boolean
]=]
function IdleServiceClient.IsHumanoidIdle(self: IdleServiceClient): boolean
	return self._humanoidIdle.Value
end

--[=[
	Returns whether the humanoid is moving.

	@return boolean
]=]
function IdleServiceClient.IsMoving(self: IdleServiceClient): boolean
	return not self._humanoidIdle.Value
end

--[=[
	Observes whether the humanoid is idle.

	@return Observable<boolean>
]=]
function IdleServiceClient.ObserveHumanoidIdle(self: IdleServiceClient): Observable.Observable<boolean>
	return self._humanoidIdle:Observe()
end

--[=[
	Returns whether idle UI should currently be shown.

	@return boolean
]=]
function IdleServiceClient.DoShowIdleUI(self: IdleServiceClient): boolean
	return self._showIdleUI.Value
end

--[=[
	Observes whether idle UI should currently be shown.

	@return Observable<boolean>
]=]
function IdleServiceClient.ObserveShowIdleUI(self: IdleServiceClient): Observable.Observable<boolean>
	return self._showIdleUI:Observe()
end

--[=[
	Returns the ValueObject containing whether idle UI should be shown.

	@return ValueObject<boolean>
]=]
function IdleServiceClient.GetShowIdleUIBoolValue(self: IdleServiceClient): ValueObject.ValueObject<boolean>
	assert(self._showIdleUI, "Not initialized")

	return self._showIdleUI
end

--[=[
	Temporarily disables idle UI.

	The returned cleanup function must be called to re-enable it.

	@return () -> ()
]=]
function IdleServiceClient.PushDisable(self: IdleServiceClient): () -> ()
	if not RunService:IsRunning() then
		return function() end
	end

	assert(self._disableStack, "Not initialized")

	return self._disableStack:PushState(true)
end

function IdleServiceClient._setEnabled(self: IdleServiceClient, enabled: boolean): ()
	assert(type(enabled) == "boolean", "Bad enabled")

	self._enabled.Value = enabled
end

function IdleServiceClient._updateShowIdleUI(self: IdleServiceClient): ()
	self._showIdleUI.Value = self._humanoidIdle.Value and self._enabled.Value and not VRService.VREnabled
end

function IdleServiceClient._handleAliveHumanoidChanged(self: IdleServiceClient): ()
	local humanoid = self._humanoidTracker.AliveHumanoid.Value

	if not humanoid then
		self._maid._humanoidMaid = nil
		return
	end

	local maid = Maid.new()
	local lastMoveTime = os.clock()

	maid:GiveTask(function()
		self._lastPosition.Value = nil
		self._humanoidIdle.Value = false
	end)

	local function updateIdleState()
		self._humanoidIdle.Value = os.clock() - lastMoveTime >= STANDING_TIME_REQUIRED
	end

	maid:GiveTask(self._enabled.Changed:Connect(function()
		lastMoveTime = os.clock()
	end))

	maid:GiveTask(RunService.Stepped:Connect(function()
		local rootPart = humanoid.RootPart

		if rootPart then
			self._lastPosition.Value = rootPart.Position

			if rootPart.AssemblyLinearVelocity.Magnitude > MOVE_SPEED_REQUIRED then
				lastMoveTime = os.clock()
			end
		end

		updateIdleState()
	end))

	self._maid._humanoidMaid = maid
end

function IdleServiceClient.Destroy(self: IdleServiceClient): ()
	self._maid:DoCleaning()
end

return IdleServiceClient
