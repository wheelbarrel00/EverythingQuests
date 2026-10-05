local _, ns = ...

local QLS = ns:RegisterSubsystem("ChainGuideQuestLineSource", {})

QLS._discovered     = {}
QLS._populated      = {}
QLS._registered     = {}
QLS._retryScheduled = {}
QLS._retryCount     = {}
QLS._gen            = 0

local _discoverSeen   = {}
local _discoverUnique = {}

function QLS:Reset()
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    for chainID, chain in pairs(Database.chains) do
        if chain._apiSourced then Database.chains[chainID] = nil end
    end
    self._discovered     = {}
    self._populated      = {}
    self._registered     = {}
    self._retryScheduled = {}
    self._retryCount     = {}
    self._gen = self._gen + 1
    local CS = ns:GetSubsystem("ChainGuideCampaignSource")
    if CS and CS.Reset then CS:Reset() end
end

local CHAIN_ID_OFFSET = 5000000
local RETRY_BASE_DELAY = 0.3
local RETRY_MAX        = 8

local function showUnrouted()
    local DB = ns:GetSubsystem("DB")
    local cg = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
    if cg and cg.showUnroutedChains ~= nil then return cg.showUnroutedChains end
    return false
end

local function routedEntry(questLineID)
    local map = ns.QUESTLINE_ROUTING
    if not map then return nil end
    local v = map[questLineID]
    if type(v) == "table" then return v end
    if type(v) == "number" then return { cat = v } end
    return nil
end
local function routedCategory(questLineID)
    local e = routedEntry(questLineID)
    return e and e.cat
end

local function authoredQuestlinesInCategory(catID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local set = {}
    for _, chain in pairs(Database.chains) do
        if chain.category == catID and chain.questlineID and not chain._apiSourced then
            set[chain.questlineID] = true
        end
    end
    return set
end

local function getOverrideList(catID)
    local DB = ns:GetSubsystem("DB")
    local map = DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
                and DB.db.profile.chainGuide.zoneMapIDs
    if not map then return nil end
    local v = map[catID]
    if type(v) == "number" then return { v } end
    if type(v) == "table"  then return v   end
    return nil
end

local function resolveMapIDs(cat, catID)
    local out, seen = {}, {}
    local function push(m)
        if m and not seen[m] then seen[m] = true; out[#out + 1] = m end
    end
    if cat then
        if cat.mapIDs then for _, m in ipairs(cat.mapIDs) do push(m) end end
        push(cat.mapID)
    end
    local list = getOverrideList(catID)
    if list then for _, m in ipairs(list) do push(m) end end
    return out
end

function QLS:CategoryMapIDs(catID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    return resolveMapIDs(Database and Database.categories[catID], catID)
end

local function appendMapIDOverride(catID, mapID)
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.db) then return end
    local cg = DB.db.profile.chainGuide
    cg.zoneMapIDs = cg.zoneMapIDs or {}
    local cur = cg.zoneMapIDs[catID]
    if type(cur) == "number" then cur = { cur }; cg.zoneMapIDs[catID] = cur end
    if type(cur) ~= "table" then cur = {}; cg.zoneMapIDs[catID] = cur end
    for i = 1, #cur do
        if cur[i] == mapID then return end
    end
    cur[#cur + 1] = mapID
end

local function matchCategoryByName(name)
    if not name or name == "" then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local lower = name:lower()
    for id, cat in pairs(Database.categories) do
        if (cat.name or ""):lower() == lower then return id end
    end
    for id, cat in pairs(Database.categories) do
        local cn = (cat.name or ""):lower()
        if cn ~= "" and (lower:find(cn, 1, true) or cn:find(lower, 1, true)) then
            return id
        end
    end
    return nil
end

function QLS:EnsureZoneChains(catID)
    if self._discovered[catID] then return end

    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local cat = Database.categories[catID]
    if not cat then return end

    if cat.campaignID then
        local CS = ns:GetSubsystem("ChainGuideCampaignSource")
        if CS then CS:EnsureCampaignChains(catID) end
        self._discovered[catID] = true
        return
    end

    local skip = authoredQuestlinesInCategory(catID)

    local function registerChain(qlID, destCat, name)
        if self._registered[qlID] or skip[qlID] then return end
        local CS = ns:GetSubsystem("ChainGuideCampaignSource")
        if CS and CS.IsChapterQuestline and CS:IsChapterQuestline(qlID) then
            return
        end
        local chainID = CHAIN_ID_OFFSET + qlID
        if not Database.chains[chainID] then
            Database:RegisterChain(chainID, {
                category    = destCat,
                name        = name or ("Questline " .. qlID),
                questlineID = qlID,
                items       = {},
                _apiSourced = true,
            })
        end
        self._registered[qlID] = true
    end

    local routing = ns.QUESTLINE_ROUTING or {}
    for qlID, entry in pairs(routing) do
        local destCat = (type(entry) == "table") and entry.cat or entry
        local name    = (type(entry) == "table") and entry.name or nil
        if destCat == catID then registerChain(qlID, destCat, name) end
    end

    if C_QuestLine and C_QuestLine.GetAvailableQuestLines then
        local mapIDs = resolveMapIDs(cat, catID)
        local includeUnrouted = showUnrouted()
        for _, mapID in ipairs(mapIDs) do
            local lines = C_QuestLine.GetAvailableQuestLines(mapID) or {}
            for i = 1, #lines do
                local info = lines[i]
                local qlID = info and info.questLineID
                if qlID and not info.isHidden then
                    local routedCat = routedCategory(qlID)
                    local destCat = routedCat or (includeUnrouted and catID or nil)
                    if destCat then
                        registerChain(qlID, destCat,
                            (info.questLineName ~= "" and info.questLineName) or nil)
                    end
                end
            end
        end
    end

    self._discovered[catID] = true
end

local NON_CHAIN_QUESTS = {
    [93811] = true, [94871] = true, [94993] = true, [95008] = true,
    [86874] = true, [89035] = true, [93566] = true,
    [92641] = true, [95276] = true,
}

function QLS:EnsureChainItems(chain)
    if not chain or self._populated[chain.id] then return end
    if not chain.questlineID then return end
    if chain.items and #chain.items > 0 then
        self._populated[chain.id] = true
        return
    end
    if not (C_QuestLine and C_QuestLine.GetQuestLineQuests) then return end

    local quests = C_QuestLine.GetQuestLineQuests(chain.questlineID)
    if not quests or #quests == 0 then
        local curated = ns.CHAINGUIDE_CURATED_ITEMS and ns.CHAINGUIDE_CURATED_ITEMS[chain.questlineID]
        if curated and #curated > 0 then
            quests = curated
        else
            local tries = self._retryCount[chain.id] or 0
            if tries < RETRY_MAX and not self._retryScheduled[chain.id] then
                self._retryScheduled[chain.id] = true
                self._retryCount[chain.id] = tries + 1
                local gen = self._gen
                C_Timer.After(RETRY_BASE_DELAY * (tries + 1), function()
                    if gen ~= self._gen then return end
                    self._retryScheduled[chain.id] = nil
                    self:EnsureChainItems(chain)
                    local CG = ns:GetSubsystem("ChainGuide")
                    if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
                        CG:RenderCurrent()
                    end
                end)
            end
            return
        end
    end

    local items = {}
    local n = 0
    for i = 1, #quests do
        local qid = quests[i]
        if not NON_CHAIN_QUESTS[qid] then
            n = n + 1
            items[n] = {
                type        = "quest",
                id          = qid,
                x           = 0,
                y           = n - 1,
                connections = (n > 1) and { n - 1 } or nil,
            }
        end
    end
    chain.items = items
    chain._normalized = true
    self._populated[chain.id] = true
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if Database and Database.ApplyOverlay then Database:ApplyOverlay(chain) end
end

function QLS:PrintCurrentZone(hint)
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
        print("|cffEBB706EQ|r: could not resolve player's map.")
        return
    end
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneName = info and info.name or "?"
    print(("|cffEBB706EQ|r: |cffffffff%s|r — uiMapID |cff66ccff%d|r"):format(zoneName, mapID))

    local catID
    if hint and hint ~= "" then
        catID = matchCategoryByName(hint)
        if not catID then
            print(("  No category matches |cffffffff%s|r."):format(hint))
        end
    else
        catID = matchCategoryByName(zoneName)
        if not catID then
            print("  No category name match. Use |cffEBB706/eqs discover <category>|r to assign manually (e.g. \"/eqs discover eversong\").")
        end
    end

    if catID then
        local Database = ns:GetSubsystem("ChainGuideDatabase")
        local cat = Database.categories[catID]
        appendMapIDOverride(catID, mapID)
        self._discovered[catID] = nil
        print(("  Added to category |cffffffff%s|r."):format(cat and cat.name or tostring(catID)))
        local CG = ns:GetSubsystem("ChainGuide")
        if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
            CG:RenderCurrent()
        end
    end

    if not (C_QuestLine and C_QuestLine.GetAvailableQuestLines) then
        print("  (C_QuestLine API unavailable on this build)")
        return
    end
    local lines = C_QuestLine.GetAvailableQuestLines(mapID) or {}
    if #lines == 0 then
        print("  No questlines reported by the API yet (move around the zone and retry).")
        return
    end
    wipe(_discoverSeen)
    wipe(_discoverUnique)
    for i = 1, #lines do
        local q = lines[i]
        if q.questLineID and not _discoverSeen[q.questLineID] then
            _discoverSeen[q.questLineID] = true
            _discoverUnique[#_discoverUnique + 1] = q
        end
    end
    print(("  |cffEBB706%d unique questline(s):|r"):format(#_discoverUnique))
    for i = 1, #_discoverUnique do
        local q = _discoverUnique[i]
        print(("    [%d] %s%s"):format(
            q.questLineID or 0,
            q.questLineName or "?",
            q.isHidden and " |cff999999(hidden)|r" or ""
        ))
    end
end
