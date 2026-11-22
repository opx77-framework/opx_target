Config = {}

-- Enables the demo command below (a demo tree on players, vehicles, the world, the sky and yourself). Off on a live server.
Config.debug = false

-- Command that toggles the demo registrations when debug is on.
Config.demoCommand = 'targetdemo'

-- Language of the texts: 'auto' follows the game language, or a file in locales/ ('en', 'fr').
Config.locale = 'auto'

-- Key held to aim (default; each player can rebind it in Settings > Key bindings, "Target eye (hold)").
Config.key = 'ALT'

-- Mouse button that opens the menu on what is under the cursor: 'right', 'left' or 'middle'.
Config.openButton = 'right'

-- ALT is also the game's weapon wheel: block the wheel while this resource runs.
Config.blockWeaponWheel = true

-- false: aiming borrows the cursor only, the game keeps the keyboard (the player can walk, push-to-talk
-- works) and the menu is used with the mouse; Escape goes to the game (its pause menu, which closes the eye).
-- true: the keyboard is held too while aiming, so the menu also answers Up / Down / Home / End / Left /
-- Right / Enter and Escape closes the menu (then the aim), but the player cannot walk or talk while ALT is held.
Config.captureKeyboard = false

-- false: the eye cannot be opened from a vehicle seat and closes when the player gets in one (aiming
-- freezes the camera, which a driver must keep). true: it also works seated (passenger tools, roleplay).
Config.allowInVehicle = false

-- Length of the camera ray in metres (what can be picked at all).
Config.rayDistance = 15.0

-- Player-to-target distance in metres of an option that sets no `distance`.
Config.defaultDistance = 3.0

-- Largest `distance` an option may ask for.
Config.maxDistance = 50.0

-- Milliseconds between two picks while aiming and the pointer moves.
Config.hoverMs = 80

-- Milliseconds between two picks while the pointer stands still (a target may move under it).
Config.hoverIdleMs = 300

-- Milliseconds between two checks that the target of an open menu is still under its ray.
Config.revalidateMs = 200

-- Frame the hovered entity with brackets fitted to its projected mesh bounds, the tag's leader line
-- leaving the frame's side (no outline native exists for a cursor target). Off: the tag leaves the cursor.
Config.highlight = true

-- Deepest submenu level (the root menu is level 1).
Config.maxDepth = 3

-- Rows shown per level; more are cut (Config.debug logs it).
Config.maxRows = 14

-- Milliseconds a row with children is hovered before its submenu opens.
Config.submenuDelayMs = 90

-- Milliseconds before a submenu closes when the pointer goes back to its parent (cancelled if it comes back).
Config.submenuGraceMs = 280

-- Time budget in milliseconds for all `canInteract` / `disabled` checks of one menu.
Config.predicateBudgetMs = 250

-- Registrations per resource, and options (all levels) per registration.
Config.limits = { perResource = 64, optionsPerRegistration = 64 }

-- Order of the document inside the NativeUI 'menu' layer.
Config.zIndex = 90

-- Smallest width of a menu level (one branch of the tree, rows included) in dp.
Config.panelWidth = 240

-- Largest width of a menu level in dp: a level grows from panelWidth up to this to fit its longest label,
-- reason or description; what still does not fit is cut at the row's edge.
Config.panelMaxWidth = 420

-- Degrees a menu level turns toward the screen centre, hinged on its trunk (0 = flat), and the perspective in dp.
Config.tilt = 6
Config.perspective = 1100

-- Calm motion for everyone: brackets and leader drawn at once. NativeUI animations already follow
-- each player's `nui.reducedmotion`, which turns the same things off.
Config.reducedMotion = false

-- Theme. Each value replaces the token of the same name declared at the top of ui/target.rcss
-- (hex #rrggbb keeps the alpha variants of the sheet, e.g. #4fe3ff59).
Config.theme = {
    holo = '#4fe3ff',                -- leader, tree lines, brackets, labels
    accent = '#ff3b47',              -- hovered / open row and its branch, lock (brackets, diamond)
    text = '#e9fbff',                -- primary text
    textDim = '#86a9b5',             -- secondary text, disabled rows
    panel = 'rgba(3, 17, 23, 0.80)', -- backing of the menu rows
    inkOn = '#071013',               -- text on a filled key cap (hint bar)
    alarm = '#ffa8ae',               -- danger rows
}

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
