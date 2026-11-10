-- The target's rank after its level, the PvP mark on your bar and a player
-- target's, and the feed line when resting starts and stops (TICK-0097).
-- Every value comes through a pcall and Plain(): a secret draws nothing and
-- throws nothing. What the marks look like needs a test sitting.

-- A logged-in world. The target's rank (w.rank, w.boss), PvP flags (w.pvp,
-- w.ffa), factions (w.faction) and resting (w.resting) are set by the test.
-- secret: each value in w.secret reads as a secret ("SECRET" from the start).
-- A test flags the very value that would draw a mark ("elite", true,
-- "Horde"), so only Plain() keeps it off: a raw "SECRET" fails the compare
-- on its own. lines: each feed line asked for.
local function World(secret, resting)
	local w = H.world()
	if secret then
		w.secret = { SECRET = true }
		w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	end
	w.pvp, w.ffa, w.faction = {}, {}, { player = "Horde", target = "Alliance" }
	w.resting = resting or false
	w.env.UnitClassification = function(u) if u == "target" then return w.rank end end
	w.env.UnitIsBossMob = function(u) return u == "target" and w.boss or false end
	w.env.UnitIsPVP = function(u) return w.pvp[u] or false end
	w.env.UnitIsPVPFreeForAll = function(u) return w.ffa[u] or false end
	w.env.UnitFactionGroup = function(u) return w.faction[u] end
	w.env.UnitIsPlayer = function(u) return u == "player" or (u == "target" and w.targetIsPlayer) or false end
	w.env.IsResting = function() return w.resting end

	-- loadAddon, with the feed watched from before the login.
	w:load(unpack(H.tocFiles()))
	local F, lines = w.ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		lines[#lines + 1] = spec
		return Line(spec)
	end
	w.lines = lines
	w:fire("ADDON_LOADED", "HUDini")
	w:fire("PLAYER_LOGIN")
	w:fire("PLAYER_ENTERING_WORLD", true, false)
	w.hasTarget = true
	return w, w.ns
end

-- The rank text after a classification change, and whether it shows.
local function Rank(w)
	w:fire("UNIT_CLASSIFICATION_CHANGED", "target")
	local bar = w.ns.GetBar("targethealth")
	return bar.rank:GetText(), bar.rankShown
end

-- The PvP mark of a bar: its atlas while shown, or nil.
local function Mark(bar)
	if bar.pvp:IsShown() then return bar.pvp:GetAtlas() end
end

local function PlayerMark(w)
	w:fire("PLAYER_FLAGS_CHANGED", "player")
	return Mark(w.ns.GetBar("health"))
end

local function TargetMark(w)
	w:fire("PLAYER_FLAGS_CHANGED", "target")
	return Mark(w.ns.GetBar("targethealth"))
end

local HORDE = "UI-HUD-UnitFrame-SmallCircle-Horde"
local ALLIANCE = "UI-HUD-UnitFrame-SmallCircle-Alliance"
local FFA = "UI-HUD-UnitFrame-Player-PVP-FFAIcon"

--------------------------------------------------------------------------------
-- The rank
--------------------------------------------------------------------------------

H.test("each rank draws its word, and a plain mob draws none", function()
	local w = World()
	for c, want in pairs({ elite = "Elite", rare = "Rare", rareelite = "Rare elite", worldboss = "Boss" }) do
		w.rank = c
		local text, shown = Rank(w)
		H.eq(text, want, c)
		H.eq(shown, true, c .. " shows")
	end
	for _, c in ipairs({ "normal", "trivial", "minus", false }) do
		w.rank = c or nil
		local text, shown = Rank(w)
		H.eq(text, "", tostring(c) .. ": no word")
		H.eq(shown, false, tostring(c) .. ": nothing shows")
	end
end)

H.test("a dungeon boss is a Boss by UnitIsBossMob, even as an elite", function()
	local w = World()
	w.rank, w.boss = "elite", true
	H.eq((Rank(w)), "Boss")
end)

H.test("the rank goes with the switch off and with no target", function()
	local w = World()
	w.rank = "elite"
	H.eq((Rank(w)), "Elite", "on")
	w.env.HUDiniDB.showRankMark = false
	H.eq((Rank(w)), "", "the switch off")
	w.env.HUDiniDB.showRankMark = true
	H.eq((Rank(w)), "Elite", "on again")
	w.hasTarget = false
	H.eq((Rank(w)), "", "no target: a sample shows no stale rank")
end)

H.test("a secret rank, a throw or no API draws no rank", function()
	local w = World(true)
	w.rank = "elite"
	w.secret.elite = true
	H.eq((Rank(w)), "", "a secret elite")
	w.secret.elite = nil
	H.eq((Rank(w)), "Elite", "the same elite, plain")
	w.rank, w.boss = "normal", true
	w.secret[true] = true
	H.eq((Rank(w)), "", "a secret boss")
	w.secret[true] = nil
	H.eq((Rank(w)), "Boss", "the same boss, plain")
	w.rank, w.boss = "elite", false
	w.env.UnitClassification = function() error("no") end
	w.env.UnitIsBossMob = function() error("no") end
	H.eq((Rank(w)), "", "a throw")
	w.env.UnitClassification, w.env.UnitIsBossMob = nil, nil
	H.eq((Rank(w)), "", "no API")
end)

H.test("a boss level of -1 reads ??", function()
	local w = World()
	w.level = -1
	w:fire("UNIT_LEVEL", "target")
	H.eq(w.ns.GetBar("targethealth").level:GetText(), "??")
end)

--------------------------------------------------------------------------------
-- The PvP mark
--------------------------------------------------------------------------------

H.test("your bar shows your faction's mark while you are flagged", function()
	local w = World()
	H.eq(PlayerMark(w), nil, "not flagged")
	w.pvp.player = true
	H.eq(PlayerMark(w), HORDE, "flagged")
	w.ffa.player = true
	H.eq(PlayerMark(w), FFA, "free-for-all comes first")
	w.ffa.player = false
	w.faction.player = "Neutral"
	H.eq(PlayerMark(w), nil, "no faction: no mark")
	w.faction.player = "Horde"
	w.env.HUDiniDB.showPvPMark = false
	H.eq(PlayerMark(w), nil, "the switch off")
	w.env.HUDiniDB.showPvPMark = true
	w.pvp.player = false
	H.eq(PlayerMark(w), nil, "flag gone")
end)

H.test("the target bar shows the mark only on a flagged player", function()
	local w = World()
	w.pvp.target = true
	H.eq(TargetMark(w), nil, "a flagged NPC: no mark")
	w.targetIsPlayer = true
	H.eq(TargetMark(w), ALLIANCE, "a flagged player")
	w.env.HUDiniDB.showPvPMark = false
	H.eq(TargetMark(w), nil, "the switch off")
	w.env.HUDiniDB.showPvPMark = true
	H.eq(TargetMark(w), ALLIANCE, "on again")
	w.hasTarget = false
	w:fire("UNIT_CLASSIFICATION_CHANGED", "target")
	H.eq(Mark(w.ns.GetBar("targethealth")), nil, "no target: no stale mark")
end)

H.test("a secret PvP flag or faction draws no mark", function()
	local w = World(true)
	w.targetIsPlayer = true
	w.pvp.player, w.pvp.target = true, true
	w.secret[true] = true
	H.eq(PlayerMark(w), nil, "a secret flag, you")
	H.eq(TargetMark(w), nil, "a secret flag, the target")
	w.secret[true] = nil
	H.eq(PlayerMark(w), HORDE, "the same flag, plain, you")
	H.eq(TargetMark(w), ALLIANCE, "the same flag, plain, the target")
	w.secret.Horde, w.secret.Alliance = true, true
	H.eq(PlayerMark(w), nil, "a secret faction, you")
	H.eq(TargetMark(w), nil, "a secret faction, the target")
	w.secret.Horde, w.secret.Alliance = nil, nil
	w.ffa.target = "SECRET"
	H.eq(TargetMark(w), ALLIANCE, "a secret free-for-all falls back to the faction")
end)

H.test("an atlas the client lacks draws no mark and moves no text", function()
	local w = World()
	local asked = {}
	w.env.C_Texture = { GetAtlasInfo = function(name)
		asked[#asked + 1] = name
		if name ~= HORDE then return { width = 16, height = 16 } end
	end }
	w.pvp.player = true
	H.eq(PlayerMark(w), nil, "no Horde atlas: no mark")
	H.eq(asked[1], HORDE, "it asked for the Horde atlas")
	w.targetIsPlayer, w.pvp.target = true, true
	H.eq(TargetMark(w), ALLIANCE, "the Alliance atlas is there")
	w.faction.target = "Horde"
	local bar = w.ns.GetBar("targethealth")
	H.eq(TargetMark(w), nil, "no Horde atlas on the target either")
	local _, to = bar.level:GetPoint(1)
	H.eq(to, bar, "the level stays at the bar's left end")
	w.env.C_Texture.GetAtlasInfo = function() error("no") end
	w.faction.target = "Alliance"
	H.eq(TargetMark(w), nil, "a throw: no mark")
end)

H.test("the level moves right of the mark, and the rank sits after the level", function()
	local w = World()
	local bar = w.ns.GetBar("targethealth")
	w.targetIsPlayer, w.pvp.target, w.rank = true, true, "elite"
	TargetMark(w)
	local _, to, rel = bar.level:GetPoint(1)
	H.ok(to == bar.pvp and rel == "RIGHT", "the level is right of the mark")
	_, to, rel = bar.rank:GetPoint(1)
	H.ok(to == bar.level and rel == "BOTTOMRIGHT", "the rank is right of the level")
	_, to, rel = bar.name:GetPoint(1)
	H.ok(to == bar.rank and rel == "BOTTOMRIGHT", "the name is right of the rank")
	w.pvp.target, w.rank = false, nil
	TargetMark(w)
	_, to = bar.level:GetPoint(1)
	H.eq(to, bar, "no mark: the level goes back to the bar's left end")
	_, to, rel = bar.name:GetPoint(1)
	H.ok(to == bar.level and rel == "BOTTOMRIGHT", "no rank: the name is right of the level")
end)

--------------------------------------------------------------------------------
-- The resting line
--------------------------------------------------------------------------------

-- The resting lines asked for since the last call.
local function RestLines(w)
	local out = {}
	for _, spec in ipairs(w.lines) do
		if spec.kind == "resting" then out[#out + 1] = spec.text end
	end
	for i = #w.lines, 1, -1 do w.lines[i] = nil end
	return table.concat(out, " | ")
end

local function Rest(w, on)
	w.resting = on
	w:fire("PLAYER_UPDATE_RESTING")
end

H.test("resting gives one line when it starts and one when it stops, none at login", function()
	local w, ns = World(false, true)
	H.eq(RestLines(w), "", "a login in an inn: no line")
	w.time = w.time + 10
	Rest(w, true)
	H.eq(RestLines(w), "", "no change: no line")
	Rest(w, false)
	H.eq(RestLines(w), ns.Text("feed.restStop"), "it stops")
	Rest(w, false)
	H.eq(RestLines(w), "", "no change again: no line")
	Rest(w, true)
	H.eq(RestLines(w), ns.Text("feed.restStart"), "it starts")
end)

H.test("a resting change in the first seconds after a login, a /reload or the feed on is quiet", function()
	-- The client may say "not resting" at the login and "resting" a moment
	-- later: that is no change you made.
	local w, ns = World()
	Rest(w, true)
	H.eq(RestLines(w), "", "just after the login: no line")
	w.time = w.time + 10
	Rest(w, false)
	H.eq(RestLines(w), ns.Text("feed.restStop"), "later: the line")
	w:fire("PLAYER_ENTERING_WORLD", false, true)
	Rest(w, true)
	H.eq(RestLines(w), "", "just after a /reload: no line")
	w.time = w.time + 10
	w.env.HUDiniDB.showFeed = false
	w.ns.HUDini:Apply()
	w.env.HUDiniDB.showFeed = true
	w.ns.HUDini:Apply()
	Rest(w, false)
	H.eq(RestLines(w), "", "just after the feed came on: no line")
	w.time = w.time + 10
	Rest(w, true)
	H.eq(RestLines(w), ns.Text("feed.restStart"), "later: the line")
	w:fire("PLAYER_ENTERING_WORLD", false, false)
	w.resting = false
	w:fire("PLAYER_UPDATE_RESTING")
	H.eq(RestLines(w), ns.Text("feed.restStop"), "a loading screen is no login: the line")
end)

H.test("a /reload is quiet, a loading screen that changes it is not", function()
	local w, ns = World()
	w.resting = true
	w:fire("PLAYER_ENTERING_WORLD", false, true)
	H.eq(RestLines(w), "", "a /reload notes it with no line")
	w.resting = false
	w:fire("PLAYER_ENTERING_WORLD", false, false)
	H.eq(RestLines(w), ns.Text("feed.restStop"), "a hearth out of the inn")
end)

H.test("the feed coming back on notes resting with no line", function()
	local w = World()
	w.env.HUDiniDB.showFeed = false
	w.ns.HUDini:Apply()
	Rest(w, true)
	H.eq(RestLines(w), "", "feed off: no line")
	w.env.HUDiniDB.showFeed = true
	w.ns.HUDini:Apply()
	H.eq(RestLines(w), "", "feed on again: no line for a change made while it was off")
	w.time = w.time + 10
	Rest(w, false)
	H.eq(RestLines(w), w.ns.Text("feed.restStop"), "the next change gives its line")
end)

H.test("Resting off gives no line, and keeps the state", function()
	local w, ns = World()
	w.time = w.time + 10
	w.env.HUDiniDB.feedResting = false
	Rest(w, true)
	H.eq(RestLines(w), "", "off: no line")
	w.env.HUDiniDB.feedResting = true
	Rest(w, true)
	H.eq(RestLines(w), "", "on again with no change: no line")
	Rest(w, false)
	H.eq(RestLines(w), ns.Text("feed.restStop"), "on: the next change speaks")
end)

H.test("a secret, a throw or no IsResting gives no line and keeps the last state", function()
	local w, ns = World(true)
	w.time = w.time + 10
	w.secret[true] = true
	Rest(w, true)
	H.eq(RestLines(w), "", "a secret true: no line")
	w.secret[true] = nil
	w.env.IsResting = function() error("no") end
	w:fire("PLAYER_UPDATE_RESTING")
	H.eq(RestLines(w), "", "a throw")
	w.env.IsResting = nil
	w:fire("PLAYER_UPDATE_RESTING")
	H.eq(RestLines(w), "", "no API")
	w.env.IsResting = function() return w.resting end
	Rest(w, true)
	H.eq(RestLines(w), ns.Text("feed.restStart"), "the last plain state was false")
end)
