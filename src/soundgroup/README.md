# SoundGroup

`SoundGroup` manages the Roblox `SoundService` hierarchy as named dot-separated
paths. It creates standard audio categories, routes sounds into those categories,
applies reversible effects, tracks hierarchy changes reactively, and provides
stackable volume modifiers.

The package complements SoundPlayer:

- SoundGroup answers **where is this sound routed, and what category-wide volume
  or effects apply?**
- SoundPlayer answers **which sound is playing, when does it swap, and how does it
  fade or loop?**

## Default hierarchy

`SoundGroupService` creates this hierarchy when the server ServiceBag starts:

```text
SoundService
└── Master
    ├── SoundEffects
    ├── Music
    └── Voice
```

The matching paths from `WellKnownSoundGroups` are:

| Constant | Path |
| --- | --- |
| `MASTER` | `Master` |
| `SFX` | `Master.SoundEffects` |
| `MUSIC` | `Master.Music` |
| `VOICE` | `Master.Voice` |

Paths are exact dot-separated names. `Master.Music.Combat` represents a
`Combat` SoundGroup beneath `Music`.

## Package children

| Module | Responsibility |
| --- | --- |
| `Server/SoundGroupService` | Initializes dependencies and creates the standard Master/SFX/Music/Voice hierarchy. |
| `Client/SoundGroupServiceClient` | Initializes Tie, RogueProperty, and `SoundEffectService` on the client. |
| `Shared/SoundEffectService` | Main public service for routing, path lookup/creation, effects, and volume multipliers. |
| `Shared/Utils/SoundGroupPathUtils` | Parses paths and finds or creates nested SoundGroups. |
| `Shared/Groups/WellKnownSoundGroups` | Frozen table of standard category paths. |
| `Shared/SoundGroupTracker` | Reactively indexes SoundGroups by path and updates when groups are added, removed, moved, or renamed. |
| `Shared/Effects/SoundEffectsRegistry` | Maps an exact path to a reactive `SoundEffectsList`. |
| `Shared/Effects/SoundEffectsList` | Owns effect callbacks and applies/removes them for active Sound or SoundGroup instances. |
| `Shared/Volume/SoundGroupVolume` | Binder class that writes a computed RogueProperty volume to a SoundGroup. |
| `Shared/Volume/SoundGroupVolumeProperties` | Declares the `Volume` RogueProperty table. |
| `Shared/Volume/SoundGroupVolumeInterface` | Tie interface exposing `CreateMultiplier()` from bound volume objects. |

## Service setup

Server:

```luau
const require = require("../Loader").load()

const ServiceBag = require("ServiceBag")
const SoundGroupService = require("SoundGroupService")

local serviceBag = ServiceBag.new()
serviceBag:GetService(SoundGroupService)
serviceBag:Init()
serviceBag:Start()
```

Client:

```luau
const require = require("../Loader").load()

const ServiceBag = require("ServiceBag")
const SoundGroupServiceClient = require("SoundGroupServiceClient")

local serviceBag = ServiceBag.new()
serviceBag:GetService(SoundGroupServiceClient)
serviceBag:Init()
serviceBag:Start()
```

Both services initialize `SoundEffectService`. Retrieve that shared service when
gameplay code needs to work with paths:

```luau
const SoundEffectService = require("SoundEffectService")

local soundEffects = serviceBag:GetService(SoundEffectService)
```

## Finding and creating SoundGroups

`GetOrCreateSoundGroup()` walks the path from `SoundService`, reuses matching
SoundGroups, and creates missing ones:

```luau
local combatMusic = soundEffects:GetOrCreateSoundGroup(
	"Master.Music.Combat"
)
```

`GetSoundGroup()` returns the current group or `nil` without intentionally
creating the path:

```luau
local voice = soundEffects:GetSoundGroup("Master.Voice")
```

Both methods tag discovered groups with the `SoundGroupVolume` binder so their
effective volume can be modified through RogueProperty.

For lower-level or custom-root work, use `SoundGroupPathUtils`:

```luau
const SoundGroupPathUtils = require("SoundGroupPathUtils")

local names = SoundGroupPathUtils.toPathTable("Master.Music.Combat")
-- { "Master", "Music", "Combat" }

local found = SoundGroupPathUtils.findSoundGroup("Music.Combat", customRoot)
local made = SoundGroupPathUtils.findOrCreateSoundGroup("Music.Combat", customRoot)
```

The utility currently treats any string as a path, so application code should
avoid empty components and periods inside actual SoundGroup names.

## Routing sounds

Assign a sound to the standard SFX category:

```luau
local sound = Instance.new("Sound")
sound.SoundId = "rbxassetid://SOUND_ID"

soundEffects:RegisterSFX(sound)
sound.Parent = workspace
sound:Play()
```

Pass a custom path when the sound needs a more specific category:

```luau
soundEffects:RegisterSFX(sound, "Master.SoundEffects.Weapons")
```

`RegisterSFX()` creates the target SoundGroup if needed and sets
`sound.SoundGroup`. It does not parent, play, or destroy the sound.

For non-SFX audio, assign the group directly:

```luau
const WellKnownSoundGroups = require("WellKnownSoundGroups")

local musicGroup = soundEffects:GetOrCreateSoundGroup(
	WellKnownSoundGroups.MUSIC
)
musicSound.SoundGroup = musicGroup
```

## Volume modifiers

The authored `SoundGroup.Volume` is treated as the base value. Create a temporary
multiplier to change the computed volume without losing that base:

```luau
soundEffects:PromiseCreateVolumeMultiplier("Master.Music")
	:Then(function(multiplier)
		multiplier.Value = 0.35
		maid:Add(multiplier)
	end)
	:Catch(warn)
```

The returned object is a `NumberValue` RogueMultiplier. Multiple multipliers
compose, so `0.5` and `0.8` produce `baseVolume * 0.5 * 0.8`.

Destroy or unparent the returned NumberValue to remove its contribution. Keeping
it in a Maid is the safest ownership pattern:

```luau
local duckingMultiplier

soundEffects:PromiseCreateVolumeMultiplier("Master.Music"):Then(function(value)
	value.Value = 0.25
	duckingMultiplier = maid:Add(value)
end)

-- Later, when dialogue ends:
if duckingMultiplier then
	duckingMultiplier:Destroy()
end
```

Typical uses include settings volume, dialogue ducking, underwater muffling,
temporary silence, and zone-based ambience gain.

The volume layer depends on Tie and RogueProperty:

```text
SoundGroupVolume binder
       │
       ├── RogueProperty Volume (base + modifiers)
       ├── Tie CreateMultiplier interface
       └── writes computed value → SoundGroup.Volume
```

## Registering reversible effects

`PushEffect()` registers an applier for one exact path. The applier receives each
matching SoundGroup and must return a Maid-compatible cleanup task:

```luau
local removeUnderwaterEffect = soundEffects:PushEffect(
	"Master.SoundEffects",
	function(instance)
		local equalizer = Instance.new("EqualizerSoundEffect")
		equalizer.HighGain = -18
		equalizer.MidGain = -8
		equalizer.LowGain = 2
		equalizer.Parent = instance

		return equalizer
	end
)

maid:Add(removeUnderwaterEffect)
```

Returning the created instance is enough because Maid destroys Instances. You
may instead return a function, connection, Maid, or any other valid Maid task.
Returning `nil` produces a warning because the registry cannot undo that effect.

The registry is reactive in both directions:

- Adding an effect applies it to matching active groups.
- Creating or discovering a matching group applies existing effects.
- Removing the effect registration runs every per-instance cleanup task.
- Destroying an affected instance releases its application automatically.

Effects are registered by exact path. An effect callback registered at
`Master.Music` is not separately invoked for `Master.Music.Combat`. Roblox's own
nested SoundGroup processing may still make a parent group's effects audible to
descendant routing.

## Applying effects to an individual Sound

`ApplyEffects()` applies the current effect list for a path to one Sound or
SoundGroup without changing its routing:

```luau
local removeEffects = soundEffects:ApplyEffects(
	"Master.SoundEffects.Weapons",
	gunshotSound
)

maid:Add(removeEffects)
```

This is useful when an effect should be attached directly to a runtime Sound
rather than to the category group. The returned cleanup stops tracking the
instance and removes every attached effect task.

## Observing the hierarchy

`SoundGroupTracker` is the package's reactive index. It recursively watches
SoundGroup children, builds their dot paths, and updates those paths when names
or ancestors change:

```luau
const SoundGroupTracker = require("SoundGroupTracker")

local tracker = maid:Add(SoundGroupTracker.new(game:GetService("SoundService")))

maid:Add(tracker:ObserveSoundGroup("Master.Music"):Subscribe(function(group)
	print("Current music group", group)
end))
```

Its public operations are:

| Method | Purpose |
| --- | --- |
| `GetFirstSoundGroup(path)` | Returns the first currently indexed group at a path. |
| `ObserveSoundGroup(path)` | Observes the first group or `nil`. |
| `ObserveSoundGroupBrio(path)` | Observes the first group with explicit lifetime. |
| `ObserveSoundGroupsBrio()` | Observes every tracked SoundGroup. |
| `ObserveSoundGroupPath(group)` | Observes the current path for one group. |
| `Track(parent)` | Adds another recursively watched root and returns cleanup. |

The tracker stores a list per path because duplicate names can exist in the data
model. High-level lookup consistently uses the first indexed group.

## Effects internals

`SoundEffectsRegistry` creates one `SoundEffectsList` per used path. A list stays
active while it has registered effects or while effects are applied to at least
one instance. Once both counts reach zero, the registry can release it.

`SoundEffectsList` exposes:

| Method | Purpose |
| --- | --- |
| `PushEffect(applier)` | Adds a reactive effect and returns removal cleanup. |
| `ApplyEffects(instance)` | Applies all current/future effects to an instance and returns cleanup. |
| `HasEffects()` | Reports whether any appliers are registered. |
| `ObserveHasEffects()` | Observes registration presence. |
| `IsActive()` | Reports whether the list has effects or active applications. |

Most game code should use `SoundEffectService` rather than constructing these
internal collections directly.

## SoundEffectService API summary

| Method | Purpose |
| --- | --- |
| `RegisterSFX(sound, path?)` | Assigns a sound to SFX or a custom category. |
| `GetOrCreateSoundGroup(path)` | Returns the path's SoundGroup, creating missing levels. |
| `GetSoundGroup(path)` | Returns the current group or `nil`. |
| `PromiseCreateVolumeMultiplier(path)` | Resolves with a temporary NumberValue multiplier. |
| `PushEffect(path, applier)` | Registers a reversible effect for a path. |
| `ApplyEffects(path, instance)` | Applies a path's effects directly to one Sound or SoundGroup. |

## Ownership and practical constraints

- SoundGroup does not play sounds; it routes and transforms them.
- Keep effect-registration cleanups and volume modifier Instances in a Maid.
- An effect callback should always return valid cleanup.
- Path matching in the registry is exact.
- Avoid periods inside SoundGroup names because periods delimit the hierarchy.
- The server creates the default hierarchy, while both runtimes can query and
  react to it.
- RogueProperty owns computed volume state; changing `SoundGroup.Volume` behind
  that layer can be overwritten by the next property emission.
- This package is runtime state, not player settings persistence. Save user
  preferences separately and translate them into volume multipliers.
