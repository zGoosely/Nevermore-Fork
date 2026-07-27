--!strict
--[=[
	Shared public types for SimulatedCharacterService.

	@class SimulatedCharacterTypes
]=]

export type PlacementMode = number
export type MovementController = number
export type TargetingMode = number
export type FacingMode = number
export type VariantSelectionMode = number

export type TemplateVariant = {
	Name: string,
	Weight: number?,
}

export type ResolvedTemplateVariant = {
	Name: string,
	Weight: number,
}

export type TemplateConfig = {
	Name: string?,
	Variants: { TemplateVariant }?,
	SelectionMode: VariantSelectionMode?,
	Scale: number?,
}

export type PlacementConfig = {
	Mode: PlacementMode?,
	GroundOffset: number?,
}

export type MovementConfig = {
	Controller: MovementController?,
	MoveSpeed: number?,
	TurnSpeed: number?,
	StoppingDistance: number?,
	FacingMode: FacingMode?,
	WanderRadius: number?,
	WanderInterval: number?,
	OrbitRadius: number?,
	OrbitSpeed: number?,
}

export type TargetingConfig = {
	Mode: TargetingMode?,
	AggroRange: number?,
	LeashRange: number?,
	TargetOffset: number?,
	RetargetInterval: number?,
}

export type FlockingConfig = {
	Group: string?,
	NeighborRadius: number?,
	SeparationPadding: number?,
	SeparationWeight: number?,
	AlignmentWeight: number?,
	CohesionWeight: number?,
	MaxSteering: number?,
}

export type PhysicsConfig = {
	HitboxRadius: number?,
	HitboxHeight: number?,
	KnockbackDamping: number?,
	GroundFriction: number?,
}

export type NetworkingConfig = {
	CullDistance: number?,
	ReplicationDistance: number?,
}

export type AnimationConfig = {
	UseDefaults: boolean?,
	Idle: string?,
	Walk: string?,
	Actions: { [string]: string }?,
}

export type ResolvedActionAnimation = {
	Name: string,
	AnimationId: string,
}

export type PlayAnimationOptions = {
	FadeTime: number?,
	Speed: number?,
	Looped: boolean?,
}

export type CharacterDefinition = {
	Template: TemplateConfig?,
	Placement: PlacementConfig?,
	Movement: MovementConfig?,
	Targeting: TargetingConfig?,
	Flocking: FlockingConfig?,
	Physics: PhysicsConfig?,
	Networking: NetworkingConfig?,
	Animations: AnimationConfig?,

	-- Legacy flat fields remain supported.
	TemplateName: string?,
	MoveSpeed: number?,
	TurnSpeed: number?,
	StoppingDistance: number?,
	HitboxRadius: number?,
	HitboxHeight: number?,
	CullDistance: number?,
	KnockbackDamping: number?,
	GroundFriction: number?,
	IdleAnimationId: string?,
	WalkAnimationId: string?,
	UseDefaultAnimations: boolean?,
	FlockGroup: string?,
}

export type ResolvedCharacterDefinition = {
	Name: string,
	TemplateName: string,
	TemplateVariants: { ResolvedTemplateVariant },
	TemplateSelectionMode: VariantSelectionMode,
	Scale: number,
	PlacementMode: PlacementMode,
	GroundOffset: number,
	MovementController: MovementController,
	MoveSpeed: number,
	TurnSpeed: number,
	StoppingDistance: number,
	FacingMode: FacingMode,
	WanderRadius: number,
	WanderInterval: number,
	OrbitRadius: number,
	OrbitSpeed: number,
	TargetingMode: TargetingMode,
	AggroRange: number,
	LeashRange: number,
	TargetOffset: number,
	RetargetInterval: number,
	HitboxRadius: number,
	HitboxHeight: number,
	CullDistance: number,
	ReplicationDistance: number,
	KnockbackDamping: number,
	GroundFriction: number,
	IdleAnimationId: string,
	WalkAnimationId: string,
	UseDefaultAnimations: boolean,
	ActionAnimations: { ResolvedActionAnimation },
	ActionAnimationIndices: { [string]: number },
	FlockGroup: string,
	FlockNeighborRadius: number,
	FlockSeparationPadding: number,
	FlockSeparationWeight: number,
	FlockAlignmentWeight: number,
	FlockCohesionWeight: number,
	FlockMaxSteering: number,
}

export type TargetCandidate = {
	Player: Player,
	Position: Vector2,
}

export type NavigationConfig = {
	Min: Vector2,
	Max: Vector2,
	CellSize: number?,
	AgentRadius: number?,
	ObstacleTag: string?,
}

export type SpawnData = {
	CFrame: CFrame?,
	Position: Vector2?,
	GroundY: number?,
	Yaw: number?,
	Ragdolled: boolean?,
}

export type NetworkState = {
	id: number,
	x: number,
	z: number,
	groundY: number,
	height: number,
	yaw: number,
	velocityX: number,
	velocityZ: number,
	verticalVelocity: number,
	mode: number,
	stateStartedAt: number,
}

export type NetworkMotionState = {
	id: number,
	x: number,
	z: number,
	height: number,
	yaw: number,
	velocityX: number,
	velocityZ: number,
	verticalVelocity: number,
	mode: number,
}

export type NetworkDefinition = {
	name: string,
	templateName: string,
	scale: number,
	placementMode: PlacementMode,
	simulationRate: number,
	cullDistance: number,
	hitboxRadius: number,
	hitboxHeight: number,
	idleAnimationId: string,
	walkAnimationId: string,
	useDefaultAnimations: boolean,
}

export type NetworkSpawn = {
	serverTime: number,
	definition: NetworkDefinition,
	state: NetworkState,
}

export type NetworkSnapshot = {
	serverTime: number,
	originX: number,
	originZ: number,
	data: buffer,
}

export type NetworkSimulationRate = {
	id: number,
	rate: number,
}

export type NetworkAnimationCatalog = {
	definitionName: string,
	animationIds: { string },
}

export type NetworkAnimationPlay = {
	id: number,
	animationIndex: number,
	sequence: number,
	serverTime: number,
	fadeTime: number,
	speed: number,
	looped: boolean,
}

export type NetworkAnimationStop = {
	id: number,
	sequence: number,
	fadeTime: number,
}

export type NetworkDebugPoint = {
	x: number,
	z: number,
}

export type NetworkDebugCharacter = {
	id: number,
	replicationDistance: number,
	hitboxHeight: number,
	stoppingDistance: number,
	flockNeighborRadius: number,
	hasFlock: boolean,
	hasTarget: boolean,
	targetX: number,
	targetZ: number,
	path: { NetworkDebugPoint },
}

export type NetworkDebugSnapshot = {
	hasNavigation: boolean,
	navigationMinX: number,
	navigationMinZ: number,
	navigationMaxX: number,
	navigationMaxZ: number,
	characters: { NetworkDebugCharacter },
}

return table.freeze({})
