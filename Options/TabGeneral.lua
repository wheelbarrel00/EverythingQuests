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
                local V = ns:GetSubsystem("TrackerVisibility")
                if V and V.Apply then V:Apply() end
            end
    end

    local h = Options:CreateSectionHeader(content, L["General"])
    h:SetPoint("TOPLEFT", 8, -8)

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
        local P = ns:GetSubsystem("MapPOIProvider")
        if P and P.provider and P.provider.RefreshAllData then
            P.provider:RefreshAllData()
        end
    end
    local qpins = Options:CreateCheckbox(content,
        L["Show quest pins on the world map"],
        questPinsGet, questPinsSet,
        L["These are the round red markers Everything Quests puts on the big world map for quests you've already picked up (the ones in your quest log). A red \"!\" means \"go here for this quest's next step.\" A red \"?\" means \"this quest is done \226\128\148 go here to turn it in.\" Quests you haven't accepted yet keep the game's own yellow \"!\" markers; EQ does not change those. Uncheck this box and all of EQ's red markers go away."])
    qpins:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -16)

    local function lockGet()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.general.lockTracker
    end
    local function lockSet(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.general.lockTracker = value and true or false end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.ApplyLockState then Tracker:ApplyLockState() end
    end
    local lock = Options:CreateCheckbox(content,
        L["Lock tracker"],
        lockGet, lockSet,
        L["Disable drag-to-move and resize."])
    lock:SetPoint("TOPLEFT", qpins, "BOTTOMLEFT", 0, -2)

    local combatGet, combatSet = generalSetting("hideInCombat")
    local combat = Options:CreateCheckbox(content,
        L["Hide tracker in combat"],
        combatGet, combatSet)
    combat:SetPoint("TOPLEFT", lock, "BOTTOMLEFT", 0, -2)

    local instGet, instSet = generalSetting("hideInInstances")
    local inst = Options:CreateCheckbox(content,
        L["Hide tracker in instances"],
        instGet, instSet,
        L["Raids, dungeons, delves."])
    inst:SetPoint("TOPLEFT", combat, "BOTTOMLEFT", 0, -2)

    local mapGet, mapSet = generalSetting("hideOnMapOpen")
    local mapHide = Options:CreateCheckbox(content,
        L["Hide tracker when world map is open"],
        mapGet, mapSet)
    mapHide:SetPoint("TOPLEFT", inst, "BOTTOMLEFT", 0, -2)

    local mplusGet, mplusSet = generalSetting("hideInMythicPlus")
    local mplus = Options:CreateCheckbox(content,
        L["Hide tracker in Mythic+"],
        mplusGet, mplusSet,
        L["Hides the tracker during an active Mythic+ run, then brings it back when the run ends."])
    mplus:SetPoint("TOPLEFT", mapHide, "BOTTOMLEFT", 0, -2)

    local autoGet, autoSet = generalSetting("autoTrackAccepted")
    local auto = Options:CreateCheckbox(content,
        L["Auto-track accepted quests"],
        autoGet, autoSet,
        L["Matches Blizzard's default."])
    auto:SetPoint("TOPLEFT", mplus, "BOTTOMLEFT", 0, -2)

    local autoAccGet, autoAccSet = generalSetting("autoAcceptQuests")
    local autoAcc = Options:CreateCheckbox(content,
        L["Auto-accept quests"],
        autoAccGet, autoAccSet,
        L["Hold Alt to pause."])
    autoAcc:SetPoint("TOPLEFT", auto, "BOTTOMLEFT", 0, -2)

    local autoTIGet, autoTISet = generalSetting("autoTurnInQuests")
    local autoTI = Options:CreateCheckbox(content,
        L["Auto-turn-in quests"],
        autoTIGet, autoTISet,
        L["Skips reward-choice screens."])
    autoTI:SetPoint("TOPLEFT", autoAcc, "BOTTOMLEFT", 0, -2)

    local restoreGet, restoreSet = generalSetting("restoreSuperTrackOnLogin")
    local restore = Options:CreateCheckbox(content,
        L["Keep focused quest after relog"],
        restoreGet, restoreSet,
        L["Restores the waypoint arrow."])
    restore:SetPoint("TOPLEFT", autoTI, "BOTTOMLEFT", 0, -2)

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
    owScale:SetPoint("TOPLEFT", restore, "BOTTOMLEFT", 0, -18)
    owScale:SetWidth(280)
    Options:AttachTooltip(owScale, L["Options Window Scale"],
        L["Resizes this Everything Quests options window only. It does not change the quest tracker or anything shown in the game world. The new size applies when you let go of the slider."])
    -- The slider sits inside the window it scales, so applying mid-drag fights the drag and snaps to the ends
    if owScale.slider then
        owScale.slider:HookScript("OnMouseUp", function() Options:ApplyWindowScale() end)
    end

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
    wnMode:SetPoint("TOPLEFT", owScale, "BOTTOMLEFT", 0, -12)

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
    npHeader:SetPoint("TOPLEFT", wnMode, "BOTTOMLEFT", 0, -16)

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
    nameplates:SetPoint("TOPLEFT", npHeader, "BOTTOMLEFT", 0, -10)

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
    npPlace:SetPoint("TOPLEFT", nameplates, "BOTTOMLEFT", 0, -8)

    local szGet, szSet = npLayoutSetting("npIconSize")
    local npSize = Options:CreateSlider(content, L["Icon size"], 12, 48, 0.5, szGet, szSet)
    npSize:SetPoint("TOPLEFT", npPlace, "BOTTOMLEFT", 0, -12)
    npSize:SetWidth(280)

    local txtGet, txtSet = npLayoutSetting("npIconTextSize")
    local npText = Options:CreateSlider(content, L["Count text size"], 8, 24, 0.5, txtGet, txtSet)
    npText:SetPoint("TOPLEFT", npSize, "BOTTOMLEFT", 0, -16)
    npText:SetWidth(280)

    local offXGet, offXSet = npLayoutSetting("npIconOffsetX")
    local npOffX = Options:CreateSlider(content, L["X offset"], -50, 50, 1, offXGet, offXSet)
    npOffX:SetPoint("TOPLEFT", npText, "BOTTOMLEFT", 0, -16)
    npOffX:SetWidth(280)
    Options:AttachTooltip(npOffX, L["X offset"],
        L["Nudges the icon and count together left or right from the Position above, so you can slide them right up against the health bar."])

    local offYGet, offYSet = npLayoutSetting("npIconOffsetY")
    local npOffY = Options:CreateSlider(content, L["Y offset"], -50, 50, 1, offYGet, offYSet)
    npOffY:SetPoint("TOPLEFT", npOffX, "BOTTOMLEFT", 0, -16)
    npOffY:SetWidth(280)
    Options:AttachTooltip(npOffY, L["Y offset"],
        L["Nudges the icon and count together up or down from the Position above (positive moves them up)."])

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
    reset:SetPoint("TOPLEFT", npOffY, "BOTTOMLEFT", 0, -16)

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
end)
