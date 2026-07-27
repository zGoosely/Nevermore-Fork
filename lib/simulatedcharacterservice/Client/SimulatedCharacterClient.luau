--!strict
--!optimize 2
--[=[
	A lightweight client-side state buffer and optional visual renderer for one
	simulated character.

	@class SimulatedCharacterClient
]=]

const require = require("../../Loader").load()

const AnimationUtils = require("AnimationUtils")
const ClientCulling = require("ClientCulling")
const DefaultCharacterAnimationUtils = require("DefaultCharacterAnimationUtils")
const Maid = require("Maid")
const MathUtils = require("MathUtils")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterPlacementMode = require("SimulatedCharacterPlacementMode")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterUtils = require("SimulatedCharacterUtils")

const SimulatedCharacterClient = {}
SimulatedCharacterClient.ClassName = "SimulatedCharacterClient"
SimulatedCharacterClient.__index = SimulatedCharacterClient

export type SimulatedCharacterClient = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_service: any,
		_id: number,
		_definition: SimulatedCharacterTypes.NetworkDefinition,
		_previousState: SimulatedCharacterTypes.NetworkState,
		_currentState: SimulatedCharacterTypes.NetworkState,
		_previousTime: number,
		_currentTime: number,
		_lifecycleTime: number,
		_simulationRate: number,
		_renderCFrame: CFrame,
		_modelPivotOffset: CFrame,
		_rootCFrameOffset: CFrame,
		_renderIndex: number,
		_culled: boolean,
		_destroyed: boolean,
		_loadToken: number,
		_model: Model?,
		_root: BasePart?,
		_ragdolled: boolean,
		_ragdollMotors: { Motor6D },
		_ragdollConstraints: { Constraint },
		_idleTrack: AnimationTrack?,
		_walkTrack: AnimationTrack?,
		_activeTrack: AnimationTrack?,
		_animationSequence: number,
		_actionState: SimulatedCharacterTypes.NetworkAnimationPlay?,
		_actionTrack: AnimationTrack?,
		_actionTracksByIndex: { [number]: AnimationTrack },
		_actionLoadToken: number,
	},
	SimulatedCharacterClient
))

function SimulatedCharacterClient.new(
	service: any,
	spawn: SimulatedCharacterTypes.NetworkSpawn
): SimulatedCharacterClient
	const state = table.clone(spawn.state)
	const self: SimulatedCharacterClient = setmetatable({} :: any, SimulatedCharacterClient)
	self._maid = Maid.new()
	self._service = service
	self._id = state.id
	self._definition = spawn.definition
	self._previousState = table.clone(state)
	self._currentState = state
	self._previousTime = spawn.serverTime
	self._currentTime = spawn.serverTime
	self._lifecycleTime = spawn.serverTime
	self._simulationRate = spawn.definition.simulationRate or 1
	self._renderCFrame = SimulatedCharacterUtils.toCFrame(state.x, state.z, state.groundY, state.height, state.yaw)
	self._modelPivotOffset = CFrame.identity
	self._rootCFrameOffset = CFrame.identity
	self._renderIndex = 0
	self._culled = true
	self._destroyed = false
	self._loadToken = 0
	self._model = nil
	self._root = nil
	self._ragdolled = false
	self._ragdollMotors = {}
	self._ragdollConstraints = {}
	self._idleTrack = nil
	self._walkTrack = nil
	self._activeTrack = nil
	self._animationSequence = 0
	self._actionState = nil
	self._actionTrack = nil
	self._actionTracksByIndex = {}
	self._actionLoadToken = 0

	ClientCulling.AddObject(self, spawn.definition.cullDistance)
	return self
end

--[=[
	Returns the numeric network id.

	@within SimulatedCharacterClient
	@return number
]=]
function SimulatedCharacterClient.GetId(self: SimulatedCharacterClient): number
	return self._id
end

--[=[
	Returns the most recently rendered root CFrame.

	@within SimulatedCharacterClient
	@return CFrame
]=]
function SimulatedCharacterClient.GetRenderCFrame(self: SimulatedCharacterClient): CFrame
	return self._renderCFrame
end

--[=[
	Returns the latest authoritative position used by custom-object culling.

	@within SimulatedCharacterClient
	@return Vector3
]=]
function SimulatedCharacterClient.GetCullPosition(self: SimulatedCharacterClient): Vector3
	const state = self._currentState
	return Vector3.new(state.x, state.groundY + state.height, state.z)
end

--[=[
	Returns the definition's root hitbox radius for culling.

	@within SimulatedCharacterClient
	@return number
]=]
function SimulatedCharacterClient.GetCullRadius(self: SimulatedCharacterClient): number
	return self._definition.hitboxRadius
end

--[=[
	Mounts or releases the visual renderer after a culling transition.

	@within SimulatedCharacterClient
	@param culled boolean
]=]
function SimulatedCharacterClient.SetCulled(self: SimulatedCharacterClient, culled: boolean)
	if self._destroyed or self._culled == culled then
		return
	end

	self._culled = culled
	if culled then
		self:_unmountModel()
	else
		self:_mountModel()
	end
end

function SimulatedCharacterClient._pushState(
	self: SimulatedCharacterClient,
	state: SimulatedCharacterTypes.NetworkState,
	serverTime: number,
	mergeLifecycleWhenOlder: boolean?
)
	if self._destroyed or state.id ~= self._id then
		return
	end
	if serverTime < self._currentTime then
		if not mergeLifecycleWhenOlder or serverTime < self._lifecycleTime then
			return
		end
		self._lifecycleTime = serverTime
		const current = self._currentState
		const previous = self._previousState
		current.groundY = state.groundY
		current.mode = state.mode
		current.stateStartedAt = state.stateStartedAt
		previous.groundY = state.groundY
		previous.mode = state.mode
		previous.stateStartedAt = state.stateStartedAt
		if self._model and self._ragdolled ~= (state.mode == SimulatedCharacterConstants.Modes.RAGDOLL) then
			self:_setModelRagdolled(state.mode == SimulatedCharacterConstants.Modes.RAGDOLL)
		end
		return
	end

	self._lifecycleTime = math.max(self._lifecycleTime, serverTime)
	self._previousState = self._currentState
	self._previousTime = self._currentTime
	self._currentState = table.clone(state)
	self._currentTime = serverTime

	if self._model and self._ragdolled ~= (state.mode == SimulatedCharacterConstants.Modes.RAGDOLL) then
		self:_setModelRagdolled(state.mode == SimulatedCharacterConstants.Modes.RAGDOLL)
	end
end

function SimulatedCharacterClient._pushMotion(
	self: SimulatedCharacterClient,
	motion: SimulatedCharacterTypes.NetworkMotionState,
	serverTime: number
)
	if self._destroyed or motion.id ~= self._id or serverTime < self._currentTime then
		return
	end

	const state = table.clone(self._currentState)
	state.x = motion.x
	state.z = motion.z
	state.height = motion.height
	state.yaw = motion.yaw
	state.velocityX = motion.velocityX
	state.velocityZ = motion.velocityZ
	state.verticalVelocity = motion.verticalVelocity
	state.mode = motion.mode
	self._previousState = self._currentState
	self._previousTime = self._currentTime
	self._currentState = state
	self._currentTime = serverTime
	if self._model and self._ragdolled ~= (state.mode == SimulatedCharacterConstants.Modes.RAGDOLL) then
		self:_setModelRagdolled(state.mode == SimulatedCharacterConstants.Modes.RAGDOLL)
	end
end

function SimulatedCharacterClient._render(self: SimulatedCharacterClient, renderTime: number)
	const model = self._model
	const root = self._root
	if not model or not root then
		return
	end

	const previous = self._previousState
	const current = self._currentState
	local x = current.x
	local z = current.z
	local groundY = current.groundY
	local height = current.height
	local yaw = current.yaw

	if self._currentTime > self._previousTime and renderTime <= self._currentTime then
		const alpha = math.clamp((renderTime - self._previousTime) / (self._currentTime - self._previousTime), 0, 1)
		x = MathUtils.lerp(previous.x, current.x, alpha)
		z = MathUtils.lerp(previous.z, current.z, alpha)
		groundY = MathUtils.lerp(previous.groundY, current.groundY, alpha)
		height = MathUtils.lerp(previous.height, current.height, alpha)
		yaw = SimulatedCharacterUtils.lerpAngle(previous.yaw, current.yaw, alpha)
	elseif renderTime > self._currentTime then
		const extrapolation =
			math.min(renderTime - self._currentTime, SimulatedCharacterConstants.DEFAULT_MAX_EXTRAPOLATION)
		x += current.velocityX * extrapolation
		z += current.velocityZ * extrapolation
		height = math.max(
			0,
			height
				+ current.verticalVelocity * extrapolation
				- 0.5 * workspace.Gravity * self._simulationRate ^ 2 * extrapolation * extrapolation
		)
	end

	self._renderCFrame = SimulatedCharacterUtils.toCFrame(x, z, groundY, height, yaw)
	if self._ragdolled then
		root.CFrame = self._renderCFrame * self._rootCFrameOffset
	else
		model:PivotTo(self._renderCFrame * self._modelPivotOffset)
	end

	self:_updateAnimation()
end

function SimulatedCharacterClient._mountModel(self: SimulatedCharacterClient)
	self._loadToken += 1
	const loadToken = self._loadToken

	self._service
		:_acquireModelAsync(self._definition.templateName)
		:Then(function(model: Model)
			if self._destroyed or self._culled or self._loadToken ~= loadToken then
				self._service:_releaseModel(self._definition.templateName, model)
				return
			end

			self:_prepareModel(model)
			self._model = model
			const state = self._currentState
			self._renderCFrame =
				SimulatedCharacterUtils.toCFrame(state.x, state.z, state.groundY, state.height, state.yaw)
			model.Name = `{self._definition.name}_{self._id}`
			model:PivotTo(self._renderCFrame * self._modelPivotOffset)
			model.Parent = self._service:_getRenderParent()
			self:_setModelRagdolled(self._currentState.mode == SimulatedCharacterConstants.Modes.RAGDOLL, true, true)
			self._service:_setCharacterRendered(self, true)
		end)
		:Catch(function(reason: any)
			if not self._destroyed and self._loadToken == loadToken then
				warn(`[SimulatedCharacterClient] - Failed to mount {self._definition.templateName}: {reason}`)
			end
		end)
end

function SimulatedCharacterClient._unmountModel(self: SimulatedCharacterClient)
	self._loadToken += 1
	self._service:_setCharacterRendered(self, false)
	const model = self._model
	if not model then
		return
	end

	self:_setModelRagdolled(false, true, false)
	self:_stopAnimations()
	self._model = nil
	self._root = nil
	self._modelPivotOffset = CFrame.identity
	self._rootCFrameOffset = CFrame.identity
	table.clear(self._ragdollMotors)
	table.clear(self._ragdollConstraints)
	self._service:_releaseModel(self._definition.templateName, model)
end

function SimulatedCharacterClient._prepareModel(self: SimulatedCharacterClient, model: Model)
	model:ScaleTo(self._definition.scale)
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		root = model:FindFirstChildWhichIsA("BasePart", true)
	end
	assert(root and root:IsA("BasePart"), `Template {self._definition.templateName} has no BasePart`)
	model.PrimaryPart = root
	self._root = root

	const pivot = model:GetPivot()
	const boundsCFrame, boundsSize = model:GetBoundingBox()
	const pivotToBounds = pivot:ToObjectSpace(boundsCFrame)
	const placementMode = self._definition.placementMode
	if placementMode == SimulatedCharacterPlacementMode.BOUNDING_BOX_CENTER then
		self._modelPivotOffset = pivotToBounds:Inverse()
	elseif placementMode == SimulatedCharacterPlacementMode.GROUNDED then
		const centerOffset = (boundsSize.Y - self._definition.hitboxHeight) * 0.5
		self._modelPivotOffset = CFrame.new(0, centerOffset, 0) * pivotToBounds:Inverse()
	else
		self._modelPivotOffset = CFrame.identity
	end
	self._rootCFrameOffset = self._modelPivotOffset * pivot:ToObjectSpace(root.CFrame)

	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = descendant ~= root
			descendant.Anchored = descendant == root
		elseif descendant:IsA("Motor6D") then
			if descendant:GetAttribute(SimulatedCharacterConstants.RAGDOLL_MOTOR_ATTRIBUTE) == true then
				table.insert(self._ragdollMotors, descendant)
			end
		elseif descendant:IsA("LocalScript") then
			descendant.Enabled = false
		elseif descendant:IsA("Constraint") then
			if descendant:GetAttribute(SimulatedCharacterConstants.RAGDOLL_CONSTRAINT_ATTRIBUTE) == true then
				table.insert(self._ragdollConstraints, descendant)
			end
		end
	end

	if #self._ragdollMotors == 0 then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("Motor6D") and descendant.Part0 ~= root and descendant.Part1 ~= root then
				table.insert(self._ragdollMotors, descendant)
			end
		end
	end
	if #self._ragdollConstraints == 0 then
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BallSocketConstraint") then
				table.insert(self._ragdollConstraints, descendant)
			end
		end
	end
end

function SimulatedCharacterClient._loadAnimations(self: SimulatedCharacterClient)
	const model = self._model
	if not model then
		return
	end

	const animator = AnimationUtils.getOrCreateAnimator(model, false)
	const animate = model:FindFirstChild("Animate")
	const templateAnimationIds = if animate
		then DefaultCharacterAnimationUtils.getAnimationIdsFromAnimate(animate)
		else {
			idleAnimationId = "",
			walkAnimationId = "",
		}
	const idleAnimationId = if self._definition.idleAnimationId ~= ""
		then self._definition.idleAnimationId
		elseif
			self._definition.useDefaultAnimations and templateAnimationIds.idleAnimationId ~= ""
		then templateAnimationIds.idleAnimationId
		elseif self._definition.useDefaultAnimations then self._service:_getDefaultAnimationId("Idle")
		else ""
	const walkAnimationId = if self._definition.walkAnimationId ~= ""
		then self._definition.walkAnimationId
		elseif
			self._definition.useDefaultAnimations and templateAnimationIds.walkAnimationId ~= ""
		then templateAnimationIds.walkAnimationId
		elseif self._definition.useDefaultAnimations then self._service:_getDefaultAnimationId("Walk")
		else ""
	if idleAnimationId ~= "" then
		self._idleTrack =
			AnimationUtils.getOrCreateAnimationTrack(animator, idleAnimationId, Enum.AnimationPriority.Idle)
	end
	if walkAnimationId ~= "" then
		self._walkTrack =
			AnimationUtils.getOrCreateAnimationTrack(animator, walkAnimationId, Enum.AnimationPriority.Movement)
	end
	self:_updateAnimation()
	self:_refreshActionAnimation()
end

function SimulatedCharacterClient._refreshAnimations(self: SimulatedCharacterClient)
	if not self._model or self._ragdolled then
		return
	end

	self:_stopAnimations()
	self:_loadAnimations()
end

function SimulatedCharacterClient._updateAnimation(self: SimulatedCharacterClient)
	if self._ragdolled then
		return
	end

	const state = self._currentState
	const speedSquared = state.velocityX * state.velocityX + state.velocityZ * state.velocityZ
	const desiredTrack = if speedSquared > 0.01 then self._walkTrack else self._idleTrack
	if desiredTrack == self._activeTrack then
		return
	end

	if self._activeTrack then
		self._activeTrack:Stop(0.15)
	end
	self._activeTrack = desiredTrack
	if desiredTrack then
		desiredTrack.Looped = true
		desiredTrack:Play(0.15, 1, self._simulationRate)
		if desiredTrack.Length > 0 then
			desiredTrack.TimePosition = math.max(
				0,
				(self._service:_getTime() - state.stateStartedAt) * self._simulationRate
			) % desiredTrack.Length
		end
	end
end

function SimulatedCharacterClient._setSimulationRate(self: SimulatedCharacterClient, rate: number)
	if self._destroyed or self._simulationRate == rate then
		return
	end

	self._simulationRate = rate
	const activeTrack = self._activeTrack
	if activeTrack then
		activeTrack:AdjustSpeed(rate)
	end
end

function SimulatedCharacterClient._playActionAnimation(
	self: SimulatedCharacterClient,
	data: SimulatedCharacterTypes.NetworkAnimationPlay
)
	if self._destroyed or data.id ~= self._id or data.sequence <= self._animationSequence then
		return
	end

	self._animationSequence = data.sequence
	self._actionState = table.clone(data)
	self._actionLoadToken += 1
	self._maid._actionLengthConnection = nil
	if self._model and not self._ragdolled then
		self:_startActionAnimation()
	end
end

function SimulatedCharacterClient._stopActionAnimation(
	self: SimulatedCharacterClient,
	data: SimulatedCharacterTypes.NetworkAnimationStop
)
	if self._destroyed or data.id ~= self._id or data.sequence <= self._animationSequence then
		return
	end

	self._animationSequence = data.sequence
	self._actionState = nil
	self._actionLoadToken += 1
	self._maid._actionLengthConnection = nil
	const actionTrack = self._actionTrack
	self._actionTrack = nil
	if actionTrack then
		actionTrack:Stop(data.fadeTime)
	end
end

function SimulatedCharacterClient._refreshActionAnimation(self: SimulatedCharacterClient)
	if self._model and not self._ragdolled and self._actionState and not self._actionTrack then
		self:_startActionAnimation()
	end
end

function SimulatedCharacterClient._startActionAnimation(self: SimulatedCharacterClient)
	const model = self._model
	const actionState = self._actionState
	if not model or not actionState or self._ragdolled then
		return
	end

	const animationId = self._service:_getActionAnimationId(self._definition.name, actionState.animationIndex)
	if not animationId then
		return
	end

	self._actionLoadToken += 1
	const loadToken = self._actionLoadToken
	self._maid._actionLengthConnection = nil
	local track = self._actionTracksByIndex[actionState.animationIndex]
	if not track then
		const animator = AnimationUtils.getOrCreateAnimator(model, false)
		track = AnimationUtils.getOrCreateAnimationTrack(animator, animationId, Enum.AnimationPriority.Action)
		if not track then
			warn(`[SimulatedCharacterClient] - Failed to load action animation {animationId}`)
			return
		end
		self._actionTracksByIndex[actionState.animationIndex] = track
	end

	const previousTrack = self._actionTrack
	if previousTrack then
		previousTrack:Stop(if previousTrack == track then 0 else actionState.fadeTime)
	end
	self._actionTrack = track
	track.Looped = actionState.looped
	track:Play(actionState.fadeTime, 1, actionState.speed)

	local function synchronizeTimePosition()
		if
			self._destroyed
			or self._actionLoadToken ~= loadToken
			or self._actionTrack ~= track
			or not self._actionState
			or self._actionState.sequence ~= actionState.sequence
		then
			return
		end

		const length = track.Length
		if length <= 0 then
			return
		end
		self._maid._actionLengthConnection = nil
		const elapsed = math.max(0, self._service:_getTime() - actionState.serverTime) * actionState.speed
		if actionState.looped then
			track.TimePosition = elapsed % length
		elseif elapsed < length then
			track.TimePosition = elapsed
		else
			track:Stop(0)
			self._actionTrack = nil
			self._actionState = nil
		end
	end

	synchronizeTimePosition()
	if track.Length <= 0 and self._actionTrack == track then
		self._maid._actionLengthConnection = track:GetPropertyChangedSignal("Length"):Connect(synchronizeTimePosition)
	end
end

function SimulatedCharacterClient._stopAnimations(self: SimulatedCharacterClient)
	self._actionLoadToken += 1
	self._maid._actionLengthConnection = nil
	if self._idleTrack then
		self._idleTrack:Stop(0)
		self._idleTrack:Destroy()
	end
	if self._walkTrack then
		self._walkTrack:Stop(0)
		self._walkTrack:Destroy()
	end
	self._idleTrack = nil
	self._walkTrack = nil
	self._activeTrack = nil
	for _, track in self._actionTracksByIndex do
		track:Stop(0)
		track:Destroy()
	end
	table.clear(self._actionTracksByIndex)
	self._actionTrack = nil
end

function SimulatedCharacterClient._setModelRagdolled(
	self: SimulatedCharacterClient,
	ragdolled: boolean,
	force: boolean?,
	resumeAnimations: boolean?
)
	if self._ragdolled == ragdolled and self._model and not force then
		return
	end

	self._ragdolled = ragdolled
	if ragdolled then
		self:_stopAnimations()
	end
	for _, motor in self._ragdollMotors do
		motor.Enabled = not ragdolled
	end
	for _, constraint in self._ragdollConstraints do
		constraint.Enabled = ragdolled
	end
	if not ragdolled and self._model and resumeAnimations ~= false then
		self:_loadAnimations()
	end
end

function SimulatedCharacterClient.Destroy(self: SimulatedCharacterClient)
	if self._destroyed then
		return
	end

	self._destroyed = true
	ClientCulling.RemoveObject(self)
	self:_unmountModel()
	self._maid:DoCleaning()
end

return SimulatedCharacterClient
