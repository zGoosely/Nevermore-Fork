--!strict
--[=[
	Initializes ragdoll related binders

	@server
	@class RagdollService
]=]
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local RagdollService = {}
RagdollService.ServiceName = "RagdollService"

--[=[
	Initializes the ragdoll service on the server. Should be done via [ServiceBag].
	@param serviceBag ServiceBag
]=]
function RagdollService:Init(serviceBag: ServiceBag.ServiceBag)
	assert(not self._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")

	-- External
	self._serviceBag:GetService(require("@game/ReplicatedStorage/Packages/Motor6DService"))

	-- Internal
	self._serviceBag:GetService(require("./RagdollBindersServer"))

	-- Binders
	self._serviceBag:GetService((require :: any)("./Classes/Ragdoll"))
	self._serviceBag:GetService((require :: any)("./Classes/Ragdollable"))
	self._serviceBag:GetService((require :: any)("./Classes/RagdollHumanoidOnDeath"))
	self._serviceBag:GetService((require :: any)("./Classes/RagdollHumanoidOnFall"))
	self._serviceBag:GetService((require :: any)("./Classes/UnragdollAutomatically"))
	self._serviceBag:GetService((require :: any)("./Classes/RagdollCameraShake"))

	-- Configure
	self._serviceBag:GetService((require :: any)("./Classes/RagdollHumanoidOnDeath")):SetAutomaticTagging(false)
	self._serviceBag:GetService((require :: any)("./Classes/RagdollHumanoidOnFall")):SetAutomaticTagging(false)
	self._serviceBag:GetService((require :: any)("./Classes/UnragdollAutomatically")):SetAutomaticTagging(false)
end

--[=[
	Sets whether ragdolls should ragdoll on fall.
	@param ragdollOnFall boolean
]=]
function RagdollService:SetRagdollOnFall(ragdollOnFall: boolean)
	assert(self._serviceBag, "Not initialized")
	assert(type(ragdollOnFall) == "boolean", "Bad ragdollOnFall")

	self._serviceBag:GetService(require("./Classes/RagdollHumanoidOnFall")):SetAutomaticTagging(ragdollOnFall)
end

--[=[
	Sets whether ragdolls should ragdoll on death.
	@param ragdollOnDeath boolean
]=]
function RagdollService:SetRagdollOnDeath(ragdollOnDeath: boolean)
	assert(self._serviceBag, "Not initialized")
	assert(type(ragdollOnDeath) == "boolean", "Bad ragdollOnDeath")

	self._serviceBag:GetService(require("./Classes/RagdollHumanoidOnDeath")):SetAutomaticTagging(ragdollOnDeath)
end

--[=[
	Sets whether ragdolls should unragdoll automatically.
	@param unragdollAutomatically boolean
]=]
function RagdollService:SetUnragdollAutomatically(unragdollAutomatically: boolean)
	assert(self._serviceBag, "Not initialized")
	assert(type(unragdollAutomatically) == "boolean", "Bad unragdollAutomatically")

	self._serviceBag:GetService(require("./Classes/UnragdollAutomatically")):SetAutomaticTagging(unragdollAutomatically)
end

return RagdollService
