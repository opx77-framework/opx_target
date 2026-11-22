-- opx_target service: hold the key to aim, the configured mouse button opens the context menu on what is
-- under the cursor. Owns the one document, the input lease and the registry; every option belongs to
-- the resource that registered it (client/modules/api.lua, init.lua).
-- Nothing runs while the key is up: the key mapping starts a loop that ends with the aim.

local Locale = require('client.modules.locale')
local Registry = require('client.modules.registry')
local Pick = require('client.modules.pick')
local View = require('client.modules.view')
local Menu = require('client.modules.menu')
local Dispatch = require('client.modules.dispatch')
local Api = require('client.modules.api')
local L = Locale.t

local RESOURCE = GetCurrentResourceName()
local MAPPING = 'opx_target.activate'
local BUTTONS = { left = 0, right = 1, middle = 2 }
local OPEN_BUTTON = BUTTONS[Config.openButton] or 1

local active = false     -- aiming (the document holds the input)
local generation = 0     -- bumped on every enter / exit: a stale loop or timer stops
local armed = true       -- a fresh key press may enter (false until the key is really released)
local rearming = false
local controls = false   -- this resource holds its aim / shoot / interaction / rotation blocks
local pointer = nil      -- { x, y (0..1), px, py }
local moved = false
local menuCtx = nil      -- context of the open menu

local function log(message) print('[opx_target] ' .. message) end
local function now() return Open77.time.monotonic() * 1000 end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function key()
    local ok, k = pcall(Open77.input.keyFor, MAPPING)
    return ok and type(k) == 'string' and k ~= '' and k or Config.key
end

-- Open77.input.isDown reads A-Z, 0-9, F1-F12, named keys, mouse and pad buttons only: a binding on another
-- key (NUMPAD0, punctuation, an AZERTY row character...) is never seen held, so the eye never opens on it.
-- Said once per key, with the reason.
local unreadable = nil

local function held()
    local k = key()
    local ok, down, why = pcall(Open77.input.isDown, k)
    if ok and down ~= true and why ~= nil and unreadable ~= k then
        unreadable = k
        log(('key "%s" cannot be read as held (%s): bind "%s" to a letter, a digit, F1-F12 or a named key')
            :format(tostring(k), tostring(why), L('binding')))
    end
    return ok and down == true
end

local function kindLabel(kind)
    local id = 'kind_' .. tostring(kind)
    local text = L(id)
    return text ~= id and text or L('kind_unknown')
end

local function distanceText(ctx)
    local d = ctx.distance
    if ctx.kind == 'sky' or type(d) ~= 'number' then return '' end
    local text = d < 10 and ('%.1f'):format(d) or tostring(math.floor(d + 0.5))
    local sep = L('decimal')
    if sep ~= 'decimal' and sep ~= '.' then text = text:gsub('%.', function() return sep end) end
    return L('distance', text)
end

local function idText(ctx)
    local t = ctx.target or {}
    local id = t.playerId or t.vehicleId or t.npcId or t.propId
    return id ~= nil and ('#' .. tostring(id)) or ''
end

-- What the tag shows for a context (and the identity the brackets lock on).
local function hoverState(ctx)
    return { kind = kindLabel(ctx.kind), id = idText(ctx), dist = distanceText(ctx), hot = Registry.anyFor(ctx),
        key = Pick.key(ctx) }
end

-- The hint bar: the keys are only named when this aim holds the keyboard (Config.captureKeyboard, or a
-- client that refused a cursor-only lease); otherwise Escape and the arrows go to the game.
local function aimHint()
    local name = BUTTONS[Config.openButton] and Config.openButton or 'right'
    return L(View.keyboard() and 'hint_aim' or 'hint_aim_mouse', L('button_' .. name))
end

local function menuHint()
    return L(View.keyboard() and 'hint_menu' or 'hint_menu_mouse')
end

-- Aim, shoot and interaction blocks plus a frozen camera while aiming; released on exit.
local function claimControls(on)
    local P = Open77.players
    if not on then
        -- Always release everything this VM holds (as open77_contextmenu does), whatever `controls` says:
        -- a block left behind freezes the camera after targeting.
        controls = false
        local okReset, reset = pcall(P.resetControls)
        if okReset and reset ~= false then return true end
        for _, call in ipairs({ { P.allowAim, true }, { P.allowShoot, true }, { P.allowInteraction, true }, { P.freezeRotation, false } }) do
            pcall(call[1], call[2])
        end
        return true
    end
    if controls then return true end
    controls = true
    local ok = true
    local calls = { { P.allowAim, false }, { P.allowShoot, false }, { P.allowInteraction, false }, { P.freezeRotation, true } }
    for _, call in ipairs(calls) do
        local success, result = pcall(call[1], call[2])
        if not success or result == false then ok = false end
    end
    return ok
end

local function rearm()
    if rearming then return end
    rearming = true
    CreateThread(function()
        while held() do Wait(100) end
        armed, rearming = true, false
    end)
end

local function boxPx(box)
    if not box then return nil end
    local W, H = View.screen()
    return { left = box.x0 * W, top = box.y0 * H, width = (box.x1 - box.x0) * W, height = (box.y1 - box.y0) * H }
end

-- Exit / menu -----------------------------------------------------------------------------------

local function exit(reason)
    if not active then return end
    active = false
    generation = generation + 1
    pointer, menuCtx = nil, nil
    -- Give the camera and the input back FIRST, each step protected: an error in the visual
    -- clean-up must never leave the player with a frozen camera or a held cursor.
    local okControls, errControls = pcall(claimControls, false)
    local okView, errView = pcall(View.aimStop)   -- blurs (releases the cursor lease) then hides
    local okMenu, errMenu = pcall(Menu.close)
    if not (okControls and okView and okMenu) then
        log(('exit %s: controls=%s view=%s menu=%s'):format(tostring(reason), tostring(errControls or 'ok'),
            tostring(errView or 'ok'), tostring(errMenu or 'ok')))
    end
    if Config.debug then log('closed: ' .. tostring(reason)) end
    if held() then rearm() else armed = true end
end

local function closeMenu()
    Menu.close()
    menuCtx = nil
    View.lock(false)
    View.frame(nil)
    View.hint(aimHint())
    if pointer then View.reticleAt(pointer.px, pointer.py) end
    moved = true
end

local function openMenu()
    if not pointer or Menu.isOpen() then return end
    local ctx = Pick.at(pointer.x, pointer.y)
    if not ctx then View.miss(L('no_target')); return end
    Pick.enrich(ctx)
    local tree = Dispatch.build(ctx)
    if not active then return end
    -- the tag the tree hangs from shows this very target
    if Config.highlight then View.frame(boxPx(Pick.box(ctx))) end
    View.hover(hoverState(ctx))
    local shown = #tree > 0 and Menu.show(tree, View.trunkAt())
    if not shown then View.miss(L('no_actions')); return end
    menuCtx = ctx
    View.lock(true)
    View.hint(menuHint())
end

Menu.onSelect = function(item)
    if not active or not menuCtx then return end
    -- the target is resolved again by a fresh ray at the same point, never taken from the UI
    local fresh = Pick.at(menuCtx.screen.x, menuCtx.screen.y)
    if not fresh or not Pick.same(menuCtx, fresh) then closeMenu(); View.miss(L('target_lost')); return end
    Pick.enrich(fresh)
    if not Dispatch.check(item, fresh) then closeMenu(); View.miss(L('unavailable')); return end
    -- input goes back before the callback runs, so it may open its own interface
    exit('selected')
    Dispatch.fire(item, fresh)
end

-- Aim loop --------------------------------------------------------------------------------------

local function hover()
    local ctx = Pick.at(pointer.x, pointer.y)
    local state = ctx and hoverState(ctx)
    -- nothing under the cursor (or only the open sky with no option for it): a faint note, no callout
    if not ctx or (ctx.kind == 'sky' and not state.hot) then
        View.frame(nil)
        View.hover(nil, L('no_target'))
        return
    end
    if Config.highlight then View.frame(boxPx(Pick.box(ctx))) end
    View.hover(state)
end

local function revalidate()
    local fresh = Pick.at(menuCtx.screen.x, menuCtx.screen.y)
    if not fresh or not Pick.same(menuCtx, fresh) then
        closeMenu()
        View.miss(L('target_lost'))
        return
    end
    if Config.highlight then View.frame(boxPx(Pick.box(fresh)), true) end
end

local function loop(gen)
    CreateThread(function()
        local lost, nextIdle, nextCheck = 0, 0, 0
        local hoverMs = math.max(16, math.floor(tonumber(Config.hoverMs) or 80))
        local idleMs = math.max(hoverMs, math.floor(tonumber(Config.hoverIdleMs) or 300))
        local checkMs = math.max(hoverMs, math.floor(tonumber(Config.revalidateMs) or 200))
        while active and generation == gen do
            -- released key, death, or a game window in the background for about three polls
            local okCursor, cursor = pcall(Open77.input.cursor)
            lost = (okCursor and cursor) and 0 or lost + 1
            local state = Pick.alive()
            if not held() then exit('released')
            elseif not state then exit('dead')
            elseif state.inVehicle and not Config.allowInVehicle then exit('vehicle')
            elseif lost >= 3 then exit('background')
            else
                -- one failing pass must not kill the loop that notices ALT being released
                local ok, err = pcall(function()
                    local t = now()
                    if menuCtx then
                        if t >= nextCheck then
                            nextCheck = t + checkMs
                            revalidate()
                        end
                    elseif pointer and (moved or t >= nextIdle) then
                        moved, nextIdle = false, t + idleMs
                        hover()
                    end
                end)
                if not ok then
                    log('aim pass failed: ' .. tostring(err))
                    exit('error')
                    return
                end
                Wait(hoverMs)
            end
        end
    end)
end

local function enter()
    if active or not armed then return end
    if not View.isReady() or not Registry.enabled() or not held() then return end
    local okCap, captured = pcall(Open77.input.isCaptured)
    if okCap and captured then return end -- another interface has the input
    local state = Pick.alive()
    if not state then return end
    if state.inVehicle and not Config.allowInVehicle then return end
    local okCursor, cursor = pcall(Open77.input.cursor)
    if not okCursor or type(cursor) ~= 'table' or cursor.captured then return end
    if not Locale.ready then Locale.load() end
    active, armed = true, false
    generation = generation + 1
    pointer, menuCtx, moved = nil, nil, false
    -- from here on every way out goes through exit(): an error while showing the document or taking the
    -- controls must never leave the cursor held or the camera frozen with no loop to notice the release
    local ok, why = pcall(function()
        if not View.aimStart(Locale.upper(key())) then return 'focus_refused' end
        View.hint(aimHint()) -- after the lease: it says whether the keyboard is held
        if not claimControls(true) then return 'controls_unavailable' end
        loop(generation)
    end)
    if not ok then
        log('aim start failed: ' .. tostring(why))
        exit('error')
    elseif why then
        exit(why)
    end
end

-- Document input --------------------------------------------------------------------------------

local H = View.handlers

H.move = function(px, py)
    if not active then return end
    local W, Hs = View.screen()
    pointer = { x = clamp(px / W, 0, 1), y = clamp(py / Hs, 0, 1), px = px, py = py }
    moved = true
    if not menuCtx then View.reticleAt(px, py) end
end

H.press = function(button, px, py)
    if not active then return end
    if Menu.isOpen() then closeMenu(); return end -- a click outside the menu closes it
    if button ~= OPEN_BUTTON then return end
    if px then H.move(px, py) end
    openMenu()
end

H.panelPress = function(button)
    if active and Menu.isOpen() and button == 1 then closeMenu() end
end

H.rowHover = function(n, i) if active then Menu.hoverRow(n, i) end end
H.panelHover = function(n) if active then Menu.hoverPanel(n) end end
H.rowClick = function(n, i) if active then Menu.click(n, i) end end

H.key = function(k)
    if not active then return end
    if Menu.isOpen() then
        if Menu.key(k) == 'close' then closeMenu() end
    elseif k == 'escape' then
        exit('cancelled')
    end
end

-- the input went to another surface (a WebUI page opened, the window was deactivated, a reload)
H.blur = function(reason)
    if active then exit('focus_lost:' .. tostring(reason)) end
end

Api.hooks.isOpen = function() return active end
Api.hooks.isMenuOpen = function() return active and Menu.isOpen() end
Api.hooks.close = function(reason) exit(reason or 'closed') end

-- Lifecycle -------------------------------------------------------------------------------------

AddEventHandler('open77:pauseKey', function() exit('pause') end)

AddEventHandler('onClientResourceStop', function(name)
    if name == RESOURCE then
        exit('stopped')
        if Config.blockWeaponWheel then pcall(Open77.input.setNativeActionBlocked, 'WeaponWheel', false) end
        View.destroy()
    else
        -- By generation, never by name: on a hot reload the resource's new VM may have registered again
        -- before this notice of the old one arrives, and its entries must stay.
        Registry.sweep()
    end
end)

Locale.load()

local created, reason = View.create()
if not created then
    log('targeting disabled, NativeUI document unavailable: ' .. tostring(reason))
else
    if type(Open77.camera.screenRaycast) ~= 'function' then
        log('this client has no screen picking (Open77.camera.screenRaycast): targeting disabled')
    else
        if Config.blockWeaponWheel then
            local ok, blocked, why = pcall(Open77.input.setNativeActionBlocked, 'WeaponWheel', true)
            if not ok or not blocked then log('cannot block the native weapon wheel: ' .. tostring(ok and why or blocked)) end
        end
        local ok, keyOrReason = RegisterKeyMapping(MAPPING, L('binding'), Config.key, function() enter() end)
        if not ok then log('key mapping refused: ' .. tostring(keyOrReason)) end
    end
end

require('client.modules.demo')
