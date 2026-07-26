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
L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Quests you haven't accepted yet keep the game's own yellow \"!\" markers; EQ does not change those. Uncheck this box and all of EQ's red markers go away."] = true
L["Lock tracker"] = true
L["Disable drag-to-move and resize."] = true
L["Hide tracker in combat"] = true
L["Hide tracker in instances"] = true
L["Raids, dungeons, delves."] = true
L["Hide tracker when world map is open"] = true
L["Hide tracker in Mythic+"] = true
L["Hides the tracker during an active Mythic+ run, then brings it back when the run ends."] = true
L["Auto-track accepted quests"] = true
L["Matches Blizzard's default."] = true
L["Auto-accept quests"] = true
L["Hold Alt to pause."] = true
L["Auto-turn-in quests"] = true
L["Skips reward-choice screens."] = true
L["Keep focused quest after relog"] = true
L["Restores the waypoint arrow."] = true
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

-- ─── Options/TabTracker.lua ───
L["Zone"] = true
L["Status"] = true
L["Type"] = true
L["Level"] = true
L["Distance"] = true
L["Recent"] = true
L["Manual"] = true
L["Normal quests"] = true
L["Daily quests"] = true
L["Weekly quests"] = true
L["Campaign quests"] = true
L["World quests"] = true
L["Show only quests in current zone"] = true
L["Tracker"] = true
L["On-Screen Tracker"] = true
L["Show only watched quests"] = true
L["Matches Blizzard's default tracker."] = true
L["Simplify Mode"] = true
L["Show only the first incomplete objective per quest."] = true
L["Simplify tracked achievements"] = true
L["Show only incomplete criteria for tracked achievements."] = true
L["Sort Order"] = true
L["|cffaaaaaaDrag and drop the quests in the tracker to reorder them however you like.|r"] = true
L["Filters"] = true
L["Reset filters to defaults"] = true
L["Options"] = true
L["Quest Title Color By Difficulty"] = true
L["Show quest level prefix"] = true
L["For example, [60] Title."] = true
L["Show zone label under quest titles"] = true
L["Show objective progress numbers"] = true
L["For example, 0/4, 1/1, etc."] = true
L["Show quest ID"] = true
L["Useful for bug reports."] = true
L["Show tracked / total on the Quests & Campaign headers"] = true
L["For example, 3/9."] = true
L["Show usable quest item buttons"] = true
L["Click to use the quest's item."] = true
L["Show Options icon on the tracker"] = true
L["A small cogwheel at the top-right of the tracker that opens the options panel."] = true
L["Show Chain Guide icon on the tracker"] = true
L["A small book at the top-right of the tracker that opens the Chain Guide."] = true
L["Hide scroll bar"] = true
L["Scroll with the mouse wheel instead."] = true
L["Show Quest Discovered popups"] = true
L["Boxes for newly discovered / completed quests."] = true
L["Show NEW tag on recently accepted quests"] = true
L["For about an hour after accepting."] = true
L["Split quest click"] = true
L["Click the icon to focus, click the title to open the quest log."] = true
L["Quest Sound"] = true
L["Plays when a quest is ready to turn in."] = true
L["Quest Complete Sound"] = true
L["Tracker Visibility"] = true
L["Profession section"] = true
L["Achievements section"] = true
L["Achievements you're tracking."] = true
L["World Quests section"] = true
L["Auto-list current-zone world quests"] = true
L["Lists every WQ in your zone without tracking each."] = true
L["Set a custom World Quests height"] = true
L["By default the World Quests area shares space with your quest list and gets squeezed when you have a lot of quests. Turn this on to give it its own height, set by the slider below."] = true
L["World Quests height"] = true
L["Section Order"] = true
L["Rearrange the tracker's sections with the arrows below. A section only appears on the tracker while it has something in it, so reordering an empty section won't look like anything changed. World Quests scroll in their own panel and can only sit at the very top or bottom \226\128\148 use the Top/Bottom control."] = true
L["Top"] = true
L["Bottom"] = true
L["World Quests position"] = true
L["Where the World Quests panel sits on the tracker. |cffffffffTop|r puts it above your quests; |cffffffffBottom|r keeps it below your quests (the default). World Quests scroll in their own capped panel, which is why they can't be mixed in between the other sections."] = true
L["Zone Progress"] = true
L["Campaign"] = true
L["Quests"] = true
L["Profession"] = true
L["Endeavors"] = true
L["Achievements"] = true
L["Move %s up"] = true
L["Move %s down"] = true
L["Reorders where this section sits in the tracker. A section only shows while it has something in it, so empty sections won't visibly move."] = true
L["Zone Progress Bar"] = true
L["Show zone progress bar"] = true
L["Approximate questline progress."] = true
L["Float as a movable bar"] = true
L["Drag to move; right-click to lock or reset."] = true
L["Scenario Bonus Objectives"] = true
L["Show bonus objectives HUD"] = true
L["Shows a small movable checklist of the extra bonus objectives that appear during some scenarios and delves, so you do not miss their rewards. Drag to move, right-click to lock or reset. Off by default."] = true
L["HUD Scale"] = true
L["Sizes the bonus objectives HUD."] = true
L["Changes apply immediately to the on-screen tracker."] = true

-- ─── Options/TabWorldQuests.lua ───
L["Gold"] = true
L["Gear / Items"] = true
L["Reputation tokens"] = true
L["Resources / Currencies"] = true
L["Artifact Power"] = true
L["Profession quests"] = true
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
L["World map pin scale"] = true
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

-- ─── Options/TabAppearance.lua ───
L["Appearance"] = true
L["Font"] = true
L["Font Size"] = true
L["Title Size Offset"] = true
L["Sizes quest and achievement titles separately from the objective text. This value is added to the Font Size above: 0 keeps titles the same size as the base font, positive makes them larger, negative smaller."] = true
L["Header Size Offset"] = true
L["Sizes the section headers (Quests, Campaign, and so on) independently of the quest text. Added on top of the Font Size above: the default 4 keeps headers at their current size, lower shrinks them (handy on a low UI scale), higher enlarges them."] = true
L["Outline"] = true
L["Thick"] = true
L["Mono"] = true
L["Mono Outline"] = true
L["Mono Thick"] = true
L["Font Outline"] = true
L["Text Shadow"] = true
L["Draws a soft drop-shadow behind all tracker text so it stays readable over bright or busy backgrounds. Use Shadow Color to tint it and Shadow Size to set how far it's cast."] = true
L["Shadow Color"] = true
L["Shadow Size"] = true
L["How far the text drop-shadow is cast behind the letters. Higher values give a larger, more pronounced shadow; lower values keep it tight. Only applies while Text Shadow is on."] = true
L["Scenario"] = true
L["Draws a drop-shadow behind the scenario / delve banner text (the Stage and name lines). This is SEPARATE from the Text Shadow above, which affects only the quest and objective text — the banner is styled on its own."] = true
L["How far the scenario banner's drop-shadow is cast. Higher values give a larger, more pronounced shadow; lower values keep it tight. Only applies while the Scenario Text Shadow above is on."] = true
L["Center"] = true
L["Banner Alignment"] = true
L["Positions the scenario / delve banner within the tracker. Left lines it up with the quest text, Center keeps it centered (the default), and Right pushes it to the tracker's right edge."] = true
L["Banner Text Size"] = true
L["Grows or shrinks the scenario / delve banner's Stage and name text. 0 is the default size. The banner artwork is a fixed size, so large values may overflow it."] = true
L["Criteria Text Size"] = true
L["Sizes the scenario / delve objective (criteria) lines shown under the banner, separately from the Banner Text Size above. Raise it if the criteria text looks small next to your quest and World Quest text."] = true
L["Background"] = true
L["Background Color"] = true
L["Border"] = true
L["Border Color"] = true
L["Border Thickness"] = true
L["Header Bar"] = true
L["Header bar"] = true
L["Draws a coloured gradient bar behind each section header (Quests, Campaign, World Quests, and so on), for a look closer to the default Blizzard tracker. Off by default."] = true
L["Bar Color"] = true
L["Header Bar 1"] = true
L["Header Bar 2"] = true
L["Bar Style"] = true
L["Header Bar 1 is a horizontal gradient (bright on the left, dark on the right). Header Bar 2 is a vertical gradient (bright at the top, dark at the bottom). Bar Color, Bar Height, and Soft edges all apply to whichever style you pick."] = true
L["Soft edges"] = true
L["Feathers the top, left, and right edges of the header bar so it blends into the UI instead of sitting in a hard box. The gradient colour is unchanged. Only applies while Header bar is on; off by default."] = true
L["Bar Height"] = true
L["How tall the section-header bar is. The bar is centred on the header row, so larger values fill more of it."] = true
L["Edge Softness"] = true
L["How soft the header bar's feathered edges are when Soft edges is on. Higher is softer; lower tightens toward a hard edge."] = true
L["Tracker Skins"] = true
L["Scroll Bar Background"] = true
L["Scroll Bar Color"] = true
L["Solid color thumb"] = true
L["Replaces the tracker scroll bar's textured thumb (the draggable block) with a flat single-colour block. Use the Thumb Color and Thumb Width controls to style it. Off restores the stock Blizzard bar."] = true
L["Thumb Color"] = true
L["Thumb Width"] = true
L["Hide scroll bar arrows"] = true
L["Hides the up and down arrow buttons at the ends of the tracker scroll bar. The bar still scrolls by dragging the thumb or using the mouse wheel."] = true
L["Colors & Dimensions"] = true
L["Reset to Defaults"] = true
L["Reset all Appearance settings to defaults?"] = true
L["Quest Title Color Override"] = true
L["When cleared, falls back to difficulty coloring or default yellow."] = true
L["Use class color"] = true
L["Colors quest, achievement, and endeavor titles with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."] = true
L["Use title color for completed quests"] = true
L["Instead of green."] = true
L["Section Header Color"] = true
L["Colors the section headers (Quests, Campaign, and so on) with the class color of the character you are currently logged in on. Overrides the color above while it is on. Off by default."] = true
L["Divider Line Color"] = true
L["Sets the color of the thin line under each section header. Defaults to the original gold."] = true
L["Tracker Scale"] = true
L["Block Spacing"] = true
L["Line Spacing"] = true
L["Adds vertical space between a quest's objective lines, across the whole tracker. 0 keeps the default spacing."] = true
L["Header Spacing"] = true
L["Adds or removes space around section headers and beneath each quest's title. 0 keeps the default spacing."] = true
L["Zone Bar Scale"] = true
L["Zone Bar Appearance"] = true
L["Same as tracker font"] = true
L["Bar Texture"] = true
L["Sets the fill texture of the zone progress bar. Textures added by other media addons (such as SharedMedia, ElvUI, or Details) appear here too."] = true
L["Header Color"] = true
L["Count Color"] = true

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
L["Right-click to open in the Chain Guide"] = true
L["Click to expand"] = true
L["Export"] = true
L["Re-scan names"] = true
L["Asks the server for the name of any \"Quest #12345\" entries. They'll fill in over the next minute or two as responses arrive."] = true
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
L["Questline"] = true
L["Calling"] = true
L["Recurring"] = true
L["World Quest"] = true
L["Sort:"] = true
L["Date"] = true
L["Name"] = true
L["Sort direction"] = true
L["Click to flip ascending / descending."] = true
L["Hide undated  |cffaaaaaa(backfilled)|r"] = true
L["(no matching quests)"] = true
L["%d entries"] = true
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
L["By character"] = true
L["Top single-quest rewards"] = true
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
L["   |cffaaaaaa(%.1f / hour)|r"] = true
L["%d   |cffaaaaaa(%d to %d)|r"] = true
L["Press Ctrl+A to select all, then Ctrl+C to copy."] = true

-- ─── Modules/History/Recorder.lua ───
L["first time seeing |cffffffff%s|r - added %d past completion%s (no dates; future turn-ins are dated)."] = true
L["Quest history loaded empty; restored a backup from %s (%d entries)."] = true
L["Quest history for %s was missing; restored a backup from %s (%d entries)."] = true

-- ─── Modules/Tracker/Achievements.lua ───
L["Left-click to open, right-click to untrack."] = true

-- ─── Modules/Tracker/AutoQuestPopup.lua ───
L["Click to view quest"] = true
L["Quest Complete!"] = true
L["Quest Discovered!"] = true

-- ─── Modules/Tracker/Events.lua ───
L["Find Group"] = true
L["Open the Premade Group Finder for this quest."] = true
L["Untrack Quest"] = true
L["Track Quest"] = true
L["Super-track (follow arrow)"] = true
L["Search on Wowhead"] = true

-- ─── Modules/Tracker/Frame.lua ───
L["Tracker locked"] = true
L["Move and resize are off. Uncheck \"Lock tracker\" in /eqs > General."] = true
L["Drag to move the tracker"] = true
L["/eqs for options"] = true
L["Open the options panel"] = true
L["Open the Chain Guide"] = true
L["Unpin from tracker"] = true
L["Pin to tracker"] = true
L["Unfocus"] = true
L["Focus"] = true
L["Get Directions"] = true
L["Open in Map & Quest Log"] = true
L["Pop Out Quest Details"] = true
L["Abandon Quest"] = true
L["Drag the top edge of the tracker to move it.\n\nType |cffEBB706/eqs|r for options."] = true

-- ─── Modules/Tracker/Profession.lua ───
L["Open in Profession"] = true
L["Untrack Recipe"] = true

-- ─── Modules/Tracker/Scenario.lua ───
L["Final Stage"] = true
L["Stage %d"] = true

-- ─── Modules/Tracker/ScenarioBonusHUD.lua ───
L["Bonus Objectives"] = true
L["Unlock (allow moving)"] = true
L["Lock position"] = true
L["Reset position"] = true
L["Delve Bonus Loot"] = true

-- ─── Modules/WhatsNew.lua ───
L["See what's new"] = true
L["updated to"] = true
L["Open Options"] = true
L["Got it"] = true
L["Don't show these again"] = true
L["Stops What's New notices entirely. You can turn them back on in /eqs > General."] = true

-- ─── Modules/WorldQuests/Pin.lua ───
L["World Quest #"] = true

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
L["Recap your current play session in chat"] = true
L["List the current zone's quest chains in chat"] = true
L["Show the What's New popup again"] = true
L["Open this About tab"] = true
L["About"] = true
L["by Wheelbarrel00"] = true
L["for WoW Midnight (12.0.x)"] = true
L["A unified replacement for the Blizzard quest experience: a custom tracker, world-map overlays, quest history, and a Midnight chain guide."] = true
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
L["Changelog"] = true
L["Older versions are on CurseForge"] = true

-- Convert the `true` sentinels to their key (the self-keyed English default).
for k, v in pairs(L) do if v == true then L[k] = k end end
