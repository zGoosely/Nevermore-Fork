# ClientCullingService

`ClientCullingService` performs render-only distance culling for tagged world
content on each client. It keeps tagged Instances in their original hierarchy,
so culling does not change ancestry, collisions, raycasts, scripts, or Roblox
streaming behavior.

Resolve the service during client initialization:

```luau
const ClientCullingService = require("@game/ReplicatedStorage/Packages/ClientCullingService")

function GameServiceClient.Init(self, serviceBag)
	self._clientCullingService = serviceBag:GetService(ClientCullingService)
end
```

The service owns its Binders and starts automatically with the `ServiceBag`.
There is no manual `Start()` or `Destroy()` call.

## Tags

Tag a supported Instance with `Cull` to hide its renderable descendants beyond
the configured distance. Full culling affects:

- `BasePart` rendering and shadows;
- `Decal` and `Texture` rendering;
- particles, beams, trails, fire, smoke, and sparkles;
- point, spot, and surface lights;
- billboard and surface GUI; and
- highlights.

Tag an Instance with `CullShadows` to disable only `CastShadow` on its
`BasePart` descendants. It never hides the object. If an Instance has both
tags, their state is tracked independently.

Overlapping tagged roots are safe. A descendant remains hidden or
shadow-culled until every applicable owner becomes visible.

## Attributes

Configuration lives on the tagged root:

| Attribute | Type | Default | Purpose |
| --- | --- | --- | --- |
| `CullDistance` | nonnegative number | `200` | Hides the nearest point on the cached bounds beyond this 3D camera distance. |
| `CullUncullDistance` | nonnegative number | `CullDistance - min(10, CullDistance * 0.1)` | Requires the camera to return inside this distance before showing the root again. Must not exceed `CullDistance`. |
| `CullDynamic` | boolean | `false` | Opts a moving root into budgeted bounds-position refreshes. |

Invalid attributes leave the root visible and produce a warning. Correcting the
attribute registers it without requiring the tag to be reapplied.

```luau
const CollectionService = game:GetService("CollectionService")

model:SetAttribute("CullDistance", 300)
model:SetAttribute("CullUncullDistance", 280)
model:SetAttribute("CullDynamic", false)
CollectionService:AddTag(model, "Cull")
```

Static roots cache their bounding box instead of calling `GetBoundingBox()` on
every update. Descendant additions and removals rebuild the cached bounds.
Use `CullDynamic = true` when a tagged root moves at runtime. Models then update
the cached bounds from `GetPivot()` without walking their descendants.

## Runtime queries

The public service intentionally exposes queries only:

```luau
if clientCullingService:IsCulled(model) then
	print("Full rendering is currently culled")
end

if clientCullingService:AreShadowsCulled(model) then
	print("Shadows are currently culled")
end
```

Both methods report the target state immediately. Large descendant trees may
take additional frames to finish applying their bounded visual mutation queue.

## Performance behavior

- Distance checks run at 10 Hz around `Workspace.CurrentCamera`.
- Cached roots are stored in power-of-two distance buckets and 3D spatial
  cells, so each update only examines nearby cells and the currently visible
  set.
- At most 256 opt-in dynamic roots refresh per update.
- At most 512 descendant visibility mutations run per frame.
- Restoration work is processed before new hiding work.
- MicroProfiler scopes are named `ClientCulling.Update`,
  `ClientCulling.SpatialQuery`, `ClientCulling.DynamicRefresh`, and
  `ClientCulling.VisualMutations`.

For a 5,000-root validation, distribute anchored tagged parts or compact models
through the test map, move or teleport the camera across the map, and confirm
the scopes remain bounded while nearby roots restore first. Also inspect Render
Stats to confirm that the tags reduce the intended draw and shadow workload.

This package complements Roblox instance streaming; it does not remove
replicated Instances or their memory. Use instance streaming and model level of
detail for large-world replication and memory management.

## Breaking migration

The previous global `ClientCulling` module and its APIs have been removed:

- `Start`, `Destroy`, and `SetUpdateFrequency`;
- `AddItem` and `RemoveItem`;
- `AddObject` and `RemoveObject`;
- active-cull helpers; and
- global transition callbacks.

Resolve `ClientCullingService` and use tags, attributes, and its two query
methods instead.

`SimulatedCharacterService` still contains calls to the removed custom-object
API by explicit migration decision. Those calls are intentionally stale and
will fail at runtime until simulated-character culling is redesigned
separately.
