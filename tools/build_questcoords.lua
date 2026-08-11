-- Derives quest location tables for the Classic flavors from an upstream dataset.
--
--   lua5.1 tools/build_questcoords.lua <dataDir> [mode] [encoding] [uiMapId]
--     mode      objective | turnin | both | spawns | npcs
--                 (default both: one point per quest, objective with turn-in as fallback)
--                 (spawns: EVERY objective location, clustered - a different table, see below)
--                 (npcs: which creatures advance each quest - no coordinates, for nameplates)
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

local SOURCES = {
    quests  = { file = "classicQuestDB.lua",   marker = "questData = [["   },
    npcs    = { file = "classicNpcDB.lua",     marker = "npcData = [["     },
    objects = { file = "classicObjectDB.lua",  marker = "objectData = [["  },
    items   = { file = "classicItemDB.lua",    marker = "itemData = [["    },
    areaMap = { file = "areaIdToUiMapId.lua",  marker = "areaIdToUiMapId = [[" },
    -- Optional. Without it, objectives inside an instance simply get no pin.
    dungeons = { file = "dungeonEntrances.lua", marker = "dungeonEntrances = [[", optional = true },
}

-- Field indices, from the upstream schema.
local NPC_SPAWNS, OBJ_SPAWNS = 7, 4
local Q_FINISHEDBY, Q_OBJECTIVES = 3, 10
local I_NPCDROPS, I_OBJDROPS = 2, 3

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

local function collect(out, rec, idx, kind, objIdx)
    local sp = rec and rec[idx]
    if type(sp) ~= "table" then return end
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
                    out[#out + 1] = { a = areaId, x = px, y = py, k = kind, oi = objIdx }
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
-- claims all four. Safe because no Era quest has both creature and killcredit objectives.
local function collectNpc(out, id, kind, objIdx)
    kind = kind or KIND_SLAY
    if npcSink and type(id) == "number" and id > 0 and objIdx then
        local byIdx = npcSink[id]
        if not byIdx then byIdx = {}; npcSink[id] = byIdx end
        local prev = byIdx[objIdx]
        -- Lower kind wins, so a real kill objective outranks the same mob merely dropping an item
        if not prev or kind < prev then byIdx[objIdx] = kind end
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

-- Entrance points belong to the spawn map only. The single point modes emit
-- ns.CLASSIC_QUEST_COORDS, which carries no kind field, so an entrance there is indistinguishable
-- from a real location. Measured: without this gate the both mode grows 3985 rows to 4062.
local WANT_ENTRANCES = (mode == "spawns")

local function objectivePoints(q)
    local pts, o = {}, q[Q_OBJECTIVES]
    if WANT_ENTRANCES then realSeen, sentinelSeen = {}, {} end
    if type(o) ~= "table" then realSeen, sentinelSeen = nil, nil; return pts end
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
    -- o[5] shares the client's "monster" type with o[1], so they would share an index space.
    -- Measured: ZERO Era quests carry both, so this cannot collide.
    if type(o[5]) == "table" then
        for i = 1, #o[5] do
            local e = o[5][i]
            if type(e) == "table" and type(e[1]) == "table" then
                for k = 1, #e[1] do collectNpc(pts, e[1][k], nil, i - 1) end
            end
        end
    end
    appendEntrances(pts)
    realSeen, sentinelSeen = nil, nil
    return pts
end

local function turninPoints(q)
    local pts, f = {}, q[Q_FINISHEDBY]
    if type(f) ~= "table" then return pts end
    if type(f[1]) == "table" then for i = 1, #f[1] do collectNpc(pts, f[1][i]) end end
    if type(f[2]) == "table" then for i = 1, #f[2] do collectObj(pts, f[2][i]) end end
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
                -- The cell keeps a real spawn rather than its centre, which would drift into
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
                -- Single-bit OR, spelled out: Lua 5.1 has no bit library
                local b = 2 ^ p.oi
                if c.oim % (b + b) < b then c.oim = c.oim + b end
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
                    -- A cell with more than one bit serves more than one objective.
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

    -- Read the emitted text back and check every value. A serializer that is right in memory
    -- and wrong on disk produces a file that loads clean and is entirely dead.
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

    -- Read the emitted TEXT back and check every row, the same discipline the coordinate tables
    -- use: a serializer that is right in memory and wrong on disk loads clean and is dead.
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
