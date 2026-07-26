<h1 align="center">Everything Quests</h1>
<p align="center">
  <strong>A unified replacement for the Blizzard quest experience — tracker, world-map overlays, nameplate quest icons, an account-wide quest history, and a Midnight chain guide.</strong>
</p>
<p align="center">
  <a href="https://ko-fi.com/wheelbarrel00"><img src="https://img.shields.io/badge/Support-Ko--fi-FF5E5B?style=flat-square&logo=ko-fi" alt="Support on Ko-fi" /></a>
  <a href="https://www.paypal.biz/wheelbarrel00"><img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal" alt="Donate with PayPal" /></a>
  <a href="https://github.com/wheelbarrel00/EverythingQuests/releases"><img src="https://img.shields.io/github/v/release/wheelbarrel00/EverythingQuests?color=6D0501&label=Version&style=flat-square" alt="Version" /></a>
  <img src="https://img.shields.io/badge/WoW-Midnight%2012.0-8B0000?style=flat-square" alt="WoW Version" />
  <img src="https://img.shields.io/badge/Interface-120005-333333?style=flat-square" alt="Interface" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wheelbarrel00/EverythingQuests?style=flat-square&color=333333" alt="License" /></a>
</p>

---

## Overview

Everything Quests is a complete replacement for Blizzard's quest tracking and quest log experience for **World of Warcraft: Midnight**. It bundles seven major features into one addon:

1. A custom on-screen **Quest Tracker** that replaces the default ObjectiveTrackerFrame
2. **Nameplate Quest Icons** — `!` + remaining count/percent on objective mobs in the 3D world
3. Interactive **World Quest pins** on the world map and zone maps
4. A standalone **Chain Guide** window for browsing Midnight quest chains
5. An account-wide **Quest History** log with five views and a backfill of past completions
6. Branded **Quest POI** overlays on zone maps
7. Optional **auto-accept / auto-turn-in** for quest dialogs (Alt to pause)

Open Options with **`/eqs`**, from the minimap button, or via **Game Menu → Options → AddOns → Everything Quests**.

---

## Features

### Quest Tracker
A native-feeling, draggable, resizable on-screen quest list that replaces Blizzard's ObjectiveTrackerFrame.

- **Filtering** — Per-quest-type toggles (Normal, Daily, Weekly, Campaign, World Quests) and a "current zone only" mode
- **Sorting** — Six modes: Zone, Status, Type, Level, Distance, or Manual (drag-to-reorder)
- **Visibility rules** — Optionally hide in combat, in instances (raids, dungeons, delves), or when the world map is open
- **Simplify mode** — Toggleable compact display
- **Watched vs all** — Show only quests you've watched (Blizzard default) or every quest in your log
- **Auto-track** — Automatically watch newly accepted quests (toggleable)
- **Hide scroll bar** — Optional clean look; mouse-wheel scrolling works either way
- **Quest item buttons** — Usable quest items render as a clickable secure button on the row; combat-safe (anchored off the block to avoid taint)
- **Smart instance header** — Two-tier header inside an instance: category (`Delves` / `Dungeon` / `Follower Dungeon` / `Raid`) over the real name (`The Darkway`, `Magisters' Terrace`, `Windrunner Spire`, etc.) resolved from `GetInstanceInfo`
- **"Quest Discovered!" callouts** — Clickable boxes at the top of the Quests section for newly discovered and ready-to-complete quests (via `GetAutoQuestPopUp`), with a toggle on the Tracker tab
- **Turn-in directions** — Ready-to-turn-in quests with no checklist objectives (the "speak to X" kind) show the quest's `objectivesText` so the block is never blank
- **Quest sound notifications** — Optional sound on quest completion; the chat-text fallback now guards against Midnight's `issecretvalue` system messages
- **Lock tracker** — Disable both drag-to-move and resize once you've placed and sized the tracker (also hides the resize grip)

### Nameplate Quest Icons
Quest-objective enemies show EQ's logo (kill objectives get a skull, talk-to objectives a chat bubble, use-item objectives the quest's item icon) right on their nameplate, along with the remaining count or percent.

- **Detection** — Two-source join: an `activeQuests` cache built from `C_QuestLog.GetQuestObjectives` (objectives keyed by display text → `{value, type, isPercent, itemTexture}`, where `value` is the *remaining* amount) joined to each nameplate via a `C_TooltipInfo.GetUnit` line-type scan (`QuestTitle` + `QuestObjective` lines matched against the cache, with matched objectives de-duplicated by entry so a party-mate's identical line can't double-count one of yours)
- **Cached per GUID** — Tooltip scans only run when a new mob appears on a plate or quest log changes, never per frame
- **Midnight-safe** — Guards all game-returned strings/GUIDs with `issecretvalue` so restricted values can't throw
- **ElvUI-aware** — Default is ON unless ElvUI is loaded (which has its own version). A one-time custom dialog asks ElvUI users which to use so duplicates don't appear; preference is remembered
- **Pure visual frames** — No secure-template descendants, so blocks/nameplates stay taint-free

### World Quest Pins
Replaces Blizzard's world quest icons with custom pins on both the world map and zone maps.

- **Reward-category rings** — Gold (yellow), Gear (blue), Reputation (purple), Resources (green), Artifact Power (orange), Profession (tan), PvP (red), Pet (cyan), Other (gray)
- **Time-urgency coloring** — Green (>4h), white (1–4h), yellow (30–60m), red (<30m)
- **Hover tooltip** — Quest title, reward type, time remaining
- **Click to super-track**, right-click to dismiss
- **Per-reward filters** — Toggle each reward category independently
- **Per-faction filters** — Grouped by expansion
- **Persistent watch list** — Manually watched world quests survive login
- **Account-wide completion cache** — Shared across characters

### Chain Guide
A standalone three-pane window for browsing hand-authored quest chains, plus live campaign data straight from Blizzard's `C_CampaignInfo`.

- **Layout** — Categories (left), Chains (middle), Quest Details (right)
- **Browser navigation** — Back / Forward buttons with full history
- **Hand-authored data** — Prerequisite branching overrides Blizzard's API chains where the API is incomplete
- **Cross-character completion** — Tracks completion of every chain across every character on your account
- **Completion-date tooltips** — Hover any quest in a chain to see when (or whether) you completed it
- **Live campaign chapters** — The Midnight Campaign and the max-level *War of Light and Shadow* render from `C_CampaignInfo` chapter-by-chapter, so they stay correct as Blizzard ships content
- **Click-to-waypoint** — Click any quest in a chain to drop a map waypoint and open the world map to it. Uses [TomTom](https://www.curseforge.com/wow/addons/tomtom)'s arrow when installed (recommended), otherwise falls back to Blizzard's built-in waypoint
- **Lazy-built** — The window is constructed on first toggle to keep load times minimal

Currently covers the Midnight expansion: **Eversong Woods**, **Zul'Aman**, **Harandar**, **Voidstorm**, **Arator**, plus the live Midnight Campaign and War of Light and Shadow storylines.

### Quest History
An account-wide log of every quest turn-in across every character. Open with `/eqs history` or the History tab in Options.

- **Five views**:
  - **Quests** — searchable, filterable list (by character, date range, or quest type). Right-click any row to jump to that quest's chain in the Chain Guide
  - **Streak** — current and best daily turn-in streaks across the whole account
  - **Chain Timeline** — every chain you've made progress in with per-quest dates; click to expand; green checkmark on fully-completed chains
  - **Activity** — 13-week heatmap of daily turn-ins
  - **Totals** — gold and XP earned per character, plus biggest single gold/XP rewards
- **One-time backfill** — `Populate from past completions` walks the game's record of completed quests and adds them to history as `(before tracking)` entries
- **Async title fill** — Backfilled entries that show as `Quest #12345` are filled in over a minute or two via server lookups (10/0.3s burst rate, post-drain sweep, `Re-scan names` button)
- **Export** — Copy the currently visible view to your clipboard as plain text
- **Compact storage** — Saved-variables use short field names (`q,t,n,c,z,k,xp,m`) to keep the file small at 5000+ entries

### Map POI Overlays
Custom 22×22 quest pins on zone maps with the Everything-suite branded red ring (#6D0501) around the standard quest icon (gold `?` for turn-ins, white `!` for in-progress). Clicks super-track; right-click dismisses. Layered above Blizzard's own quest POIs.

### Auto-Quest Dialogs
Optional, opt-in handlers for quest gossip and detail screens. Both default OFF.

- **Auto-accept** — accepts on `QUEST_DETAIL`; picks first available quest from gossip menus and the old multi-quest greeting frame
- **Auto-turn-in** — continues on `QUEST_PROGRESS`, finishes on `QUEST_COMPLETE` *only* when there's at most one reward choice (multi-choice screens are left open so the player picks)
- **Pause gates** — hold **Alt** during any interaction to skip both for that one event; declining a quest arms a 10-second lockout so the next gossip doesn't immediately re-offer it
- **Insecure-only APIs** — all touchpoints (`C_GossipInfo.*`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`) are non-protected, so no taint

### Minimap Launcher
LibDataBroker-powered launcher compatible with Titan Panel, ChocolateBar, ElvUI's data-broker bar, and any other LibDataBroker display.

| Click | Action |
|---|---|
| **Left-click** | Open the Blizzard quest log |
| **Shift+Left-click** | Open the Chain Guide |
| **Right-click** | Open Options |
| **Drag** | Reposition around the minimap |

---

## Slash Commands

| Command | Action |
|---|---|
| `/eqs` | Toggle Options |
| `/everythingquests` | Toggle Options (alias) |
| `/eqs chain` | Toggle the Chain Guide window |
| `/eqs history` | Toggle the Quest History window |
| `/eqs session` | Show a recap of your current play session (quests, XP, gold, time) |
| `/eqs whatsnew` | Show the "What's New" summary for the latest update (also `/eqs changes`) |
| `/eqs discover [zone]` | Print quest-line discovery info for the current zone (optional hint) |

### Developer diagnostics

| Command | Action |
|---|---|
| `/eqs trackerdebug` | Dump the tracker's live frame/background/content heights and watched-vs-total quest counts (diagnoses "tracker shrinks" reports) |
| `/eqs scenario` | Dump current scenario/instance API returns (used to confirm two-tier header sources) |
| `/eqs questobj` | Dump every watched quest's objectives, including fallback sources for empty objective lists |
| `/eqs autopopup` | Probe the auto-quest popup API surface (`GetNumAutoQuestPopUps` etc.) |
| `/eqs wqdebug` | Dump every data source the World Quests tracker section consults |
| `/eqs profdebug` | Dump every tracked profession recipe with its required reagent slots, per-slot kind (basic / currency / modifying), held-vs-needed counts and quality-tier count; flags any slot where the all-qualities total differs from the tier-1-only total |
| `/eqs dir` | Diagnose "Get Directions": every waypoint coordinate source for the super-tracked quest, in yards, plus the one the resolver picks |
| `/eqs profile [show \| reset \| mem on \| mem off \| memhog \| auto on \| auto off \| auto list]` | Built-in profiler with hot-path auto-instrument |

---

## Keybindings

Bindable from **Esc → Options → Key Bindings → AddOns → Everything Quests**:

| Action | Default |
|---|---|
| Toggle Options | (unbound) |
| Toggle Chain Guide | (unbound) |

---

## Options

| Tab | Settings |
|---|---|
| **General** | Lock tracker (position & size), hide in combat / in instances / when world map open, auto-track accepted quests, auto-accept / auto-turn-in quests, restore super-tracked quest on relog, **quest icons on nameplates**, world-map quest pins, show / hide minimap button, profile management, reset to defaults |
| **Tracker** | Simplify mode, sort order, per-type filters, current-zone-only mode, watched-only mode, level prefix / zone tag / objective numbers / quest ID / total counts, **usable quest-item buttons**, **hide scroll bar**, **"Quest Discovered!" popups**, quest-complete sound + sound picker, per-section visibility (Profession, World Quests) |
| **World Quests** | Show / hide pins, per-reward filters, per-faction filters |
| **Appearance** | Font picker (LibSharedMedia), font size (8–24pt), background texture picker, background alpha, border, header color, title color override, block spacing, tracker scale |
| **Chain Guide** | Cross-character chain cache stats and reset, debug-overlay toggle |
| **History** | Backfill from past completions, re-scan missing names, wipe history, view stats |

---

## Installation

### From CurseForge
1. Install via the [CurseForge app](https://www.curseforge.com/) or download manually
2. The addon will be placed automatically in your AddOns folder

### Manual Install
1. Download the latest release from the [Releases](https://github.com/wheelbarrel00/EverythingQuests/releases) page
2. Extract the `EverythingQuests` folder into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Restart WoW or type `/reload` if already in-game
4. Enable **Everything Quests** at the character select screen

---

## Dependencies

**Required:** None — Everything Quests is fully standalone. All libraries are bundled.

**Optional:**
- **[TomTom](https://www.curseforge.com/wow/addons/tomtom)** — recommended for the Chain Guide: clicking a quest uses TomTom's on-screen arrow. Without it, Chain Guide waypoints fall back to Blizzard's built-in waypoint system
- [TitanClassic](https://www.curseforge.com/wow/addons/titan-panel-classic), [ChocolateBar](https://www.curseforge.com/wow/addons/chocolatebar), or [ElvUI](https://www.tukui.org/) — display the minimap button on a data-broker bar instead of around the minimap
- **[ElvUI](https://www.tukui.org/)** — ElvUI ships its own nameplate quest icons. When detected, EQ's version defaults off and a one-time dialog asks which to use; choose either, and your pick is remembered. No conflict either way

### Bundled Libraries

LibStub, CallbackHandler-1.0, AceDB-3.0, AceEvent-3.0, AceTimer-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibMapPinHandler.

---

## Technical Details

| Metric | Value |
|---|---|
| Interface version | 120001, 120005, 120007 (Midnight 12.0) |
| SavedVariables | `EverythingQuestsDB` (account), `EverythingQuestsCharDB` (character), `EverythingQuestsChainCache` (account), `EverythingQuestsHistory` (account) |
| API compliance | Display-only by default — no taint. Auto-accept / auto-turn-in are opt-in and use insecure-only APIs (`C_GossipInfo`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`); Alt pauses them |

### Architecture
```
EverythingQuests/
├── EverythingQuests.toc              # Addon manifest, module load order
├── Bindings.xml                      # Keybinding declarations
├── Core/                             # Init, DB, Events, Profiler, Cache,
│                                     #   Util, Media, Dialog
├── Locales/                          # enUS, frFR, ruRU, koKR (all full)
├── Libs/                             # Bundled libraries
├── Modules/
│   ├── Minimap/                      # LibDataBroker launcher
│   ├── Tracker/                      # Custom quest tracker (Frame, Blocks,
│   │                                 #   Scenario, Filters, Sort, Visibility,
│   │                                 #   ItemButtons, AutoComplete,
│   │                                 #   AutoQuestPopup, QuestSound,
│   │                                 #   DragDrop, Events, Profession,
│   │                                 #   Endeavors, TaxiHighlight,
│   │                                 #   SuperTrackPersist)
│   ├── Nameplates/                   # Nameplate quest icons (QuestIcons.lua)
│   ├── WorldQuests/                  # World/zone map pins
│   ├── ChainGuide/                   # Chain browser window + campaign source
│   ├── MapPOI/                       # Quest POI overlays
│   ├── History/                      # Quest History (Recorder + Frame)
│   ├── QuestAuto.lua                 # Auto-accept / auto-turn-in handlers
│   └── WhatsNew.lua                  # One-time popup for new releases
├── Data/
│   └── QuestChains/                  # Hand-authored Midnight chain data
└── Options/                          # General, Tracker, World Quests,
                                      #   Appearance, Chain Guide, History tabs
```

Modules register into Core subsystems at load time and listen for events through a shared callback dispatcher, so multiple modules can safely react to the same WoW event without stepping on each other. `Core/Dialog.lua` provides a custom confirmation/prompt frame used in place of Blizzard's `StaticPopupDialogs` for every EQ-defined dialog, so EQ can't taint Blizzard's shared Quit/Logout popups.

---

## Localization

Everything Quests ships full, bundled translations — on a matching game client the interface displays in that language automatically, and anything untranslated falls back to English:

- **French (frFR)** — complete, by **Zox**
- **Russian (ruRU)** — complete, by **Malevi4**
- **Korean (koKR)** — complete, by **labrie75**

Other game clients fall back to English. Contributions for more languages are welcome, see [Contributing](#contributing).

---

## Contributing

Contributions are welcome! If you'd like to help:

1. **Fork** the repo
2. **Create a branch** for your feature (`git checkout -b feature/my-feature`)
3. **Commit** your changes (`git commit -m "Add my feature"`)
4. **Push** to your branch (`git push origin feature/my-feature`)
5. Open a **Pull Request**

### Reporting Bugs

Please use the [GitHub Issues](https://github.com/wheelbarrel00/EverythingQuests/issues) tab. Include:
- Your WoW client version and region
- Steps to reproduce
- Any error messages from `/console scriptErrors 1`
- Screenshot if applicable

---

## Roadmap

- [ ] Full chain coverage beyond Midnight (TWW, Dragonflight, older expansions)
- [ ] Complete localization for non-enUS locales (currently enUS only for verb classification in nameplate quest icons)
- [ ] WoWInterface and Wago publishing

---

## License

This project is licensed under the [MIT License](LICENSE).

---

## Acknowledgments

- Built by Wheelbarrel00
- Packaged and deployed with **[BigWigsMods/packager](https://github.com/BigWigsMods/packager)**
- Minimap button powered by **[LibDBIcon](https://www.curseforge.com/wow/addons/libdbicon-1-0)** and **[LibDataBroker](https://www.curseforge.com/wow/addons/libdatabroker-1-1)**
- Font/texture picker powered by **[LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)**
- WoW API references from **[Warcraft Wiki](https://warcraft.wiki.gg)**

---

<p align="center">
  <sub>Made for the Midnight expansion · 2026</sub>
</p>
