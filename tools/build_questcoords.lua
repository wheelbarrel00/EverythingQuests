-- Derives quest location tables for the Classic flavors from an upstream dataset.
--
--   lua5.1 tools/build_questcoords.lua <dataDir> [mode] [encoding] [uiMapId]
--     mode      objective | turnin | both | spawns | npcs | available | category | srcnames
--                 (default both: one point per quest, objective with turn-in as fallback)
--                 (spawns: EVERY objective location, clustered - a different table, see below)
--                 (npcs: which creatures advance each quest - no coordinates, for nameplates)
--                 (available: where a quest can be PICKED UP, plus every gate that decides
--                  whether it can be, for quests that are not in the log yet)
--                 (turnin: where each quest is HANDED IN, clustered per map. The both mode's
--                  point is the OBJECTIVE for any quest that has one, so it answers a different
--                  question and puts a finished quest's pin back on the field you farmed.)
--                 (srcnames: names for the creatures and objects that start or finish a quest,
--                  one for every id the available and turnin tables reference, bar an unnamed
--                  supplement source or an Era placeholder only supplement quests use. Rerun it
--                  whenever either of those is regenerated.)
--     encoding  packed | table                (default packed - see the memory note below)
--     uiMapId   optional, emit one zone only, for a pilot
--
-- Run it on real Lua 5.1.5, the version the game uses. <dataDir> holds the upstream files
-- listed in SOURCES below. Their rows are Lua literals inside a [[return {...}]] long string,
-- so they are loadstring'd rather than parsed.
--
-- objective and both emit one waypoint per quest as ns.CLASSIC_QUEST_COORDS. Every other mode
-- emits a table under its own global name, so those can ship beside it.
--
-- Packed is the default because a per-row {m=,x=,y=} table measured 1063 KB resident against
-- 192 KB packed, and it round-trips exactly. Do not tidy it back to a table.
--
-- Decode a packed value:
--   m = math.floor(v / 100000000)
--   x = math.floor((v % 100000000) / 10000) / 10000
--   y = (v % 10000) / 10000

local dir, mode, encoding, zoneFilter = ...
dir = dir or "."
mode = mode or "both"
encoding = encoding or "packed"
zoneFilter = tonumber(zoneFilter)

-- The upstream dump ships one file set per flavor, told apart only by a filename prefix. It is
-- detected from the directory rather than passed as an argument, so the argument order is
-- unchanged and no caller can point one flavor's prefix at another flavor's directory. Keep one
-- flavor per directory: two sets in one is refused rather than resolved by preference order.
local FLAVOR_PREFIXES = { "classic", "tbc" }

local function detectPrefix()
    local found = {}
    for i = 1, #FLAVOR_PREFIXES do
        local f = io.open(dir .. "/" .. FLAVOR_PREFIXES[i] .. "QuestDB.lua", "rb")
        if f then f:close() found[#found + 1] = FLAVOR_PREFIXES[i] end
    end
    assert(#found > 0, "no <prefix>QuestDB.lua in " .. dir
                       .. " - expected one of: " .. table.concat(FLAVOR_PREFIXES, ", "))
    assert(#found == 1, "more than one flavor's files in " .. dir
                        .. " (" .. table.concat(found, ", ") .. ") - keep one per directory")
    return found[1]
end

local PREFIX = detectPrefix()

local SOURCES = {
    quests  = { file = PREFIX .. "QuestDB.lua",  marker = "questData = [["   },
    npcs    = { file = PREFIX .. "NpcDB.lua",    marker = "npcData = [["     },
    objects = { file = PREFIX .. "ObjectDB.lua", marker = "objectData = [["  },
    items   = { file = PREFIX .. "ItemDB.lua",   marker = "itemData = [["    },
    areaMap = { file = "areaIdToUiMapId.lua",    marker = "areaIdToUiMapId = [[" },
    -- Optional. Without it, objectives inside an instance simply get no pin.
    dungeons = { file = "dungeonEntrances.lua", marker = "dungeonEntrances = [[", optional = true },
}

-- Field indices, from the upstream schema.
local NPC_SPAWNS, OBJ_SPAWNS = 7, 4
local Q_FINISHEDBY, Q_OBJECTIVES = 3, 10
-- { text, { [areaId] = { {x, y}, ... } } }: the place an exploration quest is explored, or an escort ends.
local Q_TRIGGEREND = 9
local I_NPCDROPS, I_OBJDROPS = 2, 3
-- itemKeys.vendors. A quest item that is BOUGHT has neither of the two above, so without this
-- the quest collects no points and falls back to the single-point table, which is the turn-in.
local I_VENDORS = 14

-- Read by the available mode only. Every one of these decides whether a quest that is NOT in
-- the log can be picked up, which is the one question the client cannot answer for itself.
local Q_NAME, Q_STARTEDBY = 1, 2
local Q_REQLEVEL, Q_QUESTLEVEL, Q_RACES, Q_CLASSES = 4, 5, 6, 7
local Q_PREGROUP, Q_PRESINGLE, Q_EXCLUSIVE = 12, 13, 16
local Q_REQSKILL, Q_MINREP, Q_MAXREP = 18, 19, 20
-- Read by the category mode. Positive is an area id, negative is a class or profession sort.
-- Only the positive half is used - the sort enum is not in the dump and guessing it would
-- mislabel 983 quests on Era.
local Q_ZONEORSORT = 17
local Q_NEXTINCHAIN, Q_SPECIALFLAGS, Q_PARENT = 22, 24, 25
-- The client's own quest flags: daily, and offered to the whole group as one player takes it (escorts). 64 is raid, not PvP
local Q_FLAGS, DAILY_FLAG, PARTY_ACCEPT_FLAG = 23, 4096, 2
-- The dump sets no PvP flag, so a battleground quest is known by its battleground's areas or TBC's Battlegrounds sort, -25
local BATTLEGROUND_AREAS = { [2597] = true, [2839] = true, [3277] = true, [3358] = true, [3820] = true, [-25] = true }
-- PvP quests filed elsewhere: battleground quests under the capitals and Ashenvale, Forever's Darkspear Islands, TBC's world PvP
local PVP_QUESTS = {}
for _, id in ipairs({ 7863, 7864, 7865, 7866, 7867, 7868, 8367, 8371, 8385, 8388, 98887, 98889, 98891, 98893, 98895, 98897,
                      98899, 98901, 98903, 98904, 98905, 98906, 98907, 98908, 10106, 10110, 11502, 11503, 11505, 11506 }) do
    PVP_QUESTS[id] = true
end

local function loadBlock(spec)
    local path = dir .. "/" .. spec.file
    local f = io.open(path, "rb")
    if not f and spec.optional then return nil end
    assert(f, "cannot open " .. path)
    local src = f:read("*a")
    f:close()
    local at = assert(src:find(spec.marker, 1, true), "marker not found in " .. path)
    local s = src:find("return {", at, true)
    local e = src:find("}]]", s, true)
    assert(s and e, "block delimiters not found in " .. path)
    return assert(loadstring(src:sub(s, e)))()
end

local quests  = loadBlock(SOURCES.quests)
local npcs    = loadBlock(SOURCES.npcs)
local objects = loadBlock(SOURCES.objects)
local items   = loadBlock(SOURCES.items)
local area2ui  = loadBlock(SOURCES.areaMap)
local entrances = loadBlock(SOURCES.dungeons)

-- peerRows.lua, from build_peer_rows.lua: a peer database's values, false clearing one, in the dump's map space for the conversion.
local placesFilled = false
do
    local path = dir .. "/peerRows.lua"
    local f = io.open(path, "rb")
    if f then
        f:close()
        local peer, n = assert(loadfile(path))(), 0
        for name, into in pairs({ quests = quests, npcs = npcs, objects = objects, items = items }) do
            for id, row in pairs(peer[name] or {}) do
                local have = into[id]
                if not have then
                    into[id] = row
                else
                    for field, v in pairs(row) do
                        if v == false then have[field] = nil else have[field] = v end
                    end
                end
                n = n + 1
            end
        end
        io.stderr:write(("-- peer rows: %d row(s) taken\n"):format(n))
        placesFilled = true
    end
end

-- foreverMaps.lua holds { [uiMapID] = { ax, bx, ay, by } } from both clients' map rectangles, b as a
-- map fraction. The conversion runs BEFORE the overlay, whose rows were read on Forever already.
local mapFix
do
    local path = dir .. "/foreverMaps.lua"
    local f = io.open(path, "rb")
    if f then
        f:close()
        assert(PREFIX == "classic", "a Forever map conversion cannot be applied to " .. PREFIX .. " data")
        mapFix = assert(loadfile(path))()
    end
end
local function applyMapConversion()
    local byArea, areas = {}, 0
    for areaId, ui in pairs(area2ui) do
        if mapFix[ui] then byArea[areaId] = mapFix[ui]; areas = areas + 1 end
    end
    local moved, offMap = 0, 0
    -- A point converted past the edge is not on this map, so it becomes the -1,-1 sentinel instead of
    -- being clamped to the edge. A sentinel is never converted, or it would become a real place.
    local function convert(byAreaList)
        for areaId, pts in pairs(byAreaList) do
            local t = byArea[areaId]
            if t and type(pts) == "table" then
                for i = 1, #pts do
                    local p = pts[i]
                    local x = type(p) == "table" and tonumber(p[1])
                    local y = type(p) == "table" and tonumber(p[2])
                    if x and y and x > 0 and y > 0 then
                        local nx, ny = t[1] * x + t[2] * 100, t[3] * y + t[4] * 100
                        if nx > 0 and ny > 0 and nx < 100 and ny < 100 then
                            p[1], p[2] = nx, ny
                            moved = moved + 1
                        else
                            p[1], p[2] = -1, -1
                            offMap = offMap + 1
                        end
                    end
                end
            end
        end
    end
    for _, rec in pairs(npcs) do
        if type(rec[NPC_SPAWNS]) == "table" then convert(rec[NPC_SPAWNS]) end
    end
    for _, rec in pairs(objects) do
        if type(rec[OBJ_SPAWNS]) == "table" then convert(rec[OBJ_SPAWNS]) end
    end
    for _, rec in pairs(quests) do
        local te = rec[Q_TRIGGEREND]
        if type(te) == "table" and type(te[2]) == "table" then convert(te[2]) end
    end
    if entrances then
        for _, row in pairs(entrances) do
            local coords = type(row) == "table" and row[2]
            for i = 1, type(coords) == "table" and #coords or 0 do
                local c = coords[i]
                local t = type(c) == "table" and byArea[c[1]]
                local x, y = t and tonumber(c[2]), t and tonumber(c[3])
                if x and y and x > 0 and y > 0 then
                    local nx, ny = t[1] * x + t[2] * 100, t[3] * y + t[4] * 100
                    if nx > 0 and ny > 0 and nx < 100 and ny < 100 then
                        c[2], c[3] = nx, ny
                        moved = moved + 1
                    else
                        c[2], c[3] = -1, -1
                        offMap = offMap + 1
                    end
                end
            end
        end
    end
    local maps = 0
    for _ in pairs(mapFix) do maps = maps + 1 end
    io.stderr:write(("-- map conversion: %d map(s) over %d area(s), %d point(s) moved, %d left the map\n")
        :format(maps, areas, moved, offMap))
end
if mapFix then applyMapConversion() end

-- A supplement in the same directory as its base flavor, written by build_forever_supplement.lua.
-- Its rows replace or add whole rows, so WoW Forever runs the Era data plus what its client added.
local OVERLAYS = { forever = "classic" }
local overlaid = {}
for name, baseFlavor in pairs(OVERLAYS) do
    local f = io.open(dir .. "/" .. name .. "QuestDB.lua", "rb")
    if f then
        f:close()
        assert(PREFIX == baseFlavor, ("%s rows sit on %s data, not %s"):format(name, baseFlavor, PREFIX))
        local report = {}
        for _, t in ipairs({ { quests, "QuestDB.lua", SOURCES.quests.marker },
                             { npcs, "NpcDB.lua", SOURCES.npcs.marker },
                             { objects, "ObjectDB.lua", SOURCES.objects.marker },
                             { items, "ItemDB.lua", SOURCES.items.marker } }) do
            local rows = loadBlock({ file = name .. t[2], marker = t[3] })
            local added, replaced = 0, 0
            overlaid[t[1]] = overlaid[t[1]] or {}
            for id, row in pairs(rows) do
                if t[1][id] then replaced = replaced + 1 else added = added + 1; overlaid[t[1]][id] = true end
                t[1][id] = row
            end
            report[#report + 1] = ("%s +%d ~%d"):format(t[2], added, replaced)
        end
        io.stderr:write(("-- overlay %s: %s\n"):format(name, table.concat(report, ", ")))
    end
end

-- foreverClientObjectives.lua, from build_forever_supplement.lua: each quest's objective types as the game lists them.
local clientObj
do
    local path = dir .. "/foreverClientObjectives.lua"
    local f = io.open(path, "rb")
    if f then
        f:close()
        clientObj = assert(loadfile(path))()
    end
end

-- peerForeverRows.lua, from build_peer_forever.lua: a peer database's Forever traces and fixes, after the conversion, in order.
do
    local path = dir .. "/peerForeverRows.lua"
    local f = io.open(path, "rb")
    if f then
        f:close()
        assert(PREFIX == "classic", "Forever traces cannot be applied to " .. PREFIX .. " data")
        local peer = assert(loadfile(path))()
        -- Converted Era points are not round numbers, so a point the peer gives to two decimals matches within 0.01
        local function near(p, q) return p == q or (type(p) == "number" and type(q) == "number" and math.abs(p - q) < 0.01) end
        local function same(a, b)
            if type(a) ~= "table" or type(b) ~= "table" then return a == b end
            return near(a[1], b[1]) and near(a[2], b[2])
        end
        local function fits(o, list)
            if type(o) ~= "table" then return false end
            local want = { monster = 0, object = 0, item = 0 }
            for _, t in ipairs(list) do if want[t] then want[t] = want[t] + 1 end end
            -- A stand-in for an unplaced objective counts, being the game's own list without a place, so a peer list of other kinds is refused
            local function n(t) return type(t) == "table" and #t or 0 end
            return n(o[1]) + n(o[5]) == want.monster and n(o[2]) == want.object and n(o[3]) == want.item
        end
        local function merge(list, v, drop)
            local out = {}
            for _, x in ipairs(type(list) == "table" and list or {}) do
                local gone = false
                if drop then for _, y in ipairs(v) do if same(x, y) then gone = true end end end
                if not gone then out[#out + 1] = x end
            end
            if not drop then
                for _, y in ipairs(v) do
                    local have = false
                    for _, x in ipairs(out) do if same(x, y) then have = true end end
                    if not have then out[#out + 1] = y end
                end
            end
            return out
        end
        -- {creatures, objects, items} and the objective slots merge slot by slot, places zone by zone, the rest as a list
        local SLOTTED = { quests = { [2] = 3, [3] = 3, [10] = 6 } }
        local ZONED = { npcs = { [7] = true }, objects = { [4] = true } }
        local function change(name, row, field, op, v)
            local old = row[field]
            if op == "fill" then
                if old == nil or old == "" then row[field] = v end
            elseif op == "set" then
                row[field] = v
            elseif type(v) == "table" then
                local drop = op == "remove"
                local slots = SLOTTED[name] and SLOTTED[name][field]
                if slots then
                    old = type(old) == "table" and old or {}
                    for s = 1, slots do if type(v[s]) == "table" then old[s] = merge(old[s], v[s], drop) end end
                    row[field] = old
                elseif ZONED[name] and ZONED[name][field] then
                    old = type(old) == "table" and old or {}
                    for zone, pts in pairs(v) do old[zone] = merge(old[zone], pts, drop) end
                    row[field] = old
                else
                    row[field] = merge(old, v, drop)
                end
            end
        end
        local applied, skipped, kept = 0, 0, 0
        for name, into in pairs({ quests = quests, npcs = npcs, objects = objects, items = items }) do
            for id, ops in pairs(peer[name] or {}) do
                local row = into[id]
                if not row and name ~= "quests" then row = {}; into[id] = row end
                if row then
                    for _, o in ipairs(ops) do
                        local list = name == "quests" and o[1] == 10 and o[2] == "set" and clientObj and clientObj[id]
                        -- An objective list that already has the kinds the game lists is not swapped for one that does not
                        if list and fits(row[10], list) and not fits(o[3], list) then
                            kept = kept + 1
                        else
                            change(name, row, o[1], o[2], o[3])
                            applied = applied + 1
                        end
                    end
                else
                    skipped = skipped + 1
                end
            end
        end
        io.stderr:write(("-- peer Forever rows: %d operation(s) applied, %d quest(s) the data does not hold left out, %d objective list(s) kept as the game lists them\n")
            :format(applied, skipped, kept))
    end
end

-- Upstream rows that contradict AllTheThings and their givers' factions, fixed in every mode. One that no longer matches is reported and left alone.
-- 8228 is the Horde flier at Grinkle in Orgrimmar, 8229 the Alliance one at Barrus in Ironforge. 3645 is the Horde card renewal at Oglethorpe after 3643, 3647 the Alliance one at Tinkmaster after 3641.
local CORRECTIONS = {
    { id = 8228, from = 15119, to = 15116 }, { id = 8229, from = 15116, to = 15119 },
    { id = 3645, from = 7944, to = 7406, pre = { 3641, 3643 } }, { id = 3647, from = 7406, to = 7944, pre = { 3643, 3641 } },
}
-- Each part is judged on its own against where it starts and where it should end, so one an upstream fix already made is reported.
for _, c in ipairs(CORRECTIONS) do
    local q = quests[c.id]
    if not q then
        io.stderr:write(("-- correction not applied, quest %d is not in the data\n"):format(c.id))
    else
        local sb, fb = q[Q_STARTEDBY], q[Q_FINISHEDBY]
        local function only(by, v) return type(by) == "table" and type(by[1]) == "table" and #by[1] == 1 and by[1][1] == v end
        if only(sb, c.to) and only(fb, c.to) then
            io.stderr:write(("-- correction no longer needed: quest %d is already given and handed in at %d\n"):format(c.id, c.to))
        elseif only(sb, c.from) and only(fb, c.from) then
            sb[1], fb[1] = { c.to }, { c.to }
            io.stderr:write(("-- correction: quest %d is given and handed in at %d, not %d\n"):format(c.id, c.to, c.from))
        else
            io.stderr:write(("-- CORRECTION CONFLICT: quest %d's giver or finisher is neither %d nor %d, left alone\n"):format(c.id, c.from, c.to))
        end
        if c.pre then
            local pre = q[Q_PRESINGLE]
            local one = type(pre) == "table" and #pre == 1 and pre[1]
            if one == c.pre[2] then
                io.stderr:write(("-- correction no longer needed: quest %d already follows %d\n"):format(c.id, c.pre[2]))
            elseif one == c.pre[1] then
                q[Q_PRESINGLE] = { c.pre[2] }
                io.stderr:write(("-- correction: quest %d follows %d, not %d\n"):format(c.id, c.pre[2], c.pre[1]))
            else
                io.stderr:write(("-- CORRECTION CONFLICT: quest %d's prerequisite is neither %d nor %d, left alone\n"):format(c.id, c.pre[1], c.pre[2]))
            end
        end
    end
end

-- foreverStarts.lua holds { [questID] = { {areaId, x, y[, 1 for an ATT point]}, ... } }, where that quest is offered on Forever.
local ownStarts
do
    local path = dir .. "/foreverStarts.lua"
    local f = io.open(path, "rb")
    if f then
        f:close()
        assert(PREFIX == "classic", "Forever start points cannot be applied to " .. PREFIX .. " data")
        ownStarts = assert(loadfile(path))()
    end
end

-- An item objective keeps KIND_LOOT even though it resolves through the NPC that drops it,
-- because "loot it here" is the player-facing fact.
local KIND_SLAY, KIND_OBJECT, KIND_LOOT = 1, 2, 3

-- An entrance point is the same kind plus this, so the reader recovers the real kind by
-- subtracting and the objective index still means "the nth objective of that type".
local KIND_ENTRANCE = 4
-- A place to reach, quest field 9. No objective type matches it, so the map keeps its pin until the quest is done.
local KIND_EXPLORE = 4

-- Start and turn-in points carry the creature or object that produced them in a 1e9 slot.
-- The bound guards the packing rather than recording a maximum: at 1e6 the worst packed value
-- stays under 1e15 against the 9.007e15 exact integer ceiling.
-- Loud rather than clamped, because a silently truncated id would name a different creature.
local MAX_SRC_ID = 1000000

-- areaId -> { {parentAreaId, x, y}, ... }. A dungeon has two area ids used interchangeably
-- upstream, so the alternative id is registered too or the busiest dungeons answer nothing.
local entranceFor = {}
if entrances then
    for areaId, row in pairs(entrances) do
        local alt, coords = row[1], row[2]
        if type(coords) == "table" and #coords > 0 then
            entranceFor[areaId] = coords
            if alt and alt ~= false then entranceFor[alt] = coords end
        end
    end
end

-- Set for the duration of one quest's objective walk. An objective that only ever answered
-- "exists here, location unknown" is inside an instance, so its entrance is the only honest pin.
local realSeen, sentinelSeen

-- Set while walking a quest that carries both creature and killCredit objectives. See the note
-- in objectivePoints.
local ambiguousMonster, monsterCount

-- "A", "H" or nil for the quest being walked. Vendors are stationary and faction locked, so
-- without this an item sold in both capitals pins a Horde quest in Stormwind. Race mask first,
-- then the quest giver, because war effort quests name a faction in the title and mask 0.
local N_FACTION = 13
local RACES_ALLIANCE, RACES_HORDE = 1 + 4 + 8 + 64 + 1024, 2 + 16 + 32 + 128 + 512
local questFaction

-- Upstream creatures tagged with one faction that both factions talk to. The Earthen Ring Elder stands in the capitals.
local NPC_CORRECTIONS = { { id = 26221, prefix = "tbc", from = "A", to = "AH" } }
for _, c in ipairs(NPC_CORRECTIONS) do
    if c.prefix == PREFIX then
        local n = npcs[c.id]
        if n and n[N_FACTION] == c.from then
            n[N_FACTION] = c.to
            io.stderr:write(("-- correction: creature %d is friendly to %s, not %s\n"):format(c.id, c.to, c.from))
        else
            io.stderr:write(("-- correction no longer needed: creature %d\n"):format(c.id))
        end
    end
end

local function factionOfRaces(mask)
    if type(mask) ~= "number" or mask <= 0 then return nil end
    local a, h = 0, 0
    for bit = 0, 10 do
        local b = 2 ^ bit
        if mask % (b + b) >= b then
            if RACES_ALLIANCE % (b + b) >= b then a = a + 1 end
            if RACES_HORDE % (b + b) >= b then h = h + 1 end
        end
    end
    if a > 0 and h == 0 then return "A" end
    if h > 0 and a == 0 then return "H" end
    return nil
end

-- srcID is the creature or object that produced the point, carried so a start or turn-in pin can
-- name who is standing there. Only the coordinate modes that emit it pass one - the spawn walk
-- leaves it nil, so QuestSpawns is byte identical.
local function collect(out, rec, idx, kind, objIdx, srcID)
    local sp = rec and rec[idx]
    if type(sp) ~= "table" then return end
    local om = (kind == KIND_SLAY) and ambiguousMonster or nil
    for areaId, pts in pairs(sp) do
        if type(areaId) == "number" and areaId > 0 and type(pts) == "table" then
            local key = objIdx and (kind * 100 + objIdx)
            for i = 1, #pts do
                local p = pts[i]
                local px = type(p) == "table" and tonumber(p[1])
                local py = type(p) == "table" and tonumber(p[2])
                -- -1,-1 means "exists, location unknown". It is a sentinel, not a place, and
                -- averaging it in drags the pin off the map.
                if px and py and px > 0 and py > 0 then
                    out[#out + 1] = { a = areaId, x = px, y = py, k = kind, oi = objIdx, om = om,
                                      s = srcID }
                    -- Gated on area2ui because a real coordinate in an unmapped area still
                    -- produces no cell, and would otherwise suppress the entrance fallback
                    if key and realSeen and area2ui[areaId] then realSeen[key] = true end
                elseif key and sentinelSeen then
                    local t = sentinelSeen[key]
                    if not t then t = {}; sentinelSeen[key] = t end
                    t[areaId] = true
                end
            end
        end
    end
end

-- Sorted, not pairs order. A rerun has to be byte identical and hash order is not stable.
local function appendEntrances(out)
    if not (realSeen and sentinelSeen) then return end
    local keys = {}
    for key in pairs(sentinelSeen) do
        if not realSeen[key] then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for i = 1, #keys do
        local key = keys[i]
        local kind, objIdx = math.floor(key / 100), key % 100
        local areas = {}
        for areaId in pairs(sentinelSeen[key]) do areas[#areas + 1] = areaId end
        table.sort(areas)
        for j = 1, #areas do
            local coords = entranceFor[areas[j]]
            if coords then
                for c = 1, #coords do
                    -- A map conversion can turn an entrance into the -1,-1 sentinel.
                    if coords[c][2] > 0 and coords[c][3] > 0 then
                        out[#out + 1] = { a = coords[c][1], x = coords[c][2], y = coords[c][3],
                                          k = kind + KIND_ENTRANCE, oi = objIdx }
                    end
                end
            end
        end
    end
end

-- Set while walking one quest's objectives, so the spawn walk also yields the creature list.
-- Nil everywhere else, including turninPoints, which keeps the coordinate modes byte identical.
local npcSink

-- objIdx is the position within its own type bucket, or a mob dropping one of four quest items
-- claims all four.
local function collectNpc(out, id, kind, objIdx)
    kind = kind or KIND_SLAY
    if npcSink and type(id) == "number" and id > 0 and objIdx then
        local byIdx = npcSink[id]
        if not byIdx then byIdx = {}; npcSink[id] = byIdx end
        -- An ambiguous monster bucket claims every one of its indices, for the reason in
        -- objectivePoints - the alternative is an icon that goes blank on the wrong objective.
        local first, last = objIdx, objIdx
        if kind == KIND_SLAY and monsterCount then first, last = 0, monsterCount - 1 end
        for i = first, last do
            local prev = byIdx[i]
            -- Lower kind wins, so a real kill objective outranks the same mob merely dropping an item
            if not prev or kind < prev then byIdx[i] = kind end
        end
    end
    collect(out, npcs[id], NPC_SPAWNS, kind, objIdx)
end

local function collectObj(out, id, kind, objIdx)
    collect(out, objects[id], OBJ_SPAWNS, kind or KIND_OBJECT, objIdx)
end

-- Caps the mob list only. Uncapped, a common trade good lights every mob in the zone up for one
-- gathering quest. Map pins must not use a cutoff - it drops whole quests to zero pins.
local MAX_ITEM_SOURCES = 15

local function collectItem(out, id, objIdx)
    local it = items[id]
    if not it then return end
    local drops = it[I_NPCDROPS]
    if type(drops) == "table" then
        -- The cutoff gates the sink only. collect() still runs for every source, which keeps
        -- the spawn table byte identical.
        local saved = npcSink
        if #drops > MAX_ITEM_SOURCES then npcSink = nil end
        for i = 1, #drops do collectNpc(out, drops[i], KIND_LOOT, objIdx) end
        npcSink = saved
    end
    local odrops = it[I_OBJDROPS]
    if type(odrops) == "table" then
        for i = 1, #odrops do collectObj(out, odrops[i], KIND_LOOT, objIdx) end
    end
    -- A bought item. Same KIND_LOOT because the player-facing fact is "get the item here".
    local vendors = it[I_VENDORS]
    if type(vendors) == "table" then
        -- Vendors reach 184 for one item on Era, so the same cutoff gates the mob list here too.
        local saved = npcSink
        if #vendors > MAX_ITEM_SOURCES then npcSink = nil end
        for i = 1, #vendors do
            local v = npcs[vendors[i]]
            local vf = v and v[N_FACTION]
            -- Only when both sides are known and opposite. An "AH" or unknown vendor is kept,
            -- because a surplus pin is visible and a missing one is silent.
            if not (questFaction and (vf == "A" or vf == "H") and vf ~= questFaction) then
                collectNpc(out, vendors[i], KIND_LOOT, objIdx)
            end
        end
        npcSink = saved
    end
end

-- Deterministic so a rerun is byte identical. Snaps to a real spawn because a raw centroid can
-- land in terrain no player can stand on when a mob spawns in two clusters.
local function pick(points)
    if #points == 0 then return nil end
    local byArea, order = {}, {}
    for i = 1, #points do
        local p = points[i]
        local t = byArea[p.a]
        if not t then t = {}; byArea[p.a] = t; order[#order + 1] = p.a end
        t[#t + 1] = p
    end
    table.sort(order)
    local bestA, bestN = nil, -1
    for i = 1, #order do
        if #byArea[order[i]] > bestN then bestA, bestN = order[i], #byArea[order[i]] end
    end
    local grp = byArea[bestA]
    local sx, sy = 0, 0
    for i = 1, #grp do sx = sx + grp[i].x; sy = sy + grp[i].y end
    local mx, my = sx / #grp, sy / #grp
    local best, bestD
    for i = 1, #grp do
        local dx, dy = grp[i].x - mx, grp[i].y - my
        local d = dx * dx + dy * dy
        if not bestD or d < bestD then best, bestD = grp[i], d end
    end
    return bestA, best.x, best.y
end

-- attObjectives.lua, from build_att_rules.lua or build_forever_supplement.lua --att: AllTheThings' place for each objective.
local attObj, uiArea, attStats
do
    local path = dir .. "/attObjectives.lua"
    local f = io.open(path, "rb")
    if f then
        f:close()
        attObj = assert(loadfile(path))()
        uiArea = {}
        for areaId, ui in pairs(area2ui) do
            if type(areaId) == "number" and areaId > 0 and (not uiArea[ui] or areaId < uiArea[ui]) then uiArea[ui] = areaId end
        end
        attStats = { quests = 0, objectives = 0, spots = 0, unmatched = 0, unmapped = 0, setAside = 0, graded = 0, near = 0,
                     clientChecked = 0, clientAgree = 0 }
    end
end
-- The world and continent maps, where a pin would sit in the middle of a continent.
local NOT_A_ZONE = { [947] = true, [1414] = true, [1415] = true, [1945] = true }
-- uiMapID -> the lowest dungeon area drawn on it, for a place ATT gives inside an instance.
local dungeonOf = {}
-- A battleground's own map is drawn, and the dump stands creatures on it, so it is no dungeon here
local drawnInside = {}
for _, n in pairs(npcs) do
    local sp = n[NPC_SPAWNS]
    if type(sp) == "table" then
        for areaId, list in pairs(sp) do
            if entranceFor[areaId] and type(list) == "table" and type(list[1]) == "table" and (list[1][1] or -1) >= 0 then
                drawnInside[areaId] = true
            end
        end
    end
end
do
    local kept = {}
    for areaId in pairs(drawnInside) do kept[#kept + 1] = areaId end
    table.sort(kept)
    if #kept > 0 then io.stderr:write(("-- instance areas the dump stands creatures in, kept off the entrance rule: %s\n"):format(table.concat(kept, ", "))) end
end
for areaId in pairs(entranceFor) do
    local ui = not drawnInside[areaId] and area2ui[areaId]
    if ui and (not dungeonOf[ui] or areaId < dungeonOf[ui]) then dungeonOf[ui] = areaId end
end
-- An ATT place this close to one of the dump's own places for the same objective agrees with it, in map units.
local ATT_NEAR = 5

local function attBuckets(o)
    local list = {}
    local function add(kind, idx, field, ids) list[#list + 1] = { kind = kind, idx = idx, field = field, ids = ids } end
    local n1 = type(o[1]) == "table" and #o[1] or 0
    for i = 1, n1 do local e = o[1][i]; if type(e) == "table" and e[1] then add(KIND_SLAY, i - 1, "npc", { e[1] }) end end
    for i = 1, type(o[2]) == "table" and #o[2] or 0 do local e = o[2][i]; if type(e) == "table" and e[1] then add(KIND_OBJECT, i - 1, "obj", { e[1] }) end end
    for i = 1, type(o[3]) == "table" and #o[3] or 0 do local e = o[3][i]; if type(e) == "table" and e[1] then add(KIND_LOOT, i - 1, "item", { e[1] }) end end
    for i = 1, type(o[5]) == "table" and #o[5] or 0 do
        local e = o[5][i]
        if type(e) == "table" and type(e[1]) == "table" then add(KIND_SLAY, n1 + i - 1, "npc", e[1]) end
    end
    return list
end

-- An item names the objective most surely, then an object, then a creature, because ATT also names the creature that drops an item.
local function attBucketFor(row, buckets)
    for _, field in ipairs({ "item", "obj", "npc" }) do
        local named = {}
        for _, v in ipairs(row[field] or {}) do named[v] = true end
        for _, b in ipairs(buckets) do
            if b.field == field then
                for _, v in ipairs(b.ids) do if named[v] then return b end end
            end
        end
    end
end

local CLIENT_KIND = { monster = KIND_SLAY, object = KIND_OBJECT, item = KIND_LOOT }

-- ATT's objective n in the game's list, as the masks number it. A log line gets none, as ATT puts it at the hand-in (A Rogue's Deal, 8).
local function clientBucket(list, n)
    local t = type(n) == "number" and list[n]
    local kind = t and CLIENT_KIND[t]
    if not kind then return nil end
    local idx = 0
    for i = 1, n - 1 do if list[i] == t then idx = idx + 1 end end
    return { kind = kind, idx = idx }
end

local function attFill(pts, q, id)
    local rows, o = attObj and attObj[id], q[Q_OBJECTIVES]
    local list = clientObj and clientObj[id]
    if not rows or (type(o) ~= "table" and not list) then return end
    local buckets = type(o) == "table" and attBuckets(o) or {}
    local have = {}
    for _, p in ipairs(pts) do
        local k = p.k > KIND_ENTRANCE and p.k - KIND_ENTRANCE or p.k
        local key = k * 100 + p.oi
        have[key] = have[key] or {}
        have[key][#have[key] + 1] = p
    end
    local added = false
    for _, row in ipairs(rows) do
        local b = attBucketFor(row, buckets)
        local c = list and clientBucket(list, row.n)
        if b and c then
            attStats.clientChecked = attStats.clientChecked + 1
            if b.kind == c.kind and b.idx == c.idx then attStats.clientAgree = attStats.clientAgree + 1 end
        end
        b = b or c
        if not b then
            attStats.unmatched = attStats.unmatched + 1
        else
            local key, at, own, inside = b.kind * 100 + b.idx, row.at, {}, {}
            for i = 1, #at, 3 do
                local ui, x, y = at[i], at[i + 1], at[i + 2]
                local t = mapFix and mapFix[ui]
                if dungeonOf[ui] then
                    -- Inside a dungeon, whose own map EQ never draws, so the way in stands for it as for the dump's own.
                    inside[dungeonOf[ui]] = true
                elseif NOT_A_ZONE[ui] or not uiArea[ui] then
                    attStats.unmapped = attStats.unmapped + 1
                elseif t and rows.fs then
                    -- ATT's Forever data mixes Era and Forever space on the maps Forever redrew.
                    attStats.setAside = attStats.setAside + 1
                else
                    if t then x, y = t[1] * x + t[2] * 100, t[3] * y + t[4] * 100 end
                    if x > 0 and y > 0 and x < 100 and y < 100 then own[#own + 1] = { a = uiArea[ui], x = x, y = y, ui = ui } end
                end
            end
            if have[key] then
                for _, s in ipairs(own) do
                    local best
                    for _, p in ipairs(have[key]) do
                        if area2ui[p.a] == s.ui then
                            local d = math.sqrt((p.x - s.x) ^ 2 + (p.y - s.y) ^ 2)
                            if not best or d < best then best = d end
                        end
                    end
                    if best then
                        attStats.graded = attStats.graded + 1
                        if best <= ATT_NEAR then attStats.near = attStats.near + 1 end
                    end
                end
            elseif #own > 0 or next(inside) then
                local om, before = (b.kind == KIND_SLAY) and ambiguousMonster or nil, #pts
                for _, s in ipairs(own) do
                    pts[#pts + 1] = { a = s.a, x = s.x, y = s.y, k = b.kind, oi = b.idx, om = om }
                    attStats.spots = attStats.spots + 1
                end
                local areas = {}
                if mode == "spawns" then
                    for areaId in pairs(inside) do areas[#areas + 1] = areaId end
                end
                table.sort(areas)
                for _, areaId in ipairs(areas) do
                    for _, way in ipairs(entranceFor[areaId]) do
                        if way[2] > 0 and way[3] > 0 then
                            pts[#pts + 1] = { a = way[1], x = way[2], y = way[3], k = b.kind + KIND_ENTRANCE, oi = b.idx, om = om }
                            attStats.entrances = (attStats.entrances or 0) + 1
                        end
                    end
                end
                if #pts > before then
                    attStats.objectives = attStats.objectives + 1
                    added = true
                end
            end
        end
    end
    if added then attStats.quests = attStats.quests + 1 end
end

-- Entrance points belong to the per-map tables only. The single point modes emit
-- ns.CLASSIC_QUEST_COORDS, which carries no kind field, so an entrance there is indistinguishable
-- from a real location.
local WANT_ENTRANCES = (mode == "spawns" or mode == "turnin")

local function objectivePoints(q, id)
    local pts, o = {}, q[Q_OBJECTIVES]
    if WANT_ENTRANCES then realSeen, sentinelSeen = {}, {} end
    ambiguousMonster, monsterCount = nil, nil
    questFaction = factionOfRaces(q[Q_RACES])
    if not questFaction then
        local sb = q[Q_STARTEDBY]
        if type(sb) == "table" and type(sb[1]) == "table" then
            for i = 1, #sb[1] do
                local g = npcs[sb[1][i]]
                local gf = g and g[N_FACTION]
                if gf == "A" or gf == "H" then
                    -- Two givers of opposite factions means a shared quest, so neither wins
                    if questFaction and questFaction ~= gf then questFaction = nil; break end
                    questFaction = gf
                end
            end
        end
    end
    local te = q[Q_TRIGGEREND]
    if type(te) == "table" then collect(pts, te, 2, KIND_EXPLORE, 0) end
    if type(o) ~= "table" then
        appendEntrances(pts)
        -- A quest the data lists no objectives for can still take ATT's places through the game's own list.
        if id and attObj then attFill(pts, q, id) end
        realSeen, sentinelSeen = nil, nil
        return pts
    end
    -- o[1] and o[5] are ONE index space in the quest log - the client reports both as type
    -- "monster", numbered by quest template slot. The dump does not preserve that slot, so a
    -- quest carrying both cannot be numbered reliably. Those points take every monster bit and
    -- stay until all of the quest's monster objectives are done, because a surplus pin is
    -- visible and a missing one is silent. Era has 0 such quests, TBC has 6, and 11885 is the only
    -- one where the bucket is wider than two.
    local n1 = type(o[1]) == "table" and #o[1] or 0
    local n5 = type(o[5]) == "table" and #o[5] or 0
    if n1 > 0 and n5 > 0 then
        monsterCount = n1 + n5
        ambiguousMonster = 2 ^ monsterCount - 1
    end
    if type(o[1]) == "table" then
        for i = 1, #o[1] do local e = o[1][i]; if type(e) == "table" and e[1] then collectNpc(pts, e[1], nil, i - 1) end end
    end
    if type(o[2]) == "table" then
        for i = 1, #o[2] do
            local e = o[2][i]
            if type(e) == "table" and e[1] then collectObj(pts, e[1], nil, i - 1) end
        end
    end
    if type(o[3]) == "table" then
        for i = 1, #o[3] do local e = o[3][i]; if type(e) == "table" and e[1] then collectItem(pts, e[1], i - 1) end end
    end
    if type(o[5]) == "table" then
        for i = 1, #o[5] do
            local e = o[5][i]
            if type(e) == "table" and type(e[1]) == "table" then
                for k = 1, #e[1] do collectNpc(pts, e[1][k], nil, n1 + i - 1) end
            end
        end
    end
    appendEntrances(pts)
    if id and attObj then attFill(pts, q, id) end
    realSeen, sentinelSeen = nil, nil
    ambiguousMonster, monsterCount = nil, nil
    return pts
end

-- objIdx 0 rather than nil so collect() tracks sentinels for the entrance fallback. A turn-in has
-- no objective index, and 0 is truthy in Lua, so the one slot is all it needs.
local TURNIN_IDX = 0

local function turninPoints(q)
    local pts, f = {}, q[Q_FINISHEDBY]
    if WANT_ENTRANCES then realSeen, sentinelSeen = {}, {} end
    if type(f) == "table" then
        if type(f[1]) == "table" then
            for i = 1, #f[1] do
                collect(pts, npcs[f[1][i]], NPC_SPAWNS, KIND_SLAY, TURNIN_IDX, f[1][i])
            end
        end
        if type(f[2]) == "table" then
            for i = 1, #f[2] do
                collect(pts, objects[f[2][i]], OBJ_SPAWNS, KIND_OBJECT, TURNIN_IDX, f[2][i])
            end
        end
        -- Entrance points carry no source: nobody stands at the way in, and the pin already says
        -- it is a dungeon entrance.
        appendEntrances(pts)
    end
    realSeen, sentinelSeen = nil, nil
    return pts
end

-- The same 1/2/3 the other tables use for creature, object and item, because the source of a
-- start point is the same three things. Here it means who OFFERS the quest, not what the
-- objective is, which is why the available table documents its own kinds rather than sharing.
local START_NPC, START_OBJECT, START_ITEM = 1, 2, 3

-- The supplement merges a giver's repeat visits within one map unit, so evidence that close is the same spot.
local SAME_SPOT = 1.0
local ownStats = { quests = 0, kept = 0, dropped = 0, added = 0 }

-- A giver in several places offers each quest at only some, and evidence far from every spot is a spot of the quest's own.
local function ownPoints(pts, own, sb)
    local usable, usableOn, setAside = {}, {}, {}
    for j = 1, #own do
        local ui = area2ui[own[j][1]]
        -- ATT reads some converted maps in Era space and some in Forever space, so its points choose nothing there
        if ui and own[j][4] == 1 and mapFix and mapFix[ui] then
            setAside[ui] = true
        elseif ui then
            usable[#usable + 1] = own[j]
            usableOn[ui] = true
        end
    end
    if #usable == 0 then return pts end
    ownStats.quests = ownStats.quests + 1
    local out, touched = {}, {}
    for i = 1, #pts do
        local p = pts[i]
        local ui = area2ui[p.a]
        -- A map whose only evidence was set aside has nothing to choose between its giver's spots with
        local keep = p.k == START_ITEM or (setAside[ui] and not usableOn[ui]) or false
        for j = 1, #usable do
            local e = usable[j]
            if area2ui[e[1]] == area2ui[p.a] and (p.x - e[2]) ^ 2 + (p.y - e[3]) ^ 2 <= SAME_SPOT ^ 2 then
                keep = true
                if p.k ~= START_ITEM then touched[j] = true end
            end
        end
        if keep then out[#out + 1] = p; ownStats.kept = ownStats.kept + 1 else ownStats.dropped = ownStats.dropped + 1 end
    end
    local kind, givers = START_NPC, sb[1]
    if type(givers) ~= "table" or #givers == 0 then kind, givers = START_OBJECT, sb[2] end
    if type(givers) ~= "table" or #givers == 0 then return out end
    local src = math.min(unpack(givers))
    local added = {}
    for j = 1, #usable do
        local e = usable[j]
        local dup = touched[j]
        for _, a in ipairs(added) do
            if area2ui[a.a] == area2ui[e[1]] and (a.x - e[2]) ^ 2 + (a.y - e[3]) ^ 2 <= SAME_SPOT ^ 2 then dup = true end
        end
        if not dup then
            local p = { a = e[1], x = e[2], y = e[3], k = kind, s = src }
            added[#added + 1] = p
            out[#out + 1] = p
            ownStats.added = ownStats.added + 1
        end
    end
    return out
end

-- Module scope rather than inside the available mode, because the srcnames mode has to gather
-- the very same points to know which names the shipped table will reference. Two copies of this
-- walk could drift and leave a name missing for a pin that asks for one.
local function giverPoints(q)
    local pts, sb = {}, q[Q_STARTEDBY]
    if type(sb) ~= "table" then return pts end
    if type(sb[1]) == "table" then
        for i = 1, #sb[1] do
            collect(pts, npcs[sb[1][i]], NPC_SPAWNS, START_NPC, nil, sb[1][i])
        end
    end
    if type(sb[2]) == "table" then
        for i = 1, #sb[2] do
            collect(pts, objects[sb[2][i]], OBJ_SPAWNS, START_OBJECT, nil, sb[2][i])
        end
    end
    -- A quest started by an ITEM is picked up wherever that item drops, so the pin marks
    -- the source rather than a person standing somewhere. No source id is carried: the dropper
    -- can be a creature or an object and the kind would not say which id space it came from.
    if type(sb[3]) == "table" then
        for i = 1, #sb[3] do
            local it = items[sb[3][i]]
            if it then
                local d = it[I_NPCDROPS]
                if type(d) == "table" then
                    for k = 1, #d do collect(pts, npcs[d[k]], NPC_SPAWNS, START_ITEM) end
                end
                local od = it[I_OBJDROPS]
                if type(od) == "table" then
                    for k = 1, #od do collect(pts, objects[od[k]], OBJ_SPAWNS, START_ITEM) end
                end
            end
        end
    end
    return pts
end

local function startPoints(q, id)
    local own, sb = ownStarts and ownStarts[id], q[Q_STARTEDBY]
    if own and type(sb) == "table" then return ownPoints(giverPoints(q), own, sb) end
    return giverPoints(q)
end

-- 0.01 merges spawns within about 1% of a zone into one pin, roughly the pin's own width.
-- No cap here - the limit is a user slider, so every cluster is emitted, densest first.
local SPAWN_GRID = 0.01

local function clusterByMap(points)
    local byMap = {}
    local cells = {}
    for i = 1, #points do
        local p = points[i]
        local ui = area2ui[p.a]
        if ui then
            local x, y = p.x / 100, p.y / 100
            local cx = math.floor(x / SPAWN_GRID)
            local cy = math.floor(y / SPAWN_GRID)
            -- Kind is part of the key because objIdx is numbered within its own type bucket, so
            -- one cell can only carry a mask for one kind.
            local key = ui .. ":" .. cx .. ":" .. cy .. ":" .. tostring(p.k)
            local c = cells[key]
            if not c then
                -- The cell keeps a real spawn rather than its center, which would drift into
                -- unreachable terrain. First one seen, so a rerun is byte identical.
                c = { m = ui, x = x, y = y, k = p.k, oim = 0, n = 0, seq = #(byMap[ui] or {}) }
                cells[key] = c
                byMap[ui] = byMap[ui] or {}
                table.insert(byMap[ui], c)
            end
            c.n = c.n + 1
            -- A bitmask because one location serves several objectives, and a single index would
            -- hide the pin as soon as one of them completed. Only the cell's own kind contributes.
            if p.k == c.k and p.oi then
                -- Spelled out: Lua 5.1 has no bit library
                local want = p.om or (2 ^ p.oi)
                local b = 1
                while b <= want do
                    if want % (b + b) >= b and c.oim % (b + b) < b then c.oim = c.oim + b end
                    b = b + b
                end
            end
        end
    end

    -- Densest first, and load bearing. The reader takes the first N, so re-sorting into map
    -- order would turn "the N best locations" into "N arbitrary locations".
    for _, list in pairs(byMap) do
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.seq < b.seq
        end)
    end
    return byMap
end

-- Same grid and same densest-first order as the spawn table, so a reader's prefix keeps the best
-- locations. No objective mask here - a start or turn-in point serves the whole quest.
local function clusterSimple(points)
    local byMap, cells = {}, {}
    for i = 1, #points do
        local p = points[i]
        local ui = area2ui[p.a]
        if ui then
            local x, y = p.x / 100, p.y / 100
            local key = ui .. ":" .. math.floor(x / SPAWN_GRID) .. ":"
                        .. math.floor(y / SPAWN_GRID) .. ":" .. tostring(p.k)
            local c = cells[key]
            if not c then
                -- The cell takes the FIRST point's source. A cell holding two sources is rare, a handful in
                -- thousands on each flavor, so the representative is the answer essentially always.
                c = { m = ui, x = x, y = y, k = p.k, s = p.s, n = 0, seq = #(byMap[ui] or {}) }
                cells[key] = c
                byMap[ui] = byMap[ui] or {}
                table.insert(byMap[ui], c)
            end
            c.n = c.n + 1
        end
    end
    for _, list in pairs(byMap) do
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.seq < b.seq
        end)
    end
    return byMap
end

local ids = {}
for id in pairs(quests) do ids[#ids + 1] = id end
table.sort(ids)

-- The assignment is a named constant because the shipped file wraps the constructor that
-- follows it into a long string, and the wrap has to find where the body starts.
local SPAWNS_ASSIGN = "ns.CLASSIC_QUEST_SPAWNS = {\n"

if mode == "spawns" then
    local emitted, sQuests, sPairs, widest, shared = 0, 0, 0, 0, 0
    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = { [uiMapID] = { packed, ... } }\n",
        "-- packed = objMask*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)\n",
        "-- kind 1=slay 2=object 3=loot 4=a place to reach (explore, an escort's end)\n",
        "-- and the same +4 (5,6,7,8) for a DUNGEON ENTRANCE: the objective is inside an instance\n",
        "-- whose interior coordinates nobody records, so the pin marks the way in. Recover the\n",
        "-- real kind by subtracting 4.\n",
        "-- objMask is a BITMASK of the objectives this location serves - bit i means the ith\n",
        "-- objective OF THIS KIND'S TYPE, 0 based, the same numbering Data/QuestNPCs_Classic\n",
        "-- uses. One location commonly serves several, which is why it is not a single index.\n",
        "-- decode: objMask = floor(v/1e9), kind = floor(v%1e9/1e8), rest = v%1e8,\n",
        "--         x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4\n",
        "-- Each list is ordered densest first. The reader draws the first N, so the order is\n",
        "-- what makes a pin limit keep the N best locations instead of N arbitrary ones.\n",
        SPAWNS_ASSIGN,
    }
    local expect = {}

    for i = 1, #ids do
        local id = ids[i]
        local byMap = clusterByMap(objectivePoints(quests[id], id))

        local maps = {}
        for m in pairs(byMap) do
            if (not zoneFilter) or m == zoneFilter then maps[#maps + 1] = m end
        end
        table.sort(maps)

        if #maps > 0 then
            sQuests = sQuests + 1
            local chunks = {}
            for k = 1, #maps do
                local m = maps[k]
                local list = byMap[m]
                sPairs = sPairs + 1
                if #list > widest then widest = #list end
                local nums, mine = {}, {}
                for j = 1, #list do
                    local xi = math.floor(list[j].x * 10000 + 0.5); if xi > 9999 then xi = 9999 end
                    local yi = math.floor(list[j].y * 10000 + 0.5); if yi > 9999 then yi = 9999 end
                    local kind = list[j].k or KIND_SLAY
                    local mask = list[j].oim or 0
                    -- Loud rather than clamped. An overflowing mask would name objectives that
                    -- do not exist. Widen the field if this fires.
                    assert(mask > 0 and mask <= 1023,
                           ("quest %d: objMask %s out of range"):format(id, tostring(mask)))
                    local rest, bits = mask, 0
                    while rest > 0 do
                        if rest % 2 == 1 then bits = bits + 1 end
                        rest = math.floor(rest / 2)
                    end
                    if bits > 1 then shared = shared + 1 end
                    local packed = mask * 1000000000 + kind * 100000000 + xi * 10000 + yi
                    nums[j] = ("%.0f"):format(packed)
                    -- v is the packed number itself. The wrap check below compares it exactly
                    -- and in order, which a decoded x/y/kind cannot do.
                    mine[j] = { x = xi / 10000, y = yi / 10000, k = kind, oim = mask, v = packed }
                    emitted = emitted + 1
                end
                expect[id] = expect[id] or {}
                expect[id][m] = mine
                chunks[#chunks + 1] = ("[%d]={%s}"):format(m, table.concat(nums, ","))
            end
            parts[#parts + 1] = ("\t[%d]={%s},\n"):format(id, table.concat(chunks, ","))
        end
    end
    parts[#parts + 1] = "}\n"
    local text = table.concat(parts)

    -- Right in memory and wrong on disk loads clean and is entirely dead, so every value is reread.
    do
        local probe = {}
        assert(loadstring(text))("EQ", probe)
        local got = assert(probe.CLASSIC_QUEST_SPAWNS, "emitted file did not define the table")
        local seen, worst = 0, 0
        for qid, maps in pairs(expect) do
            local gq = assert(got[qid], "quest missing after reload: " .. qid)
            for m, list in pairs(maps) do
                local gl = assert(gq[m], ("map %d missing after reload for quest %d"):format(m, qid))
                assert(#gl == #list, ("row count changed for quest %d map %d"):format(qid, m))
                for j = 1, #list do
                    local v = gl[j]
                    assert(type(v) == "number" and v >= 0,
                           ("quest %d serialized as %s - 32-bit overflow?"):format(qid, tostring(v)))
                    local mask = math.floor(v / 1000000000)
                    local kind = math.floor(v % 1000000000 / 100000000)
                    local rest = v % 100000000
                    local x, y = math.floor(rest / 10000) / 10000, (rest % 10000) / 10000
                    assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                           ("quest %d decoded out of range: %s,%s"):format(qid, x, y))
                    assert(kind == list[j].k,
                           ("quest %d kind changed on reload: %s vs %s"):format(qid, kind, list[j].k))
                    assert(mask == list[j].oim,
                           ("quest %d objMask changed on reload: %s vs %s")
                           :format(qid, mask, list[j].oim))
                    local d = math.max(math.abs(x - list[j].x), math.abs(y - list[j].y))
                    if d > worst then worst = d end
                    seen = seen + 1
                end
            end
        end
        assert(seen == emitted, "point count changed on reload")
        assert(worst <= 0.0001, "coordinate drift on reload: " .. worst)
        io.stderr:write(("-- verified %d point(s) by reload, max drift %.6f\n"):format(seen, worst))
    end

    -- Shipped as one long string, so login scans a single token and the constructor is parsed by
    -- the first caller, the minimap pin pass just after PLAYER_ENTERING_WORLD. A deferral, not a saving.
    local assignAt = assert(text:find(SPAWNS_ASSIGN, 1, true), "could not find the assignment")
    assert(not text:find(SPAWNS_ASSIGN, assignAt + #SPAWNS_ASSIGN, true),
           "the assignment appears more than once, so the slice is ambiguous")
    local head = text:sub(1, assignAt - 1)
    local bodyText = "{\n" .. text:sub(assignAt + #SPAWNS_ASSIGN)

    -- A long string is unusable if the payload contains its own terminator. The ASSEMBLED string
    -- is what has to be scanned: a body ending in "]" plus exactly this many equals signs carries
    -- no terminator of its own, yet closes the string early once the trailing "]" is appended.
    local eq = "=="
    local closeAt = #bodyText + 8   -- "return " is 7 characters, so the closer starts here
    while ("return " .. bodyText .. "]" .. eq .. "]"):find("]" .. eq .. "]", 1, true) < closeAt do
        eq = eq .. "="
    end

    local outText = head
        .. "-- Shipped as a long string, not a table. Reach it through Compat.ClassicSpawns(),\n"
        .. "-- which builds it on first use. ns.HAS_CLASSIC_SPAWNS answers the flavor question.\n"
        .. "ns.HAS_CLASSIC_SPAWNS = true\n"
        .. ("ns.CLASSIC_QUEST_SPAWNS_SRC = [%s[return %s]%s]\n"):format(eq, bodyText, eq)

    -- Proves the WRAP, which is a claim the reload check above does not make. Values are
    -- compared exactly and IN ORDER: a checksum is order insensitive, so it cannot see the
    -- densest-first ordering the reader's prefix depends on being disturbed.
    local function verifyWrap(candidate, label)
        local probe = {}
        assert(loadstring(candidate, "shipped"))("EQ", probe)
        assert(probe.HAS_CLASSIC_SPAWNS == true, label .. ": lost the presence flag")
        assert(probe.CLASSIC_QUEST_SPAWNS == nil,
               label .. ": must NOT build the table at load - that is the whole point")
        local src = assert(probe.CLASSIC_QUEST_SPAWNS_SRC, label .. ": defined no source string")
        local built = assert(loadstring(src, "deferred"))()
        local seen = 0
        for qid, maps in pairs(built) do
            local orig = assert(expect[qid], label .. ": invented quest " .. qid)
            for m, list in pairs(maps) do
                local om = assert(orig[m],
                    ("%s: invented map %d for quest %d"):format(label, m, qid))
                assert(#list == #om,
                    ("%s: row count changed for quest %d map %d"):format(label, qid, m))
                for j = 1, #list do
                    assert(list[j] == om[j].v,
                        ("%s: quest %d map %d row %d is %s, expected %s")
                        :format(label, qid, m, j, tostring(list[j]), tostring(om[j].v)))
                    seen = seen + 1
                end
            end
        end
        for qid, maps in pairs(expect) do
            assert(built[qid], label .. ": dropped quest " .. qid)
            for m in pairs(maps) do
                assert(built[qid][m],
                    ("%s: dropped map %d for quest %d"):format(label, m, qid))
            end
        end
        assert(seen == emitted, label .. ": point count changed")
    end

    verifyWrap(outText, "wrapped form")
    -- io.write expands every \n to \r\n on Windows, so the bytes the client parses are NOT the
    -- bytes checked above. Verify the form that actually ships.
    verifyWrap((outText:gsub("\n", "\r\n")), "shipped CRLF form")
    io.stderr:write(("-- long-string wrap verified LF and CRLF: %d point(s), delimiter [%s[\n")
        :format(emitted, eq))

    io.write(outText)
    io.stderr:write(("-- mode=spawns grid=%.3f UNCAPPED zone=%s | quests=%d emitted=%d quest-map pairs=%d widest=%d bytes=%d\n")
        :format(SPAWN_GRID, tostring(zoneFilter or "all"), sQuests, emitted, sPairs, widest, #outText))
    io.stderr:write(("-- %d point(s) serve MORE THAN ONE objective (%.1f%%) - each of those is a\n")
        :format(shared, shared / math.max(1, emitted) * 100))
    io.stderr:write("-- pin a single objective index would have mislabeled or hidden\n")
    if attStats then
        local s = attStats
        io.stderr:write(("-- att objectives: %d spot(s) for %d objective(s) in %d quest(s) with no place of their own; %d not matched to an objective, %d on a map with no zone, %d set aside on a redrawn map; %d of %d checked against the dump's own places within %d map units\n")
            :format(s.spots, s.objectives, s.quests, s.unmatched, s.unmapped, s.setAside, s.near, s.graded, ATT_NEAR))
        io.stderr:write(("-- att objective numbers: the game's own list puts ATT's objective number on the objective its names match for %d of %d\n")
            :format(s.clientAgree, s.clientChecked))
    end
    return
end

-- The mob list is a byproduct of the spawn walk. It reuses objectivePoints, so the creatures
-- are exactly the ones that produced the spawn points, killCredit lists and item drops included.
if mode == "npcs" then
    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = { packed, ... }\n",
        "-- packed = objIdx*1e8 + kind*1e7 + npcID.  kind 1=slay 2=object 3=loot\n",
        "-- objIdx is 0 based WITHIN ITS OWN TYPE, matching the client's nth objective of that\n",
        "-- type - a mob that drops one of four quest items must not claim the other three.\n",
        "-- decode: objIdx = floor(v/1e8), kind = floor(v%1e8/1e7), npcID = v%1e7\n",
        "ns.CLASSIC_QUEST_NPCS = {\n",
    }
    local expect, sink, distinct = {}, {}, {}
    local sQuests, emitted = 0, 0

    for i = 1, #ids do
        local id = ids[i]
        for k in pairs(sink) do sink[k] = nil end
        npcSink = sink
        objectivePoints(quests[id], id)
        npcSink = nil

        local list = {}
        for npcId, byIdx in pairs(sink) do
            for objIdx, kind in pairs(byIdx) do
                list[#list + 1] = { id = npcId, idx = objIdx, k = kind }
            end
        end
        table.sort(list, function(a, b)
            if a.id ~= b.id then return a.id < b.id end
            return a.idx < b.idx
        end)

        if #list > 0 then
            sQuests = sQuests + 1
            local nums = {}
            for j = 1, #list do
                local row = list[j]
                assert(row.id < 10000000, "npc id too large to pack: " .. row.id)
                assert(row.idx < 100, "objective index too large to pack: " .. row.idx)
                -- %.0f rather than %d: Lua 5.1's %d casts through a 32-bit int
                nums[j] = ("%.0f"):format(row.idx * 100000000 + row.k * 10000000 + row.id)
                distinct[row.id] = true
                emitted = emitted + 1
            end
            expect[id] = list
            parts[#parts + 1] = ("\t[%d]={%s},\n"):format(id, table.concat(nums, ","))
        end
    end
    parts[#parts + 1] = "}\n"
    local text = table.concat(parts)

    do
        local probe = {}
        assert(loadstring(text))("EQ", probe)
        local got = assert(probe.CLASSIC_QUEST_NPCS, "emitted file did not define the table")
        local seen = 0
        for qid, list in pairs(expect) do
            local gl = assert(got[qid], "quest missing after reload: " .. qid)
            assert(#gl == #list, "row count changed for quest " .. qid)
            for j = 1, #list do
                local v = gl[j]
                assert(type(v) == "number" and v > 0,
                       ("quest %d serialized as %s - 32-bit overflow?"):format(qid, tostring(v)))
                local objIdx = math.floor(v / 100000000)
                local kind   = math.floor((v % 100000000) / 10000000)
                local npcId  = v % 10000000
                assert(npcId == list[j].id and kind == list[j].k and objIdx == list[j].idx,
                       ("quest %d row %d changed on reload"):format(qid, j))
                assert(kind >= KIND_SLAY and kind <= KIND_LOOT,
                       ("quest %d row %d bad kind %s"):format(qid, j, tostring(kind)))
                seen = seen + 1
            end
        end
        assert(seen == emitted, "row count changed on reload")
        io.stderr:write(("-- verified %d npc row(s) by reload\n"):format(seen))
    end

    local nDistinct = 0
    for _ in pairs(distinct) do nDistinct = nDistinct + 1 end
    io.write(text)
    io.stderr:write(("-- mode=npcs | quests=%d rows=%d distinct npcs=%d bytes=%d\n")
        :format(sQuests, emitted, nDistinct, #text))
    return
end

if mode == "available" then
    -- attRules.lua, from build_att_rules.lua or build_forever_supplement.lua --att: AllTheThings' level ranges, ended quests, dailies and factions.
    local rules
    do
        local path = dir .. "/attRules.lua"
        local f = io.open(path, "rb")
        if f then
            f:close()
            rules = assert(loadfile(path))()
            for _, part in ipairs({ "caps", "ended", "daily", "faction" }) do
                assert(type(rules[part]) == "table", path .. ": no " .. part .. " table")
            end
        end
    end

    local FACTION_MASK = PREFIX == "tbc" and { A = RACES_ALLIANCE, H = RACES_HORDE } or { A = 77, H = 178 }
    local ATT_SIDE = { [1] = "H", [2] = "A" }
    local factionStats = { narrowed = {}, corrected = {}, disputed = {}, contradicted = {}, changed = {} }

    local function maskAnd(a, b)
        local out = 0
        for bit = 0, 10 do
            local v = 2 ^ bit
            if a % (v + v) >= v and b % (v + v) >= v then out = out + v end
        end
        return out
    end

    -- "A" or "H" when every way in is a creature friendly to that faction alone, which no player of the other can talk to.
    local function giversSide(q)
        local sb = q[Q_STARTEDBY]
        if type(sb) ~= "table" or type(sb[1]) ~= "table" or #sb[1] == 0 then return nil end
        if (type(sb[2]) == "table" and #sb[2] > 0) or (type(sb[3]) == "table" and #sb[3] > 0) then return nil end
        local side
        for _, c in ipairs(sb[1]) do
            local f = npcs[c] and npcs[c][N_FACTION]
            if (f ~= "A" and f ~= "H") or (side and side ~= f) then return nil end
            side = f
        end
        return side
    end

    -- Forever's own quests took their faction in the supplement, from the collector, AllTheThings and their givers, so only upstream rows are judged here.
    local function ruleRaces(id, q)
        local races = tonumber(q[Q_RACES]) or 0
        if overlaid[quests] and overlaid[quests][id] then return races end
        local side = giversSide(q)
        local qf = factionOfRaces(races)
        if not side or qf == side then return races end
        local att = ATT_SIDE[rules.faction[id]]
        if not qf then
            if att and att ~= side then
                factionStats.disputed[#factionStats.disputed + 1] = id
                return races
            end
            factionStats.narrowed[#factionStats.narrowed + 1] = id
            factionStats.changed[id] = races == 0 and FACTION_MASK[side] or maskAnd(races, FACTION_MASK[side])
            return factionStats.changed[id]
        end
        if att == side then
            factionStats.corrected[#factionStats.corrected + 1] = id
            factionStats.changed[id] = FACTION_MASK[side]
            return FACTION_MASK[side]
        end
        factionStats.contradicted[#factionStats.contradicted + 1] = id
        return races
    end

    -- Two digits of required level, two of quest level, one of flags, four of each bitmask.
    -- Thirteen digits sits well inside a double's exact integer range, and packing by decimal
    -- rather than by bits keeps this working on an interpreter with no bit library.
    local function packGates(id, q)
        local lvl   = math.max(0, math.min(99, tonumber(q[Q_REQLEVEL]) or 0))
        local qlvl  = math.max(0, math.min(99, tonumber(q[Q_QUESTLEVEL]) or 0))
        local races = rules and ruleRaces(id, q) or tonumber(q[Q_RACES]) or 0
        local class = tonumber(q[Q_CLASSES]) or 0
        -- Only the low three: repeatable, completed by exploring or by a script, monthly reset
        local flags = (tonumber(q[Q_SPECIALFLAGS]) or 0) % 8
        -- Loud rather than clamped. A truncated bitmask would offer a quest to the wrong race.
        assert(races >= 0 and races <= 9999, ("quest %d: race mask %s does not fit"):format(id, tostring(races)))
        assert(class >= 0 and class <= 9999, ("quest %d: class mask %s does not fit"):format(id, tostring(class)))
        return lvl * 100000000000 + qlvl * 1000000000 + flags * 100000000 + races * 10000 + class
    end

    local function idList(v)
        if type(v) ~= "table" then return nil end
        local out = {}
        for i = 1, #v do
            local n = tonumber(v[i])
            if n and n > 0 then out[#out + 1] = n end
        end
        if #out == 0 then return nil end
        table.sort(out)
        return out
    end

    local function pairValue(v, scale)
        if type(v) ~= "table" then return nil end
        local a, b = tonumber(v[1]), tonumber(v[2])
        if not (a and b) or a <= 0 then return nil end
        if b < 0 then b = 0 end
        return a * scale + b
    end

    local start, gates, names = {}, {}, {}
    local pre, preAll, excl, chain, parent = {}, {}, {}, {}, {}
    local skill, minRep, maxRep = {}, {}, {}
    local emitted, sQuests, sPairs, widest = 0, 0, 0, 0
    local perPairHist = {}

    for i = 1, #ids do
        local id = ids[i]
        local q = quests[id]
        local byMap = clusterSimple(startPoints(q, id))

        local maps = {}
        for m in pairs(byMap) do
            if (not zoneFilter) or m == zoneFilter then maps[#maps + 1] = m end
        end
        table.sort(maps)

        if #maps > 0 then
            sQuests = sQuests + 1
            start[id] = { order = maps, byMap = byMap }
            gates[id] = packGates(id, q)
            local nm = q[Q_NAME]
            if type(nm) == "string" and nm ~= "" then names[id] = nm end

            pre[id]    = idList(q[Q_PRESINGLE])
            preAll[id] = idList(q[Q_PREGROUP])
            excl[id]   = idList(q[Q_EXCLUSIVE])
            local nx = tonumber(q[Q_NEXTINCHAIN]); if nx and nx > 0 then chain[id] = nx end
            local pq = tonumber(q[Q_PARENT]);      if pq and pq > 0 then parent[id] = pq end
            skill[id]  = pairValue(q[Q_REQSKILL], 10000)
            minRep[id] = pairValue(q[Q_MINREP], 1000000)
            maxRep[id] = pairValue(q[Q_MAXREP], 1000000)

            for k = 1, #maps do
                local n = #byMap[maps[k]]
                sPairs = sPairs + 1
                emitted = emitted + n
                if n > widest then widest = n end
                perPairHist[#perPairHist + 1] = n
            end
        end
    end

    -- foreverMaxLevels.lua, from build_forever_supplement.lua, holds the top of each AllTheThings level range it kept, and
    -- attRules.lua each whole range. A cap at the highest level a character reaches turns no one away, so it is left out.
    local MAX_PLAYER_LEVEL = PREFIX == "tbc" and 70 or 60
    local maxLevel, capsPath, capsListed, capsAtMax, capsLeft = {}, dir .. "/foreverMaxLevels.lua", 0, {}, {}
    local capsFile = io.open(capsPath, "rb")
    local function keepCap(id, low, cap)
        capsListed = capsListed + 1
        if not start[id] then return end
        local req = math.floor(gates[id] / 100000000000)
        if low and (low ~= req or cap < req) then
            capsLeft[#capsLeft + 1] = ("%d (ATT %d to %d, required level %d)"):format(id, low, cap, req)
            return
        end
        assert(type(cap) == "number" and cap >= req and cap <= 99,
               ("quest %d: level cap %s does not fit its required level %d"):format(id, tostring(cap), req))
        if cap >= MAX_PLAYER_LEVEL then capsAtMax[#capsAtMax + 1] = id else maxLevel[id] = cap end
    end
    if capsFile then
        capsFile:close()
        assert(PREFIX == "classic", "Forever level caps cannot be applied to " .. PREFIX .. " data")
        for id, cap in pairs(assert(loadfile(capsPath))()) do keepCap(id, nil, cap) end
    end
    if rules then
        assert(not (capsFile and next(rules.caps)), "level caps in both foreverMaxLevels.lua and attRules.lua")
        for id, range in pairs(rules.caps) do keepCap(id, range[1], range[2]) end
        capsFile = capsFile or true
    end
    table.sort(capsAtMax)
    table.sort(capsLeft)

    local ended, daily, giverSide, sideQuests = {}, {}, {}, 0
    if rules then
        for id in pairs(start) do
            ended[id] = rules.ended[id]
            local flags = tonumber(quests[id][Q_FLAGS]) or 0
            if rules.daily[id] or flags % (DAILY_FLAG + DAILY_FLAG) >= DAILY_FLAG then daily[id] = 1 end
            -- A giver friendly to one faction alone offers a quest both can take only to its own side.
            if not factionOfRaces(math.floor(gates[id] % 100000000 / 10000)) then
                local sb, sided = quests[id][Q_STARTEDBY], false
                for _, c in ipairs(type(sb) == "table" and type(sb[1]) == "table" and sb[1] or {}) do
                    local f = npcs[c] and npcs[c][N_FACTION]
                    if f == "A" or f == "H" then
                        giverSide[c] = f == "A" and 2 or 1
                        sided = true
                    end
                end
                if sided then sideQuests = sideQuests + 1 end
            end
        end
    end

    -- For auto-accept: 1 offered to the whole group as one player takes it, 2 a PvP quest. Every quest, as one given inside a dungeon has no start point
    local accept, acceptIds = {}, {}
    for id, q in pairs(quests) do
        local flags, v = tonumber(q[Q_FLAGS]) or 0, 0
        if flags % (PARTY_ACCEPT_FLAG + PARTY_ACCEPT_FLAG) >= PARTY_ACCEPT_FLAG then v = v + 1 end
        if BATTLEGROUND_AREAS[q[Q_ZONEORSORT]] or PVP_QUESTS[id] then v = v + 2 end
        if v > 0 then accept[id] = v; acceptIds[#acceptIds + 1] = id end
    end
    table.sort(acceptIds)

    -- breadcrumbs.lua, from build_breadcrumbs.lua: a breadcrumb is no gate itself, as AllTheThings counts none missing, and one of its follow-ups taken closes it.
    local leads, crumbsPath = {}, dir .. "/breadcrumbs.lua"
    local crumbsFile, crumbs = io.open(crumbsPath, "rb"), nil
    if crumbsFile then
        crumbsFile:close()
        crumbs = { listed = 0, voided = {}, dropped = {}, through = {} }
        local isCrumb = {}
        for b, to in pairs(assert(loadfile(crumbsPath))()) do
            assert(type(b) == "number" and type(to) == "table" and #to > 0, crumbsPath .. ": a row is not a quest and its follow-ups")
            crumbs.listed = crumbs.listed + 1
            isCrumb[b] = to
            if start[b] then leads[b] = idList(to) end
        end
        for id in pairs(start) do
            if pre[id] then
                local here, swapped, rest, seen = false, false, {}, {}
                -- A breadcrumb into a breadcrumb stands for where the last one leads (282 to 420 to 287 and 98322)
                local function follow(p, depth)
                    if not isCrumb[p] or depth > 8 then
                        if p ~= id and not seen[p] then seen[p] = true; rest[#rest + 1] = p end
                        return
                    end
                    swapped = true
                    for _, q in ipairs(isCrumb[p]) do
                        if q == id then here = true else follow(q, depth + 1) end
                    end
                end
                for _, p in ipairs(pre[id]) do follow(p, 0) end
                if here then
                    -- The gate reads preAll only when there is no any-of list, so voiding one must not wake an all-of list.
                    assert(not preAll[id], ("quest %d: voiding its any-of list would start gating it on its all-of list"):format(id))
                    pre[id] = nil
                    crumbs.voided[#crumbs.voided + 1] = id
                elseif swapped then
                    -- A breadcrumb to another quest stands for where it leads, as TBC's 9549 waits for 9548, not its breadcrumb 10063
                    pre[id] = idList(rest)
                    crumbs.through[#crumbs.through + 1] = id
                end
            end
            if preAll[id] then
                local kept = {}
                for _, p in ipairs(preAll[id]) do
                    if isCrumb[p] then crumbs.dropped[#crumbs.dropped + 1] = id else kept[#kept + 1] = p end
                end
                preAll[id] = #kept > 0 and kept or nil
            end
        end
        table.sort(crumbs.voided)
        table.sort(crumbs.dropped)
        table.sort(crumbs.through)
    end

    local sortedIds = {}
    for id in pairs(start) do sortedIds[#sortedIds + 1] = id end
    table.sort(sortedIds)

    local parts = {
        "local _, ns = ...\n",
        "\n-- Where every quest can be PICKED UP, and the gates that decide whether it can be.\n",
        "-- The client answers none of this for a quest that is not in the log, so it ships.\n",
        "--\n",
        "-- start  [questID] = { [uiMapID] = { packed, ... } }\n",
        "--        packed = srcID*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)\n",
        "--        kind 1=an NPC offers it, 2=an object offers it, 3=an item that starts it\n",
        "--        drops here. These are SOURCES of the quest, not objective types.\n",
        "--        srcID is the creature id when kind is 1 and the object id when kind is 2, for\n",
        "--        the name the tooltip shows. It is 0 when kind is 3, because the dropper of a\n",
        "--        starting item can be either and kind would not say which id space it is.\n",
        "--        decode: srcID = floor(v/1e9), kind = floor(v/1e8)%10, rest = v%1e8,\n",
        "--                x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4\n",
        "--        A reader wanting only the coordinate can still take v%1e8 and ignore the rest.\n",
        "--        Ordered densest first, so a reader's prefix keeps the best locations.\n",
        "-- gates  [questID] = requiredLevel*1e11 + questLevel*1e9 + specialFlags*1e8\n",
        "--                    + requiredRaces*1e4 + requiredClasses\n",
        "--        specialFlags: 1 repeatable, 2 completed by exploring or by a script, 4\n",
        "--        monthly reset. Bit 2 is NOT a holiday marker and must not be gated on as\n",
        "--        one. See Modules/MapPOI/Holidays.lua for what actually decides a holiday.\n",
        "--        A bitmask of 0 means no restriction, not 'no races allowed'.\n",
        "-- names  [questID] = English title. The client is asked first and this is the fallback,\n",
        "--        so a non-English client shows English only for quests it does not know.\n",
        "-- pre    [questID] = { questID, ... }  ANY one completed satisfies it\n",
        "-- preAll [questID] = { questID, ... }  ALL must be completed\n",
        "-- excl   [questID] = { questID, ... }  any of these taken or completed rules it out\n",
        "-- chain  [questID] = questID           that quest active or done rules this one out\n",
        "-- parent [questID] = questID           must be in the log for this one to be offered\n",
        "-- skill  [questID] = skillLineID*1e4 + requiredValue\n",
        "-- minRep [questID] = factionID*1e6 + requiredStanding\n",
        "-- maxRep [questID] = factionID*1e6 + maximumStanding\n",
        "ns.CLASSIC_QUEST_AVAILABLE = {\n",
        "start = {\n",
    }
    if crumbs then
        for i = 1, #parts do
            if parts[i]:find("^%-%- parent ") then
                table.insert(parts, i + 1, "-- leads  [questID] = { questID, ... }  a breadcrumb: any of these taken or completed rules it out, and none is offered while it is in the log\n")
                break
            end
        end
    end
    if capsFile then
        table.insert(parts, #parts - 1, "-- maxLevel [questID] = the highest level it is still offered at\n")
    end
    if rules then
        table.insert(parts, #parts - 1, "-- ended  [questID] = why no character is offered it today: 1 not in the game, 2 a world\n")
        table.insert(parts, #parts - 1, "--        event that is not running, 3 the Scourge Invasion (open on Season of Discovery),\n")
        table.insert(parts, #parts - 1, "--        4 content not released here\n")
        table.insert(parts, #parts - 1, "-- daily  [questID] = 1, offered again after the daily reset\n")
        table.insert(parts, #parts - 1, "-- giverSide [creatureID] = 1 Horde, 2 Alliance: the one faction that creature offers quests to\n")
    end
    table.insert(parts, #parts - 1, "-- accept [questID] = 1 offered to the whole group as one player takes it, such as an escort,\n")
    table.insert(parts, #parts - 1, "--        2 a PvP quest, a battleground's or a world PvP quest, 3 both\n")

    local expect = {}
    for i = 1, #sortedIds do
        local id = sortedIds[i]
        local rec = start[id]
        local chunks = {}
        expect[id] = {}
        for k = 1, #rec.order do
            local m = rec.order[k]
            local list = rec.byMap[m]
            local nums, mine = {}, {}
            for j = 1, #list do
                local xi = math.floor(list[j].x * 10000 + 0.5); if xi > 9999 then xi = 9999 end
                local yi = math.floor(list[j].y * 10000 + 0.5); if yi > 9999 then yi = 9999 end
                local kind = list[j].k or START_NPC
                assert(kind >= START_NPC and kind <= START_ITEM,
                       ("quest %d: start kind %s out of range"):format(id, tostring(kind)))
                -- Only the NPC and object kinds carry a source. A START_ITEM point is wherever
                -- the starting item DROPS, and its dropper can be either a creature or an object,
                -- so the id space would be ambiguous with nothing to disambiguate it - kind is
                -- what tells the two apart everywhere else here.
                local src = (kind == START_ITEM) and 0 or (list[j].s or 0)
                assert(src >= 0 and src < MAX_SRC_ID,
                       ("quest %d: start source id %s too large to pack"):format(id, tostring(src)))
                -- Both directions, because the emitted header promises the names file holds
                -- exactly the referenced ids. Without this, dropping the source anywhere in the
                -- walk packs every point as 0 and every reload check still passes.
                if kind == START_ITEM then
                    assert(src == 0, ("quest %d: an item start must carry no source"):format(id))
                else
                    assert(src > 0, ("quest %d: kind %d start carries no source"):format(id, kind))
                end
                -- %.0f rather than %d: Lua 5.1's %d casts through a 32-bit int
                nums[j] = ("%.0f"):format(src * 1000000000 + kind * 100000000 + xi * 10000 + yi)
                mine[j] = { x = xi / 10000, y = yi / 10000, k = kind, s = src }
            end
            expect[id][m] = mine
            chunks[#chunks + 1] = ("[%d]={%s}"):format(m, table.concat(nums, ","))
        end
        parts[#parts + 1] = ("\t[%d]={%s},\n"):format(id, table.concat(chunks, ","))
    end

    local function emitScalar(name, tbl)
        parts[#parts + 1] = ("},\n%s = {\n"):format(name)
        for i = 1, #sortedIds do
            local id = sortedIds[i]
            local v = tbl[id]
            if v then parts[#parts + 1] = ("\t[%d]=%.0f,\n"):format(id, v) end
        end
    end

    local function emitList(name, tbl)
        parts[#parts + 1] = ("},\n%s = {\n"):format(name)
        for i = 1, #sortedIds do
            local id = sortedIds[i]
            local v = tbl[id]
            if v then
                local nums = {}
                for j = 1, #v do nums[j] = ("%.0f"):format(v[j]) end
                parts[#parts + 1] = ("\t[%d]={%s},\n"):format(id, table.concat(nums, ","))
            end
        end
    end

    emitScalar("gates", gates)

    parts[#parts + 1] = "},\nnames = {\n"
    for i = 1, #sortedIds do
        local id = sortedIds[i]
        if names[id] then
            parts[#parts + 1] = ("\t[%d]=%q,\n"):format(id, names[id])
        end
    end

    emitList("pre", pre)
    emitList("preAll", preAll)
    emitList("excl", excl)
    emitScalar("chain", chain)
    emitScalar("parent", parent)
    if crumbs then emitList("leads", leads) end
    emitScalar("skill", skill)
    emitScalar("minRep", minRep)
    emitScalar("maxRep", maxRep)
    if capsFile then emitScalar("maxLevel", maxLevel) end
    if rules then
        emitScalar("ended", ended)
        emitScalar("daily", daily)
        parts[#parts + 1] = "},\ngiverSide = {\n"
        local creatures = {}
        for c in pairs(giverSide) do creatures[#creatures + 1] = c end
        table.sort(creatures)
        for _, c in ipairs(creatures) do parts[#parts + 1] = ("\t[%d]=%d,\n"):format(c, giverSide[c]) end
    end
    parts[#parts + 1] = "},\naccept = {\n"
    for i = 1, #acceptIds do parts[#parts + 1] = ("\t[%d]=%.0f,\n"):format(acceptIds[i], accept[acceptIds[i]]) end
    parts[#parts + 1] = "},\n}\n"

    local text = table.concat(parts)

    do
        local probe = {}
        assert(loadstring(text))("EQ", probe)
        local got = assert(probe.CLASSIC_QUEST_AVAILABLE, "emitted file did not define the table")
        assert(type(got.start) == "table" and type(got.gates) == "table", "sub-tables missing")

        local seen, worst = 0, 0
        for qid, maps in pairs(expect) do
            local gq = assert(got.start[qid], "quest missing after reload: " .. qid)
            for m, list in pairs(maps) do
                local gl = assert(gq[m], ("map %d missing after reload for quest %d"):format(m, qid))
                assert(#gl == #list, ("row count changed for quest %d map %d"):format(qid, m))
                for j = 1, #list do
                    local v = gl[j]
                    assert(type(v) == "number" and v > 0,
                           ("quest %d serialized as %s - 32-bit overflow?"):format(qid, tostring(v)))
                    local src  = math.floor(v / 1000000000)
                    local kind = math.floor(v / 100000000) % 10
                    local rest = v % 100000000
                    local x, y = math.floor(rest / 10000) / 10000, (rest % 10000) / 10000
                    assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                           ("quest %d decoded out of range: %s,%s"):format(qid, x, y))
                    assert(kind == list[j].k,
                           ("quest %d start kind changed on reload"):format(qid))
                    -- Checked exactly. The drift tolerance below is for coordinates only, and an
                    -- id compared loosely would let a one-digit corruption name another NPC.
                    assert(src == list[j].s,
                           ("quest %d start source changed on reload: %s vs %s")
                           :format(qid, tostring(src), tostring(list[j].s)))
                    local d = math.max(math.abs(x - list[j].x), math.abs(y - list[j].y))
                    if d > worst then worst = d end
                    seen = seen + 1
                end
            end
        end
        assert(seen == emitted, "point count changed on reload")
        assert(worst <= 0.0001, "coordinate drift on reload: " .. worst)

        -- The gates are the half that decides whether a pin is a lie, so every field of every
        -- one is unpacked and compared rather than spot checked.
        local gseen = 0
        for i = 1, #sortedIds do
            local id = sortedIds[i]
            local v = assert(got.gates[id], "gates missing after reload: " .. id)
            local q = quests[id]
            assert(math.floor(v / 100000000000) == math.max(0, math.min(99, tonumber(q[Q_REQLEVEL]) or 0)),
                   ("quest %d requiredLevel changed on reload"):format(id))
            assert(math.floor(v % 100000000000 / 1000000000) == math.max(0, math.min(99, tonumber(q[Q_QUESTLEVEL]) or 0)),
                   ("quest %d questLevel changed on reload"):format(id))
            assert(math.floor(v % 1000000000 / 100000000) == (tonumber(q[Q_SPECIALFLAGS]) or 0) % 8,
                   ("quest %d specialFlags changed on reload"):format(id))
            local races = math.floor(v % 100000000 / 10000)
            assert(races == (factionStats.changed[id] or tonumber(q[Q_RACES]) or 0),
                   ("quest %d requiredRaces changed on reload"):format(id))
            assert(v % 10000 == (tonumber(q[Q_CLASSES]) or 0),
                   ("quest %d requiredClasses changed on reload"):format(id))
            if names[id] then
                assert(got.names[id] == names[id], ("quest %d name changed on reload"):format(id))
            end
            gseen = gseen + 1
        end
        assert(gseen == sQuests, "gate row count changed on reload")

        local function checkList(name, src)
            local dst = got[name]
            for i = 1, #sortedIds do
                local id = sortedIds[i]
                local v = src[id]
                if v then
                    local gv = assert(dst[id], ("%s missing after reload for quest %d"):format(name, id))
                    assert(#gv == #v, ("%s length changed for quest %d"):format(name, id))
                    for j = 1, #v do
                        assert(gv[j] == v[j], ("%s row changed for quest %d"):format(name, id))
                    end
                else
                    assert(dst[id] == nil, ("%s gained a row for quest %d"):format(name, id))
                end
            end
        end
        checkList("pre", pre)
        checkList("preAll", preAll)
        checkList("excl", excl)
        if crumbs then checkList("leads", leads) else assert(got.leads == nil, "leads emitted with no breadcrumbs file") end
        for i = 1, #sortedIds do
            local id = sortedIds[i]
            assert((got.maxLevel and got.maxLevel[id]) == maxLevel[id], ("quest %d level cap changed on reload"):format(id))
            assert((got.ended and got.ended[id]) == ended[id], ("quest %d ended reason changed on reload"):format(id))
            assert((got.daily and got.daily[id]) == daily[id], ("quest %d daily flag changed on reload"):format(id))
        end
        local accepted = 0
        for id, v in pairs(got.accept) do
            accepted = accepted + 1
            assert(accept[id] == v, ("quest %d accept flags changed on reload"):format(id))
        end
        assert(accepted == #acceptIds, "accept row count changed on reload")
        local sides, want = 0, 0
        for c, side in pairs(got.giverSide or {}) do
            sides = sides + 1
            assert(giverSide[c] == side, ("creature %d giver side changed on reload"):format(c))
        end
        for _ in pairs(giverSide) do want = want + 1 end
        assert(sides == want, "giver side row count changed on reload")
        assert(rules or (got.ended == nil and got.daily == nil and got.giverSide == nil), "rule tables emitted with no rules file")

        io.stderr:write(("-- verified %d start point(s) and %d gate row(s) by reload, max drift %.6f\n")
            :format(seen, gseen, worst))
    end

    table.sort(perPairHist)
    -- Answers 0 rather than indexing an empty list. A zone filter that matches no map leaves this
    -- empty, and the stats line would otherwise raise after the file was already written.
    local function pctl(p)
        if #perPairHist == 0 then return 0 end
        return perPairHist[math.max(1, math.floor(#perPairHist * p))]
    end
    local function countTbl(t)
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        return n
    end

    io.write(text)
    io.stderr:write(("-- mode=available grid=%.3f zone=%s | quests=%d points=%d quest-map pairs=%d widest=%d bytes=%d\n")
        :format(SPAWN_GRID, tostring(zoneFilter or "all"), sQuests, emitted, sPairs, widest, #text))
    io.stderr:write(("-- points per quest-map: median=%d p75=%d p90=%d p99=%d max=%d\n")
        :format(pctl(.5), pctl(.75), pctl(.90), pctl(.99), widest))
    io.stderr:write(("-- gate rows: pre=%d preAll=%d excl=%d chain=%d parent=%d skill=%d minRep=%d maxRep=%d names=%d\n")
        :format(countTbl(pre), countTbl(preAll), countTbl(excl), countTbl(chain),
                countTbl(parent), countTbl(skill), countTbl(minRep), countTbl(maxRep), countTbl(names)))
    do
        local group, pvp = 0, 0
        for _, v in pairs(accept) do
            if v % 2 == 1 then group = group + 1 end
            if v >= 2 then pvp = pvp + 1 end
        end
        io.stderr:write(("-- accept flags: %d offered to the whole group, %d PvP\n"):format(group, pvp))
    end
    if capsFile then
        io.stderr:write(("-- level caps: %d quest(s), of %d in the caps file\n"):format(countTbl(maxLevel), capsListed))
        if #capsAtMax > 0 then
            io.stderr:write(("-- level cap left out at or above level %d, it turns no one away: %s\n"):format(MAX_PLAYER_LEVEL, table.concat(capsAtMax, " ")))
        end
        if #capsLeft > 0 then
            io.stderr:write("-- level cap left out, the range does not start at the required level: " .. table.concat(capsLeft, ", ") .. "\n")
        end
    end
    if rules then
        local byCode = {}
        for _, code in pairs(ended) do byCode[code] = (byCode[code] or 0) + 1 end
        io.stderr:write(("-- att rules: ended %d not in the game, %d world event, %d Scourge Invasion, %d not released; %d daily; giver side for %d creature(s) in %d quest(s)\n")
            :format(byCode[1] or 0, byCode[2] or 0, byCode[3] or 0, byCode[4] or 0, countTbl(daily), countTbl(giverSide), sideQuests))
        local function listed(t) table.sort(t); return #t > 0 and table.concat(t, " ") or "none" end
        io.stderr:write(("-- att faction: %d narrowed to their givers' faction, %d race mask(s) turned to their givers' (%s), %d left open as ATT names the other faction (%s), %d kept against their givers (%s)\n")
            :format(#factionStats.narrowed, #factionStats.corrected, listed(factionStats.corrected), #factionStats.disputed,
                    listed(factionStats.disputed), #factionStats.contradicted, listed(factionStats.contradicted)))
    end
    if crumbs then
        io.stderr:write(("-- breadcrumbs: %d listed, %d with a start point here, %d quest(s) no longer gated on one (any-of list voided: %s; all-of entry dropped: %s; read as where it leads: %s)\n")
            :format(crumbs.listed, countTbl(leads), #crumbs.voided + #crumbs.dropped + #crumbs.through,
                    #crumbs.voided > 0 and table.concat(crumbs.voided, " ") or "none",
                    #crumbs.dropped > 0 and table.concat(crumbs.dropped, " ") or "none",
                    #crumbs.through > 0 and table.concat(crumbs.through, " ") or "none"))
    end
    if ownStarts then
        io.stderr:write(("-- own starts: %d quest(s) with their own evidence, %d giver spot(s) kept, %d dropped, %d added\n")
            :format(ownStats.quests, ownStats.kept, ownStats.dropped, ownStats.added))
    end
    return
end

if mode == "turnin" then
    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = { [uiMapID] = { packed, ... } }\n",
        "-- packed = srcID*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)\n",
        "-- kind 1=an NPC takes it, 2=an object does, and the same +4 (5,6) for a DUNGEON\n",
        "-- ENTRANCE - the turn-in is inside an instance whose interior coordinates nobody\n",
        "-- records, so the pin marks the way in. Recover the real kind by subtracting 4.\n",
        "-- srcID is the creature id when kind is 1 and the object id when kind is 2, for the\n",
        "-- name the tooltip shows. It is 0 for an entrance, where nobody is standing.\n",
        "-- KIND is what says which id space srcID belongs to. The two overlap numerically.\n",
        "-- decode: srcID = floor(v/1e9), kind = floor(v/1e8)%10, rest = v%1e8,\n",
        "--         x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4\n",
        "-- A reader that wants only the coordinate can still take v%1e8 and ignore the rest.\n",
        "-- Ordered densest first, so a reader's prefix keeps the best locations.\n",
        "--\n",
        "-- Deliberately NOT ns.CLASSIC_QUEST_COORDS. That table answers where a quest is\n",
        "-- ADVANCED and both would load into one name, silently keeping whichever came second.\n",
        "ns.CLASSIC_QUEST_TURNIN = {\n",
    }

    local expect = {}
    local sQuests, sPairs, emitted, widest, multiMap, entrancePts = 0, 0, 0, 0, 0, 0
    local hist = {}

    for i = 1, #ids do
        local id = ids[i]
        local byMap = clusterSimple(turninPoints(quests[id]))

        local maps = {}
        for m in pairs(byMap) do
            if (not zoneFilter) or m == zoneFilter then maps[#maps + 1] = m end
        end
        table.sort(maps)

        if #maps > 0 then
            sQuests = sQuests + 1
            if #maps > 1 then multiMap = multiMap + 1 end
            expect[id] = {}
            local chunks = {}
            for k = 1, #maps do
                local m = maps[k]
                local list = byMap[m]
                sPairs = sPairs + 1
                if #list > widest then widest = #list end
                hist[#hist + 1] = #list
                local nums, mine = {}, {}
                for j = 1, #list do
                    local xi = math.floor(list[j].x * 10000 + 0.5); if xi > 9999 then xi = 9999 end
                    local yi = math.floor(list[j].y * 10000 + 0.5); if yi > 9999 then yi = 9999 end
                    local kind = list[j].k or KIND_SLAY
                    -- Loud rather than clamped. Only the NPC and object kinds reach here, each
                    -- optionally raised by KIND_ENTRANCE, so anything else is a walk that changed.
                    assert(kind == KIND_SLAY or kind == KIND_OBJECT
                           or kind == KIND_SLAY + KIND_ENTRANCE or kind == KIND_OBJECT + KIND_ENTRANCE,
                           ("quest %d: turn-in kind %s out of range"):format(id, tostring(kind)))
                    if kind > KIND_ENTRANCE then entrancePts = entrancePts + 1 end
                    -- An entrance has no source, and neither does anything the walk could not
                    -- attribute. 0 reads as "no name" rather than as creature 0.
                    local src = list[j].s or 0
                    assert(src >= 0 and src < MAX_SRC_ID,
                           ("quest %d: turn-in source id %s too large to pack"):format(id, tostring(src)))
                    -- Both directions, for the reason in the start emitter above
                    if kind > KIND_ENTRANCE then
                        assert(src == 0, ("quest %d: an entrance must carry no source"):format(id))
                    else
                        assert(src > 0, ("quest %d: kind %d turn-in carries no source"):format(id, kind))
                    end
                    -- %.0f rather than %d: Lua 5.1's %d casts through a 32-bit int
                    nums[j] = ("%.0f"):format(src * 1000000000 + kind * 100000000 + xi * 10000 + yi)
                    mine[j] = { x = xi / 10000, y = yi / 10000, k = kind, s = src }
                    emitted = emitted + 1
                end
                expect[id][m] = mine
                chunks[#chunks + 1] = ("[%d]={%s}"):format(m, table.concat(nums, ","))
            end
            parts[#parts + 1] = ("\t[%d]={%s},\n"):format(id, table.concat(chunks, ","))
        end
    end
    parts[#parts + 1] = "}\n"
    local text = table.concat(parts)

    do
        local probe = {}
        assert(loadstring(text))("EQ", probe)
        local got = assert(probe.CLASSIC_QUEST_TURNIN, "emitted file did not define the table")
        local seen, worst = 0, 0
        for qid, maps in pairs(expect) do
            local gq = assert(got[qid], "quest missing after reload: " .. qid)
            for m, list in pairs(maps) do
                local gl = assert(gq[m], ("map %d missing after reload for quest %d"):format(m, qid))
                assert(#gl == #list, ("row count changed for quest %d map %d"):format(qid, m))
                for j = 1, #list do
                    local v = gl[j]
                    assert(type(v) == "number" and v > 0,
                           ("quest %d serialized as %s - 32-bit overflow?"):format(qid, tostring(v)))
                    local src  = math.floor(v / 1000000000)
                    local kind = math.floor(v / 100000000) % 10
                    local rest = v % 100000000
                    local x, y = math.floor(rest / 10000) / 10000, (rest % 10000) / 10000
                    assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                           ("quest %d decoded out of range: %s,%s"):format(qid, x, y))
                    assert(kind == list[j].k,
                           ("quest %d turn-in kind changed on reload"):format(qid))
                    -- Checked exactly. The drift tolerance below is for coordinates only, and an
                    -- id compared loosely would let a one-digit corruption name another NPC.
                    assert(src == list[j].s,
                           ("quest %d turn-in source changed on reload: %s vs %s")
                           :format(qid, tostring(src), tostring(list[j].s)))
                    local d = math.max(math.abs(x - list[j].x), math.abs(y - list[j].y))
                    if d > worst then worst = d end
                    seen = seen + 1
                end
            end
        end
        assert(seen == emitted, "point count changed on reload")
        assert(worst <= 0.0001, "coordinate drift on reload: " .. worst)
        io.stderr:write(("-- verified %d turn-in point(s) by reload, max drift %.6f\n"):format(seen, worst))
    end

    table.sort(hist)
    local function pctl(p)
        if #hist == 0 then return 0 end
        return hist[math.max(1, math.floor(#hist * p))]
    end

    io.write(text)
    io.stderr:write(("-- mode=turnin grid=%.3f zone=%s | quests=%d points=%d quest-map pairs=%d widest=%d bytes=%d\n")
        :format(SPAWN_GRID, tostring(zoneFilter or "all"), sQuests, emitted, sPairs, widest, #text))
    io.stderr:write(("-- points per quest-map: median=%d p75=%d p90=%d p99=%d max=%d\n")
        :format(pctl(.5), pctl(.75), pctl(.90), pctl(.99), widest))
    io.stderr:write(("-- %d quest(s) hand in on MORE THAN ONE map, %d point(s) are dungeon entrances\n")
        :format(multiMap, entrancePts))
    return
end

if mode == "srcnames" then
    local NAME = 1

    -- Exactly the ids the shipped tables reference, gathered by running the SAME walk the two
    -- emitters run rather than by taking every quest giver in the dump. A giver with no spawn
    -- record produces no point, so listing it here would be a name nothing can ask for.
    local wantNpc, wantObj = {}, {}
    local eraWants = { npc = {}, obj = {} }

    local function want(set, id)
        if type(id) == "number" and id > 0 then set[id] = true end
    end

    local function harvest(byMap, era)
        for m, list in pairs(byMap) do
            if (not zoneFilter) or m == zoneFilter then
                for j = 1, #list do
                    local kind, src = list[j].k, list[j].s
                    -- Only the two kinds that carry one. An item start and an entrance reach
                    -- here with src nil, and the emitters assert that they stay 0.
                    if kind == START_NPC then want(wantNpc, src); if era then want(eraWants.npc, src) end
                    elseif kind == START_OBJECT then want(wantObj, src); if era then want(eraWants.obj, src) end end
                end
            end
        end
    end

    for i = 1, #ids do
        local q = quests[ids[i]]
        local era = not (overlaid[quests] and overlaid[quests][ids[i]])
        harvest(clusterSimple(startPoints(q, ids[i])), era)
        harvest(clusterSimple(turninPoints(q)), era)
    end

    local parts = {
        "local _, ns = ...\n",
        "\n-- Names for the creatures and objects that START or FINISH a quest, so a start or\n",
        "-- turn-in pin can say WHO is standing there and not only where.\n",
        "--\n",
        "-- npc  [creatureID] = name\n",
        "-- obj  [objectID]   = name\n",
        "--\n",
        "-- TWO sub-tables under one global, because creature and object ids OVERLAP. 261 is both\n",
        "-- Guard Thomas and Damaged Crate, so no test on the id itself can tell them apart.\n",
        "-- The point's KIND is what says which of the two to read, and reading the wrong one\n",
        "-- returns a real name for the wrong thing rather than nil.\n",
        "--\n",
        "-- Holds exactly the ids the srcID slot of Data/QuestAvailable_*.lua's start table and\n",
        "-- Data/QuestTurnIn_*.lua actually reference, so nothing is orphaned and nothing is\n",
        "-- missing. A quest started by an ITEM stores no source and needs no name here.\n",
        "--\n",
        "-- English. The client cannot name a creature it has never seen and offers no way to\n",
        "-- ask by id on this flavor, so unlike a quest title there is nothing to prefer over it.\n",
        "ns.CLASSIC_QUEST_SOURCES = {\n",
    }

    local expect = { npc = {}, obj = {} }
    local counts, missing, unnamedOverlay = { npc = 0, obj = 0 }, { npc = 0, obj = 0 }, { npc = 0, obj = 0 }

    local function emit(label, set, db)
        parts[#parts + 1] = ("%s = {\n"):format(label)
        local sorted = {}
        for id in pairs(set) do sorted[#sorted + 1] = id end
        table.sort(sorted)
        for i = 1, #sorted do
            local id = sorted[i]
            local row = db[id]
            local nm = row and row[NAME]
            -- An Era name marked UNUSED or [PH] that only supplement quests use is a placeholder Forever reused, so it shows none.
            local stub = type(nm) == "string" and (nm:find("UNUSED", 1, true) or nm:find("^%[PH%]")) ~= nil
                         and not eraWants[label][id]
            if type(nm) == "string" and nm ~= "" and not stub then
                parts[#parts + 1] = ("\t[%d]=%q,\n"):format(id, nm)
                expect[label][id] = nm
                counts[label] = counts[label] + 1
            elseif overlaid[db] and overlaid[db][id] then
                unnamedOverlay[label] = unnamedOverlay[label] + 1
            elseif stub then
                unnamedOverlay[label] = unnamedOverlay[label] + 1
            else
                missing[label] = missing[label] + 1
            end
        end
        parts[#parts + 1] = "},\n"
    end

    local tableAt = #parts
    emit("npc", wantNpc, npcs)
    emit("obj", wantObj, objects)
    parts[#parts + 1] = "}\n"
    if unnamedOverlay.npc + unnamedOverlay.obj > 0 then
        table.insert(parts, tableAt, ("-- %d creature(s) and %d object(s) used only by Forever supplement quests have no name yet, so their pins and Quest Browser lines show none.\n")
            :format(unnamedOverlay.npc, unnamedOverlay.obj))
    end
    local text = table.concat(parts)

    do
        local probe = {}
        assert(loadstring(text))("EQ", probe)
        local got = assert(probe.CLASSIC_QUEST_SOURCES, "emitted file did not define the table")
        local seen = 0
        for _, label in ipairs({ "npc", "obj" }) do
            local dst = assert(got[label], "sub-table missing after reload: " .. label)
            for id, nm in pairs(expect[label]) do
                assert(dst[id] == nm,
                       ("%s %d name changed on reload: %s vs %s")
                       :format(label, id, tostring(dst[id]), nm))
                seen = seen + 1
            end
            -- Both directions, or a reload that INVENTED a row would pass the loop above.
            for id in pairs(dst) do
                assert(expect[label][id] ~= nil,
                       ("%s %d gained a row on reload"):format(label, id))
            end
        end
        assert(seen == counts.npc + counts.obj, "name count changed on reload")
        io.stderr:write(("-- verified %d source name(s) by reload\n"):format(seen))
    end

    -- A dump source with no name stops the build, while an unnamed supplement source is counted in the header instead.
    assert(missing.npc == 0 and missing.obj == 0,
           ("%d creature and %d object source(s) have no name upstream")
           :format(missing.npc, missing.obj))
    io.write(text)
    io.stderr:write(("-- mode=srcnames | npc names=%d (%d unnamed) obj names=%d (%d unnamed) bytes=%d\n")
        :format(counts.npc, unnamedOverlay.npc, counts.obj, unnamedOverlay.obj, #text))
    return
end

-- Derived from the dump: the client's GetQuestTagInfo cannot answer for an unaccepted quest.
if mode == "category" then
    local CAT_INSTANCE, CAT_REPEATABLE, CAT_EVENT, CAT_CLASS, CAT_PROFESSION = 1, 2, 4, 8, 16

    -- The 125 areas the entrance source names. That file's whole purpose is to say which areas
    -- are instances, so this is a claim it already makes rather than one inferred from a gap.
    -- An area merely missing from areaIdToUiMapId is NOT used - that set holds removed and
    -- sub-zone areas too, and calling those dungeons would hide open-world quests.
    local instanceArea = {}
    if entrances then
        for areaId, row in pairs(entrances) do
            instanceArea[areaId] = true
            local alt = row[1]
            if alt and alt ~= false then instanceArea[alt] = true end
        end
    end
    -- foreverInstances.lua, from build_forever_supplement.lua, adds the area ids the converter gives ATT's instances.
    local instancesPath = dir .. "/foreverInstances.lua"
    local instancesFile = io.open(instancesPath, "rb")
    if instancesFile then
        instancesFile:close()
        assert(PREFIX == "classic", "Forever instances cannot be applied to " .. PREFIX .. " data")
        for areaId in pairs(assert(loadfile(instancesPath))()) do instanceArea[areaId] = true end
    end

    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = category bitmask\n",
        "--   1 instance    the quest is sorted into a dungeon or raid area\n",
        "--   2 repeatable  specialFlags bit 0\n",
        "--   4 event       specialFlags bit 1, which marks a quest completed by exploring\n",
        "--                 or by a script. It is NOT a holiday marker.\n",
        "--   8 class       the quest carries a required class mask\n",
        "--  16 profession  the quest carries a required skill\n",
        "-- A quest with no category at all is left out, so absence means ordinary quest.\n",
        "-- Derived entirely from the dump. The client's own GetQuestTagInfo answers only for\n",
        "-- quests it already knows, which is why it cannot drive a filter for unaccepted ones.\n",
        "ns.CLASSIC_QUEST_CATEGORY = {\n",
    }

    local expect = {}
    local counts = { instance = 0, repeatable = 0, event = 0, class = 0, profession = 0 }
    local emitted = 0

    for i = 1, #ids do
        local id = ids[i]
        local q = quests[id]
        local mask = 0

        local zone = tonumber(q[Q_ZONEORSORT])
        if zone and zone > 0 and instanceArea[zone] then
            mask = mask + CAT_INSTANCE
            counts.instance = counts.instance + 1
        end

        local sf = tonumber(q[Q_SPECIALFLAGS]) or 0
        if math.floor(sf / 1) % 2 == 1 then
            mask = mask + CAT_REPEATABLE
            counts.repeatable = counts.repeatable + 1
        end
        if math.floor(sf / 2) % 2 == 1 then
            mask = mask + CAT_EVENT
            counts.event = counts.event + 1
        end

        local cls = tonumber(q[Q_CLASSES]) or 0
        if cls > 0 then
            mask = mask + CAT_CLASS
            counts.class = counts.class + 1
        end

        -- requiredSkill is {skillLineID, value}. Its presence is the claim, not the value -
        -- there is no reliable skill id to name lookup on this client, so only the fact ships.
        local skill = q[Q_REQSKILL]
        if type(skill) == "table" and tonumber(skill[1]) and tonumber(skill[1]) > 0 then
            mask = mask + CAT_PROFESSION
            counts.profession = counts.profession + 1
        end

        if mask > 0 then
            expect[id] = mask
            emitted = emitted + 1
            parts[#parts + 1] = ("\t[%d]=%d,\n"):format(id, mask)
        end
    end
    parts[#parts + 1] = "}\n"
    local text = table.concat(parts)

    do
        local probe = {}
        assert(loadstring(text))("EQ", probe)
        local got = assert(probe.CLASSIC_QUEST_CATEGORY, "emitted file did not define the table")
        local seen = 0
        for qid, mask in pairs(expect) do
            local v = got[qid]
            assert(v == mask, ("quest %d category changed on reload: %s vs %s")
                   :format(qid, tostring(v), tostring(mask)))
            assert(v > 0 and v <= 31, ("quest %d mask %s out of range"):format(qid, tostring(v)))
            seen = seen + 1
        end
        assert(seen == emitted, "row count changed on reload")
        for qid in pairs(got) do
            assert(expect[qid], "quest gained a row on reload: " .. tostring(qid))
        end
        io.stderr:write(("-- verified %d category row(s) by reload\n"):format(seen))
    end

    io.write(text)
    io.stderr:write(("-- mode=category | quests=%d categorized=%d bytes=%d\n")
        :format(#ids, emitted, #text))
    io.stderr:write(("-- instance=%d repeatable=%d event=%d class=%d profession=%d\n")
        :format(counts.instance, counts.repeatable, counts.event, counts.class, counts.profession))
    return
end

local rows = {}
local stats = { total = 0, objective = 0, turnin = 0, none = 0, noMap = 0 }
for i = 1, #ids do
    local id = ids[i]
    local q = quests[id]
    stats.total = stats.total + 1

    local pts = objectivePoints(q, id)
    if #pts > 0 then
        stats.objective = stats.objective + 1
    elseif mode == "both" then
        pts = turninPoints(q)
        if #pts > 0 then stats.turnin = stats.turnin + 1 end
    end

    if #pts == 0 then
        stats.none = stats.none + 1
    else
        local a, x, y = pick(pts)
        local ui = area2ui[a]
        if not ui then
            stats.noMap = stats.noMap + 1
        elseif (not zoneFilter) or ui == zoneFilter then
            rows[#rows + 1] = { id = id, m = ui, x = x / 100, y = y / 100 }
        end
    end
end

-- Lua 5.1's string.format("%d") casts through a 32-bit int, so a packed value above 2^31 writes
-- as -2147483648. %.0f avoids it, and the emitted text is read back and verified below.
local function packOf(r)
    local xi = math.floor(r.x * 10000 + 0.5); if xi > 9999 then xi = 9999 end
    local yi = math.floor(r.y * 10000 + 0.5); if yi > 9999 then yi = 9999 end
    return r.m * 100000000 + xi * 10000 + yi
end

-- objective and both emit this same global, so their tables are alternatives and a TOC lists one.
local out = { "local _, ns = ...\n", "\nns.CLASSIC_QUEST_COORDS = {\n" }
for i = 1, #rows do
    local r = rows[i]
    if encoding == "packed" then
        out[#out + 1] = ("\t[%d]=%.0f,\n"):format(r.id, packOf(r))
    else
        out[#out + 1] = ("\t[%d]={m=%d,x=%.4f,y=%.4f},\n"):format(r.id, r.m, r.x, r.y)
    end
end
out[#out + 1] = "}\n"
if placesFilled then
    out[#out + 1] = "\n-- A second database filled in where quests are explored or end, so one with no such place gets no arrow to its hand-in.\n"
    out[#out + 1] = "ns.CLASSIC_EXPLORE_PLACES_FILLED = true\n"
end
local body = table.concat(out)

do
    local probe = {}
    assert(loadstring(body))("EQ", probe)
    local got = assert(probe.CLASSIC_QUEST_COORDS, "emitted file did not define the table")
    assert((probe.CLASSIC_EXPLORE_PLACES_FILLED == true) == placesFilled, "the filled places mark changed on reload")
    local seen, worst = 0, 0
    for i = 1, #rows do
        local r = rows[i]
        local v = got[r.id]
        assert(v ~= nil, "row missing after reload: quest " .. r.id)
        local m, x, y
        if encoding == "packed" then
            assert(type(v) == "number" and v > 0,
                   ("quest %d serialized as %s - 32-bit overflow?"):format(r.id, tostring(v)))
            m = math.floor(v / 100000000)
            local rest = v % 100000000
            x, y = math.floor(rest / 10000) / 10000, (rest % 10000) / 10000
        else
            m, x, y = v.m, v.x, v.y
        end
        assert(m == r.m, ("map id changed on reload for quest %d"):format(r.id))
        local d = math.max(math.abs(x - r.x), math.abs(y - r.y))
        if d > worst then worst = d end
        seen = seen + 1
    end
    assert(seen == #rows, "row count changed on reload")
    assert(worst <= 0.0001, "coordinate drift on reload: " .. worst)
    io.stderr:write(("-- verified %d row(s) by reload, max drift %.6f\n"):format(seen, worst))
end

io.write(body)
io.stderr:write(("-- mode=%s enc=%s zone=%s | quests=%d emitted=%d objective=%d turnin=%d none=%d noUiMap=%d bytes=%d\n")
    :format(mode, encoding, tostring(zoneFilter or "all"), stats.total, #rows,
            stats.objective, stats.turnin, stats.none, stats.noMap, #body))
