--!strict
--[=[
	Unit tests for cancellation ownership and reason preservation.

	@class CancelTokenSource.spec
]=]
const CancelTokenSource = require("./CancelTokenSource")
const Jest = require("@game/ReplicatedStorage/Packages/Jest")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("CancelTokenSource", function()
	it("cancels once and preserves the first reason", function()
		const source = CancelTokenSource.new()
		const token = source:GetToken()
		local cancelCount = 0
		token.Cancelled:Connect(function()
			cancelCount += 1
		end)

		expect(source:Cancel("Stunned")).toEqual(true)
		expect(source:Cancel("Died")).toEqual(false)
		expect(token:IsCancelled()).toEqual(true)
		expect(token:GetReason()).toEqual("Stunned")
		expect(cancelCount).toEqual(1)

		source:Destroy()
	end)
end)
