local _, ns = ...

ns.Changelog = {
    {
        version = "1.37.1", date = "2026-08-02",
        sections = {
            { head = "Bug Fixes", items = {
                "Equipment slot names in reward tooltips are now translated. The gear comparison line on a quest reward showed its slot in English no matter what language the client was set to. All 21 slot names now come from the game's own text, so they match the wording on the item tooltip you are comparing against and are correct in every language.",
                "A cloak reward no longer says \"go back\". The slot name for a cloak shared a phrase with the Chain Guide's navigation button, so French, Russian and Korean players comparing a cloak read the word for \"go back\" where the slot name should have been.",
                "The reward chest tooltip works again. Hovering the chest icon on a scenario bonus objective silently did nothing, because the icon sat underneath the panel's own drag region and the hover never reached it.",
                "The drag ghost is readable again. Reordering quests by hand showed a solid red block that covered the row you were dropping onto. It is now a gold-outlined label that matches the width of the row you picked up, and you can see through it to the row underneath.",
                "The profile list is sorted. The profile dropdown listed profiles in no particular order, and the order could change between sessions without you touching anything.",
            } },
        },
    },
    {
        version = "1.37.0", date = "2026-07-31",
        sections = {
            { head = "Bug Fixes", items = {
                "The scroll bar thumb no longer stays stuck on the solid color. Turning Solid color thumb back off left the thumb showing the flat color until you reloaded, and toggling the option again could not recover it. Current retail thumbs are plain textures rather than atlases, and only the atlas was being restored.",
                "Endeavor requirements no longer show a double dash. Every requirement line in the Endeavors section read \"- - 1 / 15 Quests completed\", because the game already supplies the bullet and Everything Quests added a second one. Completed requirements also had a stray dash next to their checkmark.",
                "Endeavor requirements show colored progress counts. The whole line was drawn in flat grey, so a requirement's 0/15 never got the red, orange or green treatment that quest objectives, achievements and event objectives all use. Requirements with no count of their own still stay grey, as they do elsewhere.",
                "Completed endeavor requirements and profession reagents follow your complete color. Both were locked to green and ignored Use title color for completed quests, which the Achievements and quest sections already honored.",
                "Endeavor titles follow your title color. The title color and Use class color options both name endeavor titles, but the Endeavors section never applied either and its titles stayed Blizzard yellow.",
            } },
            { head = "Improvements", items = {
                "The Chain Guide now knows The Curse of Ula'tek. The patch 12.0.7 storyline was listed as \"Revelations (12.0.7)\" with its five questlines sitting loose below the zones. It now carries the campaign name the game uses, sits with the other campaigns, and renders as a campaign map with its chapters in order: Legacy of the Amani, An Island of Fangs, Ghosts of the Past, Original Sin, and The Battle for Atal'Utek.",
            } },
        },
    },
    {
        version = "1.36.0", date = "2026-07-26",
        sections = {
            { head = "New Features", items = {
                "Card layout for the tracker - a new Quest Rows section under /eqs > Appearance switches the tracker from plain rows to a Card layout, which draws every quest, achievement, endeavor, tracked recipe and world quest on its own bordered panel. Background color, border color, border thickness and padding are all adjustable, and cards can optionally be tinted by quest type so campaign, legendary, dungeon and raid quests stand out at a glance. Plain remains the default, so nothing changes until you switch it on.",
            } },
            { head = "Bug Fixes", items = {
                "Profession reagents now count every quality tier. The Profession section only counted the lowest quality of a reagent, so a bag full of rank 2 or rank 3 materials could still read as 0 held; it now sums all qualities the way Blizzard's own tracker does.",
                "Tracked recrafts are no longer broken. A recraft was never recognized as one, so it was mislabeled, listed the reagents of the normal recipe instead of its own, collapsed into a single row when the same recipe was tracked both ways, and could throw an error when untracked.",
                "Required modifying slots and currency reagents no longer vanish from the Profession section - both were skipped entirely despite counting toward the craft.",
                "Variable-quantity reagent slots show a range instead of a count against zero.",
                "The tracker's content column is now centered. With the tracker background on, rows sat 4 pixels from the left edge but 22 from the right.",
            } },
            { head = "Improvements", items = {
                "The recraft label in the Profession section now follows your language instead of a hardcoded English suffix.",
                "French and Russian translations updated for the new options. Thanks to Zox (French) and Malevi4 (Russian).",
            } },
        },
    },
    {
        version = "1.35.0", date = "2026-07-26",
        sections = {
            { head = "New Features", items = {
                "Restyle the zone progress bar - a new Bar Texture dropdown and Bar Color picker under /eqs > Appearance let you change the bar's fill texture and color. Choose from seven bundled Everything Quests bar styles or any statusbar texture from SharedMedia and other media addons, each shown with a live preview in a scrollable list. Thanks to Da Warrior for the request.",
                "Tracker line and header spacing - two new sliders under /eqs > Appearance, Line Spacing and Header Spacing, add or reduce the vertical space between a quest's objective lines and around section headers. Thanks to Rhinoplasty for the line-spacing idea.",
                "Class color button in the color picker - for players without ElvUI, the color picker now has a Class button that sets any Everything Quests color to your class color.",
            } },
            { head = "Improvements", items = {
                "French and Russian translations updated for the new options. Thanks to Zox (French) and Malevi4 (Russian).",
            } },
        },
    },
    {
        version = "1.34.0", date = "2026-07-15",
        sections = {
            { head = "New Features", items = {
                "Scale the settings window - a new Options Window Scale slider under /eqs > General resizes the entire Everything Quests options window so you can make it larger or smaller to fit your screen. The setting is account-wide.",
            } },
            { head = "Improvements", items = {
                "More of the interface follows your language - several World Quest labels and status strings (time left, world quest, expired, ready to turn in, and others) that were shown in English regardless of your game client now use your language's translation.",
                "Lighter in the background - the World Quests section, profession reagent lookups, Quest History, and quest nameplate icons now do less redundant work on each refresh.",
                "French and Russian translations updated for this release. Thanks to Zox (French) and Malevi4 (Russian).",
            } },
            { head = "Bug Fixes", items = {
                "Quest item buttons no longer stay blank after combat. A usable quest item added to the tracker while you were in combat could show an empty button until the next update; it now paints correctly once combat ends.",
                "A hidden tracker no longer catches clicks. When the tracker was hidden during combat it could still intercept mouse clicks in its now-invisible area.",
                "Quest objectives that loaded blank on login now fill in. An objective line whose text had not yet streamed from the server could stay blank for the rest of the session.",
                "Wiping Quest History now also clears the gold and trends data. The per-day gold totals behind the Trends view used to survive a history wipe.",
                "Chain Guide chapters no longer appear twice. A campaign chapter could show under both its campaign and a zone questline until the guide was reopened.",
                "Reset all settings now truly resets everything - the window scale, What's New notice mode, and minimap-button visibility were left untouched despite the dialog's promise.",
                "Assorted smaller fixes to the History heatmap and timeline, the Endeavors header count, scenario header fonts, and several option hit areas, plus internal hardening so one failing module can no longer stop others from loading.",
            } },
        },
    },
    {
        version = "1.33.0", date = "2026-07-11",
        sections = {
            { head = "New Features", items = {
                "New quest nameplate icons - the marker over a quest enemy is now the Everything Quests crest in place of the default exclamation mark, and kill objectives use a custom skull. Thanks to DrahgunFyre for the suggestion.",
            } },
            { head = "Improvements", items = {
                "Quest History follows your local day - the activity heatmap, streak, and trends now group turn-ins by your own calendar day instead of server time, so a late-night quest counts on the day you actually did it. This also fixes day labels that could read one day early west of UTC.",
                "Smoother History search - typing in the History search box no longer re-runs the full search on every keystroke.",
            } },
            { head = "Bug Fixes", items = {
                "Chain Guide campaign chapters no longer attach to the wrong zone. On some setups a campaign's chapters could register under an unrelated zone category for the session, leaving the real campaign entry empty; they now register only under their own campaign.",
                "Quest nameplate icons no longer skip your own quest in a group. When a party member's quest for the same enemy was listed first, your own objective icon could be dropped; it now shows reliably.",
                "The World Quest faction filter now applies. A dead code path meant a quest's own faction was never checked, so unchecking a faction on the map only partly filtered it; it now filters by the quest's faction as intended.",
            } },
            { head = "Thanks", items = {
                "Special thanks to DrahgunFyre for the nameplate icon idea and the steady stream of features, fixes, and reports that keep shaping Everything Quests.",
            } },
        },
    },
    {
        version = "1.32.0", date = "2026-07-08",
        sections = {
            { head = "New Features", items = {
                "Criteria Text Size - a new slider under /eqs > Appearance > Scenario resizes the objective (criteria) lines inside scenarios and delves, which used to render smaller than the rest of your tracker text.",
            } },
            { head = "Bug Fixes", items = {
                "Show only quests in current zone no longer empties the tracker. It was matching quest-log group headers (often Campaign) against your zone name and hiding everything; it now uses the quests actually on your current map.",
                "The tracker's hide options (in combat, in instances, in Mythic+, on map open) now actually hide it. Under Midnight the tracker owns protected quest-item buttons that were silently blocking the hide, so it now fades out reliably.",
                "The World quests tracker filter now works - the checkbox previously had no effect.",
                "Currency quest rewards show in tooltips again after a Midnight API change, and reputation World Quests are now categorized correctly in every language.",
                "World Quests you tracked no longer return as phantom rows after each login, and right-click Track/Untrack on a World Quest now targets the correct quest and recognizes quests Blizzard is already watching.",
                "Distance sort now includes ready-to-turn-in quests instead of stranding them at the bottom of the list.",
                "Creating a New Profile with the same name as an existing profile now asks before overwriting it.",
                "Pinned quests you were not watching no longer freeze and stop updating their objectives.",
                "Reset filters to defaults now correctly re-checks the watched-only box.",
                "Assorted stability fixes to the Chain Guide, the Zone Progress bar, and the scenario banner.",
            } },
            { head = "Improvements", items = {
                "Lower background CPU and memory use - the scenario tracker, Bonus Objectives HUD, quest-completion sound, and internal event handling are now debounced and coalesced, several retry loops are capped, and the tracker no longer rebuilds while it is hidden.",
            } },
            { head = "Thanks", items = {
                "Special thanks to Agaman - thanks for the codework on this one, your help has been extremely helpful.",
                "French and Russian translations updated for this release, by Zox (French) and Malevi4 (Russian).",
            } },
        },
    },
    {
        version = "1.31.0", date = "2026-07-07",
        sections = {
            { head = "New Features", items = {
                "World Quests height - the World Quests area used to get squeezed down to a line or two when you had a lot of quests. There is now a Set a custom World Quests height option under /eqs > Tracker, with a slider to give it as much room as you want. Off by default. Thanks to TheOneMVP.",
                "Hide tracker in Mythic+ - a new option under /eqs > General tucks the tracker away during an active Mythic+ run and brings it back when the run ends, so it stays out of your way next to the dungeon timer. Off by default. Thanks to TheOneMVP.",
            } },
            { head = "Bug Fixes", items = {
                "The tracker no longer shrinks to a few lines after a relog when you have more quests than fit. The viewport was collapsing to a section boundary; it now fills the height you set and scrolls the overflow. Thanks to ShodanDelacroix for the debug info that pinpointed it.",
                "The quest-completion sound no longer occasionally plays once at login. On a cold login the sound tracker could capture its baseline before the quest log finished syncing, then mistake every already-complete quest for a fresh completion; it now only plays on a real incomplete-to-complete transition.",
                "Fixed a Lua error when opening the flight map with a quest tracked (the taxi-node highlighter misread a map API's return values). Thanks to DrahgunFyre for the report.",
            } },
        },
    },
    {
        version = "1.30.2", date = "2026-07-07",
        sections = {
            { head = "Bug Fixes", items = {
                "The tracker no longer shrinks to a few lines a moment after you log in. With a background or border enabled, the bordered window collapsed to hug the quest content while the resize handle stayed at the full height, leaving a large empty gap below it. The window now fills the full height you size it to. Thanks to ShodanDelacroix for the detailed report.",
            } },
            { head = "Improvements", items = {
                "Russian translation - the Campaign term now uses the WoW-official spelling «Кампания». Thanks to Malevi4.",
            } },
        },
    },
    {
        version = "1.30.1", date = "2026-07-06",
        sections = {
            { head = "Improvements", items = {
                "Translations - French and Russian now cover everything added in the last two updates: the Bonus Objectives HUD, the class-color options, the custom header divider color, and the independent header size from v1.30.0, plus the tracker section order and update-notice options from v1.29.0. Thanks to Zox (French) and Malevi4 (Russian).",
            } },
        },
    },
    {
        version = "1.30.0", date = "2026-07-05",
        sections = {
            { head = "New Features", items = {
                "Bonus Objectives HUD - a new movable on-screen checklist for the bonus objectives you might otherwise miss. In delves it tracks the bonus loot mechanics (Nemesis Strongbox packs and the Sanctified Banner) so you can grab the extra rewards before the boss. Turn it on under /eqs > Tracker > Scenario Bonus Objectives, drag it anywhere, and right-click to lock or reset. Off by default. Thanks to DrahgunFyre for the idea in the Discord.",
                "Class color for titles and headers - new \"Use class color\" toggles under /eqs > Appearance color your quest and achievement titles, and your section headers, with the class color of the character you are logged in on. Off by default. Thanks to ChipW0lf.",
                "Custom header divider color - the thin line under each section header (Quests, Campaign, and so on) is no longer locked to gold; set any color under /eqs > Appearance > Divider Line Color. Thanks to ChipW0lf.",
                "Independent header text size - a new Header Size Offset slider under /eqs > Appearance sizes the section headers separately from the quest text, so they do not get oversized on a low UI scale. Thanks to ChipW0lf.",
            } },
            { head = "Improvements", items = {
                "More fonts - the font pickers now list every font registered through LibSharedMedia, including fonts added by other addons, instead of only the ones bundled with Everything Quests. Thanks to ChipW0lf.",
            } },
            { head = "Bug Fixes", items = {
                "The Clear button next to Quest Title Color Override now resets the color swatch when clicked.",
                "When the zone progress bar is set to \"Same as tracker font\", it now follows the main tracker font, size, outline, and shadow live.",
            } },
        },
    },
    {
        version = "1.29.0", date = "2026-07-03",
        sections = {
            { head = "New Features", items = {
                "Reorder tracker sections — put the tracker's sections in any order under /eqs > Tracker > Section Order, using the up/down arrows to move Campaign, Quests, Profession, Endeavors, Achievements, and the Zone Progress bar. Thanks to DrahgunFyre for suggesting it in the Discord.",
                "World Quests position — a Top / Bottom switch in the same Section Order area moves the World Quests panel above or below your quests; it keeps its own scrollbar and size cap either way.",
                "Quieter update notices — choose how you hear about new features under /eqs > General > After an update: a popup window (the default), a quiet clickable chat link, or nothing at all. The popup also has its own \"Don't show these again\" checkbox.",
            } },
            { head = "Improvements", items = {
                "Setting tooltips on multi-button options (like World Quests position and Nameplate icon position) now appear reliably next to the button you hover.",
            } },
        },
    },
    {
        version = "1.28.0", date = "2026-06-27",
        sections = {
            { head = "New Features", items = {
                "Chain Guide — added The Sunstrider Omnium (the Magisters' Terrace questline that unlocks the Omnium Folio) as its own zone, with its full quest chain mapped out like the rest of the Midnight content.",
                "Chain Guide map pins — quest-giver map pins now show for The Sunstrider Omnium and Void Acropolis chains, so you can find each step on the world map (Void Acropolis had none before).",
            } },
            { head = "Improvements", items = {
                "New addon icon — the minimap button, Titan Panel, and AddOns list now use a new gold crest in place of the old book.",
            } },
            { head = "Bug Fixes", items = {
                "Tracker sections no longer crowd together — with a lot of quests, achievements, and world quests tracked at once, a section's header could appear with its contents cut off. The quest list now keeps its sections intact, and the World Quests area yields space and scrolls instead.",
                "Ritual Sites (such as Broken Throne) now show \"Ritual Site\" in the tracker's scenario header instead of \"Delves\" — they run on the delve system, but the addon now matches Blizzard's own label.",
                "Fixed a combat error (\"action blocked\") that could appear when entering a Ritual Site or scenario while in combat with a usable quest item tracked.",
            } },
        },
    },
    {
        version = "1.27.0", date = "2026-06-26",
        sections = {
            { head = "New Features", items = {
                "Chain Guide — added the Void Acropolis zone, with its quest chains (Assault and Strike Back: Val, and Umbral Blitz) now mapped out so you can follow them like the rest of the Midnight zones.",
            } },
            { head = "Improvements", items = {
                "The two right-click options on a tracked quest now read more clearly: \"Open in Map & Quest Log\" (the game's quest map) and \"Pop Out Quest Details\" (Everything Quests' own detail panel).",
                "Appearance sliders (font sizes, shadows, border thickness, bar height, and so on) now adjust in finer 0.5 steps for more precise tuning.",
            } },
            { head = "Bug Fixes", items = {
                "The world-quest map panel no longer overlaps its pull-tab — the panel now sits clear of the tab.",
            } },
        },
    },
    {
        version = "1.26.0", date = "2026-06-25",
        sections = {
            { head = "Improvements", items = {
                "World Quest map panel — the world-quest popout on the world map is now a single docked panel (a reward summary plus a scrollable zone list) instead of separate floating boxes, and its pull-tab matches Blizzard's quest-map side tabs, including ElvUI's styling when its quest skin is active. Thanks to Malevi4 for the request.",
            } },
            { head = "Bug Fixes", items = {
                "The quest list now resizes with the tracker when you drag it wider or narrower — it previously stayed at a fixed width — and the scenario / delve banner now lines up with the quest list instead of drifting to the right on a wider tracker. Thanks to Malevi4 for reporting it and helping track down the cause.",
            } },
            { head = "Translations", items = {
                "Korean (koKR) is now fully translated, thanks to labrie75.",
            } },
        },
    },
    {
        version = "1.25.0", date = "2026-06-23",
        sections = {
            { head = "New Features", items = {
                "Header bar styles & soft edges (Appearance tab) — choose Header Bar 1 (a horizontal gradient) or Header Bar 2 (a vertical gradient), and turn on Soft edges to feather the bar's top, left, and right edges so it blends into the UI. An Edge Softness slider tunes how soft the edges are. Thanks to Malevi4 for the requests.",
                "Reset to Defaults (Appearance tab) — restores just the appearance settings (fonts, colours, shadows, header bar, scroll-bar skin, zone-bar look) to defaults, leaving filters, sections, sounds, and the zone bar's position untouched.",
            } },
            { head = "Improvements", items = {
                "The Appearance tab now scrolls inside the Options window, so it no longer runs off the bottom of the screen.",
            } },
            { head = "Bug Fixes", items = {
                "A campaign quest with a ready-to-turn-in popup could appear twice (once under Campaign, once under Quests); it now renders once, in the correct section.",
            } },
            { head = "Translations", items = {
                "Korean (koKR) is now available, thanks to labrie75 — most of the addon is translated, with more on the way.",
                "Russian (ruRU) wording refinements from Malevi4, plus the new strings; French (frFR) updated by Zox.",
            } },
        },
    },
    {
        version = "1.24.0", date = "2026-06-22",
        sections = {
            { head = "New Features", items = {
                "Header bars (Appearance tab) — an optional coloured gradient bar behind each section header (Quests, Campaign, World Quests, and so on) for a look closer to Blizzard's default tracker. Off by default, with Bar Color and Bar Height controls.",
            } },
            { head = "Improvements", items = {
                "The clickable quest-item button moved to the left of the quest icon, where it's easier to reach, and is slightly bigger; its red border was removed so it's just the icon.",
            } },
            { head = "Translations", items = {
                "French (frFR) and Russian (ruRU) are fully up to date again — thanks to Zox and Malevi4.",
            } },
        },
    },
    {
        version = "1.23.0", date = "2026-06-21",
        sections = {
            { head = "New Features", items = {
                "Scenario banner alignment & size (Appearance > Scenario) — move the delve / scenario banner Left, Center, or Right within the tracker, and resize its Stage and name text.",
                "'Search on Wowhead' in the quest right-click menu — opens a copy-ready link to the quest's Wowhead page (also on the world-quest menus).",
                "Nameplate quest-icon position & size (General tab) — place the icon + count Left, Right, Above, or Below the nameplate, with separate icon-size and count-text-size sliders.",
                "World map world-quest list behind a tab — the summary + list tuck behind a world-quest tab on the map's right edge; click to show or hide. The quest pins are unaffected.",
            } },
            { head = "Improvements", items = {
                "The tracker's quest right-click menu (and the world-quest menus) are now fully translatable.",
            } },
        },
    },
    {
        version = "1.22.1", date = "2026-06-18",
        sections = {
            { head = "Translations", items = {
                "Russian (ruRU) updated by Malevi4 and French (frFR) updated by Zox — both languages are now fully up to date with the latest features.",
            } },
            { head = "Other", items = {
                "Some code cleanup.",
            } },
        },
    },
    {
        version = "1.22.0", date = "2026-06-18",
        sections = {
            { head = "New Features", items = {
                "Shadow Size slider (Appearance) — set how far the tracker's text shadow is cast.",
                "A separate Scenario shadow group (Appearance) — the delve / scenario banner gets its own text-shadow toggle, color, and size, apart from the main tracker text.",
                "The world map's world-quest list now scrolls in a compact panel instead of filling the screen in zones with many world quests.",
            } },
            { head = "Improvements", items = {
                "Appearance tab cleanup — the color boxes line up, a new 'Tracker' header sits over the background/border options, and the scroll-bar options moved beside the Zone Bar group.",
                "The Options and Chain Guide windows no longer overlap — opening one closes the other.",
            } },
            { head = "Bug Fixes", items = {
                "Fixed your regular quests sometimes not loading on login (only world quests showing) until a /reload; the tracker now fills in as soon as your quest data arrives.",
                "Fixed an error when untracking a profession recipe from the tracker.",
                "Progress-bar achievements (like '61/100') now show their count in the tracker, not just their title.",
            } },
        },
    },
    {
        version = "1.21.1", date = "2026-06-17",
        sections = {
            { head = "Bug Fixes", items = {
                "Fixed the group-finder eye appearing on every world quest (a v1.21.0 regression); it now shows only on world bosses and group quests, matching Blizzard's own tracker.",
            } },
        },
    },
    {
        version = "1.21.0", date = "2026-06-17",
        sections = {
            { head = "New Features", items = {
                "Chain Guide overhaul, Phase 3 of 3 (map integration) — the overhaul is COMPLETE. Press Track on a chain and its quests pin on your world map (next step in gold) with a waypoint that auto-advances as you turn quests in, even with the guide closed.",
                "New 'Revelations (12.0.7)' chains — Legacy of the Amani and the March on Quel'Danas raid lead-up.",
                "Independent title size + a text-shadow option for the tracker (Appearance tab). (Suggested by tanglies.)",
                "Quick cogwheel + Chain Guide buttons at the top of the tracker, each with its own on/off toggle. (Suggested by tanglies.)",
                "Tracked achievements: a simplify mode (show only what's left), right-click to untrack, left-click to open the Achievement panel. (Suggested by tanglies.)",
            } },
            { head = "Improvements", items = {
                "The group-finder button now appears on every group-listable world boss, not just some.",
                "The Chain Guide resize grip (bottom-right) is bigger and easier to grab; the Track button reads Untrack while following a chain.",
            } },
            { head = "Bug Fixes", items = {
                "Fixed the chain 'next step' sometimes pointing at the opposite faction's version of a quest.",
                "Trimmed war-table / meta quests that aren't part of a storyline, so chains end at their real final quest.",
            } },
        },
    },
    {
        version = "1.20.0", date = "2026-06-16",
        sections = {
            { head = "New Features", items = {
                "Chain Guide overhaul, Phase 2 of 3 — every quest chain in Midnight (all zones and the campaign) now draws as a real branching graph instead of a flat list, so you can see which quests unlock which and where paths split and rejoin.",
                "Drag anywhere on the graph to pan around larger chains.",
                "The Chain Guide window is now resizable (drag the corner; your size is saved) with a button to collapse the side list so the graph fills the whole window.",
            } },
            { head = "Improvements", items = {
                "More compact quest cards so you see more of a chain at a glance.",
                "Scenario and dungeon titles are now centered in their banner.",
            } },
            { head = "Bug Fixes", items = {
                "Opening the options from the Chain Guide no longer leaves the two windows overlapping.",
            } },
        },
    },
    {
        version = "1.19.0", date = "2026-06-14",
        sections = {
            { head = "New Features", items = {
                "Chain Guide overhaul, Phase 1 of 3 — the guide now shows your NEXT step (gold border + a Continue button that routes you there) and tags quests already in your log as ON QUEST. Opening a chain scrolls to where you are.",
                "Rich Chain Guide tooltips — hover a quest for its level, objectives, and rewards, including the gear-upgrade comparison.",
                "Search the Chain Guide by quest name, not just ID (questline names match too).",
            } },
            { head = "Improvements", items = {
                "Chain nodes show each quest's level and ID; a quest ready to turn in is highlighted gold.",
                "Now available in Russian (ruRU), with updated French (frFR). New Chain Guide text will be translated once the overhaul is complete.",
            } },
            { head = "Bug Fixes", items = {
                "Getting directions from the Chain Guide in combat no longer trips an action-blocked error — the map open waits until you leave combat (the quest is still super-tracked immediately).",
            } },
        },
    },
    {
        version = "1.18.0", date = "2026-06-13",
        sections = {
            { head = "New Features", items = {
                "Search the Chain Guide by Quest ID — jumps to the chain containing it and rings the quest, so a non-English client can follow an English guide without translating names. (Sparta || Phrenic)",
                "Tracker Skins (Appearance tab): give the scroll bar a flat single-color thumb with its own color and width, or hide the up/down arrows. (Fostot)",
                "New About tab with links, slash commands, credits, and the changelog (/eqs about).",
            } },
            { head = "Improvements", items = {
                "The tracker background now wraps just your visible quests and hides when empty, instead of a tall empty box. (Spydawg2233)",
                "Every option's grey description moved into a hover tooltip for cleaner panels.",
                "Brightened the brand red used for headers, borders, and accents.",
            } },
            { head = "Bug Fixes", items = {
                "Newly accepted quests now track reliably (a stable manual watch instead of an evictable automatic one).",
            } },
        },
    },
    {
        version = "1.17.0", date = "2026-06-12",
        sections = {
            { head = "New Features", items = {
                "Quest reward gear comparison — hovering a quest in the tracker (and World Quest tooltips) shows each equippable reward's item level versus what you have equipped, and whether it's an upgrade.",
            } },
            { head = "Improvements", items = {
                "The tracker can stretch much taller — its maximum height was roughly doubled. (Spydawg2233)",
            } },
        },
    },
    {
        version = "1.16.0", date = "2026-06-08",
        sections = {
            { head = "New Features", items = {
                "Customize the floating zone progress bar — toggle its background/border, pick a border color, choose its font, and set the header and count colors.",
            } },
            { head = "Improvements", items = {
                "More of the interface displays in French (History tabs, Chain Guide nav and counts). (Zox)",
                "Lighter Chain Guide rendering.",
            } },
        },
    },
    {
        version = "1.15.0", date = "2026-06-07",
        sections = {
            { head = "New Features", items = {
                "Options button in the Chain Guide's navigation bar, opening settings straight to the Chain Guide tab. (Zox)",
            } },
            { head = "Improvements", items = {
                "More of the interface is translatable, plus a round of French refinements. (Zox)",
            } },
        },
    },
    {
        version = "1.14.1", date = "2026-06-06",
        sections = {
            { head = "Bug Fixes", items = {
                "The zone progress bar now shows up reliably on every character, including fully-completed zones.",
            } },
            { head = "Improvements", items = {
                "French translation complete — the whole interface displays in French on a French client. (Zox)",
            } },
        },
    },
}
