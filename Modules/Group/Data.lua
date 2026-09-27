local _, ns = ...

local Data = ns:RegisterSubsystem("GroupData", {})

-- [questID][playerName] = { { typeChar =, fulfilled =, required =, finished = }, ... }
local byQuest = {}

-- [playerName] = { class = "WARRIOR" or nil, quests = { [questID] = true }, at = caller's clock }
local players = {}

local function playerRecord(name)
    local p = players[name]
    if not p then
        p = { quests = {} }
        players[name] = p
    end
    return p
end

local function detach(name, questID)
    local holders = byQuest[questID]
    if not holders then return end
    holders[name] = nil
    if next(holders) == nil then byQuest[questID] = nil end
end

Data.revision = 0

function Data:Touch()
    self.revision = self.revision + 1
    return self.revision
end

function Data:Wipe()
    wipe(byQuest)
    wipe(players)
    self:Touch()
end

function Data:HasAnything()
    return next(players) ~= nil
end

function Data:DropPlayer(name)
    local p = players[name]
    if not p then return false end
    for questID in pairs(p.quests) do detach(name, questID) end
    players[name] = nil
    self:Touch()
    return true
end

function Data:Class(name)
    local p = players[name]
    return p and p.class
end

function Data:SetClass(name, class)
    if type(class) ~= "string" or class == "" then return end
    local p = playerRecord(name)
    if p.class == class then return end
    p.class = class
    self:Touch()
end

local function validObjectives(objectives)
    if type(objectives) ~= "table" then return false end
    for index, o in pairs(objectives) do
        if type(index) ~= "number" or type(o) ~= "table" then return false end
        if type(o.fulfilled) ~= "number" or type(o.required) ~= "number" then return false end
    end
    return true
end

function Data:SetQuest(name, questID, objectives, now)
    if type(name) ~= "string" or name == "" then return false end
    if type(questID) ~= "number" or questID <= 0 then return false end
    if not validObjectives(objectives) then return false end

    local p = playerRecord(name)
    p.quests[questID] = true
    p.at = now

    local holders = byQuest[questID]
    if not holders then holders = {}; byQuest[questID] = holders end
    holders[name] = objectives
    self:Touch()
    return true
end

function Data:RemoveQuest(name, questID)
    local p = players[name]
    if not p or not p.quests[questID] then return false end
    p.quests[questID] = nil
    detach(name, questID)
    self:Touch()
    return true
end

-- A REUSED array whose objectives are the live store. Copy before keeping or changing either.
local _forQuest = {}

function Data:ForQuest(questID)
    wipe(_forQuest)
    local holders = byQuest[questID]
    if not holders then return _forQuest end

    local n = 0
    for name, objectives in pairs(holders) do
        n = n + 1
        _forQuest[n] = { name = name, class = self:Class(name), objectives = objectives }
    end
    table.sort(_forQuest, function(a, b) return a.name < b.name end)
    return _forQuest
end

function Data:CountForQuest(questID)
    local holders = byQuest[questID]
    if not holders then return 0 end
    local n = 0
    for _ in pairs(holders) do n = n + 1 end
    return n
end

function Data:KnowsQuest(questID)
    return byQuest[questID] ~= nil
end

-- A REUSED array, like ForQuest's.
local _questIDs = {}

function Data:Quests()
    wipe(_questIDs)
    local n = 0
    for questID in pairs(byQuest) do n = n + 1; _questIDs[n] = questID end
    table.sort(_questIDs)
    return _questIDs, n
end

local _progress, _rows, _indices = {}, {}, {}

-- Another quest addon omits objectives its database lacks, and a gap in the indices shifts every later slot
local function pickObjectives(objectives, typeChar, slots, into)
    wipe(_indices)
    for index in pairs(objectives) do _indices[#_indices + 1] = index end
    table.sort(_indices)
    if typeChar and slots and _indices[#_indices] == #_indices then
        local seen = 0
        for k = 1, #_indices do
            local o = objectives[_indices[k]]
            if o.typeChar == typeChar then
                if slots[seen] then into[#into + 1] = o end
                seen = seen + 1
            end
        end
        if #into > 0 then return end
    end
    for k = 1, #_indices do into[#into + 1] = objectives[_indices[k]] end
end

local function byName(a, b) return a.name < b.name end

-- A REUSED array of reused rows, rewritten by the next call. Picked objectives are the store's own
function Data:Progress(questID, typeChar, slots)
    local n = 0
    local holders = byQuest[questID]
    if holders then
        for name, objectives in pairs(holders) do
            n = n + 1
            local row = _rows[n]
            if not row then row = { picked = {} }; _rows[n] = row end
            wipe(row.picked)
            row.name, row.class = name, self:Class(name)
            pickObjectives(objectives, typeChar, slots, row.picked)
            local all, done = 0, true
            for _, o in pairs(objectives) do
                all = all + 1
                if not o.finished then done = false end
            end
            -- Nothing to judge by for a quest with no objectives, such as a delivery
            row.allDone = all > 0 and done
            _progress[n] = row
        end
    end
    for i = #_progress, n + 1, -1 do _progress[i] = nil end
    table.sort(_progress, byName)
    return _progress, n
end

function Data:PlayerNames()
    local names = {}
    local n = 0
    for name in pairs(players) do n = n + 1; names[n] = name end
    table.sort(names)
    return names
end

local function inGroup(name)
    if IsInRaid() then
        -- Nil for anyone who left. A nil for your own slot is taken as an unreadable roster.
        if UnitInRaid("player") == nil then return true end
        return UnitInRaid(name) ~= nil
    end
    return UnitInParty(name) and true or false
end

local function isOnline(name)
    if type(UnitIsConnected) ~= "function" then return true end
    return UnitIsConnected(name) and true or false
end

local function defaultRoster()
    return {
        size     = GetNumGroupMembers(),
        inGroup  = inGroup,
        isOnline = isOnline,
    }
end

-- Injected so the harness drives a whole group without a client.
Data.Roster = defaultRoster

function Data:Prune(roster)
    roster = roster or self.Roster()
    local dropped = 0
    for _, name in ipairs(self:PlayerNames()) do
        if not roster.inGroup(name) then
            if self:DropPlayer(name) then dropped = dropped + 1 end
        end
    end
    return dropped
end

local lastSize = 0
local wasOnline = {}

-- The roster event fires on zone crossings too, so only size and held players' online state count.
function Data:RosterChanged(roster)
    roster = roster or self.Roster()

    local changed = roster.size ~= lastSize
    lastSize = roster.size

    local current = {}
    for _, name in ipairs(self:PlayerNames()) do
        local online = roster.isOnline(name) and true or false
        current[name] = online
        if wasOnline[name] ~= online then changed = true end
    end
    for name in pairs(wasOnline) do
        if current[name] == nil then changed = true end
    end
    wasOnline = current

    return changed
end

function Data:ResetRosterSnapshot()
    lastSize = 0
    wasOnline = {}
end
