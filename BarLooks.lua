--[[--------------------------------------------------------------------------
	HUDini - Bar looks (TICK-0224, D-049)

	One look for each bar: its texture, its gradient and the gradient's
	color. Every HUDini bar is painted through ns.PaintBar, so a gradient is
	never wiped by a later SetStatusBarColor (the game's color call sets one
	color on all four corners of the fill).

	A bar id names a bar:
	  health, power, druidmana, resource, playercast, xp, targethealth,
	  targetpower, targetcast, tot, pet   (ns.BAR_LOOK_IDS)
	  timer:<spell>   one cooldown's timer bar (the spell's client name)

	A look has three fields:
	  texture   "same" (follow Bar texture), a texture key (built-in or
	            LibSharedMedia), or a file path that starts "Interface\"
	  gradient  "off", "darker", "lighter" or "color" (to the color below)
	  color     { r, g, b }: where a "color" gradient ends
	and a timer bar a fourth (TICK-0258):
	  base      { r, g, b }: the bar's own color; none (today): the Colors
	            page's Timer bar color (ns.TimerBarColor)

	Each field comes from the first of:
	  1. the saved look: HUDiniDB.barLooks[id], account-wide, or for a
	     class bar ("resource", "timer:<spell>") ns.ClassDB().looks[id]
	  2. the class file's look (barLooks in ns.RegisterClass):
	       barLooks = {
	           resource = { texture = "flat", gradient = "darker" },
	           timer = { ["Slice and Dice"] = { gradient = "lighter" } },
	       }
	  3. today's look: "same", "off", dark gray

	A pick is saved as it is, also when it equals the default, so a pick of
	Same as Bar texture beats the class file.

	Nothing saved gives today's HUD. The colors of the bars stay where they
	are (ns.BarColor and the power and reaction colors): ns.PaintBar takes
	the bar's color from its caller and makes the gradient from it. It never
	reads a color back from a frame, so a secret value cannot reach it.

	customTextures: the files a player added (the Custom texture window,
	BarLookButton.lua), account-wide, in order, at most 10. Not a setting:
	Defaults leaves the list.
----------------------------------------------------------------------------]]

local _, ns = ...

ns.BAR_LOOK_IDS = {
	"health", "power", "druidmana", "resource", "playercast", "xp",
	"targethealth", "targetpower", "targetcast", "tot", "pet",
}
ns.LOOK_GRADIENTS = { "off", "darker", "lighter", "color" }
ns.MAX_CUSTOM_TEXTURES = 10

local LOOK_DEFAULT = { texture = "same", gradient = "off", color = { 0.15, 0.15, 0.15 } }
ns.LOOK_DEFAULT = LOOK_DEFAULT

local BASE = {}
for _, id in ipairs(ns.BAR_LOOK_IDS) do BASE[id] = true end
local GRADIENT = {}
for _, g in ipairs(ns.LOOK_GRADIENTS) do GRADIENT[g] = true end
-- base: a timer bar's own color (TICK-0258); none: the Timer bar color.
local FIELD = { texture = true, gradient = true, color = true, base = true }

-- Darker and Lighter (the design's first guess; DK's play may change them).
local DARKER  = 0.45
local LIGHTER = 0.5

--------------------------------------------------------------------------------
-- Ids
--------------------------------------------------------------------------------

-- The spell of a "timer:<spell>" id, or nil.
local function TimerSpell(id)
	if type(id) ~= "string" then return nil end
	return id:match("^timer:(.+)$")
end

-- A bar of the class you play: saved per class.
local function ClassBar(id)
	return id == "resource" or TimerSpell(id) ~= nil
end

function ns.IsBarLookId(id)
	return BASE[id] == true or TimerSpell(id) ~= nil
end

function ns.TimerLookId(spell)
	return "timer:" .. tostring(spell)
end

--------------------------------------------------------------------------------
-- Values
--------------------------------------------------------------------------------

local function Valid(field, v)
	if field == "texture" then return type(v) == "string" and v ~= "" end
	if field == "gradient" then return GRADIENT[v] == true end
	if field == "color" or field == "base" then
		return type(v) == "table" and type(v[1]) == "number"
			and type(v[2]) == "number" and type(v[3]) == "number"
	end
	return false
end

-- A file path: it starts with Interface\ (any case). A texture key never
-- does.
local function IsFile(v)
	return type(v) == "string" and v:sub(1, 10):lower() == "interface\\"
end
ns.IsTextureFile = IsFile

--------------------------------------------------------------------------------
-- Saved looks
--------------------------------------------------------------------------------

-- The saved look of a bar, or nil. create: make the tables on the way.
local function Saved(id, create)
	local db = HUDiniDB
	if type(db) ~= "table" then return nil end
	local holder
	if ClassBar(id) then
		if not ns.ClassDB then return nil end
		local cdb = ns.ClassDB()
		if create and type(cdb.looks) ~= "table" then cdb.looks = {} end
		holder = cdb.looks
	else
		if create and type(db.barLooks) ~= "table" then db.barLooks = {} end
		holder = db.barLooks
	end
	if type(holder) ~= "table" then return nil end
	if create and type(holder[id]) ~= "table" then holder[id] = {} end
	local look = holder[id]
	return type(look) == "table" and look or nil, holder
end

-- The class file's look of a class bar, or nil.
local function ClassLook(id)
	if not (ClassBar(id) and ns.ClassDefault) then return nil end
	local d = ns.ClassDefault("barLooks")
	if type(d) ~= "table" then return nil end
	local spell = TimerSpell(id)
	local look = d[id]
	if spell then look = type(d.timer) == "table" and d.timer[spell] or nil end
	return type(look) == "table" and look or nil
end

-- One field of a bar's look, from the first place that has it (the header).
function ns.BarLookField(id, field)
	if not FIELD[field] then return nil end
	local saved = Saved(id)
	if saved and Valid(field, saved[field]) then return saved[field] end
	local c = ClassLook(id)
	if c and Valid(field, c[field]) then return c[field] end
	return LOOK_DEFAULT[field]
end

-- The field's value with nothing saved for this bar: the class file's, else
-- today's look. A fixed value, so a settings row can take it as its
-- default (a function default taints).
function ns.BarLookDefault(id, field)
	if not FIELD[field] then return nil end
	local c = ClassLook(id)
	if c and Valid(field, c[field]) then return c[field] end
	return LOOK_DEFAULT[field]
end

-- The whole look, resolved: a new table each time. base: nil when the bar
-- has no color of its own.
function ns.BarLook(id)
	local c = ns.BarLookField(id, "color")
	local b = ns.BarLookField(id, "base")
	return {
		texture  = ns.BarLookField(id, "texture"),
		gradient = ns.BarLookField(id, "gradient"),
		color    = { c[1], c[2], c[3] },
		base     = b and { b[1], b[2], b[3] } or nil,
	}
end

-- Save one field of one bar's look, and repaint. nil clears the field (the
-- bar takes it from the next place again). false for a bad id, field or
-- value: nothing is saved.
-- A texture a menu offers: Same as Bar texture, a file, or a Bar texture
-- key (a built-in, or a LibSharedMedia texture loaded now). A saved key
-- whose addon is gone later still reads; its path falls back (Bars.lua).
local function Offered(t)
	if t == "same" or IsFile(t) then return true end
	if not ns.BarTextureList then return true end
	for _, e in ipairs(ns.BarTextureList()) do
		if e.key == t then return true end
	end
	return false
end

-- copied: the value is another bar's look, already saved, so a texture
-- key whose addon is not loaded now is copied too.
local function Put(id, field, value, copied)
	if not (ns.IsBarLookId(id) and FIELD[field]) then return false end
	if value ~= nil and not Valid(field, value) then return false end
	if field == "base" and not TimerSpell(id) then return false end
	if field == "texture" and value ~= nil and not copied and not Offered(value) then return false end
	if (field == "color" or field == "base") and value ~= nil then value = { value[1], value[2], value[3] } end
	local saved, holder = Saved(id, value ~= nil)
	if saved then
		saved[field] = value
		if next(saved) == nil and holder then holder[id] = nil end
	end
	if ns.RepaintLooks then ns.RepaintLooks() end
	return true
end

function ns.SetBarLook(id, field, value) return Put(id, field, value) end

-- The raw saved value of one field (nil when nothing is saved there), so a
-- Cancel can put it back as it was.
function ns.SavedBarLookField(id, field)
	if not (ns.IsBarLookId(id) and FIELD[field]) then return nil end
	local saved = Saved(id, false)
	local v = saved and saved[field]
	if type(v) == "table" then v = { v[1], v[2], v[3] } end
	return v
end

-- Give every timer bar of your class the look of one bar (the texture
-- button's Use on every timer bar): its texture, gradient, gradient color
-- and own color (TICK-0258; none: each follows the Timer bar color),
-- saved on each spell. Repaints once.
function ns.SetLookOnAllTimers(fromId)
	if not ns.IsBarLookId(fromId) then return false end
	local look = ns.BarLook(fromId)
	local repaint = ns.RepaintLooks
	ns.RepaintLooks = nil
	local spells = ns.CooldownSpells and ns.CooldownSpells() or {}
	for _, spell in ipairs(spells) do
		local id = ns.TimerLookId(spell)
		Put(id, "texture", look.texture, true)
		Put(id, "gradient", look.gradient)
		Put(id, "color", look.color)
		Put(id, "base", look.base)
	end
	ns.RepaintLooks = repaint
	if repaint then repaint() end
	return true
end

-- The old Timer bar texture row (TICK-0158), moved once at load since
-- TICK-0225 took the row away (design: Saved data): a pick other than
-- "hud" becomes the texture of every spell whose timer bar is on, in every
-- class saved, unless the spell has a texture of its own. Then the key
-- goes. Nothing else reads it (TICK-0231).
function ns.MoveTimerBarTexture(db)
	if type(db) ~= "table" then return end
	local old = db.timerBarTexture
	db.timerBarTexture = nil
	if not Valid("texture", old) or old == "hud" or type(db.classes) ~= "table" then return end
	for _, cdb in pairs(db.classes) do
		if type(cdb) == "table" and type(cdb.timerBars) == "table" then
			for spell, on in pairs(cdb.timerBars) do
				if on == true then
					if type(cdb.looks) ~= "table" then cdb.looks = {} end
					local id = ns.TimerLookId(spell)
					if type(cdb.looks[id]) ~= "table" then cdb.looks[id] = {} end
					if cdb.looks[id].texture == nil then cdb.looks[id].texture = old end
				end
			end
		end
	end
end

-- One string for a bar's whole look: a frame is painted again only when
-- it changes (TimerBars.lua).
function ns.BarLookKey(id)
	local c = ns.BarLookField(id, "color")
	local b = ns.BarLookField(id, "base") or {}
	return table.concat({ tostring(ns.BarLookPath(id)), ns.BarLookField(id, "gradient"),
		tostring(c[1]), tostring(c[2]), tostring(c[3]),
		tostring(b[1]), tostring(b[2]), tostring(b[3]) }, "|")
end

--------------------------------------------------------------------------------
-- Painting
--------------------------------------------------------------------------------

-- The texture path of a bar's look. nil id: Bar texture.
function ns.BarLookPath(id)
	local t = id and ns.BarLookField(id, "texture") or "same"
	if t == "same" then return ns.BarTexturePath() end
	if IsFile(t) then return t end
	return ns.TexturePathFor(t)
end

-- Set the fill texture. A path the game refuses (an error, or false for
-- success) gives Bar texture: no Lua error, no chat line. The bar's pick
-- stays, so a file that comes back (after a restart) is used again.
local function SetFill(bar, path)
	local ok, done = pcall(bar.SetStatusBarTexture, bar, path)
	if ok and done ~= false then return end
	local fallback = ns.BarTexturePath()
	if fallback ~= path then pcall(bar.SetStatusBarTexture, bar, fallback) end
end

local function EndColor(gradient, r, g, b, pick)
	if gradient == "darker" then return r * DARKER, g * DARKER, b * DARKER end
	if gradient == "lighter" then
		return r + (1 - r) * LIGHTER, g + (1 - g) * LIGHTER, b + (1 - b) * LIGHTER
	end
	return pick[1], pick[2], pick[3]
end
ns.LookEndColor = EndColor

-- The color a bar's strip shows on its texture button and in its menu: the
-- bar's color, or for a bar whose color changes its first one (Mana,
-- Hostile, Interruptible).
local STRIP_COLOR = {
	health = "health", power = "mana", druidmana = "mana", resource = "resource",
	playercast = "playercast", xp = "xp", targethealth = "hostile",
	targetpower = "mana", targetcast = "interrupt", tot = "hostile", pet = "health",
}
-- The color a bar has now, from HUDini's own tables (safe in a fight): the
-- power bar the color of your power, so a Warrior's strips are red.
function ns.BarLookColor(id)
	if id == "power" and ns.PowerColor then return ns.PowerColor() end
	if TimerSpell(id) then return ns.TimerBarColor(id) end
	local key = STRIP_COLOR[id] or "health"
	return ns.BarColor and ns.BarColor(key) or { 1, 1, 1 }
end

-- A timer bar's color (TICK-0258): its own, else the Timer bar color of
-- the Colors page. A new table, with the Timer bar color's alpha.
function ns.TimerBarColor(id)
	local timer = ns.BarColor and ns.BarColor("timer") or { 1, 1, 1 }
	local own = ns.BarLookField(id, "base")
	if not own then return timer end
	return { own[1], own[2], own[3], timer[4] }
end

-- The Colors page keys a bar takes its colors from (TICK-0242): its
-- texture button shows one color row for each. Mana in forms wears Mana
-- (Bars.lua CreateBar). Target power wears the color of the target's
-- power, so all three; a power with no key keeps the game's color. Target
-- of target and pet have no bar yet, so no color row.
local COLOR_KEYS_OF = {
	health = { "health", "trail" }, druidmana = { "mana" }, resource = { "resource" },
	playercast = { "playercast" }, xp = { "xp", "rested" },
	targethealth = { "hostile", "neutral", "friendly", "tapped" },
	targetpower = { "mana", "rage", "energy" }, targetcast = { "interrupt", "shielded" },
}
-- A new list each time. Your power bar: the powers of your class.
function ns.BarColorKeys(id)
	if TimerSpell(id) then return { "timer" } end
	if id == "power" then return ns.ClassPowerKeys and ns.ClassPowerKeys() or {} end
	local out = {}
	for i, key in ipairs(COLOR_KEYS_OF[id] or {}) do out[i] = key end
	return out
end

-- Give a bar its look id. flat: the texture only, never a gradient (the
-- heal parts of a health bar).
function ns.LookBar(bar, id, flat)
	bar.lookId = id
	bar.lookFlat = flat and true or nil
	bar.lookAsked = nil
	return bar
end

-- Paint a bar in its color: its look's texture, then the color, or a
-- gradient from the color. color is { r, g, b [, a] } from HUDini's own
-- tables. The bar keeps it as shownColor, so a new texture can put it back.
function ns.PaintBar(bar, color)
	if not (bar and color) then return end
	bar.shownColor = color
	local id = bar.lookId
	local path = ns.BarLookPath(id)
	if bar.lookAsked ~= path then
		SetFill(bar, path)
		bar.lookAsked = path
	end
	local r, g, b, a = color[1], color[2], color[3], color[4]
	bar:SetStatusBarColor(r, g, b, a)
	local gradient = (id and not bar.lookFlat) and ns.BarLookField(id, "gradient") or "off"
	if gradient == "off" then return end
	local tex = bar.GetStatusBarTexture and bar:GetStatusBarTexture()
	if not (tex and tex.SetGradient and CreateColor) then return end
	local r2, g2, b2 = EndColor(gradient, r, g, b, ns.BarLookField(id, "color"))
	local from, to = CreateColor(r, g, b, a or 1), CreateColor(r2, g2, b2, a or 1)
	-- A bar that fills from the right starts its fade there.
	if bar.GetReverseFill and bar:GetReverseFill() then from, to = to, from end
	tex:SetGradient("HORIZONTAL", from, to)
end

-- Set a bar's texture only (a bar with no color of its own, TestMode.lua).
function ns.PaintTexture(bar)
	local path = ns.BarLookPath(bar.lookId)
	SetFill(bar, path)
	bar.lookAsked = path
end

-- Paint a bar again after a texture change (SetStatusBarTexture resets
-- its color), in the color it shows.
function ns.RepaintBar(bar)
	bar.lookAsked = nil
	if bar.shownColor then ns.PaintBar(bar, bar.shownColor) end
end

-- A new look: every bar takes it. Bars.lua's ApplyTexture repaints its
-- bars (and the resource bar's fight fill, out of a fight); the timer bars
-- repaint on their own.
function ns.RepaintLooks()
	if ns.ApplyTexture then ns.ApplyTexture() end
	if ns.RefreshTimerBars then ns.RefreshTimerBars() end
	if ns.RepaintLookButtons then ns.RepaintLookButtons() end
end

--------------------------------------------------------------------------------
-- Class bars (for TICK-0226)
--------------------------------------------------------------------------------

-- The resource bar has a look while it can show for you: what it shows
-- now (ns.ClassResource, TICK-0199: a buff on you or a spell you know), or
-- a power it shows only in a form (a Druid's combo points in Cat Form), so
-- the row does not come and go with the form.
local function HasResourceBar()
	if ns.ClassResource and ns.ClassResource() then return true end
	local r = ns.ClassValue and ns.ClassValue("resource")
	return type(r) == "table" and r.onlyWith ~= nil
end

-- The ids of the class you play that can have a look: the resource bar, if
-- it can show for you, then each cooldown spell's timer bar.
function ns.ClassBarLookIds()
	local out = {}
	if HasResourceBar() then out[#out + 1] = "resource" end
	local spells = ns.CooldownSpells and ns.CooldownSpells() or {}
	for _, spell in ipairs(spells) do out[#out + 1] = ns.TimerLookId(spell) end
	return out
end

-- Every id a class file gives a look, as bar ids (a test can check each).
function ns.ClassFileLookIds(profile)
	local out = {}
	local d = type(profile) == "table" and profile.barLooks or nil
	if type(d) ~= "table" then return out end
	for key, look in pairs(d) do
		if key == "timer" and type(look) == "table" then
			for spell in pairs(look) do out[#out + 1] = ns.TimerLookId(spell) end
		else
			out[#out + 1] = key
		end
	end
	table.sort(out)
	return out
end

--------------------------------------------------------------------------------
-- Custom textures
--------------------------------------------------------------------------------

-- The list, with anything that is not a path dropped: a hand-edited or
-- broken saved file must not give the readers a Lua error.
function ns.CustomTextures()
	local db = HUDiniDB
	if type(db) ~= "table" then return {} end
	local list = db.customTextures
	if type(list) ~= "table" then
		db.customTextures = {}
		return db.customTextures
	end
	local clean, bad = {}, false
	for i, p in pairs(list) do
		if type(i) == "number" and type(p) == "string" and p ~= "" then
			clean[#clean + 1] = { i, p }
		else
			bad = true
		end
	end
	if bad or #clean ~= #list then
		table.sort(clean, function(a, b) return a[1] < b[1] end)
		for i = #clean, 1, -1 do clean[i] = clean[i][2] end
		db.customTextures = clean
	end
	return db.customTextures
end

-- A typed path made plain: no spaces at the ends, \ for /, one \ at a
-- time, and nothing before the Interface folder.
function ns.CleanTexturePath(s)
	if type(s) ~= "string" then return "" end
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub("/", "\\"):gsub("\\+", "\\")
	local at = s:lower():find("\\interface\\", 1, true)
	if at then s = s:sub(at + 1) end
	return s
end

-- The file's name: the last part of its path, with no ending.
function ns.TextureFileName(path)
	local name = tostring(path):match("([^\\]+)$") or tostring(path)
	return (name:gsub("%.[Tt][Gg][Aa]$", ""):gsub("%.[Bb][Ll][Pp]$", "")) -- locale: skip file endings
end

local function Find(list, path)
	local low = path:lower()
	for i, p in ipairs(list) do
		if type(p) == "string" and p:lower() == low then return i end
	end
end

-- Add a file to the list. probe: a texture to try the path on (the
-- window's preview). true, the clean path; or false and the key of the
-- line to show.
function ns.AddCustomTexture(typed, probe)
	local path = ns.CleanTexturePath(typed)
	if path == "" then return false, "look.custom.empty" end
	if not IsFile(path) then return false, "look.custom.notInterface" end
	local list = ns.CustomTextures()
	if Find(list, path) then return true, list[Find(list, path)] end
	if #list >= ns.MAX_CUSTOM_TEXTURES then return false, "look.custom.full" end
	if probe and probe.SetTexture then
		local ok, done = pcall(probe.SetTexture, probe, path)
		if not ok or done == false then return false, "look.custom.noFile" end
	end
	list[#list + 1] = path
	return true, path
end

-- Remove a file from the list. Every bar that used it goes back to Same as
-- Bar texture.
function ns.RemoveCustomTexture(path)
	local list = ns.CustomTextures()
	local i = type(path) == "string" and Find(list, path)
	if not i then return false end
	local low = list[i]:lower()
	table.remove(list, i)
	local function Clear(holder)
		if type(holder) ~= "table" then return end
		for _, look in pairs(holder) do
			if type(look) == "table" and type(look.texture) == "string" and look.texture:lower() == low then
				look.texture = "same"
			end
		end
	end
	Clear(HUDiniDB.barLooks)
	if type(HUDiniDB.classes) == "table" then
		for _, cdb in pairs(HUDiniDB.classes) do
			if type(cdb) == "table" then Clear(cdb.looks) end
		end
	end
	if ns.RepaintLooks then ns.RepaintLooks() end
	return true
end
