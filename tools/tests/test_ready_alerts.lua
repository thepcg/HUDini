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
-- db, if given, is the saved table at login.
local function World(db)
	local w = H.world()
	if db then w.env.HUDiniDB = db end
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

-- A saved sound as text: a choice (TICK-0232) as "key@volume", any other
-- value as it is.
local function Saved(v)
	if type(v) == "table" then return tostring(v.key) .. "@" .. tostring(v.volume) end
	return v
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
	H.eq(db.classes.SHAMAN.readyGlow.Heroism, true, "saved per class: the glow")
	H.eq(Saved(db.classes.SHAMAN.readySounds.Heroism), "readyCheck@100", "and the default sound, saved as its key")
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
	H.eq(ns.GetCooldownSound("Heroism"), "readyCheck", "the class's sound plays for no spell (TICK-0203)")
	ns.SetCooldownSound("Heroism", "mapPing")
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
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	ns.SetCooldownSound("Heroism", "mapPing")
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
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyGlow.Heroism, false, "off saved as false (TICK-0181)")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readySounds.Heroism, false, "the sound too")
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
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyGlow, nil, "nothing saved")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(w.sounds[1], SOUND, "the bell, no option touched")
	H.eq(Lit(ns, HEROISM), true, "and the glow")
	H.eq(ns.SetReadyAlert("Heroism", false), true, "turned off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyGlow.Heroism, false, "saved as false")
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
local VOICE_COUNT = 24 -- HUDini's voice sounds (TICK-0230, TICK-0244), after the game's
local SOUNDKIT_IDS = {
	READY_CHECK = 8960, RAID_WARNING = 8959, MAP_PING = 3175, TELL_MESSAGE = 3081,
	RAID_BOSS_EMOTE_WARNING = 12197, ALARM_CLOCK_WARNING_2 = 12867,
	PVP_THROUGH_QUEUE = 8459, LOOT_WINDOW_COIN_SOUND = 120,
}

H.test("alert sounds: every one is a game sound kit, and each key plays its own", function()
	local ns, w = World()
	local rows = {}
	for key, kit, const in H.readFile("Sounds.lua"):gmatch('{ "(%w+)",%s*(%d+),%s*%d+ }, %-%- ([%u_%d]+)') do
		rows[#rows + 1] = key
		H.eq(SOUNDKIT_IDS[const], tonumber(kit), key .. ": the SOUNDKIT ID of " .. const)
		w.sounds = {}
		H.eq(ns.PlayAlertSound(key), tonumber(kit), key .. " plays")
		H.eq(#w.sounds, 1, key .. ": once")
	end
	local game = {}
	for i = 1, #rows do game[i] = ns.AlertSounds()[i] end
	H.eq(table.concat(rows, " "), table.concat(game, " "), "every game row read, first, in menu order")
	H.eq(#ns.AlertSounds(), #rows + VOICE_COUNT, "then the voice sounds")
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
	for key, file in H.readFile("Sounds.lua"):gmatch('{ "(%w+)",%s*%d+,%s*(%d+) }, %-%- [%u_%d]+') do
		n = n + 1
		ns.ClassDB().keepUpSound = key
		H.eq(ns.MissingSoundFile(), tonumber(file), key .. ": its file")
	end
	H.eq(n + VOICE_COUNT, #ns.AlertSounds(), "every game row has a file")
	ns.ClassDB().keepUpSound = true
	H.eq(ns.MissingSoundFile(), 567397, "on: the default's file (raid warning)")
	ns.ClassDB().keepUpSound = false
	H.eq(ns.MissingSoundFile(), nil, "off: none")
end)

-- TICK-0230 (D-050): DK's 16 voice clips, 24 since TICK-0244, after the game's sounds, played
-- by path with PlaySoundFile on the Master channel.
local VOICES = { "Blocked", "Buff", "Combat", "Curse", "Disease", "Dodge", "Enrage", "Execute",
	"FadingSoon", "Gotem", "Health", "Kick", "Magic", "Mana", "Parried", "Poison", "Purge", "Ready",
	"Safe", "Shield", "Shock", "Silenced", "Stab", "Warning" }
local function VoicePath(name) return "Interface\\AddOns\\HUDini\\Media\\Sounds\\" .. name .. ".ogg" end

-- w.files logs each PlaySoundFile as "path@channel"; w.noFile[path]: the
-- game cannot play it (a file it has not found yet).
local function Voiced(w)
	w.files, w.noFile = {}, {}
	w.env.PlaySoundFile = function(path, channel)
		table.insert(w.files, path .. "@" .. tostring(channel))
		if not w.noFile[path] then return true, 1 end
	end
end

H.test("voice sounds: each plays its file on the Master channel, after the game's sounds", function()
	local ns, w = World()
	Voiced(w)
	local keys = ns.AlertSounds()
	for i, name in ipairs(VOICES) do
		local key = "voice" .. name
		H.eq(keys[#keys - #VOICES + i], key, key .. ": in menu order, after the game's")
		H.ok(ns.IsAlertSound(key), key .. ": a sound of the list")
		w.files, w.sounds = {}, {}
		H.eq(ns.PlayAlertSound(key), VoicePath(name), key .. " plays its file")
		H.eq(table.concat(w.files, " "), VoicePath(name) .. "@Master", key .. ": once, on Master")
		H.eq(#w.sounds, 0, key .. ": no game sound")
		H.eq(H.readFile("Media/Sounds/" .. name .. ".ogg") ~= nil, true, name .. ".ogg is in the addon")
	end
end)

H.test("voice sounds: a file the game cannot play falls back to the default, then the raid warning", function()
	local ns, w = World()
	Voiced(w)
	w.noFile[VoicePath("Kick")] = true
	H.eq(ns.PlayAlertSound("voiceKick", "readyCheck"), SOUND, "the default")
	H.eq(table.concat(w.sounds, " "), tostring(SOUND), "one game sound")
	w.sounds = {}
	w.env.PlaySound = function(kit) table.insert(w.sounds, kit) if kit == 8959 then return true end end
	H.eq(ns.PlayAlertSound("voiceKick", "readyCheck"), 8959, "then the raid warning")
	H.eq(table.concat(w.sounds, " "), SOUND .. " 8959")
	w.env.PlaySoundFile = nil -- a client with no PlaySoundFile
	H.eq(ns.PlayAlertSound("voiceStab", "readyCheck"), 8959, "no error")
end)

H.test("voice sounds: a cooldown, ready and buff-missing pick is kept after a reload", function()
	local ns, w = World()
	Voiced(w)
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	H.eq(ns.SetCooldownSound("Heroism", "voiceKick"), true, "the cooldown's sound")
	H.eq(ns.SetReadySound("voiceSafe"), true, "the class's ready sound")
	H.eq(ns.SetKeepUpSound("voiceBuff"), true, "the buff-missing sound")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.files, " "), VoicePath("Kick") .. "@Master", "the cooldown says its voice")
	local ns2 = World(w.env.HUDiniDB)
	H.eq(ns2.GetCooldownSound("Heroism"), "voiceKick", "the cooldown's pick, after the load")
	H.eq(ns2.GetReadySound(), "voiceSafe", "the ready pick")
	H.eq(ns2.GetKeepUpSoundChoice(), "voiceBuff", "the buff-missing pick")
	H.eq(ns2.MissingSoundFile(), VoicePath("Buff"), "the game's buff-end sound gets the file path")
end)

-- TICK-0203 (D-048): each cooldown has its own glow and its own sound, each
-- on its own switch. The timer bar is TimerBars.lua's (test_timer_bars).
local PING, WHISPER = 3175, 3081

H.test("cooldown parts: the glow alone glows with no sound", function()
	local ns, w = World()
	ns.HUDini.spells = { { spellID = HEROISM } }
	H.eq(ns.SetCooldownGlow("Heroism", true), true, "changed")
	H.eq(ns.SetCooldownGlow("Heroism", true), false, "same again: no change")
	H.eq(ns.GetCooldownSound("Heroism"), "off", "the sound stays off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyGlow.Heroism, true, "saved per class")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(#w.sounds, 0, "no sound")
	H.eq(Lit(ns, HEROISM), true, "glows")
end)

H.test("cooldown parts: the sound alone sounds with no glow and wakes nothing", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	ns.HUDini.spells = { { spellID = HEROISM } }
	H.eq(ns.SetCooldownSound("Heroism", "mapPing"), true, "changed")
	H.eq(ns.SetCooldownSound("Heroism", "mapPing"), false, "same again: no change")
	H.eq(ns.GetCooldownGlow("Heroism"), false, "the glow stays off")
	H.eq(Saved(db.classes.SHAMAN.readySounds.Heroism), "mapPing@100", "saved per class")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), tostring(PING), "its sound")
	H.eq(Lit(ns, HEROISM), false, "no glow")
	H.eq((ns.HUDini:ShouldShow()), false, "no glow, no wake")
end)

H.test("cooldown parts: each spell plays its own sound", function()
	local ns, w = World()
	ns.SetCooldownSound("Heroism", "mapPing")
	ns.SetCooldownSound("Bloodlust", "whisper")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	Cast(w, BLOODLUST)
	Finish(w, BLOODLUST)
	H.eq(table.concat(w.sounds, " "), PING .. " " .. WHISPER, "two spells, two sounds")
end)

H.test("cooldown parts: a sound key not in the list is refused; off saves false", function()
	local ns, w = World()
	H.eq(ns.SetCooldownSound("Heroism", "bellStrike"), false, "not in the list")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readySounds, nil, "nothing saved")
	ns.SetCooldownSound("Heroism", "whisper")
	H.eq(ns.SetCooldownSound("Heroism", "off"), true, "off")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readySounds.Heroism, false, "saved as false")
	H.eq(ns.GetCooldownSound("Heroism"), "off")
	w.env.HUDiniDB.classes.SHAMAN.readySounds.Heroism = "bellStrike" -- a key a later build dropped
	H.eq(ns.GetCooldownSound("Heroism"), "readyCheck", "plays the default sound")
	H.eq(ns.SetCooldownSound("", "whisper"), false, "an empty name is refused")
end)

H.test("cooldown parts: in a fight the glow holds until you cast the spell", function()
	local ns, w = World()
	local db = w.env.HUDiniDB
	db.hideWhenIdle, db.locked, db.showWhenPower = true, true, false
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetCooldownGlow("Heroism", true)
	w.combat = true
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glows")
	H.eq(ns.ReadyGlowLit(), true, "wakes the HUD at first")
	w.time = w.time + 30
	w:runTickers()
	H.eq(Lit(ns, HEROISM), true, "still glows after 30 s in the fight")
	H.eq(ns.ReadyGlowLit(), false, "but wakes the HUD only for its first 5 s")
	Cast(w, HEROISM)
	H.eq(Lit(ns, HEROISM), false, "the cast puts it out")
end)

H.test("cooldown parts: the end of the fight puts a held glow out", function()
	local ns, w = World()
	ns.SetCooldownGlow("Heroism", true)
	w.combat = true
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glows")
	w.combat = false
	w:fire("PLAYER_REGEN_ENABLED")
	H.eq(Lit(ns, HEROISM), false, "out")
end)

H.test("cooldown parts: out of a fight the glow lasts 5 s", function()
	local ns, w = World()
	ns.SetCooldownGlow("Heroism", true)
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	w.combat = true -- a pull after it went on: it stays a 5 s glow
	w.time = w.time + 5
	w:runTickers()
	H.eq(Lit(ns, HEROISM), false, "out after 5 s")
end)

H.test("cooldown parts: the glow turned off while lit goes out; the sound stays", function()
	local ns, w = World()
	ns.SetCooldownGlow("Heroism", true)
	ns.SetCooldownSound("Heroism", "whisper")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glows")
	ns.SetCooldownGlow("Heroism", false)
	H.eq(Lit(ns, HEROISM), false, "out")
	w.sounds = {}
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), tostring(WHISPER), "the sound still plays")
end)

H.test("cooldown parts: a class file start gives the glow and the default sound, no timer", function()
	local ns = World()
	StartsOn(ns)
	H.eq(ns.GetCooldownSound("Heroism"), "readyCheck", "no old sound: the default")
	ns.SetReadySound("mapPing")
	H.eq(ns.GetCooldownGlow("Heroism"), true, "glow")
	-- Review round 3, finding 1: a player who picked a Bell sound and never
	-- touched this spell keeps hearing that sound.
	H.eq(ns.GetCooldownSound("Heroism"), "mapPing", "your old sound, while nothing is saved for it")
	H.eq(ns.GetTimerBar("Heroism"), false, "no timer bar")
	H.eq(ns.GetCooldownGlow("Bloodlust"), false, "not named: off")
	H.eq(ns.GetCooldownSound("Bloodlust"), "off")
end)

H.test("cooldown parts: the setup switch turns glow and sound together, and puts back the last sound", function()
	local ns, w = World()
	ns.SetTimerBar("Heroism", true)
	H.eq(ns.SetReadyAlert("Heroism", true), true, "on")
	H.eq(ns.GetCooldownGlow("Heroism"), true, "glow on")
	H.eq(ns.GetCooldownSound("Heroism"), "readyCheck", "the default sound")
	ns.SetCooldownSound("Heroism", "whisper")
	H.eq(ns.SetReadyAlert("Heroism", false), true, "off")
	H.eq(ns.GetCooldownGlow("Heroism") or ns.GetCooldownSound("Heroism") ~= "off", false, "both off")
	H.eq(ns.GetTimerBar("Heroism"), true, "the timer bar stays")
	H.eq(ns.SetReadyAlert("Heroism", true), true, "on again")
	H.eq(ns.GetCooldownSound("Heroism"), "whisper", "the last sound comes back")
	H.eq(ns.SetReadyAlert("Heroism", true), false, "on again: no change")
	ns.SetCooldownGlow("Heroism", false)
	H.eq(ns.GetReadyAlert("Heroism"), true, "a sound alone counts as on")
	H.eq(w.env.HUDiniDB.classes.SHAMAN.readyGlow.Heroism, false)
end)

H.test("cooldown parts: a spell with a part saved on is offered and kept", function()
	local ns = World()
	ns.SetCooldownSound("Lightning Shield", "whisper")
	ns.SetCooldownGlow("Earth Shield", true)
	ns.SetTimerBar("Water Shield", true)
	local list, classCount = ns.CooldownSpells()
	local extra = {}
	for i = classCount + 1, #list do extra[#extra + 1] = list[i] end
	H.eq(list[1], "Heroism", "the class file's list first")
	H.eq(table.concat(extra, ","), "Earth Shield,Lightning Shield,Water Shield", "then the saved ones, A to Z")
	H.eq(#ns.ReadyAlertSpells(), #list, "the old name gives the same")
	H.eq(ns.CooldownSaved("Lightning Shield"), true, "a sound")
	H.eq(ns.CooldownSaved("Earth Shield"), true, "a glow")
	H.eq(ns.CooldownSaved("Water Shield"), true, "a timer bar")
	H.eq(ns.CooldownSaved("Heroism"), false, "nothing saved")
	ns.SetCooldownSound("Lightning Shield", "off")
	H.eq(ns.CooldownSaved("Lightning Shield"), false, "a sound saved off")
end)

-- A table as text, keys sorted, to compare two states.
local function Dump(v)
	if type(v) ~= "table" then return type(v) == "string" and ("%q"):format(v) or tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = {}
	for _, k in ipairs(keys) do out[#out + 1] = Dump(k) .. "=" .. Dump(v[k]) end
	return "{" .. table.concat(out, ",") .. "}"
end

-- The migration (D-048): before TICK-0203, readyAlerts[name] gave the glow
-- and one shared sound (readySound) together; timerBars was its own table.
H.test("cooldown migration: bell, bar and both carry over at login, for every class", function()
	local db = {
		classes = {
			SHAMAN = {
				readySound = "mapPing",
				readyAlerts = { Heroism = true, Bloodlust = false, ["Mana Tide Totem"] = true },
				timerBars = { ["Mana Tide Totem"] = true, ["Earth Shield"] = true },
			},
			MAGE = { readyAlerts = { Evocation = true } },
			ROGUE = { readySound = "bellStrike", readyAlerts = { Vanish = true } },
		},
	}
	local ns, w = World(db)
	local sh = w.env.HUDiniDB.classes.SHAMAN
	H.eq(sh.readyAlerts, nil, "the old table is gone")
	H.eq(sh.readyGlow.Heroism, true, "bell: glow on")
	H.eq(Saved(sh.readySounds.Heroism), "mapPing@100", "bell: the old shared sound, saved as its key")
	H.eq(ns.GetCooldownSound("Heroism"), "mapPing")
	H.eq(sh.readyGlow.Bloodlust, false, "off: glow off")
	H.eq(sh.readySounds.Bloodlust, false, "off: sound off")
	H.eq(sh.readyGlow["Earth Shield"], nil, "bar: no glow")
	H.eq(sh.readySounds["Earth Shield"], nil, "bar: no sound")
	H.eq(ns.GetTimerBar("Earth Shield"), true, "bar: the timer bar")
	H.eq(ns.GetCooldownGlow("Mana Tide Totem") and ns.GetTimerBar("Mana Tide Totem"), true, "both: glow and timer")
	H.eq(ns.GetCooldownSound("Mana Tide Totem"), "mapPing", "both: and the sound")
	local mage = w.env.HUDiniDB.classes.MAGE
	H.eq(mage.readyAlerts, nil, "another class too")
	H.eq(Saved(mage.readySounds.Evocation), "readyCheck@100", "another class with no class sound: the default")
	H.eq(Saved(w.env.HUDiniDB.classes.ROGUE.readySounds.Vanish), "readyCheck@100", "a class sound that left the list: the default")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), tostring(PING), "Heroism rings as before")
	H.eq(Lit(ns, HEROISM), true, "and glows as before")
end)

H.test("cooldown migration: a part already saved wins, and a second run changes nothing", function()
	local ns = World()
	local db = {
		classes = {
			SHAMAN = {
				readyAlerts = { Heroism = true, Bloodlust = true, [""] = true, Odd = "yes" },
				readyGlow = { Heroism = false },
				readySounds = { Bloodlust = "whisper" },
			},
			BROKEN = "not a table",
		},
	}
	ns.MigrateCooldowns(db)
	local sh = db.classes.SHAMAN
	H.eq(sh.readyGlow.Heroism, false, "the saved glow wins")
	H.eq(sh.readySounds.Heroism, "readyCheck", "the sound fills in: the default, as a key")
	H.eq(sh.readySounds.Bloodlust, "whisper", "the saved sound wins")
	H.eq(sh.readyGlow.Bloodlust, true, "the glow fills in")
	H.eq(sh.readyGlow[""], nil, "an empty name is dropped")
	H.eq(sh.readyGlow.Odd, nil, "a value that is not true or false is dropped")
	local before = Dump(db)
	ns.MigrateCooldowns(db)
	H.eq(Dump(db), before, "the second run changes nothing")
	ns.MigrateCooldowns(nil)
	ns.MigrateCooldowns({})
	ns.MigrateCooldowns({ classes = { MAGE = { readyAlerts = "junk" } } })
end)

-- Review round 2 (TICK-0203), finding 1, the designer's call (a): the page
-- has no Bell sound row, so the class's sound changes no saved spell. Each
-- spell saves its own key; a migrated spell keeps the key it rang with.
H.test("cooldown parts: the class's sound changes no saved spell; each saves its own key", function()
	local db = { classes = { SHAMAN = { readySound = "mapPing", readyAlerts = { Heroism = true } } } }
	local ns, w = World(db)
	local saved = w.env.HUDiniDB.classes.SHAMAN
	ns.SetReadyAlert("Bloodlust", true)
	H.eq(Saved(saved.readySounds.Bloodlust), "readyCheck@100", "a setup box spell: the default, as a key")
	H.eq(ns.SetReadySound("whisper"), true, "the class's sound changes (no row on the page)")
	H.eq(ns.GetCooldownSound("Heroism"), "mapPing", "a carried-over spell keeps the key it rang with")
	H.eq(ns.GetCooldownSound("Bloodlust"), "readyCheck", "a setup box spell does not follow it")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), tostring(PING), "it rings its own key")
	ns.SetCooldownSound("Bloodlust", "mapPing")
	ns.SetReadyAlert("Bloodlust", false)
	H.eq(Saved(saved.readySoundLast.Bloodlust), "mapPing@100", "off keeps the key")
	ns.SetReadyAlert("Bloodlust", true)
	H.eq(Saved(saved.readySounds.Bloodlust), "mapPing@100", "off and on: the last key")
	saved.readySoundLast.Bloodlust = nil
	ns.SetReadyAlert("Bloodlust", false)
	saved.readySoundLast.Bloodlust = nil
	ns.SetReadyAlert("Bloodlust", true)
	H.eq(Saved(saved.readySounds.Bloodlust), "readyCheck@100", "no last key: the default, never true")
	for name, sound in pairs(saved.readySounds) do
		H.ok(sound ~= true, name .. ": no true saved")
	end
	saved.readySounds.Bloodlust = "bellStrike" -- a key a later build dropped
	H.eq(ns.GetCooldownSound("Bloodlust"), "readyCheck", "a key not in the list: the default, not the class's")
	saved.readySounds.Bloodlust = 5
	H.eq(ns.GetCooldownSound("Bloodlust"), "off", "a number saved: off")
	saved.readySounds.Bloodlust = {}
	H.eq(ns.GetCooldownSound("Bloodlust"), "off", "a table saved: off")
	saved.readySounds.Bloodlust = false
	saved.readySoundLast.Bloodlust = "bellStrike"
	ns.SetReadyAlert("Bloodlust", true)
	H.eq(Saved(saved.readySounds.Bloodlust), "readyCheck@100", "a last key not in the list: the default is saved, not the dead key")
end)

-- The same finding: a saved file from the build before the fix (DK's own)
-- holds sounds of true, which played the class's sound. At login each
-- becomes that key, so it rings as before and the page names it.
H.test("cooldown migration: a sound of true saved by the build before the fix becomes its key", function()
	local db = {
		classes = {
			SHAMAN = {
				readySound = "mapPing",
				readyGlow = { Heroism = true },
				readySounds = { Heroism = true, Bloodlust = false, ["Mana Tide Totem"] = "whisper" },
				readySoundLast = { ["Lightning Shield"] = true, ["Earth Shield"] = "coins" },
			},
			MAGE = { readySounds = { Evocation = true } },
			ROGUE = { readySound = "bellStrike", readySoundLast = { Vanish = true } },
		},
	}
	local ns, w = World(db)
	local sh = w.env.HUDiniDB.classes.SHAMAN
	H.eq(Saved(sh.readySounds.Heroism), "mapPing@100", "true: the class's sound, as its key")
	H.eq(sh.readySounds.Bloodlust, false, "off stays off")
	H.eq(Saved(sh.readySounds["Mana Tide Totem"]), "whisper@100", "a key stays")
	H.eq(Saved(sh.readySoundLast["Lightning Shield"]), "mapPing@100", "the last sound too")
	H.eq(Saved(sh.readySoundLast["Earth Shield"]), "coins@100", "a last key stays")
	H.eq(Saved(w.env.HUDiniDB.classes.MAGE.readySounds.Evocation), "readyCheck@100", "no class sound: the default")
	H.eq(Saved(w.env.HUDiniDB.classes.ROGUE.readySoundLast.Vanish), "readyCheck@100", "a class sound not in the list: the default")
	ns.HUDini.spells = { { spellID = HEROISM } }
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), tostring(PING), "Heroism rings as before")
	ns.SetReadySound("whisper")
	H.eq(ns.GetCooldownSound("Heroism"), "mapPing", "and no longer follows the class's sound")
	local before = Dump(w.env.HUDiniDB.classes)
	ns.MigrateCooldowns(w.env.HUDiniDB)
	H.eq(Dump(w.env.HUDiniDB.classes), before, "a second run changes nothing")
end)

-- Finding 2: a cast whose cooldown start reads secret still ends a held glow.
H.test("cooldown parts: in a fight the cast's own event puts a held glow out", function()
	local ns, w = World()
	ns.SetCooldownGlow("Heroism", true)
	w.combat = true
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(Lit(ns, HEROISM), true, "glows")
	w.cd[HEROISM].isActive, w.cd[HEROISM].isOnGCD = true, false
	w.secret[false] = true
	w:fire("SPELL_UPDATE_COOLDOWN", HEROISM, HEROISM)
	w.secret[false] = nil
	H.eq(Lit(ns, HEROISM), true, "a start with a secret isOnGCD does not end it")
	w.secret[HEROISM] = true
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", HEROISM)
	w.secret[HEROISM] = nil
	H.eq(Lit(ns, HEROISM), true, "nor a cast with a secret ID")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", BLOODLUST)
	H.eq(Lit(ns, HEROISM), true, "nor another spell's cast")
	w:fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", HEROISM)
	H.eq(Lit(ns, HEROISM), false, "its own cast does")
end)

H.test("cooldown parts: a held glow goes out after 60 s at most", function()
	local ns, w = World()
	ns.SetCooldownGlow("Heroism", true)
	w.combat = true
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	w.time = w.time + 59
	w:runTickers()
	H.eq(Lit(ns, HEROISM), true, "still on at 59 s")
	w.time = w.time + 1
	w:runTickers()
	H.eq(Lit(ns, HEROISM), false, "out at 60 s")
end)

-- TICK-0232 (D-051): each sound is saved with its volume (Sounds.lua). A
-- voice at a lower volume plays its quieter copy, <Name>_NN.ogg.
local function QuietPath(name, volume)
	return (VoicePath(name):gsub("%.ogg$", "_" .. volume .. ".ogg"))
end

H.test("sound volume: a cooldown plays at its volume, and a new pick keeps the volume", function()
	local ns, w = World()
	Voiced(w)
	local saved = w.env.HUDiniDB.classes.SHAMAN
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	H.eq(ns.SetCooldownSound("Heroism", { key = "voiceKick", volume = 50 }), true, "a choice")
	H.eq(Saved(saved.readySounds.Heroism), "voiceKick@50", "saved with its volume")
	H.eq(ns.SetCooldownSound("Heroism", "voiceSafe"), true, "a key from the list")
	H.eq(Saved(saved.readySounds.Heroism), "voiceSafe@50", "the volume stays")
	H.eq(ns.SetCooldownSound("Heroism", { key = "voiceSafe", volume = 50 }), false, "same again: no change")
	H.eq(ns.SetCooldownSound("Heroism", { key = "nope", volume = 50 }), false, "not in the list: no change")
	H.eq(ns.GetCooldownSound("Heroism"), "voiceSafe", "the key, for the old menu")
	H.eq(Saved(ns.GetCooldownSoundValue("Heroism")), "voiceSafe@50", "the choice, for the picker")
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.files, " "), QuietPath("Safe", 50) .. "@Master", "the quieter copy plays")
	ns.SetReadyAlert("Heroism", false)
	H.eq(Saved(saved.readySoundLast.Heroism), "voiceSafe@50", "off keeps the choice")
	ns.SetReadyAlert("Heroism", true)
	H.eq(Saved(saved.readySounds.Heroism), "voiceSafe@50", "on again: the same sound and volume")
end)

H.test("sound volume: the buff-missing sound keeps its volume; the game's buff-end sound gets the quieter copy", function()
	local ns, w = World()
	local db = w.env.HUDiniDB.classes.SHAMAN
	H.eq(ns.SetKeepUpSound({ key = "voiceBuff", volume = 25 }), true, "a choice")
	H.eq(Saved(db.keepUpSound), "voiceBuff@25", "saved with its volume")
	H.eq(ns.MissingSoundFile(), QuietPath("Buff", 25), "the quieter copy for the game")
	H.eq(ns.SetKeepUpSound("voiceKick"), true, "a key from the list")
	H.eq(ns.MissingSoundFile(), QuietPath("Kick", 25), "the volume stays")
	H.eq(ns.SetKeepUpSound({ key = "raidWarning", volume = 100 }), true, "the default at full volume")
	H.eq(db.keepUpSound, true, "saves as true, as before")
	H.eq(ns.MissingSoundFile(), 567397, "the raid warning's file")
	H.eq(ns.SetKeepUpSound({ key = "raidWarning", volume = 50 }), true, "the default, quieter")
	H.eq(Saved(db.keepUpSound), "raidWarning@50", "saved as a choice")
	H.eq(ns.MissingSoundFile(), 567397, "a game sound's one file (full volume: the limit in the ticket)")
	H.eq(ns.SetKeepUpSound({ key = "nope" }), false, "not in the list: no change")
	H.eq(Saved(ns.GetKeepUpSoundValue()), "raidWarning@50", "the choice, for the picker")
	ns.SetKeepUpSound("off")
	H.eq(ns.GetKeepUpSoundValue(), false, "off")
end)

H.test("sound migration at login: an old key becomes a choice at full volume and sounds as before", function()
	local db = {
		classes = {
			SHAMAN = {
				keepUpSound = "coins",
				readySounds = { Heroism = "mapPing", Bloodlust = false },
				readySoundLast = { Bloodlust = "whisper" },
			},
			MAGE = { readySounds = { Evocation = "voiceKick" } },
		},
	}
	local ns, w = World(db)
	local sh = w.env.HUDiniDB.classes.SHAMAN
	H.eq(Saved(sh.keepUpSound), "coins@100", "the buff-missing sound")
	H.eq(Saved(sh.readySounds.Heroism), "mapPing@100", "a cooldown sound")
	H.eq(sh.readySounds.Bloodlust, false, "off stays off")
	H.eq(Saved(sh.readySoundLast.Bloodlust), "whisper@100", "the last sound")
	H.eq(Saved(w.env.HUDiniDB.classes.MAGE.readySounds.Evocation), "voiceKick@100", "every class")
	H.eq(ns.GetCooldownSound("Heroism"), "mapPing")
	ns.HUDini.spells = { { spellID = HEROISM } }
	Cast(w, HEROISM)
	Finish(w, HEROISM)
	H.eq(table.concat(w.sounds, " "), tostring(PING), "it rings as before")
end)

H.test("sound volume: a volume change alone saves", function()
	local ns, w = World()
	local saved = w.env.HUDiniDB.classes.SHAMAN
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	H.eq(ns.SetCooldownSound("Heroism", { key = "mapPing", volume = 50 }), true, "cooldown at 50")
	H.eq(ns.SetCooldownSound("Heroism", { key = "mapPing", volume = 25 }), true, "cooldown: the slider moves")
	H.eq(Saved(saved.readySounds.Heroism), "mapPing@25", "cooldown: the new volume is saved")
	H.eq(ns.SetKeepUpSound({ key = "coins", volume = 50 }), true, "buff missing at 50")
	H.eq(ns.SetKeepUpSound({ key = "coins", volume = 25 }), true, "buff missing: the slider moves")
	H.eq(Saved(saved.keepUpSound), "coins@25", "buff missing: the new volume is saved")
end)

H.test("sound volume: off, then a key, keeps the volume", function()
	local ns, w = World()
	local saved = w.env.HUDiniDB.classes.SHAMAN
	ns.HUDini.spells = { { spellID = HEROISM } }
	ns.SetReadyAlert("Heroism", true)
	ns.SetCooldownSound("Heroism", { key = "voiceKick", volume = 25 })
	ns.SetCooldownSound("Heroism", "off")
	H.eq(ns.SetCooldownSound("Heroism", "voiceKick"), true, "cooldown: on again")
	H.eq(Saved(saved.readySounds.Heroism), "voiceKick@25", "cooldown: the volume from before off")
	ns.SetKeepUpSound({ key = "voiceKick", volume = 25 })
	ns.SetKeepUpSound("off")
	H.eq(ns.GetKeepUpSoundValue(), false, "buff missing: off")
	H.eq(ns.SetKeepUpSound("voiceKick"), true, "buff missing: on again")
	H.eq(Saved(saved.keepUpSound), "voiceKick@25", "buff missing: the volume from before off")
end)
