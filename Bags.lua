--[[--------------------------------------------------------------------------
	HUDini - Bag upgrade numbers (TICK-0145, D-034) and stat marker
	(TICK-0152, D-037)

	A green "+N" on an item in your bags whose item level is N above what
	you wear in that slot. A gold "+" in the bottom left corner when the
	game's own stat compare with what you wear there (the "If you replace
	this item" lines, GetItemStatDelta) adds up to more than zero. Only in
	the game's own bag windows, combined or one window per bag; not the
	bank, not other bag addons.

	The number's rules are the loot feed's "+N ilvl" hint (FeedLoot.lua,
	TICK-0109):
	- Only gear with a slot. Shirts, tabards, bags and the rest show nothing.
	- Only gear your class can wear (DK, D-037: no mail chest for a mage):
	  a table of armour, shield and weapon types per class. Both markers.
	  The loot feed calls the same B.ClassCanWear (TICK-0153), so the table
	  loads even when the bag module is off.
	- Only gear you can wear now: the game's tooltip for that bag slot paints
	  red what stops you (the armour or weapon type, the level, the class).
	  A tooltip the game will not give, or gives as a secret, shows nothing.
	  Both markers.
	- Armour lighter than the type you wear in that slot shows no number:
	  leather is no upgrade to a shaman in mail. The stat marker has no
	  such rule: the game's compare counts the armour you lose.
	- Rings and trinkets compare with the lower of your two.
	- An empty slot counts as item level 0, so any gear for it shows.
	- Weapons: a one-hand weapon compares with the lower of your main hand
	  and off hand, but only the main hand when you cannot dual wield or
	  wear a two-hand weapon. A two-hand weapon compares with the main hand.
	- Item levels are the item's real level where it is
	  (C_Item.GetCurrentItemLevel), then the link's level. When the game
	  gives neither for the bag item or for what you wear, no number shows.

	The stat marker: the plain sum of every change the compare lists
	(+36 Armor and -1 Stamina is a gain). It uses the same slots as the
	number; with two (rings, trinkets, two one-hand weapons) a gain in
	either shows it. An empty slot compares with the item's own stats. A
	two-hand weapon, bow, gun or crossbow also loses what you hold in the
	off hand. Any compare the game will not give, or gives with a secret
	in it, shows no marker.

	When the numbers change: the game's bag windows call UpdateItems on a
	loot, a move or a sale, and HUDini paints after it. A change of gear, a
	new level and item data that comes late paint the open windows again.

	The number sits in the icon's top right corner, the stat marker in the
	bottom left, both inside the quality border. The stack count is at the
	bottom right; the game's upgrade arrow and junk coin are at the top left.

	Taint: HUDini only hooks (hooksecurefunc, HookScript) and reads. Its
	numbers are its own FontStrings, kept in its own table, never as fields
	on the game's buttons.

	It is a module (Modules.lua): on while showBagUpgrades is on (default
	off). A module never on hooks nothing, has no events and made nothing.
	A hook cannot be taken out, so once it was on, its hooks return at once
	while it is off, and its numbers are hidden.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

local Plain = ns.Plain

local M = ns.NewModule("bags", {
	label = "Bag upgrade numbers", -- locale: skip a debug name (/hud debug modules)
	setting = "showBagUpgrades",
	defaults = {
		showBagUpgrades = false, -- a green "+N" on bag items above what you wear (D-034)
	},
})

local B = {}
ns.Bags = B

local LAST_BAG = 5 -- Enum.BagIndex.ReagentBag; bags 0-5 are yours, the bank's are not

-- Where each kind of gear goes (the feed's table).
local SLOTS = {
	INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_HOLDABLE = { 17 }, INVTYPE_SHIELD = { 17 },
	INVTYPE_RANGED = { 16 }, INVTYPE_RANGEDRIGHT = { 16 },
}

-- Armour slots that take one armour type: cloth, leather, mail or plate.
local ARMOR_SLOTS = {
	INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
	INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true,
	INVTYPE_HAND = true,
}
local ARMOR_CLASS = 4 -- Enum.ItemClass.Armor; subclass 1 cloth, 2 leather, 3 mail, 4 plate

--------------------------------------------------------------------------------
-- What the game says about an item
--------------------------------------------------------------------------------

-- equipLoc, classID, subClassID of item, all plain, or nil.
local function Instant(item)
	local fn = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	if not (fn and item) then return end
	local ok, _, _, _, equipLoc, _, classID, subClassID = pcall(fn, item)
	if not ok then return end
	return Plain(equipLoc), Plain(classID), Plain(subClassID)
end

-- The armour type (1-4) of item, or 0 for none.
local function ArmorType(item)
	local _, classID, subClassID = Instant(item)
	if classID == ARMOR_CLASS and type(subClassID) == "number" and subClassID >= 1 and subClassID <= 4 then
		return subClassID
	end
	return 0
end

-- A plain item level above 0, or nil.
local function Level(v)
	v = Plain(v)
	if type(v) == "number" and v > 0 then return v end
end

-- The item's real level where it is (location), else its link's level.
local function ItemLevel(location, link)
	local I = C_Item
	if location and I and I.GetCurrentItemLevel then
		local ok, level = pcall(I.GetCurrentItemLevel, location)
		level = ok and Level(level)
		if level then return level end
	end
	local fn = I and I.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
	if link and fn then
		local ok, level = pcall(fn, link)
		return ok and Level(level) or nil
	end
end

local function Location(maker, ...)
	local L = _G.ItemLocation
	local fn = L and L[maker]
	if not fn then return end
	local ok, location = pcall(fn, L, ...)
	if ok then return location end
end

-- The plain link in a bag slot, or nil.
local function BagLink(bag, slot)
	local C = C_Container
	if not (C and C.GetContainerItemLink) then return end
	local ok, link = pcall(C.GetContainerItemLink, bag, slot)
	link = ok and Plain(link)
	if type(link) == "string" and link ~= "" then return link end
end

-- The plain link of what you wear in slot, false for an empty slot, or nil
-- when the game will not say: a secret link is not an empty slot.
local function WornLink(slot)
	local ok, link = pcall(GetInventoryItemLink, "player", slot)
	if not ok or ns.IsSecret(link) then return nil end
	if type(link) == "string" and link ~= "" then return link end
	return false
end

-- The game's red text (RED_FONT_COLOR, 1 / 0.125 / 0.125). Nil when the
-- game hides the color.
local function IsRed(color)
	if color == nil then return false end
	if ns.IsSecret(color) then return nil end
	local ok, r, g, b = pcall(function() return color.r, color.g, color.b end)
	if not ok or ns.IsSecret(r) or ns.IsSecret(g) or ns.IsSecret(b) then return nil end
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return false end
	return r > 0.9 and g < 0.3 and b < 0.3
end

-- True when you can wear the item in bag, slot now, by the game's own
-- tooltip for that slot: it paints red what stops you. Nil when the game
-- will not say.
local function Wearable(bag, slot, link)
	local T = C_TooltipInfo
	if not T then return nil end
	local ok, data
	if T.GetBagItem then
		ok, data = pcall(T.GetBagItem, bag, slot)
	elseif T.GetHyperlink then
		ok, data = pcall(T.GetHyperlink, link)
	end
	if not (ok and type(data) == "table") then return nil end
	local okLines, rows = pcall(function() return data.lines end)
	if not (okLines and type(rows) == "table") then return nil end
	-- Gear always has its name and its slot line; fewer is a tooltip the
	-- game has not loaded yet, which may still lack the red line.
	if #rows < 2 then return nil end
	for _, row in ipairs(rows) do
		local okRow, left, right = pcall(function() return row.leftColor, row.rightColor end)
		if not okRow then return nil end
		local redLeft, redRight = IsRed(left), IsRed(right)
		if redLeft == nil or redRight == nil then return nil end
		if redLeft or redRight then return false end
	end
	return true
end

local function CanDual()
	if not CanDualWield then return false end
	local ok, can = pcall(CanDualWield)
	return ok and Plain(can) == true
end

-- A main hand that leaves no off hand: a two-hand weapon, or a bow, gun
-- or crossbow (weapon subclass 2, 3, 18). A wand (19) leaves it free.
local RANGED_2H = { [2] = true, [3] = true, [18] = true }
local WEAPON_CLASS = 2 -- Enum.ItemClass.Weapon

local function BothHands(link)
	local equipLoc, classID, subClassID = Instant(link)
	if equipLoc == "INVTYPE_2HWEAPON" then return true end
	return classID == WEAPON_CLASS and RANGED_2H[subClassID] == true
end

-- What a one-hand weapon can be compared with in the off hand: a weapon,
-- or nothing. A shield or a held item is no weapon to compare with.
local OFF_WEAPON = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true }

-- What each class can wear (TICK-0152, D-037). The tooltip's red line is
-- the game's word for now (level, a skill not learned yet); this table is
-- the class's own limit, so a mage never sees a marker on mail even when
-- the tooltip has no red line. Classic and 12.x lists together: the
-- tooltip catches what one of them does not allow yet.
local SHIELD = 6 -- Enum.ItemArmorSubclass.Shield
local CLASS_ARMOR = { -- the heaviest armour type, 1 cloth .. 4 plate
	WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, ROGUE = 2, DRUID = 2,
	PRIEST = 1, MAGE = 1, WARLOCK = 1,
}
local CLASS_SHIELD = { WARRIOR = true, PALADIN = true, SHAMAN = true }
-- Weapon subclasses (Enum.ItemWeaponSubclass): 0 one-hand axe, 1 two-hand
-- axe, 2 bow, 3 gun, 4 one-hand mace, 5 two-hand mace, 6 polearm,
-- 7 one-hand sword, 8 two-hand sword, 10 staff, 13 fist weapon,
-- 15 dagger, 16 thrown, 18 crossbow, 19 wand.
local CLASS_WEAPONS = {
	WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
	PALADIN = { 0, 1, 4, 5, 6, 7, 8 },
	HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18 },
	ROGUE = { 0, 2, 3, 4, 7, 13, 15, 16, 18 },
	PRIEST = { 4, 10, 15, 19 },
	SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
	MAGE = { 7, 10, 15, 19 },
	WARLOCK = { 7, 10, 15, 19 },
	DRUID = { 4, 5, 6, 10, 13, 15 },
}
for class, list in pairs(CLASS_WEAPONS) do
	local set = { [14] = true, [20] = true } -- other weapons and fishing poles: every class
	for _, sub in ipairs(list) do set[sub] = true end
	CLASS_WEAPONS[class] = set
end

local function MyClass()
	local ok, _, class = pcall(UnitClass, "player")
	class = ok and Plain(class)
	if type(class) == "string" and CLASS_ARMOR[class] then return class end
end

-- True when your class can ever wear the item. A class HUDini does not
-- know (or the game will not name) gets no marker.
function B.ClassCanWear(equipLoc, classID, subClassID)
	local class = MyClass()
	if not class then return false end
	if classID == ARMOR_CLASS then
		if subClassID == SHIELD then return CLASS_SHIELD[class] == true end
		if ARMOR_SLOTS[equipLoc] and type(subClassID) == "number" and subClassID >= 1 and subClassID <= 4 then
			return subClassID <= CLASS_ARMOR[class]
		end
		return true
	end
	if classID == WEAPON_CLASS then
		return CLASS_WEAPONS[class][subClassID] == true
	end
	return true
end

-- The plain sum of the numbers in a stat table from the game, or nil when
-- there is none or any part of it is secret.
function B.StatSum(stats)
	if type(stats) ~= "table" or ns.IsSecret(stats) then return nil end
	local sum = 0
	local ok = pcall(function()
		for key, value in pairs(stats) do
			if ns.IsSecret(key) or ns.IsSecret(value) then error("secret") end
			if type(value) == "number" then sum = sum + value end
		end
	end)
	if ok then return sum end
end

local function Stats(link)
	local fn = C_Item and C_Item.GetItemStats or _G.GetItemStats
	if not fn then return end
	local ok, stats = pcall(fn, link)
	if ok then return B.StatSum(stats) end
end

-- The game's stat compare: what you gain if new replaces old, summed.
local function Delta(new, old)
	local fn = C_Item and C_Item.GetItemStatDelta or _G.GetItemStatDelta
	if not fn then return end
	local ok, stats = pcall(fn, new, old)
	if ok then return B.StatSum(stats) end
end

-- True when the game's stat compare of link against what you wear in one
-- of the slots in fit sums above zero. Nil when any compare is unknown.
local function Gain(link, fit)
	local both = BothHands(link)
	local gain = false
	for _, f in ipairs(fit) do
		local sum
		if f.link then sum = Delta(link, f.link) else sum = Stats(link) end
		if sum == nil then return nil end
		if both and f.slot == 16 then
			-- Both hands: what you hold in the off hand goes too.
			local off = WornLink(17)
			if off == nil then return nil end
			if off then
				local lost = Stats(off)
				if lost == nil then return nil end
				sum = sum - lost
			end
		end
		if sum > 0 then gain = true end
	end
	return gain
end

-- The two markers for the item in bag, slot (its link): how many item
-- levels it is above what you wear for it (or nil), and true when the
-- game's stat compare with what you wear there sums above zero (or nil).
-- The cheap checks come first; the tooltip is built only for an item that
-- would show a marker.
function B.Markers(bag, slot, link)
	local equipLoc, classID, subClassID = Instant(link)
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots then return end
	if not B.ClassCanWear(equipLoc, classID, subClassID) then return end
	local Info = C_Item and C_Item.GetItemInfo or GetItemInfo
	if Info then
		local ok, _, _, _, _, minLevel = pcall(Info, link)
		local myLevel = Plain(UnitLevel("player"))
		minLevel = ok and Plain(minLevel)
		if type(minLevel) == "number" and type(myLevel) == "number" and minLevel > myLevel then return end
	end

	local fitsOff = true
	if slots[#slots] == 17 then
		-- The off hand fits only beside a one-hand main hand, and for a
		-- one-hand weapon only when it is empty or holds a weapon. A link the
		-- game will not show leaves that open: no number.
		local mainHand = WornLink(16)
		if mainHand == nil then return end
		if mainHand and BothHands(mainHand) then fitsOff = false end
		if equipLoc == "INVTYPE_WEAPON" then
			if not CanDual() then
				fitsOff = false
			else
				local offHand = WornLink(17)
				if offHand == nil then return end
				if offHand and not OFF_WEAPON[Instant(offHand)] then fitsOff = false end
			end
		end
	end
	-- The slots it can go in, with what you wear there (false: empty). A
	-- link the game will not show: no marker at all.
	local fit = {}
	for _, at in ipairs(slots) do
		if at ~= 17 or fitsOff then
			local worn = WornLink(at)
			if worn == nil then return end
			fit[#fit + 1] = { slot = at, link = worn }
		end
	end
	if #fit == 0 then return end

	-- The number: item level above the lower of what you wear there.
	local up
	local level = ItemLevel(Location("CreateFromBagAndSlot", bag, slot), link)
	if level then
		local worst
		for _, f in ipairs(fit) do
			local have = 0
			if f.link then have = ItemLevel(Location("CreateFromEquipmentSlot", f.slot), f.link) end
			if not have then worst = nil break end -- the game will not say: no number
			if not worst or have < worst then worst = have end
		end
		if worst and level > worst then up = level - worst end
	end
	-- Armour lighter than what you wear there gets no number.
	if up and ARMOR_SLOTS[equipLoc] then
		local kind = ArmorType(link)
		if kind > 0 and kind < ArmorType(fit[1].link) then up = nil end
	end

	-- The second marker: the game's stat compare sums above zero.
	local gain = Gain(link, fit) or nil

	if not (up or gain) then return end
	if not Wearable(bag, slot, link) then return end
	return up, gain
end

--------------------------------------------------------------------------------
-- The numbers on the game's bag buttons
--------------------------------------------------------------------------------

local labels = setmetatable({}, { __mode = "k" }) -- the game's button -> HUDini's number
local gains = setmetatable({}, { __mode = "k" })  -- the game's button -> HUDini's stat marker
local known = {}     -- the bag windows HUDini hooked, in order
local hooked = {}    -- window -> true

-- The two markers, each in its own corner inside the quality border: the
-- stack count is at the bottom right, the upgrade arrow and the junk coin
-- at the top left.
local NUMBER = { store = labels, point = "TOPRIGHT", x = -3, y = -3, r = 0.25, g = 1, b = 0.25 } -- green
local GAIN = { store = gains, point = "BOTTOMLEFT", x = 3, y = 3, r = 1, g = 0.82, b = 0 }         -- gold

local function Label(button, make, kind)
	local fs = kind.store[button]
	if fs or not make then return fs end
	-- Sublevel 7: above the quality border, which is an OVERLAY texture too.
	fs = button:CreateFontString(nil, "OVERLAY", nil, 7)
	fs:SetFontObject("NumberFontNormal")
	fs:SetTextColor(kind.r, kind.g, kind.b)
	fs:SetPoint(kind.point, button, kind.point, kind.x, kind.y)
	kind.store[button] = fs
	return fs
end

local function Put(button, kind, text)
	local fs = Label(button, text ~= nil, kind)
	if not fs then return end
	if text then
		fs:SetText(text)
		fs:Show()
	else
		fs:SetText("")
		fs:Hide()
	end
end

local function Call(obj, method)
	local fn = obj[method]
	if type(fn) ~= "function" then return end
	local ok, v = pcall(fn, obj)
	if ok then return Plain(v) end
end

local function PaintButton(button)
	local up, gain
	local bag, slot = Call(button, "GetBagID"), Call(button, "GetID")
	if type(bag) == "number" and type(slot) == "number" and bag >= 0 and bag <= LAST_BAG then
		local link = BagLink(bag, slot)
		if link then up, gain = B.Markers(bag, slot, link) end
	end
	Put(button, NUMBER, up and ("+%d"):format(up) or nil)
	Put(button, GAIN, gain and "+" or nil)
end

-- The item buttons a bag window shows now.
local function Buttons(window)
	local list = {}
	if type(window.EnumerateValidItems) == "function" then
		local ok = pcall(function()
			for _, button in window:EnumerateValidItems() do list[#list + 1] = button end
		end)
		if ok then return list end
		wipe(list)
	end
	if type(window.Items) == "table" then
		for _, button in ipairs(window.Items) do list[#list + 1] = button end
	end
	return list
end

local function PaintWindow(window)
	if not M.enabled then return end
	for _, button in ipairs(Buttons(window)) do PaintButton(button) end
end
B.PaintWindow = PaintWindow

-- The game's bag windows: the combined one and one per bag.
local function Windows()
	local out = {}
	if _G.ContainerFrameCombinedBags then out[#out + 1] = _G.ContainerFrameCombinedBags end
	for i = 1, tonumber(_G.NUM_CONTAINER_FRAMES) or 13 do
		local window = _G["ContainerFrame" .. i]
		if window then out[#out + 1] = window end
	end
	return out
end

local function Hook()
	for _, window in ipairs(Windows()) do
		if not hooked[window] then
			hooked[window] = true
			known[#known + 1] = window
			if type(window.UpdateItems) == "function" then
				hooksecurefunc(window, "UpdateItems", PaintWindow)
			end
			window:HookScript("OnShow", PaintWindow)
		end
	end
end

local function PaintAll()
	for _, window in ipairs(known) do
		if window:IsShown() then PaintWindow(window) end
	end
end

local pending = false
local function Soon()
	if pending then return end
	pending = true
	M:After(0.1, function()
		pending = false
		PaintAll()
	end)
end

M:On({ "PLAYER_EQUIPMENT_CHANGED", "PLAYER_LEVEL_UP", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }, Soon)

function M:OnEnable()
	pending = false
	Hook()
	PaintAll()
end

function M:OnDisable()
	pending = false
	for _, store in ipairs({ labels, gains }) do
		for _, fs in pairs(store) do
			fs:SetText("")
			fs:Hide()
		end
	end
end
