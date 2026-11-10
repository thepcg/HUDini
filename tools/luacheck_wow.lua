--[[--------------------------------------------------------------------------
	luacheck options for the check gate (check 4, TICK-0050).

	tools/check.py runs luacheck v1.2.0 (MIT, lunarmodules) from the clone in
	..\.tools\luacheck, inside lupa's Lua 5.1, on every addon .lua file. Any
	warning fails the gate.

	The main catch is a global name: a misspelled API name, or a global the
	addon sets by mistake. A WoW name the addon reads must be in
	read_globals; check it in the 12.x API before you add it (as for the
	harness stubs). A global the addon writes must be in globals.

	Not a .luacheckrc in the repo root on purpose: deploy.ps1 would copy it
	into the game folder.
----------------------------------------------------------------------------]]

return {
	std = "lua51",
	max_line_length = false,

	ignore = {
		"211/ADDON", -- local ADDON, ns = ...: the WoW file header, kept in every file
		"212",       -- unused argument: event and script callbacks keep their full signature
		"542",       -- an empty if branch with only a comment says "nothing to do here"
	},

	-- Globals the addon writes.
	globals = {
		"HUDiniDB",                                         -- saved variables (.toc)
		"SLASH_HUDINI1", "SLASH_HUDINI2", "SLASH_HUDINIRELOAD1", "SlashCmdList",
		"ClickCastFrames",                                  -- Clique's shared table, filled in Clicks.lua
		"HUDini_OnAddonCompartmentClick", "HUDini_OnAddonCompartmentEnter", -- the .toc's
		"HUDini_OnAddonCompartmentLeave",                   -- AddonCompartmentFunc fields
	},

	-- Globals the addon reads: the WoW 12.x API, frames and strings.
	read_globals = {
		-- Lua helpers WoW adds
		"date", "time", "max", "nop", "tContains", "tinsert", "wipe",
		"geterrorhandler", "hooksecurefunc",

		-- C_ namespaces
		"C_ActionBar", "C_AddOns", "C_AssistedCombat", "C_Container", "C_CreatureInfo", "C_CurrencyInfo",
		"C_GossipInfo", "C_Item", "C_MajorFactions", "C_Minimap", "C_MountJournal",
		"C_PetJournal", "C_QuestLog", "C_Reputation", "C_Spell", "C_Timer",
		"C_TooltipInfo", "C_ToyBox", "C_TransmogCollection", "C_UnitAuras",

		-- Functions
		"BreakUpLargeNumbers", "CanDualWield", "CanMerchantRepair", "CreateColor",
		"CreateColorFromHexString", "CreateFont", "CreateFrame",
		"CreateSettingsButtonInitializer", "CreateSettingsCheckboxWithColorSwatchInitializer",
		"CreateSettingsListSectionHeaderInitializer",
		"GetActionInfo", "GetAddOnMetadata", "GetBindingKey", "GetDetailedItemLevelInfo",
		"GetGuildInfo", "GetInventoryItemDurability", "GetInventoryItemID", "GetInventoryItemLink",
		"GetItemIcon", "GetItemInfo", "GetItemInfoInstant", "GetLocale", "GetLootSlotInfo", "GetLootSlotLink",
		"GetMacroItem", "GetMacroSpell", "GetMaxLevelForPlayerExpansion", "GetMaxPlayerLevel",
		"GetMoney", "GetNumLootItems", "GetProfessionInfo", "GetProfessions", "GetRealmName",
		"GetRepairAllCost", "GetShapeshiftForm", "GetShapeshiftFormID", "GetShapeshiftFormInfo",
		"GetCursorPosition", "GetMinimapShape", "GetSpellLink", "GetSpellTexture", "GetTime", "GetTitleText",
		"GetWeaponEnchantInfo", "GetXPExhaustion",
		"InCombatLockdown", "IsControlKeyDown", "IsMetaKeyDown", "IsPlayerSpell", "IsResting", "IsShiftKeyDown", "IsXPUserDisabled",
		"MuteSoundFile", "UnmuteSoundFile", -- legacy globals, no generated docs; DialogueUI calls them on Forever (TICK-0133)
		"PlaySound", "RegisterAttributeDriver", "RegisterStateDriver", "ReloadUI", "ShowUIPanel",
		"SpellHasRange", "UnregisterAttributeDriver",
		"UnitAffectingCombat", "UnitCanAssist", "UnitCanAttack", "UnitCastingDuration",
		"UnitCastingInfo", "UnitChannelDuration", "UnitChannelInfo", "UnitClass", "UnitClassification",
		"UnitCreatureType", "UnitExists", "UnitFactionGroup", "UnitFullName", "UnitGUID", "UnitHealth",
		"UnitHealthMax", "UnitIsBossMob", "UnitIsConnected", "UnitIsDead", "UnitIsDeadOrGhost", "UnitIsPlayer",
		"UnitIsPVP", "UnitIsPVPFreeForAll", "C_Texture",
		"UnitIsTapDenied", "UnitLevel", "UnitName", "UnitPower", "UnitPowerMax", "UnitPowerType",
		"UnitReaction", "UnitXP", "UnitXPMax",

		-- Objects, mixins and libraries
		"AnchorUtil", "ColorPickerFrame", "Enum", "EventRegistry", "GameTooltip", "Item", "LibStub",
		"MinimalSliderWithSteppersMixin", "Settings", "SettingsPanel",

		-- Blizzard frames HUDini hides or moves
		"BagsBar", "MicroMenu", "MicroMenuContainer", "Minimap", "UIPanelWindows", "UIParent",
		-- Action Bar 1, for its end art (TICK-0084): MainActionBar in 12.x
		-- live (MainActionBar.xml:29), MainMenuBar before.
		"MainActionBar", "MainMenuBar",

		-- Tables and strings
		"DebuffTypeColor", "ERR_NEWTAXIPATH", "GUILD", "GameFontHighlight", "MAX_PLAYER_LEVEL",
		"MICRO_BUTTONS", "NUM_BAG_SLOTS", "PowerBarColor", "RAID_CLASS_COLORS", "SOUNDKIT",
		"STANDARD_TEXT_FONT", "TOOLTIP_UNIT_LEVEL", "UISpecialFrames",
	},

	-- Per-file exceptions, each with its reason. TICK-0009 has these files
	-- open, so their dead locals go in the first branch after it merges;
	-- then delete these lines.
	files = {
		["Core.lua"] = { ignore = { "211/ceil", "211/IsSecret", "431/pending" } },
		["FeedGains.lua"] = { ignore = { "231/name" } },
	},
}
