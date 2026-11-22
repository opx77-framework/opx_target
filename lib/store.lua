-- The caller's own registrations, kept in its VM with their Lua functions. The service receives a
-- copy without functions (`dynamic` / `select` flags) and calls back through the export
-- `opx_target_dispatch` published below, which evaluates predicates and runs callbacks here.

local Bridge = require('@opx_target/lib.bridge')

local Store = {}

local entries = {}  -- ref -> { ref, spec, options (with functions), wire (copy), remote (service id), service (its generation) }
local sequence = 0
local retrying = false
local wantOff = false     -- this resource asked targeting off (setEnabled(false))
local claimSynced = true  -- the service holds what wantOff says

local FIELDS = { 'name', 'label', 'icon', 'description', 'group', 'danger', 'order', 'distance', 'separator', 'serverEvent' }

local function log(message) print('[opx_target] ' .. message) end

-- Generation of the running service VM, or nil when unknown.
local function serviceGeneration()
    local ok, g = pcall(Open77.resource.generation, Bridge.SERVICE)
    return ok and math.type(g) == 'integer' and g or nil
end

-- A single option or a list of options, as a list.
local function wrap(options)
    if type(options) == 'table' and (options.label ~= nil or options.separator ~= nil or options.name ~= nil) then
        return { options }
    end
    return options
end

-- JSON-like copy (functions and other values dropped).
local function plain(v, depth)
    local t = type(v)
    if t == 'string' or t == 'number' or t == 'boolean' then return v end
    if t ~= 'table' or (depth or 0) > 4 then return nil end
    local out = {}
    for k, item in pairs(v) do
        if type(k) == 'string' or math.type(k) == 'integer' then out[k] = plain(item, (depth or 0) + 1) end
    end
    return out
end

local function serialize(list)
    if type(list) ~= 'table' then return list end
    local out = {}
    for i, o in ipairs(list) do
        if type(o) ~= 'table' then
            out[i] = o -- the service refuses it with the reason
        else
            local n = {}
            for _, field in ipairs(FIELDS) do n[field] = o[field] end
            n.data = plain(o.data)
            if type(o.disabled) == 'function' then n.dynamic = true elseif o.disabled ~= nil then n.disabled = o.disabled end
            if type(o.canInteract) == 'function' then n.dynamic = true end
            if type(o.onSelect) == 'function' or type(o.event) == 'string' then n.select = true end
            if o.children ~= nil then n.children = serialize(wrap(o.children)) end
            out[i] = n
        end
    end
    return out
end

local function find(list, path)
    local node = nil
    for index in tostring(path):gmatch('%d+') do
        node = type(list) == 'table' and list[tonumber(index)] or nil
        if type(node) ~= 'table' then return nil end
        list = wrap(node.children)
    end
    return node
end

local function setOption(ctx, o, path, ref)
    ctx.option = { name = o.name or ('option_' .. path), path = path, id = ref, data = o.data }
    return ctx
end

-- Predicates of one registration: states[path] = false (hidden) | true / 'reason' (disabled).
local function evaluate(list, prefix, ctx, states, ref)
    for i, o in ipairs(type(list) == 'table' and list or {}) do
        if type(o) == 'table' and not o.separator then
            local path = prefix and (prefix .. '.' .. i) or tostring(i)
            local state = nil
            if type(o.canInteract) == 'function' then
                local ok, allowed = pcall(o.canInteract, setOption(ctx, o, path, ref))
                if not ok then log('canInteract error (' .. path .. '): ' .. tostring(allowed)) end
                if not ok or not allowed then state = false end
            end
            if state == nil and type(o.disabled) == 'function' then
                local ok, off, reason = pcall(o.disabled, setOption(ctx, o, path, ref))
                if not ok then
                    log('disabled error (' .. path .. '): ' .. tostring(off))
                    state = false
                elseif off then
                    state = (type(reason) == 'string' and reason) or (type(off) == 'string' and off) or true
                end
            end
            if state ~= nil then states[path] = state end
            if state ~= false and o.children ~= nil then evaluate(wrap(o.children), path, ctx, states, ref) end
        end
    end
end

-- Only the service calls it (the runtime names the caller); it must not yield.
exports('opx_target_dispatch', function(op, a, b, c)
    if GetInvokingResource() ~= Bridge.SERVICE then return nil end
    if op == 'filter' then
        local out = {}
        for _, ref in ipairs(type(a) == 'table' and a or {}) do
            local e = entries[ref]
            if e then
                local states = {}
                evaluate(e.options, nil, type(b) == 'table' and b or {}, states, ref)
                out[ref] = states
            end
        end
        return out
    elseif op == 'select' then
        local e = entries[a]
        local o = e and find(e.options, b)
        if not o then return false end
        local ctx = type(c) == 'table' and c or {}
        if type(ctx.option) ~= 'table' then setOption(ctx, o, b, a) end
        -- its own task: the callback may yield (dialogs, server callbacks, Wait)
        CreateThread(function()
            if type(o.onSelect) == 'function' then
                local ok, err = pcall(o.onSelect, ctx)
                if not ok then log('onSelect error (' .. tostring(b) .. '): ' .. tostring(err)) end
            end
            if type(o.event) == 'string' then TriggerEvent(o.event, ctx) end
        end)
        return true
    end
    return nil
end)

local function push(e)
    local called, id, reason = Bridge.call('LibAdd', e.spec, e.wire, e.ref)
    if not called then return false, true, reason end
    if not id then return false, false, reason end
    e.remote = id
    e.service = serviceGeneration()
    return true
end

-- The setEnabled claim the service should hold. false: the service could not be reached (retry later).
local function pushClaim()
    if claimSynced then return true end
    local called, ok = Bridge.call('setEnabled', not wantOff)
    if not called then return false end
    claimSynced = true
    if ok ~= true then log('setEnabled refused') end
    return true
end

-- The service is not reachable yet (starting) or restarted: send what is pending, a few times.
local function retry()
    if retrying then return end
    retrying = true
    CreateThread(function()
        for _ = 1, 60 do
            local pending = not pushClaim()
            for _, e in pairs(entries) do
                if not e.remote then
                    local ok, transient, reason = push(e)
                    if not ok and not transient then
                        log(('registration %d refused: %s'):format(e.ref, tostring(reason)))
                        entries[e.ref] = nil
                    elseif not ok then
                        pending = true
                    end
                end
            end
            if not pending then break end
            Wait(500)
        end
        retrying = false
    end)
end

---@return integer|nil id, string|nil reason
function Store.add(spec, options)
    if type(options) ~= 'table' then return nil, 'invalid_options' end
    sequence = sequence + 1
    local list = wrap(options)
    local e = { ref = sequence, spec = spec, options = list, wire = serialize(list) }
    local ok, transient, reason = push(e)
    if not ok and not transient then return nil, reason end
    entries[e.ref] = e
    if not ok then retry() end
    return e.ref
end

---@return boolean
function Store.remove(ref)
    local e = entries[ref]
    if not e then return false end
    entries[ref] = nil
    if e.remote then Bridge.call('remove', e.remote) end
    return true
end

function Store.removeAll()
    for ref in pairs(entries) do Store.remove(ref) end
end

---This resource's claim on targeting: false keeps it off until true. Remembered, and sent again when the
---service (re)starts, so a claim made before opx_target runs, or across its restart, still holds.
---@return boolean ok, string|nil reason
function Store.setEnabled(value)
    wantOff = value ~= true
    claimSynced = false
    local called, ok, reason = Bridge.call('setEnabled', value == true)
    if not called then
        retry()
        return false, reason or 'service_unavailable'
    end
    claimSynced = true
    return ok == true, reason
end

-- The service restarted: its registry is empty, send everything again. It stopped: nothing is held there.
local function onStart(name)
    if name ~= Bridge.SERVICE then return end
    for _, e in pairs(entries) do e.remote = nil end
    if wantOff then claimSynced = false end
    retry()
end
-- On a hot reload the new service may already hold an entry (start notice or retry first) when the old
-- one's stop notice arrives: only what was sent to another generation than the running one is dropped.
local function onStop(name)
    if name ~= Bridge.SERVICE then return end
    local running = GetResourceState(Bridge.SERVICE) == 'running' and serviceGeneration() or nil
    for _, e in pairs(entries) do
        if running == nil or e.service ~= running then e.remote, e.service = nil, nil end
    end
end
pcall(AddEventHandler, 'onClientResourceStart', onStart)
pcall(AddEventHandler, 'onClientResourceStop', onStop)

return Store
