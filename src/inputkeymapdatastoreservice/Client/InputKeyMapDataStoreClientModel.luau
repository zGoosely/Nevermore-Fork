--!strict
--[=[
	Synchronizes one rebindable InputKeyMapList with the local player's persisted
	binding records.

	@class InputKeyMapDataStoreClientModel
	@client
]=]

const require = require("../../Loader").load()

const InputKeyMap = require("InputKeyMap")
const InputKeyMapDataStoreServiceConstants = require("InputKeyMapDataStoreServiceConstants")
const InputKeyMapDataStoreServiceNetwork = require("InputKeyMapDataStoreServiceNetwork")
const InputKeyMapDataStoreServiceTypes = require("InputKeyMapDataStoreServiceTypes")
const InputKeyMapDataStoreServiceUtils = require("InputKeyMapDataStoreServiceUtils")
const InputKeyMapList = require("InputKeyMapList")
const Maid = require("Maid")
const PlayerDataStoreServiceClient = require("PlayerDataStoreServiceClient")
const t = require("t")

type Bindings = InputKeyMapDataStoreServiceTypes.Bindings

const InputKeyMapDataStoreClientModel = {}
InputKeyMapDataStoreClientModel.ClassName = "InputKeyMapDataStoreClientModel"
InputKeyMapDataStoreClientModel.__index = InputKeyMapDataStoreClientModel

export type InputKeyMapDataStoreClientModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_providerName: string,
		_inputKeyMapList: InputKeyMapList.InputKeyMapList,
		_playerDataStoreServiceClient: PlayerDataStoreServiceClient.PlayerDataStoreServiceClient,
	},
	{} :: typeof({ __index = InputKeyMapDataStoreClientModel })
))

function InputKeyMapDataStoreClientModel.new(
	providerName: string,
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	playerDataStoreServiceClient: PlayerDataStoreServiceClient.PlayerDataStoreServiceClient
): InputKeyMapDataStoreClientModel
	assert(
		t.string(providerName)
			and providerName ~= ""
			and #providerName <= InputKeyMapDataStoreServiceConstants.MAX_NAME_LENGTH,
		"Bad providerName"
	)
	assert(t.table(inputKeyMapList) and InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(t.table(playerDataStoreServiceClient), "Bad playerDataStoreServiceClient")

	const self = setmetatable({}, InputKeyMapDataStoreClientModel) :: InputKeyMapDataStoreClientModel
	self._maid = Maid.new()
	self._providerName = providerName
	self._inputKeyMapList = inputKeyMapList
	self._playerDataStoreServiceClient = playerDataStoreServiceClient

	self._maid
		:GivePromise(self._playerDataStoreServiceClient:PromiseDataStore())
		:Then(function()
			self:_startObserving()
		end)
		:Catch(function(errorMessage: any)
			warn(`[InputKeyMapDataStoreClientModel] - Profile unavailable: {errorMessage}`)
		end)

	return self
end

function InputKeyMapDataStoreClientModel._startObserving(self: InputKeyMapDataStoreClientModel): ()
	self._maid:GiveTask(self._inputKeyMapList:ObservePairsBrio():Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const maid, _, inputKeyMap = brio:ToMaidAndValue()
		self:_observeInputKeyMap(maid, inputKeyMap)
	end))
end

function InputKeyMapDataStoreClientModel._observeInputKeyMap(
	self: InputKeyMapDataStoreClientModel,
	maid: Maid.Maid,
	inputKeyMap: InputKeyMap.InputKeyMap
): ()
	const inputModeType = inputKeyMap:GetInputModeType()
	const inputModeName = inputModeType.Name
	const listName = self._inputKeyMapList:GetListName()
	assert(
		t.string(listName) and listName ~= "" and #listName <= InputKeyMapDataStoreServiceConstants.MAX_NAME_LENGTH,
		"Bad listName"
	)
	assert(
		t.string(inputModeName)
			and inputModeName ~= ""
			and #inputModeName <= InputKeyMapDataStoreServiceConstants.MAX_NAME_LENGTH,
		"Bad inputModeName"
	)

	maid:GiveTask(
		self._playerDataStoreServiceClient
			:ObserveAtKey(InputKeyMapDataStoreServiceConstants.PROFILE_PATH)
			:Subscribe(function(bindings: Bindings?)
				if not InputKeyMapDataStoreServiceUtils.isBindings(bindings) then
					return
				end

				const binding = InputKeyMapDataStoreServiceUtils.findBinding(
					bindings :: Bindings,
					self._providerName,
					listName,
					inputModeName
				)
				const desiredInputTypes = if binding
					then InputKeyMapDataStoreServiceUtils.deserializeInputTypes(binding.InputTypes)
					else inputKeyMap:GetDefaultInputTypesList()
				if
					not desiredInputTypes
					or not InputKeyMapDataStoreServiceUtils.areInputTypesValidForMode(inputModeType, desiredInputTypes)
				then
					warn(
						`[InputKeyMapDataStoreClientModel] - Ignoring invalid binding {self._providerName}.{listName}.{inputModeName}`
					)
					return
				end

				const currentSerialized =
					InputKeyMapDataStoreServiceUtils.serializeInputTypes(inputKeyMap:GetInputTypesList())
				const desiredSerialized = InputKeyMapDataStoreServiceUtils.serializeInputTypes(desiredInputTypes)
				if
					not InputKeyMapDataStoreServiceUtils.areSerializedInputTypesEquivalent(
						currentSerialized,
						desiredSerialized
					)
				then
					inputKeyMap:SetInputTypesList(desiredInputTypes)
				end
			end)
	)

	maid:GiveTask(inputKeyMap:ObserveInputTypesList():Subscribe(function(inputTypes)
		const bindings =
			self._playerDataStoreServiceClient:GetValue(InputKeyMapDataStoreServiceConstants.PROFILE_PATH) :: Bindings?
		if not InputKeyMapDataStoreServiceUtils.isBindings(bindings) then
			return
		end

		const currentSerialized = InputKeyMapDataStoreServiceUtils.serializeInputTypes(inputTypes)
		const defaultSerialized =
			InputKeyMapDataStoreServiceUtils.serializeInputTypes(inputKeyMap:GetDefaultInputTypesList())
		const storedBinding = InputKeyMapDataStoreServiceUtils.findBinding(
			bindings :: Bindings,
			self._providerName,
			listName,
			inputModeName
		)
		const isDefault =
			InputKeyMapDataStoreServiceUtils.areSerializedInputTypesEquivalent(currentSerialized, defaultSerialized)

		if isDefault and not storedBinding then
			return
		end
		if
			storedBinding
			and not isDefault
			and InputKeyMapDataStoreServiceUtils.areSerializedInputTypesEquivalent(
				currentSerialized,
				storedBinding.InputTypes
			)
		then
			return
		end

		const request = {
			ProviderName = self._providerName,
			ListName = listName,
			InputModeName = inputModeName,
			InputTypes = if isDefault then {} else currentSerialized,
			Clear = isDefault,
		}
		assert(InputKeyMapDataStoreServiceUtils.isBindingRequest(request), "Invalid binding request")
		InputKeyMapDataStoreServiceNetwork.packets.bindingRequested.send(request)
	end))
end

function InputKeyMapDataStoreClientModel.Destroy(self: InputKeyMapDataStoreClientModel): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return InputKeyMapDataStoreClientModel
