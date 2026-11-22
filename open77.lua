resource "opx_target"
version "1.1.0"
open77_version ">=0.0.1"
auto_start true

-- The OPX targeting eye: hold ALT, aim with the cursor, right click a target for its context menu.
-- One service owns the screen; other resources register options through `require('@opx_target')`
-- (callbacks run in their own VM) or through the client exports (callbacks are named exports).
-- Provider of the `target` slot of opx_core (docs/ARCHITECTURE.md › Replacing a resource).

client_scripts {
    "config.lua",
    "client/main.lua",
}

-- client/modules: the service (require('client.modules.x')). init.lua + lib: the library that
-- `require('@opx_target')` loads into the caller's VM. ui + locales: read by the service.
files {
    "client/modules/*.lua",
    "init.lua",
    "lib/*.lua",
    "ui/target.rml",
    "ui/target.rcss",
    "locales/*.json",
}

permissions {
    "world.query",      -- Open77.camera.screenRaycast (picking), Open77.world.entityGeometry (hover frame)
    "input.actions",    -- RegisterKeyMapping, Open77.input.isDown / keyFor / cursor / isCaptured / setNativeActionBlocked
    "players.controls", -- Open77.players.allowAim / allowShoot / allowInteraction / freezeRotation while aiming
    "network.events",   -- TriggerServerEvent for options declared with `serverEvent`
    "local.events",     -- onClientResourceStart / onClientResourceStop / open77:pauseKey handlers
    "session.locale",   -- Open77.session.locale (Config.locale = 'auto')
}
