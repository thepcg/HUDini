# Contributing to HUDini

Thank you for your help. HUDini is a small addon for the WoW Forever client, and every report makes it better.

## Report a bug

Open an issue and pick **Bug report**. The form asks for:

- the HUDini version (type `/hud version`),
- your class and level,
- what you did, what you saw and what you expected,
- every Lua error that names HUDini. [BugSack](https://www.curseforge.com/wow/addons/bugsack) catches each one with the full stack; copy all of it. No BugSack? Copy the text from the game's own error window,
- whether it happened in a fight,
- your Icon layout (Options > AddOns > HUDini > Icons: Rows: Action Bars 1-3, or Packed: selected bars),
- other UI addons you use, like ElvUI or Bartender,
- the chat line from `/hud why`, if the HUD shows or hides at the wrong time,
- the chat lines from `/hud debug api`, if a feature does not work at all.

One bug in each issue, please.

## Ask for a change

Open an issue and pick **Idea**. Tell us what you try to do in the game and what stops you today.

HUDini does one thing: a small HUD at the center of the screen, with your action bars, your bars and your target's, that hides when nothing needs you. These are not planned for 1.0:

- Retail support,
- party or raid frames,
- a full UI replacement.

Ideas for play with fewer hints belong in the sister addon Unguided.

## Change the code

- HUDini runs on the retail 12.x engine of WoW Forever: the retail `C_*` API, Lua 5.1, Interface 16001.
- **Secret values.** In a fight, many values (auras, health, chat lines) are secret, and they throw an error if you compare or join them. Route each one through `ns.Plain()`, `ns.IsSecret()` or `pcall`. A change that reads a new value in a fight must say how it handles a secret one.
- **Check gate.** Run `powershell -NoProfile -File tools\check.ps1` from the repo root. It checks the Lua 5.1 syntax of every file, that the .toc and the files agree, the tests in `tools\tests`, luacheck, the glossary and the player text. Pass means the line `all passed`. It needs a Python venv with `lupa`; the top of `tools\check.ps1` says how to make it.
- **A new or renamed file** in `HUDini.toc` needs a full game restart. `/reload` does not load it.
- **Commits.** `type(scope): summary`, for example `fix(alerts): stop the outline on a dead target`. Types: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`. The body says why.
- **Player text** lives in `Locales/enUS.lua`, at three Guide's flair levels. It uses the words in `framework/glossary.md` and US spelling. Match the voice of the texts around it: at Light, short and plain; at Modest, friendly, with a dry remark now and then; at Full, Khadgar speaks, and a short aside may end the text. At every level the facts come first. Option labels, buttons and alerts on the HUD read the same at every level.
- **TICK-NNNN and D-NNN** in comments and commits point to the project's private tracker: a ticket and a decision. You do not need them to read the code.

## Add a class file

What differs between classes is data, not code. Each file in `Classes/` gives one class its spells, by name. A name covers every rank of a spell. HUDini uses names because Forever's spell IDs differ from Retail's.

Each of the nine classes has its file. A fix for a spell name, a level or a missing alert is welcome.

### An example: Mage

This is the core of `Classes/Mage.lua`. The real file also fills `auraMap` with the armor buffs that replace each other:

```lua
--[[--------------------------------------------------------------------------
	HUDini - Mage

	Data only. See Classes.lua for what each field means.
----------------------------------------------------------------------------]]

local ADDON, ns = ...

ns.RegisterClass("MAGE", {
	interrupt = "Counterspell",                   -- level 24 on Forever
	dispel    = { Curse = "Remove Lesser Curse" }, -- Forever's name, level 18
	purge     = { spell = "Spellsteal", stealable = true }, -- not in Forever's spellbook yet
	keepUp    = { "Ice Barrier", "Mana Shield" },  -- talent at 40, and level 20
	resource  = nil,                              -- Retail's Icicles is not on Forever
	auraMap   = {},
	powers    = { "MANA" },
})
```

### The fields

Leave out a field when the class has no spell for it. HUDini then builds no option row for it.

| Field | What it is | Shape |
|---|---|---|
| `interrupt` | The spell that stops an enemy cast. The interrupt alert outlines a cast it can stop | `"Spell"` |
| `dispel` | One spell for each debuff type you can remove from yourself: `Curse`, `Poison`, `Disease`, `Magic` | `{ Curse = "Spell", Poison = "Spell" }` |
| `purge` | The spell that removes a buff from an enemy. Use the table shape when it takes only stealable buffs | `"Spell"`, or `{ spell = "Spell", stealable = true }` |
| `keepUp` | The combat buffs: buffs you keep on in a fight. In a fight with none of them on, the "Combat buff is off" alert shows the first one you know | `{ "Spell", "Spell" }` |
| `resource` | A row of pips above your bars: the stacks of a buff, or a power like combo points | `{ aura = "Buff", max = 5 }`, or `{ power = "ComboPoints", onlyWith = "ENERGY" }`, or `nil` |
| `auraMap` | Extra buff names that light an icon, when the buff's name differs from the spell's | `{ ["Spell"] = { "Buff" } }` |
| `weaponBuff` | The weapon buffs of the class. Know one of them, and each weapon in your hands needs one on it | `{ "Spell", "Spell" }` |
| `powers` | Every power the class can show | `{ "MANA" }`, `{ "RAGE" }`, `{ "ENERGY" }` |

Power names come in two kinds, and a wrong kind fails with no error:

- `powers` and `resource.onlyWith` take the power token, in capitals: `MANA`, `RAGE`, `ENERGY`, `RUNIC_POWER`. It is the second value of `UnitPowerType("player")`. Only `MANA`, `RAGE` and `ENERGY` have their own color picker in the options; the others use Blizzard's colors.
- `resource.power` takes a key of `Enum.PowerType`, in CamelCase: `ComboPoints`, `HolyPower`. With a wrong key, no resource bar shows.

### Steps

1. Copy `Classes/Mage.lua` to `Classes/<Class>.lua`.
2. Change the header and the class token in `ns.RegisterClass`. The token is the game's own, in capitals: `WARRIOR`, `PALADIN`, `HUNTER`, `ROGUE`, `PRIEST`, `SHAMAN`, `MAGE`, `WARLOCK`, `DRUID`.
3. Write the spell names in Forever's spelling, from the spellbook tooltip. To check a name in the game, type `/dump C_Spell.GetSpellInfo("Name")`. A name the game knows returns a table; a wrong one returns nothing.
4. Put a short comment on each spell: the level it comes at, and any Forever note (a talent, a different name, not in the game yet).
5. Add the line `Classes\<Class>.lua` to `HUDini.toc`, with the other `Classes\` lines.
6. Run `tools\check.ps1`. It must say `all passed`.
7. Restart the game (not `/reload`), log in on that class, and check each alert you added. Write what you checked in the pull request.

`Classes.lua` explains each field again at the top of the file. Your own choices from the options and slash commands are saved for each class and win over the class file.
