-- Player-facing text from locales/<lang>.json, English as the fallback.

local Locale = {}

local strings, fallback = {}, nil
local loaded = nil -- the language `strings` holds

-- True once the language is known (Config.locale set, or the game reported its own). With 'auto' the game
-- only reports it a few seconds after the first gameplay frame: until then the texts are English and the
-- service keeps asking (client/main.lua).
Locale.ready = false

local function read(lang)
    local text = Open77.resource.readFile(('locales/%s.json'):format(lang))
    if not text then return nil end
    local ok, data = pcall(Open77.json.decode, text)
    return ok and type(data) == 'table' and data or nil
end

local function language()
    if Config.locale ~= 'auto' then return tostring(Config.locale or 'en'), true end
    -- a client without the native never reports one: nothing to wait for
    if type(Open77.session) ~= 'table' or type(Open77.session.locale) ~= 'function' then return 'en', true end
    local ok, info = pcall(Open77.session.locale)
    local code = ok and type(info) == 'table' and info.code or nil
    if type(code) ~= 'string' then return 'en', false end -- not reported yet (before the world is ready)
    return code:sub(1, 2):lower(), true
end

---Loads the texts of the current language (the files are read again only when it changed).
---@return boolean known the language is resolved (false: English for now, ask again later)
function Locale.load()
    local lang, known = language()
    if not fallback then fallback = read('en') or {} end
    if lang ~= loaded then
        strings = (lang ~= 'en' and read(lang)) or fallback
        loaded = lang
    end
    Locale.ready = known
    return known
end

---@param key string
---@return string
function Locale.t(key, ...)
    local text = strings[key] or (fallback and fallback[key]) or key
    if select('#', ...) == 0 then return text end
    local ok, formatted = pcall(string.format, text, ...)
    return ok and formatted or text
end

--- Upper case for display. RmlUi's `text-transform: uppercase` only maps ASCII ("Véhicule" -> "VéHICULE"),
--- so caps are made here: ASCII, Latin-1 accented letters (à-þ), ÿ and œ.
---@param text string
---@return string
function Locale.upper(text)
    if type(text) ~= 'string' then return '' end
    text = text:gsub('\xC3([\xA0-\xBE])', function(c)
        if c == '\xB7' then return nil end -- the division sign
        return '\xC3' .. string.char(c:byte() - 0x20)
    end)
    text = text:gsub('\xC3\xBF', '\xC5\xB8'):gsub('\xC5\x93', '\xC5\x92')
    return (text:upper())
end

return Locale
