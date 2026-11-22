---@meta

---@alias OpxNotifyType 'info' | 'success' | 'warning' | 'error'

--- Optional 5th argument of Notify, specific to opx_notification (a replacement provider may ignore it).
---@class OpxNotifyOptions
---@field id? string|number up to 160 characters: a later Notify with the same id rewrites that line in place (text, type, title, lifetime) instead of adding one; Dismiss(id) removes it
---@field persist? boolean the line has no lifetime: it stays until Dismiss(id), Clear(), a same-id update without persist, or the feed pushes it out (persistent lines leave last)

-- Ownership: a line shown with an id or persist belongs to the resource (and VM generation) that called Notify;
-- only it finds the line again by id, two resources may reuse an id, and its lines are dismissed when it stops or
-- reloads. Lines sent through opx_core are owned by opx_core (ids prefixed "<resource>:<id>" by opx_core).
-- Clear() removes every line, whoever owns it. Without NativeUI the game's own toast is shown ("TITLE: message")
-- and options are ignored. Text is cleaned (control characters, invalid UTF-8, missing glyphs); French spacing
-- uses no-break spaces (Config.notify.frenchSpacing).
--
-- Provider contract (Config.providers.notify in opx_core): required client export Notify(message, type?, duration?,
-- title?) -> boolean. message is non-empty (server messages arrive capped at 512 bytes); treat an unknown type as
-- 'info'; duration is nil (apply your default) or ms (server path clamps 500..60000, clamp it yourself); title may
-- be nil or '' (= none). It must not error, must return quickly (called async), and must show even while the HUD is
-- hidden. Optional: the 5th options argument, Dismiss(id), Clear() (callers guard them). No server side needed.

exports.opx_notification = {}

--- Shows a notification line. Identical live lines are merged (x2). Duration is clamped to 1000..60000 ms;
--- without one, Config.notify.durations[type] or Config.notify.duration applies.
--- Prefer opx_core (`OPX.Notify`, client export `Notify`, server `Notify(source, ...)`): it reaches whichever
--- resource fills the `notify` slot. Call this export by name only for the `options` extension.
---@param message string up to 300 characters (longer is cut with "...")
---@param type? OpxNotifyType default 'info'
---@param duration? integer ms
---@param title? string up to 64 characters, shown in caps before the message
---@param options? OpxNotifyOptions
---@return boolean shown
---@return string? reason 'invalid_message' (empty after trimming) | 'unavailable' (no NativeUI and the game toast failed)
function exports.opx_notification:Notify(message, type, duration, title, options) end

--- Removes the line shown with options.id = id (fades out).
---@param id string|number
---@return boolean ok
---@return string? reason 'invalid_id' | 'not_found'
function exports.opx_notification:Dismiss(id) end

--- Removes every line on screen at once, persistent ones included.
---@return integer removed number of lines that were on screen
function exports.opx_notification:Clear() end
