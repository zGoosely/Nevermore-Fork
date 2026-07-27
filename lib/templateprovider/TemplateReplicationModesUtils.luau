--!strict
--[=[
	Utilities for resolving the active [TemplateProvider] replication mode.

	@util TemplateReplicationModesUtils
]=]

const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const TemplateReplicationModes = require("TemplateReplicationModes")

const TemplateReplicationModesUtils = {}

--[=[
	Returns the replication mode for the current runtime.

	@within TemplateReplicationModesUtils
	@return TemplateReplicationMode
]=]
function TemplateReplicationModesUtils.inferReplicationMode(): TemplateReplicationModes.TemplateReplicationMode
	if not RunService:IsRunning() then
		return TemplateReplicationModes.SHARED
	elseif RunService:IsServer() then
		return TemplateReplicationModes.SERVER
	elseif RunService:IsClient() then
		return TemplateReplicationModes.CLIENT
	else
		return TemplateReplicationModes.SHARED
	end
end

return TemplateReplicationModesUtils
