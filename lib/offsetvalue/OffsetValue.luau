--!nocheck
--[[
	Calculates a value based on a base value, offsets, and multipliers that can be added.
	Order of operation for multipliers vs offsets applied can be set.
	Can be linked to a property of an instance to keep that property's value up to date with this value.

	Uses ValueObject internally for reactive value management.
	Provides Rx observables for reactive programming patterns.
	Supports Brio for lifetime management of values.
--]]

const require = require("../Loader").load()

local Brio = require('Brio')
local Maid = require('Maid')
local Observable = require('Observable')
local Signal = require('Signal')
local Table = require('TableUtils')
local ValueObject = require('ValueObject')

local OffsetValue = {}
OffsetValue.__index = OffsetValue

export type OffsetValue<T> = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_originalBaseValue: number,
		_baseValueObject: ValueObject.ValueObject<number>,
		_computedValueObject: ValueObject.ValueObject<number>,
		_operationOrder: string,
		_instance: Instance?,
		_property: string?,
		_multipliers: { [string]: number },
		_offsets: { [string]: number },
		_lockedMultiplierValue: number?,
		_lockedMultiplierId: {}?,
		_lockedOffsetValue: number?,
		_lockedOffsetId: {}?,

		Changed: Signal.Signal<number>,
	},
	OffsetValue
))

function OffsetValue.new<T>(
	baseValue: number,
	optionalOperationOrder: string?
): OffsetValue<T>
	local self = setmetatable({}, OffsetValue)

	self._maid = Maid.new()

	self._originalBaseValue = baseValue :: number
	self._operationOrder = optionalOperationOrder or 'OffsetThenMultiply'
	self._multipliers = {} :: { [string]: number }
	self._offsets = {} :: { [string]: number }
	self._lockedMultiplierValue = nil :: number?
	self._lockedMultiplierId = nil :: {}?
	self._lockedOffsetValue = nil :: number?
	self._lockedOffsetId = nil :: {}?

	self._instance = nil :: Instance?
	self._property = nil :: string?

	self._baseValueObject = self._maid:GiveTask(ValueObject.new(baseValue, 'number'))
	self._computedValueObject = self._maid:GiveTask(ValueObject.new(baseValue, 'number'))

	self.Changed = self._computedValueObject.Changed
	self._maid:GiveTask(self._baseValueObject.Changed:Connect(function()
		self:_computeValue()
	end))

	return self
end

--[=[
	Sets a new base value

	@param baseValue number
]=]
function OffsetValue.SetBaseValue<T>(self: OffsetValue<T>, baseValue: number)
	self._baseValueObject.Value = baseValue
end

--[=[
	Gets the current base value (before offsets and multipliers)

	@return number
]=]
function OffsetValue.GetBaseValue<T>(self: OffsetValue<T>): number
	return self._baseValueObject.Value
end

--[=[
	Gets the current computed value

	@return number
]=]
function OffsetValue.GetValue<T>(self: OffsetValue<T>): number
	return self._computedValueObject.Value
end

--[=[
	Observes changes to the computed value as an Rx observable

	Emits the new value whenever it changes.

	@return Observable<number>
]=]
function OffsetValue.Observe<T>(self: OffsetValue<T>): Observable.Observable<number>
	return self._computedValueObject:Observe()
end

--[=[
	Observes changes to the computed value wrapped in a Brio

	Each emission is a Brio that dies when the next value is emitted.
	Useful for managing the lifetime of resources tied to specific values.

	@return Observable<Brio<number>>
]=]
function OffsetValue.ObserveBrio<T>(
	self: OffsetValue<T>
): Observable.Observable<Brio.Brio<number>>
	return self._computedValueObject:ObserveBrio()
end

--[=[
	Observes the base value (before offsets and multipliers) as an Rx observable

	@return Observable<number>
]=]
function OffsetValue.ObserveBaseValue<T>(self: OffsetValue<T>): Observable.Observable<number>
	return self._baseValueObject:Observe()
end

--[=[
	Observes the base value wrapped in a Brio

	@return Observable<Brio<number>>
]=]
function OffsetValue.ObserveBaseValueBrio<T>(
	self: OffsetValue<T>
): Observable.Observable<Brio.Brio<number>>
	return self._baseValueObject:ObserveBrio()
end

--[=[
	Adds a multiplier with a unique key

	@param stringKey string
	@param multiplier number
]=]
function OffsetValue.AddMultiplier<T>(
	self: OffsetValue<T>,
	stringKey: string,
	multiplier: number
): () -> ()
	self._multipliers[stringKey] = multiplier
	self:_computeValue()

	return function()
		self:RemoveMultiplier(stringKey)
	end
end

--[=[
	Removes a multiplier by key

	@param stringKey string
]=]
function OffsetValue.RemoveMultiplier<T>(self: OffsetValue<T>, stringKey: string)
	if not self._multipliers then
		return
	end

	self._multipliers[stringKey] = nil
	self:_computeValue()
end

--[=[
	Adds an offset with a unique key

	@param stringKey string
	@param offset number
]=]
function OffsetValue.AddOffset<T>(
	self: OffsetValue<T>,
	stringKey: string,
	offset: number
): () -> ()
	self._offsets[stringKey] = offset
	self:_computeValue()

	return function()
		self:RemoveOffset(stringKey)
	end
end

--[=[
	Removes an offset by key

	@param stringKey string
]=]
function OffsetValue.RemoveOffset<T>(self: OffsetValue<T>, stringKey: string)
	if not self._offsets then
		return
	end

	self._offsets[stringKey] = nil
	self:_computeValue()
end

--[=[
	Checks if an offset with the given key exists

	@param stringKey string
	@return boolean
]=]
function OffsetValue.HasOffset<T>(self: OffsetValue<T>, stringKey: string): boolean
	return self._offsets ~= nil and self._offsets[stringKey] ~= nil
end

--[=[
	Checks if a multiplier with the given key exists

	@param stringKey string
	@return boolean
]=]
function OffsetValue.HasMultiplier<T>(self: OffsetValue<T>, stringKey: string): boolean
	return self._multipliers ~= nil and self._multipliers[stringKey] ~= nil
end

--[=[
	Locks multiplier computation to a specific value or existing multiplier key.

	While locked, all other multipliers are ignored until the returned cleanup is
	called or another multiplier lock replaces it.

	@param stringKeyOrMultiplier string | number
	@return () -> ()
]=]
function OffsetValue.LockToMultiplier<T>(
	self: OffsetValue<T>,
	stringKeyOrMultiplier: string | number
): () -> ()
	local multiplier

	if type(stringKeyOrMultiplier) == 'string' then
		assert(self._multipliers, 'No multipliers table')
		multiplier = self._multipliers[stringKeyOrMultiplier]
		assert(
			type(multiplier) == 'number',
			`No multiplier exists for key '{stringKeyOrMultiplier}'`
		)
	else
		assert(type(stringKeyOrMultiplier) == 'number', 'Bad stringKeyOrMultiplier')
		multiplier = stringKeyOrMultiplier
	end

	local lockId = {}
	self._lockedMultiplierId = lockId
	self._lockedMultiplierValue = multiplier
	self:_computeValue()

	return function()
		if self._lockedMultiplierId ~= lockId then
			return
		end

		self._lockedMultiplierId = nil
		self._lockedMultiplierValue = nil
		self:_computeValue()
	end
end

--[=[
	Locks offset computation to a specific value or existing offset key.

	While locked, all other offsets are ignored until the returned cleanup is
	called or another offset lock replaces it.

	@param stringKeyOrOffset string | number
	@return () -> ()
]=]
function OffsetValue.LockToOffset<T>(
	self: OffsetValue<T>,
	stringKeyOrOffset: string | number
): () -> ()
	local offset

	if type(stringKeyOrOffset) == 'string' then
		assert(self._offsets, 'No offsets table')
		offset = self._offsets[stringKeyOrOffset]
		assert(type(offset) == 'number', `No offset exists for key '{stringKeyOrOffset}'`)
	else
		assert(type(stringKeyOrOffset) == 'number', 'Bad stringKeyOrOffset')
		offset = stringKeyOrOffset
	end

	local lockId = {}
	self._lockedOffsetId = lockId
	self._lockedOffsetValue = offset
	self:_computeValue()

	return function()
		if self._lockedOffsetId ~= lockId then
			return
		end

		self._lockedOffsetId = nil
		self._lockedOffsetValue = nil
		self:_computeValue()
	end
end

--[=[
	Hooks the computed value to an instance property, keeping it synchronized

	@param instance Instance
	@param property string
]=]
function OffsetValue.BindToProperty<T>(
	self: OffsetValue<T>,
	instance: Instance,
	property: string
)
	self._instance = instance :: any
	self._property = property :: any

	(instance :: any)[property] = self._computedValueObject.Value

	self._maid:GiveTask(self._computedValueObject.Changed:Connect(function(newValue)
		if self._instance and self._property then
			(self._instance :: any)[self._property] = newValue
		end
	end))
end

--[=[
	Unhooks from the instance property
]=]
function OffsetValue.UnbindFromProperty<T>(self: OffsetValue<T>)
	self._instance = nil
	self._property = nil
end

--[=[
	Sets the operation order for applying offsets and multipliers

	@param operationOrder "OffsetThenMultiply" | "MultiplyThenOffset"
]=]
function OffsetValue.SetOperationOrder<T>(self: OffsetValue<T>, operationOrder: string)
	assert(
		operationOrder == 'OffsetThenMultiply' or operationOrder == 'MultiplyThenOffset',
		'Invalid operation order'
	)
	self._operationOrder = operationOrder
	self:_computeValue()
end

--[=[
	Resets to the original base value and clears all offsets and multipliers
]=]
function OffsetValue.ResetToDefault<T>(self: OffsetValue<T>)
	self._multipliers = {}
	self._offsets = {}
	self._lockedMultiplierValue = nil
	self._lockedMultiplierId = nil
	self._lockedOffsetValue = nil
	self._lockedOffsetId = nil

	self._baseValueObject.Value = self._originalBaseValue
end

function OffsetValue.__index(self, index)
	if OffsetValue[index] then
		return OffsetValue[index]
	elseif index == 'Value' then
		return self._computedValueObject.Value
	elseif index == 'BaseValue' then
		return self._baseValueObject.Value
	elseif string.sub(index, 1, 1) == '_' then
		return rawget(self, index)
	else
		error(string.format('%q is not a member of OffsetValue', tostring(index)))
	end
end

function OffsetValue.__newindex(self, index, value)
	if index == 'Value' then
		error('Cannot set Value directly. Use SetBaseValue() or add offsets/multipliers')
	elseif index == 'BaseValue' then
		self._baseValueObject.Value = value
	elseif string.sub(index, 1, 1) == '_' or index == 'Changed' then
		-- Allow setting internal properties (those starting with _) and Changed signal
		rawset(self, index, value)
	else
		error(string.format('%q is not a member of OffsetValue', tostring(index)))
	end
end

function OffsetValue._computeValue<T>(self: OffsetValue<T>)
	if
		not self._multipliers
		or not self._offsets
		or not self._baseValueObject
		or not self._computedValueObject
	then
		return
	end

	local baseValue = self._baseValueObject.Value
	if type(baseValue) ~= 'number' then
		return
	end

	local totalMultiplier
	if type(self._lockedMultiplierValue) == 'number' then
		totalMultiplier = self._lockedMultiplierValue
	else
		local multiplierValues = Table.values(self._multipliers)
		totalMultiplier = Table.reduce(multiplierValues, function(a: number, b: number)
			return a * b
		end, 1)
	end

	local totalOffset
	if type(self._lockedOffsetValue) == 'number' then
		totalOffset = self._lockedOffsetValue
	else
		local offsetValues = Table.values(self._offsets)
		totalOffset = Table.reduce(offsetValues, function(a: number, b: number)
			return a + b
		end, 0)
	end

	local value: number
	if self._operationOrder == 'OffsetThenMultiply' then
		value = (baseValue + totalOffset) * totalMultiplier
	elseif self._operationOrder == 'MultiplyThenOffset' then
		value = (baseValue * totalMultiplier) + totalOffset
	else
		error(`Invalid operation order: {self._operationOrder}`)
	end

	self._computedValueObject.Value = value
end

function OffsetValue.Destroy<T>(self: OffsetValue<T>)
	self:UnbindFromProperty()
	self._maid:DoCleaning()

	task.defer(function() -- Wait a frame incase of pending operations
		table.clear(self)
		setmetatable(self, nil)
	end)
end

return OffsetValue
