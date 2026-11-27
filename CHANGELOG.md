# Changelog

What changed in each version of HUDini, for players. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). HUDini uses
[semantic versions](https://semver.org/): a new minor version adds
features, and a new patch version fixes them. `/hud version` tells you
which version you have.

## [0.32.0] - 2026-11-27

### Added

- Hide the game's objective list, on the Game frames page: the tracked
  quests and other goals on the right side of the screen go away, and
  come back in Edit Mode or when you turn it off. Off at the start.
- Cursor ring, on the Game frames page: a see-through ring, halo or four
  arrows centered on your mouse cursor, so you find the cursor fast. Pick
  its shape and size; under Advanced, set how strongly it shows out of
  combat, in combat alone, and in combat in a group. Off at the start.
- Hunters: once you learn Tranquilizing Shot, it is your purge. An
  Enrage on your target shows on its health bar, with Show removable
  enemy buffs on the Alerts page. Alone it works in a fight too; in a
  group the game often hides the buff in a fight, so it may not show.
- Sound alerts, under Advanced on the Alerts page: a sound when combat
  starts, when it ends, for each honorable kill, and when your health or
  mana drops below a line you set. Each one starts off; pick a sound and
  its volume to turn it on. Low health and low mana play out of a fight
  only, because in a fight the game hides those values from addons.
- Sound alerts for your class, under Advanced on the Your class page: a
  sound for each class alert you have, such as an interrupt, a curse or
  a poison you can remove, or a buff you can purge. Each one starts off
  and is saved for that class. Repeat while the buff is missing, under
  the buff missing sound, plays it again about every 5 seconds in a fight.
- A weapon you hold with no weapon buff, such as a Rogue's poison or a
  Shaman's imbue, shows that buff's icon by your health bar out of
  combat. Turn it off with Weapon buff alert, under Buffs on the Your
  class page; Weapon buff sound, under its Sound alerts, plays a sound
  once as it shows.
- Pet alert, for Hunters and Warlocks: left of your health bar, the spell
  your pet needs. That is Revive Pet or Feed Pet out of a fight, or your
  call or summon spell while no pet is out. It is on at the start; turn it
  off under Pet on the Your class page.
- No ammo, left of your health bar, when you run out with a bow, gun or
  crossbow; a Hunter also gets Low ammo out of a fight. Either one shows
  the HUD for a few seconds. It is on for Hunters. A Warrior or a Rogue
  can turn it on with Ammo alert, under Ammo on the Your class page.
- A Textures page, after Bars: Bar texture, then a button for each bar
  that picks its own texture and a gradient (Darker, Lighter or To a
  color), or an image file of your own. The class resource bar's button
  is at the end of Resource on the Your class page, and each cooldown's
  timer bar has one next to its Timer bar box.
- Each timer bar can have its own color: This bar's color, on its
  texture button. Until you pick one, it uses Timer bar on the Colors
  page. Use on every timer bar copies the color too.
- Keep timer bars in view, under When the main HUD appears on the HUDini
  page: a running timer bar stays on screen, in its usual place, when the
  main HUD hides or fades. It is off at the start.
- HUDini setup's step for your class lists the buffs HUDini watches from
  the start, such as Arcane Intellect and your armor for a Mage: an icon
  by your health bar when one is off.
- A Paladin who tanks with Seal of Fury and no Righteous Fury sees the
  Righteous Fury icon by the health bar in a fight. Remind me of Righteous
  Fury when I tank, under Advanced on the Your class page, turns it off.

### Changed

- Bar texture moved from the Bars page to the Textures page. Timer bar
  texture is gone from the Bars page: each timer bar picks its own now,
  and a texture you picked there stays on the timer bars that are on.
- Cooldowns, under Advanced on the Your class page: each spell now has
  three controls side by side, under a row of column heads: Ready glow,
  Timer bar and Sound. Pick any mix. Each spell picks its own sound, or
  Off, and a pick plays the sound once. Your old choices carry over: a
  spell that had the bell gets the ready glow and your old Bell sound.
- The ready glow now stays on the spell's icon in a fight until you cast
  the spell or the fight ends. Out of a fight it lasts 5 seconds.
- HUDini setup's step for your class now offers a ready alert for your big
  cooldowns: the ready glow and its sound together.
- Sound when a buff is missing, and the Sound of each cooldown, now pick a
  sound and its volume: a list of sounds, with Off first, and a volume
  slider next to it (25%, 50%, 75% or 100%). Each pick or volume step
  plays the sound once. Your old sounds carry over at full volume.
- Mute cooldown and range voice lines is now seven boxes, one per voice
  line, under Advanced and Game sounds on the Game frames page: "still
  recharging", "too far away", "not enough mana", "not enough rage", "not
  enough energy", "can't attack that" and "I can't do that yet". Each box
  mutes only its own line, at once. If you had the old box on, its three
  lines ("still recharging", "too far away", "I can't do that yet") stay
  muted. The error sound and the red error text stay.

### Removed

- Bell sound, under Advanced on the Your class page: each spell picks its
  own sound in its Cooldowns row now.

### Fixed

- Your class: a spell, item or buff you learn after the first open of
  the options now joins its own section. Before, it could split
  Cooldowns in two, with Missing items in between.
- In the packed icon layout, the tooltip of Read visible action bars
  automatically, and setup's last page, now say that a bar you hide in
  Edit Mode drops its actions from the HUD. Turn the option off to choose
  bars yourself.
- Coins in the feed sit level with their numbers again.
- A feed line that wraps keeps its text clear of its icon.

## [0.31.0] - 2026-11-22

### Added

- Cooldowns, under Advanced on the Your class page: for each spell you
  know, pick a bell, a timer bar, or both. The bell rings when the
  cooldown ends and, if the spell is on the HUD, its icon glows for 5
  seconds. The timer bar sits under the HUD while the cooldown runs, with
  the spell's icon and the time left; the bar with the least time left is
  on top. Your class's own spells come first, such as Heroism and
  Bloodlust for a Shaman, then every other spell you know that has a
  cooldown, such as Earth Shock and Flame Shock. A spell you learn later
  gets its row the next time you open the options.
- The timer bars move on their own: use `/hud unlock` and drag their blue
  box, then `/hud lock`. Each class keeps its own place. Timer bar place,
  under Advanced on the Bars page, puts them back under the HUD.
- Timer bar texture and Timer bar text, under Advanced on the Bars page,
  and the timer bar color, under Advanced on the Colors page. The text
  shows the time left, or the percent left.
- Sound when a buff is missing, under Buffs on the Your class page: a
  sound when a buff reminder shows next to your health bar in a fight.
  It is off until you pick a sound.
- Bell sound, under Advanced on the Your class page: pick the sound the
  bell plays when a cooldown ends. Each sound plays once when you pick it.
- HUDini setup shows the version of HUDini at the top of every page.
- HUDini setup has a step for your class. It suggests a bell for your big
  cooldowns, the sound when a buff is missing, and missing items, already
  checked; uncheck any you do not want. It also lists the alerts that are
  already on, and the last page lists your picks.
- Each class starts a few alerts on, such as the Evocation bell for a Mage
  and the Lay on Hands bell for a Paladin. The Paladin, Priest, Shaman and
  Warrior also start the sound when a buff is missing. A bell starts when
  you learn its spell. Turn any of them off on the Your class page or in
  HUDini setup, and it stays off.
- Missing items, under Advanced on the Your class page: out of a fight, an
  icon by your health bar when your bags hold none of an item you can make
  or need for a spell, such as Flash Powder for a Rogue's Vanish. Show
  your health must be on.

### Changed

- A weapon skill line in the feed now shows how high the skill can go,
  such as "Swords 43/70". Profession lines are as before.
- Class alerts use WoW Forever's own spells for all nine classes. Spells
  that WoW Forever does not have are gone, such as Spellsteal and the
  Blessings of Salvation, Light and Sanctuary. Each class spell also has
  its WoW Forever spell ID, so the alerts find it in a game client of any
  language.

## [0.30.0] - 2026-11-14

The first public release. HUDini puts your action bars, in keybind order,
your health, power and cast, and your target's bars in one block at the
center of the screen, and hides it when nothing needs you. `/hud why` says
why it shows or hides. The README lists every part; these are the
highlights.

### Added

- HUDini setup: at your first login it says what HUDini is and sets up the
  HUD in a few plain steps. Finish for now stops there and keeps the
  choices made so far. Type
  `/hud setup`, or click Run setup on the HUDini options page, to run it
  again. Each step starts at your current settings, so Next keeps them.
- Class alerts for all nine classes: an outline on an enemy cast you can
  interrupt, a tint for a debuff on you that you can dispel, your target's
  buffs you can purge, and a mark when a combat buff is off. A learned buff
  that runs out shows its icon by your health bar (one under 30 minutes
  only in a fight), and a friend you target who lacks one shows it by
  theirs. Fishing without bait says "No bait."
- The feed: one line for each thing you get, such as loot, money, a
  finished quest, a new level, a new spell or mount, or a flight path. It
  waits out a fight, then fades. Pick what shows on the Feed page.
- An About window, from the HUDini options page: the version, the author,
  the license, the AI help, and where to get help.
- The Game frames page: hide the game's player frame, target frame, cast
  bar and experience bar; show the bag buttons, menu buttons or minimap
  only on hover; move and resize game windows. Each one is off until you
  enable it.
- Khadgar, of Dalaran, hosts HUDini. He says hello on the first page of
  HUDini setup. The Guide's flair choice, under Advanced on the HUDini
  options page, sets how much he says: Light (the default), Modest or Full.
  Errors, alerts and option names read the same at every level.
- The options have eight pages: HUDini, Icons, Bars, Colors, Alerts, Your
  class, Feed and Game frames. Each page starts with the choices most
  players change. The rest are under Advanced, at the bottom of the page.
- A Preset choice at the top of the HUDini options page: Minimal, Standard
  or Leveling. Each one sets what the HUD shows: the experience bar, your
  target's power, the feed and its two hints. Your position, size and
  colors stay. It shows Custom when your own choices match no preset.
- A minimap button: left-click opens the options, right-click runs HUDini
  setup, and a drag moves it around the minimap edge. HUDini is also in the
  addons button on the minimap. Clear Show minimap button on the HUDini
  options page to hide the button; the addons button still opens HUDini.
- A Your class options page: pick the spell for your interrupt, each
  dispel type, your purge, your combat buff and your class resource, from
  the spells on your action bars. Each class keeps its own picks. "Class
  default" puts back HUDini's own spell, and "Clear learned buffs" clears
  the buffs HUDini learned for this class.
- 15 chat commands, in three groups (`/hud help` lists them). Every setting
  is in the options. `/hud test` shows each part of the HUD with sample
  values, feed lines too; type it again to end it. `/rl` does the same as
  `/reload`, if no other addon uses it.
- A quieter screen: HUDini setup's last step offers to show the bag bar and
  the menu buttons only when the pointer is over them. It also says how to
  hide the game's own Action Bars 2 and 3 in Edit Mode: their spells are on
  the HUD, and their keys still work. It says so only while the icon layout
  is Rows: Action Bars 1-3, the default, as Packed: selected bars reads
  only the bars on screen. And it says how to hide the gryphons (or the
  wyverns) at the ends of Action Bar 1: in Edit Mode, click each End Cap
  and check its Hidden box.
- Your target's level shows Elite, Rare, Rare Elite or Boss after it, and a
  boss shows its level as "??". The level is colored by how hard the target
  is, as on the game's own target frame. A small faction mark shows on your
  health bar while you are flagged for PvP, and on your target's bar while
  it is a flagged player. The feed says when you enter or leave a rest
  area.
- Your health bar and your target's say Dead, Ghost or Offline, and turn
  gray. They show heals on the way, and the damage a spell will absorb, as
  the game's own frames do.
- Your health and power bars, and your target's, show a number: a percent,
  a short number such as 12.3k, or both. Pick it under Health and power
  numbers on the Bars page.
- Your cast bar and your target's show the spell name and the time left.
  Yours says Failed or Interrupted when a cast does not finish.
- Shamans see each totem and its time left under the HUD. Druids see a thin
  mana bar under the power bar in bear and cat form.
- Three rows of aura icons, each with its time left and stacks, under Bars:
  your debuffs on the target and the target's buffs above the HUD, and the
  debuffs on you right of your health bar.
- Mute cooldown and range voice lines, under Game sounds on the Game frames
  page: your character no longer says that a spell or item is still
  recharging, or that the target is too far away. The error sound and the
  red error text stay. Off at the start.
- Upgrade numbers in your bags, under Your bags on the Game frames page: a
  green +N on gear your class can wear now whose item level is N above what
  you wear in that slot, and a gold + at the bottom left when the stat changes
  the game lists for it add up to a gain. Off at the start.
- Date and time in chat, under Chat windows on the Game frames page: each
  new line in your chat windows starts with the server date and time, in
  place of the game's own timestamp. Date and time format picks one of
  three: 26-11-14@09:25:04, [09:25], or 11/14/26 [09:25]. The combat log
  gets none. Off at the start.
