local Format = {}

local NBSP = '\194\160' -- U+00A0 (Latin-1: every client font has it)

---@param value number
---@param min number
---@param max number
---@return number
function Format.clamp(value, min, max)
	if value < min then return min end
	if value > max then return max end
	return value
end

--- A whole number in min..max from a config or caller value; `fallback` when it is not a number (NaN
--- included). Always an integer, so it is safe for '%d' and for natives.
---@param value any
---@param fallback integer
---@param min integer
---@param max integer
---@return integer
function Format.int(value, fallback, min, max)
	value = tonumber(value)
	if not value or value ~= value then value = fallback end
	return math.floor(Format.clamp(value, min, max))
end

--- Replaces each byte that is not part of a valid UTF-8 sequence with '?' (RmlUi needs valid UTF-8).
---@param value string
---@return string
local function validUtf8(value)
	while true do
		local ok, bad = utf8.len(value)
		if ok then return value end
		value = value:sub(1, bad - 1) .. '?' .. value:sub(bad + 1)
	end
end

--- Glyphs the client fonts lack, swapped for ones they have: … draws nothing, nor do • and the
--- narrow / thin spaces French keyboards and translators produce.
---@param value string
---@return string
local function swapGlyphs(value)
	return (value
		:gsub('\226\128\166', '...')   -- … U+2026
		:gsub('\226\128\162', '\194\183') -- • U+2022 -> ·
		:gsub('\226\128\175', NBSP)    -- U+202F narrow no-break space
		:gsub('\226\128\137', NBSP))   -- U+2009 thin space
end

--- French spacing: the space before : ; ! ? % » and after «, inside digit groups (1 250) and before a
--- currency (250 €$) becomes a no-break space, so the sign never wraps alone onto the next row.
--- Only an existing space is changed; nothing is inserted.
---@param value string
---@return string
function Format.frenchSpacing(value)
	value = value:gsub(' ([:;!%?%%])', NBSP .. '%1')
		:gsub(' \194\187', NBSP .. '\194\187')   -- »
		:gsub('\194\171 ', '\194\171' .. NBSP)   -- «
		:gsub('(%d) \226\130\172', '%1' .. NBSP .. '\226\130\172') -- € (and €$)
		:gsub('(%d) %$', '%1' .. NBSP .. '$')
	for _ = 1, 2 do -- twice: "12 500 000" has overlapping groups
		value = value:gsub('(%d) (%d%d%d)%f[%D]', '%1' .. NBSP .. '%2')
	end
	return value
end

--- Trims, drops control characters, repairs UTF-8, collapses runs of spaces and caps the length of
--- caller text at `maxLength` characters (a cut ends with "...").
--- Control characters and spaces are written as byte sets, not %c / %s: those classes follow the C locale
--- of the game process, and under a Windows code page they also match bytes of UTF-8 letters (Ï, Á) and of
--- the no-break space, which would leave half a character behind.
---@param value any
---@param maxLength integer characters
---@param french boolean? apply Format.frenchSpacing
---@return string
function Format.clean(value, maxLength, french)
	if type(value) == 'number' then value = tostring(value) end
	if type(value) ~= 'string' then return '' end
	value = value:sub(1, maxLength * 4 + 16) -- bound the work below; no character is wider than 4 bytes
	value = validUtf8(swapGlyphs(value:gsub('[\0-\31\127]', ' ')))
	value = value:gsub(' +', ' '):gsub('^ ', ''):gsub(' $', '')
	if french then value = Format.frenchSpacing(value) end
	if utf8.len(value) > maxLength then
		value = value:sub(1, utf8.offset(value, maxLength - 2) - 1):gsub(' $', ''):gsub('\194\160$', '') .. '...'
	end
	return value
end

--- Upper case that keeps accents (string.upper only knows ASCII; RCSS text-transform drops them).
---@param value string
---@return string
function Format.upper(value)
	return (value:gsub(utf8.charpattern, function(ch)
		local ok, cp = pcall(utf8.codepoint, ch)
		if not ok then return ch end
		if cp >= 0x61 and cp <= 0x7A then return string.char(cp - 32) end
		if cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then return utf8.char(cp - 32) end -- à..þ
		if cp == 0xFF then return utf8.char(0x178) end   -- ÿ
		if cp == 0x153 then return utf8.char(0x152) end  -- œ
		return ch
	end))
end

---@param run string two or more identical braces
---@return string
local function spread(run)
	return (run:gsub('.', '%0 ')):sub(1, -2)
end

--- Puts a space between two braces that touch: "{{" -> "{ {", "}}}" -> "} } }". RmlUi scans every text it
--- is given for data-binding brackets: an unbalanced "{{" or "}}" makes it drop the whole fragment (the
--- line would be blank, marker included) and a balanced "{{name}}" is an expression. A single brace is
--- left alone. Applying it twice changes nothing.
---@param value string
---@return string
function Format.braces(value)
	return (value:gsub('{{+', spread):gsub('}}+', spread))
end

local ESCAPES = { ['&'] = '&amp;', ['<'] = '&lt;', ['>'] = '&gt;', ['"'] = '&quot;' }

--- Text safe inside RML markup: entities escaped and no "{{" / "}}" left (Format.braces).
---@param value string
---@return string
function Format.escape(value)
	return Format.braces((value:gsub('[&<>"]', ESCAPES)))
end

return Format
