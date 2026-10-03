local _, ns = ...
local L = ns.L

ns:GetSubsystem("Options"):AddTab("chainGuide", L["Chain Guide"], function(content)
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

    local h = Options:CreateSectionHeader(content, L["Chain Guide (Storylines)"])
    h:SetPoint("TOPLEFT", 8, -8)

    local openBtn = Options:CreateYellowButton(content, L["Open Chain Guide"], function()
        if Options.frame and Options.frame:IsShown() then Options.frame:Hide() end
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Open() end
    end)
    openBtn:SetSize(180, 28)
    openBtn:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -12)

    local loginGet, loginSet = chainSetting("showOnLogin")
    local login = Options:CreateCheckbox(content,
        L["Open Chain Guide on login"],
        loginGet, loginSet)
    login:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -16)

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
    -- Only the retail quest line source discovers chains outside the routing table
    local unrouted = login
    if ns:GetSubsystem("ChainGuideQuestLineSource") then
        unrouted = Options:CreateCheckbox(content,
            L["Show unrouted questlines"],
            unroutedGet, unroutedSet,
            L["API discoveries not in our routing table."])
        unrouted:SetPoint("TOPLEFT", login, "BOTTOMLEFT", 0, -2)
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
    local mapPins = Options:CreateCheckbox(content,
        L["Show tracked chain on the world map"],
        mapPinsGet, mapPinsSet,
        L["Pin the quests of the chain you're following on the world map, with your next step highlighted. Track a chain from the Track button in the Chain Guide."])
    mapPins:SetPoint("TOPLEFT", unrouted, "BOTTOMLEFT", 0, -2)

    local scaleGet, scaleSet = chainSetting("scale")
    local scale = Options:CreateSlider(content, L["Window scale"],
        0.6, 1.5, 0.05, scaleGet, scaleSet)
    scale:SetPoint("TOPLEFT", mapPins, "BOTTOMLEFT", 0, -10)
    scale:SetWidth(280)

    local cacheHeader = Options:CreateSectionHeader(content, L["Character cache"])
    cacheHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 460, 0)

    Options:AttachTooltip(cacheHeader, L["Character cache"],
        L["Per-character chain progress is cached account-wide so alts can browse what your other characters have completed. Clearing the cache removes that cross-character data; live completions stay (Blizzard tracks those)."])

    local clear = Options:CreateYellowButton(content, L["Clear chain cache"], function()
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
    end)
    clear:SetSize(180, 24)
    clear:SetPoint("TOPLEFT", cacheHeader, "BOTTOMLEFT", 0, -12)

    local stats = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    stats:SetWidth(380)
    stats:SetJustifyH("LEFT")
    stats:SetTextColor(0.92, 0.72, 0.02)

    local function refreshStats()
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
        stats:SetText(text)
    end

    local prune = Options:CreateYellowButton(content, L["Prune stale entries now"], function()
        local DB = ns:GetSubsystem("DB")
        if not (DB and DB.MaybePruneChainCache) then return end
        local nRec, nCoord = DB:MaybePruneChainCache(true)
        refreshStats()
        print(L["|cffEBB706EQ|r: pruned |cffffffff%d|r stale character record(s) and |cffffffff%d|r waypoint(s)."]:format(nRec or 0, nCoord or 0))
    end)
    prune:SetSize(180, 24)
    prune:SetPoint("TOPLEFT", clear, "BOTTOMLEFT", 0, -8)

    stats:SetPoint("TOPLEFT", prune, "BOTTOMLEFT", 0, -16)
    refreshStats()
    content:HookScript("OnShow", refreshStats)
end)
