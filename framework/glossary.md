# Glossary

One fixed word for each thing in player-facing text: option labels, tooltips, chat lines, README, CHANGELOG, store pages. Code names may differ. A new term is added here in the same change that first uses it.

| Use | Meaning | Do not use |
|---|---|---|
| HUD | The whole HUDini display at the center of the screen. The texts also say "main HUD" and "display" | frame (for the HUD), UI |
| icon grid | The rows of action icons in the HUD. "Buttons" is fine for the game's own action, bag and addon buttons | buttons (for icons), bar (for icons) |
| action bar | One of the game's own action bars | bar alone |
| bar | A health, power, cast or XP bar | |
| interrupt | The spell that stops a cast, and the alert for it | kick, kickable |
| proc glow | The glow when a spell becomes ready from a proc | glow alone |
| buff | A helpful effect, in the game's own sense. For HUDini's own kinds, use one of the three rows below | your buff (for a tracked buff) |
| combat buff | A buff from your class file that you keep on in a fight (for a Mage: Ice Barrier, Mana Shield). The "Combat buff is off" alert shows the one to cast | class buff, keep-up, keep up, shield |
| tracked buff | A buff of 5 minutes or more, or with no end (a paladin aura), that HUDini saw you cast, and now watches (for example Arcane Intellect). `/hud buffs` lists them. The options call them "learned buffs" ("Clear learned buffs"); both are fine | keep-up, keep up, long buff, class buff |
| weapon buff | A temporary weapon enchant (poison, oil, imbue) | weapon enchant |
| class default | The spell the class file picks for your class; the first choice in each Your class dropdown, and its reset | auto, built-in (for class default) |
| class file | HUDini's list of spells for one class: its interrupt, dispels, purge, combat buffs and resource. A player rarely needs the word; prefer "HUDini knows no ... for your class" | class profile, profile |
| feed | The fading list of what you get (loot, money, XP, rep) | loot window, toast (for the feed) |
| highlight | A feed line that stands out because it matters | |
| idle | The state where the HUD hides because nothing needs your attention (short form: "nothing needs you") | smart, auto-hide |
| lock / unlock | Fix or free the HUD position | |
| hover | Show only while the pointer is over it ("Show bag buttons only on hover"). Older docs say mouseover; both are fine | |
| dispel / purge | Remove a harmful effect from a friend / a helpful effect from an enemy | cleanse (for both) |
| the game's own frames | The game's own frames: player, target, cast bar, XP bar, bag bar, menu buttons, minimap and windows. One of them is "the game's own experience bar". Their options page is **Game frames** | default frames, Blizzard frames, Blizzard (for the game's frames) |
| preset | A ready-made set of HUD settings, picked on the HUDini options page (Minimal, Standard, Leveling). It was once called Style; code and older docs say style | profile, theme |
| Custom | The Preset dropdown's name for settings that match no preset | Manual, User |
| Edag | The author: "Made by Edag". With Khadgar, one of the two names in HUDini's text | |
| Khadgar | HUDini's host: he introduces himself on page 1 of setup at every flair level, and speaks in setup, the About window and the docs at Full. The only game character HUDini names | |
| AI help | How HUDini says that AI models helped make it: in the About window, the README and the store page, with no name of a model or company (D-032) | |
| About window | The small window with HUDini's version, who made it, and where to get help. Its credits and licenses section is "Credits and licenses" | about dialog, about box, info |
| setup | The few steps on first login that say what HUDini is and set up the HUD ("HUDini setup"; `/hud setup` or Options > HUDini > Run setup runs it again). It replaced the welcome card. "wizard" appears only in Khadgar's jokes | wizard (for setup, outside Khadgar's jokes), welcome card, welcome screen, intro, tutorial |
| Advanced | The last section of an options page, for rows most players never change | More (for Advanced), Expert |
| minimap button | The HUDini button on the minimap edge: left-click opens the options, right-click runs HUDini setup | minimap icon, LDB icon, broker |
| flair | How much of the voice's touch HUDini's words have. One setting, three levels: Light (the default), Modest, Full ("Flair levels" below). Its option is "Guide's flair"; "personality" is fine in its tooltip | tone, verbosity, Plain (for level 0) |
| addons button on the minimap | The game's button on the minimap that lists your addons; HUDini has an entry there. Docs and tickets call it the AddOns menu; player text says where it is, because the Esc menu and Options also have an "AddOns" | AddOns menu (in player text), addon compartment, compartment |

## Style

- US spelling (color, center, armor).
- No names. HUDini's text names no person, company, product or trademark. Two names are allowed: the author, Edag, and the host, Khadgar. The About window adds two more: the legal line, "not affiliated with or endorsed by Blizzard Entertainment", and the font credit, "The Mozilla Foundation and Telefonica S.A." and "The Fira Code Project Authors". At Full, lore place names (Dalaran, Azeroth) may appear in Khadgar's lines; at Light, only "Khadgar, of Dalaran" on page 1. Say "the game's own ..." for the game's frames and windows. The README's AI-help section and Credits, and the store page's AI-help paragraph, keep naming the AI model; the gate allows those names only there.
- Option labels: sentence case, no period ("Hide when idle").
- Tooltips: 1-2 sentences, the effect first ("Hides the HUD when nothing needs you. Shows it again in a fight.").
- Chat lines, four kinds, all through one `ns.Say`:
  - A setting changes: `HUDini: <Option label>: on.` (or `off.`, or the value). The label is the one in the options panel.
  - An answer: `HUDini: <sentence>.` ("HUDini: The HUD shows because you are in combat.")
  - An error: `HUDini: <what is wrong>. <what to do>.` ("HUDini: The feed is off. Type /hud feed to turn it on.")
  - Debug (`/hud debug ...`): `HUDini: <title>`, then indented lines. Debug words follow the glossary too.
- A sentence starts with a capital letter and ends with a period.
- One voice: the one in "Voice" below.

### Voice

**The texts in `Locales/enUS.lua` win.** Edag wrote every player text there. Where a rule below and those texts differ, the texts are right, and new text follows their voice. The rules below cover what the texts do not show.

Succinct, with a slight hint of flair: a learned mage who does his very best to sound like a normal person. He keeps it plain on purpose, and now and then the learning shows.

**What it is**

- Plain first. Each line works with the flair taken out. The flair never carries the meaning.
- One touch at most in a line, and most lines get none: about one line in five. This is level 0, Light, the default; levels 1 and 2 add more ("Flair levels" below).
- A small touch: a precise word where the plain one is flat ("settle", "call back", "vanish"); never a word that is also a game action, like "summon", a dry understatement, a calm and slightly formal turn ("as" for "because", "at once" for "right away").
- Calm and kind. The player did nothing wrong. Say what happened and what to do.

**What it is not**

- Not lore at Light: no quotes, places or in-jokes, except that page 1 of setup introduces Khadgar. At Modest and Full, Khadgar may use a lore place name, but never quotes the game and never needs lore to make sense.
- No contractions at Light ("it is", not "it's"); the one exception is the tagline, which matches the store page. Modest and Full may use them: Khadgar talks.
- Not theater: no "behold", "alas", "thee", no exclamation marks. The one exception is the feed's level-up highlight, `Level <n>!`: a big moment earns one.
- Not puns, memes, emoji, or a joke at the player's cost.
- Not longer. At level 0, a touch that adds more than about three words is cut.

**Where a touch may go**

| Surface | Flair |
|---|---|
| Option labels, section headers, buttons | None. Sentence case, the glossary word |
| A setting changes (`HUDini: <Option label>: on.`) | None. The format is fixed |
| Alerts on the HUD ("No bait") | None. They are read at a glance, in a fight |
| Errors | None in the "what to do" part. The "what is wrong" part stays plain too |
| Setup | The body lines follow the flair level the player picks on page 1. Questions, choice names and the line under each, "(default)", buttons, "Changes:" lines and page 7's alert lines have one text at every level. One exception: the line under each step 1 check box follows the level |
| About window | Made by, the tagline, the help line and the last line follow the flair level, and so does the `/hud version` chat line. Title, version, host line, AI line, the two section headers, the credits and licenses, the fan project line, header, link line, link, copy line, "Copied." and Close have one text |
| Tooltips | The first sentence is the effect, plain. A second sentence may have one |
| Chat answers, `/hud why`, `/hud help` lines | One at most in a line |
| Debug (`/hud debug ...`) | None. It is for bug reports |
| README, store page | One at most in a paragraph. Headings plain |

**Do and don't**

| Don't | Do | Why |
|---|---|---|
| Behold! Your HUD has vanished! | The HUD is hidden: nothing needs you. It returns the moment something does. | Theater and "!"; the touch is "the moment something does" |
| Oops, that spell eludes me. | There is no command called flarb. Type /hud help to see them all. | An error is plain: what is wrong, what to do |
| By the Kirin Tor, a mage HUD! | HUDini puts your action bars, health and target at the center of the screen. When nothing needs you, it vanishes. | No lore as a hook, no "!"; "vanishes" is the touch, and the name earns it |
| Drag it anywhere; the HUD will not mind. | Drag the blue box to where you want the HUD, then click Lock. | A how-to line in setup has one text, at every level |
| Lock the HUD: engaged. | Lock the HUD: on. | The setting format is fixed |

### Flair levels

One option, **Guide's flair** (Options > HUDini, under Advanced), and the first question in setup. Every rule above holds at every level, except where this table says more.

| Level | Name | In a line that may have flair |
|---|---|---|
| 0 | Light (default) | The voice above: one touch at most, in about one line in five, adding about three words at most |
| 1 | Modest | One touch in most such lines, sometimes two. A line grows by a few words at most |
| 2 | Full | A learned, formal turn in every such line, up to about 8 more words. In setup and the About window, the voice goes further: a warm, chatty old mage who rambles a little. He may speak as "I", and a text may end with one short aside or a small joke at his own cost. Still no lore, no theater words, no puns, no "!" |

**Full in setup and the About window.** The facts and the how-to words come first, as at every level; the aside comes last and carries no fact. One aside in a text at most. The joke is on the old mage, never on the player or the game. He is Khadgar. He names no one but himself and Edag, and he says "setup", not "wizard", except in his page 1 joke. A page must still fit the window. Samples:

- "Something about running setup seemed a little insulting to an old mage, until I really got into it."
- "Watch the HUD below: it changes size as you click, so you can judge it by eye. Take your time. I once spent a week choosing a hat."
- "Should it ever seem to have a mind of its own, simply ask it: type /hud why. It answers in one short line, a skill I never quite learned."

- **The same at every level:** labels, headers, buttons, setting lines, errors, alerts on the HUD, the feed, debug, and the first sentence of a tooltip. They have one text. No level names a person, company or product; Khadgar and Edag are the only names.
- **Which lines may have flair:** the rows of "Where a touch may go" that allow one: chat answers, `/hud why` and `/hud help` lines, a tooltip's second sentence, setup body lines, the About window's body lines, README and store page (one text: the docs are in Khadgar's voice where they say so).
- **Plain first, at every level.** Each line still works with the flair taken out, and the meaning comes first in the line.
- **A missing level uses the level below it**. A line that is the same at a level has no text of its own there. The texts of every level are in `Locales/enUS.lua`.
