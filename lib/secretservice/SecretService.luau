--!strict
--[=[
	@class SecretService
]=]

const HttpService = game:GetService("HttpService")
const RunService = game:GetService("RunService")
const require = require("../Loader").load()

const EllipticCurveCryptography = require("EllipticCurveCryptography")
const Maid = require("Maid")
const PermissionService = require("PermissionService")
const ProfileStore = require("ProfileStore")
const Promise = require("Promise")
const SecretServiceConstants = require("SecretServiceConstants")
const SecretServiceNetwork = require("SecretServiceNetwork")
const ServiceBag = require("ServiceBag")

local t = require("t")

type SecretData = {
	encrypted: { number },
	signature: { number },
}

type SecretProfile = any
type SecretValue = string | Secret

local SecretService = {}
SecretService.ServiceName = "SecretService"
SecretService.ServerOnly = true

export type SecretService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_permissionService: PermissionService.PermissionService,
		_knownSecretKeys: { [string]: boolean },
		_store: any,
		_profilePromise: Promise.Promise<SecretProfile?>?,
		_memoryStore: { [string]: SecretData },
		_storeName: string,
		_storeKey: string,
		_privateKey: any,
		_publicKey: any,
		_warningRequired: boolean,
		_useMemoryFallback: boolean,
	},
	{} :: typeof({ __index = SecretService })
))

local function sortKeys(map: { [string]: any }): { string }
	local keys = {}

	for key in map do
		table.insert(keys, key)
	end

	table.sort(keys)
	return keys
end

function SecretService.Init(self: SecretService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._permissionService = self._serviceBag:GetService(PermissionService)
	self._knownSecretKeys = {}
	self._memoryStore = {}
	self._storeName = SecretServiceConstants.DEFAULT_STORE_NAME
	self._storeKey = SecretServiceConstants.DEFAULT_STORE_KEY
	self._warningRequired = false
	self._useMemoryFallback = false

	self:SetEncryptionSeed(game.GameId)
	self._warningRequired = true

	self._store = ProfileStore.New(self._storeName, {
		[SecretServiceConstants.SECRETS_DATA_KEY] = {},
	})

	if RunService:IsStudio() then
		self._store = self._store.Mock
	end
end

function SecretService.Start(self: SecretService)
	SecretServiceNetwork.queries.requestSecretKeyNames.listen(function(request: string, player: Player?): { string }
		return self:_handleServerInvoke(player :: Player, request)
	end)
end

--[=[
	Sets the encryption seed used to generate the keypair.

	@within SecretService
	@param seed number
]=]
function SecretService.SetEncryptionSeed(self: SecretService, seed: number)
	assert(type(seed) == "number", "Bad seed")

	local privateKey, publicKey = EllipticCurveCryptography.keypair(seed)
	self._privateKey = privateKey
	self._publicKey = publicKey
	self._warningRequired = false
end

--[=[
	Sets the public key seed (alias of SetEncryptionSeed).

	@within SecretService
	@param seed number
]=]
function SecretService.SetPublicKeySeed(self: SecretService, seed: number)
	self:SetEncryptionSeed(seed)
end

--[=[
	Sets the public seed (alias of SetEncryptionSeed).

	@within SecretService
	@param seed number
]=]
function SecretService.SetPublicSeed(self: SecretService, seed: number)
	self:SetEncryptionSeed(seed)
end

--[=[
	Retrieves a secret by key asynchronously.

	@within SecretService
	@param secretKey string -- The key identifying the secret
	@return Promise.Promise<string?> -- Resolves with the decrypted secret, or nil if not found
]=]
function SecretService.PromiseSecret(self: SecretService, secretKey: string): Promise.Promise<SecretValue?>
	assert(t.string(secretKey), "Bad secretKey")

	local success, robloxSecret = pcall(function()
		return HttpService:GetSecret(secretKey)
	end)
	if success and robloxSecret ~= nil then
		local valueType = typeof(robloxSecret)
		if (valueType == "string" and robloxSecret ~= "") or valueType == "Secret" then
			self._knownSecretKeys[secretKey] = true
			return Promise.resolved(robloxSecret :: any)
		end
	end

	return self:_promiseSecretsTable():Then(function(secretMap)
		local secretData = secretMap[secretKey]
		if type(secretData) ~= "table" then
			return nil
		end

		local ok, value = self:_decrypt(secretData)
		if ok then
			self._knownSecretKeys[secretKey] = true
			return value
		end

		return Promise.rejected(value or "Failed to decrypt secret")
	end)
end

--[=[
	Gets a decrypted secret value by key (yields).

	@within SecretService
	@param secretKey string
	@return string?
]=]
function SecretService.GetSecret(self: SecretService, secretKey: string): SecretValue?
	local success, result = self:PromiseSecret(secretKey):Yield()
	if not success then
		error(result)
	end

	return result
end

--[=[
	Retrieves all stored secrets asynchronously.


	@within SecretService
	@return Promise.Promise<{ [string]: string }> -- Resolves with a map of secretKey -> decrypted value
]=]
function SecretService.PromiseAllSecrets(self: SecretService): Promise.Promise<{ [string]: string }>
	return self:_promiseSecretsTable():Then(function(secretMap)
		local result = {}

		for secretKey, secretData in secretMap do
			local ok, value = self:_decrypt(secretData)
			if ok then
				result[secretKey] = value
			end
		end

		return result
	end)
end

--[=[
	Returns a promise resolving to a sorted list of all secret keys.

	@within SecretService
	@return Promise.Promise<{ string }>
]=]
function SecretService.PromiseSecretKeyNamesList(self: SecretService): Promise.Promise<{ string }>
	local knownKeys = sortKeys(self._knownSecretKeys)
	if #knownKeys > 0 and not self._profilePromise and not self._useMemoryFallback then
		return Promise.resolved(knownKeys)
	end

	return self:_promiseSecretsTable():Then(function(secretMap)
		local combined = {}

		for _, key in knownKeys do
			combined[key] = true
		end

		for key in secretMap do
			combined[key] = true
		end

		return sortKeys(combined)
	end)
end

--[=[
	Encrypts and stores a secret value under the given key.

	@within SecretService
	@param secretKey string
	@param secretValue string
	@return Promise.Promise<boolean>
]=]
function SecretService.PromiseStoreSecret(
	self: SecretService,
	secretKey: string,
	secretValue: string
): Promise.Promise<boolean>
	assert(t.string(secretKey), "Bad secretKey")
	assert(t.string(secretValue), "Bad secretValue")

	self:_warnAboutDefaultSeed()

	return self:_promiseMutateSecrets(function(secretMap)
		local encrypted = EllipticCurveCryptography.encrypt(secretValue, self._privateKey)
		local signature = EllipticCurveCryptography.sign(self._privateKey, secretValue)

		self._knownSecretKeys[secretKey] = true
		secretMap[secretKey] = {
			encrypted = setmetatable(table.clone(encrypted), nil),
			signature = setmetatable(table.clone(signature), nil),
		} :: any
	end)
end

--[=[
	Stores a secret value under the given key (non-blocking wrapper).

	@within SecretService
	@param secretKey string
	@param secretValue string
	@return boolean
]=]
function SecretService.StoreSecret(self: SecretService, secretKey: string, secretValue: string): boolean
	local success, result

	task.spawn(function()
		success, result = self:PromiseStoreSecret(secretKey, secretValue):Yield()
		if not success then
			error(result)
		end
	end)

	return result
end

--[=[
	Deletes a stored secret by key.

	@within SecretService
	@param secretKey string
	@return Promise.Promise<boolean>
]=]
function SecretService.PromiseDeleteSecret(self: SecretService, secretKey: string): Promise.Promise<boolean>
	assert(t.string(secretKey), "Bad secretKey")

	return self:_promiseMutateSecrets(function(secretMap)
		self._knownSecretKeys[secretKey] = nil
		secretMap[secretKey] = nil
	end)
end

--[=[
	Deletes a stored secret by key (yields).

	@within SecretService
	@param secretKey string
	@return boolean
]=]
function SecretService.DeleteSecret(self: SecretService, secretKey: string): boolean
	local success, result = self:PromiseDeleteSecret(secretKey):Yield()
	if not success then
		error(result)
	end

	return result
end

--[=[
	Clears all stored secrets.

	@within SecretService
	@return Promise.Promise<boolean>
]=]
function SecretService.PromiseClearAllSecrets(self: SecretService): Promise.Promise<boolean>
	return self:_promiseMutateSecrets(function(secretMap)
		table.clear(secretMap)
		table.clear(self._knownSecretKeys)
	end)
end

--[=[
	Clears all stored secrets (yields).

	@within SecretService
	@return boolean
]=]
function SecretService.ClearAllSecrets(self: SecretService): boolean
	local success, result = self:PromiseClearAllSecrets():Yield()
	if not success then
		error(result)
	end

	return result
end

function SecretService._rebuildStore(self: SecretService)
	self._store = ProfileStore.New(self._storeName, {
		[SecretServiceConstants.SECRETS_DATA_KEY] = {},
	})
	self._profilePromise = nil

	if RunService:IsStudio() then
		self._store = self._store.Mock
	end
end

function SecretService._promiseProfile(self: SecretService): Promise.Promise<SecretProfile?>
	if self._useMemoryFallback then
		return Promise.resolved(nil)
	end

	if self._profilePromise then
		return self._profilePromise
	end

	self._profilePromise = self._maid:GivePromise(Promise.new(function(resolve)
		local success, profile = pcall(function()
			return self._store:StartSessionAsync(self._storeKey, {
				Steal = RunService:IsStudio(),
				Cancel = function()
					return false
				end,
			})
		end)

		if success and profile then
			profile:Reconcile()

			if type(profile.Data[SecretServiceConstants.SECRETS_DATA_KEY]) ~= "table" then
				profile.Data[SecretServiceConstants.SECRETS_DATA_KEY] = {}
			end

			resolve(profile)
			return
		end

		self._useMemoryFallback = true

		resolve(nil)
	end))

	return self._profilePromise :: Promise.Promise<> | any
end

function SecretService._promiseSecretsTable(self: SecretService): Promise.Promise<{ [string]: SecretData }>
	return self:_promiseProfile():Then(function(profile)
		if not profile then
			return self._memoryStore
		end

		return profile.Data[SecretServiceConstants.SECRETS_DATA_KEY] :: { [string]: SecretData }
	end)
end

function SecretService._promiseMutateSecrets(
	self: SecretService,
	mutator: ({ [string]: SecretData }) -> ()
): Promise.Promise<boolean>
	return self:_promiseProfile():Then(function(profile)
		local secretMap = if profile
			then profile.Data[SecretServiceConstants.SECRETS_DATA_KEY] :: { [string]: SecretData }
			else self._memoryStore

		mutator(secretMap)

		if profile then
			local success, err = pcall(function()
				profile:Save()
			end)
			if not success then
				return Promise.rejected(err)
			end
		end

		return true
	end)
end

function SecretService._warnAboutDefaultSeed(self: SecretService)
	if not self._warningRequired then
		return
	end

	self._warningRequired = false
	warn(
		`[SecretService] - Encryption seed is using GameId by default. Call 'SecretService:SetEncryptionSeed(...)' with your own seed to improve at-rest protection.`
	)
end

function SecretService._decrypt(self: SecretService, data: SecretData): (boolean, string)
	assert(type(data) == "table", "Bad data")
	assert(type(data.encrypted) == "table", "Bad data.encrypted")
	assert(type(data.signature) == "table", "Bad data.signature")

	local encrypted = EllipticCurveCryptography.createByteTable(data.encrypted)
	local signature = EllipticCurveCryptography.createByteTable(data.signature)
	local decrypted = EllipticCurveCryptography.decrypt(encrypted, self._privateKey)

	if not EllipticCurveCryptography.verify(self._publicKey, decrypted, signature) then
		return false, "Secret signature validation failed"
	end

	return true, tostring(decrypted)
end

function SecretService._handleServerInvoke(self: SecretService, player: Player, request: string)
	if request == SecretServiceConstants.REQUEST_SECRET_KEY_NAMES_LIST then
		return self:_promiseHandleList(player):Wait()
	end

	error(`Bad request '{tostring(request)}'`)
end

function SecretService._promiseHandleList(self: SecretService, player: Player): Promise.Promise<{ string }>
	return self._permissionService
		:PromisePermissionProvider()
		:Then(function(provider)
			return provider:PromiseIsAdmin(player)
		end)
		:Then(function(isAdmin)
			if not isAdmin then
				return Promise.rejected("Not authorized")
			end

			return self:PromiseSecretKeyNamesList()
		end)
end

function SecretService.Destroy(self: SecretService)
	local success, profile = self:_promiseProfile():Yield()
	if success and profile then
		pcall(function()
			profile:Save()
			profile:EndSession()
		end)
	end

	self._maid:Destroy()
end

return SecretService
