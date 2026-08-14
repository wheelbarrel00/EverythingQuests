-- Derives quest location tables for the Classic flavors from an upstream dataset.
--
--   lua5.1 tools/build_questcoords.lua <dataDir> [mode] [encoding] [uiMapId]
--     mode      objective | turnin | both | spawns | npcs | available | category
--                 (default both: one point per quest, objective with turn-in as fallback)
--                 (spawns: EVERY objective location, clustered - a different table, see below)
--                 (npcs: which creatures advance each quest - no coordinates, for nameplates)
--                 (available: where a quest can be PICKED UP, plus every gate that decides
--                  whether it can be, for quests that are not in the log yet)
--                 (turnin: where each quest is HANDED IN, clustered per map. The both mode's
--                  point is the OBJECTIVE for any quest that has one, so it answers a different
--                  question and puts a finished quest's pin back on the field you farmed.)
--     encoding  packed | table                (default packed - see the memory note below)
--     uiMapId   optional, emit one zone only, for a pilot
--
-- Run it on real Lua 5.1.5, the version the game uses. <dataDir> holds the upstream files
-- listed in SOURCES below. Their rows are Lua literals inside a [[return {...}]] long string,
-- so they are loadstring'd rather than parsed.
--
-- objective/turnin/both emit one waypoint per quest, spawns emits every objective location.
-- They define different global names, so both can ship at once.
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
-- mislabel 983 quests.
local Q_ZONEORSORT = 17
local Q_NEXTINCHAIN, Q_SPECIALFLAGS, Q_PARENT = 22, 24, 25

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

-- An item objective keeps KIND_LOOT even though it resolves through the NPC that drops it,
-- because "loot it here" is the player-facing fact.
local KIND_SLAY, KIND_OBJECT, KIND_LOOT = 1, 2, 3

-- An entrance point is the same kind plus this, so the reader recovers the real kind by
-- subtracting and the objective index still means "the nth objective of that type".
local KIND_ENTRANCE = 4

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

local function collect(out, rec, idx, kind, objIdx)
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
                -- averaging it in drags the pin off the map. It was 470 of 4123 rows.
                if px and py and px > 0 and py > 0 then
                    out[#out + 1] = { a = areaId, x = px, y = py, k = kind, oi = objIdx, om = om }
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
                    out[#out + 1] = { a = coords[c][1], x = coords[c][2], y = coords[c][3],
                                      k = kind + KIND_ENTRANCE, oi = objIdx }
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
    -- A bought item. Same KIND_LOOT because the player-facing fact is "get the item here", and
    -- because kinds 1-3 are the only values the entrance offset of 4 leaves room for.
    local vendors = it[I_VENDORS]
    if type(vendors) == "table" then
        -- Vendors reach 184 for one item, so the same cutoff gates the mob list here too.
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

-- Entrance points belong to the per-map tables only. The single point modes emit
-- ns.CLASSIC_QUEST_COORDS, which carries no kind field, so an entrance there is indistinguishable
-- from a real location. Measured: without this gate the both mode grows 3985 rows to 4062.
local WANT_ENTRANCES = (mode == "spawns" or mode == "turnin")

local function objectivePoints(q)
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
    if type(o) ~= "table" then realSeen, sentinelSeen = nil, nil; return pts end
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
            for i = 1, #f[1] do collect(pts, npcs[f[1][i]], NPC_SPAWNS, KIND_SLAY, TURNIN_IDX) end
        end
        if type(f[2]) == "table" then
            for i = 1, #f[2] do collect(pts, objects[f[2][i]], OBJ_SPAWNS, KIND_OBJECT, TURNIN_IDX) end
        end
        appendEntrances(pts)
    end
    realSeen, sentinelSeen = nil, nil
    return pts
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
                c = { m = ui, x = x, y = y, k = p.k, n = 0, seq = #(byMap[ui] or {}) }
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

if mode == "spawns" then
    local emitted, sQuests, sPairs, widest, shared = 0, 0, 0, 0, 0
    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = { [uiMapID] = { packed, ... } }\n",
        "-- packed = objMask*1e9 + kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)\n",
        "-- kind 1=slay 2=object 3=loot, and the same +4 (5,6,7) for a DUNGEON ENTRANCE - the\n",
        "-- objective is inside an instance whose interior coordinates nobody records, so the\n",
        "-- pin marks the way in. Recover the real kind by subtracting 4.\n",
        "-- objMask is a BITMASK of the objectives this location serves - bit i means the ith\n",
        "-- objective OF THIS KIND'S TYPE, 0 based, the same numbering Data/QuestNPCs_Classic\n",
        "-- uses. One location commonly serves several, which is why it is not a single index.\n",
        "-- decode: objMask = floor(v/1e9), kind = floor(v%1e9/1e8), rest = v%1e8,\n",
        "--         x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4\n",
        "-- Each list is ordered densest first. The reader draws the first N, so the order is\n",
        "-- what makes a pin limit keep the N best locations instead of N arbitrary ones.\n",
        "ns.CLASSIC_QUEST_SPAWNS = {\n",
    }
    local expect = {}

    for i = 1, #ids do
        local id = ids[i]
        local byMap = clusterByMap(objectivePoints(quests[id]))

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
                    nums[j] = ("%.0f"):format(mask * 1000000000 + kind * 100000000 + xi * 10000 + yi)
                    mine[j] = { x = xi / 10000, y = yi / 10000, k = kind, oim = mask }
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

    io.write(text)
    io.stderr:write(("-- mode=spawns grid=%.3f UNCAPPED zone=%s | quests=%d emitted=%d quest-map pairs=%d widest=%d bytes=%d\n")
        :format(SPAWN_GRID, tostring(zoneFilter or "all"), sQuests, emitted, sPairs, widest, #text))
    io.stderr:write(("-- %d point(s) serve MORE THAN ONE objective (%.1f%%) - each of those is a\n")
        :format(shared, shared / math.max(1, emitted) * 100))
    io.stderr:write("-- pin a single objective index would have mislabelled or hidden\n")
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
        objectivePoints(quests[id])
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
    -- The same 1/2/3 the other tables use for creature, object and item, because the source of
    -- a start point is the same three things. Here it means who OFFERS the quest, not what the
    -- objective is, which is why this table documents its own kinds rather than sharing theirs.
    local START_NPC, START_OBJECT, START_ITEM = 1, 2, 3

    local function startPoints(q)
        local pts, sb = {}, q[Q_STARTEDBY]
        if type(sb) ~= "table" then return pts end
        if type(sb[1]) == "table" then
            for i = 1, #sb[1] do collect(pts, npcs[sb[1][i]], NPC_SPAWNS, START_NPC) end
        end
        if type(sb[2]) == "table" then
            for i = 1, #sb[2] do collect(pts, objects[sb[2][i]], OBJ_SPAWNS, START_OBJECT) end
        end
        -- A quest started by an ITEM is picked up wherever that item drops, so the pin marks
        -- the source rather than a person standing somewhere.
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

    -- Two digits of required level, two of quest level, one of flags, four of each bitmask.
    -- Thirteen digits sits well inside a double's exact integer range, and packing by decimal
    -- rather than by bits keeps this working on an interpreter with no bit library.
    local function packGates(id, q)
        local lvl   = math.max(0, math.min(99, tonumber(q[Q_REQLEVEL]) or 0))
        local qlvl  = math.max(0, math.min(99, tonumber(q[Q_QUESTLEVEL]) or 0))
        local races = tonumber(q[Q_RACES]) or 0
        local class = tonumber(q[Q_CLASSES]) or 0
        -- Only the low three: repeatable, needs a world event, monthly reset
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
        local byMap = clusterSimple(startPoints(q))

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

    local sortedIds = {}
    for id in pairs(start) do sortedIds[#sortedIds + 1] = id end
    table.sort(sortedIds)

    local parts = {
        "local _, ns = ...\n",
        "\n-- Where every quest can be PICKED UP, and the gates that decide whether it can be.\n",
        "-- The client answers none of this for a quest that is not in the log, so it ships.\n",
        "--\n",
        "-- start  [questID] = { [uiMapID] = { packed, ... } }\n",
        "--        packed = kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)\n",
        "--        kind 1=an NPC offers it, 2=an object offers it, 3=an item that starts it\n",
        "--        drops here. These are SOURCES of the quest, not objective types.\n",
        "--        decode: kind = floor(v/1e8), rest = v%1e8,\n",
        "--                x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4\n",
        "--        Ordered densest first, so a reader's prefix keeps the best locations.\n",
        "-- gates  [questID] = requiredLevel*1e11 + questLevel*1e9 + specialFlags*1e8\n",
        "--                    + requiredRaces*1e4 + requiredClasses\n",
        "--        specialFlags: 1 repeatable, 2 needs a world event, 4 monthly reset\n",
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
                -- %.0f rather than %d: Lua 5.1's %d casts through a 32-bit int
                nums[j] = ("%.0f"):format(kind * 100000000 + xi * 10000 + yi)
                mine[j] = { x = xi / 10000, y = yi / 10000, k = kind }
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
    emitScalar("skill", skill)
    emitScalar("minRep", minRep)
    emitScalar("maxRep", maxRep)
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
                    local kind = math.floor(v / 100000000)
                    local rest = v % 100000000
                    local x, y = math.floor(rest / 10000) / 10000, (rest % 10000) / 10000
                    assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                           ("quest %d decoded out of range: %s,%s"):format(qid, x, y))
                    assert(kind == list[j].k,
                           ("quest %d start kind changed on reload"):format(qid))
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
            assert(math.floor(v % 100000000 / 10000) == (tonumber(q[Q_RACES]) or 0),
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
    return
end

if mode == "turnin" then
    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = { [uiMapID] = { packed, ... } }\n",
        "-- packed = kind*1e8 + floor(x*1e4)*1e4 + floor(y*1e4)\n",
        "-- kind 1=an NPC takes it, 2=an object does, and the same +4 (5,6) for a DUNGEON\n",
        "-- ENTRANCE - the turn-in is inside an instance whose interior coordinates nobody\n",
        "-- records, so the pin marks the way in. Recover the real kind by subtracting 4.\n",
        "-- decode: kind = floor(v/1e8), rest = v%1e8,\n",
        "--         x = floor(rest/1e4)/1e4, y = (rest%1e4)/1e4\n",
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
                    -- %.0f rather than %d: Lua 5.1's %d casts through a 32-bit int
                    nums[j] = ("%.0f"):format(kind * 100000000 + xi * 10000 + yi)
                    mine[j] = { x = xi / 10000, y = yi / 10000, k = kind }
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
                    local kind = math.floor(v / 100000000)
                    local rest = v % 100000000
                    local x, y = math.floor(rest / 10000) / 10000, (rest % 10000) / 10000
                    assert(x >= 0 and x <= 1 and y >= 0 and y <= 1,
                           ("quest %d decoded out of range: %s,%s"):format(qid, x, y))
                    assert(kind == list[j].k,
                           ("quest %d turn-in kind changed on reload"):format(qid))
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

    local parts = {
        "local _, ns = ...\n",
        "\n-- [questID] = category bitmask\n",
        "--   1 instance    the quest is sorted into a dungeon or raid area\n",
        "--   2 repeatable  specialFlags bit 0\n",
        "--   4 event       specialFlags bit 1, a world event or holiday quest\n",
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
    io.stderr:write(("-- mode=category | quests=%d categorised=%d bytes=%d\n")
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

    local pts
    if mode == "turnin" then
        pts = turninPoints(q)
        if #pts > 0 then stats.turnin = stats.turnin + 1 end
    else
        pts = objectivePoints(q)
        if #pts > 0 then
            stats.objective = stats.objective + 1
        elseif mode == "both" then
            pts = turninPoints(q)
            if #pts > 0 then stats.turnin = stats.turnin + 1 end
        end
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

-- Every run emits this same global name, so the objective and turn-in tables are alternatives.
-- Listing both in one TOC silently keeps whichever loads second. Rename here and in MapPOI first.
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
local body = table.concat(out)

do
    local probe = {}
    assert(loadstring(body))("EQ", probe)
    local got = assert(probe.CLASSIC_QUEST_COORDS, "emitted file did not define the table")
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
