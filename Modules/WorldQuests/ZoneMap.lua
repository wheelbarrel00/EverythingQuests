local _, ns = ...
local L = ns.L

local Z = ns:RegisterSubsystem("WQZoneMap", {})

local PAD          = 6
local ROW_H        = 32
local ROW_GAP      = 2
local ICON_SIZE    = 26

Z.rowPool   = {}
Z.activeRows = {}

local Util = ns.Util

local function questTitle(questID)
    if C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID then
        local t = C_TaskQuest.GetQuestInfoByQuestID(questID)
        if t and t ~= "" then return t end
    end
    return L["World Quest"]
end

local function buildRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", PAD, 0)

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.title:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 6, -2)
    r.title:SetPoint("RIGHT", -PAD, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)

    r.timeText = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.timeText:SetPoint("BOTTOMLEFT", r.icon, "BOTTOMRIGHT", 6, 2)
    r.timeText:SetJustifyH("LEFT")

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
        if button == "RightButton" then
            ns.ShowWorldQuestMenu(self.questID)
        else
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                C_SuperTrack.SetSuperTrackedQuestID(self.questID)
            end
            local Watch = ns:GetSubsystem("WQWatchPersist")
            if Watch and Watch.Track then Watch:Track(self.questID) end
        end
    end)

    return r
end

local function acquireRow(parent)
    return ns.Util.AcquirePooled(Z.rowPool, Z.activeRows, parent, buildRow)
end

local function releaseAll()
    for i = #Z.activeRows, 1, -1 do
        local r = Z.activeRows[i]
        r:Hide()
        r:ClearAllPoints()
        r.icon:SetTexture(nil)
        r.icon:SetTexCoord(0, 1, 0, 1)
        r.title:SetText("")
        r.timeText:SetText("")
        r.questID = nil
        Z.rowPool[#Z.rowPool + 1] = r
        Z.activeRows[i] = nil
    end
end

function Z:Render(list)
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db.profile.worldQuests.enabled ~= false
            and DB.db.profile.worldQuests.showOnZoneMap) then
        releaseAll(); return 0, nil
    end
    if not (WorldMapFrame and WorldMapFrame:IsShown()) then releaseAll(); return 0, nil end

    local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not (mapID and mapID > 0) then releaseAll(); return 0, nil end

    local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneType = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3
    if not (mapInfo and mapInfo.mapType == zoneType) then releaseAll(); return 0, nil end

    local WQ = ns:GetSubsystem("WQWorldMap")
    if not (WQ and WQ.Quests) then releaseAll(); return 0, nil end

    local quests, count = WQ:Quests()
    local found = {}
    for i = 1, count do found[i] = quests[i] end

    if #found == 0 then releaseAll(); return 0, nil end

    local sortMode = (DB and DB.db.profile.worldQuests.zoneListSort) or "time"
    table.sort(found, function(a, b)
        if sortMode == "alpha" then
            return (questTitle(a.questID) or "") < (questTitle(b.questID) or "")
        elseif sortMode == "type" then
            local ca = (a.reward and a.reward.category) or "z"
            local cb = (b.reward and b.reward.category) or "z"
            if ca ~= cb then return ca < cb end
            return (questTitle(a.questID) or "") < (questTitle(b.questID) or "")
        elseif sortMode == "faction" then
            local fa = (C_QuestLog and C_QuestLog.GetQuestFactionID and C_QuestLog.GetQuestFactionID(a.questID)) or 0
            local fb = (C_QuestLog and C_QuestLog.GetQuestFactionID and C_QuestLog.GetQuestFactionID(b.questID)) or 0
            if fa ~= fb then return fa < fb end
            return (questTitle(a.questID) or "") < (questTitle(b.questID) or "")
        else
            local ta = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                       and C_TaskQuest.GetQuestTimeLeftMinutes(a.questID) or 0
            local tb = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                       and C_TaskQuest.GetQuestTimeLeftMinutes(b.questID) or 0
            return ta < tb
        end
    end)

    releaseAll()
    local y = 0
    for i = 1, #found do
        local q = found[i]
        local row = acquireRow(list)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT",  list, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, -y)
        row.questID = q.questID

        local Rewards = ns:GetSubsystem("WQRewards")
        if Rewards and Rewards.ApplyToTexture then
            Rewards:ApplyToTexture(row.icon, q.reward)
        end

        row.title:SetText(questTitle(q.questID))

        local mins = C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes
                     and C_TaskQuest.GetQuestTimeLeftMinutes(q.questID)
        row.timeText:SetText(Util.WQTimeLong(mins))
        row.timeText:SetTextColor(Util.WQTimeColor(mins))
        row:Show()

        y = y + ROW_H + ROW_GAP
    end

    return y, L["%s — %d quests"]:format(mapInfo.name, #found)
end
