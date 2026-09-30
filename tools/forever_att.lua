-- Reads the quests in AllTheThings' compiled WoW Forever database (its MIT licensed db/Camelot folder).

local function readAll(path)
    local f = assert(io.open(path, "rb"), "cannot open " .. path)
    local s = f:read("*a")
    f:close()
    return s
end

local function scriptFiles(dir)
    local files = {}
    for file in readAll(dir .. "/Database.xml"):gmatch('<Script%s+file="([^"]+)"') do
        if not file:find("LocalizationDB", 1, true) then files[#files + 1] = file end
    end
    assert(#files > 0, "no Script entries in " .. dir .. "/Database.xml")
    return files
end

-- Anything the data asks of ATT's runtime, such as a tooltip handler, answers this stand-in.
local inert
inert = setmetatable({}, { __index = function() return inert end, __call = function() return inert end })

local function numbers(v)
    if type(v) ~= "table" then return nil end
    local out = {}
    for i = 1, #v do
        if type(v[i]) == "number" then out[#out + 1] = v[i] end
    end
    return #out > 0 and out or nil
end

local function pair(v)
    if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then return { v[1], v[2] } end
end

local function pointsOf(t)
    local out = {}
    if type(t.coords) == "table" then
        local maps = {}
        for ui in pairs(t.coords) do if type(ui) == "number" then maps[#maps + 1] = ui end end
        table.sort(maps)
        for _, ui in ipairs(maps) do
            for _, p in ipairs(t.coords[ui]) do
                if type(p) == "table" and type(p[1]) == "number" and type(p[2]) == "number" then
                    out[#out + 1] = { ui, p[1], p[2] }
                end
            end
        end
    end
    if type(t.coord) == "table" and type(t.coord[3]) == "number" then
        out[#out + 1] = { t.coord[3], t.coord[1], t.coord[2] }
    end
    return out
end

local function normalize(id, t, ctx)
    local q = { id = id, map = ctx.map, inst = ctx.inst, givers = {}, objects = {} }
    local givers = numbers(t.qgs) or (type(t.qg) == "number" and { t.qg }) or {}
    for _, g in ipairs(givers) do q.givers[#q.givers + 1] = g end
    for _, p in ipairs(type(t.providers) == "table" and t.providers or {}) do
        if type(p) == "table" and p[1] == "n" and type(p[2]) == "number" then q.givers[#q.givers + 1] = p[2] end
        if type(p) == "table" and p[1] == "o" and type(p[2]) == "number" then q.objects[#q.objects + 1] = p[2] end
    end
    q.points = pointsOf(t)
    q.reqLevel = type(t.lvl) == "table" and t.lvl[1] or t.lvl
    if type(q.reqLevel) ~= "number" then q.reqLevel = nil end
    q.faction = (t.r == 1 or t.r == 2) and t.r or nil
    q.races = numbers(t.races)
    q.classes = numbers(t.c)
    q.pre = numbers(t.sourceQuests)
    q.preCount = type(t.sqreq) == "number" and t.sqreq or nil
    q.excl = numbers(t.altQuests)
    q.skill = type(t.requireSkill) == "number" and t.requireSkill or nil
    q.minRep = pair(t.minReputation)
    q.maxRep = pair(t.maxReputation)
    q.repeatable = t.repeatable and true or nil
    q.breadcrumb = t.isBreadcrumb and true or nil
    q.variants = (t.aqd or t.hqd) and true or nil
    q.unobtainable = type(ctx.u) == "number" and ctx.u or nil
    q.addedIn = type(ctx.awp) == "number" and ctx.awp or nil
    q.removedIn = type(ctx.rwp) == "number" and ctx.rwp or nil
    return q
end

return function(dir)
    local handlers = {}
    local att = setmetatable({}, { __index = function(self, k)
        if type(k) == "string" and k:match("^Create") then
            local ctor = function(id, t)
                if type(id) == "table" and t == nil then id, t = nil, id end
                return { kind = k, id = id, t = type(t) == "table" and t or {} }
            end
            rawset(self, k, ctor)
            return ctor
        end
        return inert
    end })
    att.AddEventHandler = function(_, fn) handlers[#handlers + 1] = fn end
    -- ATT keeps a quest's Alliance and Horde halves apart until it knows the player, so the caller sees both.
    att.ResolveQuestData = function(t) return t end
    att.L = inert

    local files = scriptFiles(dir)
    for _, file in ipairs(files) do
        local src = readAll(dir .. "/" .. file):gsub("^\239\187\191", "")
        local chunk = assert(loadstring(src, "=" .. file))
        setfenv(chunk, {})
        chunk("AllTheThings", att)
    end
    local categories = {}
    for _, fn in ipairs(handlers) do
        setfenv(fn, {})
        fn(categories)
    end

    local quests, duplicates = {}, 0
    local function walk(node, ctx)
        if type(node) ~= "table" or node == inert then return end
        local kind = rawget(node, "kind")
        if not kind then
            for _, child in ipairs(node) do walk(child, ctx) end
            return
        end
        local t = node.t
        -- ATT sets these three on a group for every quest below it.
        ctx = { map = ctx.map, inst = ctx.inst, u = t.u or ctx.u, awp = t.awp or ctx.awp, rwp = t.rwp or ctx.rwp }
        if kind == "CreateMap" then ctx.map = node.id
        elseif kind == "CreateInstance" then ctx.inst = node.id end
        if kind == "CreateQuest" and type(node.id) == "number" then
            if quests[node.id] then duplicates = duplicates + 1
            else quests[node.id] = normalize(node.id, t, ctx) end
        end
        if type(t.g) == "table" then for _, child in ipairs(t.g) do walk(child, ctx) end end
        for _, child in ipairs(t) do walk(child, ctx) end
    end
    local names = {}
    for name in pairs(categories) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do walk(categories[name], {}) end

    return { quests = quests, files = #files, duplicates = duplicates }
end
