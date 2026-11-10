--[[--------------------------------------------------------------------------
	HUDini - Alerts

	Four class signals, three for everyone, and one for your race. The spells behind the class
	signals come from the class profile, by name (Classes.lua), and only
	spells you know count.

	1. Interrupt. A pulsing outline around the target cast bar while your
	   interrupt is ready and the cast can be interrupted. The class file may
	   name a list (Shield Bash, Pummel): the first one you can cast now
	   counts. Two conditions on opposite sides of the secret wall:
	     - "my interrupt is off cooldown" is PLAIN. 12.0.1 made isActive on the
	       cooldown table a non-secret boolean, exactly for this.
	     - "this cast is interruptible" is SECRET.
	   So the frame is shown by plain logic, and each edge's alpha comes from
	   the secret through Region:SetAlphaFromBoolean. The pulse animates the
	   frame. Alpha multiplies down the parent chain, which is how you AND a
	   plain fact with a hidden one.

	2. Keep-up buff. In a fight with none of your class's keep-up buffs on, the
	   one to cast shows as an icon left of your health bar.

	3. Dispel. While a debuff you can dispel is on you, the power bar takes the
	   debuff type's colour. The "HARMFUL|RAID" filter is the game's own "you
	   can dispel this", and whether a slot holds an aura at all stays plain in
	   combat. The type is only read when the aura is readable; when it is not,
	   a class that dispels one type still gets that type's colour.

	4. Purgeable buffs. Your target's buffs you could take off, drawn at the end
	   of its health bar. Deciding "purgeable" needs the aura's fields, so this
	   only works while the target's buffs are readable: out of combat, or buffs
	   Blizzard leaves visible. An unreadable buff is never guessed at.

	5. No bait, for every class. A fishing pole in hand with no bait on it
	   shows "No bait" and a bait icon left of the health bar.

	6. Target needs your buff, for every class. Out of combat, with a friendly
	   player targeted, the first long buff of yours they lack shows left of
	   their health bar, dimmed while they are out of range. Your buffs are
	   the ones HUDini learned (/hud buffs, Auras.lua) that you can cast on
	   someone else, on your bars or not. Reading their buffs needs their
	   names, which combat hides, so in a fight it stays away.

	7. Your buff is off, for every class. A long buff you keep up (/hud buffs)
	   with none of it on you shows left of your health bar, in and out of
	   combat. Auras.lua picks it (ns.missingBuffID). In a fight the keep-up
	   icon (2) can show too, next to the bar; this one moves out past it.

	The sides (D-027): left of a health bar is what is missing, to cast or
	fix (2, 5, 6, 7). Right of your health bar is for the debuffs on you.

	8. Your race's ability can help (TICK-0099). While a debuff it removes
	   is on you and it is ready, its icon on the HUD glows with the proc
	   glow: Stoneform for a poison, disease or bleed. The race data is
	   ns.RACIALS (Classes.lua). The debuff type must be plain: a type the
	   game hides in a fight lights nothing. No icon on the HUD, no glow.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Plain    = ns.Plain
local IsSecret = ns.IsSecret

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- True when your pet out now knows the spell (a Felhunter's Spell Lock).
-- IsSpellKnown(id, true) asks the pet's spellbook.
local function PetKnows(id)
	local IsSpellKnown = _G.IsSpellKnown
	if not IsSpellKnown then return false end
	local ok, known = pcall(IsSpellKnown, id, true)
	return ok and Plain(known) == true
end

-- Enum.SpellBookItemType. A FutureSpell is one the pet has not learned
-- yet. A PetAction has no spellID: its actionID is a petActionID with the
-- spell ID in the low 24 bits (warcraft.wiki.gg, GetSpellBookItemInfo).
local function ItemType(key, fallback)
	local t = Enum and Enum.SpellBookItemType
	return t and t[key] or fallback
end

-- The spell ID of one pet spellbook entry. nil when it is not learned;
-- nil, true when the game hides what it is.
local function ReadPetItem(info)
	local itemType = Plain(info.itemType)
	if itemType == nil then return nil, true end
	if itemType == ItemType("FutureSpell", 2) then return nil end
	local id = Plain(info.spellID)
	if id == nil and ns.IsSecret(info.spellID) then return nil, true end
	if id == nil and itemType == ItemType("PetAction", 3) then
		local action = Plain(info.actionID)
		if type(action) ~= "number" then return nil, true end
		id = action % 0x1000000
	end
	if type(id) == "number" and id > 0 then return id end
	return nil
end

local function ReadName(info) return info.name end

-- A pet spell by name, from the pet's spellbook: the game may not find a
-- pet spell's ID by name. nil with no pet out. The answer is kept for each
-- name until the pet or its spells change (petCache is cleared on those
-- events), but only when the walk could read the whole book: a book not
-- loaded yet, or hidden in combat, is asked again next time.
local petCache = {}

-- The spell ID, or nil. A second value true: the book could not be read.
local function WalkPetBook(name)
	local book = _G.C_SpellBook
	local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
	if not (book and book.HasPetSpells and book.GetSpellBookItemInfo and bank) then return nil, true end
	local ok, count = pcall(book.HasPetSpells)
	count = ok and Plain(count) or nil
	if type(count) ~= "number" then return nil, true end
	local unsure = false
	for i = 1, count do
		local okInfo, info = pcall(book.GetSpellBookItemInfo, i, bank)
		if not (okInfo and type(info) == "table") then
			unsure = true
		else
			local okName, itemName = pcall(ReadName, info)
			itemName = okName and Plain(itemName) or nil
			if itemName == nil then
				unsure = true
			elseif itemName == name then
				local okID, id, hidden = pcall(ReadPetItem, info)
				if okID and id then return id end
				if not okID or hidden then unsure = true end
			end
		end
	end
	return nil, unsure
end

local function PetSpellID(name)
	local cached = petCache[name]
	if cached ~= nil then return cached or nil end
	local id, unsure = WalkPetBook(name)
	if id or not unsure then petCache[name] = id or false end
	return id
end

-- The ID of a spell you or your pet know, by name or ID, or nil. Any pet
-- counts, a mind-controlled mob too: you can cast its spells from the pet
-- bar while you control it.
local function Known(spell)
	local id = ns.SpellID(spell)
	if id and IsPlayerSpell and IsPlayerSpell(id) then return id end
	if id and PetKnows(id) then return id end
	if type(spell) == "string" and spell ~= "" then return PetSpellID(spell) end
	return nil
end

-- Plain. 12.0.1: "cooldown APIs now return isEnabled and maxCharges as
-- non-secrets, and a new non-secret isActive boolean which is set to true if
-- the UI should render a cooldown display."
-- true off cooldown, false on it, nil when the game does not say.
local function OffCooldown(id)
	if not id then return nil end
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or type(info) ~= "table" then return nil end
	local active = Plain(info.isActive)
	if active == nil then return nil end
	return active == false
end

-- False only when the game plainly says you cannot cast it now: wrong
-- stance or form, no shield, no rage. An answer the game will not give
-- counts as usable, so the outline does what it did before it asked.
-- The game's plain answer: true, false, or nil when it gives none.
local function UsableAnswer(id)
	if not (C_Spell and C_Spell.IsSpellUsable) then return nil end
	local ok, usable = pcall(C_Spell.IsSpellUsable, id)
	if not ok then return nil end
	return Plain(usable)
end

local function Usable(id)
	return UsableAnswer(id) ~= false
end

-- The interrupt to use now: the class file's spell, or the first of its
-- list, that you know, is off cooldown and you can cast now. nil if none.
local function ReadyInterrupt()
	local value = ns.ClassValue("interrupt")
	local list = type(value) == "table" and value or { value }
	for _, spell in ipairs(list) do
		local id = Known(spell)
		if id and OffCooldown(id) == true and Usable(id) then return spell end
	end
	return nil
end

ns.ReadyInterrupt = ReadyInterrupt
-- The "Your class" page names the combat buff you know (Classes.lua).
ns.KnownSpell = Known

-- For chat: one spell, or a list as "Pummel, Shield Bash".
local function InterruptLabel(value)
	if type(value) ~= "table" then return ns.SpellLabel(value) end
	local names = {}
	for i, spell in ipairs(value) do names[i] = ns.SpellLabel(spell) end
	return #names > 0 and table.concat(names, ", ") or "none"
end

local InCombat = ns.InCombat

-- An aura table whose fields we may read. A secret table, or a secret in
-- place of the table, is not.
local issecrettable = _G.issecrettable

local function Readable(aura)
	if aura == nil or IsSecret(aura) then return false end
	if issecrettable and issecrettable(aura) then return false end
	return true
end

-- The aura in one slot. ok is false when the game refuses to answer.
local function AuraAt(unit, index, filter)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false, nil end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
	if not ok then return false, nil end
	return true, aura
end

-- Red edge: "this is missing, cast it". Keep-up, your buff, the target's.
local MISSING_COLOR = { 0.85, 0.15, 0.10, 1 }

-- Test mode (TICK-0067): while true, the alert samples are up and the real
-- updates leave them alone: ns.UpdateAlerts, and each one called from
-- elsewhere (a ticker, Auras.lua, Bars.lua). ns.ShowAlertSamples sets it.
local samples = false

-- A square icon with a coloured edge, for the alerts that show a spell.
local function CreateAlertIcon(parent, edgeColor)
	local f = CreateFrame("Frame", nil, parent)
	f:SetFrameLevel(parent:GetFrameLevel() + 3)

	f.edge = f:CreateTexture(nil, "BACKGROUND")
	f.edge:SetAllPoints()
	f.edge:SetColorTexture(unpack(edgeColor))

	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1)
	f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	f:Hide()
	return f
end

--------------------------------------------------------------------------------
-- 1. Interrupt: a pulsing outline around the target cast bar, which rides
--    on the target's power bar (TICK-0126)
--------------------------------------------------------------------------------

local OUTLINE      = 2                       -- pixels
local KICK_COLOR   = { 1.0, 0.85, 0.20 }

local kickOutline

local function KickOutline(holder)
	if kickOutline then return kickOutline end

	local f = CreateFrame("Frame", nil, holder)
	f:SetPoint("TOPLEFT", -OUTLINE, OUTLINE)
	f:SetPoint("BOTTOMRIGHT", OUTLINE, -OUTLINE)
	-- The cast bar is see-through on the target's power bar (castAlpha,
	-- TICK-0126); the outline keeps its full strength. The holder hangs
	-- off the anchor, whose alpha never changes, so nothing else is lost.
	if f.SetIgnoreParentAlpha then f:SetIgnoreParentAlpha(true) end
	f:SetFrameLevel(holder:GetFrameLevel() + 5)

	local function Edge(a, b, horizontal)
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetColorTexture(unpack(KICK_COLOR))
		t:SetPoint(a)
		t:SetPoint(b)
		if horizontal then t:SetHeight(OUTLINE) else t:SetWidth(OUTLINE) end
		return t
	end

	f.edges = {
		Edge("TOPLEFT",    "TOPRIGHT",    true),
		Edge("BOTTOMLEFT", "BOTTOMRIGHT", true),
		Edge("TOPLEFT",    "BOTTOMLEFT",  false),
		Edge("TOPRIGHT",   "BOTTOMRIGHT", false),
	}

	local ag = f:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local fade = ag:CreateAnimation("Alpha")
	fade:SetFromAlpha(1.0)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.5)
	f.pulse = ag

	f:Hide()
	kickOutline = f
	return f
end

-- Called by Bars.lua every time the target cast bar refreshes.
-- notInterruptible is secret, so it is never read, only handed to the edges.
function ns.OnTargetCast(notInterruptible, ended)
	if samples then return end
	local db = HUDiniDB
	local outline = KickOutline(ns.casts.targetcast.holder)

	if ended or not db.glowOnKickable or not ReadyInterrupt() then
		outline.pulse:Stop()
		outline:Hide()
		return
	end

	-- The plain half opens the gate. The secret half sets each edge's alpha.
	-- 255 and 0 are safe under either alpha scale.
	for _, edge in ipairs(outline.edges) do
		if not (edge.SetAlphaFromBoolean
			and pcall(edge.SetAlphaFromBoolean, edge, notInterruptible, 0, 255)) then
			edge:SetAlpha(1)
		end
	end
	outline:Show()
	if not outline.pulse:IsPlaying() then outline.pulse:Play() end
end

--------------------------------------------------------------------------------
-- 2. Keep-up buff: the one to cast, left of the health bar
--------------------------------------------------------------------------------

-- The first keep-up spell you know, in class-file order, or nil.
local function FirstKnown(names)
	for _, name in ipairs(names) do
		local id = Known(name)
		if id then return id end
	end
	return nil
end

local keepUpIcon, ownBuffIcon

-- Left of your health bar, what is missing (D-027),
-- growing left from the bar in this order. Each icon sits left of the last
-- shown one before it, so a hidden icon takes no place. No bait goes last:
-- its words sit left of its icon, with no icon past them.
local LEFT_ORDER = { "keepUp", "ownBuff", "bait" }
local leftIcons = {}

local function SlotLeft(bar)
	local after = bar
	for _, key in ipairs(LEFT_ORDER) do
		local icon = leftIcons[key]
		if icon then
			icon:ClearAllPoints()
			icon:SetPoint("RIGHT", after, "LEFT", -3, 0)
			if icon:IsShown() then after = icon end
		end
	end
end

local function KeepUpIcon(bar)
	if not keepUpIcon then
		-- Dimmed, with a red edge: "this is missing, cast it".
		keepUpIcon = CreateAlertIcon(bar, MISSING_COLOR)
		keepUpIcon.tex:SetVertexColor(0.65, 0.65, 0.65)
		leftIcons.keepUp = keepUpIcon
	end
	return keepUpIcon
end

local function UpdateKeepUpIcon()
	local db  = HUDiniDB
	local bar = ns.GetBar("health")
	KeepUpIcon(bar)

	-- A class with nothing to keep up, or nothing you have learned yet, never
	-- shows it.
	local keepUp  = ns.ClassValue("keepUp") or {}
	local spellID = FirstKnown(keepUp)
	-- Asked out of a fight too, so HUDini has seen the buff on or off before
	-- the fight hides it (Auras.lua, TICK-0130). Only "surely off" shows the
	-- icon: a buff the game will not answer for counts as on, so an
	-- unreadable aura never raises a false alarm.
	local off = spellID ~= nil and ns.KeepUpState(keepUp) == false
	local want = db.warnKeepUp
		and db.showHealth
		and off
		and InCombat()

	if want then
		local h = bar:GetHeight()
		keepUpIcon:SetSize(h, h)
		keepUpIcon.tex:SetTexture(C_Spell.GetSpellTexture(spellID) or 134400)
	end
	keepUpIcon:SetShown((want and bar:IsShown()) and true or false)
	SlotLeft(bar)
end

--------------------------------------------------------------------------------
-- 7. Your buff is off: the one to cast, left of your health bar
--
-- Auras.lua decides which (ns.missingBuffID) and calls this whenever it
-- looks again, in and out of combat.
--------------------------------------------------------------------------------

local function OwnBuffIcon(bar)
	if not ownBuffIcon then
		ownBuffIcon = CreateAlertIcon(bar, MISSING_COLOR)
		leftIcons.ownBuff = ownBuffIcon
	end
	return ownBuffIcon
end

local function UpdateOwnBuffIcon()
	if samples then return end
	local db = HUDiniDB
	if not db then return end
	local bar = ns.GetBar("health")
	OwnBuffIcon(bar)

	local spellID = db.warnOwnBuff and db.showHealth and ns.missingBuffID or nil
	if spellID then
		local h = bar:GetHeight()
		ownBuffIcon:SetSize(h, h)
		ownBuffIcon.tex:SetTexture(C_Spell.GetSpellTexture(spellID) or 134400)
	end
	ownBuffIcon:SetShown(spellID ~= nil)
	SlotLeft(bar)
end

ns.UpdateOwnBuffIcon = UpdateOwnBuffIcon

--------------------------------------------------------------------------------
-- 2b. No bait: a fishing pole with nothing on it, left of the health bar
--
-- Every class. Core.lua shows the HUD for it too, so it is seen while idle.
-- Bait wears off with no event to say so, so a slow ticker keeps it honest
-- while it can matter: the warning on and a fishing pole in your main hand.
--------------------------------------------------------------------------------

local BAIT_ICON = "Interface\\Icons\\INV_Misc_Orb_03"   -- Shiny Bauble

local baitIcon

local function BaitIcon(bar)
	if not baitIcon then
		baitIcon = CreateAlertIcon(bar, { 0.85, 0.15, 0.10, 1 })
		leftIcons.bait = baitIcon
		baitIcon.tex:SetTexture(BAIT_ICON)
		baitIcon.label = baitIcon:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		baitIcon.label:SetPoint("RIGHT", baitIcon, "LEFT", -4, 0)
		baitIcon.label:SetTextColor(1, 0.25, 0.2)
		baitIcon.label:SetText(ns.Text("alerts.noBait"))
	end
	return baitIcon
end

local function UpdateBaitIcon()
	if samples then return end
	local db  = HUDiniDB
	if not db then return end
	local bar = ns.GetBar("health")
	BaitIcon(bar)

	local want = db.warnNoBait and db.showHealth and ns.BaitMissing and ns.BaitMissing()
	if want then
		local h = bar:GetHeight()
		baitIcon:SetSize(h, h)
	end
	baitIcon:SetShown((want and bar:IsShown()) and true or false)
	SlotLeft(bar)
end

local baitTicker = ns.Ticker(0.5, UpdateBaitIcon)

local function BaitWanted()
	local db = HUDiniDB
	return (db and db.warnNoBait and db.showHealth
		and ns.HoldsFishingPole and ns.HoldsFishingPole()) and true or false
end

--------------------------------------------------------------------------------
-- 3. Dispel: tint the power bar with the debuff type's colour
--------------------------------------------------------------------------------

-- A dispellable debuff whose type the game hides, on a class that dispels
-- more than one type.
local DISPEL_UNKNOWN = { 0.85, 0.35, 0.85 }

local typeColors = {}

-- Blizzard's own debuff type colours: purple curse, green poison, brown
-- disease, blue magic. Cached, so each type is always the same table.
local function TypeColor(dispelType)
	if typeColors[dispelType] == nil then
		local c = DebuffTypeColor and DebuffTypeColor[dispelType]
		typeColors[dispelType] = c and { c.r, c.g, c.b } or false
	end
	return typeColors[dispelType] or DISPEL_UNKNOWN
end

-- The debuff types you can remove right now: { Curse = true }, their count,
-- and one of them.
local function KnownDispels()
	local dispel = ns.ClassValue("dispel")
	local known, count, one = {}, 0, nil
	if type(dispel) == "table" then
		for dispelType, spell in pairs(dispel) do
			if Known(spell) then
				known[dispelType] = true
				count = count + 1
				one = dispelType
			end
		end
	end
	return known, count, one
end

-- Sets ns.powerTint. Bars.lua lays it over the power colour.
local function UpdateDispelTint()
	local db = HUDiniDB
	ns.powerTint = nil
	if not (db.warnDispel and db.showPower) then return end

	local known, count, one = KnownDispels()
	if count == 0 then return end

	local hidden = false
	for i = 1, 40 do
		local ok, aura = AuraAt("player", i, "HARMFUL|RAID")
		if not ok or aura == nil then break end

		if Readable(aura) then
			local dispelType = Plain(aura.dispelName)
			if dispelType and known[dispelType] then
				ns.powerTint = TypeColor(dispelType)
				return
			end
		else
			-- There is one, but the game will not say what type.
			hidden = true
		end
	end

	if hidden then
		ns.powerTint = (count == 1) and TypeColor(one) or DISPEL_UNKNOWN
	end
end

--------------------------------------------------------------------------------
-- 8. Racial ability: its icon glows while it can help
--------------------------------------------------------------------------------

-- Ready to cast: off cooldown, or on the global cooldown only, so the glow
-- does not blink off after each spell you cast. Both fields are plain
-- (SpellCooldownInfo isActive and isOnGCD, NeverSecret in
-- SpellSharedDocumentation.lua:26, :30). false when the game does not say.
local function RacialReady(id)
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or type(info) ~= "table" then return false end
	local active = Plain(info.isActive)
	if active == nil then return false end
	if active and Plain(info.isOnGCD) ~= true then return false end
	return Usable(id)
end

-- True when a debuff of one of these types is on you and the game shows
-- its type. A hidden aura, or a hidden type, is skipped: it lights nothing.
local function DebuffOfType(types)
	for i = 1, 40 do
		local ok, aura = AuraAt("player", i, "HARMFUL")
		if not ok or aura == nil then return false end
		if Readable(aura) then
			local dispelType = Plain(aura.dispelName)
			if dispelType and types[dispelType] then return true end
		end
	end
	return false
end

-- The spell ID to glow, or nil.
local function RacialToGlow()
	local db = HUDiniDB
	if not (db and db.warnRacial) then return nil end
	local spell, types = ns.RacialAlert()
	local id = spell and Known(spell)
	if not id then return nil end
	if not (RacialReady(id) and DebuffOfType(types)) then return nil end
	return id
end

-- Core.lua draws it with the proc glow on the icon with that spell.
local function UpdateRacialGlow()
	if ns.HUDini and ns.HUDini.SetAlertGlow then
		ns.HUDini:SetAlertGlow("racial", RacialToGlow())
	end
end
ns.UpdateRacialGlow = function()
	if not HUDiniDB or samples then return end
	UpdateRacialGlow()
end

--------------------------------------------------------------------------------
-- 4. Purgeable buffs on the target
--------------------------------------------------------------------------------

local MAX_PURGE_ICONS = 4

local purgeIcons = {}

local function PurgeIcon(bar, index)
	local icon = purgeIcons[index]
	if not icon then
		icon = CreateAlertIcon(bar, { 0.20, 0.55, 1.00, 1 })
		purgeIcons[index] = icon
	end
	-- Right to left from the bar's right end, inside the bar.
	local size = max(8, bar:GetHeight() - 6)
	icon:SetSize(size, size)
	icon:ClearAllPoints()
	icon:SetPoint("RIGHT", bar, "RIGHT", -3 - (index - 1) * (size + 2), 0)
	return icon
end

-- Your purge spell and what it takes: any magic buff, or (Spellsteal) only
-- stealable ones. The class file gives "Purge" or { spell = ..., stealable = true }.
local function PurgeRule()
	local purge = ns.ClassValue("purge")
	local spell, stealableOnly = purge, false
	if type(purge) == "table" then
		spell, stealableOnly = purge.spell, purge.stealable and true or false
	end
	return Known(spell), stealableOnly
end

local function Purgeable(aura, stealableOnly)
	if stealableOnly then return Plain(aura.isStealable) == true end
	return Plain(aura.dispelName) == "Magic"
end

local function UpdatePurgeable()
	local db  = HUDiniDB
	local bar = ns.GetBar("targethealth")
	local shown = 0

	local hostile = UnitExists("target") and Plain(UnitCanAttack("player", "target"))
	if db.showPurgeable and db.showTargetHealth and hostile then
		local spellID, stealableOnly = PurgeRule()
		if spellID then
			for i = 1, 40 do
				local ok, aura = AuraAt("target", i, "HELPFUL")
				if not ok or aura == nil then break end
				if Readable(aura) and Purgeable(aura, stealableOnly) then
					shown = shown + 1
					local icon = PurgeIcon(bar, shown)
					icon.tex:SetTexture(Plain(aura.icon) or 134400)
					icon:Show()
					if shown >= MAX_PURGE_ICONS then break end
				end
			end
		end
	end

	for i = shown + 1, #purgeIcons do
		purgeIcons[i]:Hide()
	end
end

--------------------------------------------------------------------------------
-- 6. Target needs your buff, left of the target health bar
--
-- The candidates are the long buffs HUDini learned (Auras.lua), in name
-- order, and only spells you know with a range: a self-only buff (Frost
-- Armor) has none, so it never asks to be cast on someone else. A buff
-- counts as on when the target has it or its group version
-- (ns.AuraNamesFor), from anyone. A buff the
-- game will not answer for counts as on, so it never raises a false alarm.
--
-- Blessings are one per paladin per target. Once the target has any
-- blessing from you, no other blessing of yours is asked for.
--------------------------------------------------------------------------------


local function CanCastOnOthers(spellID)
	local hasRange = (C_Spell and C_Spell.SpellHasRange) or SpellHasRange
	if not hasRange then return true end
	local ok, ranged = pcall(hasRange, spellID)
	return not ok or Plain(ranged) ~= false
end

-- True when the target has any of the buffs, false when none, nil when the
-- game will not say.
local function TargetHasAny(names)
	for _, name in ipairs(names) do
		local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HELPFUL")
		if not ok then return nil end
		if data ~= nil then return true end
	end
	return false
end

-- A paladin's blessing, by the client's name (Classes.lua, TICK-0024).
local function IsBlessing(name)
	return ns.IsBlessing(name)
end

-- True when the target has a blessing you cast, false when not, nil when
-- the game will not say. "PLAYER" keeps only auras you cast.
local function YourBlessingOnTarget()
	for i = 1, 40 do
		local ok, aura = AuraAt("target", i, "HELPFUL|PLAYER")
		if not ok then return nil end
		if aura == nil then return false end
		if not Readable(aura) then return nil end
		local name = Plain(aura.name)
		if name == nil then return nil end
		if IsBlessing(name) then return true end
	end
	return false
end

-- A living, online, friendly player.
local function BuffableTarget()
	if not UnitExists("target") then return false end
	if not Plain(UnitIsPlayer("target")) then return false end
	if not Plain(UnitCanAssist("player", "target")) then return false end
	if Plain(UnitIsDeadOrGhost("target")) ~= false then return false end
	return Plain(UnitIsConnected("target")) ~= false
end

-- The spell ID of the first buff your target lacks, or nil.
local function MissingTargetBuff()
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
	local learned = ns.ClassDB().buffSpells
	if not learned then return nil end

	local names = {}
	for name in pairs(learned) do names[#names + 1] = name end
	table.sort(names)

	local blessed   -- asked once, only when a blessing comes up
	for _, source in ipairs(names) do
		local spellID = Known(source)
		if spellID and CanCastOnOthers(spellID) then
			local skip = false
			if IsBlessing(source) then
				if blessed == nil then blessed = (YourBlessingOnTarget() ~= false) end
				skip = blessed
			end
			if not skip and TargetHasAny(ns.AuraNamesFor(source)) == false then return spellID end
		end
	end
	return nil
end

local targetBuffIcon

local function TargetBuffIcon(bar)
	if not targetBuffIcon then
		targetBuffIcon = CreateAlertIcon(bar, MISSING_COLOR)
		targetBuffIcon:SetPoint("RIGHT", bar, "LEFT", -3, 0)
	end
	return targetBuffIcon
end

local function UpdateTargetBuffIcon()
	if samples then return end
	local db  = HUDiniDB
	if not db then return end
	local bar = ns.GetBar("targethealth")
	TargetBuffIcon(bar)

	local spellID
	if db.warnTargetBuff and db.showTargetHealth and not InCombat() and BuffableTarget() then
		spellID = MissingTargetBuff()
	end

	if spellID then
		local h = bar:GetHeight()
		targetBuffIcon:SetSize(h, h)
		targetBuffIcon.tex:SetTexture(C_Spell.GetSpellTexture(spellID) or 134400)
		local inRange = C_Spell.IsSpellInRange and Plain(C_Spell.IsSpellInRange(spellID, "target"))
		targetBuffIcon:SetAlpha(inRange == false and 0.4 or 1)
	end
	targetBuffIcon:SetShown(spellID ~= nil)
end

-- Walking into range fires no event, and nor does a dead or offline friend
-- coming back. So a slow ticker checks again while the icon can matter: the
-- warning on, a friendly player targeted, out of a fight. It stops itself
-- at the first tick that is no longer so.
local function TargetTickerWanted()
	local db = HUDiniDB
	return (db and db.warnTargetBuff and db.showTargetHealth and not InCombat()
		and UnitExists("target") and Plain(UnitIsPlayer("target"))
		and Plain(UnitCanAssist("player", "target"))) and true or false
end

local targetTicker
targetTicker = ns.Ticker(0.5, function()
	UpdateTargetBuffIcon()
	if not TargetTickerWanted() then targetTicker:Set(false) end
end)

--------------------------------------------------------------------------------
-- Samples for test mode (TICK-0067)
--
-- TestMode.lua calls ns.ShowAlertSamples(true) at /hud test and (false) at
-- its end. On: every alert that is turned on, on a bar that is turned on,
-- shows a fixed sample. Fixed textures and colours only: no unit, spell,
-- aura or cast is read, so no secret value is. While on, the real updates
-- return at once, so an aura change, a target cast or a ticker cannot take
-- a sample down. Off: the real updates run and put back what the game says.
--------------------------------------------------------------------------------

local SAMPLE_TEXTURES = {
	keepUp     = "Interface\\Icons\\Ability_Warrior_BattleShout",
	ownBuff    = "Interface\\Icons\\Spell_Holy_MagicalSentry",      -- Arcane Intellect
	targetBuff = "Interface\\Icons\\Spell_Nature_Regeneration",     -- Mark of the Wild
	purge      = { "Interface\\Icons\\Spell_Holy_PowerWordShield", "Interface\\Icons\\Spell_Holy_Renew" },
}

local function SampleIcon(icon, bar, texture)
	local h = bar:GetHeight()
	icon:SetSize(h, h)
	icon.tex:SetTexture(texture)
	icon:Show()
end

local function ShowSamples(db)
	if db.glowOnKickable and db.showTargetCast and ns.casts and ns.casts.targetcast then
		local outline = KickOutline(ns.casts.targetcast.holder)
		for _, edge in ipairs(outline.edges) do edge:SetAlpha(1) end
		outline:Show()
		if not outline.pulse:IsPlaying() then outline.pulse:Play() end
	end

	local health = ns.GetBar("health")
	local own = OwnBuffIcon(health)
	own:Hide()
	if db.warnOwnBuff and db.showHealth then SampleIcon(own, health, SAMPLE_TEXTURES.ownBuff) end
	local keepUp = KeepUpIcon(health)
	keepUp:Hide()
	if db.warnKeepUp and db.showHealth then SampleIcon(keepUp, health, SAMPLE_TEXTURES.keepUp) end
	local bait = BaitIcon(health)
	bait:Hide()
	if db.warnNoBait and db.showHealth then SampleIcon(bait, health, BAIT_ICON) end
	SlotLeft(health)

	ns.powerTint = (db.warnDispel and db.showPower) and TypeColor("Curse") or nil

	local target = ns.GetBar("targethealth")
	for _, icon in ipairs(purgeIcons) do icon:Hide() end
	if db.showPurgeable and db.showTargetHealth then
		for i, texture in ipairs(SAMPLE_TEXTURES.purge) do
			PurgeIcon(target, i).tex:SetTexture(texture)
			purgeIcons[i]:Show()
		end
	end
	local buff = TargetBuffIcon(target)
	buff:Hide()
	if db.warnTargetBuff and db.showTargetHealth then
		SampleIcon(buff, target, SAMPLE_TEXTURES.targetBuff)
		buff:SetAlpha(1)
	end
end

function ns.ShowAlertSamples(on)
	local db = HUDiniDB
	if not db then return end
	samples = on and true or false
	if samples then
		ShowSamples(db)
	else
		if kickOutline then
			kickOutline.pulse:Stop()
			kickOutline:Hide()
		end
		ns.UpdateAlerts()
	end
	-- The power bar takes the tint, or drops it, at its next fill (Bars.lua):
	-- the HUD poll, or TestMode.lua's ns.RefreshBars at its end.
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------

function ns.UpdateAlerts()
	if not HUDiniDB or samples then return end
	UpdateOwnBuffIcon()
	UpdateKeepUpIcon()
	UpdateDispelTint()
	UpdateRacialGlow()
	UpdatePurgeable()
	UpdateTargetBuffIcon()
	UpdateBaitIcon()
	baitTicker:Set(BaitWanted())
	targetTicker:Set(TargetTickerWanted())
end

function ns.RefreshAlerts()
	ns.UpdateAlerts()
end

function ns.ReportAlerts(out)
	-- locale: skip a debug report (/hud debug aura), in English
	local function Mark(v) return v and "|cff33ff33yes|r" or "|cffff3333no|r" end

	local ready     = ReadyInterrupt()
	local _, count  = KnownDispels()
	local purgeID   = PurgeRule()

	local ok, first = AuraAt("player", 1, "HARMFUL|RAID")
	local dispelNow = not ok and "|cffff9933cannot tell|r"
		or (first == nil and "none")
		or (Readable(first) and tostring(Plain(first.dispelName) or "?"))
		or "|cffff9933yes, type hidden|r"

	out("  Class file                            " .. tostring(ns.ClassToken()))
	out("  Interrupt spell ready                 " .. Mark(ready)
		.. "  (" .. (ready and ns.SpellLabel(ready)
			or InterruptLabel(ns.ClassValue("interrupt"))) .. ")")
	local value = ns.ClassValue("interrupt")
	local function Tell(v)
		if v == nil then return "|cffff9933cannot tell|r" end
		return Mark(v)
	end
	for _, spell in ipairs(type(value) == "table" and value or { value }) do
		local id = Known(spell)
		local cooldown, usable = "not asked", "not asked"
		if id then cooldown, usable = Tell(OffCooldown(id)), Tell(UsableAnswer(id)) end
		out("    " .. ns.SpellLabel(spell) .. ": known " .. Mark(id)
			.. ", off cooldown " .. cooldown .. ", usable now " .. usable)
	end
	out("  Dispel spells known                   " .. count)
	out("  Dispellable debuff on you now         " .. dispelNow)
	out("  Purge spell known                     " .. Mark(purgeID))
	-- locale: end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
-- A new pet, or new pet spells: walk the pet spellbook again.
local PET_EVENTS = { SPELLS_CHANGED = true, PET_BAR_UPDATE = true, UNIT_PET = true }
pcall(events.RegisterEvent, events, "SPELLS_CHANGED")
pcall(events.RegisterEvent, events, "PET_BAR_UPDATE")
pcall(events.RegisterUnitEvent, events, "UNIT_PET", "player")
-- UNIT_AURA comes from the one handler in Auras.lua (TICK-0065).
events:SetScript("OnEvent", function(self, event)
	if PET_EVENTS[event] then wipe(petCache) end
	if event == "PLAYER_ENTERING_WORLD" then
		pcall(self.RegisterEvent, self, "PLAYER_REGEN_ENABLED")
		pcall(self.RegisterEvent, self, "PLAYER_REGEN_DISABLED")
		pcall(self.RegisterEvent, self, "PLAYER_TARGET_CHANGED")
		pcall(self.RegisterEvent, self, "PLAYER_EQUIPMENT_CHANGED")
		-- A duel starts or ends on your target: purgeable or not. UNIT_FACTION
		-- is not proven on Forever, so DUEL_FINISHED covers the end too.
		pcall(self.RegisterUnitEvent, self, "UNIT_FACTION", "target")
		pcall(self.RegisterEvent, self, "DUEL_FINISHED")
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- The lockdown starts just after this event: look again next frame,
		-- so the keep-up icon sees the fight.
		C_Timer.After(0, ns.UpdateAlerts)
	end
	ns.UpdateAlerts()
end)
