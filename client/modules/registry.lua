-- Every resource's registrations: validation, ownership, static matching. The owner always comes from
-- the runtime (GetInvokingResource in client/modules/api.lua), never from an argument, so a resource
-- can only add, change or remove its own options. Nothing here calls into another VM.

local Icons = require('client.modules.icons')

local Registry = {}

-- Kinds a target can be (ctx.kind). 'self' is the local player, 'sky' a miss within the ray.
Registry.KINDS = {
    player = true, self = true, npc = true, vehicle = true, door = true, prop = true,
    device = true, item = true, object = true, world = true, sky = true,
}

-- Kinds behind each typed helper (addPlayer, addProp...).
Registry.SETS = {
    player = { 'player' },
    self = { 'self' },
    npc = { 'npc' },
    vehicle = { 'vehicle' },
    door = { 'door' },
    prop = { 'prop', 'object', 'item', 'device' },
    world = { 'world' },
    sky = { 'sky' },
    -- any entity or surface hit; the sky and yourself stay opt-in
    global = { 'player', 'npc', 'vehicle', 'door', 'prop', 'object', 'item', 'device', 'world' },
}

local SELECTOR_INTEGER = { playerId = true, vehicleId = true, npcId = true }
local SELECTOR_STRING = { propId = true, engineEntity = true }

local regs = {}        -- id -> registration
local ownerCount = {}  -- owner -> number of registrations
local claims = {}      -- owner -> generation: setEnabled(false) claims
local sequence = 0
local total = 0        -- registrations held, all owners

-- function(any): the first registration arrived (true) or the last one went (false). Nothing sets it
-- today: client/main.lua blocks the weapon wheel for as long as the resource runs (Config.blockWeaponWheel).
Registry.changed = nil

local function finite(n) return type(n) == 'number' and n == n and n > -math.huge and n < math.huge end
local function text(v, max) return type(v) == 'string' and #v > 0 and #v <= max and not v:find('[%c]') end
local function name(v) return text(v, 64) and v:match('^[%w_%.:%-]+$') ~= nil end

local function counted(delta)
    local had = total > 0
    total = total + delta
    if (total > 0) ~= had and Registry.changed then
        local ok, err = pcall(Registry.changed, total > 0)
        if not ok then print('[opx_target] ' .. tostring(err)) end
    end
end

-- An unknown icon name draws the dot. Said once per name, with or without Config.debug: a typo, or a name
-- learned from another menu, is silent otherwise.
local unknownIcons, unknownCount = {}, 0
local function unknownIcon(icon, owner, path)
    if unknownIcons[icon] or unknownCount >= 32 then return end
    unknownIcons[icon], unknownCount = true, unknownCount + 1
    local shown = icon:sub(1, 40):gsub('[%c]', '?')
    print(('[opx_target] %s: unknown icon "%s" (option %s), the dot is drawn instead. Names: README, Options.')
        :format(tostring(owner), shown, path))
end

local function dense(v, max)
    if type(v) ~= 'table' or #v < 1 or #v > max then return false end
    local count = 0
    for k in pairs(v) do
        if math.type(k) ~= 'integer' or k < 1 or k > #v then return false end
        count = count + 1
    end
    return count == #v
end

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, item in pairs(v) do out[k] = copy(item) end
    return out
end

-- Static `data` of an option: JSON-like, 4 levels, about 2 KiB.
local function dataValid(value)
    local remaining = 2048
    local function visit(v, depth)
        remaining = remaining - 8
        if remaining < 0 or depth > 4 then return false end
        local t = type(v)
        if t == 'string' then remaining = remaining - #v; return remaining >= 0 end
        if t == 'number' then return finite(v) end
        if t == 'boolean' or v == nil then return true end
        if t ~= 'table' then return false end
        for k, item in pairs(v) do
            local keyOk = (type(k) == 'string' and #k <= 64) or (math.type(k) == 'integer' and k >= 1 and k <= 64)
            if not keyOk or not visit(item, depth + 1) then return false end
        end
        return true
    end
    return visit(value, 0)
end

local function selectorValid(v)
    if type(v) ~= 'table' then return false end
    local count = 0
    for k, id in pairs(v) do
        count = count + 1
        if SELECTOR_INTEGER[k] then
            if math.type(id) ~= 'integer' or id < 1 then return false end
        elseif SELECTOR_STRING[k] then
            if type(id) ~= 'string' or #id > 20 or not id:match('^[1-9]%d*$') then return false end
        else
            return false
        end
    end
    return count == 1
end

-- A list of strings as a set; nil when absent.
local function stringSet(list, max, check)
    if list == nil then return nil, true end
    if type(list) == 'string' then list = { list } end
    if not dense(list, max) then return nil, false end
    local set = {}
    for _, v in ipairs(list) do
        if not check(v) then return nil, false end
        set[v] = true
    end
    return set, true
end

---True while the owner of a registration still runs the generation that registered it.
---@param r table
---@return boolean
function Registry.alive(r)
    local state = GetResourceState(r.owner)
    if state ~= 'running' and state ~= 'starting' then return false end
    return Open77.resource.generation(r.owner) == r.generation
end

local function erase(id)
    local r = regs[id]
    if not r then return end
    regs[id] = nil
    local left = (ownerCount[r.owner] or 1) - 1
    ownerCount[r.owner] = left > 0 and left or nil
    counted(-1)
end

---Drops the registrations whose owner stopped, or runs another generation than the one that made them
---(a reload). The entries its new generation already sent are kept: what is compared is the generation,
---never the name alone. One state read per owner and generation.
function Registry.sweep()
    local known = {}
    for id, r in pairs(regs) do
        local key = r.owner .. '#' .. r.generation
        local alive = known[key]
        if alive == nil then
            alive = Registry.alive(r)
            known[key] = alive
        end
        if not alive then erase(id) end
    end
end

-- Options -------------------------------------------------------------------------------------

-- One option list (or a single option) into validated nodes. mode 'lib': `dynamic` / `select` are
-- flags set by the library (the functions stay in the caller's VM). mode 'exports': `canInteract`,
-- `disabledWhen` and `onSelect` name exports of the owner.
local function normalize(list, mode, depth, prefix, budget)
    if type(list) ~= 'table' then return nil, 'invalid_options' end
    if list.label ~= nil or list.separator ~= nil or list.name ~= nil then list = { list } end
    if not dense(list, 32) then return nil, 'invalid_options' end
    local nodes = {}
    for i, o in ipairs(list) do
        local path = prefix and (prefix .. '.' .. i) or tostring(i)
        if type(o) ~= 'table' then return nil, 'invalid_option:' .. path end
        budget.count = budget.count + 1
        if budget.count > budget.max then return nil, 'option_limit' end
        local n = { path = path }
        if o.separator then
            n.separator = true
            if o.label ~= nil then
                if not text(o.label, 40) then return nil, 'invalid_label:' .. path end
                n.label = o.label
            end
        else
            if not text(o.label, 80) then return nil, 'invalid_label:' .. path end
            if o.name ~= nil and not name(o.name) then return nil, 'invalid_name:' .. path end
            if o.description ~= nil and not text(o.description, 180) then return nil, 'invalid_description:' .. path end
            if o.group ~= nil and not text(o.group, 40) then return nil, 'invalid_group:' .. path end
            if o.icon ~= nil and type(o.icon) ~= 'string' then return nil, 'invalid_icon:' .. path end
            if o.icon ~= nil and not Icons[o.icon] then unknownIcon(o.icon, budget.owner, path) end
            if o.danger ~= nil and type(o.danger) ~= 'boolean' then return nil, 'invalid_danger:' .. path end
            local order = o.order or 0
            if math.type(order) ~= 'integer' or math.abs(order) > 1000 then return nil, 'invalid_order:' .. path end
            if o.distance ~= nil and (not finite(o.distance) or o.distance < 0.1 or o.distance > (tonumber(Config.maxDistance) or 50)) then
                return nil, 'invalid_distance:' .. path
            end
            local disabled = o.disabled
            if disabled ~= nil and type(disabled) ~= 'boolean' and not text(disabled, 80) then return nil, 'invalid_disabled:' .. path end
            if o.serverEvent ~= nil and not name(o.serverEvent) then return nil, 'invalid_server_event:' .. path end
            if not dataValid(o.data) then return nil, 'invalid_data:' .. path end
            n.name = o.name or ('option_' .. path)
            n.label = o.label
            n.description = o.description
            n.group = o.group
            n.icon = o.icon
            n.danger = o.danger == true
            n.order = order
            n.distance = o.distance
            n.disabled = disabled ~= false and disabled or nil
            n.serverEvent = o.serverEvent
            n.data = copy(o.data)
            if mode == 'lib' then
                n.dynamic = o.dynamic == true or nil
                n.select = o.select == true or nil
            else
                for _, field in ipairs({ 'canInteract', 'disabledWhen', 'onSelect' }) do
                    if o[field] ~= nil and not name(o[field]) then return nil, 'invalid_' .. field .. ':' .. path end
                end
                n.canInteract, n.disabledWhen, n.onSelect = o.canInteract, o.disabledWhen, o.onSelect
                n.dynamic = (n.canInteract or n.disabledWhen) and true or nil
                n.select = n.onSelect and true or nil
            end
            if o.children ~= nil then
                if depth >= (tonumber(Config.maxDepth) or 3) then return nil, 'too_deep:' .. path end
                local children, err = normalize(o.children, mode, depth + 1, path, budget)
                if not children then return nil, err end
                n.children = children
            elseif not n.select and not n.serverEvent then
                return nil, 'option_without_action:' .. path
            end
        end
        nodes[i] = n
    end
    return nodes
end

local function anyDynamic(nodes)
    for _, n in ipairs(nodes) do
        if n.dynamic or (n.children and anyDynamic(n.children)) then return true end
    end
    return false
end

-- Registration --------------------------------------------------------------------------------

---@param owner string
---@param generation integer
---@param mode 'lib'|'exports'
---@param spec table { kinds?, models?, entities? }
---@param options table
---@param ref? any library-local id (mode 'lib')
---@return integer|nil id, string|nil reason
function Registry.add(owner, generation, mode, spec, options, ref)
    if not name(owner) or math.type(generation) ~= 'integer' then return nil, 'invalid_owner' end
    Registry.sweep()
    spec = type(spec) == 'table' and spec or {}
    local kinds, kindsOk = stringSet(spec.kinds, 16, function(v) return Registry.KINDS[v] == true end)
    if not kindsOk then return nil, 'invalid_kinds' end
    local models, modelsOk = stringSet(spec.models, 64, function(v) return text(v, 200) end)
    if not modelsOk then return nil, 'invalid_models' end
    local entities = nil
    if spec.entities ~= nil then
        local list = spec.entities
        if selectorValid(list) then list = { list } end
        if not dense(list, 32) then return nil, 'invalid_entities' end
        for _, v in ipairs(list) do
            if not selectorValid(v) then return nil, 'invalid_entities' end
        end
        entities = copy(list)
    end
    if not kinds and not models and not entities then return nil, 'invalid_filter' end
    -- The library sends a registration again when this service restarted (or when it cannot tell): the
    -- same owner and library id replaces its previous entry, it never doubles it.
    local previous = nil
    if mode == 'lib' and ref ~= nil then
        for id, r in pairs(regs) do
            if r.owner == owner and r.mode == 'lib' and r.ref == ref then previous = id; break end
        end
    end
    local limits = Config.limits or {}
    if (ownerCount[owner] or 0) - (previous and 1 or 0) >= (limits.perResource or 64) then return nil, 'registration_limit' end
    local budget = { count = 0, max = limits.optionsPerRegistration or 64, owner = owner }
    local nodes, err = normalize(options, mode, 1, nil, budget)
    if not nodes then return nil, err end
    sequence = sequence + 1
    regs[sequence] = {
        id = sequence, owner = owner, generation = generation, mode = mode, ref = ref,
        kinds = kinds, models = models, entities = entities, options = nodes, dynamic = anyDynamic(nodes),
    }
    ownerCount[owner] = (ownerCount[owner] or 0) + 1
    counted(1)
    if previous then erase(previous) end
    return sequence
end

---@return boolean ok, string|nil reason
function Registry.remove(owner, id)
    local r = regs[id]
    if not r then return false, 'not_found' end
    if r.owner ~= owner then return false, 'not_owner' end
    erase(id)
    return true
end

---Every registration of one resource (its own `removeAll`). Its setEnabled(false) claim is another matter:
---only setEnabled(true) or the end of the resource releases it.
function Registry.removeOwner(owner)
    for id, r in pairs(regs) do
        if r.owner == owner then erase(id) end
    end
end

-- Disable claims: targeting is on while no running resource holds one.
function Registry.setEnabled(owner, generation, value)
    claims[owner] = (not value) and generation or nil
end

-- A claim made at file scope comes from a resource still 'starting': it counts (same rule as Registry.alive).
function Registry.enabled()
    for owner, generation in pairs(claims) do
        local state = GetResourceState(owner)
        if (state ~= 'running' and state ~= 'starting') or Open77.resource.generation(owner) ~= generation then
            claims[owner] = nil
        end
    end
    return next(claims) == nil
end

---Resources holding targeting off right now (sorted names, for debugging).
---@return string[]
function Registry.claimants()
    Registry.enabled()
    local out = {}
    for owner in pairs(claims) do out[#out + 1] = owner end
    table.sort(out)
    return out
end

-- Matching ------------------------------------------------------------------------------------

---Static filters only (kind, model, entity), no predicate.
function Registry.matches(r, ctx)
    local kind = ctx.kind
    if r.kinds then
        if not r.kinds[kind] then return false end
    elseif kind == 'sky' then
        return false -- the sky is opt-in: only a registration naming it
    end
    local t = ctx.target or {}
    if r.models and not ((t.model and r.models[t.model]) or (t.className and r.models[t.className])) then return false end
    if r.entities then
        local hit = false
        for _, selector in ipairs(r.entities) do
            for k, id in pairs(selector) do
                if t[k] == id then hit = true end
            end
        end
        if not hit then return false end
    end
    return Registry.alive(r)
end

---Matching registrations, oldest first.
---@return table[]
function Registry.candidates(ctx)
    Registry.sweep()
    local out = {}
    for _, r in pairs(regs) do
        if Registry.matches(r, ctx) then out[#out + 1] = r end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

---In range of an option's distance (always for the sky).
function Registry.inRange(ctx, distance)
    if ctx.kind == 'sky' then return true end
    return finite(ctx.distance) and ctx.distance <= distance
end

---Cheap hover hint: could this target show something (predicates are not run)?
function Registry.anyFor(ctx)
    local default = tonumber(Config.defaultDistance) or 3
    for _, r in pairs(regs) do
        if Registry.matches(r, ctx) then
            for _, n in ipairs(r.options) do
                if not n.separator and Registry.inRange(ctx, n.distance or default) then return true end
            end
        end
    end
    return false
end

function Registry.get(id)
    return regs[id]
end

return Registry
