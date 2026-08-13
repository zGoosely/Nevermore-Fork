--!strict
--[=[
	Provides the client-rendered models used by SimulatedCharacterService.

	Template containers are discovered through the shared CollectionService tag
	owned by SimulatedCharacterConstants.

	@class SimulatedCharacterTemplateProvider
]=]
const SimulatedCharacterConstants = require("./Shared/SimulatedCharacterConstants")
const TaggedTemplateProvider = require("@game/ReplicatedStorage/Packages/TaggedTemplateProvider")

return TaggedTemplateProvider.new(script.Name, SimulatedCharacterConstants.TEMPLATE_CONTAINER_TAG)
