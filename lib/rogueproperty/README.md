# RogueProperty

`RogueProperty` is a reactive property system whose final value is computed from
a base value plus an ordered list of temporary modifiers. It stores runtime state
on Roblox Instances, exposes ValueObject-like access, supports nested tables and
homogeneous arrays, and lets unrelated systems add or remove effects without
overwriting each other.

For a numeric property, the common computation is:

```text
base value
   │
   ├── setter       (order 0, optional override)
   ├── additive(s)  (order 1)
   └── multiplier(s)(order 2)
   ▼
computed Value
```

For example, a base speed of `16`, an additive of `4`, and multipliers `1.5` and
`0.5` produce `(16 + 4) * 1.5 * 0.5 = 15`.

RogueProperty is runtime state, not persistence. PlayerDataStoreService should save the
authoritative setting or stat; RogueProperty can then represent its current base
value plus temporary buffs, debuffs, overrides, and local presentation effects.

## When it is useful

Good uses include:

- Character movement speed with equipment, buffs, and slows.
- Camera FOV with sprint, aiming, damage, and cutscene overrides.
- SoundGroup volume with settings, ducking, and zone modifiers.
- UI scale or opacity with accessibility and temporary animation factors.
- Any property where multiple systems need independent, removable influence.

A plain `ValueObject` is simpler when there is only one writer and no modifier
composition is required.

## Package children

### Definitions and tables

| Module | Responsibility |
| --- | --- |
| `Definition/RoguePropertyDefinition` | Declares one typed leaf property, its name, default, storage class, and assignment rules. |
| `Definition/RoguePropertyTableDefinition` | Builds nested dictionary/array schemas and returns cached runtime tables for adornees. Normal entry point. |
| `Definition/RoguePropertyDefinitionArrayHelper` | Holds the inferred homogeneous element schema for an array definition. |
| `Array/RoguePropertyArrayConstants` | Defines the internal array-element naming prefix. |
| `Array/RoguePropertyArrayUtils` | Infers array schemas and converts between array indices and stored attributes/Instances. |

### Runtime implementations

| Module | Responsibility |
| --- | --- |
| `Implementation/RogueProperty` | Runtime leaf property: base/computed values, observation, assignment inversion, and modifier creation. |
| `Implementation/RoguePropertyTable` | Runtime nested table with member/index access and whole-table reads/writes. |
| `Implementation/RoguePropertyArrayHelper` | Creates, reads, writes, removes, and observes dynamic array entries. |
| `Implementation/RoguePropertyUtils` | Encodes and decodes table values through JSON when required by storage. |

### Modifiers

| Module | Responsibility |
| --- | --- |
| `Modifiers/RogueModifierInterface` | Tie contract shared by every modifier: order, source, forward transform, inverse transform, and observation. |
| `Modifiers/RoguePropertyModifierData` | Stores modifier `Enabled`, `Order`, and source-link metadata. |
| `Modifiers/Implementations/RogueModifierBase` | Shared binder base class. |
| `Modifiers/Implementations/RogueSetter` | Replaces the incoming value while enabled. Default order `0`. |
| `Modifiers/Implementations/RogueAdditive` | Adds its ValueBase value. Default order `1`. |
| `Modifiers/Implementations/RogueMultiplier` | Multiplies by its ValueBase value. Default order `2`. |

### Services, cache, and constants

| Module | Responsibility |
| --- | --- |
| `RoguePropertyService` | Initializes the cache, Tie realm, and modifier binders. Only the server may initialize authoritative base storage. |
| `Cache/RoguePropertyCacheService` | Returns one weakly keyed cache per definition. |
| `Cache/RoguePropertyCache` | Maps an adornee to its reused runtime property/table object. |
| `RoguePropertyBaseValueTypes` | Internal `ANY` versus `INSTANCE` storage request enum. |
| `RoguePropertyBaseValueTypeUtils` | Validates those internal storage request values. |
| `RoguePropertyConstants` | Contains the attribute sentinel used when a property migrates to Instance storage. |

## Service setup

Register the same service in each ServiceBag that will use RogueProperty:

```luau
const require = require("../Loader").load()

const RoguePropertyService = require("RoguePropertyService")
const ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()
serviceBag:GetService(RoguePropertyService)
serviceBag:Init()
serviceBag:Start()
```

`RoguePropertyService` initializes:

- `RoguePropertyCacheService`
- `TieRealmService`
- `RogueSetter`, `RogueAdditive`, and `RogueMultiplier` binders

On the server, definitions may create missing base-value storage. On the client,
properties consume replicated storage and place purely local modifiers in a
non-authoritative local container when necessary.

## Declaring a property table

Definitions should live in shared ModuleScripts:

```luau
-- CharacterStats.luau
--!strict

const require = require("../Loader").load()

const RoguePropertyTableDefinition = require("RoguePropertyTableDefinition")

return RoguePropertyTableDefinition.new("CharacterStats", {
	MoveSpeed = 16,
	JumpPower = 50,
	Damage = 10,
	IsStunned = false,
	DisplayColor = Color3.new(1, 1, 1),

	Regeneration = {
		Amount = 2,
		Interval = 1,
	},

	ResistanceSlots = { 0, 0, 0 },
})
```

The default value is also the schema. Assignments must preserve declared types
and dictionary keys.

Supported scalar defaults are:

- `string`
- `number`
- `boolean`
- `Color3`
- `BrickColor`
- `Vector3`
- `CFrame`

Nested tables become nested `RoguePropertyTableDefinition` objects. Numeric keys
create a homogeneous array definition inferred from the first element. Every
default array element must have the same compatible type or table shape.

## Getting runtime properties

Resolve the definition for an adornee:

```luau
const CharacterStats = require("CharacterStats")

local stats = CharacterStats:Get(serviceBag, character)
```

The cache returns the same runtime table for the same definition and adornee, so
calling `Get()` from several systems does not create several competing wrappers.

Read leaf properties through `.Value`:

```luau
print(stats.MoveSpeed.Value)       -- computed value
print(stats.JumpPower.Value)
print(stats.Regeneration.Amount.Value)
```

Write the desired computed value through `.Value`:

```luau
stats.MoveSpeed.Value = 24
stats.Regeneration.Interval.Value = 0.5
```

Assigning `stats.MoveSpeed` directly is rejected. The extra `.Value` is
intentional because `stats.MoveSpeed` is the RogueProperty object.

## Base value versus computed value

Every leaf has two useful values:

- **Base value**: authoritative input before modifiers.
- **Computed value**: result after ordered modifiers.

```luau
local speed = stats.MoveSpeed

print(speed:GetBaseValue())
print(speed:GetValue())
print(speed.Value) -- alias for GetValue()
```

`SetBaseValue()` writes the raw input and leaves every modifier intact:

```luau
speed:SetBaseValue(20)
```

`SetValue()` and `.Value =` target the final computed value. RogueProperty walks
the current modifiers in reverse and applies their inverse operations to derive
the base value that should produce the requested result:

```luau
speed:SetValue(30)
speed.Value = 30
```

Use `SetBaseValue()` for authoritative stat/config changes. Use `SetValue()` when
the caller genuinely means “make the currently observed value equal this,” even
with invertible modifiers present.

Setter inversion cannot reconstruct information hidden by an override, so avoid
using computed assignment as a substitute for clear ownership of the base value.

## Observing values

`Observe()` emits the initial computed value and every later base or modifier
change:

```luau
maid:Add(stats.MoveSpeed:Observe():Subscribe(function(value)
	humanoid.WalkSpeed = value
end))
```

`.Changed` provides a Signal-like facade and skips the initial value:

```luau
maid:Add(stats.MoveSpeed.Changed:Connect(function(value)
	print("Speed changed", value)
end))
```

`ObserveBrio(predicate)` emits matching values with explicit lifetimes:

```luau
maid:Add(stats.IsStunned:ObserveBrio(function(isStunned)
	return isStunned
end):Subscribe(function(brio)
	local stunnedMaid = brio:ToMaid()
	print("Stun began")

	stunnedMaid:Add(function()
		print("Stun ended")
	end)
end))
```

Whole dictionary tables can also be read or observed:

```luau
print(stats:GetValue())

maid:Add(stats:Observe():Subscribe(function(currentStats)
	print(currentStats.MoveSpeed, currentStats.JumpPower)
end))
```

For large definitions, observing individual leaves avoids rebuilding a combined
dictionary when unrelated members change.

## Creating modifiers

Modifier methods return ValueBase Instances. Their Instance lifetime is the
modifier lifetime, so put them in a Maid or destroy them explicitly.

### Additive

```luau
local boots = workspace.SpeedBoots
local bonus = maid:Add(stats.MoveSpeed:CreateAdditive(4, boots))

-- Change the bonus without replacing it.
bonus.Value = 6
```

### Multiplier

```luau
local sprintController = character
local sprint = maid:Add(stats.MoveSpeed:CreateMultiplier(1.5, sprintController))

-- Stop sprinting.
sprint:Destroy()
```

### Setter

```luau
local stunEffect = character:FindFirstChild("StunEffect")
local forcedStop = maid:Add(stats.MoveSpeed:CreateSetter(0, stunEffect))
```

A setter replaces the value flowing into later modifiers. With the default
orders, additives and multipliers still run after it. If speed must remain
exactly zero regardless of later modifiers, give the setter a later order as
shown below.

### Named additive

`GetNamedAdditive()` reuses one additive by name instead of stacking duplicates:

```luau
local armorPenalty = stats.MoveSpeed:GetNamedAdditive("ArmorPenalty", armor)
if armorPenalty then
	armorPenalty.Value = -3
end
```

The stored Instance name becomes `ArmorPenaltyAdditive`.

## Modifier metadata and ordering

Every modifier has reactive metadata managed by `RoguePropertyModifierData`:

```luau
const RoguePropertyModifierData = require("RoguePropertyModifierData")

local data = RoguePropertyModifierData:Create(sprint)
data.Enabled.Value = false
data.Order.Value = 20
data.RoguePropertySourceLink.Value = sprintController
```

| Field | Purpose |
| --- | --- |
| `Enabled` | Disabled modifiers pass the incoming value through unchanged. |
| `Order` | Ascending transform order. Changes are observed and re-sort the chain. |
| `RoguePropertySourceLink` | Optional ObjectValue link explaining which Instance owns or caused the modifier. |

Default orders are:

| Modifier | Order | Operation |
| --- | ---: | --- |
| Setter | 0 | Replace incoming value. |
| Additive | 1 | `value + additive`. |
| Multiplier | 2 | `value * multiplier`. |

Modifiers with equal orders should not be given order-sensitive behavior because
their tie order is not a stable gameplay contract.

## Nested tables

Nested definitions are accessed using the same property-object pattern:

```luau
local regeneration = stats.Regeneration

print(regeneration.Amount.Value)
regeneration.Interval.Value = 0.75

regeneration.Value = {
	Amount = 4,
	Interval = 0.5,
}
```

You may read, write, or observe the complete nested table with `Value`,
`SetValue()`, `GetValue()`, and `Observe()`. Leaf access is preferable when only
one member changes frequently.

The definition enforces expected keys. Unknown dictionary members and wrong
types fail with a path-aware error such as `CharacterStats.Regeneration.Amount`.

## Arrays

A numeric default table declares a homogeneous array:

```luau
ResistanceSlots = { 0, 0, 0 }
```

Runtime access returns a RogueProperty for each index:

```luau
print(stats.ResistanceSlots[1].Value)
stats.ResistanceSlots[2].Value = 0.25

stats.ResistanceSlots.Value = { 0.1, 0.25, 0.5, 0.75 }
```

Array writes can grow or shrink the stored set. Internal names such as
`RoguePropertyArrayEntry_1` are implementation details.

Arrays of tables are supported when every entry follows the same shape:

```luau
Slots = {
	{ ItemId = "", Quantity = 0 },
	{ ItemId = "", Quantity = 0 },
}
```

Avoid mixed dictionary-and-array tables. Array observation is implemented by
combining the currently discovered element properties, and dynamic structural
replication has more caveats than fixed dictionary leaves. For high-frequency or
authoritative inventory data, a dedicated serialized data service is usually a
better boundary.

## Instance storage and replication

RogueProperty stores state in the adornee's data model so normal Roblox
replication can expose authoritative server values.

For the `CharacterStats` example, the hierarchy may look like:

```text
Character
└── CharacterStats (Folder)
    ├── attributes: MoveSpeed, JumpPower, Damage, IsStunned
    ├── Regeneration (Folder)
    │   └── attributes: Amount, Interval
    └── ResistanceSlots (Folder)
        └── indexed attributes or ValueBases
```

Scalar values prefer attributes. A property that needs child modifier Instances
is migrated to a ValueBase container, and its old attribute is replaced with the
internal `_DATAMODEL_INSTANCE` sentinel. Game code should never depend on this
physical choice; always use the RogueProperty object.

Storage classes are inferred from defaults:

| Luau/Roblox type | Storage class when Instance-backed |
| --- | --- |
| `number` | `NumberValue` |
| `string` | `StringValue` |
| `boolean` | `BoolValue` |
| `Color3` | `Color3Value` |
| `BrickColor` | `BrickColorValue` |
| `Vector3` | `Vector3Value` |
| `CFrame` | `CFrameValue` |
| nested table | `Folder` hierarchy |

The server may initialize missing folders, attributes, and ValueBases. Client
property access does not authoritatively initialize missing replicated values.
When a client needs a local-only modifier, RogueProperty can create a local
`Camera` modifier container named after the property.

Normal Roblox replication is not validation. Server gameplay must still own and
validate authoritative changes.

## How Tie is used

Each modifier binder implements `RogueModifierInterface` through Tie:

```text
modifier NumberValue
├── binder tag: RogueAdditive / RogueMultiplier / RogueSetter
├── metadata: Enabled, Order, Source
└── Tie interface
    ├── GetModifiedVersion(value)
    ├── ObserveModifiedVersion(observable)
    └── GetInvertedVersion(value)
```

RogueProperty discovers modifier implementations beneath its storage containers,
sorts them by the observed `Order` property, and composes their observable
transforms. This is why custom code should create modifiers through the public
methods or implement the full Tie modifier contract deliberately.

## Public API summary

### RogueProperty leaf

| Method/property | Purpose |
| --- | --- |
| `.Value` | Gets or sets the computed value. |
| `.Changed` | Signal-like computed-value changes, excluding the initial value. |
| `GetValue()` | Computes base plus current modifiers. |
| `SetValue(value)` | Inverts current modifiers and writes a base that targets the requested computed value. |
| `GetBaseValue()` | Reads the raw decoded base. |
| `SetBaseValue(value)` | Writes the raw base without removing modifiers. |
| `Observe()` | Observes the computed value. |
| `ObserveBrio(predicate)` | Observes matching values with lifetime. |
| `CreateSetter(value, source)` | Adds an order-0 override. |
| `CreateAdditive(amount, source)` | Adds an order-1 addition. |
| `CreateMultiplier(amount, source)` | Adds an order-2 multiplier. |
| `GetNamedAdditive(name, source)` | Finds or creates one reusable named additive. |
| `GetRogueModifiers()` | Returns current modifiers sorted by order. |
| `GetDefinition()` | Returns the leaf definition. |
| `GetAdornee()` | Returns the owning Instance. |

### RoguePropertyTable

| Method/property | Purpose |
| --- | --- |
| `table.Member` | Returns one child RogueProperty or RoguePropertyTable. |
| `table[index]` | Returns one array element property/table. |
| `.Value`, `GetValue()` | Reads the complete computed table. |
| `SetValue(table)` | Writes complete computed values. |
| `GetBaseValue()` | Reads the complete base table. |
| `SetBaseValue(table)` | Writes complete base values. |
| `Observe()` | Observes the combined dictionary or array. |
| `GetRogueProperty(name)` | Retrieves a named child explicitly. |
| `GetRogueProperties()` | Returns all child property objects. |
| `GetContainer()` | Returns the physical Folder when available. Infrastructure use. |

### RoguePropertyTableDefinition

| Method | Purpose |
| --- | --- |
| `new(name, defaults)` | Declares a named schema. |
| `Get(serviceBag, adornee)` | Returns the cached runtime table. |
| `GetContainer(serviceBag, adornee)` | Returns its physical Folder. |
| `ObserveContainerBrio(serviceBag, adornee)` | Observes the Folder lifetime. |
| `GetDefinition(name)` | Returns a named child definition. |
| `CanAssign(value, strict)` | Validates shape and types. |

## Ownership and practical constraints

- Keep modifier Instances in a Maid; destroying them removes their effect.
- The server should own base values used for authoritative gameplay.
- RogueProperty is not DataStore persistence or remote-command validation.
- Use `SetBaseValue()` when changing authoritative input and `.Value` when
  targeting the final output intentionally.
- Definitions use their defaults as schemas, so preserve types and expected keys.
- Use leaf observations for hot paths; whole-table observation allocates combined
  tables.
- Avoid order-sensitive behavior between modifiers with the same `Order`.
- Treat folders, attributes, sentinels, tags, and ValueBases as internal storage.
- Prefer dedicated serializers for large, high-frequency, or inventory-like
  dynamic collections.
