-- Builds the WoW Forever supplement from the development collector's archived sessions and, with --att, AllTheThings.
--
--   lua5.1 tools/build_forever_supplement.lua <eraDir> <outDir> [--att=<AllTheThings>/db/Camelot --questv2=<QuestV2.csv>] [<session.lua> ...]
--
-- <eraDir> holds the Era dump build_questcoords.lua reads. <outDir> receives a copy of it, an area
-- table that also covers maps only Forever has, forever<Kind>DB.lua rows that build_questcoords.lua
-- lays over the Era rows, and foreverStarts.lua, where each quest itself is offered.
--
-- Only quests the Era dump does not know become rows. An Era creature, object or item that a new
-- quest uses keeps its Era row, because the dump's spawn lists are better than what one player saw.

local eraDir, outDir = ...
local attDir, questV2File
local sessionFiles = {}
for i = 3, select("#", ...) do
    local a = select(i, ...)
    local dir, csv = a:match("^%-%-att=(.+)$"), a:match("^%-%-questv2=(.+)$")
    if dir then attDir = dir elseif csv then questV2File = csv else sessionFiles[#sessionFiles + 1] = a end
end
assert(eraDir and outDir and (#sessionFiles > 0 or attDir),
       "usage: lua5.1 tools/build_forever_supplement.lua <eraDir> <outDir> [--att=<dir> --questv2=<csv>] [<session.lua> ...]")
-- ATT lists quests Forever lacks, so a quest the collector never saw must be in the client's quest table, which also drops ATT's repeatable ones.
assert(not attDir or questV2File, "--att needs --questv2=<the Forever client's QuestV2.csv>")

local BASE_PREFIX, OVERLAY_PREFIX = "classic", "forever"

-- Upstream field positions, the same ones build_questcoords.lua reads.
local Q_NAME, Q_STARTEDBY, Q_FINISHEDBY, Q_REQLEVEL, Q_QUESTLEVEL, Q_RACES = 1, 2, 3, 4, 5, 6
local Q_CLASSES, Q_OBJECTIVES, Q_PREGROUP, Q_PRESINGLE, Q_EXCLUSIVE = 7, 10, 12, 13, 16
local Q_REQSKILL, Q_MINREP, Q_MAXREP, Q_SPECIALFLAGS = 18, 19, 20, 24
local N_NAME, N_SPAWNS, N_FACTION = 1, 7, 13
local O_NAME, O_SPAWNS = 1, 4
local I_NAME, I_NPCDROPS, I_OBJDROPS = 1, 2, 3
local OBJ_OBJECT, OBJ_ITEM, OBJ_KILLCREDIT = 2, 3, 5

-- The Era masks for a whole faction. build_questcoords.lua reads them back as "A" and "H".
local RACES_ALLIANCE, RACES_HORDE = 77, 178
local FACTION_TAG = { Alliance = "A", Horde = "H" }

-- Area ids for maps the Era area table does not cover, and ids for objectives no real creature or
-- object locates. Both sit far above anything the game uses and below the 1e7 the nameplate table packs.
local SYNTH_AREA_BASE = 9000000
local PSEUDO_BASE = 9000000

-- An attribution below this share of the leading candidate is a stray kill or loot that happened
-- to land inside the collector's window, not a source of the objective.
local KEEP_SHARE = 0.5

local SEEN_PLATE, SEEN_TARGET, SEEN_KILL, SEEN_TALK = 1, 2, 4, 8

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function writeAll(path, text)
    local f = assert(io.open(path, "wb"), "cannot write " .. path)
    f:write(text)
    f:close()
end

local function exists(path)
    local f = io.open(path, "rb")
    if f then f:close() end
    return f ~= nil
end

-- Compared by a marker file rather than by path text, which a trailing slash or a case change defeats.
do
    local marker = outDir .. "/.forever-supplement-out"
    writeAll(marker, "")
    local same = exists(eraDir .. "/.forever-supplement-out")
    os.remove(marker)
    assert(not same, "<outDir> must not be <eraDir>, or the next Era build would carry Forever rows")
end

local function parseBlock(src, marker, label)
    local at = assert(src:find(marker, 1, true), "marker not found in " .. label)
    local s = src:find("return {", at, true)
    local e = src:find("}]]", s, true)
    assert(s and e, "block delimiters not found in " .. label)
    return assert(loadstring(src:sub(s, e)))()
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t or {}) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function addCounts(dst, src)
    for k, v in pairs(src or {}) do dst[k] = (dst[k] or 0) + v end
end

local function sub(t, k)
    local v = t[k]
    if not v then v = {}; t[k] = v end
    return v
end

local BASE_FILES = {
    quests  = { file = BASE_PREFIX .. "QuestDB.lua",  marker = "questData = [["  },
    npcs    = { file = BASE_PREFIX .. "NpcDB.lua",    marker = "npcData = [["    },
    objects = { file = BASE_PREFIX .. "ObjectDB.lua", marker = "objectData = [[" },
    items   = { file = BASE_PREFIX .. "ItemDB.lua",   marker = "itemData = [["   },
}

local base, raw = {}, {}
for key, spec in pairs(BASE_FILES) do
    raw[spec.file] = readAll(eraDir .. "/" .. spec.file)
    base[key] = parseBlock(raw[spec.file], spec.marker, spec.file)
end
local areaSrc = readAll(eraDir .. "/areaIdToUiMapId.lua")
local area2ui = parseBlock(areaSrc, "areaIdToUiMapId = [[", "areaIdToUiMapId.lua")
local dungeonSrc = exists(eraDir .. "/dungeonEntrances.lua") and readAll(eraDir .. "/dungeonEntrances.lua")
local dungeons = dungeonSrc and parseBlock(dungeonSrc, "dungeonEntrances = [[", "dungeonEntrances.lua") or {}

local dungeonArea = {}
for areaId, row in pairs(dungeons) do
    dungeonArea[areaId] = true
    if type(row) == "table" and row[1] and row[1] ~= false then dungeonArea[row[1]] = true end
end

local ui2area = {}
for _, areaId in ipairs(sortedKeys(area2ui)) do
    local ui = area2ui[areaId]
    if not dungeonArea[areaId] and ui2area[ui] == nil then ui2area[ui] = areaId end
end
local synthAreas = {}
local function areaFor(ui)
    local a = ui2area[ui]
    if a then return a end
    a = SYNTH_AREA_BASE + ui
    ui2area[ui], synthAreas[a] = a, ui
    return a
end

local function sessionSize(S)
    return count(S.quests) + count(S.starts) + count(S.ends) + count(S.prog) + count(S.offers)
        + count(S.units and S.units.npc) + count(S.drops) + #(S.turned or {}) + #(S.dialogs or {})
        + count(S.titles)
end

local sessions = {}
for i = 1, #sessionFiles do
    local chunk = assert(loadfile(sessionFiles[i]))
    local env = {}
    setfenv(chunk, env)
    chunk()
    for key, S in pairs(env.EQForeverCollectorDB and env.EQForeverCollectorDB.sessions or {}) do
        local have = sessions[key]
        if not have or sessionSize(S) > sessionSize(have) then sessions[key] = S end
    end
end

-- Counts add and position sets join. Names and factions keep the first reading in session key order,
-- so a rerun is byte identical, except that a quest takes the copy with the fullest objective list.
local Q, starts, ends, prog, units, drops, titles = {}, {}, {}, {}, { npc = {}, obj = {} }, {}, {}
local refusedByServer = {}

-- An uncached creature name reads as "0/8   slain", which names nothing.
local function objectiveName(txt, isMonster)
    if type(txt) ~= "string" then return nil end
    local s = txt:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
    if isMonster then s = s:gsub("%s+slain$", ""):gsub("^slain$", "") end
    s = s:lower():gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

local function namedObjectives(obj)
    local n = 0
    for _, o in ipairs(obj or {}) do
        if objectiveName(o.txt, o.ty == "monster") then n = n + 1 end
    end
    return n
end

local function mergeDialogRecord(dst, id, r, blind)
    local m = dst[id] or { src = {}, at = {} }
    dst[id] = m
    m.n = m.n or r.n
    m.qlv = m.qlv or r.qlv
    m.rep = m.rep or r.rep
    addCounts(m.src, r.src)
    -- A dialog from no source the collector could read still records where the player stood, so that session cannot say whose each place was
    local placed, named = 0, 0
    for _, n in pairs(r.at or {}) do placed = placed + n end
    for _, n in pairs(r.src or {}) do named = named + n end
    if not blind and placed <= named then addCounts(m.at, r.at) end
end

for _, key in ipairs(sortedKeys(sessions)) do
    local S = sessions[key]
    for id, r in pairs(S.quests or {}) do
        local have = Q[id]
        if not have or (r.obj and not have.obj) or namedObjectives(r.obj) > namedObjectives(have.obj) then
            Q[id] = { n = r.n or (have and have.n), lv = r.lv or (have and have.lv), obj = r.obj,
                      rep = r.rep or (have and have.rep) }
        end
    end
    for id, r in pairs(S.titles or {}) do
        if type(id) == "number" and type(r) == "table" and type(r.n) == "string" then titles[id] = titles[id] or r end
    end
    for id, why in pairs(S.titleMisses or {}) do
        if type(id) == "number" and why == "refused" then refusedByServer[id] = true end
    end
    -- The dialog log names what a sourceless dialog showed, which a sourced dialog without a position hides from the counts
    local offeredBlind, activeBlind = {}, {}
    for _, d in ipairs(S.dialogs or {}) do
        if type(d) == "table" and not d.src then
            for _, q in ipairs(d.o or {}) do offeredBlind[q] = true end
            for _, q in ipairs(d.a or {}) do activeBlind[q] = true end
        end
    end
    for id, r in pairs(S.starts or {}) do mergeDialogRecord(starts, id, r, offeredBlind[id]) end
    for id, r in pairs(S.ends or {}) do mergeDialogRecord(ends, id, r, activeBlind[id]) end
    for id, objs in pairs(S.prog or {}) do
        for idx, r in pairs(objs) do
            local m = sub(sub(prog, id), idx)
            m.ty = m.ty or r.ty
            for _, field in ipairs({ "at", "npc", "obj", "item" }) do addCounts(sub(m, field), r[field]) end
        end
    end
    for kind, set in pairs(S.units or {}) do
        for id, u in pairs(set) do
            local m = sub(sub(units, kind), id)
            m.n, m.f, m.r = m.n or u.n, m.f or u.f, m.r or u.r
            local at = sub(m, "at")
            for cell, mask in pairs(u.at or {}) do
                local have = at[cell] or 0
                local b = 1
                while b <= mask do
                    if mask % (b + b) >= b and have % (b + b) < b then have = have + b end
                    b = b + b
                end
                at[cell] = have
            end
        end
    end
    for id, d in pairs(S.drops or {}) do
        local m = drops[id] or { npc = {}, obj = {}, at = {} }
        drops[id] = m
        m.n, m.q = m.n or d.n, m.q or d.q
        m.qi = m.qi or d.qi
        addCounts(m.npc, d.npc)
        addCounts(m.obj, d.obj)
        addCounts(m.at, d.at)
    end
end

-- A gate is read from what one character did between two of its visits to one giver.
local timeline = {}
for _, key in ipairs(sortedKeys(sessions)) do
    local S = sessions[key]
    local char = tostring(S.char or "?")
    for i, d in ipairs(S.dialogs or {}) do
        if type(d) == "table" and type(d.t) == "number" and d.src then
            timeline[#timeline + 1] = { t = d.t, seq = i, key = key, char = char, kind = "dialog", d = d }
        end
    end
    for i, r in ipairs(S.turned or {}) do
        if type(r) == "table" and type(r[1]) == "number" and type(r[2]) == "number" then
            timeline[#timeline + 1] = { t = r[2], seq = i, key = key, char = char, kind = "turnin", quest = r[1] }
        end
    end
    for i, r in ipairs(S.levels or {}) do
        if type(r) == "table" and type(r[1]) == "number" and type(r[2]) == "number" then
            timeline[#timeline + 1] = { t = r[1], seq = i, key = key, char = char, kind = "level", lv = r[2] }
        end
    end
end
table.sort(timeline, function(a, b)
    if a.t ~= b.t then return a.t < b.t end
    if a.key ~= b.key then return a.key < b.key end
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.seq < b.seq
end)

local firstTurnIn = {}
for _, e in ipairs(timeline) do
    if e.kind == "turnin" then
        local byChar = sub(firstTurnIn, e.quest)
        byChar[e.char] = byChar[e.char] or e.t
    end
end

local function listHas(list, qid)
    for _, q in ipairs(list or {}) do
        if q == qid then return true end
    end
    return false
end

-- An offer opens a gate unless this character held or was offered the quest by this giver's last full
-- list, or has turned it in. A detail dialog cannot show a quest missing, so it is never that list.
local observations = {}
local visits, firstOffer = {}, {}
for _, e in ipairs(timeline) do
    if e.kind == "dialog" then
        local src = tostring(e.d.src)
        local visitKey = e.char .. "|" .. src
        local seen = visits[visitKey] or {}
        local prev
        for i = #seen, 1, -1 do
            if seen[i].t < e.t then prev = seen[i]; break end
        end
        for _, qid in ipairs(e.d.o or {}) do
            local turnedIn = firstTurnIn[qid] and firstTurnIn[qid][e.char]
            local offeredAt = firstOffer[qid] and firstOffer[qid][e.char]
            if type(qid) == "number" and qid > 0 and prev and not (turnedIn and turnedIn <= e.t)
                and not (offeredAt and offeredAt <= prev.t)
                and not listHas(prev.d.a, qid) then
                observations[#observations + 1] = { quest = qid, src = src, char = e.char, t1 = prev.t,
                                                    t2 = offeredAt or e.t, lv1 = prev.d.lv, lv2 = e.d.lv }
            end
        end
        for _, qid in ipairs(e.d.o or {}) do
            local byChar = sub(firstOffer, qid)
            byChar[e.char] = byChar[e.char] or e.t
        end
        if not e.d.d then
            seen[#seen + 1] = e
            visits[visitKey] = seen
        end
    end
end

-- Contradicting evidence leaves a gate unset rather than picking one reading.
local preSingle, reqLevel = {}, {}
local function record(store, qid, value)
    if store[qid] == nil then store[qid] = value
    elseif store[qid] ~= value then store[qid] = false end
end

-- The window runs from just after the absent visit to this character's first offer, inclusive, because
-- a turn-in shares its second with the dialog it opens and only the turn-in can have come first.
for _, ob in ipairs(observations) do
    local turnIns, dings = {}, {}
    for _, e in ipairs(timeline) do
        if e.char == ob.char and e.t > ob.t1 and e.t <= ob.t2 then
            if e.kind == "turnin" then turnIns[#turnIns + 1] = e.quest end
            if e.kind == "level" then dings[#dings + 1] = e.lv end
        end
    end
    if #dings == 0 and #turnIns == 1 and turnIns[1] ~= ob.quest then
        ob.verdict = ("prerequisite %d"):format(turnIns[1])
        record(preSingle, ob.quest, turnIns[1])
    elseif #turnIns == 0 and #dings == 1 and type(ob.lv1) == "number" and dings[1] == ob.lv1 + 1 then
        ob.verdict = ("required level %d"):format(dings[1])
        record(reqLevel, ob.quest, dings[1])
    else
        ob.verdict = ("unresolved, %d turn-in(s) and %d level-up(s) in between"):format(#turnIns, #dings)
    end
end

local function decode(v)
    local ui = math.floor(v / 1e8)
    local x = math.floor(v % 1e8 / 1e4) / 100
    local y = (v % 1e4) / 100
    return ui, x, y
end

-- Keeps the caller's order because the generator's grid keeps the first point of a cell.
local function spawnTable(packedList)
    local out, seen = {}, {}
    for _, v in ipairs(packedList) do
        local ui, x, y = decode(v)
        if x > 0 and y > 0 then
            local a = areaFor(ui)
            local k = a .. ":" .. x .. ":" .. y
            if not seen[k] then
                seen[k] = true
                local list = sub(out, a)
                list[#list + 1] = { x, y }
            end
        end
    end
    return next(out) and out or nil
end

local function byCountThenKey(counts)
    local keys = sortedKeys(counts)
    table.sort(keys, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    return keys
end

local function cellsWithBits(at, bits)
    local out = {}
    for _, cell in ipairs(sortedKeys(at)) do
        local mask, hit = at[cell], false
        for _, b in ipairs(bits) do
            if mask % (b + b) >= b then hit = true end
        end
        if hit then out[#out + 1] = cell end
    end
    return out
end

local function soleSource(src, kind)
    local only
    for k in pairs(src or {}) do
        if only then return nil end
        only = k
    end
    local k, id = tostring(only):match("^(%a+):(%d+)$")
    if k == kind then return tonumber(id) end
end

local function sourceIds(src, kind)
    local out = {}
    for _, k in ipairs(sortedKeys(src)) do
        local kk, id = tostring(k):match("^(%a+):(%d+)$")
        if kk == kind then out[#out + 1] = tonumber(id) end
    end
    return #out > 0 and out or nil
end

local function strongest(counts, exclude)
    local keys = byCountThenKey(counts)
    local out, top = {}, nil
    for _, id in ipairs(keys) do
        if not (exclude and exclude[id]) then
            top = top or counts[id]
            if counts[id] >= top * KEEP_SHARE then out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end

local function leader(counts, exclude)
    for _, id in ipairs(byCountThenKey(counts)) do
        if not (exclude and exclude[id]) then return id end
    end
end

local function lowerName(n)
    return type(n) == "string" and n:lower() or nil
end

local newQuests = {}
for _, t in ipairs({ Q, starts, ends, prog }) do
    for id in pairs(t) do
        if type(id) == "number" and not base.quests[id] then newQuests[id] = true end
    end
end
local collectedQuest = {}
for id in pairs(newQuests) do collectedQuest[id] = true end

local att = attDir and dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tools/") .. "forever_att.lua")(attDir)
local clientQuests = {}
if questV2File then
    local csv = readAll(questV2File)
    assert(csv:match("^ID,"), questV2File .. " does not start with the ID column")
    for line in csv:gmatch("[^\r\n]+") do
        local id = tonumber(line:match("^(%d+),"))
        if id then clientQuests[id] = true end
    end
    assert(next(clientQuests), "no quest ids in " .. questV2File)
end

-- ATT's own version number for WoW Forever 1.60.1, the one its awp and rwp fields use.
local FOREVER_PATCH = 16001
local ATT_UNOBTAINABLE = { [1] = "never implemented", [2] = "removed from the game" }
local function attSkipReason(id, a)
    if ATT_UNOBTAINABLE[a.unobtainable] then return ATT_UNOBTAINABLE[a.unobtainable] end
    if a.addedIn and a.addedIn > FOREVER_PATCH then return "added after 1.60.1" end
    if a.removedIn and a.removedIn <= FOREVER_PATCH then return "removed by 1.60.1" end
    if a.variants then return "split by faction" end
    if refusedByServer[id] and not titles[id] then return "refused by the server" end
    if not clientQuests[id] then return "not in the client's quest table" end
end

local attQuests, attSkipped, attSkipNotes, skippedWhy = {}, {}, {}, {}
for _, id in ipairs(sortedKeys(att and att.quests)) do
    local a = att.quests[id]
    if not base.quests[id] then
        local why = attSkipReason(id, a)
        if why and collectedQuest[id] then
            attSkipNotes[#attSkipNotes + 1] = ("-- ATT KNOWN ANSWER MISMATCH: quest %d reads %s, but the collector saw it"):format(id, why)
        end
        if why and not collectedQuest[id] then
            local list = sub(attSkipped, why)
            list[#list + 1] = id
            skippedWhy[id] = why
        else
            attQuests[id] = a
            newQuests[id] = true
        end
    end
end

local qRows, nRows, oRows, iRows = {}, {}, {}, {}
local needNpc, needObj, needItem = {}, {}, {}

local RACE_BIT = { 1, 2, 4, 8, 16, 32, 64, 128 }
-- Skyborne ids do not fit the Era mask, so each counts as its faction, read from Forever's ChrRaces table.
local RACE_FACTION_MASK = { [95] = RACES_ALLIANCE, [96] = RACES_HORDE }

local function bitOr(a, b)
    local out, bit = 0, 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then out = out + bit end
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return out
end

local function bitAnd(a, b)
    local out, bit = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then out = out + bit end
        a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
    end
    return out
end

local function attRaceMask(a)
    if a.races then
        local mask = 0
        for _, r in ipairs(a.races) do
            local m = RACE_BIT[r] or RACE_FACTION_MASK[r]
            if not m then return nil end
            mask = bitOr(mask, m)
        end
        return mask
    end
    if a.faction == 1 then return RACES_HORDE end
    if a.faction == 2 then return RACES_ALLIANCE end
end

local function attClassMask(a)
    local mask = 0
    for _, c in ipairs(a.classes or {}) do
        if c < 1 or c > 13 then return nil end
        mask = bitOr(mask, 2 ^ (c - 1))
    end
    return mask > 0 and mask or nil
end

local function packPoint(ui, x, y)
    if x <= 0 or y <= 0 or x >= 100 or y >= 100 then return nil end
    return ui * 1e8 + math.floor(x * 100 + 0.5) * 1e4 + math.floor(y * 100 + 0.5)
end

local attStats = { rows = 0, filled = 0, confirmed = 0, mismatched = 0, dropped = 0 }
local attIssues, attPoints, attBoth, measuredPre = {}, { npc = {}, obj = {} }, {}, {}
local attGivers = { npc = {}, obj = {} }

local function attMismatch(qid, what, detail)
    attStats.mismatched = attStats.mismatched + 1
    attIssues[#attIssues + 1] = ("-- ATT KNOWN ANSWER MISMATCH: quest %d %s: %s"):format(qid, what, detail)
end

-- ATT only fills empty fields, except that an agreeing race mask or prerequisite takes ATT's more detailed form and a disputed prerequisite is dropped.
local function mergeATT(qid, row, a, lines)
    local filled = false
    local function fill(field, value)
        if value ~= nil and row[field] == nil then row[field] = value; filled = true end
    end

    local sb = row[Q_STARTEDBY]
    if sb then
        attBoth[#attBoth + 1] = qid
        local agree = false
        for _, g in ipairs(a.givers) do if listHas(sb[1], g) then agree = true end end
        for _, o in ipairs(a.objects) do if listHas(sb[2], o) then agree = true end end
        if agree then
            attStats.confirmed = attStats.confirmed + 1
        elseif #a.givers + #a.objects > 0 then
            attMismatch(qid, "giver", ("ATT %s, collected %s"):format(table.concat(a.givers, " "), table.concat(sb[1] or {}, " ")))
        end
    elseif #a.givers + #a.objects > 0 then
        row[Q_STARTEDBY] = { #a.givers > 0 and a.givers or nil, #a.objects > 0 and a.objects or nil }
        filled = true
        -- ATT does not say whose point is whose, so a quest's points place its giver only when it has a single one.
        local sole = #a.givers + #a.objects == 1
        for kind, ids in pairs({ npc = a.givers, obj = a.objects }) do
            local need = kind == "npc" and needNpc or needObj
            for _, id in ipairs(ids) do
                need[id], attGivers[kind][id] = true, true
                for _, p in ipairs(sole and a.points or {}) do
                    local v = packPoint(p[1], p[2], p[3])
                    if v then local l = sub(attPoints[kind], id); l[#l + 1] = v end
                end
            end
        end
        lines[#lines + 1] = "starts (ATT): " .. table.concat(a.givers, " ") .. (#a.objects > 0 and (" obj " .. table.concat(a.objects, " ")) or "")
    end

    if a.reqLevel and row[Q_REQLEVEL] then
        if a.reqLevel == row[Q_REQLEVEL] then attStats.confirmed = attStats.confirmed + 1
        else attMismatch(qid, "required level", ("ATT %d, collected %d"):format(a.reqLevel, row[Q_REQLEVEL])) end
    else
        fill(Q_REQLEVEL, a.reqLevel)
    end

    local races = attRaceMask(a)
    if races and row[Q_RACES] then
        if bitOr(races, row[Q_RACES]) == row[Q_RACES] then
            attStats.confirmed = attStats.confirmed + 1
            if races ~= row[Q_RACES] then row[Q_RACES] = races; filled = true end
        else
            attMismatch(qid, "races", ("ATT %d, collected %d"):format(races, row[Q_RACES]))
        end
    else
        fill(Q_RACES, races)
    end
    fill(Q_CLASSES, attClassMask(a))

    -- sqreq names how many of the list are needed, so 1 reads as any-of, the whole list as all-of, and a count between is dropped.
    local attAll, attAny = a.pre, nil
    if a.pre and a.preCount and a.preCount < #a.pre then
        attAll = nil
        if a.preCount == 1 then attAny = a.pre else attStats.dropped = attStats.dropped + 1 end
    end
    local have = row[Q_PRESINGLE] and row[Q_PRESINGLE][1]
    measuredPre[qid] = have
    if have and (attAll or attAny) then
        if listHas(attAll, have) then
            row[Q_PRESINGLE], row[Q_PREGROUP] = nil, attAll
            attStats.confirmed = attStats.confirmed + 1
        elseif listHas(attAny, have) then
            row[Q_PRESINGLE] = attAny
            attStats.confirmed = attStats.confirmed + 1
        else
            row[Q_PRESINGLE] = nil
            attMismatch(qid, "prerequisite", ("ATT %s, collected %d, left unset"):format(table.concat(attAll or attAny, " "), have))
        end
    elseif not have then
        fill(Q_PREGROUP, attAll)
        fill(Q_PRESINGLE, attAny)
    end

    fill(Q_EXCLUSIVE, a.excl)
    fill(Q_REQSKILL, a.skill and { a.skill, 1 })
    fill(Q_MINREP, a.minRep)
    -- ATT stores the first reputation value shut out and the Era dump the last one let in.
    fill(Q_MAXREP, a.maxRep and { a.maxRep[1], a.maxRep[2] - 1 })
    if a.repeatable then fill(Q_SPECIALFLAGS, 1) end

    if filled then attStats.filled = attStats.filled + 1 end
    if row[Q_PREGROUP] or row[Q_PRESINGLE] then
        lines[#lines + 1] = "prerequisite: " .. table.concat(row[Q_PREGROUP] or row[Q_PRESINGLE], row[Q_PREGROUP] and " and " or " or ")
    end
end

local pseudoNext = PSEUDO_BASE
local pseudoPoints = { npc = {}, obj = {} }
local report = {}

local function pseudo(kind, packedCells, label)
    pseudoNext = pseudoNext + 1
    local id = pseudoNext
    pseudoPoints[kind][id] = { cells = packedCells, label = label }
    return id
end

local function tickCells(p)
    return byCountThenKey(p and p.at or {})
end

local function knownItemSources(itemID)
    local d = drops[itemID]
    return d and next(d.npc) and strongest(d.npc) or nil, d and next(d.obj) and strongest(d.obj) or nil
end

for _, qid in ipairs(sortedKeys(newQuests)) do
    local meta, st, en, pg = Q[qid] or {}, starts[qid], ends[qid], prog[qid] or {}
    local row = {}
    local lines = {}
    -- A quest only ATT knows gets no placeholder name, which marks it for the next title harvest.
    row[Q_NAME] = meta.n or (st and st.n) or (en and en.n) or (titles[qid] and titles[qid].n)
        or (collectedQuest[qid] and ("quest " .. qid) or nil)
    row[Q_QUESTLEVEL] = meta.lv or (st and st.qlv) or (en and en.qlv) or (titles[qid] and titles[qid].lv)

    if st then
        local sNpc, sObj, sItem = sourceIds(st.src, "npc"), sourceIds(st.src, "obj"), sourceIds(st.src, "item")
        if sNpc or sObj or sItem then row[Q_STARTEDBY] = { sNpc, sObj, sItem } end
        for _, id in ipairs(sNpc or {}) do needNpc[id] = true end
        for _, id in ipairs(sObj or {}) do needObj[id] = true end
        for _, id in ipairs(sItem or {}) do if not base.items[id] then needItem[id] = true end end
        local faction
        for _, id in ipairs(sNpc or {}) do
            local f = units.npc[id] and units.npc[id].f
            if faction == nil then faction = f or false elseif faction ~= f then faction = false end
        end
        if faction == "Alliance" then row[Q_RACES] = RACES_ALLIANCE
        elseif faction == "Horde" then row[Q_RACES] = RACES_HORDE end
        if st.rep then row[Q_SPECIALFLAGS] = 1 end
        lines[#lines + 1] = "starts: " .. table.concat(sortedKeys(st.src), " ")
    end
    if meta.rep then row[Q_SPECIALFLAGS] = 1 end

    if en then
        local fNpc, fObj = sourceIds(en.src, "npc"), sourceIds(en.src, "obj")
        if fNpc or fObj then row[Q_FINISHEDBY] = { fNpc, fObj } end
        for _, id in ipairs(fNpc or {}) do needNpc[id] = true end
        for _, id in ipairs(fObj or {}) do needObj[id] = true end
        lines[#lines + 1] = "finishes: " .. table.concat(sortedKeys(en.src), " ")
    end

    if type(preSingle[qid]) == "number" then
        row[Q_PRESINGLE] = { preSingle[qid] }
        lines[#lines + 1] = "prerequisite: " .. preSingle[qid]
    end
    if type(reqLevel[qid]) == "number" then
        row[Q_REQLEVEL] = reqLevel[qid]
        lines[#lines + 1] = "required level: " .. reqLevel[qid]
    end

    -- Objectives stay in client order within their type, which is how EQ's pins index them. Every
    -- monster objective goes in the kill credit list, so o[1] and o[5] never share an index space.
    local objs = meta.obj
    if not objs then
        objs = {}
        -- A gap in the ticked indices hides an objective of unknown type, which could renumber a later one.
        local idxs = sortedKeys(pg)
        if idxs[1] == 1 and idxs[#idxs] == #idxs then
            for _, idx in ipairs(idxs) do objs[idx] = { ty = pg[idx].ty } end
        end
    end
    local killCredit, objects, itemsList = {}, {}, {}
    local usedItems = {}
    for i = 1, table.maxn(objs) do
        local o, p = objs[i], pg[i]
        local ty = o and o.ty
        if ty == "monster" then
            local want = objectiveName(o.txt, true)
            local ids = {}
            if p and p.npc then
                if want then
                    for _, id in ipairs(sortedKeys(p.npc)) do
                        if lowerName(units.npc[id] and units.npc[id].n) == want then ids[#ids + 1] = id end
                    end
                end
                if #ids == 0 then ids = strongest(p.npc) end
            end
            local located = false
            for _, id in ipairs(ids) do
                if base.npcs[id] then located = true else needNpc[id] = true end
            end
            if not located and #tickCells(p) > 0 and not next(ids) then
                ids = { pseudo("npc", tickCells(p), ("%s objective %d"):format(row[Q_NAME], i)) }
            end
            killCredit[#killCredit + 1] = { ids, ids[1] or 0 }
            lines[#lines + 1] = ("objective %d monster -> %s"):format(i, #ids > 0 and table.concat(ids, " ") or "none")
        elseif ty == "item" then
            local candidates, ticked = {}, p and p.item or {}
            addCounts(candidates, ticked)
            for id, d in pairs(drops) do
                if d.q == qid and not candidates[id] then candidates[id] = d.qi and 1 or 0 end
            end
            local want = objectiveName(o.txt, false)
            local pickId
            if want then
                for _, id in ipairs(sortedKeys(candidates)) do
                    if not usedItems[id] and lowerName(drops[id] and drops[id].n) == want then pickId = id; break end
                end
            end
            -- Ticked items first, as a drop only tagged for the quest scores at most 1 and could win a tie.
            if not pickId then pickId = leader(ticked, usedItems) or leader(candidates, usedItems) end
            if not pickId and #tickCells(p) > 0 then
                pickId = pseudo("obj", tickCells(p), ("%s objective %d"):format(row[Q_NAME], i))
                iRows[pickId] = { [I_NAME] = ("%s objective %d"):format(row[Q_NAME], i), [I_OBJDROPS] = { pickId } }
                oRows[pickId] = true
            elseif pickId then
                usedItems[pickId] = true
                if not base.items[pickId] then needItem[pickId] = { cells = tickCells(p) } end
            end
            itemsList[#itemsList + 1] = { pickId or 0 }
            lines[#lines + 1] = ("objective %d item -> %s"):format(i, tostring(pickId or "none"))
        elseif ty == "object" then
            local id = p and p.obj and leader(p.obj)
            if id and not base.objects[id] then needObj[id] = true end
            if not id and #tickCells(p) > 0 then
                id = pseudo("obj", tickCells(p), ("%s objective %d"):format(row[Q_NAME], i))
                oRows[id] = true
            end
            objects[#objects + 1] = { id or 0 }
            lines[#lines + 1] = ("objective %d object -> %s"):format(i, tostring(id or "none"))
        end
    end
    if #killCredit > 0 or #objects > 0 or #itemsList > 0 then
        local o = {}
        if #objects > 0 then o[OBJ_OBJECT] = objects end
        if #itemsList > 0 then o[OBJ_ITEM] = itemsList end
        if #killCredit > 0 then o[OBJ_KILLCREDIT] = killCredit end
        row[Q_OBJECTIVES] = o
    end
    if attQuests[qid] then
        attStats.rows = attStats.rows + 1
        mergeATT(qid, row, attQuests[qid], lines)
    end
    qRows[qid] = row
    report[#report + 1] = ("[%d] %s level %s%s\n    %s"):format(qid, tostring(row[Q_NAME]), tostring(row[Q_QUESTLEVEL]),
        row[Q_RACES] and (" races " .. row[Q_RACES]) or "", table.concat(lines, "\n    "))
end

-- ATT ignores a breadcrumb or a prerequisite the character cannot take, and a list cannot say that per character, so the build decides for everyone.
local ALL_RACES, ALL_CLASSES = bitOr(RACES_ALLIANCE, RACES_HORDE), 2 ^ 13 - 1
local function gateMasks(qid)
    local row = qRows[qid] or base.quests[qid]
    local r, c = tonumber(row and row[Q_RACES]) or 0, tonumber(row and row[Q_CLASSES]) or 0
    return r > 0 and r or ALL_RACES, c > 0 and c or ALL_CLASSES
end
local function breadcrumb(p) return att.quests[p] and att.quests[p].breadcrumb end
-- A Skyborne-only quest carries its whole faction's mask, so only ATT's own race list tells it apart.
local function skyborneOnly(id)
    local a = att.quests[id]
    if not (a and a.races) then return false end
    for _, r in ipairs(a.races) do if not RACE_FACTION_MASK[r] then return false end end
    return true
end
local function neverDone(p)
    if skippedWhy[p] and skippedWhy[p] ~= "split by faction" then return "skipped, " .. skippedWhy[p] end
    -- The collector saw no quest flagged complete that the client's quest table lacks.
    if not clientQuests[p] and not collectedQuest[p] then return "never flagged complete" end
end
local function reach(qid, p)
    local r, c = gateMasks(qid)
    local pr, pc = gateMasks(p)
    if bitAnd(r, pr) == 0 or bitAnd(c, pc) == 0 then return "none" end
    if skyborneOnly(p) and not skyborneOnly(qid) then return "some" end
    if bitAnd(r, pr) == r and bitAnd(c, pc) == c then return "all" end
    return "some"
end
local function coversEveryone(qid, list)
    local r, c = gateMasks(qid)
    for rb = 0, 7 do
        for cb = 0, 12 do
            if bitAnd(r, 2 ^ rb) ~= 0 and bitAnd(c, 2 ^ cb) ~= 0 then
                local covered = false
                for _, p in ipairs(list) do
                    local pr, pc = gateMasks(p)
                    if bitAnd(pr, 2 ^ rb) ~= 0 and bitAnd(pc, 2 ^ cb) ~= 0 and not (skyborneOnly(p) and not skyborneOnly(qid)) then covered = true end
                end
                if not covered then return false end
            end
        end
    end
    return true
end
local function jointlyPossible(list)
    local r, c = ALL_RACES, ALL_CLASSES
    for _, p in ipairs(list) do
        local pr, pc = gateMasks(p)
        r, c = bitAnd(r, pr), bitAnd(c, pc)
    end
    return r ~= 0 and c ~= 0
end

-- Like a collected quest, a quest ATT gives no races takes the faction its creature givers share.
for _, qid in ipairs(sortedKeys(attQuests)) do
    local row = qRows[qid]
    local sb = row[Q_STARTEDBY]
    if row[Q_RACES] == nil and sb and sb[1] and not sb[2] then
        local faction
        for _, g in ipairs(sb[1]) do
            local f = (units.npc[g] and FACTION_TAG[units.npc[g].f or ""]) or (base.npcs[g] and base.npcs[g][N_FACTION])
            if faction == nil then faction = f or false elseif faction ~= f then faction = false end
        end
        if faction == "A" then row[Q_RACES] = RACES_ALLIANCE elseif faction == "H" then row[Q_RACES] = RACES_HORDE end
    end
end

local attWaived = {}
local function waived(fmt, ...) attWaived[#attWaived + 1] = ("-- att prerequisite waived: " .. fmt):format(...) end
for _, qid in ipairs(sortedKeys(attQuests)) do
    local row, measured = qRows[qid], measuredPre[qid]
    for _, field in ipairs({ Q_PREGROUP, Q_PRESINGLE }) do
        if row[field] then
            local kept = {}
            for _, p in ipairs(row[field]) do
                local why = p ~= measured and (field == Q_PREGROUP and breadcrumb(p) and "a breadcrumb" or neverDone(p))
                if why then waived("quest %d needs %d, %s", qid, p, why) else kept[#kept + 1] = p end
            end
            row[field] = #kept > 0 and kept or nil
        end
    end

    local any = row[Q_PRESINGLE]
    if any and not listHas(any, measured) then
        for _, p in ipairs(any) do
            if breadcrumb(p) or reach(qid, p) ~= "all" then
                row[Q_PRESINGLE] = nil
                waived("quest %d needs one of %s, which ATT counts as met through %d", qid, table.concat(any, " "), p)
                break
            end
        end
    end

    local all = row[Q_PREGROUP]
    if all then
        local r, c = gateMasks(qid)
        local noRace, noClass = true, true
        for _, p in ipairs(all) do
            local pr, pc = gateMasks(p)
            if bitAnd(r, pr) ~= 0 then noRace = false end
            if bitAnd(c, pc) ~= 0 then noClass = false end
        end
        -- A quest that none of its prerequisites fits contradicts itself, so its own gate goes rather than the whole chain.
        if noRace or noClass then
            if noRace then row[Q_RACES] = nil end
            if noClass then row[Q_CLASSES] = nil end
            attWaived[#attWaived + 1] = ("-- att %s gate dropped: quest %d keeps %s, none of which fits it")
                :format(noRace and noClass and "race and class" or noRace and "race" or "class", qid, table.concat(all, " "))
            if not jointlyPossible(all) then
                row[Q_PREGROUP] = nil
                waived("quest %d needs %s, which no one character can all take", qid, table.concat(all, " "))
            end
        else
            local full, partial = {}, {}
            for _, p in ipairs(all) do
                local how = p == measured and "all" or reach(qid, p)
                if how == "all" then full[#full + 1] = p
                elseif how == "some" then partial[#partial + 1] = p
                else waived("quest %d needs %d, which no character taking it can take", qid, p) end
            end
            row[Q_PREGROUP] = #full > 0 and full or nil
            if #partial > 0 and #full > 0 then
                waived("quest %d needs %s, which only some characters taking it can take", qid, table.concat(partial, " "))
            elseif #partial > 0 then
                if coversEveryone(qid, partial) then
                    row[Q_PRESINGLE] = partial
                    waived("quest %d needs %s, each for only some characters, so any one will do", qid, table.concat(partial, " "))
                else
                    waived("quest %d needs %s, each for only some characters and not covering them all", qid, table.concat(partial, " "))
                end
            end
        end
    end
end

-- Runs before the creature and object rows, because an item's drop sources add to needNpc and needObj.
for _, itemID in ipairs(sortedKeys(needItem)) do
    if not iRows[itemID] then
        local d = drops[itemID]
        local npcIds, objIds = knownItemSources(itemID)
        local row = { [I_NAME] = d and d.n or ("item " .. itemID) }
        if npcIds then row[I_NPCDROPS] = npcIds; for _, id in ipairs(npcIds) do needNpc[id] = true end end
        if objIds then row[I_OBJDROPS] = objIds; for _, id in ipairs(objIds) do needObj[id] = true end end
        if not npcIds and not objIds then
            local want = needItem[itemID]
            local cells = type(want) == "table" and want.cells or {}
            if #cells == 0 and d then cells = byCountThenKey(d.at) end
            if #cells > 0 then
                local id = pseudo("obj", cells, row[I_NAME] .. " source")
                oRows[id] = true
                row[I_OBJDROPS] = { id }
            end
        end
        iRows[itemID] = row
    end
end

-- A dialog is held within a few yards of the giver, so repeat visits are one place, not several.
-- Anything farther from every kept point than this, as a fraction of the map, is another spawn.
local SAME_PLACE = 0.01

local function collapse(points)
    local kept = {}
    for _, v in ipairs(points) do
        local ui, x, y = decode(v)
        local near = false
        for _, k in ipairs(kept) do
            local kui, kx, ky = decode(k)
            if kui == ui and math.abs(kx - x) <= SAME_PLACE * 100 and math.abs(ky - y) <= SAME_PLACE * 100 then
                near = true
                break
            end
        end
        if not near then kept[#kept + 1] = v end
    end
    return kept
end

-- Each place a dialog was held belongs to the one giver it names, never to a record naming two.
local function dialogPoints(kind, id)
    local counts = {}
    for _, t in ipairs({ starts, ends }) do
        for _, qid in ipairs(sortedKeys(t)) do
            local r = t[qid]
            if soleSource(r.src, kind) == id then addCounts(counts, r.at) end
        end
    end
    return collapse(byCountThenKey(counts))
end

-- The collector stores where the PLAYER stood, so a creature seen on a nameplate or hovered from
-- across a camp is placed tens of yards off. Only the closest kind of sighting it has is used.
local SIGHTING_TIERS = { { SEEN_KILL }, { SEEN_TARGET }, { SEEN_PLATE } }

local function sightingPoints(at)
    for _, bits in ipairs(SIGHTING_TIERS) do
        local pts = cellsWithBits(at or {}, bits)
        if #pts > 0 then return pts end
    end
    return {}
end

local function lootPoints(objID)
    local pts = {}
    for _, itemID in ipairs(sortedKeys(drops)) do
        local d = drops[itemID]
        if not next(d.npc) and count(d.obj) == 1 and d.obj[objID] then
            for _, v in ipairs(byCountThenKey(d.at)) do pts[#pts + 1] = v end
        end
    end
    for _, qid in ipairs(sortedKeys(prog)) do
        for _, idx in ipairs(sortedKeys(prog[qid])) do
            local p = prog[qid][idx]
            if p.obj and count(p.obj) == 1 and p.obj[objID] then
                for _, v in ipairs(byCountThenKey(p.at)) do pts[#pts + 1] = v end
            end
        end
    end
    return pts
end

for _, id in ipairs(sortedKeys(needNpc)) do
    if not base.npcs[id] then
        local u = units.npc[id] or {}
        local pts = dialogPoints("npc", id)
        if #pts == 0 then pts = collapse(cellsWithBits(u.at or {}, { SEEN_TALK })) end
        if #pts == 0 and attPoints.npc[id] then pts = collapse(attPoints.npc[id]) end
        if #pts == 0 then pts = sightingPoints(u.at) end
        nRows[id] = { [N_NAME] = u.n or (not attGivers.npc[id] and ("creature " .. id) or nil), [N_SPAWNS] = spawnTable(pts),
                      [N_FACTION] = FACTION_TAG[u.f or ""] }
    end
end

for _, id in ipairs(sortedKeys(needObj)) do
    if not base.objects[id] then
        local u = units.obj[id] or {}
        local pts = dialogPoints("obj", id)
        if #pts == 0 then pts = collapse(cellsWithBits(u.at or {}, { SEEN_TALK })) end
        for _, v in ipairs(lootPoints(id)) do pts[#pts + 1] = v end
        if #pts == 0 and attPoints.obj[id] then pts = collapse(attPoints.obj[id]) end
        oRows[id] = { [O_NAME] = u.n or (not attGivers.obj[id] and ("object " .. id) or nil), [O_SPAWNS] = spawnTable(pts) }
    end
end

for kind, set in pairs(pseudoPoints) do
    for id, p in pairs(set) do
        if kind == "npc" then
            nRows[id] = { [N_NAME] = p.label, [N_SPAWNS] = spawnTable(p.cells) }
        else
            oRows[id] = { [O_NAME] = p.label, [O_SPAWNS] = spawnTable(p.cells) }
        end
    end
end
for id, v in pairs(oRows) do assert(v ~= true, "object " .. id .. " was reserved but never built") end

local function ser(v)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) then return ("%.0f"):format(v) end
        return ("%.2f"):format(v)
    elseif t == "string" then
        return ("%q"):format(v)
    elseif t == "boolean" then
        return tostring(v)
    end
    assert(t == "table", "cannot serialize a " .. t)
    local n, dense = count(v), true
    for i = 1, n do if v[i] == nil then dense = false end end
    local parts = {}
    if dense then
        for i = 1, n do parts[i] = ser(v[i]) end
    else
        for _, k in ipairs(sortedKeys(v)) do
            assert(type(k) == "number", "row keys must be numbers")
            parts[#parts + 1] = ("[%d]=%s"):format(k, ser(v[k]))
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- The generator reads a block up to its first "}]]", so the text is read back the same way and
-- every row compared, rather than trusting that no name happens to contain the terminator.
local function writeBlock(file, varName, rows, what, attFed)
    local parts = { ("-- Generated by tools/build_forever_supplement.lua from collected WoW Forever %s%s. Do not edit.\n")
                        :format(what, (att and attFed) and " and AllTheThings (MIT)" or ""),
                    varName .. " = [[return {\n" }
    for _, id in ipairs(sortedKeys(rows)) do
        parts[#parts + 1] = ("[%d]=%s,\n"):format(id, ser(rows[id]))
    end
    parts[#parts + 1] = "}]]\n"
    local text = table.concat(parts)
    writeAll(outDir .. "/" .. file, text)
    local back = parseBlock(readAll(outDir .. "/" .. file), varName .. " = [[", file)
    assert(count(back) == count(rows), file .. ": row count changed on reload")
    for id, row in pairs(rows) do
        assert(back[id] and ser(back[id]) == ser(row), ("%s: row %d changed on reload"):format(file, id))
    end
end

-- Only dialogs that named a creature or object place a quest, the collector outranks ATT on a map, and ATT points carry a 1
local ownStarts, ownStats = {}, { quests = 0, dialogs = 0, att = 0, contradicted = 0 }
for _, qid in ipairs(sortedKeys(qRows)) do
    local st, a = starts[qid], attQuests[qid]
    local dialogs = {}
    if st then
        local usable = true
        for k in pairs(st.src) do
            local kind = tostring(k):match("^(%a+):")
            if kind ~= "npc" and kind ~= "obj" then usable = false end
        end
        if usable then dialogs = collapse(byCountThenKey(st.at)) end
    end
    local list = {}
    for _, v in ipairs(dialogs) do
        local ui, x, y = decode(v)
        list[#list + 1] = { areaFor(ui), x, y }
    end
    for _, p in ipairs(a and a.points or {}) do
        if packPoint(p[1], p[2], p[3]) then
            local seenOnMap, near = false, false
            for _, v in ipairs(dialogs) do
                local ui, x, y = decode(v)
                if ui == p[1] then
                    seenOnMap = true
                    if math.sqrt((x - p[2]) ^ 2 + (y - p[3]) ^ 2) <= SAME_PLACE * 100 then near = true end
                end
            end
            if seenOnMap and not near then
                ownStats.contradicted = ownStats.contradicted + 1
            else
                list[#list + 1] = { areaFor(p[1]), p[2], p[3], 1 }
                ownStats.att = ownStats.att + 1
            end
        end
    end
    if #list > 0 then
        ownStarts[qid] = list
        ownStats.quests, ownStats.dialogs = ownStats.quests + 1, ownStats.dialogs + #dialogs
    end
end

for _, spec in pairs(BASE_FILES) do
    writeAll(outDir .. "/" .. spec.file, raw[spec.file])
    assert(readAll(outDir .. "/" .. spec.file) == raw[spec.file], "copy of " .. spec.file .. " differs")
end
if dungeonSrc then writeAll(outDir .. "/dungeonEntrances.lua", dungeonSrc) end

local areaRows = {}
for a, ui in pairs(area2ui) do areaRows[a] = ui end
for a, ui in pairs(synthAreas) do areaRows[a] = ui end
writeBlock("areaIdToUiMapId.lua", "areaIdToUiMapId", areaRows, "map ids")
writeBlock(OVERLAY_PREFIX .. "QuestDB.lua", "questData", qRows, "quests", true)
writeBlock(OVERLAY_PREFIX .. "NpcDB.lua", "npcData", nRows, "creatures", true)
writeBlock(OVERLAY_PREFIX .. "ObjectDB.lua", "objectData", oRows, "objects", true)
writeBlock(OVERLAY_PREFIX .. "ItemDB.lua", "itemData", iRows, "items")

do
    local parts = { "-- Generated by tools/build_forever_supplement.lua. [questID] = { {areaId, x, y[, 1 for an ATT point]}, ... }, where that quest is offered.\nreturn {\n" }
    for _, qid in ipairs(sortedKeys(ownStarts)) do parts[#parts + 1] = ("[%d]=%s,\n"):format(qid, ser(ownStarts[qid])) end
    parts[#parts + 1] = "}\n"
    local file = outDir .. "/" .. OVERLAY_PREFIX .. "Starts.lua"
    writeAll(file, table.concat(parts))
    local back = assert(loadfile(file))()
    assert(count(back) == count(ownStarts), file .. ": row count changed on reload")
    for qid, list in pairs(ownStarts) do
        assert(back[qid] and ser(back[qid]) == ser(list), ("%s: row %d changed on reload"):format(file, qid))
    end
end

io.stderr:write(("-- %d session(s) from %d file(s): %d new quest(s), %d creature(s), %d object(s), %d item(s), %d synthetic area(s)\n")
    :format(count(sessions), #sessionFiles, count(qRows), count(nRows), count(oRows), count(iRows), count(synthAreas)))
io.stderr:write(("-- own starts: %d quest(s), %d dialog place(s), %d ATT point(s), %d ATT point(s) the collector contradicts on their map\n")
    :format(ownStats.quests, ownStats.dialogs, ownStats.att, ownStats.contradicted))
for _, line in ipairs(report) do io.stderr:write(line .. "\n") end

-- Every gate inferred for a quest the Era dump knows is graded against the dump on every run.
local knownOk, knownBad = 0, 0
local function checkKnown(what, qid, got, want, wantText)
    if not base.quests[qid] then return end
    if want == got then
        knownOk = knownOk + 1
    else
        knownBad = knownBad + 1
        io.stderr:write(("-- KNOWN ANSWER MISMATCH: quest %d %s reads %s, the Era dump says %s\n")
            :format(qid, what, tostring(got), tostring(wantText or want)))
    end
end

local nPre, nLevel, nDisputed = 0, 0, 0
for _, qid in ipairs(sortedKeys(preSingle)) do
    if type(preSingle[qid]) == "number" then
        nPre = nPre + 1
        local era = base.quests[qid] and base.quests[qid][Q_PRESINGLE]
        -- The Era list is any-of, so a reading matching any entry is right.
        local want = type(era) == "table" and (listHas(era, preSingle[qid]) and preSingle[qid] or era[1]) or nil
        checkKnown("prerequisite", qid, preSingle[qid], want, type(era) == "table" and table.concat(era, " or ") or nil)
    else
        nDisputed = nDisputed + 1
    end
end
for _, qid in ipairs(sortedKeys(reqLevel)) do
    if type(reqLevel[qid]) == "number" then
        nLevel = nLevel + 1
        checkKnown("required level", qid, reqLevel[qid],
                   base.quests[qid] and tonumber(base.quests[qid][Q_REQLEVEL]) or nil)
    else
        nDisputed = nDisputed + 1
    end
end

-- A title the server gave is graded against any name and level the collector or the Era dump already gave that quest.
local tStats = { named = 0, same = 0, bad = 0, lvSame = 0, lvDiff = 0 }
local tIssues = {}
for _, qid in ipairs(sortedKeys(titles)) do
    local r, meta, st, en = titles[qid], Q[qid] or {}, starts[qid], ends[qid]
    local era = base.quests[qid]
    local known = meta.n or (st and st.n) or (en and en.n) or (era and era[Q_NAME])
    local knownLv = meta.lv or (st and st.qlv) or (en and en.qlv) or (era and tonumber(era[Q_QUESTLEVEL]))
    if qRows[qid] and qRows[qid][Q_NAME] == r.n and not known then tStats.named = tStats.named + 1 end
    if known then
        if known == r.n then tStats.same = tStats.same + 1
        else
            tStats.bad = tStats.bad + 1
            tIssues[#tIssues + 1] = ("-- TITLE KNOWN ANSWER MISMATCH: quest %d reads %q, the known name is %q"):format(qid, r.n, known)
        end
    end
    if r.lv and knownLv then
        if r.lv == knownLv then tStats.lvSame = tStats.lvSame + 1 else tStats.lvDiff = tStats.lvDiff + 1 end
    end
end
if next(titles) then
    io.stderr:write(("-- titles: %d read, %d name a quest nothing else names, %d known answer(s) confirmed, %d mismatch(es), quest level %d same %d differ\n")
        :format(count(titles), tStats.named, tStats.same, tStats.bad, tStats.lvSame, tStats.lvDiff))
    for _, line in ipairs(tIssues) do io.stderr:write(line .. "\n") end
end

io.stderr:write(("-- %d gate observation(s): %d prerequisite(s), %d required level(s), %d contradicted, %d known answer(s) confirmed, %d mismatch(es)\n")
    :format(#observations, nPre, nLevel, nDisputed, knownOk, knownBad))
for _, ob in ipairs(observations) do
    io.stderr:write(("--   quest %d at %s, player level %s to %s: %s%s\n"):format(ob.quest, ob.src,
        tostring(ob.lv1), tostring(ob.lv2), ob.verdict,
        base.quests[ob.quest] and " [Era knows this quest]" or " [Forever only]"))
end

if att then
    -- Where a quest's collector dialogs and ATT both place its giver, the two must be the same place.
    local PLACE_TOLERANCE = 1.0
    local placed, unplaced = 0, 0
    for _, qid in ipairs(attBoth) do
        local a, best = attQuests[qid], nil
        for _, g in ipairs(a.givers) do
            for _, v in ipairs(dialogPoints("npc", g)) do
                local ui, x, y = decode(v)
                for _, p in ipairs(a.points) do
                    if p[1] == ui then
                        local d = math.sqrt((p[2] - x) ^ 2 + (p[3] - y) ^ 2)
                        if not best or d < best then best = d end
                    end
                end
            end
        end
        if not best then unplaced = unplaced + 1
        elseif best <= PLACE_TOLERANCE then placed = placed + 1; attStats.confirmed = attStats.confirmed + 1
        else attMismatch(qid, "start point", ("ATT is %.2f map units from the collected dialogs"):format(best)) end
    end

    local era = { quests = 0, levelSame = 0, levelDiff = 0, preSame = 0, preDiff = 0 }
    for _, id in ipairs(sortedKeys(att.quests)) do
        local a, q = att.quests[id], base.quests[id]
        if q then
            era.quests = era.quests + 1
            local lvl = tonumber(q[Q_REQLEVEL])
            if a.reqLevel and lvl and lvl > 0 then
                if a.reqLevel == lvl then era.levelSame = era.levelSame + 1 else era.levelDiff = era.levelDiff + 1 end
            end
            local want = {}
            for _, f in ipairs({ Q_PRESINGLE, Q_PREGROUP }) do
                for _, p in ipairs(type(q[f]) == "table" and q[f] or {}) do want[p] = true end
            end
            if a.pre and next(want) then
                local same = count(want) == #a.pre
                for _, p in ipairs(a.pre) do if not want[p] then same = false end end
                if same then era.preSame = era.preSame + 1 else era.preDiff = era.preDiff + 1 end
            end
        end
    end

    io.stderr:write(("-- att: %d quest(s) in %d file(s), %d row(s) merged, %d filled, %d known answer(s) confirmed, %d mismatch(es), %d start point(s) within %.1f, %d with no comparable point, %d prerequisite list(s) not expressible, %d prerequisite change(s)\n")
        :format(count(att.quests), att.files, attStats.rows, attStats.filled, attStats.confirmed, attStats.mismatched,
                placed, PLACE_TOLERANCE, unplaced, attStats.dropped, #attWaived))
    io.stderr:write(("-- att era check: %d Era quest(s), required level %d same %d differ, prerequisites %d same %d differ\n")
        :format(era.quests, era.levelSame, era.levelDiff, era.preSame, era.preDiff))
    for _, why in ipairs(sortedKeys(attSkipped)) do
        io.stderr:write(("-- att skipped, %s: %s\n"):format(why, table.concat(attSkipped[why], " ")))
    end
    for _, line in ipairs(attWaived) do io.stderr:write(line .. "\n") end
    for _, line in ipairs(attSkipNotes) do io.stderr:write(line .. "\n") end
    for _, line in ipairs(attIssues) do io.stderr:write(line .. "\n") end
end
