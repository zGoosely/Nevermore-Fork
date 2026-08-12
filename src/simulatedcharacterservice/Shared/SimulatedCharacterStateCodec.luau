--!strict
--!optimize 2
--[=[
	Packs the high-frequency X/Z motion state used by SimulatedCharacterService.

	@util SimulatedCharacterStateCodec
]=]

const require = require("../../Loader").load()

const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")

const FIXED_POINT_SCALE = 32
const FIXED_POINT_INVERSE = 1 / FIXED_POINT_SCALE
const FULL_POSITION_FLAG = 4
const FULL_DYNAMICS_FLAG = 8
const MAX_UINT16 = 65_535
const MIN_INT16 = -32_768
const MAX_INT16 = 32_767
const TAU = 2 * math.pi

const RECORD_HEADER_SIZE = 5
const QUANTIZED_POSITION_SIZE = 4
const FULL_POSITION_SIZE = 8
const YAW_SIZE = 2
const QUANTIZED_PLANAR_VELOCITY_SIZE = 4
const QUANTIZED_PHYSICAL_STATE_SIZE = 4
const FULL_PLANAR_VELOCITY_SIZE = 8
const FULL_PHYSICAL_STATE_SIZE = 8

const SimulatedCharacterStateCodec = {}

const function quantizeSigned(value: number): number
	return math.clamp(math.round(value * FIXED_POINT_SCALE), MIN_INT16, MAX_INT16)
end

const function canQuantizePosition(x: number, z: number, originX: number, originZ: number): boolean
	const quantizedX = math.round((x - originX) * FIXED_POINT_SCALE)
	const quantizedZ = math.round((z - originZ) * FIXED_POINT_SCALE)
	return quantizedX >= 0 and quantizedX <= MAX_UINT16 and quantizedZ >= 0 and quantizedZ <= MAX_UINT16
end

const function canQuantizeDynamics(state: SimulatedCharacterTypes.NetworkState): boolean
	if
		math.abs(state.velocityX * FIXED_POINT_SCALE) > MAX_INT16
		or math.abs(state.velocityZ * FIXED_POINT_SCALE) > MAX_INT16
	then
		return false
	end
	if state.mode == SimulatedCharacterConstants.Modes.KINEMATIC then
		return true
	end
	return state.height >= 0
		and state.height * FIXED_POINT_SCALE <= MAX_UINT16
		and math.abs(state.verticalVelocity * FIXED_POINT_SCALE) <= MAX_INT16
end

const function getRecordSize(state: SimulatedCharacterTypes.NetworkState, originX: number, originZ: number): number
	local size = RECORD_HEADER_SIZE + YAW_SIZE
	if canQuantizePosition(state.x, state.z, originX, originZ) then
		size += QUANTIZED_POSITION_SIZE
	else
		size += FULL_POSITION_SIZE
	end
	const physical = state.mode ~= SimulatedCharacterConstants.Modes.KINEMATIC
	if canQuantizeDynamics(state) then
		size += QUANTIZED_PLANAR_VELOCITY_SIZE
		if physical then
			size += QUANTIZED_PHYSICAL_STATE_SIZE
		end
	else
		size += FULL_PLANAR_VELOCITY_SIZE
		if physical then
			size += FULL_PHYSICAL_STATE_SIZE
		end
	end
	return size
end

--[=[
	Encodes motion states at 1/32-stud precision. The packet-local origin allows
	most X/Z positions within a 2048-stud span to use two uint16 values. Records
	outside that span automatically retain float32 X/Z values.

	@within SimulatedCharacterStateCodec
	@param states { NetworkState }
	@return number, number, buffer
]=]
function SimulatedCharacterStateCodec.encode(states: { SimulatedCharacterTypes.NetworkState }): (number, number, buffer)
	if #states == 0 then
		return 0, 0, buffer.create(0)
	end

	local minimumX = math.huge
	local minimumZ = math.huge
	for _, state in states do
		minimumX = math.min(minimumX, state.x)
		minimumZ = math.min(minimumZ, state.z)
	end

	const originX = math.floor(minimumX * FIXED_POINT_SCALE) * FIXED_POINT_INVERSE
	const originZ = math.floor(minimumZ * FIXED_POINT_SCALE) * FIXED_POINT_INVERSE
	local dataLength = 0
	for _, state in states do
		dataLength += getRecordSize(state, originX, originZ)
	end

	const data = buffer.create(dataLength)
	local cursor = 0
	for _, state in states do
		const fullPosition = not canQuantizePosition(state.x, state.z, originX, originZ)
		const fullDynamics = not canQuantizeDynamics(state)
		const mode = math.clamp(math.floor(state.mode), 0, 3)
		local flags = mode
		if fullPosition then
			flags = bit32.bor(flags, FULL_POSITION_FLAG)
		end
		if fullDynamics then
			flags = bit32.bor(flags, FULL_DYNAMICS_FLAG)
		end

		buffer.writeu32(data, cursor, state.id)
		buffer.writeu8(data, cursor + 4, flags)
		cursor += RECORD_HEADER_SIZE

		if fullPosition then
			buffer.writef32(data, cursor, state.x)
			buffer.writef32(data, cursor + 4, state.z)
			cursor += FULL_POSITION_SIZE
		else
			buffer.writeu16(data, cursor, math.round((state.x - originX) * FIXED_POINT_SCALE))
			buffer.writeu16(data, cursor + 2, math.round((state.z - originZ) * FIXED_POINT_SCALE))
			cursor += QUANTIZED_POSITION_SIZE
		end

		const normalizedYaw = state.yaw % TAU
		buffer.writeu16(data, cursor, math.round(normalizedYaw / TAU * 65_536) % 65_536)
		cursor += YAW_SIZE

		if fullDynamics then
			buffer.writef32(data, cursor, state.velocityX)
			buffer.writef32(data, cursor + 4, state.velocityZ)
			cursor += FULL_PLANAR_VELOCITY_SIZE
			if mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
				buffer.writef32(data, cursor, state.height)
				buffer.writef32(data, cursor + 4, state.verticalVelocity)
				cursor += FULL_PHYSICAL_STATE_SIZE
			end
		else
			buffer.writei16(data, cursor, quantizeSigned(state.velocityX))
			buffer.writei16(data, cursor + 2, quantizeSigned(state.velocityZ))
			cursor += QUANTIZED_PLANAR_VELOCITY_SIZE
			if mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
				buffer.writeu16(data, cursor, math.clamp(math.round(state.height * FIXED_POINT_SCALE), 0, MAX_UINT16))
				buffer.writei16(data, cursor + 2, quantizeSigned(state.verticalVelocity))
				cursor += QUANTIZED_PHYSICAL_STATE_SIZE
			end
		end
	end

	return originX, originZ, data
end

--[=[
	Decodes a packed periodic snapshot into partial motion states. Ground height
	and transition time intentionally remain on the reliable lifecycle state.

	@within SimulatedCharacterStateCodec
	@param originX number
	@param originZ number
	@param data buffer
	@return { NetworkMotionState }
]=]
function SimulatedCharacterStateCodec.decode(
	originX: number,
	originZ: number,
	data: buffer
): { SimulatedCharacterTypes.NetworkMotionState }
	const dataLength = buffer.len(data)
	const states: { SimulatedCharacterTypes.NetworkMotionState } = {}
	local cursor = 0
	while cursor < dataLength do
		assert(cursor + RECORD_HEADER_SIZE <= dataLength, "Malformed simulated character motion header")
		const id = buffer.readu32(data, cursor)
		const flags = buffer.readu8(data, cursor + 4)
		const mode = bit32.band(flags, 3)
		const fullPosition = bit32.band(flags, FULL_POSITION_FLAG) ~= 0
		const fullDynamics = bit32.band(flags, FULL_DYNAMICS_FLAG) ~= 0
		cursor += RECORD_HEADER_SIZE

		local x: number
		local z: number
		if fullPosition then
			assert(cursor + FULL_POSITION_SIZE <= dataLength, "Malformed simulated character float position")
			x = buffer.readf32(data, cursor)
			z = buffer.readf32(data, cursor + 4)
			cursor += FULL_POSITION_SIZE
		else
			assert(cursor + QUANTIZED_POSITION_SIZE <= dataLength, "Malformed simulated character fixed position")
			x = originX + buffer.readu16(data, cursor) * FIXED_POINT_INVERSE
			z = originZ + buffer.readu16(data, cursor + 2) * FIXED_POINT_INVERSE
			cursor += QUANTIZED_POSITION_SIZE
		end

		assert(cursor + YAW_SIZE <= dataLength, "Malformed simulated character yaw")
		const yaw = buffer.readu16(data, cursor) / 65_536 * TAU
		cursor += YAW_SIZE

		local velocityX: number
		local velocityZ: number
		local height = 0
		local verticalVelocity = 0
		if fullDynamics then
			assert(cursor + FULL_PLANAR_VELOCITY_SIZE <= dataLength, "Malformed simulated character velocity")
			velocityX = buffer.readf32(data, cursor)
			velocityZ = buffer.readf32(data, cursor + 4)
			cursor += FULL_PLANAR_VELOCITY_SIZE
			if mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
				assert(cursor + FULL_PHYSICAL_STATE_SIZE <= dataLength, "Malformed simulated character physical state")
				height = buffer.readf32(data, cursor)
				verticalVelocity = buffer.readf32(data, cursor + 4)
				cursor += FULL_PHYSICAL_STATE_SIZE
			end
		else
			assert(cursor + QUANTIZED_PLANAR_VELOCITY_SIZE <= dataLength, "Malformed simulated character velocity")
			velocityX = buffer.readi16(data, cursor) * FIXED_POINT_INVERSE
			velocityZ = buffer.readi16(data, cursor + 2) * FIXED_POINT_INVERSE
			cursor += QUANTIZED_PLANAR_VELOCITY_SIZE
			if mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
				assert(
					cursor + QUANTIZED_PHYSICAL_STATE_SIZE <= dataLength,
					"Malformed simulated character physical state"
				)
				height = buffer.readu16(data, cursor) * FIXED_POINT_INVERSE
				verticalVelocity = buffer.readi16(data, cursor + 2) * FIXED_POINT_INVERSE
				cursor += QUANTIZED_PHYSICAL_STATE_SIZE
			end
		end

		table.insert(states, {
			id = id,
			x = x,
			z = z,
			height = height,
			yaw = yaw,
			velocityX = velocityX,
			velocityZ = velocityZ,
			verticalVelocity = verticalVelocity,
			mode = mode,
		})
	end

	return states
end

return table.freeze(SimulatedCharacterStateCodec)
