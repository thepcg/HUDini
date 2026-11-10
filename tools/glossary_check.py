"""Check 5 of the gate: no "Do not use" word of the glossary in player text.

check.py loads this file and calls run(ROOT). It returns a list of failure
lines, "glossary: <file>:<line>: <word> in "<text>"". The rules:

- Words come from the "Do not use" column of the first table in
  framework/glossary.md, one word or phrase per comma. A note in brackets
  that starts with "for" ("bar (for icons)", "your buff (for a tracked
  buff)") and the form "X alone" ban a word in one meaning only. A script
  cannot see the meaning, so those words are left to review, and the gate
  does not scan them. "(for both)" and "(in player text)" ban the word in
  all player text, so it is scanned.
- A word matches as a whole word, in any case, also with an "s" or "es"
  ("default frames"). "keep up" also matches "keep  up".
- Lua: every string literal in every addon .lua file (the folders check.py
  skips are skipped here too), but no comment. Each literal is read on its
  own, wherever it stands (in brackets, in a :format call, in a join). A
  run of literals joined with ".." is also read as one text, with "#" for
  each part that is not a lone literal, so "Read Action Bar " .. i is read
  as "Read Action Bar #", and "keep " .. "up" as "keep up". Not scanned: a
  lone literal (not joined) that is exactly one lowercase name ("bar",
  "smart", "why.reason": a key or a value, not text), a key piece in a
  join (is_key_piece: ".intro" in x .. ".intro", "flair." .. level), the
  name argument of CreateFrame, texture and file paths, and |T...|t,
  |c.../|r codes.
- The .toc: the text of its ## Title and ## Notes lines (the AddOns list).
- Markdown: the player docs in DOCS, with no code block and no `code`.
- ALLOW: phrases that are fine although they hold a banned word, each with
  where it may stand and why. An allowed phrase is taken out of the text
  before the scan, and it matches only in the same case.
- EXACT: like ALLOW, but only for a Lua literal that is the whole phrase
  and nothing more ("Auto" as a choice name, not "Auto (class default)").

To ban a new word, add it to the glossary. To allow a phrase, add it to
ALLOW or EXACT with its reason.
"""
import fnmatch
import re

DOCS = ["README.md", "CHANGELOG.md", "docs/store-page.md"]
SKIP = {"tools", "docs", "tickets", "decisions", "framework"}  # and every folder that starts with "."

# (phrase, file pattern, why). The pattern is fnmatch on the path from the
# repo root, with "/" between folders.
ALLOW = [
    # The game's own frames and buttons: the glossary bans "frame" for the
    # HUD, and "buttons" for the icon grid, not for the game's UI.
    ("Game frames", "*", "the options page for the game's own frames (D-016)"),
    ("game's own frames", "*", "the glossary's word for the game's frames (D-016)"),
    ("player frame", "*", "Blizzard's player frame"),
    ("target frame", "*", "Blizzard's target frame"),
    ("pet frame", "*", "Blizzard's pet frame"),
    ("Target frame", "*", "a Blizzard frames option label"),
    ("Hide player frame", "*", "a Blizzard frames option label"),
    ("Hide target frame", "*", "a Blizzard frames option label"),
    ("Menu buttons", "*", "Blizzard's menu buttons, a mouseover option label"),
    ("menu buttons", "*", "Blizzard's menu buttons"),
    ("clock and buttons", "*", "the buttons on Blizzard's minimap"),
    ("Frames HUDini replaces", "Locales/enUS.lua", "the Blizzard frames page header"),
    ("frames HUDini replaces", "README.md", "the Blizzard frames page"),
    ("unit frames", "README.md", "other addons' frames"),
    ("UI-HUD-UnitFrame", "Bars.lua", "the game's own atlas names, for its PvP marks (TICK-0097)"),
    ("from a loot window", "CHANGELOG.md", "the game's own loot window, not the feed"),
    # "display" and "credits" in their own sense.
    ("heads-up display", "*", "what HUD stands for (README, the .toc Notes)"),
    ("may display", "README.md", "the verb"),
    ("## Credits", "README.md", "the README's credits section, not the About window"),
    # "auto" is banned for "class default". These are another meaning: a
    # choice that picks by itself (TICK-0027 Evidence).
    ("Auto pick action bars", "*", "the option that reads only the action bars on screen"),
    ("Auto takes the side", "Locales/enUS.lua", "the feed's Line side choice"),
    # "more" and "plain" as plain words, not the Advanced or flair names.
    ("or more", "*", "a buff of 5 minutes or more"),
    ("and more", "*", "a plain word"),
    ("shows more", "*", "a plain word"),
    ("shows you more", "*", "a plain word"),
    ("A little more", "*", "a plain word"),
    ("More alerts", "*", "a plain word"),
    ("plain view", "*", "a plain word"),
    ("plain sight", "*", "a plain word"),
    # "Your buff pairs": the word is "buff pair", not "your buff".
    ("Your buff pairs", "*", "the buff pairs, not a tracked buff"),
    # D-017: Khadgar's page 1 joke names the word the glossary bans for setup.
    ("Most addons come with a setup wizard", "Locales/enUS.lua", "Khadgar's page 1 joke (D-017)"),
]

# (whole literal, file pattern, why): a Lua literal that is exactly this.
EXACT = [
    # Spell names from the game. Class files key on them.
    ("Kick", "Classes/Rogue.lua", "the Rogue spell"),
    ("Cleanse", "Classes/Paladin.lua", "the Paladin spell"),
    ("Mana Shield", "Classes/Mage.lua", "the Mage spell"),
    ("Shield Bash", "Classes/Warrior.lua", "the Warrior spell"),
    ("Auto", "Locales/enUS.lua", "the feed's Line side choice, not class default"),
]

# Comment, long string, short string, "..", a name, or one other character.
LUA_TOKEN = re.compile(
    r"--\[(=*)\[.*?\]\1\]"
    r"|--[^\n]*"
    r"|\[(=*)\[(.*?)\]\2\]"
    r"|\"((?:[^\"\\\n]|\\.)*)\""
    r"|'((?:[^'\\\n]|\\.)*)'"
    r"|\.\.\.?"
    r"|[A-Za-z_][A-Za-z0-9_]*"
    r"|\S",
    re.S,
)
WORD_TOKEN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NAME = re.compile(r"^[a-z][A-Za-z0-9_.:]*$")
# A piece of a key: a lowercase name, maybe after a ".", with no space.
KEY_PART = re.compile(r"\.?[a-z][A-Za-z0-9_.:]*")


def is_key_piece(text, kind):
    """A joined part, or a whole join, that builds a key, not player text:
    "flair." .. level, x .. ".intro", "rep:" .. name, "opt." .. k .. ".tip".
    It needs a "." or ":", so a plain word in a join ("kick") is still text.
    tools/locale_check.py uses this rule too (TICK-0078).
    Limit: one word with a period and no space ("kick.") also reads as a
    key piece. Joined player text has a space next to the name it joins."""
    if kind not in ("part", "joined"):
        return False
    t = text.replace("#", "x")
    return KEY_PART.fullmatch(t) is not None and ("." in t or ":" in t)


CODES = re.compile(r"\|T.*?\|t|\|c[0-9a-fA-F]{8}|\|r|\S*\\\S*")
# An operand of ".." ends at one of these, at its own bracket depth.
STOP = {",", ";", ")", "]", "}", "=", "==", "~=", "<", ">", "<=", ">=",
        "and", "or", "then", "do", "end", "else", "elseif", "return",
        "local", "if", "for", "while", "until", "function"}


def banned_words(glossary_text):
    """The scanned words, and the words left to review."""
    lines = glossary_text.splitlines()
    start = next(i for i, l in enumerate(lines) if l.startswith("| Use |"))
    scanned, review = [], []
    for line in lines[start + 2:]:
        if not line.startswith("|"):
            break
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3:
            continue
        for word in cells[2].split(","):
            word = word.replace("`", "").strip()
            if not word:
                continue
            note = re.search(r"\((.*?)\)", word)
            plain = re.sub(r"\(.*?\)", "", word).strip()
            if plain.endswith(" alone") or (
                    note and note.group(1).startswith("for ") and note.group(1) != "for both"):
                review.append(word)
            else:
                scanned.append(plain)
    return sorted(set(scanned)), review


def word_pattern(word):
    parts = [re.escape(p) for p in word.split()]
    return re.compile(r"(?<![\w-])" + r"\s+".join(parts) + r"(?:s|es)?(?![\w])", re.I)


def lua_texts(source):
    """(line, text, kind) for a Lua source. kind is "lone" (a literal no
    ".." touches), "part" (a literal in a join), or "joined" (a run of
    literals joined with "..", with "#" for each other part)."""
    tokens = []  # (kind, value, line)
    for m in LUA_TOKEN.finditer(source):
        tok = m.group(0)
        line = source.count("\n", 0, m.start()) + 1
        if tok.startswith("--"):
            continue
        if m.group(3) is not None:
            tokens.append(("str", m.group(3), line))
        elif m.group(4) is not None or m.group(5) is not None:
            raw = m.group(4) if m.group(4) is not None else m.group(5)
            tokens.append(("str", raw.replace('\\"', '"').replace("\\'", "'").replace("\\n", " "), line))
        else:
            tokens.append(("op", tok, line))

    def is_op(k, *values):
        return 0 <= k < len(tokens) and tokens[k][0] == "op" and tokens[k][1] in values

    def is_name(k):
        return tokens[k][0] == "op" and WORD_TOKEN.fullmatch(tokens[k][1]) is not None

    def ends_value(k):
        """Token k can end a value: a string, a name, a digit or a closing bracket."""
        return tokens[k][0] == "str" or is_name(k) or tokens[k][1] in (")", "]", "}") or tokens[k][1].isdigit()

    texts, used = [], set()
    n = len(tokens)
    for i, (kind, value, line) in enumerate(tokens):
        if kind != "str":
            continue
        # The name argument of CreateFrame("Frame", ...).
        if is_op(i - 1, "(") and is_op(i - 2, "CreateFrame"):
            continue
        joined = is_op(i - 1, "..") or is_op(i + 1, "..")
        texts.append((line, value, "part" if joined else "lone"))

        # The run of ".." from this literal, read as one text. A literal
        # that is a whole operand is used here, so the run is not read
        # again from it. Literals inside other operands are still read on
        # their own above, and start their own runs.
        if i in used:
            continue
        parts, j = [value], i + 1
        while is_op(j, ".."):
            j += 1
            depth, start = 0, j
            while j < n:
                if is_op(j, "(", "[", "{"):
                    depth += 1
                elif is_op(j, ")", "]", "}"):
                    if depth == 0:
                        break
                    depth -= 1
                elif depth == 0 and (is_op(j, "..") or is_op(j, *STOP)):
                    break
                elif depth == 0 and j > start and ends_value(j - 1) and is_name(j):
                    break  # a name right after a value starts the next statement
                j += 1
            if j - start == 1 and tokens[start][0] == "str":
                parts.append(tokens[start][1])
                used.add(start)
            else:
                parts.append("#")
        if len(parts) > 1:
            texts.append((line, "".join(parts), "joined"))
    return texts


def markdown_texts(source):
    """(line, text, kind) for each Markdown line outside code."""
    out, fence = [], False
    for n, line in enumerate(source.splitlines(), 1):
        if line.lstrip().startswith(("```", "~~~")):
            fence = not fence
            continue
        if fence:
            continue
        line = re.sub(r"`[^`]*`", " ", line)
        line = re.sub(r"\]\([^)]*\)", "]", line)  # a link's target
        out.append((n, line, "doc"))
    return out


def toc_texts(source):
    """(line, text, kind) for the ## Title and ## Notes lines of a .toc."""
    out = []
    for n, line in enumerate(source.splitlines(), 1):
        m = re.match(r"##\s*(Title|Notes)\s*:(.*)", line)
        if m:
            out.append((n, m.group(2), "doc"))
    return out


def scan(rel, texts, words, allow, exact=()):
    failures, seen = [], set()
    phrases = [p for p, pattern, _ in allow if fnmatch.fnmatch(rel, pattern)]
    phrases.sort(key=len, reverse=True)
    whole = {p for p, pattern, _ in exact if fnmatch.fnmatch(rel, pattern)}
    patterns = [(w, word_pattern(w)) for w in words]
    for line, text, kind in texts:
        if kind == "lone" and NAME.match(text):
            continue
        if is_key_piece(text, kind):
            continue
        if kind in ("lone", "part") and text in whole:
            continue
        text = CODES.sub(" ", text)
        for p in phrases:
            text = re.sub(r"(?<![\w])" + re.escape(p) + r"(?![\w])", " ", text)
        for w, pat in patterns:
            if pat.search(text) and (line, w) not in seen:
                seen.add((line, w))
                failures.append('glossary: %s:%d: "%s" in "%s"' % (rel, line, w, text.strip()))
    return failures


def _lines(failures):
    return {":".join(f.split(": ")[1].split(":")[:2]) for f in failures}


def self_test():
    """The checker checks itself first, so a broken scan cannot pass."""
    words = ["kick", "keep up", "frame", "auto", "default frames", "intro"]
    allow = [("target frame", "*", "")]
    exact = [("Auto", "*", "")]
    cases = [  # (one Lua line, a hit on it?)
        ('-- a comment with kick in it', False),
        ('local a = "Read keep " .. i .. " now"', False),
        ('local b = "keep " .. "up" .. n', True),
        ('t.tooltip = "Pulses when your kick is ready."', True),
        ('local c = CreateFrame("Frame", nil, UIParent)', False),
        ('local d = "auto"', False),
        ('local e = "Hides the target frame."', False),
        ('local f = [[a long kick string]]', True),
        ('local g = "|TInterface\\\\Buttons\\\\frame:0|t Pick"', False),
        ('local h = "Shows the default frames."', True),
        ('say("Stopped " .. (x or "your kick") .. ".")', True),
        ('say("Stopped " .. ("%s, a keep up buff"):format(x))', True),
        ('say("Stopped " .. x .. ", " .. L("your kick"))', True),
        ('say(x .. " kick")', True),
        ('say("kick" .. x)', True),
        ('local k = { "auto", "Auto" }', False),
        ('local m = { "auto", "Auto (class default)" }', True),
        ('local o = x .. "keep " .. "up"', True),
        ('Add(p.intro, Text(step.texts .. ".intro"))', False),
        ('local q = Text("opt." .. key .. ".kick")', False),
        ('say("Read the intro")', True),
        ('say("Read the " .. x .. " intro")', True),
        ('say(x .. " kick")', True),
    ]
    lua = "\n".join(c for c, _ in cases) + "\n"
    want = {"X.lua:%d" % (k + 1) for k, (_, hit) in enumerate(cases) if hit}
    got = _lines(scan("X.lua", lua_texts(lua), words, allow, exact))
    fails = []
    if got != want:
        fails.append("glossary: the Lua self-test found %s, not %s" % (sorted(got), sorted(want)))
    md = "Use `kick` here.\n```\nkick\n```\nA kick.\n~~~\nkick\n~~~\n"
    got = _lines(scan("R.md", markdown_texts(md), words, []))
    if got != {"R.md:5"}:
        fails.append("glossary: the Markdown self-test found %s, not ['R.md:5']" % sorted(got))
    toc = "## Interface: 16001\n## Title: HUDini\n## Notes: A kick for you.\n## X-Kick: no\n"
    got = _lines(scan("T.toc", toc_texts(toc), words, []))
    if got != {"T.toc:3"}:
        fails.append("glossary: the .toc self-test found %s, not ['T.toc:3']" % sorted(got))
    return fails


def run(root):
    """Failure lines for the repo at root, the scanned words, and the words
    left to review."""
    failures = self_test()
    words, review = banned_words((root / "framework" / "glossary.md").read_text(encoding="utf-8"))
    if not words:
        failures.append("glossary: no word in the \"Do not use\" column of framework/glossary.md")
    lua_files = sorted(
        p for p in root.rglob("*.lua")
        if not SKIP.intersection(p.relative_to(root).parts)
        and not any(x.startswith(".") for x in p.relative_to(root).parts)
    )
    for p in lua_files:
        rel = p.relative_to(root).as_posix()
        failures += scan(rel, lua_texts(p.read_text(encoding="utf-8")), words, ALLOW, EXACT)
    for p in sorted(root.glob("*.toc")):
        failures += scan(p.name, toc_texts(p.read_text(encoding="utf-8")), words, ALLOW)
    for rel in DOCS:
        p = root / rel
        if not p.is_file():
            failures.append("glossary: %s is missing; fix DOCS in tools/glossary_check.py" % rel)
            continue
        failures += scan(rel, markdown_texts(p.read_text(encoding="utf-8")), words, ALLOW)
    return failures, words, review
