--!strict
--!optimize 2
--[=[
	A lightweight server-authoritative simulated character.

	@class SimulatedCharacter
]=]

const Players = game:GetService("Players")

const require = require("../../Loader").load()

const Maid = require("Maid")
const MathUtils = require("MathUtils")
const Signal = require("Signal")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterFacingMode = require("SimulatedCharacterFacingMode")
const SimulatedCharacterMovementController = require("SimulatedCharacterMovementController")
const SimulatedCharacterTargetingMode = require("SimulatedCharacterTargetingMode")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterUtils = require("SimulatedCharacterUtils")

const WANDER_TARGET_ATTEMPTS = 8

const SimulatedCharacter = {}
SimulatedCharacter.ClassName = "SimulatedCharacter"
SimulatedCharacter.__index = SimulatedCharacter

export type SimulatedCharacter = typeof(setmetatable(
	{} :: {
		TargetChanged: Signal.Signal<Player?>,
		ReachedTarget: Signal.Signal<any>,
		ModeChanged: Signal.Signal<number>,
		Destroyed: Signal.Signal<>,
		_maid: Maid.Maid,
		_service: any,
		_id: number,
		_listIndex: number,
		_flockIndex: number,
		_flockSeparation: Vector2,
		_flockSteering: Vector2,
		_definition: SimulatedCharacterTypes.ResolvedCharacterDefinition,
		_templateName: string,
		_replicationDistance: number,
		_simulationRate: number,
		_simulationTime: number,
		_animationSequence: number,
		_activeAnimation: SimulatedCharacterTypes.NetworkAnimationPlay?,
		_homePosition: Vector2,
		_random: Random,
		_nextRetargetAt: number,
		_nextWanderAt: number,
		_returningHome: boolean,
		_hasReachedTarget: boolean,
		_orbitOffsetAngle: number,
		_position: Vector2,
		_groundY: number,
		_height: number,
		_yaw: number,
		_velocity: Vector2,
		_verticalVelocity: number,
		_mode: number,
		_stateStartedAt: number,
		_targetPlayer: Player?,
		_targetPosition: Vector2?,
		_destroyed: boolean,
	},
	SimulatedCharacter
))

function SimulatedCharacter.new(
	service: any,
	id: number,
	definition: SimulatedCharacterTypes.ResolvedCharacterDefinition,
	templateName: string,
	position: Vector2,
	groundY: number,
	yaw: number,
	ragdolled: boolean
): SimulatedCharacter
	const self: SimulatedCharacter = setmetatable({} :: any, SimulatedCharacter)
	self._maid = Maid.new()
	self.TargetChanged = self._maid:Add(Signal.new())
	self.ReachedTarget = self._maid:Add(Signal.new())
	self.ModeChanged = self._maid:Add(Signal.new())
	self.Destroyed = self._maid:Add(Signal.new())
	self._service = service
	self._id = id
	self._listIndex = 0
	self._flockIndex = 0
	self._flockSeparation = Vector2.zero
	self._flockSteering = Vector2.zero
	self._definition = definition
	self._templateName = templateName
	self._replicationDistance = definition.ReplicationDistance
	self._simulationRate = SimulatedCharacterConstants.DEFAULT_CHARACTER_SIMULATION_RATE or 1
	self._simulationTime = 0
	self._animationSequence = 0
	self._activeAnimation = nil
	self._homePosition = position
	self._random = Random.new(id)
	self._nextRetargetAt = 0
	self._nextWanderAt = 0
	self._returningHome = false
	self._hasReachedTarget = false
	self._orbitOffsetAngle = id * 2.399963229728653
	self._position = position
	self._groundY = groundY
	self._height = 0
	self._yaw = yaw
	self._velocity = Vector2.zero
	self._verticalVelocity = 0
	self._mode = if ragdolled
		then SimulatedCharacterConstants.Modes.RAGDOLL
		else SimulatedCharacterConstants.Modes.KINEMATIC
	self._stateStartedAt = service:_getTime()
	self._targetPlayer = nil
	self._targetPosition = nil
	self._destroyed = false
	return self
end

--[=[
	Returns the character's numeric network id.

	@within SimulatedCharacter
	@return number
]=]
function SimulatedCharacter.GetId(self: SimulatedCharacter): number
	return self._id
end

--[=[
	Returns the character definition name.

	@within SimulatedCharacter
	@return string
]=]
function SimulatedCharacter.GetDefinitionName(self: SimulatedCharacter): string
	return self._definition.Name
end

--[=[
	Returns the selected visual template name. This may differ between spawned
	characters when the definition has template variants.

	@within SimulatedCharacter
	@return string
]=]
function SimulatedCharacter.GetTemplateName(self: SimulatedCharacter): string
	return self._templateName
end

--[=[
	Returns the current authoritative world CFrame.

	@within SimulatedCharacter
	@return CFrame
]=]
function SimulatedCharacter.GetCFrame(self: SimulatedCharacter): CFrame
	return SimulatedCharacterUtils.toCFrame(self._position.X, self._position.Y, self._groundY, self._height, self._yaw)
end

--[=[
	Returns the current X/Z simulation position.

	@within SimulatedCharacter
	@return Vector2
]=]
function SimulatedCharacter.GetPosition(self: SimulatedCharacter): Vector2
	return self._position
end

--[=[
	Returns the size of the lightweight authoritative hitbox. No physical Part is
	created or replicated for this hitbox.

	@within SimulatedCharacter
	@return Vector3
]=]
function SimulatedCharacter.GetHitboxSize(self: SimulatedCharacter): Vector3
	const diameter = self._definition.HitboxRadius * 2
	return Vector3.new(diameter, self._definition.HitboxHeight, diameter)
end

--[=[
	Sets this character's server-to-client movement update distance. Global spawn
	and removal messages remain unaffected.

	@within SimulatedCharacter
	@param distance number
]=]
function SimulatedCharacter.SetReplicationDistance(self: SimulatedCharacter, distance: number)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(type(distance) == "number" and distance >= 0, "Bad distance")
	if self._replicationDistance == distance then
		return
	end

	self._replicationDistance = distance
	self._service:_onCharacterStateChanged(self)
end

--[=[
	Sets this character's local time-scale multiplier. A rate of 0 pauses the
	character, 0.5 runs it at half speed, and 2 runs it at double speed.

	@within SimulatedCharacter
	@param rate number
]=]
function SimulatedCharacter.SetSimulationRate(self: SimulatedCharacter, rate: number)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(type(rate) == "number" and rate == rate and rate >= 0 and rate < math.huge, "Bad rate")
	if self._simulationRate == rate then
		return
	end

	self._simulationRate = rate
	self._service:_onCharacterSimulationRateChanged(self)
end

--[=[
	Plays a registered action animation on interested clients. Action animations
	are cosmetic; authoritative combat timing remains on the server.

	```lua
	zombie:PlayAnimation("Attack", {
		FadeTime = 0.1,
		Speed = 1,
	})
	```

	@within SimulatedCharacter
	@param animationName string
	@param options PlayAnimationOptions?
]=]
function SimulatedCharacter.PlayAnimation(
	self: SimulatedCharacter,
	animationName: string,
	options: SimulatedCharacterTypes.PlayAnimationOptions?
)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(type(animationName) == "string" and animationName ~= "", "Bad animationName")
	assert(options == nil or type(options) == "table", "Bad options")
	const animationIndex =
		assert(self._definition.ActionAnimationIndices[animationName], `Unknown action animation {animationName}`)
	const resolvedOptions = options or {}
	const fadeTime = if resolvedOptions.FadeTime ~= nil then resolvedOptions.FadeTime else 0.1
	const speed = if resolvedOptions.Speed ~= nil then resolvedOptions.Speed else 1
	const looped = resolvedOptions.Looped == true
	assert(
		type(fadeTime) == "number" and fadeTime == fadeTime and fadeTime >= 0 and fadeTime < math.huge,
		"Bad FadeTime"
	)
	assert(type(speed) == "number" and speed == speed and speed >= 0 and speed < math.huge, "Bad Speed")
	assert(resolvedOptions.Looped == nil or type(resolvedOptions.Looped) == "boolean", "Bad Looped")

	const sequence = self._animationSequence + 1
	assert(sequence <= 4_294_967_295, "Animation sequence space exhausted")
	self._animationSequence = sequence
	const animation: SimulatedCharacterTypes.NetworkAnimationPlay = {
		id = self._id,
		animationIndex = animationIndex,
		sequence = sequence,
		serverTime = self._service:_getTime(),
		fadeTime = fadeTime,
		speed = speed,
		looped = looped,
	}
	self._activeAnimation = animation
	self._service:_onCharacterAnimationPlayed(self, animation)
end

--[=[
	Stops the currently playing registered action when its name matches.

	@within SimulatedCharacter
	@param animationName string
	@param fadeTime number?
]=]
function SimulatedCharacter.StopAnimation(self: SimulatedCharacter, animationName: string, fadeTime: number?)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(type(animationName) == "string" and animationName ~= "", "Bad animationName")
	const animationIndex =
		assert(self._definition.ActionAnimationIndices[animationName], `Unknown action animation {animationName}`)
	const resolvedFadeTime = if fadeTime ~= nil then fadeTime else 0.1
	assert(
		type(resolvedFadeTime) == "number"
			and resolvedFadeTime == resolvedFadeTime
			and resolvedFadeTime >= 0
			and resolvedFadeTime < math.huge,
		"Bad fadeTime"
	)
	const activeAnimation = self._activeAnimation
	if not activeAnimation or activeAnimation.animationIndex ~= animationIndex then
		return
	end

	const sequence = self._animationSequence + 1
	assert(sequence <= 4_294_967_295, "Animation sequence space exhausted")
	self._animationSequence = sequence
	self._activeAnimation = nil
	self._service:_onCharacterAnimationStopped(self, {
		id = self._id,
		sequence = sequence,
		fadeTime = resolvedFadeTime,
	})
end

--[=[
	Moves toward an arbitrary X/Z destination using the navigation grid.

	@within SimulatedCharacter
	@param position Vector2 | Vector3
]=]
function SimulatedCharacter.MoveTo(self: SimulatedCharacter, position: Vector2 | Vector3)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	self:_setTargetPlayer(nil)
	self._targetPosition = SimulatedCharacterUtils.toPlanarPosition(position)
	self._returningHome = false
	self._hasReachedTarget = false
end

--[=[
	Chases a player's current character position. Characters chasing the same
	player share one flow field.

	@within SimulatedCharacter
	@param player Player
]=]
function SimulatedCharacter.Chase(self: SimulatedCharacter, player: Player)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	self:_setTargetPlayer(player)
	self._targetPosition = nil
	self._returningHome = false
	self._hasReachedTarget = false
end

--[=[
	Stops kinematic movement without changing the current physical mode.

	@within SimulatedCharacter
]=]
function SimulatedCharacter.Stop(self: SimulatedCharacter)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	self:_setTargetPlayer(nil)
	self._targetPosition = nil
	self._returningHome = false
	self._hasReachedTarget = false
	if self._mode == SimulatedCharacterConstants.Modes.KINEMATIC then
		self._velocity = Vector2.zero
	end
end

--[=[
	Applies an authoritative knockback velocity.

	@within SimulatedCharacter
	@param velocity Vector3
]=]
function SimulatedCharacter.ApplyImpulse(self: SimulatedCharacter, velocity: Vector3)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(typeof(velocity) == "Vector3", "Bad velocity")

	self._velocity += Vector2.new(velocity.X, velocity.Z)
	self._verticalVelocity += velocity.Y
	if self._mode ~= SimulatedCharacterConstants.Modes.RAGDOLL then
		self:_setMode(SimulatedCharacterConstants.Modes.KNOCKBACK)
	else
		self._stateStartedAt = self._service:_getTime()
		self._service:_onCharacterStateChanged(self)
	end
end

--[=[
	Launches toward a world position using MathUtils' ballistic trajectory solver.

	@within SimulatedCharacter
	@param target Vector3
	@param speed number
	@param useHighArc boolean?
	@return boolean
]=]
function SimulatedCharacter.LaunchTowards(
	self: SimulatedCharacter,
	target: Vector3,
	speed: number,
	useHighArc: boolean?
): boolean
	assert(typeof(target) == "Vector3", "Bad target")
	assert(type(speed) == "number" and speed > 0, "Bad speed")
	assert(useHighArc == nil or type(useHighArc) == "boolean", "Bad useHighArc")

	local lowTrajectory, highTrajectory, fallbackTrajectory =
		MathUtils.computeTrajectory(self:GetCFrame().Position, target, speed, workspace.Gravity)
	const trajectory = if useHighArc
		then highTrajectory or lowTrajectory
		else lowTrajectory or highTrajectory or fallbackTrajectory
	if not trajectory then
		return false
	end

	self:ApplyImpulse(trajectory)
	return true
end

--[=[
	Enables or disables the cosmetic ragdoll state. The server continues to
	simulate only the authoritative root.

	@within SimulatedCharacter
	@param ragdolled boolean
]=]
function SimulatedCharacter.SetRagdolled(self: SimulatedCharacter, ragdolled: boolean)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(type(ragdolled) == "boolean", "Bad ragdolled")

	if ragdolled then
		self:_setMode(SimulatedCharacterConstants.Modes.RAGDOLL)
	else
		self._height = 0
		self._verticalVelocity = 0
		self._velocity = Vector2.zero
		self:_setMode(SimulatedCharacterConstants.Modes.KINEMATIC)
	end
end

--[=[
	Teleports the authoritative root and immediately replicates the new state.

	@within SimulatedCharacter
	@param cframe CFrame
]=]
function SimulatedCharacter.Teleport(self: SimulatedCharacter, cframe: CFrame)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(typeof(cframe) == "CFrame", "Bad cframe")

	const position = cframe.Position
	const lookVector = cframe.LookVector
	self._position = Vector2.new(position.X, position.Z)
	self._groundY = SimulatedCharacterUtils.resolveSpawnY(self._definition, position.Y)
	self._homePosition = self._position
	self._height = 0
	self._yaw = math.atan2(-lookVector.X, -lookVector.Z)
	self._velocity = Vector2.zero
	self._verticalVelocity = 0
	self._returningHome = false
	self._hasReachedTarget = false
	self._stateStartedAt = self._service:_getTime()
	self._service:_onCharacterStateChanged(self)
end

function SimulatedCharacter._getTarget(self: SimulatedCharacter): (Vector2?, any?)
	const targetPlayer = self._targetPlayer
	if targetPlayer then
		if targetPlayer.Parent ~= Players then
			self:_setTargetPlayer(nil)
			return nil, nil
		end

		const playerCharacter = targetPlayer.Character
		const root = playerCharacter
			and (playerCharacter:FindFirstChild("HumanoidRootPart") or playerCharacter.PrimaryPart)
		if root and root:IsA("BasePart") then
			const targetPosition = Vector2.new(root.Position.X, root.Position.Z)
			if self._definition.MovementController == SimulatedCharacterMovementController.ORBIT then
				const angle = self._simulationTime * self._definition.OrbitSpeed + self._orbitOffsetAngle
				const orbitPosition = targetPosition
					+ Vector2.new(math.cos(angle), math.sin(angle)) * self._definition.OrbitRadius
				return orbitPosition, self._id
			end

			return targetPosition, targetPlayer
		end
		return nil, nil
	end

	return self._targetPosition, self._id
end

function SimulatedCharacter._getStoppingDistance(self: SimulatedCharacter): number
	if self._returningHome then
		return math.min(self._definition.StoppingDistance, self._definition.LeashRange)
	elseif self._targetPlayer and self._definition.MovementController ~= SimulatedCharacterMovementController.ORBIT then
		return self._definition.StoppingDistance + self._definition.TargetOffset
	else
		return self._definition.StoppingDistance
	end
end

function SimulatedCharacter._step(
	self: SimulatedCharacter,
	deltaTime: number,
	navigation: any?,
	targetCandidates: { SimulatedCharacterTypes.TargetCandidate }
)
	if self._destroyed then
		return
	end
	const simulationDeltaTime = deltaTime * (self._simulationRate or 1)
	if simulationDeltaTime <= 0 then
		return
	end
	self._simulationTime += simulationDeltaTime

	if self._mode == SimulatedCharacterConstants.Modes.KINEMATIC then
		self:_stepController(targetCandidates, navigation)
		self:_stepKinematic(simulationDeltaTime, navigation)
	else
		self:_stepPhysical(simulationDeltaTime, navigation)
	end
end

function SimulatedCharacter._stepController(
	self: SimulatedCharacter,
	targetCandidates: { SimulatedCharacterTypes.TargetCandidate },
	navigation: any?
)
	const definition = self._definition
	const controller = definition.MovementController
	const automaticTargeting = definition.TargetingMode == SimulatedCharacterTargetingMode.NEAREST_PLAYER
	if controller == SimulatedCharacterMovementController.MANUAL and not automaticTargeting then
		return
	end

	const now = self._simulationTime
	const homeDelta = self._position - self._homePosition
	if homeDelta:Dot(homeDelta) > definition.LeashRange * definition.LeashRange then
		self:_setTargetPlayer(nil)
		self._targetPosition = self._homePosition
		self._returningHome = true
		self._hasReachedTarget = false
		return
	end
	if self._returningHome then
		const homeStoppingDistance = math.min(definition.StoppingDistance, definition.LeashRange)
		if homeDelta.Magnitude > homeStoppingDistance then
			self._targetPosition = self._homePosition
			return
		end
		self._targetPosition = nil
		self._returningHome = false
	end

	if automaticTargeting and now >= self._nextRetargetAt then
		self._nextRetargetAt = now + definition.RetargetInterval
		self:_retargetNearestPlayer(targetCandidates)
	end

	if self._targetPlayer then
		self._targetPosition = nil
		self._returningHome = false
		return
	end

	if controller == SimulatedCharacterMovementController.WANDER then
		const shouldSelectTarget = (self._targetPosition == nil and now >= self._nextWanderAt)
			or (self._hasReachedTarget and now >= self._nextWanderAt)
		if shouldSelectTarget then
			local targetPosition: Vector2? = nil
			for _ = 1, WANDER_TARGET_ATTEMPTS do
				const radius = math.sqrt(self._random:NextNumber()) * definition.WanderRadius
				const angle = self._random:NextNumber(0, 2 * math.pi)
				const candidate = self._homePosition + Vector2.new(math.cos(angle), math.sin(angle)) * radius
				if not navigation or navigation:IsWalkable(candidate) then
					targetPosition = candidate
					break
				end
			end

			self._targetPosition = targetPosition
			self._nextWanderAt = now + definition.WanderInterval
			self._returningHome = false
			self._hasReachedTarget = false
		end
	elseif
		controller == SimulatedCharacterMovementController.GUARD
		or controller == SimulatedCharacterMovementController.ORBIT
	then
		const distanceFromHome = homeDelta.Magnitude
		if distanceFromHome > definition.StoppingDistance then
			if not self._returningHome then
				self._hasReachedTarget = false
			end
			self._targetPosition = self._homePosition
			self._returningHome = true
		else
			self._targetPosition = nil
			self._returningHome = false
		end
	elseif controller == SimulatedCharacterMovementController.CHASE then
		self._targetPosition = nil
	end
end

function SimulatedCharacter._retargetNearestPlayer(
	self: SimulatedCharacter,
	targetCandidates: { SimulatedCharacterTypes.TargetCandidate }
)
	const definition = self._definition
	const currentTarget = self._targetPlayer
	const aggroDistanceSquared = definition.AggroRange * definition.AggroRange
	const leashDistanceSquared = definition.LeashRange * definition.LeashRange
	local currentDistanceSquared: number? = nil
	local nearestPlayer: Player? = nil
	local nearestDistanceSquared = math.huge
	for _, candidate in targetCandidates do
		const homeDelta = candidate.Position - self._homePosition
		if homeDelta:Dot(homeDelta) > leashDistanceSquared then
			continue
		end

		const targetDelta = candidate.Position - self._position
		const distanceSquared = targetDelta:Dot(targetDelta)
		if candidate.Player == currentTarget then
			currentDistanceSquared = distanceSquared
		end
		if
			distanceSquared <= aggroDistanceSquared
			and (
				nearestPlayer == nil
				or distanceSquared < nearestDistanceSquared
				or (distanceSquared == nearestDistanceSquared and candidate.Player.UserId < nearestPlayer.UserId)
			)
		then
			nearestPlayer = candidate.Player
			nearestDistanceSquared = distanceSquared
		end
	end

	const selectedPlayer = if currentTarget
			and currentDistanceSquared
			and (nearestPlayer == nil or currentDistanceSquared <= nearestDistanceSquared)
		then currentTarget
		else nearestPlayer
	self:_setTargetPlayer(selectedPlayer)
	if selectedPlayer then
		self._targetPosition = nil
		self._returningHome = false
	end
end

function SimulatedCharacter._stepKinematic(self: SimulatedCharacter, deltaTime: number, navigation: any?)
	local targetPosition, targetKey = self:_getTarget()
	if not targetPosition or targetKey == nil then
		self._velocity = Vector2.zero
		return
	end

	const targetDelta = targetPosition - self._position
	const distance = targetDelta.Magnitude
	const stoppingDistance = self:_getStoppingDistance()
	const arrived = distance <= stoppingDistance
	if arrived then
		if not self._hasReachedTarget then
			self._hasReachedTarget = true
			self.ReachedTarget:Fire(self._targetPlayer or targetPosition)
		end
	else
		self._hasReachedTarget = false
	end
	local pathDirection = Vector2.zero
	if not arrived then
		const navigationDirection = if navigation
			then navigation:GetDirection(self._position, targetKey, targetPosition)
			else targetDelta.Unit
		if not navigationDirection or navigationDirection.Magnitude < 1e-4 then
			self._velocity = Vector2.zero
			if self._definition.FacingMode == SimulatedCharacterFacingMode.TARGET_ALWAYS then
				self:_turnTowards(targetDelta / distance, deltaTime)
			end
			return
		end
		pathDirection = navigationDirection
	end

	local direction = if arrived then self._flockSeparation else pathDirection + self._flockSteering
	if arrived and distance > 1e-4 then
		const towardTarget = targetDelta / distance
		const towardTargetAmount = direction:Dot(towardTarget)
		if towardTargetAmount > 0 then
			direction -= towardTarget * towardTargetAmount
		end
	end
	if direction.Magnitude < 1e-4 then
		self._velocity = Vector2.zero
		if arrived and distance > 1e-4 and self._definition.FacingMode ~= SimulatedCharacterFacingMode.MOVEMENT then
			self:_turnTowards(targetDelta / distance, deltaTime)
		end
		return
	end
	direction = direction.Unit

	const maximumDistance = math.max(0, distance - stoppingDistance)
	const movementDistance = if arrived
		then self._definition.MoveSpeed * deltaTime
		else math.min(self._definition.MoveSpeed * deltaTime, maximumDistance)
	local nextPosition = self._position + direction * movementDistance
	if navigation and not navigation:CanMove(self._position, nextPosition) then
		const pathPosition = self._position + pathDirection * movementDistance
		if arrived or pathDirection.Magnitude < 1e-4 or not navigation:CanMove(self._position, pathPosition) then
			self._velocity = Vector2.zero
			if arrived and distance > 1e-4 and self._definition.FacingMode ~= SimulatedCharacterFacingMode.MOVEMENT then
				self:_turnTowards(targetDelta / distance, deltaTime)
			end
			return
		end
		direction = pathDirection
		nextPosition = pathPosition
	end

	self._velocity = if deltaTime > 0 then (nextPosition - self._position) / deltaTime else Vector2.zero
	self._position = nextPosition
	const faceTarget = distance > 1e-4
		and (
			self._definition.FacingMode == SimulatedCharacterFacingMode.TARGET_ALWAYS
			or (arrived and self._definition.FacingMode == SimulatedCharacterFacingMode.TARGET_WHEN_STOPPED)
		)
	self:_turnTowards(if faceTarget then targetDelta / distance else direction, deltaTime)
end

function SimulatedCharacter._stepPhysical(self: SimulatedCharacter, deltaTime: number, navigation: any?)
	const damping = math.exp(-self._definition.KnockbackDamping * deltaTime)
	self._velocity *= damping
	const nextPosition = self._position + self._velocity * deltaTime

	if not navigation or navigation:CanMove(self._position, nextPosition) then
		self._position = nextPosition
	else
		const xPosition = Vector2.new(nextPosition.X, self._position.Y)
		const zPosition = Vector2.new(self._position.X, nextPosition.Y)
		if navigation:CanMove(self._position, xPosition) then
			self._position = xPosition
			self._velocity = Vector2.new(self._velocity.X, 0)
		elseif navigation:CanMove(self._position, zPosition) then
			self._position = zPosition
			self._velocity = Vector2.new(0, self._velocity.Y)
		else
			self._velocity = Vector2.zero
		end
	end

	self._height += self._verticalVelocity * deltaTime
	self._verticalVelocity -= workspace.Gravity * deltaTime
	if self._height <= 0 then
		self._height = 0
		self._verticalVelocity = 0
		self._velocity *= math.exp(-self._definition.GroundFriction * deltaTime)

		if self._mode == SimulatedCharacterConstants.Modes.KNOCKBACK and self._velocity.Magnitude < 0.25 then
			self._velocity = Vector2.zero
			self:_setMode(SimulatedCharacterConstants.Modes.KINEMATIC)
		end
	end

	if self._velocity.Magnitude > 1e-4 then
		self:_turnTowards(self._velocity, deltaTime)
	end
end

function SimulatedCharacter._turnTowards(self: SimulatedCharacter, direction: Vector2, deltaTime: number)
	if direction.Magnitude < 1e-4 then
		return
	end

	const targetYaw = math.atan2(-direction.X, -direction.Y)
	self._yaw = SimulatedCharacterUtils.moveAngleTowards(self._yaw, targetYaw, self._definition.TurnSpeed * deltaTime)
end

function SimulatedCharacter._setMode(self: SimulatedCharacter, mode: number)
	if self._mode == mode then
		return
	end

	self._mode = mode
	self._stateStartedAt = self._service:_getTime()
	self.ModeChanged:Fire(mode)
	self._service:_onCharacterStateChanged(self)
end

function SimulatedCharacter._setTargetPlayer(self: SimulatedCharacter, player: Player?)
	if self._targetPlayer == player then
		return
	end

	self._targetPlayer = player
	self._hasReachedTarget = false
	self.TargetChanged:Fire(player)
end

function SimulatedCharacter._getNetworkState(self: SimulatedCharacter): SimulatedCharacterTypes.NetworkState
	const simulationRate = self._simulationRate or 1
	return {
		id = self._id,
		x = self._position.X,
		z = self._position.Y,
		groundY = self._groundY,
		height = self._height,
		yaw = self._yaw,
		velocityX = self._velocity.X * simulationRate,
		velocityZ = self._velocity.Y * simulationRate,
		verticalVelocity = self._verticalVelocity * simulationRate,
		mode = self._mode,
		stateStartedAt = self._stateStartedAt,
	}
end

function SimulatedCharacter._destroyInternal(self: SimulatedCharacter)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self.Destroyed:Fire()
	self._service = nil
	self._maid:DoCleaning()
end

function SimulatedCharacter.Destroy(self: SimulatedCharacter)
	if self._destroyed then
		return
	end

	const service = self._service
	if service then
		service:RemoveCharacter(self)
	else
		self:_destroyInternal()
	end
end

return SimulatedCharacter
