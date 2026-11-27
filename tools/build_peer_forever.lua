-- Writes peerForeverRows.lua into the WoW Forever source folder for build_questcoords.lua: a peer quest database's Forever
-- player traces and hand fixes, as operations the generator lays over the Forever rows after the map conversion, since they
-- were read on Forever. Of the peer's layer built from Wowhead only the reputation each quest rewards is taken, and of its
-- fixes none for one faction only.
--
--   lua5.1 tools/build_peer_forever.lua <Forever source folder> <peer database folder> <WoW Forever's Faction table, as CSV>

local srcDir, peerDir, factionCsv = ...
assert(srcDir and peerDir and factionCsv,
    "usage: lua5.1 tools/build_peer_forever.lua <Forever source folder> <peer database folder> <WoW Forever's Faction table, as CSV>")

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

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

local function csvRows(text)
    local rows, row, field, quoted, i = {}, {}, {}, false, 1
    while i <= #text do
        local c = text:sub(i, i)
        if quoted then
            if c == '"' and text:sub(i + 1, i + 1) == '"' then field[#field + 1] = '"'; i = i + 1
            elseif c == '"' then quoted = false
            else field[#field + 1] = c end
        elseif c == '"' then quoted = true
        elseif c == "," then row[#row + 1] = table.concat(field); field = {}
        elseif c == "\n" then row[#row + 1] = table.concat(field); field = {}; rows[#rows + 1] = row; row = {}
        elseif c ~= "\r" then field[#field + 1] = c end
        i = i + 1
    end
    if #field > 0 or #row > 0 then row[#row + 1] = table.concat(field); rows[#rows + 1] = row end
    return rows
end

-- A faction with a share to its parent passes part of every gain to the parent and the parent's other factions
local sharing = {}
do
    local rows = csvRows(readAll(factionCsv))
    local col = {}
    for i, name in ipairs(rows[1] or {}) do col[name] = i end
    assert(col.ID and col.ParentFactionID and col.ParentFactionMod_1, factionCsv .. " has no ID, ParentFactionID or ParentFactionMod_1 column")
    local n = 0
    for r = 2, #rows do
        local id, parent = tonumber(rows[r][col.ID]), tonumber(rows[r][col.ParentFactionID])
        local share = tonumber(rows[r][col.ParentFactionMod_1])
        if id then n = n + 1; if parent and parent ~= 0 and share and share > 0 then sharing[id] = true end end
    end
    assert(n > 100 and sharing[72] and sharing[369] and not sharing[529] and not sharing[890],
        factionCsv .. " does not read as the Faction table: Stormwind and Gadgetzan pass a share, the Argent Dawn and the Silverwing Sentinels none")
end

local function run(path, env, ...)
    local chunk = assert(loadstring(readAll(path):gsub("^\239\187\191", ""), "=" .. path))
    setfenv(chunk, setmetatable(env, { __index = _G }))
    return chunk(...)
end

-- The peer's field keys, with its list operations: a key plus 1000 adds to a list, minus 1000 removes from one.
local Lib = { Enum = {}, Meta = {} }
local KEYS = {}
for _, e in ipairs({ { "quest", "Quest" }, { "npc", "Npc" }, { "object", "Object" }, { "item", "Item" } }) do
    local meta = run(peerDir .. "/src/meta/" .. e[1] .. "Meta.lua", {}, nil, Lib)
    local keys = {}
    for name, i in pairs(meta.keys) do
        keys[name], keys[name .. "_add"], keys[name .. "_remove"] = i, i + 1000, i - 1000
    end
    KEYS[e[1]] = keys
end

-- The enum files fill Lib.Enum and some read what others define, so they load until nothing more does.
do
    local files = { "constants", "expansions", "factions", "icons", "items", "npcs", "phases", "professions", "quests",
                    "waypoints", "zones" }
    local left = files
    while #left > 0 do
        local failed = {}
        for _, name in ipairs(left) do
            local ok, err = pcall(run, peerDir .. "/src/corrections/enum/" .. name .. ".lua", {}, nil, Lib)
            if not ok then failed[#failed + 1] = name; failed.err = err end
        end
        assert(#failed < #left, "enum files will not load: " .. table.concat(failed, " ") .. ": " .. tostring(failed.err))
        left = failed
    end
end
local E = Lib.Enum
-- Forever's set holds only what differs from Classic's
local FOREVER = E.byExpansion and E.byExpansion.Forever or {}
local CLASSIC = E.byExpansion and E.byExpansion.Classic or {}
local function enum(name)
    local t = FOREVER[name] or CLASSIC[name] or E[name]
    assert(type(t) == "table", "no enum " .. name)
    return setmetatable({}, { __index = function(_, k)
        local v = t[k]
        assert(v ~= nil, ("enum %s has no %s"):format(name, tostring(k)))
        return v
    end })
end

local modules = {}
local QuestieDB = setmetatable({ questKeys = KEYS.quest, npcKeys = KEYS.npc, objectKeys = KEYS.object, itemKeys = KEYS.item },
    { __index = function(t, k) local v = enum(k); rawset(t, k, v); return v end })
local IMPORTS = {
    QuestieDB = QuestieDB,
    ZoneDB = { zoneIDs = enum("zoneIDs"), private = {} },
    QuestieProfessions = setmetatable({}, { __index = function(t, k) local v = enum(k); rawset(t, k, v); return v end }),
    Phasing = { phases = enum("phases") },
    QuestieCorrections = setmetatable({}, { __index = function(t, k) local v = {}; rawset(t, k, v); return v end }),
    l10n = setmetatable({}, { __call = function(_, s) return s end }),
}
local Loader = {
    CreateModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end,
    ImportModule = function(_, name) return assert(IMPORTS[name], "no stand-in for module " .. name) end,
}

-- The peer's area to map table, to place its areas on ours through the map they draw on
local peerUi
do
    local zoneDB = { private = {} }
    run(peerDir .. "/support/Forever/Zones/areaIdToUiMapId.lua", { QuestieLoader = { ImportModule = function() return zoneDB end } })
    peerUi = assert(loadstring(zoneDB.private.areaIdToUiMapId))()
end

local function block(path, marker)
    local s = readAll(path)
    local a = assert(s:find("return {", assert(s:find(marker, 1, true)), true))
    return assert(loadstring(s:sub(a, assert(s:find("}]]", a, true)))))()
end
local ourUi = block(srcDir .. "/areaIdToUiMapId.lua", "areaIdToUiMapId = [[")
local uiArea = {}
for area, ui in pairs(ourUi) do
    if type(area) == "number" and area > 0 and (not uiArea[ui] or area < uiArea[ui]) then uiArea[ui] = area end
end
local NOT_A_ZONE = { [947] = true, [1414] = true, [1415] = true, [1945] = true }
local moved, dropped = 0, 0
-- By the map Forever draws the area on, which can differ from the dump's table: Mount Hyjal 616 is 2482 there, not retail's 198.
local function ourArea(zone)
    local ui = peerUi[zone]
    if not ui then
        if ourUi[zone] and not NOT_A_ZONE[ourUi[zone]] then return zone end
    elseif ui > 0 and not NOT_A_ZONE[ui] then
        if ourUi[zone] == ui then return zone end
        if uiArea[ui] then moved = moved + 1; return uiArea[ui] end
    end
    dropped = dropped + 1
end
local function places(byZone)
    if type(byZone) ~= "table" then return byZone end
    local out = {}
    for zone, pts in pairs(byZone) do
        local area = ourArea(zone)
        if area then
            out[area] = out[area] or {}
            for _, p in ipairs(pts) do out[area][#out[area] + 1] = p end
        end
    end
    return out
end

-- The Skyborne bits, 32 and 33, do not fit EQ's race slot, so either one stands for its whole faction.
local function fold(mask)
    if type(mask) ~= "number" then return mask end
    if mask < 4294967296 then return mask == 255 and 0 or mask end
    local hi, low = math.floor(mask / 4294967296), mask % 4294967296
    local function with(v, bits)
        for _, b in ipairs({ 1, 2, 4, 8, 16, 32, 64, 128 }) do
            if math.floor(bits / b) % 2 == 1 and math.floor(v / b) % 2 == 0 then v = v + b end
        end
        return v
    end
    if hi % 2 == 1 then low = with(low, 77) end
    if math.floor(hi / 2) % 2 == 1 then low = with(low, 178) end
    -- Every race gates nothing, as the converter has it since 2.7.0
    return low == 255 and 0 or low
end

-- The fields EQ reads, a name only where EQ has none, never the zone (the converter's dungeon flags)
local FIELDS = {
    quest = { name = "fill", startedBy = 2, finishedBy = 3, requiredLevel = 4, questLevel = 5, requiredRaces = 6, requiredClasses = 7,
              triggerEnd = 9, objectives = 10, preQuestGroup = 12, preQuestSingle = 13, exclusiveTo = 16,
              requiredSkill = 18, requiredMinRep = 19, requiredMaxRep = 20, nextQuestInChain = 22, specialFlags = 24, parentQuest = 25,
              reputationReward = 26 },
    npc = { name = "fill", spawns = 7, friendlyToFaction = 13 },
    object = { name = "fill", spawns = 4 },
    item = { name = "fill", npcDrops = 2, objectDrops = 3, vendors = 14 },
}
local byIndex = {}
for entity, fields in pairs(FIELDS) do
    byIndex[entity] = {}
    for name, want in pairs(fields) do
        local i = assert(KEYS[entity][name], entity .. " has no field " .. name)
        if want ~= "fill" then assert(i == want, ("%s.%s is field %d, not %d"):format(entity, name, i, want)) end
        byIndex[entity][i] = name
    end
end

-- Reputation comes from the Wowhead layer and the hand fixes, as the traces also log the share the game passes to related factions
local REWARD = { [26] = true }
local LAYERS = {
    { "generated/foreverBaseQuest.lua", "ForeverBaseQuest", "quest", only = REWARD },
    { "traces/foreverQuestTraces.lua", "ForeverQuestTraces", "quest", without = REWARD, oneFaction = true },
    { "traces/foreverQuestRelationTraces.lua", "ForeverQuestRelationTraces", "quest" },
    { "traces/foreverNpcTraces.lua", "ForeverNpcTraces", "npc" },
    { "traces/foreverObjectTraces.lua", "ForeverObjectTraces", "object" },
    { "traces/foreverItemTraces.lua", "ForeverItemTraces", "item" },
    { "foreverQuestFixes.lua", "ForeverQuestFixes", "quest" },
    { "foreverNPCFixes.lua", "ForeverNpcFixes", "npc" },
    { "foreverObjectFixes.lua", "ForeverObjectFixes", "object" },
    { "foreverItemFixes.lua", "ForeverItemFixes", "item" },
}
local ENTITY = { quest = "quests", npc = "npcs", object = "objects", item = "items" }
local out = { quests = {}, npcs = {}, objects = {}, items = {} }
local counts = {}
-- A fix the peer marks "-- unverified" on its own line is its guess, mostly a race limit lifted, so it is not taken.
local function unverified(path, entity)
    local skip, id = {}, nil
    for line in readAll(path):gmatch("[^\n]+") do
        local open = line:match("^%s*%[(%d+)%]%s*=%s*{")
        if open then id = tonumber(open) end
        local name = line:match("%[%a+Keys%.([%w_]+)%]")
        if id and name and line:find("%-%-%s*unverified") then
            skip[id] = skip[id] or {}
            skip[id][assert(KEYS[entity][name], "no field " .. name)] = true
        end
    end
    return skip
end

-- Fix lines a review found wrong: 99199's race and next step, copied from the Alliance quest beside it, and two rewards copied from traces, shares and all
local WRONG = { ["foreverQuestFixes.lua"] = { [99199] = { "requiredRaces", "nextQuestInChain" },
                                              [87288] = { "reputationReward" }, [93963] = { "reputationReward" } } }

local guesses, wrongs = 0, 0
local traceReward = {}
for _, layer in ipairs(LAYERS) do
    -- Icon hints the peer's objective rows carry, which EQ does not read
    local hints = setmetatable({}, { __index = function(_, k) return k end })
    local path = peerDir .. "/src/corrections/Forever/" .. layer[1]
    run(path, { QuestieLoader = Loader, Questie = hints })
    local m = assert(modules[layer[2]], "no module " .. layer[2])
    local patch = m:Load()
    local entity, n = layer[3], 0
    local skip = unverified(path, entity)
    local wrong = {}
    for id, names in pairs(WRONG[layer[1]] or {}) do
        wrong[id] = {}
        for _, name in ipairs(names) do wrong[id][assert(KEYS[entity][name], "no field " .. name)] = true end
    end
    for id, row in pairs(patch) do
        for key, value in pairs(row) do
            local op, field = "set", key
            if key >= 1000 then op, field = "add", key - 1000 elseif key <= 0 then op, field = "remove", key + 1000 end
            local name = byIndex[entity][field]
            if layer.oneFaction and field == 26 and op == "set" and type(value) == "table" and #value == 1 then traceReward[id] = value end
            local taken = not (layer.only and not layer.only[field] or layer.without and layer.without[field])
            if name and wrong[id] and wrong[id][key] then
                wrongs = wrongs + 1
            elseif name and skip[id] and skip[id][key] then
                guesses = guesses + 1
            elseif name and taken then
                if FIELDS[entity][name] == "fill" then op = "fill" end
                if field == 7 and entity == "npc" or field == 4 and entity == "object" then value = places(value) end
                if field == 9 and entity == "quest" and type(value) == "table" then value = { value[1], places(value[2]) } end
                if field == 6 and entity == "quest" then value = fold(value) end
                local list = out[ENTITY[entity]]
                list[id] = list[id] or {}
                list[id][#list[id] + 1] = { field, op, value }
                n = n + 1
            end
        end
    end
    counts[#counts + 1] = ("%s %d"):format(layer[2], n)
end

-- A quest the other layers give no reputation takes a trace naming one faction that passes no share, which can only be its own reward
local fromTraces = 0
for id, value in pairs(traceReward) do
    local list = out.quests[id] or {}
    local given = sharing[value[1][1]]
    for _, o in ipairs(list) do if o[1] == 26 then given = true end end
    if not given then
        list[#list + 1] = { 26, "set", value }
        out.quests[id] = list
        fromTraces = fromTraces + 1
    end
end

local parts = { "-- Generated by tools/build_peer_forever.lua: a peer quest database's WoW Forever traces and hand fixes, each\n",
    "-- { field, set | fill | add | remove, value } in the order applied, in Forever's map space.\nreturn {\n" }
for _, name in ipairs({ "quests", "npcs", "objects", "items" }) do
    parts[#parts + 1] = name .. " = {\n"
    for _, id in ipairs(sortedKeys(out[name])) do parts[#parts + 1] = ("[%d]=%s,\n"):format(id, ser(out[name][id])) end
    parts[#parts + 1] = "},\n"
end
parts[#parts + 1] = "}\n"
assert(wrongs == 4, "a fix line found wrong by review is gone or moved, so read WRONG again")
local path = srcDir .. "/peerForeverRows.lua"
local f = assert(io.open(path, "wb"), "cannot write " .. path)
f:write(table.concat(parts))
f:close()
assert(loadfile(path), path .. " does not load back")
io.stderr:write("-- peer Forever operations: " .. table.concat(counts, ", ") .. "\n")
io.stderr:write(("-- peer Forever fixes marked unverified, not taken: %d, found wrong by review, not taken: %d\n"):format(guesses, wrongs))
io.stderr:write(("-- peer Forever reputation from a trace naming one faction that passes no share, for a quest the other layers give none: %d\n"):format(fromTraces))
io.stderr:write(("-- peer Forever places: %d area(s) placed through their map, %d left out\n"):format(moved, dropped))
io.stderr:write("-- peer Forever rows written to " .. path .. "\n")
