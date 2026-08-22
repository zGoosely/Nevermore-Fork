--!strict
--[=[
	Provides camera-culling bounds and cell helpers.

	@util CameraCullingUtils
]=]

const CameraCullingUtils = {}
const t = require("@game/ReplicatedStorage/Packages/t")

local function getParentBounds(instance: Instance): (Vector3?, number?)
	const parent = instance.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position, parent.Size.Magnitude * 0.5
	end
	return nil, nil
end

--[=[
	Returns a world-space center and radius for a culling instance.

	@within CameraCullingUtils
	@param instance Instance
	@return Vector3?, number?
]=]
function CameraCullingUtils.getBounds(instance: Instance): (Vector3?, number?)
	assert(t.Instance(instance), "Bad instance")
	if instance:IsA("BasePart") then
		return instance.Position, instance.Size.Magnitude * 0.5
	elseif instance:IsA("Model") then
		const cframe, size = instance:GetBoundingBox()
		if size.Magnitude >= 0.01 then
			return cframe.Position, size.Magnitude * 0.5
		end
	elseif instance:IsA("Attachment") then
		return instance.WorldPosition, 0
	end

	const parentPosition, parentRadius = getParentBounds(instance)
	if parentPosition then
		return parentPosition, parentRadius
	end

	const part = instance:FindFirstChildWhichIsA("BasePart", true)
	if part then
		return part.Position, part.Size.Magnitude * 0.5
	end

	return nil, nil
end

--[=[
	Returns integer cell coordinates for a world position.

	@within CameraCullingUtils
	@param position Vector3
	@param cellSize number
	@return number, number, number
]=]
function CameraCullingUtils.getCellCoordinates(position: Vector3, cellSize: number): (number, number, number)
	assert(t.Vector3(position), "Bad position")
	assert(t.numberPositive(cellSize), "Bad cellSize")
	return math.floor(position.X / cellSize), math.floor(position.Y / cellSize), math.floor(position.Z / cellSize)
end

--[=[
	Returns a stable key for cell coordinates.

	@within CameraCullingUtils
	@param x number
	@param y number
	@param z number
	@return string
]=]
function CameraCullingUtils.getCellKey(x: number, y: number, z: number): string
	assert(t.number(x) and t.number(y) and t.number(z), "Bad cell coordinates")
	return `{x}:{y}:{z}`
end

--[=[
	Returns whether bounds are outside the camera culling distance.

	@within CameraCullingUtils
	@param cameraPosition Vector3
	@param center Vector3
	@param radius number
	@param cullDistance number
	@return boolean
]=]
function CameraCullingUtils.shouldCull(
	cameraPosition: Vector3,
	center: Vector3,
	radius: number,
	cullDistance: number
): boolean
	assert(t.Vector3(cameraPosition), "Bad cameraPosition")
	assert(t.Vector3(center), "Bad center")
	assert(t.numberMin(0)(radius), "Bad radius")
	assert(t.numberPositive(cullDistance), "Bad cullDistance")
	return (cameraPosition - center).Magnitude - radius > cullDistance
end

return CameraCullingUtils
