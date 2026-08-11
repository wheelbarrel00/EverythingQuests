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
-- 1, 4, 6 and 8 are measured live - the 1.12 layout wikis label "Classic Era" is wrong here.
local function flatRow(i)
    local title, _, _, isHeader, _, isComplete, _, questID = _G.GetQuestLogTitle(i)
    if title == nil then return nil end
    return {
        title      = title,
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
