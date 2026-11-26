-- Writes dungeonBosses.lua into a source folder for build_questcoords.lua: the dungeon, raid and world bosses.
--
--   lua5.1 tools/build_bosses.lua <AllTheThings db folder> <source folder> <DungeonEncounter.csv> [<DungeonEncounter.csv> ...]
--
-- The client's own DungeonEncounter table names each fight, matched by name to the creature dump in the source folder,
-- AllTheThings (MIT) adds the creatures of its encounters, NAMED below adds the creatures a fight's name does not carry,
-- and ALSO the bosses no table names. A heroic copy ("Nazan (1)") matches its boss's name. Only creatures the dump ranks
-- elite, rare elite or boss are kept. TBC takes Era's table too, which names more of the old dungeons' bosses than its own.

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "tools/"

-- The creatures in a fight the client names after a group, by a name the dump spells otherwise, or after only one of them.
local NAMED = {
    ["High Inquisitor Whitemane"] = { "Scarlet Commander Mograine" },
    ["Sneed"] = { "Sneed's Shredder" },
    ["Atal'ai Defenders"] = { "Gasher", "Loro", "Hukku", "Zolo", "Mijan", "Zul'Lor" },
    ["Ring of Law"] = { "Gorosh the Dervish", "Grizzle", "Eviscerator", "Ok'thor the Breaker", "Anub'shiah", "Hedrum the Creeper" },
    ["The Seven"] = { "Anger'rel", "Seeth'rel", "Dope'rel", "Gloom'rel", "Vile'rel", "Hate'rel", "Doom'rel" },
    ["The Vault"] = { "Watchman Doomgrip" },
    ["The Lost Dwarves"] = { "Baelog", "Eric \"The Swift\"", "Olaf" },
    ["Silithid Royalty"] = { "Princess Yauj", "Vem", "Lord Kri" },
    ["Twin Emperors"] = { "Emperor Vek'lor", "Emperor Vek'nilash" },
    ["Edge of Madness"] = { "Gri'lek", "Hazza'rah", "Renataki", "Wushoolay" },
    ["The Four Horsemen"] = { "Highlord Mograine", "Thane Korth'azz", "Lady Blaumeux", "Sir Zeliek" },
    ["Geilhast"] = { "Gelihast" },
    ["Kirtonos"] = { "Kirtonos the Herald" },
    ["Ras Frostwhisperer"] = { "Ras Frostwhisper" },
    ["Willey Hopebreaker"] = { "Cannon Master Willey" },
    ["Commander Malor"] = { "Malor the Zealous" },
    ["Instructor Galford"] = { "Archivist Galford" },
    ["Lord Aurius Rivendare"] = { "Baron Rivendare" },
    ["Ghaz'rilla"] = { "Gahz'rilla" },
    ["Reliquary of Souls"] = { "Essence of Suffering", "Essence of Desire", "Essence of Anger" },
    ["Opera Hall"] = { "Dorothee", "Roar", "Strawman", "Tinhead", "The Crone", "The Big Bad Wolf", "Romulo", "Julianne" },
    ["Chess Event"] = { "Echo of Medivh" },
    ["Eredar Twins"] = { "Lady Sacrolash", "Grand Warlock Alythess" },
    ["Vazruden the Herald"] = { "Nazan", "Vazruden" },
    ["Warchief Rend Blackhand"] = { "Gyth" },
}

-- Bosses and named elites Era's quests need that no encounter table or AllTheThings encounter names, such as the summoned Dungeon Set 2 bosses
local ALSO = { "Goraluk Anvilcrack", "Sergeant Bly", "Fras Siabi", "Death Knight Darkreaver", "Solakar Flamewreath",
               "Isalien", "Jarien", "Sothos", "Mor Grayhoof", "Theldren", "Overmaster Pyron" }

-- The dump's rank field: 1 elite, 2 rare elite, 3 boss. 0 is an ordinary creature sharing a boss's name, such as an illusion.
local NPC_NAME, NPC_RANK = 1, 6
local KEPT_RANKS = { [1] = true, [2] = true, [3] = true }
local CLIENT, ATT, LISTED = 1, 2, 3

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function loadNpcs(dir)
    local found
    for _, prefix in ipairs({ "classic", "tbc" }) do
        local f = io.open(dir .. "/" .. prefix .. "NpcDB.lua", "rb")
        if f then
            f:close()
            assert(not found, "more than one flavor's files in " .. dir)
            found = prefix
        end
    end
    assert(found, "no classicNpcDB.lua or tbcNpcDB.lua in " .. dir)
    local src = readAll(dir .. "/" .. found .. "NpcDB.lua")
    local at = assert(src:find("npcData = [[", 1, true), "npcData not found")
    local s = src:find("return {", at, true)
    local e = src:find("}]]", s, true)
    return assert(loadstring(src:sub(s, e)))()
end

local function norm(name)
    return (name:lower():gsub("[^%w]", ""))
end

local function csvRows(path)
    local rows, header = {}, nil
    for line in readAll(path):gsub("\r", ""):gmatch("[^\n]+") do
        local fields, i = {}, 1
        while i <= #line + 1 do
            if line:sub(i, i) == '"' then
                local value, j = {}, i + 1
                while true do
                    local q = assert(line:find('"', j, true), "unclosed quote in " .. path .. ": " .. line)
                    value[#value + 1] = line:sub(j, q - 1)
                    if line:sub(q + 1, q + 1) == '"' then
                        value[#value + 1] = '"'
                        j = q + 2
                    else
                        i = q + 2
                        break
                    end
                end
                fields[#fields + 1] = table.concat(value)
            else
                local c = line:find(",", i, true) or #line + 1
                fields[#fields + 1] = line:sub(i, c - 1)
                i = c + 1
            end
        end
        if not header then
            header = fields
            assert(header[1] == "Name_lang" and header[2] == "ID", "not a DungeonEncounter table: " .. path)
        else
            rows[#rows + 1] = { name = fields[1], id = tonumber(fields[2]) }
        end
    end
    assert(#rows > 0, "no rows in " .. path)
    return rows
end

local function labelFor(attDir)
    local folder = attDir:gsub("[/\\]+$", ""):match("([^/\\]+)$") or attDir
    local toc = io.open(attDir .. "/../../AllTheThings.toc", "rb")
    local version = toc and toc:read("*a"):match("## Version:%s*([^\r\n]+)")
    if toc then toc:close() end
    return version and ("%s, db/%s"):format(version, folder) or ("db/" .. folder)
end

local attDir, outDir = ...
local csvPaths = { select(3, ...) }
assert(#csvPaths > 0, "usage: lua5.1 tools/build_bosses.lua <AllTheThings db folder> <source folder> <DungeonEncounter.csv> [...]")

local npcs = loadNpcs(outDir)
local byName = {}
for id, row in pairs(npcs) do
    local key = type(row[NPC_NAME]) == "string" and norm((row[NPC_NAME]:gsub("%s*%(%d+%)$", "")))
    if key then
        byName[key] = byName[key] or {}
        table.insert(byName[key], id)
    end
end

local bosses, counts, missing, unused = {}, { 0, 0, 0 }, {}, {}
local function add(id, from)
    local row = npcs[id]
    if bosses[id] or not row or not KEPT_RANKS[row[NPC_RANK]] then return end
    bosses[id] = from
    counts[from] = counts[from] + 1
end

local named, labels = {}, {}
for _, csvPath in ipairs(csvPaths) do
    labels[#labels + 1] = csvPath:gsub("\\", "/"):match("([^/]+/[^/]+)$") or csvPath
    for _, enc in ipairs(csvRows(csvPath)) do
        local ids = byName[norm(enc.name)]
        if ids then
            for _, id in ipairs(ids) do add(id, CLIENT) end
        elseif not NAMED[enc.name] then
            missing[enc.name] = true
        end
        if NAMED[enc.name] then named[enc.name] = true end
    end
end
for _, e in ipairs(dofile(here .. "forever_att.lua")(attDir).encounters) do
    for _, id in ipairs(e.npcs) do add(id, ATT) end
end
for encName, names in pairs(NAMED) do
    if named[encName] then
        for _, name in ipairs(names) do
            local ids = assert(byName[norm(name)], ("%s: no creature named %s in %s"):format(encName, name, outDir))
            for _, id in ipairs(ids) do add(id, LISTED) end
        end
    else
        unused[#unused + 1] = encName
    end
end
for _, name in ipairs(ALSO) do
    local ids = assert(byName[norm(name)], ("no creature named %s in %s"):format(name, outDir))
    for _, id in ipairs(ids) do add(id, LISTED) end
end

local ids = {}
for id in pairs(bosses) do ids[#ids + 1] = id end
table.sort(ids)
local parts = { ("-- Generated by tools/build_bosses.lua from the clients' %s and AllTheThings (MIT), %s.\n")
    :format(table.concat(labels, ", "), labelFor(attDir)),
    "-- [creature id] = where it came from: 1 the client's encounter name, 2 AllTheThings, 3 a name listed in the tool\nreturn {\n" }
for _, id in ipairs(ids) do parts[#parts + 1] = ("[%d]=%d,\n"):format(id, bosses[id]) end
parts[#parts + 1] = "}\n"
local path = outDir .. "/dungeonBosses.lua"
local f = assert(io.open(path, "wb"), "cannot write " .. path)
f:write(table.concat(parts))
f:close()

local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end
table.sort(unused)
io.stderr:write(("-- bosses: %d creature(s), %d from the client's encounter names, %d more from AllTheThings, %d more from the names listed in the tool, written to %s\n")
    :format(#ids, counts[CLIENT], counts[ATT], counts[LISTED], path))
io.stderr:write(("-- bosses: %d client encounter name(s) with no creature in the dump: %s\n")
    :format(#sortedKeys(missing), table.concat(sortedKeys(missing), "; ")))
io.stderr:write(("-- bosses: names listed in the tool that this client's table does not use: %s\n")
    :format(#unused > 0 and table.concat(unused, "; ") or "none"))
