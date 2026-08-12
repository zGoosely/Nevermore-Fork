# DeathReport

`DeathReport` is a comprehensive, production-ready death and kill tracking package for Nevermore. It provides centralized event orchestration, reactive stream observers (`Observable`), automatic stats tracking, and ultra-compact network replication via **ByteNet** and **PlayerIdService**.

---

## Table of Contents

1. [Architecture & System Overview](#architecture--system-overview)
2. [Network Optimization & Payload Encoding](#network-optimization--payload-encoding)
3. [Type Contracts](#type-contracts)
4. [Server API Reference (`DeathReportService`)](#server-api-reference-deathreportservice)
5. [Client API Reference (`DeathReportServiceClient`)](#client-api-reference-deathreportserviceclient)
6. [Stateless Utilities (`DeathReportUtils`)](#stateless-utilities-deathreportutils)
7. [Stats Tracking & Binders](#stats-tracking--binders)
   - [PlayerDeathTracker & PlayerKillTracker](#playerdeathtracker--playerkilltracker)
   - [TeamKillTracker](#teamkilltracker)
   - [PlayerKillTrackerAssigner](#playerkilltrackerassigner)
   - [DeathTrackedHumanoid](#deathtrackedhumanoid)
8. [End-to-End Integration Examples](#end-to-end-integration-examples)
   - [1. Game Initialization with ServiceBag](#1-game-initialization-with-servicebag)
   - [2. Weapon Data Retriever Setup](#2-weapon-data-retriever-setup)
   - [3. Building a Rich Killfeed UI](#3-building-a-rich-killfeed-ui)
   - [4. Leaderboard & K/D Tracking](#4-leaderboard--kd-tracking)
9. [Edge Cases & Reliability](#edge-cases--reliability)
10. [Unit Testing](#unit-testing)

---

## Architecture & System Overview

`DeathReport` decouples death detection, attribution, stats mutation, and UI presentation into modular, single-responsibility components:

```
[ Humanoid Dies ]
       │
       ▼
[ DeathTrackedHumanoid ] ──── (Detects Health <= 0)
       │
       ▼
[ DeathReportService ]  ──── (Resolves WeaponData, fires signals)
       │
       ├─────────────────────────────────────────┐
       ▼                                         ▼
[ DeathReportProcessor ]                 [ DeathReportNetwork ] (ByteNet)
(Fires Server Observables)                       │
       │                                         ▼
       ├─► PlayerKillTracker / DeathTracker  [ DeathReportServiceClient ]
       └─► TeamKillTracker                       │
                                                 ▼
                                         [ DeathReportProcessor ] (Client)
                                                 │
                                                 ├─► Client Observables
                                                 └─► NewDeathReport Signal (Killfeed UI)
```

### Key Architectural Concepts

- **Service Facade**: `DeathReportService` (Server) and `DeathReportServiceClient` (Client) orchestrate package lifecycles and expose small, clean public APIs.
- **Binder Ownership**: `DeathTrackedHumanoid` monitors humanoids and ensures deaths are reported exactly once, preventing double-reporting on multi-damage tick frames.
- **Reactive Streams**: Uses Nevermore's `Observable` pattern via `ObservableSubscriptionTable` (`DeathReportProcessor`), allowing callers to subscribe to death and killer reports for specific players, humanoids, or character models without polling.
- **ByteNet Wire Format**: Network messages use ByteNet's buffer-backed namespace definition, avoiding standard RemoteEvent overhead.
- **Player ID Compression**: Integrates with `PlayerIdService` to encode player entity references as 1-byte `uint8` identifiers instead of heavy Roblox `Instance` references over the wire.

---

## Network Optimization & Payload Encoding

Standard Roblox `RemoteEvent:FireAllClients(table)` serializes full `Instance` references for player characters, humanoids, and tools, incurring significant network overhead per death report.

`DeathReportNetwork` optimizes the wire protocol by combining **ByteNet** with **PlayerIdService**:

### ByteNet Namespace Schema (`DeathReportNetwork`)

```luau
ByteNet.defineNamespace("DeathReport", function()
	return {
		packets = {
			deathReport = ByteNet.definePacket({
				value = ByteNet.struct({
					playerId = ByteNet.optional(ByteNet.uint8),
					killerPlayerId = ByteNet.optional(ByteNet.uint8),
					adornee = ByteNet.optional(ByteNet.inst),
					killerAdornee = ByteNet.optional(ByteNet.inst),
					weaponInstance = ByteNet.optional(ByteNet.inst),
				}),
			}),
		},
	}
end)
```

### How Payload Compression Works

1. **Player Deaths (PVP)**:
   - When the victim (`deathReport.player`) is a connected player, `DeathReportService` transmits their 1-byte `uint8` ID via `playerId`.
   - `adornee` is set to `nil` in the packet payload, saving instance reference serialization.
   - When the killer (`deathReport.killerPlayer`) is a connected player, `killerPlayerId` is sent as a 1-byte `uint8`. `killerAdornee` is set to `nil`.

2. **NPC / Non-Player Deaths**:
   - If the victim is an NPC or environment entity without a `Player`, `playerId` is `nil` and the character `Instance` is transmitted via `adornee = ByteNet.inst`.

3. **Client Resolution**:
   - Upon receiving a packet, `DeathReportServiceClient` resolves `playerId` and `killerPlayerId` back to `Player` objects via `PlayerIdServiceUtils.getPlayerFromId(id)`.
   - If found, `player.Character` is automatically restored as the `adornee` / `killerAdornee`.

---

## Type Contracts

### `WeaponData`
```luau
export type WeaponData = {
	weaponInstance: Instance?,
}
```

### `DeathReport`
```luau
export type DeathReport = {
	["type"]: "deathReport",
	adornee: Instance,
	humanoid: Humanoid?,
	player: Player?,
	killerAdornee: Instance?,
	killerHumanoid: Humanoid?,
	killerPlayer: Player?,
	weaponData: WeaponData,
}
```

---

## Server API Reference (`DeathReportService`)

The server-side service responsible for collecting death reports, executing weapon retrievers, updating statistics, and replicating events to clients.

### Service Properties

| Property | Type | Description |
|---|---|---|
| `ServiceName` | `"DeathReportService"` | Service identifier for `ServiceBag` resolution |
| `ServerOnly` | `true` | Restricts instantiation to the server realm |
| `NewDeathReport` | `Signal<DeathReport>` | Signal fired whenever a new death report is processed |

### Methods

#### `Init(serviceBag: ServiceBag)`
Initializes service state, resolves dependencies (`PlayerIdService`, `DeathReportBindersServer`, `DeathTrackedHumanoid`), and creates internal maid and signal containers.

#### `Start()`
Hook for post-initialization startup logic.

#### `AddWeaponDataRetriever(getWeaponData: (humanoid: Humanoid) -> WeaponData?): () -> ()`
Registers a callback to extract weapon information when a humanoid dies. Returns a cleanup function to unregister the retriever.

```luau
const removeRetriever = deathReportService:AddWeaponDataRetriever(function(humanoid: Humanoid)
	const tool = humanoid.Parent and humanoid.Parent:FindFirstChildWhichIsA("Tool")
	if tool then
		return DeathReportUtils.createWeaponData(tool)
	end
	return nil
end)
```

#### `FindWeaponData(humanoid: Humanoid): WeaponData?`
Queries all registered weapon retrievers in order and returns the first non-nil `WeaponData` result.

#### `ObservePlayerKillerReports(player: Player): Observable<DeathReport>`
Returns an `Observable` stream that emits whenever `player` kills another entity.

#### `ObservePlayerDeathReports(player: Player): Observable<DeathReport>`
Returns an `Observable` stream that emits whenever `player` dies.

#### `ObserveHumanoidKillerReports(humanoid: Humanoid): Observable<DeathReport>`
Returns an `Observable` stream that emits whenever `humanoid` kills another entity.

#### `ObserveHumanoidDeathReports(humanoid: Humanoid): Observable<DeathReport>`
Returns an `Observable` stream that emits whenever `humanoid` dies.

#### `ObserveCharacterKillerReports(character: Model): Observable<DeathReport>`
Returns an `Observable` stream that emits whenever `character` kills another entity.

#### `ObserveCharacterDeathReports(character: Model): Observable<DeathReport>`
Returns an `Observable` stream that emits whenever `character` dies.

#### `ReportHumanoidDeath(humanoid: Humanoid, weaponData: WeaponData?): ()`
Constructs a `DeathReport` for the deceased humanoid using `DeathReportUtils.fromDeceasedHumanoid` and broadcasts it.

#### `ReportDeathReport(deathReport: DeathReport): ()`
Processes the given `DeathReport`, fires `NewDeathReport`, updates subscription tables, and transmits the compact payload over `ByteNet` to all clients.

#### `Destroy()`
Cleans up signals, maids, and subscription tables.

---

## Client API Reference (`DeathReportServiceClient`)

The client-side service that receives ByteNet packets, reconstructs `DeathReport` objects, maintains a recent death report history buffer, and exposes client observables.

### Service Properties

| Property | Type | Description |
|---|---|---|
| `ServiceName` | `"DeathReportServiceClient"` | Service identifier for `ServiceBag` resolution |
| `NewDeathReport` | `Signal<DeathReport>` | Client signal fired when a new death report arrives |

### Methods

#### `Init(serviceBag: ServiceBag)`
Initializes client state, resolves `PlayerIdServiceClient` and `DeathReportBindersClient`.

#### `Start()`
Connects the ByteNet listener on `DeathReportNetwork.packets.deathReport`.

#### `GetLastDeathReports(): { DeathReport }`
Returns an array of recent death reports recorded on the client (buffered up to `MAX_DEATH_REPORTS = 5`).

#### `ObservePlayerKillerReports(player: Player): Observable<DeathReport>`
Client stream emitting whenever `player` kills an entity.

#### `ObservePlayerDeathReports(player: Player): Observable<DeathReport>`
Client stream emitting whenever `player` dies.

#### `ObserveHumanoidKillerReports(humanoid: Humanoid): Observable<DeathReport>`
Client stream emitting whenever `humanoid` kills an entity.

#### `ObserveHumanoidDeathReports(humanoid: Humanoid): Observable<DeathReport>`
Client stream emitting whenever `humanoid` dies.

#### `ObserveCharacterKillerReports(character: Model): Observable<DeathReport>`
Client stream emitting whenever `character` kills an entity.

#### `ObserveCharacterDeathReports(character: Model): Observable<DeathReport>`
Client stream emitting whenever `character` dies.

#### `Destroy()`
Cleans up connections and signal subscriptions.

---

## Stateless Utilities (`DeathReportUtils`)

`DeathReportUtils` contains stateless helper functions for building, validating, and reading death reports.

| Function | Parameters | Return Type | Description |
|---|---|---|---|
| `fromDeceasedHumanoid` | `humanoid: Humanoid, weaponData: WeaponData?` | `DeathReport` | Builds a report for a dying humanoid using `HumanoidKillerUtils` |
| `create` | `adornee: Instance, killerAdornee: Instance?, weaponData: WeaponData?` | `DeathReport` | Constructs a full `DeathReport` table with inferred players/humanoids |
| `isDeathReport` | `value: any` | `boolean` | Validates if `value` matches the `DeathReport` table schema |
| `isWeaponData` | `value: any` | `boolean` | Validates if `value` matches `WeaponData` |
| `createWeaponData` | `weaponInstance: Instance?` | `WeaponData` | Constructs a `WeaponData` object |
| `getDeadDisplayName` | `deathReport: DeathReport` | `string?` | Returns victim's display name (`DisplayName`, character name, or fallback) |
| `getKillerDisplayName` | `deathReport: DeathReport` | `string?` | Returns killer's display name (`DisplayName`, character name, or `nil`) |
| `getDeadColor` | `deathReport: DeathReport` | `Color3?` | Returns victim's team color if assigned |
| `getKillerColor` | `deathReport: DeathReport` | `Color3?` | Returns killer's team color if assigned |
| `getDefaultColor` | *none* | `Color3` | Returns fallback display color `Color3.new(0.9, 0.9, 0.9)` |
| `involvesPlayer` | `deathReport: DeathReport, player: Player` | `boolean` | Returns `true` if `player` is the victim or killer |

---

## Stats Tracking & Binders

### `PlayerDeathTracker & PlayerKillTracker`

Stateful classes wrapping an `IntValue` that track individual player statistics.

- **`PlayerDeathTracker`**: Listens to `DeathReportService:ObservePlayerDeathReports(player)` and increments its bound `IntValue.Value` on each death.
- **`PlayerKillTracker`**: Listens to `DeathReportService:ObservePlayerKillerReports(player)` and increments its bound `IntValue.Value` on each kill.

### `TeamKillTracker`

Monitors `DeathReportService.NewDeathReport` and increments an `IntValue` score whenever a kill is performed by a player on the target `Team`.

### `PlayerKillTrackerAssigner`

Automates stats tracking by creating bound `IntValue` instances under `player` when they join the server:
- Instantiates `PlayerKillTracker` (`score.Name = "PlayerKillTracker"`)
- Instantiates `PlayerDeathTracker` (`score.Name = "PlayerDeathTracker"`)

### `DeathTrackedHumanoid`

A `PlayerHumanoidBinder` component attached to humanoids. It connects to `Humanoid.Health` changes and ensures `DeathReportService:ReportHumanoidDeath` is invoked exactly once when `Health <= 0`.

---

## End-to-End Integration Examples

### 1. Game Initialization with ServiceBag

```luau
-- Server Script
const require = require(game:GetService("ReplicatedStorage").Shared.Loader).load()

const DeathReportService = require("DeathReportService")
const PlayerKillTrackerAssigner = require("PlayerKillTrackerAssigner")
const ServiceBag = require("ServiceBag")

const serviceBag = ServiceBag.new()
const deathReportService = serviceBag:GetService(DeathReportService)

serviceBag:Init()
serviceBag:Start()

-- Enable automatic player kill/death tracker assignment
const assigner = serviceBag:Add(PlayerKillTrackerAssigner.new(serviceBag))
```

### 2. Weapon Data Retriever Setup

```luau
-- Server Script: Register weapon tracking for custom gun / sword systems
deathReportService:AddWeaponDataRetriever(function(humanoid: Humanoid)
	const character = humanoid.Parent
	if not character then
		return nil
	end

	-- Check for equipped tool
	const tool = character:FindFirstChildWhichIsA("Tool")
	if tool then
		return DeathReportUtils.createWeaponData(tool)
	end

	-- Check for custom last-damaged attribute
	const lastWeapon = character:GetAttribute("LastDamagingWeaponInstance")
	if typeof(lastWeapon) == "Instance" then
		return DeathReportUtils.createWeaponData(lastWeapon)
	end

	return nil
end)
```

### 3. Building a Rich Killfeed UI

```luau
-- Client LocalScript
const require = require(game:GetService("ReplicatedStorage").Shared.Loader).load()

const DeathReportServiceClient = require("DeathReportServiceClient")
const DeathReportUtils = require("DeathReportUtils")
const ServiceBag = require("ServiceBag")

const serviceBag = ServiceBag.new()
const deathReportClient = serviceBag:GetService(DeathReportServiceClient)

serviceBag:Init()
serviceBag:Start()

deathReportClient.NewDeathReport:Connect(function(deathReport)
	const victimName = DeathReportUtils.getDeadDisplayName(deathReport) or "Unknown Entity"
	const killerName = DeathReportUtils.getKillerDisplayName(deathReport)
	const victimColor = DeathReportUtils.getDeadColor(deathReport) or DeathReportUtils.getDefaultColor()
	const killerColor = DeathReportUtils.getKillerColor(deathReport) or DeathReportUtils.getDefaultColor()
	const weapon = deathReport.weaponData.weaponInstance

	const weaponName = if weapon then weapon.Name else "Environment"

	if killerName then
		print(`[KillFeed] <font color="#{killerColor:ToHex()}">{killerName}</font> [{weaponName}] <font color="#{victimColor:ToHex()}">{victimName}</font>`)
	else
		print(`[KillFeed] <font color="#{victimColor:ToHex()}">{victimName}</font> died ({weaponName})`)
	end
end)
```

### 4. Leaderboard & K/D Tracking

```luau
-- Server Script: Log player K/D ratio changes
deathReportService.NewDeathReport:Connect(function(deathReport)
	if deathReport.killerPlayer then
		const kills = assigner:GetPlayerKills(deathReport.killerPlayer)
		print(`{deathReport.killerPlayer.Name} total kills: {kills or 0}`)
	end
end)
```

---

## Edge Cases & Reliability

- **StreamingEnabled & Delayed Character Load**: On the client, if a character model has not yet streamed in when a ByteNet packet arrives, `DeathReportServiceClient` resolves the `playerId` to the `Player` object and falls back to `player.Character` or `player` to prevent crashes.
- **Double Death Protection**: `DeathTrackedHumanoid` disconnects its health listener upon the first frame where `Health <= 0`, guaranteeing each humanoid death is reported only once.
- **Player Disconnection Handling**: `DeathReportProcessor` listens to `Players.PlayerRemoving` and completes all pending subscriptions for departing players to prevent memory leaks.

---

## Unit Testing

Unit tests for `DeathReportUtils` are written with **Jest** in `DeathReportUtils.spec.luau`.

Run unit tests via Nevermore's test runner or CLI:

```bash
selene lib/deathreport/
stylua --check lib/deathreport/
```
