# Tie

`Tie` declares an interface once, implements it with an ordinary Luau object,
and exposes that implementation through Roblox Instances. Consumers can discover
the interface from an adornee without importing or retaining the original object.

It is a bridge between two styles of code:

```text
Luau implementation object
        │
        │ TieDefinition:Implement()
        ▼
Instance-backed contract
(attributes, ValueBases, BindableFunctions, BindableEvents)
        │
        │ TieDefinition:Find(), :Observe(), :Get()
        ▼
TieInterface facade
```

Tie is not networking. Methods and signals use `BindableFunction` and
`BindableEvent`, not RemoteEvents. A server Tie method does not become a client
RPC. Realms describe which interface members are valid in each runtime and allow
server, client, and shared implementations to coexist on the same adornee.

Tie is useful for binder classes, component contracts, runtime capabilities, and
systems that need to discover behavior from an Instance. A direct module method
call is simpler when the caller already owns the object and no discovery or
reactive lifetime is needed.

## Core vocabulary

| Term | Meaning |
| --- | --- |
| Definition | The named contract and its method, signal, and property declarations. |
| Adornee | The Roblox Instance that conceptually owns the capability. |
| Implementer | The ordinary Luau object/table that supplies contract members. |
| Implementation | The lifetime object returned by `Implement()`. It creates and owns the instance representation. |
| Implementation parent | A generated `Camera` or `Configuration` beneath the adornee containing the contract members. |
| Interface | A proxy used to call methods, access properties, and connect signals. |
| Realm | `server`, `client`, or `shared`; determines required and visible members. |
| Brio | A value paired with an explicit lifetime, used by reactive discovery APIs. |

## Package children

### Core

| Module | Responsibility |
| --- | --- |
| `Shared/TieDefinition` | Declares contracts, creates implementations, discovers interfaces, and exposes synchronous/reactive lookup APIs. This is the normal entry point. |
| `Shared/TieImplementation` | Owns one generated implementation parent and the member implementations beneath it. |
| `Shared/TieInterface` | Dynamic facade that resolves declared members into method, signal, or property interfaces. |
| `Shared/Utils/TieUtils` | Encodes tables, functions, symbols, and userdata through Bindables without losing tuple/nil argument positions. |

### Realm support

| Module | Responsibility |
| --- | --- |
| `Shared/Realms/TieRealms` | Enum-like values `SHARED`, `CLIENT`, and `SERVER`. |
| `Shared/Realms/TieRealmUtils` | Validates realms and infers the current realm from `RunService`. |
| `Shared/Services/TieRealmService` | Stores the realm associated with a ServiceBag. Packages such as RogueProperty use it when creating or querying Tie implementations. |

### Generic member foundation

| Module | Responsibility |
| --- | --- |
| `Shared/Members/TieMemberDefinition` | Base declaration logic for realm requirements, allowed access, names, and friendly error text. |
| `Shared/Members/TieMemberInterface` | Base dynamic lookup for an implementation parent and observation of that parent's lifetime. |

### Method members

| Module | Responsibility |
| --- | --- |
| `Members/Methods/TieMethodDefinition` | Declares a method member. |
| `Members/Methods/TieMethodImplementation` | Creates a BindableFunction and forwards invocation into the implementer with the correct `self`. |
| `Members/Methods/TieMethodInterfaceUtils` | Produces the colon-callable method closure and resolves the correct BindableFunction. |

### Signal members

| Module | Responsibility |
| --- | --- |
| `Members/Signals/TieSignalDefinition` | Declares a signal member. |
| `Members/Signals/TieSignalImplementation` | Creates a BindableEvent and mirrors events between it and the supplied Signal-like object. |
| `Members/Signals/TieSignalInterface` | Exposes `Fire`, `Connect`, `Once`, `Wait`, and BindableEvent observation. |
| `Members/Signals/TieSignalConnection` | Connection object that follows changing implementations and disconnects cleanly. |

### Property members

| Module | Responsibility |
| --- | --- |
| `Members/Properties/TiePropertyDefinition` | Declares a required property or a property with a default value. |
| `Members/Properties/TiePropertyImplementation` | Chooses attributes, ValueBases, or an encoded BindableFunction and keeps reactive values synchronized. |
| `Members/Properties/TiePropertyInterface` | Exposes `.Value`, `.Changed`, `Observe()`, and `ObserveBrio()`. |
| `Members/Properties/TiePropertyImplementationUtils` | Reuses or replaces the physical property Instance when its storage class changes. |

## Realm service setup

Packages that use Tie through a ServiceBag should register `TieRealmService`:

```luau
const require = require("../Loader").load()

const ServiceBag = require("ServiceBag")
const TieRealmService = require("TieRealmService")

local serviceBag = ServiceBag.new()
local tieRealmService = serviceBag:GetService(TieRealmService)

serviceBag:Init()
serviceBag:Start()

print(tieRealmService:GetTieRealm())
```

The service infers `server` or `client` during `Init()`. `SetTieRealm()` exists for
controlled environments and tests that need an explicit realm.

`TieDefinition` itself does not require ServiceBag. Every major lookup and
implementation method accepts an explicit realm, and the `.Server` and `.Client`
facades provide convenient defaults.

## Declaring a contract

Create definitions in shared modules so every consumer uses the same declaration:

```luau
-- HealthInterface.luau
--!strict

const require = require("../Loader").load()

const TieDefinition = require("TieDefinition")

return TieDefinition.new("Health", {
	-- Shared members are visible in both realms.
	GetHealth = TieDefinition.Types.METHOD,
	HealthChanged = TieDefinition.Types.SIGNAL,
	Health = 100,
	DisplayName = TieDefinition.Types.PROPERTY,

	[TieDefinition.Realms.SERVER] = {
		Damage = TieDefinition.Types.METHOD,
	},

	[TieDefinition.Realms.CLIENT] = {
		Flash = TieDefinition.Types.SIGNAL,
	},
})
```

Declaration values have these meanings:

| Declaration | Meaning |
| --- | --- |
| `TieDefinition.Types.METHOD` | Required callable method in the member's realm. |
| `TieDefinition.Types.SIGNAL` | Required Signal-like object in the member's realm. |
| `TieDefinition.Types.PROPERTY` | Required property with no fallback value. |
| Any other non-nil value | Property whose default is that value; the implementer may omit it. |
| `[TieDefinition.Realms.SERVER] = {...}` | Members required/allowed for server and shared implementations. |
| `[TieDefinition.Realms.CLIENT] = {...}` | Members required/allowed for client and shared implementations. |

Members at the root of the declaration are shared.

## Implementing a definition

An implementation is an ordinary object whose keys match the declaration:

```luau
const Signal = require("Signal")
const ValueObject = require("ValueObject")

local HealthController = {}
HealthController.__index = HealthController

function HealthController.new()
	local self = setmetatable({}, HealthController)
	self.Health = ValueObject.new(100, "number")
	self.DisplayName = ValueObject.new("Enemy", "string")
	self.HealthChanged = Signal.new()
	return self
end

function HealthController.GetHealth(self)
	return self.Health.Value
end

function HealthController.Damage(self, amount)
	self.Health.Value = math.max(0, self.Health.Value - amount)
	self.HealthChanged:Fire(self.Health.Value)
end
```

Bind it to an adornee in the appropriate realm and keep the returned
`TieImplementation` alive:

```luau
const HealthInterface = require("HealthInterface")

local controller = HealthController.new()

maid:Add(controller.Health)
maid:Add(controller.DisplayName)
maid:Add(controller.HealthChanged)

local implementation = maid:Add(
	HealthInterface.Server:Implement(npcModel, controller)
)
```

Tie invokes implementation methods as `method(actualSelf, ...)`. Define those
functions with `self`, even though the generated contract is backed by a
BindableFunction.

Destroying the `TieImplementation` removes its generated parent and all member
Instances. The implementation does not assume ownership of the implementer or
its Signals/ValueObjects; manage those through your own Maid as shown above.

### Updating an implementation through the proxy

The returned implementation also proxies declared members:

```luau
implementation.Health.Value = 75
implementation:Damage(10)
```

Assigning a declared property on the implementation object replaces that
property's backing implementation. This is an advanced operation; normal code
usually mutates the supplied `ValueObject` or ValueBase instead.

## Consuming an interface

Use `Find()` when an implementation may or may not exist:

```luau
local health = HealthInterface.Server:Find(npcModel)
if health then
	print(health:GetHealth())
	health:Damage(15)
end
```

Interface methods must use colon syntax. Tie deliberately rejects
`health.GetHealth()` because the facade itself must be the first argument.

Signals mirror the familiar Signal API:

```luau
local connection = health.HealthChanged:Connect(function(newHealth)
	print("Health changed", newHealth)
end)

health.HealthChanged:Once(function(newHealth)
	print("First change only", newHealth)
end)

health.HealthChanged:Fire(50)
```

Properties expose a ValueObject-like interface:

```luau
print(health.Health.Value)
health.Health.Value = 50

maid:Add(health.Health.Changed:Connect(function(value)
	print("Property changed", value)
end))

maid:Add(health.Health:Observe():Subscribe(function(value)
	print("Observed health", value)
end))
```

`Changed` is an Rx-backed signal created from `Observe()` and skips the initial
value. `ObserveBrio(predicate)` emits matching property values with explicit
lifetimes.

## Find, Get, Promise, Wait, and Observe

Tie offers several lookup styles because implementation lifetimes can change:

| API | Behavior |
| --- | --- |
| `Find(adornee, realm?)` | Returns the first currently valid interface or `nil`. Best synchronous default. |
| `FindFirstImplementation(...)` | Full name for `Find()`. |
| `Get(adornee, realm?)` | Always returns a lazy interface facade. Member access errors if no valid implementation exists. |
| `Promise(adornee, realm?)` | Resolves when an implementation becomes available. |
| `Wait(adornee, realm?)` | Yields until `Promise()` resolves. Avoid on critical paths without an external timeout. |
| `Observe(adornee, realm?)` | Emits the currently selected interface or `nil`. |
| `ObserveBrio(adornee, realm?)` | Emits the selected interface with a lifetime. |
| `ObserveImplementationsBrio(...)` | Emits every simultaneous valid implementation. |
| `GetImplementations(...)` | Returns all current interfaces directly on one adornee. |
| `HasImplementation(...)` | Checks current validity. |
| `ObserveIsImplemented(...)` | Observes current validity as a boolean. |

Use a brio API when setup work must be undone exactly when an implementation
disappears:

```luau
maid:Add(HealthInterface.Server:ObserveBrio(npcModel):Subscribe(function(brio)
	local implementationMaid, health = brio:ToMaidAndValue()

	implementationMaid:Add(health.HealthChanged:Connect(function(value)
		print("Alive only while this implementation exists", value)
	end))
end))
```

## Child and tag discovery

Tie can discover component implementations in a hierarchy:

```luau
for _, health in HealthInterface.Server:GetChildren(workspace.Enemies) do
	print(health:GetTieAdornee())
end
```

Reactive child discovery uses `ObserveChildrenBrio()`. CollectionService-based
discovery uses `ObserveAllTaggedBrio(tagName)`:

```luau
maid:Add(HealthInterface.Server:ObserveAllTaggedBrio("Damageable")
	:Subscribe(function(brio)
		local health = brio:GetValue()
		print("Tagged health implementation", health:GetTieAdornee())
	end))
```

The tag identifies candidate adornees; Tie still validates that each candidate
actually implements the definition.

## How members are represented

For a server implementation named `Health`, the generated hierarchy resembles:

```text
NpcModel                         ← adornee
└── Health (Camera)              ← implementation parent
    ├── GetHealth (BindableFunction)
    ├── Damage (BindableFunction)
    ├── HealthChanged (BindableEvent)
    └── DisplayName              ← attribute or ValueBase
```

Container naming by realm:

| Realm | Generated name | Valid implementation class |
| --- | --- | --- |
| Server | `DefinitionName` | `Camera` |
| Client | `DefinitionNameClient` | `Configuration` |
| Shared | `DefinitionNameShared` | `Camera` |

Properties prefer attributes for supported primitive types. Tie can also mirror
ValueObjects and ValueBases. Values that need a richer local object are exposed
through an encoded BindableFunction. This storage decision is internal; consume
the property through `.Value`, `.Changed`, or `Observe()`.

`TieUtils` preserves non-Instance Luau values through Bindable calls by wrapping
tables, functions, symbols, and userdata in closures and decoding them on the
other side. This only works within the same Luau runtime, another reason Tie
should not be treated as networking.

## Realm behavior

Each definition has three facades:

```luau
HealthInterface         -- default shared realm
HealthInterface.Server  -- server realm
HealthInterface.Client  -- client realm
```

- A server implementation requires shared and server members.
- A client implementation requires shared and client members.
- A shared implementation must satisfy members from both sides.
- A realm-specific interface rejects access to members declared only for another
  realm.
- Shared lookup is broad enough to discover server, client, or shared containers.

Prefer `.Server` or `.Client` in runtime-specific code. It makes intent explicit
and prevents accidentally relying on a member that is unavailable there.

## Validation and error behavior

An implementation is valid only when every required member has the expected
physical representation:

- Method: named `BindableFunction`
- Signal: named `BindableEvent`
- Property: named attribute, ValueBase, or encoded BindableFunction

`IsImplementation()` performs this structural validation. `TieInterface` also
checks realm and parent/container validity. Missing required members fail during
`Implement()`, while invalid lazy `Get()` member access fails when used.

## TieDefinition API summary

| Method | Purpose |
| --- | --- |
| `new(name, members)` | Declares a named contract. |
| `Implement(adornee, implementer, realm?)` | Creates and owns an instance-backed implementation. |
| `Find`, `FindFirstImplementation` | Finds the first current interface. |
| `Get` | Creates a lazy facade without first validating availability. |
| `Promise`, `Wait` | Waits asynchronously or synchronously for availability. |
| `Observe`, `ObserveBrio` | Observes the selected implementation. |
| `GetImplementations`, `ObserveImplementationsBrio` | Enumerates all implementations on one adornee. |
| `GetChildren`, `ObserveChildrenBrio` | Discovers implementations on child adornees. |
| `ObserveAllTaggedBrio` | Discovers implemented tagged instances. |
| `HasImplementation`, `ObserveIsImplemented` | Reads or observes validity. |
| `GetName`, `GetMemberMap` | Exposes definition metadata. |
| `GetValidContainerNameSet`, `GetNewContainerName` | Realm/container metadata used by infrastructure. |
| `IsImplementation` | Structurally validates an implementation parent. |

## Ownership and practical constraints

- Keep every `TieImplementation` in a Maid; destroying it removes the contract.
- Tie does not own your implementer table, Signal, or ValueObject.
- Use colon syntax for methods exposed through a Tie interface.
- Prefer `Find()` for optional synchronous access and `ObserveBrio()` for dynamic
  lifetimes.
- Use explicit `.Server` or `.Client` facades in realm-specific code.
- Tie is runtime-local and should not carry trusted server commands over the
  network.
- Treat generated Cameras, Configurations, Bindables, attributes, and ValueBases
  as implementation details rather than editing them manually.
- Default-valued properties are optional to implement; `PROPERTY` declarations
  without a default are required.
