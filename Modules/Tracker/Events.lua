local _, ns = ...
local L = ns.L

local V = ns:RegisterSubsystem("TrackerEvents", {})

local HEADER_H     = 30
local LINE_H       = 14
local ROW_GAP      = 2
local ICON_SIZE    = 26
local ICON_PAD     = 4
local LABEL_PAD    = 6
local LINE_INDENT  = ICON_PAD + ICON_SIZE + LABEL_PAD
local TICKER_INTERVAL = 30
local WQ_RING_SIZE = 33
local WQ_STAR_SIZE = 18


V.headerPool   = {}
V.linePool     = {}
V.activeHeaders = {}
V.activeLines   = {}

-- RequestLoadQuestByID on some builds fires QUEST_DATA_LOAD_RESULT even for
-- already-loaded quests, creating a refresh→request→event loop; load once per session.
V._requestedLoad = {}

local function buildHeader(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(HEADER_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    r.iconHolder = CreateFrame("Frame", nil, r)
    r.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)
    r.iconHolder:SetPoint("LEFT", ICON_PAD, 0)

    r.ring = r.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    r.ring:SetSize(WQ_RING_SIZE, WQ_RING_SIZE)
    r.ring:SetPoint("CENTER")

    r.icon = r.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    r.icon:SetSize(WQ_STAR_SIZE, WQ_STAR_SIZE)
    r.icon:SetPoint("CENTER")

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", r.iconHolder, "RIGHT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)

    r.groupFinder = CreateFrame("Button", nil, r)
    r.groupFinder:SetSize(16, 16)
    r.groupFinder:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.groupFinder.icon = r.groupFinder:CreateTexture(nil, "ARTWORK")
    r.groupFinder.icon:SetAllPoints()
    r.groupFinder.icon:SetAtlas("groupfinder-eye-single")
    r.groupFinder:Hide()
    r.groupFinder:SetScript("OnClick", function(self)
        local qid = self:GetParent().questID
        if qid and LFGListUtil_FindQuestGroup then
            LFGListUtil_FindQuestGroup(qid)
        end
    end)
    r.groupFinder:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Find Group"], 1, 1, 1)
        GameTooltip:AddLine(L["Open the Premade Group Finder for this quest."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    r.groupFinder:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r:SetScript("OnEnter", function(self)
        if not self.questID then return end
        local Tooltip = ns:GetSubsystem("WQTooltip")
        if Tooltip and Tooltip.Show then Tooltip:Show(self, self.questID) end
    end)
    r:SetScript("OnLeave", function()
        local Tooltip = ns:GetSubsystem("WQTooltip")
        if Tooltip and Tooltip.Hide then Tooltip:Hide() end
    end)
    r:SetScript("OnClick", function(self, button)
        if not self.questID then return end
        local T = ns:GetSubsystem("Tracker")
        if T and T.frame and T.frame._eqHidden then return end
        if button == "RightButton" then
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            -- Capture the quest now: a re-render can reassign this pooled row
            -- to a different quest while the menu is open.
            local qid = self.questID
            local Watch = ns:GetSubsystem("WQWatchPersist")
            local tracked = Watch and ((Watch.IsWatched and Watch:IsWatched(qid))
                            or (Watch.IsTracked and Watch:IsTracked(qid)))
            local title = ns.Util.QuestTitle(qid) or L["World Quest"]
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(title)
                if tracked then
                    root:CreateButton(L["Untrack Quest"], function()
                        if Watch and Watch.Untrack then Watch:Untrack(qid) end
                    end)
                else
                    root:CreateButton(L["Track Quest"], function()
                        if Watch and Watch.Track then Watch:Track(qid) end
                    end)
                end
                root:CreateButton(L["Super-track (follow arrow)"], function()
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(qid)
                    end
                end)
                root:CreateButton(L["Search on Wowhead"], function()
                    ns:ShowURL("https://www.wowhead.com/quest=" .. tostring(qid))
                end)
            end)
        else
            local DB  = ns:GetSubsystem("DB")
            local cfg = DB and DB.db.profile.tracker
            local overIcon = false
            if cfg and cfg.splitQuestClick then
                local ih = self.iconHolder
                if ih then
                    local mx = GetCursorPosition()
                    mx = mx / (self:GetEffectiveScale() or 1)
                    local iconRight = ih:GetRight()
                    if iconRight and mx <= iconRight then overIcon = true end
                end
            end
            if cfg and cfg.splitQuestClick and not overIcon then
                if C_AddOns and C_AddOns.LoadAddOn then
                    C_AddOns.LoadAddOn("Blizzard_QuestLog")
                end
                if QuestMapFrame_OpenToQuestDetails then
                    QuestMapFrame_OpenToQuestDetails(self.questID)
                elseif OpenWorldMap and C_TaskQuest and C_TaskQuest.GetQuestZoneID then
                    OpenWorldMap(C_TaskQuest.GetQuestZoneID(self.questID))
                end
            elseif C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
            end
        end
    end)

    return r
end

local function buildLine(parent)
    local r = CreateFrame("Frame", nil, parent)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("TOPLEFT", LINE_INDENT, 0)
    r.text:SetPoint("TOPRIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(true)
    return r
end

local function acquireHeader(parent)
    return ns.Util.AcquirePooled(V.headerPool, V.activeHeaders, parent, buildHeader)
end

local function acquireLine(parent)
    return ns.Util.AcquirePooled(V.linePool, V.activeLines, parent, buildLine)
end

local function releaseAll()
    for i = #V.activeHeaders, 1, -1 do
        local r = V.activeHeaders[i]
        r:Hide()
        r:ClearAllPoints()
        r.icon:SetTexture(nil)
        V.headerPool[#V.headerPool + 1] = r
        V.activeHeaders[i] = nil
    end
    for i = #V.activeLines, 1, -1 do
        local r = V.activeLines[i]
        r:Hide()
        r:ClearAllPoints()
        r.text:SetText("")
        V.linePool[#V.linePool + 1] = r
        V.activeLines[i] = nil
    end
end

local function getWatchedWorldQuests()
    local Watch = ns:GetSubsystem("WQWatchPersist")
    if Watch and Watch.GetTrackedQuests then
        return Watch:GetTrackedQuests()
    end
    if not (C_QuestLog and C_QuestLog.GetNumWorldQuestWatches) then return {} end
    local out = {}
    local n = C_QuestLog.GetNumWorldQuestWatches() or 0
    for i = 1, n do
        local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
        if qid then out[#out + 1] = qid end
    end
    return out
end

-- C_TaskQuest.GetQuestsForPlayerByMapID was renamed to GetQuestsOnMap; try new name first.
local function fetchTaskQuestsForMap(mapID)
    if not (C_TaskQuest and mapID) then return {} end
    if C_TaskQuest.GetQuestsOnMap then
        return C_TaskQuest.GetQuestsOnMap(mapID) or {}
    end
    if C_TaskQuest.GetQuestsForPlayerByMapID then
        return C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    end
    return {}
end

local function getInZoneActiveTaskQuests()
    if not (C_Map and C_Map.GetBestMapForUnit) then return {} end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return {} end

    -- GetLogIndexForQuestID returns non-nil for hidden task quests that the Quests
    -- section deliberately skips; use Cache:Get instead to match the same filter.
    local Cache = ns:GetSubsystem("Cache")
    local function isInQuestsSection(qid)
        return Cache and Cache.Get and Cache:Get(qid) ~= nil
    end

    local out, seenQ, seenM = {}, {}, {}
    local function walk(m)
        if not m or seenM[m] then return end
        seenM[m] = true
        local list = fetchTaskQuestsForMap(m)
        for i = 1, #list do
            local q = list[i]
            local qid = q and (q.questId or q.questID)
            if qid and q.inProgress and not seenQ[qid] and not isInQuestsSection(qid) then
                seenQ[qid] = true
                out[#out + 1] = qid
            end
        end
    end

    local m = mapID
    for _ = 1, 5 do
        if not m then break end
        walk(m)
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        m = info and info.parentMapID
    end
    return out
end

local function isWorldQuest(qid)
    if not qid then return false end
    if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(qid) then
        return true
    end
    if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(qid) then
        return true
    end
    return false
end

local function getZoneWorldQuests()
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    if not (t and t.autoListZoneWorldQuests) then return {} end
    if not (C_Map and C_Map.GetBestMapForUnit) then return {} end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return {} end
    local out = {}
    local list = fetchTaskQuestsForMap(mapID)
    for i = 1, #list do
        local q = list[i]
        local qid = q and (q.questId or q.questID)
        if isWorldQuest(qid) then
            out[#out + 1] = qid
        end
    end
    return out
end

local function getQuestLogTaskQuests()
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries
            and C_QuestLog.GetInfo) then return {} end
    local out = {}
    local n = C_QuestLog.GetNumQuestLogEntries() or 0
    for i = 1, n do
        local info = C_QuestLog.GetInfo(i)
        if info and info.questID and not info.isHeader and not info.isHidden then
            local isTaskish = info.isTask or info.isBounty
                or (QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(info.questID))
            if isTaskish then
                out[#out + 1] = info.questID
            end
        end
    end
    return out
end

local _activeCache    = {}
local _activeSeen     = {}
local _activeDirty    = true
local _activeShowWorld
-- Per-quest static render data (atlas/canGroup/title). Refetching it every render
-- churned a GetQuestTagInfo table plus 3 API calls per WQ, even on no-change passes.
-- Wiped whenever the active set is rebuilt (which covers the data-load event).
local _wqStatic       = {}
local function showWorldFilter()
    local DB = ns:GetSubsystem("DB")
    local f = DB and DB.db and DB.db.profile and DB.db.profile.tracker
              and DB.db.profile.tracker.filters
    return not f or f.showWorld ~= false
end
local function rebuildActiveWorldQuests()
    wipe(_activeCache)
    wipe(_activeSeen)
    wipe(_wqStatic)
    _activeShowWorld = showWorldFilter()
    local Cache = ns:GetSubsystem("Cache")
    -- knownWorldQuest: watched/zone sources are world quests by construction;
    -- isWorldQuest() needs tag data that stale or out-of-zone quests never load.
    local function push(qid, knownWorldQuest)
        if qid and not _activeSeen[qid]
           and not (Cache and Cache.Get and Cache:Get(qid) ~= nil)
           and (_activeShowWorld or not (knownWorldQuest or isWorldQuest(qid))) then
            _activeSeen[qid] = true
            _activeCache[#_activeCache + 1] = qid
        end
    end
    for _, qid in ipairs(getWatchedWorldQuests())     do push(qid, true) end
    for _, qid in ipairs(getInZoneActiveTaskQuests()) do push(qid) end
    for _, qid in ipairs(getQuestLogTaskQuests())     do push(qid) end
    for _, qid in ipairs(getZoneWorldQuests())        do push(qid, true) end
    _activeDirty = false
end
local function getActiveWorldQuests()
    if _activeDirty or _activeShowWorld ~= showWorldFilter() then
        rebuildActiveWorldQuests()
    end
    return _activeCache
end

function V:MarkActiveDirty()
    _activeDirty = true
end

local colorizeProgress = ns.Util.ColorizeProgress

local function questTitle(questID)
    return ns.Util.QuestTitle(questID, true)
end

local function buildStatic(qid)
    local tagInfo = C_QuestLog and C_QuestLog.GetQuestTagInfo
                    and C_QuestLog.GetQuestTagInfo(qid)
    local atlas = "Worldquest-icon"
    if QuestUtil and QuestUtil.GetWorldQuestAtlasInfo and tagInfo then
        atlas = QuestUtil.GetWorldQuestAtlasInfo(qid, tagInfo, false) or atlas
    end
    -- CanCreateQuestGroup is the exact signal Blizzard's own tracker uses. GetActivityIDForQuestID returns truthy for ordinary world quests too, so avoid it.
    local canGroup
    if QuestUtil and QuestUtil.CanCreateQuestGroup then
        canGroup = QuestUtil.CanCreateQuestGroup(qid)
    elseif C_LFGList and C_LFGList.CanCreateQuestGroup then
        canGroup = C_LFGList.CanCreateQuestGroup(qid)
    end
    return { atlas = atlas, canGroup = canGroup or false, title = questTitle(qid) }
end


function V:Render(content, contentWidth, yStart, collapsed)
    local quests = getActiveWorldQuests()
    local count = #quests

    releaseAll()

    if collapsed or count == 0 then return 0, count end

    local Media = ns:GetSubsystem("Media")

    local doneHex = "44ff44"
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    local ovR, ovG, ovB
    if ns.Util and ns.Util.EffectiveTitleColor then ovR, ovG, ovB = ns.Util.EffectiveTitleColor(t) end
    if t and t.overrideCompleteGreen ~= false and ovR then
        doneHex = ("%02x%02x%02x"):format(
            math.floor(ovR * 255 + 0.5),
            math.floor(ovG * 255 + 0.5),
            math.floor(ovB * 255 + 0.5))
    end

    local superID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                     and C_SuperTrack.GetSuperTrackedQuestID()) or 0

    local y = yStart
    for i = 1, count do
        local qid = quests[i]
        local row = acquireHeader(content)
        row:SetWidth(contentWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row.questID = qid

        local st = _wqStatic[qid]
        if not st then st = buildStatic(qid); _wqStatic[qid] = st end
        row.icon:SetAtlas(st.atlas)
        row.ring:SetTexture("Interface/WorldMap/UI-QuestPoi-NumberIcons")
        if qid == superID then
            row.ring:SetTexCoord(0.500, 0.625, 0.375, 0.5)
        else
            row.ring:SetTexCoord(0.875, 1.000, 0.375, 0.5)
        end
        row.iconHolder:Show()
        row.title:ClearAllPoints()
        row.title:SetPoint("LEFT", row.iconHolder, "RIGHT", LABEL_PAD, 0)

        if st.canGroup then
            row.groupFinder:Show()
            row.title:SetPoint("RIGHT", row.groupFinder, "LEFT", -4, 0)
        else
            row.groupFinder:Hide()
            row.title:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        end
        row.title:SetText(st.title)
        if ovR then
            row.title:SetTextColor(ovR, ovG, ovB)
        else
            row.title:SetTextColor(1.0, 0.82, 0.0)
        end
        if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end
        y = y + HEADER_H + ROW_GAP

        if C_QuestLog and C_QuestLog.RequestLoadQuestByID
           and not V._requestedLoad[qid] then
            V._requestedLoad[qid] = true
            C_QuestLog.RequestLoadQuestByID(qid)
        end

        local objs = (C_QuestLog and C_QuestLog.GetQuestObjectives
                       and C_QuestLog.GetQuestObjectives(qid)) or {}
        for j = 1, #objs do
            local obj = objs[j]
            if obj and obj.text and obj.text ~= "" then
                local lr = acquireLine(content)
                lr:SetWidth(contentWidth)
                lr:ClearAllPoints()
                lr:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                local txt = obj.text
                if obj.finished then
                    txt = "|A:common-icon-checkmark:12:12|a |cff" .. doneHex .. txt .. "|r"
                else
                    txt = "- " .. colorizeProgress(txt)
                end
                lr.text:SetText(txt)
                if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(lr.text, -2) end
                local h = math.max(lr.text:GetStringHeight(), LINE_H)
                lr:SetHeight(h)
                y = y + h + ROW_GAP + ns.Util.LineSpacing()
            end
        end
    end

    if not self._tickerArmed then
        self._tickerArmed = true
        C_Timer.After(TICKER_INTERVAL, function()
            self._tickerArmed = false
            local Tracker = ns:GetSubsystem("Tracker")
            if Tracker and Tracker.Refresh then Tracker:Refresh() end
        end)
    end

    return y - yStart, count
end

function V:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh()
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end
    Events:On("QUEST_WATCH_LIST_CHANGED", refresh)

    local function markActiveDirty() _activeDirty = true end
    Events:On("QUEST_ACCEPTED",           markActiveDirty)
    Events:On("QUEST_REMOVED",            markActiveDirty)
    Events:On("QUEST_TURNED_IN",          markActiveDirty)
    Events:On("QUEST_WATCH_LIST_CHANGED", markActiveDirty)
    Events:On("ZONE_CHANGED_NEW_AREA",    markActiveDirty)
    Events:On("PLAYER_ENTERING_WORLD",    markActiveDirty)

    -- QUEST_LOG_UPDATE doesn't always fire after RequestLoadQuestByID; use QUEST_DATA_LOAD_RESULT.
    local function dataLoadFlush()
        _activeDirty = true
        refresh()
    end
    Events:On("QUEST_DATA_LOAD_RESULT", function()
        Events:Debounce("eq.wqtracker.dataload", 0.15, dataLoadFlush)
    end)
end
