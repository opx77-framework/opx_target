# opx_target

Hold ALT to aim at a player, NPC, vehicle, door, object, surface or the sky, then right click for its context menu.
It ships no actions of its own: other resources register the options.

## Install
- Needs: an Open77 client with NativeUI and screen picking. Load after `opx_core`, before the resources that add options.
- No database.
- Do not load the official `open77_contextmenu` too: both use ALT.
- Provider of the `target` slot: a replacement implements the library and exports in `types.lua`.

## In game
- Hold ALT (rebindable in Settings > Key bindings, "Target eye"): frames and names what is under the cursor.
- Right click: opens its menu. Hover a row to open its submenu, click to run it.
- Release ALT, or click outside: closes everything.
- `/targetdemo` (only with `Config.debug`): toggles a demo menu on every kind of target.

## Config
`config.lua`: `key`, `captureKeyboard` (keyboard menu navigation, but no walking while aiming), `allowInVehicle`, `rayDistance` / `defaultDistance`. Everything else is commented in the file.

## For developers
- `local Target = require('@opx_target')` with `dependency "opx_target"` in your manifest.
- `Target.addPlayer(options)`, `addNpc`, `addVehicle`, `addDoor`, `addProp`, `addWorld`, `addSky`, `addSelf`, `addGlobal` → `id` or `nil, reason`.
- `Target.addModel(models, options)` / `Target.addEntity(selectors, options)` → `id` or `nil, reason`.
- `Target.remove(id)` → boolean. Registrations also end when your resource stops.
- `Target.setEnabled(false)` → holds targeting off until `true` or your resource stops.
- An option with `serverEvent` sends `(targetId, info)` to the server: validate everything there, the menu is client UX only.
- Full contract (option fields, `ctx`, reasons, exports-only use): `types.lua`.
