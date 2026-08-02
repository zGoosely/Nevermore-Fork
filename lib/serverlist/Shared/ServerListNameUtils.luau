--!strict
--[=[
	Generates deterministic, stable display names for server job IDs.

	@util ServerListNameUtils
]=]

const require = require("../../Loader").load()

const ServerListConstants = require("ServerListConstants")
const t = require("t")

const HASH_MODULUS = 2 ^ 32
const HASH_SEED = 5381

const ServerListNameUtils = {}

local function stableHash(value: string): number
	local hash = HASH_SEED
	for index = 1, #value do
		hash = (hash * 33 + string.byte(value, index)) % HASH_MODULUS
	end
	return hash
end

--[=[
	Returns a deterministic display name for a non-empty job ID or local fallback ID.

	@within ServerListNameUtils
	@param jobId string
	@return string
]=]
function ServerListNameUtils.generateName(jobId: string): string
	assert(t.string(jobId) and jobId ~= "" and #jobId <= ServerListConstants.MAX_JOB_ID_LENGTH, "Bad jobId")

	const hash = stableHash(jobId)
	const descriptors = ServerListConstants.NAME_DESCRIPTORS
	const nouns = ServerListConstants.NAME_NOUNS
	const descriptor = descriptors[hash % #descriptors + 1]
	const noun = nouns[math.floor(hash / #descriptors) % #nouns + 1]
	local name = `{descriptor} {noun}`

	if ServerListConstants.USE_NUMERIC_NAME_SUFFIX then
		name ..= ` {hash % ServerListConstants.NUMERIC_NAME_SUFFIX_MODULUS}`
	end

	assert(#name <= ServerListConstants.MAX_NAME_LENGTH, "Generated server name is too long")
	return name
end

--[=[
	Returns the live job ID, or a deterministic non-empty Studio fallback.

	@within ServerListNameUtils
	@param jobId string
	@param placeId number
	@param placeVersion number
	@return string
]=]
function ServerListNameUtils.resolveJobId(jobId: string, placeId: number, placeVersion: number): string
	assert(t.string(jobId) and #jobId <= ServerListConstants.MAX_JOB_ID_LENGTH, "Bad jobId")
	assert(t.number(placeId) and placeId >= 0 and placeId % 1 == 0, "Bad placeId")
	assert(t.number(placeVersion) and placeVersion >= 0 and placeVersion % 1 == 0, "Bad placeVersion")

	if jobId ~= "" then
		return jobId
	end

	return `studio-{placeId}-{placeVersion}`
end

return ServerListNameUtils
