local _, ns = ...

local W = ns:RegisterSubsystem("WQWatchPersist", {})

local MANUAL = (Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual) or 1

local function getList()
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.char) then return nil end
    DB.char.trackedWorldQuests = DB.char.trackedWorldQuests or {}
    return DB.char.trackedWorldQuests
end

local function blizzardIsWatched(questID)
    return C_QuestLog and C_QuestLog.GetQuestWatchType
           and C_QuestLog.GetQuestWatchType(questID) ~= nil
end

-- Not C_QuestLog.IsWorldQuest: that stays true for an expired world quest forever, so ghost entries could never be pruned
local function questStillActive(questID)
    if C_TaskQuest and C_TaskQuest.GetQuestTimeLeftMinutes then
        local t = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
        if t and t > 0 then return true end
    end
    if C_TaskQuest and C_TaskQuest.IsActive and C_TaskQuest.IsActive(questID) then
        return true
    end
    return false
end

-- The tracker lives in EQ Objective Tracker now. It refreshes itself on
-- QUEST_WATCH_LIST_CHANGED anyway, so this only makes a map-pin track land immediately
-- rather than on the next event.
local function notifyTracker()
    local T = _G.EQObjectiveTracker
    local Tracker = T and T.GetModule and T:GetModule("Tracker")
    if Tracker and Tracker.Refresh then Tracker:Refresh() end
end

local restored = false

local function restore()
    local list = getList()
    if not list then return end
    for questID in pairs(list) do
        if not questStillActive(questID) then
            list[questID] = nil
        elseif not blizzardIsWatched(questID) then
            if C_QuestLog and C_QuestLog.AddWorldQuestWatch then
                C_QuestLog.AddWorldQuestWatch(questID, MANUAL)
            end
        end
    end
    restored = true
    notifyTracker()
end

-- The tracker untracks through Blizzard's API directly now, so this store no longer hears
-- about it and restore() would re-add the quest on the next loading screen. Pruning here is
-- what makes an untrack stick. Gated on restored because Blizzard's watch list is empty until
-- restore has run, and pruning against it before then would wipe the saved set on every login.
local function pruneUnwatched()
    if not restored then return end
    local list = getList()
    if not list then return end
    for questID in pairs(list) do
        if not blizzardIsWatched(questID) then list[questID] = nil end
    end
end

function W:Track(questID)
    if not questID then return end
    local list = getList()
    if list then list[questID] = true end
    if C_QuestLog and C_QuestLog.AddWorldQuestWatch then
        C_QuestLog.AddWorldQuestWatch(questID, MANUAL)
    end
    notifyTracker()
end

function W:Untrack(questID)
    if not questID then return end
    local list = getList()
    if list then list[questID] = nil end
    if C_QuestLog and C_QuestLog.RemoveWorldQuestWatch then
        C_QuestLog.RemoveWorldQuestWatch(questID)
    end
    notifyTracker()
end

function W:IsTracked(questID)
    local list = getList()
    return list and list[questID] == true
end

function W:IsWatched(questID)
    if self:IsTracked(questID) then return true end
    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches
       and C_QuestLog.GetQuestIDForWorldQuestWatchIndex then
        for i = 1, C_QuestLog.GetNumWorldQuestWatches() or 0 do
            if C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i) == questID then
                return true
            end
        end
    end
    return blizzardIsWatched(questID)
end

-- Union both stores - persistent entries are not back in Blizzard's watch list until the post-login restore runs
function W:GetTrackedQuests()
    local out = {}
    local seen = {}
    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches then
        local n = C_QuestLog.GetNumWorldQuestWatches() or 0
        for i = 1, n do
            local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if qid and not seen[qid] then
                seen[qid] = true
                out[#out + 1] = qid
            end
        end
    end
    local list = getList()
    if list then
        for qid in pairs(list) do
            if not seen[qid] and questStillActive(qid) then
                seen[qid] = true
                out[#out + 1] = qid
            end
        end
    end
    return out
end

function W:OnEnable()
    local Events = ns:GetSubsystem("Events")
    Events:On("PLAYER_ENTERING_WORLD", function()
        -- WQ data is not populated immediately after login, so restore has to wait
        C_Timer.After(2, restore)
    end)
    Events:On("QUEST_WATCH_LIST_CHANGED", pruneUnwatched)
    Events:On("QUEST_TURNED_IN", function(_, questID)
        local list = getList()
        if list and questID then list[questID] = nil end
    end)
end
