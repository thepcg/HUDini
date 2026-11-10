# Changelog

What changed in each version of HUDini, for players. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). HUDini uses
[semantic versions](https://semver.org/): a new minor version adds
features, and a new patch version fixes them. `/hud version` tells you
which version you have.

## [Unreleased]

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
  that runs out shows its icon by your health bar, and a friend you target
  who lacks one shows it by theirs. Fishing without bait says "No bait."
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
