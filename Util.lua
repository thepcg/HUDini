--[[--------------------------------------------------------------------------
	HUDini: shared helpers (TICK-0012)

	Small helpers that more than one file needs. This file loads first (see
	HUDini.toc), so every other file can take them as locals at load:

		local Plain, Say = ns.Plain, ns.Say

	Put a helper here only when a second file needs it. One definition each.
----------------------------------------------------------------------------]]

local _, ns = ...

--------------------------------------------------------------------------------
-- Secret value guard
--
-- 12.0 wraps combat data in opaque "secret values". Comparing one throws a
-- Lua error. Plain() hands back nil instead of a secret, so every test on
-- its answer can fail safe.
--------------------------------------------------------------------------------

local issecret = _G.issecretvalue

function ns.Plain(v)
	if issecret and v ~= nil and issecret(v) then return nil end
	return v
end

-- True only when the value exists and the game is hiding it.
function ns.IsSecret(v)
	return (issecret and v ~= nil and issecret(v)) and true or false
end

local Plain = ns.Plain

--------------------------------------------------------------------------------
-- Combat, chat, numbers
--------------------------------------------------------------------------------

-- In a fight: combat lockdown, or the player is flagged in combat. A secret
-- combat flag counts as not in combat.
function ns.InCombat()
	if InCombatLockdown() then return true end
	return Plain(UnitAffectingCombat("player")) and true or false
end

-- The flair level (D-011, TICK-0055): 0 Light (the default), 1 Modest,
-- 2 Full. A saved value that is not one of them counts as 0.
function ns.FlairLevel()
	local v = HUDiniDB and HUDiniDB.flair
	if v == 1 or v == 2 then return v end
	return 0
end

-- The text for key at the flair level now (Locales/enUS.lua), with the
-- values joined in. A level with no text for key uses the level below it,
-- and a level with no texts at all (not 0-2) uses level 0.
-- A key with no text at all comes back as the key, so a gap shows in chat
-- and never throws.
function ns.Text(key, ...)
	local text = ns.TEXT or {}
	local top = ns.FlairLevel()
	if not text[top] then top = 0 end
	for level = top, 0, -1 do
		local s = text[level] and text[level][key]
		if s then
			if select("#", ...) > 0 then return s:format(...) end
			return s
		end
	end
	return key
end

-- One chat line from HUDini: the blue prefix, then the line. Every chat
-- line HUDini prints starts here.
function ns.Say(msg)
	print("|cff33ccffHUDini|r: " .. msg)
end

-- One line of a debug report, under the title ns.Say printed. It prints
-- the line as it is: the caller writes the indent, so a report can go to
-- chat or into a saved file with the same lines. The only other print.
function ns.Detail(line)
	print(line)
end

-- A whole number with the client's thousands separators: 12,345.
function ns.Number(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

--------------------------------------------------------------------------------
-- Sessions: what this sitting brought in, kept per character. A /reload
-- writes lastSeen on the way out (PLAYER_LOGOUT) and comes straight back, so
-- it carries on the same session. Switching the part off writes lastSeen
-- too (its OnDisable), and on again loads the session the same way.
--------------------------------------------------------------------------------

ns.RELOAD_GRACE = 300   -- seconds away that still count as the same session

-- The character's GUID, or name-realm when the GUID is hidden.
function ns.CharacterKey()
	local guid = UnitGUID and Plain(UnitGUID("player"))
	return guid or ((UnitName("player") or "?") .. "-" .. (GetRealmName() or "?"))
end

-- This character's session in HUDiniDB[field]. A session last seen more
-- than RELOAD_GRACE ago, or none, is replaced by New(). A session kept
-- skips the time away: its start moves on by it, so a rate counts only the
-- time the part was on.
function ns.LoadSession(field, New)
	HUDiniDB[field] = HUDiniDB[field] or {}
	local key = ns.CharacterKey()
	local s = HUDiniDB[field][key]
	local away = s and s.lastSeen and time() - s.lastSeen
	if not (away and away <= ns.RELOAD_GRACE) then
		s = New()
		HUDiniDB[field][key] = s
	elseif s.start and away > 0 then
		s.start = s.start + away
	end
	s.lastSeen = nil
	return s
end
