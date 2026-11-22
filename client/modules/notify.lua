--- "Transmitted feed": each notification is one typed line (drawn marker, game time, TITLE · text).
--- Own document, so it survives SetVisible(false) and character selection.
local Format = require('client.modules.format')
local Layout = require('client.modules.layout')
local Locale = require('client.modules.locale')

local Notify = {}

local KINDS = { info = true, success = true, warning = true, error = true }
-- One drawn shape per type on a 10 x 10 grid (dot, tick, triangle, cross), so the type is not carried by
-- colour alone. The client fonts have no glyph for them: they are <path> elements, filled or stroked by
-- notify.rcss.
local MARKS = {
	info = 'M2.6 5 a2.4 2.4 0 1 0 4.8 0 a2.4 2.4 0 1 0 -4.8 0 Z',
	success = 'M1.7 5.4 L4.1 7.8 L8.4 2.5',
	warning = 'M5 1.5 L8.9 8.3 H1.1 Z',
	error = 'M2.2 2.2 L7.8 7.8 M7.8 2.2 L2.2 7.8',
}
local LAYERS = { hud = true, menu = true, modal = true }
local MIN_DURATION, MAX_DURATION = 1000, 60000
-- Ids belong to the resource that called the export. Every line forwarded by opx_core is owned by opx_core,
-- which keeps its callers apart by prefixing the id ("<resource>:<id>"): room for both.
local MAX_MESSAGE, MAX_TITLE, MAX_ID = 300, 64, 160
local LINE_DP = 26     -- height reserved per line: the feed area is `max` lines tall
local TICK_MS = 40     -- shortest gap between two typed updates (at most ~20 per line)
local WATCH_MS = 2000  -- gap between two checks of the resources that own a line on screen

local ui = nil
local width = 460      -- dp, Config.notify.width once created
-- As drawn, oldest first:
-- { sel, key, id, owner, generation, persist, rows, count, opacity, timer, typer, gone }
local live = {}
local serial = 0
local reduced = false  -- nui.reducedmotion, as measured by probe()
local probing = nil    -- start time of the probe in flight
local watcher = nil    -- timer of the owner check, armed only while an owned line is on screen

---@return integer
local function maxLines()
	return Format.int(Config.notify.max, 5, 1, 20)
end

--- Text rows the feed may use: a wrapped message counts once per row.
---@return integer
local function maxRows()
	return math.max(maxLines(), Format.int(Config.notify.rows, maxLines() + 2, 1, 60))
end

--- Lifetime when the caller gives none: Config.notify.durations[kind], else Config.notify.duration.
---@param kind string
---@return number
local function defaultDuration(kind)
	local per = type(Config.notify.durations) == 'table' and tonumber(Config.notify.durations[kind]) or nil
	return per or tonumber(Config.notify.duration) or 5000
end

--- French spacing rules follow the player's language unless Config.notify.frenchSpacing says otherwise.
---@return boolean
local function french()
	local setting = Config.notify.frenchSpacing
	if setting == nil then return Locale.lang() == 'fr' end
	return setting == true
end

--- Game time from open77_weather (no permission needed); nil when it is not running or not synced yet.
--- The client sandbox has no `os`, so there is no real-time fallback: the time is left out.
---@return string?
local function clock()
	if Config.notify.clock == false then return nil end
	local ok, state = pcall(Open77.exports.callSync, 'open77_weather', 'getState')
	if ok and type(state) == 'table' and tonumber(state.hour) and tonumber(state.minute) then
		return ('%02d:%02d'):format(math.floor(state.hour), math.floor(state.minute))
	end
	return nil
end

--- nui.reducedmotion has no Lua read, but it makes movement land at once: a 300 ms slide of an empty
--- element that ends within 150 ms means it is on. One transform tween per notification, no layout.
--- The result also drives the `calm` class of #root: a stylesheet loop (the caret) is not stopped by the
--- platform setting.
local function probe()
	local now = Open77.time.monotonic()
	if probing and now - probing < 2 then return end
	probing = now
	ui:animate('#motion-probe', { from = { x = 0 }, to = { x = 8 }, duration = 0.3, easing = 'linear' }, function()
		if probing ~= now then return end
		probing = nil
		local measured = Open77.time.monotonic() - now < 0.15
		if measured ~= reduced then
			reduced = measured
			ui:class('#root', 'calm', reduced)
		end
	end)
end

--- Older lines fade by age: 1, 0.8, 0.64... down to 0.32.
local function fade()
	local n = #live
	for i = 1, n do
		local entry = live[i]
		local target = math.max(0.32, 0.8 ^ (n - i))
		if math.abs(entry.opacity - target) > 0.01 then
			entry.opacity = target
			ui:animate(entry.sel, { to = { opacity = target }, duration = 0.35, easing = 'ease-out' })
		end
	end
end

---@param entry table
local function stopTimers(entry)
	if entry.timer then ClearTimeout(entry.timer); entry.timer = nil end
	if entry.typer then ClearTimeout(entry.typer); entry.typer = nil end
end

---@param entry table
---@param fast boolean? pushed out by a newer line or cleared, rather than expired
local function dismiss(entry, fast)
	for i = 1, #live do
		if live[i] == entry then
			table.remove(live, i)
			entry.gone = true
			stopTimers(entry)
			ui:remove(entry.sel, { to = { opacity = 0 }, duration = fast and 0.2 or 0.45, easing = 'ease-in' })
			fade()
			return
		end
	end
end

--- Keeps the feed within `max` lines and `rows` text rows. `keep` (the line just written) never leaves;
--- among the others the oldest line that is not persistent goes first, then the oldest persistent one.
---@param keep table
local function trim(keep)
	while #live > 1 do
		local rows = 0
		for i = 1, #live do rows = rows + live[i].rows end
		if #live <= maxLines() and rows <= maxRows() then return end
		local victim = nil
		for i = 1, #live do
			if live[i] ~= keep and not live[i].persist then victim = live[i]; break end
		end
		if not victim then
			for i = 1, #live do
				if live[i] ~= keep then victim = live[i]; break end
			end
		end
		if not victim then return end
		dismiss(victim, true)
	end
end

--- Starts (or restarts) the lifetime; a persistent line has none.
---@param entry table
---@param duration integer ms
local function arm(entry, duration)
	if entry.timer then ClearTimeout(entry.timer); entry.timer = nil end
	if entry.persist then return end
	entry.timer = SetTimeout(duration, function()
		entry.timer = nil
		dismiss(entry)
	end)
end

--- The live plain line with this merge key.
---@param key string
---@return table?
local function findKey(key)
	for i = 1, #live do
		if live[i].key == key then return live[i] end
	end
	return nil
end

--- The live line a resource showed with this id: ids belong to the resource that called (nil = this one).
---@param owner string?
---@param id string
---@return table?
local function findId(owner, id)
	for i = 1, #live do
		if live[i].id == id and live[i].owner == owner then return live[i] end
	end
	return nil
end

-- Ownership ---------------------------------------------------------------------------------------
-- A line shown with an id or `persist` can only be updated or removed by the resource that showed it.
-- When that resource stops or reloads, nobody is left to do it: the line is dismissed here.

--- True for a line that waits on its owner: shown by another resource with an id or `persist`.
---@param entry table
---@return boolean
local function owned(entry)
	return entry.owner ~= nil and entry.generation ~= nil and (entry.id ~= nil or entry.persist == true)
end

--- True while the owner still runs the generation that showed the line. Compared by generation, never by
--- name alone: on a reload the new VM may already have shown its line again when the stop is announced.
--- A check that fails to run counts as alive (a line is never dropped on a doubt).
---@param entry table
---@return boolean
local function ownerAlive(entry)
	local ok, alive = pcall(function()
		local state = GetResourceState(entry.owner)
		if state ~= 'running' and state ~= 'starting' then return false end
		return Open77.resource.generation(entry.owner) == entry.generation
	end)
	return not ok or alive == true
end

--- Dismisses the owned lines whose resource stopped or was reloaded since.
local function sweep()
	for i = #live, 1, -1 do
		local entry = live[i]
		if entry and owned(entry) and not ownerAlive(entry) then dismiss(entry) end
	end
end

--- Keeps checking the owners while an owned line is on screen (one timer, a few comparisons): the stop
--- event of another resource is the fast path, this is the one that does not depend on its delivery or
--- on the order of events. Nothing runs once the last owned line left.
local function watch()
	if watcher then return end
	for i = 1, #live do
		if owned(live[i]) then
			watcher = SetTimeout(WATCH_MS, function()
				watcher = nil
				sweep()
				watch()
			end)
			return
		end
	end
end

--- Typewriter: a few timed ui:text updates of the message span, no per-frame loop. Speed is
--- Config.notify.typing chars/s, capped at typingMax ms; the caret (class .typing) leaves at the end.
---@param entry table
---@param message string
---@param length integer characters
local function typeIn(entry, message, length)
	local speed = tonumber(Config.notify.typing) or 0
	local total = math.min(length / speed * 1000, tonumber(Config.notify.typingMax) or 800)
	local steps = math.max(1, math.min(length, math.floor(total / TICK_MS)))
	local interval = math.max(1, math.floor(total / steps))
	local step = 0
	local function tick()
		entry.typer = nil
		if entry.gone then return end
		step = step + 1
		local shown = math.ceil(length * step / steps)
		ui:text(entry.sel .. ' .msg', message:sub(1, utf8.offset(message, shown + 1) - 1))
		if step < steps then
			entry.typer = SetTimeout(interval, tick)
		else
			ui:class(entry.sel, 'typing', false)
		end
	end
	entry.typer = SetTimeout(interval, tick)
end

---@param kind string
---@param time string?
---@param title string?
---@param message string? nil while it is typed in
---@return string
local function markup(kind, time, title, message)
	local parts = {
		('<div class="strip"><div class="mark"><path view-box="0 0 10 10" d="%s"/></div>'):format(MARKS[kind]),
	}
	if time then parts[#parts + 1] = ('<span class="time">%s</span>'):format(time) end
	if title then
		parts[#parts + 1] = ('<span class="title">%s</span><span class="sep">·</span>'):format(Format.escape(Format.upper(title)))
	end
	parts[#parts + 1] = ('<span class="msg">%s</span><div class="caret"></div><span class="count"></span></div>')
		:format(message and Format.escape(message) or '')
	return table.concat(parts)
end

---@return boolean ok
function Notify.create()
	if type(Open77.ui) ~= 'table' or type(Open77.ui.create) ~= 'function' then return false end
	-- Above the menu-layer panels by default (character selection, creator, menus), where a HUD-layer feed
	-- is drawn behind them. The document never takes the input.
	local layer = LAYERS[Config.notify.layer] and Config.notify.layer or 'menu'
	local zIndex = Format.int(Config.notify.zIndex, 200, -100000, 100000)
	local doc, reason = Open77.ui.create({ document = 'ui/notify.rml', layer = layer, zIndex = zIndex })
	if not doc and layer ~= 'hud' then
		-- never lose the feed over a layer setting: back to the HUD layer
		Open77.log.warn(('[opx_notification] ui/notify.rml refused on layer %s (%s): trying hud'):format(layer, tostring(reason)))
		doc, reason = Open77.ui.create({ document = 'ui/notify.rml', layer = 'hud', zIndex = 50 })
	end
	if not doc then
		Open77.log.error('[opx_notification] cannot create ui/notify.rml: ' .. tostring(reason))
		return false
	end
	ui = doc
	ui:onEvent('error', function(name, detail)
		Open77.log.warn(('[opx_notification] %s: %s'):format(tostring(name), tostring(detail and detail.message)))
	end)

	width = Format.int(Config.notify.width, 460, 160, 1600)
	ui:stylesheet('layout', Layout.rules(Config.notify.position, width, maxLines() * LINE_DP))
	ui:layout('#lines', { preset = 'growth' })  -- the older lines slide up when one is added or leaves
	probe()
	return true
end

--- An id as the key of a line: a string, or a number written without a fraction when it has none
--- (7 and 7.0 are the same id). '' when it is not usable.
---@param value any
---@return string
local function cleanId(value)
	if type(value) == 'number' then
		if value ~= value or value == math.huge or value == -math.huge then return '' end
		value = tostring(math.tointeger(value) or value)
	end
	return Format.clean(value, MAX_ID)
end

--- Options of the 5th Notify argument: { id?: string|number, persist?: boolean }.
---@param options any
---@return string? id
---@return boolean persist
local function readOptions(options)
	if type(options) ~= 'table' then return nil, false end
	local id = cleanId(options.id)
	return id ~= '' and id or nil, options.persist == true
end

--- Rewrites a live line in place (same owner, same id): new text, type and lifetime, no typing, the marker
--- pulses. It keeps its place in the feed and its key, so it never merges with a plain line.
---@param entry table
local function update(entry, kind, title, message, duration, persist, generation)
	stopTimers(entry)
	local time = clock()
	entry.count, entry.persist, entry.generation = 1, persist, generation
	entry.rows = Layout.rows(utf8.len(message) or #message, title and utf8.len(title) or 0, time ~= nil, width)
	ui:setClasses(entry.sel, 'line kind-' .. kind)
	ui:rml(entry.sel, markup(kind, time, title, message))
	ui:animate(entry.sel .. ' .mark', { from = { opacity = 0.2 }, to = { opacity = 1 }, duration = 0.3, easing = 'ease-out' })
	arm(entry, duration)
	trim(entry)
end

--- Shows a notification. Without NativeUI it falls back to the vanilla side popup.
---@param message any
---@param kind any 'info'|'success'|'warning'|'error'
---@param duration any ms
---@param title any
---@param options any { id?: string|number, persist?: boolean }
---@param owner string? resource that called the export (nil for this resource)
---@param generation integer? generation of that resource at the time of the call
---@return boolean shown
---@return string? reason 'invalid_message' | 'unavailable'
function Notify.show(message, kind, duration, title, options, owner, generation)
	if not Locale.resolved() then Locale.refresh() end
	local fr = french()
	message = Format.clean(message, MAX_MESSAGE, fr)
	if message == '' then return false, 'invalid_message' end
	kind = KINDS[kind] and kind or 'info'
	title = Format.clean(title, MAX_TITLE, fr)
	if title == '' then title = nil end
	duration = Format.int(tonumber(duration) or defaultDuration(kind), 5000, MIN_DURATION, MAX_DURATION)
	local id, persist = readOptions(options)

	if not ui then
		local text = title and Locale.t('fallback.titled', title, message) or message
		local ok, shown = pcall(function() return Open77.hud.notify(text) end)
		if ok and shown == true then return true end
		return false, 'unavailable'
	end

	-- Done once, here: the typed text (ui:text) and the markup (ui:rml) then show the same thing.
	message = Format.braces(message)
	if owner ~= nil and generation == nil then
		local ok, current = pcall(Open77.resource.generation, owner)
		generation = ok and current or nil
	end

	local same = id and findId(owner, id)
	if same then
		update(same, kind, title, message, duration, persist, generation)
		watch()
		return true
	end

	local key = table.concat({ kind, title or '', message }, '\1')
	same = not id and Config.notify.merge and findKey(key)
	if same then
		same.count = same.count + 1
		ui:text(same.sel .. ' .count', 'x' .. same.count)
		ui:class(same.sel, 'merged', true)
		ui:animate(same.sel .. ' .count', { from = { opacity = 0 }, to = { opacity = 1 }, preset = 'snappy' })
		arm(same, duration)
		return true
	end

	local length = utf8.len(message) or #message
	local typed = not reduced and (tonumber(Config.notify.typing) or 0) > 0 and length > 1
	local time = clock()

	serial = serial + 1
	local domId = 'opx-line-' .. serial
	local entry = {
		sel = '#' .. domId, key = id and ('\2' .. id) or key, id = id, owner = owner, generation = generation,
		persist = persist, count = 1, opacity = 1,
		rows = Layout.rows(length, title and utf8.len(title) or 0, time ~= nil, width),
	}
	ui:create('#lines', {
		id = domId,
		class = 'line kind-' .. kind .. (typed and ' typing' or ''),
		rml = markup(kind, time, title, not typed and message or nil),
		enter = { from = { opacity = 0 }, to = { opacity = 1 }, duration = 0.15, easing = 'ease-out' },
	})
	live[#live + 1] = entry
	arm(entry, duration)
	if typed then typeIn(entry, message, length) end

	trim(entry)
	fade()
	probe()
	watch()
	return true
end

--- Removes the live line the calling resource showed with options.id = id.
---@param id any
---@param owner string? resource that called the export (nil for this resource)
---@return boolean ok
---@return string? reason 'invalid_id' | 'not_found'
function Notify.dismiss(id, owner)
	id = cleanId(id)
	if id == '' then return false, 'invalid_id' end
	local entry = ui and findId(owner, id)
	if not entry then return false, 'not_found' end
	dismiss(entry)
	return true
end

--- Removes every line at once, persistent ones included, whoever showed them.
---@return integer removed
function Notify.clear()
	local count = #live
	for i = #live, 1, -1 do dismiss(live[i], true) end
	return count
end

--- Dismisses the lines (id or persistent) of resources that stopped or were reloaded. Called when another
--- resource stops; the same check runs on a timer while such a line is on screen.
function Notify.sweep()
	if ui then sweep() end
end

--- Number of lines on screen.
---@return integer
function Notify.count()
	return #live
end

return Notify
