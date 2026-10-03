local _, ns = ...

-- Classic quests belong to no client quest line, so the chains are built from the shipped prerequisite tables
local CS = ns:RegisterSubsystem("ChainGuideClassicSource", {})

local CHAIN_ID_OFFSET = 8000000
local SWEEPS          = 4
local MAX_MAP_DEPTH   = 8
local FAN_COLUMNS     = 3

local EMPTY = {}

CS.chainOf = {}
CS.stats   = {}

local function avail()
    return ns:GetSubsystem("AvailableQuests")
end

local function data()
    local A = avail()
    return A and A.Data and A:Data()
end

local function database()
    return ns:GetSubsystem("ChainGuideDatabase")
end

function CS:Title(questID)
    local A = avail()
    return A and A:Title(questID) or ("Quest #" .. tostring(questID))
end

-- Read on every access, so a title the client caches later replaces the English one
local NAMED = {
    __index = function(chain, key)
        if key == "name" then return CS:Title(rawget(chain, "rootID")) end
    end,
}

local function link(kids, pars, a, b)
    if not (a and b) or a == b then return end
    local k = kids[a]
    if not k then k = {}; kids[a] = k end
    local p = pars[b]
    if not p then p = {}; pars[b] = p end
    k[b] = true
    p[a] = true
end

local function edges(D)
    local kids, pars = {}, {}
    for q, list in pairs(D.pre) do
        for i = 1, #list do link(kids, pars, list[i], q) end
    end
    for q, list in pairs(D.preAll) do
        for i = 1, #list do link(kids, pars, list[i], q) end
    end
    for q, nextID in pairs(D.chain) do link(kids, pars, q, nextID) end
    for q, parentID in pairs(D.parent) do link(kids, pars, parentID, q) end
    return kids, pars
end

-- Nil from CanEverTake means the character could not be read, and a chain shown in error beats one hidden
local function keptQuests(D, A, kids, pars)
    local keep = {}
    local function consider(q)
        if keep[q] == nil and D.gates[q] then keep[q] = A:CanEverTake(q) ~= false end
    end
    for q in pairs(kids) do consider(q) end
    for q in pairs(pars) do consider(q) end

    local function touchesKept(set)
        for o in pairs(set) do
            if keep[o] then return true end
        end
        return false
    end
    -- An id the data lacks stays only between two kept quests, so a gap in the data cannot split a chain
    local bridges = {}
    for q, k in pairs(kids) do
        if not D.gates[q] and pars[q] and touchesKept(k) and touchesKept(pars[q]) then
            bridges[#bridges + 1] = q
        end
    end
    for i = 1, #bridges do keep[bridges[i]] = true end
    return keep
end

local function components(keep, kids, pars)
    local nodes = {}
    for q, kept in pairs(keep) do
        if kept then nodes[#nodes + 1] = q end
    end
    table.sort(nodes)

    local seen, out = {}, {}
    for i = 1, #nodes do
        local start = nodes[i]
        if not seen[start] then
            seen[start] = true
            local c, j = { start }, 1
            while j <= #c do
                local x = c[j]
                for y in pairs(kids[x] or EMPTY) do
                    if keep[y] and not seen[y] then seen[y] = true; c[#c + 1] = y end
                end
                for y in pairs(pars[x] or EMPTY) do
                    if keep[y] and not seen[y] then seen[y] = true; c[#c + 1] = y end
                end
                j = j + 1
            end
            if #c >= 2 then
                table.sort(c)
                out[#out + 1] = c
            end
        end
    end
    return out
end

local function onlyParent(q, inC, pars)
    local only
    for p in pairs(pars[q] or EMPTY) do
        if inC[p] then
            if only then return nil end
            only = p
        end
    end
    return only
end

local function hasKid(q, inC, kids)
    for k in pairs(kids[q] or EMPTY) do
        if inC[k] then return true end
    end
    return false
end

-- A quest's follow-ups that lead nowhere else and need nothing else, when there are at least `least` of them
local function fansIn(c, inC, kids, pars, least, rankOf)
    local out
    for i = 1, #c do
        local hub = c[i]
        local L
        for k in pairs(kids[hub] or EMPTY) do
            if inC[k] and onlyParent(k, inC, pars) == hub and not hasKid(k, inC, kids) then
                L = L or {}
                L[#L + 1] = k
            end
        end
        if L and #L >= least then
            table.sort(L, rankOf)
            out = out or {}
            out[#out + 1] = { hub = hub, members = L }
        end
    end
    return out
end

-- Rows by longest path from a root, branches ordered by their neighbors, a fan wider than FAN_COLUMNS wrapped under its quest
local function layout(all, kids, pars, rankOf)
    local inC = {}
    for i = 1, #all do inC[all[i]] = true end

    local fanOf = {}
    local fans = fansIn(all, inC, kids, pars, FAN_COLUMNS + 1, rankOf) or EMPTY
    for f = 1, #fans do
        local L = fans[f].members
        fans[f].cols = math.ceil(#L / math.ceil(#L / FAN_COLUMNS))
        for j = 1, #L do fanOf[L[j]] = f end
        for j = fans[f].cols + 1, #L do inC[L[j]] = nil end
    end
    local c = {}
    for i = 1, #all do
        if inC[all[i]] then c[#c + 1] = all[i] end
    end

    local depth, visiting = {}, {}
    local function depthOf(q)
        local v = depth[q]
        if v then return v end
        if visiting[q] then return 0 end
        visiting[q] = true
        local m = 0
        for p in pairs(pars[q] or EMPTY) do
            if inC[p] then
                local d = depthOf(p) + 1
                if d > m then m = d end
            end
        end
        visiting[q] = nil
        depth[q] = m
        return m
    end
    for i = 1, #c do depthOf(c[i]) end

    local roots = {}
    for i = 1, #c do
        local q = c[i]
        local hasParent = false
        for p in pairs(pars[q] or EMPTY) do
            if inC[p] then hasParent = true; break end
        end
        if not hasParent then
            roots[#roots + 1] = q
            -- A root joining part way down sits just above its first step, not at the top of the chain
            local lowest
            for k in pairs(kids[q] or EMPTY) do
                if inC[k] and (not lowest or depth[k] < lowest) then lowest = depth[k] end
            end
            if lowest and lowest - 1 > depth[q] then depth[q] = lowest - 1 end
        end
    end
    -- Quests that require each other leave no root, so every member stands for one when naming the chain
    if #roots == 0 then
        for i = 1, #c do roots[i] = c[i] end
    end

    local layers, maxDepth = {}, 0
    for i = 1, #c do
        local q = c[i]
        local d = depth[q]
        local layer = layers[d]
        if not layer then layer = {}; layers[d] = layer end
        layer[#layer + 1] = q
        if d > maxDepth then maxDepth = d end
    end
    for d = 0, maxDepth do layers[d] = layers[d] or {} end

    local pos = {}
    local function place(layer)
        local w = #layer
        for i = 1, w do pos[layer[i]] = i - (w + 1) / 2 end
    end
    for d = 0, maxDepth do place(layers[d]) end

    local bary = {}
    local function byBary(a, b)
        if bary[a] ~= bary[b] then return bary[a] < bary[b] end
        return a < b
    end
    local function reorder(layer, neighbors)
        for i = 1, #layer do
            local q = layer[i]
            local sum, n = 0, 0
            for o in pairs(neighbors[q] or EMPTY) do
                if inC[o] then sum = sum + pos[o]; n = n + 1 end
            end
            bary[q] = (n > 0) and (sum / n) or pos[q]
        end
        table.sort(layer, byBary)
        place(layer)
    end
    for _ = 1, SWEEPS do
        for d = 1, maxDepth do reorder(layers[d], pars) end
        for d = maxDepth - 1, 0, -1 do reorder(layers[d], kids) end
    end

    -- A fan's first row stays together, in its own order, where its first member landed
    if #fans > 0 then
        for d = 0, maxDepth do
            local layer, out, taken = layers[d], {}, {}
            for i = 1, #layer do
                local q = layer[i]
                local f = fanOf[q]
                if not f then
                    out[#out + 1] = q
                elseif not taken[f] then
                    taken[f] = true
                    local L = fans[f].members
                    for j = 1, fans[f].cols do out[#out + 1] = L[j] end
                end
            end
            layers[d] = out
            place(out)
        end
    end

    -- Each quest as near the average of its neighbors as one column apart allows, rows kept in their sorted order
    local x = {}
    for i = 1, #c do x[c[i]] = pos[c[i]] end
    local function settle(layer, neighbors)
        local prev, drift = nil, 0
        for i = 1, #layer do
            local q = layer[i]
            local sum, n = 0, 0
            for o in pairs(neighbors[q] or EMPTY) do
                if inC[o] then sum = sum + x[o]; n = n + 1 end
            end
            local want = (n > 0) and (sum / n) or x[q]
            local at = want
            if prev and at < prev + 1 then at = prev + 1 end
            x[q], prev = at, at
            drift = drift + (want - at)
        end
        -- Spacing only ever pushes right, so the row moves back by its average drift to stay over its neighbors
        local shift = (#layer > 0) and (drift / #layer) or 0
        for i = 1, #layer do x[layer[i]] = x[layer[i]] + shift end
    end
    for d = 1, maxDepth do settle(layers[d], pars) end
    for d = maxDepth - 1, 0, -1 do settle(layers[d], kids) end
    for d = 1, maxDepth do settle(layers[d], pars) end

    local extra = {}
    for f = 1, #fans do
        local L = fans[f].members
        local d = depth[L[1]]
        local more = math.ceil(#L / fans[f].cols) - 1
        if more > (extra[d] or 0) then extra[d] = more end
    end
    local below, acc = {}, 0
    for d = 0, maxDepth do below[d] = acc; acc = acc + (extra[d] or 0) end
    local y = {}
    for i = 1, #c do y[c[i]] = depth[c[i]] + below[depth[c[i]]] end
    for f = 1, #fans do
        local L = fans[f].members
        local top = y[L[1]]
        local n = fans[f].cols
        local cols = {}
        for j = 1, n do cols[j] = x[L[j]] end
        for j = 1, #L do
            x[L[j]] = cols[(j - 1) % n + 1]
            y[L[j]] = top + math.floor((j - 1) / n)
        end
    end

    local minX
    for i = 1, #all do
        if not minX or x[all[i]] < minX then minX = x[all[i]] end
    end
    local order = {}
    for i = 1, #all do order[i] = all[i] end
    table.sort(order, function(a, b)
        if y[a] ~= y[b] then return y[a] < y[b] end
        if x[a] ~= x[b] then return x[a] < x[b] end
        return a < b
    end)
    local index, perRow, width = {}, {}, 0
    for i = 1, #order do
        index[order[i]] = i
        local n = (perRow[y[order[i]]] or 0) + 1
        perRow[y[order[i]]] = n
        if n > width then width = n end
    end

    local items = {}
    for i = 1, #order do
        local q = order[i]
        local conn
        for p in pairs(pars[q] or EMPTY) do
            local pi = index[p]
            if pi then
                conn = conn or {}
                conn[#conn + 1] = pi
            end
        end
        if conn then table.sort(conn) end
        items[i] = {
            type        = "quest",
            id          = q,
            x           = math.floor((x[q] - minX) * 1000 + 0.5) / 1000,
            y           = y[q],
            connections = conn,
            fan         = fanOf[q] and index[fans[fanOf[q]].hub] or nil,
        }
    end
    return items, roots, width
end

-- The six capitals, since a class quest offered in every one would otherwise go to the other faction's trainer
local CAPITAL_FACTION = {
    [1453] = "Alliance", [1455] = "Alliance", [1457] = "Alliance",
    [1454] = "Horde", [1456] = "Horde", [1458] = "Horde",
}

local function foreign(mapID)
    local f = CAPITAL_FACTION[mapID]
    local mine = f and UnitFactionGroup and UnitFactionGroup("player")
    return mine ~= nil and f ~= mine
end

-- Whether a map with n points beats the best so far, the other faction's capital last and the lowest id on a tie
local function beats(mapID, n, best, bestN)
    if not best then return true end
    local f, bf = foreign(mapID), foreign(best)
    if f ~= bf then return bf end
    return n > bestN or (n == bestN and mapID < best)
end

-- The best of a quest's start maps as beats ranks them, so the answer never depends on pairs order
local function busiestMap(byMap)
    if not byMap then return nil end
    local best, bestN
    for mapID, list in pairs(byMap) do
        local n = #list
        if beats(mapID, n, best, bestN) then best, bestN = mapID, n end
    end
    return best
end

local function levelKey(A, q)
    local lvl = A:QuestLevel(q)
    return lvl or math.huge
end

-- A chain can open with one quest per capital, so a first quest in the other faction's capital gives way to the next one outside it
local function homeMap(D, roots, items)
    local away
    for i = 1, #roots do
        local m = busiestMap(D.start[roots[i]])
        if m and not foreign(m) then return m end
        away = away or m
    end
    if away then return away end
    for i = 1, #items do
        local m = busiestMap(D.start[items[i].id])
        if m then return m end
    end
    local turnIn = ns.CLASSIC_QUEST_TURNIN
    for i = 1, #items do
        local m = turnIn and busiestMap(turnIn[items[i].id])
        if m then return m end
    end
    return nil
end

local function zoneName(mapID)
    local QBD = ns:GetSubsystem("QuestBrowserData")
    local name = QBD and QBD.ZoneName and QBD:ZoneName(mapID)
    if name then return name end
    if C_Map and C_Map.GetMapInfo then
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        if ok and type(info) == "table" and type(info.name) == "string" and info.name ~= "" then
            return info.name
        end
    end
    return "Map " .. tostring(mapID)
end

function CS:Reset()
    local Database = database()
    if Database then
        for id, chain in pairs(Database.chains) do
            if chain._generated then Database.chains[id] = nil end
        end
        for id, cat in pairs(Database.categories) do
            if cat._generated then Database.categories[id] = nil end
        end
    end
    wipe(self.chainOf)
    self.stats = {}
    self._built = false
end

function CS:Ensure()
    if self._built then return end
    local D, A, Database = data(), avail(), database()
    if not (D and A and Database) then return end
    self._built = true

    local started = debugprofilestop and debugprofilestop()
    local kids, pars = edges(D)
    local keep = keptQuests(D, A, kids, pars)
    local comps = components(keep, kids, pars)

    local function rank(a, b)
        local la, lb = levelKey(A, a), levelKey(A, b)
        if la ~= lb then return la < lb end
        return a < b
    end

    local catRange = {}
    local nChains, nQuests, unplaced, widest = 0, 0, 0, 0
    for i = 1, #comps do
        local items, roots, width = layout(comps[i], kids, pars, rank)
        table.sort(roots, rank)
        local mapID = homeMap(D, roots, items)
        if mapID then
            local lo, hi
            for k = 1, #items do
                local lvl = A:QuestLevel(items[k].id)
                if lvl then
                    if not lo or lvl < lo then lo = lvl end
                    if not hi or lvl > hi then hi = lvl end
                end
            end
            local root = roots[1]
            local chainID = CHAIN_ID_OFFSET + root
            local chain = setmetatable({
                category        = mapID,
                rootID          = root,
                items           = items,
                range           = lo and { lo, hi } or nil,
                _generated      = true,
                _normalized     = true,
                _overlayApplied = true,
            }, NAMED)
            Database:RegisterChain(chainID, chain)
            for k = 1, #items do self.chainOf[items[k].id] = chainID end

            local r = catRange[mapID]
            if not r then r = {}; catRange[mapID] = r end
            if lo and (not r[1] or lo < r[1]) then r[1] = lo end
            if hi and (not r[2] or hi > r[2]) then r[2] = hi end

            nChains = nChains + 1
            nQuests = nQuests + #items
            if width > widest then widest = width end
        else
            unplaced = unplaced + 1
        end
    end

    local nCats = 0
    for mapID, r in pairs(catRange) do
        Database:RegisterCategory(mapID, {
            name       = zoneName(mapID),
            mapIDs     = { mapID },
            order      = r[1] or math.huge,
            levelRange = r[1] and { r[1], r[2] } or nil,
            _generated = true,
        })
        nCats = nCats + 1
    end

    self.stats = {
        chains     = nChains,
        quests     = nQuests,
        categories = nCats,
        unplaced   = unplaced,
        widest     = widest,
        ms         = started and (debugprofilestop() - started) or nil,
    }
end

function CS:ChainForQuest(questID)
    self:Ensure()
    return questID and self.chainOf[questID]
end

local _here = {}
local function playerMaps()
    wipe(_here)
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local depth = 0
    while m and m > 0 and depth < MAX_MAP_DEPTH do
        _here[m] = depth + 1
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
        m = info and info.parentMapID
        depth = depth + 1
    end
    return _here
end

function CS:CategoryForPlayer()
    self:Ensure()
    local Database = database()
    if not Database then return nil end
    local here = playerMaps()
    local best, bestDepth
    for mapID, depth in pairs(here) do
        local cat = Database.categories[mapID]
        if cat and cat._generated and (not bestDepth or depth < bestDepth) then best, bestDepth = mapID, depth end
    end
    return best
end

-- The map you stand on, else the busiest as busiestMap ranks it, and its first point, which the generator lists densest first
local _count = {}
local function pickPoint(points, n)
    if not n or n == 0 then return nil end
    local here = playerMaps()
    local closest, closestDepth
    wipe(_count)
    for i = 1, n do
        local p = points[i]
        local d = here[p.mapID]
        if d and (not closestDepth or d < closestDepth) then closest, closestDepth = p, d end
        _count[p.mapID] = (_count[p.mapID] or 0) + 1
    end
    if closest then return closest end
    local best, bestN
    for mapID, c in pairs(_count) do
        if beats(mapID, c, best, bestN) then best, bestN = mapID, c end
    end
    for i = 1, n do
        if points[i].mapID == best then return points[i] end
    end
    return nil
end

local _starts = {}
function CS:StartPoint(questID)
    local A = avail()
    if not (A and questID) then return nil end
    return pickPoint(_starts, A:StartsFor(questID, _starts))
end

-- The same widened packing as the start table, srcID*1e9 + kind*1e8 + coordinates
local _finishes = {}
function CS:FinishPoint(questID)
    local byMap = questID and ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID]
    if not byMap then return nil end
    local n = 0
    for mapID, list in pairs(byMap) do
        for i = 1, #list do
            local v = list[i]
            local rest = v % 1e8
            local kind, src = math.floor(v / 1e8) % 10, math.floor(v / 1e9)
            n = n + 1
            local p = _finishes[n]
            if not p then p = {}; _finishes[n] = p end
            p.mapID, p.x, p.y, p.kind = mapID, math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, kind
            p.name = ns.Compat and ns.Compat.SourceName and ns.Compat.SourceName(kind, src) or nil
        end
    end
    return pickPoint(_finishes, n)
end

-- Explain's refusal keys, compared as the Quest Browser compares them
local REASON_LATER_STEP = "later step done"
local REASON_BRANCH     = "took another branch"

local function ownStatus(questID)
    local A = avail()
    if not (A and questID) then return "pending" end
    if A:IsCompleted(questID) then return "complete" end
    local inLog, failed = A:InLog(questID)
    if inLog and not failed then
        local Cache = ns:GetSubsystem("Cache")
        local q = Cache and Cache.Get and Cache:Get(questID)
        if q and ns.QuestIsDone and ns.QuestIsDone(q) then return "turnin" end
        return "active"
    end
    local ok, why = A:Explain(questID, true)
    if ok then return "available" end
    local gone = (why == REASON_LATER_STEP or why == REASON_BRANCH) and why or A:RuledOut(questID)
    if gone == REASON_LATER_STEP then return "passed", gone end
    if gone == REASON_BRANCH then return "branch", gone end
    return "pending", why
end

local function isClosed(s) return s == "passed" or s == "branch" end

local _status, _why, _visiting = {}, {}, {}

-- One read of the quest log per question, as a quest can be asked about once for itself and again as a prerequisite
local function statusOf(questID)
    if not questID then return "pending" end
    local s = _status[questID]
    if s then return s, _why[questID] end
    local why
    s, why = ownStatus(questID)
    local D = data()
    if s == "pending" and D and not _visiting[questID] then
        _visiting[questID] = true
        local blocked = false
        local pre = D.pre[questID]
        if pre then
            blocked = #pre > 0
            for i = 1, #pre do
                if not isClosed((statusOf(pre[i]))) then blocked = false; break end
            end
        else
            local preAll = D.preAll[questID]
            for i = 1, preAll and #preAll or 0 do
                if isClosed((statusOf(preAll[i]))) then blocked = true; break end
            end
        end
        local parent = D.parent[questID]
        if parent and isClosed((statusOf(parent))) then blocked = true end
        _visiting[questID] = nil
        -- Only the quests a closed one would have led to are closed by it, never one with another way in
        if blocked then s, why = "branch", REASON_BRANCH end
    end
    _status[questID], _why[questID] = s, why
    return s, why
end

local function fresh()
    wipe(_status)
    wipe(_why)
    wipe(_visiting)
end

function CS:Status(questID)
    fresh()
    return statusOf(questID)
end

function CS:IsClosed(questID)
    fresh()
    return isClosed((statusOf(questID)))
end

-- A quest the game will no longer offer leaves the count, or a chain with a branch could never reach its total
function CS:Progress(chain)
    local items = chain and chain.items
    if not items then return 0, 0, 0 end
    fresh()
    local done, active, total = 0, 0, 0
    for i = 1, #items do
        local s = statusOf(items[i].id)
        if s == "complete" then
            done, total = done + 1, total + 1
        elseif s == "active" or s == "turnin" then
            active, total = active + 1, total + 1
        elseif not isClosed(s) then
            total = total + 1
        end
    end
    return done, active, total
end

-- What you are on first, then what you can pick up now, then what is still ahead, each the shallowest, and the other faction's capital last
function CS:NextStep(chain)
    local items = chain and chain.items
    if not items then return nil end
    fresh()
    local D = data()
    local best, bestRank
    for i = 1, #items do
        local it = items[i]
        local s = statusOf(it.id)
        if s == "active" or s == "turnin" then return it end
        local rank = (s == "available" and 1) or (s == "pending" and 2) or nil
        if rank then
            if D and foreign(busiestMap(D.start[it.id])) then rank = rank + 2 end
            if not bestRank or rank < bestRank then best, bestRank = it, rank end
        end
    end
    return best
end

-- A regeneration can give a chain a new first quest and so a new id, and the old first quest still finds it
function CS:ResolveChainID(chainID)
    self:Ensure()
    local Database = database()
    if not (Database and chainID) then return nil end
    if Database.chains[chainID] then return chainID end
    if chainID > CHAIN_ID_OFFSET then return self:ChainForQuest(chainID - CHAIN_ID_OFFSET) end
    return nil
end

-- Chain names first, then every quest's client and English titles. Never asks the server for a title
function CS:FindByName(needle)
    self:Ensure()
    local Database, D = database(), data()
    if not (Database and D and needle and needle ~= "") then return nil end
    needle = needle:lower()

    local ids = {}
    for id, chain in pairs(Database.chains) do
        if chain._generated then ids[#ids + 1] = id end
    end
    table.sort(ids)

    for i = 1, #ids do
        local chain = Database.chains[ids[i]]
        if chain.name:lower():find(needle, 1, true) then return chain.id, chain.rootID end
    end
    for i = 1, #ids do
        local chain = Database.chains[ids[i]]
        local items = chain.items
        for k = 1, #items do
            local q = items[k].id
            local english = D.names[q]
            if self:Title(q):lower():find(needle, 1, true)
               or (english and english:lower():find(needle, 1, true)) then
                return chain.id, q
            end
        end
    end
    return nil
end
