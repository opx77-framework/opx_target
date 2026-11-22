-- The targeting document (ui/target.rml), "Scan de cible": the cursor mark, the frame on the hovered
-- entity, the callout (leader line + tag) leaving the frame's side, the menu tree that drops from the tag,
-- the hint bar. It only draws and reports input; client/main.lua and client/modules/menu.lua decide.
-- Positions are written as left / top / right in px (mouse coordinates and projections are px); the
-- motion channels used are opacity, scale and x (x / y take physical pixels, so dp are converted with
-- the measured px-per-dp ratio first).

local Icons = require('client.modules.icons')
local Locale = require('client.modules.locale')

local View = {}

-- Sizes in dp, in step with ui/target.rcss.
View.HEAD = 12        -- root level: the trunk from the tag's diamond to the first branch
View.ROW, View.SEP, View.GRP, View.DESC = 30, 10, 22, 34
View.TRUNK = 8        -- the trunk's x inside a level, from its trunk side
View.GAP = 14         -- link from a parent row's edge to its submenu's trunk
View.TAGH, View.DIA = 18, 8

-- What a row holds beside its label, in dp: the gutter with its piece of trunk (22), the side bar (2), the
-- paddings (8 + 10), the icon and its margin (15 + 9). A chevron adds 12 + 6, an inline reason its box
-- (8 + 1 + 7) and 6 dp a character (Roboto Mono 10 dp). A group header: Chakra Petch 10 dp capitals with
-- 3 dp of tracking, about 9.4 dp a character, in a 4 + 4 dp padding. The description: two lines.
local GUTTER, ROW_CHROME, CHEVRON_W = 22, 66, 18
local WHY_BOX, WHY_CHAR, WHY_MAX = 16, 6, 18
local GROUP_PAD, GROUP_CHAR = 8, 9.4
local DESC_PAD, DESC_SLACK = 8, 48

-- The callout, in dp: horizontal reach from the frame's side to the diamond, how far below the anchor
-- the tag sits, the longest horizontal run of the angled part. The frame: padding, smallest side.
local REACH, DROP, DIAG = 58, 26, 34
local FRAME_PAD, FRAME_MIN = 6, 34
local MARGIN = 8 -- px kept free at the screen edges

local MODEL = 'tg'
local CHEVRON = 'M8 5l7 7-7 7'

local ui = nil
local ready = false
local handlers = {}    -- move, press, panelPress, rowHover, rowClick, panelHover, key, blur
View.handlers = handlers

local sent = {}        -- last values sent (only changes are sent)
local screenW, screenH = nil, nil
local pxPerDp = nil
local nuiReduced = false -- the player's nui.reducedmotion, measured by the cursor mark's entrance
local aimSeq = 0         -- one number per aim: a late callback of an earlier aim is ignored
local missToken = 0
local missing = false    -- a short failure note owns #note for a moment
local drawFlip = false

-- The input lease of the current aim. By default only the cursor is borrowed: the game keeps the keyboard
-- (the player walks, push-to-talk works). Config.captureKeyboard, or a client that refuses a cursor-only
-- lease, takes the keyboard too.
local leaseKeyboard = false
local forceKeyboard = false
local refusals = 0       -- cursor-only leases refused after the fact, in a row

-- What the callout is laid out from.
local cursorX, cursorY = 0, 0
local box = nil          -- the frame in px { l, t, w, h }, or nil (the callout leaves the cursor)
local tagOn = false
local targetKey = nil    -- identity of the target the brackets were drawn for
local emptyNote = nil    -- the faint note shown while nothing is under the cursor
local pin = nil          -- { x, y, side }: the diamond held where the open menu's trunk starts
local calloutWidth = nil -- dp: the root level about to hang from the tag (nil: the smallest level)
local trunk = { x = 0, y = 0, side = 'right' } -- where the diamond is now

local function log(message) print('[opx_target] ' .. message) end
local function clamp(v, a, b) return v < a and a or (v > b and b or v) end

local function replacePlain(text, from, to)
    local out, pos = {}, 1
    while true do
        local first, last = text:find(from, pos, true)
        if not first then break end
        out[#out + 1] = text:sub(pos, first - 1)
        out[#out + 1] = to
        pos = last + 1
    end
    out[#out + 1] = text:sub(pos)
    return table.concat(out)
end

-- Theme -----------------------------------------------------------------------------------------

local function hex2(n) return ('%02x'):format(math.floor(clamp(n, 0, 255) + 0.5)) end

-- A theme value as the hex colour the sheet can take: '#rrggbb', or '#rrggbbaa' where `alpha` is allowed
-- (elsewhere the sheet appends its own alpha to the base colour, so a given alpha is dropped). An old
-- 'rgb(r, g, b)' / 'rgba(r, g, b, a)' value is converted: RmlUi reads each rgba() component as 0..255 or
-- a percentage, so the CSS habit `rgba(3, 17, 23, 0.80)` is fully transparent there. nil: not a colour.
local function colour(value, alpha)
    if type(value) ~= 'string' then return nil end
    local v = value:gsub('%s+', ''):lower()
    local rgb, a = v:match('^#(%x%x%x%x%x%x)(%x?%x?)$')
    if rgb and #a ~= 1 then return '#' .. rgb .. (alpha and a or '') end
    local r, g, b, rest = v:match('^rgba?%(([%d%.]+),([%d%.]+),([%d%.]+)(.-)%)$')
    r, g, b = tonumber(r), tonumber(g), tonumber(b)
    if not r or not g or not b then return nil end
    local out = '#' .. hex2(r) .. hex2(g) .. hex2(b)
    if rest ~= '' then
        local n, percent = rest:match('^,([%d%.]+)(%%?)$')
        n = tonumber(n)
        if not n then return nil end
        -- a <= 1 is a CSS fraction (1 = opaque), a percentage is a percentage, anything else is 0..255
        if alpha then out = out .. hex2(percent == '%' and n * 2.55 or (n <= 1 and n * 255 or n)) end
    end
    return out
end
View.colour = colour

-- Swap the `@token name value` defaults of the sheet for Config.theme.
local function applyTheme(rcss)
    local theme, swaps = Config.theme or {}, {}
    for key, value in rcss:gmatch('@token%s+(%S+)%s+([^\n]-)%s*\n') do
        local wanted = theme[key]
        if wanted ~= nil then
            local hex = colour(wanted, key == 'panel')
            if not hex then
                log(('Config.theme.%s = %s is not a colour (#rrggbb%s): the default is kept'):format(key,
                    tostring(wanted), key == 'panel' and ' or #rrggbbaa' or ''))
            elseif hex ~= value then
                swaps[#swaps + 1] = { from = value, to = hex }
            end
        end
    end
    -- Longest default first, and through placeholders: a colour moved onto another token's default (holo
    -- and accent exchanged) must not be swapped a second time.
    table.sort(swaps, function(a, b) return #a.from > #b.from end)
    for i, swap in ipairs(swaps) do rcss = replacePlain(rcss, swap.from, '\1' .. i .. '\2') end
    for i, swap in ipairs(swaps) do rcss = replacePlain(rcss, '\1' .. i .. '\2', swap.to) end
    return rcss
end

-- Sizes -----------------------------------------------------------------------------------------

---Smallest width of a menu level in dp (Config.panelWidth).
function View.width()
    return math.max(160, math.floor(tonumber(Config.panelWidth) or 240))
end

---Largest width of a menu level in dp (Config.panelMaxWidth, never under the smallest).
function View.maxWidth()
    return math.max(View.width(), math.floor(tonumber(Config.panelMaxWidth) or 420))
end

local function depth() return math.max(1, math.floor(tonumber(Config.maxDepth) or 3)) end

local function levelMarkup(n)
    return ([[
<div id="lv%d" class="lv">
    <div class="lv-head"><div class="cn"><div class="cn-v"></div></div></div>
    <div class="lv-rows" id="lv%d-rows"></div>
    <div class="lv-desc"><span id="lv%d-desc"></span></div>
</div>]]):format(n, n, n)
end

local function buildSource()
    local rml = Open77.resource.readFile('ui/target.rml')
    local rcss = Open77.resource.readFile('ui/target.rcss')
    if not rml or not rcss then return nil, 'ui_files_unreadable' end
    local link = '<link type="text/rcss" href="target.rcss"/>'
    if not rml:find(link, 1, true) then return nil, 'ui_link_missing' end
    rml = replacePlain(rml, link, '<style>\n' .. applyTheme(rcss) .. '\n</style>')
    local parts = {}
    for n = 2, depth() do parts[#parts + 1] = ('<div id="lk%d" class="lk"></div>'):format(n) end
    for n = 1, depth() do parts[#parts + 1] = levelMarkup(n) end
    return replacePlain(rml, '<div id="levels"></div>', table.concat(parts, '\n'))
end

-- Widths, tilt and hinge from Config, as a stylesheet layer over the sheet. A level turns about its
-- trunk side, so the trunk (and what it connects to) stays in place.
local function sizeSheet()
    local tilt = tonumber(Config.tilt) or 0
    local p = math.max(300, math.floor(tonumber(Config.perspective) or 1100))
    local sheet = {
        -- the smallest width: View.level writes each level's own (View.fit)
        ('.lv { width: %ddp; transform-origin: %ddp 50%%; }'):format(View.width(), View.TRUNK),
        -- a mirrored level has its trunk on the right, 8 dp from the edge whatever its width: it turns
        -- about that edge (the trunk moves by less than a tenth of a dp)
        '.lv.mir { transform-origin: 100% 50%; }',
    }
    if tilt ~= 0 then
        sheet[#sheet + 1] = ('.lv.tilt-l { transform: perspective(%ddp) rotateY(%.2fdeg); }'):format(p, tilt)
        sheet[#sheet + 1] = ('.lv.tilt-r { transform: perspective(%ddp) rotateY(%.2fdeg); }'):format(p, -tilt)
    end
    return table.concat(sheet, '\n')
end

-- Text ------------------------------------------------------------------------------------------

-- Characters the client fonts do not draw, in text that comes from other resources (labels, reasons,
-- descriptions pasted from a word processor): swapped for ones they do draw.
local function glyphs(text)
    return (text:gsub('\226\128[\152\153]', "'")   -- ‘ ’
        :gsub('\226\128[\156\157]', '"')           -- “ ”
        :gsub('\226\128\166', '...')               -- …
        :gsub('\226\128\162', '\194\183')          -- • becomes ·
        :gsub('\226\128[\147\148]', '-')           -- – —
        :gsub('\226\128[\137\175]', ' '))          -- thin and narrow no-break spaces
end

---Text safe inside RML: markup escaped, and no "{{" the data model would evaluate.
function View.escape(value)
    local text = glyphs(tostring(value == nil and '' or value)):gsub('[%c]', ' ')
    text = text:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'):gsub('"', '&quot;')
    text = text:gsub('{', '{ '):gsub('}', ' }')
    return text
end
local esc = View.escape

-- Advance of each printable ASCII character (32..126) in Rajdhani at 16 dp, in tenths of a dp, rounded
-- up (measured on the font file). Lua cannot measure text, and a level is placed before a frame exists
-- (ui:rect answers one frame later): its width comes from this estimate.
local ADVANCE = {}
do
    local byte = 31
    for tenths in ('43 38 53 109 81 115 96 30 46 46 65 84 31 50 31 64 83 51 77 80 84 78 80 61 84 80 31 31 83 85 85 76 '
        .. '121 86 88 87 90 77 74 87 92 37 80 85 73 112 93 89 84 89 86 90 68 89 80 128 81 79 78 46 64 46 75 60 44 '
        .. '81 81 64 81 79 49 81 82 34 34 69 34 124 82 80 81 81 51 69 56 82 67 110 67 74 65 48 34 48 84'):gmatch('%d+') do
        byte = byte + 1
        ADVANCE[byte] = tonumber(tenths) / 10
    end
end

-- Width in dp of `text` drawn in Rajdhani at `size` dp with `spacing` dp after each character. An
-- accented letter counts as a wide capital (9.3), Œ and Æ as what they are (12.4).
local function textWidth(text, size, spacing)
    local width, scale = 0, size / 16
    for ch in text:gmatch('[%z\1-\127\194-\253][\128-\191]*') do
        local advance = ADVANCE[ch:byte()] or ((ch == '\197\146' or ch == '\195\134') and 12.4 or 9.3)
        width = width + advance * scale + spacing
    end
    return width
end

local function count(text) return select(2, text:gsub('[^\128-\191]', '')) end

-- What a row shows: its label in capitals, and its reason beside it when that is short.
local function rowLabel(item) return Locale.upper(glyphs(tostring(item.label or ''))) end
local function rowWhy(item)
    local reason = item.reason
    if type(reason) ~= 'string' or reason == '' then return nil end
    reason = glyphs(reason)
    return #reason <= WHY_MAX and reason or nil
end
local function quoted(text) return Locale.t('quote', glyphs(text)) end

---Width in dp of the level that shows `items` (client/modules/menu.lua): room for its longest row (label,
---inline reason, chevron), its group headers and a two-line description, between Config.panelWidth and
---Config.panelMaxWidth. What still does not fit is cut at the row's edge.
---@param items table[] { t = 'row', item } | { t = 'grp', label } | { t = 'sep' }
---@return integer
function View.fit(items)
    local low, high = View.width(), View.maxWidth()
    local need = 0
    for _, it in ipairs(items) do
        local w = 0
        if it.t == 'grp' then
            w = GUTTER + GROUP_PAD + count(tostring(it.label or '')) * GROUP_CHAR
        elseif it.t == 'row' then
            local item = it.item
            -- 4 % and 3 dp of air: the estimate knows neither kerning nor the pixel rounding of a glyph
            w = ROW_CHROME + textWidth(rowLabel(item), 16, 1.5) * 1.04 + 3
            local why = rowWhy(item)
            if why then w = w + WHY_BOX + count(why) * WHY_CHAR end
            if item.children then w = w + CHEVRON_W end
            local note = type(item.description) == 'string' and item.description or ''
            if type(item.reason) == 'string' and #item.reason > #note then note = item.reason end
            if note ~= '' then
                w = math.max(w, GUTTER + DESC_PAD + DESC_SLACK + textWidth(quoted(note), 14, 0) / 2)
            end
        end
        if w > need then need = w end
    end
    if Config.debug and need > high then
        log(('a menu level needs %d dp and Config.panelMaxWidth is %d: its longest text is cut'):format(math.ceil(need), high))
    end
    return clamp(math.ceil(need), low, high)
end

function View.calm()
    return Config.reducedMotion == true or nuiReduced
end

-- Events ----------------------------------------------------------------------------------------

local function emit(name, ...)
    local fn = handlers[name]
    if fn then fn(...) end
end

local function mouse(e)
    local x, y = tonumber(e and e.mouse_x), tonumber(e and e.mouse_y)
    if not x or not y then return nil end
    return x, y
end

local function listen()
    ui:on('mousemove', '#hit', function(e)
        refusals = 0 -- the pointer answers: the lease of this aim is live
        local x, y = mouse(e)
        if x then emit('move', x, y) end
    end)
    ui:on('mousedown', '#hit', function(e)
        local x, y = mouse(e)
        emit('press', tonumber(e.button) or 0, x, y)
    end)
    ui:on('mousedown', '.lv', function(e) emit('panelPress', tonumber(e.button) or 0) end)
    ui:on('mouseover', '.row', function(e)
        local n, i = tostring(e.id or ''):match('^r(%d+)_(%d+)$')
        if n then emit('rowHover', tonumber(n), tonumber(i)) end
    end)
    ui:on('click', '.row', function(e)
        local n, i = tostring(e.id or ''):match('^r(%d+)_(%d+)$')
        if n then emit('rowClick', tonumber(n), tonumber(i)) end
    end)
    ui:on('mouseover', '.lv', function(e)
        local n = tostring(e.id or ''):match('^lv(%d+)$')
        if n then emit('panelHover', tonumber(n)) end
    end)
    -- only with the keyboard lease (Config.captureKeyboard): a cursor-only lease sends no key here
    ui:on('keydown', function(e) emit('key', tostring(e.key or '')) end)
    ui:onEvent('focus', function(kind, detail)
        if kind == 'blur' then emit('blur', type(detail) == 'table' and detail.reason or 'blur') end
    end)
    ui:onEvent('error', function(kind, detail)
        local message = tostring(type(detail) == 'table' and detail.message or '')
        if kind == 'focus' then
            -- A lease refused after the fact. Twice in a row for a cursor-only one, with no pointer event
            -- in between: this client wants the full lease, as before.
            if not leaseKeyboard and not forceKeyboard then
                refusals = refusals + 1
                if refusals >= 2 then
                    forceKeyboard = true
                    log('cursor-only focus refused twice (' .. (message ~= '' and message or 'focus_unavailable')
                        .. '): the keyboard is held too while aiming, from now on')
                end
            end
            emit('blur', message ~= '' and message or 'focus_unavailable')
            return
        end
        if Config.debug then log(('ui %s: %s'):format(tostring(kind), message)) end
    end)
    ui:onEvent('loaded', function()
        ui:stylesheet('sizes', sizeSheet())
        ui:class('#root', 'calm', View.calm())
        ui:hide()
        ready = true
    end)
    ui:onEvent('reloaded', function()
        ui:stylesheet('sizes', sizeSheet())
        sent = {}
        emit('blur', 'reloaded')
    end)
end

---@return boolean ok, string|nil reason
function View.create()
    if ui then return true end
    if type(Open77.ui) ~= 'table' or type(Open77.ui.create) ~= 'function' then return false, 'nativeui_unavailable' end
    local source, reason = buildSource()
    if not source then return false, reason end
    local doc, err = Open77.ui.create({
        source = source, layer = 'menu', zIndex = math.floor(tonumber(Config.zIndex) or 90), visible = false,
        models = { [MODEL] = { tagKind = '', tagId = '', tagDist = '', note = '', key = '', hint = '' } },
    })
    if not doc then return false, err or 'ui_create_failed' end
    ui = doc
    listen()
    return true
end

function View.destroy()
    if ui then pcall(ui.destroy, ui) end
    ui, ready, sent = nil, false, {}
end

function View.isReady() return ui ~= nil and ready end

-- Screen ----------------------------------------------------------------------------------------

---Screen size in px (the document's own, a snapshot of the last frame).
function View.screen()
    local ok, state = pcall(ui.state, ui)
    if ok and type(state) == 'table' and (tonumber(state.width) or 0) > 0 then
        screenW, screenH = tonumber(state.width), tonumber(state.height)
    elseif not screenW then
        local c = Open77.input.cursor()
        if type(c) == 'table' and tonumber(c.width) then screenW, screenH = tonumber(c.width), tonumber(c.height) end
    end
    return screenW or 1920, screenH or 1080
end

---px per dp, measured on #dpref (100 dp); the 1080p rule until a frame has published it.
function View.ratio()
    local ok, r = pcall(ui.rect, ui, '#dpref')
    if ok and type(r) == 'table' and (tonumber(r.width) or 0) > 0 then pxPerDp = r.width / 100 end
    if pxPerDp then return pxPerDp end
    local _, h = View.screen()
    return math.max(0.5, h / 1080)
end

-- Helpers ---------------------------------------------------------------------------------------

local function merge(fields)
    local diff = nil
    for k, v in pairs(fields) do
        if sent[k] ~= v then
            sent[k] = v
            diff = diff or {}
            diff[k] = v
        end
    end
    if diff then ui:merge(MODEL, diff) end
end

local function class(sel, name, on)
    local key = sel .. '.' .. name
    on = on == true
    if sent[key] == on then return end
    sent[key] = on
    ui:class(sel, name, on)
end

-- Inline style, sent only when it changed (`key` names the remembered value).
local function place(sel, key, props)
    local parts = {}
    for k, v in pairs(props) do parts[#parts + 1] = k .. '=' .. v end
    table.sort(parts)
    local sig = table.concat(parts, ';')
    if sent[key] == sig then return end
    sent[key] = sig
    ui:style(sel, props)
end

local function px(v) return math.floor(v + 0.5) .. 'px' end

-- The brackets and the leader draw themselves again (flips the restart classes on #root).
local function redraw()
    if View.calm() then return end
    drawFlip = not drawFlip
    ui:class('#root', 'draw-a', drawFlip)
    ui:class('#root', 'draw-b', not drawFlip)
end

-- Note beside the cursor ------------------------------------------------------------------------

local function placeNote()
    if not sent['#note.on'] then return end
    local r = View.ratio()
    local W = View.screen()
    -- away from the callout when there is one, else to the right unless the edge is near
    local left = (tagOn and trunk.side == 'right') or cursorX + 180 * r > W
    class('#note', 'left', left)
    local top = px(cursorY + 9 * r)
    if left then
        place('#note', 'notePos', { left = 'auto', right = px(W - cursorX + 12 * r), top = top })
    else
        place('#note', 'notePos', { left = px(cursorX + 12 * r), right = 'auto', top = top })
    end
end

local function noteShow(text, flash)
    merge({ note = text })
    class('#note', 'flash', flash == true)
    class('#note', 'on', true)
    placeNote()
end

local function noteOff()
    class('#note', 'on', false)
    class('#note', 'flash', false)
end

-- Callout -----------------------------------------------------------------------------------------

-- Lays out the leader and the tag from the frame (or the cursor) and the pin of an open menu.
local function layoutCallout()
    if not ui then return end
    if not tagOn then
        class('#tag', 'on', false)
        class('#lead', 'on', false)
        return
    end
    local r = View.ratio()
    local W, H = View.screen()
    local l, t, w, h
    if box then
        l, t, w, h = box.l, box.t, box.w, box.h
    else
        local s = 10 * r
        l, t, w, h = cursorX - s, cursorY - s, 2 * s, 2 * s
    end
    local right
    if pin then
        right = pin.side ~= 'left'
    else
        -- the side with room for the leader and a menu level hanging from the tag
        local need = (REACH + (calloutWidth or View.width()) - View.TRUNK + 6) * r + MARGIN
        local roomR, roomL = W - (l + w), l
        right = roomR >= need or (roomL < need and roomR >= roomL)
    end
    local gap = 5 * r
    local ax = right and (l + w + gap) or (l - gap)
    local ay = box and (t + h * 0.3) or cursorY
    local dx, dy
    if pin then
        dx, dy = pin.x, pin.y
        -- the anchor slides along the frame's side toward a tag the menu moved, keeping the leader short
        if box then ay = clamp(dy - DROP * r, t + 4 * r, math.max(t + 4 * r, t + h - 4 * r)) end
    else
        local half = View.TAGH / 2 * r
        dx = clamp(ax + (right and REACH or -REACH) * r, MARGIN, W - MARGIN)
        dy = clamp(ay + DROP * r, MARGIN + half, H - MARGIN - half)
    end
    trunk.x, trunk.y, trunk.side = dx, dy, right and 'right' or 'left'

    -- leader: from the frame's side, angled to the tag's height, then level up to the diamond's edge
    local s = dx >= ax and 1 or -1
    local run = math.min(math.abs(dy - ay), DIAG * r, math.max(0, math.abs(dx - ax) - 8 * r))
    local ex, ey = ax + s * run, dy
    local lx = dx - s * (View.DIA / 2 + 2) * r
    if (lx - ex) * s < 0 then lx = ex end
    local pad = 3
    local x0 = math.floor(math.min(ax, ex, lx)) - pad
    local y0 = math.floor(math.min(ay, ey)) - pad
    local x1 = math.ceil(math.max(ax, ex, lx)) + pad
    local y1 = math.ceil(math.max(ay, ey)) + pad
    local bw, bh = x1 - x0, y1 - y0
    local d = ('M%.1f %.1f L%.1f %.1f L%.1f %.1f'):format(ax - x0, ay - y0, ex - x0, ey - y0, lx - x0, ey - y0)
    if sent.leadD ~= d then
        sent.leadD = d
        ui:style('#lead', { width = bw .. 'px', height = bh .. 'px' })
        ui:attr('#lead', 'view-box', ('0 0 %d %d'):format(bw, bh))
        ui:attr('#lead', 'd', d)
    end
    place('#lead', 'leadPos', { left = x0 .. 'px', top = y0 .. 'px' })

    -- tag: the diamond's centre on (dx, dy), the text away from the leader
    local half = View.DIA / 2 * r
    local top = px(dy - View.TAGH / 2 * r)
    if right then
        place('#tag', 'tagPos', { left = px(dx - half), right = 'auto', top = top })
    else
        place('#tag', 'tagPos', { left = 'auto', right = px(W - dx - half), top = top })
    end
    class('#tag', 'left', not right)
    class('#tag', 'on', true)
    class('#lead', 'on', true)
    placeNote()
end

---Where the tag's diamond is: the top of the menu's trunk. { px, py, side 'right'|'left' }
---`width` (dp) is the root level about to hang from it: the callout takes the side with room for it
---(until the menu closes).
function View.trunkAt(width)
    if width and not pin and width ~= calloutWidth then
        calloutWidth = width
        layoutCallout()
    end
    return { px = trunk.x, py = trunk.y, side = trunk.side }
end

---Holds the diamond at (x, y) on `side` while a menu hangs from it (client/modules/menu.lua).
function View.pin(x, y, side)
    pin = { x = x, y = y, side = side }
    layoutCallout()
end

-- Aiming ----------------------------------------------------------------------------------------

-- Borrows the input for this aim. A cursor-only lease first (the game keeps the keyboard); a client that
-- answers no to it gets the full lease, which is what every client accepted before.
local function takeFocus()
    local keyboard = Config.captureKeyboard == true or forceKeyboard
    local ok = ui:focus({ keyboard = keyboard, cursor = true })
    if not ok and not keyboard then
        ok = ui:focus({ keyboard = true, cursor = true })
        if ok then
            keyboard, forceKeyboard = true, true
            log('cursor-only focus refused by this client: the keyboard is held too while aiming')
        end
    end
    leaseKeyboard = keyboard
    return ok ~= false and ok ~= nil
end

---True when the current aim holds the keyboard too (arrow keys and Enter then move in the menu, Escape
---reaches the document). Known once View.aimStart has taken the input.
function View.keyboard()
    return leaseKeyboard
end

---Shows the cursor mark (screen centre: the lease puts the pointer there) and takes the input.
---@param key string the held key, as shown on the key cap
---@return boolean focused
function View.aimStart(key)
    aimSeq = aimSeq + 1
    local seq = aimSeq
    ui:show()
    ui:watch('#dpref')
    local w, h = View.screen()
    View.reticleAt(math.floor(w / 2), math.floor(h / 2))
    merge({ key = key })
    class('#cursor', 'on', true)
    class('#hintbar', 'on', true)
    class('#root', 'calm', View.calm())
    local at = GetGameTimer()
    ui:animate('#cursor', { from = { opacity = 0, scale = 1.8 }, to = { opacity = 1, scale = 1 },
        spring = { duration = 0.35, bounce = 0.2 } }, function()
        -- The spring takes ~0.35 s; landing at once means the player's nui.reducedmotion is on. The
        -- callback of an aim that already ended says nothing (it may have been cut short).
        if not ui or seq ~= aimSeq then return end
        nuiReduced = GetGameTimer() - at < 120
        class('#root', 'calm', View.calm())
    end)
    return takeFocus()
end

function View.aimStop()
    if not ui then return end
    aimSeq = aimSeq + 1
    ui:blur()
    ui:unwatch('#dpref')
    for n = 1, depth() do View.hideLevel(n) end
    missToken, missing = missToken + 1, false
    pin, calloutWidth = nil, nil
    View.hover(nil)
    View.frame(nil)
    View.lock(false)
    noteOff()
    class('#cursor', 'on', false)
    class('#cursor', 'miss', false)
    class('#hintbar', 'on', false)
    ui:hide()
end

---The hint bar's text after the key cap (the model's `hint`; an empty text clears it).
---@param text string|nil
function View.hint(text)
    merge({ hint = type(text) == 'string' and text or '' })
end

---The cursor mark (and the callout, when it has no frame to leave from) follows the pointer.
function View.reticleAt(x, y)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if sent.rx == x and sent.ry == y then return end
    sent.rx, sent.ry = x, y
    cursorX, cursorY = x, y
    ui:style('#cursor', { left = x .. 'px', top = y .. 'px' })
    placeNote()
    if not box then layoutCallout() end
end

---What is under the cursor: { kind, id, dist, hot, key } or nil (nothing; `empty` is the faint note then).
function View.hover(state, empty)
    if state then
        merge({ tagKind = state.kind or '', tagId = state.id or '', tagDist = state.dist or '' })
        class('#tag', 'no-id', (state.id or '') == '')
        class('#tag', 'no-dist', (state.dist or '') == '')
        local fresh = not tagOn or state.key ~= targetKey
        tagOn, targetKey, emptyNote = true, state.key, nil
        local hot = state.hot == true
        class('#tag', 'hot', hot)
        class('#lead', 'hot', hot)
        class('#frame', 'hot', hot)
        class('#cursor', 'hot', hot)
        if not missing then noteOff() end
        layoutCallout()
        if fresh then
            -- lock-on: the brackets and the leader draw themselves, the tag comes in
            redraw()
            ui:animate('#tag', { from = { opacity = 0 }, to = { opacity = 1 }, tween = { duration = 0.2, easing = 'ease-out' } })
        end
        return
    end
    tagOn, targetKey, emptyNote = false, nil, empty
    class('#tag', 'hot', false)
    class('#lead', 'hot', false)
    class('#frame', 'hot', false)
    class('#cursor', 'hot', false)
    layoutCallout()
    if not missing then
        if empty then noteShow(empty, false) else noteOff() end
    end
end

---Frame around the hovered entity: { left, top, width, height } in px (mesh bounds), or nil.
function View.frame(b, lock)
    if not b then
        class('#frame', 'on', false)
        if box then
            box = nil
            layoutCallout()
        end
        return
    end
    local r = View.ratio()
    local pad, min = FRAME_PAD * r, FRAME_MIN * r
    local l, t = b.left - pad, b.top - pad
    local w, h = b.width + 2 * pad, b.height + 2 * pad
    if w < min then l, w = l - (min - w) / 2, min end
    if h < min then t, h = t - (min - h) / 2, min end
    l, t, w, h = math.floor(l), math.floor(t), math.floor(w), math.floor(h)
    place('#frame', 'framePos', { left = l .. 'px', top = t .. 'px', width = w .. 'px', height = h .. 'px' })
    box = { l = l, t = t, w = w, h = h }
    class('#frame', 'lock', lock == true)
    class('#frame', 'on', true)
    layoutCallout()
end

---Locked on the target of an open menu: red brackets, red diamond, the frame clamps.
function View.lock(on)
    on = on == true
    class('#cursor', 'lock', on)
    class('#frame', 'lock', on)
    class('#tag', 'lock', on)
    class('#lead', 'lock', on)
    if on then
        redraw()
        ui:animate('#frame', { from = { scale = 1.1 }, to = { scale = 1 }, spring = { duration = 0.3, bounce = 0.3 } })
        ui:animate('#cursor', { from = { scale = 1.5 }, to = { scale = 1 }, spring = { duration = 0.3, bounce = 0.35 } })
    elseif pin or calloutWidth then
        pin, calloutWidth = nil, nil
        layoutCallout()
    end
end

---A short failure note beside the cursor (no target, no action, target lost, unavailable).
function View.miss(text)
    missToken = missToken + 1
    local token = missToken
    missing = true
    noteShow(text, true)
    class('#cursor', 'miss', true)
    ui:animate('#cursor', { from = { scale = 0.7 }, to = { scale = 1 }, spring = { duration = 0.3, bounce = 0.5 } })
    SetTimeout(900, function()
        if not ui or token ~= missToken then return end
        missing = false
        class('#cursor', 'miss', false)
        if not tagOn and emptyNote then noteShow(emptyNote, false) else noteOff() end
    end)
end

-- Menu levels -----------------------------------------------------------------------------------

local TRUNK_ONLY = '<div class="cn"><div class="cn-v"></div></div>'
local BRANCH = '<div class="cn"><div class="cn-v"></div><div class="cn-h"></div></div>'

local function rowsRml(n, items)
    local out, total = {}, #items
    for i, it in ipairs(items) do
        local pos = (i == 1 and ' first' or '') .. (i == total and ' last' or '')
        if it.t == 'sep' then
            out[#out + 1] = '<div class="it sep' .. pos .. '">' .. TRUNK_ONLY .. '<div class="sep-line"></div></div>'
        elseif it.t == 'grp' then
            out[#out + 1] = '<div class="it grp' .. pos .. '">' .. TRUNK_ONLY .. '<span>' .. esc(it.label) .. '</span></div>'
        else
            local item = it.item
            local classes = 'it row' .. pos
            if item.off then classes = classes .. ' off' end
            if item.danger then classes = classes .. ' danger' end
            if item.children then classes = classes .. ' kids' end
            local reason = rowWhy(item)
            local why = reason and ('<span class="why">' .. esc(reason) .. '</span>') or ''
            local chev = item.children and ('<div class="chev"><path view-box="0 0 24 24" d="' .. CHEVRON .. '"/></div>') or ''
            out[#out + 1] = ('<div class="%s" id="r%d_%d">%s<div class="rb"><div class="ic"><path view-box="0 0 24 24" d="%s"/></div>'
                .. '<span class="lb">%s</span>%s%s</div></div>'):format(classes, n, i, BRANCH, Icons[item.icon] or Icons.dot,
                esc(rowLabel(item)), why, chev)
        end
    end
    return table.concat(out)
end

---Draws level n of the tree: { items, width (dp), hasDesc, left, top (px), tilt 'l'|'r', mirror,
---link = { x, y, w } (px) }.
function View.level(n, spec)
    local sel = '#lv' .. n
    local link = n > 1 and ('#lk' .. n) or nil
    local width = math.floor(tonumber(spec.width) or View.width())
    ui:batch(function()
        ui:text(sel .. '-desc', '')
        ui:rml(sel .. '-rows', rowsRml(n, spec.items))
        ui:class(sel, 'has-desc', spec.hasDesc == true)
        ui:class(sel, 'tilt-l', spec.tilt == 'l')
        ui:class(sel, 'tilt-r', spec.tilt == 'r')
        ui:class(sel, 'mir', spec.mirror == true)
        ui:class(sel, 'sub', n > 1)
        ui:style(sel, { left = math.floor(spec.left) .. 'px', top = math.floor(spec.top) .. 'px', width = width .. 'dp' })
        ui:class(sel, 'on', true)
        if link then
            if spec.link then
                ui:style(link, { left = px(spec.link.x), top = math.floor(spec.link.y) .. 'px', width = px(math.max(1, spec.link.w)) })
            end
            ui:class(link, 'on', spec.link ~= nil)
        end
    end)
    sent['lv' .. n] = true
    -- the tree unfolds: items (and their pieces of trunk) come in one after the other, rows slide off the trunk
    local r = View.ratio()
    ui:animate(sel, { from = { opacity = 0 }, to = { opacity = 1 }, tween = { duration = 0.12, easing = 'ease-out' } })
    ui:animate(sel .. ' .it', { from = { opacity = 0 }, to = { opacity = 1 },
        tween = { duration = 0.16, easing = 'ease-out' }, stagger = 0.022 })
    ui:animate(sel .. ' .rb', { from = { x = (spec.mirror and 10 or -10) * r }, to = { x = 0 },
        tween = { duration = 0.2, easing = 'ease-out' }, stagger = 0.022 })
    if link and spec.link then
        ui:animate(link, { from = { opacity = 0 }, to = { opacity = 1 }, tween = { duration = 0.12, easing = 'ease-out' } })
    end
end

function View.hideLevel(n)
    if not sent['lv' .. n] then return end
    sent['lv' .. n] = nil
    local sel = '#lv' .. n
    ui:class(sel, 'on', false)
    ui:rml(sel .. '-rows', '')
    if n > 1 then ui:class('#lk' .. n, 'on', false) end
end

function View.rowClass(n, i, name, on)
    ui:class(('#r%d_%d'):format(n, i), name, on)
end

---The focused row's description under level n, quoted (empty clears it).
function View.desc(n, text)
    text = type(text) == 'string' and text or ''
    if text ~= '' then text = quoted(text):gsub('{', '{ '):gsub('}', ' }') end
    ui:text(('#lv%d-desc'):format(n), text)
end

return View
