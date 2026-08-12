--!strict
--[=[
	Unit tests for shared named post-processing effects.

	@class PostProcessingStackService.spec
]=]

const require = require("../../Loader").load()

const Jest = require("Jest")
const ServiceBag = require("ServiceBag")
const PostProcessingStackService = require("PostProcessingStackService")

const describe = Jest.Globals.describe
const expect = Jest.Globals.expect
const it = Jest.Globals.it

local function createService(): (PostProcessingStackService.PostProcessingStackService, ServiceBag.ServiceBag)
	const serviceBag = ServiceBag.new()
	const service: PostProcessingStackService.PostProcessingStackService =
		serviceBag:GetService(PostProcessingStackService)
	serviceBag:Init()
	return service, serviceBag
end

describe("PostProcessingStackService", function()
	it("shares named effects and cleans them up with the service", function()
		const service, serviceBag = createService()
		const first = service:GetOrCreateEffect("PostProcessingSharedSpec", "BlurEffect")
		const second = service:GetOrCreateEffect("PostProcessingSharedSpec", "BlurEffect")

		expect(second).toEqual(first)
		expect(first:GetInstance().Parent).toEqual(game:GetService("Lighting"))

		serviceBag:Destroy()
		expect(first:GetInstance().Parent).toEqual(nil)
	end)

	it("rejects changing the class of an existing named effect", function()
		const service, serviceBag = createService()
		service:GetOrCreateEffect("PostProcessingClassSpec", "BlurEffect")

		expect(function()
			service:GetOrCreateEffect("PostProcessingClassSpec", "BloomEffect")
		end).toThrow()

		serviceBag:Destroy()
	end)
end)
