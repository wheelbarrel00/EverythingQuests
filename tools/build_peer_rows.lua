-- Writes peerRows.lua into a source folder for build_questcoords.lua: a peer quest database's values where they differ from
-- the dump's, from that database in the same upstream layout, decoded to <peer dir>.
--
--   lua5.1 tools/build_peer_rows.lua <source folder> <peer dir> [game objective lists] [AllTheThings db folder]
--
-- The peer database is the dump with years of corrections, so its value wins wherever the two differ, an empty one included
-- (written false), except that a faction it leaves empty is unknown rather than neutral, quest flags are the client's own,
-- and a place in an area the dump does not know is left out. The optional files grade what is taken: the game's objective
-- lists (foreverClientObjectives.lua), and AllTheThings' givers, levels and prerequisites for the same quests.

local srcDir, peerDir, clientPath, attDir = ...
assert(srcDir and peerDir, "usage: lua5.1 tools/build_peer_rows.lua <source folder> <peer dir> [game objective lists] [AllTheThings db folder]")

local function block(path, marker)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    local a = assert(s:find("return {", assert(s:find(marker, 1, true), "marker not found in " .. path), true))
    return assert(loadstring(s:sub(a, assert(s:find("}]]", a, true)))))()
end

local function empty(v) return v == nil or v == 0 or v == false or (type(v) == "table" and next(v) == nil) end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
    end)
    return keys
end

local function ser(v)
    local t = type(v)
    if t == "number" then return v == math.floor(v) and ("%d"):format(v) or ("%.15g"):format(v) end
    if t == "string" then return ("%q"):format(v) end
    if t == "boolean" then return tostring(v) end
    assert(t == "table", "cannot write a " .. t)
    local parts = {}
    for _, k in ipairs(sortedKeys(v)) do parts[#parts + 1] = ("[%s]=%s"):format(ser(k), ser(v[k])) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- An objective entry's third field is 0 on one side and absent on the other, the same meaning.
local function canon(v)
    if type(v) == "number" then return ("%.4f"):format(v) end
    if type(v) ~= "table" then return tostring(v) end
    local parts = {}
    for _, k in ipairs(sortedKeys(v)) do
        if not (k == 3 and v[k] == 0 and type(v[1]) == "number") then parts[#parts + 1] = tostring(k) .. "=" .. canon(v[k]) end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- [field] = true to clear the dump's value where the peer has none, false to keep it.
local ENTITIES = {
    { "quests", "QuestDB.lua", "questData = [[", { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [7] = true,
        [9] = true, [10] = true, [12] = true, [13] = true, [16] = true, [17] = true, [18] = true, [19] = true, [20] = true,
        [22] = true, [24] = true, [25] = true } },
    { "npcs", "NpcDB.lua", "npcData = [[", { [7] = true, [13] = false } },
    { "objects", "ObjectDB.lua", "objectData = [[", { [4] = true } },
    { "items", "ItemDB.lua", "itemData = [[", { [2] = true, [3] = true, [14] = true } },
}

local prefix = io.open(srcDir .. "/classicQuestDB.lua", "rb") and "classic" or "tbc"

-- The peer database keeps zone ids of its own above 10000, which draw nowhere and would stop a quest falling back to its hand-in.
local known = {}
for area in pairs(block(srcDir .. "/areaIdToUiMapId.lua", "areaIdToUiMapId = [[")) do known[area] = true end
local dungeonFile = io.open(srcDir .. "/dungeonEntrances.lua", "rb")
if dungeonFile then
    dungeonFile:close()
    for area, row in pairs(block(srcDir .. "/dungeonEntrances.lua", "dungeonEntrances = [[")) do
        known[area] = true
        if row[1] then known[row[1]] = true end
    end
end
local dropped = 0
local function placed(byArea)
    if type(byArea) ~= "table" then return byArea end
    local out = {}
    for area, pts in pairs(byArea) do
        if known[area] then out[area] = pts else dropped = dropped + 1 end
    end
    return out
end
local SPAWN_FIELD = { npcs = 7, objects = 4 }
local function keep(name, f, v)
    if SPAWN_FIELD[name] == f then return placed(v) end
    if name == "quests" and f == 9 and type(v) == "table" then return { v[1], placed(v[2]) } end
    return v
end

-- Peer values a review found wrong, so the dump's stays, or a function trims the peer's. Each one is reported when it no longer differs.
local function arathiOnly(v) return type(v) == "table" and { v[1], { [45] = v[2] and v[2][45] } } or v end
local HOLD = {
    -- 6622 Triage for the Horde is done at Hammerfall, and the peer gives it 6624's Theramore spot
    -- 8121 and 8122 are held in Arathi Basin, and the peer adds Horde battlemasters in three other zones
    -- 8871, 8872, 8874 and 8875 lose their emissary in the peer's, which hides them
    -- 3375 Replacement Phial would wait for 2201, the quest the phial is used for
    quests = { [6622] = { [9] = true }, [8121] = { [9] = arathiOnly }, [8122] = { [9] = arathiOnly },
               [8871] = { [2] = true }, [8872] = { [2] = true }, [8874] = { [2] = true }, [8875] = { [2] = true },
               [3375] = { [13] = true } },
    -- Lieutenant Nevell stands in Dun Morogh, and the peer files his spot under Ironforge
    npcs = { [16484] = { [7] = true } },
    objects = {},
    -- 20944, which starts 8740 Twilight Marauders, drops from the creature the peer leaves out
    items = { [20944] = { [2] = true } },
}
local held = {}

local out, lines, taken = {}, {}, {}
for _, e in ipairs(ENTITIES) do
    local A = block(srcDir .. "/" .. prefix .. e[2], e[3])
    local B = block(peerDir .. "/" .. prefix .. e[2], e[3])
    local rows, counts, added = {}, {}, 0
    local fields = sortedKeys(e[4])
    for id, b in pairs(B) do
        local a = A[id]
        if not a then
            -- A quest the dump lacks is left out, since whether the game offers it is the dump's call. Anything else only
            -- matters once a quest names it.
            if e[1] ~= "quests" then
                local row = {}
                for k, v in pairs(b) do row[k] = keep(e[1], k, v) end
                rows[id] = row
                added = added + 1
            end
        else
            for _, f in ipairs(fields) do
                local bf, hold = b[f], HOLD[e[1]][id] and HOLD[e[1]][id][f]
                -- A quest the peer gates on a profession specialty keeps the dump's prerequisites, since EQ does not read that gate
                if not hold and e[1] == "quests" and (f == 12 or f == 13) and not empty(b[31]) then hold = true end
                if hold then
                    local was = bf
                    if hold == true then bf = a[f] else bf = hold(bf) end
                    if HOLD[e[1]][id] then held[#held + 1] = { e[1], id, f, canon(was) ~= canon(bf) } end
                end
                local v = keep(e[1], f, bf)
                local lost = not empty(bf) and (empty(v) or (f == 9 and e[1] == "quests" and empty(v[2])))
                local c = counts[f] or { fill = 0, change = 0, clear = 0 }
                counts[f] = c
                -- When every place it gives is in an area the dump does not know, the dump's own stays
                if lost then
                    c.kept = (c.kept or 0) + 1
                elseif empty(a[f]) and not empty(v) then
                    rows[id] = rows[id] or {}
                    rows[id][f] = v
                    c.fill = c.fill + 1
                elseif not empty(a[f]) and empty(v) then
                    if e[4][f] then
                        rows[id] = rows[id] or {}
                        rows[id][f] = false
                        c.clear = c.clear + 1
                    end
                elseif not empty(v) and canon(a[f]) ~= canon(v) then
                    rows[id] = rows[id] or {}
                    rows[id][f] = v
                    c.change = c.change + 1
                    taken[e[1] .. f] = taken[e[1] .. f] or {}
                    taken[e[1] .. f][id] = a[f]
                end
            end
        end
    end
    out[e[1]] = rows
    for id, byField in pairs(HOLD[e[1]]) do
        for f in pairs(byField) do
            local hit
            for _, h in ipairs(held) do if h[1] == e[1] and h[2] == id and h[3] == f then hit = h[4] end end
            if not hit then lines[#lines + 1] = ("-- peer rows: hold no longer needed, %s %d field %d"):format(e[1], id, f) end
        end
    end
    local parts = {}
    for _, f in ipairs(fields) do
        local c = counts[f] or { fill = 0, change = 0, clear = 0 }
        parts[#parts + 1] = ("%d: +%d ~%d -%d"):format(f, c.fill, c.change, c.clear)
    end
    lines[#lines + 1] = ("-- peer rows: %s (field: filled ~changed -cleared) %s; %d whole row(s) the dump lacks")
        :format(e[1], table.concat(parts, ", "), added)
end

-- An objective list taken is graded by its kinds against what the game lists for the quest.
if clientPath then
    local client = assert(loadfile(clientPath))()
    local checked, same = 0, 0
    for id, row in pairs(out.quests) do
        local o, list = row[10], client[id]
        if o and list then
            local want = { monster = 0, object = 0, item = 0 }
            for _, t in ipairs(list) do if want[t] then want[t] = want[t] + 1 end end
            local n1 = type(o[1]) == "table" and #o[1] or 0
            local n5 = type(o[5]) == "table" and #o[5] or 0
            local got = { monster = n1 + n5, object = type(o[2]) == "table" and #o[2] or 0, item = type(o[3]) == "table" and #o[3] or 0 }
            checked = checked + 1
            if got.monster == want.monster and got.object == want.object and got.item == want.item then same = same + 1 end
        end
    end
    lines[#lines + 1] = ("-- peer rows graded: %d of %d objective lists taken have the kinds the game lists"):format(same, checked)
end

-- Where the peer changed a giver, a required level or a prerequisite, AllTheThings says which side it agrees with.
if attDir then
    local att = dofile((debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tools/") .. "forever_att.lua")(attDir).quests
    local function set(t)
        local s = {}
        for _, v in ipairs(type(t) == "table" and t or {}) do s[#s + 1] = v end
        table.sort(s)
        return table.concat(s, ",")
    end
    local grades = {
        { "quests2", "givers", function(q) return set(q.givers) end, function(v) return set(type(v) == "table" and v[1]) end },
        { "quests4", "required levels", function(q) return tostring(q.reqLevel) end, function(v) return tostring(v) end },
        { "quests13", "prerequisites", function(q) return set(q.pre) end, function(v) return set(v) end },
    }
    for _, g in ipairs(grades) do
        local peerSide, ourSide, neither = 0, 0, 0
        for id, ours in pairs(taken[g[1]] or {}) do
            local q = att[id]
            if q then
                local a = g[3](q)
                local theirs = g[4](out.quests[id][tonumber(g[1]:match("%d+"))])
                if a == theirs then peerSide = peerSide + 1 elseif a == g[4](ours) then ourSide = ourSide + 1 else neither = neither + 1 end
            end
        end
        lines[#lines + 1] = ("-- peer rows graded: %s changed, AllTheThings agrees with the peer for %d, with the dump for %d, with neither for %d")
            :format(g[2], peerSide, ourSide, neither)
    end
end

local parts = { "-- Generated by tools/build_peer_rows.lua: a peer quest database's values where they differ from the dump's, false\n",
    "-- where it has none.\nreturn {\n" }
for _, e in ipairs(ENTITIES) do
    parts[#parts + 1] = e[1] .. " = {\n"
    for _, id in ipairs(sortedKeys(out[e[1]])) do parts[#parts + 1] = ("[%d]=%s,\n"):format(id, ser(out[e[1]][id])) end
    parts[#parts + 1] = "},\n"
end
parts[#parts + 1] = "}\n"
local path = srcDir .. "/peerRows.lua"
local f = assert(io.open(path, "wb"), "cannot write " .. path)
f:write(table.concat(parts))
f:close()
local back = assert(loadfile(path))()
for _, e in ipairs(ENTITIES) do
    local n, want = 0, 0
    for _ in pairs(back[e[1]]) do n = n + 1 end
    for _ in pairs(out[e[1]]) do want = want + 1 end
    assert(n == want, path .. ": " .. e[1] .. " row count changed on reload")
end
for _, line in ipairs(lines) do io.stderr:write(line .. "\n") end
io.stderr:write(("-- peer rows: %d place list(s) in an area the dump does not know left out\n"):format(dropped))
io.stderr:write("-- peer rows written to " .. path .. "\n")
