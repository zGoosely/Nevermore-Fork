--!strict
--[=[
	Creates a [TemplateProvider] backed by CollectionService tags.

	@class TaggedTemplateProvider
]=]

const require = require("../Loader").load()

const RxCollectionServiceUtils = require("RxCollectionServiceUtils")
const TemplateProvider = require("TemplateProvider")

const TaggedTemplateProvider = {}

--[=[
	Constructs a template provider containing every instance with the given tag.

	@within TaggedTemplateProvider
	@param providerName string
	@param tagName string
	@return TemplateProvider
]=]
function TaggedTemplateProvider.new(providerName: string, tagName: string): TemplateProvider.TemplateProvider
	assert(type(providerName) == "string", "Bad providerName")
	assert(type(tagName) == "string", "Bad tagName")

	return TemplateProvider.new(providerName, RxCollectionServiceUtils.observeTaggedBrio(tagName))
end

return TaggedTemplateProvider
