if type(Config.notify) ~= 'table' then Config.notify = {} end

local RESOURCE = GetCurrentResourceName()

local Locale = assert(require('client.modules.locale'))
-- Config.locale = 'auto': the game reports its language a few seconds after the first gameplay frame (well
-- after this file ran on a fresh join). English is used until then; the language is asked again here, with
-- no deadline, and at every notification (French spacing follows it).
if not Locale.load() then
	CreateThread(function()
		local pause = 500
		while not Locale.refresh() do
			Wait(pause)
			if pause < 5000 then pause = pause + 500 end
		end
	end)
end

local Notify = assert(require('client.modules.notify'))
Notify.create()

--- The resource calling one of the exports below, and its generation: a line shown with an id or `persist`
--- belongs to it. nil for a call made by this resource itself (/notifytest).
---@return string? owner
---@return integer? generation
local function caller()
	local name = GetInvokingResource()
	if type(name) ~= 'string' or name == '' or name == RESOURCE then return nil, nil end
	return name, GetInvokingResourceGeneration()
end

-- Contract (docs/ARCHITECTURE.md › Replacing a resource › notify): Notify(message, type?, duration?, title?,
-- options?) with options = { id?, persist? } (README › Client exports). None of the three exports yields:
-- opx_core may call them synchronously.
exports('Notify', function(message, kind, duration, title, options)
	local owner, generation = caller()
	return Notify.show(message, kind, duration, title, options, owner, generation)
end)

-- Removes the line the calling resource showed with options.id = id: true, or false + 'invalid_id' | 'not_found'.
exports('Dismiss', function(id)
	local owner = caller()
	return Notify.dismiss(id, owner)
end)

-- Removes every line on screen (persistent ones included, whoever showed them); returns how many left.
exports('Clear', function()
	return Notify.clear()
end)

-- A resource that stops or reloads can no longer update or dismiss the lines it showed with an id or
-- `persist`: they are dismissed (README › Who owns a line).
AddEventHandler('onClientResourceStop', function(name)
	if name ~= RESOURCE then Notify.sweep() end
end)

if Config.debug then
	-- /notifytest: one line of each type (each with its own drawn marker), a merged duplicate (x2), a long
	-- line, braces in a title and in a typed message, then a persistent line updated in place (options.id)
	-- and closed. Spaced so each types in.
	RegisterCommand('notifytest', function()
		local samples = {
			{ Locale.t('test.info'), 'info', nil, Locale.t('test.title') },
			{ Locale.t('test.success'), 'success' },
			{ Locale.t('test.warning'), 'warning' },
			{ Locale.t('test.error'), 'error' },
			{ Locale.t('test.success'), 'success' },
			{ Locale.t('test.long'), 'info', 9000 },
			{ Locale.t('test.braces'), 'info', nil, '{{Sync}}' },
			{ Locale.t('test.progress', 0), 'info', nil, nil, { id = 'notifytest', persist = true } },
			{ Locale.t('test.progress', 60), 'info', nil, nil, { id = 'notifytest', persist = true } },
			{ Locale.t('test.done'), 'success', 4000, nil, { id = 'notifytest' } },
		}
		for i, sample in ipairs(samples) do
			SetTimeout((i - 1) * 900, function()
				Notify.show(sample[1], sample[2], sample[3], sample[4], sample[5])
			end)
		end
	end, false)
end
