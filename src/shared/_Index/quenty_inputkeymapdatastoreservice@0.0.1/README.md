# InputKeyMapDataStoreService

`InputKeyMapDataStoreService` persists the local player's rebindable `InputKeyMapList` values through this fork's
`PlayerDataStoreService`. It is adapted from Quenty's `settings-inputkeymap` package, but does not depend on the legacy
`SettingsService` or remote-event stack.

The client observes registered rebindable keymaps. A local change sends one typed ByteNet request containing the provider,
list, input mode, and serialized input types. The server accepts only registered rebindable maps, validates every input
against its input mode, rate-limits requests, and writes the result to the player's existing profile. Authoritative updates
and rejected-request rollbacks return through `PlayerDataStoreService`'s ByteNet mirror.

## Profile contract

The selected `PlayerDataStoreServiceProfile` must include this root field in both its template and its Squash schema:

```luau
const InputKeyMapDataStoreServiceUtils = require("@game/ReplicatedStorage/Packages/InputKeyMapDataStoreServiceUtils")
const Squash = require("@game/ReplicatedStorage/Packages/Squash")

return {
	Template = {
		InputKeyMapBindings = {},
		-- Other game data...
	},
	Schema = Squash.record({
		InputKeyMapBindings = InputKeyMapDataStoreServiceUtils.getBindingsSchema(),
		-- Other game codecs...
	}),
	Validators = {
		InputKeyMapBindings = InputKeyMapDataStoreServiceUtils.isBindings,
	},
}
```

If `SaveSlotService` selects `SlotsProfileData`, add the same field, codec, and validator to that profile contract. This
package deliberately does not select or open another profile.

## Service setup

Resolve `InputKeyMapDataStoreService` on the server and `InputKeyMapDataStoreServiceClient` on the client through their
respective `ServiceBag`s. Both services also resolve the input-keymap registry and player-data service during `Init`.

```luau
-- Server
serviceBag:GetService(require("@game/ServerStorage/ServerPackages/InputKeyMapDataStoreService"))

-- Client
serviceBag:GetService(require("@game/ReplicatedStorage/Packages/InputKeyMapDataStoreServiceClient"))
```

Only lists created with `rebindable = true` participate. Existing input-keymap APIs remain the write surface:

```luau
inputKeyMap:SetInputTypesList({ Enum.KeyCode.F })
inputKeyMap:RestoreDefault()
```

Bindings are keyed by provider name, list name, and input-mode name, so independently owned providers cannot overwrite one
another. Defaults are not stored; restoring a map removes its override from the profile.
