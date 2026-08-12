--!strict
--[=[
	Unit tests for overlap-safe client culling visibility state.

	@class ClientCullingVisibilityState.spec
]=]

const require = require("../Loader").load()

const ClientCullingVisibilityState = require("ClientCullingVisibilityState")
const Jest = require("Jest")
const TransparencyService = require("TransparencyService")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createTransparencyService(): TransparencyService.TransparencyService
	const transparencyService = {} :: any
	TransparencyService.Init(transparencyService)
	return transparencyService
end

describe("ClientCullingVisibilityState", function()
	it("keeps overlapping render and shadow owners isolated", function()
		const transparencyService = createTransparencyService()
		const visibility = ClientCullingVisibilityState.new(transparencyService)
		const root = Instance.new("Model")
		const part = Instance.new("Part")
		part.CastShadow = true
		part.Parent = root
		const emitter = Instance.new("ParticleEmitter")
		emitter.Enabled = true
		emitter.Parent = part

		const renderOwner = { _adornee = root }
		const shadowOwner = { _adornee = root }
		visibility:SetRootCulled(renderOwner, root, "Render", true)
		visibility:SetRootCulled(shadowOwner, root, "Shadows", true)
		visibility:Step(100)
		expect(part.LocalTransparencyModifier).toEqual(1)
		expect(part.CastShadow).toEqual(false)
		expect(emitter.Enabled).toEqual(false)

		visibility:SetRootCulled(renderOwner, root, "Render", false)
		visibility:Step(100)
		expect(part.LocalTransparencyModifier).toEqual(0)
		expect(part.CastShadow).toEqual(false)
		expect(emitter.Enabled).toEqual(true)

		visibility:SetRootCulled(shadowOwner, root, "Shadows", false)
		visibility:Step(100)
		expect(part.CastShadow).toEqual(true)

		visibility:Destroy()
		transparencyService:Destroy()
		root:Destroy()
	end)

	it("restores descendants that leave a culled root", function()
		const transparencyService = createTransparencyService()
		const visibility = ClientCullingVisibilityState.new(transparencyService)
		const root = Instance.new("Model")
		const part = Instance.new("Part")
		part.Parent = root
		const owner = { _adornee = root }

		visibility:SetRootCulled(owner, root, "Render", true)
		visibility:Step(100)
		expect(part.LocalTransparencyModifier).toEqual(1)

		visibility:RemoveDescendant(owner, part)
		part.Parent = nil
		visibility:Step(100)
		expect(part.LocalTransparencyModifier).toEqual(0)

		visibility:Destroy()
		transparencyService:Destroy()
		part:Destroy()
		root:Destroy()
	end)

	it("does not apply queued hiding after a descendant leaves", function()
		const transparencyService = createTransparencyService()
		const visibility = ClientCullingVisibilityState.new(transparencyService)
		const root = Instance.new("Model")
		const part = Instance.new("Part")
		part.Parent = root
		const owner = { _adornee = root }

		visibility:SetRootCulled(owner, root, "Render", true)
		visibility:RemoveDescendant(owner, part)
		part.Parent = nil
		visibility:Step(100)
		expect(part.LocalTransparencyModifier).toEqual(0)

		visibility:Destroy()
		transparencyService:Destroy()
		part:Destroy()
		root:Destroy()
	end)

	it("invalidates stale queued mutations when state reverses", function()
		const transparencyService = createTransparencyService()
		const visibility = ClientCullingVisibilityState.new(transparencyService)
		const part = Instance.new("Part")
		const owner = { _adornee = part }

		visibility:SetRootCulled(owner, part, "Render", true)
		visibility:SetRootCulled(owner, part, "Render", false)
		visibility:SetRootCulled(owner, part, "Render", true)
		visibility:Step(100)
		expect(part.LocalTransparencyModifier).toEqual(1)

		visibility:Destroy()
		expect(part.LocalTransparencyModifier).toEqual(0)
		transparencyService:Destroy()
		part:Destroy()
	end)
end)
