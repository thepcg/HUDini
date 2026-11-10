-- TICK-0060: interrupt may be one spell or a list. The outline uses the
-- first spell you know, off cooldown, that you can cast now (stance, form,
-- shield, rage).

-- A Warrior who knows both, with usable[name] saying what the game says.
-- usableAnswer, when given, replaces IsSpellUsable.
local function Warrior(usable, ready, usableAnswer)
	local NAMES = { [1] = "Pummel", [2] = "Shield Bash" }
	local w = H.world()
	w.class, w.className = "WARRIOR", "Warrior"
	local env = w.env
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end
	env.C_Spell.GetSpellCooldown = function(id)
		return { isActive = not (ready == nil or ready[NAMES[id]]) }
	end
	env.C_Spell.IsSpellUsable = usableAnswer
		or function(id) return usable[NAMES[id]], false end
	return w:loadAddon(), w
end

H.test("the first spell not usable, the second is picked", function()
	local ns = Warrior({ ["Pummel"] = false, ["Shield Bash"] = true })
	H.eq(ns.ReadyInterrupt(), "Shield Bash", "Defensive Stance with a shield")
end)

H.test("the first spell usable is picked first", function()
	local ns = Warrior({ ["Pummel"] = true, ["Shield Bash"] = false })
	H.eq(ns.ReadyInterrupt(), "Pummel", "Berserker Stance")
end)

H.test("no spell usable, no interrupt", function()
	local ns = Warrior({ ["Pummel"] = false, ["Shield Bash"] = false })
	H.eq(ns.ReadyInterrupt(), nil, "Berserker Stance with no rage")
end)

H.test("a usable spell on cooldown is skipped", function()
	local ns = Warrior({ ["Pummel"] = true, ["Shield Bash"] = true },
		{ ["Pummel"] = false, ["Shield Bash"] = true })
	H.eq(ns.ReadyInterrupt(), "Shield Bash", "Pummel on cooldown")
end)

H.test("an unreadable usable answer counts as usable", function()
	local ns = Warrior({})
	H.eq(ns.ReadyInterrupt(), "Pummel", "IsSpellUsable gives nil")
end)

H.test("a string interrupt still works, and /hud interrupt sets one", function()
	local ns = Warrior({ ["Pummel"] = false, ["Shield Bash"] = true })
	ns.ClassDB().interrupt = "Shield Bash"
	H.eq(ns.ReadyInterrupt(), "Shield Bash", "your own choice")
	ns.ClassDB().interrupt = "Pummel"
	H.eq(ns.ReadyInterrupt(), nil, "Pummel alone, not usable")
end)

H.test("/hud report names the spell it would use", function()
	local ns = Warrior({ ["Pummel"] = false, ["Shield Bash"] = true })
	local lines = {}
	ns.ReportAlerts(function(line) lines[#lines + 1] = line end)
	local found
	for _, line in ipairs(lines) do
		if line:find("Interrupt spell ready", 1, true) then found = line end
	end
	H.ok(found and found:find("(Shield Bash)", 1, true), "report: " .. tostring(found))
end)

-- A list saved by /hud interrupt, which TICK-0019 took out (the Your
-- class page shows it: test_class_picks.lua).
H.test("a saved interrupt list still works", function()
	local ns = Warrior({ ["Pummel"] = false, ["Shield Bash"] = true })
	ns.ClassDB().interrupt = { "Pummel", "Shield Bash" }
	H.eq(ns.ReadyInterrupt(), "Shield Bash", "the first one ready")
end)

-- A secret "false" from IsSpellUsable. The game hides the answer, so it must
-- count as usable, and it must go through ns.Plain: compared as it is, a
-- real secret throws. Only the answer of IsSpellUsable is secret here, not
-- the cooldown's isActive = false, so the fake marks the next false after
-- IsSpellUsable as secret, until the next cooldown read.
H.test("a secret usable answer counts as usable", function()
	local hidden = false
	local w = H.world()
	w.env.issecretvalue = function(v) return hidden and v == false end
	local env = w.env
	local NAMES = { [1] = "Pummel", [2] = "Shield Bash" }
	w.class, w.className = "WARRIOR", "Warrior"
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end
	env.C_Spell.GetSpellCooldown = function()
		hidden = false
		return { isActive = false }
	end
	env.C_Spell.IsSpellUsable = function()
		hidden = true
		return false, false
	end
	local ns = w:loadAddon()
	H.eq(ns.ReadyInterrupt(), "Pummel", "secret false")
end)

-- A secret isActive = false: off cooldown, the answer that would make the
-- interrupt ready. The game hides it, so the interrupt is not ready; only
-- Plain keeps it so. The fake marks the next false after GetSpellCooldown
-- as secret, until IsSpellUsable answers.
H.test("a secret off-cooldown answer is not ready", function()
	local hidden, hide = false, false
	local w = H.world()
	w.env.issecretvalue = function(v) return hidden and v == false end
	local env = w.env
	local NAMES = { [1] = "Pummel", [2] = "Shield Bash" }
	w.class, w.className = "WARRIOR", "Warrior"
	env.C_Spell.GetSpellName = function(id) return NAMES[id] end
	env.C_Spell.GetSpellInfo = function(name)
		for id, n in pairs(NAMES) do
			if n == name then return { spellID = id } end
		end
	end
	env.IsPlayerSpell = function(id) return NAMES[id] ~= nil end
	env.C_Spell.GetSpellCooldown = function()
		hidden = hide
		return { isActive = false }
	end
	env.C_Spell.IsSpellUsable = function()
		hidden = false
		return true, false
	end
	local ns = w:loadAddon()
	H.eq(ns.ReadyInterrupt(), "Pummel", "plain: off cooldown, ready")
	hide = true
	H.eq(ns.ReadyInterrupt(), nil, "secret: not ready")
end)

H.test("an IsSpellUsable that throws counts as usable", function()
	local ns = Warrior({}, nil, function() error("blocked") end)
	H.eq(ns.ReadyInterrupt(), "Pummel", "error in the call")
end)
