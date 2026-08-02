# MixinNetwork

`MixinNetwork` exposes one operation from each endpoint in an existing ByteNet network as a method on a class or
service. It deliberately requires the operation name because ByteNet packets have different valid operations on the
server and client, and choosing a server broadcast automatically would be unsafe.

```luau
const MixinNetwork = require("MixinNetwork")
const PurchaseNetwork = require("PurchaseNetwork")

const PurchaseService = {}

MixinNetwork:Add(PurchaseService, PurchaseNetwork.packets, "sendTo")

function PurchaseService.CompletePurchase(self: PurchaseService, data: PurchaseData, player: Player): ()
	self:PurchaseProcessed(data, player)
end
```

The endpoint key's first letter is uppercased, so `purchaseProcessed` becomes `PurchaseProcessed`. Arguments and
return values are forwarded unchanged after the instance `self` is removed.

Typical bindings are:

- Client packet sender: `MixinNetwork:Add(Class, Network.packets, "send")`
- Server targeted packet sender: `MixinNetwork:Add(Class, Network.packets, "sendTo")`
- Server broadcast packet sender: `MixinNetwork:Add(Class, Network.packets, "sendToAll")`
- Client query caller: `MixinNetwork:Add(Class, Network.queries, "invoke")`

Use separate classes or services when different endpoints need different operations. The mixin rejects missing ByteNet
operations and method-name collisions while the module is loading.
