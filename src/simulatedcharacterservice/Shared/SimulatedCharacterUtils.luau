--!strict
--[=[
	Shared math and definition helpers for SimulatedCharacterService.

	@util SimulatedCharacterUtils
]=]

const require = require("../../Loader").load()

const MathUtils = require("MathUtils")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterFacingMode = require("SimulatedCharacterFacingMode")
const SimulatedCharacterMovementController = require("SimulatedCharacterMovementController")
const SimulatedCharacterPlacementMode = require("SimulatedCharacterPlacementMode")
const SimulatedCharacterTargetingMode = require("SimulatedCharacterTargetingMode")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterVariantSelectionMode = require("SimulatedCharacterVariantSelectionMode")

const SimulatedCharacterUtils = {}

--[=[
	Resolves and validates a registered character definition.

	@within SimulatedCharacterUtils
	@param name string
	@param definition CharacterDefinition
	@return ResolvedCharacterDefinition
]=]
function SimulatedCharacterUtils.resolveDefinition(
	name: string,
	definition: SimulatedCharacterTypes.CharacterDefinition
): SimulatedCharacterTypes.ResolvedCharacterDefinition
	assert(type(name) == "string" and name ~= "", "Bad name")
	assert(type(definition) == "table", "Bad definition")
	assert(definition.Template == nil or type(definition.Template) == "table", "Bad Template")
	assert(definition.Placement == nil or type(definition.Placement) == "table", "Bad Placement")
	assert(definition.Movement == nil or type(definition.Movement) == "table", "Bad Movement")
	assert(definition.Targeting == nil or type(definition.Targeting) == "table", "Bad Targeting")
	assert(definition.Flocking == nil or type(definition.Flocking) == "table", "Bad Flocking")
	assert(definition.Physics == nil or type(definition.Physics) == "table", "Bad Physics")
	assert(definition.Networking == nil or type(definition.Networking) == "table", "Bad Networking")
	assert(definition.Animations == nil or type(definition.Animations) == "table", "Bad Animations")

	const template = definition.Template or {}
	const placement = definition.Placement or {}
	const movement = definition.Movement or {}
	const targeting = definition.Targeting or {}
	const flocking = definition.Flocking or {}
	const physics = definition.Physics or {}
	const networking = definition.Networking or {}
	const animations = definition.Animations or {}
	assert(template.Name == nil or type(template.Name) == "string", "Bad Template.Name")
	assert(template.Variants == nil or type(template.Variants) == "table", "Bad Template.Variants")
	assert(
		template.SelectionMode == nil or SimulatedCharacterVariantSelectionMode:IsValue(template.SelectionMode),
		"Bad Template.SelectionMode"
	)
	assert(template.Scale == nil or type(template.Scale) == "number", "Bad Template.Scale")
	assert(placement.Mode == nil or SimulatedCharacterPlacementMode:IsValue(placement.Mode), "Bad Placement.Mode")
	assert(placement.GroundOffset == nil or type(placement.GroundOffset) == "number", "Bad Placement.GroundOffset")
	assert(
		movement.Controller == nil or SimulatedCharacterMovementController:IsValue(movement.Controller),
		"Bad Movement.Controller"
	)
	assert(movement.MoveSpeed == nil or type(movement.MoveSpeed) == "number", "Bad Movement.MoveSpeed")
	assert(movement.TurnSpeed == nil or type(movement.TurnSpeed) == "number", "Bad Movement.TurnSpeed")
	assert(
		movement.StoppingDistance == nil or type(movement.StoppingDistance) == "number",
		"Bad Movement.StoppingDistance"
	)
	assert(
		movement.FacingMode == nil or SimulatedCharacterFacingMode:IsValue(movement.FacingMode),
		"Bad Movement.FacingMode"
	)
	assert(movement.WanderRadius == nil or type(movement.WanderRadius) == "number", "Bad Movement.WanderRadius")
	assert(movement.WanderInterval == nil or type(movement.WanderInterval) == "number", "Bad Movement.WanderInterval")
	assert(movement.OrbitRadius == nil or type(movement.OrbitRadius) == "number", "Bad Movement.OrbitRadius")
	assert(movement.OrbitSpeed == nil or type(movement.OrbitSpeed) == "number", "Bad Movement.OrbitSpeed")
	assert(targeting.Mode == nil or SimulatedCharacterTargetingMode:IsValue(targeting.Mode), "Bad Targeting.Mode")
	assert(targeting.AggroRange == nil or type(targeting.AggroRange) == "number", "Bad Targeting.AggroRange")
	assert(targeting.LeashRange == nil or type(targeting.LeashRange) == "number", "Bad Targeting.LeashRange")
	assert(targeting.TargetOffset == nil or type(targeting.TargetOffset) == "number", "Bad Targeting.TargetOffset")
	assert(
		targeting.RetargetInterval == nil or type(targeting.RetargetInterval) == "number",
		"Bad Targeting.RetargetInterval"
	)
	assert(flocking.Group == nil or type(flocking.Group) == "string", "Bad Flocking.Group")
	assert(flocking.NeighborRadius == nil or type(flocking.NeighborRadius) == "number", "Bad Flocking.NeighborRadius")
	assert(
		flocking.SeparationPadding == nil or type(flocking.SeparationPadding) == "number",
		"Bad Flocking.SeparationPadding"
	)
	assert(
		flocking.SeparationWeight == nil or type(flocking.SeparationWeight) == "number",
		"Bad Flocking.SeparationWeight"
	)
	assert(
		flocking.AlignmentWeight == nil or type(flocking.AlignmentWeight) == "number",
		"Bad Flocking.AlignmentWeight"
	)
	assert(flocking.CohesionWeight == nil or type(flocking.CohesionWeight) == "number", "Bad Flocking.CohesionWeight")
	assert(flocking.MaxSteering == nil or type(flocking.MaxSteering) == "number", "Bad Flocking.MaxSteering")
	assert(physics.HitboxRadius == nil or type(physics.HitboxRadius) == "number", "Bad Physics.HitboxRadius")
	assert(physics.HitboxHeight == nil or type(physics.HitboxHeight) == "number", "Bad Physics.HitboxHeight")
	assert(
		physics.KnockbackDamping == nil or type(physics.KnockbackDamping) == "number",
		"Bad Physics.KnockbackDamping"
	)
	assert(physics.GroundFriction == nil or type(physics.GroundFriction) == "number", "Bad Physics.GroundFriction")
	assert(networking.CullDistance == nil or type(networking.CullDistance) == "number", "Bad Networking.CullDistance")
	assert(
		networking.ReplicationDistance == nil or type(networking.ReplicationDistance) == "number",
		"Bad Networking.ReplicationDistance"
	)
	assert(animations.UseDefaults == nil or type(animations.UseDefaults) == "boolean", "Bad Animations.UseDefaults")
	assert(animations.Idle == nil or type(animations.Idle) == "string", "Bad Animations.Idle")
	assert(animations.Walk == nil or type(animations.Walk) == "string", "Bad Animations.Walk")
	assert(animations.Actions == nil or type(animations.Actions) == "table", "Bad Animations.Actions")
	assert(definition.TemplateName == nil or type(definition.TemplateName) == "string", "Bad TemplateName")
	assert(definition.MoveSpeed == nil or type(definition.MoveSpeed) == "number", "Bad MoveSpeed")
	assert(definition.TurnSpeed == nil or type(definition.TurnSpeed) == "number", "Bad TurnSpeed")
	assert(definition.StoppingDistance == nil or type(definition.StoppingDistance) == "number", "Bad StoppingDistance")
	assert(definition.HitboxRadius == nil or type(definition.HitboxRadius) == "number", "Bad HitboxRadius")
	assert(definition.HitboxHeight == nil or type(definition.HitboxHeight) == "number", "Bad HitboxHeight")
	assert(definition.CullDistance == nil or type(definition.CullDistance) == "number", "Bad CullDistance")
	assert(definition.KnockbackDamping == nil or type(definition.KnockbackDamping) == "number", "Bad KnockbackDamping")
	assert(definition.GroundFriction == nil or type(definition.GroundFriction) == "number", "Bad GroundFriction")
	assert(definition.IdleAnimationId == nil or type(definition.IdleAnimationId) == "string", "Bad IdleAnimationId")
	assert(definition.WalkAnimationId == nil or type(definition.WalkAnimationId) == "string", "Bad WalkAnimationId")
	assert(
		definition.UseDefaultAnimations == nil or type(definition.UseDefaultAnimations) == "boolean",
		"Bad UseDefaultAnimations"
	)
	assert(definition.FlockGroup == nil or type(definition.FlockGroup) == "string", "Bad FlockGroup")
	const usesNestedConfig = definition.Template ~= nil
		or definition.Placement ~= nil
		or definition.Movement ~= nil
		or definition.Targeting ~= nil
		or definition.Flocking ~= nil
		or definition.Physics ~= nil
		or definition.Networking ~= nil
		or definition.Animations ~= nil

	local templateName = template.Name or definition.TemplateName
	assert(templateName == nil or type(templateName) == "string", "Bad Template.Name")
	assert(templateName == nil or templateName ~= "", "Bad Template.Name")
	assert(template.Variants == nil or type(template.Variants) == "table", "Bad Template.Variants")
	const templateVariants: { SimulatedCharacterTypes.ResolvedTemplateVariant } = {}
	local totalVariantWeight = 0
	if template.Variants then
		for _, variant in template.Variants do
			assert(type(variant) == "table", "Bad template variant")
			assert(type(variant.Name) == "string" and variant.Name ~= "", "Bad template variant Name")
			assert(
				variant.Weight == nil or (type(variant.Weight) == "number" and variant.Weight >= 0),
				"Bad template variant Weight"
			)
			const weight = variant.Weight or 1
			totalVariantWeight += weight
			table.insert(
				templateVariants,
				table.freeze({
					Name = variant.Name,
					Weight = weight,
				})
			)
		end
		assert(#templateVariants > 0, "Template.Variants must not be empty")
		templateName = templateName or templateVariants[1].Name
	else
		assert(type(templateName) == "string" and templateName ~= "", "No template configured")
		totalVariantWeight = 1
		templateVariants[1] = table.freeze({
			Name = templateName,
			Weight = 1,
		})
	end
	assert(totalVariantWeight > 0, "Template variants must have positive total weight")
	const templateSelectionMode = template.SelectionMode or SimulatedCharacterVariantSelectionMode.WEIGHTED
	assert(SimulatedCharacterVariantSelectionMode:IsValue(templateSelectionMode), "Bad Template.SelectionMode")
	const scale = template.Scale or SimulatedCharacterConstants.DEFAULT_SCALE
	assert(type(scale) == "number" and scale > 0, "Bad Template.Scale")

	const placementMode = placement.Mode
		or (
			if usesNestedConfig then SimulatedCharacterPlacementMode.GROUNDED else SimulatedCharacterPlacementMode.PIVOT
		)
	assert(SimulatedCharacterPlacementMode:IsValue(placementMode), "Bad Placement.Mode")
	const groundOffset = if placement.GroundOffset ~= nil
		then placement.GroundOffset
		else if usesNestedConfig then SimulatedCharacterConstants.DEFAULT_GROUND_OFFSET else 0
	assert(type(groundOffset) == "number", "Bad Placement.GroundOffset")

	const movementController = movement.Controller or SimulatedCharacterMovementController.MANUAL
	assert(SimulatedCharacterMovementController:IsValue(movementController), "Bad Movement.Controller")
	const moveSpeed = movement.MoveSpeed or definition.MoveSpeed or SimulatedCharacterConstants.DEFAULT_MOVE_SPEED
	const turnSpeed = movement.TurnSpeed or definition.TurnSpeed or SimulatedCharacterConstants.DEFAULT_TURN_SPEED
	const stoppingDistance = movement.StoppingDistance
		or definition.StoppingDistance
		or SimulatedCharacterConstants.DEFAULT_STOPPING_DISTANCE
	const facingMode = movement.FacingMode or SimulatedCharacterFacingMode.TARGET_WHEN_STOPPED
	const wanderRadius = movement.WanderRadius or SimulatedCharacterConstants.DEFAULT_WANDER_RADIUS
	const wanderInterval = movement.WanderInterval or SimulatedCharacterConstants.DEFAULT_WANDER_INTERVAL
	const orbitRadius = movement.OrbitRadius or SimulatedCharacterConstants.DEFAULT_ORBIT_RADIUS
	const orbitSpeed = movement.OrbitSpeed or SimulatedCharacterConstants.DEFAULT_ORBIT_SPEED
	assert(type(moveSpeed) == "number" and moveSpeed >= 0, "Bad Movement.MoveSpeed")
	assert(type(turnSpeed) == "number" and turnSpeed >= 0, "Bad Movement.TurnSpeed")
	assert(type(stoppingDistance) == "number" and stoppingDistance >= 0, "Bad Movement.StoppingDistance")
	assert(SimulatedCharacterFacingMode:IsValue(facingMode), "Bad Movement.FacingMode")
	assert(type(wanderRadius) == "number" and wanderRadius >= 0, "Bad Movement.WanderRadius")
	assert(type(wanderInterval) == "number" and wanderInterval > 0, "Bad Movement.WanderInterval")
	assert(type(orbitRadius) == "number" and orbitRadius >= 0, "Bad Movement.OrbitRadius")
	assert(type(orbitSpeed) == "number", "Bad Movement.OrbitSpeed")

	const targetingMode = targeting.Mode or SimulatedCharacterTargetingMode.MANUAL
	const aggroRange = targeting.AggroRange or SimulatedCharacterConstants.DEFAULT_AGGRO_RANGE
	const leashRange = targeting.LeashRange or SimulatedCharacterConstants.DEFAULT_LEASH_RANGE
	const targetOffset = targeting.TargetOffset or SimulatedCharacterConstants.DEFAULT_TARGET_OFFSET
	const retargetInterval = targeting.RetargetInterval or SimulatedCharacterConstants.DEFAULT_RETARGET_INTERVAL
	assert(SimulatedCharacterTargetingMode:IsValue(targetingMode), "Bad Targeting.Mode")
	assert(type(aggroRange) == "number" and aggroRange >= 0, "Bad Targeting.AggroRange")
	assert(type(leashRange) == "number" and leashRange >= aggroRange, "Bad Targeting.LeashRange")
	assert(type(targetOffset) == "number" and targetOffset >= 0, "Bad Targeting.TargetOffset")
	assert(type(retargetInterval) == "number" and retargetInterval > 0, "Bad Targeting.RetargetInterval")

	const hitboxRadius = physics.HitboxRadius
		or definition.HitboxRadius
		or SimulatedCharacterConstants.DEFAULT_HITBOX_RADIUS
	const hitboxHeight = physics.HitboxHeight
		or definition.HitboxHeight
		or SimulatedCharacterConstants.DEFAULT_HITBOX_HEIGHT
	const knockbackDamping = physics.KnockbackDamping
		or definition.KnockbackDamping
		or SimulatedCharacterConstants.DEFAULT_KNOCKBACK_DAMPING
	const groundFriction = physics.GroundFriction
		or definition.GroundFriction
		or SimulatedCharacterConstants.DEFAULT_GROUND_FRICTION
	assert(type(hitboxRadius) == "number" and hitboxRadius >= 0, "Bad Physics.HitboxRadius")
	assert(type(hitboxHeight) == "number" and hitboxHeight >= 0, "Bad Physics.HitboxHeight")
	assert(type(knockbackDamping) == "number" and knockbackDamping >= 0, "Bad Physics.KnockbackDamping")
	assert(type(groundFriction) == "number" and groundFriction >= 0, "Bad Physics.GroundFriction")

	const cullDistance = networking.CullDistance
		or definition.CullDistance
		or SimulatedCharacterConstants.DEFAULT_CULL_DISTANCE
	const replicationDistance = networking.ReplicationDistance or cullDistance
	assert(type(cullDistance) == "number" and cullDistance >= 0, "Bad Networking.CullDistance")
	assert(type(replicationDistance) == "number" and replicationDistance >= 0, "Bad Networking.ReplicationDistance")

	const idleAnimationId = animations.Idle or definition.IdleAnimationId or ""
	const walkAnimationId = animations.Walk or definition.WalkAnimationId or ""
	const useDefaultAnimations = if animations.UseDefaults ~= nil
		then animations.UseDefaults
		else definition.UseDefaultAnimations ~= false
	assert(type(idleAnimationId) == "string", "Bad Animations.Idle")
	assert(type(walkAnimationId) == "string", "Bad Animations.Walk")
	assert(type(useDefaultAnimations) == "boolean", "Bad Animations.UseDefaults")
	const actionAnimationNames: { string } = {}
	for actionName, animationId in animations.Actions or {} do
		assert(type(actionName) == "string" and actionName ~= "", "Bad Animations.Actions name")
		assert(type(animationId) == "string" and animationId ~= "", `Bad Animations.Actions.{actionName}`)
		table.insert(actionAnimationNames, actionName)
	end
	table.sort(actionAnimationNames)
	assert(#actionAnimationNames <= 255, "Animations.Actions supports at most 255 entries")
	const actionAnimations: { SimulatedCharacterTypes.ResolvedActionAnimation } = table.create(#actionAnimationNames)
	const actionAnimationIndices: { [string]: number } = {}
	for index, actionName in actionAnimationNames do
		const animationId = (animations.Actions :: { [string]: string })[actionName]
		actionAnimations[index] = table.freeze({
			Name = actionName,
			AnimationId = animationId,
		})
		actionAnimationIndices[actionName] = index
	end

	const flockGroup = if flocking.Group ~= nil then flocking.Group else definition.FlockGroup or ""
	const flockNeighborRadius = flocking.NeighborRadius or SimulatedCharacterConstants.DEFAULT_FLOCK_NEIGHBOR_RADIUS
	const flockSeparationPadding = flocking.SeparationPadding
		or SimulatedCharacterConstants.DEFAULT_FLOCK_SEPARATION_PADDING
	const flockSeparationWeight = flocking.SeparationWeight
		or SimulatedCharacterConstants.DEFAULT_FLOCK_SEPARATION_WEIGHT
	const flockAlignmentWeight = flocking.AlignmentWeight or SimulatedCharacterConstants.DEFAULT_FLOCK_ALIGNMENT_WEIGHT
	const flockCohesionWeight = flocking.CohesionWeight or SimulatedCharacterConstants.DEFAULT_FLOCK_COHESION_WEIGHT
	const flockMaxSteering = flocking.MaxSteering or SimulatedCharacterConstants.DEFAULT_FLOCK_MAX_STEERING
	assert(type(flockGroup) == "string", "Bad Flocking.Group")
	assert(type(flockNeighborRadius) == "number" and flockNeighborRadius >= 0, "Bad Flocking.NeighborRadius")
	assert(type(flockSeparationPadding) == "number" and flockSeparationPadding >= 0, "Bad Flocking.SeparationPadding")
	assert(type(flockSeparationWeight) == "number" and flockSeparationWeight >= 0, "Bad Flocking.SeparationWeight")
	assert(type(flockAlignmentWeight) == "number" and flockAlignmentWeight >= 0, "Bad Flocking.AlignmentWeight")
	assert(type(flockCohesionWeight) == "number" and flockCohesionWeight >= 0, "Bad Flocking.CohesionWeight")
	assert(type(flockMaxSteering) == "number" and flockMaxSteering >= 0, "Bad Flocking.MaxSteering")

	return table.freeze({
		Name = name,
		TemplateName = templateName :: string,
		TemplateVariants = table.freeze(templateVariants),
		TemplateSelectionMode = templateSelectionMode,
		Scale = scale,
		PlacementMode = placementMode,
		GroundOffset = groundOffset,
		MovementController = movementController,
		MoveSpeed = moveSpeed,
		TurnSpeed = turnSpeed,
		StoppingDistance = stoppingDistance,
		FacingMode = facingMode,
		WanderRadius = wanderRadius,
		WanderInterval = wanderInterval,
		OrbitRadius = orbitRadius,
		OrbitSpeed = orbitSpeed,
		TargetingMode = targetingMode,
		AggroRange = aggroRange,
		LeashRange = leashRange,
		TargetOffset = targetOffset,
		RetargetInterval = retargetInterval,
		HitboxRadius = hitboxRadius,
		HitboxHeight = hitboxHeight,
		CullDistance = cullDistance,
		ReplicationDistance = replicationDistance,
		KnockbackDamping = knockbackDamping,
		GroundFriction = groundFriction,
		IdleAnimationId = idleAnimationId,
		WalkAnimationId = walkAnimationId,
		UseDefaultAnimations = useDefaultAnimations,
		ActionAnimations = table.freeze(actionAnimations),
		ActionAnimationIndices = table.freeze(actionAnimationIndices),
		FlockGroup = flockGroup,
		FlockNeighborRadius = flockNeighborRadius,
		FlockSeparationPadding = flockSeparationPadding,
		FlockSeparationWeight = flockSeparationWeight,
		FlockAlignmentWeight = flockAlignmentWeight,
		FlockCohesionWeight = flockCohesionWeight,
		FlockMaxSteering = flockMaxSteering,
	})
end

--[=[
	Resolves a configured spawn Y coordinate into the authoritative hitbox center.

	@within SimulatedCharacterUtils
	@param definition ResolvedCharacterDefinition
	@param y number
	@return number
]=]
function SimulatedCharacterUtils.resolveSpawnY(
	definition: SimulatedCharacterTypes.ResolvedCharacterDefinition,
	y: number
): number
	if definition.PlacementMode == SimulatedCharacterPlacementMode.GROUNDED then
		return y + definition.HitboxHeight * 0.5 + definition.GroundOffset
	end
	return y + definition.GroundOffset
end

--[=[
	Converts a world position into the X/Z simulation plane.

	@within SimulatedCharacterUtils
	@param value Vector2 | Vector3
	@return Vector2
]=]
function SimulatedCharacterUtils.toPlanarPosition(value: Vector2 | Vector3): Vector2
	if typeof(value) == "Vector2" then
		return value
	elseif typeof(value) == "Vector3" then
		return Vector2.new(value.X, value.Z)
	end

	error("Bad planar position")
end

--[=[
	Returns the shortest interpolated angle.

	@within SimulatedCharacterUtils
	@param from number
	@param to number
	@param alpha number
	@return number
]=]
function SimulatedCharacterUtils.lerpAngle(from: number, to: number, alpha: number): number
	const difference = (to - from + math.pi) % (2 * math.pi) - math.pi
	return MathUtils.lerp(from, from + difference, alpha)
end

--[=[
	Moves an angle toward another angle by a maximum delta.

	@within SimulatedCharacterUtils
	@param from number
	@param to number
	@param maxDelta number
	@return number
]=]
function SimulatedCharacterUtils.moveAngleTowards(from: number, to: number, maxDelta: number): number
	const difference = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + math.clamp(difference, -maxDelta, maxDelta)
end

--[=[
	Builds the rendered root CFrame for a network state.

	@within SimulatedCharacterUtils
	@param x number
	@param z number
	@param groundY number
	@param height number
	@param yaw number
	@return CFrame
]=]
function SimulatedCharacterUtils.toCFrame(x: number, z: number, groundY: number, height: number, yaw: number): CFrame
	return CFrame.new(x, groundY + height, z) * CFrame.Angles(0, yaw, 0)
end

return SimulatedCharacterUtils
