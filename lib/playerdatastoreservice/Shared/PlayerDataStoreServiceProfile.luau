--!strict
--[=[
	Selects the consuming game's profile contract before PlayerDataStoreService initializes.
	PlayerDataStoreService defaults to `ProfileData`; feature services such as SaveSlotService
	may select a more specialized contract in their own `Init` method.

	@util PlayerDataStoreServiceProfile
]=]

const require = require("../../Loader").load()

const ProfileData = require("ProfileData")
const t = require("t")

const isValidators = t.optional(t.map(t.string, t.callback))

export type Validators = { [string]: (value: any) -> (boolean, string?) }

export type ProfileDefinition = {
	Template: any,
	Schema: any,
	Validators: Validators?,
	StoreName: string?,
	StoreVersion: number?,
	SlotDataSchema: any?,
}

const PlayerDataStoreServiceProfile = {}

local selectedProfile = ProfileData :: ProfileDefinition
local selectedName = "ProfileData"
local isLocked = false

local function assertValidProfile(profileDefinition: ProfileDefinition, profileName: string)
	assert(type(profileDefinition) == "table", "Bad profileDefinition")
	assert(type(profileDefinition.Template) == "table", "Profile definition must provide Template")
	assert(
		type(profileDefinition.Schema) == "table"
			and type(profileDefinition.Schema.ser) == "function"
			and type(profileDefinition.Schema.des) == "function",
		`{profileName}.Schema must be a single Squash codec exposing ser and des; wrap the per-key fields with Squash.record`
	)
	assert(isValidators(profileDefinition.Validators), `{profileName}.Validators must map paths to t checkers`)
end

--[=[
	Selects the profile contract used by PlayerDataStoreService in the current realm. This
	must happen before PlayerDataStoreService or PlayerDataStoreServiceClient initializes.

	@within PlayerDataStoreServiceProfile
	@param profileDefinition ProfileDefinition
	@param profileName string
]=]
function PlayerDataStoreServiceProfile.Select(profileDefinition: ProfileDefinition, profileName: string)
	assert(type(profileName) == "string" and profileName ~= "", "Bad profileName")
	assertValidProfile(profileDefinition, profileName)

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
	-- Validate here too: the default ProfileData never passes through Select, so
	-- without this a malformed default Schema surfaces as a cryptic nil call deep
	-- inside profile loading rather than a clear failure at initialization.
	assertValidProfile(selectedProfile, selectedName)
	isLocked = true
	return selectedProfile
end

return PlayerDataStoreServiceProfile
