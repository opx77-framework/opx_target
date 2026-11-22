-- The context menu: levels (root + submenus), focus, hover timing and keyboard.
-- Drawn as a tree (client/modules/view.lua): the root level hangs from the tag's diamond, a submenu from a
-- link leaving its parent row. Levels are placed in px from fixed row heights (no layout read): a submenu
-- opens to the right of its row, or to the left when it would leave the screen, and stays on that side for
-- deeper levels. A level opening leftward is mirrored (trunk on its right).

local View = require('client.modules.view')
local Locale = require('client.modules.locale')

local Menu = {
    onSelect = nil, -- function(item): a leaf was chosen (set by client/main.lua)
}

local levels = {}      -- levels[n] = { items, body, head, hasDesc, width, focus, parent, openRow, left, top, side, mirror, tilt, link }
local anchor = nil     -- { px, py, side }: the tag's diamond, where the root trunk starts
local pending = nil    -- { kind = 'open'|'trim', level } of the hover timer
local pendingToken = 0

local function maxDepth() return math.max(1, math.floor(tonumber(Config.maxDepth) or 3)) end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

function Menu.isOpen() return #levels > 0 end

-- Layout -----------------------------------------------------------------------------------------

local function layout(nodes, parent)
    local items, rows, hasDesc, lastGroup = {}, 0, false, nil
    local maxRows = math.max(1, math.floor(tonumber(Config.maxRows) or 14))
    for _, it in ipairs(nodes) do
        if it.separator then
            if it.label then
                items[#items + 1] = { t = 'grp', label = Locale.upper(it.label), h = View.GRP }
            else
                items[#items + 1] = { t = 'sep', h = View.SEP }
            end
            lastGroup = nil
        elseif rows >= maxRows then
            if Config.debug then print(('[opx_target] menu cut at %d rows (Config.maxRows)'):format(maxRows)) end
            break
        else
            if it.group and it.group ~= lastGroup then
                items[#items + 1] = { t = 'grp', label = Locale.upper(it.group), h = View.GRP }
            end
            lastGroup = it.group
            items[#items + 1] = { t = 'row', item = it, h = View.ROW }
            rows = rows + 1
            if it.description or it.reason then hasDesc = true end
        end
    end
    while #items > 0 and items[#items].t ~= 'row' do items[#items] = nil end
    local y = 0
    for _, it in ipairs(items) do
        it.y = y
        y = y + it.h
    end
    -- its own width (dp), from Config.panelWidth up to Config.panelMaxWidth for long labels
    return { items = items, body = y, hasDesc = hasDesc, parent = parent, width = View.fit(items) }
end

local function heightDp(L)
    return (L.head or 0) + L.body + (L.hasDesc and View.DESC or 0)
end

-- Where a point of level L (dp from its left / top) lands on screen once the level is tilted: it turns
-- about its trunk (Config.tilt, Config.perspective; same transform as view.lua's 'sizes' layer).
local function projected(L, xDp, yDp)
    local r = View.ratio()
    local tilt = tonumber(Config.tilt) or 0
    if tilt == 0 or not L.tilt then return L.left + xDp * r, L.top + yDp * r end
    local p = math.max(300, math.floor(tonumber(Config.perspective) or 1100))
    local ox = L.mirror and (L.width - View.TRUNK) or View.TRUNK
    local oy = heightDp(L) / 2
    local a = math.rad(L.tilt == 'l' and tilt or -tilt)
    local dx = xDp - ox
    local s = p / (p + dx * math.sin(a)) -- rotateY(+) sends +x away from the viewer
    return L.left + (ox + dx * math.cos(a) * s) * r, L.top + (oy + (yDp - oy) * s) * r
end

local function place(n, L, parent, parentRow)
    local r = View.ratio()
    local W, H = View.screen()
    local w = L.width * r
    local margin = 8
    local trunkIn = View.TRUNK * r
    if n == 1 then
        -- the trunk drops from the diamond; the tag moves with the level when the level has to move
        L.head = View.HEAD
        local h = heightDp(L) * r
        local mirror = anchor.side == 'left'
        local below = (View.DIA / 2 + 1) * r
        local left = mirror and (anchor.px - w + trunkIn) or (anchor.px - trunkIn)
        left = clamp(left, margin, math.max(margin, W - w - margin))
        local minTop = margin + View.TAGH / 2 * r + below
        local top = clamp(anchor.py + below, minTop, math.max(minTop, H - h - margin))
        L.left, L.top, L.mirror, L.side = left, top, mirror, mirror and 'left' or 'right'
        View.pin(mirror and (left + w - trunkIn) or (left + trunkIn), top - below, L.side)
    else
        -- the first item level with the parent row, a link from the row's outer edge to the trunk
        L.head = 0
        local h = heightDp(L) * r
        local rowMid = (parent.head or 0) + parentRow.y + parentRow.h / 2
        local gap = View.GAP * r
        local side = parent.side
        local ex, ey = projected(parent, side == 'right' and parent.width or 0, rowMid)
        local left = side == 'right' and (ex + gap - trunkIn) or (ex - gap - w + trunkIn)
        if side == 'right' and left + w > W - margin then
            side = 'left'
            ex, ey = projected(parent, 0, rowMid)
            left = ex - gap - w + trunkIn
        elseif side == 'left' and left < margin then
            side = 'right'
            ex, ey = projected(parent, parent.width, rowMid)
            left = ex + gap - trunkIn
        end
        left = clamp(left, margin, math.max(margin, W - w - margin))
        local tx = side == 'right' and (left + trunkIn) or (left + w - trunkIn)
        local first = L.items[1]
        local top = clamp(ey - (first and first.h or View.ROW) / 2 * r, margin, math.max(margin, H - h - margin))
        L.left, L.top, L.side, L.mirror = left, top, side, side == 'left'
        L.link = { x = math.min(ex, tx), y = ey, w = math.abs(tx - ex) }
    end
    L.tilt = (L.left + w / 2 < W / 2) and 'l' or 'r'
end

local function render(n, L)
    View.level(n, {
        items = L.items, width = L.width, hasDesc = L.hasDesc, left = L.left, top = L.top, tilt = L.tilt,
        mirror = L.mirror, link = L.link,
    })
end

-- Focus and levels -------------------------------------------------------------------------------

local function setFocus(n, i)
    local L = levels[n]
    if not L or L.focus == i then return end
    if L.focus then View.rowClass(n, L.focus, 'focus', false) end
    L.focus = i
    if i then View.rowClass(n, i, 'focus', true) end
    if L.hasDesc then
        local it = i and L.items[i] and L.items[i].item
        View.desc(n, it and ((it.off and it.reason) or it.description or it.reason) or '')
    end
end

-- Closes every level deeper than n.
local function trim(n)
    for k = #levels, n + 1, -1 do
        View.hideLevel(k)
        levels[k] = nil
    end
    local L = levels[n]
    if L and L.openRow then
        View.rowClass(n, L.openRow, 'open', false)
        L.openRow = nil
    end
end

local function rows(L)
    local out = {}
    for i, it in ipairs(L.items) do
        if it.t == 'row' then out[#out + 1] = i end
    end
    return out
end

local function focusFirst(n)
    local L = levels[n]
    local list = L and rows(L) or {}
    if list[1] then setFocus(n, list[1]) end
end

local function canOpen(n, row)
    return row and row.t == 'row' and row.item.children ~= nil and not row.item.off and n < maxDepth()
end

local function openChild(n, i, keyboard)
    local L = levels[n]
    local row = L and L.items[i]
    if not canOpen(n, row) then return end
    local child = levels[n + 1]
    if child and child.parent == i then
        if keyboard then focusFirst(n + 1) end
        return
    end
    trim(n)
    child = layout(row.item.children, i)
    if #child.items == 0 then return end
    place(n + 1, child, L, row)
    levels[n + 1] = child
    render(n + 1, child)
    L.openRow = i
    View.rowClass(n, i, 'open', true)
    if keyboard then focusFirst(n + 1) end
end

local function cancel()
    pendingToken = pendingToken + 1
    pending = nil
end

local function schedule(ms, kind, level, fn)
    pendingToken = pendingToken + 1
    local token = pendingToken
    pending = { kind = kind, level = level }
    SetTimeout(ms, function()
        if token ~= pendingToken or not Menu.isOpen() then return end
        pending = nil
        fn()
    end)
end

local function activate(n, i)
    local L = levels[n]
    local row = L and L.items[i]
    if not row or row.t ~= 'row' or row.item.off then return end
    if row.item.children then
        cancel()
        openChild(n, i, true)
        return
    end
    if Menu.onSelect then Menu.onSelect(row.item) end
end

-- API ----------------------------------------------------------------------------------------------

---Opens the root level for a built tree, hanging from the tag's diamond `at` = { px, py, side }
---(View.trunkAt()); the callout first takes the side with room for this level's own width.
---@return boolean shown
function Menu.show(tree, at)
    Menu.close()
    local L = layout(tree, nil)
    if #L.items == 0 then return false end
    anchor = View.trunkAt(L.width) or at
    place(1, L)
    levels[1] = L
    render(1, L)
    return true
end

function Menu.close()
    cancel()
    trim(0)
    levels = {}
end

---The pointer is on row i of level n.
function Menu.hoverRow(n, i)
    local L = levels[n]
    local row = L and L.items[i]
    if not row or row.t ~= 'row' then return end
    setFocus(n, i)
    local child = levels[n + 1]
    if child and child.parent == i then
        cancel()
        return
    end
    local kids = canOpen(n, row)
    if child then
        -- back on the parent: the open submenu closes after a grace delay (cancelled if the pointer returns)
        schedule(math.floor(tonumber(Config.submenuGraceMs) or 280), 'trim', n, function()
            trim(n)
            if kids and levels[n] and levels[n].focus == i then openChild(n, i, false) end
        end)
    elseif kids then
        schedule(math.floor(tonumber(Config.submenuDelayMs) or 90), 'open', n, function()
            if levels[n] and levels[n].focus == i then openChild(n, i, false) end
        end)
    else
        cancel()
    end
end

---The pointer is inside level n: keep it open, and its parent row highlighted.
function Menu.hoverPanel(n)
    if pending and pending.kind == 'trim' and pending.level < n then cancel() end
    local L = levels[n]
    if L and L.parent and levels[n - 1] then setFocus(n - 1, L.parent) end
end

function Menu.click(n, i)
    activate(n, i)
end

---Keyboard on the deepest level. Returns 'close' when the menu should close.
---@param key string
---@return string|nil
function Menu.key(key)
    local n = #levels
    local L = levels[n]
    if not L then return nil end
    if key == 'escape' then return 'close' end
    local list = rows(L)
    if key == 'down' or key == 'up' or key == 'home' or key == 'end' then
        if #list == 0 then return nil end
        local at = 0
        for k, i in ipairs(list) do
            if i == L.focus then at = k end
        end
        if key == 'home' then at = 1
        elseif key == 'end' then at = #list
        elseif at == 0 then at = key == 'down' and 1 or #list
        else at = (at - 1 + (key == 'down' and 1 or -1)) % #list + 1 end
        cancel()
        setFocus(n, list[at])
    elseif key == 'right' then
        if L.focus then openChild(n, L.focus, true) end
    elseif key == 'left' then
        if n > 1 then
            cancel()
            trim(n - 1)
            setFocus(n - 1, L.parent)
        end
    elseif key == 'enter' or key == 'space' then
        if L.focus then activate(n, L.focus) end
    end
    return nil
end

return Menu
