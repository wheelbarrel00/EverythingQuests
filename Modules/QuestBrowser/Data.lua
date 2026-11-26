local _, ns = ...

-- Answers the Quest Browser from EQ's own Classic tables: what matches a search, all about one quest, and every quest by
-- zone. Nothing here draws, so it runs offline against the shipped data.
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

local function hasBit(mask, i)
    local bit = 2 ^ (i - 1)
    return (mask % (bit + bit)) >= bit
end

-- A zero mask is no gate rather than "no races allowed", so it adds no names
local function maskNames(mask, namer, count, out)
    if not mask or mask == 0 then return out end
    for i = 1, count do
        if hasBit(mask, i) then
            local name = namer(i)
            if name then
                out = out or {}
                out[#out + 1] = name
            end
        end
    end
    return out
end

local FACTION_RACES = {
    { label = "FACTION_ALLIANCE", races = { 1, 3, 4, 7, 11 } },
    { label = "FACTION_HORDE",    races = { 2, 5, 6, 8, 9, 10 } },
}

local _factionData, _factionMasks

-- Only races the loaded data names somewhere count, so 77 is the whole Alliance on Era and not on TBC
local function factionMasks(A, D)
    if _factionData == D then return _factionMasks end
    local present = {}
    for questID in pairs(D.gates) do
        local mask = A:RaceMask(questID)
        if mask and mask > 0 then
            for i = 1, #RACE_TOKEN do
                if hasBit(mask, i) then present[i] = true end
            end
        end
    end
    local masks = {}
    for f = 1, #FACTION_RACES do
        local races, sum = FACTION_RACES[f].races, 0
        for k = 1, #races do
            local i = races[k]
            if present[i] then sum = sum + 2 ^ (i - 1) end
        end
        masks[f] = sum
    end
    _factionData, _factionMasks = D, masks
    return masks
end

local function containsMask(mask, part)
    for i = 1, #RACE_TOKEN do
        if hasBit(part, i) and not hasBit(mask, i) then return false end
    end
    return true
end

local function raceNames(A, D, mask)
    if not mask or mask == 0 then return nil end
    local masks = factionMasks(A, D)
    local out
    for f = 1, #FACTION_RACES do
        local label = _G[FACTION_RACES[f].label]
        local whole = masks[f]
        if whole > 0 and type(label) == "string" and label ~= "" and containsMask(mask, whole) then
            out = out or {}
            out[#out + 1] = label
            mask = mask - whole
        end
    end
    return maskNames(mask, raceName, #RACE_TOKEN, out)
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

        if mapID then keep = A:StartsOnMap(questID, mapID) end

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
            elseif scope == "hidden" then
                keep = A:IsHidden(questID)
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
        maxLevel = A:MaxLevel(questID),
    }

    local ok, why = A:Explain(questID)
    r.available, r.reason = ok, why
    r.completed = A:IsCompleted(questID)
    r.inLog, r.failed = A:InLog(questID)

    r.races   = raceNames(A, D, A:RaceMask(questID))
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
    local leads = A:LeadsTo(questID)
    r.isBreadcrumb = leads ~= nil
    -- A breadcrumb's chain link usually names one of its follow-ups, so each quest is listed once
    local ids = { nextID }
    for _, id in ipairs(leads or {}) do
        if id ~= nextID then ids[#ids + 1] = id end
    end
    if #ids > 0 then r.leadsTo = questRefs(ids, A, {}) end
    r.breadcrumbs = questRefs(A:LedBy(questID), A, {})
    local parentID = D.parent[questID]
    if parentID then r.parent = { id = parentID, name = A:Title(parentID), done = A:IsCompleted(parentID) } end

    local skillLine, skillValue = A:SkillGate(questID)
    if skillLine then r.skill = { line = skillLine, value = skillValue, name = A:SkillName(skillLine) } end

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

local function nearest(places)
    if not (places and places[1]) then return nil end
    local f = C_Map and C_Map.GetBestMapForUnit
    local ok, here = false, nil
    if f then ok, here = pcall(f, "player") end
    if ok and here then
        for _, p in ipairs(places) do
            if p.mapID == here then return p end
        end
    end
    return places[1]
end

function QB:Waypoint(record)
    if not record then return nil end
    if record.inLog then
        local Arrow = ns:GetSubsystem("QuestArrow")
        if Arrow and Arrow.PointFor then
            local m, x, y = Arrow:PointFor(record.id)
            if m then return "quest", m, x, y end
            -- A quest in your log with no spot known for what is left gets no directions, not its giver's
            return nil
        end
    end
    local first = nearest(record.starts)
    if first then return "start", first.mapID, first.x, first.y end
    local turn = nearest(record.turnIn)
    if turn then return "turnin", turn.mapID, turn.x, turn.y end
    return nil
end

-- Quests by zone. A key is a zone's map id, DUNGEON_KEY or BATTLEGROUND_KEY plus an area id, or a heading's name
QB.DUNGEON_KEY = 10000000
QB.BATTLEGROUND_KEY = 20000000

-- Shut as the data stands, or until a later step or branch in the log is dropped, so left out of a zone's count
local CLOSED = {
    ["race or class"] = true, ["above level range"] = true, ["not in the game"] = true, ["event not running"] = true,
    ["not released"] = true, ["later step done"] = true, ["took another branch"] = true, ["follow-up taken"] = true,
}
-- Shut by a choice the character made, so the quests it would have led to read as another branch, not as never open
local CHOICE = { ["later step done"] = true, ["took another branch"] = true, ["follow-up taken"] = true }
-- Shut for now, so the quests behind it say why rather than never. In an any-of list a choice outranks these, and these outrank locked
local CARRIED = { ["not released"] = true, ["reputation"] = true }
local SHUT_RANK = { ["locked"] = 1, ["not released"] = 2, ["reputation"] = 2, ["took another branch"] = 3 }

-- TBC's Battlegrounds heading in the quest log, its sort -25
local BATTLEGROUND_SORT = -25

-- Where most of the quest's start points are, the lowest map on a tie
local function startMap(D, questID)
    local byMap = D.start[questID]
    if not byMap then return nil end
    local best, most
    for mapID, list in pairs(byMap) do
        local n = #list
        if not most or n > most or (n == most and mapID < best) then best, most = mapID, n end
    end
    return best
end

local function groupOf(A, questID)
    local classes = A:ClassMask(questID)
    if classes and classes > 0 then return "class" end
    local cat = ns.CLASSIC_QUEST_CATEGORY and ns.CLASSIC_QUEST_CATEGORY[questID] or 0
    if math.floor(cat / 16) % 2 == 1 then return "profession" end
    local H = ns.CLASSIC_QUEST_HOLIDAY
    if H and H.event and H.event[questID] then return "event" end
    return nil
end

-- The log's zone or dungeon, Battlegrounds, the quest's group, Other for any other heading, else where it starts
function QB:ZoneOf(questID)
    local A = avail()
    local D = A and A.Data and A:Data()
    if not (D and questID and D.gates[questID]) then return nil end
    local v = ns.CLASSIC_QUEST_ZONE and ns.CLASSIC_QUEST_ZONE[questID]
    if v and v > 0 then return v end
    if v == BATTLEGROUND_SORT then return "battleground" end
    local group = groupOf(A, questID)
    if group then return group end
    if v then return "other" end
    return startMap(D, questID) or "other"
end

-- A quest's own status. Explain names only the first gate that fails, so a choice that shut it is asked after
local function ownStatus(A, questID)
    if A:InLog(questID) then return "log" end
    local ok, reason = A:Explain(questID, true)
    if ok == true then return "available" end
    if reason == "completed" then return "done" end
    if CLOSED[reason] then return "closed", reason end
    local gone = A:RuledOut(questID)
    if gone then return "closed", gone end
    if reason == "reputation" and A.RepTooHigh and A:RepTooHigh(questID) then return "closed", reason end
    return "notYet", reason
end

-- Kept for one build only, as a branch in the log can be dropped
local _status, _reason, _visiting = {}, {}, {}

-- A quest whose every way in is shut is shut too, as the Forever Chain Guide reads it
local function statusOf(A, D, questID)
    local s = _status[questID]
    if s then return s, _reason[questID], false end
    if _visiting[questID] then return "notYet", nil, true end
    local reason
    s, reason = ownStatus(A, questID)
    local guessed = false
    if s == "notYet" then
        _visiting[questID] = true
        local function shut(q)
            -- A way in already done is never what shuts a quest, even a repeatable that now reads closed
            if A:IsCompleted(q) then return nil end
            local qs, qr, g = statusOf(A, D, q)
            guessed = guessed or g
            if qs ~= "closed" then return nil end
            if CHOICE[qr] then return "took another branch" end
            return CARRIED[qr] and qr or "locked"
        end
        local by
        local pre = D.pre[questID]
        if pre then
            by = #pre > 0 and "locked" or nil
            for i = 1, #pre do
                local r = shut(pre[i])
                if not r then by = nil break end
                if SHUT_RANK[r] > SHUT_RANK[by] then by = r end
            end
        else
            local preAll = D.preAll[questID]
            for i = 1, preAll and #preAll or 0 do
                by = shut(preAll[i])
                if by then break end
            end
        end
        local parent = D.parent[questID]
        if not by and parent then by = shut(parent) end
        _visiting[questID] = nil
        if by then s, reason = "closed", by end
    end
    -- A quest met again inside its own loop reads open, so an open answer resting on that is not kept
    if s == "closed" or not guessed then _status[questID], _reason[questID] = s, reason end
    return s, reason, guessed and s ~= "closed"
end

-- Every quest under its key with this character's status, counting what is not closed, repeatable or daily
function QB:ZoneIndex()
    local A = avail()
    local D = A and A.Data and A:Data()
    if not D then return nil end
    wipe(_status)
    wipe(_reason)
    wipe(_visiting)
    local index = {}
    for questID, stored in pairs(D.names) do
        local key = self:ZoneOf(questID)
        -- Your class's heading lists only the quests this character can take
        if key and not (key == "class" and A:CanEverTake(questID) == false) then
            local status, reason = statusOf(A, D, questID)
            local e = index[key]
            if not e then
                e = { key = key, quests = {}, done = 0, total = 0 }
                index[key] = e
            end
            local level = questLevelOf(A, questID)
            local repeatable = A:IsRepeatable(questID) or (D.daily and D.daily[questID]) ~= nil
            e.quests[#e.quests + 1] = { id = questID, status = status, reason = reason, level = level,
                                        sortName = stored, repeatable = repeatable or nil }
            if status ~= "closed" then
                if level > 0 then
                    if not e.minLevel or level < e.minLevel then e.minLevel = level end
                    if not e.maxLevel or level > e.maxLevel then e.maxLevel = level end
                end
                if not repeatable then
                    e.total = e.total + 1
                    if status == "done" then e.done = e.done + 1 end
                end
            end
        end
    end
    for _, e in pairs(index) do table.sort(e.quests, sortRows) end
    return index
end
