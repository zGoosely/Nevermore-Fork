--!strict
--[=[
	Unit tests for forwarding ByteNet endpoint operations as instance methods.

	@class MixinNetwork.spec
]=]

const require = require("../Loader").load()

const Jest = require("Jest")
const MixinNetwork = require("MixinNetwork")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("MixinNetwork", function()
	it("forwards arguments and return values without forwarding self", function()
		const class = {}
		const received = {}

		MixinNetwork:Add(class, {
			someNetworkMethod = {
				invoke = function(first: number, second: number): (number, number)
					table.insert(received, first)
					table.insert(received, second)
					return first + second, first * second
				end,
			},
		}, "invoke")

		const object = setmetatable({}, { __index = class }) :: any
		const sum, product = object:SomeNetworkMethod(3, 4)

		expect(received).toEqual({ 3, 4 })
		expect(sum).toEqual(7)
		expect(product).toEqual(12)
	end)

	it("rejects missing operations and existing class methods", function()
		expect(function()
			MixinNetwork:Add({}, {
				missing = {},
			}, "send")
		end).toThrow()

		expect(function()
			MixinNetwork:Add({
				Changed = function() end,
			}, {
				changed = {
					send = function() end,
				},
			}, "send")
		end).toThrow()
	end)
end)
