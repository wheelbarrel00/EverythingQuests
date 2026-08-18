local _, ns = ...

-- Feature detection only. Never branch on WOW_PROJECT_ID or a build number - Blizzard
-- backports API into Classic builds, so a version check is wrong the moment it ships.

local function method(tbl, name)
    return type(tbl) == "table" and type(tbl[name]) == "function"
end

local Has = {}
ns.Has = Has

-- A flag is legitimate only where existence and behavior agree. Every POI, world quest and
-- C_TaskQuest name exists on Classic and returns nothing usable, so the TOC is their gate.

Has.QuestDataRequest = method(C_QuestLog, "RequestLoadQuestByID")
Has.TooltipDataUnit  = method(C_TooltipInfo, "GetUnit")

-- No flag for C_MapExplorationInfo.GetExploredAreaIDsAtPosition on purpose. MEASURED 2026-08-16
-- against a retail control: present on Era and answers nil everywhere, including ground the player
-- is standing on, while retail discriminates explored from unexplored on the identical call. A
-- hide-unexplored-markers option was built against it and removed. Do not rebuild it.

local Compat = {}
ns.Compat = Compat

-- GetNumQuestLogEntries counts only visible rows on Classic, so a collapsed header hides
-- quests that are still addressable by index. Treat it as a floor and probe past it.
local PROBE_AHEAD = 75

-- Rows are stored at their quest log index, holes and all, and the second return is the highest
-- index filled, not a count - callers pass that index back to Blizzard, so never compact it.
local function walk(out, getRow, reported)
    local last = 0
    for i = 1, reported do
        local row = getRow(i)
        if row then
            out[i] = row
            last = i
        end
    end
    for i = reported + 1, reported + PROBE_AHEAD do
        local row = getRow(i)
        if not row then break end
        out[i] = row
        last = i
    end
    return last
end

-- Classic has no C_QuestLog.GetInfo, so this flat global is its only row source. Positions
-- 1, 2, 4, 6 and 8 are all measured live now - the 1.12 layout wikis label "Classic Era" is
-- wrong here. Position 2 was the last one taken from a signature and is CONFIRMED as the level
-- by /eqsprobe port on Era 1.15.9: row 2 read title Goldtooth, [2]=8, [8]=87, and the shipped
-- quest data independently puts quest 87 at level 8. Header rows read 0 there, as they should.
local function flatRow(i)
    local title, level, _, isHeader, _, isComplete, _, questID = _G.GetQuestLogTitle(i)
    if title == nil then return nil end
    return {
        title      = title,
        level      = type(level) == "number" and level or nil,
        isHeader   = isHeader and true or false,
        questID    = questID,
        isComplete = isComplete,
    }
end

function Compat.CollectQuestLog(out)
    wipe(out)

    if method(C_QuestLog, "GetInfo") then
        local reported = method(C_QuestLog, "GetNumQuestLogEntries")
            and C_QuestLog.GetNumQuestLogEntries() or 0
        return out, walk(out, C_QuestLog.GetInfo, reported)
    end

    if type(_G.GetQuestLogTitle) ~= "function" then return out, 0 end
    local reported = 0
    if type(_G.GetNumQuestLogEntries) == "function" then
        local n = _G.GetNumQuestLogEntries()
        reported = tonumber(n) or 0
    end
    return out, walk(out, flatRow, reported)
end

-- Where the tracked set lives on Classic, resolved in ONE place because the reader below and
-- the repaint in Modules/TrackerBridge.lua must never disagree about which object owns it.
-- Absent on retail, where the module is not in EQOT's TOC and C_QuestLog answers instead.
function Compat.TrackedSet()
    local T = _G.EQObjectiveTracker
    local TS = T and T.GetModule and T:GetModule("TrackedSet")
    return (type(TS) == "table" and type(TS.IsTracked) == "function") and TS or nil
end

-- MEASURED 2026-08-16 on Era 1.15.9 by /eqsprobe mappoi: GetQuestWatchType is absent, and the
-- pre-namespace IsQuestWatched(logIndex) answered FALSE for all 14 quests while EQOT named 9 of
-- them tracked. EQOT owns the tracked set on this flavor and empties Blizzard's list behind every
-- add, so reading that global hides every owned pin - a confident wrong answer, worse than none.
-- Do not wire it back up.
-- Returns nil where nothing can answer, and a caller must treat nil as "cannot tell" and SHOW
-- the quest - collapsing nil into "not tracked" empties the map by the other route.
function Compat.IsQuestWatched(questID)
    if method(C_QuestLog, "GetQuestWatchType") then
        return C_QuestLog.GetQuestWatchType(questID) ~= nil
    end
    local TS = Compat.TrackedSet()
    if TS then
        local ok, tracked = pcall(TS.IsTracked, TS, questID)
        if ok then return tracked end
    end
    return nil
end

-- Sorted so a caller that caps the result keeps the same subset each run. The flat global
-- answers a set keyed by questID, not an array, so an index walk finds nothing and reads zero.
function Compat.CompletedQuestIDs(out)
    wipe(out)
    local n = 0

    if method(C_QuestLog, "GetAllCompletedQuestIDs") then
        local list = C_QuestLog.GetAllCompletedQuestIDs()
        if type(list) == "table" then
            for i = 1, #list do
                n = n + 1
                out[n] = list[i]
            end
        end
    end

    if n == 0 and type(_G.GetQuestsCompleted) == "function" then
        local set = _G.GetQuestsCompleted()
        if type(set) == "table" then
            for id, done in pairs(set) do
                if done then
                    n = n + 1
                    out[n] = id
                end
            end
        end
    end

    table.sort(out)
    return out, n
end

-- MEASURED on Era: GetQuestLogRewardXP IGNORES its argument and reports whatever quest log
-- entry is SELECTED. Existence is identical on both flavors, so the split cannot be a Has flag.
function Compat.RewardXPNeedsSelection()
    return type(_G.C_QuestLog) ~= "table" or type(_G.C_QuestLog.GetInfo) ~= "function"
end

-- NEVER call this from a mouseover. Each answer costs a SelectQuestLogEntry on Classic, which
-- moves the player's own quest log, so only rows missing from out are asked about.
function Compat.CollectRewardXP(rows, last, out)
    local getXP = _G.GetQuestLogRewardXP
    if type(getXP) ~= "function" then return false end

    local function want(info)
        return info and not info.isHeader and info.questID and out[info.questID] == nil
    end

    if not Compat.RewardXPNeedsSelection() then
        for i = 1, last do
            local info = rows[i]
            if want(info) then
                local ok, xp = pcall(getXP, info.questID)
                if ok and type(xp) == "number" then out[info.questID] = xp end
            end
        end
        return true
    end

    local selectEntry = _G.SelectQuestLogEntry
    if type(selectEntry) ~= "function" then return false end

    local before
    if type(_G.GetQuestLogSelection) == "function" then
        local ok, sel = pcall(_G.GetQuestLogSelection)
        if ok then before = sel end
    end

    local moved = false
    for i = 1, last do
        local info = rows[i]
        if want(info) and pcall(selectEntry, i) then
            moved = true
            local ok, xp = pcall(getXP)
            if ok and type(xp) == "number" then out[info.questID] = xp end
        end
    end

    -- Restored even when a row raised, or the quest log is left pointing somewhere the player
    -- did not put it.
    if moved and before then pcall(selectEntry, before) end
    return true
end
