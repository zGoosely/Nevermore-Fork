--!strict
--[=[
	Unit tests for the Blend-compatible shimmer utility.

	@class UIShimmerUtils.spec
]=]

const require = require("../Loader").load()

const Blend = require("Blend")
const Jest = require("Jest")
const UIShimmerUtils = require("UIShimmerUtils")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

const function getShimmer(target: GuiObject): Frame
	return target:FindFirstChild("UIShimmer") :: Frame
end

describe("UIShimmerUtils", function()
	it("validates options", function()
		expect(function()
			UIShimmerUtils.shimmer({
				DelayTime = 0.25,
				Duration = 2,
			})
		end).never.toThrow()
		expect(function()
			UIShimmerUtils.shimmer({ Duration = 0 })
		end).toThrow()
		expect(function()
			UIShimmerUtils.shimmer({ DelayTime = -1 })
		end).toThrow()
		expect(function()
			UIShimmerUtils.shimmer({ Unknown = true } :: any)
		end).toThrow()

		const attach = UIShimmerUtils.shimmer()
		const invalidTarget = Instance.new("Folder")
		const target = Instance.new("Frame")
		expect(function()
			attach(invalidTarget :: any, true)
		end).toThrow()
		expect(function()
			attach(target, "yes" :: any)
		end).toThrow()
		invalidTarget:Destroy()
		target:Destroy()
	end)

	it("mounts an active shimmer with the default appearance", function()
		const target = Instance.new("Frame")
		target.ZIndex = 4
		const maid = Blend.mount(target, {
			[UIShimmerUtils.shimmer()] = true,
		})
		const shimmer = getShimmer(target)
		const gradient = shimmer:FindFirstChildOfClass("UIGradient") :: UIGradient

		expect(shimmer.Visible).toEqual(true)
		expect(shimmer.ZIndex).toEqual(5)
		expect(gradient.Rotation).toEqual(15)
		target.ZIndex = 7
		expect(shimmer.ZIndex).toEqual(8)

		maid:DoCleaning()
		target:Destroy()
	end)

	it("reactively controls and cleans the shimmer", function()
		const root = Instance.new("Folder")
		const target = Instance.new("Frame")
		target.Parent = root
		const enabled = Blend.State(false)
		const maid = Blend.mount(target, {
			[UIShimmerUtils.shimmer()] = enabled,
		})
		const shimmer = getShimmer(target)
		const gradient = shimmer:FindFirstChildOfClass("UIGradient") :: UIGradient

		expect(shimmer.Visible).toEqual(false)
		enabled.Value = true
		expect(shimmer.Visible).toEqual(true)
		enabled.Value = false
		expect(shimmer.Visible).toEqual(false)
		expect(gradient.Offset).toEqual(Vector2.new(-1, 0))

		maid:DoCleaning()
		expect(target.Parent).toEqual(root)
		expect(shimmer.Parent).toEqual(nil)
		root:Destroy()
	end)

	it("tracks corners and padding", function()
		const target = Instance.new("Frame")
		const corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = target
		const padding = Instance.new("UIPadding")
		padding.PaddingBottom = UDim.new(0, 8)
		padding.PaddingLeft = UDim.new(0.1, 4)
		padding.PaddingRight = UDim.new(0.1, 6)
		padding.PaddingTop = UDim.new(0, 2)
		padding.Parent = target

		const maid = Blend.mount(target, {
			[UIShimmerUtils.shimmer()] = false,
		})
		const shimmer = getShimmer(target)
		const shimmerCorner = shimmer:FindFirstChildOfClass("UICorner") :: UICorner

		expect(shimmerCorner.CornerRadius).toEqual(UDim.new(0, 8))
		expect(shimmer.Size).toEqual(UDim2.new(1.25, 10, 1, 10))
		expect(shimmer.Position).toEqual(UDim2.new(0.5, 1, 0.5, 3))

		corner.CornerRadius = UDim.new(0, 16)
		padding.PaddingRight = UDim.new(0.1, 10)
		expect(shimmerCorner.CornerRadius).toEqual(UDim.new(0, 16))
		expect(shimmer.Size).toEqual(UDim2.new(1.25, 14, 1, 10))
		expect(shimmer.Position).toEqual(UDim2.new(0.5, 3, 0.5, 3))

		corner.Parent = nil
		padding.Parent = nil
		expect(shimmer:FindFirstChildOfClass("UICorner")).toEqual(nil)
		expect(shimmer.Size).toEqual(UDim2.fromScale(1, 1))
		expect(shimmer.Position).toEqual(UDim2.fromScale(0.5, 0.5))

		corner.CornerRadius = UDim.new(0, 4)
		corner.Parent = target
		padding.Parent = target
		expect((shimmer:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius).toEqual(UDim.new(0, 4))
		expect(shimmer.Size).toEqual(UDim2.new(1.25, 14, 1, 10))

		maid:DoCleaning()
		target:Destroy()
	end)
end)
