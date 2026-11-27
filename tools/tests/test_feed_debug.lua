-- /hud debug feed (TICK-0228): hard sample lines in the feed, through
-- F.Line, to check the layout (wrapped lines, money, icons, colors, odd
-- characters). It adds lines only: no saved data, no session totals. How
-- the lines look needs the game.

-- A logged-in world with the feed on. w.shown: each line F.Line made;
-- w.specs: each spec F.Line got; w.big: each highlight.
local function World()
	local w = H.world()
	w:loadAddon()
	w.time = w.time + 10 -- past the quiet time after login
	local F = w.ns.Feed
	w.shown, w.specs, w.big = {}, {}, {}
	local Line, Highlight = F.Line, F.Highlight
	F.Line = function(spec)
		w.specs[#w.specs + 1] = spec
		local L = Line(spec)
		if L then w.shown[#w.shown + 1] = L end
		return L
	end
	F.Highlight = function(item)
		w.big[#w.big + 1] = item
		return Highlight(item)
	end
	return w, w.ns
end

-- Saved data as one string, keys sorted, to see that nothing changed.
local function Dump(v, seen)
	seen = seen or {}
	if type(v) ~= "table" then return type(v) .. ":" .. tostring(v) end
	if seen[v] then return "<loop>" end
	seen[v] = true
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local out = {}
	for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. Dump(v[k], seen) end
	return "{" .. table.concat(out, ",") .. "}"
end

local function TextOf(L)
	local t = L.text
	if type(t) == "function" then t = t(L) end
	return t
end

-- Pixels on one line: 6 a character shown, 14 an icon; codes take none.
local function Width(t)
	t = t:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|[TA][^|]*|t", "##")
		:gsub("||", "|"):gsub("[\128-\191]", "")
	return #t * 6 + select(2, t:gsub("##", "")) * 2
end

-- A fake font string 300 pixels wide.
local function Measured()
	local fs = {}
	function fs.GetWidth() return 300 end
	function fs.SetText(self, t) self.t = t end
	function fs.GetUnboundedStringWidth(self) return Width(self.t) end
	return { fs = fs }
end

H.test("/hud debug feed puts its lines in the feed through F.Line", function()
	local w, ns = World()
	w:slash("/hud debug feed")
	H.eq(#w.specs, 8, "eight sample lines")
	H.eq(#w.shown, 8, "all shown with every kind on")
	local kinds = {}
	for _, L in ipairs(w.shown) do
		kinds[L.kind] = true
		H.ok(L.icon, L.kind .. ": its icon")
		local text = TextOf(L)
		H.ok(type(text) == "string" and #text > 20, L.kind .. ": a text")
		H.ok(not text:find("nil", 1, true), "no nil in: " .. text)
	end
	for _, kind in ipairs({ "loot", "money", "quest", "gear", "xp", "rep" }) do
		H.ok(kinds[kind], "a " .. kind .. " line")
	end
	H.eq(#w.big, 1, "one big highlight")
	H.ok(H.printed(w, ns.TEXT[0]["debug.feedSent"]:format(8)), "it says how many")
end)

H.test("the long lines fill to 2 and 3 lines at the line's width", function()
	local w = World()
	w:slash("/hud debug feed")
	local fills = {}
	for _, spec in ipairs(w.specs) do
		if type(spec.text) == "function" then
			local L = Measured()
			local text = spec.text(L)
			local lines = Width(text) / 300
			fills[#fills + 1] = { kind = spec.kind, lines = lines, text = text }
			H.eq(spec.text(L), text, "built once")
		end
	end
	local two, three = 0, 0
	for _, f in ipairs(fills) do
		-- Half a line past n - 1, and less than half a line past that.
		if f.lines >= 1.5 and f.lines < 2 then two = two + 1 end
		if f.lines >= 2.5 and f.lines < 3 then three = three + 1 end
	end
	H.ok(two >= 1, "a line of 2")
	H.ok(three >= 1, "a line of 3")
	-- Money at the very end of a wrapped line.
	local last = false
	for _, f in ipairs(fills) do
		if f.kind == "money" and f.text:find("Copper[^|]*|t$") then last = true end
	end
	H.ok(last, "a money line ends with its coins")
end)

H.test("with no width from the game, a long line still gets its words", function()
	local w = World()
	w:slash("/hud debug feed")
	for _, L in ipairs(w.shown) do
		local text = TextOf(L)
		H.ok(type(text) == "string", L.kind)
	end
	local fill
	for _, spec in ipairs(w.specs) do
		if type(spec.text) == "function" then fill = spec.text break end
	end
	local L = { fs = { GetWidth = function() return 0 end, SetText = function() end } }
	local text = fill(L)
	H.ok(#text > 60, "words added: " .. text)
end)

H.test("/hud debug feed changes no saved data and no session totals", function()
	local w, ns = World()
	local before, session = Dump(w.env.HUDiniDB), Dump(ns.Feed.session)
	w:slash("/hud debug feed")
	w.time = w.time + 1
	w:runTimers()
	H.eq(Dump(ns.Feed.session), session, "the session")
	H.eq(Dump(w.env.HUDiniDB), before, "the saved data")
end)

H.test("/hud debug feed works in a fight", function()
	local w = World()
	w.combat = true
	w:slash("/hud debug feed")
	H.eq(#w.shown, 8)
	H.eq(#w.blocked, 0, "nothing blocked")
end)

H.test("with the feed off it says so and adds nothing", function()
	local w, ns = World()
	w.env.HUDiniDB.showFeed = false
	w:slash("/hud debug feed")
	H.eq(#w.specs, 0)
	H.ok(H.printed(w, ns.TEXT[0]["feed.offForTest"]))
end)

H.test("/hud debug lists feed", function()
	local w, ns = World()
	w:slash("/hud debug")
	H.ok(H.printed(w, ns.TEXT[0]["debug.helpLine"]:format("feed", ns.TEXT[0]["debug.feed"])))
end)
