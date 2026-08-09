local _, ns = ...

-- Feature detection only. Nothing in EQ may branch on WOW_PROJECT_ID or a build number -
-- Blizzard backports API into Classic builds constantly, so a version check is wrong the
-- moment it ships. If a flavor needs different behavior, that is a new Has flag.

local function method(tbl, name)
    return type(tbl) == "table" and type(tbl[name]) == "function"
end

local Has = {}
ns.Has = Has

-- ⛔ A flag is legitimate ONLY where existence and behavior agree. These names are all
-- PRESENT on Classic and return nothing usable forever, so a probe on any of them answers
-- true and lies to its caller: C_QuestLog.GetQuestsOnMap, QuestPOIGetIconInfo (which is
-- also ABSENT on retail), GetQuestPOIs, C_QuestLog.SetMapForQuestPOIs, GetQuestPOILeaderBoard,
-- QuestUtils_IsQuestWorldQuest and all of C_TaskQuest. Their gate is the TOC, not a flag.
-- GetNumQuestLogEntries is the worst of them - it returns a real number that counts only
-- VISIBLE rows. See CollectQuestLog below.

Has.QuestDataRequest = method(C_QuestLog, "RequestLoadQuestByID")
Has.TooltipDataUnit  = method(C_TooltipInfo, "GetUnit")

local Compat = {}
ns.Compat = Compat

-- GetNumQuestLogEntries counts only VISIBLE rows on Classic, so collapsing a header drops it
-- to the header count while every quest stays addressable by index. Treat it as a floor and
-- keep reading past it until an index comes back empty. On retail the count is exact, so the
-- second loop stops on its first probe and the result is unchanged.
local PROBE_AHEAD = 75

-- ⛔ Rows are stored AT THEIR QUEST LOG INDEX, holes and all, and the second return is the
-- highest index filled rather than a count. Callers hand that index straight back to APIs
-- like GetQuestLogSpecialItemInfo, so compacting the array would silently misalign them.
-- Walk it with `for i = 1, last do local info = out[i]; if info then`.
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

-- ⛔ MEASURED 2026-08-09 on Era 1.15.9: `C_QuestLog.GetInfo` and `C_QuestLog.GetNumQuestLogEntries`
-- are BOTH ABSENT there. Classic kept the pre-namespace globals instead, so the flat path is
-- not a nicety, it is the only quest log row source that flavor has.
--
-- Era returns SEVENTEEN values, the full modern layout:
--   1 title  2 level  3 suggestedGroup  4 isHeader  5 isCollapsed  6 isComplete
--   7 frequency  8 questID  9 startEvent ... 17 isScaling
-- ⛔ Positions 1, 4, 6 and 8 are MEASURED on a live client, not read off a page. Index 8 gave
-- quest 87, which QuestUtils_GetQuestName resolved to "Goldtooth". Index 6 answered 1 on both
-- quests that were ready to turn in and nil on all ten that were not - it is a NUMBER, 1 for
-- complete and -1 for failed, so it is compared against 1 rather than tested for truthiness.
-- ⚠ The 1.12 signature that the Fandom wikis still label "Classic Era" is DIFFERENT - it puts
-- isHeader at 5 and questID at 9. Building this from that page would have broken it silently.
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

-- Sorted, because a caller that caps the result would otherwise keep a different subset every
-- run. The flat global answers a SET keyed questID -> true, not an array, so walking it by
-- index finds nothing and reads as a clean zero.
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
