--!strict
--[=[
	Provides the client-rendered models used by SimulatedCharacterService.

	Template containers are discovered through the shared CollectionService tag
	owned by SimulatedCharacterConstants.

	@class SimulatedCharacterTemplateProvider
]=]

const require = require("../Loader").load()

const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const TaggedTemplateProvider = require("TaggedTemplateProvider")

return TaggedTemplateProvider.new(script.Name, SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG)
