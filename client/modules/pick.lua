-- Picking: what is under a screen point, as the context (`ctx`) every callback receives.
-- One Open77.camera.screenRaycast per call (a synchronous game-thread query): called on a click and at
-- the bounded hover rate while aiming, never per frame and never while the key is up.

local Pick = {}

local function finite(n) return n ~= nil and n == n and n > -math.huge and n < math.huge end

-- A vector of the engine as plain finite numbers (what goes on to callbacks, exports and server events),
-- or nil.
local function vec(v)
    if v == nil then return nil end
    local x, y, z = tonumber(v.x), tonumber(v.y), tonumber(v.z)
    if not finite(x) or not finite(y) or not finite(z) then return nil end
    return { x = x, y = y, z = z }
end

local function distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

---The local player's state when attached and alive, else nil.
function Pick.alive()
    local ok, state = pcall(Open77.character.state)
    if not ok or type(state) ~= 'table' then return nil end
    if not state.attached or not state.alive or (tonumber(state.health) or 0) <= 0 then return nil end
    return state
end

---The context under a normalized screen point (0..1).
---@param x number
---@param y number
---@return table|nil ctx, string|nil reason
function Pick.at(x, y)
    if type(x) ~= 'number' or type(y) ~= 'number' or x ~= x or y ~= y or x < 0 or x > 1 or y < 0 or y > 1 then
        return nil, 'invalid_point'
    end
    local state = Pick.alive()
    if not state then return nil, 'player_not_ready' end
    local ok, hit, reason = pcall(Open77.camera.screenRaycast, x, y, tonumber(Config.rayDistance) or 15, { self = true })
    if not ok then return nil, tostring(hit) end
    if type(hit) ~= 'table' then return nil, reason or 'no_hit' end
    local ctx = { screen = { x = x, y = y }, origin = vec(hit.origin), direction = vec(hit.direction) }
    if not hit.hit then
        -- a miss: a direction, not a place (position is only the end of the ray)
        ctx.kind = 'sky'
        ctx.target = { kind = 'sky', position = vec(hit.position) }
        return ctx
    end
    local position = vec(hit.position)
    local me = vec(state.position)
    if not position or not me then return nil, 'no_position' end
    local d = distance(position, me)
    local t = type(hit.target) == 'table' and hit.target or nil
    local kind = 'world'
    if t then kind = t.isLocalPlayer and 'self' or tostring(t.kind or 'object') end
    ctx.kind = kind
    ctx.distance = d
    ctx.hit = { position = position, normal = vec(hit.normal), material = hit.material, source = hit.hitSource }
    ctx.target = {
        kind = kind,
        playerId = t and t.playerId or nil,
        npcId = t and t.npcId or nil,
        vehicleId = t and t.vehicleId or nil,
        propId = t and t.propId or nil,
        engineEntity = t and t.engineEntity or nil,
        entity = t and t.entity or nil,
        model = t and t.record or nil,
        className = t and t.className or nil,
        name = t and t.name or nil,
        networked = t and t.networked == true or false,
        isLocalPlayer = t and t.isLocalPlayer == true or false,
        position = position,
        distance = d,
    }
    return ctx
end

---A short identity of the target: the hover UI only changes when it changes.
function Pick.key(ctx)
    if not ctx then return nil end
    local t = ctx.target or {}
    if ctx.kind == 'sky' or ctx.kind == 'world' then return ctx.kind end
    return ctx.kind .. ':' .. tostring(t.engineEntity or t.playerId or t.vehicleId or t.npcId or t.propId or '?')
end

---Same target as when the menu opened (a moving target that left the ray is not).
function Pick.same(a, b)
    if not a or not b or a.kind ~= b.kind then return false end
    if a.kind == 'sky' then
        local p, q = a.direction, b.direction
        return p ~= nil and q ~= nil and p.x * q.x + p.y * q.y + p.z * q.z > 0.9998
    end
    local ta, tb = a.target or {}, b.target or {}
    if ta.engineEntity or tb.engineEntity then return ta.engineEntity == tb.engineEntity end
    local p, q = a.hit and a.hit.position, b.hit and b.hit.position
    return p ~= nil and q ~= nil and distance(p, q) < 0.2
end

-- Entity reference for Open77.world.entityGeometry: the typed form when an Open77 id exists, else the
-- engine id, only when it converts to an exact Lua integer (never a rounded 64-bit value).
local function geometryRef(t)
    if (t.kind == 'player' or t.kind == 'self') and math.type(t.playerId) == 'integer' then return { kind = 'player', id = t.playerId } end
    if t.kind == 'vehicle' and math.type(t.vehicleId) == 'integer' then return { kind = 'vehicle', id = t.vehicleId } end
    if t.kind == 'npc' and math.type(t.npcId) == 'integer' then return { kind = 'npc', id = t.npcId } end
    local n = math.tointeger(tonumber(t.engineEntity))
    if n and tostring(n) == t.engineEntity then return n end
    return nil
end

local function geometry(ctx)
    if not ctx or ctx.kind == 'world' or ctx.kind == 'sky' or not ctx.target then return nil end
    local ref = geometryRef(ctx.target)
    if not ref then return nil end
    local ok, g = pcall(Open77.world.entityGeometry, ref)
    if not ok or type(g) ~= 'table' then return nil end
    return g
end

---Puts the entity's own position on ctx.target (the hit point stays in ctx.hit).
function Pick.enrich(ctx)
    local g = geometry(ctx)
    local p = g and vec(g.position)
    if p then ctx.target.position = p end
    return ctx
end

---Screen box of the entity's loaded mesh bounds, normalized { x0, y0, x1, y1 }, or nil (no bounds,
---behind the camera, or filling the screen). 1 geometry read + 8 projections.
function Pick.box(ctx)
    local g = geometry(ctx)
    local b = g and type(g.bounds) == 'table' and g.bounds
    local mn, mx = b and vec(b.min), b and vec(b.max)
    if not mn or not mx then return nil end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 0, 7 do
        local corner = {
            x = (i & 1) == 1 and mx.x or mn.x,
            y = (i & 2) == 2 and mx.y or mn.y,
            z = (i & 4) == 4 and mx.z or mn.z,
        }
        local ok, s = pcall(Open77.camera.project, corner)
        if not ok or type(s) ~= 'table' then return nil end
        local sx, sy = tonumber(s.x), tonumber(s.y)
        if not finite(sx) or not finite(sy) then return nil end
        if s.depth and s.depth <= 0 then return nil end
        x0, x1 = math.min(x0, sx), math.max(x1, sx)
        y0, y1 = math.min(y0, sy), math.max(y1, sy)
    end
    x0, y0 = math.max(0, x0), math.max(0, y0)
    x1, y1 = math.min(1, x1), math.min(1, y1)
    if x1 - x0 < 0.004 or y1 - y0 < 0.004 or (x1 - x0 > 0.95 and y1 - y0 > 0.95) then return nil end
    return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
end

return Pick
