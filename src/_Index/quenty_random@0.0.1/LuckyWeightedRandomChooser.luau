--!strict
--[=[
	Chooses weighted options while applying a reactive pity value to options with
	luck influence. Pity increases after non-lucky choices and can reset after a
	lucky choice. Numeric weights have no luck influence; use a weight record to
	mark and boost lucky options. The adjusted weight is
	`weight * (1 + luckInfluence * pity)`.

	```lua
	local chooser = LuckyWeightedRandomChooser.new({
		Common = 80,
		Rare = {
			Weight = 20,
			LuckInfluence = 1,
		},
	}, {
		resetOnLuckyRoll = true,
		maxPity = 1,
		pityIncrement = 0.2,
	})
	```

	@class LuckyWeightedRandomChooser
]=]
const Maid = require("@game/ReplicatedStorage/Packages/Maid")
const Observable = require("@game/ReplicatedStorage/Packages/Observable")
const ValueObject = require("@game/ReplicatedStorage/Packages/ValueObject")
const WeightedRandomChooser = require("./WeightedRandomChooser")
const t = require("@game/ReplicatedStorage/Packages/t")

export type Weight = {
	Weight: number,
	LuckInfluence: number?,
}

export type Weights<T> = { [T]: number | Weight }

export type Config = {
	resetOnLuckyRoll: boolean?,
	maxPity: number?,
	pityIncrement: number?,
}

type WeightData = {
	weight: number,
	luckInfluence: number,
}

type ResolvedConfig = {
	resetOnLuckyRoll: boolean,
	maxPity: number,
	pityIncrement: number,
}

const DEFAULT_CONFIG: ResolvedConfig = {
	resetOnLuckyRoll = true,
	maxPity = 1,
	pityIncrement = 0.2,
}

const isWeight = t.strictInterface({
	Weight = t.numberMin(0),
	LuckInfluence = t.optional(t.numberMin(0)),
})

const isConfig = t.strictInterface({
	resetOnLuckyRoll = t.optional(t.boolean),
	maxPity = t.optional(t.numberMin(0)),
	pityIncrement = t.optional(t.numberMin(0)),
})

const LuckyWeightedRandomChooser = {}
LuckyWeightedRandomChooser.ClassName = "LuckyWeightedRandomChooser"
LuckyWeightedRandomChooser.__index = LuckyWeightedRandomChooser

export type LuckyWeightedRandomChooser<T> = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_chooser: WeightedRandomChooser.WeightedRandomChooser<T>,

		_weightData: { [T]: WeightData },
		_luck: ValueObject.ValueObject<number>,

		_baseTotalWeight: number,
		_resetOnLuckyRoll: boolean,
		_maxPity: number,
		_pityIncrement: number,
	},
	{} :: typeof({ __index = LuckyWeightedRandomChooser })
))

function LuckyWeightedRandomChooser.new<T>(weights: Weights<T>, config: Config?): LuckyWeightedRandomChooser<T>
	assert(t.table(weights), "Bad weights")
	assert(t.optional(isConfig)(config), "Bad config")

	if config and config.maxPity ~= nil then
		assert(t.number(config.maxPity) and config.maxPity < math.huge, "Bad config.maxPity")
	end
	if config and config.pityIncrement ~= nil then
		assert(t.number(config.pityIncrement) and config.pityIncrement < math.huge, "Bad config.pityIncrement")
	end

	const resolvedConfig: ResolvedConfig = {
		resetOnLuckyRoll = if config and config.resetOnLuckyRoll ~= nil
			then config.resetOnLuckyRoll
			else DEFAULT_CONFIG.resetOnLuckyRoll,
		maxPity = if config and config.maxPity ~= nil then config.maxPity else DEFAULT_CONFIG.maxPity,
		pityIncrement = if config and config.pityIncrement ~= nil
			then config.pityIncrement
			else DEFAULT_CONFIG.pityIncrement,
	}

	const self = setmetatable({} :: any, LuckyWeightedRandomChooser) :: LuckyWeightedRandomChooser<T>
	self._maid = Maid.new()
	self._chooser = WeightedRandomChooser.new()

	self._weightData = {}
	self._luck = self._maid:Add(ValueObject.new(0, t.number))
	self._baseTotalWeight = 0
	self._resetOnLuckyRoll = resolvedConfig.resetOnLuckyRoll
	self._maxPity = resolvedConfig.maxPity
	self._pityIncrement = resolvedConfig.pityIncrement

	for option, weightData in weights do
		if t.number(weightData) then
			self:SetWeight(option, weightData :: number)
		else
			const weight = weightData :: Weight
			assert(isWeight(weight), "Bad weight")
			self:SetWeight(option, weight.Weight, weight.LuckInfluence)
		end
	end

	assert(t.number(self._baseTotalWeight) and self._baseTotalWeight > 0, "Bad weights: expected a positive total")

	return self
end

--[=[
	Sets an option's base weight and luck influence. Passing nil as the weight
	removes the option. An option with positive luck influence counts as lucky
	when chosen.

	@within LuckyWeightedRandomChooser
	@param option T
	@param weight number?
	@param luckInfluence number?
]=]
function LuckyWeightedRandomChooser.SetWeight<T>(
	self: LuckyWeightedRandomChooser<T>,
	option: T,
	weight: number?,
	luckInfluence: number?
): ()
	assert(t.any(option) and option ~= nil, "Bad option")
	assert(t.optional(t.numberMin(0))(weight) and (weight == nil or weight < math.huge), "Bad weight")
	assert(
		t.optional(t.numberMin(0))(luckInfluence) and (luckInfluence == nil or luckInfluence < math.huge),
		"Bad luckInfluence"
	)

	if weight == nil then
		const previousData = self._weightData[option]
		if previousData then
			self._baseTotalWeight -= previousData.weight
		end

		self._weightData[option] = nil
		self._chooser:Remove(option)
		return
	end

	const data = {
		weight = weight,
		luckInfluence = luckInfluence or 0,
	}
	const adjustedWeight = self:_getAdjustedWeight(data)
	assert(t.number(adjustedWeight) and adjustedWeight < math.huge, "Adjusted weight is too large")

	const maxAdjustedWeight = data.weight * (1 + data.luckInfluence * self._maxPity)
	assert(t.number(maxAdjustedWeight) and maxAdjustedWeight < math.huge, "Maximum adjusted weight is too large")

	const previousData = self._weightData[option]
	if previousData then
		self._baseTotalWeight -= previousData.weight
	end

	self._weightData[option] = data
	self._baseTotalWeight += weight

	if adjustedWeight > 0 then
		self._chooser:SetWeight(option, adjustedWeight)
	else
		self._chooser:Remove(option)
	end
end

--[=[
	Removes an option from the chooser.

	@within LuckyWeightedRandomChooser
	@param option T
]=]
function LuckyWeightedRandomChooser.Remove<T>(self: LuckyWeightedRandomChooser<T>, option: T): ()
	self:SetWeight(option, nil)
end

--[=[
	Returns an option's base weight.

	@within LuckyWeightedRandomChooser
	@param option T
	@return number?
]=]
function LuckyWeightedRandomChooser.GetWeight<T>(self: LuckyWeightedRandomChooser<T>, option: T): number?
	assert(t.any(option) and option ~= nil, "Bad option")

	const data = self._weightData[option]
	return if data then data.weight else nil
end

--[=[
	Returns an option's probability with the current pity applied.

	@within LuckyWeightedRandomChooser
	@param option T
	@return number?
]=]
function LuckyWeightedRandomChooser.GetProbability<T>(self: LuckyWeightedRandomChooser<T>, option: T): number?
	assert(t.any(option) and option ~= nil, "Bad option")
	assert(self._baseTotalWeight > 0, "Cannot get a probability without positive weight")

	const data = self._weightData[option]
	if not data then
		return nil
	elseif data.weight == 0 then
		return 0
	end

	return self._chooser:GetProbability(option)
end

--[=[
	Chooses an option using its luck-adjusted weight, then updates pity. Options
	with positive luck influence are lucky; all other options add pity.

	@within LuckyWeightedRandomChooser
	@param random Random?
	@return T
]=]
function LuckyWeightedRandomChooser.Choose<T>(self: LuckyWeightedRandomChooser<T>, random: Random?): T
	assert(t.optional(t.Random)(random), "Bad random")
	assert(self._baseTotalWeight > 0, "Cannot choose without positive weight")

	const option = self._chooser:Choose(random)
	const data = self._weightData[option]
	assert(data, "Chosen option is missing weight data")

	if data.luckInfluence > 0 then
		if self._resetOnLuckyRoll then
			self:ResetPity()
		end
	else
		self:AddPity()
	end

	return option
end

--[=[
	Returns the current pity value.

	@within LuckyWeightedRandomChooser
	@return number
]=]
function LuckyWeightedRandomChooser.GetPity<T>(self: LuckyWeightedRandomChooser<T>): number
	return self._luck.Value
end

--[=[
	Adds pity, clamped to the configured maximum. The configured pity increment
	is used when no amount is supplied.

	@within LuckyWeightedRandomChooser
	@param amount number?
]=]
function LuckyWeightedRandomChooser.AddPity<T>(self: LuckyWeightedRandomChooser<T>, amount: number?): ()
	assert(t.optional(t.numberMin(0))(amount) and (amount == nil or amount < math.huge), "Bad amount")
	self:_setPity(self._luck.Value + (amount or self._pityIncrement))
end

--[=[
	Removes pity, clamped to zero. The configured pity increment is used when no
	amount is supplied.

	@within LuckyWeightedRandomChooser
	@param amount number?
]=]
function LuckyWeightedRandomChooser.RemovePity<T>(self: LuckyWeightedRandomChooser<T>, amount: number?): ()
	assert(t.optional(t.numberMin(0))(amount) and (amount == nil or amount < math.huge), "Bad amount")
	self:_setPity(self._luck.Value - (amount or self._pityIncrement))
end

--[=[
	Resets pity to zero.

	@within LuckyWeightedRandomChooser
]=]
function LuckyWeightedRandomChooser.ResetPity<T>(self: LuckyWeightedRandomChooser<T>): ()
	self:_setPity(0)
end

--[=[
	Observes the current pity value and future changes.

	@within LuckyWeightedRandomChooser
	@return Observable<number>
]=]
function LuckyWeightedRandomChooser.ObservePity<T>(self: LuckyWeightedRandomChooser<T>): Observable.Observable<number>
	return self._luck:Observe()
end

function LuckyWeightedRandomChooser._getAdjustedWeight<T>(self: LuckyWeightedRandomChooser<T>, data: WeightData): number
	return data.weight * (1 + data.luckInfluence * self._luck.Value)
end

function LuckyWeightedRandomChooser._setPity<T>(self: LuckyWeightedRandomChooser<T>, pity: number): ()
	const nextPity = math.clamp(pity, 0, self._maxPity)
	if self._luck.Value == nextPity then
		return
	end

	for option, data in self._weightData do
		const adjustedWeight = data.weight * (1 + data.luckInfluence * nextPity)

		if adjustedWeight > 0 then
			self._chooser:SetWeight(option, adjustedWeight)
		else
			self._chooser:Remove(option)
		end
	end
	self._luck.Value = nextPity
end

function LuckyWeightedRandomChooser.Destroy<T>(self: LuckyWeightedRandomChooser<T>): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return LuckyWeightedRandomChooser
