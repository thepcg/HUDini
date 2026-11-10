--[[--------------------------------------------------------------------------
	HUDini - Modules (TICK-0009)

	A module is one feature that can be switched off: the feed, the XP bar,
	the window mover. While it is off it has no events, no tickers and no
	timers, and a module that was never on made none of its frames (D-002).

		local M = ns.NewModule("feed", {
			label    = "Feed",              -- its name in /hud debug modules
			setting  = "showFeed",          -- on while HUDiniDB.showFeed is
			-- isOn  = function() ... end,  -- or a test of its own
			defaults = { showFeed = true }, -- merged into ns.defaults
		})

		M:On("PLAYER_MONEY", fn)          -- fn(event, ...) while the module is on
		M:On({ "A", "B" }, fn)            -- one handler for several events
		M:Every(5, fn)                    -- a ticker; only while on
		M:After(0.5, fn)                  -- a one-shot timer; dropped when it goes off
		M:CreateFrame(type, name, parent) -- a frame, counted by /hud debug modules
		M.OnEnable, M.OnDisable           -- called as M:OnEnable(), M:OnDisable()

	Events are listed at load and registered when the module goes on, on a
	frame of its own made the first time. Going off unregisters them and
	cancels every ticker and timer. A frame cannot be destroyed, so OnDisable
	hides what OnEnable showed.

	Modules go on at PLAYER_LOGIN, after the saved settings and their
	migrations are in, and follow their setting after that: HUDini:Apply
	calls ns.UpdateModules() first. A module that goes on after the first
	loading screen gets its PLAYER_ENTERING_WORLD handler called at once,
	with a 4th argument true ("late"), so its start-up runs. A late start
	runs inside HUDini:Apply, which lays the HUD out right after.

	A setting key belongs to one module only: two defaults for one key is an
	error at load.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local modules, byName = {}, {}
local loggedIn, inWorld = false, false

local Module = {}
Module.__index = Module

-- Run fn, and report an error without stopping the other modules.
local function Call(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) else error(err, 0) end
	end
end

function ns.NewModule(name, spec)
	spec = spec or {}
	if byName[name] then error("HUDini: two modules named " .. name, 2) end -- locale: skip an error for addon authors
	ns.defaults = ns.defaults or {}
	for k, v in pairs(spec.defaults or {}) do
		if ns.defaults[k] ~= nil then
			error(("HUDini: module %s sets a default for %s, which another part sets"):format(name, k), 2) -- locale: skip an error for addon authors
		end
		ns.defaults[k] = v
	end
	local M = setmetatable({
		name = name, label = spec.label or name, setting = spec.setting, isOn = spec.isOn,
		enabled = false, gen = 0,
		handlers = {}, tickers = {}, timers = {}, frames = {},
	}, Module)
	modules[#modules + 1] = M
	byName[name] = M
	return M
end

function ns.GetModule(name) return byName[name] end

local function Dispatch(frame, event, ...)
	local M = frame.module
	local fn = M.enabled and M.handlers[event]
	if fn then fn(event, ...) end
end

function Module:On(events, fn)
	if type(events) == "string" then events = { events } end
	for _, event in ipairs(events) do
		self.handlers[event] = fn
		-- Listed while on: register it now.
		if self.enabled and self.frame then pcall(self.frame.RegisterEvent, self.frame, event) end
	end
end

function Module:Every(seconds, fn)
	if not self.enabled then return nil end
	local M = self
	local t = C_Timer.NewTicker(seconds, function()
		if M.enabled then fn() end
	end)
	self.tickers[#self.tickers + 1] = t
	return t
end

function Module:After(seconds, fn)
	if not self.enabled then return nil end
	local M, gen = self, self.gen
	local t
	t = C_Timer.NewTimer(seconds, function()
		M.timers[t] = nil
		-- Off since, or off and on again: not this run's timer any more.
		if M.enabled and M.gen == gen then fn() end
	end)
	self.timers[t] = true
	return t
end

function Module:CreateFrame(kind, name, parent, template)
	local f = CreateFrame(kind, name, parent, template)
	self.frames[#self.frames + 1] = f
	return f
end

function Module:IsOn()
	local db = HUDiniDB
	if not db then return false end
	if self.isOn then return self.isOn() and true or false end
	if self.setting then return db[self.setting] and true or false end
	return true
end

local function Enable(M)
	M.enabled = true
	M.gen = M.gen + 1
	if M.OnEnable then Call(M.OnEnable, M) end
	if next(M.handlers) then
		if not M.frame then
			M.frame = CreateFrame("Frame")
			M.frame.module = M
			M.frame:SetScript("OnEvent", Dispatch)
		end
		for event in pairs(M.handlers) do pcall(M.frame.RegisterEvent, M.frame, event) end
	end
	local pew = M.handlers.PLAYER_ENTERING_WORLD
	if inWorld and pew and M.enabled then Call(pew, "PLAYER_ENTERING_WORLD", false, false, true) end
end

local function Disable(M)
	M.enabled = false
	M.gen = M.gen + 1
	if M.frame then M.frame:UnregisterAllEvents() end
	for _, t in ipairs(M.tickers) do t:Cancel() end
	wipe(M.tickers)
	for t in pairs(M.timers) do t:Cancel() end
	wipe(M.timers)
	if M.OnDisable then Call(M.OnDisable, M) end
end

-- Switch each module on or off to match its setting.
function ns.UpdateModules()
	if not (loggedIn and HUDiniDB) then return end
	for _, M in ipairs(modules) do
		local want = M:IsOn()
		if want and not M.enabled then
			Enable(M)
		elseif M.enabled and not want then
			Disable(M)
		end
	end
end

-- What each module has now, for /hud debug modules.
function ns.ModuleReport()
	local out = {}
	for _, M in ipairs(modules) do
		local events = 0
		if M.frame then
			for event in pairs(M.handlers) do
				if M.frame:IsEventRegistered(event) then events = events + 1 end
			end
		end
		local timers = 0
		for _ in pairs(M.timers) do timers = timers + 1 end
		out[#out + 1] = {
			name = M.name, label = M.label, on = M.enabled, events = events,
			tickers = #M.tickers, timers = timers, frames = #M.frames + (M.frame and 1 or 0),
			note = M.note, -- a locale key: why the part draws nothing, if set
			report = M.Report, -- a function: the part's own debug line, if any
		}
	end
	return out
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		loggedIn = true
		ns.UpdateModules()
	else
		inWorld = true
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	end
end)
