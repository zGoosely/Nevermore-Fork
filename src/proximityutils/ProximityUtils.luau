--!strict
--[=[
	Utilities for proximity-based queries and spatial operations

	@class ProximityUtils
]=]

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
const require = require("../Loader").load()

local Brio = require('Brio')
local Maid = require('Maid')
local Observable = require('Observable')
local Rx = require('Rx')

local ProximityUtils = {}

function ProximityUtils.getPlayersNearPosition(position: Vector3, radius: number): { Player }
	local nearbyPlayers = {}

	for _, player in Players:GetPlayers() do
		local distance = player:DistanceFromCharacter(position)
		if distance > 0 and distance <= radius then
			table.insert(nearbyPlayers, player)
		end
	end

	return nearbyPlayers
end

function ProximityUtils.getClosestPlayer(position: Vector3, maxDistance: number?): (Player?, number?)
	local closestPlayer = nil
	local closestDistance = maxDistance or math.huge

	for _, player in Players:GetPlayers() do
		local distance = player:DistanceFromCharacter(position)
		if distance > 0 and distance < closestDistance then
			closestPlayer = player
			closestDistance = distance
		end
	end

	return closestPlayer, closestDistance
end

function ProximityUtils.getPartsNearPosition(position: Vector3, radius: number, whitelist: { Instance }?): { BasePart }
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	if whitelist then
		overlapParams.FilterDescendantsInstances = whitelist
	end

	local parts = workspace:GetPartBoundsInRadius(position, radius, overlapParams)
	return parts
end

function ProximityUtils.isWithinDistance(pos1: Vector3, pos2: Vector3, distance: number): boolean
	return (pos1 - pos2).Magnitude <= distance
end

function ProximityUtils.sortByDistance(position: Vector3, objects: { any }): { any }
	local sorted = table.clone(objects)

	table.sort(sorted, function(a, b)
		local posA = if typeof(a) == 'Instance' and a:IsA('BasePart') then a.Position else Vector3.zero
		local posB = if typeof(b) == 'Instance' and b:IsA('BasePart') then b.Position else Vector3.zero

		return (posA - position).Magnitude < (posB - position).Magnitude
	end)

	return sorted
end

function ProximityUtils.getDistance(obj1: any, obj2: any): number
	local pos1 = ProximityUtils.getPosition(obj1)
	local pos2 = ProximityUtils.getPosition(obj2)

	return (pos1 - pos2).Magnitude
end

function ProximityUtils.getPosition(obj: any): Vector3
	if typeof(obj) == 'Vector3' then
		return obj
	elseif typeof(obj) == 'Instance' then
		if obj:IsA('BasePart') then
			return obj.Position
		elseif obj:IsA('Model') then
			return obj:GetPivot().Position
		end
	end

	return Vector3.zero
end

function ProximityUtils.getPlayersInPart(part: BasePart): { Player }
	local touchingParts = part:GetTouchingParts()
	local playersInPart = {}
	local addedPlayers = {}

	for _, touchingPart in touchingParts do
		local character = touchingPart:FindFirstAncestorOfClass('Model')
		if character then
			local player = Players:GetPlayerFromCharacter(character)
			if player and not addedPlayers[player] then
				table.insert(playersInPart, player)
				addedPlayers[player] = true
			end
		end
	end

	return playersInPart
end

function ProximityUtils.getClosestPart(position: Vector3, parts: { BasePart }): (BasePart?, number?)
	local closestPart = nil
	local closestDistance = math.huge

	for _, part in parts do
		local distance = (part.Position - position).Magnitude
		if distance < closestDistance then
			closestPart = part
			closestDistance = distance
		end
	end

	return closestPart, closestDistance
end

function ProximityUtils.isPlayerInRange(player1: Player, player2: Player, range: number): boolean
	local char2 = player2.Character
	if not char2 then
		return false
	end

	local hrp2 = char2:FindFirstChild('HumanoidRootPart')
	if not hrp2 then
		return false
	end

	local distance = player1:DistanceFromCharacter(hrp2.Position)
	return distance > 0 and distance <= range
end

function ProximityUtils.getPlayersNearPositionExcluding(
	position: Vector3,
	radius: number,
	excludePlayer: Player?
): { Player }
	local nearbyPlayers = ProximityUtils.getPlayersNearPosition(position, radius)

	if excludePlayer then
		for i = #nearbyPlayers, 1, -1 do
			if nearbyPlayers[i] == excludePlayer then
				table.remove(nearbyPlayers, i)
			end
		end
	end

	return nearbyPlayers
end

--[=[
	Observes players near a position with Rx.
	Emits a new array of players whenever the set of nearby players changes.

	@param position Vector3 | () -> Vector3 -- Position or function that returns position
	@param radius number -- Detection radius
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@return Observable<{Player}>
]=]
function ProximityUtils.observePlayersNearPosition(
	position: Vector3 | () -> Vector3,
	radius: number,
	updateInterval: number?
)
	return Observable.new(function(sub)
		local maid = Maid.new()
		local interval = updateInterval or 0.5
		local lastPlayers = {}

		local function getPosition(): Vector3
			if type(position) == 'function' then
				return position()
			end
			return position
		end

		local function checkProximity()
			local currentPos = getPosition()
			local currentPlayers = ProximityUtils.getPlayersNearPosition(currentPos, radius)

			-- Check if the set of players changed
			local changed = #currentPlayers ~= #lastPlayers
			if not changed then
				for _, player in currentPlayers do
					local found = false
					for _, lastPlayer in lastPlayers do
						if player == lastPlayer then
							found = true
							break
						end
					end
					if not found then
						changed = true
						break
					end
				end
			end

			if changed then
				lastPlayers = currentPlayers
				sub:Fire(currentPlayers)
			end
		end

		-- Initial check
		checkProximity()

		-- Set up periodic checks
		local lastCheck = os.clock()
		maid:GiveTask(RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - lastCheck >= interval then
				lastCheck = now
				checkProximity()
			end
		end))

		return maid
	end)
end

--[=[
	Observes players near a position with Rx and Brio.
	Each player gets a Brio that dies when they leave the radius.

	@param position Vector3 | () -> Vector3 -- Position or function that returns position
	@param radius number -- Detection radius
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@return Observable<Brio<Player>>
]=]
function ProximityUtils.observePlayersNearPositionBrio(
	position: Vector3 | () -> Vector3,
	radius: number,
	updateInterval: number?
)
	return ProximityUtils.observePlayersNearPosition(position, radius, updateInterval):Pipe({
		Rx.switchMap(function(players)
			return Rx.of(unpack(players))
		end),
		Rx.map(function(player)
			return Brio.new(player)
		end),
	})
end

--[=[
	Observes the closest player to a position with Rx.
	Emits the closest player and their distance whenever it changes.

	@param position Vector3 | () -> Vector3 -- Position or function that returns position
	@param maxDistance number? -- Maximum distance to consider
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@return Observable<{player: Player?, distance: number?}>
]=]
function ProximityUtils.observeClosestPlayer(
	position: Vector3 | () -> Vector3,
	maxDistance: number?,
	updateInterval: number?
)
	return Rx.observable(function(observer)
		local maid = Maid.new()
		local interval = updateInterval or 0.5
		local lastPlayer = nil
		local lastDistance = nil

		local function getPosition(): Vector3
			if type(position) == 'function' then
				return position()
			end
			return position
		end

		local function checkProximity()
			local currentPos = getPosition()
			local player, distance = ProximityUtils.getClosestPlayer(currentPos, maxDistance)

			if player ~= lastPlayer or distance ~= lastDistance then
				lastPlayer = player
				lastDistance = distance
				observer.next({
					player = player,
					distance = distance,
				})
			end
		end

		-- Initial check
		checkProximity()

		-- Set up periodic checks
		local lastCheck = os.clock()
		local connection = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - lastCheck >= interval then
				lastCheck = now
				checkProximity()
			end
		end)

		maid:GiveTask(connection)

		return function()
			maid:Destroy()
		end
	end)
end

--[=[
	Observes whether a player is within range of a position with Rx.
	Emits true when player enters range, false when they leave.

	@param player Player -- Player to track
	@param position Vector3 | () -> Vector3 -- Position or function that returns position
	@param radius number -- Detection radius
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@return Observable<boolean>
]=]
function ProximityUtils.observePlayerInRange(
	player: Player,
	position: Vector3 | () -> Vector3,
	radius: number,
	updateInterval: number?
)
	return Rx.observable(function(observer)
		local maid = Maid.new()
		local interval = updateInterval or 0.5
		local lastInRange = false

		local function getPosition(): Vector3
			if type(position) == 'function' then
				return position()
			end
			return position
		end

		local function checkProximity()
			local currentPos = getPosition()
			local distance = player:DistanceFromCharacter(currentPos)
			local inRange = distance > 0 and distance <= radius

			if inRange ~= lastInRange then
				lastInRange = inRange
				observer.next(inRange)
			end
		end

		-- Initial check
		checkProximity()

		-- Set up periodic checks
		local lastCheck = os.clock()
		local connection = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - lastCheck >= interval then
				lastCheck = now
				checkProximity()
			end
		end)

		maid:GiveTask(connection)

		-- Clean up when player leaves
		local playerRemoving = Players.PlayerRemoving:Connect(function(removedPlayer)
			if removedPlayer == player then
				observer.complete()
			end
		end)

		maid:GiveTask(playerRemoving)

		return function()
			maid:Destroy()
		end
	end):Pipe({
		Rx.distinctUntilChanged(),
	})
end

--[=[
	Observes players in a part with Rx.
	Emits a new array of players whenever the set of players in the part changes.

	@param part BasePart -- Part to monitor
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@return Observable<{Player}>
]=]
function ProximityUtils.observePlayersInPart(part: BasePart, updateInterval: number?)
	return Rx.observable(function(observer)
		local maid = Maid.new()
		local interval = updateInterval or 0.5
		local lastPlayers = {}

		local function checkPlayers()
			local currentPlayers = ProximityUtils.getPlayersInPart(part)

			-- Check if the set of players changed
			local changed = #currentPlayers ~= #lastPlayers
			if not changed then
				for _, player in currentPlayers do
					local found = false
					for _, lastPlayer in lastPlayers do
						if player == lastPlayer then
							found = true
							break
						end
					end
					if not found then
						changed = true
						break
					end
				end
			end

			if changed then
				lastPlayers = currentPlayers
				observer.next(currentPlayers)
			end
		end

		-- Initial check
		checkPlayers()

		-- Set up periodic checks
		local lastCheck = os.clock()
		local connection = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - lastCheck >= interval then
				lastCheck = now
				checkPlayers()
			end
		end)

		maid:GiveTask(connection)

		return function()
			maid:Destroy()
		end
	end)
end

--[=[
	Observes players in a part with Rx and Brio.
	Each player gets a Brio that dies when they leave the part.

	@param part BasePart -- Part to monitor
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@return Observable<Brio<Player>>
]=]
function ProximityUtils.observePlayersInPartBrio(part: BasePart, updateInterval: number?)
	return ProximityUtils.observePlayersInPart(part, updateInterval):Pipe({
		Rx.switchMap(function(players)
			return Rx.of(unpack(players))
		end),
		Rx.map(function(player)
			return Brio.new(player)
		end),
	})
end

--[=[
	Observes the distance between two objects with Rx.
	Emits the distance whenever it changes significantly.

	@param obj1 any -- First object (Vector3, BasePart, Model, or Player)
	@param obj2 any -- Second object (Vector3, BasePart, Model, or Player)
	@param updateInterval number? -- How often to check (default: 0.5 seconds)
	@param threshold number? -- Minimum change to emit (default: 1 stud)
	@return Observable<number>
]=]
function ProximityUtils.observeDistance(obj1: any, obj2: any, updateInterval: number?, threshold: number?)
	return Rx.observable(function(observer)
		local maid = Maid.new()
		local interval = updateInterval or 0.5
		local changeThreshold = threshold or 1
		local lastDistance = nil

		local function checkDistance()
			local distance = ProximityUtils.getDistance(obj1, obj2)

			if lastDistance == nil or math.abs(distance - lastDistance) >= changeThreshold then
				lastDistance = distance
				observer.next(distance)
			end
		end

		-- Initial check
		checkDistance()

		-- Set up periodic checks
		local lastCheck = os.clock()
		local connection = RunService.Heartbeat:Connect(function()
			local now = os.clock()
			if now - lastCheck >= interval then
				lastCheck = now
				checkDistance()
			end
		end)

		maid:GiveTask(connection)

		return function()
			maid:Destroy()
		end
	end)
end

return ProximityUtils
