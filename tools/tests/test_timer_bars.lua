-- Cooldown timer bars (TICK-0158, GitHub #2). A spell you turn on gets a
-- bar under the HUD while its own cooldown runs. Only SPELL_UPDATE_COOLDOWN
-- or SPELL_UPDATE_CHARGES (and the look one frame later) starts a bar,
-- never the global cooldown alone; a plain "ready" ends it. The game's
-- duration object goes to the bar, the Cooldown and the text as it is.
-- Out of a fight the bars sort by time left; in a fight the order stays.
-- What the player sees needs DK's play.

-- Test class profiles, not the live class files (classes_fixture.lua).
local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local HEROISM, BLOODLUST, EARTH, FLAME = 32182, 2825, 8042, 8050
local NAMES = { Heroism = HEROISM, Bloodlust = BLOODLUST, ["Earth Shock"] = EARTH, ["Flame Shock"] = FLAME }
-- A made-up spell that replaces Heroism (an override).
local OVERRIDE = 99001

-- A Shaman. w.cd[id]: what GetSpellCooldown answers. w.left[id]: the
-- seconds the duration object says are left (a number, or "secret").
-- Each StatusBar keeps the last object it was given (f.fed), each Cooldown
-- too (f.cdFed); each text binding keeps its duration and its format.
-- setup(w), if given, runs before the addon loads (a save to start from).
local function World(setup)
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.secret, w.charges, w.loc, w.override, w.left = {}, {}, {}, {}, {}
	w.cd = {}
	for _, id in pairs(NAMES) do w.cd[id] = { isEnabled = true, isActive = false, isOnGCD = false } end
	w.cd[OVERRIDE] = { isEnabled = true, isActive = false, isOnGCD = false }
	local Throw = function() error("a secret value was used") end
	w.hidden = setmetatable({}, { __lt = Throw, __le = Throw, __concat = Throw, __index = Throw,
		__eq = Throw, __len = Throw, __unm = Throw })
	w.secret[w.hidden] = true
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_Spell.GetSpellInfo = function(name)
		local id = NAMES[name]
		if id then return { spellID = id } end
	end
	env.C_Spell.GetSpellName = function(id)
		for name, known in pairs(NAMES) do
			if known == id then return name end
		end
	end
	env.C_Spell.GetSpellCooldown = function(id) return w.cd[id] end
	env.C_Spell.GetSpellCharges = function(id) return w.charges[id] end
	env.C_Spell.GetSpellLossOfControlCooldownInfo = function(id) return w.loc[id] end
	env.C_Spell.GetOverrideSpell = function(id) return w.override[id] or id end
	env.IsPlayerSpell = function(id) return w.cd[id] ~= nil end
	-- The duration object: the global cooldown is left out (ignoreGCD).
	w.ignoreGCD = {}
	env.C_Spell.GetSpellCooldownDuration = function(id, ignoreGCD)
		w.ignoreGCD[id] = ignoreGCD
		local left = w.left[id]
		if left == nil then left = 0 end
		local o = { id = id }
		if left == "secret" then
			o.IsZero = function() return w.hidden end
			o.HasSecretValues = function() return true end
			o.GetRemainingDuration = function() return w.hidden end
		else
			o.IsZero = function() return left <= 0 end
			o.HasSecretValues = function() return false end
			o.GetRemainingDuration = function() return left end
		end
		return o
	end
	w.zero = { zero = true }
	env.C_DurationUtil = {
		CreateDuration = function() return w.zero end,
		CreateDurationTextBinding = function()
			local b = { enabled = false }
			function b:SetFontString(fs) self.fs = fs end
			function b:SetFormatter(f) self.formatter = f end
			function b:SetTextFormat(text, parts) self.text, self.parts = text, parts end
			function b:SetDuration(d) self.duration = d end
			function b:Enable() self.enabled = true end
			function b:Disable() self.enabled = false end
			return b
		end,
	}
	env.C_StringUtil = {
		CreateSecondsFormatter = function() return { kind = "seconds" } end,
		CreateNumericRuleFormatter = function()
			local f = { kind = "rule" }
			function f:SetBreakpoints(list) self.breakpoints = list end
			return f
		end,
	}
	env.Enum.DurationTextBindingProperty = { RemainingPercent = 7 }
	-- Record what each StatusBar and Cooldown is given.
	local make = env.CreateFrame
	env.CreateFrame = function(kind, ...)
		local f = make(kind, ...)
		if kind == "StatusBar" then
			rawset(f, "SetTimerDuration", function(self, d) self.fed = d end)
		elseif kind == "Cooldown" then
			rawset(f, "SetCooldownFromDurationObject", function(self, d) self.cdFed = d end)
			rawset(f, "Clear", function(self) self.cdFed = nil end)
		end
		return f
	end
	if setup then setup(w) end
	Classes.Use(w)
	local ns = w:loadAddon()
	return ns, w
end

-- Cast: the game starts the spell's own cooldown and says so in the event.
local function Cast(w, id, left)
	w.cd[id].isActive, w.cd[id].isOnGCD = true, false
	w.left[id] = left
	w:fire("SPELL_UPDATE_COOLDOWN", id, id)
end

-- The cooldown ends; the ticker looks.
local function Finish(w, id)
	w.cd[id].isActive = false
	w.left[id] = 0
	w:runTickers()
end

local function Order(ns) return table.concat(ns.TimerBarOrder(), ",") end

-- On screen: the frame and every parent shown (the stub's IsVisible looks
-- at the frame alone).
local function OnScreen(f)
	while f do
		if not f:IsShown() then return false end
		f = f:GetParent()
	end
	return true
end
local function Bar(ns, name) return ns.TimerBarFrame(name) end

H.test("timer bars: the class file's spells are offered, all off, and nothing shows", function()
	local ns, w = World()
	local list = ns.TimerBarSpells()
	H.eq(list[1], "Heroism")
	H.eq(list[2], "Bloodlust")
	H.eq(ns.GetTimerBar("Heroism"), false, "off by default")
	Cast(w, HEROISM, 300)
	H.eq(Order(ns), "", "no bar for a spell left off")
	H.eq(Bar(ns, "Heroism"), nil, "no frame made")
end)

H.test("timer bars: two spells turned on show two bars, least time left on top", function()
	local ns, w = World()
	H.eq(ns.SetTimerBar("Heroism", true), true, "changed")
	H.eq(ns.SetTimerBar("Heroism", true), false, "same again: no change")
	ns.SetTimerBar("Bloodlust", true)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBars.Heroism, true, "saved per class")
	Cast(w, HEROISM, 300)
	H.eq(Order(ns), "Heroism", "one bar")
	Cast(w, BLOODLUST, 120)
	H.eq(Order(ns), "Bloodlust,Heroism", "sorted: least time left on top")
	local f = Bar(ns, "Heroism")
	H.eq(f:IsShown(), true, "the bar shows")
	H.eq(f.bar.fed.id, HEROISM, "the bar drains from the game's object")
	H.eq(f.cd.cdFed.id, HEROISM, "the Cooldown has it too, for its end")
	H.eq(f.bind.duration.id, HEROISM, "and the time text")
	H.eq(f.bind.enabled, true, "the text runs")
	H.eq(f.bind.formatter.kind, "seconds", "seconds by default")
	H.eq(w.ignoreGCD[HEROISM], true, "the global cooldown is left out of the object")
	H.eq(f.label:GetText(), "Heroism", "its name on the bar")
	local holder = ns.TimerBarHolder()
	H.eq(f:GetParent(), holder, "in the holder")
	H.eq(holder:GetParent(), ns.HUDini.body, "part of the HUD: it hides with it")
	local top = { Bar(ns, "Bloodlust"):GetPoint(1) }
	local second = { f:GetPoint(1) }
	H.eq(top[2], holder, "placed in the holder")
	H.eq(select(2, holder:GetPoint(1)), ns.HUDini.mover, "the holder against the HUD")
	H.ok(second[5] < top[5], "Heroism sits under Bloodlust")
end)

H.test("timer bars: the global cooldown alone starts no bar", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, true
	w.left[HEROISM] = 0
	w:fire("SPELL_UPDATE_COOLDOWN")
	w:runTimers()
	H.eq(Order(ns), "", "no bar")
end)

H.test("timer bars: isOnGCD misread, but the object without the global cooldown is zero: no bar", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w.left[HEROISM] = 0
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Order(ns), "", "a plain zero is no cooldown")
end)

H.test("timer bars: a spell turned ready ends its bar with a zero duration", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	Finish(w, HEROISM)
	H.eq(Order(ns), "", "the bar goes")
	H.eq(f:IsShown(), false, "hidden")
	H.eq(f.bar.fed, w.zero, "cleared with a zero duration, not a value")
	H.eq(f.bind.enabled, false, "the text stops")
end)

H.test("timer bars: the ticker never starts a bar", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w.left[HEROISM] = 300
	w:runTickers()
	H.eq(Order(ns), "", "only the event starts a bar")
end)

H.test("timer bars: a shared cooldown with no event of its own shows on the next frame", function()
	local ns, w = World()
	ns.SetTimerBar("Earth Shock", true)
	ns.SetTimerBar("Flame Shock", true)
	H.eq(ns.TimerBarSpells()[5], "Earth Shock", "an extra spell is offered after the class file's")
	-- The event names Earth Shock; the game moves Flame Shock a frame later.
	w.cd[EARTH].isActive, w.left[EARTH] = true, 6
	w:fire("SPELL_UPDATE_COOLDOWN", EARTH, EARTH)
	H.eq(Order(ns), "Earth Shock", "Earth Shock at once")
	w.cd[FLAME].isActive, w.left[FLAME] = true, 6
	w:runTimers()
	H.eq(Order(ns), "Earth Shock,Flame Shock", "Flame Shock on the second look")
end)

H.test("timer bars: the event payload is not filtered by spell", function()
	local ns, w = World()
	ns.SetTimerBar("Flame Shock", true)
	w.cd[FLAME].isActive, w.left[FLAME] = true, 6
	w:fire("SPELL_UPDATE_COOLDOWN", EARTH, EARTH)
	H.eq(Order(ns), "Flame Shock", "an event for another spell still asks this one")
end)

H.test("timer bars: a spell is asked by its override", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.override[HEROISM] = OVERRIDE
	Cast(w, OVERRIDE, 60)
	H.eq(Order(ns), "Heroism", "the override's cooldown shows on Heroism's bar")
	H.eq(Bar(ns, "Heroism").bar.fed.id, OVERRIDE, "the override's object")
end)

H.test("timer bars: in a fight the order stays, a ready bar leaves, a new one joins at the end", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	ns.SetTimerBar("Earth Shock", true)
	w.combat = true
	Cast(w, HEROISM, "secret")
	Cast(w, BLOODLUST, "secret")
	H.eq(Order(ns), "Heroism,Bloodlust", "the order they came in: time left cannot be compared")
	Finish(w, HEROISM)
	H.eq(Order(ns), "Bloodlust", "a ready bar leaves")
	Cast(w, EARTH, "secret")
	H.eq(Order(ns), "Bloodlust,Earth Shock", "a new bar joins at the end")
	-- The fight ends: the time left reads again.
	w.combat = false
	w.left[BLOODLUST], w.left[EARTH] = 200, 5
	-- No cooldown event: the end of the fight alone gets new objects.
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Order(ns), "Earth Shock,Bloodlust", "sorted again out of the fight")
end)

H.test("timer bars: a secret answer changes nothing", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	Cast(w, BLOODLUST, 100)
	w.cd[HEROISM].isActive = w.hidden
	w.cd[BLOODLUST].isActive = w.hidden
	w:fire("SPELL_UPDATE_COOLDOWN")
	w:runTimers()
	w:runTickers()
	H.eq(Order(ns), "Bloodlust", "no new bar, and the bar that shows stays")
end)

H.test("timer bars: each event hands the object again, so a cut cooldown is right", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local first = Bar(ns, "Heroism").bar.fed
	w.left[HEROISM] = 30
	w:fire("SPELL_UPDATE_COOLDOWN")
	local f = Bar(ns, "Heroism")
	H.ok(f.bar.fed ~= first, "a new object")
	H.eq(f.bar.fed:GetRemainingDuration(), 30, "with the new time")
	H.eq(f.bind.duration, f.bar.fed, "the text has it too")
end)

H.test("timer bars: the Cooldown's end looks again", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	w.cd[HEROISM].isActive = false
	f.cd:GetScript("OnCooldownDone")(f.cd)
	H.eq(Order(ns), "", "the bar goes on OnCooldownDone")
end)

H.test("timer bars: percent text, and a change of format takes at once", function()
	local ns, w = World()
	w.env.HUDiniDB.timerBarTime = "percent"
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	local bind = f.bind
	H.eq(bind.text, "{}%", "a percent")
	H.eq(bind.parts[1].property, 7, "of the time left")
	H.eq(bind.parts[1].formatter.breakpoints[1].format, "%.0f", "whole numbers")
	w.env.HUDiniDB.timerBarTime = "seconds"
	ns.RefreshTimerBars()
	H.ok(f.bind ~= bind, "a new binding")
	H.eq(bind.enabled, false, "the old one stops")
	H.eq(f.bind.formatter.kind, "seconds", "seconds now")
	H.eq(f.bind.duration, f.bar.fed, "with the same time")
end)

H.test("timer bars: the bar takes the timer color and the HUD's texture, or its own", function()
	local ns, w = World()
	local seen = {}
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	rawset(f.bar, "SetStatusBarTexture", function(_, path) seen.texture = path end)
	rawset(f.bar, "SetStatusBarColor", function(_, r, g, b) seen.color = { r, g, b } end)
	w.env.HUDiniDB.colors = w.env.HUDiniDB.colors or {}
	w.env.HUDiniDB.colors.timer = { 1, 0, 0 }
	ns.RefreshTimerBars()
	H.eq(seen.texture, ns.BarTexturePath(), "the HUD's bar texture by default")
	H.eq(seen.color[1], 1, "the chosen color")
	H.eq(seen.color[2], 0)
	ns.SetBarLook(ns.TimerLookId("Heroism"), "texture", "flat")
	ns.RefreshTimerBars()
	H.eq(seen.texture, ns.TexturePathFor("flat"), "a texture of its own")
end)

H.test("timer bars: each bar wears its own color; one with none, the timer color (TICK-0258)", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	Cast(w, HEROISM, 300)
	Cast(w, BLOODLUST, 100)
	local seen = {}
	for _, name in ipairs({ "Heroism", "Bloodlust" }) do
		rawset(Bar(ns, name).bar, "SetStatusBarColor", function(_, r, g, b) seen[name] = { r, g, b } end)
	end
	w.env.HUDiniDB.colors = w.env.HUDiniDB.colors or {}
	w.env.HUDiniDB.colors.timer = { 1, 0, 0 }
	ns.RefreshTimerBars()
	ns.SetBarLook(ns.TimerLookId("Heroism"), "base", { 0, 1, 0 })
	H.eq(table.concat(seen.Heroism, ","), "0,1,0", "Heroism: its own color, at once")
	H.eq(table.concat(seen.Bloodlust, ","), "1,0,0", "Bloodlust keeps the timer color")
end)

H.test("timer bars: under the totem row when it shows, right under the HUD when not", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	ns.SetTimerBar("Heroism", true)
	db.showTotems = true
	Cast(w, HEROISM, 300)
	local withTotems = select(5, ns.TimerBarHolder():GetPoint(1))
	db.showTotems = false
	ns.RefreshTimerBars()
	local without = select(5, ns.TimerBarHolder():GetPoint(1))
	H.ok(withTotems < without, "lower when the totem row is there")
	H.eq(without, -3, "a gap under the HUD")
end)

H.test("timer bars: a spell turned off loses its bar; the last one off turns the part off", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	Cast(w, HEROISM, 300)
	Cast(w, BLOODLUST, 100)
	ns.SetTimerBar("Bloodlust", false)
	H.eq(Order(ns), "Heroism", "Bloodlust's bar goes")
	ns.SetTimerBar("Heroism", false)
	H.eq(Order(ns), "", "no bar")
	H.eq(Bar(ns, "Heroism"):IsShown(), false, "hidden")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBars, nil, "nothing saved")
	Cast(w, HEROISM, 300)
	H.eq(Order(ns), "", "off: the event does nothing")
end)

H.test("timer bars: a spell with charges shows while a charge comes back", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	local chargeObject = { id = "charge", IsZero = function() return false end,
		HasSecretValues = function() return false end, GetRemainingDuration = function() return 20 end }
	w.env.C_Spell.GetSpellChargeDuration = function() return chargeObject end
	w.charges[HEROISM] = { maxCharges = 2, currentCharges = 1, isActive = true }
	w:fire("SPELL_UPDATE_CHARGES")
	H.eq(Order(ns), "Heroism", "a bar while a charge comes back")
	H.eq(Bar(ns, "Heroism").bar.fed, chargeObject, "the charge's object")
	w.charges[HEROISM].isActive = false
	w:runTickers()
	H.eq(Order(ns), "", "every charge back: the bar goes")
end)

H.test("timer bars: with a bar showing, the ticker and a Cooldown's end still start no bar", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	Cast(w, BLOODLUST, 120)
	-- Heroism's cooldown runs, but no event says so.
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w.left[HEROISM] = 300
	w:runTickers()
	H.eq(Order(ns), "Bloodlust", "the ticker starts none")
	local f = Bar(ns, "Bloodlust")
	f.cd:GetScript("OnCooldownDone")(f.cd)
	H.eq(Order(ns), "", "nor a Cooldown's end (which ends its own bar)")
end)

H.test("timer bars: in a fight the order stays, even when the time left reads plain", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	w.combat = true
	Cast(w, HEROISM, 300)
	Cast(w, BLOODLUST, 120)
	H.eq(Order(ns), "Heroism,Bloodlust", "no sort in a fight")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Order(ns), "Bloodlust,Heroism", "sorted after it")
end)

H.test("timer bars: an answer not known keeps the bar and hands its object again", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	local first = f.bar.fed
	w.cd[HEROISM].isActive = w.hidden
	w.left[HEROISM] = 30
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Order(ns), "Heroism", "the bar stays")
	H.ok(f.bar.fed ~= first, "in the event: a new object")
	H.eq(f.bar.fed:GetRemainingDuration(), 30, "with the new time")
	H.eq(f.cd.cdFed, f.bar.fed, "the Cooldown has it too")
	w.left[HEROISM] = 0
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Order(ns), "", "a plain zero object ends it")
end)

-- Review round 1 (TICK-0158).

H.test("timer bars: isOnGCD read outside the cooldown event never ends a bar", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.combat = true
	Cast(w, HEROISM, "secret")
	local f = Bar(ns, "Heroism")
	-- A stale isOnGCD true: in the event this would say "only the global
	-- cooldown is left".
	w.cd[HEROISM].isOnGCD = true
	w:fire("SPELLS_CHANGED")
	H.eq(Order(ns), "Heroism", "SPELLS_CHANGED (a form change in a fight)")
	w:fire("PLAYER_ENTERING_WORLD")
	H.eq(Order(ns), "Heroism", "PLAYER_ENTERING_WORLD")
	ns.RefreshTimerBars()
	H.eq(Order(ns), "Heroism", "a change of options")
	w:fire("SPELL_UPDATE_CHARGES")
	H.eq(Order(ns), "Heroism", "SPELL_UPDATE_CHARGES, for a spell with no charges")
	w:runTimers()
	H.eq(Order(ns), "Heroism", "the look one frame later")
	H.eq(f:IsShown(), true, "shown")
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Order(ns), "", "only the event itself ends it")
end)

H.test("timer bars: isOnGCD read outside the cooldown event starts no bar but the late look", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.combat = true
	-- Heroism is on the global cooldown alone, and isOnGCD reads false.
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w.left[HEROISM] = "secret"
	w:fire("SPELLS_CHANGED")
	H.eq(Order(ns), "", "SPELLS_CHANGED")
	ns.RefreshTimerBars()
	H.eq(Order(ns), "", "a change of options")
	w:fire("SPELL_UPDATE_CHARGES")
	H.eq(Order(ns), "", "SPELL_UPDATE_CHARGES, for a spell with no charges")
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Order(ns), "", "the end of a fight")
end)

H.test("timer bars: the late look does not start again a bar the event just ended", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	w.combat = true
	Cast(w, HEROISM, "secret")
	w:runTimers()
	-- Its own cooldown is over; only the global cooldown is left.
	w.cd[HEROISM].isOnGCD = true
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(Order(ns), "", "the event ends it")
	-- One frame later isOnGCD reads false, and the object is secret.
	w.cd[HEROISM].isOnGCD = false
	w:runTimers()
	H.eq(Order(ns), "", "the late look leaves it ended")
	-- The next real cast starts it.
	Cast(w, HEROISM, "secret")
	H.eq(Order(ns), "Heroism", "a new cast")
end)

H.test("timer bars: many cooldown events in one frame make one late look", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	local reads, get = 0, w.env.C_Spell.GetSpellCooldown
	w.env.C_Spell.GetSpellCooldown = function(id)
		if id == HEROISM then reads = reads + 1 end
		return get(id)
	end
	w:fire("SPELL_UPDATE_COOLDOWN")
	reads = 0
	w:runTimers()
	local one = reads
	H.ok(one > 0, "the late look reads the spell")
	w:fire("SPELL_UPDATE_COOLDOWN")
	w:fire("SPELL_UPDATE_COOLDOWN")
	w:fire("SPELL_UPDATE_COOLDOWN")
	reads = 0
	w:runTimers()
	H.eq(reads, one, "three events: one late look")
	w:fire("SPELL_UPDATE_COOLDOWN")
	reads = 0
	w:runTimers()
	H.eq(reads, one, "the next frame gets its own")
end)

H.test("timer bars: a Cooldown's end ends that bar only, even with the global cooldown left", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	ns.SetTimerBar("Bloodlust", true)
	Cast(w, HEROISM, 300)
	Cast(w, BLOODLUST, 100)
	local f = Bar(ns, "Bloodlust")
	w.cd[BLOODLUST].isOnGCD = true -- isActive stays true: the global cooldown
	f.cd:GetScript("OnCooldownDone")(f.cd)
	H.eq(Order(ns), "Heroism", "Bloodlust's own time is up: its bar goes, Heroism's stays")
end)

H.test("timer bars: with charges, a Cooldown's end gets the next charge's object", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	local n = 0
	w.env.C_Spell.GetSpellChargeDuration = function()
		n = n + 1
		return { id = "charge" .. n, IsZero = function() return false end,
			HasSecretValues = function() return false end, GetRemainingDuration = function() return 20 end }
	end
	w.charges[HEROISM] = { maxCharges = 2, currentCharges = 0, isActive = true }
	w:fire("SPELL_UPDATE_CHARGES")
	local f = Bar(ns, "Heroism")
	local first = f.bar.fed
	f.cd:GetScript("OnCooldownDone")(f.cd)
	H.eq(Order(ns), "Heroism", "a charge still comes back")
	H.ok(f.bar.fed ~= first, "the next charge's object")
end)

H.test("timer bars: a bar is styled when it shows or its look changes, not on each look", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	local n = 0
	rawset(f.bar, "SetStatusBarTexture", function() n = n + 1 end)
	w:runTickers()
	w:fire("SPELL_UPDATE_COOLDOWN")
	w:runTimers()
	H.eq(n, 0, "the ticker and the events do not style it again")
	ns.SetBarLook(ns.TimerLookId("Heroism"), "texture", "flat")
	ns.RefreshTimerBars()
	H.eq(n, 1, "a new texture does")
	w.env.HUDiniDB.iconSize = 50
	ns.HUDini:Layout()
	H.eq(n, 2, "a new size does")
end)

H.test("timer bars: the label is the name of the spell the game uses now", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	local name = w.env.C_Spell.GetSpellName
	w.env.C_Spell.GetSpellName = function(id)
		if id == OVERRIDE then return "Big Heroism" end
		return name(id)
	end
	Cast(w, HEROISM, 60)
	H.eq(Bar(ns, "Heroism").label:GetText(), "Heroism", "no override: its own name")
	Finish(w, HEROISM)
	w.override[HEROISM] = OVERRIDE
	Cast(w, OVERRIDE, 60)
	H.eq(Bar(ns, "Heroism").label:GetText(), "Big Heroism", "the override's name")
end)

--------------------------------------------------------------------------------
-- Their own place (TICK-0169, D-044)
--------------------------------------------------------------------------------

-- Unlock the HUD the way /hud unlock does.
local function SetLocked(ns, w, locked)
	w.env.HUDiniDB.locked = locked
	ns.HUDini:ApplyLock()
end

-- Drag the blue box: the game leaves the holder's top left at x, y (in its
-- own pixels).
local function Drag(ns, x, y)
	local holder = ns.TimerBarHolder()
	holder.grab:GetScript("OnDragStart")(holder.grab)
	rawset(holder, "GetLeft", function() return x end)
	rawset(holder, "GetTop", function() return y end)
	holder.grab:GetScript("OnDragStop")(holder.grab)
end

H.test("timer bars: no saved place is today's place under the HUD (an old save)", function()
	local ns, w = World(function(w)
		-- A save from before TICK-0169: a timer bar on, no place.
		w.env.HUDiniDB = { locked = true, classes = { SHAMAN = { timerBars = { ["Earth Shock"] = true } } } }
	end)
	Cast(w, EARTH, 5)
	H.eq(Order(ns), "Earth Shock", "the bar shows")
	local holder = ns.TimerBarHolder()
	local point, to, rel, x = holder:GetPoint(1)
	H.eq(point, "TOPLEFT")
	H.eq(to, ns.HUDini.mover, "under the HUD, moving with it")
	H.eq(rel, "BOTTOMLEFT")
	H.eq(x, 1)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace, nil, "nothing written")
	H.eq(holder.grab:IsShown(), false, "locked: no blue box")
end)

H.test("timer bars: the saved place loads", function()
	local ns, w = World(function(w)
		w.env.HUDiniDB = { locked = true, classes = { SHAMAN = {
			timerBars = { ["Earth Shock"] = true }, timerBarPlace = { x = 300, y = 200 } } } }
	end)
	Cast(w, EARTH, 5)
	local point, to, rel, x, y = ns.TimerBarHolder():GetPoint(1)
	H.eq(point, "TOPLEFT")
	H.eq(to, w.env.UIParent, "on the screen, not on the HUD")
	H.eq(rel, "BOTTOMLEFT")
	H.eq(x, 300)
	H.eq(y, 200)
	H.eq(select(2, Bar(ns, "Earth Shock"):GetPoint(1)), ns.TimerBarHolder(), "the bar in the holder")
end)

H.test("timer bars: a bad saved place is no place", function()
	local ns, w = World(function(w)
		w.env.HUDiniDB = { locked = true, classes = { SHAMAN = {
			timerBars = { ["Earth Shock"] = true }, timerBarPlace = { x = "left" } } } }
	end)
	Cast(w, EARTH, 5)
	H.eq(select(2, ns.TimerBarHolder():GetPoint(1)), ns.HUDini.mover, "under the HUD")
end)

H.test("timer bars: unlocked, a blue box to drag; the place is saved per class; the HUD stays", function()
	local ns, w = World()
	ns.SetTimerBar("Earth Shock", true)
	local holder = ns.TimerBarHolder()
	SetLocked(ns, w, false)
	H.eq(holder:IsShown(), true, "the holder shows")
	H.eq(holder.grab:IsShown(), true, "the blue box shows with no bar running")
	H.ok(holder.grab:GetFrameLevel() > holder:GetFrameLevel(), "over the bars")
	H.ok(holder:GetHeight() > 0, "two sample rows to grab")
	H.eq(holder.grab.text:GetText(), ns.Text("timerBars.dragMe"), "it says what it is")
	local hudPoints = { ns.HUDini:GetPoint(1) }
	holder:SetScale(2)
	Drag(ns, 150, 100)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace.x, 300, "saved in screen pixels")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace.y, 200)
	local _, to, _, x, y = holder:GetPoint(1)
	H.eq(to, w.env.UIParent, "anchored where it was dropped")
	H.eq(x, 150)
	H.eq(y, 100)
	H.eq(holder:IsUserPlaced(), false, "the game's layout cache keeps nothing")
	local after = { ns.HUDini:GetPoint(1) }
	for i = 1, 5 do H.eq(after[i], hudPoints[i], "the HUD did not move") end
	-- A layout of the HUD (a new icon size) leaves the bars where they are.
	ns.HUDini:Layout()
	H.eq(select(2, holder:GetPoint(1)), w.env.UIParent, "still on its own place")
	SetLocked(ns, w, true)
	H.eq(holder.grab:IsShown(), false, "locked: the blue box goes")
	H.eq(select(4, holder:GetPoint(1)), 150, "and the place stays")
end)

H.test("timer bars: locked or in a fight, no drag", function()
	local ns, w = World()
	ns.SetTimerBar("Earth Shock", true)
	Drag(ns, 150, 100)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace, nil, "locked: nothing moves")
	SetLocked(ns, w, false)
	w.combat = true
	Drag(ns, 150, 100)
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace, nil, "in a fight: nothing moves")
	H.eq(ns.ResetTimerBarsPlace(), false, "no reset in a fight")
end)

H.test("timer bars: a reset puts the bars back under the HUD", function()
	local ns, w = World()
	ns.SetTimerBar("Earth Shock", true)
	SetLocked(ns, w, false)
	Drag(ns, 150, 100)
	H.eq(select(2, ns.TimerBarHolder():GetPoint(1)), w.env.UIParent, "moved")
	H.eq(ns.ResetTimerBarsPlace(), true, "reset")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace, nil, "the place is gone")
	H.eq(select(2, ns.TimerBarHolder():GetPoint(1)), ns.HUDini.mover, "under the HUD again")
end)

H.test("timer bars: /hud reset class clears the place too", function()
	local ns, w = World()
	ns.SetTimerBar("Earth Shock", true)
	SetLocked(ns, w, false)
	Drag(ns, 150, 100)
	w:slash("/hud reset class")
	w:slash("/hud reset yes")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.timerBarPlace, nil, "the class's saved choices go")
end)

H.test("timer bars: off, the holder and its blue box hide, unlocked or not", function()
	local ns, w = World()
	ns.SetTimerBar("Earth Shock", true)
	SetLocked(ns, w, false)
	H.eq(ns.TimerBarHolder().grab:IsShown(), true, "on: the blue box")
	ns.SetTimerBar("Earth Shock", false)
	H.eq(ns.TimerBarHolder():IsShown(), false, "off: the holder hides")
	H.eq(ns.TimerBarHolder().grab:IsShown(), false, "and its blue box")
	SetLocked(ns, w, true)
	SetLocked(ns, w, false)
	H.eq(ns.TimerBarHolder().grab:IsShown(), false, "unlocked again: still nothing")
end)

H.test("timer bars stay (TICK-0219): off by default, a bar hides with the HUD", function()
	local ns, w = World()
	H.eq(w.env.HUDiniDB.timerBarsStay, false, "off by default")
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	local f = Bar(ns, "Heroism")
	H.eq(ns.TimerBarHolder():GetParent(), ns.HUDini.body, "in the body")
	ns.HUDini.body:Hide()
	H.eq(OnScreen(f), false, "the HUD hides: the bar goes with it")
end)

H.test("timer bars stay (TICK-0219): on, a running bar shows while the HUD hides", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	Cast(w, HEROISM, 300)
	w.env.HUDiniDB.timerBarsStay = true
	ns.RefreshTimerBars()
	local holder = ns.TimerBarHolder()
	H.eq(holder:GetParent(), ns.HUDini, "on the anchor, which never hides")
	ns.HUDini.body:Hide()
	local f = Bar(ns, "Heroism")
	H.eq(OnScreen(f), true, "the bar stays in view")
	local _, rel = holder:GetPoint(1)
	H.eq(rel, ns.HUDini.mover, "at the same place: under the HUD")
	Finish(w, HEROISM)
	H.eq(OnScreen(f), false, "no running bar: nothing shows")
	-- Off again: back in the body, hiding with it.
	w.env.HUDiniDB.timerBarsStay = false
	Cast(w, HEROISM, 300)
	H.eq(holder:GetParent(), ns.HUDini.body, "back in the body")
	H.eq(OnScreen(f), false, "and hidden with it")
end)

H.test("timer bars stay (TICK-0219): a saved place and the blue box still work", function()
	local ns, w = World(function(w2)
		w2.env.HUDiniDB = { timerBarsStay = true }
	end)
	ns.SetTimerBar("Heroism", true)
	w.env.HUDiniDB.locked = false
	ns.HUDini:ApplyLock()
	local holder = ns.TimerBarHolder()
	H.eq(holder:GetParent(), ns.HUDini, "on the anchor from login")
	H.eq(holder.grab:IsShown(), true, "the blue box shows while unlocked")
	w.env.HUDiniDB.classes.SHAMAN.timerBarPlace = { x = 200, y = 300 }
	ns.RefreshTimerBars()
	local _, rel = holder:GetPoint(1)
	H.eq(rel, w.env.UIParent, "at its saved place")
	H.eq(#w.blocked, 0, "nothing blocked")
end)
