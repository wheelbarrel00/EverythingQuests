local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

local function trackerSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.tracker[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.tracker[key] = value end
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker then Tracker:Refresh() end
        end
end

local function filterSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.tracker.filters[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.tracker.filters[key] = value end
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker then Tracker:Refresh() end
        end
end

local SORT_OPTIONS = {
    { value = "zone",     label = L["Zone"]     },
    { value = "status",   label = L["Status"]   },
    { value = "type",     label = L["Type"]     },
    { value = "level",    label = L["Level"]    },
    { value = "distance", label = L["Distance"] },
    { value = "recent",   label = L["Recent"]   },
    { value = "manual",   label = L["Manual"]   },
}

local FILTER_ROWS = {
    { key = "showNormal",      label = L["Normal quests"]   },
    { key = "showDaily",       label = L["Daily quests"]    },
    { key = "showWeekly",      label = L["Weekly quests"]   },
    { key = "showCampaign",    label = L["Campaign quests"] },
    { key = "showWorld",       label = L["World quests"]    },
    { key = "onlyCurrentZone", label = L["Show only quests in current zone"] },
}

Options:AddTab("tracker", L["Tracker"], function(content)
    local header = Options:CreateSectionHeader(content, L["On-Screen Tracker"])
    header:SetPoint("TOPLEFT", 8, -8)

    local watchedGet, watchedSet = trackerSetting("showOnlyWatched")
    local watched = Options:CreateCheckbox(
        content,
        L["Show only watched quests"],
        watchedGet, watchedSet,
        L["Matches Blizzard's default tracker."])
    watched:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -16)

    local simplifyGet, simplifySet = trackerSetting("simplifyMode")
    local simplify = Options:CreateCheckbox(
        content,
        L["Simplify Mode"],
        simplifyGet, simplifySet,
        L["Show only the first incomplete objective per quest."])
    simplify:SetPoint("TOPLEFT", watched, "BOTTOMLEFT", 0, -2)

    local achSimpGet, achSimpSet = trackerSetting("simplifyAchievements")
    local achSimplify = Options:CreateCheckbox(
        content,
        L["Simplify tracked achievements"],
        achSimpGet, achSimpSet,
        L["Show only incomplete criteria for tracked achievements."])
    achSimplify:SetPoint("TOPLEFT", simplify, "BOTTOMLEFT", 0, -2)

    local sortGet, sortSet = trackerSetting("sortMode")
    local manualHint, filtersHeader, sort
    local function syncManualHint(value)
        local manual = (value == "manual")
        if manualHint then
            if manual then manualHint:Show() else manualHint:Hide() end
        end
        if filtersHeader and sort then
            filtersHeader:ClearAllPoints()
            if manual and manualHint then
                filtersHeader:SetPoint("TOPLEFT", manualHint, "BOTTOMLEFT", 0, -10)
            else
                filtersHeader:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -14)
            end
        end
    end
    sort = Options:CreateRadioGroup(
        content, L["Sort Order"],
        SORT_OPTIONS, sortGet,
        function(v) sortSet(v); syncManualHint(v) end,
        440, 14)
    sort:SetPoint("TOPLEFT", achSimplify, "BOTTOMLEFT", 0, -12)

    manualHint = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    manualHint:SetPoint("TOPLEFT", sort, "BOTTOMLEFT", 0, -2)
    manualHint:SetWidth(440)
    manualHint:SetJustifyH("LEFT")
    manualHint:SetTextColor(0.92, 0.72, 0.02)
    manualHint:SetText(L["|cffaaaaaaDrag and drop the quests in the tracker to reorder them however you like.|r"])

    filtersHeader = Options:CreateSectionHeader(content, L["Filters"])
    syncManualHint(sortGet())

    local prev = filtersHeader
    local filterCheckboxes = {}
    for i, row in ipairs(FILTER_ROWS) do
        local get, set = filterSetting(row.key)
        local cb = Options:CreateCheckbox(content, row.label, get, set)
        cb:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", i == 1 and 0 or 0, i == 1 and -8 or -2)
        filterCheckboxes[#filterCheckboxes + 1] = { row = row, cb = cb }
        prev = cb
    end

    local resetFilters = Options:CreateYellowButton(content, L["Reset filters to defaults"], function()
        local DB = ns:GetSubsystem("DB")
        if not DB then return end
        local f = DB.db.profile.tracker.filters
        f.showNormal      = true
        f.showDaily       = true
        f.showWeekly      = true
        f.showCampaign    = true
        f.showWorld       = true
        f.onlyCurrentZone = false
        DB.db.profile.tracker.showOnlyWatched = true
        watched:SetChecked(true)
        for _, entry in ipairs(filterCheckboxes) do
            entry.cb:SetChecked(f[entry.row.key] and true or false)
        end
        local V = ns:GetSubsystem("TrackerVisibility")
        if V and V.Apply then V:Apply() end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end)
    resetFilters:SetSize(180, 24)
    resetFilters:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -10)

    local optionsHeader = Options:CreateSectionHeader(content, L["Options"])
    optionsHeader:SetPoint("TOPLEFT", header, "TOPLEFT", 460, 0)

    local diffGet, diffSet = trackerSetting("colorByDifficulty")
    local diff = Options:CreateCheckbox(
        content,
        L["Quest Title Color By Difficulty"],
        diffGet, diffSet)
    diff:SetPoint("TOPLEFT", optionsHeader, "BOTTOMLEFT", 0, -10)

    local lvlGet, lvlSet = trackerSetting("showLevelInTracker")
    local lvl = Options:CreateCheckbox(content,
        L["Show quest level prefix"],
        lvlGet, lvlSet,
        L["For example, [60] Title."])
    lvl:SetPoint("TOPLEFT", diff, "BOTTOMLEFT", 0, -2)

    local zoneGet, zoneSet = trackerSetting("showZoneTag")
    local zoneCheck = Options:CreateCheckbox(content,
        L["Show zone label under quest titles"], zoneGet, zoneSet)
    zoneCheck:SetPoint("TOPLEFT", lvl, "BOTTOMLEFT", 0, -2)

    local objGet, objSet = trackerSetting("showObjectiveNumbers")
    local objCheck = Options:CreateCheckbox(content,
        L["Show objective progress numbers"],
        objGet, objSet,
        L["For example, 0/4, 1/1, etc."])
    objCheck:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -2)

    local qidGet, qidSet = trackerSetting("showQuestID")
    local qidCheck = Options:CreateCheckbox(content,
        L["Show quest ID"],
        qidGet, qidSet,
        L["Useful for bug reports."])
    qidCheck:SetPoint("TOPLEFT", objCheck, "BOTTOMLEFT", 0, -2)

    local qtotalGet, qtotalSet = trackerSetting("showQuestTotal")
    local qtotalCheck = Options:CreateCheckbox(content,
        L["Show tracked / total on the Quests & Campaign headers"],
        qtotalGet, qtotalSet,
        L["For example, 3/9."])
    qtotalCheck:SetPoint("TOPLEFT", qidCheck, "BOTTOMLEFT", 0, -2)

    local itemBtnGet, itemBtnSet = trackerSetting("showItemButtons")
    local itemBtnCheck = Options:CreateCheckbox(content,
        L["Show usable quest item buttons"],
        itemBtnGet, itemBtnSet,
        L["Click to use the quest's item."])
    itemBtnCheck:SetPoint("TOPLEFT", qtotalCheck, "BOTTOMLEFT", 0, -2)

    local function headerIconGet(key)
        return function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.tracker[key] ~= false
        end
    end
    local function headerIconSet(key)
        return function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.tracker[key] = value end
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker and Tracker.ApplyHeaderIcons then Tracker:ApplyHeaderIcons() end
        end
    end
    local optIconCheck = Options:CreateCheckbox(content,
        L["Show Options icon on the tracker"],
        headerIconGet("showOptionsIcon"), headerIconSet("showOptionsIcon"),
        L["A small cogwheel at the top-right of the tracker that opens the options panel."])
    optIconCheck:SetPoint("TOPLEFT", itemBtnCheck, "BOTTOMLEFT", 0, -2)

    local cgIconCheck = Options:CreateCheckbox(content,
        L["Show Chain Guide icon on the tracker"],
        headerIconGet("showChainGuideIcon"), headerIconSet("showChainGuideIcon"),
        L["A small book at the top-right of the tracker that opens the Chain Guide."])
    cgIconCheck:SetPoint("TOPLEFT", optIconCheck, "BOTTOMLEFT", 0, -2)

    local hideBarGet, hideBarSet = trackerSetting("hideScrollBar")
    local hideBarCheck = Options:CreateCheckbox(content,
        L["Hide scroll bar"],
        hideBarGet, hideBarSet,
        L["Scroll with the mouse wheel instead."])
    hideBarCheck:SetPoint("TOPLEFT", cgIconCheck, "BOTTOMLEFT", 0, -2)

    local popupGet, popupSet = trackerSetting("showQuestPopups")
    local popupCheck = Options:CreateCheckbox(content,
        L["Show Quest Discovered popups"],
        popupGet, popupSet,
        L["Boxes for newly discovered / completed quests."])
    popupCheck:SetPoint("TOPLEFT", hideBarCheck, "BOTTOMLEFT", 0, -2)

    local newTagGet, newTagSet = trackerSetting("showRecentlyAddedTag")
    local newTagCheck = Options:CreateCheckbox(content,
        L["Show NEW tag on recently accepted quests"],
        newTagGet, newTagSet,
        L["For about an hour after accepting."])
    newTagCheck:SetPoint("TOPLEFT", popupCheck, "BOTTOMLEFT", 0, -2)

    local splitGet, splitSet = trackerSetting("splitQuestClick")
    local splitCheck = Options:CreateCheckbox(content,
        L["Split quest click"],
        splitGet, splitSet,
        L["Click the icon to focus, click the title to open the quest log."])
    splitCheck:SetPoint("TOPLEFT", newTagCheck, "BOTTOMLEFT", 0, -2)

    local Media = ns:GetSubsystem("Media")
    local soundGet, soundSet = trackerSetting("questSoundEnabled")
    local soundCheck = Options:CreateCheckbox(
        content,
        L["Quest Sound"],
        soundGet, soundSet,
        L["Plays when a quest is ready to turn in."])
    soundCheck:SetPoint("TOPLEFT", splitCheck, "BOTTOMLEFT", 0, -8)

    local soundList = (Media and Media.GetSoundList and Media:GetSoundList()) or {}
    local sndChoiceGet, sndChoiceSet = trackerSetting("questCompleteSound")
    local function playSound(value)
        local f = Media and Media.GetSoundFile and Media:GetSoundFile(value)
        if f and PlaySoundFile then
            PlaySoundFile(f, "Master")
        end
    end
    local soundDD = Options:CreateDropdown(content, L["Quest Complete Sound"], soundList, sndChoiceGet, function(value)
        sndChoiceSet(value)
        playSound(value)
    end, playSound)
    soundDD:SetPoint("TOPLEFT", soundCheck, "BOTTOMLEFT", 0, -8)
    soundDD:SetWidth(280)

    local visHeader = Options:CreateSectionHeader(content, L["Tracker Visibility"])
    visHeader:SetPoint("TOPLEFT", resetFilters, "BOTTOMLEFT", 0, -10)

    local profGet, profSet = trackerSetting("showProfessionSection")
    local profCheck = Options:CreateCheckbox(content, L["Profession section"], profGet, profSet)
    profCheck:SetPoint("TOPLEFT", visHeader, "BOTTOMLEFT", 0, -8)

    local achGet, achSet = trackerSetting("showAchievementsSection")
    local achCheck = Options:CreateCheckbox(content, L["Achievements section"], achGet, achSet,
        L["Achievements you're tracking."])
    achCheck:SetPoint("TOPLEFT", profCheck, "BOTTOMLEFT", 0, -2)

    local wqGet, wqSet = trackerSetting("showWorldQuestsSection")
    local wqCheck = Options:CreateCheckbox(content, L["World Quests section"], wqGet, wqSet)
    wqCheck:SetPoint("TOPLEFT", achCheck, "BOTTOMLEFT", 0, -2)

    local autoWQGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.autoListZoneWorldQuests
    end
    local autoWQSet = function(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.autoListZoneWorldQuests = value end
        local Events = ns:GetSubsystem("TrackerEvents")
        if Events and Events.MarkActiveDirty then Events:MarkActiveDirty() end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local autoWQCheck = Options:CreateCheckbox(content,
        L["Auto-list current-zone world quests"],
        autoWQGet, autoWQSet,
        L["Lists every WQ in your zone without tracking each."])
    autoWQCheck:SetPoint("TOPLEFT", wqCheck, "BOTTOMLEFT", 0, -2)

    local wqHeightSlider
    local function setWqHeightEnabled(on)
        if not wqHeightSlider then return end
        wqHeightSlider:SetAlpha(on and 1 or 0.4)
        if wqHeightSlider.slider then wqHeightSlider.slider:EnableMouse(on and true or false) end
    end
    local wqhGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.worldQuestsHeightOverride
    end
    local wqhSet = function(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.worldQuestsHeightOverride = value end
        setWqHeightEnabled(value)
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    local wqhCheck = Options:CreateCheckbox(content,
        L["Set a custom World Quests height"],
        wqhGet, wqhSet,
        L["By default the World Quests area shares space with your quest list and gets squeezed when you have a lot of quests. Turn this on to give it its own height, set by the slider below."])
    wqhCheck:SetPoint("TOPLEFT", autoWQCheck, "BOTTOMLEFT", 0, -2)

    local wqHeightGet = function()
        local DB = ns:GetSubsystem("DB")
        return (DB and DB.db.profile.tracker.worldQuestsHeight) or 120
    end
    local wqHeightSet = function(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.worldQuestsHeight = value end
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker then Tracker:Refresh() end
    end
    wqHeightSlider = Options:CreateSlider(content, L["World Quests height"], 40, 400, 10,
        wqHeightGet, wqHeightSet)
    wqHeightSlider:SetPoint("TOPLEFT", wqhCheck, "BOTTOMLEFT", 0, -8)
    wqHeightSlider:SetWidth(280)
    setWqHeightEnabled(wqhGet())

    local orderHeader = Options:CreateSectionHeader(content, L["Section Order"])
    orderHeader:SetPoint("TOPLEFT", wqHeightSlider, "BOTTOMLEFT", 0, -18)
    Options:AttachTooltip(orderHeader, L["Section Order"],
        L["Rearrange the tracker's sections with the arrows below. A section only appears on the tracker while it has something in it, so reordering an empty section won't look like anything changed. World Quests scroll in their own panel and can only sit at the very top or bottom \226\128\148 use the Top/Bottom control."])

    local WQ_POS_OPTIONS = {
        { value = "top",    label = L["Top"]    },
        { value = "bottom", label = L["Bottom"] },
    }
    local wqPosGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and (DB.db.profile.tracker.worldQuestsPosition or "bottom")
    end
    local wqPosSet = function(value)
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.SetWorldQuestsPosition then Tracker:SetWorldQuestsPosition(value) end
    end
    local wqPos = Options:CreateRadioGroup(content, L["World Quests position"],
        WQ_POS_OPTIONS, wqPosGet, wqPosSet, 300, 14,
        L["World Quests position"],
        L["Where the World Quests panel sits on the tracker. |cffffffffTop|r puts it above your quests; |cffffffffBottom|r keeps it below your quests (the default). World Quests scroll in their own capped panel, which is why they can't be mixed in between the other sections."])
    wqPos:SetPoint("TOPLEFT", orderHeader, "BOTTOMLEFT", 0, -8)

    local SECTION_ROW_LABELS = {
        zoneprogress = L["Zone Progress"],
        campaign     = L["Campaign"],
        quests       = L["Quests"],
        profession   = L["Profession"],
        endeavors    = L["Endeavors"],
        achievements = L["Achievements"],
    }
    local ORDER_ROW_H = 24
    local orderList = CreateFrame("Frame", nil, content)
    orderList:SetPoint("TOPLEFT", wqPos, "BOTTOMLEFT", 0, -8)
    orderList:SetSize(300, ORDER_ROW_H)

    local function makeOrderArrow(parent, dir)
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(18, 18)
        b:SetNormalTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Up")
        b:SetPushedTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Down")
        b:SetDisabledTexture("Interface\\Buttons\\Arrow-" .. dir .. "-Disabled")
        local isUp = (dir == "Up")
        b:HookScript("OnEnter", function(self2)
            local r = self2:GetParent()
            local name = (r and SECTION_ROW_LABELS[r.sectionID]) or ""
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            -- SetText arg 5 is alpha, not wrap - pass 1 or the line can render invisible
            GameTooltip:SetText((isUp and L["Move %s up"] or L["Move %s down"]):format(name), 1, 1, 1, 1, true)
            GameTooltip:AddLine(L["Reorders where this section sits in the tracker. A section only shows while it has something in it, so empty sections won't visibly move."], 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local orderRows = {}
    local function renderOrderRows()
        local Tracker = ns:GetSubsystem("Tracker")
        local order = (Tracker and Tracker.GetInContentOrder and Tracker:GetInContentOrder())
                      or { "zoneprogress", "campaign", "quests", "profession", "endeavors", "achievements" }
        for _, r in ipairs(orderRows) do r:Hide() end
        for i, id in ipairs(order) do
            local row = orderRows[i]
            if not row then
                row = CreateFrame("Frame", nil, orderList)
                row:SetHeight(ORDER_ROW_H)
                row.up = makeOrderArrow(row, "Up")
                row.up:SetPoint("LEFT", 0, 0)
                row.down = makeOrderArrow(row, "Down")
                row.down:SetPoint("LEFT", row.up, "RIGHT", 3, 0)
                row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.label:SetPoint("LEFT", row.down, "RIGHT", 8, 0)
                row.label:SetTextColor(1, 1, 1)
                orderRows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  orderList, "TOPLEFT",  0, -(i - 1) * ORDER_ROW_H)
            row:SetPoint("TOPRIGHT", orderList, "TOPRIGHT", 0, -(i - 1) * ORDER_ROW_H)
            row.sectionID = id
            row.label:SetText(SECTION_ROW_LABELS[id] or id)
            row.up:SetEnabled(i > 1)
            row.down:SetEnabled(i < #order)
            row.up:SetScript("OnClick", function()
                local T = ns:GetSubsystem("Tracker")
                if T and T.MoveSection then T:MoveSection(id, -1) end
                renderOrderRows()
            end)
            row.down:SetScript("OnClick", function()
                local T = ns:GetSubsystem("Tracker")
                if T and T.MoveSection then T:MoveSection(id, 1) end
                renderOrderRows()
            end)
            row:Show()
        end
        orderList:SetHeight(math.max(1, #order * ORDER_ROW_H))
    end
    renderOrderRows()

    local zpHeader = Options:CreateSectionHeader(content, L["Zone Progress Bar"])
    zpHeader:SetPoint("TOPLEFT", soundDD, "BOTTOMLEFT", 0, -16)

    local zpEnableGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db.profile.tracker.showZoneProgressBar
    end
    local zpEnableSet = function(value)
        local DB = ns:GetSubsystem("DB")
        if DB then DB.db.profile.tracker.showZoneProgressBar = value end
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.SetEnabled then
            ZP:SetEnabled(value)
        else
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker then Tracker:Refresh() end
        end
    end
    local zpEnable = Options:CreateCheckbox(content,
        L["Show zone progress bar"],
        zpEnableGet, zpEnableSet,
        L["Approximate questline progress."])
    zpEnable:SetPoint("TOPLEFT", zpHeader, "BOTTOMLEFT", 0, -8)

    local zpFloatGet = function()
        local DB = ns:GetSubsystem("DB")
        return DB and (DB.db.profile.tracker.zoneProgressLocation or "floating") == "floating"
    end
    local zpFloatSet = function(value)
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if ZP and ZP.SetLocation then ZP:SetLocation(value and "floating" or "tracker") end
    end
    local zpFloat = Options:CreateCheckbox(content,
        L["Float as a movable bar"],
        zpFloatGet, zpFloatSet,
        L["Drag to move; right-click to lock or reset."])
    zpFloat:SetPoint("TOPLEFT", zpEnable, "BOTTOMLEFT", 0, -2)

    local sbHeader = Options:CreateSectionHeader(content, L["Scenario Bonus Objectives"])
    sbHeader:SetPoint("TOPLEFT", zpFloat, "BOTTOMLEFT", 0, -16)

    local sbEnableGet = function()
        local DB = ns:GetSubsystem("DB")
        local st = DB and DB.db.profile.tracker.scenarioBonusHUD
        return st and st.enabled
    end
    local sbEnableSet = function(value)
        local Hud = ns:GetSubsystem("TrackerScenarioBonusHUD")
        if Hud and Hud.SetEnabled then Hud:SetEnabled(value) end
    end
    local sbEnable = Options:CreateCheckbox(content,
        L["Show bonus objectives HUD"],
        sbEnableGet, sbEnableSet,
        L["Shows a small movable checklist of the extra bonus objectives that appear during some scenarios and delves, so you do not miss their rewards. Drag to move, right-click to lock or reset. Off by default."])
    sbEnable:SetPoint("TOPLEFT", sbHeader, "BOTTOMLEFT", 0, -8)

    local sbScaleGet = function()
        local DB = ns:GetSubsystem("DB")
        local st = DB and DB.db.profile.tracker.scenarioBonusHUD
        return (st and st.scale) or 1.0
    end
    local sbScaleSet = function(value)
        local Hud = ns:GetSubsystem("TrackerScenarioBonusHUD")
        if Hud and Hud.SetScale then Hud:SetScale(value) end
    end
    local sbScale = Options:CreateSlider(content, L["HUD Scale"], 0.5, 2.0, 0.05, sbScaleGet, sbScaleSet)
    sbScale:SetPoint("TOPLEFT", sbEnable, "BOTTOMLEFT", 0, -16)
    sbScale:SetWidth(280)
    Options:AttachTooltip(sbScale, L["HUD Scale"], L["Sizes the bonus objectives HUD."])

    Options:AttachTooltip(header, L["On-Screen Tracker"],
        L["Changes apply immediately to the on-screen tracker."])
end)
