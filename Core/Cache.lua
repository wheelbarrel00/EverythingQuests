local _, ns = ...

local Cache = ns:RegisterSubsystem("Cache", {})

Cache.quests          = {}
Cache.headerOrder     = {}
Cache.dirtyAll        = true
Cache.dirtyObjectives = false

local firstSeen = {}

local baselined = false

-- On a cold login the quest log can still be empty, so the first build is empty.
-- The cheap refresh only updates cached quests - stay on full rebuild until primed.
local primed = false

local function deriveIsCampaign(id, info)
    if C_CampaignInfo and C_CampaignInfo.GetCampaignID then
        local cid = C_CampaignInfo.GetCampaignID(id)
        if cid and cid > 0 then return true end
    end
    return (info and info.campaignID and info.campaignID > 0) and true or false
end

-- Memoize hits only - a miss can mean the quest's static data has not streamed yet,
-- and a cached miss would never retry.
local tagIDCache = {}
local function getTagID(id)
    local cached = tagIDCache[id]
    if cached then return cached end
    local info = C_QuestLog and C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(id)
    local tagID = info and info.tagID
    if tagID then tagIDCache[id] = tagID end
    return tagID
end

local objTextCache = {}
local function getObjectivesText(id)
    local cached = objTextCache[id]
    if cached ~= nil then return cached end
    local text = ""
    if C_QuestLog and C_QuestLog.SetSelectedQuest and _G.GetQuestLogQuestText then
        local saved = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
        C_QuestLog.SetSelectedQuest(id)
        local _, objText = _G.GetQuestLogQuestText()
        text = objText or ""
        if saved and saved ~= 0 then C_QuestLog.SetSelectedQuest(saved) end
    end
    -- Do not memoize "" - the text may not have streamed yet and a cached "" never retries
    if text ~= "" then objTextCache[id] = text end
    return text
end

local _logRows = {}

-- Survives a rebuild on purpose, because on Classic each answer costs a SelectQuestLogEntry and
-- remembering them is what keeps the steady-state cost at zero. Dropped on level up, where a
-- retail reward is rescaled and the cached figure would be stale for the rest of the session.
local _rewardXP = {}

-- Reading XP moves the quest log selection on Classic, and if that fires QUEST_LOG_UPDATE the
-- refresh would re-enter this.
local _sweeping = false

local function fullRebuild()
    if _sweeping then return end
    wipe(Cache.quests)
    wipe(Cache.headerOrder)

    local currentHeader = nil
    local rows, last = ns.Compat.CollectQuestLog(_logRows)
    for i = 1, last do
        local info = rows[i]
        if info then
            if info.isHeader then
                currentHeader = info.title
            elseif info.isHidden then
            else
                local id = info.questID
                local fs = firstSeen[id]
                if not fs then
                    fs = baselined and time() or 0
                    firstSeen[id] = fs
                end
                local q = {
                    questID        = id,
                    firstSeen      = fs,
                    title          = info.title or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)),
                    level          = info.level,
                    zone           = currentHeader,
                    frequency      = info.frequency,
                    -- Classic has no C_QuestLog.IsComplete. Its completion flag rides the quest
                    -- log row instead, as a NUMBER: 1 ready to turn in, -1 failed, nil neither.
                    isComplete     = (C_QuestLog.IsComplete and C_QuestLog.IsComplete(id))
                                     or info.isComplete == 1
                                     or false,
                    -- A failed quest can be taken again, so its giver is still worth marking.
                    isFailed       = info.isComplete == -1,
                    isOnMap        = info.isOnMap,
                    isCampaign     = deriveIsCampaign(id, info),
                    isAutoComplete = info.isAutoComplete,
                    isWatched      = ns.Compat.IsQuestWatched(id),
                    tagID          = getTagID(id),
                    classification = (C_QuestInfoSystem
                                      and C_QuestInfoSystem.GetQuestClassification
                                      and C_QuestInfoSystem.GetQuestClassification(id))
                                  or (C_QuestLog
                                      and C_QuestLog.GetQuestClassification
                                      and C_QuestLog.GetQuestClassification(id)),
                    objectives     = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {},
                }
                if #q.objectives == 0 then
                    q.fallbackText = getObjectivesText(id)
                end
                Cache.quests[id] = q
            end
        end
    end
    -- After the rows are read, because on Classic this moves the quest log selection and the
    -- walk above must not be running while it does.
    _sweeping = true
    pcall(ns.Compat.CollectRewardXP, rows, last, _rewardXP)
    _sweeping = false
    for id, q in pairs(Cache.quests) do
        q.rewardXP = _rewardXP[id]
    end

    for qid in pairs(firstSeen) do
        if not Cache.quests[qid] then firstSeen[qid] = nil end
    end
    for qid in pairs(tagIDCache) do
        if not Cache.quests[qid] then tagIDCache[qid] = nil end
    end
    if next(Cache.quests) ~= nil then
        primed    = true
        baselined = true
    end
    Cache.dirtyAll        = false
    Cache.dirtyObjectives = false
end

-- An older EQOT satisfies '## Dependencies:' with no filter API, so a nil answer here has to
-- fall back to refreshing everything rather than refreshing nothing.
local function trackerFilterState()
    local T = _G.EQObjectiveTracker
    local DB = T and T.GetModule and T:GetModule("DB")
    if not (DB and DB.Tracker) then return false, nil end

    local cfg  = DB:Tracker()
    local char = DB.Char and DB:Char()
    local onlyWatched = cfg and cfg.showOnlyWatched ~= false
    -- EQOT keys pinned by provider first so two providers cannot collide on a bare id.
    local pinnedSet = char and char.pinned and char.pinned.quests
    return onlyWatched and true or false, pinnedSet
end

local function refreshDynamicFields()
    local onlyWatched, pinnedSet = trackerFilterState()
    for id, q in pairs(Cache.quests) do
        local watched = ns.Compat.IsQuestWatched(id)
        q.isWatched = watched
        q.isCampaign = deriveIsCampaign(id)
        if watched or not onlyWatched or (pinnedSet and pinnedSet[id]) then
            if C_QuestLog.GetQuestObjectives then
                q.objectives = C_QuestLog.GetQuestObjectives(id) or q.objectives
            end
            if C_QuestLog.IsComplete then
                q.isComplete = C_QuestLog.IsComplete(id) or false
            end
            if q.objectives and #q.objectives == 0 and not q.fallbackText then
                q.fallbackText = getObjectivesText(id)
            end
        end
    end
    Cache.dirtyObjectives = false
end

local function refresh()
    if Cache.dirtyAll then
        fullRebuild()
    elseif Cache.dirtyObjectives then
        refreshDynamicFields()
    end
end

function Cache:Get(questID)
    refresh()
    return self.quests[questID]
end

function Cache:All()
    refresh()
    return self.quests
end

-- The tracked set on Classic lives in EQOT's saved variables and answers to no game event, so a
-- toggle there has to say so itself. Objective-level is enough - refreshDynamicFields recomputes
-- isWatched for every cached quest, and nothing else about the quest moved.
function Cache:InvalidateWatched()
    Cache.dirtyObjectives = true
end

function Cache:OnInitialize()
    local Events = ns:GetSubsystem("Events")

    local function dirtyAll() Cache.dirtyAll = true end
    Events:On("QUEST_ACCEPTED",   dirtyAll)
    Events:On("QUEST_REMOVED",    dirtyAll)
    Events:On("QUEST_TURNED_IN",  dirtyAll)
    Events:On("PLAYER_LEVEL_UP",  function() wipe(_rewardXP); dirtyAll() end)

    -- On Classic the ready-to-turn-in flag lives on the quest log ROW, which only the full
    -- rebuild walks. A Classic log is about 20 entries, so promoting to one is cheap there.
    local hasIsComplete = type(C_QuestLog) == "table"
                          and type(C_QuestLog.IsComplete) == "function"

    local function dirtyDynamic()
        if not primed or not hasIsComplete then
            Cache.dirtyAll = true
        else
            Cache.dirtyObjectives = true
        end
    end
    Events:On("QUEST_LOG_UPDATE",         dirtyDynamic)
    Events:On("QUEST_WATCH_LIST_CHANGED", dirtyDynamic)
end
