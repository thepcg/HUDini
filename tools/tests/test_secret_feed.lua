-- Feed.lua when the game hides an answer (TICK-0112). Each test first runs
-- the value that WOULD change the feed, plain, and checks that it does.
-- Then it flags that same value secret and checks that the feed does what
-- it does for no answer, and throws nothing. So a missing Plain() fails the
-- test (the method of TICK-0110).

-- A logged-in world with the feed on. w.secret: the values issecretvalue
-- calls secret. w.textHeight: what every font string says its text needs.
local function World()
	local w = H.world()
	w.secret = {}
	w.env.issecretvalue = function(v) return v ~= nil and w.secret[v] == true end
	local Frame = w.Frame
	function w:Frame(...)
		local f = Frame(self, ...)
		f.GetStringHeight = function() return w.textHeight or 12 end
		return f
	end
	local ns = w:loadAddon()
	w.time = w.time + 10                       -- past the quiet time after login
	return w, ns.Feed
end

--------------------------------------------------------------------------------
-- Line height
--------------------------------------------------------------------------------

H.test("a secret text height gives the line one line's height", function()
	local w, F = World()
	w.textHeight = 41
	H.eq(F.Line({ kind = "test", text = "two lines" }).h, 41, "plain: as tall as its text")
	w.secret[41] = true
	H.eq(F.Line({ kind = "test", text = "two lines again" }).h, 18, "secret: one line")
end)

--------------------------------------------------------------------------------
-- Open windows
--------------------------------------------------------------------------------

H.test("a secret window type does not open a bank", function()
	local w, F = World()
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
	H.eq(F.AtBank(), true, "plain: at the bank")
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 8)
	w.secret[8] = true
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 8)
	H.eq(F.AtBank(), false, "secret: not known to be open")
end)

H.test("a secret window type does not shut a bank", function()
	local w, F = World()
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
	H.eq(F.AtBank(), false, "plain: shut")
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 10)
	w.secret[10] = true
	w:fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 10)
	H.eq(F.AtBank(), true, "secret: still open")
end)
