--- Turns a config position ({ anchor = 'top-right', x, y }) into the RCSS of the feed area.
local Format = require('client.modules.format')

local Layout = {}

local MAX_OFFSET = 10000 -- dp: keeps a wild config value printable with '%d'

---@param position table?
---@return 'top'|'bottom' vertical
---@return 'left'|'center'|'right' horizontal
---@return integer x
---@return integer y
function Layout.parse(position)
	position = type(position) == 'table' and position or {}
	local vertical, horizontal = tostring(position.anchor or ''):match('^(%a+)%-(%a+)$')
	if vertical ~= 'top' and vertical ~= 'bottom' then vertical = 'top' end
	if horizontal ~= 'left' and horizontal ~= 'center' and horizontal ~= 'right' then horizontal = 'right' end
	return vertical, horizontal,
		Format.int(position.x, 0, -MAX_OFFSET, MAX_OFFSET), Format.int(position.y, 0, -MAX_OFFSET, MAX_OFFSET)
end

--- The area is width x height dp at the anchor; #lines sits on its bottom edge and grows up.
--- Widths are explicit: % inside an absolute box would resolve against the screen.
--- Both edges of each axis are always written. RmlUi places an absolute box by `top` when `top` and `bottom`
--- are both set (and by `left` over `right`), so the edge that is not used has to be put back to `auto`
--- over the default rule of notify.rcss: without it a bottom anchor stays at the default top.
---@param position table?
---@param width integer dp
---@param height integer dp
---@return string
function Layout.rules(position, width, height)
	local vertical, horizontal, x, y = Layout.parse(position)
	local anchor = { ('width: %ddp; height: %ddp;'):format(width, height) }
	if vertical == 'bottom' then
		anchor[#anchor + 1] = ('top: auto; bottom: %ddp;'):format(y)
	else
		anchor[#anchor + 1] = ('top: %ddp; bottom: auto;'):format(y)
	end
	if horizontal == 'center' then
		anchor[#anchor + 1] = ('left: 50%%; right: auto; margin-left: %ddp;'):format(x - width // 2)
	elseif horizontal == 'left' then
		anchor[#anchor + 1] = ('left: %ddp; right: auto; margin-left: 0dp;'):format(x)
	else
		anchor[#anchor + 1] = ('left: auto; right: %ddp; margin-left: 0dp;'):format(x)
	end
	return ('#notify-anchor { %s } #lines { width: %ddp; } .strip { max-width: %ddp; }')
		:format(table.concat(anchor, ' '), width, width)
end

-- Average advances in dp, measured loosely on the faces of notify.rcss (a slight over-estimate is safer:
-- it only makes an old line leave a little early).
local CHAR_DP = 7.4        -- Rajdhani 17dp, mixed case
local TITLE_CHAR_DP = 9.5  -- Chakra Petch bold 12dp caps, 0.12em tracking
local PREFIX_DP = 19 + 28  -- marker box + room for the x2 counter
local TIME_DP = 46         -- "21:04" in Roboto Mono 12dp + gap
local SEP_DP = 17          -- " · " after the title
local PADDING_DP = 22      -- .strip horizontal padding

--- Rough number of text rows a line takes once wrapped in a column `width` dp wide. There is no layout
--- read-back from Lua, so this estimate keeps the feed inside its area when long messages wrap.
---@param chars integer message length in characters
---@param titleChars integer title length in characters (0 = no title)
---@param hasTime boolean
---@param width integer dp
---@return integer
function Layout.rows(chars, titleChars, hasTime, width)
	local used = PREFIX_DP + chars * CHAR_DP
	if hasTime then used = used + TIME_DP end
	if titleChars > 0 then used = used + titleChars * TITLE_CHAR_DP + SEP_DP end
	return math.max(1, math.ceil(used / math.max(80, width - PADDING_DP)))
end

return Layout
