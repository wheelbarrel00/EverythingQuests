local _, ns = ...
local L = ns.L

ns:GetSubsystem("Options"):AddTab("general", L["General"], function(content)
    local Options = ns:GetSubsystem("Options")

    local function generalSetting(key)
        return
            function()
                local DB = ns:GetSubsystem("DB")
                return DB and DB.db.profile.general[key]
            end,
            function(value)
                local DB = ns:GetSubsystem("DB")
                if DB then DB.db.profile.general[key] = value end
            end
    end

    local h = Options:CreateSectionHeader(content, L["General"])
    h:SetPoint("TOPLEFT", 8, -8)

    -- Sections are skipped per flavor, which would break a chain of SetPoint(prev), so the
    -- column walks a cursor carrying an absolute indent instead.
    local prev, prevIndent = h, 0
    local function place(widget, indent, gap)
        indent = indent or 0
        widget:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", indent - prevIndent, -gap)
        prev, prevIndent = widget, indent
        return widget
    end

    local function refreshPins()
        local P = ns:GetSubsystem("MapPOIProvider")
        if P and P.provider and P.provider.RefreshAllData then
            P.provider:RefreshAllData()
        end
    end

    if ns:GetSubsystem("MapPOIProvider") then
        local function questPinsGet()
            local DB = ns:GetSubsystem("DB")
            return not DB or not DB.db.profile.map
                   or DB.db.profile.map.showQuestPins ~= false
        end
        local function questPinsSet(v)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.showQuestPins = v and true or false
            end
            refreshPins()
        end
        local qpins = Options:CreateCheckbox(content,
            L["Show quest pins on the world map"],
            questPinsGet, questPinsSet,
            L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Uncheck this box and all of EQ's red markers go away. Quests you have not accepted yet are controlled separately."])
        place(qpins, 0, 16)

        local function pinScaleGet()
            local DB = ns:GetSubsystem("DB")
            local s = DB and DB.db.profile.map and DB.db.profile.map.pinScale
            return type(s) == "number" and s or 1.0
        end
        local function pinScaleSet(value)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.pinScale = value
            end
            refreshPins()
        end
        local pinScale = Options:CreateSlider(content, L["World map pin scale"],
            0.5, 2.0, 0.05, pinScaleGet, pinScaleSet)
        place(pinScale, 4, 6)
        pinScale:SetWidth(280)
        Options:AttachTooltip(pinScale, L["World map pin scale"],
            L["Quest pins are drawn at a fixed size no matter how far the map is zoomed, and this sets that size. Raise it if the pins are hard to pick out on a large or high-resolution display."])

        local MAX_PINS = ns.MAPPOI_MAX_PINS or 250
        local function pinCapGet()
            local DB = ns:GetSubsystem("DB")
            local n = DB and DB.db.profile.map and DB.db.profile.map.pinCap
            return type(n) == "number" and n or 50
        end
        local function pinCapSet(value)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.pinCap = value
            end
            refreshPins()
            -- The minimap reads the same pinCap, so without this it keeps the old set until an
            -- unrelated quest event fires
            local MM = ns:GetSubsystem("MinimapQuestPins")
            if MM then MM:Rebuild() end
        end
        local pinCap = Options:CreateSlider(content, L["Objective pins per quest"],
            25, MAX_PINS, 25, pinCapGet, pinCapSet,
            function(v) return v >= MAX_PINS and L["No limit"] or ("%d"):format(v) end)
        place(pinCap, 4, 6)
        pinCap:SetWidth(280)
        Options:AttachTooltip(pinCap, L["Objective pins per quest"],
            L["How many places to mark for a single quest on one map. The busiest locations are kept first, so a lower number still points you somewhere useful. Slide all the way right for no limit at all - a few gathering quests can then put hundreds of markers on one map."])
    end

    local Avail = ns:GetSubsystem("AvailableQuests")
    if Avail then
        local function rebuildAvailable()
            Avail:Invalidate()
            refreshPins()
            local MM = ns:GetSubsystem("MinimapQuestPins")
            if MM then MM:Rebuild() end
        end

        local function availGet()
            local DB = ns:GetSubsystem("DB")
            return not DB or not DB.db.profile.map
                   or DB.db.profile.map.showAvailableQuests ~= false
        end
        local function availSet(v)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.showAvailableQuests = v and true or false
            end
            rebuildAvailable()
        end
        local avail = Options:CreateCheckbox(content,
            L["Show quests you can pick up"],
            availGet, availSet,
            L["Marks every quest giver who has something for you but is not in your quest log yet, with a gold ring around the exclamation mark so it reads apart from the quests you are already carrying. One marker covers a whole quest giver, and hovering it lists everything that giver offers. Quests are filtered by your level, race, class and the quests you have already finished. Holiday quests are left out, because nothing in the data says whether the holiday is running."])
        place(avail, 0, 16)

        local function lowGet()
            local DB = ns:GetSubsystem("DB")
            return not DB or not DB.db.profile.map
                   or DB.db.profile.map.hideLowLevelQuests ~= false
        end
        local function lowSet(v)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.hideLowLevelQuests = v and true or false
            end
            rebuildAvailable()
        end
        local low = Options:CreateCheckbox(content,
            L["Hide quests below your level"],
            lowGet, lowSet,
            L["Leaves out quests the game has already grayed out for you, using the game's own threshold rather than a fixed number of levels. On by default. Turn it off to see everything a quest giver has, including the quests you have outleveled."])
        place(low, 16, 6)
    end

    local MinimapPins = ns:GetSubsystem("MinimapQuestPins")
    if MinimapPins then
        local function minimapPinsGet()
            local DB = ns:GetSubsystem("DB")
            return not DB or not DB.db.profile.map
                   or DB.db.profile.map.showMinimapPins ~= false
        end
        local function minimapPinsSet(v)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.showMinimapPins = v and true or false
            end
            MinimapPins:Rebuild()
        end
        local mmpins = Options:CreateCheckbox(content,
            L["Show objective pins on the minimap"],
            minimapPinsGet, minimapPinsSet,
            L["Puts the same objective markers on the minimap as on the world map, for the zone you are standing in. They use the per-quest limit above. Hover one for the quest name and what it still needs."])
        place(mmpins, 0, 16)
    end

    if ns:GetSubsystem("QuestAuto") then
        local autoAccGet, autoAccSet = generalSetting("autoAcceptQuests")
        local autoAcc = Options:CreateCheckbox(content,
            L["Auto-accept quests"],
            autoAccGet, autoAccSet,
            L["Hold Alt to pause."])
        place(autoAcc, 0, 6)

        local autoTIGet, autoTISet = generalSetting("autoTurnInQuests")
        local autoTI = Options:CreateCheckbox(content,
            L["Auto-turn-in quests"],
            autoTIGet, autoTISet,
            L["Skips reward-choice screens."])
        place(autoTI, 0, 2)
    end

    if ns:GetSubsystem("MapPOIProvider") then
        local mapHeader = Options:CreateSectionHeader(content, L["Map"])
        place(mapHeader, 0, 16)

        -- Asked of the pin's own resolver rather than read here, because an unset value means ON
        -- on retail and OFF on Classic. A second copy of that rule would leave the box and the map
        -- disagreeing, and only one of the two is on screen at a time.
        local function pinRingGet()
            return ns.QuestPinRingWanted and ns.QuestPinRingWanted(false) or false
        end
        local function pinRingSet(v)
            local DB = ns:GetSubsystem("DB")
            if DB then
                DB.db.profile.map = DB.db.profile.map or {}
                DB.db.profile.map.showPinRing = v and true or false
            end
            refreshPins()
        end
        local pinRing = Options:CreateCheckbox(content,
            L["Show a ring around quest pins"],
            pinRingGet, pinRingSet,
            L["Draws the red circle behind every world map marker for a quest in your log, both the ones you are still working on and the ones that are ready to turn in. Turn it off for plain icons and a much quieter map when a zone is busy."])
        place(pinRing, 0, 10)

        if ns:GetSubsystem("AvailableQuests") then
            local function availRingGet()
                local DB = ns:GetSubsystem("DB")
                return (DB and DB.db.profile.map and DB.db.profile.map.showAvailableRing) == true
            end
            local function availRingSet(v)
                local DB = ns:GetSubsystem("DB")
                if DB then
                    DB.db.profile.map = DB.db.profile.map or {}
                    DB.db.profile.map.showAvailableRing = v and true or false
                end
                refreshPins()
                local MM = ns:GetSubsystem("MinimapQuestPins")
                if MM then MM:Rebuild() end
            end
            local availRing = Options:CreateCheckbox(content,
                L["Show a ring around quests you can pick up"],
                availRingGet, availRingSet,
                L["Draws the gold circle behind the exclamation mark of every quest giver who has something for you. Off by default. The mark itself still tells these apart from the quests you are already carrying, because those use their own objective art or the turn-in mark instead."])
            place(availRing, 0, 6)
        end
    end

    if Avail and ns.CLASSIC_QUEST_CATEGORY then
        local function rebuildAvailable()
            Avail:Invalidate()
            refreshPins()
            local MM = ns:GetSubsystem("MinimapQuestPins")
            if MM then MM:Rebuild() end
        end

        -- Each box HIDES its category, so the stored value is the filter rather than the content.
        -- nil therefore reads as "show it" and an existing profile is unchanged.
        local function categoryOption(key, label, tooltip)
            local box = Options:CreateCheckbox(content, label,
                function()
                    local DB = ns:GetSubsystem("DB")
                    return (DB and DB.db.profile.map and DB.db.profile.map[key]) == true
                end,
                function(v)
                    local DB = ns:GetSubsystem("DB")
                    if DB then
                        DB.db.profile.map = DB.db.profile.map or {}
                        DB.db.profile.map[key] = v and true or false
                    end
                    rebuildAvailable()
                end,
                tooltip)
            place(box, 16, 6)
        end

        local filterHeader = Options:CreateSectionHeader(content, L["Hide these quests on the map"])
        place(filterHeader, 0, 14)
        Options:AttachTooltip(filterHeader, L["Hide these quests on the map"],
            L["These only affect the markers for quests you have NOT picked up yet. A quest already in your log always keeps its markers, because hiding something you are carrying would make the map lie about what you still have to do."])

        categoryOption("hideDungeonQuests", L["Dungeon and raid quests"],
            L["Leaves out quests that are sorted into a dungeon or a raid. Most are picked up inside the instance or from a quest giver at its door, so they clutter the outdoor map without helping you while you are questing in the world."])
        categoryOption("hideRepeatableQuests", L["Repeatable quests"],
            L["Leaves out the quests you can hand in over and over, usually a turn-in for reputation or a common trade good. They never stop being offered, so they stay on the map forever once you can see them."])
        categoryOption("hideProfessionQuests", L["Profession quests"],
            L["Leaves out quests that require a trade skill, such as a Blacksmithing or Alchemy specialization. Everything Quests cannot read your skill levels on this version of the game, so these are offered even when you have not trained the profession they need."])
    end

    do
        local QB = ns:GetSubsystem("QuestBrowser")
        if QB and QB.Available and QB:Available() then
            local browserHeader = Options:CreateSectionHeader(content, L["Quest Browser"])
            place(browserHeader, 0, 16)

            local browserBtn = Options:CreateYellowButton(content, L["Open Quest Browser"], function()
                local B = ns:GetSubsystem("QuestBrowser")
                if B then B:Open() end
            end)
            place(browserBtn, 0, 12)
            Options:AttachTooltip(browserBtn, L["Quest Browser"],
                L["Look up almost any quest in the game, including ones you have never picked up. Shows the level and race and class requirements, where it starts and turns in, what has to be finished first, and why you cannot take it yet. Also on /eqs quests, or right-click a gold quest marker on the map."])
        end
    end

    if ns:GetSubsystem("TrackerBridge") then
        local trackerHeader = Options:CreateSectionHeader(content, L["Tracker"])
        place(trackerHeader, 0, 16)

        local trackerBtn = Options:CreateYellowButton(content, L["Open Tracker Settings"], function()
            local Bridge = ns:GetSubsystem("TrackerBridge")
            if Bridge then Bridge:OpenTrackerOptions() end
        end)
        place(trackerBtn, 0, 10)
        Options:AttachTooltip(trackerBtn, L["Open Tracker Settings"],
            L["The tracker is now EQ Objective Tracker, a separate addon that Everything Quests installs for you. Its own options panel holds everything: position and size, fonts, colors, sections, filters, sorting and visibility. You can also open it by typing /eqot, or with the cogwheel at the top right of the tracker itself."])

        local eqIconGet, eqIconSet = generalSetting("showEQIcon")
        local eqIcon = Options:CreateCheckbox(content,
            L["Show Everything Quests icon on the tracker"],
            eqIconGet,
            function(value)
                eqIconSet(value)
                local Bridge = ns:GetSubsystem("TrackerBridge")
                if Bridge then Bridge:ApplyEQIcon() end
            end,
            L["Adds the Everything Quests logo at the top right of the tracker, which opens this options window. The tracker's own cogwheel opens the tracker's settings instead. You can also reach this window from the minimap button or by typing /eqs."])
        place(eqIcon, 0, 8)

        if ns:GetSubsystem("ChainGuide") then
            local chainIconGet, chainIconSet = generalSetting("showChainGuideIcon")
            local chainIcon = Options:CreateCheckbox(content,
                L["Show Chain Guide icon on the tracker"],
                chainIconGet,
                function(value)
                    chainIconSet(value)
                    local Bridge = ns:GetSubsystem("TrackerBridge")
                    if Bridge then Bridge:ApplyChainIcon() end
                end,
                L["Adds a small chain icon beside the cogwheel at the top right of the tracker, which opens the Chain Guide."])
            place(chainIcon, 0, 2)
        end
    end

    local function owScaleGet()
        local DB = ns:GetSubsystem("DB")
        return (DB and DB.db.global.optionsWindowScale) or 1.0
    end
    local function owScaleSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB and type(value) == "number" and value > 0 then
            DB.db.global.optionsWindowScale = value
        end
    end
    local owScale = Options:CreateSlider(content, L["Options Window Scale"], 0.7, 1.4, 0.05, owScaleGet, owScaleSet)
    place(owScale, 0, 18)
    owScale:SetWidth(280)
    Options:AttachTooltip(owScale, L["Options Window Scale"],
        L["Resizes this Everything Quests options window only. It does not change the quest tracker or anything shown in the game world. The new size applies when you let go of the slider."])
    -- The slider sits inside the window it scales, so applying mid-drag fights the drag and snaps to the ends
    if owScale.slider then
        owScale.slider:HookScript("OnMouseUp", function() Options:ApplyWindowScale() end)
    end

    if ns:GetSubsystem("WhatsNew") then
        local WHATSNEW_MODES = {
            { value = "popup", label = L["Popup window"] },
            { value = "chat",  label = L["Chat link"] },
            { value = "none",  label = L["None"] },
        }
        local function wnModeGet()
            local DB = ns:GetSubsystem("DB")
            return (DB and DB.db.global.whatsNewMode) or "popup"
        end
        local function wnModeSet(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.global.whatsNewMode = value end
        end
        local wnMode = Options:CreateRadioGroup(content, L["After an update"],
            WHATSNEW_MODES, wnModeGet, wnModeSet, 320, 14,
            L["After an update"],
            L["How Everything Quests tells you about new features: a Popup window, a quiet clickable Chat link in your chat frame, or None. New features always ship off until you turn them on."])
        place(wnMode, 0, 12)
    end

    if ns:GetSubsystem("NameplateQuestIcons") then
        local function npLayoutSetting(key)
            return
                function()
                    local DB = ns:GetSubsystem("DB")
                    return DB and DB.db.profile.general[key]
                end,
                function(value)
                    local DB = ns:GetSubsystem("DB")
                    if DB then DB.db.profile.general[key] = value end
                    local QI = ns:GetSubsystem("NameplateQuestIcons")
                    if QI and QI.ApplyLayout then QI:ApplyLayout() end
                end
        end

        local npHeader = Options:CreateSectionHeader(content, L["Nameplate Quest Icons"])
        place(npHeader, 0, 16)

        local function npGet()
            local QI = ns:GetSubsystem("NameplateQuestIcons")
            return QI and QI.IsEnabled and QI:IsEnabled()
        end
        local function npSet(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.general.questNameplateIcons = value and true or false end
            local QI = ns:GetSubsystem("NameplateQuestIcons")
            if QI and QI.ApplyEnabled then QI:ApplyEnabled() end
        end
        local nameplates = Options:CreateCheckbox(content,
            L["Quest icons on nameplates"],
            npGet, npSet,
            L["Shows the \"!\" + count on objective mobs."])
        place(nameplates, 0, 10)

        local NP_PLACEMENT = {
            { value = "LEFT",   label = L["Left"] },
            { value = "RIGHT",  label = L["Right"] },
            { value = "TOP",    label = L["Above"] },
            { value = "BOTTOM", label = L["Below"] },
        }
        local placeGet, placeSet = npLayoutSetting("npIconPlacement")
        local npPlace = Options:CreateRadioGroup(content, L["Position"], NP_PLACEMENT, placeGet, placeSet, 260, nil,
            L["Position"],
            L["Where the quest icon + count sits relative to the enemy nameplate. Move it closer to the health bar to taste."])
        place(npPlace, 0, 8)

        local szGet, szSet = npLayoutSetting("npIconSize")
        local npSize = Options:CreateSlider(content, L["Icon size"], 12, 48, 0.5, szGet, szSet)
        place(npSize, 0, 12)
        npSize:SetWidth(280)

        local txtGet, txtSet = npLayoutSetting("npIconTextSize")
        local npText = Options:CreateSlider(content, L["Count text size"], 8, 24, 0.5, txtGet, txtSet)
        place(npText, 0, 16)
        npText:SetWidth(280)

        local offXGet, offXSet = npLayoutSetting("npIconOffsetX")
        local npOffX = Options:CreateSlider(content, L["X offset"], -50, 50, 1, offXGet, offXSet)
        place(npOffX, 0, 16)
        npOffX:SetWidth(280)
        Options:AttachTooltip(npOffX, L["X offset"],
            L["Nudges the icon and count together left or right from the Position above, so you can slide them right up against the health bar."])

        local offYGet, offYSet = npLayoutSetting("npIconOffsetY")
        local npOffY = Options:CreateSlider(content, L["Y offset"], -50, 50, 1, offYGet, offYSet)
        place(npOffY, 0, 16)
        npOffY:SetWidth(280)
        Options:AttachTooltip(npOffY, L["Y offset"],
            L["Nudges the icon and count together up or down from the Position above (positive moves them up)."])
    end

    local reset = Options:CreateYellowButton(content, L["Reset all settings"], function()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title   = "Everything Quests",
            text    = L["Reset every Everything Quests setting to defaults?"],
            button1 = L["Reset"],
            button2 = L["Cancel"],
            onAccept = function()
                local DB = ns:GetSubsystem("DB")
                if DB and DB.db then
                    if DB.db.ResetProfile then DB.db:ResetProfile() end
                    -- ResetProfile clears only the profile scope, so restore the global and per-character settings too
                    local g = DB.db.global
                    if g then
                        g.optionsWindowScale = DB.defaults.global.optionsWindowScale
                        g.whatsNewMode       = DB.defaults.global.whatsNewMode
                    end
                    if DB.char and DB.char.minimap then
                        DB.char.minimap.hide = DB.defaults.char.minimap.hide
                    end
                end
                ReloadUI()
            end,
        })
    end)
    reset:SetSize(160, 24)
    place(reset, 0, 16)

    local profilesHeader = Options:CreateSectionHeader(content, L["Profiles"])
    profilesHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 460, 0)

    local function profileList()
        local DB = ns:GetSubsystem("DB")
        local out = {}
        if not (DB and DB.db and DB.db.GetProfiles) then return out end
        -- AceDB builds this list with pairs(), so the order is arbitrary and reshuffles
        -- between sessions unless we sort it. The table is freshly built per call
        local names = DB.db:GetProfiles()
        table.sort(names)
        for _, name in ipairs(names) do
            out[#out + 1] = { value = name, label = name }
        end
        return out
    end
    local function currentProfile()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db and DB.db:GetCurrentProfile() or "Default"
    end
    local function setProfile(name)
        local DB = ns:GetSubsystem("DB")
        if DB and DB.db and DB.db.SetProfile then
            DB.db:SetProfile(name)
            ReloadUI()
        end
    end

    local function createProfileCopiedFromCurrent(name)
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.db) then return end
        local source = DB.db:GetCurrentProfile()
        DB.db:SetProfile(name)
        if source and source ~= name and DB.db.CopyProfile then
            DB.db:CopyProfile(source, true)
        end
        ReloadUI()
    end

    local function profileExists(name)
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.db and DB.db.GetProfiles) then return false end
        for _, p in ipairs(DB.db:GetProfiles()) do
            if p == name then return true end
        end
        return false
    end
    local profDD = Options:CreateDropdown(content, L["Active profile"],
        profileList, currentProfile, setProfile)
    profDD:SetPoint("TOPLEFT", profilesHeader, "BOTTOMLEFT", 0, -16)
    profDD:SetWidth(280)

    local function promptNewProfile()
        local Dialog = ns:GetSubsystem("Dialog")
        if not Dialog then return end
        Dialog:Show({
            title      = L["New Profile"],
            text       = L["Profile name:"],
            hasEditBox = true,
            maxLetters = 32,
            button1    = L["Create"],
            button2    = L["Cancel"],
            onAccept = function(text)
                local name = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                if name == "" then return end
                if name ~= currentProfile() and profileExists(name) then
                    Dialog:Show({
                        title    = L["Overwrite profile?"],
                        text     = (L["A profile named \"%s\" already exists. Overwrite it with a copy of your current settings?"]):format(name),
                        button1  = L["Overwrite"],
                        button2  = L["Cancel"],
                        onAccept = function() createProfileCopiedFromCurrent(name) end,
                    })
                else
                    createProfileCopiedFromCurrent(name)
                end
            end,
        })
    end
    local newProfileBtn = Options:CreateYellowButton(content, L["New Profile"], promptNewProfile)
    newProfileBtn:SetSize(120, 22)
    newProfileBtn:SetPoint("LEFT", profDD.button, "RIGHT", 6, 0)

    Options:AttachTooltip(profilesHeader, L["Profiles"],
        L["Switching profiles reloads the UI. Profiles are shared across characters; use them to keep different setups (e.g. raid vs solo). |cffEBB706New Profile|r prompts for a name and creates it on the spot."])

    local slashHeader = Options:CreateSectionHeader(content, L["Slash commands"])
    slashHeader:SetPoint("TOPLEFT", profDD, "BOTTOMLEFT", 0, -20)

    local slashText = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    slashText:SetPoint("TOPLEFT", slashHeader, "BOTTOMLEFT", 0, -8)
    slashText:SetJustifyH("LEFT")
    slashText:SetTextColor(0.92, 0.72, 0.02)
    slashText:SetText(L["/eqs\n/everythingquests\n\n|cff999999Both open this options window.|r\n\n/eqs whatsnew\n\n|cff999999Show what's new in the latest update.|r\n\n/eqs session\n\n|cff999999Show a recap of your current play session.|r"])

    if ns:GetSubsystem("Minimap") then
        local function mmGet()
            local DB = ns:GetSubsystem("DB")
            return DB and not DB.char.minimap.hide
        end
        local function mmSet(value)
            local DB = ns:GetSubsystem("DB")
            if not DB then return end
            DB.char.minimap.hide = not value
            local LDBI = LibStub and LibStub("LibDBIcon-1.0", true)
            if LDBI then
                if value then LDBI:Show("EverythingQuests") else LDBI:Hide("EverythingQuests") end
            end
        end
        local mm = Options:CreateCheckbox(content, L["Show minimap button"], mmGet, mmSet)
        mm:SetPoint("TOPLEFT", slashText, "BOTTOMLEFT", 0, -30)
    end
end)
