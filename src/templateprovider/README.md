# TemplateProvider

`TemplateProvider` is a named registry for cloneable Roblox instances. It keeps
asset ownership on the server, advertises lightweight placeholders to clients,
and transfers a template only when a client asks for it.

It is useful when a system owns reusable models, sounds, effects, ModuleScripts,
or other authored instances that should be retrieved by name without replicating
the full library to every player immediately.

The practical rule is simple: call `CloneTemplate()` on the server, and call
`PromiseCloneTemplate()` on the client. Use TemplateProvider for authored
Instances, not for player save data or rapidly changing gameplay state.

## The basic structure

A provider is normally a shared ModuleScript whose children are the templates:

```text
VehicleTemplateProvider
├── init.luau
├── CopCar
├── Taxi
└── Emergency
    ├── Ambulance
    └── FireTruck
```

`init.luau` returns a configured provider service:

```lua
--!strict

const require = require("../Loader").load()

const TemplateProvider = require("TemplateProvider")

return TemplateProvider.new(script.Name, script)
```

The `script` passed to `TemplateProvider.new()` is a container. Its children are
registered as templates. Child Folders are themselves templates and are also
searched recursively.

The provider name must be unique. It is used by ServiceBag and by the ByteNet
request router.

## Server and client setup

Initialize the same provider service through ServiceBag on both sides.

```lua
-- Server service
const require = require("../Loader").load()

const VehicleTemplateProvider = require("VehicleTemplateProvider")

function VehicleService.Init(self, serviceBag)
	self._templates = serviceBag:GetService(VehicleTemplateProvider)
end
```

```lua
-- Client service
const require = require("../Loader").load()

const VehicleTemplateProvider = require("VehicleTemplateProvider")

function VehicleServiceClient.Init(self, serviceBag)
	self._templates = serviceBag:GetService(VehicleTemplateProvider)
end
```

ServiceBag initializes the provider. No separate networking service needs to be
started.

## What happens on the server

When the provider initializes on the server:

1. It moves the source templates beneath a `Camera` named
   `PreventReplication`. Roblox does not replicate those descendants normally.
2. It registers every template by its current `Name`.
3. It creates small Folder tombstones in the original hierarchy. Each tombstone
   contains an opaque generated template id.
4. It watches additions, removals, and renames so the registry and tombstone tree
   remain current.

The source instances stay server-owned and must have `Archivable` enabled so the
provider can clone them.

## What happens when a client requests a template

The client initially receives only tombstones. Calling
`PromiseCloneTemplate("CopCar")` performs this flow:

```text
Client tombstone
      │
      │ ByteNet query: provider name + opaque template id
      ▼
Server validates the provider and id
      │
      │ temporary GUID-named clone under that player's PlayerGui
      ▼
ByteNet returns the GUID; the client waits for that exact clone
      │
      │ client caches a clone; server removes the transfer copy later
      ▼
Promise resolves with a separate clone for the caller
```

Only the requesting player receives the transfer copy. The cached source remains
available for the lifetime of the client provider, so later clones do not make
another request.

Clients cannot select arbitrary server instances. Requests are limited to opaque
ids currently registered by the named provider.

## Cloning templates

Use `PromiseCloneTemplate()` when the template might not be loaded yet. This is
the normal client API.

```lua
self._templates:PromiseCloneTemplate("CopCar")
	:Then(function(copCar)
		copCar:PivotTo(CFrame.new(0, 5, 0))
		copCar.Parent = workspace
	end)
	:Catch(warn)
```

Use `CloneTemplate()` when the template is already available, which is normally
the case on the server:

```lua
const copCar = self._templates:CloneTemplate("CopCar")
copCar.Parent = workspace
```

If a template is named `CopCarTemplate`, its clone is named `CopCar`. Other names
are preserved.

## Adding templates dynamically

`AddTemplates()` accepts an Instance container, a nested list of declarations,
or an `Observable<Brio<Instance>>`.

```lua
const cleanup = self._templates:AddTemplates(workspace.RuntimeTemplates)

-- Stop providing that container later
cleanup()
```

A direct Instance declaration is treated as a container; its children become
templates. An observable declaration emits the template instances themselves.

When multiple templates have the same name, the most recently registered one is
canonical. Removing that declaration restores the previous template, which makes
temporary overrides possible.

```lua
const removeSeasonalOverrides = self._templates:AddTemplates(seasonalTemplates)

-- Seasonal templates now win by name

removeSeasonalOverrides()
-- Original templates become canonical again
```

## Observing templates

`ObserveTemplate()` emits the current canonical template and updates whenever it
changes:

```lua
self._maid:Add(self._templates:ObserveTemplate("CopCar"):Subscribe(function(template)
	if template then
		print("CopCar is available", template)
	else
		print("CopCar is unavailable")
	end
end))
```

Name-level observations use brios so consumers know when a name stops being
valid:

```lua
self._maid:Add(self._templates:ObserveTemplateNamesBrio():Subscribe(function(brio)
	const maid, templateName = brio:ToMaidAndValue()
	print("Template added", templateName)

	maid:Add(function()
		print("Template removed", templateName)
	end)
end))
```

## Tagged templates

`TaggedTemplateProvider` creates a provider from CollectionService tags:

```lua
const require = require("../Loader").load()

const TaggedTemplateProvider = require("TaggedTemplateProvider")

return TaggedTemplateProvider.new("WeaponTemplates", "WeaponTemplate")
```

Tagged instances are added and removed reactively. The tag observable emits each
tagged instance as the template itself rather than treating it as a container.

## API summary

| Method | Purpose |
| --- | --- |
| `GetTemplate(name)` | Returns the loaded canonical source or `nil`. |
| `CloneTemplate(name)` | Immediately clones a loaded template; errors if unavailable. |
| `PromiseTemplate(name)` | Resolves with the raw source, requesting it on the client if needed. |
| `PromiseCloneTemplate(name)` | Resolves with a new clone; preferred by client consumers. |
| `AddTemplates(declaration)` | Adds containers or observable templates and returns cleanup. |
| `IsTemplateAvailable(name)` | Reports whether the source is loaded in this runtime. |
| `GetTemplateList()` | Returns every loaded canonical source. |
| `GetContainerList()` | Returns every registered root or recursive Folder container. |
| `ObserveTemplate(name)` | Observes the canonical source for one name. |
| `ObserveTemplateNamesBrio()` | Observes loaded names and their lifetimes. |
| `ObserveUnreplicatedTemplateNamesBrio()` | Observes names advertised through tombstones. |

The older aliases `Get`, `Clone`, `PromiseClone`, `IsAvailable`, `GetAll`, and
`GetAllTemplates` remain supported.

## How CmdrService uses it

CmdrService uses a server-only provider containing two ModuleScript templates:

```text
CmdrTemplateProviderServer
├── CmdrCommandDefinitionTemplate
└── CmdrExecutionTemplate
```

For each table-defined command, CmdrService clones both modules. The definition
contains JSON-safe command metadata, while the execution module contains ids that
route back to the server function. Cmdr itself moves the definition module into
its replicated `Commands` folder. TemplateProvider networking is therefore not
used for Cmdr commands; TemplateProvider supplies the server-side module factory,
and Cmdr owns command replication.

## Practical constraints

- Provider names must be unique on the server.
- Source templates must be archivable.
- Table-defined Cmdr command metadata must be JSON-compatible.
- Use promises on clients because a tombstone may be known before its template is
  loaded.
- The client cache lasts until the provider is destroyed.
- Destroy providers through ServiceBag so observers, pending promises, temporary
  registrations, and server routing entries are cleaned up together.
