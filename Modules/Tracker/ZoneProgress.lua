local _, ns = ...

local ZP = ns:RegisterSubsystem("TrackerZoneProgress", {})

local RECOMPUTE_KEY   = "eq.zoneprogress.recompute"
local ZONE_KEY        = "eq.zoneprogress.zone"
local DEBOUNCE_DELAY  = 0.25
local RETRY_DELAY     = 0.3
local RETRY_MAX       = 5
local MAX_HOPS        = 5

local BAR_H       = 12
local ROW_PAD_TOP = 2
local ROW_PAD_BOT = 4

ZP._countCache     = {}
ZP._retryScheduled = {}
ZP._retryCount     = {}
ZP._seen           = {}
ZP._scratchMaps    = {}
ZP._voteTally      = {}

local function DBsub() return ns:GetSubsystem("DB") end

local function enabled()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    return (p and p.showZoneProgressBar == true) or false
end

local function location()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    return (p and p.zoneProgressLocation) or "floating"
end

local function barState()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    if not p then return nil end
    p.zoneProgressBar = p.zoneProgressBar or {}
    return p.zoneProgressBar
end

local DEFAULT_BAR_TEXTURE = [[Interface\TargetingFrame\UI-StatusBar]]

local function applyBarFill(bar)
    if not bar then return end
    local st = barState() or {}
    local Media = ns:GetSubsystem("Media")
    local tex = (Media and Media.GetStatusBarFile and Media:GetStatusBarFile(st.barTexture))
                or DEFAULT_BAR_TEXTURE
    bar:SetStatusBarTexture(tex)
    local c = st.barColor
    if c then bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    else       bar:SetStatusBarColor(0.26, 0.42, 1.0) end
end

local function qlQuestStore()
    local db = DBsub()
    if not (db and db.db and db.db.global) then return nil end
    local zp = db.db.global.zoneProgress
    if not zp then zp = {}; db.db.global.zoneProgress = zp end
    zp.qlQuests = zp.qlQuests or {}
    return zp.qlQuests
end

local function zoneCatStore()
    local db = DBsub()
    if not (db and db.db and db.db.global) then return nil end
    local zp = db.db.global.zoneProgress
    if not zp then zp = {}; db.db.global.zoneProgress = zp end
    zp.zoneCat = zp.zoneCat or {}
    return zp.zoneCat
end

local function categoryByName(name)
    if not name or name == "" then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (Database and Database.categories) then return nil end
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

local function categoryByMapID(rootID)
    if not rootID then return nil end
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (Database and Database.categories) then return nil end
    local db = DBsub()
    local overrides = db and db.db and db.db.profile and db.db.profile.chainGuide
                      and db.db.profile.chainGuide.zoneMapIDs
    for id, cat in pairs(Database.categories) do
        if cat.mapID == rootID then return id end
        local mids = cat.mapIDs
        if type(mids) == "table" then
            for i = 1, #mids do if mids[i] == rootID then return id end end
        end
        local ov = overrides and overrides[id]
        if type(ov) == "table" then
            for i = 1, #ov do if ov[i] == rootID then return id end end
        elseif type(ov) == "number" and ov == rootID then
            return id
        end
    end
    return nil
end

-- zoneRoot is called several times per tracker render (HeaderInfo + Render), each
-- walking up to MAX_HOPS GetMapInfo allocations. Cache it, invalidated on the zone
-- events onZone already fires for.
local _rootID, _rootName, _rootDirty = nil, nil, true
local function zoneRoot()
    if not _rootDirty then return _rootID, _rootName end
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID or mapID <= 0 then return nil end
    _rootDirty = false
    local id = mapID
    for _ = 1, MAX_HOPS do
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == Enum.UIMapType.Zone then
            _rootID, _rootName = id, info.name
            return id, info.name
        end
        local parent = info.parentMapID
        if not parent or parent <= 0 then break end
        id = parent
    end
    local info = C_Map.GetMapInfo(mapID)
    _rootID, _rootName = mapID, info and info.name or nil
    return _rootID, _rootName
end

function ZP:EnsureQuests(qlID)
    if not (qlID and C_QuestLine and C_QuestLine.GetQuestLineQuests) then return end
    local store = qlQuestStore()
    if not store then return end

    local quests = C_QuestLine.GetQuestLineQuests(qlID)
    if not quests or #quests == 0 then
        local n = self._retryCount[qlID] or 0
        if n < RETRY_MAX and not self._retryScheduled[qlID] then
            self._retryScheduled[qlID] = true
            self._retryCount[qlID] = n + 1
            C_Timer.After(RETRY_DELAY * (n + 1), function()
                self._retryScheduled[qlID] = nil
                if not enabled() then return end
                self:EnsureQuests(qlID)
                self:ScheduleRecompute()
            end)
        end
        return
    end

    self._retryCount[qlID] = nil
    local existing = store[qlID]
    if not existing or #quests >= #existing then
        store[qlID] = quests
    end
end

function ZP:_CategoryQuestLines(catID)
    local routing = ns.QUESTLINE_ROUTING
    if not (routing and catID) then return nil end
    if self._catIndexFor ~= routing then
        local idx = {}
        for qlID, entry in pairs(routing) do
            local c = (type(entry) == "table") and entry.cat or entry
            if c then
                local list = idx[c]
                if not list then list = {}; idx[c] = list end
                list[#list + 1] = qlID
            end
        end
        self._catIndex    = idx
        self._catIndexFor = routing
    end
    return self._catIndex[catID]
end

function ZP:_VoteCategory(rootID)
    if not (rootID and C_QuestLine and C_QuestLine.GetAvailableQuestLines and ns.QUESTLINE_ROUTING) then
        return nil
    end
    local maps = self._scratchMaps
    wipe(maps)
    maps[1] = rootID
    if C_Map and C_Map.GetMapChildrenInfo then
        local kids = C_Map.GetMapChildrenInfo(rootID, nil, true)
        if kids then
            for i = 1, #kids do
                if kids[i] and kids[i].mapID then maps[#maps + 1] = kids[i].mapID end
            end
        end
    end

    local routing = ns.QUESTLINE_ROUTING
    local tally = self._voteTally
    wipe(tally)
    local bestCat, bestN = nil, 0
    for m = 1, #maps do
        local lines = C_QuestLine.GetAvailableQuestLines(maps[m])
        if lines then
            for i = 1, #lines do
                local info = lines[i]
                local qlID = info and info.questLineID
                local entry = qlID and routing[qlID]
                local c = entry and ((type(entry) == "table") and entry.cat or entry)
                if c then
                    local n = (tally[c] or 0) + 1
                    tally[c] = n
                    if n > bestN then bestN, bestCat = n, c end
                end
            end
        end
    end
    return bestCat
end

function ZP:_CategoryFromHistory(rootID)
    local routing = ns.QUESTLINE_ROUTING
    if not (rootID and routing) then return nil end
    local db = DBsub()
    if not db then return nil end

    local tally = self._voteTally
    wipe(tally)
    local bestCat, bestN = nil, 0
    local function tallySet(set)
        if type(set) ~= "table" then return end
        for qlID in pairs(set) do
            local entry = routing[qlID]
            local c = entry and ((type(entry) == "table") and entry.cat or entry)
            if c then
                local n = (tally[c] or 0) + 1
                tally[c] = n
                if n > bestN then bestN, bestCat = n, c end
            end
        end
    end

    local g = db.db and db.db.global and db.db.global.zoneProgress
    if g and g.discovered then tallySet(g.discovered[rootID]) end
    local ch = db.char and db.char.zoneProgress and db.char.zoneProgress.questlines
    if ch then tallySet(ch[rootID]) end
    return bestCat
end

function ZP:_ResolveCategory(rootID, name)
    if not rootID then return nil end
    local cache = zoneCatStore()
    if cache and cache[rootID] then return cache[rootID] end

    local catID = categoryByMapID(rootID)
                  or categoryByName(name)
                  or self:_CategoryFromHistory(rootID)
                  or self:_VoteCategory(rootID)
    if catID and cache then cache[rootID] = catID end
    return catID
end

function ZP:Recompute(rootID, name)
    if not rootID then return end
    local store = qlQuestStore()
    if not store then return end

    local catID = self:_ResolveCategory(rootID, name)
    local lines = catID and self:_CategoryQuestLines(catID)

    local seen = self._seen
    wipe(seen)
    local total, completed = 0, 0

    if lines then
        local flagged = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
        for li = 1, #lines do
            local qlID  = lines[li]
            local quests = store[qlID]
            if not quests then
                self:EnsureQuests(qlID)
                quests = store[qlID]
            end
            if quests then
                for i = 1, #quests do
                    local qid = quests[i]
                    if qid and not seen[qid] then
                        seen[qid] = true
                        total = total + 1
                        if flagged and flagged(qid) then
                            completed = completed + 1
                        end
                    end
                end
            end
        end
    end

    local cache = self._countCache[rootID]
    if not cache then cache = {}; self._countCache[rootID] = cache end
    cache.total     = total
    cache.completed = completed
    local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(rootID)
    cache.name = (info and info.name) or name or cache.name

    if total == 0 and not catID then self:_DebugUnresolved(rootID, name) end
end

function ZP:_DebugUnresolved(rootID, name)
    if not ns.zoneBarDebug then return end
    if not self._debugSeen then self._debugSeen = {} end
    if self._debugSeen[rootID] then return end
    self._debugSeen[rootID] = true
    print(("|cffEBB706EQ ZoneBar:|r no routing for zone |cffffffff%s|r (uiMapID %d). Add it to _QuestLineRouting.lua.")
        :format(name or "?", rootID))
end

function ZP:PrintStatus()
    local rootID, name = zoneRoot()
    if not rootID then
        print("|cffEBB706EQ ZoneBar:|r no current zone (instanced / no map).")
        return
    end
    self:Recompute(rootID, name)
    local catID = self:_ResolveCategory(rootID, name)
    local cat
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if catID and Database and Database.categories then cat = Database.categories[catID] end
    local c = self._countCache[rootID]
    print(("|cffEBB706EQ ZoneBar:|r zone |cffffffff%s|r (uiMapID %d) → %s, %d/%d complete.")
        :format(name or "?", rootID,
                cat and ("category |cffffffff" .. (cat.name or "?") .. "|r")
                     or "|cffff5555no routing match|r",
                (c and c.completed) or 0, (c and c.total) or 0))
end

function ZP:ScheduleRecompute()
    if not enabled() then return end
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    if not self._recomputeThunk then
        self._recomputeThunk = function()
            local rootID, name = zoneRoot()
            if rootID then ZP:Recompute(rootID, name) end
            ZP:_Repaint()
        end
    end
    Events:Debounce(RECOMPUTE_KEY, DEBOUNCE_DELAY, self._recomputeThunk)
end

function ZP:_Repaint()
    local Tracker = ns:GetSubsystem("Tracker")
    if Tracker and Tracker.Refresh then Tracker:Refresh() end
    self:UpdateFrame()
end

function ZP:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    self._zoneThunk = function()
        if not enabled() then return end
        local rootID, name = zoneRoot()
        if not rootID then return end
        ZP:Recompute(rootID, name)
        ZP:_Repaint()
    end

    local function onZone()
        _rootDirty = true
        if not enabled() then return end
        Events:Debounce(ZONE_KEY, DEBOUNCE_DELAY, ZP._zoneThunk)
    end
    local function onQuest()
        if not enabled() then return end
        ZP:ScheduleRecompute()
    end

    Events:On("ZONE_CHANGED_NEW_AREA", onZone)
    Events:On("PLAYER_ENTERING_WORLD", onZone)
    Events:On("QUEST_TURNED_IN",       onQuest)
    Events:On("QUEST_REMOVED",         onQuest)

    -- GetAvailableQuestLines is async; re-resolve when data lands so the cache learns the mapping.
    Events:On("QUESTLINE_UPDATE", onZone)
end

function ZP:SetEnabled(on)
    if on then
        local rootID, name = zoneRoot()
        if rootID then
            self:Recompute(rootID, name)
        end
    else
        wipe(self._countCache)
        if self.frame then self.frame:Hide() end
    end
    self:_Repaint()
end

local FRAME_W       = 220
local FRAME_BAR_H   = 12

function ZP:ApplySettings()
    local f = self.frame
    if not f then return end
    local st = barState() or {}
    f:ClearAllPoints()
    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",
               st.x or 0, st.y or 220)
    f:SetScale(st.scale or 1.0)

    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    else
        f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)
    end

    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        local bc = st.borderColor
        if bc then f:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a or 1)
        else       f:SetBackdropBorderColor(0.635, 0.000, 0.039, 1) end   -- brand red #a2000a
    end
end

function ZP:_SavePosition()
    local f, st = self.frame, barState()
    if not (f and st) then return end
    local point, _, relPoint, x, y = f:GetPoint()
    st.point, st.relPoint, st.x, st.y = point, relPoint, x, y
end

function ZP:_ContextMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu and self.frame) then return end
    MenuUtil.CreateContextMenu(self.frame, function(_, root)
        root:CreateTitle(ns.L["Zone Progress Bar"])
        local st = barState() or {}
        root:CreateButton(st.locked and ns.L["Unlock (allow moving)"] or ns.L["Lock position"],
            function()
                local s = barState(); if s then s.locked = not s.locked end
                ZP:ApplySettings()
            end)
        root:CreateButton(ns.L["Reset position"], function()
            local s = barState()
            if s then s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, 220 end
            ZP:ApplySettings()
        end)
        root:CreateDivider()
        root:CreateButton(ns.L["Cancel"], function() end)
    end)
end

function ZP:_AcquireFrame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "EverythingQuestsZoneProgressBar", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, 38)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        local st = barState()
        if st and st.locked then return end
        s:StartMoving()
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        ZP:_SavePosition()
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ZP:_ContextMenu() end
    end)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 6, -4)
    f.title:SetJustifyH("LEFT")
    f.title:SetTextColor(0.93, 0.32, 0.10)

    f.count = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.count:SetPoint("TOPRIGHT", -6, -5)
    f.count:SetTextColor(0.92, 0.72, 0.02)

    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("BOTTOMLEFT", 6, 5)
    bar:SetPoint("BOTTOMRIGHT", -6, 5)
    bar:SetHeight(FRAME_BAR_H)
    bar:SetMinMaxValues(0, 100)
    applyBarFill(bar)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER")
    f.bar = bar

    self.frame = f
    self:ApplySettings()
    return f
end

function ZP:UpdateFrame()
    local show = enabled() and location() == "floating"
    if not show then
        if self.frame then self.frame:Hide() end
        return
    end
    local rootID, zname = zoneRoot()
    if not rootID then
        if self.frame then self.frame:Hide() end
        return
    end
    local cache = self._countCache[rootID]
    if not cache then
        self:Recompute(rootID, zname)
        cache = self._countCache[rootID]
    end
    local total = (cache and cache.total) or 0
    local f = self:_AcquireFrame()
    if total <= 0 then f:Hide(); return end
    local completed = (cache and cache.completed) or 0

    local pct = (completed / total) * 100
    f.title:SetText((cache and cache.name) or zname or "")
    f.count:SetText(completed .. "/" .. total)
    f.bar:SetValue(pct)
    f.bar.label:SetText(("%d%%"):format(math.floor(pct + 0.5)))

    local st = barState() or {}
    local hc = st.headerColor
    if hc then f.title:SetTextColor(hc.r, hc.g, hc.b, hc.a or 1)
    else       f.title:SetTextColor(0.93, 0.32, 0.10) end
    local cc = st.countColor
    if cc then f.count:SetTextColor(cc.r, cc.g, cc.b, cc.a or 1)
    else       f.count:SetTextColor(0.92, 0.72, 0.02) end

    local Media = ns:GetSubsystem("Media")
    if Media and Media.ApplyTrackerFont then
        local bf = st.font
        Media:ApplyTrackerTitleFont(f.title, bf)
        Media:ApplyTrackerFont(f.count, -2, bf)
        Media:ApplyTrackerFont(f.bar.label, -2, bf)
    end
    applyBarFill(f.bar)

    f:Show()
end

function ZP:SetLocation(loc)
    local db = DBsub()
    if db and db.db then db.db.profile.tracker.zoneProgressLocation = loc end
    self:_Repaint()
end

function ZP:SetScale(v)
    local st = barState()
    if st then st.scale = v end
    self:ApplySettings()
end

function ZP:SetLocked(b)
    local st = barState()
    if st then st.locked = b end
    self:ApplySettings()
end

function ZP:RefreshAppearance()
    self:ApplySettings()
    self:UpdateFrame()
end

function ZP:SetShowBorder(b)
    local st = barState(); if st then st.showBorder = b and true or false end
    self:RefreshAppearance()
end

function ZP:SetShowBackground(b)
    local st = barState(); if st then st.showBackground = b and true or false end
    self:RefreshAppearance()
end

function ZP:SetBorderColor(c)
    local st = barState(); if st then st.borderColor = c end
    self:ApplySettings()
end

function ZP:SetBarFont(name)
    local st = barState(); if st then st.font = (name ~= "" and name) or nil end
    self:UpdateFrame()
end

function ZP:SetHeaderColor(c)
    local st = barState(); if st then st.headerColor = c end
    self:UpdateFrame()
end

function ZP:SetCountColor(c)
    local st = barState(); if st then st.countColor = c end
    self:UpdateFrame()
end

function ZP:SetBarTexture(name)
    local st = barState(); if st then st.barTexture = (name ~= "" and name) or nil end
    self:_Repaint()
end

function ZP:SetBarColor(c)
    local st = barState(); if st then st.barColor = c end
    self:_Repaint()
end

function ZP:HeaderInfo()
    local rootID, name = zoneRoot()
    if not rootID then return nil end
    local c = self._countCache[rootID]
    if not c then return name end
    return (c.name or name), (c.completed or 0) .. "/" .. (c.total or 0)
end

function ZP:_AcquireBar(parent)
    local bar = self.bar
    if bar then
        if bar:GetParent() ~= parent then bar:SetParent(parent) end
        return bar
    end
    bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(BAR_H)
    bar:SetMinMaxValues(0, 100)
    applyBarFill(bar)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0.04, 0.07, 0.18, 0.9)

    bar.border = CreateFrame("Frame", nil, bar, "BackdropTemplate")
    bar.border:SetPoint("TOPLEFT", -1, 1)
    bar.border:SetPoint("BOTTOMRIGHT", 1, -1)
    bar.border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    bar.border:SetBackdropBorderColor(0, 0, 0, 0.9)

    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER", bar, "CENTER", 0, 0)

    self.bar = bar
    return bar
end

function ZP:_hideBar()
    if self.bar then self.bar:Hide() end
    return 0, 0
end

function ZP:Render(content, contentWidth, yStart, collapsed)
    if not enabled() then return self:_hideBar() end
    if location() ~= "tracker" then return self:_hideBar() end

    local rootID, name = zoneRoot()
    if not rootID then return self:_hideBar() end

    local cache = self._countCache[rootID]
    if not cache then
        self:Recompute(rootID, name)
        cache = self._countCache[rootID]
    end

    local total = (cache and cache.total) or 0
    if total <= 0 then return self:_hideBar() end
    local completed = (cache and cache.completed) or 0

    if collapsed then
        if self.bar then self.bar:Hide() end
        return 0, 1, total
    end

    local bar = self:_AcquireBar(content)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -(yStart + ROW_PAD_TOP))
    bar:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(yStart + ROW_PAD_TOP))

    local pct = (completed / total) * 100
    bar:SetValue(pct)
    bar.label:SetText(("%d%%"):format(math.floor(pct + 0.5)))

    local Media = ns:GetSubsystem("Media")
    if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(bar.label, -2) end
    applyBarFill(bar)

    bar:Show()
    return ROW_PAD_TOP + BAR_H + ROW_PAD_BOT, 1, total
end
