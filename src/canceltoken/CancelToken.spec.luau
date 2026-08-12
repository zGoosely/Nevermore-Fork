--!strict
--[=[
	Compatibility tests for executor-owned cancellation.

	@class CancelToken.spec
]=]

const require = require("../Loader").load()

const CancelToken = require("CancelToken")
const Jest = require("Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("CancelToken", function()
	it("cancels when its executor maid is cleaned", function()
		local cleanExecutorMaid: (() -> ())? = nil
		const token = CancelToken.new(function(_cancel, maid)
			cleanExecutorMaid = function()
				maid:DoCleaning()
			end
		end)

		const clean = cleanExecutorMaid
		assert(clean, "CancelToken executor did not expose its maid")
		clean()

		expect(token:IsCancelled()).toEqual(true)
		expect(token:GetReason()).toEqual("MaidCleaned")
	end)
end)
