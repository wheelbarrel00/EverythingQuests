local _, ns = ...
local L = ns.L

local CG = ns:RegisterSubsystem("ChainGuide", {})

local SIDEBAR_W   = 280
local MIN_W       = 760
local MIN_H       = 460
local DEFAULT_W   = 1100
local DEFAULT_H   = 720
local SIDE_PAD    = 12
local FIELD_GAP   = 8
local NOTE_GAP    = 6
local LABEL_GAP   = 16
local LIST_GAP    = 6
local BUTTON_SIZE = 32
local BUTTON_GAP  = 2
local HEAD_LEFT   = 16
local HEAD_TOP    = 12
local HINT_GAP    = 4

local function guideCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db and DB.db.profile and DB.db.profile.chainGuide
end

local function hideResizeHint(f)
    local cfg = guideCfg()
    if cfg then cfg.resizeHintSeen = true end
    if f.resizeHint then f.resizeHint:Hide() end
end

local function sortedCategories(self)
    if self._sortedCategories then return self._sortedCategories end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local cats = {}
    for id, c in pairs(Database.categories) do
        cats[#cats + 1] = { id = id, def = c }
    end
    table.sort(cats, function(a, b)
        local ao = a.def.order or math.huge
        local bo = b.def.order or math.huge
        if ao ~= bo then return ao < bo end
        return (a.def.name or "") < (b.def.name or "")
    end)
    self._sortedCategories = cats
    return cats
end

local function rangeText(range)
    if not range then return nil end
    if range[1] == range[2] then return tostring(range[1]) end
    return ("%d-%d"):format(range[1], range[2])
end

function CG:ZoneOptions()
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not Database then return {} end
    Database:EnsureGenerated()
    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end
    local hasChains = {}
    for _, c in pairs(Database.chains) do hasChains[c.category] = true end
    local out = {}
    for _, entry in ipairs(sortedCategories(self)) do
        if hasChains[entry.id] then
            out[#out + 1] = {
                value  = entry.id,
                label  = entry.def.name or ("Category " .. entry.id),
                suffix = rangeText(entry.def.levelRange),
            }
        end
    end
    return out
end

-- Forever's own zone, else a category listing your map or a parent of it, else the first
function CG:HomeCategory()
    local CS = ns:GetSubsystem("ChainGuideClassicSource")
    local here = CS and CS:CategoryForPlayer()
    if here then return here end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    local zones = self:ZoneOptions()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local seen = 0
    while map and map > 0 and seen < 8 do
        for _, z in ipairs(zones) do
            local def = Database.categories[z.value]
            local maps = (QLS and QLS.CategoryMapIDs and QLS:CategoryMapIDs(z.value)) or (def and def.mapIDs) or {}
            for _, m in ipairs(maps) do
                if m == map then return z.value end
            end
        end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map = info and info.parentMapID
        seen = seen + 1
    end
    return zones[1] and zones[1].value
end

local function iconButton(ctx, parent, icon, title, body, onClick)
    local b = ctx:CreateIconButton(parent, icon, BUTTON_SIZE)
    b:SetScript("OnClick", onClick)
    ctx:AttachTooltip(b, title, body)
    return b
end

local function placeListLabel(f)
    local above = f.searchNote:IsShown() and f.searchNote or f.search
    f.listLabel:ClearAllPoints()
    f.listLabel:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, -LABEL_GAP)
    f.list:ClearAllPoints()
    f.list:SetPoint("TOPLEFT", f.listLabel, "BOTTOMLEFT", -SIDE_PAD, -LIST_GAP)
    f.list:SetPoint("BOTTOMRIGHT", f.sidebar, "BOTTOMRIGHT", 0, 0)
end

function CG:Build()
    if self.frame then return end
    local Options = ns:GetSubsystem("Options")
    local ctx = Options.ui

    local f = ctx:CreateWindow({
        name = "EQChainGuideFrame", title = L["Chain Guide"],
        width = DEFAULT_W, height = DEFAULT_H, minWidth = MIN_W, minHeight = MIN_H,
        sidebarWidth = SIDEBAR_W, gripTip = L["Drag to resize"],
        getSize = function()
            local cfg = guideCfg()
            if cfg then return cfg.width, cfg.height end
        end,
        setSize = function(w, h)
            local cfg = guideCfg()
            if cfg then cfg.width, cfg.height = w, h end
        end,
        getMaximized = function()
            local cfg = guideCfg()
            return cfg and cfg.maximized or false
        end,
        setMaximized = function(on)
            local cfg = guideCfg()
            if cfg then cfg.maximized = on or nil end
        end,
        onResize = function(win)
            hideResizeHint(win)
            self:RenderCurrent()
        end,
    })
    self.frame = f

    f:AddHeaderButton("icon-settings", L["Options"], nil, function()
        Options:Show()
        Options:SelectTab("chainGuide")
    end)

    -- On the grip's level, so the graph cannot cover it, and gone once the window has been resized
    f.resizeHint = ctx:CreateText(f.grip, L["Drag to resize"], "hint")
    f.resizeHint:SetPoint("RIGHT", f.grip, "LEFT", -HINT_GAP, 0)
    local cfg = guideCfg()
    if cfg and cfg.resizeHintSeen then f.resizeHint:Hide() end

    local side = f.sidebar
    f.zonePicker = ctx:CreateDropdown(side, nil, function() return self:ZoneOptions() end,
        function() return self._activeCatID end,
        function(id) self:NavigateCategory(id) end)
    f.zonePicker:SetPoint("TOPLEFT", side, "TOPLEFT", SIDE_PAD, -SIDE_PAD)
    f.zonePicker:SetPoint("TOPRIGHT", side, "TOPRIGHT", -SIDE_PAD, -SIDE_PAD)

    f.search = ctx:CreateSearchField(side, L["Find quest"], function(text) self:RunSearch(text) end,
        L["Find quest"], L["Type a quest name or its ID to jump to the chain that contains it."])
    f.search:SetPoint("TOPLEFT", f.zonePicker, "BOTTOMLEFT", 0, -FIELD_GAP)
    f.search:SetPoint("TOPRIGHT", f.zonePicker, "BOTTOMRIGHT", 0, -FIELD_GAP)

    f.searchNote = ctx:CreateText(side, "", "hint")
    f.searchNote:SetPoint("TOPLEFT", f.search, "BOTTOMLEFT", 0, -NOTE_GAP)
    f.searchNote:SetPoint("TOPRIGHT", f.search, "BOTTOMRIGHT", 0, -NOTE_GAP)
    f.searchNote:SetWordWrap(true)
    f.searchNote:Hide()

    f.listLabel = ctx:CreateHeading(side, L["Chains"])
    f.list = ctx:CreateList(side, function(id) self:NavigateChain(id) end)
    placeListLabel(f)

    local body = f.body
    f.hideListBtn = iconButton(ctx, body, "icon-sidebar", L["Hide the navigation panel"],
        L["Collapse the zone picker, search and chain list so the graph fills the whole window. Click again to bring them back."],
        function() self:SetRailCollapsed(true) end)
    f.hideListBtn:SetPoint("TOPLEFT", body, "TOPLEFT", HEAD_LEFT, -HEAD_TOP)
    f.showListBtn = iconButton(ctx, body, "icon-sidebar", L["Show the navigation panel"], nil,
        function() self:SetRailCollapsed(false) end)
    f.showListBtn:SetPoint("TOPLEFT", body, "TOPLEFT", HEAD_LEFT, -HEAD_TOP)
    f.backBtn = iconButton(ctx, body, "chevron-left", L["Back"], nil, function() self:Back() end)
    f.backBtn:SetPoint("LEFT", f.hideListBtn, "RIGHT", BUTTON_GAP, 0)
    f.fwdBtn = iconButton(ctx, body, "chevron-right", L["Forward"], nil, function() self:Forward() end)
    f.fwdBtn:SetPoint("LEFT", f.backBtn, "RIGHT", BUTTON_GAP, 0)

    local CV = ns:GetSubsystem("ChainGuideView")
    CV:_ensureUI(body, ctx)
    -- The chain header, built after these buttons, spans the same corner, so they are raised over it
    for _, b in ipairs({ f.hideListBtn, f.showListBtn, f.backBtn, f.fwdBtn }) do
        b:SetFrameLevel(body._cvHead:GetFrameLevel() + 1)
    end

    self:SetRailCollapsed(cfg and cfg.railCollapsed or false)
    local home = self:HomeCategory()
    if home then self:NavigateCategory(home) else self:NavigateHome() end
end

function CG:ApplySettings()
    if not self.frame then return end
    local cfg = guideCfg()
    if cfg and cfg.scale then self.frame:SetScale(cfg.scale) end
    self.frame:Refit()
    if self.frame:IsMaximized() then
        -- A refit can shrink the scroll range under the current offset, and no render follows it
        local body = self.frame.body
        if body and body._cvClampScroll then C_Timer.After(0, body._cvClampScroll) end
    end
end

function CG:OnEnable()
    local cfg = guideCfg()
    if cfg and cfg.showOnLogin then
        C_Timer.After(0.5, function() self:Open() end)
    end
end

local function hideOptions()
    local O = ns:GetSubsystem("Options")
    if O and O.frame and O.frame:IsShown() then O.frame:Hide() end
end

-- Drawn again once shown, because a centered chain is placed from the view's width
function CG:Toggle()
    self:Build()
    self:ApplySettings()
    if self.frame:IsShown() then
        self.frame:Hide()
    else
        hideOptions()
        self:CancelSearch()
        self.frame:Show()
        self:RenderCurrent()
    end
end

function CG:Open()
    self:Build()
    self:ApplySettings()
    if not self.frame:IsShown() then
        hideOptions()
        self:CancelSearch()
        self.frame:Show()
        self:RenderCurrent()
    end
end

function CG:SetRailCollapsed(collapsed)
    local f = self.frame
    if not f then return end
    self._railCollapsed = collapsed and true or false
    f:SetSidebarShown(not self._railCollapsed)
    f.hideListBtn:SetShown(not self._railCollapsed)
    f.showListBtn:SetShown(self._railCollapsed)
    local cfg = guideCfg()
    if cfg then cfg.railCollapsed = self._railCollapsed end
    self:RenderCurrent()
end

function CG:NavigateHome()
    local H = ns:GetSubsystem("ChainGuideHistory")
    H:Push({ type = "home" })
    self:RenderCurrent()
end

function CG:NavigateCategory(catID)
    local H = ns:GetSubsystem("ChainGuideHistory")
    self:CancelSearch()
    H:Push({ type = "category", id = catID })
    self:RenderCurrent()
end

function CG:NavigateChain(chainID, highlightQuestID)
    local H = ns:GetSubsystem("ChainGuideHistory")
    local cur = H:Current()
    -- History refuses a repeat of the shown chain, which would leave the highlight on the old quest
    if highlightQuestID and cur and cur.type == "chain" and cur.id == chainID then
        cur.highlight = highlightQuestID
    end
    self:CancelSearch()
    H:Push({ type = "chain", id = chainID, highlight = highlightQuestID })
    -- A quest named again is scrolled to again, even when it is the one already shown
    self._scrollAgain = highlightQuestID ~= nil
    self:RenderCurrent()
end

function CG:FindChainForQuest(questID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not Database then return nil end
    Database:EnsureGenerated()

    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end
    for _, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
        if QLS then pcall(QLS.EnsureChainItems, QLS, chain) end
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it and it.type ~= "chain" then
                    if it.id == questID then return chain.id end
                    if it.variations then
                        for v = 1, #it.variations do
                            if it.variations[v].id == questID then return chain.id end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local SEARCH_MAX_ATTEMPTS = 6
local SEARCH_RETRY_DELAY  = 0.4

local function classicSource()
    return ns:GetSubsystem("ChainGuideClassicSource")
end

function CG:SetSearchNote(text)
    local f = self.frame
    if not f then return end
    f.searchNote:SetText(text or "")
    f.searchNote:SetShown(text ~= nil)
    placeListLabel(f)
end

-- Ends the retries of an earlier search, so a late answer never lands over a newer one
function CG:CancelSearch()
    self._searchGen = (self._searchGen or 0) + 1
    self:SetSearchNote(nil)
end

function CG:RunSearch(text)
    if not (text and text ~= "") then return end
    if self.frame then self.frame.search:SetText("") end
    self:CancelSearch()
    if text:match("^%d+$") then
        self:SearchByQuestID(tonumber(text), nil, text, self._searchGen)
    else
        self:SearchByName(text, nil, self._searchGen)
    end
end

function CG:SearchMissed(text)
    self:SetSearchNote((L["No chain quest matches \"%s\"."]):format(text))
end

local function searchLive(self, gen)
    return self.frame and self.frame:IsShown() and gen == self._searchGen
end

function CG:SearchByQuestID(questID, _attempt, text, gen)
    _attempt = _attempt or 1
    local CS = classicSource()

    -- A generated chain's titles are shipped, so its search never asks the server
    if not CS and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        C_QuestLog.RequestLoadQuestByID(questID)
    end

    local chainID = self:FindChainForQuest(questID)
    if chainID then
        self:NavigateChain(chainID, questID)
        return
    end

    if not CS and _attempt < SEARCH_MAX_ATTEMPTS then
        C_Timer.After(SEARCH_RETRY_DELAY, function()
            if searchLive(self, gen) then self:SearchByQuestID(questID, _attempt + 1, text, gen) end
        end)
        return
    end

    self:SearchMissed(text or tostring(questID))
end

function CG:FindChainByName(needle)
    local CS = classicSource()
    if CS then return CS:FindByName(needle) end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    if not (Database and needle and needle ~= "") then return nil end
    needle = needle:lower()

    if QLS then
        for id in pairs(Database.categories) do QLS:EnsureZoneChains(id) end
    end

    for _, chain in pairs(Database.chains) do
        if chain.name and chain.name:lower():find(needle, 1, true) then
            return chain.id
        end
    end

    local QuestTitle = ns.Util.QuestTitle
    local reqLoad    = C_QuestLog and C_QuestLog.RequestLoadQuestByID

    for _, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
        if QLS then pcall(QLS.EnsureChainItems, QLS, chain) end
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it and it.type ~= "chain" then
                    local title = it.id and QuestTitle(it.id)
                    if title then
                        if title:lower():find(needle, 1, true) then return chain.id, it.id end
                    elseif reqLoad and it.id then
                        reqLoad(it.id)
                    end
                    if it.variations then
                        for v = 1, #it.variations do
                            local vid = it.variations[v].id
                            local vt  = vid and QuestTitle(vid)
                            if vt then
                                if vt:lower():find(needle, 1, true) then return chain.id, vid end
                            elseif reqLoad and vid then
                                reqLoad(vid)
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function CG:SearchByName(text, _attempt, gen)
    _attempt = _attempt or 1
    local chainID, questID = self:FindChainByName(text)
    if chainID then
        self:NavigateChain(chainID, questID)
        return
    end

    if not classicSource() and _attempt < SEARCH_MAX_ATTEMPTS then
        C_Timer.After(SEARCH_RETRY_DELAY, function()
            if searchLive(self, gen) then self:SearchByName(text, _attempt + 1, gen) end
        end)
        return
    end

    self:SearchMissed(text)
end

function CG:Back()
    local H = ns:GetSubsystem("ChainGuideHistory")
    self:CancelSearch()
    H:Back()
    self:RenderCurrent()
end

function CG:Forward()
    local H = ns:GetSubsystem("ChainGuideHistory")
    self:CancelSearch()
    H:Forward()
    self:RenderCurrent()
end

function CG:RenderCurrent()
    if not self.frame then return end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    Database:EnsureGenerated()
    local H = ns:GetSubsystem("ChainGuideHistory")
    local state = H:Current() or { type = "home" }

    self.frame.backBtn:SetEnabled(H:CanBack())
    self.frame.fwdBtn:SetEnabled(H:CanForward())

    local activeCatID, activeChainID
    if state.type == "category" then
        activeCatID = state.id
    elseif state.type == "chain" then
        -- A retail chain the questline source dropped, as "Show unrouted questlines" does, is looked for again first
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if not Database.chains[state.id] and QLS then
            for catID in pairs(Database.categories) do QLS:EnsureZoneChains(catID) end
        end
        local chain = Database.chains[state.id]
        activeCatID   = chain and chain.category
        activeChainID = state.id
    end

    self._activeCatID     = activeCatID
    self._activeChainID   = activeChainID
    self._activeHighlight = state.highlight

    self:RenderChains(activeCatID, activeChainID)
    self:RenderDetail(activeChainID, state.highlight)
end

function CG:GetTrackedChainID()
    local DB = ns:GetSubsystem("DB")
    local id = DB and DB.char and DB.char.trackedChainID
    local CS = ns:GetSubsystem("ChainGuideClassicSource")
    local moved = id and CS and CS:ResolveChainID(id)
    if moved and moved ~= id then
        DB.char.trackedChainID = moved
        return moved
    end
    return id
end

function CG:GetTrackedChain()
    local id = self:GetTrackedChainID()
    if not id then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not Database then return nil end
    Database:EnsureGenerated()
    if not Database.chains[id] then
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.EnsureZoneChains and Database.categories then
            for catID in pairs(Database.categories) do QLS:EnsureZoneChains(catID) end
        end
    end
    return Database.chains[id] or nil, id
end

function CG:IsTrackingChain(chainID)
    return chainID ~= nil and self:GetTrackedChainID() == chainID
end

function CG:SetTrackedChainID(chainID)
    local DB = ns:GetSubsystem("DB")
    if not (DB and DB.char) then return end
    if DB.char.trackedChainID == chainID then return end
    DB.char.trackedChainID = chainID
    self:OnTrackedChainChanged()
end

function CG:ClearTrackedChainID()
    self:SetTrackedChainID(nil)
end

function CG:OnTrackedChainChanged()
    local MP = ns:GetSubsystem("ChainGuideMapPins")
    if MP and MP.Refresh then MP:Refresh() end
    if self.frame and self.frame:IsShown() then self:RenderCurrent() end
end

function CG:RenderChains(activeCatID, activeChainID)
    local f = self.frame
    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")

    local zone = activeCatID and Database.categories[activeCatID]
    f:SetSection(zone and zone.name or nil)
    -- Its options walk every zone's chains, so the picker is read again only when the zone changes
    if activeCatID ~= self._pickerCatID then
        f.zonePicker:Refresh()
        self._pickerCatID = activeCatID
    end

    local rows = {}
    if activeCatID then
        if QLS then QLS:EnsureZoneChains(activeCatID) end
        local chains = {}
        for id, c in pairs(Database.chains) do
            if c.category == activeCatID then chains[#chains + 1] = { id = id, def = c } end
        end
        table.sort(chains, function(a, b)
            local ao, bo = a.def._campaignOrder, b.def._campaignOrder
            if ao and bo then return ao < bo end
            if ao or bo then return ao ~= nil end
            -- Generated chains read as a leveling path, lowest level first, then by name and id
            if a.def._generated and b.def._generated then
                local al = a.def.range and a.def.range[1] or math.huge
                local bl = b.def.range and b.def.range[1] or math.huge
                if al ~= bl then return al < bl end
                local an, bn = a.def.name, b.def.name
                if an ~= bn then return an < bn end
                return a.id < b.id
            end
            return (a.def.name or "") < (b.def.name or "")
        end)

        local selectedIndex
        for i = 1, #chains do
            local entry = chains[i]
            if QLS then QLS:EnsureChainItems(entry.def) end
            local name = entry.def.name or ("Chain " .. entry.id)
            local complete, _, total = Characters:ChainProgress(entry.def)
            local done = total > 0 and complete >= total
            local icons = {}
            if self:IsTrackingChain(entry.id) then icons[#icons + 1] = { name = "icon-map", color = "accentHi" } end
            if done then icons[#icons + 1] = { name = "check", color = "muted" } end
            rows[#rows + 1] = {
                key      = entry.id,
                text     = name,
                value    = total > 0 and ("%d/%d"):format(complete, total) or nil,
                selected = entry.id == activeChainID,
                muted    = done,
                icons    = icons,
                tip      = { name, total > 0 and (L["%d / %d quests done"]):format(complete, total) or nil },
            }
            if entry.id == activeChainID then selectedIndex = i end
        end
        f.list:SetRows(rows)
        -- Only a new zone or chain moves the list, so a list scrolled by hand stays put through log updates
        -- and through Back to the zone it shows
        local listKey = tostring(activeCatID) .. "/" .. tostring(activeChainID)
        if listKey ~= self._listScrolledFor then
            local stay = not selectedIndex and activeCatID == self._listZone
            if stay or f.list:ScrollToRow(selectedIndex or 1) then
                self._listScrolledFor, self._listZone = listKey, activeCatID
            end
        end
    else
        f.list:SetRows(rows)
        self._listScrolledFor, self._listZone = nil, nil
    end
end

function CG:RenderDetail(activeChainID, highlightQuestID)
    local CV = ns:GetSubsystem("ChainGuideView")
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local chain = activeChainID and Database.chains[activeChainID]
    local again = self._scrollAgain
    self._scrollAgain = nil
    CV:Render(self.frame.body, chain, highlightQuestID, again)
end
