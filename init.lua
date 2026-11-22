-- opx_target client library: `local Target = require('@opx_target')` in a resource that declares
-- `dependency "opx_target"`. It runs in the CALLER's VM: callbacks are plain Lua functions, kept here;
-- the opx_target service only receives a copy without functions. Registrations disappear with the
-- resource that made them. File scope is fine (pending registrations are sent once the service runs).

local Bridge = require('@opx_target/lib.bridge')
local Store = require('@opx_target/lib.store')

local Target = {}

local function typed(set)
    return function(options) return Store.add({ kinds = set }, options) end
end

---Options on other players.
Target.addPlayer = typed('player')
---Options on yourself (your visible body, F7).
Target.addSelf = typed('self')
---Options on NPCs.
Target.addNpc = typed('npc')
---Options on vehicles.
Target.addVehicle = typed('vehicle')
---Options on doors.
Target.addDoor = typed('door')
---Options on world objects (prop, object, item, device).
Target.addProp = typed('prop')
---Options on a world surface with no entity (ctx.hit.position / normal).
Target.addWorld = typed('world')
---Options on the sky: a miss within the ray, a direction (ctx.origin / ctx.direction), never a place.
Target.addSky = typed('sky')
---Options on everything that is hit (players, NPCs, vehicles, doors, objects, surfaces); not the sky, not yourself.
Target.addGlobal = typed('global')

---Options on a kind ('npc'), a set ('prop', 'global') or a list of kinds ({ 'npc', 'player' }).
---@param kinds string|string[]
---@param options OpxTargetOption|OpxTargetOption[]
---@return integer|nil id, string|nil reason
function Target.add(kinds, options)
    return Store.add({ kinds = kinds }, options)
end

---Options on exact models: a record ('Character.Judy', 'Vehicle.v_sport2_quadra_type66') or a class name.
---@param models string|string[]
---@param options OpxTargetOption|OpxTargetOption[]
---@return integer|nil id, string|nil reason
function Target.addModel(models, options)
    if models == nil then return nil, 'invalid_models' end
    return Store.add({ models = models }, options)
end

---Options on exact entities: { playerId = 3 }, { vehicleId = 12 }, { npcId = 7 }, { propId = '123' },
---{ engineEntity = '123' }, or a list of them.
---@param selectors OpxTargetSelector|OpxTargetSelector[]
---@param options OpxTargetOption|OpxTargetOption[]
---@return integer|nil id, string|nil reason
function Target.addEntity(selectors, options)
    if selectors == nil then return nil, 'invalid_entities' end
    return Store.add({ entities = selectors }, options)
end

---Removes one registration of this resource.
---@param id integer
---@return boolean
function Target.remove(id)
    return Store.remove(id)
end

---Removes every registration this resource made through the library.
function Target.removeAll()
    Store.removeAll()
end

---false: this resource keeps targeting off (and closes it) until it calls setEnabled(true) or stops.
---Other resources' claims are independent: targeting is on only while no running resource holds one.
---The wish is remembered: if opx_target is not running yet (false, 'service_unavailable'...) or restarts,
---the library sends it again by itself.
---@param value boolean
---@return boolean ok, string|nil reason
function Target.setEnabled(value)
    return Store.setEnabled(value == true)
end

---True while no resource holds targeting off (false when opx_target is not running).
function Target.isEnabled()
    local called, value = Bridge.call('isEnabled')
    return called and value == true
end

---Resources whose setEnabled(false) keeps targeting off right now, sorted ({} when none or unreachable).
---@return string[]
function Target.getDisabledBy()
    local called, value = Bridge.call('getDisabledBy')
    return called and type(value) == 'table' and value or {}
end

---Version of the running opx_target service ('1.1.0'), or nil when it is not running.
---@return string|nil
function Target.getVersion()
    local called, value = Bridge.call('getVersion')
    return called and value or nil
end

---True while the player aims (key held), menu open or not.
function Target.isOpen()
    local called, value = Bridge.call('isOpen')
    return called and value == true
end

---True while a context menu is on screen.
function Target.isMenuOpen()
    local called, value = Bridge.call('isMenuOpen')
    return called and value == true
end

---Closes the aim and its menu (a fresh key press is needed to aim again).
function Target.close()
    Bridge.call('close')
end

return Target
