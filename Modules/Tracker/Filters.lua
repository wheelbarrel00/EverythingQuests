local _, ns = ...

local Filters = ns:RegisterSubsystem("TrackerFilters", {})

local DAILY_FREQ  = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Daily)  or LE_QUEST_FREQUENCY_DAILY  or 2
local WEEKLY_FREQ = (Enum and Enum.QuestFrequency and Enum.QuestFrequency.Weekly) or LE_QUEST_FREQUENCY_WEEKLY or 3

local function currentZoneName()
    return GetZoneText and GetZoneText() or nil
end

local function isWorldQuest(questID)
    if C_QuestLog and C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(questID) then
        return true
    end
    if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(questID) then
        return true
    end
    return false
end

-- Zone membership comes from map POIs - quest-log headers are campaign groupings that rarely equal GetZoneText(), so comparing them hides everything.
-- Returns a reused scratch table, or nil when the map or API is unavailable, and callers must then fail open rather than hide.
local _zoneScratch = {}
function Filters:CurrentZoneQuests()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map then return nil end
    local list = C_QuestLog and C_QuestLog.GetQuestsOnMap and C_QuestLog.GetQuestsOnMap(map)
    if not list then return nil end
    wipe(_zoneScratch)
    for i = 1, #list do
        local e = list[i]
        local qid = e and e.questID
        if qid then _zoneScratch[qid] = true end
    end
    return _zoneScratch
end

function Filters:Visible(questID, q, showAllInLog, zoneSet)
    if not q then return false end

    local DB = ns:GetSubsystem("DB")
    if not DB then return true end
    local profile = DB.db.profile.tracker
    local f       = profile.filters
    local char    = DB.char

    if not showAllInLog and char.hidden and char.hidden[questID] then return false end

    if char.pinned and char.pinned[questID] then return true end

    if not showAllInLog and profile.showOnlyWatched and not q.isWatched then
        return false
    end

    if isWorldQuest(questID) then
        if f.showWorld == false then return false end
    elseif q.isCampaign then
        if not f.showCampaign then return false end
    elseif q.frequency == DAILY_FREQ then
        if not f.showDaily then return false end
    elseif q.frequency == WEEKLY_FREQ then
        if not f.showWeekly then return false end
    else
        if not f.showNormal then return false end
    end

    if f.onlyCurrentZone and zoneSet then
        local inZone = zoneSet[questID] or (q.zone and q.zone == currentZoneName())
        if not inZone then return false end
    end

    return true
end
