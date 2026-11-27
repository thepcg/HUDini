-- The purge alert for an enrage-only purge (TICK-0217): a Hunter's
-- Tranquilizing Shot takes an Enrage only. The game lists what your group
-- can remove with the filter HELPFUL|RAID_PLAYER_DISPELLABLE, enrages on
-- enemies too, and picks them in a fight when the aura is hidden. Alone,
-- every aura in that list is yours to take; in a group, only one that
-- plainly names its type an Enrage.

local Classes = assert(loadstring(H.readFile("tools/tests/classes_fixture.lua")))()

local FILTER = "HELPFUL|RAID_PLAYER_DISPELLABLE"
local TRANQ, TRANQ_ID, TRANQ_ICON = "Tranquilizing Shot", 19801, 132323

-- A level 60 Hunter with Tranquilizing Shot (unless known is false) and a
-- hostile target. w.auras[unit .. filter]: the auras in slot order.
-- w.secret[v]: the game hides v. w.party, w.raid: what UnitExists says for
-- party1 and raid1 (false when nil).
local function World(known)
	local w = Classes.Use(H.world())
	local env = w.env
	w.class, w.className = "HUNTER", "HUNTER"
	w.secret, w.auras = {}, {}
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		local list = w.auras[unit .. (filter or "")]
		return list and list[i]
	end
	if known ~= false then
		local info = env.C_Spell.GetSpellInfo
		env.C_Spell.GetSpellInfo = function(n)
			if n == TRANQ or n == TRANQ_ID then return { spellID = TRANQ_ID, name = TRANQ } end
			return info and info(n)
		end
		local isKnown = env.IsPlayerSpell
		env.IsPlayerSpell = function(i) return i == TRANQ_ID or (isKnown and isKnown(i)) or false end
	end
	env.C_Spell.GetSpellTexture = function(id) if id == TRANQ_ID then return TRANQ_ICON end end
	env.UnitCanAttack = function() return true end
	local exists = env.UnitExists
	env.UnitExists = function(unit)
		if unit == "party1" then return w.party or false end
		if unit == "raid1" then return w.raid or false end
		return exists(unit)
	end
	local ns = w:loadAddon()
	ns.RegisterClass("HUNTER", { purge = { spell = TRANQ, enrage = true } })
	w.hasTarget = true
	return w, ns
end

-- The purge icons on the target bar that show, right to left.
local function PurgeIcons(w)
	local bar, out = w.ns.GetBar("targethealth"), {}
	for _, f in ipairs(w.frames) do
		local point, to, rel = f:GetPoint(1)
		if f:GetParent() == bar and f.tex and point == "RIGHT" and to == bar and rel == "RIGHT" and f:IsShown() then
			out[#out + 1] = f
		end
	end
	return out
end

-- An aura the game hides: a secret table that throws if HUDini opens it.
local function Hidden(w)
	local aura = setmetatable({}, { __index = function(_, k) error("opened a hidden aura: " .. tostring(k)) end })
	w.secret[aura] = true
	return aura
end

-- The texture the first purge icon draws at the next look.
local function Drawn(w)
	local icon = PurgeIcons(w)[1]
	if not icon then return nil end
	local drawn
	rawset(icon.tex, "SetTexture", function(_, t) drawn = t end)
	w.ns.UpdateAlerts()
	return drawn
end

H.test("alone: a plain Enrage on the target shows the purge icon", function()
	local w, ns = World()
	w.auras["target" .. FILTER] = { { dispelName = "", icon = 136224 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 1, "one icon")
	H.eq(Drawn(w), 136224, "the Enrage's own icon")
	w.auras["target" .. FILTER] = nil
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "the Enrage ends: gone")
end)

H.test("alone: a hidden Enrage shows Tranquilizing Shot's icon and is never opened", function()
	local w, ns = World()
	w.auras["target" .. FILTER] = { { dispelName = "", icon = 136224 } }
	ns.UpdateAlerts()
	w.auras["target" .. FILTER] = { Hidden(w) }
	H.eq(Drawn(w), TRANQ_ICON, "hidden: your purge's icon")
	H.eq(#PurgeIcons(w), 1, "still one icon")
end)

H.test("alone: a readable buff of another type does not count", function()
	local w, ns = World()
	w.auras["target" .. FILTER] = { { dispelName = "Magic", icon = 1 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "in case the game's list holds more than enrages")
	w.auras["target" .. FILTER] = { { icon = 2 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 1, "no type name: counts alone")
	w.secret["Magic"] = true
	w.auras["target" .. FILTER] = { { dispelName = "Magic", icon = 3 } }
	ns.UpdateAlerts()
	w.secret["Magic"] = nil
	H.eq(#PurgeIcons(w), 1, "a hidden type name: counts alone, blind")
end)

H.test("in a raid with no party, the group rule", function()
	local w, ns = World()
	w.raid = true
	w.auras["target" .. FILTER] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "raid1 there: a hidden aura shows nothing")
end)

H.test("a hidden answer to \"is party1 there\" counts as a group", function()
	local w, ns = World()
	local hidden = {}
	w.secret[hidden] = true
	w.party = hidden
	w.auras["target" .. FILTER] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "the quiet rule")
end)

H.test("joining a group looks again", function()
	local w, ns = World()
	w.auras["target" .. FILTER] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 1, "alone")
	w.party = true
	w:fire("GROUP_ROSTER_UPDATE")
	H.eq(#PurgeIcons(w), 0, "in a party now, with no other look")
end)

H.test("the game's other buffs on the target are not asked for", function()
	local w, ns = World()
	w.auras["targetHELPFUL"] = { { dispelName = "Magic", icon = 1 }, { dispelName = "", icon = 2 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "only the game's removable list counts")
end)

H.test("in a group: only an aura that plainly names an Enrage counts", function()
	local w, ns = World()
	w.party = true
	w.auras["target" .. FILTER] = { { dispelName = "Magic", icon = 1 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "a priest's magic buff")
	w.auras["target" .. FILTER] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "hidden: it can be the priest's")
	w.auras["target" .. FILTER] = { { dispelName = "", icon = 2 }, { dispelName = "Enrage", icon = 3 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 2, "an empty type name and \"Enrage\"")
	w.secret[""] = true
	w.auras["target" .. FILTER] = { { dispelName = "", icon = 2 } }
	ns.UpdateAlerts()
	w.secret[""] = nil
	H.eq(#PurgeIcons(w), 0, "a hidden type name")
end)

H.test("no icon before you learn Tranquilizing Shot", function()
	local w, ns = World(false)
	w.auras["target" .. FILTER] = { { dispelName = "", icon = 136224 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "not known")
end)

H.test("the purge sound plays for an Enrage", function()
	local w, ns = World()
	local heard
	ns.PlaySoundChoice = function(saved, default)
		local c = ns.SoundChoice(saved, default)
		heard = c and c.key
		return heard
	end
	ns.SetClassAlertSound("soundPurge", "voiceShield")
	w.auras["target" .. FILTER] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(heard, "voiceShield", "hidden, alone")
	-- On, with the alert's own sound: Voice: Enrage (TICK-0244).
	ns.SetClassAlertSound("soundPurge", true)
	w.auras["target" .. FILTER] = nil
	ns.UpdateAlerts()
	heard = nil
	w.auras["target" .. FILTER] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(heard, "voiceEnrage", "the enrage purge's own sound")
end)

H.test("a magic purge never opens a hidden buff", function()
	local w, ns = World()
	-- The same spell as a plain purge: it takes magic buffs, from HELPFUL.
	ns.RegisterClass("HUNTER", { purge = TRANQ })
	w.auras["targetHELPFUL"] = { { dispelName = "Magic", icon = 1 } }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 1, "plain magic: one icon")
	w.auras["targetHELPFUL"] = { Hidden(w) }
	ns.UpdateAlerts()
	H.eq(#PurgeIcons(w), 0, "hidden: none, and never read")
end)
