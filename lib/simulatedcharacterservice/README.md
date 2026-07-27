# SimulatedCharacterService

`SimulatedCharacterService` runs lightweight, server-authoritative NPC roots on
a flat X/Z plane. The server stores numbers rather than physical character
models. Each client clones, animates, interpolates, ragdolls, and culls its own
visual models.

The package is designed for dozens of NPCs. Characters may overlap by default,
or use optional flock groups for lightweight local avoidance and coordinated
movement.

## Architecture

- The server simulates all roots at 20 Hz and publishes interest-managed
  ByteNet snapshots at 10 Hz.
- `TimeSyncService` gives snapshots a shared timestamp so clients interpolate
  approximately 100 ms behind the server.
- Navigation uses a flat X/Z occupancy grid. Direct paths skip flow-field work;
  blocked paths share one cached flow field per chased player.
- The server hitbox is a CFrame plus `HitboxRadius` and `HitboxHeight`. It does
  not allocate a Part, incur physics cost, or replicate an invisible Part.
- `TemplateProvider` transfers a model only when a client needs to render it.
- `ClientCulling` checks simulated characters at 10 Hz with squared X/Z
  distance. A culled NPC has no model in Workspace.
- Visible NPCs share one `RenderStepped` connection and one animation driver.

## Templates

Keep game-specific models outside the package. Create a Folder in your game's
asset hierarchy and point the service at it during server initialization:

```text
ReplicatedStorage
└── Assets
    └── SimulatedCharacters
        ├── Zombie
        └── Skeleton
```

```luau
const ReplicatedStorage = game:GetService("ReplicatedStorage")

simulatedCharacters:SetTemplateContainer(
	ReplicatedStorage:WaitForChild("Assets"):WaitForChild("SimulatedCharacters")
)
```

The selected Folder receives the `SimulatedCharacterTemplateContainer`
CollectionService tag. The shared tagged provider therefore discovers the same
container on the server and clients. On the server, TemplateProvider moves the
real models beneath its non-replicating `Camera` and leaves lightweight
tombstones in the Folder. Clients download a model only when they need to render
it.

Give each model a `PrimaryPart` or a part named `HumanoidRootPart`.

A template may contain a normal Roblox `Animate` hierarchy. The service reads
its idle and walk animation objects, disables the cloned `LocalScript`, and
plays those tracks from the shared renderer. It does not run one animation
script per NPC.

Animation resolution is:

1. `Animations.Idle` or `Animations.Walk` in the registered definition.
2. The NPC template's `Animate` hierarchy.
3. The local player's default `Animate` hierarchy or applied
   `HumanoidDescription`.

Set `Animations.UseDefaults = false` to disable steps 2 and 3.

## Server setup

Acquire the service from the game's existing `ServiceBag`, then configure one
explicit navigation region and register character definitions during startup:

```luau
const SimulatedCharacterService = require("SimulatedCharacterService")
const SimulatedCharacterEnums = require("SimulatedCharacterEnums")

local simulatedCharacters = serviceBag:GetService(SimulatedCharacterService)

const FacingMode = SimulatedCharacterEnums.FacingMode
const MovementController = SimulatedCharacterEnums.MovementController
const PlacementMode = SimulatedCharacterEnums.PlacementMode
const TargetingMode = SimulatedCharacterEnums.TargetingMode
const VariantSelectionMode = SimulatedCharacterEnums.VariantSelectionMode

simulatedCharacters:ConfigureNavigation({
	Min = Vector2.new(-256, -256),
	Max = Vector2.new(256, 256),
	CellSize = 4,
	AgentRadius = 2,
	ObstacleTag = "SimulatedCharacterObstacle",
})

simulatedCharacters:RegisterCharacter("Zombie", {
	Template = {
		Variants = {
			{ Name = "Zombie", Weight = 8 },
			{ Name = "ArmoredZombie", Weight = 2 },
		},
		SelectionMode = VariantSelectionMode.WEIGHTED,
		Scale = 1,
	},
	Placement = {
		Mode = PlacementMode.GROUNDED,
		GroundOffset = 0.1,
	},
	Movement = {
		Controller = MovementController.GUARD,
		MoveSpeed = 10,
		TurnSpeed = math.rad(360),
		StoppingDistance = 3,
		FacingMode = FacingMode.TARGET_WHEN_STOPPED,
		WanderRadius = 24,
		WanderInterval = 4,
		OrbitRadius = 8,
		OrbitSpeed = math.rad(45),
	},
	Targeting = {
		Mode = TargetingMode.NEAREST_PLAYER,
		AggroRange = 80,
		LeashRange = 140,
		TargetOffset = 2,
		RetargetInterval = 0.25,
	},
	Flocking = {
		Group = "Undead",
		NeighborRadius = 14,
		SeparationPadding = 1,
		SeparationWeight = 1.6,
		AlignmentWeight = 0.2,
		CohesionWeight = 0.08,
		MaxSteering = 1.75,
	},
	Physics = {
		HitboxRadius = 2,
		HitboxHeight = 6,
		KnockbackDamping = 2,
		GroundFriction = 8,
	},
	Networking = {
		CullDistance = 220,
		ReplicationDistance = 240,
	},
	Animations = {
		UseDefaults = true,
		Idle = "",
		Walk = "",
		Actions = {
			Attack = "rbxassetid://1234567890",
			Stun = "rbxassetid://2345678901",
		},
	},
})
```

The nested sections are the preferred registration format. Existing flat
fields such as `TemplateName`, `MoveSpeed`, `CullDistance`, and `FlockGroup`
remain supported so current definitions do not need to be migrated at once.

## Enum lists

Each categorical setting has its own `Enums` list and all five are also exposed
by `SimulatedCharacterEnums`:

- `SimulatedCharacterPlacementMode`: `PIVOT`, `BOUNDING_BOX_CENTER`, `GROUNDED`.
- `SimulatedCharacterMovementController`: `MANUAL`, `CHASE`, `WANDER`, `GUARD`, `ORBIT`.
- `SimulatedCharacterTargetingMode`: `MANUAL`, `NEAREST_PLAYER`.
- `SimulatedCharacterFacingMode`: `MOVEMENT`, `TARGET_WHEN_STOPPED`, `TARGET_ALWAYS`.
- `SimulatedCharacterVariantSelectionMode`: `WEIGHTED`, `RANDOM`, `SEQUENTIAL`.

You may require a specific list directly when that makes a module clearer:

```luau
const SimulatedCharacterMovementController = require("SimulatedCharacterMovementController")

simulatedCharacters:RegisterCharacter("Wanderer", {
	Template = { Name = "Zombie" },
	Movement = {
		Controller = SimulatedCharacterMovementController.WANDER,
	},
})
```

`MANUAL` leaves movement to `MoveTo`, `Chase`, and `Stop`. `CHASE` waits for a
target, `WANDER` picks walkable points around the spawn home without leaving the
configured navigation bounds, `GUARD` chases and returns home, and `ORBIT` moves
around its target. `NEAREST_PLAYER` performs automatic target acquisition at
`RetargetInterval`; `MANUAL` only uses targets assigned through the character
handle. Every retarget evaluates all eligible players. The current player is
retained when tied, but a closer player inside `AggroRange` replaces it. An
existing target may remain outside `AggroRange` until it leaves `LeashRange`.

`GROUNDED` interprets a spawn Y as the floor, raises the authoritative hitbox by
half its height plus `GroundOffset`, centers the visual on X/Z, and places the
visual bounding-box bottom on that floor. `BOUNDING_BOX_CENTER` aligns the full
visual bounding-box center to the authoritative CFrame. `PIVOT` preserves the
template's authored pivot behavior.

`WEIGHTED` uses each variant's `Weight`, `RANDOM` gives every variant equal
odds, and `SEQUENTIAL` cycles through registration order. Selection happens
once on spawn. Only the selected template and the other client-rendering fields
are replicated; server-only movement, targeting, flocking, and physics tuning
do not inflate movement snapshots.

The client must acquire `SimulatedCharacterServiceClient` through its own
`ServiceBag`. Its lifecycle starts culling, time synchronization, networking,
rendering, pooling, and animation automatically.

```luau
const SimulatedCharacterServiceClient = require("SimulatedCharacterServiceClient")

local simulatedCharactersClient = serviceBag:GetService(SimulatedCharacterServiceClient)
```

## Spawning and movement

```luau
local zombie = simulatedCharacters:SpawnCharacter("Zombie", {
	-- With GROUNDED placement, Y=0 is the floor rather than the root center.
	CFrame = CFrame.new(0, 0, 0),
})

zombie:Chase(player)

-- Or move toward a fixed destination.
zombie:MoveTo(Vector3.new(100, 0, -40))

zombie:Stop()
zombie:Teleport(CFrame.new(20, 3, 20))
zombie:SetReplicationDistance(300)

-- Per-character time scaling. The default is 1.
zombie:SetSimulationRate(0.5) -- Half speed
zombie:SetSimulationRate(2) -- Double speed
zombie:SetSimulationRate(0) -- Paused
zombie:SetSimulationRate(1) -- Normal speed
zombie:Destroy()
```

`MoveTo` and `Chase` ignore Y. `GroundY` and `CFrame.Y` use the definition's
placement mode. Knockback can temporarily add visual height above the resolved
baseline. Facing always stays on X/Z and therefore never tilts a character
toward a target above or below it.

`Targeting.TargetOffset` is additional stand-off distance while directly
chasing a player. The player remains the real navigation and facing target, so
a large offset cannot place an artificial destination behind the NPC. The
effective arrival distance is
`Movement.StoppingDistance + Targeting.TargetOffset`. `ORBIT` continues to use
`Movement.OrbitRadius` and its normal stopping distance instead.

## Server-driven action animations

Register combat and interaction animations under `Animations.Actions`, then
play them by name from the server character handle:

```luau
zombie:PlayAnimation("Attack", {
	FadeTime = 0.1,
	Speed = 1,
	Looped = false,
})

-- Stops only when Attack is still the active action.
zombie:StopAnimation("Attack", 0.15)
```

Names are case-sensitive. Registration sorts them deterministically and sends
the asset-ID catalog once per character definition. Play packets use the
resulting `uint8` index instead of repeating a name or asset ID, and are sent
only to clients with network interest in that NPC. One action override may be
active per character; playing another replaces it.

Action tracks use `Enum.AnimationPriority.Action`. A client that mounts the
model late, returns from culling, or receives the catalog after the play packet
seeks to the correct point using `TimeSyncService`. A non-looping animation is
discarded when its elapsed server time is beyond the track length. `Speed` is
explicit action playback speed and is independent of `SetSimulationRate`,
which continues to scale locomotion animations.

These tracks are cosmetic. Keep hit timing, damage, cooldowns, and validation
authoritative in the server combat system rather than relying on client
animation markers.

## Spatial queries

Server code can query authoritative NPC centers with either a `Vector2` or
`Vector3`. Results are nearest-first and `Vector3.Y` is ignored:

```luau
const nearby = simulatedCharacters:Query(hitPosition, 40)
const nearest = nearby[1]

for _, character in nearby do
	print(character:GetId(), character:GetPosition())
end
```

Queries use an incrementally updated X/Z spatial hash. Small radii inspect only
overlapping cells; large radii automatically scan the dense character set when
that is cheaper than visiting empty cells. Distances are measured from each
authoritative character center and do not include its hitbox radius.

`SetSimulationRate` changes the character's local passage of time without
changing the service's global 20 Hz simulation or 10 Hz snapshot schedules. It
scales movement, turning, targeting timers, wandering, orbiting, knockback,
gravity, extrapolated velocity, and client locomotion animation playback. Rate
changes use one small reliable packet; the rate is not repeated in periodic
movement snapshots.

Spawned handles expose lifecycle signals without adding binders or Instances:

```luau
zombie.TargetChanged:Connect(function(targetPlayer)
	print("New target", targetPlayer)
end)

zombie.ReachedTarget:Connect(function(target)
	print("Reached", target)
end)

zombie.ModeChanged:Connect(function(mode)
	print("New physical mode", mode)
end)

zombie.Destroyed:Connect(function()
	print("Removed")
end)
```

Each spawned character starts with `Networking.ReplicationDistance`, which
defaults to `Networking.CullDistance`. `SetReplicationDistance` overrides only
that character's periodic updates and immediate state changes; global spawn and
removal messages remain unchanged. Keep replication distance at least as large
as cull distance if a visible NPC should never stop receiving updates before
client culling removes its model.

## Flocking and local avoidance

Set `Flocking.Group` to a non-empty string to give characters in that group
server-authoritative crowd steering:

```luau
simulatedCharacters:RegisterCharacter("Zombie", {
	Template = { Name = "Zombie" },
	Flocking = { Group = "Undead" },
})
```

Only characters with the same exact group name influence each other. The
service combines hitbox-based separation, light velocity alignment, and light
cohesion with the existing path direction. If the blended move is blocked, it
falls back to the unmodified navigation direction. After movement, a symmetric
bounded overlap solver enforces the combined hitbox radii plus the larger
configured separation padding without moving a character through blocked
navigation cells.

Flocking runs only for kinematic movement. Knockback and ragdoll characters do
not steer or influence their group until they return to kinematic mode. The
calculation uses reusable dense group arrays, squared X/Z distance checks, and
does not add anything to network snapshots.

## Network interest

Spawn and removal messages are sent globally so every client maintains the
complete lightweight NPC registry. This allows an NPC to become visible as
soon as it approaches without needing a second spawn lifecycle.

Periodic movement snapshots and immediate state changes are sent only to
players within that character's replication distance. Distance checks use X/Z
and include `Physics.HitboxRadius`. When an NPC leaves range, the server sends
one final reliable state so the client cannot leave a stale model visible, then
stops updates until the NPC enters range again.

The 10 Hz movement stream uses a custom ByteNet buffer instead of repeating the
full lifecycle struct. X/Z positions, planar velocity, physical height, and
vertical velocity use 1/32-stud fixed point; yaw uses a uint16 turn. A normal
kinematic record is 15 bytes and a knockback or ragdoll record is 19 bytes,
compared with 45 bytes for the previous full-state record. Each packet chooses
its own X/Z origin, allowing positions in a roughly 2048-stud span to stay
compact anywhere in the world. An outlying position automatically falls back
to float32 for that record. Extreme velocity or height values also fall back to
float32 instead of being clamped. Reliable spawn, teleport, mode transition,
and out-of-range correction packets retain full state.

## Debug drawing

Toggle local debug drawing through the client service:

```luau
simulatedCharactersClient:SetDebug(true)

-- Remove every debug drawing and stop requesting debug data.
simulatedCharactersClient:SetDebug(false)
```

`SetDebug(true)` loads the `Draw` package locally and creates a
`Workspace.SimulatedCharacterDebug` folder visible only to that client. It
requests path data only for nearby NPCs at 5 Hz. Debug requests are rate-limited
on the server, and no debug packets or drawing work run while disabled.

The visualization refreshes at 5 Hz:

- Red boxes are authoritative hitboxes.
- Gray rings are client culling ranges.
- Cyan rings are per-character network-update ranges.
- Magenta rings are flock neighbor ranges.
- Yellow rings are stopping distances around current targets.
- Green lines show direct or flow-field paths.
- Orange lines show actual movement after flock steering.
- Blue lines are the configured navigation bounds.

Debug defaults to false and is cleaned up automatically with the client
service.

## Knockback and cosmetic ragdolls

```luau
zombie:ApplyImpulse(Vector3.new(25, 35, 0))

zombie:SetRagdolled(true)
zombie:ApplyImpulse(Vector3.new(25, 35, 0))

task.delay(2, function()
	if simulatedCharacters:GetCharacter(zombie:GetId()) then
		zombie:SetRagdolled(false)
	end
end)

-- Uses MathUtils.computeTrajectory internally.
zombie:LaunchTowards(targetPosition, 60)
```

The server simulates only root velocity and height. Client limbs are cosmetic.
For precise ragdolls, tag the intended `Motor6D` objects with the boolean
attribute `SimulatedCharacterRagdollMotor` and the replacement constraints with
`SimulatedCharacterRagdollConstraint`. Without attributes, the renderer falls
back to non-root motors and all `BallSocketConstraint` objects.

## Obstacles and rebuilding

Tag obstacle `BasePart` or `Model` instances with the configured obstacle tag.
Adding or removing the tag schedules a grid rebuild. If a tagged obstacle moves
or resizes without a tag change, rebuild explicitly:

```luau
simulatedCharacters:RebuildNavigation()
```

Keep navigation bounds tight and use the largest cell size that still fits the
gameplay geometry. A 512 by 512 stud region with four-stud cells is a 128 by 128
grid. Flow fields are cached per chase target, so many NPCs chasing the same
player reuse the same path data.

## Performance notes

- Avoid putting cosmetic models on the server; use the template provider.
- Prefer `Chase(player)` when many NPCs share a target. Unique blocked `MoveTo`
  destinations require unique flow fields.
- Character visuals are pooled per template after culling.
- Normal movement, navigation, and culling use X/Z only.
- Characters without a `Flocking.Group`, and characters in different groups, may
  overlap. Members of one flock use soft local avoidance rather than Roblox
  physics collisions.
- Use `GetCFrame()` and `GetHitboxSize()` for authoritative server-side combat
  checks instead of relying on client limbs.
