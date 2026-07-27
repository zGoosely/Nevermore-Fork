# FakeSkybox

`FakeSkybox` renders a client-side sky from six camera-centered parts, plus
separate sun and moon parts. Unlike a normal `Sky`, it can spring-fade in and
out, which makes it useful for transitions, local sky overrides, cutscenes, and
preview cameras.

The package is client-only and does not use a ServiceBag. Create and own each
`FakeSkybox` directly.

## Basic setup

```luau
const FakeSkybox = require("FakeSkybox")

local fakeSkybox = maid:Add(FakeSkybox.new())
fakeSkybox.Gui.Parent = workspace
fakeSkybox:Show()
```

New instances automatically observe:

- `workspace.CurrentCamera`
- The topmost `Sky` parented to `Lighting`
- The topmost `Atmosphere` parented to `Lighting`
- `Lighting.ClockTime`, `GeographicLatitude`, and
  `EnvironmentDiffuseScale`

The fake sky starts hidden. Call `Show()` to fade it in, `Hide()` to fade it
out, or pass `true` to either method to apply visibility immediately:

```luau
fakeSkybox:Show(true)
fakeSkybox:Hide(true)
```

Parent `Gui` to `workspace` so its rendered parts are visible. Destroying the
`FakeSkybox` cleans up the folder, parts, subscriptions, and mounted values.

## Rendering a specific Sky

Pass any `Sky` instance to `SetSky()`. It does not need to be parented to
`Lighting`, so a client can keep several sky presets in a template folder and
select one without changing global Lighting state.

```luau
local sky = Instance.new("Sky")
sky.SkyboxBk = "rbxassetid://123456"
sky.SkyboxDn = "rbxassetid://123457"
sky.SkyboxFt = "rbxassetid://123458"
sky.SkyboxLf = "rbxassetid://123459"
sky.SkyboxRt = "rbxassetid://123460"
sky.SkyboxUp = "rbxassetid://123461"
sky.SunTextureId = "rbxassetid://123462"
sky.MoonTextureId = "rbxassetid://123463"

maid:Add(sky)
maid:Add(fakeSkybox:SetSky(sky))
```

Changes to the Sky's texture, angular-size, celestial-body, and orientation
properties are observed while it is mounted. Calling `SetSky(nil)` resumes
tracking the `Sky` in `Lighting`; it does not select an empty sky.

Use `SetAtmosphere()` in the same way when the selected sky should sample a
specific `Atmosphere` rather than the one in `Lighting`:

```luau
local atmosphere = Instance.new("Atmosphere")
atmosphere.Density = 0.35

maid:Add(atmosphere)
maid:Add(fakeSkybox:SetAtmosphere(atmosphere))
```

The Atmosphere's density influences celestial-body sizing. The package does not
clone or render all Atmosphere effects itself.

## Transitioning between skyboxes

Use two instances when both skies need to be visible during a crossfade:

```luau
local function createSkybox(sky: Sky): FakeSkybox.FakeSkybox
	local skybox = FakeSkybox.new()
	skybox.Gui.Parent = workspace
	skybox:SetSky(sky)
	skybox:SetSpeed(20)
	skybox:Hide(true)
	return skybox
end

local outgoing = createSkybox(daySky)
local incoming = createSkybox(nightSky)

outgoing:Show(true)

-- Start the crossfade.
outgoing:Hide()
incoming:Show()

-- Own both with a Maid and destroy the outgoing instance once your transition
-- window has finished.
```

`SetSpeed()` controls the visibility spring. Higher values settle more quickly;
the default is `30`.

## Render methods

The default renderer is `SURFACEGUI`:

```luau
const FakeSkyboxRenderMethod = require("FakeSkyboxRenderMethod")

fakeSkybox:SetRenderMethod(FakeSkyboxRenderMethod.SURFACEGUI)
```

| Method | Behavior | Best use |
| --- | --- | --- |
| `SURFACEGUI` | Uses an `ImageLabel` and supports vertical color gradients and brightness | Normal rendering and sky transitions |
| `DECAL` | Uses a `Decal`, approximates gradient tint with one color, and compensates for decal render-distance limits | A fallback when SurfaceGui rendering is undesirable |

Decal mode substitutes compatible textures for Roblox's built-in sun and moon
images. Prefer SurfaceGui unless a specific visual or engine limitation requires
Decals.

## Using another camera

The sky follows `workspace.CurrentCamera` by default. A viewport, menu, replay,
or cutscene system can bind it to another Camera:

```luau
maid:Add(fakeSkybox:SetCamera(cutsceneCamera))
```

Only the camera position centers the sky geometry. The camera's own rotation
does not rotate the cube. Calling `SetCamera(nil)` resumes tracking
`workspace.CurrentCamera`, including future CurrentCamera replacements.

## Reactive configuration

Properties that accept a `ValueObject.Mountable<T>` can receive a static value,
`ValueObject`, or compatible Observable. This is useful when another system
already owns the current sky preset:

```luau
const ValueObject = require("ValueObject")

local activeSky = maid:Add(ValueObject.new(daySky))
maid:Add(fakeSkybox:SetSky(activeSky))

activeSky.Value = stormSky
```

The same pattern works with `SetCamera()`, `SetAtmosphere()`, `SetPartSize()`,
`SetRenderMethod()`, and `SetViewportLightingArgs()`.

`SetViewportLightingArgs()` is an advanced override for the
`SunPositionUtils.ViewportLightingArgs` used to calculate the sky gradient and
sun appearance. Leave the default in place when the fake sky should follow
Lighting normally.

## Common use cases

- Crossfade between day, night, weather, or biome skies.
- Give an interior, portal, or isolated map zone a local sky without changing
  the server's `Lighting.Sky`.
- Keep a cutscene or replay sky centered on its own camera.
- Render a controlled sky behind a character, item, or map preview.
- Let each client choose accessibility or graphics-specific sky presentation.

FakeSkybox is visual only. Gameplay that depends on time of day or weather
should continue to use authoritative game state instead of inferring it from the
currently rendered preset.

## API

### `FakeSkybox.new()`

Creates a hidden FakeSkybox that tracks the current Lighting Sky, Atmosphere,
and camera.

### `SetSky(sky)`

Mounts a `Sky`, ValueObject, or Observable. Pass `nil` to follow Lighting again.

### `SetAtmosphere(atmosphere)`

Mounts an `Atmosphere`, ValueObject, or Observable. Pass `nil` to follow
Lighting again.

### `SetCamera(camera)`

Mounts a `Camera`, ValueObject, or Observable. Pass `nil` to follow
`workspace.CurrentCamera` again.

### `SetPartSize(width)`

Sets the width of each skybox face in studs. The default is `2000`, matching the
maximum size expected by the implementation.

### `SetSpeed(speed)`

Sets the visibility spring speed. The default is `30`.

### `SetRenderMethod(renderMethod)`

Selects `FakeSkyboxRenderMethod.SURFACEGUI` or
`FakeSkyboxRenderMethod.DECAL`.

### `SetViewportLightingArgs(args)`

Overrides the viewport-lighting values used for gradients and celestial-body
presentation.

### `ObserveBrightness()`

Returns an `Observable<number>` for the calculated sky brightness:

```luau
maid:Add(fakeSkybox:ObserveBrightness():Subscribe(function(brightness)
	print("Sky brightness", brightness)
end))
```

### `Show()`, `Hide()`, and `SetVisible()`

Control visibility through the inherited `BasicPane` API.

### `Destroy()`

Cleans up the FakeSkybox and its rendered Instances. As with the other APIs in
this project, `Destroy()` is the final lifecycle operation.
