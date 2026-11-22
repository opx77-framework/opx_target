-- Line icons of the menu rows: SVG path data on a 24 x 24 grid, drawn by RmlUi <path> (stroke only, no
-- icon font, no remote asset, no markup from a caller). An option names one with `icon = 'hand'`; an
-- unknown or missing name draws 'dot' (and is reported once in the console). Data only: every key is a
-- name, every value its path. Add your own here: one entry, nothing else to change.
-- The names are the ones opx_menu knows as well (same vocabulary and aliases for a developer), kept as a
-- local copy: the two resources share no file.

local Icons = {
    dot = 'M9 12 a3 3 0 1 0 6 0 a3 3 0 1 0 -6 0 Z',
    hand = 'M8 12V5a2 2 0 0 1 4 0v6 M12 9h3l4 4v4l-3 4h-5l-6-7a2 2 0 0 1 3-2Z',
    person = 'M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0Z M4 21v-3a8 8 0 0 1 16 0v3',
    vehicle = 'M4 10l2-6h12l2 6 M3 10h18v8H3Z M5 18v3 M19 18v3 M6 14h2 M16 14h2',
    door = 'M6 21V3h12v18 M4 21h16 M14.5 12v.5',
    lock = 'M6 10V7a6 6 0 0 1 12 0v3 M4 10h16v11H4Z M12 14v3',
    unlock = 'M6 10V7a6 6 0 0 1 11.6-2.2 M4 10h16v11H4Z M12 14v3',
    key = 'M4 15a4 4 0 1 0 8 0a4 4 0 1 0 -8 0Z M11 12l9-9 M17 6l3 3 M15 8l2 2',
    info = 'M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0Z M12 11v6 M12 7v.2',
    search = 'M4 11a7 7 0 1 0 14 0a7 7 0 1 0 -14 0Z M16 16l5 5',
    eye = 'M2.5 12 C5.4 7.6 8.6 6 12 6 C15.4 6 18.6 7.6 21.5 12 C18.6 16.4 15.4 18 12 18 C8.6 18 5.4 16.4 2.5 12 Z M9.2 12 a2.8 2.8 0 1 0 5.6 0 a2.8 2.8 0 1 0 -5.6 0 Z',
    chat = 'M4 5h16v11H9l-5 4Z',
    box = 'M3 7l9-4 9 4v10l-9 4-9-4Z M3 7l9 4 9-4 M12 11v10',
    heart = 'M12 20s-8-5-8-11a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 9c0 6-8 11-8 11Z',
    money = 'M3 6h18v12H3Z M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0Z M6 9v.2 M18 15v.2',
    phone = 'M7 2h10v20H7Z M11 18h2',
    gear = 'M9 12a3 3 0 1 0 6 0a3 3 0 1 0 -6 0Z M12 2v3 M12 19v3 M2 12h3 M19 12h3 M4.9 4.9l2.1 2.1 M17 17l2.1 2.1 M4.9 19.1l2.1-2.1 M17 7l2.1-2.1',
    tool = 'M14 3a6 6 0 0 0-6 8l-6 6 5 5 6-6a6 6 0 0 0 8-7l-4 4-5-5 4-4Z',
    location = 'M20 10c0 6-8 12-8 12S4 16 4 10a8 8 0 1 1 16 0Z M15 10a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z',
    arrow = 'M5 19L19 5 M10 5h9v9',
    camera = 'M3 8h4l2-3h6l2 3h4v11H3Z M9 13a3 3 0 1 0 6 0a3 3 0 1 0 -6 0Z',
    star = 'M12 3l2.8 5.8 6.2.9-4.5 4.4 1 6.3L12 17.5 6.5 20.4l1-6.3L3 9.7l6.2-.9Z',
    music = 'M9 18V5l11-2v13 M9 18a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z M20 16a3 3 0 1 1-6 0a3 3 0 1 1 6 0Z',
    copy = 'M8 3h8v3H8Z M6 4H4v17h16V4h-2',
    warning = 'M12 3l10 18H2Z M12 10v5 M12 18v.2',
    trash = 'M4 7h16 M9 7V4h6v3 M6 7l1 14h10l1-14 M10 11v6 M14 11v6',

    -- the names opx_menu adds to that list (paths copied from opx_menu/lib/icons.lua)
    group = 'M12 8 A3.2 3.2 0 1 1 5.6 8 A3.2 3.2 0 1 1 12 8 Z M2.5 19.5 C2.5 15.8 5 13.8 8.8 13.8 C12.6 13.8 15 15.8 15 19.5 M15 5.1 A3 3 0 1 1 16.6 10.9 M17.2 13.9 C19.8 14.5 21.5 16.4 21.5 19.5',
    mail = 'M3 5.5 H21 V18.5 H3 Z M3 6 L12 13 L21 6',
    bag = 'M5 8 H19 L18 21 H6 Z M9 10.5 V6.5 A3 3 0 0 1 15 6.5 V10.5',
    medical = 'M9.5 3.5 H14.5 V9.5 H20.5 V14.5 H14.5 V20.5 H9.5 V14.5 H3.5 V9.5 H9.5 Z',
    card = 'M3 5.5 H21 V18.5 H3 Z M11 10 A2 2 0 1 1 7 10 A2 2 0 1 1 11 10 Z M5.5 15.5 C6 13.8 7.2 13 9 13 C10.8 13 12 13.8 12.5 15.5 M14.5 10 H18.5 M14.5 13.5 H17.5',
    chip = 'M7 7 H17 V17 H7 Z M10 10 H14 V14 H10 Z M9.5 4 V7 M14.5 4 V7 M9.5 17 V20 M14.5 17 V20 M4 9.5 H7 M4 14.5 H7 M17 9.5 H20 M17 14.5 H20',
    gun = 'M3 7.5 H20.5 V11 H14.5 L13.5 13.5 H10.5 L9.5 18 H5.5 L7 11 H3 Z',
    bolt = 'M13.5 2.5 L5 13.5 H11.5 L10.5 21.5 L19 10.5 H12.5 Z',
    shield = 'M12 3 L19.5 6 V11.5 C19.5 16 16.5 19.5 12 21 C7.5 19.5 4.5 16 4.5 11.5 V6 Z',
    map = 'M3 6 L9 3.5 L15 6 L21 3.5 V18 L15 20.5 L9 18 L3 20.5 Z M9 3.5 V18 M15 6 V20.5',
    home = 'M3.5 11 L12 4 L20.5 11 M6 9 V20 H18 V9 M10 20 V14 H14 V20',
    flag = 'M5 21 V3.5 M5 4 H18 L15.5 8.5 L18 13 H5',
    clock = 'M21 12 A9 9 0 1 1 3 12 A9 9 0 1 1 21 12 Z M12 7 V12 L15.5 14',
    list = 'M9 6 H20 M9 12 H20 M9 18 H20 M4.5 6 H5.5 M4.5 12 H5.5 M4.5 18 H5.5',
    edit = 'M4 20 L4.8 16.2 L15.5 5.5 L18.5 8.5 L7.8 19.2 Z M13.5 7.5 L16.5 10.5',
    plus = 'M12 5 V19 M5 12 H19',
    minus = 'M5 12 H19',
    check = 'M4.5 12.5 L9.5 17.5 L19.5 6.5',
    close = 'M6 6 L18 18 M18 6 L6 18',
    back = 'M20 12 H5 M11 6 L5 12 L11 18',
    refresh = 'M19.5 12 A7.5 7.5 0 1 1 16.8 6.2 M17.5 2.8 V6.8 H13.5',
    power = 'M7.5 6.5 A7.5 7.5 0 1 0 16.5 6.5 M12 3 V11',
    exit = 'M10 4 H5 V20 H10 M14 8 L18 12 L14 16 M18 12 H9',
    -- opx_menu's `arrow` points right; here `arrow` keeps its own drawing (up and right), so `next` gets
    -- that right arrow and stays the pair of `previous`
    next = 'M4 12 H19 M13 6 L19 12 L13 18',
}

-- Other names for the same drawings (opx_menu's aliases).
local ALIASES = {
    user = 'person', users = 'group', people = 'group', car = 'vehicle',
    settings = 'gear', cog = 'gear', wrench = 'tool', repair = 'tool',
    pin = 'location', marker = 'location', gps = 'location', cash = 'money', wallet = 'money',
    id = 'card', health = 'medical', weapon = 'gun', hack = 'chip', cyberware = 'chip',
    message = 'chat', inventory = 'box', shop = 'bag', delete = 'trash', alert = 'warning',
    pencil = 'edit', add = 'plus', remove = 'minus', ok = 'check', cancel = 'close', x = 'close',
    logout = 'exit', time = 'clock', favorite = 'star', previous = 'back',
}
for alias, name in pairs(ALIASES) do
    if Icons[alias] == nil then Icons[alias] = Icons[name] end
end

return Icons
