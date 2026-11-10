-- Bars.lua when the game hides an answer (TICK-0112). Each test first runs
-- the value that WOULD change what HUDini draws, plain, and checks that it
-- does. Then it flags that same value secret and checks that HUDini draws
-- what it draws for no answer, and throws nothing. So a missing Plain() or
-- IsSecret() fails the test (the method of TICK-0110, tools/tests/harness
-- .lua). Each flagged value is used for nothing else in its test.

-- A logged-in world. w.secret: the values issecretvalue calls secret.
-- Set the world's stubs in setup(w, env), before the addon loads.
local function World(setup)
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	if setup then setup(w, env) end
	local ns = w:loadAddon()
	return w, ns
end

local function Near(got, want, msg)
	H.ok(type(got) == "table", (msg or "") .. ": no color")
	for i = 1, 3 do
		H.ok(math.abs(got[i] - want[i]) < 1e-6,
			("%s: got %s,%s,%s"):format(msg or "", tostring(got[1]), tostring(got[2]), tostring(got[3])))
	end
end

--------------------------------------------------------------------------------
-- Your power type (DisplayPower)
--------------------------------------------------------------------------------

H.test("a secret power type of yours reads as mana", function()
	local w, ns = World(function(w, env)
		env.UnitPowerType = function(u) if u == "player" then return w.ptype, w.token end return 0, "MANA" end
	end)
	w.ptype, w.token = 3, "ENERGY"
	local ptype, token = ns.DisplayPower()
	H.eq(ptype, 3, "plain: energy's number")
	H.eq(token, "ENERGY", "plain: energy's token")

	w.secret[3] = true
	ptype, token = ns.DisplayPower()
	H.eq(ptype, 0, "secret number: mana's")
	H.eq(token, "ENERGY", "the plain token stays")

	w.secret[3], w.secret.ENERGY = nil, true
	ptype, token = ns.DisplayPower()
	H.eq(ptype, 3, "the plain number stays")
	H.eq(token, "MANA", "secret token: mana")
end)

--------------------------------------------------------------------------------
-- The target's health color (TargetReactionColor)
--------------------------------------------------------------------------------

-- The color the target's health bar is told, after a target change.
local function ReactionWorld()
	local w, ns = World(function(w, env)
		env.UnitIsTapDenied = function() return w.tapped end
		env.UnitReaction = function() return w.reaction end
		env.UnitCanAttack = function() return w.attack end
	end)
	w.hasTarget, w.tapped, w.reaction, w.attack = true, false, 5, false
	local bar = ns.GetBar("targethealth")
	rawset(bar, "SetStatusBarColor", function(_, r, g, b) w.color = { r, g, b } end)
	local function Color()
		w.color = nil
		w:fire("PLAYER_TARGET_CHANGED")
		return w.color
	end
	return w, ns, Color
end

H.test("a secret tapped answer is not drawn as tapped", function()
	local w, ns, Color = ReactionWorld()
	w.tapped = "tagged"            -- truthy, and used for nothing else
	Near(Color(), ns.BarColor("tapped"), "plain: tapped")
	w.secret.tagged = true
	Near(Color(), ns.BarColor("friendly"), "secret: the reaction's color")
end)

H.test("a secret reaction falls back to the attack answer", function()
	local w, ns, Color = ReactionWorld()
	-- The bar starts hostile and skips a color it already shows: draw
	-- friendly first, so the hostile color is told again.
	Near(Color(), ns.BarColor("friendly"), "plain 5: friendly")
	w.reaction = 2
	Near(Color(), ns.BarColor("hostile"), "plain: 2 is hostile")
	w.secret[2] = true
	Near(Color(), ns.BarColor("friendly"), "secret: UnitCanAttack's false, friendly")
end)

H.test("a secret attack answer, with no reaction, draws hostile", function()
	local w, ns, Color = ReactionWorld()
	w.reaction = nil
	Near(Color(), ns.BarColor("friendly"), "plain false: friendly")
	w.secret[false] = true
	Near(Color(), ns.BarColor("hostile"), "secret false: the default, hostile")
end)

--------------------------------------------------------------------------------
-- Your resource bar's pips (ResourcePips)
--------------------------------------------------------------------------------

H.test("a secret maximum of combo points counts 5 pips", function()
	-- The pips split the bar with ticks; /hud debug names their count.
	local w, ns = World(function(w, env)
		w.class = "ROGUE"
		env.Enum.PowerType.ComboPoints = 4
		env.UnitPowerMax = function(u, t)
			if u == "player" and t == 4 then return w.pips end
			return 100
		end
	end)
	local function Pips()
		local lines = {}
		ns.ReportBars(function(line) lines[#lines + 1] = line end)
		return lines[#lines]
	end
	w.pips = 7
	H.ok(Pips():find("ComboPoints max 7", 1, true), "plain: the game's own maximum")
	w.secret[7] = true
	H.ok(Pips():find("ComboPoints max 5", 1, true), "secret: 5")
end)

--------------------------------------------------------------------------------
-- The target's power (UpdateTargetPower)
--------------------------------------------------------------------------------

-- The target's power bar: UnitPower and UnitPowerMax say which type they
-- were asked for, so a test can see which type HUDini asked.
local function TargetPowerWorld()
	local w, ns = World(function(w, env)
		env.UnitPowerType = function(u) if u == "target" then return w.ptype, w.token end return 0, "MANA" end
		env.UnitPower = function(u, t) if u == "target" then return 10 + (t or 0) end return 50 end
		env.UnitPowerMax = function(u, t)
			if u == "target" then return w.most or (100 + (t or 0)) end
			return 100
		end
	end)
	w.hasTarget, w.ptype, w.token = true, 0, "MANA"
	local power = ns.GetBar("targetpower")
	local function Update()
		w:fire("PLAYER_TARGET_CHANGED")
		return power
	end
	return w, ns, Update
end

H.test("a secret target power type asks for mana", function()
	local w, _, Update = TargetPowerWorld()
	local mana = Update().shownColor
	w.ptype, w.token = 3, "ENERGY"
	local power = Update()
	H.eq(power.__h.value, 13, "plain: energy's value")
	H.eq(power.__h.max, 103, "plain: energy's maximum")
	local energy = power.shownColor
	H.ok(energy ~= mana, "plain: energy's color")

	w.secret[3] = true
	power = Update()
	H.eq(power.__h.value, 10, "secret number: mana's value")
	H.eq(power.__h.max, 100, "secret number: mana's maximum")
	H.eq(power.shownColor, energy, "the plain token keeps its color")

	w.secret[3], w.secret.ENERGY = nil, true
	power = Update()
	H.eq(power.__h.value, 13, "the plain number stays")
	H.eq(power.shownColor, mana, "secret token: mana's color")
end)

-- Its own bar since TICK-0126: it stays, as yours does at 0 rage, so the
-- target's cast keeps its place.
H.test("only a plain maximum of 0 empties the target's power bar", function()
	local w, _, Update = TargetPowerWorld()
	w.most = 0
	local power = Update()
	H.eq(power.__h.shown, true, "plain 0: the bar stays")
	H.eq(power.__h.value, 0, "plain 0: empty")
	H.eq(power.__h.max, 1, "plain 0: no 0 maximum on the bar")
	H.eq(power.powerShown, false, "plain 0: no fill, so no number")
	w.secret[0] = true
	power = Update()
	H.eq(power.__h.shown, true, "secret: shown, the bar takes the value")
	H.eq(power.__h.max, 0, "the secret maximum goes to the bar as it came")
	H.eq(power.powerShown, true, "secret: the game draws what it has")
end)

--------------------------------------------------------------------------------
-- The target's text (NpcTitle, PlayerInfo, the name, the creature type)
--------------------------------------------------------------------------------

local function TextWorld()
	local w, ns = World(function(w, env)
		env.UnitIsPlayer = function(u) return u == "player" or (u == "target" and w.targetIsPlayer) or false end
		env.UnitName = function(u) return u == "player" and "Tester" or w.first end
		env.UnitFullName = function(u)
			if u == "target" then return w.first, w.last end
			return "Tester", "Realm"
		end
		env.UnitClass = function(u)
			if u == "target" then return w.tclass, w.tfile end
			return "Mage", "MAGE"
		end
		env.GetGuildInfo = function(u) if u == "target" then return w.guild end end
		env.UnitCanAttack = function() return w.attack end
		env.UnitCreatureType = function() return w.kind end
		env.C_TooltipInfo = { GetUnit = function()
			return { lines = { { leftText = w.first }, { leftText = w.title } } }
		end }
	end)
	w.hasTarget, w.first, w.attack = true, "Mira", false
	local bar = ns.GetBar("targethealth")
	local function Change() w:fire("PLAYER_TARGET_CHANGED") end
	return w, bar, Change
end

H.test("a secret NPC title is not shown", function()
	local w, bar, Change = TextWorld()
	w.title = "Innkeeper"
	Change()
	H.eq(bar.info:GetText(), "<Innkeeper>", "plain: the title")
	w.secret.Innkeeper = true
	Change()
	H.eq(bar.info:GetText(), "", "secret: no title")
end)

H.test("a secret guild is not shown", function()
	local w, bar, Change = TextWorld()
	w.targetIsPlayer, w.last, w.guild = true, "Stormrage", "Night Watch"
	Change()
	H.eq(bar.info:GetText(), "<Night Watch>", "plain: the guild")
	w.secret["Night Watch"] = true
	Change()
	H.eq(bar.info:GetText(), "", "secret: no guild")
end)

H.test("a secret class name is not shown, and a secret class token draws no color", function()
	local w, bar, Change = TextWorld()
	w.targetIsPlayer, w.last = true, "Stormrage"
	w.tclass, w.tfile = "Warrior", "WARRIOR"
	Change()
	H.eq(bar.info:GetText(), "|cffffffffWarrior|r", "plain: the class in its color")

	w.secret.Warrior = true
	Change()
	H.eq(bar.info:GetText(), "", "secret name: no class")

	w.secret.Warrior, w.secret.WARRIOR = nil, true
	Change()
	H.eq(bar.info:GetText(), "Warrior", "secret token: the name, no color")
end)

H.test("a secret first or last name is passed on alone, never joined", function()
	local w, bar, Change = TextWorld()
	w.targetIsPlayer, w.last = true, "Stormrage"
	Change()
	H.eq(bar.name:GetText(), "Mira Stormrage", "plain: both names")

	w.secret.Mira = true
	Change()
	H.eq(bar.name:GetText(), "Mira", "secret first name: it alone, as it came")

	w.secret.Mira, w.secret.Stormrage = nil, true
	Change()
	H.eq(bar.name:GetText(), "Mira", "secret last name: the first alone")
end)

H.test("a secret creature type is not shown", function()
	local w, bar, Change = TextWorld()
	w.attack, w.kind = true, "Beast"
	Change()
	H.eq(bar.info:GetText(), "Beast", "plain: the type")
	w.secret.Beast = true
	Change()
	H.eq(bar.info:GetText(), "", "secret: no type")
end)

--------------------------------------------------------------------------------
-- /hud debug aura (ProbeAura)
--------------------------------------------------------------------------------

H.test("a secret stack count is reported as secret", function()
	local w, ns = World(function(w, env)
		env.C_UnitAuras.GetAuraDataBySpellName = function() return { applications = w.stacks } end
	end)
	local real = ns.ClassValue
	ns.ClassValue = function(key)
		if key == "resource" then return { aura = "Test Buff", max = 5 } end
		return real(key)
	end
	local function Report()
		local lines = {}
		ns.ProbeAura(function(line) lines[#lines + 1] = line end)
		return lines[#lines]
	end
	w.stacks = 3
	H.ok(Report():find("Stacks: 3", 1, true), "plain: the count")
	w.secret[3] = true
	H.ok(Report():find("Stacks: secret", 1, true), "secret: the word secret")
end)
