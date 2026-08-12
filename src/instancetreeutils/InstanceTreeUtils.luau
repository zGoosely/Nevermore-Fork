--[[
	Creates instances with given properties based on the given tree data table.
	This streamlines the tedious process of calling Instance.new and setting each property
	by creating a table of properties and a ClassName instead.
--]]

type PropertiesTable = { [string]: any }

type InstanceTree = {
	className: string,
	properties: PropertiesTable?,
	children: { InstanceTree }?,
}

local InstanceTreeUtils = {}

local function iteratePathSegments(...: string)
	local segments = {}

	for _, path in ipairs({ ... }) do
		for _, segment in ipairs(string.split(path, '/')) do
			if segment ~= '' then
				table.insert(segments, segment)
			end
		end
	end

	return segments
end

function InstanceTreeUtils.getInstance<T>(instance: Instance, ...: string): T
	for _, childName in ipairs(iteratePathSegments(...)) do
		local child = instance:FindFirstChild(childName)
		assert(child, string.format('%s is not a child of %s', childName, instance:GetFullName()))
		instance = child
	end

	-- We want this function to be callable with generic types
	return (instance :: any) :: T
end

function InstanceTreeUtils.createInstanceTree<T>(tree: InstanceTree): T
	local object = Instance.new(tree.className)

	if tree.properties then
		for property, value in pairs(tree.properties :: PropertiesTable) do
			assert(property ~= 'Parent', 'Cannot set Parent as property through createInstanceTree')
			object[property] = value
		end
	end

	if tree.children then
		for _, childTree in ipairs(tree.children :: { InstanceTree }) do
			local childObject = InstanceTreeUtils.createInstanceTree(childTree)
			childObject.Parent = object
		end
	end

	return object :: T | any
end

return InstanceTreeUtils
