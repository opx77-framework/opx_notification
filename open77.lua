resource "opx_notification"
version "1.0.0"
open77_version ">=0.0.1"
auto_start true

-- Notifications for OPX//77 (NativeUI, "transmitted feed": one typed line each). Provider of the `notify` slot in opx_core Config.providers.

permissions {
    "ui.vanilla.hud", -- Open77.hud.notify: fallback toast when NativeUI is unavailable
    "session.locale", -- Open77.session.locale: Config.locale = 'auto' follows the game's language
    "local.events",   -- kept as a precaution: the AddEventHandler card checks no permission and official
                      -- resources get onClientResourceStop without it; no native here is known to need it
    "http.request", -- server: Open77.http.get (update check, Config.versionCheck)
}

client_scripts {
    "config.lua",
    "client/main.lua",
}

-- Server side only for the update check (Config.versionCheck).
server_scripts {
    "config.lua",
    "server/version.lua",
}

files {
    "client/modules/*.lua",
    "ui/*.rml",
    "ui/*.rcss",
    "locales/*.json",
}
