--!strict
--[=[
	@class TiePropertyDefinition
]=]

local require = require("../../../../Loader").load()

local TieMemberDefinition = require("TieMemberDefinition")
local TiePropertyImplementation = require("TiePropertyImplementation")
local TiePropertyInterface = require("TiePropertyInterface")
local TieRealmUtils = require("TieRealmUtils")
local TieRealms = require("TieRealms")

local TiePropertyDefinition = setmetatable({}, TieMemberDefinition)
TiePropertyDefinition.ClassName = "TiePropertyDefinition"
TiePropertyDefinition.__index = TiePropertyDefinition

export type TiePropertyDefinition =
	typeof(setmetatable(
		{} :: {
			_defaultValue: any,
		},
		{} :: typeof({ __index = TieMemberDefinition })
	))
	& TieMemberDefinition.TieMemberDefinition

function TiePropertyDefinition.new(
	tieDefinition: any,
	propertyName: string,
	defaultValue: any,
	memberTieRealm: TieRealms.TieRealm
): TiePropertyDefinition
	assert(TieRealmUtils.isTieRealm(memberTieRealm), "Bad memberTieRealm")

	local self: TiePropertyDefinition =
		setmetatable(TieMemberDefinition.new(tieDefinition, propertyName, memberTieRealm) :: any, TiePropertyDefinition)

	self._defaultValue = defaultValue

	return self
end

function TiePropertyDefinition.GetDefaultValue(self: TiePropertyDefinition): any
	return self._defaultValue
end

function TiePropertyDefinition.IsRequiredForImplementation(
	self: TiePropertyDefinition,
	currentRealm: TieRealms.TieRealm
): boolean
	-- Override
	if getmetatable(TiePropertyDefinition).IsRequiredForImplementation(self, currentRealm) then
		if self:GetDefaultValue() ~= nil then
			return false
		end

		return true
	end

	return false
end

function TiePropertyDefinition.Implement(
	self: TiePropertyDefinition,
	implParent: Instance,
	initialValue: any,
	_actualSelf: any,
	tieRealm: TieRealms.TieRealm
): TiePropertyImplementation.TiePropertyImplementation
	assert(typeof(implParent) == "Instance", "Bad implParent")
	assert(TieRealmUtils.isTieRealm(tieRealm), "Bad tieRealm")

	return TiePropertyImplementation.new(self, implParent, initialValue, tieRealm)
end

function TiePropertyDefinition.GetInterface(
	self: TiePropertyDefinition,
	implParent: Instance,
	_actualSelf: any,
	tieRealm: TieRealms.TieRealm
): TiePropertyInterface.TiePropertyInterface
	assert(typeof(implParent) == "Instance", "Bad implParent")
	assert(TieRealmUtils.isTieRealm(tieRealm), "Bad tieRealm")

	return TiePropertyInterface.new(implParent, nil, self, tieRealm)
end

return TiePropertyDefinition
