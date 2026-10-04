local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

local function chainSetting(key)
    return
        function()
            local DB = ns:GetSubsystem("DB")
            return DB and DB.db.profile.chainGuide[key]
        end,
        function(value)
            local DB = ns:GetSubsystem("DB")
            if DB then DB.db.profile.chainGuide[key] = value end
            local CG = ns:GetSubsystem("ChainGuide")
            if CG and CG.ApplySettings then CG:ApplySettings() end
        end
end

local function unroutedGet()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.chainGuide.showUnroutedChains
end

local function unroutedSet(value)
    local DB = ns:GetSubsystem("DB")
    if DB then DB.db.profile.chainGuide.showUnroutedChains = value end
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS and QLS.Reset then QLS:Reset() end
    local CG = ns:GetSubsystem("ChainGuide")
    if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
        CG:RenderCurrent()
    end
end

local function mapPinsGet()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.chainGuide.showMapPins ~= false
end

local function mapPinsSet(value)
    local DB = ns:GetSubsystem("DB")
    if DB then DB.db.profile.chainGuide.showMapPins = value end
    local MP = ns:GetSubsystem("ChainGuideMapPins")
    if MP and MP.Refresh then MP:Refresh() end
end

local function cacheStats()
    local cache = _G.EverythingQuestsChainCache or {}
    local nChars, nCoords = 0, 0
    for _, v in pairs(cache) do
        if type(v) == "table" and v.completed ~= nil then nChars = nChars + 1 end
    end
    local qc = cache.questCoords
    if qc then for _ in pairs(qc) do nCoords = nCoords + 1 end end

    local CDB = ns:GetSubsystem("ChainGuideDatabase")
    local nCats, nChains = 0, 0
    if CDB then
        for _ in pairs(CDB.categories) do nCats = nCats + 1 end
        for _ in pairs(CDB.chains)     do nChains = nChains + 1 end
    end

    local text = L["Cached: |cffffffff%d|r characters, |cffffffff%d|r waypoint locations\n|cffffffff%d|r chains across |cffffffff%d|r categories"]
        :format(nChars, nCoords, nChains, nCats)
    if cache.lastPrune and cache.lastPrune > 0 then
        local days = math.floor((time() - cache.lastPrune) / 86400)
        local when = (days <= 0 and L["today"]) or (days == 1 and L["1 day ago"]) or (L["%d days ago"]:format(days))
        text = text .. L["\n|cffaaaaaaLast pruned: %s|r"]:format(when)
    end
    return text
end

local function guideCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["Chain Guide (Storylines)"]))
    card:Add(self:CreateButton(content, L["Open Chain Guide"], nil, function()
        if Options.frame and Options.frame:IsShown() then Options.frame:Hide() end
        local CG = ns:GetSubsystem("ChainGuide")
        if CG then CG:Open() end
    end))

    local loginGet, loginSet = chainSetting("showOnLogin")
    card:Add(self:CreateCheckbox(content, L["Open Chain Guide on login"], loginGet, loginSet))

    -- Only the retail quest line source discovers chains outside the routing table
    if ns:GetSubsystem("ChainGuideQuestLineSource") then
        card:Add(self:CreateCheckbox(content, L["Show unrouted questlines"], unroutedGet, unroutedSet,
            L["API discoveries not in our routing table."]))
    end

    card:Add(self:CreateCheckbox(content, L["Show tracked chain on the world map"], mapPinsGet, mapPinsSet,
        L["Pin the quests of the chain you're following on the world map, with your next step highlighted. Track a chain from the Track button in the Chain Guide."]))

    local scaleGet, scaleSet = chainSetting("scale")
    card:Add(self:CreateSlider(content, L["Window scale"], 0.6, 1.5, 0.05, scaleGet, scaleSet))
end

local function cacheCard(self, content, stack, w)
    local card = stack(self:CreateGroup(content, L["Character cache"]))
    self:AttachTooltip(card.label, L["Character cache"],
        L["Per-character chain progress is cached account-wide so alts can browse what your other characters have completed. Clearing the cache removes that cross-character data; live completions stay (Blizzard tracks those)."])

    local block = self:CreateTextBlock(content)
    w.stats = block:AddLine("")
    card:Add(block, { fitHeight = true })
    w.cacheCard = card

    card:Add(self:CreateButton(content, L["Prune stale entries now"], nil, function()
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.MaybePruneChainCache) then return end
        local nRec, nCoord = DB:MaybePruneChainCache(true)
        w.refresh()
        print(L["|cffEBB706EQ|r: pruned |cffffffff%d|r stale character record(s) and |cffffffff%d|r waypoint(s)."]:format(nRec or 0, nCoord or 0))
    end))
end

Options:RegisterTab({
    id    = "chainGuide",
    title = L["Chain Guide"],
    order = 40,
    footer = function(self, bar)
        local clear = self:CreateButton(bar, L["Clear chain cache"], nil, function()
            local Dialog = ns:GetSubsystem("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title   = "Everything Quests",
                text    = L["Clear all cached chain-completion data across every character?"],
                button1 = L["Clear"],
                button2 = L["Cancel"],
                onAccept = function()
                    _G.EverythingQuestsChainCache = {}
                    ReloadUI()
                end,
            })
        end, nil, "danger")
        clear:SetPoint("RIGHT")
    end,
    build = function(self, content)
        local stack = Options.CardStack(self)
        local w = {}
        -- The counts change outside this tab, so they are read again on every view
        w.refresh = function()
            w.stats:SetText(cacheStats())
            w.cacheCard:Layout()
        end
        content._refresh = w.refresh

        guideCard(self, content, stack)
        cacheCard(self, content, stack, w)
        w.refresh()
    end,
    refresh = function(_, content)
        if content._refresh then content._refresh() end
    end,
})
