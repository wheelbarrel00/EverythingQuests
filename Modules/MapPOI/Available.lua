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

local _level, _raceBit, _classBit, _raceEveryOf, _side, _sideRead

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
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    -- The generator's giverSide numbering: 1 Horde, 2 Alliance
    _side = (faction == "Alliance" and 2) or (faction == "Horde" and 1) or nil
    _sideRead = true
    if not _raceBit then
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

-- [skillLineID] = rank with its bonuses. M._skillsAll is true only once the whole list was read and, on Era and TBC, every name recognized
local _skills = {}
local _skillNameToID
-- Also for /eqsprobe available: which route read the list, how many lines it had, and the first name no table knew
M._skillsAll, M._skillRoute, M._skillLines, M._skillUnknown = false, nil, 0, nil

local function skillNames()
    local names = ns.SKILL_NAMES
    if not names then return nil end
    local locale = GetLocale and GetLocale()
    return names[locale] or names.enUS
end

local function points(v)
    return type(v) == "number" and v or 0
end

-- Bonus points count toward the rank too, so a doubtful case offers the quest rather than hiding it
local function readSkills()
    wipe(_skills)
    M._skillsAll, M._skillRoute, M._skillLines, M._skillUnknown = false, nil, 0, nil
    local S = _G.C_SkillInfo
    if S and S.GetNumSkillLines and S.GetSkillLineInfo then
        local okN, n = pcall(S.GetNumSkillLines)
        if not (okN and type(n) == "number" and n > 0) then return end
        M._skillRoute, M._skillLines = "ids", n
        local all = true
        for i = 1, n do
            local ok, t = pcall(S.GetSkillLineInfo, i)
            if not (ok and type(t) == "table") then
                all = false
            elseif t.isHeader then
                if t.isCollapsed then all = false end
            elseif type(t.skillID) == "number" and type(t.rank) == "number" then
                _skills[t.skillID] = t.rank + points(t.tempPoints) + points(t.modifier)
            end
        end
        M._skillsAll = all
        return
    end
    -- Era and TBC name each skill in the client's language only, so the shipped names map it back to its id
    local count, info, names = _G.GetNumSkillLines, _G.GetSkillLineInfo, skillNames()
    if not (count and info and names) then return end
    if not _skillNameToID then
        _skillNameToID = {}
        for id, name in pairs(names) do _skillNameToID[name] = id end
    end
    local okN, n = pcall(count)
    if not (okN and type(n) == "number" and n > 0) then return end
    M._skillRoute, M._skillLines = "names", n
    local all = true
    for i = 1, n do
        local ok, name, isHeader, isExpanded, rank, temp, modifier = pcall(info, i)
        if not ok then
            all = false
        elseif isHeader then
            if not isExpanded then all = false end
        else
            local id = name and _skillNameToID[name]
            if id and type(rank) == "number" then
                _skills[id] = rank + points(temp) + points(modifier)
            else
                -- A name the shipped table lacks could be a renamed profession, so nothing reads as missing
                all = false
                M._skillUnknown = M._skillUnknown or tostring(name)
            end
        end
    end
    M._skillsAll = all
end

local function knownLine(line)
    local names = ns.SKILL_NAMES
    return names ~= nil and names.enUS ~= nil and names.enUS[line] ~= nil
end

local function skillFails(packed)
    if not packed then return false end
    -- A need of 0 still asks for the skill
    local line, need = math.floor(packed / 1e4), math.max(packed % 1e4, 1)
    local have = _skills[line]
    -- A line with no shipped name can never be read by name, so its absence proves nothing
    if have == nil and not (M._skillsAll and knownLine(line)) then return false end
    M._gatesRun.profession = true
    return (have or 0) < need
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
local REASON_MAX_LEVEL   = "above level range"
local REASON_LOW_LEVEL   = "low level"
local REASON_HIGH_LEVEL  = "high level"
local REASON_PREREQ      = "prerequisite"
local REASON_BREADCRUMB  = "breadcrumb in your log"
local REASON_FOLLOW_UP   = "follow-up taken"
local REASON_LATER_STEP  = "later step done"
local REASON_BRANCH      = "took another branch"
local REASON_REPUTATION  = "reputation"
local REASON_PROFESSION  = "profession"
local REASON_NOT_IN_GAME = "not in the game"
local REASON_EVENT       = "event not running"
local REASON_UNRELEASED  = "not released"
local REASON_DAILY_DONE  = "daily done today"
local REASON_HIDDEN      = "hidden by you"

-- The ended codes tools/build_att_rules.lua writes. An unknown code still refuses, so the reasons keep summing to the total
local ENDED_REASON = { [1] = REASON_NOT_IN_GAME, [2] = REASON_EVENT, [3] = REASON_EVENT, [4] = REASON_UNRELEASED }
local ENDED_INVASION = 3

-- Season of Discovery runs the Scourge Invasion for good on the Era client. 2 is its season id where the enum is missing
local function invasionRunning()
    local S = _G.C_Seasons
    if not (S and S.GetActiveSeason) then return false end
    local ok, season = pcall(S.GetActiveSeason)
    local sod = _G.Enum and _G.Enum.SeasonID and _G.Enum.SeasonID.SeasonOfDiscovery or 2
    return ok and season == sod
end

-- Seconds to the daily reset, nil past a day: the client can answer epoch time on a login's first load
local function secondsToReset()
    local f = _G.GetQuestResetTime
    if type(f) ~= "function" then return nil end
    local ok, s = pcall(f)
    if ok and type(s) == "number" and s > 0 and s <= 86400 then return s end
    return nil
end

local function serverNow()
    local f = _G.GetServerTime or _G.time
    if type(f) == "function" then return f() end
    return nil
end

-- [questID] = the server time of the reset after this character handed it in, as the completed set is unmeasured for dailies on TBC
local function dailyStore()
    local DB = ns:GetSubsystem("DB")
    local char = DB and DB.char
    if not char then return nil end
    char.dailyDone = char.dailyDone or {}
    return char.dailyDone
end

-- [questID] = true for a quest this character took off the map by hand
local function hiddenStore()
    local DB = ns:GetSubsystem("DB")
    local char = DB and DB.char
    if not char then return nil end
    char.hiddenQuests = char.hiddenQuests or {}
    return char.hiddenQuests
end

local _dailyDone, _now, _invasionOn, _hidden

-- preparePass drops every record whose reset has passed, so one still held is from today
local function doneToday(questID)
    return _dailyDone ~= nil and _dailyDone[questID] ~= nil
end

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

-- [follow-up questID] = { breadcrumb questID, ... }, built at first use from the shipped leads, which never change
local _ledBy

local function ledBy(D)
    if not _ledBy then
        _ledBy = {}
        for crumb, to in pairs(D.leads or {}) do
            for i = 1, #to do
                local list = _ledBy[to[i]]
                if not list then list = {}; _ledBy[to[i]] = list end
                list[#list + 1] = crumb
            end
        end
        for _, list in pairs(_ledBy) do table.sort(list) end
    end
    return _ledBy
end

-- On Era and Forever, Taking Back Silithus and Securing the Supply Lines list each other as branches, so a breadcrumb's own link is never one
local function branchTaken(questID, D, leads)
    local excl = D.excl[questID]
    if excl then
        local crumbs = D.leads and ledBy(D)[questID]
        for i = 1, #excl do
            local other = excl[i]
            local own = false
            for k = 1, leads and #leads or 0 do
                if leads[k] == other then own = true end
            end
            for k = 1, crumbs and #crumbs or 0 do
                if crumbs[k] == other then own = true end
            end
            if not own and (logState(other) or isCompleted(other)) then return true end
        end
    end
    return false
end

-- A later step or another branch in the log or done, which keeps the game from offering the quest. Taking setAside, always one of its own follow-ups, is not counted
local function ruledOut(questID, D, setAside)
    local leads = D.leads and D.leads[questID]
    if leads then
        -- A breadcrumb's chain link often names its follow-up, so the follow-up comes first, and a branch taken before both
        if branchTaken(questID, D, leads) then return REASON_BRANCH end
        for i = 1, #leads do
            local q = leads[i]
            if q ~= setAside and (logState(q) or isCompleted(q)) then return REASON_FOLLOW_UP end
        end
    end

    local nextID = D.chain[questID]
    if nextID and nextID ~= setAside then
        local nextInLog = logState(nextID)
        if nextInLog or isCompleted(nextID) then return REASON_LATER_STEP end
    end

    if branchTaken(questID, D, leads) then return REASON_BRANCH end
    return nil
end

-- Unfiltered asks what the game itself would offer, so the map's display filters stay out and the season always counts
local function isAvailable(questID, D, hideLowLevel, floor, unfiltered)
    if _permaNo[questID] then return false, REASON_RACE_CLASS end

    local gates = D.gates[questID]
    if not gates then return false end

    local hiddenBy = not unfiltered and categoryHidden(questID)
    if hiddenBy then return false, hiddenBy end

    local flags = math.floor(gates % 1e9 / 1e8)
    local repeatable = (flags % (SF_REPEATABLE + SF_REPEATABLE)) >= SF_REPEATABLE
    local daily = D.daily and D.daily[questID]

    -- A daily is judged by the record alone, as one TBC daily lacks the repeatable flag
    if isCompleted(questID) and not (repeatable or daily) then return false, REASON_COMPLETED end
    if daily and doneToday(questID) then return false, REASON_DAILY_DONE end

    local inLog, failed = logState(questID)
    if inLog and not failed then return false, REASON_IN_LOG end

    -- Ahead of race, class and level, as no character is offered it and the reason should say so
    local ended = D.ended and D.ended[questID]
    if ended and not (ended == ENDED_INVASION and _invasionOn) then
        return false, ENDED_REASON[ended] or REASON_NOT_IN_GAME
    end

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
    local maxLevel = D.maxLevel and D.maxLevel[questID]
    if maxLevel and _level > maxLevel then return false, REASON_MAX_LEVEL end

    if hideLowLevel and floor then
        local questLevel = math.floor(gates % 1e11 / 1e9)
        if questLevel > 0 and questLevel < floor then return false, REASON_LOW_LEVEL end
    end

    -- The `> 0` test mirrors the low filter and cannot fire here, as the ceiling is above the player.
    if not unfiltered and _hideHigh and _redCeiling then
        local questLevel = math.floor(gates % 1e11 / 1e9)
        if questLevel > 0 and questLevel >= _redCeiling then return false, REASON_HIGH_LEVEL end
    end

    -- Below race, class and level so it counts only what the season costs. Holidays.lua owns the dates
    if (_hideSeason or unfiltered) and _holidays and _holidays:IsOutOfSeason(questID) then
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

    -- Measured on Era: Eagan Peltskinner does not offer Wolves Across the Border (33) while the breadcrumb to him (5261) is in the log
    local crumbs = ledBy(D)[questID]
    if crumbs then
        for i = 1, #crumbs do
            if logState(crumbs[i]) then return false, REASON_BREADCRUMB end
        end
    end

    local gone = ruledOut(questID, D)
    if gone then return false, gone end

    if repFails(D.minRep[questID], true) then return false, REASON_REPUTATION end
    if repFails(D.maxRep[questID], false) then return false, REASON_REPUTATION end

    if skillFails(D.skill[questID]) then return false, REASON_PROFESSION end

    -- Last, so it counts only quests every other gate passes, and never in an unfiltered answer, which asks what the game offers
    if not unfiltered and _hidden and _hidden[questID] then return false, REASON_HIDDEN end

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
    readSkills()
    _invasionOn = invasionRunning()
    _hidden = hiddenStore()
    -- Only TBC's daily table has rows, so the other clients never read a clock or the record
    local D = data()
    _now = D and D.daily and next(D.daily) and serverNow() or nil
    _dailyDone = _now and dailyStore() or nil
    if _dailyDone then
        for questID, at in pairs(_dailyDone) do
            if at <= _now then _dailyDone[questID] = nil end
        end
    end
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

function M:MaxLevel(questID)
    local D = data()
    return D and D.maxLevel and D.maxLevel[questID] or nil
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

-- The start table's kind for a creature giver, the only kind whose source id is a unit you can hover
local START_NPC = 1

-- A creature friendly to one faction alone offers the other nothing, whatever the quest's own races say. An unread faction hides none
local function hostileGiver(D, kind, src)
    local side = kind == START_NPC and D.giverSide and D.giverSide[src]
    if not side then return false end
    if not _sideRead then readPlayer() end
    return _side ~= nil and side ~= _side
end

-- Every start of one quest on every map, less givers hostile to you, where PointsFor answers what to draw on one map
function M:StartsFor(questID, out)
    local D = data()
    local byMap = D and D.start[questID]
    if not byMap then return 0 end
    local n = 0
    for mapID, list in pairs(byMap) do
        for i = 1, #list do
            local kind, x, y, _, src = decodeStart(list[i])
            if not hostileGiver(D, kind, src) then
                n = n + 1
                out[n] = { mapID = mapID, x = x, y = y, kind = kind,
                           name = ns.Compat.SourceName(kind, src) }
            end
        end
    end
    return n
end

function M:HostileGiver(kind, src)
    local D = data()
    return D ~= nil and hostileGiver(D, kind, src)
end

-- Whether a giver who will talk to you offers the quest on this map
function M:StartsOnMap(questID, mapID)
    local D = data()
    local list = D and D.start[questID] and D.start[questID][mapID]
    if not list then return false end
    for i = 1, #list do
        local kind, _, _, _, src = decodeStart(list[i])
        if not hostileGiver(D, kind, src) then return true end
    end
    return false
end

-- The ended code no character is offered the quest for, with Season of Discovery's invasion left open as the gate leaves it
function M:Ended(questID)
    local D = data()
    local code = D and D.ended and questID and D.ended[questID]
    if not code or (code == ENDED_INVASION and invasionRunning()) then return nil end
    return code
end

-- accept [questID]: bit 1 the game offers it to the whole group as one player takes it, escorts among them, bit 2 a PvP quest
local ACCEPT_GROUP, ACCEPT_PVP = 1, 2

local function acceptBit(questID, bit)
    local D = data()
    local v = D and D.accept and questID and D.accept[questID]
    return v ~= nil and v % (bit + bit) >= bit
end

function M:StartsForGroup(questID) return acceptBit(questID, ACCEPT_GROUP) end
function M:IsPvPQuest(questID) return acceptBit(questID, ACCEPT_PVP) end

-- [creatureID] = { questID, ... }, built on the first tooltip that asks and kept, as the data never changes
local _byGiver

function M:QuestsStartedBy(npcID)
    local D = data()
    if not (D and npcID) then return nil end
    if not _byGiver then
        _byGiver = {}
        for questID, byMap in pairs(D.start) do
            for _, list in pairs(byMap) do
                for i = 1, #list do
                    local kind, _, _, _, src = decodeStart(list[i])
                    if kind == START_NPC and src > 0 then
                        local quests = _byGiver[src]
                        if not quests then quests = {}; _byGiver[src] = quests end
                        -- One quest's points are walked together, so a repeat of it can only be the last entry
                        if quests[#quests] ~= questID then quests[#quests + 1] = questID end
                    end
                end
            end
        end
    end
    if hostileGiver(D, START_NPC, npcID) then return nil end
    return _byGiver[npcID]
end

-- skillLineID*1e4 + requiredValue
function M:SkillGate(questID)
    local D = data()
    local v = D and D.skill[questID]
    if not v then return nil end
    return math.floor(v / 1e4), v % 1e4
end

-- In the client's language: the game's own name where it can give one, else the shipped name, else nil
function M:SkillName(line)
    local S = _G.C_SkillInfo
    if S and S.GetSkillLineInfoByID then
        local ok, t = pcall(S.GetSkillLineInfoByID, line)
        if ok and type(t) == "table" and type(t.name) == "string" and t.name ~= "" then return t.name end
    end
    local names = skillNames()
    return names and names[line] or nil
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
function M:Explain(questID, unfiltered)
    local D = data()
    if not (D and questID and D.gates[questID]) then return nil end
    ensure()
    -- Not for an unfiltered answer, which applies the season even where the map's pass did not
    if not unfiltered and _available[questID] then return true end
    -- A pass can stop before reading the player (the option off), and the browser still owes an answer
    if not _prepared and not preparePass() then return nil end
    if unfiltered then return isAvailable(questID, D, false, nil, true) end
    return isAvailable(questID, D, _hideLowLevel, _floor)
end

-- What the game would offer, without the map's filters or its whole pass, as an NPC tooltip asks per quest on a hover
function M:Offers(questID)
    local D = data()
    if not (D and questID and D.gates[questID]) then return nil end
    if not _prepared and not preparePass() then return nil end
    return isAvailable(questID, D, false, nil, true) == true
end

-- Explain names only the first gate that fails, and a prerequisite still missing would hide a branch already lost
function M:RuledOut(questID)
    local D = data()
    if not (D and questID and D.gates[questID]) then return nil end
    ensure()
    if not _prepared and not preparePass() then return nil end
    return ruledOut(questID, D)
end

function M:LeadsTo(questID)
    local D = data()
    return D and D.leads and questID and D.leads[questID] or nil
end

function M:LedBy(questID)
    local D = data()
    if not (D and D.leads and questID) then return nil end
    return ledBy(D)[questID]
end

-- The breadcrumbs to a quest that this character could still have taken until taking the quest closed them
function M:SkippedBreadcrumbs(questID, out)
    for i = #out, 1, -1 do out[i] = nil end
    local D = data()
    local crumbs = D and D.leads and ledBy(D)[questID]
    if not crumbs then return out end
    if not _prepared and not preparePass() then return out end
    -- A breadcrumb done means you came the way it sent you, so none of the others is named
    for i = 1, #crumbs do
        if isCompleted(crumbs[i]) then return out end
    end
    for i = 1, #crumbs do
        local crumb = crumbs[i]
        if D.gates[crumb] then
            local ok, why = isAvailable(crumb, D, false, nil, true)
            -- ruledOut stopped at the follow-up, so its other gates are asked here with this quest set aside
            if why == REASON_FOLLOW_UP then
                ok = not (ruledOut(crumb, D, questID) or repFails(D.minRep[crumb], true)
                          or repFails(D.maxRep[crumb], false) or skillFails(D.skill[crumb]))
            end
            if ok then out[#out + 1] = crumb end
        end
    end
    return out
end

local _warned, _skipped = {}, {}

-- One line per breadcrumb title, as a follow-up's breadcrumbs are often one quest offered by several givers
function M:WarnSkipped(questID)
    local DB = ns:GetSubsystem("DB")
    local general = DB and DB.db.profile.general
    if (general and general.warnSkippedBreadcrumbs == false) or type(questID) ~= "number" or _warned[questID] then return end
    if #self:SkippedBreadcrumbs(questID, _skipped) == 0 then return end
    _warned[questID] = true
    local QL = ns:GetSubsystem("QuestLink")
    local function named(id) return (QL and QL.Link and QL:Link(id)) or self:Title(id) end
    local said = {}
    for i = 1, #_skipped do
        local title = self:Title(_skipped[i])
        if not said[title] then
            said[title] = true
            print(ns.L["|cffEBB706EQ|r: by accepting %s, you skipped its breadcrumb quest %s, which is no longer offered."]
                :format(named(questID), named(_skipped[i])))
        end
    end
end

-- Race and class alone, the two gates no amount of play changes. Nil when the character cannot be read
function M:CanEverTake(questID)
    local D = data()
    local gates = D and questID and D.gates[questID]
    if not gates then return nil end
    if not ((_raceBit or _raceEveryOf) and _classBit) then readPlayer() end
    if not ((_raceBit or _raceEveryOf) and _classBit) then return nil end
    return raceAllows(math.floor(gates % 1e8 / 1e4)) and hasBit(gates % 1e4, _classBit)
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
                if not hostileGiver(D, kind, src) then
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

local _resetTimer

local function repaint()
    local P = ns:GetSubsystem("MapPOIProvider")
    if P and P.provider and P.provider.RefreshAllData then P.provider:RefreshAllData() end
    local MM = ns:GetSubsystem("MinimapQuestPins")
    if MM and MM.Rebuild then MM:Rebuild() end
end

-- One timer, at the soonest reset a recorded daily waits for, so its "!" comes back without a reload
local function scheduleReset()
    if _resetTimer then _resetTimer:Cancel(); _resetTimer = nil end
    local store, now, soonest = dailyStore(), serverNow(), nil
    if not (store and now and C_Timer and C_Timer.NewTimer) then return end
    for _, at in pairs(store) do
        if at > now and (not soonest or at < soonest) then soonest = at end
    end
    if not soonest then return end
    _resetTimer = C_Timer.NewTimer(soonest - now + 1, function()
        _resetTimer = nil
        M:Invalidate()
        repaint()
        scheduleReset()
    end)
end

function M:RecordDaily(questID)
    local D = data()
    if not (D and D.daily and questID and D.daily[questID]) then return false end
    local s, store, now = secondsToReset(), dailyStore(), serverNow()
    if not (s and store and now) then return false end
    store[questID] = now + s
    scheduleReset()
    return true
end

function M:IsHidden(questID)
    local store = hiddenStore()
    return store ~= nil and questID ~= nil and store[questID] == true
end

function M:SetHidden(questID, on)
    local store = hiddenStore()
    if not (store and type(questID) == "number") then return false end
    store[questID] = on and true or nil
    M:Invalidate()
    repaint()
    local QB = ns:GetSubsystem("QuestBrowser")
    if QB and QB.Refresh then QB:Refresh() end
    return true
end

function M:HiddenCount()
    local n = 0
    for _ in pairs(hiddenStore() or {}) do n = n + 1 end
    return n
end

-- For /eqsprobe available: the dailies held back now, the client's reset answer and the season's invasion
function M:DailyState()
    local store, now, n = dailyStore(), serverNow(), 0
    for _, at in pairs(now and store or {}) do
        if at > now then n = n + 1 end
    end
    return n, secondsToReset(), invasionRunning()
end

function M:OnEnable()
    local D = data()
    if not D then return end
    local Events = ns:GetSubsystem("Events")

    local function invalidate() M:Invalidate() end
    -- QUEST_LOG_UPDATE is the only event for a quest failing in place, and it brings a cold login's log
    Events:On("QUEST_LOG_UPDATE",     invalidate)
    Events:On("QUEST_ACCEPTED", function(_, a, b)
        invalidate()
        -- Era and TBC pass the log index first, Forever the id alone. Half a second later, so the line follows the game's own accept message
        local questID = b or a
        C_Timer.After(0.5, function() M:WarnSkipped(questID) end)
    end)
    Events:On("QUEST_REMOVED",        invalidate)
    Events:On("QUEST_TURNED_IN", function(_, questID)
        M:RecordDaily(questID)
        invalidate()
    end)
    Events:On("PLAYER_LEVEL_UP",      invalidate)
    -- In case UnitLevel still reads the old level while PLAYER_LEVEL_UP is handled
    Events:On("PLAYER_LEVEL_CHANGED", invalidate)
    Events:On("PLAYER_ENTERING_WORLD", invalidate)
    Events:On("SKILL_LINES_CHANGED",  invalidate)
    Events:On("UPDATE_FACTION",       invalidate)
    if D.daily and next(D.daily) then scheduleReset() end
end
