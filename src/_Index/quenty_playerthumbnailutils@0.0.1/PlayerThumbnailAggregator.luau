--!strict
--[=[
	Deduplicates and caches player thumbnail requests for one thumbnail type and
	size. Roblox does not expose a bulk thumbnail endpoint, so each queued user
	ID is requested independently through [PlayerThumbnailUtils].

	@class PlayerThumbnailAggregator
]=]
const Aggregator = require("@game/ReplicatedStorage/Packages/Aggregator")
const BaseObject = require("@game/ReplicatedStorage/Packages/BaseObject")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const PlayerThumbnailUtils = require("./PlayerThumbnailUtils")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const Rx = require("@game/ReplicatedStorage/Packages/Rx")
const t = require("@game/ReplicatedStorage/Packages/t")

export type ThumbnailResult = {
	Id: number,
	Image: string,
}

const PlayerThumbnailAggregator = setmetatable({}, BaseObject)
PlayerThumbnailAggregator.ClassName = "PlayerThumbnailAggregator"
PlayerThumbnailAggregator.__index = PlayerThumbnailAggregator

export type PlayerThumbnailAggregator =
	typeof(setmetatable(
		{} :: {
			_aggregator: Aggregator.Aggregator<ThumbnailResult>,
			_thumbnailType: Enum.ThumbnailType,
			_thumbnailSize: Enum.ThumbnailSize,
		},
		{} :: typeof({ __index = PlayerThumbnailAggregator })
	))
	& BaseObject.BaseObject<any>

function PlayerThumbnailAggregator.new(
	thumbnailType: Enum.ThumbnailType?,
	thumbnailSize: Enum.ThumbnailSize?
): PlayerThumbnailAggregator
	assert(t.optional(t.enum(Enum.ThumbnailType))(thumbnailType), "Bad thumbnailType")
	assert(t.optional(t.enum(Enum.ThumbnailSize))(thumbnailSize), "Bad thumbnailSize")

	const self = setmetatable(BaseObject.new() :: any, PlayerThumbnailAggregator) :: PlayerThumbnailAggregator

	self._thumbnailType = thumbnailType or Enum.ThumbnailType.HeadShot
	self._thumbnailSize = thumbnailSize or Enum.ThumbnailSize.Size100x100
	self._aggregator = self._maid:Add(Aggregator.new("PlayerThumbnailUtils.promiseUserThumbnail", function(userIdList)
		assert(#userIdList == 1, "Expected one thumbnail request")

		const userId = userIdList[1]
		return PlayerThumbnailUtils.promiseUserThumbnail(userId, self._thumbnailType, self._thumbnailSize)
			:Then(function(image: string): { ThumbnailResult }
				return {
					{
						Id = userId,
						Image = image,
					},
				}
			end)
	end))

	-- The Roblox endpoint accepts one user ID per call. A batch size of one keeps
	-- failures isolated while Aggregator still deduplicates and caches requests.
	self._aggregator:SetMaxBatchSize(1)

	return self
end

--[=[
	Promises the configured thumbnail for a user. Repeated requests for the same
	user ID share the cached underlying request.

	@within PlayerThumbnailAggregator
	@param userId number
	@return Promise<string>
]=]
function PlayerThumbnailAggregator.PromiseUserThumbnail(
	self: PlayerThumbnailAggregator,
	userId: number
): Promise.Promise<string>
	assert(t.number(userId), "Bad userId")

	return self._aggregator:Promise(userId):Then(function(result: ThumbnailResult): string
		return result.Image
	end)
end

--[=[
	Observes the configured thumbnail for a user. The observable emits once when
	the shared thumbnail request resolves.

	@within PlayerThumbnailAggregator
	@param userId number
	@return Observable<string>
]=]
function PlayerThumbnailAggregator.ObserveUserThumbnail(
	self: PlayerThumbnailAggregator,
	userId: number
): Observable.Observable<string>
	assert(t.number(userId), "Bad userId")

	return self._aggregator:Observe(userId):Pipe({
		Rx.map(function(result: ThumbnailResult): string
			return result.Image
		end),
	})
end

return PlayerThumbnailAggregator
