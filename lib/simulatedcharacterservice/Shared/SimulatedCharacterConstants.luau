--!strict
--[=[
	Constants shared by SimulatedCharacterService runtimes.

	@class SimulatedCharacterConstants
]=]

const SimulatedCharacterConstants = {}

SimulatedCharacterConstants.Modes = table.freeze({
	KINEMATIC = 0,
	KNOCKBACK = 1,
	RAGDOLL = 2,
})

SimulatedCharacterConstants.DEFAULT_SIMULATION_RATE = 20
SimulatedCharacterConstants.DEFAULT_CHARACTER_SIMULATION_RATE = 1
SimulatedCharacterConstants.DEFAULT_SNAPSHOT_RATE = 10
SimulatedCharacterConstants.DEFAULT_INTERPOLATION_DELAY = 0.1
SimulatedCharacterConstants.DEFAULT_MAX_EXTRAPOLATION = 0.25
SimulatedCharacterConstants.DEFAULT_SPATIAL_CELL_SIZE = 32
SimulatedCharacterConstants.DEFAULT_NAVIGATION_CELL_SIZE = 4
SimulatedCharacterConstants.DEFAULT_NAVIGATION_AGENT_RADIUS = 2
SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_REFRESH = 0.25
SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_PRUNE_INTERVAL = 5
SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_LIFETIME = 10
SimulatedCharacterConstants.DEFAULT_OBSTACLE_TAG = "SimulatedCharacterObstacle"
SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG = "SimulatedCharacterTemplateContainer"

SimulatedCharacterConstants.DEFAULT_MOVE_SPEED = 12
SimulatedCharacterConstants.DEFAULT_TURN_SPEED = math.rad(360)
SimulatedCharacterConstants.DEFAULT_STOPPING_DISTANCE = 2
SimulatedCharacterConstants.DEFAULT_HITBOX_RADIUS = 2
SimulatedCharacterConstants.DEFAULT_HITBOX_HEIGHT = 6
SimulatedCharacterConstants.DEFAULT_CULL_DISTANCE = 250
SimulatedCharacterConstants.DEFAULT_KNOCKBACK_DAMPING = 2
SimulatedCharacterConstants.DEFAULT_GROUND_FRICTION = 8
SimulatedCharacterConstants.DEFAULT_SCALE = 1
SimulatedCharacterConstants.DEFAULT_GROUND_OFFSET = 0.1

SimulatedCharacterConstants.DEFAULT_AGGRO_RANGE = 80
SimulatedCharacterConstants.DEFAULT_LEASH_RANGE = 140
SimulatedCharacterConstants.DEFAULT_TARGET_OFFSET = 0
SimulatedCharacterConstants.DEFAULT_RETARGET_INTERVAL = 0.25
SimulatedCharacterConstants.DEFAULT_WANDER_RADIUS = 24
SimulatedCharacterConstants.DEFAULT_WANDER_INTERVAL = 4
SimulatedCharacterConstants.DEFAULT_ORBIT_RADIUS = 8
SimulatedCharacterConstants.DEFAULT_ORBIT_SPEED = math.rad(45)

SimulatedCharacterConstants.DEFAULT_FLOCK_NEIGHBOR_RADIUS = 14
SimulatedCharacterConstants.DEFAULT_FLOCK_SEPARATION_PADDING = 1
SimulatedCharacterConstants.DEFAULT_FLOCK_SEPARATION_WEIGHT = 1.6
SimulatedCharacterConstants.DEFAULT_FLOCK_ALIGNMENT_WEIGHT = 0.2
SimulatedCharacterConstants.DEFAULT_FLOCK_COHESION_WEIGHT = 0.08
SimulatedCharacterConstants.DEFAULT_FLOCK_MAX_STEERING = 1.75

SimulatedCharacterConstants.RAGDOLL_CONSTRAINT_ATTRIBUTE = "SimulatedCharacterRagdollConstraint"
SimulatedCharacterConstants.RAGDOLL_MOTOR_ATTRIBUTE = "SimulatedCharacterRagdollMotor"

return table.freeze(SimulatedCharacterConstants)
