--!strict
--[=[
	Validates culling configuration and performs bounds and distance math.

	@util ClientCullingUtils
]=]
const ClientCullingConstants = require("./ClientCullingConstants")
const ClientCullingTypes = require("./ClientCullingTypes")
const t = require("@game/ReplicatedStorage/Packages/t")

type CullBounds = ClientCullingTypes.CullBounds
type CullConfig = ClientCullingTypes.CullConfig

const ClientCullingUtils = {}

local function isFiniteNonnegativeNumber(value: any): boolean
	return t.number(value) and value >= 0 and value < math.huge
end

local function deriveForPVInstance(instance: Instance): (CFrame?, Vector3?)
	if instance:IsA("Model") then
		const cframe, size = instance:GetBoundingBox()
		if size.Magnitude >= 0.01 then
			return cframe, size
		end

		const primaryPart = instance.PrimaryPart
		if primaryPart then
			return primaryPart.CFrame, primaryPart.Size
		end

		const firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			return firstPart.CFrame, firstPart.Size
		end
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return nil, nil
end

local function deriveForAdornee(instance: SurfaceGui | BillboardGui): (CFrame?, Vector3?)
	const adornee = (instance :: any).Adornee or instance.Parent
	if adornee and (adornee:IsA("BasePart") or adornee:IsA("Model")) then
		return deriveForPVInstance(adornee)
	end
	return nil, nil
end

local function deriveForBeamLike(instance: Beam | Trail): (CFrame?, Vector3?)
	const attachment0 = instance.Attachment0
	const attachment1 = instance.Attachment1
	if not attachment0 or not attachment1 then
		return nil, nil
	end

	const position0 = attachment0.WorldPosition
	const position1 = attachment1.WorldPosition
	const center = (position0 + position1) * 0.5
	const delta = position1 - position0
	const length = delta.Magnitude
	const thickness = if instance:IsA("Beam") then math.max(instance.Width0, instance.Width1, 1) else 1
	if length < 0.001 then
		return CFrame.new(center), Vector3.one * thickness
	end

	return CFrame.lookAt(center, center + delta.Unit), Vector3.new(thickness, thickness, length)
end

local function deriveForParent(instance: Instance): (CFrame?, Vector3?)
	const parent = instance.Parent
	if not parent then
		return nil, nil
	elseif parent:IsA("Attachment") then
		return parent.WorldCFrame, Vector3.one
	elseif parent:IsA("BasePart") or parent:IsA("Model") then
		return deriveForPVInstance(parent)
	end
	return nil, nil
end

--[=[
	Resolves and validates the culling attributes on an Instance.

	@within ClientCullingUtils
	@param adornee Instance
	@return CullConfig?
	@return string?
]=]
function ClientCullingUtils.getConfig(adornee: Instance): (CullConfig?, string?)
	assert(t.Instance(adornee), "Bad adornee")

	const rawCullDistance = adornee:GetAttribute(ClientCullingConstants.CULL_DISTANCE_ATTRIBUTE)
	const cullDistance = rawCullDistance or ClientCullingConstants.DEFAULT_CULL_DISTANCE
	if not isFiniteNonnegativeNumber(cullDistance) then
		return nil, "CullDistance must be a finite nonnegative number"
	end

	const defaultHysteresis = math.min(ClientCullingConstants.DEFAULT_UNCULL_HYSTERESIS, cullDistance * 0.1)
	const rawUncullDistance = adornee:GetAttribute(ClientCullingConstants.CULL_UNCULL_DISTANCE_ATTRIBUTE)
	const uncullDistance = rawUncullDistance or math.max(0, cullDistance - defaultHysteresis)
	if not isFiniteNonnegativeNumber(uncullDistance) or uncullDistance > cullDistance then
		return nil, "CullUncullDistance must be between zero and CullDistance"
	end

	const rawDynamic = adornee:GetAttribute(ClientCullingConstants.CULL_DYNAMIC_ATTRIBUTE)
	if rawDynamic ~= nil and not t.boolean(rawDynamic) then
		return nil, "CullDynamic must be a boolean"
	end

	return {
		CullDistance = cullDistance,
		UncullDistance = uncullDistance,
		Dynamic = rawDynamic == true,
	}, nil
end

--[=[
	Derives a cached oriented bounding box for a supported culling root.

	@within ClientCullingUtils
	@param adornee Instance
	@return CullBounds?
]=]
function ClientCullingUtils.deriveBounds(adornee: Instance): CullBounds?
	assert(t.Instance(adornee), "Bad adornee")

	local cframe: CFrame?
	local size: Vector3?
	if adornee:IsA("Model") or adornee:IsA("BasePart") then
		cframe, size = deriveForPVInstance(adornee)
	elseif adornee:IsA("SurfaceGui") or adornee:IsA("BillboardGui") then
		cframe, size = deriveForAdornee(adornee)
	elseif adornee:IsA("Beam") or adornee:IsA("Trail") then
		cframe, size = deriveForBeamLike(adornee)
	elseif adornee:IsA("Attachment") then
		cframe, size = adornee.WorldCFrame, Vector3.one
	elseif
		adornee:IsA("PointLight")
		or adornee:IsA("SpotLight")
		or adornee:IsA("SurfaceLight")
		or adornee:IsA("Decal")
		or adornee:IsA("Texture")
		or adornee:IsA("ParticleEmitter")
	then
		cframe, size = deriveForParent(adornee)
	end

	if not cframe or not size then
		return nil
	end

	return {
		CFrame = cframe,
		Size = size,
		Radius = size.Magnitude * 0.5,
	}
end

--[=[
	Returns whether cached bounds should be culled at the supplied distance.

	@within ClientCullingUtils
	@param bounds CullBounds
	@param cameraPosition Vector3
	@param distance number
	@return boolean
]=]
function ClientCullingUtils.shouldCull(bounds: CullBounds, cameraPosition: Vector3, distance: number): boolean
	assert(t.table(bounds), "Bad bounds")
	assert(t.Vector3(cameraPosition), "Bad cameraPosition")
	assert(isFiniteNonnegativeNumber(distance), "Bad distance")

	const localPoint = bounds.CFrame:PointToObjectSpace(cameraPosition)
	const halfSize = bounds.Size * 0.5
	const clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -halfSize.X, halfSize.X),
		math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
	)
	const closestPoint = bounds.CFrame:PointToWorldSpace(clampedLocal)
	const delta = closestPoint - cameraPosition
	return delta:Dot(delta) > distance * distance
end

--[=[
	Returns the power-of-two spatial bucket that contains the supplied range.

	@within ClientCullingUtils
	@param range number
	@return number
]=]
function ClientCullingUtils.getSpatialBucketSize(range: number): number
	assert(isFiniteNonnegativeNumber(range), "Bad range")

	local bucketSize = ClientCullingConstants.MINIMUM_SPATIAL_CELL_SIZE
	while bucketSize < range do
		const nextBucketSize = bucketSize * 2
		if nextBucketSize == math.huge then
			return range
		end
		bucketSize = nextBucketSize
	end
	return bucketSize
end

return ClientCullingUtils
