--!strict
--[=[
	Utility helpers for Roblox friend lists and friend presence.

	@class FriendUtils
]=]

local Players = game:GetService("Players")
const require = require("../Loader").load()

local Promise = require("Promise")

local FriendUtils = {}

export type FriendData = {
	Id: number,
	Username: string,
	DisplayName: string,
	IsOnline: boolean,
}

export type OnlineFriendData = {
	VisitorId: number?,
	UserId: number?,
	UserName: string?,
	Username: string?,
	DisplayName: string?,
	LastOnline: string?,
	IsOnline: boolean?,
	LastLocation: string?,
	PlaceId: number?,
	GameId: string?,
	LocationType: number?,
}

--[=[
	Wraps Players:GetFriendsAsync.

	@param userId number
	@return Promise<FriendPages>
]=]
function FriendUtils.promiseFriendPages(userId: number): Promise.Promise<FriendPages>
	assert(type(userId) == "number", "Bad userId")

	return Promise.new(function(resolve, reject)
		local pages
		local ok, err = pcall(function()
			pages = Players:GetFriendsAsync(userId)
		end)

		if not ok then
			reject(err)
			return
		end

		if not pages then
			reject("Failed to get friend pages")
			return
		end

		resolve(pages)
	end)
end

--[=[
	Iterates over FriendPages and yields each friend entry.

	@param pages FriendPages
	@return () -> FriendData?
]=]
function FriendUtils.iterateFriendsYielding(pages: FriendPages): () -> FriendData?
	assert(pages, "Bad pages")

	return coroutine.wrap(function()
		while true do
			for _, userData in pages:GetCurrentPage() do
				assert(type(userData.Id) == "number", "Bad userData.Id")
				assert(type(userData.Username) == "string", "Bad userData.Username")
				assert(type(userData.IsOnline) == "boolean", "Bad userData.IsOnline")

				coroutine.yield(userData)
			end

			if pages.IsFinished then
				break
			end

			pages:AdvanceToNextPageAsync()
		end
	end)
end

--[=[
	Returns all friends for a user id.

	@param userId number
	@param limitMaxFriends number?
	@return Promise<{ FriendData }>
]=]
function FriendUtils.promiseAllFriends(userId: number, limitMaxFriends: number?): Promise.Promise<{ FriendData }>
	assert(type(userId) == "number", "Bad userId")
	assert(limitMaxFriends == nil or type(limitMaxFriends) == "number", "Bad limitMaxFriends")

	return FriendUtils.promiseFriendPages(userId):Then(function(pages: FriendPages)
		return Promise.spawn(function(resolve)
			local friends = {}

			for friendData in FriendUtils.iterateFriendsYielding(pages) do
				table.insert(friends, friendData)

				if limitMaxFriends and #friends >= limitMaxFriends then
					resolve(friends)
					return
				end
			end

			resolve(friends)
		end)
	end)
end

--[=[
	Wraps Player:GetFriendsOnline.

	@param player Player
	@param maxFriends number?
	@return Promise<{ OnlineFriendData }>
]=]
function FriendUtils.promiseOnlineFriends(player: Player, maxFriends: number?): Promise.Promise<{ OnlineFriendData }>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(maxFriends == nil or type(maxFriends) == "number", "Bad maxFriends")

	return Promise.new(function(resolve, reject)
		local friends
		local ok, err = pcall(function()
			if maxFriends then
				friends = player:GetFriendsOnline(maxFriends)
			else
				friends = player:GetFriendsOnline()
			end
		end)

		if not ok then
			reject(err)
			return
		end

		resolve(friends or {})
	end)
end

--[=[
	Returns friends whose presence reports an online state.

	@param friends { OnlineFriendData }
	@return { OnlineFriendData }
]=]
function FriendUtils.onlineFriends(friends: { OnlineFriendData }): { OnlineFriendData }
	assert(type(friends) == "table", "Bad friends")

	local results = {}
	for _, friend in friends do
		if friend.IsOnline == true then
			table.insert(results, friend)
		end
	end
	return results
end

--[=[
	Returns friends whose presence has any PlaceId.

	@param friends { OnlineFriendData }
	@param placeId number?
	@return { OnlineFriendData }
]=]
function FriendUtils.friendsWhoPlayed(friends: { OnlineFriendData }, placeId: number?): { OnlineFriendData }
	assert(type(friends) == "table", "Bad friends")
	assert(placeId == nil or type(placeId) == "number", "Bad placeId")

	local results = {}
	for _, friend in friends do
		if friend.PlaceId and (placeId == nil or friend.PlaceId == placeId) then
			table.insert(results, friend)
		end
	end
	return results
end

--[=[
	Returns online friends whose presence is in the given place id.

	@param friends { OnlineFriendData }
	@param placeId number
	@return { OnlineFriendData }
]=]
function FriendUtils.friendsInPlace(friends: { OnlineFriendData }, placeId: number): { OnlineFriendData }
	assert(type(friends) == "table", "Bad friends")
	assert(type(placeId) == "number", "Bad placeId")

	local results = {}
	for _, friend in friends do
		if friend.IsOnline == true and friend.PlaceId == placeId then
			table.insert(results, friend)
		end
	end
	return results
end

--[=[
	Returns online friends in the current place.

	@param friends { OnlineFriendData }
	@return { OnlineFriendData }
]=]
function FriendUtils.friendsInCurrentPlace(friends: { OnlineFriendData }): { OnlineFriendData }
	return FriendUtils.friendsInPlace(friends, game.PlaceId)
end

--[=[
	Returns online friends in the current server job.

	@param friends { OnlineFriendData }
	@return { OnlineFriendData }
]=]
function FriendUtils.friendsInCurrentServer(friends: { OnlineFriendData }): { OnlineFriendData }
	assert(type(friends) == "table", "Bad friends")

	local results = {}
	for _, friend in friends do
		if friend.IsOnline == true and friend.GameId == game.JobId then
			table.insert(results, friend)
		end
	end
	return results
end

--[=[
	Promises friends whose presence has any PlaceId, or a specific PlaceId.

	@param player Player
	@param placeId number?
	@param maxFriends number?
	@return Promise<{ OnlineFriendData }>
]=]
function FriendUtils.promiseFriendsWhoPlayed(
	player: Player,
	placeId: number?,
	maxFriends: number?
): Promise.Promise<{ OnlineFriendData }>
	return FriendUtils.promiseOnlineFriends(player, maxFriends):Then(function(friends)
		return FriendUtils.friendsWhoPlayed(friends, placeId)
	end)
end

--[=[
	Promises online friends in a specific place.

	@param player Player
	@param placeId number
	@param maxFriends number?
	@return Promise<{ OnlineFriendData }>
]=]
function FriendUtils.promiseFriendsInPlace(
	player: Player,
	placeId: number,
	maxFriends: number?
): Promise.Promise<{ OnlineFriendData }>
	return FriendUtils.promiseOnlineFriends(player, maxFriends):Then(function(friends)
		return FriendUtils.friendsInPlace(friends, placeId)
	end)
end

--[=[
	Promises online friends in the current place.

	@param player Player
	@param maxFriends number?
	@return Promise<{ OnlineFriendData }>
]=]
function FriendUtils.promiseFriendsInCurrentPlace(
	player: Player,
	maxFriends: number?
): Promise.Promise<{ OnlineFriendData }>
	return FriendUtils.promiseFriendsInPlace(player, game.PlaceId, maxFriends)
end

--[=[
	Promises online friends in the current server job.

	@param player Player
	@param maxFriends number?
	@return Promise<{ OnlineFriendData }>
]=]
function FriendUtils.promiseFriendsInCurrentServer(
	player: Player,
	maxFriends: number?
): Promise.Promise<{ OnlineFriendData }>
	return FriendUtils.promiseOnlineFriends(player, maxFriends):Then(function(friends)
		return FriendUtils.friendsInCurrentServer(friends)
	end)
end

--[=[
	Returns true when the two players are friends.

	@param player Player
	@param otherUserId number
	@return Promise<boolean>
]=]
function FriendUtils.promiseIsFriendsWith(player: Player, otherUserId: number): Promise.Promise<boolean>
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	assert(type(otherUserId) == "number", "Bad otherUserId")

	return Promise.new(function(resolve, reject)
		local isFriendsWith = false
		local ok, err = pcall(function()
			isFriendsWith = player:IsFriendsWithAsync(otherUserId)
		end)

		if not ok then
			reject(err)
			return
		end

		resolve(isFriendsWith)
	end)
end

return FriendUtils
