--!strict
--[=[
	Stateless utility functions for death report construction and inspection.

	@util DeathReportUtils
]=]

const require = require("../../Loader").load()

const CharacterUtils = require("CharacterUtils")
const HumanoidKillerUtils = require("HumanoidKillerUtils")
const t = require("t")

const DEFAULT_COLOR = Color3.new(0.9, 0.9, 0.9)

export type WeaponData = {
	weaponInstance: Instance?,
}

export type DeathReport = {
	["type"]: "deathReport",
	adornee: Instance,
	humanoid: Humanoid?,
	player: Player?,
	killerAdornee: Instance?,
	killerHumanoid: Humanoid?,
	killerPlayer: Player?,
	weaponData: WeaponData,
}

const isWeaponDataValidator = t.strictInterface({
	weaponInstance = t.optional(t.instance),
})

const isDeathReportValidator = t.strictInterface({
	type = t.literal("deathReport"),
	adornee = t.instance,
	humanoid = t.optional(t.instanceIsA("Humanoid")),
	player = t.optional(t.instanceIsA("Player")),
	killerAdornee = t.optional(t.instance),
	killerHumanoid = t.optional(t.instanceIsA("Humanoid")),
	killerPlayer = t.optional(t.instanceIsA("Player")),
	weaponData = isWeaponDataValidator,
})

const DeathReportUtils = {}

--[=[
	Constructs a new DeathReport from a deceased humanoid.

	@within DeathReportUtils
	@param humanoid Humanoid
	@param weaponData WeaponData?
	@return DeathReport
]=]
function DeathReportUtils.fromDeceasedHumanoid(humanoid: Humanoid, weaponData: WeaponData?): DeathReport
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")
	assert(t.optional(isWeaponDataValidator)(weaponData), "Bad weaponData")

	const killerHumanoid = HumanoidKillerUtils.getKillerHumanoidOfHumanoid(humanoid)
	const character = assert(humanoid.Parent, "No character for humanoid")
	return DeathReportUtils.create(character, killerHumanoid, weaponData)
end

--[=[
	Constructs a DeathReport from given adornes and weapon data.

	@within DeathReportUtils
	@param adornee Instance
	@param killerAdornee Instance?
	@param weaponData WeaponData?
	@return DeathReport
]=]
function DeathReportUtils.create(adornee: Instance, killerAdornee: Instance?, weaponData: WeaponData?): DeathReport
	assert(t.instance(adornee), "Bad adornee")
	assert(t.optional(t.instance)(killerAdornee), "Bad killerAdornee")
	assert(t.optional(isWeaponDataValidator)(weaponData), "Bad weaponData")

	local humanoid: Humanoid?
	if adornee:IsA("Humanoid") then
		humanoid = adornee
	else
		humanoid = adornee:FindFirstChildWhichIsA("Humanoid")
	end

	return {
		type = "deathReport",
		adornee = adornee,
		humanoid = humanoid,
		player = CharacterUtils.getPlayerFromCharacter(adornee),
		killerAdornee = killerAdornee,
		killerHumanoid = if killerAdornee and killerAdornee:IsA("Humanoid") then killerAdornee else nil,
		killerPlayer = if killerAdornee then CharacterUtils.getPlayerFromCharacter(killerAdornee) else nil,
		weaponData = weaponData or DeathReportUtils.createWeaponData(nil),
	}
end

--[=[
	Returns true if the given value is a valid DeathReport.

	@within DeathReportUtils
	@param deathReport any
	@return boolean
]=]
function DeathReportUtils.isDeathReport(deathReport: any): boolean
	return isDeathReportValidator(deathReport)
end

--[=[
	Returns true if the given value is valid WeaponData.

	@within DeathReportUtils
	@param weaponData any
	@return boolean
]=]
function DeathReportUtils.isWeaponData(weaponData: any): boolean
	return isWeaponDataValidator(weaponData)
end

--[=[
	Creates a WeaponData table from a weapon instance.

	@within DeathReportUtils
	@param weaponInstance Instance?
	@return WeaponData
]=]
function DeathReportUtils.createWeaponData(weaponInstance: Instance?): WeaponData
	assert(t.optional(t.instance)(weaponInstance), "Bad weaponInstance")

	return {
		weaponInstance = weaponInstance,
	}
end

--[=[
	Gets the display name of the dead player or entity.

	@within DeathReportUtils
	@param deathReport DeathReport
	@return string?
]=]
function DeathReportUtils.getDeadDisplayName(deathReport: DeathReport): string?
	assert(isDeathReportValidator(deathReport), "Bad deathReport")

	if deathReport.player then
		return deathReport.player.DisplayName
	elseif deathReport.humanoid then
		const character = deathReport.humanoid.Parent
		if character then
			return character.Name
		else
			warn("[DeathReportUtils] - DeathReport.humanoid without character")
			return "Unknown entity"
		end
	elseif deathReport.adornee then
		return nil
	else
		error("[DeathReportUtils] - DeathReport without an adornee")
	end
end

--[=[
	Returns true if the death involves the specified player.

	@within DeathReportUtils
	@param deathReport DeathReport
	@param player Player
	@return boolean
]=]
function DeathReportUtils.involvesPlayer(deathReport: DeathReport, player: Player): boolean
	assert(isDeathReportValidator(deathReport), "Bad deathReport")
	assert(t.instanceIsA("Player")(player), "Bad player")

	return (deathReport.player == player) or (deathReport.killerPlayer == player)
end

--[=[
	Gets the killer display name for the death report.

	@within DeathReportUtils
	@param deathReport DeathReport
	@return string?
]=]
function DeathReportUtils.getKillerDisplayName(deathReport: DeathReport): string?
	assert(isDeathReportValidator(deathReport), "Bad deathReport")

	if deathReport.killerPlayer then
		return deathReport.killerPlayer.DisplayName
	elseif deathReport.killerHumanoid then
		const character = deathReport.killerHumanoid.Parent
		if character then
			return character.Name
		else
			warn("[DeathReportUtils] - DeathReport.killerHumanoid without character")
			return nil
		end
	else
		return nil
	end
end

--[=[
	Returns the dead player's team color if available.

	@within DeathReportUtils
	@param deathReport DeathReport
	@return Color3?
]=]
function DeathReportUtils.getDeadColor(deathReport: DeathReport): Color3?
	assert(isDeathReportValidator(deathReport), "Bad deathReport")

	if deathReport.player then
		const team = deathReport.player.Team
		if team then
			return team.TeamColor.Color
		end
	end

	return nil
end

--[=[
	Returns the killer player's team color if available.

	@within DeathReportUtils
	@param deathReport DeathReport
	@return Color3?
]=]
function DeathReportUtils.getKillerColor(deathReport: DeathReport): Color3?
	assert(isDeathReportValidator(deathReport), "Bad deathReport")

	if deathReport.killerPlayer then
		const team = deathReport.killerPlayer.Team
		if team then
			return team.TeamColor.Color
		end
	end

	return nil
end

--[=[
	Gets the default color used for death report displays.

	@within DeathReportUtils
	@return Color3
]=]
function DeathReportUtils.getDefaultColor(): Color3
	return DEFAULT_COLOR
end

return DeathReportUtils
