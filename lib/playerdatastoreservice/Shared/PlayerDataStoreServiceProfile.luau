--!strict
--[=[
	Selects the consuming game's profile contract before PlayerDataStoreService initializes.
	PlayerDataStoreService defaults to `ProfileData`; feature services such as SaveSlotService
	may select a more specialized contract in their own `Init` method.

	@util PlayerDataStoreServiceProfile
]=]

const require = require("../../Loader").load()

const ProfileData = require("ProfileData")

export type ProfileDefinition = {
	Template: any,
	Schema: any,
	StoreName: string?,
	StoreVersion: number?,
	SlotDataSchema: any?,
}

const PlayerDataStoreServiceProfile = {}

local selectedProfile = ProfileData :: ProfileDefinition
local selectedName = "ProfileData"
local isLocked = false

--[=[
	Selects the profile contract used by PlayerDataStoreService in the current realm. This
	must happen before PlayerDataStoreService or PlayerDataStoreServiceClient initializes.

	@within PlayerDataStoreServiceProfile
	@param profileDefinition ProfileDefinition
	@param profileName string
]=]
function PlayerDataStoreServiceProfile.Select(profileDefinition: ProfileDefinition, profileName: string)
	assert(type(profileDefinition) == "table", "Bad profileDefinition")
	assert(type(profileDefinition.Template) == "table", "Profile definition must provide Template")
	assert(
		type(profileDefinition.Schema) == "table"
			and type(profileDefinition.Schema.ser) == "function"
			and type(profileDefinition.Schema.des) == "function",
		"Profile definition must provide a Squash Schema"
	)
	assert(type(profileName) == "string" and profileName ~= "", "Bad profileName")

	if isLocked then
		assert(
			selectedProfile == profileDefinition,
			`PlayerDataStoreService already initialized with {selectedName}; {profileName} must be selected earlier`
		)
		return
	end

	selectedProfile = profileDefinition
	selectedName = profileName
end

--[=[
	Returns the currently selected profile contract.

	@within PlayerDataStoreServiceProfile
	@return ProfileDefinition
]=]
function PlayerDataStoreServiceProfile.Get(): ProfileDefinition
	return selectedProfile
end

--[=[
	Returns the name of the selected profile contract.

	@within PlayerDataStoreServiceProfile
	@return string
]=]
function PlayerDataStoreServiceProfile.GetName(): string
	return selectedName
end

--[=[
	Locks and returns the selected profile contract. PlayerDataStoreService and
	PlayerDataStoreServiceClient call this during initialization.

	@within PlayerDataStoreServiceProfile
	@return ProfileDefinition
]=]
function PlayerDataStoreServiceProfile.Lock(): ProfileDefinition
	isLocked = true
	return selectedProfile
end

return PlayerDataStoreServiceProfile
