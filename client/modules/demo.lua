-- Developer demo, Config.debug only: `/targetdemo` toggles a demo tree on players, NPCs, vehicles,
-- doors, the world, the sky and yourself, with nested submenus, a disabled row and a predicate.
-- It goes through the public exports-only path (callbacks are named exports of this resource),
-- exactly as a third-party resource would.

if not Config.debug then return end

local RESOURCE = GetCurrentResourceName()
local ids = nil

local function say(text)
    print('[opx_target demo] ' .. text)
    -- shown on screen through opx_core's notify provider when it runs; the log line is enough otherwise
    pcall(Open77.exports.call, 'opx_core', 'Notify', text, 'info', 3000)
end

exports('opx_target_demo_select', function(ctx)
    local t = ctx.target or {}
    local id = t.playerId or t.vehicleId or t.npcId or t.propId or t.engineEntity or '-'
    local where = ctx.kind == 'sky' and ctx.direction
        and ('direction %.2f %.2f %.2f'):format(ctx.direction.x, ctx.direction.y, ctx.direction.z)
        or ('%.1f m'):format(ctx.distance or 0)
    say(('%s > %s (%s %s, %s)'):format(ctx.option and ctx.option.path or '?', ctx.option and ctx.option.name or '?',
        tostring(ctx.kind), tostring(id), where))
    return true
end)

-- canInteract: only within 2 m.
exports('opx_target_demo_close', function(ctx)
    return (ctx.distance or 99) <= 2.0
end)

-- disabledWhen: greyed with a reason (an animation provider is not wired in the demo).
exports('opx_target_demo_noprovider', function()
    return true, 'No provider'
end)

local SELECT = 'opx_target_demo_select'

local function register()
    local list = {}
    local function add(export, ...)
        local ok, id, reason = pcall(Open77.exports.callSync, RESOURCE, export, ...)
        if ok and id then list[#list + 1] = id else say(('%s failed: %s'):format(export, tostring(ok and reason or id))) end
    end
    add('addPlayer', {
        { name = 'interact', label = 'Interact', icon = 'hand', children = {
            { name = 'greet', label = 'Greet', icon = 'chat', onSelect = SELECT },
            { name = 'search', label = 'Search', icon = 'search', description = 'A submenu inside a submenu.', children = {
                { name = 'pockets', label = 'Pockets', icon = 'hand', onSelect = SELECT },
                { name = 'bag', label = 'Bag', icon = 'box', onSelect = SELECT },
            } },
            { separator = true },
            { name = 'give', label = 'Give money', icon = 'money', disabled = 'No cash', onSelect = SELECT },
            { name = 'close', label = 'Only within 2 m', icon = 'warning', danger = true, canInteract = 'opx_target_demo_close', onSelect = SELECT },
        } },
        { name = 'inspect', label = 'Inspect', icon = 'eye', description = 'Prints the target context.', onSelect = SELECT },
    })
    add('addVehicle', {
        { name = 'vehicle', label = 'Vehicle', icon = 'vehicle', distance = 4.0, children = {
            { name = 'doors', label = 'Doors', icon = 'door', children = {
                { name = 'lock', label = 'Lock', icon = 'lock', onSelect = SELECT },
                { name = 'unlock', label = 'Unlock', icon = 'unlock', onSelect = SELECT },
            } },
            { name = 'trunk', label = 'Trunk', icon = 'box', onSelect = SELECT },
            { separator = true, label = 'Staff' },
            { name = 'impound', label = 'Impound', icon = 'trash', danger = true, onSelect = SELECT },
        } },
    })
    add('addNpc', { { name = 'talk', label = 'Talk', icon = 'chat', group = 'Demo', onSelect = SELECT } })
    add('addDoor', { { name = 'knock', label = 'Knock', icon = 'door', onSelect = SELECT } })
    add('addWorld', {
        { name = 'mark', label = 'Mark this point', icon = 'location', distance = 10.0, onSelect = SELECT },
        { name = 'surface', label = 'Surface info', icon = 'info', distance = 10.0,
          description = 'Material and normal are in ctx.hit.', onSelect = SELECT },
    })
    add('addSky', { { name = 'point', label = 'Point this direction', icon = 'arrow', onSelect = SELECT } })
    add('addSelf', {
        { name = 'me', label = 'Me', icon = 'person', children = {
            { name = 'animations', label = 'Animations', icon = 'music', disabledWhen = 'opx_target_demo_noprovider', onSelect = SELECT },
            { name = 'id', label = 'Show my id', icon = 'copy', onSelect = SELECT },
        } },
    })
    return list
end

RegisterCommand(Config.demoCommand or 'targetdemo', function()
    if ids then
        for _, id in ipairs(ids) do pcall(Open77.exports.callSync, RESOURCE, 'remove', id) end
        ids = nil
        say('demo options removed')
        return
    end
    ids = register()
    say(('demo options added (%d registrations): hold %s, right click a target'):format(#ids, tostring(Config.key)))
end, false)
