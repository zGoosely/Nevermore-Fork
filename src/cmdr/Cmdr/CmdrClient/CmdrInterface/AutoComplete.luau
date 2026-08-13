--!strict
-- luacheck: ignore 212

local Players = game:GetService("Players")
local Player = Players.LocalPlayer

local CmdrInterfaceUtils = require(script.Parent.CmdrInterfaceUtils)

const AUTOCOMPLETE_EDGE_PADDING = 12
const AUTOCOMPLETE_MAX_HEIGHT = 190
const AUTOCOMPLETE_MAX_WIDTH = 320
const AUTOCOMPLETE_MIN_WIDTH = 220
const AUTOCOMPLETE_VERTICAL_GAP = 16
const DESCRIPTION_MAX_HEIGHT = 72
const SELECTED_TRANSPARENCY = 0.18

return function(Cmdr)
	local AutoComplete = {
		Items = {},
		ItemOptions = {},
		SelectedItem = 0,
	}

	local Util = Cmdr.Util

	local Gui = Player:WaitForChild("PlayerGui"):WaitForChild("Cmdr"):WaitForChild("Autocomplete")
	local AutoItem = Gui:WaitForChild("TextButton")
	local Title = Gui:WaitForChild("Title")
	local Description = Gui:WaitForChild("Description")
	local Entry = Gui.Parent:WaitForChild("Frame"):WaitForChild("Entry")
	local GhostText = Entry.TextBox:WaitForChild("GhostText")
	AutoItem.Parent = nil

	local defaultBarThickness = Gui.ScrollBarThickness
	local autocompleteContentWidth = AUTOCOMPLETE_MIN_WIDTH
	local autocompleteHorizontalOffset = 0

	function AutoComplete.GetCompletionText(self: any): string
		local item = self:GetSelectedItem()
		if not item then
			return Entry.TextBox.Text
		end

		return CmdrInterfaceUtils.getCompletionText(item, self.Command, self.Arg, self.NumArgs, self.IsPartial)
	end

	function AutoComplete.UpdateGhostText(self: any): ()
		if not Gui.Visible then
			GhostText.Text = ""
			return
		end

		local item = self:GetSelectedItem()
		if not item then
			GhostText.Text = ""
			return
		end

		const typedText = Entry.TextBox.Text
		const ghostCompletion = CmdrInterfaceUtils.getGhostCompletionText(typedText, item, self:GetCompletionText())
		GhostText.Text = CmdrInterfaceUtils.getGhostRichText(typedText, ghostCompletion)
	end

	-- Helper function that sets text and resizes labels
	local function SetText(obj, textObj, text, sizeFromContents)
		obj.Visible = text ~= nil
		textObj.Text = text or ""

		if sizeFromContents then
			textObj.Size = UDim2.new(
				0,
				Util.GetTextSize(text or "", textObj, Vector2.new(1000, 1000), 1, 0).X,
				obj.Size.Y.Scale,
				obj.Size.Y.Offset
			)
		end
	end

	const function updateContainerPosition()
		if not Gui.Visible then
			return
		end

		const desiredX = Entry.TextBox.AbsolutePosition.X + autocompleteHorizontalOffset
		const maxX = math.max(
			AUTOCOMPLETE_EDGE_PADDING,
			Gui.Parent.AbsoluteSize.X - Gui.AbsoluteSize.X - AUTOCOMPLETE_EDGE_PADDING
		)
		const xOffset = math.clamp(desiredX, AUTOCOMPLETE_EDGE_PADDING, maxX)
		const entryBottom = math.max(
			Entry.AbsolutePosition.Y + Entry.AbsoluteSize.Y,
			Entry.TextBox.AbsolutePosition.Y + Entry.TextBox.AbsoluteSize.Y
		)
		const yOffset = entryBottom + AUTOCOMPLETE_VERTICAL_GAP

		Gui.Position = UDim2.fromOffset(xOffset, yOffset)
	end

	const function updateContainerSize()
		updateContainerPosition()

		const maxAvailableWidth = math.max(1, Gui.Parent.AbsoluteSize.X - 2 * AUTOCOMPLETE_EDGE_PADDING)
		const width = math.min(
			math.max(Title.Field.TextBounds.X + Title.Field.Type.TextBounds.X + 28, autocompleteContentWidth),
			AUTOCOMPLETE_MAX_WIDTH,
			maxAvailableWidth
		)
		const availableHeight =
			math.max(0, Gui.Parent.AbsoluteSize.Y - Gui.AbsolutePosition.Y - AUTOCOMPLETE_EDGE_PADDING)
		const height = math.min(Gui.UIListLayout.AbsoluteContentSize.Y, AUTOCOMPLETE_MAX_HEIGHT, availableHeight)

		Gui.Size = UDim2.fromOffset(width, height)
		updateContainerPosition()
	end

	-- Update the info display (Name, type, and description) based on given options.
	local function UpdateInfoDisplay(options)
		-- Update the objects' text and sizes
		SetText(Title, Title.Field, options.name, true)
		SetText(
			Title.Field.Type,
			Title.Field.Type,
			options.type and ": " .. options.type:sub(1, 1):upper() .. options.type:sub(2)
		)
		SetText(Description, Description.Label, options.description)

		Description.Label.TextColor3 = options.invalid and Color3.fromRGB(255, 73, 73) or Color3.fromRGB(255, 255, 255)
		Description.Size = UDim2.new(1, 0, 0, 34)

		-- Flow description text
		while Description.Visible and not Description.Label.TextFits do
			Description.Size = Description.Size + UDim2.new(0, 0, 0, 2)

			if Description.Size.Y.Offset >= DESCRIPTION_MAX_HEIGHT then
				break
			end
		end

		-- Update container
		task.wait()
		Gui.UIListLayout:ApplyLayout()
		updateContainerSize()
		Gui.ScrollBarThickness = defaultBarThickness
	end

	--- Shows the auto complete menu with the given list and possible options
	-- item = {typedText, suggestedText, options?=options}
	-- The options table is optional. `at` should only be passed into AutoComplete::Show
	-- name, type, and description may be passed in an options dictionary inside the items as well
	-- options.at?: the character index at which to show the menu
	-- options.name?: The name to display in the info box
	-- options.type?: The type to display in the info box
	-- options.prefix?: The current type prefix (%Team)
	-- options.description?: The description for the currently active info box
	-- options.invalid?: If true, description is shown in red.
	-- options.isLast?: If true, auto complete won't keep going after this argument.
	function AutoComplete.Show(self: any, items: any, options: any): ()
		options = options or {}

		-- Remove old options.
		for _, item in pairs(self.Items) do
			if item.gui then
				item.gui:Destroy()
			end
		end

		-- Reset state
		self.SelectedItem = 1
		self.Items = items
		self.Prefix = options.prefix or ""
		self.LastItem = options.isLast or false
		self.Command = options.command
		self.Arg = options.arg
		self.NumArgs = options.numArgs
		self.IsPartial = options.isPartial

		-- Generate the new option labels
		local autocompleteWidth = AUTOCOMPLETE_MIN_WIDTH

		Gui.ScrollBarThickness = 0

		for i, item in pairs(self.Items) do
			local leftText = item[1]
			local rightText = item[2]

			local btn = AutoItem:Clone()
			btn.Name = leftText .. rightText
			btn.BackgroundTransparency = i == self.SelectedItem and SELECTED_TRANSPARENCY or 1

			local start, stop = string.find(rightText:lower(), leftText:lower(), 1, true)
			btn.Typed.Text = string.rep(" ", start - 1) .. leftText
			btn.Suggest.Text = string.sub(rightText, 0, start - 1)
				.. string.rep(" ", #leftText)
				.. string.sub(rightText, stop + 1)

			btn.Parent = Gui
			btn.LayoutOrder = i

			local maxBounds = math.max(btn.Typed.TextBounds.X, btn.Suggest.TextBounds.X) + 20
			if maxBounds > autocompleteWidth then
				autocompleteWidth = maxBounds
			end

			item.gui = btn
		end

		autocompleteWidth = math.min(
			autocompleteWidth,
			AUTOCOMPLETE_MAX_WIDTH,
			math.max(1, Gui.Parent.AbsoluteSize.X - 2 * AUTOCOMPLETE_EDGE_PADDING)
		)
		autocompleteContentWidth = autocompleteWidth
		Gui.UIListLayout:ApplyLayout()

		-- Todo: Use TextService to find accurate position for auto complete box
		local text = Entry.TextBox.Text
		local words = Util.SplitString(text)
		if text:sub(#text, #text) == " " and not options.at then
			words[#words + 1] = "e"
		end
		table.remove(words, #words)
		local extra = (options.at and options.at or (#table.concat(words, " ") + 1)) * 7

		autocompleteHorizontalOffset = extra
		Gui.Size = UDim2.fromOffset(autocompleteWidth, AUTOCOMPLETE_MAX_HEIGHT)
		Gui.Visible = true
		updateContainerSize()
		self:UpdateGhostText()

		-- Finally, update thge info display
		UpdateInfoDisplay(self.Items[1] and self.Items[1].options or options)
	end

	--- Returns the selected item in the auto complete
	function AutoComplete.GetSelectedItem(self: any): any
		if Gui.Visible == false then
			return nil
		end

		return self.Items[self.SelectedItem]
	end

	--- Hides the auto complete
	function AutoComplete.Hide(_self: any): ()
		Gui.Visible = false
		GhostText.Text = ""
	end

	--- Returns if the menu is visible
	function AutoComplete.IsVisible(_self: any): boolean
		return Gui.Visible
	end

	--- Changes the user's item selection by the given delta
	function AutoComplete.Select(self: any, delta: number): ()
		if not Gui.Visible then
			return
		end

		self.SelectedItem = self.SelectedItem + delta

		if self.SelectedItem > #self.Items then
			self.SelectedItem = 1
		elseif self.SelectedItem < 1 then
			self.SelectedItem = #self.Items
		end

		for i, item in pairs(self.Items) do
			item.gui.BackgroundTransparency = i == self.SelectedItem and SELECTED_TRANSPARENCY or 1
		end

		Gui.CanvasPosition = Vector2.new(
			0,
			math.max(
				0,
				Title.Size.Y.Offset
					+ Description.Size.Y.Offset
					+ self.SelectedItem * AutoItem.Size.Y.Offset
					- Gui.Size.Y.Offset
			)
		)

		if self.Items[self.SelectedItem] and self.Items[self.SelectedItem].options then
			UpdateInfoDisplay(self.Items[self.SelectedItem].options or {})
		end

		self:UpdateGhostText()
	end

	Gui.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContainerSize)
	Gui.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateContainerSize)
	Entry.TextBox:GetPropertyChangedSignal("AbsolutePosition"):Connect(updateContainerPosition)
	Entry.TextBox:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateContainerPosition)

	return AutoComplete
end
