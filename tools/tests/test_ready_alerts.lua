-- Cooldown ready alerts (TICK-0157, GitHub #1). A spell you turn on plays a
-- sound and glows on the HUD when its cooldown ends. Off by default. Only
-- SPELL_UPDATE_COOLDOWN (or SPELL_UPDATE_CHARGES) marks a spell "on
-- cooldown", never the global cooldown alone and never the ticker; the
-- ticker only finds the end. A secret answer is unknown: no alert. What the
-- player hears and sees needs DK's play.

-- Test class profiles, not the live class files (classes_fixture.lua).
local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local HEROISM, BLOODLUST = 32182, 2825
local SOUND = 8960 -- the ready check, the default (TICK-0167)
local NAMES = { Heroism = HEROISM, Bloodlust = BLOODLUST }
-- A made-up spell that replaces Heroism (an override).
local OVERRIDE = 99001

-- A Shaman who knows Heroism and Bloodlust. w.cd[id] is what
-- GetSpellCooldown answers, w.charges[id] what GetSpellCharges answers.
-- w.sounds logs each PlaySound. w.secret holds the values the game hides.
local function World()
	local w = H.world()
	local env = w.env
	w.class, w.className = "SHAMAN", "Shaman"
	w.secret, w.sounds, w.charges = {}, {}, {}
	w.cd = {
		[HEROISM] = { isEnabled = true, isActive = false, isOnGCD = false },
		[BLOODLUST] = { isEnabled = true, isActive = false, isOnGCD = false },
	}
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
	w.loc, w.override = {}, {}
	env.C_Spell.GetSpellLossOfControlCooldownInfo = function(id) return w.loc[id] end
	env.C_Spell.GetOverrideSpell = function(id) return w.override[id] or id end
	env.IsPlayerSpell = function(id) return id == HEROISM or id == BLOODLUST or id == OVERRIDE end
	env.PlaySound = function(kit) table.insert(w.sounds, kit) return true end
	Classes.Use(w)
	local ns = w:loadAddon()
	return ns, w
end

local function Lit(ns, id) return ns.HUDini.alertGlow["cooldown:" .. id] == id end

-- Cast: the game starts the spell's own cooldown and says so in the event.
local function Cast(w, id)
	w.cd[id].isActive, w.cd[id].isOnGCD = true, false
	w:fire("SPELL_UPDATE_COOLDOWN", id, id)
end

-- Seconds pass: longer than any global cooldown.
local function Wait(w)
	w.time = w.time + 10
end

-- The cooldown ends; the ticker looks.
local function Finish(w, id)
	Wait(w)
	w.cd[id].isActive = false
	w:runTickers()
end

H.test("ready alerts: the class file's spells are offered, all off", function()
	local ns = World()
	local list = ns.ReadyAlertSpells()
	H.eq(list[1], "Heroism")
	H.eq(list[2], "Bloodlust")
	H.eq(ns.GetReadyAlert("Heroism"), false, "off by default")
end)

H.test("ready alerts: a spell left off makes no sound and no glow", function()
	local ns, w = World()
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no sound")
	H.eq(Lit(ns, HEROISM), false, "no glow")
end)

H.test("ready alerts: a spell turned on sounds and glows when ready, then the glow goes out", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	ns.HUDini.spells = { { spellID = HEROISM } }
	H.eq(ns.SetReadyAlert("Heroism", true), true, "changed")
	H.eq(ns.SetReadyAlert("Heroism", true), false, "same again: no change")
	H.eq(ns.GetReadyAlert("Heroism"), true)
	H.eq(db.classes.SHAMAN.readyAlerts.Heroism, true, "saved per class")
	H.eq((ns.HUDini:ShouldShow()), false, "idle: hidden")
	Cast(w, HEROISM)
	w:runTickers()
	H.eq(#w.sounds, 0, "no sound while on cooldown")
	Finish(w, HEROISM)
	H.eq(#w.sounds, 1, "one sound")
	H.eq(w.sounds[1], SOUND, "the sound")
	H.eq(Lit(ns, HEROISM), true, "glows")
	local show, why = ns.HUDini:ShouldShow()
	H.eq(show, true, "the glow wakes the HUD")
	H.eq(why, ns.Text("why.cooldownReady"))
	w:runTickers()
	H.eq(#w.sounds, 1, "one sound only")
	w.time = w.time + 5
	w:runTickers()
	H.eq(Lit(ns, HEROISM), false, "the glow goes out after 5 s")
	H.eq((ns.HUDini:ShouldShow()), false, "idle again")
end)

-- TICK-0167 (D-043): the player picks the ready sound, one per class.
H.test("ready alerts: the picked sound plays, on the Master channel", function()
	local ns, w = World()
	local channels = {}
	w.env.PlaySound = function(kit, ch)
		table.insert(w.sounds, kit)
		table.insert(channels, ch)
		return true
	end
	H.eq(ns.GetReadySound(), "readyCheck", "the default")
	H.eq(ns.SetReadySound("mapPing"), true, "changed")
	H.eq(ns.SetReadySound("mapPing"), false, "same again: no change")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readySound, "mapPing", "saved per class")
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), "3175", "the minimap ping")
	H.eq(channels[1], "Master", "Master: it plays with Sound Effects turned down")
	H.eq(ns.SetReadySound("readyCheck"), true, "back to the default")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readySound, nil, "the default is not saved")
end)

H.test("ready alerts: a key not in the list is the default and cannot be set", function()
	local ns, w = World()
	H.eq(ns.SetReadySound("bellStrike"), false, "not in the list: no change")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readySound, nil, "nothing saved")
	w.env.HUDiniDB.classes.SHAMAN.readySound = "bellStrike" -- a key a later build dropped
	H.eq(ns.GetReadySound(), "readyCheck", "plays the default")
end)

-- WoW Forever's PlaySound returns nothing for a kit its data lacks (DK's
-- test): the pick falls back to the default, then the raid warning.
H.test("ready alerts: a pick the client cannot play plays the default", function()
	local ns, w = World()
	w.env.PlaySound = function(kit)
		table.insert(w.sounds, kit)
		if kit ~= 3175 then return true end
	end
	ns.SetReadySound("mapPing")
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), "3175 " .. SOUND, "the ping, then the ready check")
	H.eq(Lit(ns, HEROISM), true, "glows")
end)

H.test("ready alerts: the ticker stops when nothing is on cooldown or glowing", function()
	local ns, w = World()
	local before = #w.tickers
	ns.SetReadyAlert("Heroism", true)
	H.eq(#w.tickers, before, "no ticker while nothing is on cooldown")
	Cast(w, HEROISM)
	H.eq(#w.tickers, before + 1, "a ticker runs while on cooldown")
	local ticker = w.tickers[#w.tickers]
	Finish(w, HEROISM)
	H.eq(ticker.cancelled, false, "still runs while it glows")
	w.time = w.time + 5
	w:runTickers()
	H.eq(ticker.cancelled, true, "stopped")
end)

H.test("ready alerts: the global cooldown alone is not the spell's cooldown", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, true
	w:fire("SPELL_UPDATE_COOLDOWN", 403, 403)
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no sound after a global cooldown")
end)

H.test("ready alerts: only the event marks a spell on cooldown, never the ticker", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	ns.SetReadyAlert("Bloodlust", true)
	-- Bloodlust's event starts the ticker. Heroism reads "on cooldown" at a
	-- tick (another spell's global cooldown looks like that), but no event
	-- said so for it.
	Cast(w, BLOODLUST)
	w.cd[HEROISM].isActive = true
	w:runTickers()
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no sound for Heroism")
	H.eq(Lit(ns, HEROISM), false, "no glow for Heroism")
end)

H.test("ready alerts: a spell already ready at the event is not an alert", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	w:fire("SPELL_UPDATE_COOLDOWN")
	w:runTickers()
	H.eq(#w.sounds, 0, "no sound at login")
end)

H.test("ready alerts: the event can see the end too", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Wait(w)
	w.cd[HEROISM].isActive = false
	w:fire("SPELL_UPDATE_COOLDOWN")
	H.eq(#w.sounds, 1, "the event's read of the end")
	H.eq(Lit(ns, HEROISM), true, "glows")
end)

-- The secret guards: each runs plain first, then with the very value that
-- WOULD start or end the cooldown flagged secret.
H.test("ready alerts: a secret isActive in the event does not start a cooldown", function()
	for _, secret in ipairs({ false, true }) do
		local ns, w = World()
		ns.SetReadyAlert("Heroism", true)
		w.secret[true] = secret
		Cast(w, HEROISM)
		w.secret[true] = nil
		Finish(w, HEROISM)
		H.eq(#w.sounds, secret and 0 or 1, "sound when plain only, secret=" .. tostring(secret))
	end
end)

H.test("ready alerts: a secret isOnGCD in the event does not start a cooldown", function()
	for _, secret in ipairs({ false, true }) do
		local ns, w = World()
		ns.SetReadyAlert("Heroism", true)
		-- false is isOnGCD's value; isActive stays a plain true.
		w.secret[false] = secret
		Cast(w, HEROISM)
		w.secret[false] = nil
		Finish(w, HEROISM)
		H.eq(#w.sounds, secret and 0 or 1, "sound when plain only, secret=" .. tostring(secret))
	end
end)

H.test("ready alerts: a secret isActive at the end is not ready", function()
	for _, secret in ipairs({ false, true }) do
		local ns, w = World()
		ns.SetReadyAlert("Heroism", true)
		Cast(w, HEROISM)
		w.secret[false] = secret
		Finish(w, HEROISM)
		H.eq(#w.sounds, secret and 0 or 1, "sound when plain only, secret=" .. tostring(secret))
		H.eq(Lit(ns, HEROISM), not secret, "glow when plain only")
	end
end)

H.test("ready alerts: a secret charge isActive in the event does not start a cooldown", function()
	for _, secret in ipairs({ false, true }) do
		local ns, w = World()
		ns.SetReadyAlert("Heroism", true)
		local charges = { maxCharges = 2, currentCharges = 1, isActive = true }
		w.charges[HEROISM] = charges
		w.secret[true] = secret
		w:fire("SPELL_UPDATE_CHARGES")
		w.secret[true] = nil
		Wait(w)
		charges.currentCharges, charges.isActive = 2, false
		w:runTickers()
		H.eq(#w.sounds, secret and 0 or 1, "sound when plain only, secret=" .. tostring(secret))
	end
end)

-- DK's probe log (TICK-0156): the spell's own cooldown ends while another
-- cast's global cooldown runs, and the game says isActive true, isOnGCD true.
-- Plain only: isActive and isOnGCD are both true here, so the harness
-- cannot flag one secret without the other. Both pass through Plain().
H.test("ready alerts: an event that shows only the global cooldown left is ready", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Wait(w)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, true
	w:fire("SPELL_UPDATE_COOLDOWN", 403, 403)
	H.eq(#w.sounds, 1, "sound at the event")
	H.eq(Lit(ns, HEROISM), true, "glows")
end)

H.test("ready alerts: the ticker never takes the global cooldown as ready", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	w.cd[HEROISM].isOnGCD = true
	w:runTickers()
	H.eq(#w.sounds, 0, "no sound from the ticker")
end)

H.test("ready alerts: turned off on cooldown, or while it glows, it stops", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	H.eq(ns.SetReadyAlert("Heroism", false), true, "changed")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyAlerts.Heroism, false, "off saved as false (TICK-0181)")
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no sound once off")

	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glows")
	ns.SetReadyAlert("Heroism", false)
	H.eq(Lit(ns, HEROISM), false, "off puts the glow out")
end)

H.test("ready alerts: cast again while it glows puts the glow out", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glows")
	Cast(w, HEROISM)
	H.eq(Lit(ns, HEROISM), false, "used again")
end)

H.test("ready alerts: two spells ready at once both glow", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	ns.SetReadyAlert("Bloodlust", true)
	Cast(w, HEROISM)
	Cast(w, BLOODLUST)
	Wait(w)
	w.cd[HEROISM].isActive, w.cd[BLOODLUST].isActive = false, false
	w:runTickers()
	H.eq(#w.sounds, 2, "two sounds")
	H.eq(Lit(ns, HEROISM) and Lit(ns, BLOODLUST), true, "both glow")
end)

H.test("ready alerts: a spell with charges is ready when every charge is back", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	local charges = { maxCharges = 2, currentCharges = 2, isActive = false }
	w.charges[HEROISM] = charges
	-- One charge used: it recharges, and the spell can still be cast, so
	-- GetSpellCooldown says not active.
	charges.currentCharges, charges.isActive = 1, true
	w:fire("SPELL_UPDATE_CHARGES")
	w:runTickers()
	H.eq(#w.sounds, 0, "a charge left is not the end")
	Wait(w)
	charges.currentCharges, charges.isActive = 2, false
	w:runTickers()
	H.eq(#w.sounds, 1, "every charge back")
end)

-- Review TICK-0157 #1: SPELL_UPDATE_CHARGES is not the place to read
-- isOnGCD; a stale false there would start every ready spell.
H.test("ready alerts: SPELL_UPDATE_CHARGES does not start a spell without charges", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w:fire("SPELL_UPDATE_CHARGES")
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no sound")
end)

-- Review TICK-0157 #2: an interrupted cast locks the school, and the game
-- shows a cooldown on each of its spells. Not seen in game yet.
H.test("ready alerts: a school lockout is not the spell's cooldown", function()
	for _, locked in ipairs({ false, true }) do
		local ns, w = World()
		ns.SetReadyAlert("Heroism", true)
		w.loc[HEROISM] = { isActive = locked, shouldReplaceNormalCooldown = locked }
		Cast(w, HEROISM)
		w.loc[HEROISM] = nil
		Finish(w, HEROISM)
		H.eq(#w.sounds, locked and 0 or 1, "sound when not locked, locked=" .. tostring(locked))
	end
end)

H.test("ready alerts: a secret lockout answer is not a start", function()
	-- A unique value stands for the secret, so isOnGCD's false stays plain.
	local answer = {}
	for _, secret in ipairs({ false, true }) do
		local ns, w = World()
		ns.SetReadyAlert("Heroism", true)
		w.secret[answer] = secret
		w.loc[HEROISM] = { isActive = answer }
		Cast(w, HEROISM)
		w.loc[HEROISM] = nil
		Finish(w, HEROISM)
		H.eq(#w.sounds, secret and 0 or 1, "sound when plain only, secret=" .. tostring(secret))
	end
end)

-- Review TICK-0157 #3: only a glow you can see wakes the HUD.
H.test("ready alerts: a watched spell with no HUD icon rings and does not wake the HUD", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	ns.HUDini.spells = { { spellID = BLOODLUST } }
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(#w.sounds, 1, "the bell rings")
	H.eq((ns.HUDini:ShouldShow()), false, "the HUD stays hidden")
end)

-- pm (ForeverAuras comparison): a spell another spell replaces is watched
-- by the ID the game uses now; the icon may show either ID.
H.test("ready alerts: an override is watched, and its base ID glows and wakes too", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	ns.HUDini.spells = { { spellID = HEROISM } }
	w.override[HEROISM] = OVERRIDE
	w.cd[OVERRIDE] = { isEnabled = true, isActive = false, isOnGCD = false }
	ns.SetReadyAlert("Heroism", true)
	Cast(w, OVERRIDE)
	Finish(w, OVERRIDE)
	H.eq(#w.sounds, 1, "the override's end rings")
	H.eq(Lit(ns, OVERRIDE), true, "the override glows")
	H.eq(ns.HUDini.alertGlow["cooldown_base:" .. OVERRIDE], HEROISM, "the base ID glows")
	H.eq((ns.HUDini:ShouldShow()), true, "an icon with the base ID wakes the HUD")
	w.time = w.time + 5
	w:runTickers()
	H.eq(ns.HUDini.alertGlow["cooldown_base:" .. OVERRIDE], nil, "the base glow goes out too")
end)

-- Review TICK-0157 #6: the override changes while the spell is on cooldown.
H.test("ready alerts: a new override keeps the cooldown, and its end rings", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	w.override[HEROISM] = OVERRIDE
	w.cd[OVERRIDE] = { isEnabled = true, isActive = true, isOnGCD = false }
	w:fire("SPELLS_CHANGED")
	Finish(w, OVERRIDE)
	H.eq(#w.sounds, 1, "the end rings")
end)

-- pm (ForeverAuras comparison): a shared cooldown fires no event of its
-- own; the look one frame later finds it.
H.test("ready alerts: a cooldown that lands after the event is found one frame later", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	w:fire("SPELL_UPDATE_COOLDOWN", 8042, 8042)
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w:runTimers()
	Finish(w, HEROISM)
	H.eq(#w.sounds, 1, "the shared cooldown's end rings")
end)

-- The look one frame later: the event saw only the global cooldown, and
-- the late read misses isOnGCD.
local function LateStart(w, id)
	w.cd[id].isActive, w.cd[id].isOnGCD = true, true
	w:fire("SPELL_UPDATE_COOLDOWN", 403, 403)
	w.cd[id].isOnGCD = false
	w:runTimers()
end

H.test("ready alerts: a cooldown that ends inside a global cooldown makes no sound", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	LateStart(w, HEROISM)
	w.time = w.time + 1.5
	w.cd[HEROISM].isActive = false
	w:runTickers()
	H.eq(#w.sounds, 0, "no sound for a misread global cooldown")
	H.eq(Lit(ns, HEROISM), false, "no glow")
end)

-- Review TICK-0157 round 2 #3: a start seen in the event is real, so a
-- reset soon after it (Cold Snap on Ice Block) rings.
H.test("ready alerts: a reset soon after a cast rings", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	w.time = w.time + 1.5
	w.cd[HEROISM].isActive = false
	w:runTickers()
	H.eq(#w.sounds, 1, "the reset rings")
end)

-- Review TICK-0157 round 2 #1: the late look trusts no isOnGCD for an end.
H.test("ready alerts: the look one frame later does not end a cooldown", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	w.time = w.time + 4
	w:fire("SPELL_UPDATE_COOLDOWN", 403, 403)
	w.cd[HEROISM].isOnGCD = true
	w:runTimers()
	H.eq(#w.sounds, 0, "no bell while the cooldown runs")
	H.eq(Lit(ns, HEROISM), false, "no glow")
end)

-- Review TICK-0157 round 2 #2: a start the late look finds keeps the glow.
H.test("ready alerts: a start found one frame later keeps the glow", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glowing")
	LateStart(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "the glow stays")
	H.eq(ns.ReadyGlowLit(), true, "the HUD stays awake")
end)

-- Review TICK-0157 round 2 #4: an override can change with no SPELLS_CHANGED.
H.test("ready alerts: an override that comes with no SPELLS_CHANGED is found at the next event", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	w.override[HEROISM] = OVERRIDE
	w.cd[OVERRIDE] = { isEnabled = true, isActive = false, isOnGCD = false }
	Cast(w, OVERRIDE)
	Finish(w, OVERRIDE)
	H.eq(#w.sounds, 1, "the override's end rings")
end)

H.test("ready alerts: another spell can be turned on and is offered after the class list", function()
	local ns = World()
	ns.SetReadyAlert("Lightning Shield", true)
	local list = ns.ReadyAlertSpells()
	H.eq(list[#list], "Lightning Shield")
	H.eq(ns.SetReadyAlert("", true), false, "an empty name is refused")
end)

-- D-047 (TICK-0181): a class file can start some alerts on. A saved choice
-- always wins; Off saves false so it does.
local function StartsOn(ns, extra)
	local profile = { readyAlert = { "Heroism", "Bloodlust" }, readyAlertOn = { "Heroism" } }
	for k, v in pairs(extra or {}) do profile[k] = v end
	ns.RegisterClass("SHAMAN", profile)
	ns.RefreshReadyAlerts()
end

H.test("class defaults: a readyAlertOn spell rings with nothing saved; Off saves false and sticks", function()
	local ns, w = World()
	StartsOn(ns)
	H.eq(ns.GetReadyAlert("Heroism"), true, "starts on")
	H.eq(ns.GetReadyAlert("Bloodlust"), false, "not named: off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyAlerts, nil, "nothing saved")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(w.sounds[1], SOUND, "the bell, no option touched")
	H.eq(Lit(ns, HEROISM), true, "and the glow")
	H.eq(ns.SetReadyAlert("Heroism", false), true, "turned off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyAlerts.Heroism, false, "saved as false")
	ns.RefreshReadyAlerts() -- as at a /reload
	H.eq(ns.GetReadyAlert("Heroism"), false, "Off wins over the class file")
	w.sounds = {}
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no bell")
	H.eq(ns.SetReadyAlert("Bloodlust", true), true, "a saved On")
	H.eq(ns.GetReadyAlert("Bloodlust"), true, "wins too")
end)

H.test("class defaults: a readyAlertOn spell you do not know is silent; learned, it starts on", function()
	local ns, w = World()
	w.env.IsPlayerSpell = function(id) return id == BLOODLUST end
	StartsOn(ns)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "not known: no sound")
	w.env.IsPlayerSpell = function(id) return id == HEROISM or id == BLOODLUST end
	w:fire("SPELLS_CHANGED")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(w.sounds[1], SOUND, "learned: the bell")
end)

H.test("class defaults: a readyAlertOn spell outside readyAlert is offered (More spells) when you know it", function()
	local ns, w = World()
	StartsOn(ns, { readyAlertOn = { "Mana Tide Totem" } })
	H.eq(#ns.ReadyAlertSpells(), 2, "not known (another race's spell): not offered")
	NAMES["Mana Tide Totem"] = 16190
	w.env.IsPlayerSpell = function(id) return id == HEROISM or id == BLOODLUST or id == 16190 end
	local list, classCount = ns.ReadyAlertSpells()
	NAMES["Mana Tide Totem"] = nil
	H.eq(classCount, 2, "the class list")
	H.eq(list[3], "Mana Tide Totem", "offered after it")
	H.eq(ns.GetReadyAlert("Mana Tide Totem"), true, "on")
	H.eq(ns.GetReadyAlert("Heroism"), false, "the class list is off")
end)

H.test("class defaults: keepUpSoundOn starts the buff sound on with the default; Off saves false and sticks", function()
	local ns = World()
	H.eq(ns.GetKeepUpSound(), false, "no field: off, as before")
	StartsOn(ns, { keepUpSoundOn = true })
	local db = ns.ClassDB()
	H.eq(db.keepUpSound, nil, "nothing saved")
	H.eq(ns.GetKeepUpSound(), true, "on")
	H.eq(ns.GetKeepUpSoundChoice(), ns.MISSING_SOUND_DEFAULT, "the default sound")
	H.ok(ns.MissingSoundFile() ~= nil, "the game gets a file")
	H.eq(ns.SetKeepUpSound("off"), true, "turned off")
	H.eq(db.keepUpSound, false, "saved as false")
	H.eq(ns.GetKeepUpSound(), false, "Off wins over the class file")
	H.eq(ns.GetKeepUpSoundChoice(), "off")
	H.eq(ns.MissingSoundFile(), nil, "no file")
	ns.SetKeepUpSound("coins")
	H.eq(ns.GetKeepUpSoundChoice(), "coins", "a saved pick wins")
	ns.SetKeepUpSound(true)
	H.eq(ns.GetKeepUpSoundChoice(), "coins", "the old check box on keeps it")
end)

H.test("ready alerts: /hud debug aura lists the watched spells", function()
	local ns, w = World()
	ns.SetReadyAlert("Heroism", true)
	Cast(w, HEROISM)
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	H.ok(table.concat(lines, "\n"):find("Heroism (on cooldown)", 1, true) ~= nil, "report line")
end)

-- TICK-0167 (D-043): the list holds only the game's own sound kits. Each
-- row names its SOUNDKIT constant; the IDs below are the game's
-- (Blizzard_SharedXML/Mainline/SoundKitConstants.lua), so a typo or a file
-- ID fails here. A new sound adds its constant here too.
local SOUNDKIT_IDS = {
	READY_CHECK = 8960, RAID_WARNING = 8959, MAP_PING = 3175, TELL_MESSAGE = 3081,
	RAID_BOSS_EMOTE_WARNING = 12197, ALARM_CLOCK_WARNING_2 = 12867,
	PVP_THROUGH_QUEUE = 8459, LOOT_WINDOW_COIN_SOUND = 120,
}

H.test("alert sounds: every one is a game sound kit, and each key plays its own", function()
	local ns, w = World()
	local rows = {}
	for key, kit, const in H.readFile("Alerts.lua"):gmatch('{ "(%w+)",%s*(%d+),%s*%d+ }, %-%- ([%u_%d]+)') do
		rows[#rows + 1] = key
		H.eq(SOUNDKIT_IDS[const], tonumber(kit), key .. ": the SOUNDKIT ID of " .. const)
		w.sounds = {}
		H.eq(ns.PlayAlertSound(key), tonumber(kit), key .. " plays")
		H.eq(#w.sounds, 1, key .. ": once")
	end
	H.eq(table.concat(rows, " "), table.concat(ns.AlertSounds(), " "), "every row read, in menu order")
	H.ok(#rows >= 2, "a list")
	H.ok(ns.READY_SOUND_DEFAULT ~= ns.MISSING_SOUND_DEFAULT, "the two defaults differ")
	local listed = {}
	for _, key in ipairs(ns.AlertSounds()) do listed[key] = true end
	H.ok(listed[ns.READY_SOUND_DEFAULT] and listed[ns.MISSING_SOUND_DEFAULT], "both defaults are in the list")
	local keys = ns.AlertSounds()
	keys[1] = "changed"
	H.ok(ns.AlertSounds()[1] ~= "changed", "a copy: a caller cannot change the list")
	w.sounds = {}
	H.eq(ns.PlayAlertSound("nope"), 8959, "an unknown key: the raid warning")
end)

-- TICK-0168: the game's buff-end sound takes a sound file, not a kit
-- (C_UnitAuras.AddAuraSound). Each row's third value is its kit's file;
-- the picked sound gives its own, the sound off gives none.
H.test("alert sounds: the buff-missing sound gives the picked row's file", function()
	local ns = World()
	local n = 0
	for key, file in H.readFile("Alerts.lua"):gmatch('{ "(%w+)",%s*%d+,%s*(%d+) }, %-%- [%u_%d]+') do
		n = n + 1
		ns.ClassDB().keepUpSound = key
		H.eq(ns.MissingSoundFile(), tonumber(file), key .. ": its file")
	end
	H.eq(n, #ns.AlertSounds(), "every row has a file")
	ns.ClassDB().keepUpSound = true
	H.eq(ns.MissingSoundFile(), 567397, "on: the default's file (raid warning)")
	ns.ClassDB().keepUpSound = false
	H.eq(ns.MissingSoundFile(), nil, "off: none")
end)
