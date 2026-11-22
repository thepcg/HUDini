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
	DurationObject, which keeps ticking on its own. A fight hides your buffs
	from every read, so then the game's own aura container draws a spell's
	buff time and charges on its icon (TICK-0159, below). An icon with no
	container, and an item's icon, is left as it was when no read answers.
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
ns.AurasHidden = AurasHidden

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
	f.castTime = nil
	f.buff:Show()
	return true
end

local function ClearTime(f)
	f.castTime = nil
	if f.buff.Clear then f.buff:Clear() end
	f.buff:Hide()
end

-- A buff's charges (its stack count, the game's "applications") on its
-- icon, bottom right, where the game puts a stack count (TICK-0148). The
-- game makes the text: GetAuraApplicationDisplayCount gives "" under the
-- minimum. Minimum 1: the last charge shows, and a buff with no charges (0)
-- shows nothing. A restricted aura gives a secret string; SetText takes it
-- as it is, and nothing here compares or joins it. An item's icon keeps
-- that spot for the item count (Core.lua UpdateCounts), so it gets none.
local function ChargesText(f)
	if not f.charges then
		f.charges = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		f.charges:SetPoint("BOTTOMRIGHT", -1, 2)
		f.charges:SetJustifyH("RIGHT")
	end
	return f.charges
end

local function ClearCharges(f)
	if f.charges then f.charges:SetText("") end
end

-- A client without the call: the count, only when it reads plain. A read
-- that fails leaves the last text, as ShowTime leaves the last time.
local function ShowCharges(f, instanceID, data)
	local text
	local get = C_UnitAuras.GetAuraApplicationDisplayCount
	if type(get) == "function" then
		local ok, count = pcall(get, "player", instanceID, 1)
		if not ok then return end
		text = count
	else
		local ok, count = pcall(function() return data.applications end)
		count = ok and Plain(count) or nil
		text = (type(count) == "number" and count >= 1) and tostring(count) or ""
	end
	pcall(ChargesText(f).SetText, ChargesText(f), text)
end

--------------------------------------------------------------------------------
-- The game draws the buff in a fight (TICK-0159)
--
-- Under the restriction (AurasHidden) addon code reads nothing about your
-- own auras: no lookup by name, spell ID or instance ID answers, and the
-- UNIT_AURA payload is secret (DK's probe, 2026-11-21). The game's own aura
-- container still sees them. So each spell icon gets one, with one aura
-- slot for that spell's buff, matched by spell ID. While your auras are
-- hidden the container is on and draws the buff's time and charges over
-- the icon, and HUDini's own time and charges on that icon clear. While
-- they read, it is off (off clears it) and HUDini draws them as before.
--
-- Facts, from the game's source (Blizzard_CustomAuraContainer.lua,
-- Blizzard_CustomAuraButton.lua, Blizzard_AuraContainerSlots.lua) and
-- TargetDebuffs.lua:
-- - AddAuraSlot makes the slot's button at once and gives it to
--   initializeFrame. After that HUDini may not touch the button while
--   auras are secret, so every part is set there.
-- - The slot matches spell IDs only (includeSpellIDs; allowed for helpful
--   auras on you): the icon's spell, and each spell ID HUDini read from a
--   buff of the icon's names while your auras read, kept per class. A
--   buff whose ID was never read shows no time or charges in a fight.
-- - With no formatter the game writes a count only over 1 (a formatter
--   gets the count, which can be secret): the last charge shows no number
--   in a fight.
-- - The button shows and hides itself with the buff. It has no picture of
--   its own (no SetIcon): the icon's own picture stays. HUDini gives it a
--   thin cover at the edge, from the icon's picture (MakeCover), for the
--   red edge under it (TICK-0168).
-- - The container is made, placed and sized only out of a fight. It is a
--   child of the HUD's anchor, on the icon's own point, not a child of the
--   icon or anchored to it: the icons and the body hide in a fight, and a
--   protected child would block that (TargetDebuffs.lua, top). Switching
--   it on and off (SetEnabled) works in a fight. It takes the body's alpha
--   as the body fades.
-- - An on container listens to every change of your auras, so only an icon
--   that may show a buff gets one: one with a spell ID HUDini read for its
--   names, or with more names than its spell's own (an aura map). Fireball
--   gets none. Its spell IDs are worked out again only when they can change.
-- - A buff of the icon's names that the slot cannot match (its ID was never
--   read) still gets its time from the cast (TICK-0135), drawn by HUDini.
--------------------------------------------------------------------------------

local body = HUDini.body

-- Call a method that may not exist on this client.
local function Try(f, method, ...)
	local fn = f[method]
	if type(fn) ~= "function" then return false end
	return pcall(fn, f, ...)
end

-- Spell IDs read from your buffs, by buff name, for this class:
-- { [name] = { [spellID] = true } }. Saved, so a fight right after login
-- knows them too.
local function KnownIDs()
	local cdb = ns.ClassDB()
	cdb.auraSpellIDs = cdb.auraSpellIDs or {}
	return cdb.auraSpellIDs
end

-- Goes up each time a new ID is kept, so each slot works its IDs out again.
local knownVersion = 0

local function LearnID(name, data)
	local ok, id = pcall(function() return data.spellId end)
	id = ok and Plain(id) or nil
	if type(id) ~= "number" then return end
	local known = KnownIDs()
	known[name] = known[name] or {}
	if known[name][id] then return end
	known[name][id] = true
	knownVersion = knownVersion + 1
end

-- The spell IDs an icon's slot matches, as a set, and as one string that
-- changes when the set does.
local function SlotIDs(e)
	local set, list = {}, {}
	local function Add(id)
		if type(id) == "number" and not set[id] then
			set[id] = true
			list[#list + 1] = id
		end
	end
	Add(Plain(e.spellID))
	local known = KnownIDs()
	for _, name in ipairs(AuraNames(e)) do
		for id in pairs(known[name] or {}) do Add(id) end
	end
	table.sort(list)
	return set, table.concat(list, " ")
end

-- True when the icon may show a buff, so it is worth a container (above).
local function MayShowBuff(e)
	local names = AuraNames(e)
	if #names > 1 then return true end
	local known = KnownIDs()
	for _, name in ipairs(names) do
		if known[name] and next(known[name]) then return true end
	end
	return false
end

-- The slot's IDs for this icon now, worked out again only when the icon's
-- entry, its spell or the kept IDs changed.
local function WantedIDs(s, e)
	if s.forEntry ~= e or s.forSpell ~= e.spellID or s.forVersion ~= knownVersion then
		s.wantSet, s.wantKey = SlotIDs(e)
		s.forEntry, s.forSpell, s.forVersion = e, e.spellID, knownVersion
	end
	return s.wantSet, s.wantKey
end

-- Set below, with what HUDini last saw of each buff (TICK-0164).
local UpdateUnder = function() end -- the red layer under the slot's button (TICK-0168), set below

-- The slot's button, from the game's own code (maybe in a fight). Its
-- parts copy the icon's own: the time bottom left in green (StyleBuffTime),
-- the charges bottom right. It takes no mouse, so the icon's own tooltip
-- still shows under it. The game shows and hides it with the buff. In a
-- fight the button is closed to HUDini (DenyTaintedAccessWhenAurasAreSecret,
-- Blizzard_AuraContainerShared.lua) and its shown state is secret: HUDini
-- touches nothing on it then.
local function DressSlot(button, box, size)
	button:ClearAllPoints()
	button:SetPoint("CENTER", box, "CENTER")
	button:SetSize(size, size)
	Try(button, "SetMouseMotionEnabled", false)
	Try(button, "SetMouseClickEnabled", false)

	local cd = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	cd:SetAllPoints(button)
	ns.StyleBuffTime(cd)
	Try(button, "SetDurationCooldown", cd)

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", -1, 2)
	count:SetJustifyH("RIGHT")
	Try(button, "SetApplicationCount", count, {})
end

-- The red edge under the slot's button (TICK-0168, option B). The button
-- draws no picture of its own, so it gets a cover (MakeCover): the same
-- edge strips cut from the icon's own picture. The game shows the button,
-- and with it the cover, while the buff is on: the edge looks as it always
-- does. The game hides it when the buff ends, in a fight too: the red edge
-- shows. HUDini reads nothing to show it: it is up while the container is
-- on and the buff would count as missing if it were off (UpdateUnder). The
-- game's button does the rest. No sound: HUDini never learns the buff ended.
-- Only an edge: a cover over the whole icon would hide its key, count,
-- cooldown and proc glow.
local UNDER_COLOR = { 0.85, 0.15, 0.10 } -- the missing icon's red (Alerts.lua MISSING_COLOR)
local UNDER_EDGE  = 2                     -- pixels, inside the icon
local CROP_LO, CROP_HI = 0.07, 0.93       -- the icon picture's crop (Core.lua CreateIcon)

-- One strip for each side: its two points on the frame, and whether it
-- runs across (its height is the edge) or down (its width is).
local SIDES = {
	{ "TOPLEFT", "TOPRIGHT", true },
	{ "BOTTOMLEFT", "BOTTOMRIGHT", true },
	{ "TOPLEFT", "BOTTOMLEFT", false },
	{ "TOPRIGHT", "BOTTOMRIGHT", false },
}

local function Strips(parent, layer)
	local list = {}
	for i, side in ipairs(SIDES) do
		local t = parent:CreateTexture(nil, layer)
		t:SetPoint(side[1])
		t:SetPoint(side[2])
		if side[3] then t:SetHeight(UNDER_EDGE) else t:SetWidth(UNDER_EDGE) end
		list[i] = t
	end
	return list
end

local function MakeUnder()
	local u = CreateFrame("Frame", nil, HUDini)
	u:Hide()
	local r, g, b = unpack(UNDER_COLOR)
	for _, t in ipairs(Strips(u, "BORDER")) do t:SetColorTexture(r, g, b, 1) end
	return u
end

-- The cover, on the game's button (from initializeFrame). Under the
-- button's own time and count. Off until CoverOn puts it on; its picture
-- comes later (CoverPicture).
local function MakeCover(button)
	local list = Strips(button, "BACKGROUND")
	for _, t in ipairs(list) do t:SetAlpha(0) end
	return list
end

-- Give the cover the icon's picture, cut to the same edges. Out of a fight
-- only: in one the button is closed to HUDini. s.coverTex is the picture
-- the cover has; while it is not the icon's (a Bar 1 page change in a
-- fight) the red edge stays down, as the cover would not match. A cover
-- that did not take its picture (s.covered false) keeps it down too. Not
-- while your auras are hidden either (between keystone pulls, with no
-- lockdown): the button may be closed then too. A cover that has this
-- picture at this size is not written again.
local function CoverPicture(f)
	local s = f.auraBox
	if not (s and s.cover) or InCombatLockdown() or AurasHidden() then return end
	local okTex, tex = Try(f.icon, "GetTexture")
	tex = okTex and Plain(tex) or nil
	if tex == nil then s.covered = false return end
	local size = s.size and s.size > 0 and s.size or f:GetWidth()
	if s.covered and tex == s.coverTex and size == s.coverSize then return end
	local c = (CROP_HI - CROP_LO) * UNDER_EDGE / size
	local L, R = CROP_LO, CROP_HI
	local coords = {
		{ L, R, L, L + c },
		{ L, R, R - c, R },
		{ L, L + c, L, R },
		{ R - c, R, L, R },
	}
	local ok = pcall(function()
		for i, t in ipairs(s.cover) do
			t:SetTexture(tex)
			t:SetTexCoord(unpack(coords[i]))
		end
	end)
	s.covered, s.coverTex, s.coverSize = ok, tex, size
end

-- The container goes on the icon's point on the anchor, the same size, two
-- levels above the icon's own buff time. The red edge goes just above the
-- icon's cooldown: under the icon's buff time, its proc glow and the
-- game's button. The icon must sit on the anchor's top left by its center,
-- as Layout puts it: the flow layout may size the container, and its
-- center stays. Out of a fight only. Layout can move the icons in a fight
-- too (a target change): then the red edge goes down until the next
-- layout out of a fight, as it cannot follow.
local function Place(f)
	local s = f.auraBox
	if not s then return end
	local point, rel, relPoint, x, y = f:GetPoint(1)
	if InCombatLockdown() then
		if s.under and not (s.at and x == s.at[1] and y == s.at[2]
			and point == "CENTER" and rel == HUDini and relPoint == "TOPLEFT") then
			s.underPlaced = false
			s.under:Hide()
		end
		return
	end
	s.placed = false
	s.at = nil
	if point ~= "CENTER" or rel ~= HUDini or relPoint ~= "TOPLEFT" then return end
	local w, h = f:GetWidth(), f:GetHeight()
	s.placed = pcall(function()
		s.box:ClearAllPoints()
		s.box:SetPoint("CENTER", HUDini, "TOPLEFT", x, y)
		s.box:SetSize(w, h)
		s.box:SetFrameLevel(f.buff:GetFrameLevel() + 2)
	end)
	if s.under then
		s.underPlaced = s.placed and pcall(function()
			s.under:ClearAllPoints()
			s.under:SetPoint("CENTER", HUDini, "TOPLEFT", x, y)
			s.under:SetSize(w, h)
			s.under:SetFrameLevel(f.cd:GetFrameLevel() + 1)
		end)
		if s.underPlaced then s.at = { x, y } else s.under:Hide() end
	end
	-- The button refuses while your auras are hidden (a keystone between
	-- pulls). At its old size it would not fit the icon: not placed, so it
	-- stays off until a layout can size it.
	if s.placed and s.button and s.size ~= w then
		if pcall(s.button.SetSize, s.button, w, h) then
			s.size = w
		else
			s.placed = false
		end
	end
	CoverPicture(f)
end

local noContainer -- true once this client proved to have none

-- Make the icon's container once, out of a fight. Its slot matches the
-- spell IDs it is given. False when it cannot be made.
local function Build(f, set, key)
	if f.auraBox ~= nil then return f.auraBox end
	if noContainer or InCombatLockdown() then return nil end
	f.auraBox = false
	if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") -- locale: skip an addon name
	end
	local ok, box = pcall(CreateFrame, "AuraContainer", nil, HUDini, "CustomAuraContainerTemplate")
	if not ok or not box or type(box.AddAuraSlot) ~= "function" then
		noContainer = true
		if ok and box then
			Try(box, "SetEnabled", false)
			box:Hide()
		end
		return false
	end
	-- Off before the slot goes in: on, it would listen for every unit.
	Try(box, "SetEnabled", false)
	Try(box, "SetEditModePreviewEnabled", false)
	Try(box, "SetUnit", "player")
	local size = f:GetWidth() or 1
	local cover
	local okSlot, button = Try(box, "AddAuraSlot", "buff", "HELPFUL", { -- locale: skip a slot key and a filter
		candidateFilters = { includeSpellIDs = set },
		initializeFrame = function(b)
			pcall(DressSlot, b, box, size)
			local okCover, strips = pcall(MakeCover, b)
			cover = okCover and strips or nil
		end,
	})
	if not okSlot then
		Try(box, "SetEnabled", false)
		box:Hide()
		return false
	end
	local okUnder, under = pcall(MakeUnder)
	f.auraBox = { box = box, button = button, key = key, set = set, size = size, on = false,
		under = okUnder and under or nil, cover = cover }
	Try(box, "SetAlpha", body:GetAlpha())
	if f.auraBox.under then f.auraBox.under:SetAlpha(body:GetAlpha()) end
	Place(f)
	return f.auraBox
end

-- Switch the icon's container on while your auras are hidden and it can
-- draw this icon's buff: buff time on, a spell (not an item), the icon and
-- the body shown, the container placed. True when it is on: the icon's own
-- time and charges then stay clear. With no container, false: the icon
-- keeps its own, as before.
local function Sync(f, e, hidden)
	local spell = e.spellID ~= nil and not e.itemID
	local s = f.auraBox
	if s == nil and spell and HUDiniDB.showBuffTime and not InCombatLockdown()
		and not noContainer and MayShowBuff(e) then
		local set, key = SlotIDs(e)
		s = Build(f, set, key)
	end
	if not s then return false end
	local want = hidden and spell and HUDiniDB.showBuffTime and s.placed
		and f:IsShown() and body:IsShown() or false
	if want then
		-- A new spell on the icon (a Bar 1 page change) or a newly read ID.
		local set, key = WantedIDs(s, e)
		if key ~= s.key then
			if Try(s.box, "SetAuraSlotCandidateFilters", "buff", { includeSpellIDs = set }) then -- locale: skip a slot key
				s.key, s.set = key, set
			else
				want = false
			end
		end
	end
	-- On, the game reads all your auras at once (SetEnabled does it). A
	-- switch that fails leaves it as it was. s.want keeps what HUDini
	-- wanted: a switch off that failed must not keep the red edge up.
	s.want = want
	if want ~= s.on and Try(s.box, "SetEnabled", want) then
		s.on = want
	end
	UpdateUnder(f, e)
	return s.on
end

-- Switch off the containers of icons the HUD does not use now: they stay
-- on the anchor, which does not hide (a form change makes fewer icons).
local function SpareOff()
	for i = #HUDini.spells + 1, #HUDini.icons do
		local s = HUDini.icons[i].auraBox
		if s then s.want = false end
		if s and s.on and Try(s.box, "SetEnabled", false) then s.on = false end
		if s and s.under then s.under:Hide() end
	end
end

-- The icon's own time and charges, while the game draws its buff. A time
-- from a cast stays: the slot could not match that buff (TimeCast).
local function ClearOwn(f)
	ClearCharges(f)
	if not f.castTime then ClearTime(f) end
end

-- True when the game draws this cast's buff on the icon now: its container
-- is on and its slot matches the cast's spell ID or an ID read for its name.
local function Drawn(f, cast, spellID)
	local s = f.auraBox
	if not (s and s.on) then return false end
	if spellID and s.set[spellID] then return true end
	for id in pairs(KnownIDs()[cast] or {}) do
		if s.set[id] then return true end
	end
	return false
end

local SyncWatches -- the game's watches on your buffs, set below

hooksecurefunc(HUDini, "Layout", function() -- locale: skip a method name
	for _, f in pairs(HUDini.icons) do Place(f) end
	SpareOff()
	if SyncWatches then pcall(SyncWatches) end
end)

-- Paint gives the icons their pictures after Layout and checks the red
-- edges before this runs: copy the pictures, then check them again.
hooksecurefunc(HUDini, "Paint", function() -- locale: skip a method name
	for i, f in ipairs(HUDini.icons) do
		if f.auraBox then UpdateUnder(f, HUDini.spells[i]) end
	end
end)

hooksecurefunc(body, "SetAlpha", function(_, alpha) -- locale: skip a method name
	for _, f in pairs(HUDini.icons) do
		if f.auraBox then
			Try(f.auraBox.box, "SetAlpha", alpha)
			if f.auraBox.under then f.auraBox.under:SetAlpha(alpha) end
		end
	end
end)

-- The body shows or hides (hide when idle, in a fight too): each
-- container follows. An icon the game draws now has none of its own.
local function FollowBody()
	if not HUDiniDB then return end
	local hidden = AurasHidden()
	for i = 1, #HUDini.spells do
		local f, e = HUDini.icons[i], HUDini.spells[i]
		if f and e and f.buff and Sync(f, e, hidden) then ClearOwn(f) end
	end
	SpareOff()
end
body:HookScript("OnShow", FollowBody)
body:HookScript("OnHide", FollowBody)

function ns.UpdateIconAuras()
	local db = HUDiniDB
	if not db then return end
	if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName and C_UnitAuras.GetAuraDuration) then
		return
	end

	local hidden = AurasHidden()
	for i = 1, #HUDini.spells do
		local f = HUDini.icons[i]
		local e = HUDini.spells[i]
		if f and e and f.buff then
			if e.itemID then ClearCharges(f) end
			if Sync(f, e, hidden) then
				ClearOwn(f)
			elseif not db.showBuffTime then
				ClearTime(f)
				ClearCharges(f)
			else
				-- First name that answers wins. One that cannot tell leaves the
				-- icon alone, rather than wiping a timer that is still right.
				local found, foundData, foundName, unknown = nil, nil, nil, false
				for _, name in ipairs(AuraNames(e)) do
					local id, data = FindAura(name)
					if id then found, foundData, foundName = id, data, name break end
					if id == nil then unknown = true end
				end

				-- Always re-hand the duration: a recast buff can keep its
				-- instance ID and only move its end time.
				if found then
					-- The game's container matches by spell ID (above).
					if not e.itemID then
						LearnID(foundName, foundData)
						-- A first read ID can make it worth a container.
						if f.auraBox == nil then Sync(f, e, hidden) end
					end
					ShowTime(f, found)
					if not e.itemID then ShowCharges(f, found, foundData) end
				elseif not unknown then
					ClearTime(f)
					ClearCharges(f)
				end
			end
		end
	end

	SpareOff()
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
-- The saved value is the buff's full length in seconds, as the aura's
-- duration last read it (0: no end). A buff under 30 minutes (Lightning
-- Shield) is one you keep up for a fight, so it counts as missing only in
-- a fight (D-033, TICK-0144): out of one it gives no icon and does not show
-- the HUD. An entry saved before TICK-0144 is true, with no length: it
-- counts in and out of a fight, as it did, until HUDini next reads the buff
-- on you and saves its length. A length is saved only when it reads plain;
-- a secret one leaves the saved value as it was.
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
local SHORT_BUFF = 1800 -- seconds: under this, missing only in a fight

-- True when a learned buff that is off counts as missing now. length is the
-- saved value: a plain number from Learn, or true from before TICK-0144.
local function CountsNow(length, fight)
	if type(length) == "number" and length > 0 and length < SHORT_BUFF then return fight end
	return true
end

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
	if type(duration) == "number" and (duration == 0 or duration >= LONG_BUFF) then
		local mine = ns.ClassDB()
		mine.buffSpells = mine.buffSpells or {}
		mine.buffSpells[source] = duration
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

--------------------------------------------------------------------------------
-- A buff that ends in a fight (TICK-0164, TICK-0168)
--
-- A fight hides your auras, so BuffState goes by what HUDini last saw
-- (Recall). Lightning Shield on at the fight start, whose charges the
-- enemy's hits use up, would count as on to its 10-minute end, and the
-- buff-missing icon and sound would not come for the rest of the fight.
--
-- The game's Cooldown Manager is the sign. Its two buff viewers are the
-- game's own code, and they read your auras in a fight. Each buff the
-- player tracks there has an item frame. The game sets the frame's
-- auraInstanceID while the buff is on you, and sets it and auraDataCached
-- to nil when the buff ends (ClearAuraInstanceInfo,
-- CooldownViewerItemData.lua, wow-ui-source forever 9dc84f0). The ID may
-- be secret; a nil never is, and type() reads either. So nil means off,
-- anything else means on. Only from a viewer that is visible: a hidden one,
-- or one whose parent is hidden (Alt-Z), stops its UNIT_AURA
-- (CooldownViewerMixin:OnHide) and its frames go stale.
--
-- The viewer counts only the auras you cast yourself ("HELPFUL|PLAYER",
-- sourceUnit "player", CooldownViewerItemData.lua). HUDini goes by name,
-- from any caster. So its "off" counts only after it said "on" for that
-- buff, with no cast of it since (viewerSaw): the same buff from another
-- caster, or a cast whose aura the viewer has not read yet, keeps what
-- HUDini saw. A plain read asks it too: your auras hide some time into a
-- fight with no event, and the buff's end can be the first change after.
-- The player sets it up: the Cooldown Manager on, the buff in its tracked
-- buffs, the viewer shown (it may be faded out). With none of that, a
-- buff goes by what HUDini last saw, as before.
--
-- Not the icon's aura container (TICK-0159): the game closes its button to
-- HUDini while your auras are secret (DenyTaintedAccessWhenAurasAreSecret,
-- Blizzard_AuraContainerShared.lua), and hooks on it never went on in the
-- game (DK's probe, 2026-11-21: hookFailed 2, calls 0).
--------------------------------------------------------------------------------

local VIEWERS = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" } -- locale: skip frame names
local viewerNames = {} -- cooldownID -> { [buff name] = true }, read once (SPELLS_CHANGED clears it)

-- The buff names of a viewer item: its spell, its override, its linked
-- spells. nil when none reads. A set with a name that did not read (secret
-- in a fight) is not kept, so a later read gets it whole.
local function ItemNames(frame)
	local cooldownID = Plain(frame.cooldownID)
	if cooldownID == nil then return nil end
	if viewerNames[cooldownID] then return viewerNames[cooldownID] end
	local info = frame.cooldownInfo
	local api = _G.C_CooldownViewer
	if type(info) ~= "table" and type(api) == "table"
			and type(api.GetCooldownViewerCooldownInfo) == "function" then
		info = api.GetCooldownViewerCooldownInfo(cooldownID)
	end
	if type(info) ~= "table" then return nil end
	local names, any, whole = {}, false, true
	local function Add(id)
		id = Plain(id)
		if type(id) ~= "number" then return end
		local name = Plain(C_Spell.GetSpellName(id))
		if type(name) == "string" and name ~= "" then
			names[name], any = true, true
		else
			whole = false
		end
	end
	Add(info.spellID)
	Add(info.overrideSpellID)
	if type(info.linkedSpellIDs) == "table" then
		for _, id in ipairs(info.linkedSpellIDs) do Add(id) end
	end
	if not any then return nil end
	if whole then viewerNames[cooldownID] = names end
	return names
end

-- What the visible buff viewers say of a buff with these names: true when
-- an item of them alone is on; false when each name has an item and all
-- are off; nil else (a name with no item could be on). An item that also
-- links another buff can be on for that one: its "on" says nothing.
local function ViewerSays(names)
	if #names == 0 then return nil end
	local off, wanted = {}, {}
	for _, name in ipairs(names) do wanted[name] = true end
	for _, key in ipairs(VIEWERS) do
		local viewer = _G[key]
		local pool = type(viewer) == "table" and viewer.itemFramePool
		if pool and Plain(viewer:IsVisible()) then
			for frame in pool:EnumerateActive() do
				local mine = ItemNames(frame)
				local on = type(frame.auraInstanceID) ~= "nil" or type(frame.auraDataCached) ~= "nil"
				local alone = true
				for name in pairs(mine or {}) do
					if not wanted[name] then alone = false break end
				end
				for _, name in ipairs(names) do
					if mine and mine[name] then
						if on and alone then return true end
						if not on then off[name] = true end
					end
				end
			end
		end
	end
	for _, name in ipairs(names) do
		if not off[name] then return nil end
	end
	return false
end

-- In a fight, for the buff-missing check: a short buff counts as missing
-- only then (CountsNow). ns.InCombat() alone runs on past the fight's end:
-- UnitAffectingCombat can stay true after PLAYER_REGEN_ENABLED, and your
-- auras read again (the restriction ends) while it is true. A buff seen
-- off then would show the icon, and play the sound, for a moment as the
-- fight ends (TICK-0168). So a fight ends at PLAYER_REGEN_ENABLED, or when
-- your auras read again after they were hidden in it; it starts again at
-- PLAYER_REGEN_DISABLED.
-- source -> true: the viewer said "on" for it at the last read, with no cast
-- of it since (above).
local viewerSaw = {}

local fightEnded, fightHid = false, false
local function InFight()
	local hidden = AurasHidden()
	if hidden then fightHid = true end
	if fightEnded or not ns.InCombat() then return false end
	return hidden or not fightHid
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
		local ok, says = pcall(ViewerSays, names)
		viewerSaw[source] = ok and says == true or nil
		Remember(source, last)
		return true
	end
	if unknown then
		-- The Cooldown Manager reads your auras in a fight (above).
		local ok, says = pcall(ViewerSays, names)
		if ok and says then
			if not Recall(source) then
				-- On again (cast in the fight): it ends with its known length.
				local length = lasts[source]
				seen[source] = { on = true, ends = length and GetTime() + length or nil }
			end
			viewerSaw[source] = true
		elseif ok and says == false and viewerSaw[source] then
			Remember(source, nil)
			return false
		end
		return Recall(source)
	end
	viewerSaw[source] = nil
	Remember(source, nil)
	return false
end

-- The keep-up list (Alerts.lua, alert 2) counts as one buff: on while any of
-- it is on. Its icon shows only in a fight, and a fight hides your auras: a
-- hidden aura is not found by name, with no error
-- (SecretPredicatesDocumentation.lua:28-30 and :80-82, wow-ui-source forever
-- 9dc84f0). So it goes by what HUDini last saw, as your buffs do (TICK-0130).
-- The key cannot be a spell name. Alerts.lua asks ns.GameSounds and
-- ns.BuffWatched with it (ns.KEEP_UP_KEY).
local KEEP_UP = "keepUp"
ns.KEEP_UP_KEY = KEEP_UP

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

--------------------------------------------------------------------------------
-- The game's own watch on each buff to keep up (TICK-0168, second pass)
--
-- The red icon by your health bar and the buff-missing sound, in a fight,
-- with no setup by the player. HUDini reads no aura in a fight for this:
-- the game does the work.
--
-- Icon: each buff gets an aura container of its own, filtered to the buff's
-- read spell IDs, with room for one aura. The game sizes a container in its
-- own code, in a fight too: one aura element wide while the buff is on you,
-- 1 (or 0) when it is off (OnLayoutComplete and ApplyFlowLayout,
-- Blizzard_CustomAuraContainer.lua and AnchorUtil.lua, wow-ui-source forever
-- 9dc84f0). The container is invisible. A clip frame hangs off the
-- container's right edge, and the red icon (a copy of Alerts.lua's) sits in
-- the clip at the icon's spot left of the bar. Buff off: the clip covers the
-- spot and the icon shows. Buff on: the clip moves a whole element to the
-- right, off the spot, and the icon is cut away. No Lua runs for it.
--
-- Sound: the game plays a sound file when an aura with a given spell ID
-- leaves you (C_UnitAuras.AddAuraSound, UnitAuraSoundTrigger.Removed;
-- UnitAuraDocumentation.lua). The call has restrictions: the game refuses it
-- in a fight, from the fight's first event on (TICK-0168, third pass: asked
-- at the fight's start, the sound never played). So HUDini asks out of a
-- fight, while your auras read, for each watched buff, and keeps it through
-- the fight. A buff under 30 minutes is missed only in a fight (D-033), so
-- HUDini takes the sound back SOUND_LEAD seconds before the buff's end (a
-- timer), and asks for none for a buff that ends sooner: a buff that runs
-- out out of a fight makes no sound. Not for a watch of two or more buff
-- names: one of them ending does not mean all are off (seals and forms
-- change by design). Each spell ID is asked for once, so a shared ID sounds
-- once. At a fight's start and end HUDini makes no sound calls at all.
--
-- The Cooldown Manager path above stays: where the player tracks the buff
-- there, HUDini's own state knows too, so the HUD icon glows (D-035), the
-- keep-up icon is not doubled and /hud why can tell. It is also all there
-- is on a client with no containers or no aura sounds.
--
-- A watch needs a read ID for each of its buff names (one sight of the buff
-- out of a fight, as Covers): else the buff on could not hide the icon.
-- Watches are made, placed and given their IDs out of a fight only. Each has
-- a spot of its own left of the bar, in Alerts.lua's order: the keep-up
-- list first, then your own buffs (the grid, then by name). In a fight
-- Alerts.lua hides its own icon for a watched buff (one icon for a buff, on
-- one spot) and puts its other icons left of the watches' spots
-- (ns.BuffWatched, ns.BuffWatchSpots). A watch whose buff is on leaves its
-- spot empty: the spots cannot move in a fight.
--------------------------------------------------------------------------------

local WATCH_MAX    = 8       -- buffs watched at once
local WATCH_GROUP  = "watch" -- locale: skip a group key
local WATCH_GAP    = 3       -- pixels from the bar (Alerts.lua SlotLeft)
local WATCH_MARGIN = 8       -- pixels: room for the game's size to be off by a little
local WATCH_DIM    = 0.65    -- the keep-up icon's dim (Alerts.lua KeepUpIcon)

local watches = {} -- in order; false once this client proved to have no container
local watchFight = false -- a fight is on: the icons may show
local watchMax = WATCH_MAX -- lower once a container could not be made: no new try
local soundsBroken = false -- the game took a sound and gave no ID back: never again
-- Each time the game gave no ID back. The return may be nil (the game's
-- documentation says so), maybe as a "no": the first waits for the next
-- fight's end, as a refusal does; the second stops the game sounds.
local soundNoIDs = 0
local soundsHeld = false -- a fight is on, from its first event: no sound calls
local SOUND_LEAD = 5 -- seconds before a buff's end its sound is taken back

-- The game's sound registrations: soundReg[soundID] = { id = spellID, file
-- = the file it plays }. For each watched buff (a source name, or KEEP_UP):
-- soundFor, the game will sound when it ends; soundOn, it was on (or not
-- known off) at the fight's start, or cast since. soundNo[spellID]: the file
-- the game refused for it, not asked again until the next fight's end.
local soundReg, soundFor, soundOn, soundNo = {}, {}, {}, {}
local soundLast = "none yet" -- locale: skip a debug report
local soundTimer, soundTimerAt = nil, nil
local SyncSounds

-- The read IDs of every name, as a set and a key; nil when a name has none.
local function WatchIDs(names)
	local known = KnownIDs()
	local set, list = {}, {}
	for _, name in ipairs(names) do
		local any = false
		for id in pairs(known[name] or {}) do
			any = true
			if not set[id] then
				set[id] = true
				list[#list + 1] = id
			end
		end
		if not any then return nil end
	end
	if #list == 0 then return nil end
	table.sort(list)
	return set, table.concat(list, " ")
end

-- The buffs to watch now, in order: the alerts' own lists and settings.
local function WantedWatches()
	local db = HUDiniDB
	local want, taken = {}, {}
	if not (db and db.showHealth) then return want end
	local function Add(key, names, iconID, dim)
		if taken[key] then return end
		taken[key] = true
		local set, idKey = WatchIDs(names)
		if set then
			want[#want + 1] = { key = key, names = names, set = set, idKey = idKey,
				iconID = iconID, dim = dim }
		end
	end
	if db.warnOwnBuff then
		local learned = ns.ClassDB().buffSpells or {}
		DropNotToKeep(learned)
		for _, e in ipairs(HUDini.spells) do
			local source = e.spellID and not e.itemID and Plain(C_Spell.GetSpellName(e.spellID))
			if type(source) == "string" and learned[source] and not IsState(source, e.spellID) then
				Add(source, AuraNamesFor(source), e.spellID)
			end
		end
		local rest = {}
		for source in pairs(learned) do
			if not taken[source] then rest[#rest + 1] = source end
		end
		table.sort(rest)
		for _, source in ipairs(rest) do
			local id = ns.SpellID(source)
			if id and IsPlayerSpell and IsPlayerSpell(id) then
				Add(source, AuraNamesFor(source), id)
			end
		end
	end
	if db.warnKeepUp then
		local names = KeepUpNames(ns.ClassValue("keepUp"))
		local iconID
		for _, name in ipairs(names) do
			-- A keep-up buff that is a learned buff has its own watch
			-- (Alerts.lua OwnBuffCovers): one icon is enough.
			if taken[name] then return want end
			local id = ns.SpellID(name)
			if not iconID and id and IsPlayerSpell and IsPlayerSpell(id) then iconID = id end
		end
		if iconID then Add(KEEP_UP, names, iconID, true) end
	end
	return want
end

-- Alerts.lua's order (LEFT_ORDER): the keep-up list first, then your own
-- buffs; no more than this client can make.
local function WatchOrder()
	local found, want = WantedWatches(), {}
	for _, wnt in ipairs(found) do
		if wnt.key == KEEP_UP then want[1] = wnt end
	end
	for _, wnt in ipairs(found) do
		if wnt.key ~= KEEP_UP and #want < watchMax then want[#want + 1] = wnt end
	end
	while #want > watchMax do table.remove(want) end
	return want
end

-- The red icon, as Alerts.lua's: a red square, the spell's picture 1 pixel
-- inside it.
local function WatchArt(clip)
	local art = CreateFrame("Frame", nil, clip, "DisableUntrustedLayoutScriptsTemplate")
	local edge = art:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	local r, g, b = unpack(UNDER_COLOR)
	edge:SetColorTexture(r, g, b, 1)
	local tex = art:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(CROP_LO, CROP_HI, CROP_LO, CROP_HI)
	return art, tex
end

-- The container's one aura frame: never seen (the container's alpha is 0)
-- and no mouse, so it takes no tooltip and no click.
local function QuietFrame(b)
	Try(b, "SetMouseMotionEnabled", false)
	Try(b, "SetMouseClickEnabled", false)
end

local function DropBox(box)
	Try(box, "SetEnabled", false)
	pcall(box.Hide, box)
	return false
end

-- Make a watch once, out of a fight. False when this client cannot.
local function MakeWatch(bar)
	if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") -- locale: skip an addon name
	end
	local ok, box = pcall(CreateFrame, "AuraContainer", nil, HUDini, "CustomAuraContainerTemplate")
	if not ok or not box then return false end
	if type(box.AddAuraGroup) ~= "function" then return DropBox(box) end
	-- Off before the group goes in: on, it would listen for every unit.
	Try(box, "SetEnabled", false)
	Try(box, "SetEditModePreviewEnabled", false)
	Try(box, "SetUnit", "player")
	Try(box, "SetAlpha", 0)
	if not Try(box, "AddAuraGroup", WATCH_GROUP, "HELPFUL", { -- locale: skip a filter
		maxFrameCount = 1,
		candidateFilters = { includeSpellIDs = {} },
		layout = { elementWidth = 1, elementHeight = 1 },
		initializeFrame = function(b) pcall(QuietFrame, b) end,
	}) then
		return DropBox(box)
	end
	-- Anchored to the container, so made with the aspect the container
	-- asks for (AddAuraGroup, Blizzard_CustomAuraContainer.lua). A child of
	-- the bar: it shows, hides and fades with it.
	local okClip, clip = pcall(CreateFrame, "Frame", nil, bar, "DisableUntrustedLayoutScriptsTemplate") -- locale: skip a frame type
	if not okClip or not clip or not pcall(clip.SetClipsChildren, clip, true) then
		return DropBox(box)
	end
	clip:Hide()
	local okArt, art, tex = pcall(WatchArt, clip)
	if not okArt then return DropBox(box) end
	return { box = box, clip = clip, art = art, tex = tex, armed = false }
end

-- The icon's first spot left of the health bar, on the anchor (as
-- Alerts.lua SlotLeft puts it): its top left and size. nil with no place
-- yet. On the anchor, not the bar: the bar shows and hides in a fight.
-- Spot i is i - 1 icons and gaps further left.
local function WatchSpot()
	local bar = ns.GetBar and ns.GetBar("health")
	if not bar then return nil end
	local point, rel, relPoint, x, y = bar:GetPoint(1)
	if point ~= "BOTTOMLEFT" or rel ~= HUDini or relPoint ~= "TOPLEFT" then return nil end
	local h = bar:GetHeight()
	if not (h and h > 0) then return nil end
	return x - WATCH_GAP - h, y + h, h, bar
end

-- Put a watch on the spot, h high: the container's element one icon and
-- two margins wide, the clip off its right edge (above).
local function PlaceWatch(w, x, y, h, level)
	local m = WATCH_MARGIN
	if not Try(w.box, "SetAuraGroupLayout", WATCH_GROUP, { elementWidth = h + 1 + 2 * m, elementHeight = h }) then
		return false
	end
	return pcall(function()
		w.box:ClearAllPoints()
		w.box:SetPoint("TOPLEFT", HUDini, "TOPLEFT", x, y)
		w.clip:ClearAllPoints()
		w.clip:SetPoint("TOPLEFT", w.box, "TOPRIGHT", -1 - m, m)
		w.clip:SetSize(h + 2 * m, h + 2 * m)
		w.clip:SetFrameLevel(level)
		w.art:ClearAllPoints()
		w.art:SetPoint("TOPLEFT", HUDini, "TOPLEFT", x, y)
		w.art:SetSize(h, h)
	end)
end

local function Disarm(w)
	w.armed, w.key, w.idKey = false, nil, nil
	Try(w.box, "SetEnabled", false)
	pcall(w.clip.Hide, w.clip)
end

-- Show each armed watch's clip in a fight, hide every one out of it.
local function ShowWatches()
	if watches == false then return end
	for _, w in ipairs(watches) do
		pcall(w.clip.SetShown, w.clip, watchFight and w.armed or false)
	end
end

-- True while the game refuses a sound: a fight, the lockdown, or your
-- auras hidden (ForeverAuras waits for the same before it asks).
local function SoundsLocked()
	return soundsHeld or InCombatLockdown() or AurasHidden()
end

-- True when the buff is on and ends within SOUND_LEAD seconds.
local function EndsSoon(key)
	local s = seen[key]
	return s ~= nil and s.on == true and s.ends ~= nil and GetTime() >= s.ends - SOUND_LEAD
end

-- A set of spell IDs as one sorted line.
local function IDLine(set)
	local list = {}
	for id in pairs(set or {}) do list[#list + 1] = id end
	table.sort(list)
	return table.concat(list, ",")
end

-- A timer to the earliest end of a buff the game sounds for, less
-- SOUND_LEAD: out of a fight the sound then goes (SyncSounds).
local function TimeSounds()
	local first
	for _, w in ipairs(watches) do
		local s = soundFor[w.key] and seen[w.key]
		if s and s.on and s.ends and (not first or s.ends < first) then first = s.ends end
	end
	local at = first and first - SOUND_LEAD
	-- No timer while the game refuses sounds (the fight's end and your
	-- auras reading again sync anyway), nor for a time gone by (the sync
	-- just ran; a sound that will not go waits for the next): that timer
	-- would only start itself again, ten times a second.
	if at and (SoundsLocked() or at <= GetTime()) then at = nil end
	if at == soundTimerAt then return end
	if soundTimer then soundTimer:Cancel() end
	soundTimer, soundTimerAt = nil, at
	if at and C_Timer and C_Timer.NewTimer then
		soundTimer = C_Timer.NewTimer(math.max(at - GetTime(), 0.1), function()
			soundTimer, soundTimerAt = nil, nil
			pcall(SyncSounds)
		end)
	end
end

-- Out of a fight: the game sounds for each armed watch of one name whose
-- buff does not end soon, and for nothing else (above). A sound that will
-- not go stays counted and is tried again at the next sync; its ID is not
-- asked for again meanwhile (one sound, not two). In a fight: no calls,
-- only what HUDini counts on.
SyncSounds = function()
	if watches == false then return end
	local api = C_UnitAuras
	local trigger = Enum and Enum.UnitAuraSoundTrigger and Enum.UnitAuraSoundTrigger.Removed
	if not SoundsLocked() and api and api.AddAuraSound and api.RemoveAuraSound and trigger then
		local file = ns.MissingSoundFile and ns.MissingSoundFile()
		local want = {}
		if file and not soundsBroken then
			for _, w in ipairs(watches) do
				if w.armed and #w.names == 1 and not EndsSoon(w.key) then
					for id in pairs(w.set) do want[id] = true end
				end
			end
		end
		local have = {}
		for soundID, r in pairs(soundReg) do
			if r.file ~= file or not want[r.id] or have[r.id] then
				if pcall(api.RemoveAuraSound, soundID) then
					soundReg[soundID] = nil
				else
					have[r.id] = true
					soundLast = "will not go: " .. soundID -- locale: skip a debug report
				end
			else
				have[r.id] = true
			end
		end
		for id in pairs(want) do
			if not have[id] and soundNo[id] ~= file and not soundsBroken then
				local ok, res = pcall(api.AddAuraSound, trigger, {
					unitToken = "player", -- locale: skip a unit
					spellID = id,
					soundFileID = file,
					outputChannel = "Master", -- locale: skip a channel
				})
				local soundID = ok and Plain(res) or nil
				if type(soundID) == "number" then
					soundReg[soundID] = { id = id, file = file }
					have[id] = true
					soundLast = ("asked %d: sound %d"):format(id, soundID) -- locale: skip a debug report
				elseif ok then
					-- No ID back: maybe a "no", maybe a sound HUDini could
					-- never take back. Once: as a refusal. Twice: no more.
					soundNoIDs = soundNoIDs + 1
					soundNo[id] = file
					soundsBroken = soundNoIDs >= 2
					soundLast = ("asked %d: no ID back (%d)"):format(id, soundNoIDs) -- locale: skip a debug report
				else
					soundNo[id] = file
					soundLast = ("asked %d: refused, %s"):format(id, tostring(res)) -- locale: skip a debug report
				end
			end
		end
	end
	local have = {}
	for _, r in pairs(soundReg) do have[r.id] = true end
	soundFor = {}
	for _, w in ipairs(watches) do
		if w.armed and #w.names == 1 then
			for id in pairs(w.set) do
				if have[id] then soundFor[w.key] = true end
			end
		end
	end
	TimeSounds()
end

-- /hud debug aura: the watches and the game's sounds, in English.
-- locale: skip a debug report
function ns.BuffWatchReport(out)
	out("  Buff watches (TICK-0168)")
	if watches == false then
		out("    No aura container on this client.")
		return
	end
	local file = ns.MissingSoundFile and ns.MissingSoundFile()
	out(("    Fight %s, sounds held %s, game refuses sounds now %s, no-ID stop %s"):format(
		tostring(watchFight), tostring(soundsHeld), tostring(SoundsLocked()), tostring(soundsBroken)))
	out("    Sound file " .. tostring(file))
	for i, w in ipairs(watches) do
		local key = w.key == KEEP_UP and "combat buff list" or tostring(w.key)
		out(("    Watch %d: %s, IDs %s, armed %s, game sound %s, on at the fight start %s"):format(
			i, key, IDLine(w.set), tostring(w.armed), tostring(soundFor[w.key] == true), tostring(soundOn[w.key])))
	end
	local regs = {}
	for soundID, r in pairs(soundReg) do regs[#regs + 1] = ("%d for %d (file %s)"):format(soundID, r.id, tostring(r.file)) end
	table.sort(regs)
	out("    Sounds the game holds: " .. (#regs > 0 and table.concat(regs, "; ") or "none"))
	out("    Last try: " .. soundLast)
	out("    Take-back timer at " .. tostring(soundTimerAt) .. ", now " .. tostring(GetTime()))
end
-- locale: end

-- True when the game sounds for this buff (a source name, or ns.KEEP_UP_KEY) as
-- it ends in this fight: Alerts.lua then plays none (one sound, not two).
-- A buff already off at the fight's start gets HUDini's.
function ns.GameSounds(key)
	return soundFor[key] == true and soundOn[key] == true
end

-- In a fight: true when an armed watch shows this buff's red icon (a source
-- name, or ns.KEEP_UP_KEY), so Alerts.lua shows none of its own.
function ns.BuffWatched(key)
	if not watchFight or watches == false then return false end
	for _, w in ipairs(watches) do
		if w.armed and w.key == key then return true end
	end
	return false
end

-- In a fight: the spots left of the bar the watches hold (Alerts.lua puts
-- its own icons left of them). 0 out of a fight.
function ns.BuffWatchSpots()
	if not watchFight or watches == false then return 0 end
	local n = 0
	for i, w in ipairs(watches) do
		if w.armed then n = i end
	end
	return n
end

-- Make, fill and place the watches, out of a fight only.
SyncWatches = function()
	if watches == false or InCombatLockdown() then return end
	local want = WatchOrder()
	local x, y, h, bar = WatchSpot()
	if not x then want = {} end
	for i, wnt in ipairs(want) do
		local w = watches[i]
		if not w then
			w = MakeWatch(bar)
			if not w then
				if i == 1 then
					watches = false
					return
				end
				watchMax = i - 1
				for j = #want, i, -1 do want[j] = nil end
				break
			end
			watches[i] = w
		end
		w.key, w.names, w.set = wnt.key, wnt.names, wnt.set
		if w.idKey ~= wnt.idKey then
			w.idKey = Try(w.box, "SetAuraGroupCandidateFilters", WATCH_GROUP,
				{ includeSpellIDs = wnt.set }) and wnt.idKey or nil
			-- New IDs on a container that is on: off and on again, so the
			-- game reads your auras with them, not only the next change.
			if w.armed then
				Try(w.box, "SetEnabled", false)
				w.armed = false
			end
		end
		local place = table.concat({ x, y, h, i }, " ")
		if w.place ~= place then
			local sx = x - (i - 1) * (h + WATCH_GAP)
			-- Above the alerts' own icons.
			w.place = PlaceWatch(w, sx, y, h, bar:GetFrameLevel() + 4) and place or nil
		end
		pcall(function()
			w.tex:SetTexture(C_Spell.GetSpellTexture(wnt.iconID) or 134400)
			local shade = wnt.dim and WATCH_DIM or 1
			w.tex:SetVertexColor(shade, shade, shade)
		end)
		local armed = w.idKey ~= nil and w.place ~= nil
		-- On out of a fight too: the game has your auras read when one
		-- starts, so the icon does not flash up for a buff that is on.
		if armed ~= w.armed then
			w.armed = Try(w.box, "SetEnabled", armed) and armed or false
		end
	end
	for i = #want + 1, #watches do
		if watches[i].armed or watches[i].key then Disarm(watches[i]) end
	end
	pcall(SyncSounds)
	ShowWatches()
end
ns.SyncBuffWatches = SyncWatches

-- A fight starts (just after ns.UpdateBuffMissing synced the watches)
-- or ends.
local function WatchFight(on)
	watchFight = on
	if on then
		-- No sound calls (the game refuses them now): which buffs the game
		-- sounds for was settled out of the fight. A buff off now gets
		-- HUDini's own sound.
		soundOn = {}
		for _, w in ipairs(watches ~= false and watches or {}) do
			if soundFor[w.key] then soundOn[w.key] = Recall(w.key) ~= false end
		end
	else
		-- The sounds stay with the game. The game may refuse a call still in
		-- this event: a frame later the sync takes back those of buffs that
		-- end soon and asks again for one refused (unless a fight is on).
		soundOn, soundNo = {}, {}
		local function Release()
			if watchFight then return end
			soundsHeld = false
			pcall(SyncSounds)
		end
		if C_Timer and C_Timer.After then C_Timer.After(0, Release) else Release() end
	end
	pcall(ShowWatches)
	-- Alerts.lua hides its icon for a watched buff in a fight, and moves its
	-- other icons left of the watches.
	if ns.UpdateOwnBuffIcon then pcall(ns.UpdateOwnBuffIcon) end
end

function ns.UpdateBuffMissing()
	passTracking, inPass = nil, true
	passForm, passFormRead = nil, false
	LearnFromYourBuffs()
	local missingID
	if HUDiniDB and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local learned = ns.ClassDB().buffSpells or {}
		local fight = InFight()
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
				if learned[source] and on == false and not missingID
						and CountsNow(learned[source], fight) then
					missingID = e.spellID
				end
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
					and BuffState(source, AuraNamesFor(source)) == false and not missingID
					and CountsNow(learned[source], fight) then
				missingID = id
			end
		end
	end
	-- A learned buff, a read ID or a setting: the game's watches too. In
	-- the pass, so the form and the tracking are read once.
	pcall(SyncWatches)
	passTracking, inPass = nil, false
	ns.buffMissing   = missingID ~= nil
	ns.missingBuffID = missingID
	-- The red layers: a fight's start or end, a learned buff, the setting.
	for i = 1, #HUDini.spells do
		local f = HUDini.icons[i]
		if f then UpdateUnder(f, HUDini.spells[i]) end
	end
	if ns.UpdateOwnBuffIcon then ns.UpdateOwnBuffIcon() end
end

-- A buff you cast is on, to the end its length gives (nil: no end known).
-- One still on that ends later, or never, stays: with two of the keep-up
-- list on, the later end counts (BuffState).
local function CastOn(source, ends)
	-- The viewer reads the new aura later: until it says "on" again, its
	-- "off" is the old aura's (viewerSaw).
	viewerSaw[source] = nil
	-- On again: the game sounds when it ends (SyncSounds).
	if soundFor[source] then soundOn[source] = true end
	local s = seen[source]
	if ends and Recall(source) and (s.ends == nil or s.ends > ends) then return end
	seen[source] = { on = true, ends = ends }
end

--------------------------------------------------------------------------------
-- The red layer under the slot's button (TICK-0168)
--------------------------------------------------------------------------------

-- True when the slot matches a read ID for each of the icon's buff names.
local function Covers(s, e)
	local known = KnownIDs()
	for _, name in ipairs(AuraNames(e)) do
		local any = false
		for id in pairs(known[name] or {}) do
			if s.set[id] then any = true break end
		end
		if not any then return false end
	end
	return true
end

-- Show the red layer while the container is on (your auras hidden, the
-- icon and the body shown), the red icon is on in the options, the icon's
-- spell is a learned buff that counts as missing now (a short one only in
-- a fight: CountsNow), and the slot matches a read ID for each of its buff
-- names (Covers): else the button could stay hidden with the buff on. The
-- button's cover must have the icon's picture now (CoverPicture): else the
-- red edge would show through the button with the buff on. And the cover
-- must be on (CoverOn).
local function Under(f, e)
	local s = f.auraBox
	local u = s and s.under
	if not u then return end
	local db = HUDiniDB
	local want = s.on and s.want and s.underPlaced and s.covered and s.coverOn
		and db and db.warnOwnBuff and db.showHealth
		and e and e.spellID and not e.itemID and true or false
	if want then
		local okTex, tex = Try(f.icon, "GetTexture")
		tex = okTex and Plain(tex) or nil
		want = tex ~= nil and tex == s.coverTex
	end
	if want then
		local source = Plain(C_Spell.GetSpellName(e.spellID))
		local length = type(source) == "string" and (ns.ClassDB().buffSpells or {})[source]
		want = length and CountsNow(length, InFight()) and Covers(s, e) and true or false
	end
	u:SetShown(want)
end

-- True when a fight could put this icon's red edge up: the red icon is on
-- in the options, the spell is a learned buff, and the slot it gets in a
-- fight matches a read ID for each buff name.
local function CouldWarn(s, e)
	local db = HUDiniDB
	if not (db and db.warnOwnBuff and db.showHealth and e and e.spellID and not e.itemID) then
		return false
	end
	local source = Plain(C_Spell.GetSpellName(e.spellID))
	if type(source) ~= "string" or not (ns.ClassDB().buffSpells or {})[source] then return false end
	return Covers({ set = WantedIDs(s, e) or {} }, e)
end

-- The cover shows only on an icon whose red edge a fight could put up:
-- on every other icon the game's button stays as it was, with no edge over
-- the icon's cooldown, glow and tint. Set out of a fight, with your auras
-- shown, as the picture is (CoverPicture); s.coverOn keeps what is set.
local function CoverOn(f, e)
	local s = f.auraBox
	if not (s and s.cover) or InCombatLockdown() or AurasHidden() then return end
	CoverPicture(f)
	local on = s.covered and CouldWarn(s, e) or false
	if on == s.coverOn then return end
	local ok = pcall(function()
		for _, t in ipairs(s.cover) do t:SetAlpha(on and 1 or 0) end
	end)
	-- A failed switch leaves the strips unknown: the red edge stays down,
	-- and the next check writes the picture and the alpha again (nil is
	-- neither on nor off).
	if ok then s.coverOn = on else s.coverOn, s.covered = nil, false end
end

UpdateUnder = function(f, e)
	pcall(CoverOn, f, e)
	if not pcall(Under, f, e) and f.auraBox and f.auraBox.under then
		pcall(f.auraBox.under.Hide, f.auraBox.under)
	end
end

-- The icons that give the cast buff count its time from the cast, while
-- your auras are hidden (TICK-0135). The UNIT_AURA for it leaves a hidden
-- icon alone, before or after this. Readable auras need none of this: the
-- aura's own time goes on the icon (UpdateIconAuras).
local function TimeCast(cast, length, now, spellID)
	if not (length and HUDiniDB.showBuffTime and AurasHidden()) then return end
	for i = 1, #HUDini.spells do
		local f, e = HUDini.icons[i], HUDini.spells[i]
		-- The game draws the real time on this icon (TICK-0159).
		if f and e and f.buff and not Drawn(f, cast, spellID) then
			for _, name in ipairs(AuraNames(e)) do
				if name == cast then
					if pcall(f.buff.SetCooldown, f.buff, now, length) then
						f.castTime = true
						f.buff:Show()
					end
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
	TimeCast(cast, length, now, spellID)
	for source in pairs(ns.ClassDB().buffSpells or {}) do
		for _, name in ipairs(AuraNamesFor(source)) do
			if name == cast then CastOn(source, ends) break end
		end
	end
	-- A keep-up spell you cast counts as on. It is marked before the
	-- own-buff look below: that look also redraws the keep-up icon
	-- (TICK-0166), which must not flash on (and sound) for a buff just cast.
	local keptUp = false
	for _, name in ipairs(KeepUpNames(ns.ClassValue("keepUp"))) do
		if name == cast then
			CastOn(KEEP_UP, ends)
			keptUp = true
			break
		end
	end
	ns.UpdateBuffMissing()
	-- Its UNIT_AURA may come before this event, so look at the keep-up icon
	-- again.
	if keptUp and ns.UpdateAlerts then ns.UpdateAlerts() end
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

-- The one UNIT_AURA handler (TICK-0065). Your auras feed the resource bar
-- (Bars.lua), the icon auras and the alerts; your target's feed only the
-- alerts.
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

-- In a fight, the Cooldown Manager reads your auras in its own UNIT_AURA
-- (ViewerSays), maybe after this one: check your buffs again a frame later,
-- once however many came.
local viewerDue = false
local function ViewerLater()
	if viewerDue then return end
	viewerDue = true
	C_Timer.After(0, function()
		viewerDue = false
		if HUDiniDB then Call(ns.UpdateBuffMissing) end
	end)
end

local function OnUnitAura(unit)
	if unit == "player" then
		Call(ns.UpdateResource)
		Call(ns.UpdateIconAuras)
		Call(LearnStackingBuffs)
		if ns.InCombat() or AurasHidden() then ViewerLater() end
	end
	Call(ns.UpdateAlerts)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, unit, info, spellID)
	if event == "UNIT_AURA" then
		OnUnitAura(unit)
		return
	end
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if HUDiniDB then OnCast(spellID) end
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		-- A short buff counts as missing only in a fight (D-033): check now.
		-- The lockdown starts just after this event, so check again a frame
		-- later. The end of a fight checks below.
		-- The icons' containers switch on then too (TICK-0159).
		fightEnded, fightHid = false, false
		-- The game refuses sound calls from here to the fight's end.
		soundsHeld = true
		if HUDiniDB then
			Call(ns.UpdateBuffMissing)
			-- After the check: a buff off now gets HUDini's own sound.
			WatchFight(true)
			C_Timer.After(0, function()
				Call(ns.UpdateBuffMissing)
				Call(ns.UpdateIconAuras)
			end)
		end
		return
	end
	if event == "SPELLS_CHANGED" then
		-- A new tracking spell joins the minimap's list: read it again.
		minimapTracking = nil
		viewerNames = {}
		return
	end
	if event == "PLAYER_ENTERING_WORLD" then
		pcall(self.RegisterUnitEvent, self, "UNIT_AURA", "player", "target")
		pcall(self.RegisterUnitEvent, self, "UNIT_SPELLCAST_SUCCEEDED", "player")
		pcall(self.RegisterEvent, self, "PLAYER_REGEN_ENABLED")
		pcall(self.RegisterEvent, self, "PLAYER_REGEN_DISABLED")
		pcall(self.RegisterEvent, self, "SPELLS_CHANGED")
		-- Fired after a restriction ends, so your auras read again (TICK-0125).
		-- Also fired before one starts; it is not enforced until the event
		-- is done, so those reads are plain too.
		pcall(self.RegisterEvent, self, "ADDON_RESTRICTION_STATE_CHANGED")
		minimapTracking = nil
		viewerNames = {}
		-- The slot probe of TICK-0164 and TICK-0168 is gone.
		if HUDiniDB then HUDiniDB.slotProbe = nil end
	end
	if event == "PLAYER_REGEN_ENABLED" then
		fightEnded = true
		WatchFight(false)
	end
	-- After a fight, a restriction or on login: a stacking buff still up is
	-- learned now, and your buffs read again.
	Call(LearnStackingBuffs)
	ns.UpdateIconAuras()
	-- A restriction that starts is enforced only after its event: check
	-- again a frame later, so the icons' containers switch on (TICK-0159).
	if event == "ADDON_RESTRICTION_STATE_CHANGED" then
		C_Timer.After(0, function() Call(ns.UpdateIconAuras) end)
	end
end)
