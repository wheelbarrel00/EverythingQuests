<h1 align="center">Everything Quests</h1>
<p align="center">
  <strong>A unified replacement for the Blizzard quest experience — objective tracker, world-map overlays, nameplate quest icons, an account-wide quest history, and a Midnight chain guide.</strong>
</p>
<p align="center">
  <a href="https://ko-fi.com/wheelbarrel00"><img src="https://img.shields.io/badge/Support-Ko--fi-FF5E5B?style=flat-square&logo=ko-fi" alt="Support on Ko-fi" /></a>
  <a href="https://www.paypal.biz/wheelbarrel00"><img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal" alt="Donate with PayPal" /></a>
  <a href="https://github.com/wheelbarrel00/EverythingQuests/releases"><img src="https://img.shields.io/github/v/release/wheelbarrel00/EverythingQuests?color=6D0501&label=Version&style=flat-square" alt="Version" /></a>
  <img src="https://img.shields.io/badge/WoW-Midnight%2012.0-8B0000?style=flat-square" alt="WoW Version" />
  <img src="https://img.shields.io/badge/Interface-120100-333333?style=flat-square" alt="Interface" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wheelbarrel00/EverythingQuests?style=flat-square&color=333333" alt="License" /></a>
</p>

---

## Overview

Everything Quests is a complete replacement for Blizzard's quest tracking and quest log experience for **World of Warcraft: Midnight**.

1. An on-screen **objective tracker** that replaces the default ObjectiveTrackerFrame, provided by [EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker) and installed automatically alongside this addon
2. **Nameplate Quest Icons** — `!` + remaining count/percent on objective mobs in the 3D world
3. Interactive **World Quest pins** on the world map and zone maps, plus a docked World Quests panel
4. A standalone **Chain Guide** window for browsing Midnight quest chains
5. An account-wide **Quest History** log with five views and a backfill of past completions
6. Branded **Quest POI** overlays on zone maps
7. Optional **auto-accept / auto-turn-in** for quest dialogs (Alt to pause)

Open Options with **`/eqs`**, from the minimap button, from the Everything Quests icon on the tracker, or via **Game Menu → Options → AddOns → Everything Quests**.

---

## About the tracker

As of **v1.38.0** the objective tracker lives in its own addon, **[EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker)**. It is a required dependency and your addon manager installs it for you, so there is nothing extra to set up.

Nothing was lost in the move. Existing users keep their position, size, fonts, colors, section order, filters and sorting, along with pinned quests, hidden quests, collapsed sections and saved world quest watches on every character — all carried across automatically on first login.

**Why it was split.** The tracker is useful on its own, and there is now one copy of that code instead of two, so a tracker fix reaches everyone at once.

**What this means day to day:**

| Want | Where |
|---|---|
| **Tracker settings** | The cogwheel at the top right of the tracker, or `/eqot` |
| **Everything Quests settings** | The Everything Quests logo beside the cogwheel, the minimap button, or `/eqs` |
| **Chain Guide** | The chain icon on the tracker, or `/eqs chain` |

Each of the two Everything Quests icons on the tracker can be switched off under `/eqs` → General. Everything Quests also adds **Get Directions** to a quest's right-click menu on the tracker.

If the tracker is missing, check that EQ Objective Tracker is enabled in your AddOns list. `/eqot status` prints what the tracker is doing and is the most useful thing to include in a bug report.

---

## Features

### Nameplate Quest Icons
Quest-objective enemies show EQ's logo (kill objectives get a skull, talk-to objectives a chat bubble, use-item objectives the quest's item icon) right on their nameplate, along with the remaining count or percent.

- **Detection** — Two-source join: an `activeQuests` cache built from `C_QuestLog.GetQuestObjectives` (objectives keyed by display text → `{value, type, isPercent, itemTexture}`, where `value` is the *remaining* amount) joined to each nameplate via a `C_TooltipInfo.GetUnit` line-type scan (`QuestTitle` + `QuestObjective` lines matched against the cache, with matched objectives de-duplicated by entry so a party-mate's identical line can't double-count one of yours)
- **Cached per GUID** — Tooltip scans only run when a new mob appears on a plate or quest log changes, never per frame
- **Midnight-safe** — Guards all game-returned strings/GUIDs with `issecretvalue` so restricted values can't throw
- **ElvUI-aware** — Default is ON unless ElvUI is loaded (which has its own version). A one-time custom dialog asks ElvUI users which to use so duplicates don't appear; preference is remembered
- **Pure visual frames** — No secure-template descendants, so nameplates stay taint-free

### World Quest Pins
Replaces Blizzard's world quest icons with custom pins on both the world map and zone maps.

- **Reward-category rings** — Gold (yellow), Gear (blue), Reputation (purple), Resources (green), Artifact Power (orange), Profession (tan), PvP (red), Pet (cyan), Other (gray)
- **Time-urgency coloring** — Green (>4h), white (1–4h), yellow (30–60m), red (<30m)
- **Hover tooltip** — Quest title, reward type, time remaining
- **Click to super-track**, right-click to dismiss
- **Docked panel** — A full-height World Quests list beside the world map, opened by a side tab styled to match Blizzard's or ElvUI's frame
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

Currently covers the Midnight expansion: **Eversong Woods**, **Zul'Aman**, **Harandar**, **Arator**, **Voidstorm**, **The Sunstrider Omnium** and **Void Acropolis**, plus the live **Midnight Campaign**, **The War of Light and Shadow** and **The Curse of Ula'tek** storylines.

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
- **Backups** — History is snapshotted so an empty or missing log can be restored automatically

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
| `/eqs about` | Open Options on the About tab |
| `/eqs session` | Show a recap of your current play session (quests, XP, gold, time) |
| `/eqs whatsnew` | Show the "What's New" summary for the latest update (also `/eqs changes`) |
| `/eqs whatsnew chat` | Print the same summary to chat instead of the popup |
| `/eqs discover [zone]` | Print quest-line discovery info for the current zone (optional hint) |

Tracker settings have their own panel and commands — see `/eqot` and `/eqot status`.

### Developer diagnostics

| Command | Action |
|---|---|
| `/eqs scenario` | Dump current scenario/instance API returns |
| `/eqs questobj` | Dump every watched quest's objectives, including fallback sources for empty objective lists |
| `/eqs questzone` | Dump every quest's header, on-map state and zone IDs, to diagnose "only current zone" filtering |
| `/eqs autopopup` | Probe the auto-quest popup API surface (`GetNumAutoQuestPopUps` etc.) |
| `/eqs wqdebug` | Dump every data source the World Quests code consults |
| `/eqs dir` | Diagnose "Get Directions": every waypoint coordinate source for the super-tracked quest, in yards, plus the one the resolver picks |
| `/eqs chaindump` | Dump the loaded Chain Guide categories and chains |
| `/eqs campdump` | Dump Blizzard's campaign data as EQ reads it |
| `/eqs campfind [filter]` | Find a campaign by ID or name, with no filter to list them all |
| `/eqs zonedump [zone]` | Dump the zone-progress routing table and its live counts |
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
| **General** | Open Tracker Settings, Everything Quests and Chain Guide icons on the tracker, auto-accept / auto-turn-in quests, restore super-tracked quest on relog, **quest icons on nameplates**, world-map quest pins, show / hide minimap button, update notice style, options window scale, profile management, reset to defaults |
| **World Quests** | Show / hide pins, per-reward filters, per-faction filters, docked map panel |
| **Chain Guide** | Map pins and waypoints, cross-character chain cache stats and reset, prune stale entries |
| **History** | Backfill from past completions, re-scan missing names, restore from backup, wipe history, view stats |
| **About** | Version, changelog, credits, and links |

Tracker and appearance settings (fonts, colors, sorting, filters, section order, sizing) live in EQ Objective Tracker's own panel — the button at the top of the General tab opens it, or type `/eqot`.

---

## Installation

### From CurseForge
1. Install via the [CurseForge app](https://www.curseforge.com/) or download manually
2. **EQ Objective Tracker is pulled down automatically** as a required dependency

### Manual Install
1. Download the latest release from the [Releases](https://github.com/wheelbarrel00/EverythingQuests/releases) page
2. Download **[EQ Objective Tracker](https://github.com/wheelbarrel00/EQObjectiveTracker/releases)** as well — Everything Quests will not load without it
3. Extract both folders into:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
4. Restart WoW or type `/reload` if already in-game
5. Enable **Everything Quests** and **EQ Objective Tracker** at the character select screen

---

## Dependencies

**Required:** **[EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker)** — provides the objective tracker. Addon managers install it automatically; a manual install needs both folders. All other libraries are bundled.

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
| Interface version | 120100, 120007, 120005 (Midnight 12.0) |
| SavedVariables | `EverythingQuestsDB` (account), `EverythingQuestsCharDB` (character), `EverythingQuestsChainCache` (account), `EverythingQuestsHistory` (account), `EverythingQuestsHistoryBackups` (account) |
| API compliance | Display-only by default — no taint. Auto-accept / auto-turn-in are opt-in and use insecure-only APIs (`C_GossipInfo`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`); Alt pauses them |

### Architecture
```
EverythingQuests/
├── EverythingQuests.toc              # Addon manifest, module load order
├── Bindings.xml                      # Keybinding declarations
├── Core/                             # Init, DB, Events, Profiler, Cache, Util,
│                                     #   Media, Dialog, Changelog, QuestRewards
├── Locales/                          # enUS, frFR, ruRU, koKR (generated)
├── Libs/                             # Bundled libraries
├── Modules/
│   ├── Minimap/                      # LibDataBroker launcher
│   ├── Nameplates/                   # Nameplate quest icons (QuestIcons.lua)
│   ├── WorldQuests/                  # World/zone map pins, docked panel
│   ├── ChainGuide/                   # Chain browser window + campaign source
│   ├── MapPOI/                       # Quest POI overlays
│   ├── History/                      # Quest History (Recorder + Frame)
│   ├── QuestAuto.lua                 # Auto-accept / auto-turn-in handlers
│   ├── TrackerBridge.lua             # Puts EQ's icons and menu entry onto
│   │                                 #   EQ Objective Tracker via its public API
│   └── WhatsNew.lua                  # One-time popup for new releases
├── Data/
│   └── QuestChains/                  # Hand-authored Midnight chain data
└── Options/                          # General, World Quests, Chain Guide,
                                      #   History, About tabs
```

Modules register into Core subsystems at load time and listen for events through a shared callback dispatcher, so multiple modules can safely react to the same WoW event without stepping on each other. `Core/Dialog.lua` provides a custom confirmation/prompt frame used in place of Blizzard's `StaticPopupDialogs` for every EQ-defined dialog, so EQ can't taint Blizzard's shared Quit/Logout popups.

`Modules/TrackerBridge.lua` is the seam to EQ Objective Tracker. It reaches the tracker only through that addon's documented API and guards every call, so a mismatched version degrades quietly instead of erroring.

---

## Localization

Everything Quests ships bundled translations — on a matching game client the interface displays in that language automatically, and anything untranslated falls back to English:

- **French (frFR)** — by **Zox**
- **Russian (ruRU)** — by **Malevi4**
- **Korean (koKR)** — by **labrie75**

Translations for Everything Quests and EQ Objective Tracker are maintained together in **[EverythingLocales](https://github.com/wheelbarrel00/EverythingLocales)**. The `Locales/` files in this repo are generated from it, so translation pull requests belong there rather than here. Contributions for more languages are very welcome.

---

## Contributing

Contributions are welcome! If you'd like to help:

1. **Fork** the repo
2. **Create a branch** for your feature (`git checkout -b feature/my-feature`)
3. **Commit** your changes (`git commit -m "Add my feature"`)
4. **Push** to your branch (`git push origin feature/my-feature`)
5. Open a **Pull Request**

Translations are the exception — those go to [EverythingLocales](https://github.com/wheelbarrel00/EverythingLocales), which feeds both addons.

### Reporting Bugs

Please use the [GitHub Issues](https://github.com/wheelbarrel00/EverythingQuests/issues) tab. Include:
- Your WoW client version and region
- Steps to reproduce
- Any error messages from `/console scriptErrors 1`
- Screenshot if applicable
- For anything involving the tracker, the output of `/eqot status`

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
