"""Check 6 of the gate: every player text is in Locales/enUS.lua (TICK-0025).

check.py loads this file and calls run(ROOT, glossary, lua51). glossary is
the loaded tools/glossary_check.py, for its Lua reader (lua_texts). It
returns the failure lines and a count of the keys the code asks for.

Two checks:

1. No player text in a string literal of an addon .lua file outside
   Locales/ and Classes/. Classes/<Class>.lua hold only the game's spell
   and buff names, which the code matches by name, so they stay. A literal
   is player text when, after the codes (|T..|t, |c, |r, paths), the
   format items (%s, %-26s) and the code names are taken out, it still
   holds two or more words, one word that starts with a capital ("Icons"),
   or any word in a joined part (" pips"). Code names are a name with a
   "." ":" or "_" in it ("why.combat", "C_Timer.After"), a name with two
   capitals ("MainMenuBar", "HUDini") and an all-caps name ("CENTER").
   A literal that is the first thing a call that shows text gets (Say,
   say, out, Print, Detail, AddMessage, AddLine, SetText,
   SetFormattedText; also as ("..."):format) is player text if any word
   is left after the codes, the format items and the code names (with a
   ".", ":" or "_", with two capitals, or after a "/") are taken out. An
   all-caps word and one lowercase word count here: ns.Say("ERROR"),
   ns.Say("hello").
   Limit: a literal kept in a variable first and shown later is judged by
   its shape only, so one lowercase word ("hello") or a code name with
   one word beside it ("Not_ready yet") gets through there. The same goes
   for a single-quoted or long string ('...', [[...]]) in a call that
   shows text: only a double-quoted first literal is read as shown text.
   Not player text:
   - A whole literal in CODE: a value the game or the code reads ("Alpha"
     for an animation, "Magic" for a dispel type).
   - A joined part that is a key piece ("flair.", "rep:"), by the
     glossary check's rule (is_key_piece).
   - A line that ends in the comment "-- locale: skip <why>", and the lines
     between "-- locale: skip <why>" on a line of its own and the next
     "-- locale: end". A debug report's lines (ns.Detail) stay in English
     for bug reports, the game's own names stay as the game spells them.
2. Every key the code asks for with Text("key") or ns.Text("key") has a
   level 0 text, and every key at level 1 or 2 has a level 0 text. A key
   built at run time ("flair." .. level, "opt." .. key) is not checked
   here; the harness tests look for a raw key in what the code shows.
"""
import re

SKIP = {"tools", "docs", "tickets", "decisions", "framework"}  # and every folder that starts with "."
LOCALE = "Locales/enUS.lua"

# (whole literal, why): literals the game or the code reads.
CODE = [
    ("Alpha", "an animation type (CreateAnimation)"),
    ("Scale", "an animation type (CreateAnimation)"),
    ("Magic", "a dispel type from the game"),
    ("Curse", "a dispel type from the game"),
    ("Poison", "a dispel type from the game"),
    ("Disease", "a dispel type from the game"),
    ("Gold", "the coin icon name in the texture path"),
    ("Silver", "the coin icon name in the texture path"),
    ("Copper", "the coin icon name in the texture path"),
    ("Version", "the .toc field GetAddOnMetadata reads"),
]

FMT = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[a-zA-Z%]")
IDENT = re.compile(r"[A-Za-z_]\w*(?:[.:_]\w+)+|\b\w*[A-Z]\w*[A-Z]\w*\b|\b[A-Z0-9_]{2,}\b")
WORD = re.compile(r"[A-Za-z]+")
SKIP_LINE = re.compile(r"--\s*locale:\s*skip\b")
SKIP_START = re.compile(r"^\s*--\s*locale:\s*skip\b")
SKIP_END = re.compile(r"^\s*--\s*locale:\s*end\b")
KEY_CALL = re.compile(r"(?<![\w.:])(?:ns\.)?Text\(\s*\"([^\"]+)\"\s*[,)]")
SHOW_IDENT = re.compile(r"/\w+|[A-Za-z_]\w*(?:[.:_]\w+)+|\b(?=\w*[a-z])\w*[A-Z]\w*[A-Z]\w*\b")
SHOW_CALL = re.compile(
    r"(?<![\w])(?:Say|say|out|Print|Detail|AddMessage|AddLine|SetText|SetFormattedText)"
    r"\(\s*\(?\s*\"((?:[^\"\\]|\\.)*)\"")


def words(text, codes):
    t = codes.sub(" ", text)
    t = FMT.sub(" ", t)
    t = IDENT.sub(" ", t)
    return [w for w in WORD.findall(t) if len(w) >= 2 or w in ("a", "A", "I")]


def is_player_text(text, kind, codes):
    found = words(text, codes)
    if len(found) >= 2:
        return True
    if len(found) == 1:
        return bool(re.fullmatch(r"[A-Z][a-z]+", found[0])) or kind == "part"
    return False


def skipped_lines(rel, source):
    """The line numbers the skip comments cover, and the failures for an
    unclosed or stray marker."""
    lines, fails, start = set(), [], None
    for n, line in enumerate(source.splitlines(), 1):
        if SKIP_START.match(line):
            if start is not None:
                fails.append("locale: %s:%d: \"locale: skip\" inside the skip at line %d" % (rel, n, start))
            start = n
        elif SKIP_END.match(line):
            if start is None:
                fails.append("locale: %s:%d: \"locale: end\" with no skip before it" % (rel, n))
            start = None
        elif SKIP_LINE.search(line):
            lines.add(n)
        if start is not None:
            lines.add(n)
    if start is not None:
        fails.append("locale: %s:%d: \"locale: skip\" has no \"locale: end\"" % (rel, start))
    return lines, fails


def scan(rel, source, glossary):
    lines, fails = skipped_lines(rel, source)
    code = {c for c, _ in CODE}
    hit = set()
    for line, text, kind in glossary.lua_texts(source):
        if kind == "joined" or line in lines:
            continue
        if kind == "lone" and glossary.NAME.match(text):
            continue
        if text in code:
            continue
        if glossary.is_key_piece(text, kind):
            continue  # a piece of a key: "flair." .. level, "rep:" .. name
        if is_player_text(text, kind, glossary.CODES):
            hit.add(line)
            fails.append('locale: %s:%d: player text outside %s: "%s"' % (rel, line, LOCALE, text.strip()))
    for n, src in enumerate(source.splitlines(), 1):
        if n in lines or n in hit:
            continue
        for m in SHOW_CALL.finditer(src):
            t = SHOW_IDENT.sub(" ", FMT.sub(" ", glossary.CODES.sub(" ", m.group(1))))
            if WORD.search(t) and m.group(1) not in code:
                fails.append('locale: %s:%d: shown text outside %s: "%s"' % (rel, n, LOCALE, m.group(1).strip()))
                break
    return fails


def self_test(glossary):
    cases = [  # (one Lua line, a hit on it?)
        ('ns.Say("Test mode is off.")', True),
        ('ns.Say(Text("test.off"))', False),
        ('f:SetPoint("CENTER", UIParent, "CENTER")', False),
        ('local a = CreateFrame("Frame", "HUDiniAnchor", UIParent)', False),
        ('local b = ag:CreateAnimation("Alpha")', False),
        ('page = "Icons"', True),
        ('s = n .. " pips"', True),
        ('s = "  %2d. r%d c%-2d"', False),
        ('t = "Interface\\\\Buttons\\\\WHITE8X8"', False),
        ('out("  Resource: " .. x) -- locale: skip debug', False),
        ('-- locale: skip debug report', False),
        ('out("  Class file " .. x)', False),
        ('-- locale: end', False),
        ('out("  Class file " .. x)', True),
        ('k = "flair." .. level', False),
        ('key = "rep:" .. name', False),
        ('e = "item:(%d+)"', False),
        ('say("Stopped tracking " .. (x or "a buff"))', True),
        ('ns.Say("ERROR")', True),
        ('ns.Say("hello")', True),
        ('out(("cannot.start now %d"):format(n))', True),
        ('f.label:SetText("Not_ready yet")', True),
        ('f.label:SetText("")', False),
        ('ns.Say(Text("x.y"), "CENTER")', False),
        ('Detail("  C_ActionBar.IsUsableAction " .. x)', False),
        ('out(("|cffffd200%s:|r %s / %.1f%%"):format(a, b, c))', False),
        ('b:SetText("HUDini")', False),
    ]
    lua = "\n".join(c for c, _ in cases) + "\n"
    want = {k + 1 for k, (_, hit) in enumerate(cases) if hit}
    got = {int(f.split(":")[2]) for f in scan("X.lua", lua, glossary)}
    fails = []
    if got != want:
        fails.append("locale: the self-test found lines %s, not %s" % (sorted(got), sorted(want)))
    _, bad = skipped_lines("Y.lua", "-- locale: skip x\nlocal a = 1\n")
    if len(bad) != 1:
        fails.append("locale: the self-test missed a skip with no end")
    return fails


def locale_keys(root, lua51):
    """{level: set of keys} from Locales/enUS.lua, run as the game runs it."""
    state = lua51.LuaRuntime()
    load = state.eval(
        "function(src, name)"
        " local f, e = loadstring(src, name) if not f then return nil, e end"
        " local ns = {} local ok, err = pcall(f, 'HUDini', ns)"
        " if not ok then return nil, tostring(err) end"
        " local out = {}"
        " for level, t in pairs(ns.TEXT or {}) do"
        "  local keys = {} for k in pairs(t) do keys[#keys + 1] = k end"
        "  out[level] = table.concat(keys, '\\n')"
        " end"
        " return out, '' end")
    out, err = load((root / LOCALE).read_text(encoding="utf-8"), "@" + LOCALE)
    if out is None:
        return None, str(err)
    return {int(k): set(str(v).split("\n")) for k, v in out.items()}, None


def run(root, glossary, lua51):
    """Failure lines for the repo at root, and the number of keys asked for."""
    failures = self_test(glossary)
    keys, err = locale_keys(root, lua51)
    if keys is None:
        return failures + ["locale: %s did not load: %s" % (LOCALE, err)], 0
    level0 = keys.get(0, set())
    for level in (1, 2):
        for k in sorted(keys.get(level, set()) - level0):
            failures.append("locale: %s: key %s has a level %d text but no level 0 text" % (LOCALE, k, level))
    asked = set()
    for p in sorted(root.rglob("*.lua")):
        parts = p.relative_to(root).parts
        if SKIP.intersection(parts) or any(x.startswith(".") for x in parts):
            continue
        rel = p.relative_to(root).as_posix()
        source = p.read_text(encoding="utf-8")
        for n, line in enumerate(source.splitlines(), 1):
            for m in KEY_CALL.finditer(line.split("--")[0]):
                asked.add(m.group(1))
                if m.group(1) not in level0:
                    failures.append("locale: %s:%d: key %s has no level 0 text in %s" % (rel, n, m.group(1), LOCALE))
        if rel == LOCALE or parts[0] == "Classes":
            continue
        failures += scan(rel, source, glossary)
    return failures, len(asked)
