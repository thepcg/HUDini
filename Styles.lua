--[[--------------------------------------------------------------------------
	HUDini - Styles: Minimal, Standard, Leveling (TICK-0068)

	A style is a fixed value for each of five settings, and picking one
	writes those five and nothing else: never the position, the size, the
	look, hide when idle or an alert. Every style
	sets the same five, so any style can follow any other.

	Standard is built from ns.defaults, so the two cannot drift. This file
	loads after XP.lua and Feed.lua, whose modules add three of the five
	defaults.

	No style name is saved. ns.MatchStyle reads the five settings each time,
	so a setting changed by hand shows as no style ("Custom").

	The Style dropdown (Options.lua) calls ns.ApplyStyle and
	ns.MatchStyle; they keep the panel rows in step.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

-- The five settings a style sets, in the order presets.md lists them.
local KEYS = { "showXP", "showTargetPower", "showFeed", "feedQuestProgress", "feedUpgrade" }

ns.STYLE_KEYS  = KEYS
-- The order the dropdown lists the styles in.
ns.STYLE_ORDER = { "minimal", "standard", "leveling" }

local standard = {}
for _, key in ipairs(KEYS) do standard[key] = ns.defaults[key] end

ns.styles = {
	-- The icon grid, your bars and your target. No XP bar, no feed.
	minimal = {
		showXP = false, showTargetPower = false, showFeed = false,
		feedQuestProgress = false, feedUpgrade = false,
	},
	-- The defaults: Minimal, plus the XP bar, your target's power and the feed.
	standard = standard,
	-- Standard, plus quest progress and upgrade hints in the feed.
	leveling = {
		showXP = true, showTargetPower = true, showFeed = true,
		feedQuestProgress = true, feedUpgrade = true,
	},
}

-- Write a style's five settings, then apply them once. "custom", or any
-- name that is not a style, changes nothing. True if it applied.
function ns.ApplyStyle(name)
	local style, db = ns.styles[name], HUDiniDB
	if not (style and db) then return false end
	for _, key in ipairs(KEYS) do db[key] = style[key] end
	-- Apply switches the feed and the XP bar on or off, and gives Blizzard's
	-- XP bar back out of a fight only (TICK-0002).
	ns.HUDini:Apply()
	return true
end

-- The style whose five values all equal the saved ones, or nil.
function ns.MatchStyle()
	local db = HUDiniDB
	if not db then return nil end
	for _, name in ipairs(ns.STYLE_ORDER) do
		local style, same = ns.styles[name], true
		for _, key in ipairs(KEYS) do
			if db[key] ~= style[key] then same = false break end
		end
		if same then return name end
	end
	return nil
end
