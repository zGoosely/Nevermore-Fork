--!strict
--[=[
	Handles actions involving HumanoidDescription objects, including loading character appearance.

	@util HumanoidDescriptionUtils
]=]

const Players = game:GetService("Players")

const InsertServiceUtils = require("@game/ReplicatedStorage/Packages/InsertServiceUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const t = require("@game/ReplicatedStorage/Packages/t")

const isAssetTypeVerification = t.enum(Enum.AssetTypeVerification)
const isHumanoid = t.instanceIsA("Humanoid")
const isHumanoidDescription = t.instanceIsA("HumanoidDescription")

const HumanoidDescriptionUtils = {}

const promiseUserIdFromName = function(name: string): Promise.Promise<number>
	assert(t.string(name) and name ~= "", "Bad name")

	return Promise.spawn(function(resolve, reject)
		local userId
		const ok, err = pcall(function()
			userId = Players:GetUserIdFromNameAsync(name)
		end)

		if not ok then
			return reject(err)
		end

		if not t.numberPositive(userId) then
			return reject("UserId returned was not a positive number")
		end

		return resolve(userId)
	end)
end

--[=[
	Applies a humanoid description asynchronously.

	@within HumanoidDescriptionUtils
	@param humanoid Humanoid
	@param description HumanoidDescription
	@return Promise.Promise<()>
]=]
function HumanoidDescriptionUtils.promiseApplyDescription(
	humanoid: Humanoid,
	description: HumanoidDescription
): Promise.Promise<()>
	assert(isHumanoid(humanoid), "Bad humanoid")
	assert(isHumanoidDescription(description), "Bad description")

	return Promise.spawn(function(resolve, reject)
		const ok, err = pcall(function()
			humanoid:ApplyDescriptionAsync(description)
		end)
		if not ok then
			reject(err)
			return
		end
		resolve()
	end)
end

--[=[
	Applies a humanoid description through the reset API asynchronously.

	@within HumanoidDescriptionUtils
	@param humanoid Humanoid
	@param description HumanoidDescription
	@param assetTypeVerification AssetTypeVerification
	@return Promise.Promise<()>
]=]
function HumanoidDescriptionUtils.promiseApplyDescriptionReset(
	humanoid: Humanoid,
	description: HumanoidDescription,
	assetTypeVerification: Enum.AssetTypeVerification
): Promise.Promise<()>
	assert(isHumanoid(humanoid), "Bad humanoid")
	assert(isHumanoidDescription(description), "Bad description")
	assert(isAssetTypeVerification(assetTypeVerification), "Bad assetTypeVerification")

	return Promise.spawn(function(resolve, reject)
		const ok, err = pcall(function()
			humanoid:ApplyDescriptionResetAsync(description, assetTypeVerification)
		end)
		if not ok then
			reject(err)
			return
		end
		resolve()
	end)
end

--[=[
	Applies the humanoid description belonging to a username asynchronously.

	@within HumanoidDescriptionUtils
	@param humanoid Humanoid
	@param userName string
	@return Promise.Promise<()>
]=]
function HumanoidDescriptionUtils.promiseApplyFromUserName(humanoid: Humanoid, userName: string): Promise.Promise<()>
	assert(isHumanoid(humanoid), "Bad humanoid")
	assert(t.string(userName) and userName ~= "", "Bad userName")

	return HumanoidDescriptionUtils.promiseFromUserName(userName):Then(function(description)
		return HumanoidDescriptionUtils.promiseApplyDescription(humanoid, description)
	end)
end

--[=[
	Retrieves a humanoid description from a username asynchronously.

	@within HumanoidDescriptionUtils
	@param userName string
	@return Promise.Promise<HumanoidDescription>
]=]
function HumanoidDescriptionUtils.promiseFromUserName(userName: string): Promise.Promise<HumanoidDescription>
	assert(t.string(userName) and userName ~= "", "Bad userName")

	return promiseUserIdFromName(userName):Then(function(userId)
		return HumanoidDescriptionUtils.promiseFromUserId(userId)
	end)
end

--[=[
	Retrieves a humanoid description from a user ID asynchronously.

	@within HumanoidDescriptionUtils
	@param userId number
	@return Promise.Promise<HumanoidDescription>
]=]
function HumanoidDescriptionUtils.promiseFromUserId(userId: number): Promise.Promise<HumanoidDescription>
	assert(t.numberPositive(userId), "Bad userId")

	return Promise.spawn(function(resolve, reject)
		local description = nil
		const ok, err = pcall(function()
			description = Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if not ok then
			reject(err)
			return
		end
		if not description then
			reject("API failed to return a description")
			return
		end
		assert(isHumanoidDescription(description), "Bad description")
		resolve(description)
	end)
end

--[=[
	Parses a comma-separated HumanoidDescription asset property into asset IDs.

	@within HumanoidDescriptionUtils
	@param assetString string
	@return { number }
]=]
function HumanoidDescriptionUtils.getAssetIdsFromString(assetString: string): { number }
	assert(t.string(assetString), "Bad assetString")

	if assetString == "" then
		return {}
	end

	const assetIds = {}
	for _, assetIdStr in string.split(assetString, ",") do
		const num = tonumber(assetIdStr)
		if num then
			table.insert(assetIds, num)
		elseif assetIdStr ~= "" then
			warn(
				string.format(
					"[HumanoidDescriptionUtils/getAssetIdsFromString] - Failed to convert %q to assetId",
					assetIdStr
				)
			)
		end
	end

	return assetIds
end

--[=[
	Creates asset-loading promises for a comma-separated HumanoidDescription asset property.

	@within HumanoidDescriptionUtils
	@param assetString string
	@return { Promise.Promise<Instance> }
]=]
function HumanoidDescriptionUtils.getAssetPromisesFromString(assetString: string): { Promise.Promise<Instance> }
	assert(t.string(assetString), "Bad assetString")

	const promises = {}
	for _, assetId in HumanoidDescriptionUtils.getAssetIdsFromString(assetString) do
		table.insert(promises, InsertServiceUtils.promiseAsset(assetId))
	end
	return promises
end

return HumanoidDescriptionUtils
