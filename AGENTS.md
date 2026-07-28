# Nevermore Fork conventions

This is the target style for all new and changed code in `lib/`. Some packages are older ports and do not yet follow every rule below. Treat this document, not nearby legacy code, as the source of truth. Preserve an established public API unless a change explicitly includes a migration.

## Non-negotiable rules

- Start every Luau module with `--!strict`. `lib/Loader.luau` is the only nonstrict exception.
- Use `t` for runtime argument and value validation. Do not introduce `assert(type(...))`, `assert(typeof(...))`, or `assert(value:IsA(...))` checks.
- Define methods with dot notation and an explicit typed `self`: `function Class.Method(self: Class, ...)`. Calls may use normal colon syntax.
- Put stateless logic in a `*Utils` module. A private helper that does not read or mutate `self`, and does not need another instance method, does not belong on a service or class.
- Resolve every service dependency in `Init`, store it on the service, and declare that field in the exported service type.
- Check the packages already available in `lib/` before creating a module or implementing functionality from scratch.
- Format every changed Luau file with StyLua. Tabs, indentation, spacing, double quotes, and blank lines are part of correctness.
- Keep service public APIs small. Services orchestrate lifecycle and dependencies; they are not miscellaneous function containers.
- Do not add redundant `_isStarted` or `_isDestroyed` service fields. `ServiceBag` owns service lifecycle ordering, and the service's `Maid` owns cleanup; use those lifecycle mechanisms instead of tracking duplicate state.

## Pick the right module kind

| Kind                  | Owns lifecycle/state?                   | Public naming                              | Purpose                                                                         |
| --------------------- | --------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------- |
| Service               | Yes, one instance per `ServiceBag`      | `PascalCase`                               | Coordinates dependencies, realm lifecycle, and application behavior             |
| Class/model           | Yes, one stateful instance per `.new()` | `PascalCase`                               | Represents one object, controller, cache, or stateful model                     |
| Utility               | No                                      | `camelCase`                                | Pure or stateless validation, conversion, serialization, lookup, and algorithms |
| Types                 | No                                      | Exported type names use `PascalCase`       | Shared type contracts without runtime behavior                                  |
| Constants             | No                                      | `UPPER_SNAKE_CASE`                         | Read-only package configuration and protocol constants                          |
| Network               | No                                      | Packet/query names use `camelCase`         | A package's ByteNet schema only; no business logic                              |
| Interface             | No                                      | Contract member names match the public API | A Tie or other cross-realm contract                                             |
| Binder provider       | Provider-owned                          | Binder names use `PascalCase`              | Registers classes with real tagged-instance lifecycles                          |
| Support service/model | Yes, focused                            | `PascalCase`                               | Owns one cohesive part of a larger service or class workflow                    |

If a module starts accumulating responsibilities from two rows, split it before adding more behavior.

### Before creating a module

Search `lib/` by concept and by likely module name before writing anything. Reuse the established package that already owns the behavior, or compose existing packages, instead of adding a near-duplicate abstraction. Inspect its API and lifecycle rather than guessing from its filename.

Use the packages that match the job: `Maid` for owned cleanup, `Promise` for asynchronous completion, `Observable`/`Rx` for streams, `ValueObject` for reactive state, `Binder` for genuine tagged-instance ownership, `t` for runtime validation, and the existing utility packages for common transformations. Do not recreate these locally.

After implementation, perform a separate revision pass. Ask:

- Is the module formatted and easy to scan?
- Are names, spacing, types, and public docs consistent?
- Is any method doing more than one job?
- Can existing library code replace custom code?
- Are hot paths avoiding unnecessary allocation, repeated lookup, or repeated work?
- Is the optimization understandable and justified rather than speculative?

## Package layout

Keep a small package flat:

```text
lib/example/
	Example.luau
	ExampleUtils.luau
```

Use realm folders and `Shared` once a package has both server and client behavior:

```text
lib/exampleservice/
	ExampleService.luau
	ExampleServiceClient.luau
	README.md
	Server/
		ExampleServerModel.luau
	Client/
		ExampleClientModel.luau
	Shared/
		ExampleServiceConstants.luau
		ExampleServiceInterface.luau
		ExampleServiceNetwork.luau
		ExampleServiceTypes.luau
		ExampleServiceUtils.luau
```

Only create folders that have content. A two-file service does not need empty `Server`, `Client`, or `Shared` directories. Put code in `Shared` only when both realms can safely require it; shared modules must not access server-only APIs.

Prefer owner-specific names such as `SaveSlotSerializationUtils` or `PlayerIdServiceUtils`. A generic name such as `Utils` hides ownership and collides with the loader's name-based lookup.

### Decomposing crowded modules

Split a service or class when it owns several independently describable workflows, has large groups of unrelated private methods, or becomes difficult to scan. The main module remains the public facade and composes focused support modules.

For a crowded service:

```text
lib/coinservice/
	CoinService.luau          # Public facade; resolves and coordinates support services
	CoinPickupService.luau    # Picks up coins
	CoinObserveService.luau   # Watches coins
	CoinSpawnService.luau     # Spawns coins
	Shared/
		CoinServiceTypes.luau
		CoinServiceUtils.luau
```

`CoinService.Init` resolves all three support services through its `ServiceBag` and stores them in typed fields. Each support service owns one lifecycle and one area of behavior. Keep shared stateless rules in `CoinServiceUtils`; do not copy them across support services. Avoid cycles: support services should depend on lower-level packages or shared modules, not reach back into the facade without a deliberate interface.

For a crowded class:

```text
lib/quest/
	Quest.luau               # Main public class and coordinator
	QuestTrackerModel.luau   # Tracks quest state
	QuestCreatorModel.luau   # Creates quest state
	QuestUpdateModel.luau    # Applies quest updates
	QuestUtils.luau          # Stateless quest rules
```

`Quest.new` constructs its support models, registers them with its maid, and stores them in the exported `Quest` type. The main class keeps the stable public API and delegates focused work. `adorneedata` is a useful architectural reference for a main abstraction split into entry/value support classes, but its legacy syntax and validation are not style precedent.

### Supporting modules

- `*Types.luau` exports related types and returns an empty module table so it remains requireable.
- `*Constants.luau` returns a `TableUtils.deepReadonly({...})` table when callers must not mutate it.
- `*Network.luau` defines one package namespace and returns it read-only. It contains schemas, packets, and queries only.
- `*Interface.luau` describes a shared public contract. Realm-specific members belong under the appropriate realm key.
- Add binders only when a tagged `Instance` genuinely owns an object's lifetime. Do not use a binder merely to observe players or characters.

## Module order

Use this order consistently:

1. `--!strict`, then `--!optimize 2` only for a measured hot path.
2. One Moonwave module header.
3. Roblox services from `game:GetService()`.
4. The relative loader acquisition.
5. Bare-name package requires.
6. Exported/local types.
7. Module constants and reusable validators.
8. The module table and `ClassName` or `ServiceName` metadata.
9. Exported class/service type.
10. Constructor or `Init`, then `Start`.
11. Public methods.
12. Private stateful methods.
13. `Destroy` when the module owns cleanup.
14. The final `return`.

Separate those groups with one blank line. Sort requires; StyLua's `sort_requires` setting handles this. Put static module requires at module scope. Never call `require()` from `Start`, an ordinary public/private method, a callback, or a loop. If a module genuinely must be loaded per construction or delayed for registration, require it once at the beginning of the class's `.new()` or the service's `Init`; bind the result to a clearly named value instead of inlining `require()` inside another call.

Use the appropriate Moonwave tag:

```luau
--[=[
	A useful one-paragraph description.

	@class ExampleService
	@server
]=]
```

Use `@class` for services and stateful classes, `@util` for utility modules, `@types` for type collections, and `@network` for network definitions. Document every public non-lifecycle method with a short behavior description, `@within`, meaningful parameters, and its return value. Do not add empty prose such as "Does something." Never add method-level Moonwave documentation to `.new()`, `Init`, `Start`, `Destroy`, or private methods.

## Requires and the loader

Acquire the loader once, then import packages by bare module name:

```luau
const require = require("../Loader").load()

const Maid = require("Maid")
const t = require("t")
```

Never convert bare-name imports into Roblox hierarchy paths. Match the relative path to `lib/Loader.luau`. Remember that an `init.luau` collapses its folder and therefore uses one fewer `../` segment than a regular file beside it.

Module loading and service resolution are different operations:

- `require("SomeService")` loads the service module and normally belongs with the top-level imports.
- `self._serviceBag:GetService(SomeService)` resolves the service instance and always belongs in `Init`.
- A class constructs its owned dependencies in `.new()`.
- Do not look up services lazily from `Start`, public methods, private methods, or callbacks.

## Bindings, names, and types

- Use `const` whenever a binding is never reassigned, at module scope or inside a function.
- Use `local` for a binding that is reassigned. Mutation inside a table does not reassign the table binding.
- Use `PascalCase` for services, classes, exported types, public methods, and enum-like values.
- Use `camelCase` for utility functions and local functions.
- Prefix private fields and private stateful methods with `_camelCase`.
- Prefix boolean queries with `Is`, `Has`, or `Can` for methods and `is`, `has`, or `can` for utilities.
- Suffix new imperative promise-returning operations with `Async`. Keep an established `PromiseX` name when compatibility requires it.
- Add explicit parameter and return types. Use `: ()` for functions intentionally returning nothing when the surrounding package uses explicit returns.
- Use `_self` only when a public/interface method must accept `self` but intentionally does not use instance state. A private `_method(_self, ...)` is usually a utility waiting to be extracted.
- Include every stored service and owned support module in the exported type, using its exported type rather than `any`.

## Runtime validation and assertions

Require `t` in every module that validates public inputs:

```luau
const t = require("t")

assert(t.string(name) and name ~= "", "Bad name")
assert(t.numberPositive(duration), "Bad duration")
assert(t.instanceIsA("Player")(player), "Bad player")
assert(t.optional(t.instanceIsA("Folder"))(parent), "Bad parent")
```

For structured values, define a reusable validator once rather than repeating field checks:

```luau
const isOptions = t.strictInterface({
	Enabled = t.boolean,
	Timeout = t.optional(t.numberPositive),
})

assert(isOptions(options), "Bad options")
```

Every assertion whose purpose is to validate a value's runtime type or shape starts with a `t` checker. Add semantic predicates after the type checker when necessary, or expose a named predicate from the owning utility module for domain rules such as IDs and paths.

```luau
assert(t.number(playerId) and PlayerIdServiceUtils.isPlayerId(playerId), "Bad playerId")
```

Do not write new validation like this:

```luau
assert(type(name) == "string", "Bad name")
assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
```

A bare `assert` is reserved for a state invariant rather than type validation, for example double initialization, an impossible state, a missing required lookup, or an exhausted pool:

```luau
assert(not (self :: any)._serviceBag, "Already initialized")
assert(#availableIds > 0, "No ID available")
```

Write actionable assertion messages and name the bad argument: `"Bad player"`, `"Bad options.Timeout"`, or a precise invariant failure. Never rely only on static Luau annotations at a public boundary, network boundary, or data-deserialization boundary.

## Services

A service is constructed by `ServiceBag`; it does not expose `.new()`. It owns dependency wiring, subscriptions, and high-level orchestration.

```luau
--!strict
--[=[
	Coordinates example behavior.

	@class ExampleService
	@server
]=]

const require = require("../Loader").load()

const CmdrService = require("CmdrService")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const t = require("t")

const ExampleService = {}
ExampleService.ServiceName = "ExampleService"
ExampleService.ServerOnly = true

export type ExampleService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: CmdrService.CmdrService,
	},
	{} :: typeof({ __index = ExampleService })
))

function ExampleService.Init(self: ExampleService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")
	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._cmdrService = self._serviceBag:GetService(CmdrService)
end

function ExampleService.Start(self: ExampleService): ()
	-- Connect behavior after every service has initialized.
end

function ExampleService.Destroy(self: ExampleService): ()
	self._maid:DoCleaning()
end

return ExampleService
```

Service responsibilities:

- `Init` is the first method after the exported type. It validates one-time initialization, stores the `ServiceBag`, creates the maid, and resolves every service dependency. It should not depend on another service having started.
- `Start` connects runtime behavior after all services have initialized. Put player observers, network listeners, and startup side effects here when they do not need to exist during dependency setup.
- `Destroy` releases every connection, promise, object, and callback owned by the service.
- Do not track initialization or destruction with redundant boolean fields such as `_isStarted` or `_isDestroyed`; `ServiceBag` controls lifecycle ordering and `Maid` cleanup controls owned resources.
- Resolve services only in `Init`. Never call `GetService` from `Start`, another method, or a callback.
- Store every resolved service on `self` and declare it in the exported type, for example `_cmdrService: CmdrService.CmdrService`. This keeps the complete dependency graph visible at the top of the module.
- Set `ServerOnly = true` on server-only services. Client mirrors use the `ServiceClient` suffix and must not pretend client state is authoritative.
- Resolve required dependencies with `GetService`. Use `HasService` only for intentionally optional integration.
- Public methods express the service's domain. Conversion, serialization, table manipulation, codecs, and independent validation belong in package-local utilities.
- Keep callbacks small. If a callback becomes a workflow, delegate to a named stateful method or a utility as appropriate.
- Keep `Init` and `Start` at the top of the implementation, in that order, and keep `Destroy` as the bottom method immediately before `return`.

For server/client packages, put shared constants, types, validation, and wire schemas under `Shared`. The server owns authoritative mutation. The client owns a read-only observable mirror and only sends explicit requests allowed by the API.

For PlayerDataStoreService-backed features, use a namespaced dot path such as `Inventory.Tools`. Go through `PlayerDataStoreService:SetValue`, `GetValue`, and `ObserveAtKey` at the persistence boundary. Register custom replication during `Init`; keep serialization in a shared utility/codec module and network definitions in `*Network.luau`. When custom deltas replace default replication, seed the client mirror from the full profile and then apply queued deltas in receive order.

## Classes and models

Use a class when each constructed object has independent state or lifetime.

```luau
--!strict
--[=[
	Represents one example.

	@class Example
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const t = require("t")

const Example = {}
Example.ClassName = "Example"
Example.__index = Example

export type Example = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_name: string,
	},
	{} :: typeof({ __index = Example })
))

function Example.new(name: string): Example
	assert(t.string(name) and name ~= "", "Bad name")

	const self = setmetatable({}, Example) :: Example
	self._maid = Maid.new()

	self._name = name

	return self
end

--[=[
	Returns this example's name.

	@within Example
	@return string
]=]
function Example.GetName(self: Example): string
	return self._name
end

function Example.Destroy(self: Example): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return Example
```

- Put `.new()` first after the exported type, public methods next, private stateful methods after them, and `Destroy` as the bottom method immediately before `return`.
- Every class owns a maid directly or inherits one through `BaseObject`. Register all connections, promises, signals, and child objects with it.
- Use `BaseObject` when an object naturally wraps an Instance or benefits from the established base lifecycle. Inherit or extend its cleanup instead of duplicating it.
- Keep the exported type beside the class table and list private/public state explicitly. Do not use `any` merely to avoid describing ordinary fields.
- A private method is justified only when it uses instance state or polymorphic behavior. If all inputs can be parameters, extract it to an owner-specific utility module.

## Utilities

Utilities are stateless module tables. They do not have `ClassName`, `.new()`, `Init`, `Start`, or `Destroy`.

```luau
--!strict
--[=[
	Validates and transforms example values.

	@util ExampleUtils
]=]

const require = require("../Loader").load()

const t = require("t")

const ExampleUtils = {}

--[=[
	Normalizes a name for comparison.

	@within ExampleUtils
	@param name string
	@return string
]=]
function ExampleUtils.normalizeName(name: string): string
	assert(t.string(name), "Bad name")
	return string.lower(string.gsub(name, "%s+", ""))
end

return ExampleUtils
```

Move a helper into `OwnerUtils.luau` when it:

- does not read or mutate `self`;
- depends only on arguments, immutable module constants, or explicitly passed dependencies;
- performs validation, normalization, selection, serialization, conversion, copying, math, or lookup; or
- is useful to server and client implementations of the same package.

Do not turn a stateless helper into `_helper(_self, ...)` merely to keep it on a class. Pass dependencies explicitly to utilities when that keeps them stateless, but do not let a utility require its owning service and create a cycle.

File-local functions are appropriate inside the utility itself when they are implementation details. A tiny closure inside a method may also remain local when it deliberately captures method-local state, such as an event callback or an Rx update function. The extraction rule targets independent logic, not every anonymous callback.

Utility functions use `camelCase`, including predicates such as `isPlayerId` and codecs such as `serializeSlotState`. Public utility functions receive Moonwave documentation; private file-local helpers do not.

## Formatting and spacing

`stylua.toml` is authoritative:

- tabs with an indent width of 4;
- a 120-column limit;
- Unix line endings;
- double quotes;
- parentheses on calls as configured;
- sorted requires; and
- no collapsed simple statements.

Use one space around binary operators and after commas. Do not insert a space between a function name and `(`. Use one blank line between logical sections, no repeated blank lines, and no trailing whitespace. Multiline tables and calls use one entry/argument per line with trailing commas where valid. Let StyLua choose wrapping and indentation; do not hand-align fields with spaces.

Comments should explain intent, ordering, ownership, protocol constraints, or a non-obvious tradeoff. Do not narrate syntax. Keep related assignments together, return early to reduce nesting, and avoid mixing cleanup, networking, persistence, and transformation in one long method.

## Verification

Run the checks that match the changed scope from the repository root:

```bash
stylua path/to/ChangedFile.luau
stylua --check lib/
selene lib/
```

For a focused change, format and check the changed files first; run the full commands before handing off a package-wide change. Add targeted tests when the package has a test harness. At minimum, exercise serialization round trips, boundary validation, cleanup, and server/client ordering when those behaviors change.

## Review checklist

- Did you search `lib/` and reuse the right existing packages before creating new code?
- Is this a service, stateful class, or stateless utility for the right reason?
- Is the main service/class still focused, or should cohesive workflows become support services/models?
- Did every new runtime type/shape assertion use `t`?
- Did every independent private helper move to a package-local `*Utils` module?
- Does every method definition use dot notation with typed `self`?
- Are all static requires at module scope, with any necessary delayed require only at the start of `.new()` or `Init`?
- Are all service dependencies resolved in `Init`, stored on `self`, and declared with concrete types in the exported type?
- Are public names, async suffixes, and private prefixes consistent?
- Are resources owned by a maid and cleaned exactly once?
- Is shared code safe in both realms, with network schemas separated from behavior?
- Are public methods documented while `.new()`, lifecycle methods, and private methods remain undocumented?
- Are `.new()` or `Init`/`Start` at the top and `Destroy` at the bottom?
- Did you perform a final readability and optimization pass?
- Did StyLua and Selene pass?

Useful architectural references in this fork include `playeridservice` for a small realm-aware service, `gameconfig` for a larger server/client/shared split, `saveslot` for shared serialization, `gameproductservice` for network boundaries, `buttondragmodel` for a stateful model, `adorneedata` for decomposing a main abstraction into focused classes, and `simulatedcharacterservice` for performance-oriented codecs and models. Use their architecture as context, but use this document when their older formatting or validation differs.
