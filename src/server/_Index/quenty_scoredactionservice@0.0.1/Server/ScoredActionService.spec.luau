--!strict
--[[
	@class ScoredActionService.spec.lua
]]
local InputKeyMapService = require("@game/ReplicatedStorage/Packages/InputKeyMapService")
local Jest = require("@game/ReplicatedStorage/Packages/Jest")
local Maid = require("@game/ReplicatedStorage/Packages/Maid")
local ScoredActionService = require("./ScoredActionService")
local ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local describe = Jest.Globals.describe
local expect = Jest.Globals.expect
local it = Jest.Globals.it

type Controller = {
	serviceBag: ServiceBag.ServiceBag,
	service: any,
	destroy: () -> (),
}

local function setup(): Controller
	local maid = Maid.new()

	local serviceBag: ServiceBag.ServiceBag = maid:Add(ServiceBag.new()) :: any
	local service = serviceBag:GetService(ScoredActionService)
	serviceBag:Init()
	serviceBag:Start()

	local controller: Controller = {
		serviceBag = serviceBag,
		service = service,

		destroy = function()
			maid:DoCleaning()
		end,
	}

	return controller
end

describe("ScoredActionService.Init", function()
	it("initializes through the service bag", function()
		local controller = setup()

		expect(controller.service).never.toBeNil()
		expect(ScoredActionService.ServiceName).toBe("ScoredActionService")

		controller.destroy()
	end)

	it("registers the input key map service", function()
		local controller = setup()

		expect(controller.serviceBag:HasService(InputKeyMapService)).toBe(true)

		controller.destroy()
	end)

	it("throws when initialized twice", function()
		local controller = setup()

		expect(function()
			controller.service:Init(controller.serviceBag)
		end).toThrow()

		controller.destroy()
	end)

	it("throws without a serviceBag", function()
		local controller = setup()

		expect(function()
			(ScoredActionService :: any):Init(nil)
		end).toThrow()

		controller.destroy()
	end)
end)
