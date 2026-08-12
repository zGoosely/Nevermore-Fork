--!strict
--[=[
	ByteNet protocol for SimulatedCharacterService.

	@network SimulatedCharacterNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("SimulatedCharacters", function()
	const state = ByteNet.struct({
		id = ByteNet.uint32,
		x = ByteNet.float32,
		z = ByteNet.float32,
		groundY = ByteNet.float32,
		height = ByteNet.float32,
		yaw = ByteNet.float32,
		velocityX = ByteNet.float32,
		velocityZ = ByteNet.float32,
		verticalVelocity = ByteNet.float32,
		mode = ByteNet.uint8,
		stateStartedAt = ByteNet.float64,
	})

	const definition = ByteNet.struct({
		name = ByteNet.string,
		templateName = ByteNet.string,
		scale = ByteNet.float32,
		placementMode = ByteNet.uint8,
		simulationRate = ByteNet.float32,
		cullDistance = ByteNet.float32,
		hitboxRadius = ByteNet.float32,
		hitboxHeight = ByteNet.float32,
		idleAnimationId = ByteNet.string,
		walkAnimationId = ByteNet.string,
		useDefaultAnimations = ByteNet.bool,
	})

	const spawn = ByteNet.struct({
		serverTime = ByteNet.float64,
		definition = definition,
		state = state,
	})

	const animationCatalog = ByteNet.struct({
		definitionName = ByteNet.string,
		animationIds = ByteNet.array(ByteNet.string),
	})

	const animationPlay = ByteNet.struct({
		id = ByteNet.uint32,
		animationIndex = ByteNet.uint8,
		sequence = ByteNet.uint32,
		serverTime = ByteNet.float64,
		fadeTime = ByteNet.float32,
		speed = ByteNet.float32,
		looped = ByteNet.bool,
	})

	const animationStop = ByteNet.struct({
		id = ByteNet.uint32,
		sequence = ByteNet.uint32,
		fadeTime = ByteNet.float32,
	})

	const debugPoint = ByteNet.struct({
		x = ByteNet.float32,
		z = ByteNet.float32,
	})

	const debugCharacter = ByteNet.struct({
		id = ByteNet.uint32,
		replicationDistance = ByteNet.float32,
		hitboxHeight = ByteNet.float32,
		stoppingDistance = ByteNet.float32,
		flockNeighborRadius = ByteNet.float32,
		hasFlock = ByteNet.bool,
		hasTarget = ByteNet.bool,
		targetX = ByteNet.float32,
		targetZ = ByteNet.float32,
		path = ByteNet.array(debugPoint),
	})

	return {
		packets = {
			animationCatalogChanged = ByteNet.definePacket({
				value = animationCatalog,
			}),
			animationPlayed = ByteNet.definePacket({
				value = animationPlay,
			}),
			animationStopped = ByteNet.definePacket({
				value = animationStop,
			}),
			debugRequested = ByteNet.definePacket({
				value = ByteNet.bool,
			}),
			debugSnapshot = ByteNet.definePacket({
				reliabilityType = "unreliable",
				value = ByteNet.struct({
					hasNavigation = ByteNet.bool,
					navigationMinX = ByteNet.float32,
					navigationMinZ = ByteNet.float32,
					navigationMaxX = ByteNet.float32,
					navigationMaxZ = ByteNet.float32,
					characters = ByteNet.array(debugCharacter),
				}),
			}),
			spawned = ByteNet.definePacket({
				value = spawn,
			}),
			removed = ByteNet.definePacket({
				value = ByteNet.uint32,
			}),
			simulationRateChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					id = ByteNet.uint32,
					rate = ByteNet.float32,
				}),
			}),
			stateChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					serverTime = ByteNet.float64,
					state = state,
				}),
			}),
			snapshot = ByteNet.definePacket({
				reliabilityType = "unreliable",
				value = ByteNet.struct({
					serverTime = ByteNet.float64,
					originX = ByteNet.float32,
					originZ = ByteNet.float32,
					data = ByteNet.buff,
				}),
			}),
		},
		queries = {
			requestAnimationCatalogs = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.array(animationCatalog),
			}),
			requestInitialState = ByteNet.defineQuery({
				request = ByteNet.nothing,
				response = ByteNet.array(spawn),
			}),
		},
	}
end))
