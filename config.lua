Config = {}

-- Language: 'auto' follows each player's game language, or a file in locales/ ('en', 'fr') for everyone.
-- Missing keys fall back to English. This resource only has test and fallback texts of its own (the
-- messages come from the callers): the language mostly decides French spacing, see
-- Config.notify.frenchSpacing. With 'auto' the game reports its language a few seconds after the player
-- is in the world; English rules apply until then.
Config.locale = 'auto'

-- Registers /notifytest to fire sample notifications. Keep it off on a live server.
Config.debug = false

Config.notify = {
	-- The feed scrolls inside an area max lines tall: the newest line is written at its bottom edge and the
	-- older ones move up. anchor 'top-left' | 'top-center' | 'top-right' | 'bottom-left' | 'bottom-center' |
	-- 'bottom-right'; x, y = offsets in dp from that corner (for a top anchor, y is the top of the area; for
	-- a bottom anchor, the distance from the bottom of the screen to the newest line; with a centre anchor
	-- x shifts the column from the middle of the screen).
	-- Default: right column, below opx_hud's money/job strip (top-right, y 36 to 91) and clear of opx_chat
	-- (centre-left). Moving one of them? Keep the three apart.
	position = { anchor = 'top-right', x = 32, y = 140 },
	-- Drawing layer and order inside it. 'menu' (default) draws the feed above the panels of the menu layer:
	-- character selection, creator, menus and dialogs (zIndex 0 to 100 in OPX), so a message sent during
	-- those screens is not hidden behind them. 'hud' puts it back with the HUD, under every menu;
	-- 'modal' is above every menu whatever its zIndex. The feed never takes the keyboard or the mouse.
	layer = 'menu',
	zIndex = 200,      -- -100000..100000; raise it if another resource draws a menu above 200
	width = 460,       -- dp: the column the lines start in; a longer message wraps
	max = 5,           -- lines on screen at once; the oldest leaves first
	rows = 7,          -- text rows on screen at once (a wrapped message counts each row): long messages make
	                   -- the feed grow above its area, by (rows - max) rows at most. 7 keeps the default feed
	                   -- under the HUD strip (top of the feed at y 103); at least `max`
	duration = 5000,   -- default lifetime in ms when the caller gives none (clamped to 1000..60000)
	durations = {      -- per type, when the caller gives none; a type left out uses `duration`
		warning = 7000,
		error = 8000,
	},
	merge = true,      -- an identical live line is refreshed and counted (x2) instead of repeated
	typing = 32,       -- typewriter speed of the newest line, characters per second; 0 = lines appear whole
	typingMax = 800,   -- ms: a long message types faster so it is always complete within this
	clock = true,      -- game time (open77_weather) before each line; left out when that resource is not running
	-- No-break space before : ; ! ? % » and after «, in digit groups (1 250) and before €/$ so a sign never
	-- wraps alone. nil = on when the player's language is French (Config.locale, or the game language with
	-- 'auto'); true / false forces it for everyone.
	frenchSpacing = nil,
}

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
