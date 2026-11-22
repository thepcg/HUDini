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

	9. Your cooldown is ready (TICK-0157, GitHub #1). A spell you turned on
	   (Classes.lua, ns.SetReadyAlert) plays a sound when its cooldown ends,
	   and its icon on the HUD glows for a few seconds. Off for every spell
	   until you turn it on. Only SPELL_UPDATE_COOLDOWN (or, for a spell with
	   charges, SPELL_UPDATE_CHARGES) can mark a spell "on cooldown": the
	   game says isOnGCD is only true to trust in that event, and the global
	   cooldown alone is not the spell's cooldown. While a watched spell is
	   on cooldown, a 0.5 s ticker looks only for isActive false (ready),
	   which is safe at any time. No alert at login: a spell counts only
	   after the game was seen to start its cooldown.
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

-- On the global cooldown only (TICK-0161). The game says isOnGCD is to
-- trust only inside SPELL_UPDATE_COOLDOWN (SpellSharedDocumentation.lua:30),
-- so that event notes it for each spell asked about here (Core.lua calls
-- ns.NoteGlobalCooldowns), and the note stands until the next one. A spell
-- not noted yet counts as on its own cooldown while isActive is true.
local gcdAsked = {} -- spell ID -> true, once ReadySoon asked about it
local gcdOnly = {}  -- spell ID -> true while the last event said "global only"

-- true when you can cast it now or right after the global cooldown: off
-- cooldown, or on the global cooldown only. false on its own cooldown, nil
-- when the game does not say.
local function ReadySoon(id)
	if not id then return nil end
	gcdAsked[id] = true
	local off = OffCooldown(id)
	if off ~= false then return off end
	return gcdOnly[id] == true
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
-- list, that you know, is off cooldown (the global cooldown alone does not
-- count, so the outline does not go out after each spell you cast) and you
-- can cast now. nil if none.
local function ReadyInterrupt()
	local value = ns.ClassValue("interrupt")
	local list = type(value) == "table" and value or { value }
	for _, spell in ipairs(list) do
		local id = Known(spell)
		if id and ReadySoon(id) == true and Usable(id) then return spell end
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

-- The target's cast while it runs: { ni = notInterruptible }, or nil. Kept
-- only to hand on again (ns.NoteGlobalCooldowns); never read.
local targetCast

-- Called by Bars.lua every time the target cast bar refreshes.
-- notInterruptible is secret, so it is never read, only handed to the edges.
function ns.OnTargetCast(notInterruptible, ended)
	if samples then return end
	local db = HUDiniDB
	local outline = KickOutline(ns.casts.targetcast.holder)
	targetCast = not ended and { ni = notInterruptible } or nil

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
-- shown one before it, so a hidden icon takes no place. A missing item
-- (TICK-0182) shows out of a fight only, after the buffs. No bait goes last:
-- its words sit left of its icon, with no icon past them. In a fight the
-- game's buff watches (Auras.lua, TICK-0168) hold the first spots, in the
-- same order: these icons start left of them.
local LEFT_ORDER = { "keepUp", "ownBuff", "item", "bait" }
local leftIcons = {}
ns.leftIcons = leftIcons -- read only: the tests tell the icons apart by it

local function SlotLeft(bar)
	local after = bar
	local held = ns.BuffWatchSpots and ns.BuffWatchSpots() or 0
	local skip = held * ((bar:GetHeight() or 0) + 3)
	for _, key in ipairs(LEFT_ORDER) do
		local icon = leftIcons[key]
		if icon then
			icon:ClearAllPoints()
			icon:SetPoint("RIGHT", after, "LEFT", -3 - (after == bar and skip or 0), 0)
			if icon:IsShown() then after = icon end
		end
	end
end

-- True when a buff watch shows this buff's icon in the fight (Auras.lua).
local function Watched(key)
	return key ~= nil and ns.BuffWatched ~= nil and ns.BuffWatched(key) == true
end

-- The alert sounds the player picks from (D-043, TICK-0167), in menu order:
-- the game's own sound kits (SOUNDKIT, SoundKitConstants.lua), old enough
-- to be in WoW Forever's data. HUDini ships no sound. The cooldown viewer's
-- kits (353392, 353397) are not: PlaySound returns nothing for them there
-- (DK's test, 2026-11-21). The names are the locale's "sound.<key>".
-- The third value is the kit's one sound file (the game's SoundKitEntry
-- table, by wago.tools): the game's buff-end sound takes a file, not a
-- kit (C_UnitAuras.AddAuraSound, Auras.lua, TICK-0168).
local ALERT_SOUNDS = {
	{ "readyCheck",   8960, 567478 }, -- READY_CHECK
	{ "raidWarning",  8959, 567397 }, -- RAID_WARNING
	{ "mapPing",      3175, 567416 }, -- MAP_PING
	{ "whisper",      3081, 567421 }, -- TELL_MESSAGE
	{ "bossEmote",   12197, 567394 }, -- RAID_BOSS_EMOTE_WARNING
	{ "alarmClock",  12867, 567399 }, -- ALARM_CLOCK_WARNING_2
	{ "pvpQueue",     8459, 568011 }, -- PVP_THROUGH_QUEUE
	{ "coins",         120, 567428 }, -- LOOT_WINDOW_COIN_SOUND
}
local soundKit, soundFile, soundKeys = {}, {}, {}
for i, s in ipairs(ALERT_SOUNDS) do
	soundKeys[i], soundKit[s[1]], soundFile[s[1]] = s[1], s[2], s[3]
end
-- Two defaults that differ, so good news and a warning are told apart.
ns.READY_SOUND_DEFAULT   = "readyCheck"
ns.MISSING_SOUND_DEFAULT = "raidWarning"
-- DK heard it play on WoW Forever: the last try when a pick will not play.
local LAST_SOUND = 8959

-- The keys in menu order (a copy).
function ns.AlertSounds()
	local keys = {}
	for i, key in ipairs(soundKeys) do keys[i] = key end
	return keys
end

-- Plays key's sound once on the Master channel, so it plays with Sound
-- Effects turned down. If the client cannot play it, then default's, then
-- LAST_SOUND. The kit ID played, or nil. The option rows call it once on a
-- pick (a preview), so it never skips a call.
function ns.PlayAlertSound(key, default)
	local kits, added = {}, {}
	for _, kit in ipairs({ soundKit[key] or false, soundKit[default] or false, LAST_SOUND }) do
		if kit and not added[kit] then
			added[kit] = true
			kits[#kits + 1] = kit
		end
	end
	return ns.PlaySoundFirst(kits, "Master") -- locale: skip the game's sound channel
end

-- The ready alert's sound, one for every spell of the class: the saved key,
-- or the default when none is saved or the key left the list.
function ns.GetReadySound()
	local key = HUDiniDB and ns.ClassDB().readySound
	if soundKit[key] then return key end
	return ns.READY_SOUND_DEFAULT
end

-- True if it changed. A key not in the list changes nothing.
function ns.SetReadySound(key)
	if not (HUDiniDB and soundKit[key]) then return false end
	local db = ns.ClassDB()
	local want = key ~= ns.READY_SOUND_DEFAULT and key or nil
	if db.readySound == want then return false end
	db.readySound = want
	return true
end

-- Which red icon is on in a fight now. The sound plays once when the first
-- turns on, and again only after both went off. An icon turns on only for
-- "surely off" (an unreadable aura counts as on), so a secret read is
-- silent. A buff missing before the fight sounds when the fight starts (the
-- alerts look again then); one that ends in the fight sounds when its icon
-- turns on, which needs a sign the game gives (TICK-0164 slot hooks).
-- A buff that leaves you in a fight while the game plays its own sound for
-- it (ns.GameSounds, Auras.lua, TICK-0168) gets none from HUDini: one
-- sound, not two.
local missingOn = { keepUp = false, ownBuff = false }
local missingSounded = false

-- Saved per class as keepUpSound: false off, true on with the default
-- (TICK-0163 saves), a key on with that sound. Nothing saved: on with the
-- default when the class file says keepUpSoundOn (D-047), else off. Off
-- saves false, so it wins over that start (TICK-0181). No migration: an
-- Off from before TICK-0181 saved nothing, so it reads as the start.
local function KeepUpSaved()
	local saved = ns.ClassDB().keepUpSound
	if saved == nil and ns.ClassDefault and ns.ClassDefault("keepUpSoundOn") == true then
		return true
	end
	return saved
end

function ns.GetKeepUpSound()
	if not HUDiniDB then return false end
	local saved = KeepUpSaved()
	return saved == true or type(saved) == "string"
end

-- "off", or the key of the sound that plays (the default for true or for a
-- key that left the list).
function ns.GetKeepUpSoundChoice()
	if not ns.GetKeepUpSound() then return "off" end
	local saved = KeepUpSaved()
	if soundKit[saved] then return saved end
	return ns.MISSING_SOUND_DEFAULT
end

-- true (on, the sound kept), false or "off", or a key. True if it changed;
-- a key not in the list changes nothing.
function ns.SetKeepUpSound(choice)
	if not HUDiniDB then return false end
	local db = ns.ClassDB()
	local want
	if choice == true then
		want = ns.GetKeepUpSound() and KeepUpSaved() or true
	elseif choice == false or choice == nil or choice == "off" then
		want = false
	elseif soundKit[choice] then
		want = choice ~= ns.MISSING_SOUND_DEFAULT and choice or true
	else
		return false
	end
	if db.keepUpSound == want then return false end
	db.keepUpSound = want
	-- The game's sound for a buff that ends in a fight follows now, not at
	-- the next aura change: a fight can start first (TICK-0168).
	if ns.SyncBuffWatches then pcall(ns.SyncBuffWatches) end
	return true
end

-- The sound file the game plays when a buff leaves you in a fight, or nil
-- with the sound off.
function ns.MissingSoundFile()
	if not ns.GetKeepUpSound() then return nil end
	return soundFile[ns.GetKeepUpSoundChoice()] or soundFile[ns.MISSING_SOUND_DEFAULT]
end

-- buff: the buff the icon shows (a buff name, or ns.KEEP_UP_KEY for the
-- list), for ns.GameSounds.
local function MissingSound(key, on, buff)
	missingOn[key] = on and true or false
	local any = missingOn.keepUp or missingOn.ownBuff
	local byGame = on and buff ~= nil and ns.GameSounds ~= nil and ns.GameSounds(buff)
	if any and not missingSounded and ns.GetKeepUpSound() and not byGame then
		ns.PlayAlertSound(ns.GetKeepUpSoundChoice(), ns.MISSING_SOUND_DEFAULT)
	end
	missingSounded = any
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

-- True when the own-buff icon (alert 7) shows a spell of the keep-up list.
-- The same buff can be both: a class pick of Lightning Shield, a buff
-- HUDini learned too (TICK-0166). One icon is enough, and the own-buff
-- icon knows more in a fight (the slot sign, TICK-0164), so it wins.
local function OwnBuffCovers(keepUp)
	local db = HUDiniDB
	local id = db.warnOwnBuff and db.showHealth and ns.missingBuffID
	if not id then return false end
	local name = Plain(C_Spell.GetSpellName(id))
	if type(name) ~= "string" then return false end
	for _, spell in ipairs(keepUp) do
		local listed = spell
		if type(spell) == "number" then listed = Plain(C_Spell.GetSpellName(spell)) end
		if listed == name then return true end
	end
	return false
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
		and not OwnBuffCovers(keepUp)

	if want then
		local h = bar:GetHeight()
		keepUpIcon:SetSize(h, h)
		keepUpIcon.tex:SetTexture(C_Spell.GetSpellTexture(spellID) or 134400)
	end
	-- A watch shows it in a fight: one icon. The sound still counts it.
	keepUpIcon:SetShown((want and bar:IsShown() and not Watched(ns.KEEP_UP_KEY)) and true or false)
	SlotLeft(bar)
	MissingSound("keepUp", want, ns.KEEP_UP_KEY)
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
	local buff = spellID and Plain(C_Spell.GetSpellName(spellID))
	if type(buff) ~= "string" then buff = nil end
	-- A watch shows it in a fight: one icon. The sound and the glow still
	-- count it.
	ownBuffIcon:SetShown(spellID ~= nil and not Watched(buff))
	SlotLeft(bar)
	-- The icon shows out of a fight too; the sound is for a fight only.
	MissingSound("ownBuff", spellID ~= nil and InCombat(), buff)
	-- The HUD icon of that spell glows while this shows (D-035, TICK-0150),
	-- with the proc glow setting off too. ns.missingBuffID is the grid
	-- entry's own spell ID when the spell is on the grid (Auras.lua
	-- UpdateBuffMissing), so the glow finds its icon by that ID. A spell off
	-- the grid has no icon: nothing glows.
	if ns.HUDini and ns.HUDini.SetAlertGlow then ns.HUDini:SetAlertGlow("ownBuff", spellID) end
end

-- Auras.lua calls this when ns.missingBuffID may have changed: the
-- keep-up icon looks again too, as it steps aside for the same spell.
ns.UpdateOwnBuffIcon = function()
	UpdateOwnBuffIcon()
	if HUDiniDB and not samples then UpdateKeepUpIcon() end
end

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
-- 2c. Missing item: an item you make or need is not in your bags
--     (TICK-0182, D-047), left of the health bar, out of a fight only
--
-- The class file's missingItem rows (Classes.lua). A row counts when its
-- choice is on and you know its spell: make (the spell that makes it), or
-- one of needs (spells that use it). The icon shows the first such row, in
-- class file order, whose items your bags hold none of and whose buff (if
-- it has one) is not on you. A count or a buff the game will not give
-- counts as "you have it", so an unreadable bag never raises a false alarm.
-- Bags: BAG_UPDATE_DELAYED. Spells, the fight's start and end, and auras
-- call ns.UpdateAlerts.
--------------------------------------------------------------------------------

local itemIcon

local function ItemIcon(bar)
	if not itemIcon then
		itemIcon = CreateAlertIcon(bar, MISSING_COLOR)
		leftIcons.item = itemIcon
	end
	return itemIcon
end

-- The ID of the row's spell you know, or nil: make, else the first of needs.
local function RowKnown(row)
	if row.make ~= nil then return Known(row.make) end
	if type(row.needs) == "table" then return FirstKnown(row.needs) end
	return Known(row.needs)
end
ns.MissingItemKnown = RowKnown

-- How many of one item your bags hold, or nil when the game will not say.
-- C_Item.GetItemCount(id, includeBank, includeUses, includeReagentBank), as
-- FeedLoot.lua asks it.
local function ItemCount(id)
	local get = C_Item and C_Item.GetItemCount
	if not get then return nil end
	local ok, n = pcall(get, id, false, false, true)
	n = ok and Plain(n) or nil
	return type(n) == "number" and n or nil
end

-- true when the bags hold one of the row's items, or the game will not say.
local function HasItem(row)
	for _, id in ipairs(row.items) do
		local n = ItemCount(id)
		if n == nil or n > 0 then return true end
	end
	return false
end

-- true when the buff is on you, or the game will not say. Asked out of a
-- fight only, where your auras read.
local function BuffOn(name)
	if name == nil then return false end
	local auras = C_UnitAuras
	if not (auras and auras.GetAuraDataBySpellName) then return true end
	local ok, aura = pcall(auras.GetAuraDataBySpellName, "player", name, "HELPFUL")
	if not ok or ns.IsSecret(aura) then return true end
	return aura ~= nil
end

-- The row to show now and its known spell's ID, or nil. Out of a fight,
-- with the health bar on. makeOnly: only a row you make (for the wake).
-- Makes no table: the HUD's poll asks it through ns.MissingItemWake.
local function MissingRow(makeOnly)
	local db = HUDiniDB
	if not (db and db.showHealth) or InCombat() then return nil end
	local list = ns.ClassDefault and ns.ClassDefault("missingItem")
	if type(list) ~= "table" then return nil end
	for _, row in ipairs(list) do
		if (not makeOnly or (type(row) == "table" and row.make ~= nil))
			and ns.MissingItemOn(row) then
			local id = RowKnown(row)
			if id and not HasItem(row) and not BuffOn(row.buff) then return row, id end
		end
	end
	return nil
end

-- The game's name for the row's item: the first of its IDs the game names.
-- nil while the game has not loaded any (it is asked to).
function ns.MissingItemName(row)
	local get = C_Item and C_Item.GetItemNameByID
	if not (get and type(row) == "table" and type(row.items) == "table") then return nil end
	for _, id in ipairs(row.items) do
		local ok, name = pcall(get, id)
		name = ok and Plain(name) or nil
		if type(name) == "string" and name ~= "" then return name end
	end
	local load = C_Item.RequestLoadItemDataByID
	if load then
		for _, id in ipairs(row.items) do pcall(load, id) end
	end
	return nil
end

-- The item's own icon, else the spell's, else the question mark.
local function RowTexture(row, spellID)
	local get = C_Item and C_Item.GetItemIconByID
	if get and row.items[1] then
		local ok, tex = pcall(get, row.items[1])
		tex = ok and Plain(tex) or nil
		if tex then return tex end
	end
	return (spellID and Plain(C_Spell.GetSpellTexture(spellID))) or 134400
end

local function UpdateItemIcon()
	if samples or not HUDiniDB then return end
	local bar = ns.GetBar("health")
	ItemIcon(bar)
	local row, id = MissingRow(false)
	if row then
		local h = bar:GetHeight()
		itemIcon:SetSize(h, h)
		itemIcon.tex:SetTexture(RowTexture(row, id))
	end
	itemIcon:SetShown((row and bar:IsShown()) and true or false)
	SlotLeft(bar)
end
ns.UpdateMissingItem = UpdateItemIcon

-- Core.lua shows the HUD for it, so its icon is seen while idle: a row you
-- make is missing, and you can cast its spell now. A row you need for a
-- spell never wakes the HUD, so hide when idle still works with no shards.
function ns.MissingItemWake()
	local row, id = MissingRow(true)
	return row ~= nil and UsableAnswer(id) == true
end

-- Your bags changed. At login, ask the game to load the items' names, for
-- the setup page and Options. Bags are heard from the first
-- PLAYER_ENTERING_WORLD on, as Core and the alerts frame do: a bag event
-- on the login screen must not build the health bar before the HUD.
local itemEvents = CreateFrame("Frame")
pcall(itemEvents.RegisterEvent, itemEvents, "PLAYER_ENTERING_WORLD")
itemEvents:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_ENTERING_WORLD" then
		pcall(self.RegisterEvent, self, "BAG_UPDATE_DELAYED")
		for _, row in ipairs(ns.MissingItemRows and ns.MissingItemRows() or {}) do
			ns.MissingItemName(row)
		end
	end
	UpdateItemIcon()
end)

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

-- Ready to cast: off cooldown, or on the global cooldown only (ReadySoon),
-- so the glow does not blink off after each spell you cast. false when the
-- game does not say.
local function RacialReady(id)
	return ReadySoon(id) == true and Usable(id)
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

-- The spells asked about from the first event on, so the first ask in a
-- global cooldown finds a note: each interrupt you know, and your racial.
local function SeedAsked()
	local value = ns.ClassValue("interrupt")
	for _, spell in ipairs(type(value) == "table" and value or { value }) do
		local id = Known(spell)
		if id then gcdAsked[id] = true end
	end
	local racial = ns.RacialAlert and ns.RacialAlert()
	local id = racial and Known(racial)
	if id then gcdAsked[id] = true end
end

local function CooldownInfo(id)
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or type(info) ~= "table" then return nil, nil end
	return Plain(info.isActive), Plain(info.isOnGCD)
end

-- The outline on a target's cast looks again with the notes as they are.
-- A target cast bar hidden with no "ended" (target cleared, the bar off)
-- drops the cast here.
local function OutlineAgain()
	if not targetCast or not HUDiniDB or samples then return end
	local cast = ns.casts and ns.casts.targetcast
	if not (HUDiniDB.showTargetCast and cast and cast.holder:IsShown()) then
		targetCast = nil
		if kickOutline then
			kickOutline.pulse:Stop()
			kickOutline:Hide()
		end
		return
	end
	ns.OnTargetCast(targetCast.ni)
end

-- A shared cooldown (Flame Shock starts Earth Shock's) can land a frame
-- after the event, with no event of its own. One frame later, a spell noted
-- "global only" that now reads as anything else loses its note. The look
-- only takes notes away: isOnGCD out of the event is never trusted to say
-- "ready".
local lateDue = false
local function LateLook()
	lateDue = false
	local changed = false
	for id in pairs(gcdOnly) do
		local active, gcd = CooldownInfo(id)
		if not (active == true and gcd == true) then
			gcdOnly[id] = nil
			changed = true
		end
	end
	if changed and HUDiniDB and not samples then
		OutlineAgain()
		UpdateRacialGlow()
	end
end

-- Core.lua calls this inside SPELL_UPDATE_COOLDOWN, the one place isOnGCD
-- is to trust: note it for each spell ReadySoon asked about. Both fields
-- are plain (SpellCooldownInfo isActive and isOnGCD, NeverSecret in
-- SpellSharedDocumentation.lua:26, :30). Then the outline on a target's
-- cast looks again: Bars.lua asks only when the cast starts, and your
-- interrupt can come off cooldown, or go on it, while the cast runs.
function ns.NoteGlobalCooldowns()
	SeedAsked()
	for id in pairs(gcdAsked) do
		local active, gcd = CooldownInfo(id)
		gcdOnly[id] = (active == true and gcd == true) or nil
	end
	OutlineAgain()
	if next(gcdOnly) and not lateDue then
		lateDue = true
		C_Timer.After(0, LateLook)
	end
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
-- game will not say. Not found while auras are hidden (some maps, PvP) is
-- "will not say": a hidden aura is not found by name (TICK-0161).
local function TargetHasAny(names)
	for _, name in ipairs(names) do
		local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "target", name, "HELPFUL")
		if not ok then return nil end
		if data ~= nil then return true end
	end
	if ns.AurasHidden and ns.AurasHidden() then return nil end
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
	-- A missing item: your class file's first row that is on (TICK-0182).
	local item = ItemIcon(health)
	item:Hide()
	if db.showHealth then
		for _, row in ipairs(ns.MissingItemRows and ns.MissingItemRows() or {}) do
			if ns.MissingItemOn(row) then
				SampleIcon(item, health, RowTexture(row))
				break
			end
		end
	end
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
-- 9. Cooldown ready: a sound and a glow when a cooldown you watch ends
--------------------------------------------------------------------------------

-- The sound is the player's pick for the class (ns.GetReadySound, section 2,
-- D-043), default the ready check.
-- Seconds the icon glows. Not until you cast it: a ready spell you keep for
-- later would then hold the HUD awake (ShouldShow) and defeat hide when idle.
local READY_GLOW_TIME = 5

local watchIDs   = {} -- spell ID the game uses now -> name, for each spell you turned on and know
local baseIDs    = {} -- that ID -> the ID you know, when an override replaces it
local onCooldown = {} -- spell ID -> GetTime() when an event saw its cooldown start
local lateStart  = {} -- spell ID -> true when only the look one frame later saw that start
local readyLit   = {} -- spell ID -> GetTime() when its glow went on
local litBase    = {} -- spell ID -> the base ID lit with it, while it glows

-- No watched cooldown is this short. A start that only the look one frame
-- later saw read isOnGCD outside its event (SpellSharedDocumentation.lua:30);
-- if that "cooldown" ends sooner, it was a global cooldown read as the
-- spell's own, and it ends with no sound. A start seen in the event is
-- real, so a reset soon after it (Cold Snap) still rings.
local MIN_COOLDOWN = 3

-- The ID the game uses now for a spell you know: its override (a talent or
-- form can replace one spell with another, C_Spell.GetOverrideSpell, which
-- returns the ID itself when there is none) or the spell itself.
local function EffectiveID(id)
	local get = C_Spell.GetOverrideSpell
	if not get then return id end
	local ok, over = pcall(get, id)
	over = ok and Plain(over) or nil
	if type(over) == "number" and over > 0 then return over end
	return id
end

-- The plain charge info of a spell with two or more charges, or nil. Its
-- isActive is true while a charge is coming back (NeverSecret,
-- SpellSharedDocumentation.lua:6-15).
local function ChargeInfo(id)
	if not C_Spell.GetSpellCharges then return nil end
	local ok, info = pcall(C_Spell.GetSpellCharges, id)
	if not ok or type(info) ~= "table" then return nil end
	local max = Plain(info.maxCharges)
	if type(max) ~= "number" or max < 2 then return nil end
	return info
end

-- True while a school lockout holds the spell. An interrupted cast locks
-- every spell of its school, and the game shows that as a cooldown on each.
-- Its own info says so plainly (SpellLossOfControlInfo.isActive,
-- NeverSecret, SpellSharedDocumentation.lua). A secret answer is unknown:
-- treated as locked, so it is never a start.
local function LockedOut(id)
	local get = C_Spell.GetSpellLossOfControlCooldownInfo
	if not get then return false end
	local ok, info = pcall(get, id)
	if not ok or type(info) ~= "table" then return false end
	local active = info.isActive
	if IsSecret(active) then return true end
	return active == true
end

-- Only in SPELL_UPDATE_COOLDOWN or SPELL_UPDATE_CHARGES (and its look one
-- frame later): true when the spell's own cooldown runs. The global
-- cooldown alone is false, and so are a school lockout and a secret or
-- missing answer: unknown is never "on cooldown".
local function CooldownStarted(id)
	if LockedOut(id) then return false end
	local charges = ChargeInfo(id)
	if charges then return Plain(charges.isActive) == true end
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or type(info) ~= "table" then return false end
	if Plain(info.isActive) ~= true then return false end
	local gcd = info.isOnGCD
	if IsSecret(gcd) then return false end
	-- DK's probe log: with isActive true, isOnGCD is always true or false;
	-- nil came only with isActive false.
	return gcd == false
end

-- Safe at any time: true when the game plainly says the spell is ready
-- again (isActive false). A spell with charges is ready when every charge
-- is back. A secret or missing answer is not ready.
local function ReadyAgain(id)
	local charges = ChargeInfo(id)
	if charges then return Plain(charges.isActive) == false end
	return OffCooldown(id) == true
end

-- Only in the event: true when the spell's own cooldown is over and only
-- the global cooldown is left on it (isOnGCD true). DK's probe log
-- (TICK-0156) shows this when a cooldown ends during other casts; the
-- ticker would see it only after the global cooldown.
local function OnlyGCDLeft(id)
	if ChargeInfo(id) then return false end
	local ok, info = pcall(C_Spell.GetSpellCooldown, id)
	if not ok or type(info) ~= "table" then return false end
	return Plain(info.isActive) == true and Plain(info.isOnGCD) == true
end

-- The same reads for the timer bars (TimerBars.lua, TICK-0158), so both
-- parts agree on when a cooldown starts and ends.
ns.CooldownReads = {
	EffectiveID     = EffectiveID,
	ChargeInfo      = ChargeInfo,
	CooldownStarted = CooldownStarted,
	ReadyAgain      = ReadyAgain,
	OnlyGCDLeft     = OnlyGCDLeft,
}

-- True when a HUD icon shows the spell (its ID now, or the base ID).
local function OnHUD(id)
	local hud = ns.HUDini
	local spells = hud and hud.spells
	if type(spells) ~= "table" then return false end
	local base = litBase[id]
	for _, e in ipairs(spells) do
		if e.spellID == id or (base and e.spellID == base) then return true end
	end
	return false
end

-- True while a ready glow is on a HUD icon: ShouldShow (Core.lua) wakes the
-- HUD. A watched spell with no icon only rings: there is no glow to see.
function ns.ReadyGlowLit()
	for id in pairs(readyLit) do
		if OnHUD(id) then return true end
	end
	return false
end

-- One source per spell, so two spells ready at once both glow. The base ID
-- glows too, for an icon that shows the spell by the ID you know.
local function Glow(id, base, on)
	if not (ns.HUDini and ns.HUDini.SetAlertGlow) then return end
	ns.HUDini:SetAlertGlow("cooldown:" .. id, on and id or nil)
	if base then ns.HUDini:SetAlertGlow("cooldown_base:" .. id, on and base or nil) end
end

local function Unlight(id)
	if not readyLit[id] then return end
	readyLit[id] = nil
	local base = litBase[id]
	litBase[id] = nil
	Glow(id, base, false)
end

local function Ready(id)
	local since, late = onCooldown[id], lateStart[id]
	onCooldown[id], lateStart[id] = nil, nil
	if late and since and GetTime() - since < MIN_COOLDOWN then return end
	ns.PlayAlertSound(ns.GetReadySound(), ns.READY_SOUND_DEFAULT)
	-- readyLit first: SetAlertGlow asks ShouldShow at once.
	readyLit[id] = GetTime()
	litBase[id] = baseIDs[id]
	Glow(id, litBase[id], true)
end

local readyTicker
local function SetReadyTicker()
	readyTicker:Set(next(onCooldown) ~= nil or next(readyLit) ~= nil)
end

-- The ticker never marks a spell "on cooldown": it only finds the end, and
-- puts out a glow when its time is up.
readyTicker = ns.Ticker(0.5, function()
	for id in pairs(onCooldown) do
		if ReadyAgain(id) then Ready(id) end
	end
	local now = GetTime()
	for id, since in pairs(readyLit) do
		if now - since >= READY_GLOW_TIME then Unlight(id) end
	end
	SetReadyTicker()
end)

-- The event reads every watched spell, not only the event's spell ID: a
-- cast can start the cooldown of another rank, and the ID may be secret.
-- SPELL_UPDATE_CHARGES says nothing about isOnGCD, so it reads only the
-- spells with charges.
-- late: the look one frame later, outside the event, where isOnGCD can be
-- wrong. It only finds starts, and puts out no glow: a misread start there
-- must not end a glow you can see. Its only end is the safe ReadyAgain.
local function OnCooldownEvent(event, late)
	local chargesOnly = event == "SPELL_UPDATE_CHARGES"
	for id in pairs(watchIDs) do
		if not chargesOnly or ChargeInfo(id) then
			if not onCooldown[id] then
				if CooldownStarted(id) then
					onCooldown[id] = GetTime()
					if late then
						lateStart[id] = true
					else
						-- Cast again while it glowed: the glow has done its job.
						Unlight(id)
					end
				end
			elseif ReadyAgain(id) or (not late and OnlyGCDLeft(id)) then
				Ready(id)
			end
		end
	end
	SetReadyTicker()
end

-- Rebuild the watch from your choices: a spell you turned off, or no longer
-- know, drops out with its glow. A spell whose ID changed (a new override)
-- keeps its "on cooldown", so its end still rings.
function ns.RefreshReadyAlerts()
	local was, wasLate = {}, {}
	for id, since in pairs(onCooldown) do
		if watchIDs[id] then
			was[watchIDs[id]] = since
			wasLate[watchIDs[id]] = lateStart[id]
		end
	end
	wipe(watchIDs)
	wipe(baseIDs)
	wipe(onCooldown)
	wipe(lateStart)
	if HUDiniDB and ns.ClassToken() then
		-- Your saved choices, and the class file's spells that start on
		-- (D-047): ns.GetReadyAlert says which are on. One you do not know
		-- yet makes no sound; SPELLS_CHANGED looks again when you learn it.
		local names = {}
		local saved = ns.ClassDB().readyAlerts
		if type(saved) == "table" then
			for name in pairs(saved) do names[name] = true end
		end
		local starts = ns.ClassDefault and ns.ClassDefault("readyAlertOn")
		if type(starts) == "table" then
			for _, name in ipairs(starts) do
				if type(name) == "string" then names[name] = true end
			end
		end
		for name in pairs(names) do
			local known = ns.GetReadyAlert(name) and Known(name)
			if known then
				local id = EffectiveID(known)
				watchIDs[id] = name
				if id ~= known then baseIDs[id] = known end
				onCooldown[id] = was[name]
				lateStart[id] = wasLate[name]
			end
		end
	end
	for id in pairs(readyLit) do
		if not watchIDs[id] then Unlight(id) end
	end
	SetReadyTicker()
end

-- True when a watched spell's override changed with no SPELLS_CHANGED (a
-- form or a proc can swap it): the watch reads stale IDs until rebuilt.
local function OverrideMoved()
	for id in pairs(watchIDs) do
		if EffectiveID(baseIDs[id] or id) ~= id then return true end
	end
	return false
end

-- A shared cooldown (Earth Shock starts Flame Shock's) fires no event of
-- its own and can land after the event: look at every watched spell again
-- on the next frame, for starts only (OnCooldownEvent, late).
local recheckDue = false
local function Recheck()
	recheckDue = false
	OnCooldownEvent("SPELL_UPDATE_COOLDOWN", true)
end

local readyEvents = CreateFrame("Frame")
pcall(readyEvents.RegisterEvent, readyEvents, "PLAYER_ENTERING_WORLD")
pcall(readyEvents.RegisterEvent, readyEvents, "SPELLS_CHANGED")
pcall(readyEvents.RegisterEvent, readyEvents, "SPELL_UPDATE_COOLDOWN")
pcall(readyEvents.RegisterEvent, readyEvents, "SPELL_UPDATE_CHARGES")
readyEvents:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
		ns.RefreshReadyAlerts()
		return
	end
	if OverrideMoved() then ns.RefreshReadyAlerts() end
	OnCooldownEvent(event)
	if event == "SPELL_UPDATE_COOLDOWN" and next(watchIDs) and not recheckDue then
		recheckDue = true
		C_Timer.After(0, Recheck)
	end
end)

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
	UpdateItemIcon()
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
	local watched = {}
	for id, name in pairs(watchIDs) do
		watched[#watched + 1] = name .. (onCooldown[id] and " (on cooldown)" or "")
			.. (readyLit[id] and " (glowing)" or "")
	end
	table.sort(watched)
	out("  Cooldown ready alerts                 " .. (#watched > 0 and table.concat(watched, ", ") or "none"))
	-- Missing items (TICK-0182): each row, and each item ID with the game's
	-- name for it and the count in your bags. A name proves the ID.
	local rows = ns.MissingItemRows and ns.MissingItemRows() or {}
	out("  Missing item rows                     " .. #rows)
	for _, row in ipairs(rows) do
		local spell = row.make or (type(row.needs) == "table" and table.concat(row.needs, ", ")) or row.needs
		out("    " .. row.key .. ": " .. (row.make and "make " or "needs ") .. tostring(spell)
			.. ", known " .. Mark(RowKnown(row)) .. ", on " .. Mark(ns.MissingItemOn(row))
			.. (row.buff and (", buff " .. tostring(row.buff) .. " on " .. Mark(BuffOn(row.buff))) or ""))
		for _, id in ipairs(row.items) do
			local name
			local get = C_Item and C_Item.GetItemNameByID
			if get then
				local okName, got = pcall(get, id)
				name = okName and Plain(got) or nil
			end
			if type(name) ~= "string" or name == "" then
				name = "|cffff9933no name: a wrong ID, or not loaded yet (ask again)|r"
				if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
			end
			out("      item " .. tostring(id) .. ": " .. name .. ", in bags " .. tostring(ItemCount(id) or "cannot tell"))
		end
	end
	out("  Missing item icon now                 " .. Mark(itemIcon and itemIcon:IsShown()))
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
