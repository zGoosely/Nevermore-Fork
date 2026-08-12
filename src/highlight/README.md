# AnimatedHighlight

The highlight package creates spring-animated Roblox `Highlight` instances on the
client. `HighlightServiceClient` is the normal entry point: it shares one
`AnimatedHighlightGroup`, stacks competing highlight requests per adornee, and
shows the request with the highest score.

## Setup

Register the service in the client ServiceBag:

```luau
const HighlightServiceClient = require("HighlightServiceClient")
const ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()
local highlights = serviceBag:GetService(HighlightServiceClient)

serviceBag:Init()
serviceBag:Start()
```

This package is visual and client-only. It does not replicate highlight state
from the server.

## Highlighting an object

`Highlight()` returns an `AnimatedHighlightModel`. Keep that model alive for as
long as the request should exist, and destroy it to remove the request:

```luau
local handle = maid:Add(highlights:Highlight(workspace.Enemy, 10))

handle:SetFillColor(Color3.fromRGB(255, 70, 70))
handle:SetOutlineColor(Color3.new(1, 1, 1))
handle:SetFillTransparency(0.45)
handle:SetOutlineTransparency(0)
handle:SetHighlightDepthMode(Enum.HighlightDepthMode.AlwaysOnTop)
handle:SetSpeed(20)
handle:SetColorSpeed(40)
handle:SetTransparencySpeed(40)

-- Removing the handle lets the stack fall back to the next request and then
-- animates the Highlight out when no requests remain.
handle:Destroy()
```

The adornee can be a `Model`, `BasePart`, or any other Instance accepted by a
Roblox `Highlight`.

## Priority stacking

Multiple systems can request a highlight for the same adornee. The highest score
wins without either system needing to know about the other:

```luau
local hoverHandle = maid:Add(highlights:Highlight(enemy, 10))
hoverHandle:SetFillColor(Color3.fromRGB(255, 220, 80))

local targetHandle = maid:Add(highlights:Highlight(enemy, 100))
targetHandle:SetFillColor(Color3.fromRGB(255, 60, 60))

-- The target style is visible. Destroying it reveals the hover style.
targetHandle:Destroy()
```

The score may also be an `Observable<number>`, allowing priority to change
without replacing the handle:

```luau
const ValueObject = require("ValueObject")

local score = maid:Add(ValueObject.new(0))
local handle = maid:Add(highlights:Highlight(enemy, score:Observe()))

score.Value = 100
```

Omitting the score uses `0`.

## Group defaults

Configure defaults once when every new handle should begin with the same style:

```luau
local group = highlights:GetAnimatedHighlightGroup()

group:SetDefaultHighlightDepthMode(Enum.HighlightDepthMode.Occluded)
group:SetDefaultFillColor(Color3.fromRGB(80, 170, 255))
group:SetDefaultOutlineColor(Color3.new(1, 1, 1))
group:SetDefaultFillTransparency(0.6)
group:SetDefaultOutlineTransparency(0)
group:SetDefaultTransparencySpeed(30)
group:SetDefaultSpeed(18)
```

Per-handle values override these defaults. Setting a model property to `nil`
causes the active stack entry to inherit the group default again.

## Transferring a highlight

The shared group can transfer the current animated appearance between adornees,
which avoids a visual pop when replacing a model:

```luau
local group = highlights:GetAnimatedHighlightGroup()
local replacementHandle = maid:Add(group:HighlightWithTransferredProperties(
	oldCharacter,
	newCharacter,
	100
))
```

## Low-level AnimatedHighlight

Use `AnimatedHighlight` directly only when stacking is unnecessary:

```luau
const AnimatedHighlight = require("AnimatedHighlight")

local highlight = AnimatedHighlight.new()
highlight:SetAdornee(enemy)
highlight:SetFillColor(Color3.fromRGB(255, 80, 80), true)
highlight:SetOutlineTransparency(0)
highlight:Show()

highlight:Finish(false, function()
	highlight:Destroy()
end)
```

The second argument accepted by color and transparency setters skips spring
animation and applies the value immediately. `Show()`, `Hide()`, and `Destroy()`
come from `BasicPane`.
