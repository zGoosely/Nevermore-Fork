--!strict
--[=[
	Unit tests for named lighting effects and property override stacks.

	@class LightingEffect.spec
]=]
const Jest = require("@game/ReplicatedStorage/Packages/Jest")
const LightingEffect = require("./LightingEffect")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

describe("LightingEffect", function()
	it("restores the baseline through a property stack", function()
		const effect = LightingEffect.new("LightingEffectBaselineSpec", "BlurEffect")
		const blur = effect:GetInstance() :: BlurEffect
		const originalSize = blur.Size
		const sizeStack = effect:GetPropertyStack("Size")

		const removeFirst = sizeStack:PushState(12)
		expect(blur.Size).toEqual(12)

		const removeSecond = sizeStack:PushState(24)
		expect(blur.Size).toEqual(24)

		removeSecond()
		expect(blur.Size).toEqual(12)

		removeFirst()
		expect(blur.Size).toEqual(originalSize)

		effect:Destroy()
	end)

	it("supports removing a lower stack entry first", function()
		const effect = LightingEffect.new("LightingEffectOrderSpec", "BlurEffect")
		const blur = effect:GetInstance() :: BlurEffect
		const removeFirst = effect:PushProperty("Size", 8)
		const removeSecond = effect:PushProperty("Size", 16)

		removeFirst()
		expect(blur.Size).toEqual(16)

		removeSecond()
		expect(blur.Size).toEqual(0)

		effect:Destroy()
	end)

	it("keeps stacks for separate properties independent", function()
		const effect = LightingEffect.new("LightingEffectPropertiesSpec", "BlurEffect")
		const blur = effect:GetInstance() :: BlurEffect
		const originalSize = blur.Size
		const originalEnabled = blur.Enabled
		const removeSize = effect:PushProperty("Size", 20)
		const removeEnabled = effect:PushProperty("Enabled", true)

		expect(blur.Size).toEqual(20)
		expect(blur.Enabled).toEqual(true)

		removeSize()
		expect(blur.Size).toEqual(originalSize)
		expect(blur.Enabled).toEqual(true)

		removeEnabled()
		expect(blur.Enabled).toEqual(originalEnabled)

		effect:Destroy()
	end)

	it("rejects non-post-processing classes", function()
		expect(function()
			LightingEffect.new("LightingEffectInvalidClassSpec", "Folder")
		end).toThrow()
	end)
end)
