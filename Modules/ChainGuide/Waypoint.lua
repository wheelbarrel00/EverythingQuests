local _, ns = ...

local W = ns:RegisterSubsystem("ChainGuideWaypoint", {})

-- Listed only where the Classic quest tables load, so its presence is the flavor test
local function classicSource()
    return ns:GetSubsystem("ChainGuideClassicSource")
end

local function titleOf(questID)
    local CS = classicSource()
    if CS then return CS:Title(questID) end
    return ns.Util.QuestTitle(questID, true)
end

-- Era and TBC have no GetLogIndexForQuestID, so the Classic tables read the log through the same gate as the map
local function inLog(questID)
    local Characters = classicSource() and ns:GetSubsystem("ChainGuideCharacters")
    if Characters then return Characters:IsQuestActive(questID) end
    return C_QuestLog and C_QuestLog.GetLogIndexForQuestID
           and C_QuestLog.GetLogIndexForQuestID(questID) ~= nil or false
end

local function cacheTable()
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.chainCache) then return nil end
    DB.chainCache.questCoords = DB.chainCache.questCoords or {}
    return DB.chainCache.questCoords
end

local function cacheGet(questID)
    local t = cacheTable()
    local e = t and t[questID]
    if e and e.m and e.x and e.y then
        e.lastSeen = time()
        return e.m, e.x, e.y
    end
end

local function cacheSet(questID, mapID, x, y)
    if not (questID and mapID and x and y) then return end
    local t = cacheTable()
    if t then t[questID] = { m = mapID, x = x, y = y, lastSeen = time() } end
end

function W:PruneStaleCoords(now, ttl)
    local t = cacheTable()
    if not t then return 0 end
    local removed = 0
    for questID, e in pairs(t) do
        if type(e) == "table" then
            if not e.lastSeen then
                e.lastSeen = now
            elseif now - e.lastSeen > ttl then
                t[questID] = nil
                removed = removed + 1
            end
        end
    end
    return removed
end

local _cand = {}
local function candidateMaps(chain)
    wipe(_cand)
    local seen = {}
    local function push(m)
        if m and m > 0 and not seen[m] then seen[m] = true; _cand[#_cand + 1] = m end
    end

    if C_Map and C_Map.GetBestMapForUnit then
        push(C_Map.GetBestMapForUnit("player"))
    end

    local catID = chain and chain.category
    if catID then
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local cat = Database and Database.categories[catID]
        if cat then
            if cat.mapIDs then for _, m in ipairs(cat.mapIDs) do push(m) end end
            push(cat.mapID)
        end
        local DB = ns:GetSubsystem("DB")
        local ov = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
                   and DB.db.profile.chainGuide.zoneMapIDs
                   and DB.db.profile.chainGuide.zoneMapIDs[catID]
        if type(ov) == "number" then push(ov)
        elseif type(ov) == "table" then for _, m in ipairs(ov) do push(m) end end
    end
    return _cand
end

local function questLineStart(questID, mapID)
    if not (C_QuestLine and C_QuestLine.GetQuestLineInfo) then return nil end
    local info = C_QuestLine.GetQuestLineInfo(questID, mapID)
    if not (info and info.x and info.y and (info.x ~= 0 or info.y ~= 0)) then return nil end
    -- Blizzard's own quest offers drop an answer that starts outside the asked map (QuestOfferDataProvider)
    local start = info.startMapID
    if start and start ~= mapID
       and not (MapUtil and MapUtil.IsChildMapCached and MapUtil.IsChildMapCached(start, mapID)) then
        return nil, nil, start
    end
    return info.x, info.y
end

-- Only Resolve follows an answer naming another start map, asking that map once
local function questLineStartAnywhere(questID, mapID)
    local x, y, other = questLineStart(questID, mapID)
    if x then return mapID, x, y end
    if other and other > 0 then
        local ox, oy = questLineStart(questID, other)
        if ox then return other, ox, oy end
    end
    return nil
end

function W:Resolve(questID, chain)
    if not questID then return nil end

    local CS = classicSource()
    if CS then
        local p = CS:StartPoint(questID)
        if p then return p.mapID, p.x, p.y end
    end

    local m, x, y = cacheGet(questID)
    if m then return m, x, y end

    local static = ns.CHAINGUIDE_QUEST_COORDS and ns.CHAINGUIDE_QUEST_COORDS[questID]
    if static and static.m and static.x and static.y then
        cacheSet(questID, static.m, static.x, static.y)
        return static.m, static.x, static.y
    end

    if not CS then
        local maps = candidateMaps(chain)
        for i = 1, #maps do
            local qm, qx, qy = questLineStartAnywhere(questID, maps[i])
            if qm then
                cacheSet(questID, qm, qx, qy)
                return qm, qx, qy
            end
        end
    end

    return nil
end

function W:SetWaypoint(mapID, x, y, title, questID)
    if classicSource() then
        -- The one arrow slot the map pins and the tracker focus already share, so a click here retargets it
        local Arrow = ns:GetSubsystem("QuestArrow")
        if Arrow and Arrow:Available() and Arrow:Set(mapID, x, y, title, questID) then return true end
    elseif TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(mapID, x, y, { title = title, from = "Everything Quests" })
        return true
    end
    -- Never write Blizzard's user waypoint here - SetUserWaypoint and SetSuperTrackedUserWaypoint seed sticky taint into shared super-track state that the AreaPOI tooltip and quest data provider read later
    print(("|cffEBB706EQ|r: |cffffffff%s|r is at |cff66ccff%.1f, %.1f|r — opening the map there."):format(
        title or "Quest", (x or 0) * 100, (y or 0) * 100))
    return false
end

-- Retargeting the world map makes every data provider re-acquire pins, and from an insecure click that refresh runs tainted (C_Timer does not launder it), so openMap skips the retarget when already on this mapID
local function doOpenMap(mapID)
    if OpenWorldMap then
        OpenWorldMap(mapID)
    elseif WorldMapFrame then
        if ShowUIPanel then ShowUIPanel(WorldMapFrame) end
        if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(mapID) end
    end
end

local function openMap(mapID)
    if mapID and WorldMapFrame and WorldMapFrame:IsShown()
       and WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() == mapID then
        return
    end
    -- Never retarget the map in combat - data providers call the protected SetPropagateMouseClicks when re-acquiring pins after SetMapID, which blocks under lockdown
    if InCombatLockdown() then
        local Events = ns:GetSubsystem("Events")
        if Events then
            Events:RunWhenOutOfCombat("chainGuideOpenMap", function() doOpenMap(mapID) end)
        end
        return
    end
    doOpenMap(mapID)
end

local function liveWaypoint(questID)
    local Arrow = classicSource() and ns:GetSubsystem("QuestArrow")
    if Arrow and Arrow.PointFor then
        local m, x, y = Arrow:PointFor(questID)
        if m and x and y then return m, x, y end
    end
    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        local m, x, y = C_QuestLog.GetNextWaypoint(questID)
        if m and x and y and (x ~= 0 or y ~= 0) then return m, x, y end
    end
    if C_QuestLog and C_QuestLog.GetQuestsOnMap
       and C_Map and C_Map.GetBestMapForUnit then
        local pm = C_Map.GetBestMapForUnit("player")
        local list = pm and C_QuestLog.GetQuestsOnMap(pm)
        if list then
            for i = 1, #list do
                local e = list[i]
                if e.questID == questID and e.x and e.y and (e.x ~= 0 or e.y ~= 0) then
                    return pm, e.x, e.y
                end
            end
        end
    end
    return nil
end

function W:ResolveForPin(questID, chain, viewMapID)
    if not questID then return nil end
    local onQuest = inLog(questID)
    if onQuest then
        local m, x, y = liveWaypoint(questID)
        if m and x and y then return m, x, y, true end
    end
    local m, x, y = self:Resolve(questID, chain)
    -- A step not in the log takes its start point on the viewed map, where the stored answer may not lie
    if viewMapID and m ~= viewMapID and not onQuest and not classicSource() then
        local vx, vy = questLineStart(questID, viewMapID)
        if vx then return viewMapID, vx, vy, false end
    end
    if m and x and y then return m, x, y, onQuest end
    return nil
end

function W:_goToInLog(questID, title)
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        -- Clear the user waypoint only if one exists - a needless call still fires SUPER_TRACKING_CHANGED, and each such event re-acquires quest pins on our tainted stack
        if C_SuperTrack.SetSuperTrackedUserWaypoint
           and C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() then
            C_SuperTrack.SetSuperTrackedUserWaypoint(false)
        end
        -- Same redundant-event reasoning - do not re-super-track the quest we already track
        local cur = C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID()
        if cur ~= questID then
            C_SuperTrack.SetSuperTrackedQuestID(questID)
        end
    end
    local wm, wx, wy = liveWaypoint(questID)
    -- No TomTom test here. SetWaypoint already branches on it and prints the coordinates when it
    -- is absent, and gating on TomTom first made that message unreachable from this path while
    -- the not-in-log path printed it - the same click said different things about the same quest.
    if wm and wx and wy then
        self:SetWaypoint(wm, wx, wy, title, questID)
    else
        -- Silence read as a dead button. The client returning no position is a normal answer, not
        -- a failure, and saying so beats a click that appears to do nothing.
        local why = classicSource() and "no position is known for its next objective"
                    or "the game has not given a position for its next objective"
        print(("|cffEBB706EQ|r: |cffffffff%s|r is super-tracked and the map is open, but %s, so there is no arrow to set."):format(
            title or "Quest", why))
    end
    openMap(wm or (C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")))
    return true
end

function W:_goToGiver(questID, chain, title)
    local mapID, x, y = self:Resolve(questID, chain)
    if mapID and x and y then
        self:SetWaypoint(mapID, x, y, title)
        openMap(mapID)
        return true
    end
    return false
end

local _stepCellDone  = {}
local _stepCellInLog = {}

local function stepCellKey(raw)
    if raw.x and raw.y then return raw.y * 4096 + raw.x end
    return nil
end

local function readSteps(chain)
    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    if not (Database and Characters) then return nil end
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)
    local items = chain.items
    if not items then return nil end
    local char = Database:CurrentCharacter()

    -- Faction-paired steps share one overlay cell and the off-faction twin can never complete, so collapse by cell - done if any member is done, and prefer a member in the player's log
    wipe(_stepCellDone)
    wipe(_stepCellInLog)
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local key = stepCellKey(raw)
            if key then
                local item = Database:GetVariation(raw, char)
                local qid  = item and item.id
                if qid then
                    if Characters:IsQuestCompleted(qid) then
                        _stepCellDone[key] = true
                    elseif C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                           and C_QuestLog.GetLogIndexForQuestID(qid) then
                        _stepCellInLog[key] = item
                    end
                end
            end
        end
    end
    return items, Database, Characters, char
end

local function nextActionableStep(chain)
    if not chain then return nil end
    if chain._generated then
        local CS = classicSource()
        if CS then return CS:NextStep(chain) end
    end
    local items, Database, Characters, char = readSteps(chain)
    if not items then return nil end

    -- A quest you are on comes first, as Forever's NextStep does, so a branch you took is the one followed
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local key = stepCellKey(raw)
            local onIt = key and _stepCellInLog[key]
            if onIt and not _stepCellDone[key] then return onIt end
        end
    end

    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" and not raw.breadcrumb then
            local item = Database:GetVariation(raw, char)
            if item and item.id and not Characters:IsQuestCompleted(item.id) then
                local key = stepCellKey(raw)
                if not (key and _stepCellDone[key]) then
                    if key and _stepCellInLog[key] then return _stepCellInLog[key] end
                    return item
                end
            end
        end
    end
    return nil
end

local NO_LINKS = {}

-- A card sends you back only to a step its quest still needs through the chain's links
local function stepItNeeds(chain, questID)
    local items, Database, Characters, char = readSteps(chain)
    if not items then return nil end
    local function stepAt(i)
        local raw = items[i]
        if not raw or raw.type == "chain" or raw.breadcrumb then return nil end
        local item = Database:GetVariation(raw, char)
        if not (item and item.id) then return nil end
        local key = stepCellKey(raw)
        local finished = (key and _stepCellDone[key]) or Characters:IsQuestCompleted(item.id)
        return (key and _stepCellInLog[key]) or item, finished
    end
    local function onQuest(i)
        local key = items[i] and stepCellKey(items[i])
        return key and _stepCellInLog[key] and not _stepCellDone[key]
    end
    -- Every linked cell must be done, as twins share one, and a step you are on counts as reached
    local function open(i)
        if onQuest(i) then return true end
        for _, p in ipairs(items[i].connections or NO_LINKS) do
            local step, finished = stepAt(p)
            if step and not finished then return false end
        end
        return true
    end
    local start
    for i = 1, #items do
        local raw = items[i]
        if raw.type ~= "chain" then
            local item = Database:GetVariation(raw, char)
            if raw.id == questID or (item and item.id == questID) then
                start = i
                break
            end
        end
    end
    if not start then return nil end
    local need, stack = { [start] = true }, { start }
    while #stack > 0 do
        local i = table.remove(stack)
        for _, p in ipairs(items[i].connections or NO_LINKS) do
            if not need[p] then
                local step, finished = stepAt(p)
                if step and not finished then
                    need[p] = true
                    stack[#stack + 1] = p
                end
            end
        end
    end
    local first
    for i = 1, #items do
        if need[i] and open(i) then
            local step = stepAt(i)
            if step and onQuest(i) then return step end
            first = first or step
        end
    end
    return first
end

function W:NextActionableStep(chain)
    return nextActionableStep(chain)
end

function W:AdvanceWaypoint(chain)
    local step = nextActionableStep(chain)
    if not (step and step.id) then return nil end
    local id = step.id
    if inLog(id) then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
            local cur = C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
            if cur ~= id then C_SuperTrack.SetSuperTrackedQuestID(id) end
        end
        if TomTom and TomTom.AddWaypoint then
            local wm, wx, wy = liveWaypoint(id)
            if wm and wx and wy then self:SetWaypoint(wm, wx, wy, titleOf(id), id) end
        end
    elseif TomTom and TomTom.AddWaypoint then
        local m, x, y = self:Resolve(id, chain)
        if m and x and y then self:SetWaypoint(m, x, y, titleOf(id)) end
    end
    return step
end

function W:GoTo(questID, chain)
    local title = titleOf(questID)

    local navID, navTitle = questID, title
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    if chain and not inLog(questID) and Characters and not Characters:IsQuestCompleted(questID) then
        local CS = chain._generated and classicSource()
        if not CS then
            local step = stepItNeeds(chain, questID)
            if step and step.id ~= questID then
                navID    = step.id
                navTitle = titleOf(step.id) or navTitle
                print(("|cffEBB706EQ|r: |cffffffff%s|r needs |cffffffff%s|r first, so directions are set there."):format(
                    title, navTitle))
            end
        -- A quest the game offers you right now is a step in its own right, wherever it sits in the chain
        elseif CS:Status(questID) ~= "available" then
            local step = nextActionableStep(chain)
            if step and step.id and step.id ~= questID then
                navID    = step.id
                navTitle = titleOf(step.id) or navTitle
                print(("|cffEBB706EQ|r: |cffffffff%s|r comes later in |cffffffff%s|r, so directions are set to your next step, |cffffffff%s|r."):format(
                    title, chain.name or "this chain", navTitle))
            end
        end
    end

    if inLog(navID) then
        return self:_goToInLog(navID, navTitle)
    end

    if self:_goToGiver(navID, chain, navTitle) then
        return true
    end

    local maps = candidateMaps(chain)
    if maps[1] then openMap(maps[1]) end
    print(("|cffEBB706EQ|r: no precise location for |cffffffff%s|r yet — it'll be saved automatically the first time you pick it up."):format(navTitle))
    return false
end

local function harvest(questID)
    if not (questID and questID > 0) then return end
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return end
    local m = C_Map.GetBestMapForUnit("player")
    if not m then return end
    local pos = C_Map.GetPlayerMapPosition(m, "player")
    if not pos then return end
    local x, y = pos:GetXY()
    if x and y and (x ~= 0 or y ~= 0) then
        cacheSet(questID, m, x, y)
    end
end

local function questBelongsToChain(chain, questID)
    if not (chain and chain.items and questID) then return false end
    for i = 1, #chain.items do
        local raw = chain.items[i]
        if raw and raw.type ~= "chain" then
            if raw.id == questID then return true end
            if raw.variations then
                for j = 1, #raw.variations do
                    if raw.variations[j].id == questID then return true end
                end
            end
        end
    end
    return false
end

function W:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    Events:On("QUEST_DETAIL", function()
        if GetQuestID then harvest(GetQuestID()) end
    end)
    Events:On("QUEST_ACCEPTED", function(_, a, b)
        harvest(b or a)
    end)

    Events:On("QUEST_TURNED_IN", function(_, questID)
        local CG = ns:GetSubsystem("ChainGuide")
        local chain = CG and CG.GetTrackedChain and CG:GetTrackedChain()
        if not chain then return end
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        if Database then Database:NormalizeChain(chain) end
        if not questBelongsToChain(chain, questID) then return end
        -- IsQuestFlaggedCompleted can lag one frame behind QUEST_TURNED_IN, so defer the next-step recompute
        C_Timer.After(0, function()
            local step = self:AdvanceWaypoint(chain)
            if not step and chain.items and #chain.items > 0 then
                if CG.ClearTrackedChainID then CG:ClearTrackedChainID() end
                print(("|cffEBB706EQ|r: |cffffffff%s|r complete — no longer following it."):format(chain.name or "This chain"))
            end
        end)
    end)
end
