-- A weapon skill-up line in the feed shows your cap (TICK-0170, GitHub #15):
-- the game's cap from the skills list (C_SkillInfo on the Forever client),
-- else 5 points per level (DK's rule). A profession line is as before
-- (GetProfessionInfo), and a secret line shows as it came.

-- A logged-in level 14 Warrior with the feed on. w.lines: the skills list
-- C_SkillInfo shows (nil: the client has no C_SkillInfo). w.profs: the
-- professions, { name, icon, rank, maxRank }.
local function World(setup)
	local w = H.world()
	w.class, w.className = "WARRIOR", "Warrior"
	w.level = 14
	w.secret = {}
	w.lines = {}
	w.profs = {}
	local env = w.env
	env.SKILL_RANK_UP = "Your skill in %s has increased to %d."
	env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	env.C_SkillInfo = {
		GetNumSkillLines = function() return #w.lines end,
		GetSkillLineInfo = function(i) return w.lines[i] end,
	}
	env.GetProfessions = function()
		local out = {}
		for i = 1, #w.profs do out[i] = i end
		return unpack(out)
	end
	env.GetProfessionInfo = function(i)
		local p = w.profs[i]
		if p then return p[1], p[2], p[3], p[4] end
	end
	if setup then setup(w) end
	w:loadAddon()
	w.time = w.time + 10                       -- past the quiet time after login
	local F, shown = w.ns.Feed, {}
	local Line = F.Line
	F.Line = function(spec)
		local L = Line(spec)
		if L then shown[#shown + 1] = L end
		return L
	end
	w.shown = shown
	return w
end

-- The game says the skill went up; the feed's newest line, and its text.
local function Skill(w, msg)
	w:fire("CHAT_MSG_SKILL", msg)
	w:runTimers()
	local L = w.shown[#w.shown]
	local text = L and L.text
	if type(text) == "function" then text = text(L) end
	return L, text
end

local function Line(name, rank, maxRank, header)
	return { name = name, isHeader = header or false, rank = rank, maxRank = maxRank }
end

H.test("skill cap: a weapon skill uses the game's cap from the skills list", function()
	local w = World()
	w.lines = { Line("Weapon Skills", 0, 0, true), Line("Swords", 42, 70), Line("Maces", 10, 65) }
	local L, text = Skill(w, "Your skill in Swords has increased to 43.")
	H.eq(text, "Swords 43/70", "the game's cap")
	H.eq(L.key, "skill:Swords", "one line per skill: it replaces itself")
	local _, maces = Skill(w, "Your skill in Maces has increased to 11.")
	H.eq(maces, "Maces 11/65", "each skill its own cap")
end)

H.test("skill cap: no cap from the game is 5 x your level", function()
	local w = World()
	-- Not in the list (a collapsed header hides it).
	local _, text = Skill(w, "Your skill in Swords has increased to 43.")
	H.eq(text, "Swords 43/70", "5 x level 14")
	-- In the list, but with no plain cap.
	w.lines = { Line("Swords", 43, 0) }
	_, text = Skill(w, "Your skill in Swords has increased to 44.")
	H.eq(text, "Swords 44/70", "a zero cap is no cap")
	local hidden = {}
	w.secret[hidden] = true
	w.lines = { Line("Swords", 44, hidden) }
	_, text = Skill(w, "Your skill in Swords has increased to 45.")
	H.eq(text, "Swords 45/70", "a secret cap is no cap")
	-- A new level: the next skill-up has the new cap.
	w.level = 15
	_, text = Skill(w, "Your skill in Swords has increased to 46.")
	H.eq(text, "Swords 46/75", "the cap follows your level")
end)

H.test("skill cap: a client with no C_SkillInfo, or one that throws, uses 5 x your level", function()
	local w = World(function(w) w.env.C_SkillInfo = nil end)
	local _, text = Skill(w, "Your skill in Defense has increased to 20.")
	H.eq(text, "Defense 20/70", "no API")
	w.env.C_SkillInfo = {
		GetNumSkillLines = function() return 1 end,
		GetSkillLineInfo = function() error("no") end,
	}
	_, text = Skill(w, "Your skill in Defense has increased to 21.")
	H.eq(text, "Defense 21/70", "a throw")
	w.env.C_SkillInfo.GetNumSkillLines = function() error("no") end
	_, text = Skill(w, "Your skill in Defense has increased to 22.")
	H.eq(text, "Defense 22/70", "a throw on the count")
end)

H.test("skill cap: no level and no game cap, no cap", function()
	local w = World()
	local hidden = {}
	w.secret[hidden] = true
	w.level = hidden
	local _, text = Skill(w, "Your skill in Swords has increased to 43.")
	H.eq(text, "Swords 43", "as before TICK-0170")
end)

H.test("skill cap: a profession line is as before", function()
	local w = World()
	w.profs = { { "Tailoring", 136249, 75, 150 } }
	-- The skills list would say otherwise: the profession's own answer wins.
	w.lines = { Line("Tailoring", 75, 300) }
	local L, text = Skill(w, "Your skill in Tailoring has increased to 76.")
	H.eq(text, "Tailoring 76/150", "GetProfessionInfo's top rank")
	H.eq(L.icon, 136249, "and its icon")
	-- A profession found by part of its name has no top rank, and no 5 x level.
	w.profs = { { "Cooking", 133971, 10, 75 } }
	_, text = Skill(w, "Your skill in Cooking Lore has increased to 11.")
	H.eq(text, "Cooking Lore 11", "no cap for a part match")
end)

H.test("skill cap: a secret line shows as it came", function()
	local w = World()
	w.lines = { Line("Swords", 42, 70) }
	local msg = "Your skill in Swords has increased to 43."
	local L = Skill(w, msg)
	H.eq(L.raw, nil, "plain: read")
	w.secret[msg] = true
	L = Skill(w, msg)
	H.eq(L.raw, msg, "secret: as it came")
	H.eq(L.maxRank, nil, "and no cap")
end)
