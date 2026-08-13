# SaveSlot

`SaveSlotService` adapts Nevermore's SaveSlot lifecycle to this fork's
`PlayerDataStoreService`. It does not open another DataStore or ProfileStore session.
Instead, each player's existing profile contains account-wide data plus a
`SaveSlots` branch:

```text
Profile
├── account-wide fields
└── SaveSlots
    ├── ActiveSlotId
    ├── LastActiveSlotId
    ├── Metadata[slotId]
    └── Slots[slotId]       (stored server-side; active slot mirrors read-only)
```

Selecting a slot changes which `Slots[slotId]` table the server API reads and
writes. The entire `SaveSlots` branch is hidden from ordinary PlayerDataStoreService
replication before profiles load. Compact metadata and lazy selected-slot data
use the dedicated SaveSlot transport; inactive slots never leave the server.

This is intentionally different from Quenty's original implementation, which
creates DataStore substores. Your PlayerDataStoreService already owns one session-locked
ProfileStore profile per player; opening or swapping a second session would
fight that ownership model.

## ProfileData setup

The consuming game must add this shape to both `ProfileData.Template` and
`ProfileData.Schema`, and export `SlotDataSchema`. SaveSlot uses that exported
schema to compress lazy active-slot query results on both the server and client.
It must match the data passed to `SetDefaultSlotData`. Before starting the
ServiceBag, configure either `SetDefaultSlotData` or
`SetDefaultSlotDataProvider`; the service will not guess a schema-dependent
default.

```luau
const Squash = require("@game/ReplicatedStorage/Packages/Squash")

const SlotMetadataSchema = Squash.record({
	SlotId = Squash.string(),
	SlotIndex = Squash.u16(),
	SlotName = Squash.string(),
	CreatedTime = Squash.f64(),
	LastPlayedTime = Squash.f64(),
	Summary = Squash.string(),
})

const SlotDataSchema = Squash.record({
	Coins = Squash.f64(),
	Level = Squash.u16(),
})

local ProfileData = {}

-- Required by SaveSlotSerializationUtils on both realms.
ProfileData.SlotDataSchema = SlotDataSchema

ProfileData.Template = {
	-- Account-wide fields belong outside SaveSlots.
	Settings = {},

	SaveSlots = {
		ActiveSlotId = "",
		LastActiveSlotId = "",
		Metadata = {},
		Slots = {},
	},
}

ProfileData.Schema = Squash.record({
	Settings = Squash.record({}),

	SaveSlots = Squash.record({
		ActiveSlotId = Squash.string(),
		LastActiveSlotId = Squash.string(),
		Metadata = Squash.map(Squash.string(), SlotMetadataSchema),
		Slots = Squash.map(Squash.string(), SlotDataSchema),
	}),
})

return ProfileData
```

Do not put account entitlements, settings, purchase receipts, or other
cross-character state inside `SlotDataSchema` unless each slot should own a
separate copy.

## Server setup

Configure the service after `ServiceBag:Init()` and before
`ServiceBag:Start()`:

```luau
const SaveSlotService = require("@game/ReplicatedStorage/Packages/SaveSlotService")
const ServiceBag = require("@game/ReplicatedStorage/Packages/ServiceBag")

local serviceBag = ServiceBag.new()
local saveSlots = serviceBag:GetService(SaveSlotService)

serviceBag:Init()

saveSlots:SetMaxSlotCount(3)
saveSlots:SetDefaultSlotData({
	Coins = 0,
	Level = 1,
})

saveSlots:SetDefaultSummaryProvider(function(_player, slotData)
	return `Level {slotData.Level} - {slotData.Coins} coins`
end)

-- Optional: leave every player unselected until UI or game code chooses.
-- saveSlots:RequireExplicitSelection()

serviceBag:Start()
```

Without explicit selection, joining players select their valid teleport slot,
then their last active slot, then slot index 1. Index 1 is created automatically
when none exists.

## Server usage

Wait for initialization before the first synchronous read:

```luau
saveSlots:ReadyAsync(player):Then(function()
	print(saveSlots:GetActiveSlotId(player))
	print(saveSlots:GetSlotList(player))

	saveSlots:SetValue(player, "Coins", function(coins)
		return coins + 25
	end)

	print(saveSlots:GetValue(player, "Coins"))
end)
```

Slot management is promise-based:

```luau
saveSlots:CreateSlotAsync(player, 2, {
	SlotName = "Mage",
	Summary = "New character",
}):Then(function(slotId)
	return saveSlots:SelectSlotAsync(player, slotId)
end)

saveSlots:SetSlotMetadataAsync(player, slotId, {
	SlotName = "Archmage",
})

-- The active slot cannot be deleted.
saveSlots:DeleteSlotAsync(player, inactiveSlotId)
```

The active data helpers are:

- `GetActiveSlotData(player)`
- `GetLastActiveSlotId(player)`
- `GetValue(player, path)`
- `SetValue(player, path, valueOrCallback)`
- `UpdateActiveSlot(player, callback)`
- `ObserveActiveSlotData(player)`
- `ObserveAtKey(player, path)`
- `ObserveSlotMetadata(player, slotId)`

Writing through these helpers keeps slot routing centralized and refreshes the
configured summary provider. `PlayerDataStoreService` remains responsible for autosaving,
shutdown flushing, profile reconciliation, and datastore failure handling.

## Client usage

The client requests compact slot metadata during startup. `ReadyAsync()` waits
for that metadata, but deliberately does not request gameplay data. Use an async
read when you need a one-time active-slot snapshot, or subscribe to an observer
to keep a value current:

```luau
const SaveSlotServiceClient = require("@game/ReplicatedStorage/Packages/SaveSlotServiceClient")

local saveSlotsClient = serviceBag:GetService(SaveSlotServiceClient)

saveSlotsClient:ReadyAsync():Then(function()
	for _, metadata in saveSlotsClient:GetSlotList() do
		print(metadata.SlotIndex, metadata.SlotName, metadata.Summary)
	end

	saveSlotsClient:GetValueAsync("Coins"):Then(function(coins)
		print("Coins", coins)
	end)
end)

saveSlotsClient:ObserveActiveSlotId():Subscribe(function(slotId)
	print("Active slot", slotId)
end)

saveSlotsClient:ObserveAtKey("Coins"):Subscribe(function(coins)
	print("Coins changed", coins)
end)

saveSlotsClient:ObserveActiveSlotData():Subscribe(function(slotData)
	print("Active slot data", slotData)
end)

saveSlotsClient:CreateSlotAsync(2, { SlotName = "Mage" }):Then(function(slotId)
	return saveSlotsClient:SelectSlotAsync(slotId)
end)
```

`GetActiveSlotDataAsync` and `GetValueAsync` perform one compressed query.
`GetActiveSlotData` and `GetValue` read the resulting cache synchronously.
Observers perform the first query lazily, receive only a compact `u32`
invalidation when server data changes, and re-query at most once per deferred
batch. Unsubscribing the last observer disables invalidations on the server.

The wire format never sends metadata tables through `ByteNet.unknown`:

- Squash records remove keys such as `SlotName`, `Summary`, and `CreatedTime`
  from the payload because both realms already know the schema.
- Slot GUIDs occupy 16 bytes instead of 36-byte strings.
- Active and last-active selections use their `u16` slot indexes rather than
  repeating GUIDs.
- Timestamps use `u32`, and slot state changes made in one task are coalesced
  into one buffer.
- Active gameplay data is serialized by `ProfileData.SlotDataSchema`, and only
  the currently selected slot can be queried.

All client gameplay access remains read-only. The server owns every write, and
inactive slot data never leaves the server.

## Cmdr

The server registers these `DefaultAdmin` commands through `CmdrService`:

- `list-save-slots player`
- `set-save-slot player slotIndex`
- `create-save-slot player slotIndex`
- `delete-save-slot player slotIndex`

## Teleports

To select a known slot after teleporting, include its ID under
`IncomingSaveSlotId` in `TeleportData`. Invalid or deleted IDs fall back to the
normal selection flow.

## Migration note

This storage layout does not read Quenty SaveSlot's old
`SaveSlots.slots.<slotId>` DataStore substores. Existing games using that
package need a one-time migration into the `ProfileData.SaveSlots` branch.
