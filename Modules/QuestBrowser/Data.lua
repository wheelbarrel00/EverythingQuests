local _, ns = ...

-- Answers the two questions the Quest Browser asks of EQ's own Classic tables: which quests match
-- what was typed, and everything known about one of them. Nothing here draws, so it can be driven
-- offline against the real shipped data.
local QB = ns:RegisterSubsystem("QuestBrowserData", {})

local function avail()
    return ns:GetSubsystem("AvailableQuests")
end

function QB:Loaded()
    local A = avail()
    return (A and A.Data and A:Data()) ~= nil
end

-- The low eight digits of every packed point in these tables are the coordinate pair. What sits
-- above them differs per table - a source kind here, an objective bitmask there - so only the
-- half that is genuinely shared is decoded in one place.
local function coords(v)
    local rest = v % 1e8
    return math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4
end

local _zoneName = {}

function QB:ZoneName(mapID)
    if not mapID then return nil end
    local cached = _zoneName[mapID]
    if cached ~= nil then return cached ~= false and cached or nil end
    local name
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            name = info.name
        end
    end
    _zoneName[mapID] = name or false
    return name
end

local RACE_TOKEN = {
    "Human", "Orc", "Dwarf", "NightElf", "Scourge", "Tauren",
    "Gnome", "Troll", "Goblin", "BloodElf", "Draenei",
}
local CLASS_TOKEN = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT",
    "SHAMAN", "MAGE", "WARLOCK", "MONK", "DRUID",
}

local function raceName(index)
    if C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local ok, info = pcall(C_CreatureInfo.GetRaceInfo, index)
        if ok and type(info) == "table" and type(info.raceName) == "string" and info.raceName ~= "" then
            return info.raceName
        end
    end
    return RACE_TOKEN[index]
end

local function className(index)
    local token = CLASS_TOKEN[index]
    if not token then return nil end
    local map = _G.LOCALIZED_CLASS_NAMES_MALE
    if type(map) == "table" and type(map[token]) == "string" and map[token] ~= "" then
        return map[token]
    end
    return token
end

-- A mask of zero is no gate at all rather than "no races allowed", which is why it returns nil
-- and the caller renders nothing instead of an empty list.
local function maskNames(mask, namer, count)
    if not mask or mask == 0 then return nil end
    local out
    for i = 1, count do
        local bit = 2 ^ (i - 1)
        if (mask % (bit + bit)) >= bit then
            local name = namer(i)
            if name then
                out = out or {}
                out[#out + 1] = name
            end
        end
    end
    return out
end

-- Blizzard's own reputation bar boundaries. The generator clamps a negative requirement to zero,
-- so only the standings from Neutral upward can ever be stored.
local STANDING_FLOOR = { 0, 3000, 9000, 21000, 42000 }
local STANDING_LABEL = { 4, 5, 6, 7, 8 }

local function labelAt(i)
    local label = _G["FACTION_STANDING_LABEL" .. STANDING_LABEL[i]]
    return type(label) == "string" and label or nil
end

-- The tier the stored value sits in. Right for a MINIMUM gate, where the stored number is the
-- first value that qualifies.
local function standingName(value)
    local pick = 1
    for i = 1, #STANDING_FLOOR do
        if value >= STANDING_FLOOR[i] then pick = i end
    end
    return labelAt(pick)
end

-- The first tier that is shut out. A MAXIMUM gate stores the LAST value that still qualifies,
-- so naming the tier it sits in excludes the very tier that can take the quest - quest 9221
-- stores 8999 and is open to Friendly, but reads as "only below Friendly" through standingName.
local function standingCeilName(value)
    for i = 1, #STANDING_FLOOR do
        if value < STANDING_FLOOR[i] then return labelAt(i) end
    end
    return nil
end

local function factionName(factionID)
    if type(_G.GetFactionInfoByID) == "function" then
        local ok, name = pcall(_G.GetFactionInfoByID, factionID)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, info = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return nil
end

-- 4 is the event bit, deliberately not taken: it is built from the same flag as
-- IsExplorationOrScripted and names escorts rather than holidays.
local CAT_INSTANCE, CAT_REPEATABLE, CAT_CLASS, CAT_PROFESSION = 1, 2, 8, 16

local function hasCat(mask, bit)
    if not mask then return false end
    return math.floor(mask / bit) % 2 == 1
end

-- The shipped English title, which is the only complete set. QUERIES run against this because the
-- client can only name a quest it has already seen, which is never true of the unaccepted ones
-- this window exists for. Display goes through A:Title so a known quest still shows in the
-- player's own language.
local function storedName(D, questID)
    return D.names[questID]
end

local function displayName(A, questID)
    return A:Title(questID)
end

local function questLevelOf(A, questID)
    return A:QuestLevel(questID) or A:RequiredLevel(questID) or 0
end

-- Rows are pooled rather than rebuilt. A query with no text walks every quest the table names,
-- and this runs on a debounced keystroke, so allocating a fresh table per match would churn a few
-- hundred kilobytes per letter typed.
local _rows, _rowPool = {}, {}

local function recycleRows()
    for i = #_rows, 1, -1 do
        _rowPool[#_rowPool + 1] = _rows[i]
        _rows[i] = nil
    end
end

local function takeRow()
    local r = table.remove(_rowPool)
    if not r then return {} end
    r.name = nil
    return r
end

-- Sorted on the STORED title, never the displayed one. The displayed title is only resolved for
-- the rows that survive the limit, so it does not exist yet at this point.
local function sortRows(a, b)
    if a.level ~= b.level then return a.level < b.level end
    if a.sortName ~= b.sortName then return a.sortName < b.sortName end
    return a.id < b.id
end

-- A quoted query matches the whole title rather than any part of it, which is what separates a
-- short name from every longer title containing it. It does NOT narrow to one quest: 408 Era
-- titles are shared by more than one quest and "The Missing Diplomat" alone covers 17.
local function parseText(text)
    if type(text) ~= "string" then return nil, nil, nil end
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, nil, nil end
    local quoted = text:match('^"(.*)"$')
    if quoted then return quoted:lower(), true, nil end
    return text:lower(), false, tonumber(text)
end

function QB:Query(opts)
    opts = opts or {}
    local A = avail()
    local D = A and A.Data and A:Data()
    recycleRows()
    if not D then return _rows, 0 end

    local needle, exact, asID = parseText(opts.text)
    local scope = opts.scope or "all"
    local mapID = opts.mapID

    local matched = 0
    for questID, stored in pairs(D.names) do
        local keep = true

        if mapID then
            local byMap = D.start[questID]
            keep = (byMap and byMap[mapID]) ~= nil
        end

        if keep and needle then
            if exact then
                keep = stored:lower() == needle
            else
                keep = questID == asID or stored:lower():find(needle, 1, true) ~= nil
            end
        end

        if keep and scope ~= "all" then
            if scope == "available" then
                -- Explain, never IsAvailable. IsAvailable reads the map pass's result set, which
                -- is empty whenever the map option is off, so this list would come up empty while
                -- the detail pane beside it called the same quests available.
                keep = A:Explain(questID) == true
            elseif scope == "completed" then
                keep = A:IsCompleted(questID)
            elseif scope == "log" then
                keep = A:InLog(questID)
            end
        end

        if keep then
            matched = matched + 1
            local row = takeRow()
            row.id, row.sortName, row.level = questID, stored, questLevelOf(A, questID)
            _rows[matched] = row
        end
    end

    table.sort(_rows, sortRows)

    local limit = opts.limit
    if limit and matched > limit then
        for i = matched, limit + 1, -1 do
            _rowPool[#_rowPool + 1] = _rows[i]
            _rows[i] = nil
        end
    end

    -- The display title asks the client, which can only answer for a quest it has already seen.
    -- Resolved here rather than during the scan so a search matching thousands of quests costs
    -- one client call per VISIBLE row instead of one per match.
    for i = 1, #_rows do
        _rows[i].name = displayName(A, _rows[i].id)
    end
    return _rows, matched
end

-- withSource is passed explicitly and never inferred. This is shared by the TURN IN table, whose
-- 1e9 slot holds the creature or object that takes the quest, and by the OBJECTIVE spawn table,
-- whose 1e9 slot holds the objective BITMASK. Decoding the second as a source would hand a mask
-- to the name lookup and answer with whatever creature happens to carry that id.
local function pointList(byMap, out, withSource)
    if not byMap then return nil end
    for mapID, list in pairs(byMap) do
        local x, y = coords(list[1])
        local name
        if withSource then
            -- Every distinct one, for the same reason the start rows list every giver
            local names, seen = {}, {}
            for i = 1, #list do
                local v = list[i]
                local nm = ns.Compat.SourceName(math.floor(v / 1e8) % 10, math.floor(v / 1e9))
                if nm and not seen[nm] then seen[nm] = true; names[#names + 1] = nm end
            end
            name = (#names > 0) and table.concat(names, " / ") or nil
        end
        out[#out + 1] = { mapID = mapID, x = x, y = y, points = #list, name = name }
    end
    if #out == 0 then return nil end
    table.sort(out, function(a, b) return a.mapID < b.mapID end)
    return out
end

-- known says whether the table can actually describe this quest. 126 of the 4,309 chain
-- references on Era point at quests the data does not carry, and the caller has to render those
-- as plain text - a live link to a quest with no record blanks the whole pane.
local function questRefs(ids, A, out)
    if not ids then return nil end
    local D = A:Data()
    for i = 1, #ids do
        local id = ids[i]
        out[#out + 1] = {
            id    = id,
            name  = A:Title(id),
            done  = A:IsCompleted(id),
            known = (D and D.gates[id]) ~= nil,
        }
    end
    return out
end

function QB:Record(questID)
    local A = avail()
    local D = A and A.Data and A:Data()
    if not (D and questID and D.gates[questID]) then return nil end

    local r = {
        id       = questID,
        name     = displayName(A, questID),
        stored   = storedName(D, questID),
        level    = A:QuestLevel(questID),
        reqLevel = A:RequiredLevel(questID),
    }

    local ok, why = A:Explain(questID)
    r.available, r.reason = ok, why
    r.completed = A:IsCompleted(questID)
    r.inLog, r.failed = A:InLog(questID)

    r.races   = maskNames(A:RaceMask(questID),  raceName,  #RACE_TOKEN)
    r.classes = maskNames(A:ClassMask(questID), className, #CLASS_TOKEN)

    local cats = ns.CLASSIC_QUEST_CATEGORY and ns.CLASSIC_QUEST_CATEGORY[questID]
    r.isInstance   = hasCat(cats, CAT_INSTANCE)
    r.isRepeatable = hasCat(cats, CAT_REPEATABLE) or A:IsRepeatable(questID)
    -- NOT CAT_EVENT, which is built from the same flag as IsExplorationOrScripted and so
    -- names escorts rather than holidays. The holiday table is what actually knows.
    local hol = ns.CLASSIC_QUEST_HOLIDAY
    r.isEvent      = (hol and hol.event and hol.event[questID]) ~= nil
    r.isClassQuest = hasCat(cats, CAT_CLASS)
    r.isProfession = hasCat(cats, CAT_PROFESSION)

    local starts = {}
    if A:StartsFor(questID, starts) > 0 then
        -- Merged to one row per map. A giver standing next to another is two points and one place
        -- as far as a reader is concerned.
        local byMap, order = {}, {}
        for i = 1, #starts do
            local s = starts[i]
            local slot = byMap[s.mapID]
            if not slot then
                slot = { mapID = s.mapID, x = s.x, y = s.y, kind = s.kind,
                         names = {}, seen = {}, points = 0 }
                byMap[s.mapID] = slot
                order[#order + 1] = slot
            elseif s.kind < slot.kind then
                slot.kind, slot.x, slot.y = s.kind, s.x, s.y
            end
            -- EVERY distinct giver on this map, because a row is merged per MAP while a map pin
            -- is merged per COORDINATE. 25 Classic and 36 TBC rows cover more than one person -
            -- quest 109 in Elwynn is offered by three - and naming only the first states
            -- something false about the other locations. Each name was resolved against its own
            -- point's kind in StartsFor, so accumulating them here cannot cross the id spaces.
            if s.name and not slot.seen[s.name] then
                slot.seen[s.name] = true
                slot.names[#slot.names + 1] = s.name
            end
            slot.points = slot.points + 1
        end
        for i = 1, #order do
            local slot = order[i]
            slot.name = (#slot.names > 0) and table.concat(slot.names, " / ") or nil
            slot.names, slot.seen = nil, nil
        end
        table.sort(order, function(a, b) return a.mapID < b.mapID end)
        r.starts = order
    end

    local spawns = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    r.objectives = pointList(spawns and spawns[questID], {}, false)
    r.turnIn     = pointList(ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID], {}, true)

    -- preQuestSingle is ANY of, and is consulted INSTEAD of preQuestGroup rather than alongside
    -- it, which is the semantic the availability gate already follows.
    if D.pre[questID] then
        r.pre, r.preMode = questRefs(D.pre[questID], A, {}), "any"
    elseif D.preAll[questID] then
        r.pre, r.preMode = questRefs(D.preAll[questID], A, {}), "all"
    end
    r.excl = questRefs(D.excl[questID], A, {})

    local nextID = D.chain[questID]
    if nextID then r.chain = { id = nextID, name = A:Title(nextID), done = A:IsCompleted(nextID) } end
    local parentID = D.parent[questID]
    if parentID then r.parent = { id = parentID, name = A:Title(parentID), done = A:IsCompleted(parentID) } end

    local skillLine, skillValue = A:SkillGate(questID)
    if skillLine then r.skill = { line = skillLine, value = skillValue } end

    for _, which in ipairs({ "min", "max" }) do
        local faction, value = A:RepGate(questID, which)
        if faction then
            local entry = {
                faction  = faction,
                name     = factionName(faction),
                value    = value,
                standing = (which == "max") and standingCeilName(value) or standingName(value),
            }
            if which == "min" then r.minRep = entry else r.maxRep = entry end
        end
    end

    return r
end

-- Where an arrow should point for this quest. A finished one wants its finisher, and anything
-- else wants a place it can be picked up, which is the whole point of browsing an unaccepted one.
function QB:Waypoint(record)
    if not record then return nil end
    if record.inLog then
        local Arrow = ns:GetSubsystem("QuestArrow")
        if Arrow and Arrow.PointAtQuest then return "quest" end
    end
    local first = record.starts and record.starts[1]
    if first then return "start", first.mapID, first.x, first.y end
    local turn = record.turnIn and record.turnIn[1]
    if turn then return "turnin", turn.mapID, turn.x, turn.y end
    return nil
end
