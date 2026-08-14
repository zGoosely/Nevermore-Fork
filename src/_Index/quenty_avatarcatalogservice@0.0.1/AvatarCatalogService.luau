--!strict
--[=[
	Maintains a cached catalog of R6 and R15 body parts and packages, applies them on demand, and
	automatically replaces configured avatar assets after each player appearance loads.

	@class AvatarCatalogService
	@server
]=]

const ReplicatedStorage = game:GetService("ReplicatedStorage")

const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const MarketplaceServiceCache = require("@game/ReplicatedStorage/Packages/MarketplaceServiceCache")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const Promise = require("@game/ReplicatedStorage/Packages/Promise")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")
const t = require("@game/ReplicatedStorage/Packages/t")
const TieRealmService = require("@game/ReplicatedStorage/Packages/TieRealmService")
const ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")

const AvatarCatalogHumanoidBinder = require("./Binders/AvatarCatalogHumanoidBinder")
const AvatarCatalogCache = require("./Catalog/AvatarCatalogCache")
const AvatarCatalogServiceInterface = require("./AvatarCatalogServiceInterface")
const AvatarCatalogServiceTypes = require("./AvatarCatalogServiceTypes")
const AvatarCatalogServiceUtils = require("./AvatarCatalogServiceUtils")

export type AvatarScales = AvatarCatalogServiceTypes.AvatarScales
export type BodyPartDefinition = AvatarCatalogServiceTypes.BodyPartDefinition
export type PackageDefinition = AvatarCatalogServiceTypes.PackageDefinition

const AvatarCatalogService = {}
AvatarCatalogService.ServiceName = "AvatarCatalogService"
AvatarCatalogService.ServerOnly = true

export type AvatarCatalogService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_marketplaceServiceCache: MarketplaceServiceCache.MarketplaceServiceCache,
		_tieRealmService: TieRealmService.TieRealmService,
		_humanoidBinder: typeof(AvatarCatalogHumanoidBinder),
		_cache: AvatarCatalogCache.AvatarCatalogCache,
		_bodyParts: AvatarCatalogServiceTypes.BodyPartCatalog,
		_packages: AvatarCatalogServiceTypes.PackageCatalog,
		_bodyPartReplacements: AvatarCatalogServiceTypes.BodyPartReplacementCatalog,
		_packageReplacements: AvatarCatalogServiceTypes.PackageReplacementCatalog,
		_enforcePromises: { [Humanoid]: Promise.Promise<boolean> },
		_shouldUseUnfairList: ValueObject.ValueObject<boolean>,
		_revision: ValueObject.ValueObject<number>,
	},
	{} :: typeof({ __index = AvatarCatalogService })
))

function AvatarCatalogService.Init(self: AvatarCatalogService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._marketplaceServiceCache = self._serviceBag:GetService(MarketplaceServiceCache)
	self._tieRealmService = self._serviceBag:GetService(TieRealmService)
	self._humanoidBinder = self._serviceBag:GetService(AvatarCatalogHumanoidBinder)
	self._cache = self._maid:Add(AvatarCatalogCache.new(self._marketplaceServiceCache))
	self._bodyParts = {}
	self._packages = {}
	self._bodyPartReplacements = {}
	self._packageReplacements = {}
	self._enforcePromises = {}
	self._shouldUseUnfairList = self._maid:Add(ValueObject.new(true, "boolean"))
	self._revision = self._maid:Add(ValueObject.new(0, "number"))
	self._maid:Add(
		AvatarCatalogServiceInterface:Implement(ReplicatedStorage, self, self._tieRealmService:GetTieRealm())
	)
end

function AvatarCatalogService.Start(_self: AvatarCatalogService): ()
	-- The PlayerHumanoidBinder owns player-humanoid discovery and update subscriptions.
end

--[=[
	Sets whether the built-in well-known unfair body-part list is enforced. It is enabled by default.
	Disabling it stops future enforcement but does not reconstruct characters already changed.

	@within AvatarCatalogService
	@param shouldUse boolean
]=]
function AvatarCatalogService.ShouldUseUnfairList(self: AvatarCatalogService, shouldUse: boolean): ()
	assert(t.boolean(shouldUse), "Bad shouldUse")
	if self._shouldUseUnfairList.Value == shouldUse then
		return
	end
	self._shouldUseUnfairList.Value = shouldUse
	self:_requestUpdate()
end

--[=[
	Observes the current update revision. The initial revision is emitted immediately, and bound
	player humanoids use subsequent revisions to re-apply the current catalog policy.

	@within AvatarCatalogService
	@return Observable<number>
]=]
function AvatarCatalogService.ObserveUpdateRequested(self: AvatarCatalogService): Observable.Observable<number>
	return self._revision:Observe()
end

--[=[
	Adds or updates a named R6 or R15 body part in the local catalog.

	@within AvatarCatalogService
	@param name string
	@param definition BodyPartDefinition
]=]
function AvatarCatalogService.SetBodyPart(self: AvatarCatalogService, name: string, definition: BodyPartDefinition): ()
	assert(t.string(name) and name ~= "", "Bad name")
	assert(AvatarCatalogServiceUtils.isBodyPartDefinition(definition), "Bad definition")
	const existing = self._bodyParts[name]
	assert(
		existing == nil or (existing.RigType == definition.RigType and existing.BodyPart == definition.BodyPart),
		"Cannot change a registered body part's rig type or slot"
	)
	self._bodyParts[name] = AvatarCatalogServiceUtils.copyBodyPart(definition)
	self:_requestUpdate()
end

--[=[
	Removes a body part and every automatic rule that targets it.

	@within AvatarCatalogService
	@param name string
]=]
function AvatarCatalogService.RemoveBodyPart(self: AvatarCatalogService, name: string): ()
	assert(t.string(name) and name ~= "", "Bad name")
	if self._bodyParts[name] == nil then
		return
	end
	self._bodyParts[name] = nil
	for key, replacementName in self._bodyPartReplacements do
		if replacementName == name then
			self._bodyPartReplacements[key] = nil
		end
	end
	self:_requestUpdate()
end

--[=[
	Returns a copy of a catalog body part.

	@within AvatarCatalogService
	@param name string
	@return BodyPartDefinition?
]=]
function AvatarCatalogService.GetBodyPart(self: AvatarCatalogService, name: string): BodyPartDefinition?
	assert(t.string(name) and name ~= "", "Bad name")
	const definition = self._bodyParts[name]
	return if definition then AvatarCatalogServiceUtils.copyBodyPart(definition) else nil
end

--[=[
	Adds or updates a named R6 or R15 body package in the local catalog.

	@within AvatarCatalogService
	@param name string
	@param definition PackageDefinition
]=]
function AvatarCatalogService.RegisterPackage(
	self: AvatarCatalogService,
	name: string,
	definition: PackageDefinition
): ()
	assert(t.string(name) and name ~= "", "Bad name")
	assert(AvatarCatalogServiceUtils.isPackageDefinition(definition), "Bad definition")
	const existing = self._packages[name]
	assert(existing == nil or existing.RigType == definition.RigType, "Cannot change a registered package's rig type")
	self._packages[name] = AvatarCatalogServiceUtils.copyPackage(definition)
	self:_requestUpdate()
end

--[=[
	Loads a Roblox avatar bundle once, caches it, and registers its body package under a game-defined name.

	@within AvatarCatalogService
	@param name string
	@param bundleId number
	@param rigType Enum.HumanoidRigType
	@return Promise<PackageDefinition>
]=]
function AvatarCatalogService.LoadBundleAsync(
	self: AvatarCatalogService,
	name: string,
	bundleId: number,
	rigType: Enum.HumanoidRigType
): Promise.Promise<PackageDefinition>
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.numberPositive(bundleId) and bundleId % 1 == 0, "Bad bundleId")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")
	return self._cache:PromiseBundle(bundleId, rigType):Then(function(definition: PackageDefinition)
		self:RegisterPackage(name, definition)
		return AvatarCatalogServiceUtils.copyPackage(definition)
	end)
end

--[=[
	Loads a legacy Roblox package asset once, caches its product metadata, and registers its body parts.

	@within AvatarCatalogService
	@param name string
	@param packageAssetId number
	@param rigType Enum.HumanoidRigType
	@return Promise<PackageDefinition>
]=]
function AvatarCatalogService.LoadPackageAssetAsync(
	self: AvatarCatalogService,
	name: string,
	packageAssetId: number,
	rigType: Enum.HumanoidRigType
): Promise.Promise<PackageDefinition>
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.numberPositive(packageAssetId) and packageAssetId % 1 == 0, "Bad packageAssetId")
	assert(t.enum(Enum.HumanoidRigType)(rigType), "Bad rigType")
	return self._cache:PromisePackageAsset(packageAssetId, rigType):Then(function(definition: PackageDefinition)
		self:RegisterPackage(name, definition)
		return AvatarCatalogServiceUtils.copyPackage(definition)
	end)
end

--[=[
	Removes a package and every automatic package rule that references it.

	@within AvatarCatalogService
	@param name string
]=]
function AvatarCatalogService.RemovePackage(self: AvatarCatalogService, name: string): ()
	assert(t.string(name) and name ~= "", "Bad name")
	if self._packages[name] == nil then
		return
	end
	self._packages[name] = nil
	for sourceName, replacementName in self._packageReplacements do
		if sourceName == name or replacementName == name then
			self._packageReplacements[sourceName] = nil
		end
	end
	self:_requestUpdate()
end

--[=[
	Returns a copy of a catalog package.

	@within AvatarCatalogService
	@param name string
	@return PackageDefinition?
]=]
function AvatarCatalogService.GetPackage(self: AvatarCatalogService, name: string): PackageDefinition?
	assert(t.string(name) and name ~= "", "Bad name")
	const definition = self._packages[name]
	return if definition then AvatarCatalogServiceUtils.copyPackage(definition) else nil
end

--[=[
	Automatically replaces one source asset whenever it appears in the target body-part slot and rig.

	@within AvatarCatalogService
	@param sourceAssetId number
	@param replacementName string
]=]
function AvatarCatalogService.SetBodyPartReplacement(
	self: AvatarCatalogService,
	sourceAssetId: number,
	replacementName: string
): ()
	assert(t.numberPositive(sourceAssetId) and sourceAssetId % 1 == 0, "Bad sourceAssetId")
	assert(t.string(replacementName) and replacementName ~= "", "Bad replacementName")
	const replacement = self._bodyParts[replacementName]
	assert(replacement ~= nil, `Unknown body part {replacementName}`)
	const key = AvatarCatalogServiceUtils.getReplacementKey(replacement.RigType, replacement.BodyPart, sourceAssetId)
	self._bodyPartReplacements[key] = replacementName
	self:_requestUpdate()
end

--[=[
	Stops automatically replacing one source body-part asset. Existing characters are not reverted.

	@within AvatarCatalogService
	@param rigType Enum.HumanoidRigType
	@param bodyPart Enum.BodyPart
	@param sourceAssetId number
]=]
function AvatarCatalogService.RemoveBodyPartReplacement(
	self: AvatarCatalogService,
	rigType: Enum.HumanoidRigType,
	bodyPart: Enum.BodyPart,
	sourceAssetId: number
): ()
	const key = AvatarCatalogServiceUtils.getReplacementKey(rigType, bodyPart, sourceAssetId)
	if self._bodyPartReplacements[key] ~= nil then
		self._bodyPartReplacements[key] = nil
		self:_requestUpdate()
	end
end

--[=[
	Automatically replaces a fully matching source package with another package of the same rig type.

	@within AvatarCatalogService
	@param sourceName string
	@param replacementName string
]=]
function AvatarCatalogService.SetPackageReplacement(
	self: AvatarCatalogService,
	sourceName: string,
	replacementName: string
): ()
	assert(t.string(sourceName) and sourceName ~= "", "Bad sourceName")
	assert(t.string(replacementName) and replacementName ~= "", "Bad replacementName")
	assert(sourceName ~= replacementName, "Source and replacement packages must differ")
	const source = self._packages[sourceName]
	const replacement = self._packages[replacementName]
	assert(source ~= nil, `Unknown source package {sourceName}`)
	assert(replacement ~= nil, `Unknown replacement package {replacementName}`)
	assert(source.RigType == replacement.RigType, "Package rig types must match")
	self._packageReplacements[sourceName] = replacementName
	self:_requestUpdate()
end

--[=[
	Stops one automatic package replacement. Existing characters are not reverted.

	@within AvatarCatalogService
	@param sourceName string
]=]
function AvatarCatalogService.RemovePackageReplacement(self: AvatarCatalogService, sourceName: string): ()
	assert(t.string(sourceName) and sourceName ~= "", "Bad sourceName")
	if self._packageReplacements[sourceName] ~= nil then
		self._packageReplacements[sourceName] = nil
		self:_requestUpdate()
	end
end

--[=[
	Applies one named body part to a humanoid without creating an automatic replacement rule.

	@within AvatarCatalogService
	@param humanoid Humanoid
	@param name string
	@return Promise<boolean>
]=]
function AvatarCatalogService.ApplyBodyPartAsync(
	self: AvatarCatalogService,
	humanoid: Humanoid,
	name: string
): Promise.Promise<boolean>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")
	assert(t.string(name) and name ~= "", "Bad name")
	const definition = self._bodyParts[name]
	assert(definition ~= nil, `Unknown body part {name}`)
	assert(definition.RigType == humanoid.RigType, "Body part rig type does not match humanoid")
	return AvatarCatalogServiceUtils.applyDescriptionMutationAsync(humanoid, function(description)
		return AvatarCatalogServiceUtils.applyBodyPart(description, definition)
	end)
end

--[=[
	Applies one named body package to a humanoid without creating an automatic replacement rule.

	@within AvatarCatalogService
	@param humanoid Humanoid
	@param name string
	@return Promise<boolean>
]=]
function AvatarCatalogService.ApplyPackageAsync(
	self: AvatarCatalogService,
	humanoid: Humanoid,
	name: string
): Promise.Promise<boolean>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")
	assert(t.string(name) and name ~= "", "Bad name")
	const definition = self._packages[name]
	assert(definition ~= nil, `Unknown package {name}`)
	assert(definition.RigType == humanoid.RigType, "Package rig type does not match humanoid")
	return AvatarCatalogServiceUtils.applyDescriptionMutationAsync(humanoid, function(description)
		return AvatarCatalogServiceUtils.applyPackage(description, definition)
	end)
end

--[=[
	Applies every currently matching automatic replacement rule to a humanoid.

	@within AvatarCatalogService
	@param humanoid Humanoid
	@return Promise<boolean>
]=]
function AvatarCatalogService.EnforceAsync(self: AvatarCatalogService, humanoid: Humanoid): Promise.Promise<boolean>
	assert(t.instanceIsA("Humanoid")(humanoid), "Bad humanoid")
	const existing = self._enforcePromises[humanoid]
	if existing then
		return existing
	end

	const promise = self:_enforceUntilCurrentAsync(humanoid)
	self._enforcePromises[humanoid] = promise
	promise:Finally(function()
		if self._enforcePromises[humanoid] == promise then
			self._enforcePromises[humanoid] = nil
		end
	end)
	return promise
end

function AvatarCatalogService._enforceUntilCurrentAsync(
	self: AvatarCatalogService,
	humanoid: Humanoid
): Promise.Promise<boolean>
	const revision = self._revision.Value
	const shouldUseUnfairList = self._shouldUseUnfairList.Value
	return AvatarCatalogServiceUtils.applyDescriptionMutationAsync(humanoid, function(description)
		local changed = AvatarCatalogServiceUtils.applyReplacements(
			description,
			humanoid.RigType,
			self._packages,
			self._packageReplacements,
			self._bodyParts,
			self._bodyPartReplacements
		)
		if shouldUseUnfairList then
			changed = AvatarCatalogServiceUtils.applyWellKnownUnfairParts(description, humanoid.RigType) or changed
		end
		return changed
	end):Then(function(changed: boolean)
		if revision ~= self._revision.Value and humanoid.Parent ~= nil then
			return self:_enforceUntilCurrentAsync(humanoid):Then(function(changedAgain: boolean)
				return changed or changedAgain
			end)
		end
		return changed
	end)
end

function AvatarCatalogService._requestUpdate(self: AvatarCatalogService): ()
	self._revision.Value += 1
end

function AvatarCatalogService.Destroy(self: AvatarCatalogService): ()
	self._maid:DoCleaning()
end

return AvatarCatalogService
