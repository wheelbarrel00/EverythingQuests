local _, ns = ...
local L = ns.L

local HF = ns:RegisterSubsystem("HistoryFrame", {})

-- German's filter row needs 986 to keep a gap before its longest entry count (measured on Barlow)
local DEFAULT_W, DEFAULT_H, MIN_W, MIN_H, SIDEBAR_W = 1000, 660, 990, 480, 196
local SIDE_PAD, SIDE_BOTTOM, SIDE_BUTTON_GAP = 8, 12, 8
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 20, 24, 28
local BAR_TOP, BAR_BOTTOM, BAR_ROW_GAP, FIELD_H, FIELD_GAP, CHECK_GAP = 14, 12, 8, 30, 10, 16
local SEARCH_W, CHAR_W, DATE_W, TYPE_W, SORT_W, DIR_SIZE = 280, 180, 140, 150, 110, 30
-- German's "Dungeon oder Schlachtzug" is 153 px in Barlow 13, and its sort row beside the wider menu needs 1019
local CLASSIC_TYPE_W, CLASSIC_MIN_W = 200, 1020
local ROW_H, SUB_H, SUB_INDENT, ROW_ICON, ROW_GAP, INTRO_PAD = 44, 28, 64, 16, 12, 16
local GROUP_GAP, LABEL_GAP, CARD_PAD, TILE_GAP, LINE_GAP = 22, 8, 14, 14, 4
local CELL, CELL_GAP, HEATMAP_DAYS, HEATMAP_ROWS, SWATCH = 16, 3, 91, 7, 14
local CHART_H, BAR_SPACING, MAX_BARS = 160, 3, 30
local MAX_ROWS = 500
local HINT_GAP = 4
local BAR_ROOM = 10
local SEP = "  \226\128\162  "
local DASH = "\226\128\148"

local function windowCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db and DB.db.profile and DB.db.profile.historyWindow
end

local function fmtTime(t)
    if not t or t == 0 then return L["(before tracking)"] end
    return date("%Y-%m-%d %H:%M", t)
end

local function fmtMoney(copper)
    copper = copper or 0
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    return (L["%dg %ds %dc"]):format(g, s, c)
end

local function fmtBigNumber(n)
    if not n then return "0" end
    if BreakUpLargeNumbers then return BreakUpLargeNumbers(n) end
    return tostring(n)
end

local function formatMetric(key, v)
    v = v or 0
    if key == "gold" then return fmtMoney(v) end
    if key == "xp"   then return (L["%s XP"]):format(fmtBigNumber(v)) end
    return fmtBigNumber(v) .. (v == 1 and " quest" or " quests")
end

-- A sign, not a color: the library has no green, and its red means danger
local function fmtDelta(key, d)
    if d == 0 then return "no change" end
    -- On the number, since some languages put their word for XP first
    local sign = d > 0 and "+" or "-"
    if key == "gold" then return sign .. fmtMoney(math.abs(d)) end
    local mag = sign .. fmtBigNumber(math.abs(d))
    if key == "xp" then return (L["%s XP"]):format(mag) end
    return mag
end

local function ui()
    return HF._ctx
end

HF._pools, HF._active = {}, {}

local function release(page)
    local active = HF._active[page]
    if not active then return end
    for kind, list in pairs(active) do
        local pool = HF._pools[page .. kind]
        for i = #list, 1, -1 do
            local w = list[i]
            w:Hide()
            w:ClearAllPoints()
            pool[#pool + 1] = w
            list[i] = nil
        end
    end
end

local function acquire(page, kind, make)
    local key = page .. kind
    HF._pools[key] = HF._pools[key] or {}
    HF._active[page] = HF._active[page] or {}
    HF._active[page][kind] = HF._active[page][kind] or {}
    local w = table.remove(HF._pools[key]) or make()
    w:Show()
    local list = HF._active[page][kind]
    list[#list + 1] = w
    return w
end

local function findChainForQuest(questID)
    -- WoW Forever's chains exist only once built, and ChainForQuest builds them first
    local Classic = ns:GetSubsystem("ChainGuideClassicSource")
    if Classic then return Classic:ChainForQuest(questID) end

    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local QLS      = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS       = ns:GetSubsystem("ChainGuideCampaignSource")
    if not (Database and Database.chains) then return nil end

    if Database.categories then
        for catID in pairs(Database.categories) do
            if QLS and QLS.EnsureZoneChains    then QLS:EnsureZoneChains(catID)    end
            if CS  and CS.EnsureCampaignChains then CS:EnsureCampaignChains(catID) end
        end
    end
    if QLS and QLS.EnsureChainItems then
        for _, chain in pairs(Database.chains) do QLS:EnsureChainItems(chain) end
    end

    for chainID, chain in pairs(Database.chains) do
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it and it.type == "quest" then
                    if it.id == questID then return chainID end
                    for _, v in ipairs(it.variations or {}) do
                        if v.id == questID then return chainID end
                    end
                end
            end
        end
    end
    return nil
end

local function openChain(chainID, questID)
    local CG = ns:GetSubsystem("ChainGuide")
    if not CG then return end
    if CG.Open          then CG:Open()                         end
    if CG.NavigateChain then CG:NavigateChain(chainID, questID) end
end

local function setResizeHintSeen(f)
    local cfg = windowCfg()
    if cfg then cfg.resizeHintSeen = true end
    if f.resizeHint then f.resizeHint:Hide() end
end

local function rowButton(ctx, parent, height)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(height)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(ctx:Color("hover"))
    ctx:Paint(r, nil, "divider", "B")
    r:SetScript("OnLeave", function() ctx:HideTooltip() end)
    return r
end

local function dropdownOptions(list)
    local out = {}
    for _, o in ipairs(list) do out[#out + 1] = { value = o[1], label = o[2] } end
    return out
end

local DATE_OPTIONS = {
    { "all", L["All time"] }, { "today", L["Today"] }, { "7d", L["Past 7 days"] }, { "30d", L["Past 30 days"] },
}
local TYPE_OPTIONS = {
    { "all", L["All types"] }, { "campaign", L["Campaign"] }, { "questline", L["Questline"] },
    { "calling", L["Calling"] }, { "recurring", L["Recurring"] }, { "worldquest", L["World Quest"] }, { "other", L["Other"] },
}
-- The Quest Browser's own tag names, so both windows use the same words
local CLASSIC_TYPE_OPTIONS = {
    { "all", L["All types"] }, { "dungeon", L["Dungeon or raid"] }, { "event", L["World event"] },
    { "class", L["Class quest"] }, { "profession", L["Profession"] }, { "repeatable", L["Repeatable"] }, { "other", L["Other"] },
}
local SORT_OPTIONS = { { "date", L["Date"] }, { "name", L["Name"] }, { "type", L["Type"] } }

local function classicTypes()
    local R = ns:GetSubsystem("History")
    return R and R.UsesClassicTypes and R:UsesClassicTypes() or false
end

local function typeOptions()
    return classicTypes() and CLASSIC_TYPE_OPTIONS or TYPE_OPTIONS
end

local function nameOf(e)
    local R = ns:GetSubsystem("History")
    return (R and R.NameOf and R:NameOf(e)) or e.n
end

local function exportType(e)
    if not classicTypes() then return e.k or "?" end
    local R = ns:GetSubsystem("History")
    return R:TypeOf(e)
end

local function questTitle(questID)
    local t = ns.Util.QuestTitle(questID)
    if t then return t end
    local R = ns:GetSubsystem("History")
    return R and R.NameOf and R:NameOf({ q = questID }) or nil
end

local function characterOptions()
    local R = ns:GetSubsystem("History")
    local out = { { value = "all", label = L["All characters"] } }
    if R then
        for _, c in ipairs(R:GetCharacters()) do out[#out + 1] = { value = c, label = c } end
    end
    return out
end

local function syncSortArrow(b)
    local up = (HF._sortDir or "desc") == "asc"
    for _, t in ipairs({ b:GetNormalTexture(), b:GetDisabledTexture() }) do
        if up then t:SetTexCoord(0, 1, 1, 0) else t:SetTexCoord(0, 1, 0, 1) end
    end
end

local function debounced(key, fn)
    local Events = ns:GetSubsystem("Events")
    if Events and Events.Debounce then Events:Debounce(key, 0.2, fn) else fn() end
end

local function buildQuestsPage(ctx, page)
    local bar = CreateFrame("Frame", nil, page)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar:SetHeight(BAR_TOP + FIELD_H + BAR_ROW_GAP + FIELD_H + BAR_BOTTOM)
    bar._controls = {}
    ctx:Paint(bar, nil, "divider", "B")
    page.bar = bar

    page.search = ctx:CreateSearchField(bar, L["Find quest"], function() HF:Render() end)
    page.search:SetPoint("TOPLEFT", bar, "TOPLEFT", PAD_SIDE, -BAR_TOP)
    page.search:SetWidth(SEARCH_W)
    page.search.box:HookScript("OnTextChanged", function(_, userInput)
        if userInput then debounced("eq.history.search", function() HF:Render() end) end
    end)

    page.hideUndated = ctx:CreateCheckbox(bar, L["Hide undated  |cffaaaaaa(backfilled)|r"],
        function() return HF._hideBackfilled == true end,
        function(v) HF._hideBackfilled = v and true or nil; HF:Render() end)
    page.hideUndated:SetPoint("LEFT", page.search, "RIGHT", CHECK_GAP, 0)

    page.count = ctx:CreateText(bar, "", "hint")
    page.count:SetPoint("RIGHT", bar, "TOPRIGHT", -PAD_SIDE, -(BAR_TOP + FIELD_H / 2))

    local function dd(options, width, getter, setter, anchor)
        local d = ctx:CreateDropdown(bar, nil, options, getter, setter)
        d:SetWidth(width)
        if anchor then d:SetPoint("LEFT", anchor, "RIGHT", FIELD_GAP, 0)
        else d:SetPoint("TOPLEFT", page.search, "BOTTOMLEFT", 0, -BAR_ROW_GAP) end
        return d
    end
    page.char = dd(characterOptions, CHAR_W, function() return HF._charFilter or "all" end,
        function(v) HF._charFilter = v; HF:Render() end)
    page.date = dd(function() return dropdownOptions(DATE_OPTIONS) end, DATE_W,
        function() return HF._dateFilter or "all" end, function(v) HF._dateFilter = v; HF:Render() end, page.char)
    page.type = dd(function() return dropdownOptions(typeOptions()) end, classicTypes() and CLASSIC_TYPE_W or TYPE_W,
        function() return HF._classFilter or "all" end, function(v) HF._classFilter = v; HF:Render() end, page.date)
    page.sortLabel = ctx:CreateText(bar, L["Sort:"], "label")
    page.sortLabel:SetPoint("LEFT", page.type, "RIGHT", CHECK_GAP, 0)
    page.sort = ctx:CreateDropdown(bar, nil, function() return dropdownOptions(SORT_OPTIONS) end,
        function() return HF._sortBy or "date" end, function(v) HF._sortBy = v; HF:Render() end)
    page.sort:SetWidth(SORT_W)
    page.sort:SetPoint("LEFT", page.sortLabel, "RIGHT", FIELD_GAP, 0)
    page.dir = ctx:CreateIconButton(bar, "chevron-down", DIR_SIZE)
    page.dir:SetPoint("LEFT", page.sort, "RIGHT", LINE_GAP, 0)
    ctx:AttachTooltip(page.dir, L["Sort direction"], L["Click to flip ascending / descending."])
    page.dir:SetScript("OnClick", function(b)
        HF._sortDir = ((HF._sortDir or "desc") == "desc") and "asc" or "desc"
        syncSortArrow(b)
        HF:Render()
    end)
    syncSortArrow(page.dir)

    page.area = ctx:CreateScrollArea(page, { clearGrip = true })
    page.area:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
    page.area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
    page.empty = ctx:CreateEmptyState(page.area, L["(no matching quests)"])
    page.empty:SetPoint("TOP", page.area, "CENTER", 0, 8)
end

local function buildIntroPage(ctx, page, intro)
    page.intro = ctx:CreateText(page, intro, "hint")
    page.intro:SetPoint("TOPLEFT", page, "TOPLEFT", PAD_SIDE, -INTRO_PAD)
    page.intro:SetPoint("TOPRIGHT", page, "TOPRIGHT", -PAD_SIDE, -INTRO_PAD)
    page.intro:SetWordWrap(true)
    page.head = CreateFrame("Frame", nil, page)
    page.head:SetPoint("TOPLEFT")
    page.head:SetPoint("TOPRIGHT")
    page.head:SetHeight(INTRO_PAD * 2 + 15)
    ctx:Paint(page.head, nil, "divider", "B")
    page.area = ctx:CreateScrollArea(page, { clearGrip = true })
    page.area:SetPoint("TOPLEFT", page.head, "BOTTOMLEFT")
    page.area:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
end

function HF:Build()
    if self.frame then return end
    local Options = ns:GetSubsystem("Options")
    local ctx = Options.ui
    self._ctx = ctx

    local f = ctx:CreateWindow({
        name = "EQHistoryFrame", title = L["Quest History"],
        width = DEFAULT_W, height = DEFAULT_H, minHeight = MIN_H,
        minWidth = classicTypes() and CLASSIC_MIN_W or MIN_W,
        sidebarWidth = SIDEBAR_W, gripTip = L["Drag to resize"],
        getSize = function()
            local cfg = windowCfg()
            if cfg then return cfg.width, cfg.height end
        end,
        setSize = function(w, h)
            local cfg = windowCfg()
            if cfg then cfg.width, cfg.height = w, h end
        end,
        getMaximized = function()
            local cfg = windowCfg()
            return cfg and cfg.maximized or false
        end,
        setMaximized = function(on)
            local cfg = windowCfg()
            if cfg then cfg.maximized = on or nil end
        end,
        onResize = function(win)
            setResizeHintSeen(win)
            self:Render()
        end,
    })
    self.frame = f

    f.resizeHint = ctx:CreateText(f.grip, L["Drag to resize"], "hint")
    f.resizeHint:SetPoint("RIGHT", f.grip, "LEFT", -HINT_GAP, 0)
    local cfg = windowCfg()
    if cfg and cfg.resizeHintSeen then f.resizeHint:Hide() end

    self._pages = {
        { id = "quests",   title = L["Quests"],         icon = ctx:Texture("icon-history") },
        { id = "timeline", title = L["Chain Timeline"], icon = ctx:Texture("icon-chain") },
        { id = "stats",    title = L["Stats"],          icon = ctx:Texture("icon-stats") },
    }
    f.nav = ctx:CreateNav(f.sidebar, self._pages, function(id) self:SwitchTab(id) end)

    local width = SIDEBAR_W - SIDE_PAD * 2
    f.export = ctx:CreateButton(f.sidebar, L["Export"], width, function() self:_openExportPopup() end)
    f.export:SetPoint("BOTTOMLEFT", f.sidebar, "BOTTOMLEFT", SIDE_PAD, SIDE_BOTTOM)
    f.rescan = ctx:CreateButton(f.sidebar, L["Re-scan names"], width, function()
        local R = ns:GetSubsystem("History")
        if not R then return end
        local queued = R:RequestMissingTitles() or 0
        if queued > 0 then
            print((L["|cffEBB706EQ History:|r requested %d quest name%s from the server. Names will fill in over the next minute or two."]):format(
                queued, queued == 1 and "" or "s"))
        else
            print(L["|cffEBB706EQ History:|r nothing left to look up — every entry that can be resolved already is."])
        end
    end)
    f.rescan:SetPoint("BOTTOMLEFT", f.export, "TOPLEFT", 0, SIDE_BUTTON_GAP)
    ctx:AttachTooltip(f.rescan, L["Re-scan for quest names"],
        L["Asks the server for the name of any \"Quest #12345\" entries. They'll fill in over the next minute or two as responses arrive."])

    self._views = {}
    for _, p in ipairs(self._pages) do
        local view = CreateFrame("Frame", nil, f.body)
        view:SetAllPoints(f.body)
        view:Hide()
        self._views[p.id] = view
    end
    buildQuestsPage(ctx, self._views.quests)
    buildIntroPage(ctx, self._views.timeline,
        L["Chains where you have at least one completed quest. Click a chain to expand and see per-quest completion dates."])
    self._views.timeline.empty = ctx:CreateEmptyState(self._views.timeline.area, L["(no chain quests recorded yet)"])
    self._views.timeline.empty:SetPoint("TOP", self._views.timeline.area, "CENTER", 0, 8)
    local stats = self._views.stats
    stats.area = ctx:CreateScrollArea(stats, { clearGrip = true })
    stats.area:SetAllPoints(stats)
    stats.area.content._controls = {}

    self._timelineOpen = self._timelineOpen or {}
    self._trendGran, self._trendMetric, self._trendCharFilter = "daily", "gold", "all"
    self:SwitchTab("quests")
end

function HF:SwitchTab(id)
    if not self._views then return end
    for key, view in pairs(self._views) do view:SetShown(key == id) end
    self.frame.nav:Select(id)
    for _, p in ipairs(self._pages) do
        if p.id == id then self.frame:SetSection(p.title) end
    end
    self._activeTab = id
    self:Render()
end

function HF:IsShowing(page)
    return self.frame ~= nil and self.frame:IsShown() and self._activeTab == page
end

local function areaWidth(area)
    local w = area.scroll:GetWidth() or 0
    if w <= 0 then w = (HF.frame.body:GetWidth() or 0) - BAR_ROOM end
    if w <= 0 then w = DEFAULT_W - SIDEBAR_W - BAR_ROOM end
    return w
end

local function questRow(ctx, content)
    local r = rowButton(ctx, content, ROW_H)
    r.t1 = ctx:CreateText(r, "", "label")
    r.t1:SetPoint("TOPLEFT", r, "TOPLEFT", PAD_SIDE, -6)
    r.t1:SetWordWrap(false)
    r.t2 = ctx:CreateText(r, "", "hint")
    r.t2:SetPoint("TOPLEFT", r.t1, "BOTTOMLEFT", 0, -2)
    r.t2:SetWordWrap(false)
    r.right = ctx:CreateText(r, "", "hint")
    r.right:SetPoint("RIGHT", r, "RIGHT", -PAD_SIDE, 0)
    r.t1:SetPoint("RIGHT", r.right, "LEFT", -ROW_GAP, 0)
    r.t2:SetPoint("RIGHT", r.right, "LEFT", -ROW_GAP, 0)
    r:SetScript("OnEnter", function(self)
        local lines = {}
        if self._held and self._held > 0 and self._accepted then
            lines[#lines + 1] = (L["Accepted %1$s, held %2$s"]):format(fmtTime(self._accepted), ns.Util.FmtDurationLong(self._held))
        end
        lines[#lines + 1] = L["Right-click to open in the Chain Guide"]
        ctx:ShowTooltip(self, self._fullName or ("Quest #" .. tostring(self._questID)), table.concat(lines, "\n"))
    end)
    r:SetScript("OnClick", function(self, button)
        if button ~= "RightButton" then return end
        local chainID = findChainForQuest(self._questID)
        if chainID then
            openChain(chainID, self._questID)
        else
            print((L["|cffEBB706EQ History|r: |cffffffff%s|r isn't part of any chain in the Chain Guide."]):format(
                self._fullName or ("Quest #" .. tostring(self._questID))))
        end
    end)
    return r
end

local function queryEntries()
    local R = ns:GetSubsystem("History")
    if not R then return {} end
    local page = HF._views.quests
    return R:Query({
        search         = page.search:GetText(),
        char           = HF._charFilter,
        dateRange      = HF._dateFilter,
        classification = HF._classFilter,
        hideBackfilled = HF._hideBackfilled,
        sortBy         = HF._sortBy or "date",
        sortDir        = HF._sortDir or "desc",
    })
end

function HF:_renderQuests()
    local ctx = ui()
    local page = self._views.quests
    release("quests")
    local entries = queryEntries()
    local n = #entries
    page.count:SetText((L["%d entries"]):format(n))
    page.empty:SetShown(n == 0)
    local content = page.area.content
    local width = areaWidth(page.area)
    local shown = math.min(n, MAX_ROWS)
    for i = 1, shown do
        local e = entries[i]
        local r = acquire("quests", "row", function() return questRow(ctx, content) end)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((i - 1) * ROW_H))
        local name = nameOf(e)
        r.t1:SetText(name or ("Quest #" .. tostring(e.q)))
        r.t1:SetTextColor(ctx:Color((e.t and e.t > 0) and "text" or "muted"))
        local meta = e.c or ""
        if e.z and e.z ~= "" then meta = meta .. SEP .. e.z end
        if e.d and e.d > 0 then meta = meta .. SEP .. (L["held for %s"]):format(ns.Util.FmtDurationLong(e.d)) end
        r.t2:SetText(meta)
        r.right:SetText(fmtTime(e.t))
        r._questID, r._fullName, r._held = e.q, name, e.d
        r._accepted = (e.t and e.t > 0 and e.d) and (e.t - e.d) or nil
    end
    if n > MAX_ROWS then
        local which = L["first"]
        if (self._sortBy or "date") == "date" then
            which = (self._sortDir == "asc") and L["oldest"] or L["newest"]
        end
        page.count:SetText((L["%d entries (showing %s %d)"]):format(n, which, MAX_ROWS))
    end
    page.area:SetContentSize(width, math.max(1, shown * ROW_H))
end

local function timelineChains()
    local R         = ns:GetSubsystem("History")
    local Database  = ns:GetSubsystem("ChainGuideDatabase")
    local QLS       = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS        = ns:GetSubsystem("ChainGuideCampaignSource")
    if not (R and Database) then return {}, {} end

    if Database.EnsureGenerated then Database:EnsureGenerated() end
    if Database.categories then
        for catID in pairs(Database.categories) do
            if QLS and QLS.EnsureZoneChains    then QLS:EnsureZoneChains(catID)    end
            if CS  and CS.EnsureCampaignChains then CS:EnsureCampaignChains(catID) end
        end
    end
    if QLS and QLS.EnsureChainItems then
        for _, chain in pairs(Database.chains) do QLS:EnsureChainItems(chain) end
    end

    local completion = R:CompletionMap()
    local sorted = {}
    for chainID, chain in pairs(Database.chains) do
        local items = chain.items
        if items and #items > 0 then
            local doneN, latest, questTotal = 0, 0, 0
            for i = 1, #items do
                local it = items[i]
                if it and it.type == "quest" then
                    questTotal = questTotal + 1
                    local t = completion[it.id]
                    if t then
                        doneN = doneN + 1
                        if t > latest then latest = t end
                    end
                end
            end
            if doneN > 0 then
                sorted[#sorted + 1] = { id = chainID, chain = chain, doneN = doneN, latest = latest, total = questTotal }
            end
        end
    end
    table.sort(sorted, function(a, b)
        if a.latest ~= b.latest then return a.latest > b.latest end
        return (a.chain.name or "") < (b.chain.name or "")
    end)
    return sorted, completion
end

local function chainRow(ctx, content)
    local r = rowButton(ctx, content, ROW_H)
    r.chev = r:CreateTexture(nil, "ARTWORK")
    r.chev:SetSize(ROW_ICON, ROW_ICON)
    r.chev:SetPoint("LEFT", r, "LEFT", PAD_SIDE, 0)
    r.chev:SetVertexColor(ctx:Color("navText"))
    r.t1 = ctx:CreateText(r, "", "label")
    r.t1:SetPoint("TOPLEFT", r.chev, "TOPRIGHT", ROW_GAP, 8)
    r.t1:SetTextColor(ctx:Color("text"))
    r.t1:SetWordWrap(false)
    r.t2 = ctx:CreateText(r, "", "hint")
    r.t2:SetPoint("TOPLEFT", r.t1, "BOTTOMLEFT", 0, -2)
    r.right = ctx:CreateText(r, "", "hint")
    r.right:SetPoint("RIGHT", r, "RIGHT", -PAD_SIDE, 0)
    r.check = r:CreateTexture(nil, "ARTWORK")
    r.check:SetSize(ROW_ICON, ROW_ICON)
    r.check:SetTexture(ctx:Texture("check"))
    r.check:SetVertexColor(ctx:Color("accentHi"))
    r.check:SetPoint("RIGHT", r.right, "LEFT", -ROW_GAP, 0)
    r.t1:SetPoint("RIGHT", r.check, "LEFT", -ROW_GAP, 0)
    r:SetScript("OnEnter", function(self)
        ctx:ShowTooltip(self, self._chainName or L["Chain"], L["Click to expand"] .. "\n" .. L["Right-click to open in the Chain Guide"])
    end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            openChain(self._chainID)
            return
        end
        HF._timelineOpen[self._chainID] = not HF._timelineOpen[self._chainID]
        HF:_renderTimeline()
    end)
    return r
end

local function subRow(ctx, content)
    local r = CreateFrame("Frame", nil, content)
    r:SetHeight(SUB_H)
    ctx:Paint(r, nil, "divider", "B")
    r.t1 = ctx:CreateText(r, "", "label")
    r.t1:SetPoint("LEFT", r, "LEFT", SUB_INDENT, 0)
    r.t1:SetWordWrap(false)
    r.right = ctx:CreateText(r, "", "hint")
    r.right:SetPoint("RIGHT", r, "RIGHT", -PAD_SIDE, 0)
    r.t1:SetPoint("RIGHT", r.right, "LEFT", -ROW_GAP, 0)
    return r
end

function HF:_renderTimeline()
    local ctx = ui()
    local page = self._views.timeline
    release("timeline")
    local sorted, completion = timelineChains()
    page.empty:SetShown(#sorted == 0)
    local content = page.area.content
    local y = 0
    for _, rec in ipairs(sorted) do
        local open = self._timelineOpen[rec.id]
        local r = acquire("timeline", "chain", function() return chainRow(ctx, content) end)
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        r:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
        r.chev:SetTexture(ctx:Texture(open and "chevron-down" or "chevron-right"))
        r.t1:SetText(rec.chain.name or ("Chain #" .. tostring(rec.id)))
        r.t2:SetText((L["%d of %d quests recorded"]):format(rec.doneN, rec.total))
        r.right:SetText(fmtTime(rec.latest))
        r.check:SetShown(rec.doneN >= rec.total)
        r._chainID, r._chainName = rec.id, rec.chain.name
        y = y + ROW_H
        if open then
            for _, it in ipairs(rec.chain.items) do
                if it and it.type == "quest" then
                    local sub = acquire("timeline", "sub", function() return subRow(ctx, content) end)
                    sub:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
                    sub:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                    local t = completion[it.id]
                    sub.t1:SetText(questTitle(it.id) or it.name or ("Quest #" .. tostring(it.id)))
                    sub.t1:SetTextColor(ctx:Color(t and "label" or "muted"))
                    sub.right:SetText(t and fmtTime(t) or DASH)
                    y = y + SUB_H
                end
            end
        end
    end
    page.area:SetContentSize(areaWidth(page.area), math.max(1, y))
end

local function mix(ctx, from, to, t)
    local fr, fg, fb = ctx:Color(from)
    local tr, tg, tb = ctx:Color(to)
    return fr + (tr - fr) * t, fg + (tg - fg) * t, fb + (tb - fb) * t
end

-- Five steps from an empty cell to the accent, the color a progress bar fills with
local function heatColor(ctx, step)
    if step <= 0 then return ctx:Color("track") end
    return mix(ctx, "track", "accent", 0.25 + step * 0.1875)
end

local _y, _cardW

-- Each card owns its pieces, pooled by kind, so after the first render nothing new is made
local function cardPiece(card, kind, make)
    local pool = card._pool[kind]
    if not pool then pool = {} card._pool[kind] = pool end
    local n = (card._used[kind] or 0) + 1
    card._used[kind] = n
    local w = pool[n]
    if not w then w = make() pool[n] = w end
    w:Show()
    return w
end

local function resetCard(card)
    for _, pool in pairs(card._pool) do
        for i = 1, #pool do
            pool[i]:Hide()
            pool[i]:ClearAllPoints()
        end
    end
    card._used = {}
end

local function statsGroup(ctx, content, key, title, build)
    local stats = HF._views.stats
    stats.cards = stats.cards or {}
    local slot = stats.cards[key]
    if not slot then
        slot = { label = ctx:CreateText(content, "", "groupLabel"), card = CreateFrame("Frame", nil, content) }
        ctx:Paint(slot.card, "surface", "surfaceBorder")
        slot.card._controls, slot.card._pool, slot.card._used = {}, {}, {}
        stats.cards[key] = slot
    end
    _y = _y + ((_y > PAD_TOP) and GROUP_GAP or 0)
    slot.label:ClearAllPoints()
    slot.label:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    slot.label:SetText(title)
    _y = _y + (slot.label:GetStringHeight() or 12) + LABEL_GAP
    local card = slot.card
    resetCard(card)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    card:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -_y)
    local h = build(card) + CARD_PAD
    card:SetHeight(h)
    _y = _y + h
end

-- Each style's own color, set on every use, so a pooled string a row recolored never keeps it
local function colorOf(style)
    if style == "hint" or style == "groupLabel" then return "muted" end
    if style == "label" then return "label" end
    return "text"
end

local function text(ctx, card, style, str, x, y, width)
    local fs = cardPiece(card, "text_" .. style, function() return ctx:CreateText(card, "", style) end)
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
    if width then fs:SetWidth(width) fs:SetWordWrap(true) else fs:SetWordWrap(false) end
    fs:SetText(str)
    fs:SetTextColor(ctx:Color(colorOf(style)))
    return fs
end

-- A row of figures: each a muted label over its number, the tiles parted by a divider
local function tiles(ctx, card, list, y, perRow)
    perRow = perRow or 3
    local w = (_cardW - CARD_PAD * 2) / perRow
    local rowH = 0
    for i, t in ipairs(list) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        local x = CARD_PAD + col * w + (col > 0 and TILE_GAP or 0)
        local ty = y + row * (rowH + TILE_GAP)
        local label = text(ctx, card, "hint", t[1], x, ty, w - TILE_GAP * 2)
        local value = text(ctx, card, "figure", t[2], x, ty + (label:GetStringHeight() or 12) + LINE_GAP)
        local h = (label:GetStringHeight() or 12) + LINE_GAP + (value:GetStringHeight() or 22)
        if t[3] then
            local delta = text(ctx, card, "label", t[3], x, ty + h + LINE_GAP)
            h = h + LINE_GAP + (delta:GetStringHeight() or 13)
        end
        if col > 0 then
            local div = cardPiece(card, "vdiv", function()
                local d = card:CreateTexture(nil, "BORDER")
                d:SetColorTexture(ctx:Color("divider"))
                d:SetWidth(1)
                return d
            end)
            div:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + col * w, -ty)
            div:SetHeight(h)
        end
        rowH = math.max(rowH, h)
    end
    local rows = math.ceil(#list / perRow)
    return y + rows * rowH + (rows - 1) * TILE_GAP
end

local function streakCard(ctx, card)
    local R = ns:GetSubsystem("History")
    local s = R and R:Streak() or { current = 0, best = 0, total = 0 }
    local y = tiles(ctx, card, {
        { L["Current daily streak"], (L["%d days"]):format(s.current) },
        { L["Best daily streak"], (L["%d days"]):format(s.best) },
        { L["Total quests recorded with a date"], fmtBigNumber(s.total) },
    }, CARD_PAD)
    local note = text(ctx, card, "hint",
        L["Streak counts consecutive days (local time) with at least one quest turn-in across any character on the account. Today or yesterday keeps the streak alive - you don't lose it until a whole day passes with no activity."],
        CARD_PAD, y + TILE_GAP, _cardW - CARD_PAD * 2)
    return y + TILE_GAP + (note:GetStringHeight() or 15)
end

local function cellTip(self)
    if not self._day then return end
    local c = self._count or 0
    ui():ShowTooltip(self, date("!%A, %Y-%m-%d", self._day * 86400), (L["%d quest%s turned in"]):format(c, c == 1 and "" or "s"))
end

local function activityCard(ctx, card)
    local R = ns:GetSubsystem("History")
    local intro = text(ctx, card, "hint",
        (L["Quest turn-ins per day over the last %d days. Brighter = busier. Hover a cell for the date and count. The bottom-right cell is today."]):format(HEATMAP_DAYS - 1),
        CARD_PAD, CARD_PAD, _cardW - CARD_PAD * 2)
    local y = CARD_PAD + (intro:GetStringHeight() or 15) + TILE_GAP
    local counts, today = {}, 0
    if R and R.DayCounts then counts, today = R:DayCounts(HEATMAP_DAYS) end
    local maxCount, total, busiestDay, busiestCount = 0, 0, nil, 0
    for d, c in pairs(counts) do
        total = total + c
        if c > maxCount then maxCount = c end
        if c > busiestCount then busiestCount, busiestDay = c, d end
    end
    for i = 1, HEATMAP_DAYS do
        local cell = cardPiece(card, "cell", function()
            local c = CreateFrame("Frame", nil, card)
            c:SetSize(CELL, CELL)
            c.fill = c:CreateTexture(nil, "ARTWORK")
            c.fill:SetAllPoints()
            c:EnableMouse(true)
            c:SetScript("OnEnter", cellTip)
            c:SetScript("OnLeave", function() ui():HideTooltip() end)
            return c
        end)
        local col = math.floor((i - 1) / HEATMAP_ROWS)
        local row = (i - 1) % HEATMAP_ROWS
        cell:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD + col * (CELL + CELL_GAP), -(y + row * (CELL + CELL_GAP)))
        local day = today - (HEATMAP_DAYS - i)
        local count = counts[day] or 0
        cell._day, cell._count = day, count
        local step = 0
        if count > 0 then step = math.max(1, math.min(4, math.ceil(count / math.max(maxCount, 1) * 4))) end
        cell.fill:SetColorTexture(heatColor(ctx, step))
    end
    y = y + HEATMAP_ROWS * (CELL + CELL_GAP) - CELL_GAP + TILE_GAP
    local less = text(ctx, card, "hint", L["Less"], CARD_PAD, y)
    local x = CARD_PAD + (less:GetStringWidth() or 24) + LINE_GAP
    for step = 0, 4 do
        local sw = cardPiece(card, "swatch", function() return card:CreateTexture(nil, "ARTWORK") end)
        sw:SetSize(SWATCH, SWATCH)
        sw:SetPoint("TOPLEFT", card, "TOPLEFT", x, -y)
        sw:SetColorTexture(heatColor(ctx, step))
        x = x + SWATCH + LINE_GAP
    end
    text(ctx, card, "hint", L["More"], x, y)
    y = y + SWATCH + TILE_GAP
    local fig = text(ctx, card, "figure", fmtBigNumber(total), CARD_PAD, y)
    local figH = fig:GetStringHeight() or 22
    text(ctx, card, "hint", (L["total turn-ins in the last %d days"]):format(HEATMAP_DAYS - 1), CARD_PAD, y + figH + LINE_GAP)
    y = y + figH + LINE_GAP + 15
    if busiestDay and busiestCount > 0 then
        local b = text(ctx, card, "label", (L["Busiest day: %s (%d quests)"]):format(date("!%Y-%m-%d", busiestDay * 86400), busiestCount), CARD_PAD, y + LINE_GAP)
        y = y + LINE_GAP + (b:GetStringHeight() or 13)
    end
    return y
end

local function keyValueRows(ctx, card, rows, y)
    for i, r in ipairs(rows) do
        local left = text(ctx, card, "label", r[1], CARD_PAD, y + 7)
        left:SetTextColor(ctx:Color("text"))
        local right = cardPiece(card, "right", function() return ctx:CreateText(card, "", "hint") end)
        right:SetPoint("RIGHT", card, "TOPRIGHT", -CARD_PAD, -(y + 14))
        right:SetText(r[2])
        if i > 1 then
            local div = cardPiece(card, "hdiv", function()
                local d = card:CreateTexture(nil, "BORDER")
                d:SetColorTexture(ctx:Color("divider"))
                d:SetHeight(1)
                return d
            end)
            div:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
            div:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
        end
        y = y + 28
    end
    return y
end

local function byCount(a, b)
    if a.rec.count ~= b.rec.count then return a.rec.count > b.rec.count end
    return a.key < b.key
end

local function totalsCard(ctx, card)
    local R = ns:GetSubsystem("History")
    if not (R and R.Totals) then return CARD_PAD end
    local t = R:Totals()
    local abandoned, avg = DASH, DASH
    -- A zero here would read as "you abandoned none" when recording was simply switched off
    if t.recording ~= false then
        abandoned = fmtBigNumber(t.abandoned or 0)
        if t.avgHeld and (t.heldCount or 0) > 0 then
            -- The count is shown because the average covers only quests seen accepted, not every quest in the totals beside it
            avg = (L["%1$s   |cffaaaaaa(%2$d quests)|r"]):format(ns.Util.FmtDurationLong(t.avgHeld), t.heldCount)
        end
    end
    local y = tiles(ctx, card, {
        { L["Total quests with reward data"], fmtBigNumber(t.rewardCount) },
        { L["Total gold earned"], fmtMoney(t.totalMoney) },
        { L["Total XP earned"], (L["%s XP"]):format(fmtBigNumber(t.totalXP)) },
        { L["Total quests abandoned"], abandoned },
        { L["Average time"], avg },
    }, CARD_PAD)
    local chars = {}
    for k, v in pairs(t.byChar) do chars[#chars + 1] = { key = k, rec = v } end
    table.sort(chars, byCount)
    y = y + TILE_GAP * 2
    text(ctx, card, "groupLabel", L["By character"], CARD_PAD, y)
    y = y + 14 + LABEL_GAP
    local rows = {}
    for _, c in ipairs(chars) do
        rows[#rows + 1] = { c.key, (L["%d quests"]):format(c.rec.count) .. SEP .. fmtMoney(c.rec.money) .. SEP
            .. (L["%s XP"]):format(fmtBigNumber(c.rec.xp)) }
    end
    y = keyValueRows(ctx, card, rows, y)
    local top = {}
    if t.topGold then top[#top + 1] = { nameOf(t.topGold) or ("Quest #" .. tostring(t.topGold.q)), fmtMoney(t.topGold.m) } end
    if t.topXP then top[#top + 1] = { nameOf(t.topXP) or ("Quest #" .. tostring(t.topXP.q)), (L["%s XP"]):format(fmtBigNumber(t.topXP.xp)) } end
    if #top == 0 then return y end
    y = y + TILE_GAP
    text(ctx, card, "groupLabel", L["Top single-quest rewards"], CARD_PAD, y)
    y = y + 14 + LABEL_GAP
    return keyValueRows(ctx, card, top, y)
end

local function barTip(self)
    if not self._rangeText then return end
    ui():ShowTooltip(self, self._rangeText, self._valueText)
end

local function trendsCard(ctx, card)
    local R = ns:GetSubsystem("History")
    if not (R and R.Trends) then return CARD_PAD end
    local stats = HF._views.stats
    -- Built once, on this card, which is made once too
    if not stats.gran then
        stats.gran = ctx:CreateRadioGroup(card, nil, { { value = "daily", label = L["Daily"] }, { value = "weekly", label = L["Weekly"] } },
            function() return HF._trendGran end, function(v) HF._trendGran = v; HF:_renderStats() end, 9999)
        stats.showLabel = ctx:CreateText(card, L["Show:"], "label")
        stats.charDD = ctx:CreateDropdown(card, nil, characterOptions, function() return HF._trendCharFilter or "all" end,
            function(v) HF._trendCharFilter = v; HF:_renderStats() end)
        stats.charDD:SetWidth(CHAR_W)
        stats.metric = ctx:CreateRadioGroup(card, nil, { { value = "count", label = L["Quests"] }, { value = "xp", label = L["XP"] },
            { value = "gold", label = L["Gold"] } }, function() return HF._trendMetric end, function(v) HF._trendMetric = v; HF:_renderStats() end, 9999)
        stats.chart = CreateFrame("Frame", nil, card)
        stats.chart:SetHeight(CHART_H)
        ctx:Paint(stats.chart, nil, "track", "B")
        stats.bars = {}
        for i = 1, MAX_BARS do
            local b = CreateFrame("Frame", nil, stats.chart)
            b.fill = b:CreateTexture(nil, "ARTWORK")
            b.fill:SetAllPoints()
            b:EnableMouse(true)
            b:SetScript("OnEnter", barTip)
            b:SetScript("OnLeave", function() ui():HideTooltip() end)
            stats.bars[i] = b
        end
        stats.axisL = ctx:CreateText(card, "", "hint")
        stats.axisR = ctx:CreateText(card, "", "hint")
    end
    for _, w in ipairs({ stats.gran, stats.showLabel, stats.charDD, stats.metric, stats.chart, stats.axisL, stats.axisR }) do
        w:ClearAllPoints()
    end
    stats.gran:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
    stats.gran:Refresh()
    stats.showLabel:SetPoint("LEFT", stats.gran, "LEFT", 200, 0)
    stats.charDD:SetPoint("LEFT", stats.showLabel, "RIGHT", FIELD_GAP, 0)
    stats.metric:SetPoint("LEFT", stats.charDD, "RIGHT", CHECK_GAP, 0)
    stats.metric:Refresh()
    if stats.charDD.Refresh then stats.charDD:Refresh() end

    local gran, metric = HF._trendGran or "daily", HF._trendMetric or "gold"
    local data = R:Trends(gran, HF._trendCharFilter)
    local periods = data.periods
    local n = #periods
    local y = CARD_PAD + FIELD_H + TILE_GAP
    if n == 0 then return y end
    local cur = periods[n]
    local prev = periods[n - 1] or { xp = 0, gold = 0, count = 0 }
    local curLabel  = (gran == "weekly") and L["This week"] or L["Today"]
    local prevLabel = (gran == "weekly") and L["last week"] or L["yesterday"]
    local list = {}
    for _, d in ipairs({ { "count", L["Quests"] }, { "xp", L["XP"] }, { "gold", L["Gold"] } }) do
        local key = d[1]
        list[#list + 1] = { (L["%s \226\128\148 %s"]):format(d[2], curLabel), formatMetric(key, cur[key] or 0),
            (L["%s vs %s"]):format(fmtDelta(key, (cur[key] or 0) - (prev[key] or 0)), prevLabel) }
    end
    y = tiles(ctx, card, list, y)
    y = y + TILE_GAP
    stats.chart:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    stats.chart:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    local maxV = (metric == "xp" and data.maxXP) or (metric == "gold" and data.maxGold) or data.maxCount
    local cw = _cardW - CARD_PAD * 2
    local barW = (cw - (n - 1) * BAR_SPACING) / n
    for i = 1, MAX_BARS do
        local bar = stats.bars[i]
        if i <= n then
            local p = periods[i]
            local v = (metric == "xp" and p.xp) or (metric == "gold" and p.gold) or p.count
            local h = 1
            if maxV > 0 and v > 0 then h = math.max(2, (v / maxV) * (CHART_H - 4)) end
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", stats.chart, "BOTTOMLEFT", (i - 1) * (barW + BAR_SPACING), 0)
            bar:SetSize(math.max(barW, 1), h)
            bar.fill:SetColorTexture(ctx:Color(v > 0 and "accent" or "track"))
            local rng = p.label
            -- Plain hyphen, not an en dash - the Korean game font has no glyph for U+2013 and draws a box
            if gran == "weekly" then rng = rng .. " - " .. date("!%b %d", p.day1 * 86400) end
            bar._rangeText = rng
            bar._valueText = formatMetric(metric, v)
            bar:Show()
        else
            bar:Hide()
        end
    end
    y = y + CHART_H + LINE_GAP
    stats.axisL:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    stats.axisL:SetText(periods[1].label)
    stats.axisR:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    stats.axisR:SetText(periods[n].label)
    y = y + 15 + TILE_GAP
    local caveat = text(ctx, card, "hint",
        L["Gold is all income (loot, vendor, rewards) tracked forward from when this version was installed \226\128\148 past periods may read 0. XP and quest counts come from quest turn-ins."],
        CARD_PAD, y, cw)
    return y + (caveat:GetStringHeight() or 15)
end

local function sessionCard(ctx, card)
    local Sess = ns:GetSubsystem("Session")
    if not (Sess and Sess.Summary) then return CARD_PAD end
    local sm = Sess:Summary()
    local intro = text(ctx, card, "hint",
        L["Your quest activity this play session. A session starts when you log in and continues across /reload; it resets the next time you log in fresh."],
        CARD_PAD, CARD_PAD, _cardW - CARD_PAD * 2)
    local rate = sm.perHour and (L["   |cffaaaaaa(%.1f / hour)|r"]):format(sm.perHour) or ""
    local levels = "0"
    if sm.levelUps > 0 then levels = (L["%d   |cffaaaaaa(%d to %d)|r"]):format(sm.levelUps, sm.startLevel, sm.curLevel) end
    return tiles(ctx, card, {
        { L["Played this session"], ns.Util.FmtDuration(sm.played) },
        { L["Quests completed"], fmtBigNumber(sm.quests) .. rate },
        { L["Quest XP earned"], (L["%s XP"]):format(fmtBigNumber(sm.xp)) },
        { L["Quest gold earned"], fmtMoney(sm.gold) },
        { L["Level-ups"], levels },
        { L["Quests abandoned"], sm.recording == false and DASH or fmtBigNumber(sm.abandoned or 0) },
    }, CARD_PAD + (intro:GetStringHeight() or 15) + TILE_GAP)
end

function HF:_renderStats()
    local ctx = ui()
    local stats = self._views.stats
    local content = stats.area.content
    local width = areaWidth(stats.area)
    _cardW = width - PAD_SIDE * 2
    _y = PAD_TOP
    statsGroup(ctx, content, "streak", L["Streak"], function(card) return streakCard(ctx, card) end)
    statsGroup(ctx, content, "activity", L["Activity"], function(card) return activityCard(ctx, card) end)
    statsGroup(ctx, content, "totals", L["Totals"], function(card) return totalsCard(ctx, card) end)
    statsGroup(ctx, content, "trends", L["Trends"], function(card) return trendsCard(ctx, card) end)
    statsGroup(ctx, content, "session", L["This Session"], function(card) return sessionCard(ctx, card) end)
    stats.area:SetContentSize(width, _y + PAD_BOTTOM)
end

-- Gold can come in many times a second in a dungeon, so live refreshes are folded into one each half second
function HF:RenderSoon()
    local Events = ns:GetSubsystem("Events")
    if Events and Events.Debounce then
        Events:Debounce("eq.history.live", 0.5, function() HF:Render() end)
    else
        self:Render()
    end
end

function HF:Render()
    if not self.frame or not self.frame:IsShown() then return end
    local t = self._activeTab
    if t == "quests"   then self:_renderQuests() end
    if t == "timeline" then self:_renderTimeline() end
    if t == "stats"    then self:_renderStats() end
end

function HF:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

function HF:Open()
    if not ns:GetSubsystem("Options") then return end
    self:Build()
    self.frame:Show()
    -- Above the options window, which the History tab opens it from
    self.frame:Raise()
    local R = ns:GetSubsystem("History")
    if R and R.RequestMissingTitles then R:RequestMissingTitles() end
    self:Render()
end

local function fmtMoneyText(copper)
    copper = copper or 0
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return ("%dg %ds %dc"):format(g, s, c) end
    if s > 0 then return ("%ds %dc"):format(s, c) end
    return ("%dc"):format(c)
end

function HF:_exportQuests()
    if not ns:GetSubsystem("History") then return "(history unavailable)" end
    local entries = queryEntries()
    local lines = { ("# Quest History — %d entries"):format(#entries) }
    lines[#lines + 1] = "# date | character | quest | type | zone | held"
    for i = 1, #entries do
        local e = entries[i]
        local d = (e.t and e.t > 0) and date("%Y-%m-%d %H:%M", e.t) or L["(before tracking)"]
        lines[#lines + 1] = ("%s | %s | %s | %s | %s | %s"):format(
            d, e.c or "?", nameOf(e) or ("Quest #" .. tostring(e.q)), exportType(e), e.z or "",
            (e.d and e.d > 0) and ns.Util.FmtDurationLong(e.d) or "")
    end
    return table.concat(lines, "\n")
end

function HF:_exportTimeline()
    local sorted, completion = timelineChains()
    if not ns:GetSubsystem("ChainGuideDatabase") then return "(history or chain guide unavailable)" end
    local lines = { "# Chain Timeline — chains with at least one recorded completion" }
    for _, rec in ipairs(sorted) do
        lines[#lines + 1] = ("## %s — %d of %d quests"):format(
            rec.chain.name or ("Chain #" .. tostring(rec.id)), rec.doneN, rec.total)
        for j = 1, #rec.chain.items do
            local it = rec.chain.items[j]
            if it and it.type == "quest" then
                local t = completion[it.id]
                local title = questTitle(it.id) or it.name or ("Quest #" .. tostring(it.id))
                local when = t and ((t > 0 and date("%Y-%m-%d", t)) or L["(before tracking)"]) or DASH
                lines[#lines + 1] = ("  - %s [%s]"):format(title, when)
            end
        end
    end
    return table.concat(lines, "\n")
end

function HF:_exportStats()
    local R = ns:GetSubsystem("History")
    if not (R and R.Totals) then return "(history unavailable)" end
    local s = R:Streak()
    local t = R:Totals()
    local lines = {
        "Quest History — Stats",
        "",
        ("Current daily streak: %d days"):format(s.current),
        ("Best daily streak: %d days"):format(s.best),
        ("Total dated entries: %d"):format(s.total),
        "",
        ("Total quests with reward data: %d"):format(t.rewardCount),
        ("Total gold earned: %s"):format(fmtMoneyText(t.totalMoney)),
        ("Total XP earned: %d"):format(t.totalXP),
        ("Total quests abandoned: %s"):format(t.recording == false and "not recorded" or tostring(t.abandoned or 0)),
        (t.recording ~= false and t.avgHeld)
            and ("Average time: %s (over %d quests)"):format(ns.Util.FmtDurationLong(t.avgHeld), t.heldCount or 0)
            or "Average time: n/a",
        "",
        "By character:",
    }
    local chars = {}
    for k, v in pairs(t.byChar) do chars[#chars + 1] = { key = k, rec = v } end
    table.sort(chars, byCount)
    for _, c in ipairs(chars) do
        lines[#lines + 1] = ("  %s — %d quests, %s, %d XP"):format(c.key, c.rec.count, fmtMoneyText(c.rec.money), c.rec.xp)
    end
    if t.topGold then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("Biggest single gold reward: %s (%s)"):format(
            nameOf(t.topGold) or ("Quest #" .. tostring(t.topGold.q)), fmtMoneyText(t.topGold.m))
    end
    if t.topXP then
        if not t.topGold then lines[#lines + 1] = "" end
        lines[#lines + 1] = ("Biggest single XP reward: %s (%d XP)"):format(
            nameOf(t.topXP) or ("Quest #" .. tostring(t.topXP.q)), t.topXP.xp)
    end
    if R.DayCounts then
        local counts, today = R:DayCounts(HEATMAP_DAYS)
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("# Activity — last %d days"):format(HEATMAP_DAYS)
        lines[#lines + 1] = "# date | turn-ins"
        for i = HEATMAP_DAYS, 1, -1 do
            local day = today - (i - 1)
            lines[#lines + 1] = ("%s | %d"):format(date("!%Y-%m-%d", day * 86400), counts[day] or 0)
        end
    end
    if R.Trends then
        local gran, scope = self._trendGran or "daily", self._trendCharFilter
        local data = R:Trends(gran, scope)
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("# Trends (%s, %s)"):format(gran,
            (not scope or scope == "all" or scope == "") and "all characters" or scope)
        lines[#lines + 1] = "# period | quests | xp | gold"
        for _, p in ipairs(data.periods) do
            local period = (gran == "weekly")
                and (date("!%Y-%m-%d", p.day0 * 86400) .. " - " .. date("!%Y-%m-%d", p.day1 * 86400))
                or date("!%Y-%m-%d", p.day0 * 86400)
            lines[#lines + 1] = ("%s | %d | %d | %s"):format(period, p.count, p.xp, fmtMoneyText(p.gold))
        end
    end
    local Sess = ns:GetSubsystem("Session")
    if Sess and Sess.Summary then
        local sm = Sess:Summary()
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("Played this session: %s"):format(ns.Util.FmtDuration(sm.played))
        lines[#lines + 1] = ("Quests completed: %d%s"):format(sm.quests,
            sm.perHour and ((" (%.1f/hour)"):format(sm.perHour)) or "")
        lines[#lines + 1] = ("Quest XP earned: %d"):format(sm.xp)
        lines[#lines + 1] = ("Quest gold earned: %s"):format(fmtMoneyText(sm.gold))
        lines[#lines + 1] = ("Quests abandoned: %s"):format(sm.recording == false and "not recorded" or tostring(sm.abandoned or 0))
        if sm.levelUps > 0 then
            lines[#lines + 1] = ("Level-ups: %d (%d to %d)"):format(sm.levelUps, sm.startLevel, sm.curLevel)
        end
    end
    return table.concat(lines, "\n")
end

function HF:_exportForTab(tabId)
    if tabId == "quests"   then return self:_exportQuests()   end
    if tabId == "timeline" then return self:_exportTimeline() end
    if tabId == "stats"    then return self:_exportStats()    end
    return "(nothing to export)"
end

function HF:_buildExportPopup()
    if self._exportPopup then return self._exportPopup end
    local ctx = ui()
    local p = ctx:CreateWindow({ name = "EQHistoryExportFrame", title = L["Export"], width = 540, height = 380 })
    p.hint = ctx:CreateText(p.body, L["Press Ctrl+A to select all, then Ctrl+C to copy."], "hint")
    p.hint:SetPoint("TOPLEFT", p.body, "TOPLEFT", PAD_SIDE, -INTRO_PAD)
    p.field = ctx:CreateMultilineField(p.body, { readOnly = true })
    p.field:SetPoint("TOPLEFT", p.hint, "BOTTOMLEFT", 0, -LABEL_GAP)
    p.field:SetPoint("BOTTOMRIGHT", p.body, "BOTTOMRIGHT", -PAD_SIDE, PAD_SIDE)
    -- The field holds the keyboard after SelectAll, so its Escape closes the window, as the old one did
    p.field.box:HookScript("OnEscapePressed", function() p:Hide() end)
    self._exportPopup = p
    return p
end

function HF:_openExportPopup()
    local p = self:_buildExportPopup()
    p.field:SetText(self:_exportForTab(self._activeTab) or "")
    p:Show()
    p:Raise()
    p.field:SelectAll()
end
