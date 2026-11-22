--- Player-facing text from locales/<lang>.json, English as the fallback.
--- Config.locale = 'auto' follows the game's language (Open77.session.locale, permission session.locale).
--- The client only reports it a few seconds after the first gameplay frame: until then English is used and
--- Locale.refresh() asks again.
local Locale = {}

local strings, fallback = {}, {}
local lang = 'en'       -- two-letter code of the language in use ('en' until 'auto' is resolved)
local resolved = false  -- false while 'auto' still waits for the game language

---@param name string file name without its extension
---@return table?
local function read(name)
	if not name:match('^[%w_%-]+$') then return nil end
	local text = Open77.resource.readFile(('locales/%s.json'):format(name))
	if type(text) ~= 'string' then return nil end
	local ok, data = pcall(Open77.json.decode, text)
	return ok and type(data) == 'table' and data or nil
end

--- The language to use and whether that answer is final.
---@return string code two letters, lower case
---@return boolean known false while 'auto' waits for the game language
---@return string? file locale file asked for by name in the config, when it is not just the code
---@return string? refusal why 'auto' cannot work on this client (final)
local function language()
	local wanted = Config.locale
	if wanted ~= nil and wanted ~= 'auto' then
		wanted = tostring(wanted)
		local code = wanted:sub(1, 2):lower()
		return code:match('^%l%l$') and code or 'en', true, wanted
	end
	if type(Open77.session) ~= 'table' or type(Open77.session.locale) ~= 'function' then return 'en', true end
	local ok, info, reason = pcall(Open77.session.locale)
	local code = ok and type(info) == 'table' and info.code or nil
	if type(code) == 'string' and code:match('^%a%a') then return code:sub(1, 2):lower(), true end
	-- A missing permission or a host without a game never changes: English for good. Anything else
	-- ('locale_not_reported') means "not yet": the question is asked again later.
	local why = tostring(ok and reason or info)
	if why:find('permission_denied', 1, true) or why:find('game_unavailable', 1, true) then
		return 'en', true, nil, why
	end
	return 'en', false
end

--- Asks the language again while 'auto' is unresolved and loads its file once it is known.
---@return boolean known true once the language is final
function Locale.refresh()
	if resolved then return true end
	local code, known, file, refusal = language()
	if not known then return false end
	lang, resolved = code, true
	strings = (file and file ~= code and read(file)) or (code ~= 'en' and read(code)) or fallback
	if refusal then
		Open77.log.warn(("[opx_notification] Config.locale = 'auto' cannot read the game language (%s): English is used")
			:format(refusal))
	end
	return true
end

--- Loads English and makes a first attempt at the configured language.
---@return boolean known false while 'auto' still waits for the game language (call Locale.refresh later)
function Locale.load()
	fallback = read('en') or {}
	strings, lang, resolved = fallback, 'en', false
	return Locale.refresh()
end

---@return boolean
function Locale.resolved()
	return resolved
end

--- Two-letter code of the player's language: Config.locale, or the game language once it is known.
--- It can be a language without a file in locales/ (the texts are then in English).
---@return string
function Locale.lang()
	return lang
end

--- Translated string for `key`, formatted with the extra arguments. Unknown keys return the key.
---@param key string
---@return string
function Locale.t(key, ...)
	local text = strings[key] or fallback[key] or tostring(key)
	if select('#', ...) == 0 then return text end
	local ok, formatted = pcall(string.format, text, ...)
	return ok and formatted or text
end

return Locale
