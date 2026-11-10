--[[--------------------------------------------------------------------------
	HUDini - Auras

	Buff time on the icon that gives the buff. A self-buff on you shows its
	time left on the icon that casts it. Eat, and the food icon counts down.

	Matching goes by name, not spell ID. Every rank of a spell shares one name
	with the buff it puts on you, so one rule covers them all, and it does not
	care that Forever's spell IDs differ from Retail's.

		spell icon -> the spell's own name
		item icon  -> the spell the item casts when used ("Food", "Drink")
		then       -> extra names: shared and class pairings (ns.AuraMapFor,
		              Classes.lua), then your own HUDiniDB.auraMap

	Secrets: auras can be secret in combat, and reading one then throws. Every
	read sits in a pcall. The time goes into a Cooldown widget as a
	DurationObject, which keeps ticking on its own. When a read fails the icon
	is left as it was, so a buff seen before the fight keeps counting down.
----------------------------------------------------------------------------]]

local ADDON, ns = ...
local Text = ns.Text

local HUDini = ns.HUDini
local Plain    = ns.Plain

--------------------------------------------------------------------------------
-- Which buff names belong to an icon
--------------------------------------------------------------------------------

local function SourceName(entry)
	if entry.spellID then
		return C_Spell.GetSpellName(entry.spellID)
	end
	if entry.itemID and C_Item.GetItemSpell then
		return (C_Item.GetItemSpell(entry.itemID))
	end
	return nil
end

local function AddNames(list, seen, names)
	if not names then return end
	for _, name in ipairs(names) do
		if not seen[name] then
			seen[name] = true
			list[#list + 1] = name
		end
	end
end

-- Every buff name that counts for one spell or item name: its own, the
-- shared and class pairings, then yours.
local function AuraNamesFor(source)
	local list, seen = {}, {}
	AddNames(list, seen, { source })
	AddNames(list, seen, ns.AuraMapFor(source))
	AddNames(list, seen, HUDiniDB.auraMap and HUDiniDB.auraMap[source])
	return list
end

ns.AuraNamesFor = AuraNamesFor

-- Built once per scan and kept on the entry.
local function AuraNames(entry)
	if entry.auraNames then return entry.auraNames end

	local source = Plain(SourceName(entry))
	-- Item data can arrive late. Only keep a list that found its source.
	if not source then return {} end
	entry.auraNames = AuraNamesFor(source)
	return entry.auraNames
end

ns.AuraNames = AuraNames

--------------------------------------------------------------------------------
-- Reading your buffs
--------------------------------------------------------------------------------

-- True unless the game plainly says your auras read as they are. The game
-- hides them under its addon restriction (a fight, an encounter, a keystone,
-- PvP, some maps), and a hidden aura is not found by name
-- (RequiresNonSecretAura). That restriction has its own state, apart from
-- InCombatLockdown and UnitAffectingCombat (TICK-0125). No answer, an error
-- or a secret answer count as hidden. A client without the question leaves
-- it to the lookup.
local function AurasHidden()
	local secrets = _G.C_Secrets
	local ask = secrets and secrets.ShouldAurasBeSecret
	if type(ask) ~= "function" then return false end
	local ok, hidden = pcall(ask)
	return not (ok and Plain(hidden) == false)
end

-- How long each buff lasts, by its name, as last read while your auras
-- read (TICK-0135). A fight hides your auras, so a buff cast in it has no
-- time HUDini can read: OnCast gives it this one, from the cast.
local lasts = {}

local function NoteLength(name, data)
	local ok, length = pcall(function() return data.duration end)
	length = ok and Plain(length) or nil
	if type(length) == "number" and length > 0 then lasts[name] = length end
end

-- The aura's instance ID and data, false when you surely do not have it, or
-- nil when the game will not say. Not found while your auras are hidden is
-- "will not say".
local function FindAura(name)
	local ok, data = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
	if not ok then return nil end
	if data == nil then
		if AurasHidden() then return nil end
		return false
	end

	local okID, id = pcall(function() return data.auraInstanceID end)
	if not okID then return nil end
	NoteLength(name, data)
	return Plain(id), data
end

local function ShowTime(f, instanceID)
	local ok, duration = pcall(C_UnitAuras.GetAuraDuration, "player", instanceID)
	if not (ok and duration) then return false end
	if not pcall(f.buff.SetCooldownFromDurationObject, f.buff, duration) then return false end
	f.buff:Show()
	return true
end

local function ClearTime(f)
	if f.buff.Clear then f.buff:Clear() end
	f.buff:Hide()
end

function ns.UpdateIconAuras()
	local db = HUDiniDB
	if not db then return end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and C_UnitAuras.GetAuraDuration) then
		return
	end

	for i = 1, #HUDini.spells do
		local f = HUDini.icons[i]
		local e = HUDini.spells[i]
		if f and e and f.buff then
			if not db.showBuffTime then
				ClearTime(f)
			else
				-- First name that answers wins. One that cannot tell leaves the
				-- icon alone, rather than wiping a timer that is still right.
				local found, unknown = nil, false
				for _, name in ipairs(AuraNames(e)) do
					local id = FindAura(name)
					if id then found = id break end
					if id == nil then unknown = true end
				end

				-- Always re-hand the duration: a recast buff can keep its
				-- instance ID and only move its end time.
				if found then
					ShowTime(f, found)
				elseif not unknown then
					ClearTime(f)
				end
			end
		end
	end

	ns.UpdateBuffMissing()
end

--------------------------------------------------------------------------------
-- Buffs to reapply
--
-- A spell counts as "keep this on me" once HUDini has seen its buff on you
-- lasting 5 minutes or more, or with no end at all (a paladin aura). A
-- tracking buff and a state (Stealth, a form, a mount) never count; see
-- below. Learned per class, in HUDiniDB.classes[CLASS].buffSpells. Short self-buffs
-- (Ice Block, Evocation) and combat shields never count, or the HUD would
-- never hide.
--
-- Two ways in: a spell on the grid whose buff is on you, and any timed buff
-- on you that you cast with a spell you know. The second catches buffs kept
-- on a bar the grid does not read (Bar 4 and up in "one row per action bar").
--
-- ns.buffMissing is true while a learned buff spell you know has none of its
-- buffs on you, on the grid or not. Core.lua shows the HUD for it, and
-- ns.missingBuffID (the first one, grid order, then by name) is the icon
-- Alerts.lua puts by your health bar.
--
-- A fight can hide your auras. Then HUDini goes by what it last saw: a buff
-- that was on stays on until its end time, and a buff you cast counts as on,
-- until the end its length last read gives (TICK-0135).
-- A buff it never saw and cannot read never counts as missing. In a fight a
-- "not found" is not trusted either: a lookup by name can miss an aura whose
-- name is secret, so only a buff seen off before the fight counts as off.
-- Nor is it trusted while the game says your auras are hidden, with or
-- without a fight (AurasHidden, TICK-0125): the moments around a fight
-- once taught HUDini a buff was off while it was on.
--
-- A tracking buff (Sense Undead, Find Herbs, Track Beasts) only says what
-- the minimap shows. It has no end, but it is never a buff to keep up, so it
-- is never learned, and one learned before is dropped (TICK-0056).
--
-- A state (Stealth, a druid form, Ghost Wolf, Shadowform, a stance, a mount,
-- Feign Death) has no end, or one so long that it counts as none, but you leave it on purpose: out of it is not "missing"
-- (TICK-0062). Never learned, and one learned before is dropped. A paladin
-- aura is not a state: it is a buff to keep up.
--
-- A long buff for one job (Unending Breath, Water Walking, Detect
-- Invisibility, Righteous Fury) is cast when the job comes, not kept up, so
-- its end is not "missing" either (TICK-0064). Never learned, and one learned
-- before is dropped.
--------------------------------------------------------------------------------

local LONG_BUFF = 300   -- seconds

-- Tracking spells by name, for a client whose minimap list cannot be read.
-- Each is a set of the enUS names and the client's own (Classes.lua,
-- TICK-0024): call it to get the set.
-- locale: skip the game's spell names
local TRACKING = ns.NameSet({
	"Find Fish", "Find Herbs", "Find Minerals",
	"Find Treasure", "Sense Demons", "Sense Undead",
	"Track Beasts", "Track Demons", "Track Dragonkin",
	"Track Elementals", "Track Giants", "Track Hidden",
	"Track Humanoids", "Track Undead",
})

-- States by name: enUS and the client's own, from SPELL_IDS (TICK-0024).
-- FormName also catches a form while you are in it, and IsMount a mount the
-- mount journal knows. Prowl runs inside Cat Form (the form is Cat Form),
-- Shadowmeld and Feign Death have no form, and Stealth may have no form ID:
-- the name catches those.
local STATES = ns.NameSet({
	"Stealth", "Prowl", "Shadowmeld", "Feign Death",
	"Bear Form", "Dire Bear Form", "Cat Form",
	"Travel Form", "Aquatic Form", "Moonkin Form",
	"Tree of Life", "Flight Form", "Swift Flight Form",
	"Ghost Wolf", "Shadowform",
	"Battle Stance", "Defensive Stance", "Berserker Stance",
	-- Class mounts: the journal may not know their spell IDs on this client.
	"Summon Warhorse", "Summon Charger",
	"Summon Felsteed", "Summon Dreadsteed",
})

-- Long buffs for one job, by name: enUS and the client's own (TICK-0024).
-- Righteous Fury
-- is on the list for the paladin who does not tank; a tank loses the
-- reminder for it, as HUDini cannot tell the two apart. A priest casts Fear
-- Ward or Shadow Protection for one pull; both of the Shadow Protection pair
-- (Classes.lua) are here, so neither is learned.
local ONE_JOB = ns.NameSet({
	"Unending Breath", "Water Walking", "Water Breathing",
	"Detect Lesser Invisibility", "Detect Invisibility",
	"Detect Greater Invisibility", "Righteous Fury",
	"Fear Ward", "Shadow Protection", "Prayer of Shadow Protection",
})
-- locale: end

-- The spells in the minimap's tracking list, by name, in the client's own
-- language. Kept only once every entry could be read, and read again after
-- your spells change (SPELLS_CHANGED) or a loading screen. A name or kind
-- the game hides leaves a gap, and a list with a gap is not kept: nothing
-- secret is ever looked up.
local minimapTracking
-- A list with a gap, kept for one ns.UpdateBuffMissing only, so one update
-- reads the list once, not once for each buff it checks.
local passTracking, inPass = nil, false

-- One entry of the list: read, name, kind. read is false when the entry
-- could not be read: the read threw, the name or the kind is secret (in a
-- fight), or there is no name yet. A plain entry with no kind is read; it
-- only does not count.
local function TrackingInfo(i)
	local ok, info, _, _, kind = pcall(C_Minimap.GetTrackingInfo, i)
	if not ok or ns.IsSecret(info) then return false end
	-- 12.x hands back a table; older clients hand back name, texture,
	-- active, kind.
	if type(info) == "table" then
		local okRead, name, kindRead = pcall(function() return info.name, info.type end)
		if not okRead then return false end
		info, kind = name, kindRead
	end
	-- A secret kind is not read either: a list kept without that entry could
	-- let its tracking buff be learned in a fight.
	if ns.IsSecret(info) or ns.IsSecret(kind) or type(info) ~= "string" then return false end
	return true, info, kind
end

local function MinimapTracking()
	if minimapTracking then return minimapTracking end
	if inPass and passTracking then return passTracking end
	if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return {} end
	local ok, count = pcall(C_Minimap.GetNumTrackingTypes)
	count = ok and Plain(count)
	if type(count) ~= "number" or count < 1 then return {} end
	local names, complete = {}, true
	for i = 1, count do
		-- Only kind "spell" counts. Town services (Banker, Flight Master)
		-- are kind "other", and a missing or odd kind counts as not
		-- tracking: dropping a saved buff cannot be undone.
		local read, name, kind = TrackingInfo(i)
		if not read then
			complete = false
		elseif kind == "spell" then
			names[name] = true
		end
	end
	-- A list with a gap is used for this update only and read again next
	-- time, so a fight cannot leave it short until the next loading screen.
	if complete then
		minimapTracking = names
	elseif inPass then
		passTracking = names
	end
	return names
end

-- True for a tracking buff. source is always a plain name here.
local function IsTracking(source)
	return TRACKING()[source] or MinimapTracking()[source] or false
end
ns.IsTrackingBuff = IsTracking

-- The name of the form you are in now (a druid form, Stealth, Ghost Wolf,
-- Shadowform, a stance), or nil. A form has a form ID; a paladin aura on
-- the stance bar has none. Every read is in a pcall and must be plain.
local function ReadFormName()
	if not (GetShapeshiftFormID and GetShapeshiftForm and GetShapeshiftFormInfo) then return nil end
	local okID, formID = pcall(GetShapeshiftFormID)
	if not (okID and Plain(formID)) then return nil end
	local okIndex, index = pcall(GetShapeshiftForm)
	index = okIndex and Plain(index)
	if type(index) ~= "number" or index < 1 then return nil end
	local okInfo, _, _, _, spellID = pcall(GetShapeshiftFormInfo, index)
	spellID = okInfo and Plain(spellID)
	return spellID and Plain(C_Spell.GetSpellName(spellID)) or nil
end

-- Read once for each ns.UpdateBuffMissing: it checks every learned buff.
local passForm, passFormRead = nil, false
local function FormName()
	if not inPass then return ReadFormName() end
	if not passFormRead then passForm, passFormRead = ReadFormName(), true end
	return passForm
end

local function SummonsMount(id)
	if type(id) ~= "number" then return false end
	local ok, mountID = pcall(C_MountJournal.GetMountFromSpell, id)
	return ok and Plain(mountID) ~= nil
end

-- True when the spell summons a mount. spellID is the ID you have (the
-- grid's or the aura's): a mount from the journal is not in your spellbook,
-- so a lookup by name can fail. The name is the fallback.
local function IsMount(source, spellID)
	if not (C_MountJournal and C_MountJournal.GetMountFromSpell) then return false end
	if spellID and SummonsMount(spellID) then return true end
	local id = ns.SpellID(source)
	return id ~= nil and SummonsMount(id)
end

-- True for a state you leave on purpose. source is always a plain name.
local function IsState(source, spellID)
	return STATES()[source] or source == FormName() or IsMount(source, spellID) or false
end
ns.IsStateBuff = IsState

-- A learned buff that is tracking, a state or one job (TICK-0056, TICK-0062,
-- TICK-0064) is never one to keep up: drop it. Learn never adds one, so
-- this changes your saved settings only if one of those lists grew.
local function DropNotToKeep(learned)
	for source in pairs(learned) do
		if ONE_JOB()[source] or IsTracking(source) or IsState(source) then
			learned[source] = nil
		end
	end
end

-- spellID: the spell ID you have for it, the grid's or the aura's (see IsMount).
local function Learn(source, data, spellID)
	if ONE_JOB()[source] or IsTracking(source) or IsState(source, spellID) then return end
	local ok, duration = pcall(function() return data.duration end)
	duration = ok and Plain(duration) or nil
	if duration and (duration == 0 or duration >= LONG_BUFF) then
		local mine = ns.ClassDB()
		mine.buffSpells = mine.buffSpells or {}
		mine.buffSpells[source] = true
	end
end

-- Every timed buff on you that you cast, with a spell you know. Food,
-- potions and other people's buffs are not yours to cast, so they never
-- count. Buffs with no end (forms, stealth, mounts) come only from the grid,
-- or Cat Form would ask to be kept up.
local function LearnFromYourBuffs()
	if not C_UnitAuras.GetAuraDataByIndex then return end
	for i = 1, 40 do
		local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL|PLAYER")
		if not ok or data == nil then return end
		local okRead, name, spellID = pcall(function() return data.name, data.spellId end)
		name, spellID = okRead and Plain(name), okRead and Plain(spellID)
		local okDur, duration = pcall(function() return data.duration end)
		duration = okDur and Plain(duration) or nil
		if name and spellID and duration and duration >= LONG_BUFF
				and IsPlayerSpell and IsPlayerSpell(spellID) then
			Learn(name, data, spellID)
		end
	end
end

-- What HUDini last saw of each buff: seen[source] = { on = bool, ends = t }.
local seen = {}

-- An aura's end time, or nil for one with no end (or one the game hides).
local function EndOf(data)
	local ok, t = pcall(function() return data.expirationTime end)
	t = ok and Plain(t) or nil
	if t and t > 0 then return t end
	return nil
end

local function Remember(source, data)
	seen[source] = { on = data ~= nil, ends = data and EndOf(data) or nil }
end

-- The last answer, aged: a buff past its end time is off. nil if never seen.
local function Recall(source)
	local s = seen[source]
	if not s then return nil end
	if s.on and s.ends and GetTime() >= s.ends - 0.5 then return false end
	return s.on
end


-- true on, false off, nil when the game will not say and HUDini never saw it.
-- learnID: the grid's spell ID, to learn the buff from; nil to only check.
-- With two of the names on (Ice Barrier and Mana Shield), the one that ends
-- last is remembered: one with no end beats any end time.
local function BuffState(source, names, learnID)
	local unknown = ns.InCombat()
	local last, lastEnds
	for _, name in ipairs(names) do
		local id, data = FindAura(name)
		if id then
			if not last and learnID then Learn(source, data, learnID) end
			local ends = EndOf(data)
			if not last or (lastEnds and (not ends or ends > lastEnds)) then
				last, lastEnds = data, ends
			end
		elseif id == nil then
			unknown = true
		end
	end
	if last then
		Remember(source, last)
		return true
	end
	if unknown then return Recall(source) end
	Remember(source, nil)
	return false
end

-- The keep-up list (Alerts.lua, alert 2) counts as one buff: on while any of
-- it is on. Its icon shows only in a fight, and a fight hides your auras: a
-- hidden aura is not found by name, with no error
-- (SecretPredicatesDocumentation.lua:28-30 and :80-82, wow-ui-source forever
-- 9dc84f0). So it goes by what HUDini last saw, as your buffs do (TICK-0130).
-- The key cannot be a spell name.
local KEEP_UP = "keepUp"

-- The list by the client's names: a spell ID typed in by hand is looked up.
local function KeepUpNames(list)
	local names = {}
	for _, spell in ipairs(type(list) == "table" and list or {}) do
		local name = spell
		if type(spell) == "number" then name = Plain(C_Spell.GetSpellName(spell)) end
		if type(name) == "string" and name ~= "" then names[#names + 1] = name end
	end
	return names
end

-- true when one of the list is on, false when none is, nil when the game
-- will not say and HUDini never saw it.
function ns.KeepUpState(list)
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
	return BuffState(KEEP_UP, KeepUpNames(list))
end

function ns.UpdateBuffMissing()
	passTracking, inPass = nil, true
	passForm, passFormRead = nil, false
	LearnFromYourBuffs()
	local missingID
	if HUDiniDB and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local learned = ns.ClassDB().buffSpells or {}
		DropNotToKeep(learned)
		local checked = {}
		for _, e in ipairs(HUDini.spells) do
			local source = e.spellID and Plain(C_Spell.GetSpellName(e.spellID))
			if source and not checked[source] then
				checked[source] = true
				-- A learned mount, by its spell ID (DropNotToKeep has only
				-- the name).
				if learned[source] and IsState(source, e.spellID) then learned[source] = nil end
				local on = BuffState(source, AuraNames(e), e.spellID)
				if learned[source] and on == false and not missingID then missingID = e.spellID end
			end
		end

		-- Learned buffs off the grid, by name, while you still know the spell.
		local rest = {}
		for source in pairs(learned) do
			if not checked[source] then rest[#rest + 1] = source end
		end
		table.sort(rest)
		for _, source in ipairs(rest) do
			local id = ns.SpellID(source)
			if id and IsPlayerSpell and IsPlayerSpell(id)
					and BuffState(source, AuraNamesFor(source)) == false and not missingID then
				missingID = id
			end
		end
	end
	passTracking, inPass = nil, false
	ns.buffMissing   = missingID ~= nil
	ns.missingBuffID = missingID
	if ns.UpdateOwnBuffIcon then ns.UpdateOwnBuffIcon() end
end

-- A buff you cast is on, to the end its length gives (nil: no end known).
-- One still on that ends later, or never, stays: with two of the keep-up
-- list on, the later end counts (BuffState).
local function CastOn(source, ends)
	local s = seen[source]
	if ends and Recall(source) and (s.ends == nil or s.ends > ends) then return end
	seen[source] = { on = true, ends = ends }
end

-- The icons that give the cast buff count its time from the cast, while
-- your auras are hidden (TICK-0135). The UNIT_AURA for it leaves a hidden
-- icon alone, before or after this. Readable auras need none of this: the
-- aura's own time goes on the icon (UpdateIconAuras).
local function TimeCast(cast, length, now)
	if not (length and HUDiniDB.showBuffTime and AurasHidden()) then return end
	for i = 1, #HUDini.spells do
		local f, e = HUDini.icons[i], HUDini.spells[i]
		if f and e and f.buff then
			for _, name in ipairs(AuraNames(e)) do
				if name == cast then
					if pcall(f.buff.SetCooldown, f.buff, now, length) then f.buff:Show() end
					break
				end
			end
		end
	end
end

-- A buff you cast counts as on, for the times the game hides your auras.
-- Cast on someone else in a fight, it fools HUDini until your auras read
-- again; out of combat the aura itself always wins. Its end comes from how
-- long the buff lasted when HUDini last read it; with none known it stays
-- on until your auras read again.
local function OnCast(spellID)
	spellID = Plain(spellID)
	local cast = spellID and Plain(C_Spell.GetSpellName(spellID))
	if not cast then return end
	local now, length = GetTime(), lasts[cast]
	local ends = length and now + length or nil
	TimeCast(cast, length, now)
	for source in pairs(ns.ClassDB().buffSpells or {}) do
		for _, name in ipairs(AuraNamesFor(source)) do
			if name == cast then CastOn(source, ends) break end
		end
	end
	ns.UpdateBuffMissing()
	-- A keep-up spell you cast counts as on. Its UNIT_AURA may come before
	-- this event, so look at the keep-up icon again.
	for _, name in ipairs(KeepUpNames(ns.ClassValue("keepUp"))) do
		if name == cast then
			CastOn(KEEP_UP, ends)
			if ns.UpdateAlerts then ns.UpdateAlerts() end
			break
		end
	end
end

--------------------------------------------------------------------------------
-- Weapon buffs
--
-- Rockbiter Weapon and its kin sit on the weapon as an enchant. Retail reads
-- that with GetWeaponEnchantInfo, but on Forever it answers "none" while the
-- buff frame and the weapon's tooltip both show the buff. So the tooltip
-- counts too: a line with the buff's first word ("Rockbiter"). So does a buff
-- on you with the spell's name. The class file lists them (weaponBuff); once
-- you know any one, each weapon in your hands needs one. A shield, an empty
-- off hand or a fishing pole needs nothing. Asked fresh every
-- time, so it needs no event, and an unreadable answer never counts as
-- missing.
--------------------------------------------------------------------------------

local MAIN_HAND, OFF_HAND = 16, 17

local function KnowsAny(spells)
	for _, spell in ipairs(spells) do
		local id = ns.SpellID(spell)
		if id and IsPlayerSpell and IsPlayerSpell(id) then return true end
	end
	return false
end

-- A fishing pole is a weapon too, but nobody buffs one. Its weapon kind
-- (subclass 20) says so in every language, from the item ID alone
-- (TICK-0024).
local FISHING_POLE = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole or 20

local function ItemInfo(itemID)
	local info = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	return info(itemID)
end

local function IsFishing(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then return false end
	return select(7, ItemInfo(itemID)) == FISHING_POLE
end

local function HoldsWeapon(slot)
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then return false end
	local classID = select(6, ItemInfo(itemID))
	return classID == Enum.ItemClass.Weapon and not IsFishing(slot)
end

-- Every line of the item's tooltip, as plain text. Nil when the game will
-- not say.
local function TooltipLines(slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return nil end
	local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slot)
	if not (ok and data) then return nil end
	local okLines, rows = pcall(function() return data.lines end)
	if not (okLines and type(rows) == "table") then return nil end
	local lines = {}
	for _, row in ipairs(rows) do
		local okText, text = pcall(function() return row.leftText end)
		if not okText or ns.IsSecret(text) then return nil end
		if type(text) == "string" and text ~= "" then lines[#lines + 1] = text end
	end
	return lines
end

-- The first tooltip line that test() likes, false for none, nil when the
-- game will not say.
local function TooltipFind(slot, test)
	local lines = TooltipLines(slot)
	if not lines then return nil end
	for _, text in ipairs(lines) do
		if test(text) then return text end
	end
	return false
end

-- "Rockbiter Weapon" shows on the weapon as "Rockbiter 3 (53 min)".
local function BuffWords(spells)
	local words = {}
	for _, spell in ipairs(spells) do
		words[#words + 1] = spell:match("^(%S+)") or spell
	end
	return words
end

-- A timed enchant ends its tooltip line with the time left, in the client's
-- own format (ITEM_ENCHANT_TIME_LEFT_*): "Lure +75 (10 min)", German
-- "(10 Min.)", Chinese "（10分钟）". Only those formats: a weapon's tooltip
-- also has "(0.7 damage per second)", "Requires Fishing (100)" and
-- "(1 Hour Cooldown)", and none of them is bait. With no format from the
-- client, the enUS one: a number and one word.
local TIMED = {}

-- A plural mark "|4hour:hours;" gives one format for each form, and the
-- format with the mark itself (below).
local function Forms(fmt, out)
	local pre, forms, post = fmt:match("^(.-)|4([^;]*);(.*)$")
	if not pre then
		out[#out + 1] = fmt
		return
	end
	for form in (forms .. ":"):gmatch("([^:]*):") do Forms(pre .. form .. post, out) end
end

for _, key in ipairs({ "DAYS", "HOURS", "MIN", "SEC" }) do
	local fmt = _G["ITEM_ENCHANT_TIME_LEFT_" .. key]
	if type(fmt) == "string" and fmt:find("%%d") then
		local forms = {}
		Forms(fmt, forms)
		-- The tooltip line can keep the mark as it is: "(1 |4hour:hrs;)".
		if fmt:find("|4", 1, true) then forms[#forms + 1] = fmt end
		for _, form in ipairs(forms) do
			-- "%s (%d hrs)" -> "^.- %(%d+ hrs%)$"
			local p = form:gsub("%%s", "\1"):gsub("%%d", "\2")
			p = p:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
			p = p:gsub("\1", ".-"):gsub("\2", "%%d+")
			TIMED[#TIMED + 1] = "^" .. p .. "$"
		end
	end
end
if #TIMED == 0 then TIMED[1] = "%(%d+ %a+%)$" end

local function Timed(text)
	for _, p in ipairs(TIMED) do
		if text:find(p) then return true end
	end
	return false
end

-- The buff on you, by the spell's name. Nil when the game will not say.
local function WeaponBuffOnYou(spells)
	local unknown = false
	for _, name in ipairs(spells) do
		local id = FindAura(name)
		if id then return name end
		if id == nil then unknown = true end
	end
	if unknown then return nil end
	return false
end

-- True, false, or nil when the game will not say.
local function HandBuffed(slot, has, words)
	if ns.IsSecret(has) then return nil end
	if has then return true end
	local found = TooltipFind(slot, function(text)
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then return true end
		end
		return false
	end)
	if found == nil then return nil end
	return found ~= false
end

function ns.WeaponBuffMissing()
	local spells = ns.ClassValue("weaponBuff")
	if not (spells and GetWeaponEnchantInfo and KnowsAny(spells)) then return false end
	if WeaponBuffOnYou(spells) ~= false then return false end
	local ok, hasMain, _, _, _, hasOff = pcall(GetWeaponEnchantInfo)
	if not ok then return false end
	local words = BuffWords(spells)
	for slot, has in pairs({ [MAIN_HAND] = hasMain, [OFF_HAND] = hasOff }) do
		if HoldsWeapon(slot) and HandBuffed(slot, has, words) == false then return true end
	end
	return false
end

-- For /hud debug weapon: what the game says, raw, and what HUDini makes of it.
-- locale: skip a debug report (/hud debug weapon), in English
function ns.WeaponBuffDetail()
	local spells = ns.ClassValue("weaponBuff") or {}
	local words = BuffWords(spells)
	local lines = {}

	local raw = { pcall(GetWeaponEnchantInfo) }
	for i = 1, #raw do raw[i] = ns.IsSecret(raw[i]) and "secret" or tostring(raw[i]) end
	lines[#lines + 1] = "GetWeaponEnchantInfo: " .. table.concat(raw, ", ")

	local onYou = WeaponBuffOnYou(spells)
	lines[#lines + 1] = "Weapon buff on you: " .. (onYou or (onYou == nil and "secret") or "none")

	-- Every buff on you, so a name Forever uses shows up here.
	if C_UnitAuras.GetAuraDataByIndex then
		local buffs = {}
		for i = 1, 40 do
			local okData, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
			if not okData then buffs[#buffs + 1] = "Error: " .. tostring(data) break end
			if not data then break end
			local okRead, name, id = pcall(function() return data.name, data.spellId end)
			name = okRead and Plain(name)
			if name then
				buffs[#buffs + 1] = ("%s (%s)"):format(name, tostring(Plain(id)))
			else
				buffs[#buffs + 1] = "secret"
			end
		end
		lines[#lines + 1] = "Buffs on you: " .. (#buffs > 0 and table.concat(buffs, ", ") or "none")
	end

	for _, hand in ipairs({
		{ "Main hand", MAIN_HAND },
		{ "Off hand", OFF_HAND },
	}) do
		local label, slot = hand[1], hand[2]
		local link = GetInventoryItemLink("player", slot)
		local name = link and link:match("%[(.-)%]") or "empty"
		local buffed = HandBuffed(slot, nil, words)
		lines[#lines + 1] = ("%s: %s. Needs a weapon buff: %s. Tooltip shows one: %s."):format(
			label, name, HoldsWeapon(slot) and "yes" or "no",
			buffed == nil and "cannot read" or (buffed and "yes" or "no"))
		-- The timed lines, or every line when none is timed.
		local all = link and TooltipLines(slot)
		if all then
			local timed = {}
			for _, text in ipairs(all) do
				if Timed(text) then timed[#timed + 1] = text end
			end
			lines[#lines + 1] = "  Tooltip: " .. table.concat(#timed > 0 and timed or all, " | ")
		end
	end
	return lines
end
-- locale: end

-- A fishing pole in your main hand: the bait warning can matter (Alerts.lua).
function ns.HoldsFishingPole()
	return IsFishing(MAIN_HAND)
end

-- Bait (Shiny Bauble, Nightcrawlers) goes on the pole as a timed enchant,
-- so a fishing pole in hand with no timed line has no bait. Every class.
function ns.BaitMissing()
	if not IsFishing(MAIN_HAND) then return false end
	if GetWeaponEnchantInfo then
		local ok, hasMain = pcall(GetWeaponEnchantInfo)
		if ok and hasMain and not ns.IsSecret(hasMain) then return false end
	end
	return TooltipFind(MAIN_HAND, Timed) == false
end

-- /hud buffs              list the tracked buffs
-- /hud buffs forget Name  stop tracking one
-- /hud buffs clear        forget them all
function ns.BuffsCommand(rest, say)
	local mine = ns.ClassDB()
	mine.buffSpells = mine.buffSpells or {}
	local forget = rest:match("^forget%s+(.+)$")
	if rest:lower() == "clear" then
		wipe(mine.buffSpells)
		say(Text("buffs.cleared"))
	elseif forget and mine.buffSpells[forget] == nil then
		say(Text("buffs.notTracked", forget))
	elseif forget then
		mine.buffSpells[forget] = nil
		say(Text("buffs.stopped", forget))
	else
		local names = {}
		for name in pairs(mine.buffSpells) do names[#names + 1] = name end
		table.sort(names)
		say(#names == 0 and Text("buffs.none") or Text("buffs.list", table.concat(names, ", ")))
	end
	ns.UpdateBuffMissing()
end

--------------------------------------------------------------------------------
-- Your own map entries
--
--     /hud auramap Conjure Mana Gem = Mana Gem
--     /hud auramap Conjure Mana Gem =        (removes it)
--     /hud auramap                           (lists them)
--------------------------------------------------------------------------------

function ns.AuraMapCommand(rest, say)
	HUDiniDB.auraMap = HUDiniDB.auraMap or {}
	local map = HUDiniDB.auraMap

	local spell, aura = rest:match("^(.-)%s*=%s*(.-)$")
	if not spell or spell == "" then
		local any = false
		for s, list in pairs(map) do
			say(s .. ": " .. table.concat(list, ", ") .. ".")
			any = true
		end
		if not any then say(Text("auramap.none")) end
		return
	end

	if aura == "" then
		map[spell] = nil
		say(Text("auramap.removed", spell))
	else
		map[spell] = map[spell] or {}
		tinsert(map[spell], aura)
		say(Text("auramap.added", spell, aura))
	end

	ns.ForgetAuraNames()
end

-- Rebuild every icon's buff names, after the pairs changed.
function ns.ForgetAuraNames()
	for _, e in ipairs(HUDini.spells) do e.auraNames = nil end
	ns.UpdateIconAuras()
end

--------------------------------------------------------------------------------
-- Buffs that stack: the Resource row's choices (TICK-0094)
--------------------------------------------------------------------------------

-- No spell says if its buff can stack, and most stacking buffs come from
-- talents, not from a spell on the action bars. So HUDini learns them: a buff
-- you cast, seen on you with 2 stacks or more, joins your class's list
-- with the most stacks seen (classes[token].stackBuffs[name] = count), and
-- the Resource row offers it (ns.ClassPickSpells). A first pick of it fills
-- at that count (ns.SetClassPick). The list only grows: a buff that stacked
-- once can stack again.
--
-- Not read in a fight: a proc that stacks only in a fight is learned if it
-- is still up when the fight ends (PLAYER_REGEN_ENABLED). Aura data can also
-- be secret on some maps, in PvP or in a keystone run; Plain then drops it
-- and nothing is learned there.
--
-- Secrets: in a fight the name and the stack count may be secret, and
-- comparing one throws. So this reads nothing in a fight, and Plain drops a
-- secret value before any compare. PLAYER_REGEN_ENABLED reads once more, for
-- a buff that is still up after the fight.
local function LearnStackingBuffs()
	if not (HUDiniDB and C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
	if ns.InCombat() then return end
	local mine
	for i = 1, 40 do
		local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL|PLAYER")
		if not ok or data == nil then return end
		local okRead, name, stacks = pcall(function() return data.name, data.applications end)
		if okRead then
			name, stacks = Plain(name), Plain(stacks)
			if type(name) == "string" and name ~= "" and type(stacks) == "number" and stacks >= 2 then
				mine = mine or ns.ClassDB()
				mine.stackBuffs = type(mine.stackBuffs) == "table" and mine.stackBuffs or {}
				local most = mine.stackBuffs[name]
				if type(most) ~= "number" or stacks > most then mine.stackBuffs[name] = stacks end
			end
		end
	end
end

ns.LearnStackingBuffs = LearnStackingBuffs

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

-- The one UNIT_AURA handler (TICK-0065). Its payload is not read: it is
-- secret while auras are secret. Your auras feed the resource bar (Bars.lua),
-- the icon auras and the alerts; your target's feed only the alerts.
-- Each runs on its own, so an error in one does not stop the others: it
-- goes to the error handler (BugSack, or the game's popup), as in Modules.lua.
local function Call(fn)
	if not fn then return end
	local ok, err = pcall(fn)
	if not ok then
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) else error(err, 0) end
	end
end

local function OnUnitAura(unit)
	if unit == "player" then
		Call(ns.UpdateResource)
		Call(ns.UpdateIconAuras)
		Call(LearnStackingBuffs)
	end
	Call(ns.UpdateAlerts)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, unit, _, spellID)
	if event == "UNIT_AURA" then
		OnUnitAura(unit)
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if HUDiniDB then OnCast(spellID) end
		return
	end
	if event == "SPELLS_CHANGED" then
		-- A new tracking spell joins the minimap's list: read it again.
		minimapTracking = nil
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		pcall(self.RegisterUnitEvent, self, "UNIT_AURA", "player", "target")
		pcall(self.RegisterUnitEvent, self, "UNIT_SPELLCAST_SUCCEEDED", "player")
		pcall(self.RegisterEvent, self, "PLAYER_REGEN_ENABLED")
		pcall(self.RegisterEvent, self, "SPELLS_CHANGED")
		-- Fired after a restriction ends, so your auras read again (TICK-0125).
		-- Also fired before one starts; it is not enforced until the event
		-- is done, so those reads are plain too.
		pcall(self.RegisterEvent, self, "ADDON_RESTRICTION_STATE_CHANGED")
		minimapTracking = nil
	end
	-- After a fight, a restriction or on login: a stacking buff still up is
	-- learned now, and your buffs read again.
	Call(LearnStackingBuffs)
	ns.UpdateIconAuras()
end)
