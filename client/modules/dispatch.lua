-- Talking to the owners of the options: the predicates that decide what a menu shows, and the
-- selected option's callback. Library registrations are reached through the export the library
-- publishes in its caller's VM (one call per resource per menu); exports-only registrations through
-- the export names they gave. A server event is sent from here, with the target's canonical id.

local Registry = require('client.modules.registry')

local Dispatch = {}

local LIB_EXPORT = 'opx_target_dispatch'
Dispatch.LIB_EXPORT = LIB_EXPORT

local function now() return Open77.time.monotonic() * 1000 end

local function log(message) print('[opx_target] ' .. message) end

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = copy(item) end
    return out
end

---The context a callback receives: plain data, plus the option it is about.
local function public(ctx, r, n)
    local c = copy(ctx)
    if r and n then
        c.option = { name = n.name, path = n.path, id = r.mode == 'lib' and r.ref or r.id, data = copy(n.data) }
    end
    return c
end

local function callSync(owner, export, ...)
    local ok, a, b = pcall(Open77.exports.callSync, owner, export, ...)
    if not ok then return false, tostring(a) end
    return true, a, b
end

-- States of the dynamic options of library registrations, one call per owner:
-- out[r.id] = { [path] = false (hidden) | true (disabled) | 'reason' (disabled) } or nil when the call failed.
local function libraryStates(regs, ctx, deadline)
    local byOwner, out = {}, {}
    for _, r in ipairs(regs) do
        if r.mode == 'lib' and r.dynamic then
            local list = byOwner[r.owner]
            if not list then list = {}; byOwner[r.owner] = list end
            list[#list + 1] = r
        end
    end
    local plain = public(ctx)
    for owner, list in pairs(byOwner) do
        if now() < deadline then
            local refs = {}
            for i, r in ipairs(list) do refs[i] = r.ref end
            local ok, result = callSync(owner, LIB_EXPORT, 'filter', refs, plain)
            if ok and type(result) == 'table' then
                for _, r in ipairs(list) do
                    out[r.id] = type(result[r.ref]) == 'table' and result[r.ref] or {}
                end
            elseif not ok then
                log(('%s: options hidden, predicate call failed: %s'):format(owner, tostring(result)))
            end
        end
    end
    return out
end

-- The state of one exports-only node: false hidden, true/'reason' disabled, nil visible.
local function exportState(r, n, ctx, deadline)
    if n.canInteract then
        if now() >= deadline then return false end
        local ok, allowed = callSync(r.owner, n.canInteract, public(ctx, r, n))
        if not ok or allowed ~= true then return false end
    end
    if n.disabledWhen then
        if now() >= deadline then return false end
        local ok, off, reason = callSync(r.owner, n.disabledWhen, public(ctx, r, n))
        if not ok then return false end
        if off then return type(reason) == 'string' and reason:sub(1, 80) or true end
    end
    return nil
end

local function nodeState(r, n, ctx, states, deadline)
    if not n.dynamic then return nil end
    if r.mode == 'lib' then
        local s = states[r.id]
        if s == nil then return false end
        return s[n.path]
    end
    return exportState(r, n, ctx, deadline)
end

local function actionable(n)
    return n.select or n.serverEvent
end

-- Drops leading, trailing and doubled separators.
local function tidy(items)
    local out = {}
    for _, it in ipairs(items) do
        if it.separator then
            if #out > 0 and not out[#out].separator then out[#out + 1] = it end
        else
            out[#out + 1] = it
        end
    end
    while #out > 0 and out[#out].separator do out[#out] = nil end
    return out
end

local function hasRow(items)
    for _, it in ipairs(items) do
        if not it.separator then return true end
    end
    return false
end

local function visible(r, nodes, ctx, states, deadline, inherited, chain)
    local out, lastOrder = {}, 0
    for index, n in ipairs(nodes) do
        if n.separator then
            -- a separator keeps its place: it sorts with the option declared before it
            out[#out + 1] = { separator = true, label = n.label, order = lastOrder, index = index }
        else
            lastOrder = n.order
            local range = n.distance or inherited
            if Registry.inRange(ctx, range) then
                local state = nodeState(r, n, ctx, states, deadline)
                if state ~= false then
                    local off = n.disabled
                    if state ~= nil then off = state end
                    local path = { table.unpack(chain) }
                    path[#path + 1] = n
                    local children = nil
                    if n.children then
                        children = visible(r, n.children, ctx, states, deadline, range, path)
                        if not hasRow(children) then children = nil end
                    end
                    if children or actionable(n) then
                        out[#out + 1] = {
                            reg = r, node = n, chain = path, distance = range,
                            label = n.label, icon = n.icon, description = n.description, group = n.group,
                            danger = n.danger, order = n.order, index = index,
                            off = off and true or false, reason = type(off) == 'string' and off or nil,
                            children = children,
                        }
                    end
                end
            end
        end
    end
    -- options keep their declared order inside a registration; `order` moves them
    table.sort(out, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.index < b.index
    end)
    return tidy(out)
end

---The menu tree for a context: every matching registration's visible options, merged.
---@param ctx table
---@return table[] items
function Dispatch.build(ctx)
    local deadline = now() + (tonumber(Config.predicateBudgetMs) or 250)
    local regs = Registry.candidates(ctx)
    local states = libraryStates(regs, ctx, deadline)
    local default = tonumber(Config.defaultDistance) or 3
    local merged = {}
    for rank, r in ipairs(regs) do
        for _, it in ipairs(visible(r, r.options, ctx, states, deadline, default, {})) do
            it.rank = rank
            merged[#merged + 1] = it
        end
    end
    -- across resources: `order` first, then registration age, then declared order
    table.sort(merged, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.index < b.index
    end)
    -- a thin line where the options of one registration end and another's begin
    local out = {}
    for _, it in ipairs(merged) do
        local prev = out[#out]
        if prev and not prev.separator and not it.separator and prev.rank ~= it.rank then
            out[#out + 1] = { separator = true }
        end
        out[#out + 1] = it
    end
    return tidy(out)
end

---Still allowed on a fresh context (same target): range, filters and the predicates of the option and
---of every parent on its way.
---@return boolean
function Dispatch.check(item, ctx)
    local r = item.reg
    if not Registry.get(r.id) or not Registry.matches(r, ctx) then return false end
    if not Registry.inRange(ctx, item.distance) then return false end
    if item.off then return false end
    local deadline = now() + (tonumber(Config.predicateBudgetMs) or 250)
    local states = r.dynamic and r.mode == 'lib' and libraryStates({ r }, ctx, deadline) or {}
    for _, n in ipairs(item.chain) do
        local state = nodeState(r, n, ctx, states, deadline)
        if state ~= nil then return false end -- hidden or disabled now
    end
    return true
end

-- Canonical id of the target for a server event (never an engine id).
local function targetId(ctx)
    local t = ctx.target or {}
    return t.playerId or t.vehicleId or t.npcId or t.propId
end

---Runs the option: the owner's callback, then its server event.
function Dispatch.fire(item, ctx)
    local r, n = item.reg, item.node
    local pub = public(ctx, r, n)
    if n.select then
        if r.mode == 'lib' then
            local ok, err = callSync(r.owner, LIB_EXPORT, 'select', r.ref, n.path, pub)
            if not ok then log(('%s: select failed: %s'):format(r.owner, tostring(err))) end
        else
            local promise, reason = Open77.exports.call(r.owner, n.onSelect, pub)
            if not promise then
                log(('%s.%s: %s'):format(r.owner, n.onSelect, tostring(reason)))
            else
                CreateThread(function()
                    local result, err = promise:await()
                    if err or result == false then
                        log(('%s.%s failed: %s'):format(r.owner, n.onSelect, tostring(err or 'returned false')))
                    end
                end)
            end
        end
    end
    if n.serverEvent then
        local t = ctx.target or {}
        local sky = ctx.kind == 'sky'
        -- the sky is a direction, never a place: no position (the end of the ray is not a world point)
        local sent, reason = TriggerServerEvent(n.serverEvent, targetId(ctx), {
            kind = ctx.kind, option = n.name, model = t.model,
            position = not sky and ((ctx.hit and ctx.hit.position) or t.position) or nil, distance = ctx.distance,
            direction = sky and ctx.direction or nil,
            data = copy(n.data),
        })
        if sent == false then log(('serverEvent %s: %s'):format(n.serverEvent, tostring(reason))) end
    end
end

return Dispatch
