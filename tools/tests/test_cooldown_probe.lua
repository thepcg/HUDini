-- /hud debug cooldown <spell> (TICK-0156): the probe for the cooldown
-- spike. It logs what the game says about one spell's cooldown, and who
-- saw it change (the event or the poll), and saves the log. It must never
-- print a secret: a secret field prints as the word "secret". What the
-- test bar shows needs DK's play.

local SPELL = 1766

-- A world where spell 1766 is Kick. w.cd is what GetSpellCooldown returns;
-- w.secret holds the values the game hides.
local function World()
	local w = H.world()
	local env = w.env
	w.secret = {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	w.cd = { isEnabled = true, isActive = false, isOnGCD = false, startTime = 100.5, duration = 30.25 }
	local C_Spell = env.C_Spell
	C_Spell.GetSpellCooldown = function(id) if id == SPELL then return w.cd end end
	C_Spell.GetSpellInfo = function(name) if name == "Kick" then return { spellID = SPELL } end end
	C_Spell.GetSpellName = function(id) if id == SPELL then return "Kick" end end
	C_Spell.IsSpellUsable = function() return true, false end
	C_Spell.GetSpellCooldownDuration = function()
		return {
			HasSecretValues = function() return w.secret[w.cd.duration] == true end,
			GetRemainingDuration = function() return w.cd.duration end,
		}
	end
	w:loadAddon()
	return w
end

local function Printed(w, text)
	return H.printed(w, text)
end

-- Two poll ticks POLL_HOLD (1.6 s) apart: the poll logs a change only
-- once the new state has held that long.
local function Poll(w)
	w:runTickers()
	w.time = w.time + 2
	w:runTickers()
end

H.test("cooldown probe: no spell prints how to use it", function()
	local w = World()
	w:slash("/hud debug cooldown")
	H.ok(Printed(w, "/hud debug cooldown <spell name or ID>"), "usage line")
	w:slash("/hud debug cooldown Nothing Such")
	H.ok(Printed(w, "/hud debug cooldown <spell name or ID>"), "usage for an unknown name")
end)

H.test("cooldown probe: a number that is not a known spell starts nothing", function()
	for _, arg in ipairs({ "99999999", "inf" }) do
		local w = World()
		w:slash("/hud debug cooldown " .. arg)
		H.ok(Printed(w, "/hud debug cooldown <spell name or ID>"), "usage line for " .. arg)
		H.ok(not Printed(w, "Cooldown probe on"), "no probe for " .. arg)
	end
end)

H.test("cooldown probe: a number that is not a spell ID starts nothing, even if the game names it", function()
	for _, arg in ipairs({ "1e12", "-1", "1.5", "0" }) do
		local w = World()
		w.env.C_Spell.GetSpellName = function() return "Any" end
		w:slash("/hud debug cooldown " .. arg)
		H.ok(Printed(w, "/hud debug cooldown <spell name or ID>"), "usage line for " .. arg)
		H.ok(not Printed(w, "Cooldown probe on"), "no probe for " .. arg)
		w:slash("/hud debug cooldown stop")
		H.ok(Printed(w, "No cooldown probe is running."), "nothing to stop for " .. arg)
	end
end)

H.test("cooldown probe: plain values print as they are", function()
	local w = World()
	w:slash("/hud debug cooldown Kick")
	H.ok(Printed(w, "Cooldown probe on Kick (spell 1766)"), "start line")
	H.ok(Printed(w, "startTime=100.5 duration=30.25"), "plain start and duration")
	H.ok(Printed(w, "HasSecretValues=false"), "duration object answers")
	H.ok(Printed(w, "remaining=30.25"), "plain remaining time")
end)

H.test("cooldown probe: secret values print as secret, never as a number", function()
	local w = World()
	w.secret[100.5], w.secret[30.25] = true, true
	w:slash("/hud debug cooldown 1766")
	H.ok(Printed(w, "startTime=secret duration=secret"), "secret start and duration")
	H.ok(Printed(w, "HasSecretValues=true"), "duration object says it is secret")
	H.ok(Printed(w, "remaining=secret"), "secret remaining time")
	H.ok(not Printed(w, "100.5") and not Printed(w, "30.25"), "no secret number printed")
end)

H.test("cooldown probe: logs who saw the change, and saves the log on stop", function()
	local w = World()
	w:slash("/hud debug cooldown 1766")
	w.cd.isActive = true
	w:fire("SPELL_UPDATE_COOLDOWN", SPELL, SPELL)
	H.ok(Printed(w, "event: on cooldown false -> true"), "the event saw the start")
	w:runTickers()
	H.ok(not Printed(w, "poll: on cooldown false -> true"), "the poll waits out the global cooldown")
	w.time = w.time + 2
	w:runTickers()
	H.ok(Printed(w, "poll: on cooldown false -> true (first seen at"), "the poll saw the start")
	w.cd.isActive = false
	Poll(w)
	H.ok(Printed(w, "poll: on cooldown true -> false"), "the poll saw the end")
	w:fire("SPELL_UPDATE_COOLDOWN", 99999, 99999)
	H.ok(not Printed(w, "event: on cooldown true -> false"), "another spell's event is not this one")
	w:slash("/hud debug cooldown stop")
	H.ok(Printed(w, "stop: 2 SPELL_UPDATE_COOLDOWN events (1 for this spell, 0 for all spells)"), "event count")
	local report = w.env.HUDiniDB.lastReport
	H.ok(type(report) == "table" and #report > 0, "report saved")
	local joined = table.concat(report, "\n")
	H.ok(joined:find("event: on cooldown false -> true", 1, true) ~= nil, "report has the event line")
	w:slash("/hud debug cooldown stop")
	H.ok(Printed(w, "No cooldown probe is running."), "a second stop says so")
end)

H.test("cooldown probe: the global cooldown alone is not the spell's cooldown", function()
	local w = World()
	w.cd.isActive, w.cd.isOnGCD = true, true
	w:slash("/hud debug cooldown 1766")
	w:fire("SPELL_UPDATE_COOLDOWN", SPELL, SPELL)
	Poll(w)
	H.ok(not Printed(w, "on cooldown false -> true"), "no start logged")
	w.cd.isOnGCD = false
	Poll(w)
	H.ok(Printed(w, "poll: on cooldown false -> true"), "the real cooldown is logged")
end)

H.test("cooldown probe: a global cooldown shorter than the hold is not logged by the poll", function()
	local w = World()
	w:slash("/hud debug cooldown 1766")
	w.cd.isActive = true
	w:runTickers()
	w.time = w.time + 1
	w:runTickers()
	w.cd.isActive = false
	w.time = w.time + 1
	w:runTickers()
	w.time = w.time + 2
	w:runTickers()
	H.ok(not Printed(w, "poll: on cooldown"), "a 1 s flicker is not a change")
end)

-- Review TICK-0156 #4: the guards on isActive, isOnGCD and the event's
-- spell ID. Each runs plain first, then with the same value flagged.
H.test("cooldown probe: a secret isActive is unknown, not a change", function()
	for _, secret in ipairs({ false, true }) do
		local w = World()
		w:slash("/hud debug cooldown 1766")
		w.cd.isActive = true
		w.secret[true] = secret
		w:fire("SPELL_UPDATE_COOLDOWN", SPELL, SPELL)
		H.eq(Printed(w, "event: on cooldown false -> true"), not secret, "change logged when plain only")
	end
end)

H.test("cooldown probe: a secret isOnGCD is unknown, not a change", function()
	-- false is isOnGCD's value here; isActive stays a plain true.
	for _, secret in ipairs({ false, true }) do
		local w = World()
		w:slash("/hud debug cooldown 1766")
		w.cd.isActive = true
		w.secret[false] = secret
		w:fire("SPELL_UPDATE_COOLDOWN", SPELL, SPELL)
		H.eq(Printed(w, "event: on cooldown false -> true"), not secret, "change logged when plain only")
	end
end)

H.test("cooldown probe: a secret spell ID in the event counts as all spells", function()
	for _, secret in ipairs({ false, true }) do
		local w = World()
		w:slash("/hud debug cooldown 1766")
		w.secret[4321] = secret
		w:fire("SPELL_UPDATE_COOLDOWN", 4321, 4321)
		w:slash("/hud debug cooldown stop")
		local want = secret and "(0 for this spell, 1 for all spells)" or "(0 for this spell, 0 for all spells)"
		H.ok(Printed(w, want), "count when secret=" .. tostring(secret))
	end
end)

H.test("cooldown probe: charges are reread on SPELL_UPDATE_CHARGES", function()
	local w = World()
	local charges = { maxCharges = 2, currentCharges = 2, isActive = false }
	w.env.C_Spell.GetSpellCharges = function() return charges end
	w:slash("/hud debug cooldown 1766")
	charges.isActive = true
	w:fire("SPELL_UPDATE_CHARGES")
	H.ok(Printed(w, "charges: on cooldown false -> true"), "charge recharge start")
	w:fire("SPELL_UPDATE_CHARGES")
	charges.isActive = false
	w:fire("SPELL_UPDATE_CHARGES")
	H.ok(Printed(w, "charges: on cooldown true -> false"), "charge recharge end")
end)

H.test("cooldown probe: the test bar sits above other windows near the top of the screen", function()
	local w = World()
	local env, made = w.env, {}
	local real = env.CreateFrame
	env.CreateFrame = function(kind, ...)
		local f = real(kind, ...)
		made[#made + 1] = f
		return f
	end
	w:slash("/hud debug cooldown 1766")
	-- The test bar is the first frame made on the screen itself.
	local bar
	for _, f in ipairs(made) do
		if f.__h.parent == env.UIParent then bar = f break end
	end
	H.ok(bar ~= nil, "the test bar is made")
	H.eq(bar.__h.strata, "DIALOG", "strata")
	local point, to, rel, x, y = bar:GetPoint(1)
	H.eq(point, "TOP", "point")
	H.ok(to == env.UIParent, "anchored to the screen, not the HUD")
	H.eq(rel, "TOP", "relative point")
	H.eq(x, 0, "x")
	H.eq(y, -180, "y")
end)
