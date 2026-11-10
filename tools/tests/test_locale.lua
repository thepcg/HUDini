-- The player text in Locales/enUS.lua (TICK-0025). The gate's locale check
-- sees a key only in a Text("key") call; /hud help and /hud debug read their
-- keys from tables, so these tests run the commands and look for a raw key
-- in what they print, at each flair level.

local function Logged()
	local w = H.world()
	w:loadAddon()
	w.printed = {}
	return w
end

local LINES = {
	"/hud help", "/hud help why", "/hud help buffs", "/hud help auramap", "/hud help feedignore",
	"/hud help feedsession", "/hud help xp", "/hud help version", "/hud help debug", "/hud help reset",
	"/hud help lock", "/hud help unlock", "/hud help test", "/hud help setup", "/hud help options",
	"/hud help help", "/hud help nothere", "/hud nothere",
	"/hud debug", "/hud debug nothere", "/hud reset", "/hud reset yes", "/hud reset class",
	"/hud reset no", "/hud reset settings", "/hud reset no", "/hud lock", "/hud unlock", "/hud lock",
	"/hud buffs", "/hud auramap", "/hud feedignore", "/hud feedsession", "/hud xp reset",
	"/hud version", "/hud why",
}

-- The first key of level 0 that shows in the printed text, or nil.
local function RawKey(w)
	local all = table.concat(w.printed, "\n")
	for key in pairs(w.ns.TEXT[0]) do
		if all:find(key, 1, true) then return key end
	end
	return nil
end

H.test("no chat command prints a raw key, at any flair level", function()
	for level = 0, 2 do
		local w = Logged()
		w.env.HUDiniDB.flair = level
		for _, line in ipairs(LINES) do w:slash(line) end
		H.ok(#w.printed > 40, ("level %d: %d lines"):format(level, #w.printed))
		local key = RawKey(w)
		H.ok(not key, ("level %d: %s shows as a key"):format(level, tostring(key)))
	end
end)

H.test("/hud help reads its lines at the flair level now", function()
	local w = Logged()
	w:slash("/hud help why")
	H.ok(H.printed(w, "Explain why the main HUD is visible or hidden."), "level 0")
	w.env.HUDiniDB.flair = 2
	w.printed = {}
	w:slash("/hud help why")
	H.ok(H.printed(w, "Ask the main HUD to account for its presence or absence. A disappearing act is much easier to appreciate once you know the trick."), "level 2")
	w.printed = {}
	w:slash("/hud help")
	H.ok(H.printed(w, w.ns.TEXT[0]["help.section.hud"] .. ":|r"), "a section name has one text")
end)

H.test("the action bar names come from the locale", function()
	local w = Logged()
	local names = {}
	for _, bar in ipairs(w.ns.BAR_LAYOUT) do names[#names + 1] = bar.name end
	H.ok(#names >= 8, "bars: " .. #names)
	for i = 1, 8 do H.eq(names[i], "Action Bar " .. i) end
end)
