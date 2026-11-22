-- Client exports of opx_target. Two ways in, one registry:
--  * exports-only (any resource, any style): Open77.exports.call('opx_target', 'addPlayer', options)
--    where `onSelect`, `canInteract`, `disabledWhen` are names of the CALLER's own client exports;
--  * the library (`require('@opx_target')`, init.lua) uses LibAdd: its callbacks stay plain Lua functions
--    in the caller's VM and are reached through the export the library publishes there.
-- The owner of every call is the runtime's GetInvokingResource(), never an argument.

local Registry = require('client.modules.registry')

local Api = {
    VERSION = '1.1.0',
    hooks = {}, -- isOpen(), isMenuOpen(), close(reason): set by client/main.lua
}

local function owner()
    return GetInvokingResource(), GetInvokingResourceGeneration()
end

local function kindsOf(kinds)
    if type(kinds) == 'string' then
        if Registry.SETS[kinds] then return Registry.SETS[kinds] end
        return { kinds }
    end
    return kinds
end

local function add(mode, spec, options, ref)
    local r, g = owner()
    if not r or not g then return nil, 'export_call_required' end
    return Registry.add(r, g, mode, spec, options, ref)
end

local function typed(set)
    return function(options) return add('exports', { kinds = Registry.SETS[set] }, options) end
end

exports('addPlayer', typed('player'))
exports('addSelf', typed('self'))
exports('addNpc', typed('npc'))
exports('addVehicle', typed('vehicle'))
exports('addDoor', typed('door'))
exports('addProp', typed('prop'))
exports('addWorld', typed('world'))
exports('addSky', typed('sky'))
exports('addGlobal', typed('global'))

-- add(kinds, options): kinds is a kind ('npc'), a helper set name ('prop', 'global') or a list of kinds.
exports('add', function(kinds, options)
    return add('exports', { kinds = kindsOf(kinds) }, options)
end)

-- addModel(models, options): exact record ('Character.Judy', 'Vehicle.v_sport2_quadra_type66') or class name.
exports('addModel', function(models, options)
    if models == nil then return nil, 'invalid_models' end
    return add('exports', { models = models }, options)
end)

-- addEntity(selectors, options): { playerId = 3 } / { vehicleId = 12 } / { npcId = 7 } / { propId = '123' } /
-- { engineEntity = '123' }, or a list of them.
exports('addEntity', function(selectors, options)
    if selectors == nil then return nil, 'invalid_entities' end
    return add('exports', { entities = selectors }, options)
end)

exports('remove', function(id)
    local r = owner()
    if not r then return false, 'export_call_required' end
    return Registry.remove(r, id)
end)

exports('removeAll', function()
    local r = owner()
    if not r then return false, 'export_call_required' end
    Registry.removeOwner(r)
    return true
end)

-- setEnabled(false) holds a claim of the calling resource that keeps targeting off (and closes it);
-- setEnabled(true) releases only that claim. Claims end when their resource stops.
exports('setEnabled', function(value)
    local r, g = owner()
    if not r or not g then return false, 'export_call_required' end
    if type(value) ~= 'boolean' then return false, 'expected_boolean' end
    Registry.setEnabled(r, g, value)
    if not value and Api.hooks.close then Api.hooks.close('disabled') end
    return true
end)

exports('isEnabled', function() return Registry.enabled() end)
-- getDisabledBy() -> string[]: the resources whose setEnabled(false) claim keeps targeting off (sorted).
exports('getDisabledBy', function() return Registry.claimants() end)
exports('isOpen', function() return Api.hooks.isOpen ~= nil and Api.hooks.isOpen() == true end)
exports('isMenuOpen', function() return Api.hooks.isMenuOpen ~= nil and Api.hooks.isMenuOpen() == true end)
exports('close', function()
    if Api.hooks.close then Api.hooks.close('closed') end
    return true
end)
exports('getVersion', function() return Api.VERSION end)

-- Library entry (init.lua): spec = { kinds?, models?, entities? }, options with `dynamic` / `select`
-- flags, ref = the library's own id for this registration.
exports('LibAdd', function(spec, options, ref)
    if ref == nil then return nil, 'invalid_ref' end
    spec = type(spec) == 'table' and spec or {}
    return add('lib', { kinds = kindsOf(spec.kinds), models = spec.models, entities = spec.entities }, options, ref)
end)

return Api
