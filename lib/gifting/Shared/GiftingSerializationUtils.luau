--!strict
--[=[
	Squash serialization for compact gift snapshots. Static field names never enter
	the network payload.

	@util GiftingSerializationUtils
]=]

const HttpService = game:GetService("HttpService")

const require = require("../../Loader").load()

const GiftingAssetTypes = require("GiftingAssetTypes")
const GiftingTypes = require("GiftingTypes")
const Squash = require("Squash")

type GiftRecord = GiftingTypes.GiftRecord

const MAX_U32 = 2 ^ 32 - 1

const GIFT_SCHEMA = Squash.record({
	Key = Squash.string(),
	AssetId = Squash.u32(),
	AssetType = Squash.literal(GiftingAssetTypes.GamePass, GiftingAssetTypes.Product),
	GiftedBy = Squash.vlq(),
	GiftedAt = Squash.u32(),
	Quantity = Squash.vlq(),
	Metadata = Squash.string(),
})

const SNAPSHOT_SCHEMA = Squash.record({
	Sequence = Squash.u32(),
	Gifts = Squash.array(GIFT_SCHEMA),
})

const GiftingSerializationUtils = {}

--[=[
	Serializes a gift map and sequence number.

	@within GiftingSerializationUtils
	@param sequence number
	@param gifts { [string]: GiftRecord }
	@return buffer
]=]
function GiftingSerializationUtils.serialize(sequence: number, gifts: { [string]: GiftRecord }): buffer
	assert(type(sequence) == "number", "Bad sequence")
	assert(type(gifts) == "table", "Bad gifts")

	const transport = table.create(0)
	for key, gift in gifts do
		local metadata = "{}"
		const encoded, value = pcall(HttpService.JSONEncode, HttpService, gift.Metadata)
		if encoded then
			metadata = value
		end
		table.insert(transport, {
			Key = key,
			AssetId = math.clamp(math.floor(gift.AssetId), 0, MAX_U32),
			AssetType = gift.AssetType,
			GiftedBy = math.max(0, math.floor(gift.GiftedBy)),
			GiftedAt = math.clamp(math.floor(gift.GiftedAt), 0, MAX_U32),
			Quantity = math.max(1, math.floor(gift.Quantity)),
			Metadata = metadata,
		})
	end
	table.sort(transport, function(left, right)
		return left.Key < right.Key
	end)

	const cursor = Squash.cursor()
	SNAPSHOT_SCHEMA.ser(cursor, {
		Sequence = math.clamp(math.floor(sequence), 0, MAX_U32),
		Gifts = transport,
	})
	return Squash.tobuffer(cursor)
end

--[=[
	Deserializes a compact gift snapshot.

	@within GiftingSerializationUtils
	@param data buffer
	@return (number, { [string]: GiftRecord })
]=]
function GiftingSerializationUtils.deserialize(data: buffer): (number, { [string]: GiftRecord })
	assert(typeof(data) == "buffer", "Bad data")
	const decoded = SNAPSHOT_SCHEMA.des(Squash.frombuffer(data))
	const gifts: { [string]: GiftRecord } = {}
	for _, transport in decoded.Gifts do
		local metadata = {}
		const succeeded, value = pcall(HttpService.JSONDecode, HttpService, transport.Metadata)
		if succeeded and type(value) == "table" then
			metadata = value
		end
		gifts[transport.Key] = {
			AssetId = transport.AssetId,
			AssetType = transport.AssetType,
			GiftedBy = transport.GiftedBy,
			GiftedAt = transport.GiftedAt,
			Quantity = transport.Quantity,
			Metadata = metadata,
		}
	end
	return decoded.Sequence, gifts
end

return GiftingSerializationUtils
