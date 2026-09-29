local _, ns = ...

local M = ns:RegisterSubsystem("AvailableQuests", {})

-- Gated on the generated table's presence, never a build number. Only the flavor TOCs list it
local function data()
    return ns.CLASSIC_QUEST_AVAILABLE
end

-- Bit i (zero based) is race or class id i+1, tested by modulo as the offline interpreter has no bit library
local function hasBit(mask, flag)
    if not mask or mask == 0 then return true end
    if not flag then return false end
    return (mask % (flag + flag)) >= flag
end

-- For a client that gives no numeric id, since the gate cannot run without a bit
local RACE_BIT = {
    Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16,
    Tauren = 32, Gnome = 64, Troll = 128, Goblin = 256, BloodElf = 512, Draenei = 1024,
}
local CLASS_BIT = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, MONK = 512, DRUID = 1024,
}

-- Forever's Skyborne races (ids 95 and 96) have no mask bit, so they need every Era race of their faction
local ALLIANCE_ERA_RACES = { 1, 4, 8, 64 }
local HORDE_ERA_RACES    = { 2, 16, 32, 128 }

local _level, _raceBit, _classBit, _raceEveryOf

local function readLevel()
    _level = UnitLevel and UnitLevel("player") or 0
end

local function raceAllows(races)
    if _raceEveryOf then
        for i = 1, #_raceEveryOf do
            if not hasBit(races, _raceEveryOf[i]) then return false end
        end
        return true
    end
    return hasBit(races, _raceBit)
end

local function readPlayer()
    readLevel()

    local _, raceToken, raceID = UnitRace("player")
    _raceEveryOf = nil
    if type(raceID) == "number" and raceID > 0 and raceID < 32 then
        _raceBit = 2 ^ (raceID - 1)
    else
        _raceBit = RACE_BIT[raceToken or ""]
    end
    if not _raceBit then
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        _raceEveryOf = (faction == "Alliance" and ALLIANCE_ERA_RACES)
                    or (faction == "Horde" and HORDE_ERA_RACES)
                    or nil
    end
    M._raceRoute = (_raceBit and "race bit") or (_raceEveryOf and "faction") or nil

    local _, classToken, classID = UnitClass("player")
    if type(classID) == "number" and classID > 0 and classID < 32 then
        _classBit = 2 ^ (classID - 1)
    else
        _classBit = CLASS_BIT[classToken or ""]
    end
end

-- For /eqsprobe, since a gate that never ran and one that filtered look identical on the map
M._gatesRun = {}
M._resolved, M._availableN, M._reason = 0, 0, {}

local _completed = {}
local _completedOk = false

local function readCompleted()
    _completedOk = false
    if type(_G.GetQuestsCompleted) ~= "function" then return end
    wipe(_completed)
    -- Answers a SET keyed questID, not an array, so it is filled rather than counted
    local ok = pcall(_G.GetQuestsCompleted, _completed)
    if not ok then return end
    _completedOk = next(_completed) ~= nil
end

local function isCompleted(questID)
    if _completedOk then return _completed[questID] and true or false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
    end
    return false
end

-- A quest in the log is not on offer unless it FAILED, as a failed quest can be taken again
local function logState(questID)
    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache.quests and Cache.quests[questID]
    if not q then return false, false end
    return true, q.isFailed and true or false
end

-- Only bit rejections are remembered. The faction route can stand in for a race that failed to read.
local _permaNo = {}

-- Declared here because isAvailable reads them and preparePass, further down, is what sets them.
local _holidays, _hideSeason, _hideHigh, _redCeiling

-- Bit 2 marks a quest completed by exploring or a script, never a holiday. The source gates nothing on it
local SF_REPEATABLE, SF_EXPLORE = 1, 2

-- The client's own grey threshold. Unreadable shows every quest, as hiding on missing data empties the map
local function trivialFloor()
    local ok, range
    if type(_G.GetQuestGreenRange) == "function" then
        ok, range = pcall(_G.GetQuestGreenRange, "player")
        if not (ok and type(range) == "number") then
            -- Older builds take no unit argument
            ok, range = pcall(_G.GetQuestGreenRange)
            if not ok then return nil end
        end
    elseif type(_G.UnitQuestTrivialLevelRange) == "function" then
        -- The retail client's name for the same range, and WoW Forever runs the retail client
        ok, range = pcall(_G.UnitQuestTrivialLevelRange, "player")
        if not ok then return nil end
        -- Blizzard's DifficultyUtil keeps a quest yellow down to 4 levels below you, whatever the range
        if type(range) == "number" then range = math.max(range, 4) end
    end
    if type(range) ~= "number" then return nil end
    return _level - range
end

-- The first level the client colors red, derived rather than fixed (+5 at level 22 on 1.15.9). Nil shows the quest
local function redCeiling()
    if type(_G.GetQuestDifficultyColor) ~= "function" then return nil end
    local impossible = _G.QuestDifficultyColors and _G.QuestDifficultyColors.impossible
    if not impossible then return nil end
    if not _level or _level <= 0 then return nil end
    for offset = 1, 20 do
        local ok, color = pcall(_G.GetQuestDifficultyColor, _level + offset)
        if ok and color == impossible then return _level + offset end
    end
    return nil
end

local function anyCompleted(list)
    for i = 1, #list do
        if isCompleted(list[i]) then return true end
    end
    return false
end

local function allCompleted(list)
    for i = 1, #list do
        if not isCompleted(list[i]) then return false end
    end
    return true
end

-- An unreadable standing shows the quest, since a missing pin fails silently and a surplus one is seen
local function repStanding(factionID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, info = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and type(info) == "table" and type(info.currentStanding) == "number" then
            return info.currentStanding
        end
    end
    if type(_G.GetFactionInfoByID) == "function" then
        local ok, _, _, _, _, _, standing = pcall(_G.GetFactionInfoByID, factionID)
        if ok and type(standing) == "number" then return standing end
    end
    return nil
end

local function repFails(packed, wantAtLeast)
    if not packed then return false end
    local faction = math.floor(packed / 1e6)
    local value   = packed % 1e6
    local have    = repStanding(faction)
    if have == nil then return false end
    M._gatesRun.reputation = true
    if wantAtLeast then return have < value end
    return have > value
end

local function countReason(key)
    M._reason[key] = (M._reason[key] or 0) + 1
end

-- Returned rather than counted, so the Quest Browser can ask about one quest without touching the counters
local REASON_COMPLETED   = "completed"
local REASON_IN_LOG      = "in your quest log"
local REASON_HOLIDAY     = "holiday quest"
local REASON_RACE_CLASS  = "race or class"
local REASON_REQ_LEVEL   = "too low level"
local REASON_LOW_LEVEL   = "low level"
local REASON_HIGH_LEVEL  = "high level"
local REASON_PREREQ      = "prerequisite"
local REASON_LATER_STEP  = "later step done"
local REASON_BRANCH      = "took another branch"
local REASON_REPUTATION  = "reputation"

-- The Data/QuestCategory bits. The event bit (4) stays unread, as it comes from SF_EXPLORE, not holidays
local CAT_INSTANCE, CAT_REPEATABLE, CAT_PROFESSION = 1, 2, 16

-- Each key HIDES its category, so nil shows it and older profiles are unchanged
local CATEGORY_FILTERS = {
    { bit = CAT_INSTANCE,   key = "hideDungeonQuests",    reason = "dungeon or raid quest" },
    { bit = CAT_REPEATABLE, key = "hideRepeatableQuests", reason = "repeatable quest" },
    { bit = CAT_PROFESSION, key = "hideProfessionQuests", reason = "profession quest" },
}

-- Rebuilt per pass, so the settings are read once rather than once per quest.
local _catMask = 0

local function refreshCategoryMask()
    _catMask = 0
    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db.profile.map
    if not map then return end
    for i = 1, #CATEGORY_FILTERS do
        local f = CATEGORY_FILTERS[i]
        if map[f.key] == true then _catMask = _catMask + f.bit end
    end
end

-- Answers the reason, so every refusal counts toward /eqsprobe available's sum to the total
local function categoryHidden(questID)
    if _catMask == 0 then return nil end
    local cats = ns.CLASSIC_QUEST_CATEGORY
    local mask = cats and cats[questID]
    if not mask then return nil end
    for i = 1, #CATEGORY_FILTERS do
        local f = CATEGORY_FILTERS[i]
        if math.floor(_catMask / f.bit) % 2 == 1 and math.floor(mask / f.bit) % 2 == 1 then
            return f.reason
        end
    end
    return nil
end

-- Ordered cheapest first, because every check below the masks walks a list.
local function isAvailable(questID, D, hideLowLevel, floor)
    if _permaNo[questID] then return false, REASON_RACE_CLASS end

    local gates = D.gates[questID]
    if not gates then return false end

    local hiddenBy = categoryHidden(questID)
    if hiddenBy then return false, hiddenBy end

    local flags = math.floor(gates % 1e9 / 1e8)
    local repeatable = (flags % (SF_REPEATABLE + SF_REPEATABLE)) >= SF_REPEATABLE

    if isCompleted(questID) and not repeatable then return false, REASON_COMPLETED end

    local inLog, failed = logState(questID)
    if inLog and not failed then return false, REASON_IN_LOG end

    local races = math.floor(gates % 1e8 / 1e4)
    if not raceAllows(races) then
        if not _raceEveryOf then _permaNo[questID] = true end
        return false, REASON_RACE_CLASS
    end
    local classes = gates % 1e4
    if not hasBit(classes, _classBit) then
        _permaNo[questID] = true
        return false, REASON_RACE_CLASS
    end
    M._gatesRun.raceClass = true

    local reqLevel = math.floor(gates / 1e11)
    if reqLevel > 0 and _level < reqLevel then return false, REASON_REQ_LEVEL end

    if hideLowLevel and floor then
        local questLevel = math.floor(gates % 1e11 / 1e9)
        if questLevel > 0 and questLevel < floor then return false, REASON_LOW_LEVEL end
    end

    -- The `> 0` test mirrors the low filter and cannot fire here, as the ceiling is above the player.
    if _hideHigh and _redCeiling then
        local questLevel = math.floor(gates % 1e11 / 1e9)
        if questLevel > 0 and questLevel >= _redCeiling then return false, REASON_HIGH_LEVEL end
    end

    -- Below race, class and level so it counts only what the season costs. Holidays.lua owns the dates
    if _hideSeason and _holidays and _holidays:IsOutOfSeason(questID) then
        return false, REASON_HOLIDAY
    end

    local pre = D.pre[questID]
    if pre then
        if not anyCompleted(pre) then return false, REASON_PREREQ end
    else
        local preAll = D.preAll[questID]
        if preAll and not allCompleted(preAll) then return false, REASON_PREREQ end
    end

    -- The parent must be in the log, not merely done, as these steps exist only while you are on it
    local parent = D.parent[questID]
    if parent then
        local parentInLog = logState(parent)
        if not parentInLog then return false, REASON_PREREQ end
    end

    local nextID = D.chain[questID]
    if nextID then
        local nextInLog = logState(nextID)
        if nextInLog or isCompleted(nextID) then return false, REASON_LATER_STEP end
    end

    local excl = D.excl[questID]
    if excl then
        for i = 1, #excl do
            local other = excl[i]
            local otherInLog = logState(other)
            if otherInLog or isCompleted(other) then return false, REASON_BRANCH end
        end
    end

    if repFails(D.minRep[questID], true) then return false, REASON_REPUTATION end
    if repFails(D.maxRep[questID], false) then return false, REASON_REPUTATION end

    return true
end

local _available = {}
local _built, _prepared = false, false
local _hideLowLevel, _floor

function M:Invalidate()
    _built, _prepared = false, false
end

-- The player side of the gate, shared with Explain. _prepared saves a log refresh per question asked
local function preparePass()
    refreshCategoryMask()

    -- Forces the cache's refresh once, as logState reads Cache.quests directly and a cold login reads it empty
    local Cache = ns:GetSubsystem("Cache")
    if Cache and Cache.All then Cache:All() end

    -- Once per pass, as the season answer is the same for every quest in a rebuild
    _holidays = ns:GetSubsystem("QuestHolidays")
    if _holidays then _holidays:BeginPass() end

    readPlayer()
    if not ((_raceBit or _raceEveryOf) and _classBit) then return false end
    readCompleted()
    -- Set once the masks are readable, so it holds even on a pass that rejects every quest.
    M._gatesRun.raceClass = true

    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db.profile.map
    -- Compared against false, so a profile older than the option reads ON, as its checkbox shows
    _hideLowLevel = not (map and map.hideLowLevelQuests == false)
    _hideSeason = not (map and map.hideOutOfSeasonQuests == false)
    _hideHigh = (map and map.hideHighLevelQuests) == true
    _redCeiling = _hideHigh and redCeiling() or nil
    M._gatesRun.highLevel = (_redCeiling ~= nil)
    M._gatesRun.season = (_hideSeason and _holidays ~= nil) or false
    _floor = _hideLowLevel and trivialFloor() or nil
    M._gatesRun.trivial = (_floor ~= nil)
    _prepared = true
    return true
end

function M:Rebuild()
    wipe(_available)
    wipe(M._reason)
    -- Wiped too, or a pass that returns early reports the gates an earlier pass ran
    wipe(M._gatesRun)
    M._resolved, M._availableN, M._raceRoute = 0, 0, nil
    _built = true

    local D = data()
    if not D then M._stage = "no data table on this flavor" return end

    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db.profile.map
    if map and map.showAvailableQuests == false then
        M._stage = "off in options"
        return
    end

    if not preparePass() then
        M._stage = "player race or class did not resolve"
        return
    end

    for questID in pairs(D.gates) do
        M._resolved = M._resolved + 1
        local ok, why = isAvailable(questID, D, _hideLowLevel, _floor)
        if ok then
            _available[questID] = true
            M._availableN = M._availableN + 1
        elseif why then
            countReason(why)
        end
    end
    M._stage = "ran"
end

local function ensure()
    if not _built then M:Rebuild() end
end

function M:IsAvailable(questID)
    ensure()
    return _available[questID] and true or false
end

function M:All()
    ensure()
    return _available
end

function M:Title(questID)
    if _G.QuestUtils_GetQuestName then
        local name = _G.QuestUtils_GetQuestName(questID)
        if type(name) == "string" and name ~= "" then return name end
    end
    local D = data()
    return (D and D.names[questID]) or ("Quest #" .. tostring(questID))
end

function M:RequiredLevel(questID)
    local D = data()
    local gates = D and D.gates[questID]
    if not gates then return nil end
    local n = math.floor(gates / 1e11)
    return n > 0 and n or nil
end

function M:QuestLevel(questID)
    local D = data()
    local gates = D and D.gates[questID]
    if not gates then return nil end
    local n = math.floor(gates % 1e11 / 1e9)
    return n > 0 and n or nil
end

function M:IsRepeatable(questID)
    local D = data()
    local gates = D and D.gates[questID]
    if not gates then return false end
    local flags = math.floor(gates % 1e9 / 1e8)
    return (flags % (SF_REPEATABLE + SF_REPEATABLE)) >= SF_REPEATABLE
end

function M:IsExplorationOrScripted(questID)
    local D = data()
    local gates = D and D.gates[questID]
    if not gates then return false end
    local flags = math.floor(gates % 1e9 / 1e8)
    return (flags % (SF_EXPLORE + SF_EXPLORE)) >= SF_EXPLORE
end

-- The raw masks, leaving the bit names to the caller. Zero means no gate
function M:RaceMask(questID)
    local D = data()
    local gates = D and D.gates[questID]
    if not gates then return nil end
    return math.floor(gates % 1e8 / 1e4)
end

function M:ClassMask(questID)
    local D = data()
    local gates = D and D.gates[questID]
    if not gates then return nil end
    return gates % 1e4
end

-- The gate's own two state reads, so one question cannot disagree with the map
function M:IsCompleted(questID)
    ensure()
    if not _prepared then preparePass() end
    return isCompleted(questID)
end

function M:InLog(questID)
    ensure()
    -- As in IsCompleted, since only preparePass forces the refresh that fills Cache.quests
    if not _prepared then preparePass() end
    return logState(questID)
end

function M:Data()
    return data()
end

function M:TrivialFloor()
    readLevel()
    return trivialFloor()
end

-- srcID*1e9 + kind*1e8 + coordinates. The merge key is the coordinates alone, so one giver is one pin
local function decodeStart(v)
    local rest = v % 1e8
    return math.floor(v / 1e8) % 10, math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, rest,
           math.floor(v / 1e9)
end

-- Every start of one quest on every map, where PointsFor answers what to draw on one map
function M:StartsFor(questID, out)
    local D = data()
    local byMap = D and D.start[questID]
    if not byMap then return 0 end
    local n = 0
    for mapID, list in pairs(byMap) do
        for i = 1, #list do
            local kind, x, y, _, src = decodeStart(list[i])
            n = n + 1
            out[n] = { mapID = mapID, x = x, y = y, kind = kind,
                       name = ns.Compat.SourceName(kind, src) }
        end
    end
    return n
end

-- skillLineID*1e4 + requiredValue. The id has no name lookup here, so only the need can be shown
function M:SkillGate(questID)
    local D = data()
    local v = D and D.skill[questID]
    if not v then return nil end
    return math.floor(v / 1e4), v % 1e4
end

-- factionID*1e6 + standing. An if, as the and/or form answers the minimum when no maximum exists
function M:RepGate(questID, which)
    local D = data()
    if not D then return nil end
    local v
    if which == "max" then v = D.maxRep[questID] else v = D.minRep[questID] end
    if not v then return nil end
    return math.floor(v / 1e6), v % 1e6
end

-- The SAME gate the map pass asks, for one quest, so the browser and the map cannot disagree
function M:Explain(questID)
    local D = data()
    if not (D and questID and D.gates[questID]) then return nil end
    ensure()
    if _available[questID] then return true end
    -- A pass can stop before reading the player (the option off), and the browser still owes an answer
    if not _prepared and not preparePass() then return nil end
    return isAvailable(questID, D, _hideLowLevel, _floor)
end

-- An item-started quest reaches over a thousand points on one map. One spot can hold over two dozen quests
local MAX_PER_QUEST = 4

M._locX, M._locY, M._locKind, M._locQuests, M._locN = {}, {}, {}, {}, 0

local _byCoord, _order = {}, {}

function M:PointsFor(mapID)
    ensure()
    self._locN = 0
    local D = data()
    if not D or not mapID then return 0 end

    wipe(_byCoord)
    wipe(_order)

    for questID in pairs(_available) do
        local byMap = D.start[questID]
        local list = byMap and byMap[mapID]
        if list then
            local taken = 0
            -- Stored densest first, so the cap keeps the best locations. Never reorder here
            for i = 1, #list do
                if taken >= MAX_PER_QUEST then break end
                local kind, x, y, key, src = decodeStart(list[i])
                local slot = _byCoord[key]
                if not slot then
                    slot = { x = x, y = y, kind = kind, src = src, quests = {}, kinds = {} }
                    _byCoord[key] = slot
                    _order[#_order + 1] = key
                elseif kind < slot.kind or (kind == slot.kind and src < slot.src) then
                    -- The lower kind wins, then the lower source. They move together, as the kind picks the id space
                    slot.kind, slot.src = kind, src
                end
                local q = #slot.quests + 1
                slot.quests[q], slot.kinds[q] = questID, kind
                taken = taken + 1
            end
        end
    end

    local n = 0
    for i = 1, #_order do
        local slot = _byCoord[_order[i]]
        n = n + 1
        self._locX[n], self._locY[n] = slot.x, slot.y
        self._locKind[n], self._locQuests[n] = slot.kind, slot.quests
        -- On the quest list, which travels to the pin. Named keys leave #quests as the count
        slot.quests.startKind = slot.kind
        slot.quests.startSrc  = slot.src
        slot.quests.startKinds = slot.kinds
    end
    self._locN = n
    return n
end

function M:OnEnable()
    if not data() then return end
    local Events = ns:GetSubsystem("Events")

    local function invalidate() M:Invalidate() end
    -- QUEST_LOG_UPDATE is the only event for a quest failing in place, and it brings a cold login's log
    Events:On("QUEST_LOG_UPDATE",     invalidate)
    Events:On("QUEST_ACCEPTED",       invalidate)
    Events:On("QUEST_REMOVED",        invalidate)
    Events:On("QUEST_TURNED_IN",      invalidate)
    Events:On("PLAYER_LEVEL_UP",      invalidate)
    Events:On("PLAYER_ENTERING_WORLD", invalidate)
    Events:On("SKILL_LINES_CHANGED",  invalidate)
    Events:On("UPDATE_FACTION",       invalidate)
end
