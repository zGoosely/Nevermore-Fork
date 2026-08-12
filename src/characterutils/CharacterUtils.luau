--!strict
--[=[
	General character utility code.
	@class CharacterUtils
]=]

local Players = game:GetService('Players')

local CharacterUtils = {}

export type BaseCharacter = Model & {
	Humanoid: Humanoid,
	HumanoidRootPart: Part,
}

export type R6Character = BaseCharacter & {
	Head: Part,
	Torso: Part,
	LeftArm: Part,
	RightArm: Part,
	LeftLeg: Part,
	RightLeg: Part,
}

export type R15Character<T> = BaseCharacter & {
	Head: Part,

	UpperTorso: Part,
	LowerTorso: Part,

	LeftUpperArm: Part,
	LeftLowerArm: Part,
	LeftHand: Part,

	RightUpperArm: Part,
	RightLowerArm: Part,
	RightHand: Part,

	LeftUpperLeg: Part,
	LeftLowerLeg: Part,
	LeftFoot: Part,

	RightUpperLeg: Part,
	RightLowerLeg: Part,
	RightFoot: Part,
} & T

-- --[=[
--     Assigns a unique replication ID to the character for tracking across the server.
--     If the character already has an ID, it returns early.

--     When the character is removed from the hierarchy, its ID is returned to the pool.

--     @param character Model
--     @return number -- The assigned replication ID
-- ]=]
-- function CharacterUtils.setReplicationId(character: Model)
-- 	if character:GetAttribute(Attributes.CharacterId) then
-- 		return
-- 	end

-- 	local id = table.remove(AVAILABLE_IDS, 1)
-- 	character:SetAttribute(Attributes.CharacterId, id)

-- 	character.AncestryChanged:Connect(function(_, parent)
-- 		if not parent then
-- 			local oldId = character:GetAttribute(Attributes.CharacterId)
-- 			if oldId then
-- 				table.insert(AVAILABLE_IDS, oldId)
-- 			end
-- 		end
-- 	end)

-- 	return id
-- end

-- --[=[
--     Finds a character in the workspace by its replication ID.

--     @param id number
--     @return Model? -- The character with the matching replication ID, or nil if not found
-- ]=]
-- function CharacterUtils.getByReplicationId(id: number)
-- 	for _, character in ipairs(workspace.Characters:GetChildren()) do
-- 		local uid = character:GetAttribute(Attributes.CharacterId)
-- 		if uid == id then
-- 			return character
-- 		end
-- 	end
-- 	return nil
-- end

--[=[
	Gets a player's humanoid, if it exists
	@param player Player
	@return Humanoid? -- Nil if not found
]=]
function CharacterUtils.getPlayerHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass('Humanoid')
end

--[=[
	Gets a player's humanoid, and ensures it is alive, otherwise returns nil
	@param player Player
	@return Humanoid? -- Nil if not found
]=]
function CharacterUtils.getAlivePlayerHumanoid(player: Player): Humanoid?
	local humanoid = CharacterUtils.getPlayerHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

--[=[
	Gets a player's humanoid's rootPart, and ensures the humanoid is alive, otherwise
	returns nil
	@param player Player
	@return BasePart? -- Nil if not found
]=]
function CharacterUtils.getAlivePlayerRootPart(player: Player): BasePart?
	local humanoid = CharacterUtils.getPlayerHumanoid(player)
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid.RootPart
end

--[=[
	Gets a player's humanoid's rootPart otherwise returns nil
	@param player Player
	@return BasePart? -- Nil if not found
]=]
function CharacterUtils.getPlayerRootPart(player: Player): BasePart?
	local humanoid = CharacterUtils.getPlayerHumanoid(player)
	if not humanoid then
		return nil
	end

	return humanoid.RootPart
end

--[=[
	Unequips all tools for a give player's humanomid, if the humanoid
	exists

	```lua
	local Players = game:GetService("Players")

	for _, player in Players:GetPlayers() do
		CharacterUtils.unequipTools(player)
	end
	```

	@param player Player
]=]
function CharacterUtils.unequipTools(player: Player)
	local humanoid = CharacterUtils.getPlayerHumanoid(player)
	if humanoid then
		humanoid:UnequipTools()
	end
end

--[=[
	Returns the player that a descendent is part of, if it is part of one.

	```lua
	script.Parent.Touched:Connect(function(inst)
		local player = CharacterUtils.getPlayerFromCharacter(inst)
		if player then
			-- activate button!
		end
	end)
	```

	:::tip
	This method is useful in a ton of different situations. For example, you can
	use it on classes bound to a humanoid, to determine the player. You can also
	use it to determine, upon touched events, if a part is part of a character.
	:::

	@param descendant Instance -- A child of the potential character.
	@return Player? -- Nil if not found
]=]
function CharacterUtils.getPlayerFromCharacter(descendant: Instance): Player?
	local character = descendant
	-- TODO: Only use models
	local player = Players:GetPlayerFromCharacter(character :: any)

	while not player do
		if character.Parent then
			character = character.Parent
			player = Players:GetPlayerFromCharacter(character)
		else
			return nil
		end
	end

	return player
end

--[=[
	Calculates the offset from the humanoid's root part center to the bottom.
	This is useful for positioning attachments at the bottom of a character.

	@param humanoid Humanoid
	@return number -- The Y offset (half of the RootPart's Y size)
]=]
function CharacterUtils.getHumanoidRootPartOffset(humanoid: Humanoid): number
	local rootPart = humanoid.RootPart
	assert(rootPart, 'Humanoid has no RootPart set')

	return (rootPart.Size.Y * 0.5) + humanoid.HipHeight
end

--[=[
	Checks if the humanoids rootpart is not nil.

	@param humanoid Humanoid
]=]
function CharacterUtils.isRootPartSet(humanoid: Humanoid): boolean
	return humanoid.RootPart ~= nil
end

--[=[
	Checks if a characters primary part is not nil.

	@param character Model
]=]
function CharacterUtils.isPrimaryPartSet(character: Model): boolean
	return character.PrimaryPart ~= nil
end

--[=[
	Checks if a humanoid has health greater than 0.

	@param humanoid Humanoid
]=]
function CharacterUtils.isHumanoidAlive(humanoid: Humanoid): boolean
	return humanoid and humanoid.Health > 0
end

--[=[
    @function ForceStandHumanoid
    @param Humanoid Humanoid
    @return void
    @within CharacterUtils

  	Stands a humanoid up if sitting forcably
]=]
function CharacterUtils.forceStandHumanoid(humanoid: Humanoid)
	assert(
		typeof(humanoid) == 'Instance' and humanoid:IsA('Humanoid'),
		'Exception on ForceStandHumanoid: Humanoid must be instance Humanoid'
	)

	if humanoid.SeatPart then
		local weld = humanoid.SeatPart:FindFirstChild('SeatWeld')

		if weld then
			weld:Destroy()
		end

		humanoid.SeatPart:Sit(nil)
	end

	humanoid.Sit = false
end

return CharacterUtils
