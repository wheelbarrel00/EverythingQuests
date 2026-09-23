<h1 align="center">Everything Quests</h1>
<p align="center">
  <strong>A unified replacement for the Blizzard quest experience — objective tracker, world-map overlays, nameplate quest icons, an account-wide quest history, and a Midnight chain guide. Runs on retail, Classic Era, Burning Crusade Classic and, as a work in progress, WoW Forever.</strong>
</p>
<p align="center">
  <a href="https://ko-fi.com/wheelbarrel00"><img src="https://img.shields.io/badge/Support-Ko--fi-FF5E5B?style=flat-square&logo=ko-fi" alt="Support on Ko-fi" /></a>
  <a href="https://www.paypal.biz/wheelbarrel00"><img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=flat-square&logo=paypal" alt="Donate with PayPal" /></a>
  <a href="https://discord.gg/vm8K2WfQUE"><img src="https://img.shields.io/badge/Discord-Join-5865F2?style=flat-square&logo=discord&logoColor=white" alt="Join our Discord" /></a>
  <a href="https://github.com/wheelbarrel00/EverythingQuests/releases"><img src="https://img.shields.io/github/v/release/wheelbarrel00/EverythingQuests?color=6D0501&label=Version&style=flat-square" alt="Version" /></a>
  <img src="https://img.shields.io/badge/WoW-Midnight%2012.1-8B0000?style=flat-square" alt="WoW Retail" />
  <img src="https://img.shields.io/badge/WoW-Classic%20Era%201.15-C69B6D?style=flat-square" alt="WoW Classic Era" />
  <img src="https://img.shields.io/badge/WoW-Burning%20Crusade%202.5-A330C9?style=flat-square" alt="WoW Burning Crusade Classic" />
  <img src="https://img.shields.io/badge/WoW-Forever%201.60%20beta-3F7F5F?style=flat-square" alt="WoW Forever" />
  <img src="https://img.shields.io/badge/Interface-120100%20%7C%2020506%20%7C%2016001%20%7C%2011509-333333?style=flat-square" alt="Interface" />
  <a href="LICENSE"><img src="https://img.shields.io/github/license/wheelbarrel00/EverythingQuests?style=flat-square&color=333333" alt="License" /></a>
</p>

---

## Overview

Everything Quests replaces Blizzard's quest tracking and builds on the rest of its quest experience for **World of Warcraft: Midnight**, with limited support for **Classic Era** and **Burning Crusade Classic**, and work-in-progress support for the **WoW Forever** beta.

1. An on-screen **objective tracker** that replaces the default ObjectiveTrackerFrame, provided by [EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker) and installed automatically alongside this addon
2. **Nameplate Quest Icons** — a quest icon plus the remaining count or percent on objective mobs in the 3D world
3. Interactive **World Quest pins** on the world map and zone maps, plus a docked World Quests panel (retail)
4. A standalone **Chain Guide** window for browsing Midnight quest chains (retail)
5. An account-wide **Quest History** log with six views and a backfill of past completions (retail)
6. Branded **Quest POI** overlays on zone maps, and on Classic, objective spawn markers on both the world map and the minimap
7. A **Quest Browser** on Classic, for looking up almost any quest in the game before you accept it, plus **shareable quest links** in chat on every flavor
8. **Quest progress on game tooltips** — a bag item names the quest that wants it and how many are still missing
9. **Coordinate readouts** on the world map and under the minimap, for the cursor and for your own position
10. Optional **auto-accept / auto-turn-in** for quest dialogs (Alt to pause)
11. **Group quest features** — quest announcements in party or raid chat, escorts and other group quests joined for you, and the groundwork for seeing your group's quest progress

Open Options with **`/eqs`**, from the minimap button, from the Everything Quests icon on the tracker, or via **Game Menu > Options > AddOns > Everything Quests**.

---

## Classic support

Everything Quests has run on **Classic Era (1.15)** since v1.39.0, on **Burning Crusade Classic (2.5)** since v1.41.0, and on **WoW Forever (1.60)**, which is still in beta, since v1.48.0. On Classic Era and Burning Crusade Classic, support is deliberately partial: what ships is what was measured working on a live client, not the whole addon. WoW Forever loads the same feature set and is still being checked there (see below). Elsewhere in this README, "Classic" covers all three unless a flavor is named.

Era and TBC were measured identical across every game API the addon reads, so one implementation covers both. They differ only in their generated dataset — TBC ships its own, because Era quest data has nothing for Outland or for the Blood Elf and Draenei starting zones. Since v1.49.0 WoW Forever has its own dataset too: the Classic Era data adjusted to Forever's maps, plus quests gathered by playing Forever itself. Each flavor's TOC lists exactly one set; they define the same globals and are alternatives, never companions.

**Working on Classic Era and TBC**

- **Objective markers** on the world map and the minimap, drawn from a generated coordinate database rather than from the client, which exposes no quest coordinates at all
- **Objective kind icons** — kill, loot, or interact — and dungeon objectives marked at the dungeon entrance
- **Turn-in markers** at every location a finished quest can be handed in, and **markers for quests you can pick up**, gated on level, race, class, prerequisites, reputation, completion, and whether a holiday quest's world event is actually running
- **Named quest givers and finishers** — a marker for a quest you can pick up names who is standing there, and a marker for one you have finished names who takes it back, on the world map, the minimap and in the Quest Browser
- **Nameplate quest icons**, resolved from the creature ID in the unit GUID, since a Classic Era or TBC unit tooltip carries no quest data
- **The Quest Browser** — look up almost any quest in the game, including ones never picked up, with its level, race and class requirements, start and turn-in locations, prerequisites, and the reason it is not available yet. `/eqs quests`, or right-click a gold marker
- **Shareable quest links** — shift-click a marker or a Quest Browser row with a chat box open and the quest goes into chat as readable text carrying its ID. Anyone else running Everything Quests sees a clickable link that opens their Quest Browser on that quest
- **Quest progress on tooltips** — a bag item names the quest that wants it and what is still missing, and on Classic Era and TBC an enemy names the quest it counts toward, which the client there never does
- **Coordinates** on the world map and under the minimap, with a slider for how many decimals to show
- **Two more ways to quiet a busy map** on top of the filters above, both off by default: leave out markers for quests you have untracked, and fade markers sitting on top of your own position
- **Quest announcements** and **party quest progress**, which also reads the progress the established Classic quest addon shares (groundwork for now, with nothing on screen yet). **Joining group quests automatically** is included too, but has not been checked in game yet
- **Auto-accept / auto-turn-in**, the **minimap button**, the **tracker bridge**, the **focus arrow**, and the **`/eqs`** options window (General and About tabs)
- All bundled locales

**WoW Forever**

Forever runs 1.x content on the modern game client. Everything Quests loads its Classic Era feature set there, without the Chain Guide, World Quests and Quest History.

- **Checked there so far:** the world map markers, both for the quests in your log and for quests you can pick up
- **Included but not yet tested there:** everything else, including the minimap markers, the Quest Browser, nameplate icons, auto-accept and auto-turn-in, quest links and the group features. The tracker focus arrow is not available there, because EQ Objective Tracker does not offer quest focus on Forever yet
- **A quest database of its own** since v1.49.0. It adds 25 quests new to Forever so far, most of them on Zephras Isle and in Elwynn Forest. Most of them have a marker where you pick them up, a marker where you hand them in and a Quest Browser entry, and more will follow as they are gathered. Quests gathered on Forever do not carry a level requirement yet, so a few may be marked before you are high enough to take them
- **Four maps drawn over different ground.** Forever draws Stormwind City, Redridge Mountains, Mulgore and Eastern Plaguelands over different ground than Classic Era does, so the markers on those maps are converted to Forever's own. Stormwind and Redridge have been checked in game. Mulgore and Eastern Plaguelands are converted the same way but not yet checked
- **Skyborne characters** are treated as their faction: a quest open to every race of the Alliance, or of the Horde, is marked for them. A few quests limited to particular races, such as some Stormwind mage quests, stay hidden for Skyborne characters until we can confirm that Forever offers them

**Known issues on WoW Forever**

- A quest in your quest log can show the game's own marker beside the Everything Quests one, on the world map and the minimap. A fix is planned
- The Forever beta forgets every addon's settings when the game restarts. That is a bug in the beta client itself, reported to Blizzard, and until it is fixed Everything Quests starts from its default settings on each launch

**Retail-only**

The **Chain Guide** (the authored chain data is Midnight content, and on Classic Era and TBC `C_QuestLine` and `C_CampaignInfo` are absent as well), the **World Quests** panel (no world quests exist), and **Quest History** (on Classic Era and TBC, `GetTitleForQuestID` and `RequestLoadQuestByID` are both absent, so a backfilled row could never resolve its own name). WoW Forever leaves out the same three.

Each omission is declared by name in `EverythingQuests_Vanilla.toc`, `EverythingQuests_TBC.toc` and `EverythingQuests_Camelot.toc` (the WoW Forever manifest) with a `# check-toc: omit` directive, and `tools/check_toc.py` errors if one goes stale.

**`/eqsprobe`** prints what the addon actually found on the running client and is the single most useful thing to attach to a Classic or WoW Forever bug report.

---

## About the tracker

As of **v1.38.0** the objective tracker lives in its own addon, **[EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker)**. It is a required dependency and your addon manager installs it for you, so there is nothing extra to set up. It publishes for Classic Era, Burning Crusade Classic and WoW Forever as well.

Nothing was lost in the move. Existing users keep their position, size, fonts, colors, section order, filters and sorting, along with pinned quests, hidden quests, collapsed sections and saved world quest watches on every character — all carried across automatically on first login.

**Why it was split.** The tracker is useful on its own, and there is now one copy of that code instead of two, so a tracker fix reaches everyone at once.

**What this means day to day:**

| Want | Where |
|---|---|
| **Tracker settings** | The cogwheel at the top right of the tracker, or `/eqot` |
| **Everything Quests settings** | The Everything Quests logo beside the cogwheel, the minimap button, or `/eqs` |
| **Chain Guide** (retail) | The chain icon on the tracker, or `/eqs chain` |

The Everything Quests icon on the tracker, and on retail the Chain Guide icon, can each be switched off under `/eqs` > General. On retail, Everything Quests also adds **Get Directions** to a quest's right-click menu on the tracker.

If the tracker is missing, check that EQ Objective Tracker is enabled in your AddOns list. `/eqot status` prints what the tracker is doing and is the most useful thing to include in a bug report.

---

## Features

### Nameplate Quest Icons
Quest-objective enemies show EQ's logo (kill objectives get a skull, talk-to objectives a chat bubble, use-item objectives the quest's item icon) right on their nameplate, along with the remaining count or percent.

- **Detection on retail** — Two-source join: an `activeQuests` cache built from `C_QuestLog.GetQuestObjectives` (objectives keyed by display text -> `{value, type, isPercent, itemTexture}`, where `value` is the *remaining* amount) joined to each nameplate via a `C_TooltipInfo.GetUnit` line-type scan (`QuestTitle` + `QuestObjective` lines matched against the cache, with matched objectives de-duplicated by entry so a party-mate's identical line can't double-count one of yours). WoW Forever's client has the same tooltip API, so it takes this route too
- **Detection on Classic Era and TBC** — the tooltip route does not exist there, so the creature ID is read from the unit GUID and matched against a generated `questID -> creatures` table, inverted at runtime over the quest log only
- **Cached per GUID** — Tooltip scans only run when a new mob appears on a plate or quest log changes, never per frame
- **Midnight-safe** — Guards all game-returned strings/GUIDs with `issecretvalue` so restricted values can't throw
- **ElvUI-aware** — Default is ON unless ElvUI is loaded (which has its own version). A one-time custom dialog asks ElvUI users which to use so duplicates don't appear; preference is remembered
- **Pure visual frames** — No secure-template descendants, so nameplates stay taint-free

### World Quest Pins
Replaces Blizzard's world quest icons with custom pins on both the world map and zone maps. Retail only.

- **Reward-category rings** — Gold (yellow), Gear (blue), Reputation (purple), Resources (green), Artifact Power (orange), Profession (tan), PvP (red), Pet (cyan), Other (gray)
- **Time-urgency coloring** — Red (under 30m), orange (30m to 2h), yellow (2h to 12h), green (12h or more)
- **Hover tooltip** — Quest title, reward type, time remaining
- **Click to super-track** and watch the quest; right-click for a menu to track or untrack it, super-track it, or look it up on Wowhead
- **Docked panel** — A full-height World Quests list beside the world map, opened by a side tab styled to match Blizzard's or ElvUI's frame
- **Zone quest list** — On zone maps, a list of that zone's world quests, sorted by time left, reward, faction or name
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
- **Click-to-waypoint** — Click any quest in a chain to point you at it and open the world map there. Uses [TomTom](https://www.curseforge.com/wow/addons/tomtom)'s arrow when installed (recommended). Without TomTom, a quest already in your log is super-tracked, and otherwise the coordinates are printed in chat as the map opens. Blizzard's own map waypoint is deliberately never written, because it taints shared map state
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
  - **Stats** — gold and XP earned per character plus biggest single rewards, a total of quests abandoned and the average time a quest spends in your log, with a **Trends** toggle that charts quests, XP and gold over time, daily or weekly, account-wide or per character
- **How long you held each quest** — a quest accepted and later turned in shows its held time on its row, and the row tooltip names when you accepted it. Quests you were already carrying when this shipped have no accept time to measure from, so they show nothing rather than a guess. The average prints the number of quests behind it, because it covers only quests accepted since the feature shipped and would otherwise read as a lifetime figure beside lifetime totals. With recording switched off both figures show a dash rather than a zero
- **One-time backfill** — `Populate from past completions` walks the game's record of completed quests and adds them to history as `(before tracking)` entries
- **Async title fill** — Backfilled entries that show as `Quest #12345` are filled in over a minute or two via server lookups (10/0.3s burst rate, post-drain sweep, `Re-scan names` button)
- **Export** — Copy the currently visible view to your clipboard as plain text
- **Compact storage** — Saved-variables use short field names (`q,t,n,c,z,k,xp,m`) to keep the file small at 5000+ entries
- **Backups** — History is snapshotted on logout so an empty or missing log can be restored automatically

### Map POI Overlays
Custom quest pins on zone maps. On retail the icon sits in a red ring; on Classic the ring starts off, because a zone there can draw hundreds of pins. Clicks super-track, or set a TomTom waypoint where the game has no super-track; right-click opens the quest log, or the Quest Browser for a quest you have not picked up.

- **Aggregated tooltips** — hovering lists every quest whose nearest pin is within reach, nearest first, so overlapping pins stop hiding each other. The reach is measured in pin widths, so it stays a constant on-screen distance at any zoom. The tooltip carries the quest level, its objectives and its experience reward
- **Fixed size at every zoom** — `SetScalingLimits(1, s, s)` collapses Blizzard's zoom lerp to a constant, with a per-map-type factor so continent and world maps draw smaller. A scale slider and a per-quest pin limit live under `/eqs` > General
- **On Classic** — in-progress pins come from `Data/QuestSpawns_*.lua` and carry objective art rather than a `!`, marking every clustered location a quest can be advanced, with a per-quest minimum separation applied at read time so a low limit still spreads across the zone
- **Turn-in pins on Classic** — a finished quest is placed from `Data/QuestTurnIn_*.lua`, at every map where it can be handed in. That table is authoritative once it knows a quest, because on Classic Era alone 475 quests hand in on a different map from their objective
- **Available quest pins on Classic** — gold `!` markers for quests you can pick up but have not accepted, from `Data/QuestAvailable_*.lua`, gated on level, race, class, prerequisites, reputation and completion. Pins merge by location rather than by quest
- **Source names on start and turn-in pins** — the creature or object each of those points belongs to is packed alongside its coordinate, and named from `Data/QuestSources_*.lua`. Creature and object IDs overlap numerically, so the point's *kind* decides which of the two name tables to read; nothing infers it from the ID. A quest that starts from a looted item stores no source, because its dropper could be either
- **Holiday quests follow their season** — a Lunar Festival or Brewfest quest is pinned only while that world event is running, from `Data/QuestHolidays_*.lua`. On by default. The one date that moves each year fails open, so a year the table does not list shows those quests rather than hiding them
- **Filters for a busy map**, all under `/eqs` > General — leave out dungeon, repeatable or profession quests, hide quests below your level using the game's own gray threshold, or hide the ones it colors red for you. That last one is off by default, because a red quest is still worth knowing about if you mean to come back for it

### Minimap Objective Pins
The same objective markers on the minimap, for the zone you are standing in, powered by HereBeDragons-Pins. Classic only, and keyed on `C_Map.GetBestMapForUnit` rather than the open world map. Pins are hover-only so clicks pass through to the minimap underneath.

### Quest Browser
Classic only (Classic Era, Burning Crusade Classic and WoW Forever). A search-and-details window over EQ's own generated quest tables, answering the one thing a Classic client cannot: what a quest is before you have ever accepted it.

- **Search** by name substring, by quest ID, or `"quoted"` for a whole-title match. The scan runs against the shipped English titles, because the client can only name a quest it has already seen; the row you see uses the client's own wording where it knows it
- **Details** — quest level, required level, race and class gates, category, every map it starts / has objectives / turns in on, prerequisites (any-of vs all-of), follow-ups, exclusions, and skill and reputation gates
- **The reason it is unavailable** comes from `AvailableQuests:Explain`, the *same* gate that decides which gold markers are drawn. There is deliberately one implementation — a second copy would let the window and the map disagree while both looked right
- **Clickable throughout** — a location opens the world map there and sets a TomTom waypoint; a prerequisite or follow-up navigates to that quest. References the data cannot describe render as plain text rather than a dead link
- **Who to talk to** — the Starts and Turn in rows name the giver and the finisher. A row is merged per map while a map pin is merged per coordinate, so a row covering several different people names all of them rather than picking one
- **Entry points** — `/eqs quests [text]`, the button under `/eqs` > General, or right-clicking a gold available-quest marker
- **Coverage is not total.** It reads the `names`/`gates` tables (3,794 Era / 5,652 TBC) while the coordinate tables cover more, so 357 Era and 508 TBC quests EQ pins on the map are not in the browser. WoW Forever's tables are the Era set plus the Forever quests gathered so far, with a similar gap
- `/eqsprobe questbrowser` reports the data, a live query, the player's zone, one full decoded record, and whether the browser and the map pins agree

### Shareable Quest Links
Shift-click a quest marker on the map or a row or a detail line in the Quest Browser (on retail, a map marker or a Chain Guide node) with a chat box open, and the quest drops into chat as `[[18] The Defias Brotherhood (155)]`. On Classic, a reader running Everything Quests sees a colored, clickable link that opens their Quest Browser on that quest.

- **The wire form is plain text on purpose.** The client refuses to send a hyperlink type it does not know, so a custom link arrives empty for every recipient, and the one type it does know cannot name a quest that is not already in your log. Plain text reads correctly with no addon at all and carries the ID, which is what lets a receiver rebuild a real link locally
- **Byte-compatible with the established Classic quest addon's format**, so its users get rich links from Everything Quests and Everything Quests users get rich links from them, with no addon-to-addon channel on either side
- **A click is only taken when a chat box is already open.** Shift-clicking a marker with chat closed still sets a waypoint exactly as before. All four producers ask the same question, so the behavior cannot drift between two quest lists in the same addon
- **A reference inside somebody else's hyperlink is never rewritten** — an item called `[Bundle (155)]` stays an item
- **Only a quest the Quest Browser can describe is made clickable**, since that is where the click lands. The rest stay readable plain text rather than becoming dead links
- On retail the client's own quest link is preferred, falling back to plain text when the client cannot name the quest

### Group Quest Features
Everything Quests can tell your group what you are doing, and keep track of what they are doing, without anyone typing.

- **Quest announcements** — posts a line to party or raid chat when you accept a quest, finish one of its objectives, hand it in or abandon it. Nothing is sent until you pick a channel under `/eqs` > General > Quest announcements, each kind of line has its own switch, and abandoned quests stay quiet unless you turn them on. **Also print to your own chat** shows what would go out before anyone else sees it. Each line carries the quest the same way a shared quest link does, and anyone else running Everything Quests sees it marked with the Everything Quests logo. On retail, world quests and bonus objectives are not announced as accepted or abandoned just because you passed through their area
- **Hide announcements from other players** — hides the quest updates other people in your group post, including the ones other quest addons send. Your own lines are always shown. Off by default
- **Party quest progress** — shares how far along you are on each quest with group members running it, and keeps what they share with you. It travels as hidden addon messages, so nothing is ever posted to anyone's chat, and it pauses in battlegrounds and in groups larger than 15. On Classic it also reads the progress shared by the established Classic quest addon, and asks group members running it for their quest log when you join. **Nothing in the interface shows this yet**: it is groundwork a display can build on later. Both switches are under `/eqs` > General > Party quest progress and are on by default, and switching sharing off takes back what your group was holding for you
- **Join group quests automatically** — see Auto-Quest Dialogs below

### Auto-Quest Dialogs
Optional, opt-in handlers for quest gossip and detail screens. All default OFF.

- **Auto-accept** — accepts on `QUEST_DETAIL`; picks first available quest from gossip menus and the old multi-quest greeting frame
- **Auto-turn-in** — continues on `QUEST_PROGRESS`, finishes on `QUEST_COMPLETE` *only* when there's at most one reward choice (multi-choice screens are left open so the player picks)
- **Join group quests automatically** — when someone in your group starts an escort or another quest the game asks you to join, Everything Quests answers yes for you and closes the question. It only answers for people actually in your group, holding Alt pauses it, and it keeps working with Immersion installed
- **Pause gates** — hold **Alt** during any interaction to skip both for that one event; declining a quest arms a 10-second lockout so the next gossip doesn't immediately re-offer it
- **Immersion is left alone** — Immersion replaces the quest and gossip windows so you can read them, and auto-accept and auto-turn-in would click straight past it. With Immersion installed, Everything Quests stands aside. If you had auto-questing switched on it asks once which you would rather have, and a checkbox under `/eqs` > General changes the answer later. Detection keys on the addon being loaded rather than on its frame being visible, because Immersion deliberately leaves that frame hidden for some events it handles. With Immersion not installed nothing changes at all
- **Insecure-only APIs** — all touchpoints (`C_GossipInfo.*`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`, `ConfirmAcceptQuest`) are non-protected, so no taint

### Minimap Launcher
LibDataBroker-powered launcher compatible with Titan Panel, Arcana (formerly ChocolateBar), ElvUI's data-broker bar, and any other LibDataBroker display.

| Click | Action |
|---|---|
| **Left-click** | Open the Blizzard quest log |
| **Shift+Left-click** | Open the Chain Guide (retail) |
| **Right-click** | Open Options |
| **Drag** | Reposition around the minimap |

---

## Slash Commands

| Command | Action |
|---|---|
| `/eqs` | Toggle Options |
| `/everythingquests` | Toggle Options (alias) |
| `/eqs chain` | Toggle the Chain Guide window |
| `/eqs quests [text]` | Open the Quest Browser, optionally with a search. Classic Era, TBC and WoW Forever only |
| `/eqs history` | Toggle the Quest History window |
| `/eqs about` | Open Options on the About tab |
| `/eqs session` | Show a recap of your current play session (quests, XP, gold, time) |
| `/eqs whatsnew` | Show the "What's New" summary for the latest update (also `/eqs changes`) |
| `/eqs whatsnew chat` | Print the same summary to chat instead of the popup |
| `/eqs discover [zone]` | Print quest-line discovery info for the current zone (optional hint) |
| `/eqsprobe [section]` | Print what EQ found on the running client (also `/eqs flavorprobe`). Ships on every flavor |

On Classic Era, Burning Crusade Classic and WoW Forever the Chain Guide, discover, History and session commands resolve to nothing, since those subsystems are not loaded there. `/eqs quests` is the reverse: it is Classic-only, because retail already opens any quest in Blizzard's own quest log.

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

These are mostly retail tools. The Chain Guide and profiler commands do nothing on the Classic flavors, where those parts are not loaded.

`/eqsprobe` sections: `media`, `map`, `poi`, `pins`, `minimap`, `available`, `questbrowser`, `group`, `mappoi`, `flare`, `quest`, `port`, `tooltip`, `xp`, `events`, `ui`, `misc`. No argument runs all except `tooltip`, `mappoi`, `flare` and `xp`, each of which needs something set up first — and `flare` and `xp` both mutate state, so `/reload` after using `flare`.

---

## Keybindings

Bindable from **Esc > Options > Key Bindings > AddOns > Everything Quests**:

| Action | Default |
|---|---|
| Toggle Options | (unbound) |
| Toggle Chain Guide (retail) | (unbound) |

---

## Options

| Tab | Settings |
|---|---|
| **General** | World-map quest pins, pin scale, objective pins per quest, quests you can pick up and their level and holiday filters (Classic), minimap objective pins (Classic), auto-accept / auto-turn-in / join group quests, the Immersion hand-off (when Immersion is installed), **quest announcements**, **party quest progress**, pin rings, markers for tracked quests only, fading markers under your position, **coordinates**, dungeon / repeatable / profession quest filters (Classic), quest progress on tooltips, the Quest Browser button (Classic), Open Tracker Settings and the tracker icons, options window scale, update notice style, **quest icons on nameplates** with their position, size and offsets, reset to defaults, profile management, show / hide minimap button |
| **World Quests** | Master switch, world map pins, zone quest list and its sort order, per-reward filters, per-faction filters, pin scale |
| **Chain Guide** | Open on login, window scale, unrouted questlines, the tracked chain on the world map, cross-character chain cache stats and reset, prune stale entries |
| **History** | Record completed quests, maximum entries kept, backfill from past completions, re-scan missing names, restore from backup, wipe history |
| **About** | Version, changelog, commands, credits, and links |

Every section gates on the subsystem it drives rather than on a flavor check, so on Classic Era, Burning Crusade Classic and WoW Forever only General and About appear and no control is left inert. Tracker and appearance settings live in EQ Objective Tracker's own panel — the Open Tracker Settings button on the General tab opens it, or type `/eqot`.

---

## Installation

### From CurseForge
1. Install via the [CurseForge app](https://www.curseforge.com/) or download manually
2. **EQ Objective Tracker is pulled down automatically** as a required dependency

### Manual Install
1. Download the latest release from the [Releases](https://github.com/wheelbarrel00/EverythingQuests/releases) page
2. Download **[EQ Objective Tracker](https://github.com/wheelbarrel00/EQObjectiveTracker/releases)** as well — Everything Quests will not load without it
3. Extract both folders into your client's AddOns directory, for example:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   World of Warcraft/_classic_era_/Interface/AddOns/
   World of Warcraft/_anniversary_/Interface/AddOns/
   World of Warcraft/_classic_beta_/Interface/AddOns/
   ```
   The last two are Burning Crusade Classic and the WoW Forever beta
4. Restart WoW or type `/reload` if already in-game
5. Enable **Everything Quests** and **EQ Objective Tracker** at the character select screen

---

## Dependencies

**Required:** **[EQ Objective Tracker](https://www.curseforge.com/wow/addons/eq-objective-tracker)** — provides the objective tracker. Addon managers install it automatically; a manual install needs both folders. All other libraries are bundled.

**Optional:**
- **[TomTom](https://www.curseforge.com/wow/addons/tomtom)** — recommended on retail for the Chain Guide, and effectively required on Classic Era and Burning Crusade Classic: clicking a quest or an objective marker uses TomTom's on-screen arrow, and those clients have no built-in waypoint system to fall back on. On WoW Forever a marker click uses the game's own super-tracking, which that client has, though TomTom still serves the Quest Browser's location links
- [TitanClassic](https://www.curseforge.com/wow/addons/titan-panel-classic), Arcana (formerly ChocolateBar), or [ElvUI](https://www.tukui.org/) — display the minimap button on a data-broker bar instead of around the minimap
- **[ElvUI](https://www.tukui.org/)** — ElvUI ships its own nameplate quest icons. When detected, EQ's version defaults off and a one-time dialog asks which to use; choose either, and your pick is remembered. No conflict either way

### Bundled Libraries

LibStub, CallbackHandler-1.0, AceDB-3.0, AceComm-3.0 with ChatThrottleLib, AceEvent-3.0, AceTimer-3.0, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0, LibMapPinHandler, and HereBeDragons-2.0 / HereBeDragons-Pins-2.0.

HereBeDragons is listed by the three Classic TOCs only. HBD-Pins calls `WorldMapFrame:AddDataProvider` at file scope on the real map canvas, which is precisely what LibMapPinHandler's shadow canvas exists to keep EQ away from on retail, where the AreaPOI taint crash is live. Retail safety rests on the file not being listed, not on `LibStub` returning nil.

---

## Technical Details

| Metric | Value |
|---|---|
| Interface version | 120100, 120007, 120005 (Midnight 12.1), 20506 (Burning Crusade Classic 2.5), 16001 (WoW Forever 1.60) and 11509 (Classic Era 1.15) |
| SavedVariables | `EverythingQuestsDB` (account), `EverythingQuestsCharDB` (character), `EverythingQuestsChainCache` (account), `EverythingQuestsHistory` (account), `EverythingQuestsHistoryBackups` (account) |
| API compliance | No protected actions and no taint. Auto-accept, auto-turn-in and joining group quests are opt-in and use insecure-only APIs (`C_GossipInfo`, `AcceptQuest`, `CompleteQuest`, `GetQuestReward`, `ConfirmAcceptQuest`); Alt pauses them. Chat announcements stay off until you choose a channel, and party quest progress travels as hidden addon messages |

### Architecture
```
EverythingQuests/
├── EverythingQuests.toc              # Retail manifest, module load order
├── EverythingQuests_Vanilla.toc      # Classic Era manifest, omissions declared inline
├── EverythingQuests_TBC.toc          # Burning Crusade Classic manifest, same shape
├── EverythingQuests_Camelot.toc      # WoW Forever manifest, the Classic Era file set
│                                     #   with Forever's own data files
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
│   ├── Group/                        # Party quest progress over hidden addon messages
│   ├── Announce.lua                  # Quest announcements in party and raid chat
│   ├── MapCoords.lua                 # Coordinates on the world map and minimap
│   ├── QuestArrow.lua                # Shared TomTom waypoint slot
│   ├── QuestAuto.lua                 # Auto-accept / auto-turn-in handlers, joining
│   │                                 #   group quests, and standing aside for Immersion
│   ├── QuestLink.lua                 # Shareable quest links in chat
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
│   ├── QuestHolidays_*.lua           # Generated: questID -> its world event
│   └── QuestSources_*.lua            # Generated: creature and object names for the
│                                     #   points that start and finish a quest
│                                     #   Each has a _Classic, a _TBC and a _Forever
│                                     #   variant, except QuestHolidays, which Forever
│                                     #   shares with Classic Era. A TOC lists exactly
│                                     #   one set; they define the same globals
├── tools/                            # TOC and locale-format gates, plus their own
│                                     #   self-tests, and the quest data generators
└── Options/                          # General, World Quests, Chain Guide,
                                      #   History, About tabs
```

Modules register into Core subsystems at load time and listen for events through a shared callback dispatcher, so multiple modules can safely react to the same WoW event without stepping on each other. `Core/Events.lua` wraps `RegisterEvent` in a `pcall` and records refused event names, because `RegisterEvent` raises rather than no-ops on an event the client does not know — several events EQ uses do exactly that on Classic Era and TBC. `Core/Dialog.lua` provides a custom confirmation/prompt frame used in place of Blizzard's `StaticPopupDialogs` for every EQ-defined dialog, so EQ can't taint Blizzard's shared Quit/Logout popups.

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

Translations are the exception — those go to [EverythingLocales](https://github.com/wheelbarrel00/EverythingLocales), which feeds all four addons.

### Reporting Bugs

Please use the [GitHub Issues](https://github.com/wheelbarrel00/EverythingQuests/issues) tab. Include:
- Your WoW client version and region
- Steps to reproduce
- Any error messages from `/console scriptErrors 1`
- Screenshot if applicable
- For anything involving the tracker, the output of `/eqot status`
- On Classic Era, Burning Crusade Classic or WoW Forever, the output of `/eqsprobe`

---

## Roadmap

- [ ] Mists of Pandaria Classic, which needs its own generated dataset exactly as Burning Crusade Classic did
- [ ] Keep growing the WoW Forever quest data as more of Forever is played, check the Mulgore and Eastern Plaguelands markers in game, and stop the game's own marker doubling up with Everything Quests' there
- [ ] Close the gap on the 261 Classic Era objectives that still have no marker, which need hand-authored corrections because the upstream data has no location for them at all
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
- Fonts and textures shared with other addons through **[LibSharedMedia](https://www.curseforge.com/wow/addons/libsharedmedia-3-0)**
- Minimap pin placement powered by **[HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons)**
- WoW API references from **[Warcraft Wiki](https://warcraft.wiki.gg)**

---

<p align="center">
  <sub>Made for the Midnight expansion · 2026</sub>
</p>
