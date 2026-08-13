--!strict
--[=[
	Constructs Cmdr's client interface with Blend.

	@util CmdrBlendGui
]=]

const require = require("../../Loader").load()

const Blend = require("Blend")
const Maid = require("Maid")
const Observable = require("Observable")
const t = require("t")

const HIDDEN_Y_OFFSET = 84
const VISIBLE_Y_OFFSET = 72

const CmdrBlendGui = {}

const function textLabel(name: string, text: string, font: Enum.Font, textSize: number)
	return Blend.New("TextLabel")({
		Name = name,
		AutomaticSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		Font = font,
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = Color3.fromRGB(235, 235, 235),
		TextSize = textSize,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

--[=[
	Mounts the Cmdr interface beneath the given PlayerGui.

	@within CmdrBlendGui
	@param parent PlayerGui
	@param percentVisible Observable<number>
	@param isVisible Observable<boolean>
	@return Maid
	@return ScreenGui
]=]
function CmdrBlendGui.mount(
	parent: PlayerGui,
	percentVisible: Observable.Observable<number>,
	isVisible: Observable.Observable<boolean>
): (Maid.Maid, ScreenGui)
	assert(t.instanceIsA("PlayerGui")(parent), "Bad parent")
	assert(Observable.isObservable(percentVisible), "Bad percentVisible")
	assert(Observable.isObservable(isVisible), "Bad isVisible")

	const oldGui = parent:FindFirstChild("Cmdr")
	if oldGui then
		oldGui:Destroy()
	end

	const shouldRender = Blend.Computed(isVisible, percentVisible, function(visible: boolean, percent: number): boolean
		return visible or percent > 0.001
	end)
	local screenGui = nil :: ScreenGui?

	const maid = Maid.new()
	maid:Add(Blend.New("ScreenGui")({
		Name = "Cmdr",
		AutoLocalize = false,
		DisplayOrder = 1000,
		Enabled = shouldRender,
		IgnoreGuiInset = true,
		Parent = parent,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,

		Blend.New("ScrollingFrame")({
			Name = "Frame",
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(15, 17, 22),
			BackgroundTransparency = Blend.Computed(percentVisible, function(percent: number): number
				return 1 - 0.92 * math.clamp(percent, 0, 1)
			end),
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			Position = Blend.Computed(percentVisible, function(percent: number): UDim2
				const clampedPercent = math.clamp(percent, 0, 1)
				const yOffset = HIDDEN_Y_OFFSET + (VISIBLE_Y_OFFSET - HIDDEN_Y_OFFSET) * clampedPercent
				return UDim2.new(0.025, 0, 0, yOffset)
			end),
			ScrollBarImageColor3 = Color3.fromRGB(105, 113, 130),
			ScrollBarThickness = 4,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Selectable = false,
			Size = UDim2.new(0.95, 0, 0, 0),
			Visible = shouldRender,

			Blend.New("UICorner")({ CornerRadius = UDim.new(0, 6) }),
			Blend.New("UIScale")({
				Scale = Blend.Computed(percentVisible, function(percent: number): number
					return 0.97 + 0.03 * math.clamp(percent, 0, 1)
				end),
			}),
			Blend.New("UIStroke")({
				Color = Color3.fromRGB(72, 78, 92),
				Transparency = 0.35,
				Thickness = 1,
			}),
			Blend.New("UIListLayout")({
				Name = "UIListLayout",
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Blend.New("UIPadding")({
				Name = "UIPadding",
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
				PaddingTop = UDim.new(0, 10),
			}),
			Blend.New("TextBox")({
				Name = "Line",
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				Font = Enum.Font.Code,
				Size = UDim2.new(1, 0, 0, 20),
				Text = "",
				TextColor3 = Color3.fromRGB(235, 235, 235),
				TextEditable = false,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Blend.New("Frame")({
				Name = "Entry",
				BackgroundTransparency = 1,
				LayoutOrder = 1_000_000,
				Size = UDim2.new(1, 0, 0, 22),

				Blend.New("UIListLayout")({
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 7),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Blend.New("TextLabel")({
					Name = "TextLabel",
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					Font = Enum.Font.Code,
					Size = UDim2.fromOffset(0, 22),
					Text = "",
					TextColor3 = Color3.fromRGB(255, 211, 92),
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Blend.New("TextBox")({
					Name = "TextBox",
					BackgroundTransparency = 1,
					ClearTextOnFocus = false,
					Font = Enum.Font.Code,
					LayoutOrder = 1_000_000,
					Size = UDim2.new(1, 0, 0, 22),
					Text = "",
					TextColor3 = Color3.fromRGB(245, 245, 245),
					TextSize = 14,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 2,

					Blend.New("TextLabel")({
						Name = "GhostText",
						BackgroundTransparency = 1,
						Font = Enum.Font.Code,
						RichText = true,
						Size = UDim2.fromScale(1, 1),
						Text = "",
						TextSize = 14,
						TextXAlignment = Enum.TextXAlignment.Left,
						ZIndex = 3,
					}),
				}),
			}),
		}),

		Blend.New("ScrollingFrame")({
			Name = "Autocomplete",
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Color3.fromRGB(22, 24, 30),
			BackgroundTransparency = 0.02,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			ClipsDescendants = true,
			Position = UDim2.fromOffset(167, 75),
			ScrollBarImageColor3 = Color3.fromRGB(105, 113, 130),
			ScrollBarThickness = 4,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Selectable = false,
			Size = UDim2.fromOffset(220, 190),
			Visible = false,
			ZIndex = 10,

			Blend.New("UICorner")({ CornerRadius = UDim.new(0, 8) }),
			Blend.New("UIStroke")({
				Color = Color3.fromRGB(72, 78, 92),
				Transparency = 0.25,
				Thickness = 1,
			}),
			Blend.New("UIListLayout")({
				Name = "UIListLayout",
				Padding = UDim.new(0, 1),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Blend.New("Frame")({
				Name = "Title",
				BackgroundColor3 = Color3.fromRGB(42, 46, 57),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				LayoutOrder = -2,
				Size = UDim2.new(1, 0, 0, 34),

				Blend.New("UIPadding")({ PaddingLeft = UDim.new(0, 10) }),
				Blend.New("TextLabel")({
					Name = "Field",
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					Font = Enum.Font.SourceSansBold,
					Size = UDim2.fromOffset(0, 34),
					Text = "",
					TextColor3 = Color3.fromRGB(245, 245, 245),
					TextSize = 18,
					TextXAlignment = Enum.TextXAlignment.Left,

					Blend.New("TextLabel")({
						Name = "Type",
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Font = Enum.Font.SourceSans,
						Position = UDim2.fromScale(1, 0),
						Size = UDim2.fromOffset(0, 34),
						Text = "",
						TextColor3 = Color3.fromRGB(174, 181, 198),
						TextSize = 13,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
				}),
			}),
			Blend.New("Frame")({
				Name = "Description",
				BackgroundColor3 = Color3.fromRGB(42, 46, 57),
				BackgroundTransparency = 0.1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				LayoutOrder = -1,
				Size = UDim2.new(1, 0, 0, 20),

				Blend.New("UIPadding")({
					PaddingBottom = UDim.new(0, 10),
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				}),
				Blend.New("TextLabel")({
					Name = "Label",
					BackgroundTransparency = 1,
					Font = Enum.Font.SourceSansLight,
					Size = UDim2.fromScale(1, 1),
					Text = "",
					TextColor3 = Color3.fromRGB(235, 235, 235),
					TextSize = 16,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),
			}),
			Blend.New("TextButton")({
				Name = "TextButton",
				BackgroundColor3 = Color3.fromRGB(61, 68, 84),
				BackgroundTransparency = 0.18,
				BorderSizePixel = 0,
				Font = Enum.Font.Code,
				Size = UDim2.new(1, 0, 0, 28),
				Text = "",
				ZIndex = 11,

				Blend.New("UICorner")({ CornerRadius = UDim.new(0, 4) }),
				Blend.New("UIPadding")({ PaddingLeft = UDim.new(0, 10) }),
				textLabel("Suggest", "", Enum.Font.Code, 13),
				Blend.New("TextLabel")({
					Name = "Typed",
					BackgroundTransparency = 1,
					Font = Enum.Font.Code,
					Size = UDim2.fromScale(1, 1),
					Text = "",
					TextColor3 = Color3.fromRGB(131, 222, 255),
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 12,
				}),
			}),
		}),
	}):Subscribe(function(instance: Instance)
		screenGui = instance :: ScreenGui
	end))

	return maid, assert(screenGui, "Cmdr ScreenGui was not mounted")
end

return CmdrBlendGui
