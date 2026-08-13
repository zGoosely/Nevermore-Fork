--!strict

const ReplicatedStorage = game:GetService("ReplicatedStorage")

--- Handles initial preparation of the game server-side.
return function(cmdr: any): ()
	local replicatedRoot = script.Parent.CmdrClient

	local function create(class: string, name: string, parent: Instance?): Instance
		const object = Instance.new(class)
		object.Name = name
		object.Parent = parent or replicatedRoot

		return object
	end

	replicatedRoot.Parent = ReplicatedStorage
	create("Folder", "Commands")
	create("Folder", "Types")

	script.Parent.Shared.Parent = replicatedRoot

	cmdr.ReplicatedRoot = replicatedRoot

	cmdr:RegisterTypesIn(script.Parent.BuiltInTypes)

	script.Parent.BuiltInTypes:Destroy()
	script.Parent.BuiltInCommands.Name = "Server commands"
end
