--!strict

const RunService = game:GetService("RunService")
const Util = require(script.Shared:WaitForChild("Util"))

if RunService:IsServer() == false then
	error("Cmdr server module is somehow running on a client!")
end

local Cmdr
do
	Cmdr = setmetatable({
		ReplicatedRoot = nil,
		Network = nil,
		Util = Util,
		DefaultCommandsFolder = script.BuiltInCommands,
	}, {
		__index = function(self, k)
			local r = self.Registry[k]
			if r and type(r) == "function" then
				return function(_, ...)
					return r(self.Registry, ...)
				end
			end
		end,
	})

	Cmdr.Registry = require(script.Shared.Registry)(Cmdr)
	Cmdr.Dispatcher = require(script.Shared.Dispatcher)(Cmdr)

	require(script.Initialize)(Cmdr)
end

function Cmdr.SetNetwork(self: any, network: any): ()
	if self.Network == network then
		return
	end
	assert(self.Network == nil, "Cmdr network already configured")
	self.Network = network

	network.queries.execute.listen(function(request: { text: string, data: any? }, player: Player?): string
		if not player then
			return "Missing command executor"
		end
		if #request.text > network.MAX_COMMAND_LENGTH then
			return "Input too long"
		end

		return tostring(Cmdr.Dispatcher:EvaluateAndRun(request.text, player, {
			Data = request.data,
		}))
	end)
end

return Cmdr :: any
