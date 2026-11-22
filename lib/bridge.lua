-- Calls from the caller's VM to the opx_target service (exports run inline, values are copied).

local Bridge = { SERVICE = 'opx_target' }

---@return boolean called false when the service could not be reached (not running yet, stopping...)
---@return any result, any reason
function Bridge.call(name, ...)
    local ok, a, b = pcall(Open77.exports.callSync, Bridge.SERVICE, name, ...)
    if not ok then return false, nil, tostring(a) end
    return true, a, b
end

return Bridge
