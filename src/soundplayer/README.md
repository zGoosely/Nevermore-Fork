# SoundPlayer

`SoundPlayer` is the client playback layer for long-running music, ambience, and
other sounds that need smooth transitions. It can cross-fade between tracks,
schedule changes at loop boundaries, choose sounds from a collection, synchronize
loops to a clock or BPM, combine multiple synchronized layers, and arbitrate
between competing players by priority.

The package does not stream playback commands from the server. The server-side
`SoundPlayerService` only initializes the corresponding SoundGroup package. The
actual `Sound` instances, timing, transitions, and stacks are owned by the client.

Use `SoundUtils.playFromId()` for a short fire-and-forget sound. Use SoundPlayer
when a sound has a lifecycle: it should remain alive, transition, loop, or react
to changing game state.

## Mental model

The main objects form this pipeline:

```text
SoundPlayerServiceClient
└── named SoundPlayerStack
    ├── low-priority LoopedSoundPlayer
    └── high-priority LoopedSoundPlayer  ← currently audible
        └── SimpleLoopedSoundPlayer
            └── Roblox Sound

LayeredLoopedSoundPlayer
├── "Base" LoopedSoundPlayer
├── "Drums" LoopedSoundPlayer
└── "Danger" LoopedSoundPlayer
```

- `LoopedSoundPlayer` is the normal single-track controller.
- `LayeredLoopedSoundPlayer` coordinates several named single-track players.
- `SoundPlayerStack` selects one player from competing requests.
- `SoundPlayerServiceClient` owns named stacks such as `Music` or `Ambience`.
- `SimpleLoopedSoundPlayer` is the low-level `Sound` plus timed volume fade.

Visibility controls volume, not whether the underlying sound clock exists. A
player can keep a loop running silently while hidden, then fade back in without
restarting the track.

## Package children

| Module | Responsibility |
| --- | --- |
| `Client/Loops/LoopedSoundPlayer` | Main single-track controller: swapping, cross-fades, random selections, scheduling, loop promises, BPM synchronization, and time-position restoration. |
| `Client/Loops/SimpleLoopedSoundPlayer` | Wraps one looping Roblox `Sound` and fades its effective volume with `TimedTransitionModel`. Usually created internally. |
| `Client/Loops/Layered/LayeredLoopedSoundPlayer` | Owns named `LoopedSoundPlayer` layers for adaptive music or compound ambience. |
| `Client/Loops/Layered/LayeredSoundHelper` | Generic keyed-layer cache and lifetime manager used by layered players and the service. |
| `Client/Schedule/SoundLoopScheduleUtils` | Validates and constructs immutable loop schedule tables. |
| `Client/Stack/SoundPlayerStack` | Sorts competing `LoopedSoundPlayer` objects by a number or observable priority and shows only the highest entry. |
| `Client/Service/SoundPlayerServiceClient` | Provides named priority stacks to the rest of the client. |
| `Server/SoundPlayerService` | Server bootstrap that ensures `SoundGroupService` is initialized; it performs no playback or networking. |

## Service setup

Register the server service in the server ServiceBag:

```luau
const require = require("../Loader").load()

const ServiceBag = require("ServiceBag")
const SoundPlayerService = require("SoundPlayerService")

local serviceBag = ServiceBag.new()
serviceBag:GetService(SoundPlayerService)
serviceBag:Init()
serviceBag:Start()
```

Register the client service in the client ServiceBag:

```luau
const require = require("../Loader").load()

const ServiceBag = require("ServiceBag")
const SoundPlayerServiceClient = require("SoundPlayerServiceClient")

local serviceBag = ServiceBag.new()
local soundPlayers = serviceBag:GetService(SoundPlayerServiceClient)

serviceBag:Init()
serviceBag:Start()
```

The client service initializes `SoundGroupServiceClient` automatically. You can
also construct `LoopedSoundPlayer` or `LayeredLoopedSoundPlayer` directly when a
priority stack is unnecessary.

## Accepted sound IDs

SoundPlayer delegates construction to `SoundUtils`. A `SoundId` can be:

```luau
-- A number
1843529634

-- A Roblox asset string
"rbxassetid://1843529634"

-- A property table
{
	SoundId = "rbxassetid://1843529634",
	Volume = 0.5,
	PlaybackSpeed = 1.1,
	RollOffMaxDistance = 120,
}

-- An authored Sound used as a template
script.MusicTemplate
```

The property table is useful when a track needs authored playback settings but
does not justify a separate `Sound` template. A supplied `Sound` is copied so the
player owns its runtime instance.

## Basic looping playback

Create a `LoopedSoundPlayer`, parent its internal sounds somewhere appropriate,
then show it:

```luau
const SoundService = game:GetService("SoundService")

const LoopedSoundPlayer = require("LoopedSoundPlayer")

local music = maid:Add(LoopedSoundPlayer.new(
	"rbxassetid://1843529634",
	SoundService
))

music:SetCrossFadeTime(0.75)
music:SetVolumeMultiplier(0.8)
music:Show()
```

`LoopedSoundPlayer` inherits the visibility and spring-transition API from
`SpringTransitionModel`, including `Show()`, `Hide()`, `SetVisible()`,
`PromiseShow()`, `PromiseHide()`, and `SetSpeed()`.

The player creates a new low-level sound when the selected sound changes. The
new sound fades in while the old one fades out, and the old runtime sound is
destroyed after its hide transition finishes.

### Assigning a SoundGroup

Route the sound through the SoundGroup package so music volume and effects can be
managed independently:

```luau
const SoundEffectService = require("SoundEffectService")
const WellKnownSoundGroups = require("WellKnownSoundGroups")

local soundEffects = serviceBag:GetService(SoundEffectService)
local musicGroup = soundEffects:GetOrCreateSoundGroup(WellKnownSoundGroups.MUSIC)

music:SetSoundGroup(musicGroup)
```

`SetSoundGroup`, `SetSoundParent`, `SetCrossFadeTime`, and `SetBPM` accept
mountable values where indicated by their types, so a `ValueObject` or observable
can drive them without recreating the player. Keep the returned cleanup function
when mounting reactive state.

## Swapping tracks

An immediate swap uses the default schedule:

```luau
music:Swap("rbxassetid://NEXT_TRACK")
```

Useful variants are:

```luau
-- Replace the track close to the current loop boundary.
music:SwapOnLoop("rbxassetid://NEXT_TRACK")

-- Play one loop, then stop.
music:PlayOnce("rbxassetid://STINGER")

-- Wait for the current boundary, then play one loop.
music:PlayOnceOnLoop("rbxassetid://STINGER")

-- Allow the current sound to finish its loop, then become silent.
music:StopAfterLoop()
```

Calling `Swap()` replaces any pending swap schedule. `GetCurrentSoundId()` returns
the selected source, while `GetSound()` returns the current runtime `Sound` or
`nil`.

`PromiseLoopDone()` resolves at the next detected loop boundary.
`PromiseSustain()` intentionally never resolves and is useful when a promise
chain should own the player until an external Maid destroys it.

## Loop schedules

A schedule controls when the first selection begins and what happens around each
loop:

```luau
music:Swap("rbxassetid://1843529634", {
	playOnNextLoop = true,
	maxInitialWaitTimeForNextLoop = 8,
	initialDelay = NumberRange.new(0.1, 0.4),
	loopDelay = NumberRange.new(1, 3),
	maxLoops = 4,
})
```

| Field | Meaning |
| --- | --- |
| `playOnNextLoop` | Waits near the current sound's loop boundary before applying the new selection. The cross-fade duration is included in the boundary calculation. |
| `maxInitialWaitTimeForNextLoop` | Caps how long `playOnNextLoop` may wait. It can be a number or sampled `NumberRange`. |
| `initialDelay` | Adds a delay before the first selected sound begins. |
| `loopDelay` | Pauses the sound after each loop, waits, then resumes it. |
| `maxLoops` | Clears the current selection after the configured loop limit. |

Delay values accept a number or `NumberRange`. A range is sampled with
`math.random()` each time it is needed.

`SoundLoopScheduleUtils` also exposes:

| Function | Purpose |
| --- | --- |
| `default()` | Returns an empty frozen schedule. |
| `schedule(options)` | Validates and freezes a schedule table. |
| `onNextLoop(options)` | Returns a schedule with `playOnNextLoop = true`. |
| `maxLoops(count, options)` | Returns a schedule with a loop limit. |
| `getWaitTimeSeconds(value)` | Resolves a number or samples a `NumberRange`. |

## Randomized loops

Use `SwapToSamples()` for a shuffled bag. Every item is used before the bag is
refilled, and the sampler avoids an immediate repeat across refill boundaries:

```luau
music:SwapToSamples({
	"rbxassetid://AMBIENCE_A",
	"rbxassetid://AMBIENCE_B",
	"rbxassetid://AMBIENCE_C",
}, {
	loopDelay = NumberRange.new(2, 6),
})
```

Use `SwapToChoice()` for an independent random choice at each boundary. It may
repeat the same sound consecutively:

```luau
music:SwapToChoice({
	"rbxassetid://BIRD_A",
	"rbxassetid://BIRD_B",
	"rbxassetid://BIRD_C",
})
```

## Synchronization and restored positions

`SetDoSyncSoundPlayback(true)` aligns playback to a shared `os.clock()` timeline.
If a BPM is configured, the player aligns the sound to beat boundaries and treats
the usable loop length as a whole number of beats:

```luau
music:SetBPM(120)
music:SetDoSyncSoundPlayback(true)
```

Without a BPM, synchronized playback uses `os.clock() % TimeLength`. This is
useful for clients independently starting the same deterministic ambient loop.
It is not server networking or sample-accurate multi-device audio synchronization.

Time-position restoration is enabled by default. If the same sound source is
recreated, the player remembers its last position and advances it by elapsed
wall-clock time. Disable this behavior when every recreation should restart:

```luau
music:SetDoRestoreTimePosition(false)
```

Synchronization works best with loaded, seamless loops whose lengths align with
the selected BPM.

## Adaptive layered music

`LayeredLoopedSoundPlayer` creates one `LoopedSoundPlayer` per string layer ID.
Every layer inherits the same parent, SoundGroup, BPM, cross-fade time, outer
visibility, and volume multiplier. New layers automatically enable synchronized
playback.

```luau
const SoundService = game:GetService("SoundService")

const LayeredLoopedSoundPlayer = require("LayeredLoopedSoundPlayer")

local soundtrack = maid:Add(LayeredLoopedSoundPlayer.new(SoundService))
soundtrack:SetSoundGroup(musicGroup)
soundtrack:SetBPM(120)
soundtrack:SetDefaultCrossFadeTime(0.5)
soundtrack:Show()

soundtrack:Swap("Base", "rbxassetid://BASE_LOOP")
soundtrack:Swap("Drums", "rbxassetid://DRUM_LOOP")

-- Add danger without restarting the base layers.
soundtrack:SwapOnLoop("Danger", "rbxassetid://DANGER_LOOP")

-- Fade one layer out.
soundtrack:StopLayer("Danger")
```

Layer IDs are arbitrary. Good choices describe musical roles or gameplay state:
`Base`, `Percussion`, `Combat`, `LowHealth`, and `Boss`.

The layered variants of `SwapToSamples`, `SwapToChoice`, `PlayOnce`, and
`PlayOnceOnLoop` take the layer ID as their first argument. `StopAll()` starts a
hide transition for every existing layer; the implementation returns an
aggregate promise that completes when those hide operations finish.

## Priority stacks

Use `SoundPlayerServiceClient` when independent systems may compete for the same
audio channel. A named stack shows the player with the highest priority and hides
the previous winner:

```luau
const LoopedSoundPlayer = require("LoopedSoundPlayer")

local exploration = maid:Add(LoopedSoundPlayer.new(
	"rbxassetid://EXPLORE",
	SoundService
))
local combat = maid:Add(LoopedSoundPlayer.new(
	"rbxassetid://COMBAT",
	SoundService
))

local removeExploration = soundPlayers:PushSoundPlayer("Music", exploration, 10)
local removeCombat = soundPlayers:PushSoundPlayer("Music", combat, 100)

-- Combat is visible. Removing it reveals exploration again.
removeCombat()
```

The priority may be an `Observable<number>`:

```luau
local priority = maid:Add(ValueObject.new(10))
local remove = soundPlayers:PushSoundPlayer(
	"Music",
	exploration,
	priority:Observe()
)

priority.Value = 200
```

`GetOrCreateSoundPlayerStack(layerId)` exposes the underlying stack if you need
its `HidingComplete` signal or want to push players directly. Removing a stack
entry hides that player; the caller still owns and must destroy the player.

## Low-level SimpleLoopedSoundPlayer

Use `SimpleLoopedSoundPlayer` only when you want one looping `Sound` with a linear
timed fade and do not need swapping or scheduling:

```luau
const SimpleLoopedSoundPlayer = require("SimpleLoopedSoundPlayer")

local player = maid:Add(SimpleLoopedSoundPlayer.new("rbxassetid://LOOP"))
player.Sound.Parent = SoundService
player:SetSoundGroup(musicGroup)
player:SetTransitionTime(0.4)
player.Sound:Play()
player:Show()
```

Its public `Sound` property is the owned Roblox instance. Destroying the player
destroys that sound through its Maid.

## API summary

### LoopedSoundPlayer

| Method | Purpose |
| --- | --- |
| `new(soundId?, soundParent?)` | Creates a single-track controller. |
| `SetCrossFadeTime(value)` | Mounts the overlap/fade duration. |
| `SetVolumeMultiplier(number)` | Scales the authored sound volume. |
| `SetSoundGroup(value)` | Mounts a Roblox `SoundGroup`. |
| `SetBPM(value)` | Mounts an optional BPM. |
| `SetSoundParent(value)` | Mounts the parent for runtime sounds. |
| `SetDoSyncSoundPlayback(bool)` | Enables deterministic clock/BPM alignment. |
| `SetDoRestoreTimePosition(bool)` | Controls restoration when a sound is recreated. |
| `Swap`, `SwapOnLoop` | Replaces the active sound now or near a boundary. |
| `SwapToSamples`, `SwapToChoice` | Chooses a new sound at loop boundaries. |
| `PlayOnce`, `PlayOnceOnLoop` | Plays one loop now or at the next boundary. |
| `StopAfterLoop()` | Clears playback after the current loop. |
| `PromiseLoopDone()` | Resolves at the next loop boundary. |
| `GetCurrentSoundId()` | Returns the selected source. |
| `GetSound()` | Returns the current runtime `Sound`. |

### LayeredLoopedSoundPlayer

| Method | Purpose |
| --- | --- |
| `new(soundParent?)` | Creates an empty keyed layer collection. |
| `SetDefaultCrossFadeTime`, `SetVolumeMultiplier`, `SetBPM` | Configures shared layer behavior. |
| `SetSoundParent`, `SetSoundGroup` | Configures shared Roblox routing. |
| `Swap*`, `PlayOnce*` | Runs the corresponding operation on one layer ID. |
| `StopLayer(layerId)` | Hides one layer. |
| `StopAll()` | Hides all current layers. |

### SoundPlayerServiceClient

| Method | Purpose |
| --- | --- |
| `GetOrCreateSoundPlayerStack(layerId)` | Returns a named priority channel. |
| `PushSoundPlayer(layerId, player, priority?)` | Adds a player and returns removal cleanup. |

## Ownership and practical constraints

- SoundPlayer is client playback; it is not a server-to-client command bus.
- Parent runtime sounds before expecting them to be audible.
- Call `Show()` when a directly constructed player should fade in.
- Keep players and stack-removal callbacks in a Maid.
- Destroying a modifier, stack entry, or service does not imply ownership of every
  player supplied by outside code.
- Use the SoundGroup package for category volume and sound effects.
- Prefer `SwapToSamples` over `SwapToChoice` when immediate repeats are unwanted.
- BPM synchronization assumes sensible, non-zero `TimeLength` values after load.
- Sound IDs and property tables are local configuration; they are not validated
  or selected by the server package.
