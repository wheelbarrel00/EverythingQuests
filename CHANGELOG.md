# Changelog

All notable changes to Everything Quests will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.46.0] - 2026-09-01

Quests you can paste into chat, a history that knows how long you took, and a truce with Immersion.

### New Features

- **Shareable quest links on Classic Era and Burning Crusade Classic.** Shift-click a quest marker on the map, or a row in the Quest Browser, with a chat box open, and the quest drops into chat as text anyone can read. Someone else running Everything Quests sees a colored, clickable link that opens their Quest Browser on that quest. It is plain text on purpose: the game refuses to send a link type it does not recognize, so a custom link would arrive empty for everyone, and the game cannot name a quest that is not already in your log. The wording matches the format the established Classic quest addon already sends, so links pass between the two without either addon knowing about the other. Shift-clicking with no chat box open still sets a waypoint exactly as before.

- **Quest History records how long you held each quest, and what you abandoned.** On retail, a quest you accept and later turn in now shows the time you held it on its row, and hovering that row tells you when you accepted it. The Stats tab gains a total of quests abandoned and the average time a quest spends in your log. Quests you were already carrying have no accept time to measure from, so they show nothing rather than a guess, and the average prints the number of quests behind it so it cannot be mistaken for a lifetime figure.

### Improvements

- **Immersion is left to handle the quest windows.** Immersion replaces the quest and gossip windows so you can read them, and Everything Quests' auto-accept and auto-turn-in would click straight past it. With both installed, Everything Quests now stands aside. If you had auto-questing switched on it asks once which you would rather have, and a checkbox under /eqs > General changes your mind later. With Immersion not installed, nothing changes at all.

## [1.45.1] - 2026-08-30

A one-line fix for a problem that had nothing to do with quests, and all six languages are complete again.

### Improvements

- **German, French, Korean, Russian, Simplified Chinese and Traditional Chinese are back to 100%.** Version 1.44.0 added the two new map filters and reworded one of the map explanations, and those six phrases had been rendering in English ever since. They are translated now, so the Hide holiday quests out of season and Hide quests above your level checkboxes, both of their explanations, the explanation on Show quests you can pick up, and the Quest Browser's reason for hiding a quest that is above your level all read in your own language. Thanks as always to Stonetwist, Zox, labrie75, Malevi4, Keriaovo and BNS333, and corrections are always welcome.

### Bug Fixes

- **Everything Quests no longer resets Arcana's bar layout.** On retail, our TOC named ChocolateBar as an optional dependency, left over from when ChocolateBar was the data-broker display addon that showed our minimap launcher. Arcana, which replaced it, ships a load-on-demand stub folder still called ChocolateBar so it can import old ChocolateBar profiles, and naming a load-on-demand addon as an optional dependency force-loads it. So every login, Everything Quests was quietly triggering that import: Arcana re-ran its migration, replaced its own live settings with the result, and re-initialized, which moved bar tiles back and undid display settings. The entry is gone, along with the TitanClassic and ElvUI entries beside it. None of the three bought anything: our launcher is not registered until everything has finished loading at login, so load order could never have mattered, and everything Everything Quests reads from ElvUI it reads later still. Nothing else changes. The Classic Era and Burning Crusade Classic builds never carried the entry and were never affected. Thanks to RoadBlock for the report that turned this up.

## [1.45.0] - 2026-08-26

Quest markers on Classic Era and Burning Crusade Classic now tell you who to talk to.

### New Features

- **Quest markers name the person who gives the quest, and the one who takes it back.** Hovering a marker for a quest you can pick up tells you who is standing there, and hovering a marker for a quest you have finished tells you who to hand it in to. The same names appear in the Quest Browser under Starts and Turn in, so you can see where a quest begins without opening the map. This covers about 1,700 quest givers and finishers on Classic Era and 2,700 on Burning Crusade Classic, including the ones that are not people: a noticeboard, a sealed crate or a scrap of parchment is named too. A quest that starts from an item you loot has nobody to name, and says so the way it always did.

### Bug Fixes

- **The What's New window in 1.44.0 showed the previous release's notes.** It was headed 1.44.0 but described the 1.43.0 features, so the holiday season gate and the level filter it was meant to announce were not mentioned anywhere in it. The window now matches the release again.

## [1.44.0] - 2026-08-24

Quest markers are far more accurate on Classic Era and Burning Crusade Classic. Quests that were being hidden by mistake are back, holiday quests no longer sit on the map all year, and there is a new option to leave out quests that are still out of reach.

### Bug Fixes

- **About 190 quests on Classic Era and 310 on Burning Crusade Classic were hidden from the map by mistake, and they are back.** Everything Quests was reading a flag in its quest data as "this belongs to a world event" when what it actually marks is "this quest is finished by exploring somewhere, or by a scripted event". That covers a great many perfectly ordinary quests, and none of them drew a marker: The Defias Brotherhood, The Missing Diplomat, The Fargodeep Mine, Rescue OOX-17/TN! and essentially every escort quest in the game. Nearly all of them draw one again, the exception being the few that really are holiday quests and now follow the season.

### New Features

- **Holiday quests are now only shown while their world event is actually running.** The Lunar Festival, Winter Veil, Hallow's End, Midsummer, Brewfest, the Darkmoon Faire and the rest used to put markers on the map every day of the year, which is how you could find Brewfest quests sitting there in August. A new checkbox under the map options, Hide holiday quests out of season, is on by default. Turning it off puts every holiday quest back on the map all year, the way it behaved before. Thanks to JonnyN for reporting it.
- **A new option leaves out quests the game considers out of reach.** Hide quests above your level removes anything the game colors red for you, which is roughly five levels above you and higher. It is off by default, because a red quest is still worth knowing about if you mean to come back for it later. It reads the game's own difficulty color rather than counting a fixed number of levels, which is the same approach the existing low level filter takes at the other end of the scale.

## [1.43.2] - 2026-08-23

Some incorrect information fixed on the About tab, and a faster addon load on Classic Era and Burning Crusade Classic.

### Bug Fixes

- **Fixed some incorrect info on the About tab.** It now reads the game version from the game itself, and on Classic Era and Burning Crusade Classic it describes the map and minimap markers, the nameplate icons and the Quest Browser.

### Improvements

- **The addon finishes loading sooner on Classic Era and Burning Crusade Classic.** The objective location database is the largest thing Everything Quests carries, and it was being read in full every time you logged in or reloaded. It is now left packed until something needs it, which takes about 110ms off the load on Classic Era and about 150ms on Burning Crusade Classic. It is unpacked the first time markers are drawn, usually a moment after you enter the world, so this moves the work off the loading screen rather than removing it. Nothing about the markers themselves changes, and retail is unaffected because it never loaded that database in the first place.
- **Cooldown Master has been added to the add-on list on the About tab**, alongside Everything Delves and Loot Pro.

## [1.43.1] - 2026-08-19

German joins the bundled languages, and every language is now complete.

### New Features

- **German (deDE)** - the addon now ships German translations alongside French, Russian, Korean, Simplified Chinese and Traditional Chinese, contributed by Stonetwist.

### Improvements

- **Every bundled language now covers the whole addon.** French, Russian, Korean, Simplified Chinese, Traditional Chinese and German are all at 100%, so nothing falls back to English on a matching client any more. Since v1.43.0 that is 406 new phrases in Traditional Chinese, 104 in Korean, 75 in Simplified Chinese, and 19 each in French and Russian.
- If something in your language reads oddly or is not formatted properly, let me know and I will fix it.

## [1.43.0] - 2026-08-17

Quest information on the tooltips you already hover, coordinates on the map and minimap, and two new ways to quiet a busy map. Plus Traditional Chinese.

### New Features

- **Quest progress on tooltips** - hovering an item in your bags now tells you which quest wants it and how many you still need. On Classic, hovering an enemy tells you which quest it counts toward and what is left, which the game there never says. Nothing is added to a tooltip that has nothing to say, and the enemy half is left alone on retail because the game already writes those lines itself. Note: the bag item half has been tested on Classic but not on retail, so if it looks wrong there please let me know.
- **Coordinates on the world map** - a readout in the bottom left showing the spot your mouse is pointing at, and your own position when you are looking at the zone you are standing in. There is a matching readout under the minimap, off by default, and a slider for how many decimals to show.
- **Only show markers for quests you are tracking** - leaves out the map markers for any quest in your log you have untracked, so a busy zone shows only what you are actually working on. Off by default. Quests you have not picked up yet are unaffected, because there is nothing to have untracked.
- **Fade markers that cover your position** - markers sitting on top of your own arrow become see-through so you can still find yourself on a zone drawing hundreds of them. Off by default. The markers stay where they are and still answer the mouse.
- **Traditional Chinese (zhTW)** - the addon now ships zhTW translations alongside French, Russian, Korean and Simplified Chinese, contributed by BNS333.

### Improvements

- **Auto-accept picks the right quest at a busy quest giver** - it now takes the first quest it can actually accept rather than whatever sits at the top of the list, and passes over a trivial grey quest when there is a real one on offer. A trivial quest is still accepted when it is the only thing there.

### Bug Fixes

- **"Get Directions" looked like it did nothing** - on a quest already in your log it set a waypoint only when TomTom was installed and the game knew where your next objective was, and said nothing at all in either other case. It now prints the coordinates when you have no TomTom, the same as it always did for a quest you have not accepted yet, and otherwise tells you the quest has been super-tracked but the game has given no position to point at. Reported by AIR.

## [1.42.0] - 2026-08-15

The Quest Browser: look up almost any quest in the game on Classic Era and Burning Crusade Classic, including the ones you have never picked up. Plus Simplified Chinese translations.

### New Features

- **The Quest Browser** (Classic Era and TBC) - look up almost any quest in the game, including the ones you have never picked up, which is the one thing the game itself cannot tell you there. Search by name or by quest number, or put quotes around a name for an exact match. Each quest shows its level, its race and class requirements, where it starts, where its objectives are and where it is handed in, what has to be finished before it, and if you cannot take it yet, the reason why. Open it with `/eqs quests`, from the button under `/eqs` > General, or by right-clicking a gold quest marker on the map.
- **The browser is clickable throughout** - clicking a location opens the map there and drops a waypoint on it, and clicking a listed prerequisite or follow-up jumps to that quest, so most chains can be walked without typing anything.
- **Simplified Chinese (zhCN)** - the addon now ships Chinese translations alongside French, Russian and Korean.

### Improvements

- **French and Russian are complete again** - both cover every phrase in the addon, including everything added in this release.

### Bug Fixes

- **The "Don't show these again" checkbox on the What's New window overlapped the last line of text** - the text area and the checkbox were positioned independently, so a long enough release note ran underneath it.

## [1.41.0] - 2026-08-13

Burning Crusade Classic support, plus markers for quests you can pick up, markers for where a quest is handed in, and a Map section in the options to control them.

### New Features

- **Burning Crusade Classic support** - everything that works on Classic Era now works on TBC too, with its own quest database covering Outland and the Blood Elf and Draenei starting zones as well as the old world. Era and TBC read identically to the addon, so the two share one implementation and differ only in their data. The Chain Guide, World Quests panel and Quest History stay retail-only, exactly as on Era.
- **Markers for quests you can pick up** (Classic Era and TBC) - every quest giver holding something for you is marked with a gold exclamation mark, filtered by your level, race, class and the quests you have already finished. One marker covers a whole quest giver, and hovering it lists everything that giver offers. There are checkboxes for it and for hiding quests you have outleveled under `/eqs` > General.
- **Turn-in markers** (Classic Era and TBC) - a finished quest now points at the person who takes it instead of the field you farmed it in, on every map where it can be handed in. 475 quests hand in somewhere other than where their objective is, and every one of them used to be marked in the wrong place.
- **Items you buy are marked at the merchants who sell them** (Classic Era and TBC) - an objective item with no drop source used to produce no markers at all, so the quest fell back to a single point. 21 quests gain their first useful marker.
- **Hide quests by category** (Classic Era and TBC) - dungeon and raid quests, repeatable quests and profession quests each get a checkbox that leaves them off the map. These only affect quests you have not picked up yet; a quest in your log always keeps its markers.
- **A Map section in the options**, holding the two marker ring toggles and the category filters.
- **The tracker's focused quest gets an arrow** (Classic Era and TBC) - clicking a quest's icon in EQ Objective Tracker now drops a TomTom arrow on it, and clicking it again clears it. Classic has no in-game waypoint, so the tracker announces the focus and Everything Quests places the arrow from its own database. Map markers and the tracker share one arrow, so using both retargets instead of leaving two.
- **Quest level and reward XP in the marker tooltip** - the level goes in front of the title the way the quest log writes it, and the experience reward is listed underneath.

### Improvements

- **Countdown timers use your own language's abbreviations** - the day, hour and minute suffixes now come from the game client instead of being hardcoded English, so Korean shows 일 / 시간 / 분 and German T / Std / Min. English is unchanged.
- **The options window opens at the left edge of the screen** - it is the same size as the tracker's own options window and both used to open dead center, landing exactly on top of each other.
- **Markers are smaller on continent and world maps**, matching how the map itself scales down.
- **The world map timer text has an outline and a shadow**, so it stays readable over bright terrain.
- **Two option descriptions were rewritten** - the pin scale and quest pin tooltips had both stopped describing what the addon does.

### Bug Fixes

- **A finished quest was marked where you farmed it** - the single-point table it read holds the objective location for any quest that has one, so "Ready to turn in" appeared on farming grounds. The Tome of Divinity hands in at Stormwind and drew its turn-in marker on the Elwynn field it was farmed in.
- **Reward gold and experience read the wrong quest on Classic** - the game ignores the quest ID on that version and answers about whatever quest log entry is selected, so a tooltip could confidently report another quest's rewards.

### Notes

- On Classic Era and Burning Crusade Classic the red ring behind quest markers now starts switched off. A zone there can draw hundreds of objective markers and the rings crowd each other, and the icons still tell the states apart on their own. Retail is unchanged. The checkbox is under `/eqs` > General > Map.

## [1.40.0] - 2026-08-11

Chain Guide coverage for patch 12.1's new zone, and a fix for four Curse of Ula'tek chapters that had been listing the wrong quests entirely.

### New Features

- **The Coiled Isle in the Chain Guide** - patch 12.1's new zone has its own category, covering all seven of its questlines: Bone Deep, Renown of Midnight, A Fiery Blast from the Past, Something Vile This Way Comes, Strange Friends in Odd Places, Ancient Anthropology, and Living Legend.

### Bug Fixes

- **Four Curse of Ula'tek chapters were listing the wrong quests** - An Island of Fangs, Ghosts of the Past, Original Sin and The Battle for Atal'Utek each showed a handful of quests that belong to The War of Light and Shadow instead of their own. The game reported no quests for those chapters when they were added in v1.37.0, and the stand-in list used in their place was wrong. The game supplies real data for them now, so they show their actual contents: 17, 6, 10 and 8 quests.
- **Legacy of the Amani was missing its opening quest** - the chapter gained a new first quest in patch 12.1, and it drew off to the side of the chain instead of at the top of it.

### Notes

- The Call of the Void, patch 12.1's new chapter of The Curse of Ula'tek, appears on its own. The Chain Guide reads campaign chapters live from the game, so it needed no update to pick the new one up.

## [1.39.0] - 2026-08-10

Everything Quests runs on Classic Era for the first time, and map markers got easier to read everywhere.

### New Features

- **Classic Era support, limited but real** - quest markers on the world map and the minimap, quest icons on nameplates, auto-accept and auto-turn-in, the minimap button and the `/eqs` options window all work on Classic Era. Burning Crusade Classic and Mists of Pandaria Classic are next.
- **Objective markers on Classic** - markers show every place a quest can be advanced rather than a single spot, and say whether you are there to kill, loot or use something. Clicking one sets a TomTom waypoint if TomTom is installed. Objectives inside a dungeon are marked at the dungeon entrance.
- **Objective markers on the minimap** - the same markers for the zone you are standing in, with a hover tooltip naming the quest and what it still needs. There is a checkbox for them under `/eqs` > General, and they use the same per-quest limit as the world map.
- **Marker tooltips aggregate** - hovering a marker now lists every quest at that spot instead of only the top one, so overlapping markers no longer hide each other. This applies on every game version.

### Improvements

- **Markers are a fixed size at every zoom level** - they no longer shrink as you zoom out, which made them easy to miss on large or high-resolution displays. There is a scale slider under `/eqs` > General.
- **A marker only names the objectives its own location serves** - a spot that drops one of a quest's four items no longer advertises the other three, and a location whose objective is already finished is not drawn at all.
- **Fewer, better-placed markers** - markers for one quest keep a minimum distance apart, which covers more of a zone with fewer icons.

### Bug Fixes

- **Map pin frame levels are resolved properly again** - the lookup read the wrong frame and always fell through to a hardcoded level, on every game version. Retail now leaves pin placement to the game as it did before, and Classic gets a level computed from what the client actually defines.

## [1.38.1] - 2026-08-07

Follow-up fixes to the tracker split, plus a bug found while going back over the code afterwards.

### Bug Fixes

- **The Quest History Trends view no longer shows a box on Korean clients** - the weekly date range separator used a dash the Korean game font has no glyph for, so it drew as an empty box in the bar tooltip and in exported text.

### Improvements

- **More of the interface is translated in Korean** - the phrases added by the tracker split are now covered, including the General tab's tracker settings button and the tracker icon options.
- **The addon description and README match the split** - both still described a tracker that Everything Quests no longer contains, and pointed at options tabs that have moved to EQ Objective Tracker.

### Notes

- **The Chain Guide's class and race check was corrected internally.** It read your character's class and race in a way that quietly produced nothing at all. No chain published today varies its steps by class or race, so there is nothing to see here; the check is simply right now for chains that will. Faction handling was never affected.

## [1.38.0] - 2026-08-06

Everything Quests' tracker has moved out into its own addon, EQ Objective Tracker, which now comes down automatically with Everything Quests. Your layout and settings carry across on their own and there is nothing to set up again. The reason for the split is maintenance: there is one copy of the tracker code now instead of two, so a tracker fix lands everywhere at once.

### Changes

- **The tracker is now EQ Objective Tracker** - a required dependency, installed for you. Your position, size, fonts, colors, section order, filters and sorting all carry over, along with your pinned quests, hidden quests, collapsed sections and saved world quest watches on every character.
- **Tracker settings moved to their own panel** - open it with the cogwheel at the top right of the tracker, or by typing `/eqot`. Everything that was under `/eqs` > Tracker and `/eqs` > Appearance is there, in the same shape. Those two tabs have been removed from Everything Quests, and the General tab has a button through to the new panel.
- **An Everything Quests icon on the tracker** - the cogwheel now opens the tracker's settings, so there is a new Everything Quests logo beside it that opens `/eqs`. The Chain Guide chain icon is still there, and each of the three icons can be switched off under `/eqs` > General. The minimap button is unchanged.

### Bug Fixes

- **Untracking a world quest sticks** - a world quest untracked from the tracker could come back on the next loading screen, because the map's saved watch list never heard about it.

### Notes

- Nothing else in Everything Quests changed. The quest log book, world map overlays, nameplate icons, quest history and Chain Guide all work as before.
- If the tracker is missing, check that EQ Objective Tracker is enabled in your AddOns list. `/eqot status` prints what the tracker is doing and is the most useful thing to include in a bug report.

## [1.37.1] - 2026-08-02

Everything in this release came out of building EQ Objective Tracker, a new standalone tracker you will be able to run on its own without Everything Quests. Porting Everything Quests' code across surfaced five bugs in Everything Quests itself, and three of them had never been reported because nobody could see them.

### Bug Fixes

- **Equipment slot names in reward tooltips are now translated** - the gear comparison line on a quest reward showed its slot in English no matter what language the client was set to. All 21 slot names now come from the game's own text, so they match the wording on the item tooltip you are comparing against and are correct in every language.
- **A cloak reward no longer says "go back"** - the slot name for a cloak shared a phrase with the Chain Guide's navigation button, so French, Russian and Korean players comparing a cloak read the word for "go back" where the slot name should have been.
- **The reward chest tooltip works again** - hovering the chest icon on a scenario bonus objective silently did nothing. The icon sat underneath the panel's own drag region, so the hover never reached it.
- **The drag ghost is readable again** - reordering quests by hand showed a solid red block that covered the row you were dropping onto. It is now a gold-outlined label that matches the width of the row you picked up, and you can see through it to the row underneath.
- **The profile list is sorted** - the profile dropdown listed profiles in no particular order, and the order could change between sessions without you touching anything.

## [1.37.0] - 2026-07-31

A batch of tracker fixes, most of them colors and text that ignored your settings, plus the Chain Guide now recognizes the patch 12.0.7 storyline under the campaign name the game itself uses.

### Bug Fixes

- **The scroll bar thumb no longer stays stuck on the solid color** - turning **Solid color thumb** back off left the thumb showing the flat color until you reloaded, and toggling the option again could not recover it. Current retail thumbs are plain textures rather than atlases, and only the atlas was being restored.
- **Endeavor requirements no longer show a double dash** - every requirement line in the Endeavors section read `- - 1 / 15 Quests completed`, because the game already supplies the bullet and Everything Quests added a second one. Completed requirements also had a stray dash sitting next to their checkmark.
- **Endeavor requirements show colored progress counts** - the whole line was drawn in flat grey, so a requirement's `0/15` never got the red, orange or green treatment that quest objectives, achievements and event objectives all use. Requirements with no count of their own still stay grey, as they do elsewhere.
- **Completed endeavor requirements and profession reagents follow your complete color** - both were locked to green and ignored **Use title color for completed quests**, which the Achievements and quest sections already honored.
- **Endeavor titles follow your title color** - the title color and **Use class color** options both name endeavor titles, but the Endeavors section never applied either and its titles stayed Blizzard yellow.

### Improvements

- **The Chain Guide now knows The Curse of Ula'tek** - the patch 12.0.7 storyline was listed as "Revelations (12.0.7)" with its five questlines sitting loose below the zones. It now carries the campaign name the game uses, sits with the other campaigns, and renders as a campaign map with its chapters in order: Legacy of the Amani, An Island of Fangs, Ghosts of the Past, Original Sin, and The Battle for Atal'Utek.

## [1.36.0] - 2026-07-26

An optional card layout that gives every tracked row its own bordered panel, plus a rewrite of profession reagent counting that fixes four separate ways it could report the wrong numbers.

### New Features

- **Card layout for the tracker** - a new **Quest Rows** section under `/eqs` > Appearance switches the tracker from plain rows to a **Card** layout, which draws every quest, achievement, endeavor, tracked recipe and world quest on its own bordered panel. Background color, border color, border thickness and padding are all adjustable, and cards can optionally be tinted by quest type so campaign, legendary, dungeon and raid quests stand out at a glance. **Plain** remains the default, so nothing changes until you switch it on.

### Bug Fixes

- **Profession reagents now count every quality tier** - the Profession section only counted the lowest quality of a reagent, so a bag full of rank 2 or rank 3 materials could still read as 0 held. It now sums all qualities the way Blizzard's own tracker does.
- **Tracked recrafts are no longer broken** - a recraft was never recognized as one, so it was mislabeled, listed the reagents of the normal recipe instead of its own, collapsed into a single row when the same recipe was tracked both ways, and could throw an error when untracked.
- **Required modifying slots and currency reagents no longer vanish** - both were skipped entirely by the Profession section despite counting toward the craft.
- **Variable-quantity reagent slots show a range** - a slot that accepts a variable amount used to show a count against zero.
- **The tracker's content column is now centered** - with the tracker background on, rows sat 4 pixels from the left edge but 22 from the right.

### Improvements

- **The recraft label follows your language** - it previously used a hardcoded English suffix regardless of your game client.
- **French and Russian translations** updated for the new options. Thanks to Zox (French) and Malevi4 (Russian).

## [1.35.0] - 2026-07-26

Customize the zone progress bar's texture and color, new Line Spacing and Header Spacing sliders for the tracker, and a Class color button in the color picker for players without ElvUI.

### New Features

- **Restyle the zone progress bar** - a new Bar Texture dropdown and Bar Color picker under `/eqs` > Appearance > Zone Bar Appearance let you change the bar's fill texture and color. Choose from seven bundled Everything Quests bar styles or any statusbar texture provided by SharedMedia and other media addons, each shown with a live preview in a scrollable list. Thanks to Da Warrior for the request.
- **Tracker line and header spacing** - two new sliders under `/eqs` > Appearance, **Line Spacing** and **Header Spacing**, add or reduce the vertical space between a quest's objective lines and around section headers, so you can fit more on screen or give the tracker more room to breathe. Thanks to Rhinoplasty for the line-spacing idea.
- **Class color button in the color picker** - for players without ElvUI, the color picker now has a **Class** button that sets any Everything Quests color to your class color.

### Improvements

- **French and Russian translations** updated for the new options. Thanks to Zox (French) and Malevi4 (Russian).

## [1.34.0] - 2026-07-15

A new option to scale the whole settings window, wider translation coverage, and a batch of smaller fixes and background performance improvements.

### New Features

- **Scale the settings window** - a new **Options Window Scale** slider under `/eqs` > General resizes the entire Everything Quests options window so you can make it larger or smaller to fit your screen. The setting is account-wide.

### Improvements

- **More of the interface follows your language** - several World Quest labels and status strings (time left, world quest, expired, ready to turn in, and others) that were shown in English regardless of your game client now use your language's translation.
- **Lighter in the background** - the World Quests section, profession reagent lookups, Quest History, and quest nameplate icons now do less redundant work on each refresh.
- **French and Russian translations** updated for this release. Thanks to Zox (French) and Malevi4 (Russian).

### Bug Fixes

- **Quest item buttons no longer stay blank after combat** - a usable quest item added to the tracker while you were in combat could show an empty button until the next update; it now paints correctly once combat ends.
- **A hidden tracker no longer catches clicks** - when the tracker was hidden during combat it could still intercept mouse clicks in its now-invisible area.
- **Quest objectives that loaded blank on login now fill in** - an objective line whose text had not yet streamed from the server could stay blank for the rest of the session.
- **Wiping Quest History now also clears the gold and trends data** - the per-day gold totals behind the Trends view used to survive a history wipe.
- **Chain Guide chapters no longer appear twice** - a campaign chapter could show under both its campaign and a zone questline until the guide was reopened.
- **"Reset all settings" now truly resets everything** - the window scale, What's New notice mode, and minimap-button visibility were left untouched despite the dialog's promise.
- **Assorted smaller fixes** to the History heatmap and timeline, the Endeavors header count, scenario header fonts, and several option hit areas, plus internal hardening so one failing module can no longer stop others from loading.

## [1.33.0] - 2026-07-11

New Everything Quests icons on quest nameplates, and the Quest History calendar now follows your own local day instead of server time - plus fixes to the Chain Guide, World Quest filters, and grouped-quest nameplates.

### New Features

- **New quest nameplate icons** - the marker over a quest enemy is now the Everything Quests crest in place of the default exclamation mark, and kill objectives use a custom skull. Thanks to DrahgunFyre for the suggestion.

### Improvements

- **Quest History follows your local day** - the activity heatmap, streak, and trends now group turn-ins by your own calendar day instead of server time, so a late-night quest counts on the day you actually did it. This also fixes day labels that could read one day early west of UTC.
- **Smoother History search** - typing in the History search box no longer re-runs the full search on every keystroke.

### Bug Fixes

- **Chain Guide campaign chapters no longer attach to the wrong zone** - on some setups a campaign's chapters could register under an unrelated zone category for the session, leaving the real campaign entry empty. They now register only under their own campaign.
- **Quest nameplate icons no longer skip your own quest in a group** - when a party member's quest for the same enemy was listed first, your own objective icon could be dropped. It now shows reliably.
- **World Quest faction filter now applies** - a dead code path meant a quest's own faction was never checked, so unchecking a faction on the map only partly filtered it. It now filters by the quest's faction as intended.

### Thanks

- Special thanks to **DrahgunFyre** for the nameplate icon idea and the steady stream of features, fixes, and reports that keep shaping Everything Quests.

## [1.32.0] - 2026-07-08

A large bug-fix and polish release, plus a new scenario text-size option. Several tracker filters and hide options that quietly did nothing now work the way they should.

### New Features

- **Scenario text size** - a new **Criteria Text Size** slider under `/eqs` > Appearance > Scenario resizes the objective lines inside scenarios and delves, which used to render noticeably smaller than the rest of your tracker text.

### Bug Fixes

- **"Show only quests in current zone" no longer empties the tracker** - the filter was comparing quest-log group headers (often "Campaign") against your zone name and hiding everything. It now uses the quests actually on your current map.
- **The tracker's hide options actually hide it now** - "hide in combat", "hide in instances", "hide in Mythic+", and "hide when the map is open" were being silently blocked under Midnight (the tracker owns protected quest-item buttons). The tracker now fades out reliably in all four cases.
- **"World quests" tracker filter now works** - the checkbox had no effect before.
- **Currency quest rewards show in tooltips again** - they stopped appearing after a Midnight API change, and reputation World Quests are now categorized correctly in every language.
- **No more phantom World Quest rows** - a tracked World Quest that expired could come back as a ghost row after every login. Expired tracked World Quests are now pruned, and right-click Track/Untrack targets the correct quest and recognizes quests Blizzard is already watching.
- **Distance sort includes ready-to-turn-in quests** - they were stranded at the bottom instead of sorted by how close the turn-in is.
- **New Profile asks before overwriting** - creating a profile with the same name as an existing one now prompts for confirmation instead of silently replacing it.
- **Pinned quests keep updating** - a pinned quest you were not watching could freeze and stop refreshing its objectives.
- **"Reset filters to defaults" re-checks the watched-only box** correctly.
- Assorted stability fixes to the Chain Guide, the Zone Progress bar, and the scenario banner.

### Improvements

- **Lighter in the background** - the scenario tracker, Bonus Objectives HUD, quest-completion sound, and internal event handling are now debounced and coalesced, several retry loops are capped, and the tracker no longer rebuilds itself while it is hidden.
- **French and Russian translations** updated for this release. Thanks to Zox (French) and Malevi4 (Russian).

### Thanks

- Special thanks to **Agaman** - thanks for the codework on this one, your help has been extremely helpful.

## [1.31.0] - 2026-07-07

Two tracker-customization features plus three bug fixes. Both new options are off by default, so nothing changes unless you turn them on.

### New Features

- **World Quests height** - when you have a lot of quests, the World Quests area used to get squeezed down to a line or two. Tick **Set a custom World Quests height** under `/eqs` > Tracker and drag the slider to give it as much room as you want. Off by default. Thanks to TheOneMVP.
- **Hide tracker in Mythic+** - a new option under `/eqs` > General tucks the tracker away during an active Mythic+ run and brings it back when the run ends, so it stays out of your way next to the dungeon timer. Off by default. Thanks to TheOneMVP.

### Bug Fixes

- **Tracker no longer shrinks with many quests** - the quest viewport was collapsing to a section boundary when your quest list overflowed the frame, cutting it down to a couple of lines. It now fills the height you set and scrolls the overflow. Thanks to ShodanDelacroix for the debug info that pinpointed it.
- **Quest-completion sound no longer plays at login** - on a cold login the sound tracker could capture its baseline before the quest log finished syncing, then mistake every already-complete quest for a fresh completion. It now only plays on a real incomplete-to-complete transition.
- **Fixed a flight-map error** - opening the flight map with a quest tracked could throw a Lua error (the taxi-node highlighter misread a map API's return values). Thanks to DrahgunFyre for the report.

## [1.30.2] - 2026-07-07

Bug-fix release: the quest tracker no longer shrinks after a relog.

### Bug Fixes

- **Tracker no longer shrinks after login** - with a background or border enabled, the tracker window collapsed to a few lines a moment after logging in, while the resize handle stayed far below. The bordered window now fills the full height you size it to, instead of hugging the quest content. Thanks to ShodanDelacroix for the detailed report.

### Improvements

- **Russian translation** - the "Campaign" term now uses the WoW-official spelling «Кампания». Thanks to Malevi4.

## [1.30.1] - 2026-07-06

Localization catch-up: French and Russian are back to full coverage for everything added in the last two updates. No feature, gameplay, or interface changes in this release.

### Improvements

- **French and Russian translations** - now cover all of the v1.30.0 additions (Bonus Objectives HUD, class-color options for titles and headers, custom header divider color, and independent header size) as well as the v1.29.0 tracker section-order and update-notice strings. Thanks to Zox (French) and Malevi4 (Russian).

## [1.30.0] - 2026-07-05

Make the tracker look the way you want, and never miss a delve's bonus loot. This release adds a movable Bonus Objectives HUD, a customizable section-header divider color, independent header text sizing, class-color options for titles and headers, and the full LibSharedMedia font list. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Bonus Objectives HUD** - A new movable on-screen checklist for the bonus objectives you might otherwise miss. In delves it tracks the bonus loot mechanics (Nemesis Strongbox packs and the Sanctified Banner) so you can grab the extra rewards before the boss. Turn it on under **/eqs > Tracker > Scenario Bonus Objectives**, drag it anywhere, and right-click to lock or reset. Off by default. Thanks to DrahgunFyre for the idea in the Discord.
- **Class color for titles and headers** - New "Use class color" toggles under **/eqs > Appearance** color your quest and achievement titles, and your section headers, with the class color of the character you are logged in on. Off by default. Thanks to ChipW0lf.
- **Custom header divider color** - The thin line under each section header (Quests, Campaign, and so on) is no longer locked to gold. Set any color under **/eqs > Appearance > Divider Line Color**. Thanks to ChipW0lf.
- **Independent header text size** - A new **Header Size Offset** slider under **/eqs > Appearance** sizes the section headers separately from the quest text, so they do not get oversized on a low UI scale. Thanks to ChipW0lf.

### Improvements

- **More fonts** - The font pickers now list every font registered through LibSharedMedia, including fonts added by other addons, instead of only the ones bundled with Everything Quests. Thanks to ChipW0lf.

### Bug Fixes

- **Clear button** - The Clear button next to Quest Title Color Override now resets the color swatch when clicked.
- **Zone bar font** - When the zone progress bar is set to "Same as tracker font", it now follows the main tracker font, size, outline, and shadow live.

## [1.29.0] - 2026-07-03

Make the tracker yours: reorder its sections however you like, move the World Quests panel to the top or bottom, and choose how — or whether — Everything Quests tells you about updates. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Reorder tracker sections** — Put the tracker's sections in any order under **/eqs > Tracker > Section Order**, using the up/down arrows to move Campaign, Quests, Profession, Endeavors, Achievements, and the Zone Progress bar. Thanks to DrahgunFyre for suggesting it in the Discord.
- **World Quests position** — A **Top / Bottom** switch in the same Section Order area moves the World Quests panel above or below your quests. It keeps its own scrollbar and size cap either way.
- **Quieter update notices** — Choose how you hear about new features under **/eqs > General > After an update**: a popup window (the default), a quiet clickable chat link, or nothing at all. You can also turn the popup off with its own "Don't show these again" checkbox.

### Improvements

- **Reliable option tooltips** — Hovering the individual buttons of a multi-choice setting (such as World Quests position or the Nameplate icon position) now shows its explanation tooltip next to the button.

## [1.28.0] - 2026-06-27

A new Chain Guide questline — **The Sunstrider Omnium** — plus quest-giver map pins for it and Void Acropolis, a fresh addon icon, a tracker layout fix so sections no longer crowd together, and correct "Ritual Site" labeling. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **The Sunstrider Omnium (Chain Guide)** — Added the Magisters' Terrace questline that unlocks the Omnium Folio as its own Chain Guide zone, with its full chain mapped out like the rest of the Midnight content.
- **Map pins for more chains** — Quest-giver map pins now show for *The Sunstrider Omnium* and *Void Acropolis* chains, so you can find each step on the world map (Void Acropolis had none before).

### Improvements

- **New addon icon** — The minimap button, Titan Panel, and AddOns list now use a new gold crest in place of the old book.

### Bug Fixes

- **Tracker sections no longer crowd together** — With a lot of quests, achievements, and world quests tracked at once, a section's header could appear with its contents cut off. The quest list now keeps its sections intact, and the World Quests area yields space and scrolls instead.
- **"Ritual Site" label** — Ritual Sites such as *Broken Throne* now show **Ritual Site** in the tracker's scenario header instead of **Delves**. They run on the delve system under the hood, so the game reported them as delves — the tracker now matches Blizzard's own wording.
- **Combat error in Ritual Sites** — Entering a Ritual Site or scenario while in combat (with a usable quest item tracked) could throw an "action blocked" error. The tracker now waits until combat ends to resize.

## [1.27.0] - 2026-06-26

The Chain Guide now covers **Void Acropolis** — its quest chains are mapped out so you can follow them like every other Midnight zone. Plus clearer right-click quest options, finer-grained Appearance sliders, and a world-quest panel that no longer overlaps its pull-tab. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Void Acropolis (Chain Guide)** — The Chain Guide now includes the Void Acropolis zone, with its quest chains — *Assault and Strike Back: Val* and *Umbral Blitz* — laid out so you can follow them step by step like the rest of the Midnight zones.

### Improvements

- **Clearer quest menu** — The two right-click options on a tracked quest now read more clearly: **Open in Map & Quest Log** (the game's quest map) and **Pop Out Quest Details** (Everything Quests' own detail panel).
- **Finer Appearance sliders** — The Appearance sliders (font sizes, shadows, border thickness, bar height, and so on) now adjust in 0.5 steps for more precise tuning.

### Bug Fixes

- **World Quest panel overlap** — The world-quest map panel no longer overlaps its pull-tab; the panel now sits clear of the tab.

## [1.26.0] - 2026-06-25

The world-quest popout on the world map is now a single docked panel that matches Blizzard's (and ElvUI's) quest-map tabs, and the tracker now resizes correctly when you drag it wider or narrower — the quest list and the scenario/delve banner stay in step. Korean is now fully translated. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### Improvements

- **World Quest map panel** — The world-quest popout on the world map is now a single docked panel (a reward summary plus a scrollable zone list) instead of separate floating boxes, and its pull-tab matches Blizzard's quest-map side tabs — including ElvUI's styling when its quest skin is active. Thanks to Malevi4 for the request.

### Bug Fixes

- **Tracker width** — The quest list now resizes with the tracker when you drag it wider or narrower (it previously stayed frozen at a fixed width), and the scenario / delve banner now lines up with the quest list instead of drifting to the right on a wider tracker. Thanks to Malevi4 for reporting it and helping track down the cause.

### Translations

- **Korean (koKR)** — Now fully translated, thanks to labrie75.

## [1.25.0] - 2026-06-23

Header bars get more style — a vertical-gradient option and soft, feathered edges — plus a one-click Reset to Defaults for the Appearance tab, which now scrolls. A duplicate "quest ready" popup is fixed, and Korean joins the translations. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Header bar styles & soft edges** — The Appearance tab's header bar now offers two styles — Header Bar 1 (a horizontal gradient) and Header Bar 2 (a vertical gradient) — plus a Soft edges option that feathers the bar's top, left, and right edges so it blends into the UI instead of sitting in a hard box. An Edge Softness slider tunes how soft those edges are. Thanks to Malevi4 for the requests.
- **Reset to Defaults (Appearance)** — A new button at the top of the Appearance tab restores only the appearance settings (fonts, colors, shadows, header bar, scroll-bar skin, zone-bar look) to their defaults, leaving filters, sections, sounds, and the zone bar's saved position untouched.

### Improvements

- **Scrollable Appearance tab** — The Appearance tab now scrolls inside the Options window, so it no longer runs off the bottom of the screen, and the header-bar controls sit in their own tidy section.

### Bug Fixes

- **Duplicate "quest ready" popup** — A campaign quest with a ready-to-turn-in popup could appear twice — once under the Campaign header and once under Quests. It now renders once, in the correct section.

### Translations

- **Korean (koKR)** — Everything Quests is now available in Korean, thanks to labrie75. Most of the addon is translated, with more on the way.
- **Russian (ruRU)** — A round of wording refinements from Malevi4, plus translations for the new strings.
- **French (frFR)** — Updated by Zox; all current strings are translated.

## [1.24.0] - 2026-06-22

The clickable quest-item button on a tracked quest moved to the left of the quest icon — easier to reach and a little bigger — and there's a new optional gradient "header bar" behind each section header for a look closer to the default Blizzard tracker. French and Russian are fully up to date again. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Header bars** — A new "Header bar" option in the Appearance tab draws a colored gradient bar behind each section header (Quests, Campaign, World Quests, and so on), for a look closer to Blizzard's default tracker. Off by default, with Bar Color and Bar Height controls.

### Improvements

- **Quest-item button moved left** — The clickable quest-item button (the one you press to use a quest's item) now sits to the left of the quest icon, where it's easier to click, and is slightly bigger. Its red border was removed, so it shows just the icon.

### Translations

- French (frFR) and Russian (ruRU) are fully up to date with the new strings — thanks to Zox and Malevi4.

## [1.23.0] - 2026-06-21

A batch of community-requested features (thanks, Malevi4). The scenario / delve banner can be aligned and resized, the quest right-click menu is now fully translatable and can open quests on Wowhead, the nameplate quest icons can be repositioned and resized, and the world map's world-quest list now tucks away behind a tab for a cleaner map. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Scenario banner alignment & size** — A new "Banner Alignment" (Left / Center / Right) and "Banner Text Size" control in the Appearance tab's Scenario group move the delve / scenario banner within the tracker and resize its Stage and name text.
- **"Search on Wowhead" in the right-click menu** — Right-clicking a quest (or a world quest) now offers "Search on Wowhead," which opens a copy-ready link to that quest's Wowhead page.
- **Nameplate quest-icon position & size** — The quest icon + count on enemy nameplates can now be placed Left, Right, Above, or Below the nameplate, with separate sliders for the icon size and the count text size (General tab).
- **World-quest map list behind a tab** — On the world map, the world-quest summary and list now tuck behind a small world-quest tab on the map's right edge. Click it to show or hide them — the map stays clean by default, and the quest pins are unaffected.

### Improvements

- **Translatable right-click menu** — Every entry in the tracker's quest right-click menu (and the world-quest menus) is now translatable, so it shows in your language instead of English.

### Translations

- The new text is in English for now; Russian and French updates are on the way — thanks again to Malevi4 and Zox.

## [1.22.1] - 2026-06-18

Localization update — the Russian and French translations are now fully up to date with the latest features. Thanks to Malevi4 (Russian) and Zox (French) for the continued translation work.

### Translations

- **Russian (ruRU)** — Updated by Malevi4; all current strings are translated.
- **French (frFR)** — Updated by Zox (batch 5); all current strings are translated.

### Other

- Some code cleanup.

## [1.22.0] - 2026-06-18

A round of fixes plus Appearance and World-Quest improvements after the Chain Guide overhaul. Your regular quests no longer occasionally fail to load on login, untracking a profession recipe no longer errors, progress-bar achievements show their count, and the Options and Chain Guide windows can't overlap. The text shadow gains a size slider and a separate scenario-banner shadow, and the world map's world-quest list now scrolls instead of filling the screen. Missed a previous version? Every release's notes are in the About tab's changelog (`/eqs` > About).

### New Features

- **Shadow Size slider** — A new Appearance slider sets how far the tracker's text shadow is cast — a larger, more pronounced shadow at higher values. Works alongside the existing Text Shadow toggle and color.
- **Separate scenario-banner shadow** — A new "Scenario" group in the Appearance tab gives the delve / scenario banner its own text-shadow toggle, color, and size, independent of the main tracker text. A tooltip notes that it's separate.
- **Scrollable world-quest list on the map** — In zones with many world quests (older expansions especially), the world map's quest list now scrolls inside a compact panel (about ten rows tall) instead of growing down the screen. Every quest is still listed (just scroll) and pinned on the map; the reward-type and per-faction filters in the World Quests options trim it further.

### Improvements

- **Appearance tab cleanup** — The color swatches line up in clean columns, a new "Tracker" header sits over the background and border options, and the scroll-bar ("Tracker Skins") options moved beside the Zone Bar group.
- **No more overlapping windows** — Opening the Options or the Chain Guide now closes the other; the two are similar-sized windows that previously could stack and overlap each other's text.

### Bug Fixes

- **Quests sometimes didn't load on login** — On a slow cold login the tracker could come up showing only world quests, with your regular quests missing until a `/reload`. The quest cache now rebuilds itself the moment the quest log finishes loading, so the tracker fills in on its own.
- **Profession untrack error** — Right-clicking "Untrack Recipe" on a tracked profession recipe could throw a `SetRecipeTracked` error; fixed.
- **Progress-bar achievements showed no count** — Tracked achievements that use a progress bar (for example "61/100") displayed only their title; they now show the X/Y count like other achievements.

## [1.21.1] - 2026-06-17

**Hotfix.** A change in v1.21.0 ("Group up for world bosses") accidentally put the group-finder eye on **every** world quest. This release corrects it so the eye appears only on the world bosses and group quests you'd actually want a group for — matching Blizzard's own tracker. Thanks to everyone who reported it.

### Bug Fixes

- **Group-finder eye no longer shows on every world quest** — v1.21.0 gated the eye on `C_LFGList.GetActivityIDForQuestID`, which returns an activity for ordinary world quests too, so the eye appeared on all of them. The tracker now uses the same signal Blizzard's own objective tracker uses — `C_LFGList.CanCreateQuestGroup` (via the cached `QuestUtil.CanCreateQuestGroup` wrapper) — so the eye shows only on world bosses / elite / dungeon / raid world quests. This also restores the eye on world bosses that the earlier `isElite`-only check used to miss.

## [1.21.0] - 2026-06-17

**The Chain Guide overhaul is complete.** This release ships **Phase 3 — map integration**, the final phase of the three-part rebuild: track a chain and its quests appear as pins on your world map with a waypoint that advances itself as you go. It also adds the new patch 12.0.7 **"Revelations"** chains, a batch of tracker and achievement features suggested by **tanglies**, a wider world-boss group-finder button, and a round of polish. Huge thanks for sticking with the overhaul while it came together — it's finished now, so things will settle down. If anything looks off, please report it on Discord or in the CurseForge comments.

### New Features

- **Chain Guide overhaul, Phase 3 of 3 — map integration** — Open a chain and press **Track**, and that chain's quests appear as pins on your world map with your next step highlighted in gold. Your waypoint **auto-advances** to the next step as you turn quests in, it keeps following the chain even with the guide window closed, and it clears itself when the chain is finished. Press **Untrack** to stop. A "Show tracked chain on the world map" toggle lives in the Chain Guide options.
- **New "Revelations (12.0.7)" chains** — The Chain Guide now covers the patch 12.0.7 storyline: *Legacy of the Amani* (a full branching chain) and the lead-up to the *March on Quel'Danas* raid (*An Island of Fangs*, *Ghosts of the Past*, *Original Sin*, *The Battle for Atal'Utek*). Brand-new content, so some details fill in as the patch settles.
- **Independent title size** — A new Appearance slider sizes quest and achievement *titles* separately from the objective text. *(Suggested by tanglies.)*
- **Tracker text shadow** — A new Appearance option adds a drop shadow behind tracker text for legibility over bright or busy backgrounds, with a color picker. *(Suggested by tanglies.)*
- **Quick-access tracker buttons** — A cogwheel (opens Options) and a Chain Guide button at the top-right of the tracker, each with its own on/off toggle in the Tracker options. *(Suggested by tanglies.)*
- **Achievement quality-of-life** — A "simplify" mode for tracked achievements (shows only remaining criteria), right-click a tracked achievement to untrack it, and left-click to open it in the Achievement panel. *(Suggested by tanglies.)*

### Improvements

- **Group up for world bosses** — The group-finder button now appears on *every* group-listable world boss in the tracker, not just some; one click opens the Premade Group Finder filtered to that fight.
- **Easier Chain Guide resize** — The resize grip in the bottom-right corner is larger, clearer, and has a generous grab area, with a "Drag to resize" tooltip.
- The Chain Guide's **Track** button reads **Untrack** while a chain is being followed.

### Bug Fixes

- Fixed the Chain Guide's "next step" sometimes pointing at the opposite faction's version of a quest, which could send you to a quest you couldn't pick up.
- Trimmed war-table / campaign-meta quests that aren't part of a storyline out of the chains, so each chain ends at its real final quest (and progress counts no longer include quests you can't complete).

## [1.20.0] - 2026-06-16

**Phase 2** of the Chain Guide overhaul is here, and it's a big one. Every quest chain in Midnight now draws as a real *branching graph* instead of a flat list, inside a redesigned window you can resize, drag to pan, and collapse. Phase 1 made the guide *actionable*; Phase 2 makes it a *map*. Phase 3 (map integration with quest-giver pins and auto-advancing waypoints) is next. As always while the overhaul is underway, expect more frequent updates — and if anything looks off, let me know on Discord or in the CurseForge comments.

### New Features

- **Every chain is now a branching graph** — Until now a quest chain was drawn as a flat top-to-bottom list. As of this update, *every* quest chain in Midnight — all of Eversong Woods, Zul'Aman, Harandar, Voidstorm, Arator, and the full campaign — renders as a true branching tree. You can see which quests unlock which, where a chain splits into parallel paths, and where those paths rejoin.
- **Drag to pan** — Click and drag anywhere on the graph to move around the larger chains.
- **Resizable, collapsible window** — Drag the bottom-right corner to resize the Chain Guide (your size is remembered between sessions), and use the new collapse button to hide the side list so the graph fills the whole window.

### Improvements

- More compact quest cards, so you see more of a chain at a glance.
- Scenario and dungeon titles are now centered in their banner.

### Bug Fixes

- Opening the options from the Chain Guide no longer leaves the two windows overlapping on top of each other.

## [1.19.0] - 2026-06-14

This release begins a multi-phase overhaul of the Chain Guide. **Phase 1** makes it *actionable* — it now tells you what to do next, shows rich quest info on hover, and can be searched by name. (Phase 2 will add a real branching graph you can drag and explore; Phase 3, map integration with quest-giver pins and auto-advancing waypoints.) Expect more frequent updates than usual while the overhaul is underway.

### New Features

- **The Chain Guide shows your next step** — Open any chain and Everything Quests highlights the next quest you should do: a gold border, a **NEXT** tag, and a **Continue** button that sets your course straight to it (super-tracking it if it's already in your log, or pointing you to where to pick it up). Opening a chain auto-scrolls to where you are.
- **"On quest" tags** — Quests currently in your quest log are tagged **ON QUEST** in the guide, so you can see at a glance what you're already carrying.
- **Rich quest tooltips** — Hovering a quest in a chain now shows its difficulty level, objectives, and rewards — including the same gear-upgrade comparison the tracker uses, so you can tell whether a reward beats what you're wearing.
- **Search by name** — The Chain Guide's find box now accepts a quest *name* as well as an ID, and matches questline names too, jumping to the chain that contains your search.

### Improvements

- **Clearer chain nodes** — Each quest node now shows its difficulty level and ID, and a quest that's ready to turn in is highlighted in gold.
- **Now available in Russian** — Everything Quests has a full Russian (ruRU) translation, with updated French (frFR). The newly added Chain Guide text will be translated once the overhaul is complete.

### Bug Fixes

- **No more "action blocked" when getting directions in combat** — Clicking a quest in the Chain Guide while in combat could trip a taint error as the world map retargeted (a protected map call during combat lockdown). The map now waits until you leave combat to open; the quest is still super-tracked immediately, so the on-screen objective arrow guides you right away.

## [1.18.0] - 2026-06-13

### New Features

- **Search the Chain Guide by Quest ID** — The Chain Guide now has a **Find Quest ID** box in its navigation bar. Type a quest's ID (the universal number from sites like Wowhead) and Everything Quests jumps to the chain that contains it, rings the quest, and scrolls it into view. Because quest *names* are localized but quest *IDs* aren't, this lets players on a non-English client follow an English guide without translating names back and forth. If the ID isn't part of any chain Everything Quests knows, a Wowhead link is printed in chat instead. *(Suggested by Sparta | Phrenic.)*
- **Skin the tracker scroll bar** — A new **Tracker Skins** section on the Appearance tab lets you restyle the tracker's scroll bar: give it a flat single-color thumb with its own color and width, or hide the up/down arrow buttons. Off by default, so the stock bar is untouched until you enable it. *(Suggested by Fostot.)*
- **About tab** — A new **About** tab (the seventh) gathers the live version, copyable links (Discord, CurseForge, GitHub, Report a Bug), the user-facing slash commands, credits, and the full changelog. Open it directly with `/eqs about`.

### Improvements

- **The tracker background wraps your quests** — The tracker's background and border now hug just the visible quests instead of spanning the full frame height, and disappear entirely when nothing is tracked, so a short quest list no longer floats in a tall empty box. *(Contributed by Spydawg2233.)*
- **Cleaner option panels** — Every setting's grey explanatory text has moved into a hover tooltip. Mouse over any option to read what it does; the panels themselves now show clean, short labels.
- **Brighter brand red** — The Everything-suite red used for section headers, borders, and accents was brightened a little (it had always read a touch too dark in-game).

### Bug Fixes

- **Newly accepted quests track reliably** — A freshly accepted quest could occasionally fail to appear in the tracker. Everything Quests was adding it as an *automatic* watch, which the game silently drops once you pass its small auto-watch cap; it now adds a stable *manual* watch (the same as ticking the checkbox in the quest log), for both auto-track-on-accept and the tracker's right-click **Track Quest**.

## [1.17.0] - 2026-06-12

### New Features

- **Quest reward gear comparison** — Hovering a quest in the tracker now shows a tooltip with its rewards, and every equippable gear reward is compared against what you currently have equipped: it lists the reward's item level, your equipped item level for that slot, and whether it's an upgrade, a sidegrade, or lower. Pick-one-of-many quests compare *each* choice, an empty slot is flagged as a free equip, and rings/trinkets compare against the lower of your two equipped pieces. The same comparison now also appears on World Quest tooltips. *(Item-level only — it doesn't weigh stats or spec.)*

### Improvements

- **The tracker can stretch much taller** — The quest tracker's maximum height has been roughly doubled, so you can drag the bottom-right corner to keep far more quests in view at once (it still stays on-screen at smaller resolutions). *(Suggested by Spydawg2233.)*

## [1.16.0] - 2026-06-08

### New Features

- **Customize the floating zone progress bar** — A new **Zone Bar Appearance** section under the Appearance tab lets you restyle the floating zone progress bar: toggle its background and border, choose a border color, pick its font from the bundled typefaces, and set custom colors for the zone-name header and the x/x count. Defaults match the previous look, so nothing changes until you adjust it. *(The bar is off by default — enable it under Tracker → Zone Progress Bar.)*

### Improvements

- **More of the interface displays in French** — The History window's tab labels and the Chain Guide's navigation buttons and per-chain progress counts (made translatable in 1.15.0) now display in French on a French game client. Every other language continues to display in English. *(French translation contributed by Zox.)*
- **Lighter Chain Guide rendering** — Viewing and navigating between chains in the Chain Guide allocates less memory per render, bringing it in line with the rest of the add-on's pooled UI.

## [1.15.0] - 2026-06-07

### New Features

- **Options button in the Chain Guide** — The Chain Guide window now has an **Options** button in its navigation bar that opens the settings straight to the Chain Guide tab, so you no longer have to retype `/eqs` to get back to its options. *(Suggested by Zox.)*

### Improvements

- **More of the interface is translatable** — The History window's tab labels (Quests, Streak, Chain Timeline, Activity, Stats, This Session), the Chain Guide's navigation buttons, and its per-chain progress counts are now wrapped for translation. They display in English until translated and fall back to English automatically.
- **French translation refinements** — A round of wording and fit corrections to the French (frFR) translation. *(French translation contributed by Zox.)*

## [1.14.1] - 2026-06-06

### Bug Fixes

- **Zone progress bar now shows up reliably** — On some characters the zone progress bar could come up empty and show nothing. It was relying on a live questline scan that returns nothing for a zone you've already finished, so a character who had completed a zone's questlines saw a blank bar. The bar now measures against Everything Quests' built-in Midnight questline data instead, so it works the same on every character — fresh alt or fully-completed main — and resolves correctly in every language. Completion is still counted per character.

### Improvements

- **French translation complete** — The French (frFR) translation is now fully complete: the entire Everything Quests interface displays in French on a French game client (every other language continues to display in English). *(French translation contributed by Zox.)*

## [1.14.0] - 2026-06-06

### New Features

- **French translation (frFR) and localization support** — Everything Quests now ships with a full localization layer and French translations. On a French game client the entire options window appears in French, with more of the interface following in a future update; every other language keeps displaying in English, and any untranslated text falls back to English automatically. *(French translation contributed by Zox.)*
- **Zone progress bar** — An optional bar showing approximate questline progress for your current zone. It can float as a movable standalone bar (drag to move; right-click to lock or reset) or appear as a section on the on-screen tracker. Off by default — enable it under Tracker → Zone Progress Bar, and adjust its size under Appearance → Zone Bar Scale.

### Improvements

- **Options window sizing** — The options window is a little taller and the History tab's description text is wider, so longer text (including translations and larger fonts) no longer pushes the bottom buttons off-screen.

## [1.13.1] - 2026-06-05

### Bug Fixes

- **Fewer "secret value" Lua errors from the world map** — Under Midnight's new UI-protection rules, hovering a point of interest on the world map can throw a "secret value" Lua error from Blizzard's own tooltip code, which names whichever add-on was last active on the shared tooltip. Everything Quests now draws its world-map pin tooltips (world quests, quest pins, and the Chain Guide map button) on its own private tooltip instead of the shared one, and no longer piggy-backs on Blizzard's world-quest refresh — so EQ stays off that shared path and is far less likely to be the add-on blamed. This is a Blizzard-side issue that affects many add-ons; these changes reduce EQ's involvement but can't make the error disappear entirely.

## [1.13.0] - 2026-06-03

### New Features

- **Tracked achievements in the tracker** — Achievements you're tracking from the Achievement UI now appear in their own **Achievements** section of the on-screen tracker, with each achievement's criteria listed beneath it: a checkmark for finished criteria and a colorized "X/Y" for measured progress. The section hides itself when you're not tracking anything, and can be turned off under Tracker → Tracker Visibility. *(Suggested by LightsBeacon on Discord.)*
- **WoW's default fonts** — The Appearance font dropdown now includes WoW's own built-in fonts — **WoW Default (Friz Quadrata)**, **WoW Arial Narrow**, and **WoW Morpheus** — alongside the bundled selection, for anyone who prefers the stock look. *(Suggested by Zox on Discord.)*
- **Auto-list current-zone world quests** — A new Tracker option lists every world quest in your current zone in the tracker's World Quests section without having to track each one individually. It's off by default (in WQ-dense zones the list can get long), and these auto-listed quests drop off when you leave the zone. *(Suggested by Zox on Discord.)*
- **Click a world quest on the map to track it** — Left-clicking a world quest pin on the world map, or a row in the zone world-quest list, now both follows it (waypoint arrow) and lists it in the tracker — no more right-click → Track step just to make a selected world quest show up. *(Suggested by Zox on Discord.)*

### Improvements

- **World Quest icons in the tracker** — Rows in the tracker's World Quests section now show Blizzard's stock world-quest icon — the brown ring with the gold star (plus the PvP / dungeon / profession / boss / etc. variants where they apply) — and the ring turns gold when that World Quest is focused (super-tracked).
- **Optional Blizzard-style quest clicks** — A new "Split quest click" option (Tracker tab, off by default) changes left-click behavior to match Blizzard's tracker: click the quest's icon/circle to focus it, and click the title to open it in the quest log. With the option on, World Quest rows in the tracker behave the same way — click the icon to focus, click the title to open the quest's map details. With the option off, EQ keeps its existing behavior where a left-click anywhere on the row focuses the quest. *(Suggested by Zox on Discord.)*

## [1.12.0] - 2026-06-03

### New Features

- **Sort your Quest History** — The Quests tab now has a **Sort** control (next to the Type filter) with a clickable direction arrow. Sort by **Date**, **Name** (A–Z), or **Type**, and click the arrow to flip between ascending and descending. Undated "before tracking" entries always group at the bottom of a date sort, and the Export and result count follow whatever sort you've chosen. The "Hide undated" checkbox moved to the far right of the toolbar.

### Bug Fixes

- **Manual tracker order no longer loses hidden quests** — When you drag-reorder the tracker in Manual sort mode, quests that were filtered off-screen at the time (unwatched, wrong zone, or a collapsed section) used to lose their place and drop to the bottom when they reappeared. Their position is now preserved.
- **Color picker keeps transparency on Cancel** — Cancelling out of a color picker (background, border, title color, etc.) could snap the color back to fully opaque, losing your transparency setting. Cancel now restores the exact color you started with.
- **Quest History list quirks** — Fixed a case where an expanded quest row in the Chain Timeline could show a stale tooltip or click action carried over from another row.

### Improvements

- **Stable sort order** — Quests with the same sort key (same zone, level, or type) no longer shuffle position between refreshes; they now hold a consistent, predictable order.

### Maintenance

- Consolidated several hand-rolled "wait then refresh once" timers across the tracker, Chain Guide, and History windows into a single shared helper, and removed per-frame work that re-created click handlers on every redraw — less wasted memory, no behavior change.

## [1.11.0] - 2026-06-01

### New Features

- **Stats tab with Trends** — The Quest History window's "Totals" tab is now "Stats" and adds a new **Trends** view that charts your quests, XP, and gold over time. Switch between daily (last 30 days) and weekly (last 12 weeks), compare the current period to the one before it with at-a-glance cards, and view it account-wide or for a single character. The original lifetime totals are still there under the same tab.
- **Real gold tracking** — The Trends "Gold" figure now counts *all* the gold you earn — loot, vendor sales, quest rewards, everything — bucketed per day, not just quest-reward coin. It starts counting from this update forward (gold earned before now can't be reconstructed) and re-baselines at each login so offline mail and auction-house changes aren't miscounted.
- **Community Discord** — There's now a "Join our Discord!" link at the top of the Options window and in the What's New popup. Since the game can't open a browser, clicking it shows the invite link pre-selected so you can copy it with one Ctrl+C.

### Improvements

- **World Quest titles follow your color scheme** — World Quest titles in the tracker now use the title color you chose in Appearance instead of always rendering yellow, so every section matches the rest of your colors.

## [1.10.0] - 2026-05-31

### Bug Fixes

- **No more Lua errors or "blocked action" messages from the world map** — With the map open, switching it to a tracked quest's zone or hovering a point of interest could throw a "secret value" Lua error (in the map's tooltip) or an `ADDON_ACTION_BLOCKED` message. Under Midnight's new UI-protection rules, Everything Quests was refreshing the map's own quest and point-of-interest markers from an unsafe context. Those refreshes have been removed or made safe, so the map is clean again.
- **Chain Guide "Get Directions" points to your next step** — Clicking a quest you haven't reached yet in a chain used to drop a waypoint where you were standing, with nothing to pick up there. It now sends you to the earliest quest in that chain you can actually act on, and tells you which step that is.

### Removed

- **"Zoom world map to focused quest's zone" option** — This was the main cause of the map errors above, and there is no way to keep it working safely under Midnight's map-protection rules. The world map no longer re-centers itself when you open it; use the map's own navigation or "Get Directions" to jump to a quest's zone.

## [1.9.0] - 2026-05-31

### New Features

- **Session summary** — A new "This Session" view recaps your current play session: quests completed, quest XP and gold earned, time played, quests per hour, and level-ups. Type `/eqs session` for a quick chat recap, or open the new "This Session" tab in the Quest History window (`/eqs history`). A session starts when you log in and continues across `/reload`; it resets the next time you log in fresh.

### Maintenance

- Consolidated the frame-pool "acquire" pattern that around ten UI surfaces each hand-rolled into a single shared helper — no behavior change, just less duplicated code.
- Removed an unused, never-displayed localization scaffold (Everything Quests is English-only, so it did nothing).

## [1.8.1] - 2026-05-31

### Bug Fixes

- **Tracker no longer throws a "blocked action" error in combat** — With a usable quest-item button showing in the tracker, entering combat could repeatedly trigger an `ADDON_ACTION_BLOCKED` error as the tracker tried to resize itself — a protected action while in combat. The tracker now holds that resize until combat ends and catches up automatically, so the error spam is gone. Your quest blocks still update live during the fight.
- **Fixed an empty box appearing in a few hints** — A right-arrow symbol used in the locked-tracker tooltip, a Chain Guide label, and the `/eqs dir` diagnostic showed as a missing-glyph box in the default game font. They now use plain text that renders everywhere.

### New Features

- **`/eqs whatsnew`** — Type `/eqs whatsnew` (or `/eqs changes`) at any time to reopen the "What's New" summary. It's also listed under Slash Commands in the General options tab.

### Improvements

- **Sort Order buttons fit on one row** — At the default UI font the tracker's Sort Order options used to wrap the "Manual" button onto a lonely second row. The row is now spaced to stay on a single line (the "Recently Added" sort is labeled "Recent"), so it reads as one clean line.

## [1.8.0] - 2026-05-30

### New Features

- **Color completed quests with your title color** — A new Appearance option, "Use title color for completed quests (instead of green)" (on by default), makes completed quests use your chosen tracker title color (for example your class color) in place of the default "ready to turn in" green — for both the quest title and its completed objective lines, in the main tracker and the World Quests section. The checkmark still marks objectives done. If you haven't set a title color, completed quests stay green.
- **Lock the tracker's size, not just its position** — The "Lock tracker" option (General) now also locks the tracker's dimensions and hides the resize grip, so a locked tracker can't be resized either. Combat-safe.
- **Quest history safety net** — Everything Quests now keeps rolling backups of your account-wide quest history in a separate saved file, automatically restores it if the live history ever loads empty or a character's entries go missing (with a one-time notice), and backfills a newly seen character's past completions once so an alt is never silently empty. A deliberate "wipe history" still clears everything, backups included.

### Improvements

- **"Keep focused quest after relog" is now on by default** — The game's waypoint arrow returns to your last focused (super-tracked) quest when you log back in. Toggle it under General.
- **Options window no longer clips its own text** — Widened the options window, wrapped the Tracker tab's Sort Order buttons to a second row, and bounded the "Manual" sort hint to its column, so long setting descriptions and hints no longer run off the edge or into the next column.

### Bug Fixes

- **"Get Directions" leads to the right place for quests you already have** — For a quest in your log, Get Directions now hands off to the game's own quest navigation, pointing at your current objective — or the turn-in once the quest is complete — instead of the spot where you originally picked the quest up. TomTom users get a pin at the objective (or the turn-in for completed quests).

### Developer

- Added a `/eqs dir` diagnostic that prints every coordinate source the Get Directions resolver consults for the super-tracked quest, each in yards, plus the source it picks.

## [1.7.0] - 2026-05-29

### New Features

- **"Recently Added" highlight** — Quests you just picked up now show a "NEW" tag next to their name in the tracker for about an hour, so a fresh quest is easy to spot in a long list. There's also a new "Recently Added" sort order that floats your newest quests to the top. Toggle the tag under Tracker in Options.
- **Sort your tracker by distance** — A new "Distance" sort order arranges your tracked quests by how close they are, so the next thing you can reach sits at the top. Find it under Sort Order on the Tracker options tab.
- **"Get Directions" on any quest** — Right-click a quest in the tracker and choose "Get Directions" to drop a map waypoint at the quest and open the map there — using TomTom if you have it, otherwise the game's own waypoint. This is the same routing the Chain Guide uses.

### Improvements

- **Lighter on memory over long play sessions** — Everything Quests' account-wide Chain Guide cache (per-character completions and saved quest locations) now trims entries it no longer needs instead of growing forever. A "Prune stale entries now" button and a cache-size readout were added to the Chain Guide options tab. Everything pruned is rebuilt automatically when needed, so nothing is lost.
- **World quests and just-loaded quests show their real names** — Places that previously showed "Quest #12345" for a moment (world quests, and quests whose names hadn't arrived from the server yet) now resolve the proper title wherever the game makes it available.

### Bug Fixes

- **No more "blocked action" errors from the tracker in combat** — Hiding the tracker in combat (the "hide in combat" option), and dragging or resizing it during a fight, could trigger a "blocked action" error (ADDON_ACTION_BLOCKED) because those actions touch protected frames mid-combat. Both now wait until combat ends, so the tracker behaves cleanly.
- **Fixed a world-map slowdown on long sessions** — The world-map quest-pin code was re-hooking itself every time you changed zones or reloaded, slowly piling up duplicate handlers over a session. It now hooks once.
- **Cached character class is recorded correctly** — The Chain Guide's per-character cache was always storing an empty class because of a code slip; it now records the right class and repairs existing entries.

## [1.6.2] - 2026-05-25

### Bug Fixes

- **Fixed an error from the quest-complete sound on some system messages** — On Midnight, certain system chat messages are now "secret values" that an addon can't read. The quest-complete sound's chat-text fallback (which listens for "...completed." lines to catch instant turn-ins) tried to read those and threw a Lua error (QuestSound.lua:118, "secret string value"). It now skips secret messages. Completion sounds are unaffected — quests that enter your log still trigger the sound through the normal path.

## [1.6.1] - 2026-05-25

### Bug Fixes

- **No more "blocked action" error on logout or quit** — Everything Quests' own confirmation dialogs (reset settings, new profile, wipe history, clear chain cache, the move-it hint, and the ElvUI nameplate prompt) were built on Blizzard's shared popup system, which on Midnight could leave EQ blamed for a taint error (ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN) when you logged out or quit — because that system recycles the same frames Blizzard uses for its Quit / Logout dialogs. All of EQ's dialogs now use their own self-contained window, removing EQ from that system entirely so it can't taint those dialogs.

## [1.6.0] - 2026-05-25

### New Features

- **Quest icons on nameplates** — Quest objective enemies now show a "!" right on their nameplate, along with the amount you still need (a count like 3, or a percent like 76% for progress objectives). Kill objectives get a skull, talk-to objectives a chat bubble, and use-item objectives the quest's item icon. See at a glance which mobs count for your quests instead of guessing. On by default; toggle it under General in Options. If ElvUI (which has its own version) is installed, EQ defaults this off and asks once which you'd prefer, so you never get duplicate icons.
- **"Quest Discovered!" popup boxes** — Newly discovered and ready-to-complete quests now show a clickable callout box at the top of the Quests section of the tracker, matching the game's default behavior (which EQ's tracker previously hid). Click a box to open the quest. Toggle under Tracker in Options.

### Improvements

- **Directions on ready-to-turn-in quests** — Quests that are ready to hand in but have no checklist objectives (the "go talk to someone" kind) used to show a bare title with nothing underneath. They now show where to go — e.g. "Speak to Mothkeeper Wew'tam in the Den." — matching what Blizzard's and ElvUI's trackers display.

### Bug Fixes

- **Quest-item buttons no longer error in combat** — The usable quest-item button on a tracker row could trigger a "blocked action" error (ADDON_ACTION_BLOCKED) while you were in combat. The button is now anchored so it never makes its tracker row combat-protected, so the tracker updates cleanly during a fight.
- **Hardened popups against a quit-time error** — Everything Quests' own dialogs now use a high popup slot so they can't taint Blizzard's protected Quit / Force Quit dialog (which could otherwise blame EQ for an ADDON_ACTION_FORBIDDEN error when you quit).

## [1.5.0] - 2026-05-24

### New Features

- **Delves and dungeons show their real name** — The tracker's instance header is now two-tier: a small category line ("Delves", "Dungeon", "Follower Dungeon", "Raid") sits above the specific name of where you actually are ("The Darkway", "Windrunner Spire", and so on). Before, a delve header just read "Delves" with no hint of which delve you were in. This works for every instance type without a hard-coded list, so new content is named correctly too.
- **Hide the tracker scroll bar** — A new "Hide scroll bar" option on the Tracker options tab removes the scroll bar entirely; you scroll with the mouse wheel instead. Thanks to Spydawg2233 for the suggestion.
- **Mouse-wheel scrolling** — Both the quest list and the World Quests list now scroll with the mouse wheel, whether or not the scroll bar is showing.
- **Everything Quests now appears in Blizzard's AddOns options list** — Game Menu > Options > AddOns now includes an Everything Quests entry with a button that opens the full options window. Typing `/eqs` still works as before.

### Bug Fixes

- **Normal dungeons no longer mislabel as "Follower Dungeon"** — Follower Dungeons and normal dungeons report the same scenario type to the game, and the header was tagging every normal dungeon as a Follower Dungeon based on that alone. It now tells them apart by difficulty, so a normal dungeon reads "Dungeon" and a Follower Dungeon reads "Follower Dungeon".

## [1.4.1] - 2026-05-21

### Bug Fixes

- **Reloading no longer drops your focused quest** — Reloading the UI (`/reload`) was clearing the quest you had super-tracked, forcing you to re-select it. The login cleanup that removes a stale waypoint arrow now only runs on a genuine fresh login or client restart, so reloads (and zone changes) leave your focused quest exactly as it was.

### Improvements

- **Scenario header auto-names anything it doesn't recognize** — Instead of falling back to the generic word "Scenario" for content types it hasn't been taught (open-world events, story scenarios, future Midnight content), the tracker now shows the scenario's own name from the game. Known categories like Delves, Dungeon, Follower Dungeon, and Raid still use their friendly labels.

## [1.4.0] - 2026-05-20

### New Features

- **Quest History** — An account-wide log of every quest you turn in, kept across all your characters. Open it with `/eqs history` or from the new **History** tab on the options window. Five views:
    - **Quests** — searchable, filterable list (by character, date range, or quest type). Right-click any row to jump straight to that quest's chain in the Chain Guide.
    - **Streak** — your current and best daily turn-in streaks across the whole account.
    - **Chain Timeline** — every chain you've made progress in, with per-quest dates. Click a chain to expand it; right-click to open it in the Chain Guide.
    - **Activity** — a 13-week heatmap showing how many quests you turned in each day.
    - **Totals** — gold and XP earned per character, plus your single biggest gold and XP rewards.
  - **One-time backfill** — A "Populate from past completions" button on the History options tab walks the list of quests this character has already completed (according to the game's own record) and adds them to history. These show as "(before tracking)" since the game doesn't tell us when they happened.
  - **Quest names fill in automatically** — Backfilled entries may show as "Quest #12345" at first because Blizzard hasn't sent your client their names yet. EQ asks the server for them in the background; names trickle in over a minute or two. A **Re-scan names** button in the History window (and on the options tab) re-runs the lookup if you want to nudge it.
  - **Export** — An Export button on the History window copies the currently visible data to your clipboard as plain text, ready to paste anywhere.
- **Completion date in Chain Guide tooltips** — Hover any quest in the Chain Guide and you'll now see when (or whether) you've completed it.
- **Smarter Scenario header** — The Scenario section header now identifies Follower Dungeons, regular Dungeons, Raids, Battlegrounds, etc. instead of always saying "Scenario." A new `/eqs scenario` diagnostic prints everything Blizzard tells us about the current instance — useful if you ever see a generic label and want to report it.
- **"Keep focused quest after relog"** — New option on the General tab, off by default. When off, EQ clears whatever quest the game restored as super-tracked at login so you don't log in to a stale waypoint arrow (or TomTom marker).

### Improvements

- **What's New popup** — A one-time popup at login walks you through the v1.4.0 additions. Dismiss it once and it won't come back; the next major release will bring a fresh one.
- **Tracker drag-and-drop is gentler on memory** — The throttled drag-ghost update was rebuilt around a shared elapsed counter so a single quest reorder no longer allocates a function per frame.
- **Safety-net hook for world-quest data** — A backup hook on Blizzard's own world-quest provider makes sure EQ's world-quest pins refresh in the rare case our normal events miss a change.
- **Developer tooling** — `/eqs profile auto on` instruments the heaviest render and refresh paths so you can profile them without editing code. `/eqs profile auto off` removes the instrumentation, `/eqs profile auto list` shows what's wrapped.

## [1.3.12] - 2026-05-19

### New Features

- **Auto-accept and auto-turn-in quests** — Two new toggles on the General tab let Everything Quests click through quest dialogs for you. Auto-accept accepts offered quests; auto-turn-in finishes quests whenever there's no reward to choose between (multi-choice reward screens stay open so you pick the item yourself). Hold **Alt** while talking to a quest-giver to pause automation for that interaction, or decline a quest manually to pause everything for 10 seconds.
- **"Chain" button on the world map's quest details** — A small button next to Abandon: click it and the Chain Guide opens directly to that quest's chain, highlighting it. If the quest isn't in any chain Everything Quests knows about yet, a Wowhead link is printed in chat instead so the click is never dead.
- **Flight master highlight** — Open a flight master and the taxi node closest to your focused quest's destination now glows gold, so you can spot the right one at a glance.
- **Auto-zoom map** — Optional toggle on the General tab (off by default): opening the world map automatically switches it to your focused quest's zone. Stays put while you're already on a flight path.
- **Skipped-quest markers in the Chain Guide** — If you've moved past a quest in a chain without finishing it, the Chain Guide flags it with an orange marker and a red ✕, plus a "N skipped" count at the top of the chain. Hover the marked quest for an explanation. Optional breadcrumb quests aren't flagged.

### Bug Fixes

- **Completion sound now fires for instant-complete quests** — Some quests (certain dailies, scenario step turn-ins, a few Midnight callings) finish without ever entering your quest log, so the completion sound was silently skipped. They're now caught from the chat message and play the sound like any other quest.

### Improvements

- **Live memory meter** — New `/eqs profile memhog` slash command opens a small draggable panel showing Everything Quests' current memory use and how fast that's changing in kB/s. Useful for the curious or for spotting allocation spikes during play. Type the same command again to hide it.
- **Under-the-hood polish** — Tighter cleanup when tracker quest entries are recycled (invisible during play, but keeps memory healthier) and a new internal tooltip-reading helper for future features.

## [1.3.11] - 2026-05-19

### Improvements

- **Developer tooling** — New `/eqs profile` slash command for diagnosing CPU and memory hot spots (`show`, `reset`, `mem on/off`), plus a shared event-throttler primitive for upcoming features. Under-the-hood groundwork — no visible change for typical play.

## [1.3.10] - 2026-05-19

### Bug Fixes

- **Quest item buttons are now clickable** — The new tracker item buttons added in 1.3.9 wouldn't actually use the item when clicked. They now work as intended (out of combat).

### Improvements

- **Out-of-range tint** — Quest item buttons in the tracker now tint red when their item is out of range, and return to normal as soon as you're close enough to use it.

## [1.3.9] - 2026-05-18

### New Features

- **Usable quest item buttons** — Quests that come with a usable item now show a clickable button right on their tracker entry, so you can use it without opening the quest log. On by default; toggle it on the Tracker tab. (Items become clickable for quests you already had when you entered combat — the game doesn't allow setting these up during a fight.)

### Bug Fixes

- **No more "action blocked" message in combat** — With the new item buttons present, changing the tracker scale (or having a pending scale change) during combat could trigger a Blizzard "action blocked" message. Scale changes are now applied safely, deferred until combat ends if needed.

## [1.3.8] - 2026-05-18

### Bug Fixes

- **Drag-and-drop drop line** — When reordering quests by dragging (manual sort mode), the yellow "drop here" line could land a couple of quests below the cursor, especially with a non-default Tracker Scale. It now tracks the cursor exactly at any scale.

### Improvements

- **Hardier saved settings** — Your manual quest order is now cleaned up when it loads, so a corrupted saved value can't break the tracker's sorting. Also includes some under-the-hood groundwork for upcoming features. No visible change from these.

## [1.3.7] - 2026-05-18

### Bug Fixes

- **Campaign quests after a game restart** — After fully restarting the game client (not a UI reload), campaign quests could appear under the regular "Quests" section instead of "Campaign" until you turned in a quest. They now move into the Campaign section on their own, within a few seconds of logging in.
- **Hidden objective numbers** — With "Show objective numbers" turned off, some objective lines could show a stray color code as text (e.g. `44ff44Apprentice…`). Objective text is now clean when numbers are hidden.

## [1.3.6] - 2026-05-18

### New Features

- **Tracker border** — Optional border around the quest tracker, off by default. Turn it on in the Appearance tab, pick any color (including your class color via the picker's **Class** button), and set how thick it is with the new **Border Thickness** slider. The border wraps cleanly around the tracker whether or not the background is enabled. Thanks to **Spydawg2233** for the suggestion!

## [1.3.5] - 2026-05-17

### Improvements

- **Much lighter quest tracker** — The tracker now reuses each quest's display and only redraws a quest when something about it actually changes, instead of rebuilding every quest from scratch on every update. This sharply cuts memory churn (steady tracker memory is well below previous versions) and keeps the tracker smooth even with a full quest log — with no change to how it looks or behaves.

## [1.3.4] - 2026-05-17

### Improvements

- **Lighter, smoother tracker** — The quest tracker now does far less repeated work each time it updates: it remembers your font instead of re-applying it to every quest on every refresh, reuses internal scratch space instead of creating throwaway work, and stops re-checking icon art it has already looked up. The result is noticeably less memory churn with a full quest log, with no change to how the tracker looks or behaves.

## [1.3.3] - 2026-05-17

### Improvements

- **Consistent world quest timers** — The time-left countdown on a world quest now uses the same colors and the same format everywhere it appears: the map pin, the zone list, and the tooltip. Before, the same quest could look more or less urgent depending on where you read it, and the tooltip spelled the time out differently. Now it's one clear scale — green when there's plenty of time, down through yellow and orange to red as it runs out.
- **Lighter quest sorting** — Sorting the tracker's quest list no longer creates throwaway work every time it refreshes, shaving off a bit more memory churn.

## [1.3.2] - 2026-05-17

### Improvements

- **Clearer explanation of the red map markers** — The General options tab now plainly describes Everything Quests' red `!` / `?` world-map markers: they're for quests you've already picked up (a red `!` means "go here for this quest's next step," a red `?` means "this one's done, go turn it in"). Quests you haven't accepted yet keep the game's normal yellow markers.
- **Lighter and smoother world quests** — World quest pins now remember each quest's reward instead of working it out again every time the map refreshes, and the addon no longer keeps retrying quests whose reward never loads. The result is less memory use and a smoother world map, especially in zones packed with world quests.

## [1.3.1] - 2026-05-17

### Bug Fixes

- **Font picker could spam errors** — Opening the Appearance font dropdown could throw a stream of "Invalid font file asset" errors when another addon had registered a font whose file was missing or mispathed (e.g. a media pack with absent files). The picker now lists only the fonts bundled with Everything Quests, so every entry is guaranteed valid, and font previews fall back to the default font instead of erroring.
- **Internal developer text showed in scenario steps** — On some scenarios (notably Void Incursion), a step could display a raw Blizzard placeholder string such as "12.0.5 Void Assaults - Eversong - Major Attack - Scenario 01 - Step 02 Completion (JTL)" where its description should be. These build-marker strings are now detected and hidden, leaving just the clean progress bar and stage banner.

### Improvements

- **Void Incursion label** — Void Incursion events now show "Void Incursion" as the scenario tracker's section header instead of the generic "Scenario". Other scenario types are unaffected.

## [1.3.0] - 2026-05-16

### New Features

- **Chain Guide now follows the real campaign** — The "Midnight Campaign" category is sourced live from Blizzard's campaign data instead of a hand-maintained list, so it mirrors your actual in-game campaign: all 17 chapters, in story order, with live per-chapter progress. Previously the category showed a mostly-wrong fixed set of questlines and your real campaign quests never appeared there.
- **New "The War of Light and Shadow" category** — The max-level campaign (Foothold, The Voidspire, Gathering of the Elves, The Battle of the Bridge, March on Quel'Danas, Dawn of a New Well) now has its own category, sourced the same live way, so you can track that endgame storyline before and as you unlock it.

### Improvements

- **Categories grouped sensibly** — The Chain Guide category list is now ordered campaigns-first (leveling, then max-level) then zones in Midnight progression order, instead of an alphabetical jumble.
- **Bigger Chain Guide window** — Larger window and wider list panes; long category names (e.g. "The War of Light and Shadow") are no longer clipped, and hovering any category or chain shows its full name (plus quest progress for chains).
- **No more duplicate storylines** — A questline that is a campaign chapter now appears only under its campaign, not also under its zone. Categories left with no chains of their own are hidden rather than shown as empty.

## [1.2.1] - 2026-05-16

### Bug Fixes

- **Campaign quests vanished from the tracker when accepted** — Accepting a campaign quest in the field left it untracked, forcing you to open the quest log and re-track it every time. EQ's tracker shows watched quests, but Blizzard surfaces campaign quests through a separate system that never adds them to the watch list, so they stayed hidden. With auto-track on (the default), EQ now adds the watch itself the moment a quest is accepted, so campaign quests appear in the tracker immediately. World quests are unaffected (they keep their own tracking).

### Improvements

- **Clearer options wording** — The General tab's "Show quest pins on the world map" description is rewritten in plain language explaining exactly what the red `!` / `?` markers are. The World Quests tab's master switch now states explicitly that it does **not** control those red quest rings (those live on the General tab) and does **not** affect the tracker's World Quests list.

## [1.2.0] - 2026-05-16

### New Features

- **Campaign section** — Campaign quests now have their own "Campaign" header, split out of the general "Quests" section (same header style and behavior). It only appears when you have campaign quests.
- **World Quests pinned to the bottom** — The World Quests section is now fixed at the bottom of the tracker and always visible, with its own height cap and internal scroll, while everything above it scrolls. It sits flush beneath your quests (no dead gap) until they grow enough to need scrolling.
- **Hide quest map pins** — New General-tab option to turn off EQ's red `!`/`?` quest pins on the world map (Blizzard's own pins are unaffected).
- **Disable World Quest map features** — New World Quests-tab master switch that turns off all WQ map overlays (world-map pins, summary box, zone list) without affecting the tracker — for players who only want the tracker and Chain Guide.
- **Tracked / total counts** — The Quests and Campaign headers can show "shown / category total" (e.g. `3/9`), toggleable on the Tracker tab (on by default).

### Improvements

- **Left-click focuses a quest** — Left-clicking a tracked quest now super-tracks it (waypoint/arrow) instead of opening the quest log; the quest log / details moved to right-click.
- **Group Finder accuracy** — The Find Group eye and elite rosette now show only on elite world quests, not on the many ordinary WQs that merely had a premade-group activity.
- **Softer icon glow** — The classification glow behind quest icons is now ~50% lighter.
- **Consistent header counts** — Every section's count renders in the Section Header Color at the quest-description font size.
- **World Quests options layout** — Reorganized so the pin-scale slider and sort options no longer run off the window.
- **Interface versions** — TOC updated to include the upcoming patch build for forward compatibility.

## [1.1.3] - 2026-05-16

### Fixed

- **CurseForge releases** — Automated builds now publish to CurseForge. The CurseForge project ID was missing from the TOC, so the packager only ever created the GitHub release and skipped CurseForge entirely. No in-game changes from 1.1.2.

## [1.1.2] - 2026-05-16

### Bug Fixes

- **`/eq` did nothing** — `/eq` is Blizzard's own built-in command for equipping items, so the game intercepted it before the addon ever received it. The short command to open Options is now **`/eqs`**; `/everythingquests` still works as before. All in-game hints, tooltips, the move-the-tracker popup, and the README were updated to match.
- **Scroll bar background misaligned** — The scroll-bar backdrop sat to the left of the scroll bar instead of directly behind it. It is now anchored to the bar itself, so it always lines up.

### Improvements

- **Subtler scroll bar background** — The default backdrop is now a faint, barely-there grey that just hints the bar is present (still fully adjustable in Appearance), and the same backdrop was added to the World Quests options tab.
- **Options layout** — The Scroll Bar Color picker now lines up in the same column as the Background Color picker.

## [1.1.0] - 2026-05-16

### New Features

- **Chain Guide waypoints** — Clicking any quest in a chain now drops a waypoint (TomTom if installed, otherwise Blizzard's user waypoint + super-track) and opens the world map to it. Ships with quest-giver coordinates for the Midnight chains, with a live questline-API lookup and passive harvesting as fallbacks so coverage keeps improving as you play.
- **Bundled font selection** — A large set of fonts now ships with the addon and is registered with LibSharedMedia, so every user has the full font list in Appearance with no external addon required. Default is GothamXNarrow Black.
- **Move-the-tracker discovery** — A one-time popup on first load explains how to reposition the tracker, and the (previously invisible) top drag strip now highlights and shows a tooltip on hover, with a lock-aware message.

### Bug Fixes

- **"Find Group" eye on solo quests** — The group-finder eye no longer appears on regular quests; it is shown only on elite/group world quests, matching Blizzard's tracker.
- **Expired world quests** — Expired WQs (no time remaining / no longer active) are now filtered out of the world-quest list, summary, and pins instead of lingering as stale "Expired" rows.
- **Delve section labeled "Scenario"** — The tracker now correctly labels Delves as "Delves" (detected via scenario type, since the legacy texture-kit signal is absent in Midnight).
- **Background opacity slider** — Dragging the tracker background fade now updates live; it previously relied on a UI global removed in 10.0, so the alpha was always read as fully opaque.

### Improvements

- **World-quest reward classification** — Rewritten to a tag → money → item → currency pipeline: far fewer rewards fall to "Other", artifact power / trade goods / equipment are distinguished, and the "Other" summary icon is no longer a question mark.
- **Section header hierarchy** — Section headers now render in the user's font a few points larger than quest titles (and live-update with the Appearance settings), so the layout reads correctly.
- **Cleaner tracker** — Removed the "All Objectives" master header (each section has its own) and the boxed background behind the Delves header.

## [1.0.1] - 2026-05-15

### Bug Fixes

- **Font dropdown was unusable** — The Appearance tab's font picker rendered an empty list because the scroll content frame was hardcoded to 1px wide, collapsing every row. Font rows now size to the scroll width and display each font as a live preview.
- **World quest shown twice** — A watched/quest-log task quest (e.g. "Nulling Nullaeus") could render in both the Quests and World Quests sections. The "already in the Quests section" exclusion is now applied to all world-quest sources, not just in-zone task quests.
- **Rename leftovers** — Cleaned up internal `EQL` identifiers left over from the EverythingQuestLog → Everything Quests rename: frame names, the map-pin mixin/template, and user-visible chat prefixes are now `EQ`.

### New Features

- **Find Group button** — Group-eligible world quests (elite world quests, raid bosses) now show a Find Group eye button in the tracker that opens the Premade Group Finder for that quest, plus the gold elite rosette icon — matching Blizzard's own tracker.
- **No-sound option** — "None" is now the first choice in the Quest Complete Sound dropdown, so the completion sound can be disabled directly from the picker.
- **Bundled font** — GothamNarrow Black now ships with the addon and is registered with LibSharedMedia, so the default typeface works with no external dependency.

### Improvements

- **Condensed tracker** — Layout tightened to match Blizzard's compact tracker: the zone subtitle is off by default, block padding and spacing are reduced, and world-quest rows are shorter.
- **Blizzard-style objectives** — In-progress objectives use a `- ` dash prefix; completed objectives show a checkmark.
- **Default appearance** — Default font is GothamNarrow Black at size 15 with an outline.
- **Options window styling** — The Options window now has the Everything-suite red (#6D0501) border and a larger outlined title, matching the sibling addons.

## [1.0.0] - 2026-05-12

### New Features

- Initial stable release — out of beta.
- **Quest Tracker** — Custom on-screen tracker replacing the default Blizzard ObjectiveTrackerFrame. Draggable, resizable, with per-type filters (Normal, Daily, Weekly, Campaign, World Quests), six sort modes, and manual drag-to-reorder.
- **World Quest Pins** — Custom pins on world and zone maps with colored rings by reward category, time-urgency coloring, hover tooltips, and per-reward / per-faction filtering.
- **Chain Guide** — Standalone three-pane window for browsing hand-authored Midnight quest chains across Eversong Woods, Zul'Aman, Harandar, Voidstorm, and Arator, with cross-character completion tracking.
- **Map POI overlays** — Branded quest pins (red ring, #6D0501) on zone maps with super-track and dismiss support.
- **Minimap launcher** — LibDataBroker integration compatible with Titan Panel, ChocolateBar, and ElvUI. Left-click opens the Blizzard quest log, shift-click opens the Chain Guide, right-click opens Options.
- **Options panel** — Tabs for General, Tracker, World Quests, Appearance, and Chain Guide settings. Font and texture pickers powered by LibSharedMedia.
- Localization stubs for deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW. Full enUS strings.
