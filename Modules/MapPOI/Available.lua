local _, ns = ...

local M = ns:RegisterSubsystem("AvailableQuests", {})

-- Everything here is gated on the generated table's own presence, never a build number. Only the
-- flavor TOCs list it, so on retail this answers nothing and Blizzard's own available markers are
-- left to do the job they already do there.
local function data()
    return ns.CLASSIC_QUEST_AVAILABLE
end

-- Bit index i, zero based, is race id i+1 and class id i+1. Tested by modulo rather than by the
-- bit library, which the offline harness's interpreter does not have.
local function hasBit(mask, flag)
    if not mask or mask == 0 then return true end
    if not flag then return false end
    return (mask % (flag + flag)) >= flag
end

-- The third return of UnitRace and UnitClass is the numeric id, but a token fallback is kept
-- because the feature is meaningless without one - a wrong race bit offers the other faction's
-- quests, which is worse than showing nothing.
local RACE_BIT = {
    Human = 1, Orc = 2, Dwarf = 4, NightElf = 8, Scourge = 16,
    Tauren = 32, Gnome = 64, Troll = 128, Goblin = 256, BloodElf = 512, Draenei = 1024,
}
local CLASS_BIT = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16, DEATHKNIGHT = 32,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, MONK = 512, DRUID = 1024,
}

local _level, _raceBit, _classBit

local function readPlayer()
    _level = UnitLevel and UnitLevel("player") or 0

    local _, raceToken, raceID = UnitRace("player")
    if type(raceID) == "number" and raceID > 0 and raceID < 32 then
        _raceBit = 2 ^ (raceID - 1)
    else
        _raceBit = RACE_BIT[raceToken or ""]
    end

    local _, classToken, classID = UnitClass("player")
    if type(classID) == "number" and classID > 0 and classID < 32 then
        _classBit = 2 ^ (classID - 1)
    else
        _classBit = CLASS_BIT[classToken or ""]
    end
end

-- Read by /eqsprobe. Which gates ran and which could not is the difference between "this quest is
-- filtered out" and "this gate never fired", and the two look identical on the map.
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

-- A quest in the log is not on offer, with one exception that is easy to miss: a FAILED quest can
-- be taken again, so its giver should still be marked.
local function logState(questID)
    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache.quests and Cache.quests[questID]
    if not q then return false, false end
    return true, q.isFailed and true or false
end

-- Race and class never change for a character, so a rejection for either is safe to remember.
local _permaNo = {}

local SF_REPEATABLE, SF_EVENT = 1, 2

-- Blizzard's own grey threshold, so "low level" here means exactly what the client means by it.
-- Absent means the filter cannot judge and every quest is shown, which is the same fail-open rule
-- the objective mask uses - hiding on missing data empties the map and reads as a broken feature.
local function trivialFloor()
    if type(_G.GetQuestGreenRange) ~= "function" then return nil end
    local ok, range = pcall(_G.GetQuestGreenRange, "player")
    if not (ok and type(range) == "number") then
        -- Older builds take no unit argument
        ok, range = pcall(_G.GetQuestGreenRange)
        if not ok then return nil end
    end
    if type(range) ~= "number" then return nil end
    return _level - range
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

-- A gate that cannot be evaluated shows the quest - a missing pin is a silent failure, a surplus
-- one is visible.
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

-- Category bits, matching Data/QuestCategory_Classic.lua. The event bit is deliberately not read
-- here: a holiday quest is already refused outright further down, because nothing in the data
-- says whether the holiday is running.
local CAT_INSTANCE, CAT_REPEATABLE, CAT_PROFESSION = 1, 2, 16

-- Each entry is a filter the user can switch on to REMOVE that category, so nil reads as "show
-- it" and a profile that predates these options is unchanged.
local CATEGORY_FILTERS = {
    { bit = CAT_INSTANCE,   key = "hideDungeonQuests",    reason = "dungeon or raid quest" },
    { bit = CAT_REPEATABLE, key = "hideRepeatableQuests", reason = "repeatable quest" },
    { bit = CAT_PROFESSION, key = "hideProfessionQuests", reason = "profession quest" },
}

-- Rebuilt per pass rather than read per quest, so a settings lookup does not happen 3,794 times.
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

-- Answers the REASON so the caller can count it, because /eqsprobe available proves itself by
-- every rejection summing to the number considered. A gate that returns a bare false leaks.
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
    if _permaNo[questID] then countReason("race or class") return false end

    local gates = D.gates[questID]
    if not gates then return false end

    local hiddenBy = categoryHidden(questID)
    if hiddenBy then countReason(hiddenBy) return false end

    local flags = math.floor(gates % 1e9 / 1e8)
    local repeatable = (flags % (SF_REPEATABLE + SF_REPEATABLE)) >= SF_REPEATABLE

    -- A repeatable quest comes back after it is completed, so completion only rules out the rest
    if isCompleted(questID) and not repeatable then countReason("completed") return false end

    local inLog, failed = logState(questID)
    if inLog and not failed then countReason("in your quest log") return false end

    -- Nothing in the base data says whether a world event is running, and a holiday quest pinned
    -- year round is a confident lie. Hidden outright, which costs the pin during the holiday.
    if (flags % (SF_EVENT + SF_EVENT)) >= SF_EVENT then countReason("holiday quest") return false end

    local races = math.floor(gates % 1e8 / 1e4)
    if not hasBit(races, _raceBit) then
        _permaNo[questID] = true
        countReason("race or class")
        return false
    end
    local classes = gates % 1e4
    if not hasBit(classes, _classBit) then
        _permaNo[questID] = true
        countReason("race or class")
        return false
    end
    M._gatesRun.raceClass = true

    local reqLevel = math.floor(gates / 1e11)
    if reqLevel > 0 and _level < reqLevel then countReason("too low level") return false end

    if hideLowLevel and floor then
        local questLevel = math.floor(gates % 1e11 / 1e9)
        if questLevel > 0 and questLevel < floor then countReason("low level") return false end
    end

    local pre = D.pre[questID]
    if pre then
        if not anyCompleted(pre) then countReason("prerequisite") return false end
    else
        local preAll = D.preAll[questID]
        if preAll and not allCompleted(preAll) then countReason("prerequisite") return false end
    end

    -- The parent has to be ACTIVE, not merely done - these are the steps of an escort or a
    -- multi-part quest that only exist while you are on it.
    local parent = D.parent[questID]
    if parent then
        local parentInLog = logState(parent)
        if not parentInLog then countReason("prerequisite") return false end
    end

    local nextID = D.chain[questID]
    if nextID then
        local nextInLog = logState(nextID)
        if nextInLog or isCompleted(nextID) then countReason("later step done") return false end
    end

    local excl = D.excl[questID]
    if excl then
        for i = 1, #excl do
            local other = excl[i]
            local otherInLog = logState(other)
            if otherInLog or isCompleted(other) then countReason("took another branch") return false end
        end
    end

    if repFails(D.minRep[questID], true) then countReason("reputation") return false end
    if repFails(D.maxRep[questID], false) then countReason("reputation") return false end

    return true
end

local _available = {}
local _built = false

function M:Invalidate()
    _built = false
end

function M:Rebuild()
    wipe(_available)
    wipe(M._reason)
    -- Wiped with the rest, or a pass that returned early keeps reporting the gates an EARLIER
    -- pass ran, which is the one thing this counter exists to tell apart.
    wipe(M._gatesRun)
    M._resolved, M._availableN = 0, 0
    _built = true

    local D = data()
    if not D then M._stage = "no data table on this flavor" return end

    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db.profile.map
    if map and map.showAvailableQuests == false then
        M._stage = "off in options"
        return
    end

    refreshCategoryMask()

    -- Forces the cache's own refresh once, up front. logState reads Cache.quests directly below,
    -- which skips that refresh, so without this a cold login reads an empty log and every quest
    -- already in it is offered again.
    local Cache = ns:GetSubsystem("Cache")
    if Cache and Cache.All then Cache:All() end

    readPlayer()
    if not (_raceBit and _classBit) then
        M._stage = "player race or class did not resolve"
        return
    end
    readCompleted()
    -- Set here rather than inside the loop, so it means "the masks were readable" rather than
    -- "at least one quest survived them" - the second says nothing on a pass that rejected all.
    M._gatesRun.raceClass = true

    -- Compared against false, not tested for truthiness, so a profile written before this option
    -- existed reads as ON, which is what the checkbox shows for the same nil.
    local hideLowLevel = not (map and map.hideLowLevelQuests == false)
    local floor = hideLowLevel and trivialFloor() or nil
    M._gatesRun.trivial = (floor ~= nil)

    for questID in pairs(D.gates) do
        M._resolved = M._resolved + 1
        if isAvailable(questID, D, hideLowLevel, floor) then
            _available[questID] = true
            M._availableN = M._availableN + 1
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

-- The cap bounds points per quest, where the worst item started quest offers 1,161 on one map.
-- Locations merge below because one giver can offer 27 quests and a pin each would stack them.
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
            -- Stored densest first, so walking in order is what makes a low cap keep the best
            -- locations rather than arbitrary ones. Never reorder here.
            for i = 1, #list do
                if taken >= MAX_PER_QUEST then break end
                local v = list[i]
                local kind = math.floor(v / 1e8)
                local rest = v % 1e8
                local key = rest
                local slot = _byCoord[key]
                if not slot then
                    slot = { x = math.floor(rest / 1e4) / 1e4, y = (rest % 1e4) / 1e4,
                             kind = kind, quests = {} }
                    _byCoord[key] = slot
                    _order[#_order + 1] = key
                elseif kind < slot.kind then
                    -- An NPC who offers a quest outranks the same spot merely dropping a starter
                    slot.kind = kind
                end
                slot.quests[#slot.quests + 1] = questID
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
        -- Rides on the quest list because that table is what travels to the pin and on to the
        -- tooltip. A named key leaves the array border alone, so #quests is still the count.
        slot.quests.startKind = slot.kind
    end
    self._locN = n
    return n
end

function M:OnEnable()
    if not data() then return end
    local Events = ns:GetSubsystem("Events")

    local function invalidate() M:Invalidate() end
    -- QUEST_LOG_UPDATE is the ONLY event that fires when a quest fails in place, and it is also
    -- what arrives when a cold login's quest log finally streams in. Without it a pass computed
    -- against an empty log latched for the session and drew every quest you were carrying as one
    -- you could pick up. Invalidate is a single flag write, and the sweep it schedules is lazy.
    Events:On("QUEST_LOG_UPDATE",     invalidate)
    Events:On("QUEST_ACCEPTED",       invalidate)
    Events:On("QUEST_REMOVED",        invalidate)
    Events:On("QUEST_TURNED_IN",      invalidate)
    Events:On("PLAYER_LEVEL_UP",      invalidate)
    Events:On("PLAYER_ENTERING_WORLD", invalidate)
    Events:On("SKILL_LINES_CHANGED",  invalidate)
    Events:On("UPDATE_FACTION",       invalidate)
end
