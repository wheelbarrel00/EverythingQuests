<h1 align="center">Everything Quests</h1>
<p align="center">
  <strong>A unified replacement for the Blizzard quest experience — objective tracker, world-map overlays, nameplate quest icons, an account-wide quest history, and a Midnight chain guide. Runs on retail, Classic Era and Burning Crusade Classic.</strong>
</p>
<p align="center">
  <a href="https://ko-fi.com/wheelbarrel00"><img src="https://img.shields.io/badge/Support-Ko--fi-FF5E5B?style=flat-square&logo=ko-fi" alt="Support on Ko-fi" /></a>
  <a href="https://www.paypal.biz/wheelbarrel00"><img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal" alt="Donate with PayPal" /></a>
  <a href="https://discord.gg/vm8K2WfQUE"><img src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Join our Discord" /></a>
  <a href="https://github.com/wheelbarrel00/EverythingQuests/releases"><img src="https://img.shields.io/github/v/release/wheelbarrel00/EverythingQuests?color=6D0501&label=Version&style=flat-square" alt="Version" /></a>
  <img src="https://img.shields.io/badge/WoW-Midnight%2012.1-8B0000?style=flat-square" alt="WoW Retail" />
  <img src="https://img.shields.io/badge/WoW-Classic%20Era%201.15-C69B6D?style=flat-square" alt="WoW Classic Era" />
  <img src="https://img.shields.io/badge/WoW-Burning%20Crusade%202.5-A330C9?style=flat-square" alt="WoW Burning Crusade Classic" />
  <img src="https://img.shields.io/badge/Interface-120100%20%7C%2020506%20%7C%2011509-333333?style=flat-square" alt="Interface" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wheelbarrel00/EverythingQuests?style=flat-square&color=333333" alt="License" /></a>
</p>

---

## Overview

Everything Quests is a complete replacement for Blizzard's quest tracking and quest log experience for **World of Warcraft: Midnight**, with limited support for **Classic Era** and **Burning Crusade Classic**.

1. An on-screen **objective tracker** that replaces the default ObjectiveTrackerFrame, provided by [EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker) and installed automatically alongside this addon
2. **Nameplate Quest Icons** — `!` + remaining count/percent on objective mobs in the 3D world
3. Interactive **World Quest pins** on the world map and zone maps, plus a docked World Quests panel
4. A standalone **Chain Guide** window for browsing Midnight quest chains
5. An account-wide **Quest History** log with six views and a backfill of past completions
6. Branded **Quest POI** overlays on zone maps, and on Classic, objective spawn markers on both the world map and the minimap
7. A **Quest Browser** on Classic, for looking up almost any quest in the game before you accept it
8. **Quest progress on game tooltips** — a bag item names the quest that wants it and how many are still missing
9. **Coordinate readouts** on the world map and under the minimap, for the cursor and for your own position
10. Optional **auto-accept / auto-turn-in** for quest dialogs (Alt to pause)

Open Options with **`/eqs`**, from the minimap button, from the Everything Quests icon on the tracker, or via **Game Menu → Options → AddOns → Everything Quests**.

---

## Classic support

Everything Quests has run on **Classic Era (1.15)** since v1.39.0 and on **Burning Crusade Classic (2.5)** since v1.41.0. Support is deliberately partial: what ships is what was measured working on a live client, not the whole addon.

Era and TBC were measured identical across every game API the addon reads, so one implementation covers both. They differ only in their generated dataset — TBC ships its own, because Era quest data has nothing for Outland or for the Blood Elf and Draenei starting zones. Each flavor's TOC lists exactly one set; they define the same globals and are alternatives, never companions.

**Working on Classic Era and TBC**

- **Objective markers** on the world map and the minimap, drawn from a generated coordinate database rather than from the client, which exposes no quest coordinates at all
- **Objective kind icons** — kill, loot, or interact — and dungeon objectives marked at the dungeon entrance
- **Turn-in markers** at every location a finished quest can be handed in, and **markers for quests you can pick up**, gated on level, race, class, prerequisites, reputation, completion, and whether a holiday quest's world event is actually running
- **Nameplate quest icons**, resolved from the creature ID in the unit GUID, since a Classic unit tooltip carries no quest data
- **The Quest Browser** — look up almost any quest in the game, including ones never picked up, with its level, race and class requirements, start and turn-in locations, prerequisites, and the reason it is not available yet. `/eqs quests`, or right-click a gold marker
- **Quest progress on tooltips** — a bag item names the quest that wants it and what is still missing, and on Classic an enemy names the quest it counts toward, which the client there never does
- **Coordinates** on the world map and under the minimap, with a slider for how many decimals to show
- **Two more ways to quiet a busy map** on top of the filters above, both off by default: leave out markers for quests you have untracked, and fade markers sitting on top of your own position
- **Auto-accept / auto-turn-in**, the **minimap button**, the **tracker bridge**, the **focus arrow**, and the **`/eqs`** options window (General and About tabs)
- All bundled locales

**Retail-only**

The **Chain Guide** (`C_QuestLine` and `C_CampaignInfo` are absent, and the authored chain data is Midnight content), the **World Quests** panel (no world quests exist), and **Quest History** (`GetTitleForQuestID` and `RequestLoadQuestByID` are both absent, so a backfilled row could never resolve its own name).

Each omission is declared by name in `EverythingQuests_Vanilla.toc` and `EverythingQuests_TBC.toc` with a `# check-toc: omit` directive, and `tools/check_toc.py` errors if one goes stale.

**`/eqsprobe`** prints what the addon actually found on the running client and is the single most useful thing to attach to a Classic bug report.

---

## About the tracker

As of **v1.38.0** the objective tracker lives in its own addon, **[EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker)**. It is a required dependency and your addon manager installs it for you, so there is nothing extra to set up. It publishes for Classic Era and Burning Crusade Classic as well.

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

- **Detection on retail** — Two-source join: an `activeQuests` cache built from `C_QuestLog.GetQuestObjectives` (objectives keyed by display text → `{value, type, isPercent, itemTexture}`, where `value` is the *remaining* amount) joined to each nameplate via a `C_TooltipInfo.GetUnit` line-type scan (`QuestTitle` + `QuestObjective` lines matched against the cache, with matched objectives de-duplicated by entry so a party-mate's identical line can't double-count one of yours)
- **Detection on Classic** — the tooltip route does not exist there, so the creature ID is read from the unit GUID and matched against a generated `questID -> creatures` table, inverted at runtime over the quest log only
- **Cached per GUID** — Tooltip scans only run when a new mob appears on a plate or quest log changes, never per frame
- **Midnight-safe** — Guards all game-returned strings/GUIDs with `issecretvalue` so restricted values can't throw
- **ElvUI-aware** — Default is ON unless ElvUI is loaded (which has its own version). A one-time custom dialog asks ElvUI users which to use so duplicates don't appear; preference is remembered
- **Pure visual frames** — No secure-template descendants, so nameplates stay taint-free

### World Quest Pins
Replaces Blizzard's world quest icons with custom pins on both the world map and zone maps. Retail only.

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
A standalone three-pane window for browsing hand-authored quest chains, plus live campaign data straight from Blizzard's `C_CampaignInfo`. Retail only.

- **Layout** — Categories (left), Chains (middle), Quest Details (right)
- **Browser navigation** — Back / Forward buttons with full history
- **Hand-authored overlays** — Prerequisite branching overrides Blizzard's API chains where the API is incomplete. Branching is authored only, never inferred from quest-type APIs
- **Cross-character completion** — Tracks completion of every chain across every character on your account
- **Completion-date tooltips** — Hover any quest in a chain to see when (or whether) you completed it
- **Live campaign chapters** — Campaigns render from `C_CampaignInfo` chapter by chapter, so a new patch chapter appears without a data update
- **Click-to-waypoint** — Click any quest in a chain to drop a map waypoint and open the world map to it. Uses [TomTom](https://www.curseforge.com/wow/addons/tomtom)'s arrow when installed (recommended), otherwise falls back to Blizzard's built-in waypoint
- **Lazy-built** — The window is constructed on first toggle to keep load times minimal

Currently covers the Midnight expansion: **Eversong Woods**, **Zul'Aman**, **Harandar**, **Arator**, **Voidstorm**, **The Sunstrider Omnium**, **Void Acropolis** and **The Coiled Isle**, plus the live **Midnight Campaign**, **The War of Light and Shadow** and **The Curse of Ula'tek** storylines.

### Quest History
An account-wide log of every quest turn-in across every character. Open with `/eqs history` or the History tab in Options. Retail only.

- **Six views**:
  - **Quests** — searchable, filterable list (by character, date range, or quest type). Right-click any row to jump to that quest's chain in the Chain Guide
  - **This Session** — a live recap of the current play session: quests, XP, gold, time played, quests per hour, level-ups
  - **Streak** — current and best daily turn-in streaks across the whole account
  - **Chain Timeline** — every chain you've made progress in with per-quest dates; click to expand; green checkmark on fully-completed chains
  - **Activity** — 13-week heatmap of daily turn-ins
  - **Stats** — gold and XP earned per character plus biggest single rewards, with a **Trends** toggle that charts quests, XP and gold over time, daily or weekly, account-wide or per character
- **One-time backfill** — `Populate from past completions` walks the game's record of completed quests and adds them to history as `(before tracking)` entries
- **Async title fill** — Backfilled entries that show as `Quest #12345` are filled in over a minute or two via server lookups (10/0.3s burst rate, post-drain sweep, `Re-scan names` button)
- **Export** — Copy the currently visible view to your clipboard as plain text
- **Compact storage** — Saved-variables use short field names (`q,t,n,c,z,k,xp,m`) to keep the file small at 5000+ entries
- **Backups** — History is snapshotted on logout so an empty or missing log can be restored automatically

### Map POI Overlays
Custom quest pins on zone maps. On retail the icon carries the Everything-suite branded red ring (#6D0501); on Classic the ring starts off, because a zone there can draw hundreds of pins. Clicks super-track, or set a TomTom waypoint where the game has no super-track; right-click dismisses.

- **Aggregated tooltips** — hovering lists every quest whose nearest pin is within reach, nearest first, so overlapping pins stop hiding each other. The reach is measured in pin widths, so it stays a constant on-screen distance at any zoom. The tooltip carries the quest level, its objectives and its experience reward
- **Fixed size at every zoom** — `SetScalingLimits(1, s, s)` collapses Blizzard's zoom lerp to a constant, with a per-map-type factor so continent and world maps draw smaller. A scale slider and a per-quest pin limit live under `/eqs` → General
- **On Classic** — in-progress pins come from `Data/QuestSpawns_Classic.lua` and carry objective art rather than a `!`, marking every clustered location a quest can be advanced, with a per-quest minimum separation applied at read time so a low limit still spreads across the zone
- **Turn-in pins on Classic** — a finished quest is placed from `Data/QuestTurnIn_Classic.lua`, at every map where it can be handed in. That table is authoritative once it knows a quest, because 475 quests hand in on a different map from their objective
- **Available quest pins on Classic** — gold `!` markers for quests you can pick up but have not accepted, from `Data/QuestAvailable_Classic.lua`, gated on level, race, class, prerequisites, reputation and completion. Pins merge by location rather than by quest
- **Holiday quests follow their season** — a Lunar Festival or Brewfest quest is pinned only while that world event is running, from `Data/QuestHolidays_Classic.lua`. On by default. The one date that moves each year fails open, so a year the table does not list shows those quests rather than hiding them
- **Filters for a busy map**, all under `/eqs` → General → Map — leave out dungeon, repeatable or profession quests, hide quests below your level using the game's own gray threshold, or hide the ones it colors red for you. That last one is off by default, because a red quest is still worth knowing about if you mean to come back for it

### Minimap Objective Pins
The same objective markers on the minimap, for the zone you are standing in, powered by HereBeDragons-Pins. Classic only, and keyed on `C_Map.GetBestMapForUnit` rather than the open world map. Pins are hover-only so clicks pass through to the minimap underneath.

### Quest Browser
Classic Era and Burning Crusade Classic only. A search-and-details window over EQ's own generated quest tables, answering the one thing a Classic client cannot: what a quest is before you have ever accepted it.

- **Search** by name substring, by quest ID, or `"quoted"` for a whole-title match. The scan runs against the shipped English titles, because the client can only name a quest it has already seen; the row you see uses the client's own wording where it knows it
- **Details** — quest level, required level, race and class gates, category, every map it starts / has objectives / turns in on, prerequisites (any-of vs all-of), follow-ups, exclusions, and skill and reputation gates
- **The reason it is unavailable** comes from `AvailableQuests:Explain`, the *same* gate that decides which gold markers are drawn. There is deliberately one implementation — a second copy would let the window and the map disagree while both looked right
- **Clickable throughout** — a location opens the world map there and sets a TomTom waypoint; a prerequisite or follow-up navigates to that quest. References the data cannot describe render as plain text rather than a dead link
- **Entry points** — `/eqs quests [text]`, the button under `/eqs` > General, or right-clicking a gold available-quest marker, which previously did nothing
- **Coverage is not total.** It reads the `names`/`gates` tables (3,794 Era / 5,652 TBC) while the coordinate tables cover more, so 357 Era and 508 TBC quests EQ pins on the map are not in the browser
- `/eqsprobe questbrowser` reports the data, a live query, the player's zone, one full decoded record, and whether the browser and the map pins agree

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
| `/eqs quests [text]` | Open the Quest Browser, optionally with a search. Classic Era and TBC only |
| `/eqs history` | Toggle the Quest History window |
| `/eqs about` | Open Options on the About tab |
| `/eqs session` | Show a recap of your current play session (quests, XP, gold, time) |
| `/eqs whatsnew` | Show the "What's New" summary for the latest update (also `/eqs changes`) |
| `/eqs whatsnew chat` | Print the same summary to chat instead of the popup |
| `/eqs discover [zone]` | Print quest-line discovery info for the current zone (optional hint) |
| `/eqsprobe [section]` | Print what EQ found on the running client. Ships on every flavor |

On Classic Era and Burning Crusade Classic the Chain Guide, History and session commands resolve to nothing, since those subsystems are not loaded there. `/eqs quests` is the reverse: it is Classic-only, because retail already opens any quest in Blizzard's own quest log.

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
| `/eqs campdump` | Dump Blizzard's campaign data as EQ reads it, with quest IDs per chapter |
| `/eqs campfind [filter]` | Find a campaign by ID or name, with no filter to list them all. Prints a paste-ready `_Index.lua` line for anything unregistered |
| `/eqs zonedump [zone]` | Dump the zone-progress routing table and its live counts |
| `/eqs profile [show \| reset \| mem on \| mem off \| memhog \| auto on \| auto off \| auto list]` | Built-in profiler with hot-path auto-instrument |

`/eqsprobe` sections: `media`, `map`, `poi`, `pins`, `minimap`, `available`, `questbrowser`, `mappoi`, `flare`, `quest`, `port`, `tooltip`, `xp`, `events`, `ui`, `misc`. No argument runs all except `tooltip`, `mappoi`, `flare` and `xp`, each of which needs something set up first — and `flare` and `xp` both mutate state, so `/reload` after using `flare`.

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
| **General** | Open Tracker Settings, Everything Quests and Chain Guide icons on the tracker, auto-accept / auto-turn-in quests, restore super-tracked quest on relog, **quest icons on nameplates**, world-map quest pins, pin scale, objective pins per quest, minimap objective pins, **map filters** (dungeon, repeatable, profession, below your level, above your level, holiday quests out of season), show / hide minimap button, update notice style, options window scale, profile management, reset to defaults |
| **World Quests** | Show / hide pins, per-reward filters, per-faction filters, docked map panel |
| **Chain Guide** | Map pins and waypoints, cross-character chain cache stats and reset, prune stale entries |
| **History** | Backfill from past completions, re-scan missing names, restore from backup, wipe history, view stats |
| **About** | Version, changelog, credits, and links |

Every section gates on the subsystem it drives rather than on a flavor check, so on both Classic flavors only General and About appear and no control is left inert. Tracker and appearance settings live in EQ Objective Tracker's own panel — the button at the top of the General tab opens it, or type `/eqot`.

---

## Installation

### From CurseForge
1. Install via the [CurseForge app](https://www.curseforge.com/) or download manually
2. **EQ Objective Tracker is pulled down automatically** as a required dependency

### Manual Install
1. Download the latest release from the [Releases](https://github.com/wheelbarrel00/EverythingQuests/releases) page
2. Download **[EQ Objective Tracker](https://github.com/wheelbarrel00/EQObjectiveTracker/releases)** as well — Everything Quests will not load without it
3. Extract both folders into your client's AddOns directory:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   World of Warcraft/_classic_era_/Interface/AddOns/
   ```
4. Restart WoW or type `/reload` if already in-game
5. Enable **Everything Quests** and **EQ Objective Tracker** at the character select screen

---

## Dependencies

**Required:** **[EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker)** — provides the objective tracker. Addon managers install it automatically; a manual install needs both folders. All other libraries are bundled.

**Optional:**
- **[TomTom](https://www.curseforge.com/wow/addons/tomtom)** — recommended on retail for the Chain Guide, and effectively required on Classic: clicking a quest or an objective marker uses TomTom's on-screen arrow, and Classic has no built-in waypoint system to fall back on
- [TitanClassic](https://www.curseforge.com/wow/addons/titan-panel-classic), [ChocolateBar](https://www.curseforge.com/wow/addons/chocolatebar), or [ElvUI](https://www.tukui.org/) — display the minimap button on a data-broker bar instead of around the minimap
- **[ElvUI](https://www.tukui.org/)** — ElvUI ships its own nameplate quest icons. When detected, EQ's version defaults off and a one-time dialog asks which to use; choose either, and your pick is remembered. No conflict either way

### Bundled Libraries

LibStub, CallbackHandler-1.0, AceDB-3.0, AceEvent-3.0, AceTimer-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibMapPinHandler, and HereBeDragons-2.0 / HereBeDragons-Pins-2.0.

HereBeDragons is listed by the Classic TOC only. HBD-Pins calls `WorldMapFrame:AddDataProvider` at file scope on the real map canvas, which is precisely what LibMapPinHandler's shadow canvas exists to keep EQ away from on retail, where the AreaPOI taint crash is live. Retail safety rests on the file not being listed, not on `LibStub` returning nil.

---

## Technical Details

| Metric | Value |
|---|---|
| Interface version | 120100, 120007, 120005 (Midnight 12.1), 20506 (Burning Crusade Classic 2.5) and 11509 (Classic Era 1.15) |
| SavedVariables | `EverythingQuestsDB` (account), `EverythingQuestsCharDB` (character), `EverythingQuestsChainCache` (account), `EverythingQuestsHistory` (account), `EverythingQuestsHistoryBackups` (account) |
| API compliance | Display-only by default — no taint. Auto-accept / auto-turn-in are opt-in and use insecure-only APIs (`C_GossipInfo`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`); Alt pauses them |

### Architecture
```
EverythingQuests/
├── EverythingQuests.toc              # Retail manifest, module load order
├── EverythingQuests_Vanilla.toc      # Classic Era manifest, omissions declared inline
├── EverythingQuests_TBC.toc          # Burning Crusade Classic manifest, same shape
├── Bindings.xml                      # Keybinding declarations
├── Core/                             # Init, Compat, DB, Events, Profiler, Cache, Util,
│                                     #   Media, Dialog, QuestRewards, Changelog, FlavorProbe
├── Locales/                          # enUS plus the bundled translations (generated)
├── Libs/                             # Bundled libraries
├── Modules/
│   ├── Minimap/                      # LibDataBroker launcher + Classic objective pins
│   ├── Nameplates/                   # Nameplate quest icons (QuestIcons.lua)
│   ├── WorldQuests/                  # World/zone map pins, docked panel
│   ├── ChainGuide/                   # Chain browser window + campaign source
│   ├── MapPOI/                       # Quest POI overlays, Classic spawn markers,
│   │                                 #   available-quest pins, the holiday season gate
│   ├── QuestBrowser/                 # Classic quest lookup window (Data + Frame)
│   ├── Tooltips/                     # Quest progress on item and unit tooltips
│   ├── History/                      # Quest History (Recorder + Frame + Session)
│   ├── MapCoords.lua                 # Coordinates on the world map and minimap
│   ├── QuestArrow.lua                # Shared TomTom waypoint slot
│   ├── QuestAuto.lua                 # Auto-accept / auto-turn-in handlers
│   ├── TrackerBridge.lua             # Puts EQ's icons and menu entry onto
│   │                                 #   EQ Objective Tracker via its public API
│   └── WhatsNew.lua                  # One-time popup for new releases
├── Data/
│   ├── QuestChains/                  # Hand-authored Midnight chain data
│   ├── QuestCoords_*.lua             # Generated: questID -> single waypoint
│   ├── QuestSpawns_*.lua             # Generated: questID -> every objective location
│   ├── QuestNPCs_*.lua               # Generated: questID -> creatures that advance it
│   ├── QuestTurnIn_*.lua             # Generated: questID -> every hand-in location
│   ├── QuestAvailable_*.lua          # Generated: where a quest starts, plus its gates
│   ├── QuestCategory_*.lua           # Generated: dungeon / repeatable / class / profession
│   └── QuestHolidays_*.lua           # Generated: questID -> its world event
│                                     #   Each has a _Classic and a _TBC variant. A TOC
│                                     #   lists exactly one; they define the same globals
├── tools/                            # TOC and locale-format gates, plus their own
│                                     #   self-tests, and build_questcoords.lua
└── Options/                          # General, World Quests, Chain Guide,
                                      #   History, About tabs
```

Modules register into Core subsystems at load time and listen for events through a shared callback dispatcher, so multiple modules can safely react to the same WoW event without stepping on each other. `Core/Events.lua` wraps `RegisterEvent` in a `pcall` and records refused event names, because `RegisterEvent` raises rather than no-ops on an event the client does not know — four of EQ's registered events do exactly that on Classic. `Core/Dialog.lua` provides a custom confirmation/prompt frame used in place of Blizzard's `StaticPopupDialogs` for every EQ-defined dialog, so EQ can't taint Blizzard's shared Quit/Logout popups.

`Core/Compat.lua` is the capability layer. It defines exactly two `ns.Has` flags, because a flag is only legitimate where existence and behavior agree — many quest APIs are present on Classic and return nothing, so their gate is the TOC rather than a runtime check.

`Modules/TrackerBridge.lua` is the seam to EQ Objective Tracker. It reaches the tracker only through that addon's documented API and guards every call, so a mismatched version degrades quietly instead of erroring.

### The TOC gate

`tools/check_toc.py` runs in CI before packaging and enforces that every authored file is listed by a TOC, that a flavor TOC lists everything the retail TOC lists, and that the `## Version:` line agrees across every TOC on disk. Holes are declared, never waived:

- `# check-toc: omit <path>` — a legitimate omission from a flavor TOC. A stale directive is an error
- `# check-toc: flavor-only <path>` — a file no retail TOC lists. Must be declared in the retail TOC, which is the declaration of record
- `# check-toc: scaffold` — exempts a whole TOC, and still reports the size of the gap on every run

`tools/test_check_toc.py` is its self-test.

---

## Localization

Everything Quests ships bundled translations — on a matching game client the interface displays in that language automatically, and anything untranslated falls back to English:

- **French (frFR)** — by **Zox**
- **Russian (ruRU)** — by **Malevi4**
- **Korean (koKR)** — by **labrie75**
- **Simplified Chinese (zhCN)** — by **Keriaovo**
- **Traditional Chinese (zhTW)** — by **BNS333**
- **German (deDE)** — by **Stonetwist**

Translations for Everything Quests, EQ Objective Tracker, Cooldown Master and Everything Delves are maintained together in **[EverythingLocales](https://github.com/wheelbarrel00/EverythingLocales)**. The `Locales/` files in this repo are generated from it, so translation pull requests belong there rather than here. Contributions for more languages are very welcome.

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
- On Classic Era or Burning Crusade Classic, the output of `/eqsprobe`

---

## Roadmap

- [ ] Mists of Pandaria Classic, which needs its own generated dataset exactly as Burning Crusade Classic did
- [ ] Close the gap on the 261 Classic objectives that still have no marker, which need hand-authored corrections because the upstream data has no location for them at all
- [ ] Full chain coverage beyond Midnight (TWW, Dragonflight, older expansions)
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
- Minimap pin placement powered by **[HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons)**
- WoW API references from **[Warcraft Wiki](https://warcraft.wiki.gg)**

---

<p align="center">
  <sub>Made for the Midnight expansion · 2026</sub>
</p>
