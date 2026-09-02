-- Locales/enUS.lua
-- Default locale + source-of-truth phrase list for Everything Quests.
--
-- ns.L["English string"] returns the localized text for the player's client
-- (per GetLocale()), or the English string itself when no translation exists
-- (the metatable __index below). So EVERY wrapped string is safe to use even
-- with zero translations loaded -- untranslated text simply renders in English.
--
-- Translations are crowd-sourced on CurseForge. The keys listed below ARE the
-- base phrases: paste this list into the project's Localization page so the
-- frFR (and future) translators have something to translate. At build time the
-- packager injects their work via the --@localization@ token in the other
-- Locales/*.lua files (an inert comment in raw git checkouts).
--
-- Pattern: the English string IS the key (no semantic IDs). Keep keys in sync
-- with the code -- if you reword an English string, update it here too or the
-- existing translation orphans (and the new text falls back to English).
--
-- GENERATED FILE: produced by docs/_gen_enus.py from the L[...] usages in the
-- code. Do not hand-edit; re-run the generator after an extraction pass.


local _, ns = ...

ns.L = setmetatable({}, { __index = function(_, k) return k end })
local L = ns.L

-- ─── Options/TabGeneral.lua ───
L["General"] = true
L["Show quest pins on the world map"] = true
L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Uncheck this box and all of EQ's red markers go away. Quests you have not accepted yet are controlled separately."] = true
L["World map pin scale"] = true
L["Quest pins are drawn at a fixed size no matter how far the map is zoomed, and this sets that size. Raise it if the pins are hard to pick out on a large or high-resolution display."] = true
L["Objective pins per quest"] = true
L["No limit"] = true
L["How many places to mark for a single quest on one map. The busiest locations are kept first, so a lower number still points you somewhere useful. Slide all the way right for no limit at all - a few gathering quests can then put hundreds of markers on one map."] = true
L["Show quests you can pick up"] = true
L["Marks every quest giver who has something for you but is not in your quest log yet, with a gold ring around the exclamation mark so it reads apart from the quests you are already carrying. One marker covers a whole quest giver, and hovering it lists everything that giver offers. Quests are filtered by your level, race, class and the quests you have already finished, and holiday quests are shown only while their world event is running."] = true
L["Hide quests below your level"] = true
L["Leaves out quests the game has already grayed out for you, using the game's own threshold rather than a fixed number of levels. On by default. Turn it off to see everything a quest giver has, including the quests you have outleveled."] = true
L["Hide holiday quests out of season"] = true
L["Leaves out quests belonging to a world event that is not running, such as the Lunar Festival in July. On by default. Turn it off to see every holiday quest all year, which is how the map behaved before."] = true
L["Hide quests above your level"] = true
L["Leaves out quests the game colors red for you, using its own threshold rather than a fixed number of levels. Off by default, because a red quest is still worth knowing about if you are coming back later."] = true
L["Show objective pins on the minimap"] = true
L["Puts the same objective markers on the minimap as on the world map, for the zone you are standing in. They use the per-quest limit above. Hover one for the quest name and what it still needs."] = true
L["Let Immersion handle quest dialogs"] = true
L["Immersion replaces the quest and gossip windows so you can read them, so EQ leaves accepting and turning in to you while it is installed. Uncheck to accept and turn in automatically anyway."] = true
L["Hold Alt to pause."] = true
L["Skips reward-choice screens."] = true
L["Immersion is handling quest windows, so this does nothing right now."] = true
L["Auto-accept quests"] = true
L["Auto-turn-in quests"] = true
L["Map"] = true
L["Show a ring around quest pins"] = true
L["Draws the red circle behind every world map marker for a quest in your log, both the ones you are still working on and the ones that are ready to turn in. Turn it off for plain icons and a much quieter map when a zone is busy."] = true
L["Show a ring around quests you can pick up"] = true
L["Draws the gold circle behind the exclamation mark of every quest giver who has something for you. Off by default. The mark itself still tells these apart from the quests you are already carrying, because those use their own objective art or the turn-in mark instead."] = true
L["Only show markers for quests you are tracking"] = true
L["Leaves out the markers for any quest in your log that you have untracked, so a busy zone shows only what you are actually working on. Off by default. Quests you have not picked up yet are not affected, because there is nothing to have tracked."] = true
L["Fade markers that cover your position"] = true
L["Makes any marker sitting on top of your own arrow see-through, so you can still find yourself on a zone that is drawing hundreds of them. Off by default. The markers are still there and still answer the mouse, they are only dimmed while you are standing under them."] = true
L["Coordinates"] = true
L["Show coordinates on the world map"] = true
L["Puts a small readout in the bottom left of the world map with the position your mouse is pointing at, and your own position when you are looking at the zone you are standing in. Turn it off if another addon already shows coordinates there."] = true
L["Show coordinates under the minimap"] = true
L["Puts your own position just below the minimap so it is readable without opening the map. Off by default, because many interface addons already put something there."] = true
L["Coordinate decimals"] = true
L["How precise the numbers are. Zero is whole numbers, which is enough to find a spot on the map. Two is what most quest guides quote."] = true
L["Hide these quests on the map"] = true
L["These only affect the markers for quests you have NOT picked up yet. A quest already in your log always keeps its markers, because hiding something you are carrying would make the map lie about what you still have to do."] = true
L["Dungeon and raid quests"] = true
L["Leaves out quests that are sorted into a dungeon or a raid. Most are picked up inside the instance or from a quest giver at its door, so they clutter the outdoor map without helping you while you are questing in the world."] = true
L["Repeatable quests"] = true
L["Leaves out the quests you can hand in over and over, usually a turn-in for reputation or a common trade good. They never stop being offered, so they stay on the map forever once you can see them."] = true
L["Profession quests"] = true
L["Leaves out quests that require a trade skill, such as a Blacksmithing or Alchemy specialization. Everything Quests cannot read your skill levels on this version of the game, so these are offered even when you have not trained the profession they need."] = true
L["Tooltips"] = true
L["Show quest progress on tooltips"] = true
L["Adds the quest name and what it still needs to the tooltips you already see in the game. Hovering an item in your bags tells you which quest wants it and how many are still missing. On Classic, hovering an enemy also tells you which quest it counts toward, which the game itself never says there. Only quests already in your log are listed, and nothing is added to a tooltip that has nothing to say."] = true
L["Quest Browser"] = true
L["Open Quest Browser"] = true
L["Look up almost any quest in the game, including ones you have never picked up. Shows the level and race and class requirements, where it starts and turns in, what has to be finished first, and why you cannot take it yet. Also on /eqs quests, or right-click a gold quest marker on the map."] = true
L["Tracker"] = true
L["Open Tracker Settings"] = true
L["The tracker is now EQ Objective Tracker, a separate addon that Everything Quests installs for you. Its own options panel holds everything: position and size, fonts, colors, sections, filters, sorting and visibility. You can also open it by typing /eqot, or with the cogwheel at the top right of the tracker itself."] = true
L["Show Everything Quests icon on the tracker"] = true
L["Adds the Everything Quests logo at the top right of the tracker, which opens this options window. The tracker's own cogwheel opens the tracker's settings instead. You can also reach this window from the minimap button or by typing /eqs."] = true
L["Show Chain Guide icon on the tracker"] = true
L["Adds a small chain icon beside the cogwheel at the top right of the tracker, which opens the Chain Guide."] = true
L["Options Window Scale"] = true
L["Resizes this Everything Quests options window only. It does not change the quest tracker or anything shown in the game world. The new size applies when you let go of the slider."] = true
L["Popup window"] = true
L["Chat link"] = true
L["None"] = true
L["After an update"] = true
L["How Everything Quests tells you about new features: a Popup window, a quiet clickable Chat link in your chat frame, or None. New features always ship off until you turn them on."] = true
L["Nameplate Quest Icons"] = true
L["Quest icons on nameplates"] = true
L["Shows the \"!\" + count on objective mobs."] = true
L["Left"] = true
L["Right"] = true
L["Above"] = true
L["Below"] = true
L["Position"] = true
L["Where the quest icon + count sits relative to the enemy nameplate. Move it closer to the health bar to taste."] = true
L["Icon size"] = true
L["Count text size"] = true
L["X offset"] = true
L["Nudges the icon and count together left or right from the Position above, so you can slide them right up against the health bar."] = true
L["Y offset"] = true
L["Nudges the icon and count together up or down from the Position above (positive moves them up)."] = true
L["Reset all settings"] = true
L["Reset every Everything Quests setting to defaults?"] = true
L["Reset"] = true
L["Cancel"] = true
L["Profiles"] = true
L["Active profile"] = true
L["New Profile"] = true
L["Profile name:"] = true
L["Create"] = true
L["Overwrite profile?"] = true
L["A profile named \"%s\" already exists. Overwrite it with a copy of your current settings?"] = true
L["Overwrite"] = true
L["Switching profiles reloads the UI. Profiles are shared across characters; use them to keep different setups (e.g. raid vs solo). |cffEBB706New Profile|r prompts for a name and creates it on the spot."] = true
L["Slash commands"] = true
L["/eqs\n/everythingquests\n\n|cff999999Both open this options window.|r\n\n/eqs whatsnew\n\n|cff999999Show what's new in the latest update.|r\n\n/eqs session\n\n|cff999999Show a recap of your current play session.|r"] = true
L["Show minimap button"] = true

-- ─── Options/TabWorldQuests.lua ───
L["Gold"] = true
L["Gear / Items"] = true
L["Reputation tokens"] = true
L["Resources / Currencies"] = true
L["Artifact Power"] = true
L["PvP"] = true
L["Pet battles"] = true
L["Other / Uncategorized"] = true
L["Classic"] = true
L["The Burning Crusade"] = true
L["Wrath of the Lich King"] = true
L["Cataclysm"] = true
L["Mists of Pandaria"] = true
L["Warlords of Draenor"] = true
L["Legion"] = true
L["Battle for Azeroth"] = true
L["Shadowlands"] = true
L["Dragonflight"] = true
L["The War Within"] = true
L["Midnight"] = true
L["Other"] = true
L["World Quests"] = true
L["Enable World Quests map features"] = true
L["Off: Everything Quests stops putting World Quests on the map — no world-map pins, no reward summary box, no zone quest list. The boxes below do nothing while this is off. This switch is ONLY for World Quests. It does NOT remove the red \"!\" / \"?\" quest rings — those are your normal quests, and you turn them off on the General tab. It also does NOT change the World Quests list in your tracker (that's on the Tracker tab)."] = true
L["Show world quest pins on the world map"] = true
L["Show zone quest list on zone maps"] = true
L["Filters by reward type"] = true
L["Enable All"] = true
L["Disable All"] = true
L["Filter by faction"] = true
L["Uncheck a faction to hide its world quests on the map."] = true
L["No major factions unlocked on this character yet."] = true
L["%s  |cffaaaaaa(Renown %d)|r"] = true
L["Faction %d"] = true
L["Display"] = true
L["Time left"] = true
L["Reward"] = true
L["Faction"] = true
L["A-Z"] = true
L["Sort zone quest list by"] = true
L["Filters apply immediately when the world map is open."] = true

-- ─── Options/TabChainGuide.lua ───
L["Chain Guide"] = true
L["Chain Guide (Storylines)"] = true
L["Open Chain Guide"] = true
L["Open Chain Guide on login"] = true
L["Show unrouted questlines"] = true
L["API discoveries not in our routing table."] = true
L["Show tracked chain on the world map"] = true
L["Pin the quests of the chain you're following on the world map, with your next step highlighted. Track a chain from the Track button in the Chain Guide."] = true
L["Window scale"] = true
L["Character cache"] = true
L["Per-character chain progress is cached account-wide so alts can browse what your other characters have completed. Clearing the cache removes that cross-character data; live completions stay (Blizzard tracks those)."] = true
L["Clear chain cache"] = true
L["Clear all cached chain-completion data across every character?"] = true
L["Clear"] = true
L["Cached: |cffffffff%d|r characters, |cffffffff%d|r waypoint locations\n|cffffffff%d|r chains across |cffffffff%d|r categories"] = true
L["today"] = true
L["1 day ago"] = true
L["%d days ago"] = true
L["\n|cffaaaaaaLast pruned: %s|r"] = true
L["Prune stale entries now"] = true
L["|cffEBB706EQ|r: pruned |cffffffff%d|r stale character record(s) and |cffffffff%d|r waypoint(s)."] = true

-- ─── Options/TabHistory.lua ───
L["History"] = true
L["Quest History"] = true
L["Record completed quests"] = true
L["When on, Everything Quests writes an entry to your account-wide quest history every time you turn in a quest. The data is shared across all of your characters; the history window can filter by character."] = true
L["Maximum entries kept"] = true
L["When the history grows past this many entries, the oldest ones are dropped. Set higher if you want a longer record, lower to save disk space. 5000 entries is enough for several months of heavy questing."] = true
L["Open Quest History"] = true
L["Populate from past completions"] = true
L["this character"] = true
L["|cffEBB706EQ History:|r added %d past completion%s for |cffffffff%s|r (no dates)."] = true
L["One-time per character: walks the list of quests this character has completed (according to the game's own record) and adds any that aren't already in your history. Entries created this way have no date — the game doesn't tell us when they happened."] = true
L["Re-scan for quest names"] = true
L["|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."] = true
L["|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is."] = true
L["Some quests in the backfilled history show up as \"Quest #12345\" because Blizzard hasn't sent the client their name yet. This button asks the server for every missing one. Quests the server flatly has no data for (retired or internal IDs) will keep their numeric placeholder."] = true
L["Restore history from backup"] = true
L["|cffEBB706EQ History:|r no backup yet — one is saved automatically each time you log out."] = true
L["Restore quest history from the backup taken %s (%d entries)? This replaces the current history."] = true
L["Restore"] = true
L["|cffEBB706EQ History:|r restored %d entr%s from backup."] = true
L["Everything Quests saves a rolling backup of your history when you log out, and automatically restores it if your history is ever found empty or missing a character on load. Use this button to restore manually."] = true
L["Wipe history"] = true
L["Delete ALL recorded quest history (every character)? This cannot be undone."] = true
L["Wipe"] = true
L["|cffEBB706EQ History:|r wiped."] = true

-- ─── Options/Frame.lua ───
L["Join our Discord!"] = true
L["Join our Discord"] = true
L["Version %s"] = true
L["Everything Quests opens its full options in a dedicated window. Click the button below, or type |cffEBB706/eqs|r in chat."] = true
L["Open Everything Quests Options"] = true
L["|cffEBB706EQ|r: the quest browser needs the Classic quest data, which this version of the game does not load."] = true
L["|cffEBB706Everything Quests|r: couldn't open Options \226\128\148 %s"] = true

-- ─── Core/Init.lua ───
L["Everything Quests Discord"] = true
L["Join the community for help, feedback, and updates.\nCopy the invite below (it's pre-selected — just press Ctrl+C):"] = true
L["Close"] = true
L["Copy the link below (it's pre-selected — just press Ctrl+C):"] = true

-- ─── Core/QuestRewards.lua ───
L["Equip — empty slot"] = true
L["Equipped: ilvl %d"] = true
L["+%d ilvl upgrade"] = true
L["%d ilvl lower"] = true
L["Same item level"] = true
L["ilvl %d"] = true
L["%d XP"] = true
L["Choose one:"] = true

-- ─── Core/Util.lua ───
L["Expired"] = true

-- ─── Modules/ChainGuide/CampaignSource.lua ───
L["Campaign Map"] = true

-- ─── Modules/ChainGuide/ChainView.lua ───
L["Completed"] = true
L["Ready to turn in"] = true
L["In your quest log"] = true
L["Skipped"] = true
L["A later quest in this chain has already passed this one."] = true
L["May be worth going back to pick up."] = true
L["Not started"] = true
L["Level %d"] = true
L["Completed: "] = true
L["Completed (before tracking)"] = true
L["Shift-click to link in chat"] = true
L["Level %d–%d"] = true
L["Click to open this chain"] = true
L["Pick a chain on the left to view its quests."] = true
L["Untrack"] = true
L["Track"] = true
L["%d/%d done"] = true
L["%d active"] = true
L["|cffff9933%d skipped|r"] = true
L["Lv %d  •  ID %d"] = true
L["ON QUEST"] = true
L["NEXT"] = true
L["(optional)"] = true
L["Continue"] = true
L["Track this chain"] = true
L["Follow this chain — its quests pin on the world map (next step highlighted) and your waypoint auto-advances to the next step as you complete it. Works even with this window closed. Click again to stop."] = true
L["(no quests defined for this chain yet)"] = true

-- ─── Modules/ChainGuide/Frame.lua ───
L["Hide the navigation panel"] = true
L["Collapse the category and chain list so the graph fills the whole window. Click again to bring it back."] = true
L["Back"] = true
L["Forward"] = true
L["Home"] = true
L["Options"] = true
L["Find quest"] = true
L["Type a quest name or its ID to jump to the chain that contains it."] = true
L["Go"] = true
L["Categories"] = true
L["Drag to resize"] = true
L["|cffEBB706EQ Chain Guide:|r found quest |cffffffff%d|r%s — jumping to its chain."] = true
L["|cffEBB706EQ Chain Guide:|r quest |cffffffff%d|r%s isn't in any chain I know about."] = true
L["|cffEBB706EQ Chain Guide:|r found |cffffffff%s|r — jumping to its chain."] = true
L["|cffEBB706EQ Chain Guide:|r no chain quest matches |cffffffff%s|r."] = true
L["Pick a category"] = true
L["Chains"] = true
L["%d / %d quests done"] = true

-- ─── Modules/ChainGuide/MapPin.lua ───
L["Your next step"] = true
L["On this quest"] = true
L["Comes later in the chain"] = true

-- ─── Modules/ChainGuide/QuestMapButton.lua ───
L["Chain"] = true
L["Find this quest in EQ's Chain Guide"] = true
L["Falls back to a Wowhead link in chat if EQ doesn't have a chain for this quest yet."] = true

-- ─── Modules/History/Frame.lua ───
L["(before tracking)"] = true
L["|cffEBB706EQ History|r: |cffffffff%s|r isn't part of any chain in the Chain Guide."] = true
L["Accepted %1$s, held %2$s"] = true
L["Right-click to open in the Chain Guide"] = true
L["Click to expand"] = true
L["Export"] = true
L["Re-scan names"] = true
L["Asks the server for the name of any \"Quest #12345\" entries. They'll fill in over the next minute or two as responses arrive."] = true
L["Quests"] = true
L["Streak"] = true
L["Chain Timeline"] = true
L["Activity"] = true
L["Stats"] = true
L["This Session"] = true
L["Character:"] = true
L["All characters"] = true
L["Date:"] = true
L["All time"] = true
L["Today"] = true
L["Past 7 days"] = true
L["Past 30 days"] = true
L["Type:"] = true
L["All types"] = true
L["Campaign"] = true
L["Questline"] = true
L["Calling"] = true
L["Recurring"] = true
L["World Quest"] = true
L["Sort:"] = true
L["Date"] = true
L["Name"] = true
L["Type"] = true
L["Sort direction"] = true
L["Click to flip ascending / descending."] = true
L["Hide undated  |cffaaaaaa(backfilled)|r"] = true
L["(no matching quests)"] = true
L["%d entries"] = true
L["held for %s"] = true
L["first"] = true
L["oldest"] = true
L["newest"] = true
L["%d entries (showing %s %d)"] = true
L["Current daily streak"] = true
L["Best daily streak"] = true
L["Total quests recorded with a date"] = true
L["Streak counts consecutive days (local time) with at least one quest turn-in across any character on the account. Today or yesterday keeps the streak alive - you don't lose it until a whole day passes with no activity."] = true
L["%d days"] = true
L["Chains where you have at least one completed quest. Click a chain to expand and see per-quest completion dates."] = true
L["(no chain quests recorded yet)"] = true
L["%d of %d quests recorded"] = true
L["Quest turn-ins per day over the last %d days. Brighter = busier. Hover a cell for the date and count. The bottom-right cell is today."] = true
L["%d quest%s turned in"] = true
L["Less"] = true
L["More"] = true
L["total turn-ins in the last %d days"] = true
L["Busiest day: %s (%d quests)"] = true
L["%dg %ds %dc"] = true
L["Totals"] = true
L["Trends"] = true
L["Account-wide quest rewards. Totals count only quests turned in while reward tracking was on; older entries didn't capture XP or gold."] = true
L["Total quests with reward data"] = true
L["Total gold earned"] = true
L["Total XP earned"] = true
L["Total quests abandoned"] = true
L["Average time"] = true
L["By character"] = true
L["Top single-quest rewards"] = true
L["%1$s   |cffaaaaaa(%2$d quests)|r"] = true
L["%s  \194\183  %s quests  \194\183  %s  \194\183  %s XP"] = true
L["Biggest gold:  |cffffffff%s|r  \194\183  %s"] = true
L["Biggest gold:  (none yet)"] = true
L["Biggest XP:    |cffffffff%s|r  \194\183  %s XP"] = true
L["Biggest XP:    (none yet)"] = true
L["Daily"] = true
L["Weekly"] = true
L["Show:"] = true
L["XP"] = true
L["Gold is all income (loot, vendor, rewards) tracked forward from when this version was installed \226\128\148 past periods may read 0. XP and quest counts come from quest turn-ins."] = true
L["This week"] = true
L["last week"] = true
L["yesterday"] = true
L["%s \226\128\148 %s"] = true
L["%s vs %s"] = true
L["Your quest activity this play session. A session starts when you log in and continues across /reload; it resets the next time you log in fresh."] = true
L["Played this session"] = true
L["Quests completed"] = true
L["Quest XP earned"] = true
L["Quest gold earned"] = true
L["Level-ups"] = true
L["Quests abandoned"] = true
L["   |cffaaaaaa(%.1f / hour)|r"] = true
L["%d   |cffaaaaaa(%d to %d)|r"] = true
L["Press Ctrl+A to select all, then Ctrl+C to copy."] = true

-- ─── Modules/History/Recorder.lua ───
L["first time seeing |cffffffff%s|r - added %d past completion%s (no dates; future turn-ins are dated)."] = true
L["Quest history loaded empty; restored a backup from %s (%d entries)."] = true
L["Quest history for %s was missing; restored a backup from %s (%d entries)."] = true

-- ─── Modules/MapCoords.lua ───
L["Cursor"] = true
L["Player"] = true

-- ─── Modules/MapPOI/Pin.lua ───
L["%s XP"] = true
L["Dungeon entrance"] = true
L["Available quest"] = true
L["Repeatable quest"] = true
L["and %d more"] = true
L["Starts from an item that drops here"] = true
L["Right-click for quest details"] = true

-- ─── Modules/QuestAuto.lua ───
L["Immersion is installed. It replaces the quest and gossip windows so you can read them, and EQ's auto-accept and auto-turn-in would click straight past it. Which would you like?"] = true
L["Keep auto-questing"] = true
L["Let Immersion handle it"] = true

-- ─── Modules/QuestBrowser/Frame.lua ───
L["You have already completed this quest."] = true
L["This quest is already in your quest log."] = true
L["Part of a world event, so it is only offered while that event is running."] = true
L["Your race or class cannot take this quest."] = true
L["You do not meet the required level yet."] = true
L["Too far below your level to be worth showing. Turn off the low level filter to see it."] = true
L["The game colors this quest red for you, so it is out of reach for now. Turn off the high level filter to see it."] = true
L["An earlier quest has to be finished first."] = true
L["A later step of this chain is already done or in your log."] = true
L["You took a different branch of this quest line."] = true
L["Your reputation standing does not allow it."] = true
L["Hidden by your dungeon and raid filter."] = true
L["Hidden by your repeatable quest filter."] = true
L["Hidden by your profession quest filter."] = true
L["A character here offers it"] = true
L["An object here offers it"] = true
L["An item that starts it drops here"] = true
L["Click to open this quest"] = true
L["Click to open the map here and set a waypoint"] = true
L["All quests"] = true
L["Available to you"] = true
L["This zone only"] = true
L["Only list quests that can be picked up on the map you are standing in."] = true
L["No quest data on this version of the game."] = true
L["%d quests (showing the first %d)"] = true
L["%d quests"] = true
L["%d locations"] = true
L["Pick a quest on the left."] = true
L["Requires level %d"] = true
L["You can pick this up now."] = true
L["Not available to you right now."] = true
L["Failed, so you can take it again."] = true
L["Dungeon or raid"] = true
L["Repeatable"] = true
L["World event"] = true
L["Class quest"] = true
L["Profession"] = true
L["Races: %s"] = true
L["Classes: %s"] = true
L["Requires a profession at rank %d"] = true
L["faction %d"] = true
L["Requires %s with %s"] = true
L["Only below %s with %s"] = true
L["Requirements"] = true
L["Starts"] = true
L["Objectives"] = true
L["Turn in"] = true
L["Finish all of these first"] = true
L["Finish one of these first"] = true
L["Part of"] = true
L["Leads to"] = true
L["Instead of"] = true

-- ─── Modules/TrackerBridge.lua ───
L["EQ Objective Tracker is not loaded, so the tracker is unavailable."] = true
L["Open the Chain Guide"] = true
L["Open the Everything Quests options"] = true
L["Get Directions"] = true

-- ─── Modules/WhatsNew.lua ───
L["See what's new"] = true
L["updated to"] = true
L["Open Options"] = true
L["Got it"] = true
L["Don't show these again"] = true
L["Stops What's New notices entirely. You can turn them back on in /eqs > General."] = true

-- ─── Modules/WorldQuests/Pin.lua ───
L["World Quest #"] = true
L["Untrack Quest"] = true
L["Track Quest"] = true
L["Super-track (follow arrow)"] = true
L["Search on Wowhead"] = true

-- ─── Modules/WorldQuests/Summary.lua ───
L["Gear"] = true
L["Reputation"] = true
L["Resources"] = true
L["Professions"] = true
L["Pet Battles"] = true

-- ─── Modules/WorldQuests/Tab.lua ───
L["Click to hide the World Quests list."] = true
L["Click to show the World Quests list."] = true

-- ─── Modules/WorldQuests/Tooltip.lua ───
L["Time Left: "] = true

-- ─── Modules/WorldQuests/ZoneMap.lua ───
L["%s — %d quests"] = true

-- ─── Options/TabAbout.lua ───
L["Open or close the options window"] = true
L["Open the Quest History window"] = true
L["Look up almost any quest in the game"] = true
L["Recap your current play session in chat"] = true
L["List the current zone's quest chains in chat"] = true
L["Show the What's New popup again"] = true
L["Open this About tab"] = true
L["About"] = true
L["by Wheelbarrel00"] = true
L["for WoW %s"] = true
L["A unified replacement for the Blizzard quest experience: a custom tracker, world-map overlays, quest history, and a Midnight chain guide."] = true
L["A unified replacement for the Blizzard quest experience: a custom tracker, objective markers on the map and minimap, nameplate quest icons, and a browser for the quests you have not picked up yet."] = true
L["CurseForge"] = true
L["GitHub"] = true
L["Report a Bug"] = true
L["What's New"] = true
L["Commands"] = true
L["Tip: right-click the minimap button to open Options."] = true
L["Tutorials"] = true
L["Video tutorials are coming soon."] = true
L["More Add-ons by Wheelbarrel00"] = true
L["Thanks"] = true
L["Built with feedback, reports, and ideas from the community — especially "] = true
L[". Thank you!"] = true
L["Special thanks to "] = true
L[" for the many features, fixes, and reports that keep shaping Everything Quests."] = true
L[" for the many hours spent translating Everything Quests into French."] = true
L[" for the many hours spent translating Everything Quests into Russian."] = true
L[" for the many hours spent translating Everything Quests into Korean."] = true
L[" for the many hours spent translating Everything Quests into Simplified Chinese."] = true
L[" for the many hours spent translating Everything Quests into Traditional Chinese."] = true
L[" for the many hours spent translating Everything Quests into German."] = true
L["Changelog"] = true
L["Older versions are on CurseForge"] = true

-- Convert the `true` sentinels to their key (the self-keyed English default).
for k, v in pairs(L) do if v == true then L[k] = k end end
