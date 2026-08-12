--!strict
--[=[
	Provides shared, named post-processing effects for the local client.

	@class PostProcessingStackService
	@client
]=]

const require = require("../../Loader").load()

const LightingEffect = require("LightingEffect")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const t = require("t")

const PostProcessingStackService = {}
PostProcessingStackService.ServiceName = "PostProcessingStackService"

export type PostProcessingStackService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_effectsByName: { [string]: LightingEffect.LightingEffect },
	},
	{} :: typeof({ __index = PostProcessingStackService })
))

function PostProcessingStackService.Init(self: PostProcessingStackService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._effectsByName = {}
end

--[=[
	Returns the shared effect with the given name, creating it when necessary.

	@within PostProcessingStackService
	@param name string
	@param className string
	@return LightingEffect
]=]
function PostProcessingStackService.GetOrCreateEffect(
	self: PostProcessingStackService,
	name: string,
	className: string
): LightingEffect.LightingEffect
	assert(t.string(name) and name ~= "", "Bad name")
	assert(t.string(className) and className ~= "", "Bad className")

	const existing = self._effectsByName[name]
	if existing then
		assert(
			existing:GetClassName() == className,
			string.format("Effect %q already uses class %q", name, existing:GetClassName())
		)
		return existing
	end

	const effect = self._maid:Add(LightingEffect.new(name, className))
	self._effectsByName[name] = effect

	return effect
end

function PostProcessingStackService.Destroy(self: PostProcessingStackService): ()
	self._maid:DoCleaning()
	table.clear(self._effectsByName)
end

return PostProcessingStackService
