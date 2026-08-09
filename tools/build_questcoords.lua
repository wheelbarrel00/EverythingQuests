-- Derives a quest -> single-waypoint table for the Classic flavors from an upstream dataset.
--
--   lua5.1 tools/build_questcoords.lua <dataDir> [mode] [encoding] [uiMapId]
--     mode      objective | turnin | both     (default both: objective, turn-in as fallback)
--     encoding  packed | table                (default packed - see the memory note below)
--     uiMapId   optional, emit one zone only, for a pilot
--
-- Run it on real Lua 5.1.5, the version the game uses. <dataDir> holds the upstream files
-- listed in SOURCES below; the rows in them are Lua literals inside a [[return {...}]] long
-- string, so they are loadstring'd rather than parsed. Exact, and it cannot drift.
--
-- ⛔ ONE point per quest, matching what retail's GetNextWaypointForMap returns. NOT a spawn
-- map. Storing every spawn would be roughly 100x the size to support behavior EQ does not have.
--
-- ⛔ MEASURED on Lua 5.1.5, 3985 rows: the {m=,x=,y=} shape EQ ships on retail costs 1063 KB
-- resident, because each row is its own hash table. The packed encoding costs 192 KB and
-- round-trips exactly. That is why packed is the default. Do not "tidy" it back to a table.
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
}

-- Field indices, from the upstream schema.
local NPC_SPAWNS, OBJ_SPAWNS = 7, 4
local Q_FINISHEDBY, Q_OBJECTIVES = 3, 10
local I_NPCDROPS, I_OBJDROPS = 2, 3

local function loadBlock(spec)
    local path = dir .. "/" .. spec.file
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
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
local area2ui = loadBlock(SOURCES.areaMap)

local function collect(out, rec, idx)
    local sp = rec and rec[idx]
    if type(sp) ~= "table" then return end
    for areaId, pts in pairs(sp) do
        if type(areaId) == "number" and areaId > 0 and type(pts) == "table" then
            for i = 1, #pts do
                local p = pts[i]
                local px = type(p) == "table" and tonumber(p[1])
                local py = type(p) == "table" and tonumber(p[2])
                -- -1,-1 means "exists, location unknown". It is a sentinel, not a place, and
                -- averaging it in drags the pin off the map. It was 470 of 4123 rows.
                if px and py and px > 0 and py > 0 then
                    out[#out + 1] = { a = areaId, x = px, y = py }
                end
            end
        end
    end
end

local function collectNpc(out, id) collect(out, npcs[id], NPC_SPAWNS) end
local function collectObj(out, id) collect(out, objects[id], OBJ_SPAWNS) end

local function collectItem(out, id)
    local it = items[id]
    if not it then return end
    local drops = it[I_NPCDROPS]
    if type(drops) == "table" then for i = 1, #drops do collectNpc(out, drops[i]) end end
    local odrops = it[I_OBJDROPS]
    if type(odrops) == "table" then for i = 1, #odrops do collectObj(out, odrops[i]) end end
end

-- Deterministic so a rerun is byte identical: the zone holding the most spawns, then the real
-- spawn nearest that zone's mean. A raw centroid can land in terrain no player can stand on
-- when a mob spawns in two clusters, so it snaps to an actual point.
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

local function objectivePoints(q)
    local pts, o = {}, q[Q_OBJECTIVES]
    if type(o) ~= "table" then return pts end
    if type(o[1]) == "table" then
        for i = 1, #o[1] do local e = o[1][i]; if type(e) == "table" and e[1] then collectNpc(pts, e[1]) end end
    end
    if type(o[2]) == "table" then
        for i = 1, #o[2] do local e = o[2][i]; if type(e) == "table" and e[1] then collectObj(pts, e[1]) end end
    end
    if type(o[3]) == "table" then
        for i = 1, #o[3] do local e = o[3][i]; if type(e) == "table" and e[1] then collectItem(pts, e[1]) end end
    end
    if type(o[5]) == "table" then
        for i = 1, #o[5] do
            local e = o[5][i]
            if type(e) == "table" and type(e[1]) == "table" then
                for k = 1, #e[1] do collectNpc(pts, e[1][k]) end
            end
        end
    end
    return pts
end

local function turninPoints(q)
    local pts, f = {}, q[Q_FINISHEDBY]
    if type(f) ~= "table" then return pts end
    if type(f[1]) == "table" then for i = 1, #f[1] do collectNpc(pts, f[1][i]) end end
    if type(f[2]) == "table" then for i = 1, #f[2] do collectObj(pts, f[2][i]) end end
    return pts
end

local ids = {}
for id in pairs(quests) do ids[#ids + 1] = id end
table.sort(ids)

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

-- ⛔ Lua 5.1's string.format("%d") casts through a 32-bit int, so a packed value above 2^31
-- writes as -2147483648. The numbers are correct in memory - only serializing them breaks -
-- so %.0f is used AND the emitted text is read back and verified below. An encoder that is
-- right in memory and wrong on disk produces a file that loads clean and is entirely dead.
local function packOf(r)
    local xi = math.floor(r.x * 10000 + 0.5); if xi > 9999 then xi = 9999 end
    local yi = math.floor(r.y * 10000 + 0.5); if yi > 9999 then yi = 9999 end
    return r.m * 100000000 + xi * 10000 + yi
end

-- ⛔ EVERY run emits this SAME global name, whichever table was generated. The objective and
-- turn-in tables are therefore ALTERNATIVES, not a pair - listing both in one TOC silently
-- keeps whichever loads second and no error is raised. Rename here first if both are ever
-- wanted at once, and rename the reader in Modules/MapPOI with it.
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
