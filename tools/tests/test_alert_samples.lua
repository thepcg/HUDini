-- Alert samples for test mode (TICK-0067). ns.ShowAlertSamples(true) shows a
-- fixed sample of every alert that is turned on, with no unit, spell or aura
-- read; the real updates leave the samples up; (false) puts back the real
-- state.

local function World()
	local w = H.world()
	w:loadAddon()
	return w, w.ns, w.env.HUDiniDB
end

-- Every alert icon (CreateAlertIcon gives each an edge and a texture).
local function Icons(w)
	local list = {}
	for _, f in ipairs(w.frames) do
		if f.edge and f.tex then list[#list + 1] = f end
	end
	return list
end

local function Shown(list)
	local n = 0
	for _, f in ipairs(list) do
		if f:IsShown() then n = n + 1 end
	end
	return n
end

-- The pulsing outline on the target cast bar.
local function KickOutline(w)
	for _, f in ipairs(w.frames) do
		if f.edges and f.pulse then return f end
	end
end

local function BaitIcon(w)
	for _, f in ipairs(w.frames) do
		if f:GetText() == "No bait" then return f:GetParent() end
	end
end

-- The icons inside the right end of the target health bar.
local function PurgeIcons(w)
	local bar, list = w.ns.GetBar("targethealth"), {}
	for _, f in ipairs(Icons(w)) do
		local point, to, rel = f:GetPoint(1)
		if point == "RIGHT" and to == bar and rel == "RIGHT" then list[#list + 1] = f end
	end
	return list
end

-- Make the kick outline the way a target cast would, so it can be checked.
local function MakeOutline(ns)
	ns.OnTargetCast(nil, true)
end

H.test("with no target and no auras, every alert sample shows, and goes again", function()
	local w, ns = World()
	MakeOutline(ns)
	ns.ShowAlertSamples(true)
	-- Your buff, keep-up, No bait, the target's buff, two purge icons.
	H.eq(Shown(Icons(w)), 6, "alert icons shown")
	H.eq(Shown(PurgeIcons(w)), 2, "purge icons shown")
	H.eq(BaitIcon(w):IsShown(), true, "No bait shown")
	H.eq(KickOutline(w):IsShown(), true, "the kick outline shows")
	H.ok(ns.powerTint ~= nil, "the power bar has the dispel tint")

	ns.ShowAlertSamples(false)
	H.eq(Shown(Icons(w)), 0, "alert icons after test mode")
	H.eq(KickOutline(w):IsShown(), false, "the kick outline after test mode")
	H.eq(ns.powerTint, nil, "the dispel tint after test mode")
end)

H.test("your buff's sample sits after the keep-up sample, left of the bar", function()
	local w, ns = World()
	ns.ShowAlertSamples(true)
	local bar = ns.GetBar("health")
	local keepUp, own
	for _, f in ipairs(Icons(w)) do
		local point, to, rel = f:GetPoint(1)
		if point == "RIGHT" and to == bar and rel == "LEFT" then keepUp = f end
	end
	for _, f in ipairs(Icons(w)) do
		local point, to = f:GetPoint(1)
		if point == "RIGHT" and to == keepUp then own = f end
	end
	H.ok(keepUp ~= nil and keepUp:IsShown(), "the keep-up sample by the health bar")
	H.ok(own ~= nil and own:IsShown(), "your buff's sample after it")
	H.ok(keepUp ~= own, "two icons")
end)

H.test("while the samples are up, the real updates leave them up", function()
	local w, ns = World()
	MakeOutline(ns)
	ns.ShowAlertSamples(true)
	w:fire("UNIT_AURA", "player")
	w:fire("UNIT_AURA", "target")
	w:fire("PLAYER_TARGET_CHANGED")
	w:fire("PLAYER_EQUIPMENT_CHANGED", 16)
	w:fire("SPELLS_CHANGED")
	ns.UpdateAlerts()
	ns.UpdateOwnBuffIcon()
	ns.OnTargetCast(nil, true) -- a target cast bar refresh with no cast
	w:runTickers()
	w:runTimers()
	H.eq(Shown(Icons(w)), 6, "alert icons still shown")
	H.eq(KickOutline(w):IsShown(), true, "the kick outline still shows")
	H.ok(ns.powerTint ~= nil, "the dispel tint stays")
end)

H.test("an alert that is turned off shows no sample", function()
	local w, ns, db = World()
	db.warnNoBait, db.showPurgeable, db.warnDispel, db.glowOnKickable = false, false, false, false
	MakeOutline(ns)
	ns.ShowAlertSamples(true)
	H.eq(BaitIcon(w):IsShown(), false, "No bait, turned off")
	H.eq(Shown(PurgeIcons(w)), 0, "purge icons, turned off")
	H.eq(ns.powerTint, nil, "dispel tint, turned off")
	H.eq(KickOutline(w):IsShown(), false, "kick outline, turned off")
	H.eq(Shown(Icons(w)), 3, "the other three still show")
	db.showHealth = false
	ns.ShowAlertSamples(true)
	H.eq(Shown(Icons(w)), 1, "with the health bar off, only the target's buff")
	db.warnTargetBuff = false
	ns.ShowAlertSamples(true)
	H.eq(Shown(Icons(w)), 0, "the target's buff, turned off")
	db.warnTargetBuff, db.showTargetHealth = true, false
	ns.ShowAlertSamples(true)
	H.eq(Shown(Icons(w)), 0, "the target's buff, with the target health bar off")
end)

H.test("real purge icons past the two samples go when the samples show", function()
	local w, ns = World()
	local PURGE = 370
	ns.ClassDB().purge = PURGE
	w.env.IsPlayerSpell = function(id) return id == PURGE end
	w.env.UnitCanAttack = function() return true end
	w.env.C_UnitAuras.GetAuraDataByIndex = function(unit, i, filter)
		if unit == "target" and filter == "HELPFUL" and i <= 3 then
			return { dispelName = "Magic", icon = 100 + i }
		end
	end
	w.hasTarget = true
	ns.UpdateAlerts()
	H.eq(Shown(PurgeIcons(w)), 3, "three real purge icons first")
	ns.ShowAlertSamples(true)
	H.eq(Shown(PurgeIcons(w)), 2, "only the two purge samples")
end)

H.test("the samples read no unit, spell or aura", function()
	local w, ns = World()
	local reads = 0
	local function Read() reads = reads + 1 end
	local env = w.env
	for _, name in ipairs({ "UnitExists", "UnitIsPlayer", "UnitCanAttack", "UnitCanAssist",
			"UnitIsDeadOrGhost", "GetInventoryItemLink", "IsPlayerSpell", "GetWeaponEnchantInfo" }) do
		env[name] = Read
	end
	env.C_UnitAuras.GetAuraDataByIndex = Read
	env.C_UnitAuras.GetAuraDataBySpellName = Read
	env.C_Spell.GetSpellTexture = Read
	env.C_Spell.GetSpellInfo = Read
	ns.ShowAlertSamples(true)
	H.eq(reads, 0, "unit, spell or aura reads")
	H.eq(Shown(Icons(w)), 6, "and every sample shows")
end)

H.test("the bait and target buff tickers leave the samples up", function()
	local w, ns = World()
	local function Live()
		local n = 0
		for _, t in ipairs(w.tickers) do if not t.cancelled then n = n + 1 end end
		return n
	end
	local idle = Live()
	w:holdItem(16, 6256, 2, 20, "Fishing Pole")
	w.env.UnitIsPlayer = function() return true end
	w.hasTarget = true
	ns.UpdateAlerts()
	H.eq(Live(), idle + 2, "both alert tickers run")
	ns.ShowAlertSamples(true)
	w:runTickers()
	H.eq(BaitIcon(w):IsShown(), true, "No bait after the bait ticker")
	H.eq(Shown(Icons(w)), 6, "every sample after the tickers")
end)
