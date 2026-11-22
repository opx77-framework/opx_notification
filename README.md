# opx_notification

Notifications as a feed of single typed lines at the top right: a coloured marker (info, success, warning,
error), the game time, then the text. Identical lines are counted (`x2`) instead of repeated.

## Install
- Needs: nothing (calls arrive through `opx_core`). Load it after `opx_core`. `open77_weather` is optional (game time before each line).
- No database.
- Provider of the `notify` slot: a replacement implements the exports in `types.lua` and is set in opx_core `Config.providers.notify`.

## In game
- Nothing to press: lines appear and fade on their own.
- `/notifytest` shows samples, only with `Config.debug = true`.

## Config
`config.lua`: `locale`, `notify.position`, `notify.max` (lines on screen), `notify.duration` / `notify.durations`.
Everything else is commented in the file.

## For developers
- Send through opx_core: `OPX.Notify(message, type?, duration?, title?, options?)` (client) or `exports.opx_core:Notify(source, ...)` (server).
- `Notify(message, type?, duration?, title?, options?)` → `true`, or `false, reason`.
- `options = { id, persist }`: a later call with the same `id` rewrites the line; `persist` keeps it until dismissed.
- `Dismiss(id)` → `true`, or `false, reason`. `Clear()` → number of lines removed.
- Full contract: `types.lua`.
