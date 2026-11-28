local _, ns = ...
local L = ns.L

-- Everything the client cannot tell you about a quest you have not accepted. The data half lives
-- in QuestBrowserData, so this file only lays out what that returns.
local QB = ns:RegisterSubsystem("QuestBrowser", {})

local DEFAULT_W, DEFAULT_H = 1000, 660
local MIN_W, MIN_H = 760, 480
local SIDEBAR_W = 300
local SIDE_PAD, FIELD_GAP, CHECK_GAP, COUNT_GAP, LIST_GAP = 12, 8, 12, 10, 8
local PAD_TOP, PAD_SIDE, PAD_BOTTOM = 20, 24, 28
local META_GAP, STATUS_GAP, TAG_GAP, TAG_SPACING, STATUS_ICON = 4, 12, 10, 6, 16
local GROUP_GAP, LABEL_GAP = 22, 8
local ROW_H, ROW_PAD, TEXT_PAD, ROW_ICON, ROW_ICON_GAP = 28, 14, 6, 16, 8
local BUTTON_GAP = 16
local HINT_GAP = 4
local BAR_ROOM = 10
local MAX_ROWS = 300
local SEP = "  \226\128\162  "

local GOSSIP_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local DONE_ICONS = { { name = "check", color = "muted" } }
local GOSSIP_ACTIVE    = "Interface\\GossipFrame\\ActiveQuestIcon"
local BROWSER_ICON = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\icon-browser"
local PROGRESS_GAP = 6
local GROUP_ORDER = { class = 1, profession = 2, event = 3, other = 4 }

local function data()
    return ns:GetSubsystem("QuestBrowserData")
end

local function avail()
    return ns:GetSubsystem("AvailableQuests")
end

local function browserCfg()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db and DB.db.profile and DB.db.profile.questBrowser
end

-- One literal L key per branch keeps each phrase visible to the locale scanner, which cannot read L[reason]
local function reasonText(reason)
    if reason == "completed"            then return L["You have already completed this quest."] end
    if reason == "in your quest log"    then return L["This quest is already in your quest log."] end
    if reason == "holiday quest"        then return L["Part of a world event, so it is only offered while that event is running."] end
    if reason == "race or class"        then return L["Your race or class cannot take this quest."] end
    if reason == "too low level"        then return L["You do not meet the required level yet."] end
    if reason == "above level range"    then return L["You are past the highest level this quest is offered at."] end
    if reason == "low level"            then return L["Too far below your level to be worth showing. Turn off the low level filter to see it."] end
    if reason == "high level"           then return L["The game colors this quest red for you, so it is out of reach for now. Turn off the high level filter to see it."] end
    if reason == "prerequisite"         then return L["An earlier quest has to be finished first."] end
    if reason == "breadcrumb in your log" then return L["A breadcrumb quest in your log sends you here. Hand it in first."] end
    if reason == "follow-up taken"      then return L["A quest this breadcrumb leads to is already done or in your log."] end
    if reason == "later step done"      then return L["A later step of this chain is already done or in your log."] end
    if reason == "took another branch"  then return L["You took a different branch of this quest line."] end
    if reason == "reputation"           then return L["Your reputation standing does not allow it."] end
    if reason == "profession"           then return L["You do not have the skill this quest needs yet, or not at a high enough rank."] end
    if reason == "dungeon or raid quest" then return L["Hidden by your dungeon and raid filter."] end
    if reason == "repeatable quest"     then return L["Hidden by your repeatable quest filter."] end
    if reason == "profession quest"     then return L["Hidden by your profession quest filter."] end
    if reason == "not in the game"      then return L["This quest is no longer in the game, or never was."] end
    if reason == "event not running"    then return L["Part of a one-time world event that is not running here."] end
    if reason == "not released"         then return L["Part of content that is not released on this version of the game yet."] end
    if reason == "daily done today"     then return L["You have done this daily quest today. It is offered again after the daily reset."] end
    if reason == "hidden by you"        then return L["You can pick this up now, but you took it off your map. Uncheck \"Hide from the map\" to show it again."] end
    if reason == "locked"               then return L["It needs an earlier quest your character can never take."] end
    return nil
end

local SOURCE_KIND = 3

local function sourceText(kind)
    if kind == 1 then return L["A character here offers it"] end
    if kind == 2 then return L["An object here offers it"] end
    if kind == SOURCE_KIND then return L["An item that starts it drops here"] end
    return nil
end

-- The same sentences for the Chain Guide's tooltips, so a reason never reads two ways
function QB:ReasonText(reason) return reasonText(reason) end
function QB:SourceText(kind) return sourceText(kind) end

local function scopeOptions()
    return {
        { value = "all",       label = L["All quests"] },
        { value = "available", label = L["Available to you"] },
        { value = "log",       label = L["In your quest log"] },
        { value = "completed", label = L["Completed"] },
        { value = "hidden",    label = L["Hidden by you"] },
    }
end

-- Rows are pooled per kind, since each kind's tooltip is attached once, when the row is made
QB._pools, QB._active = {}, {}

local function release()
    for kind, list in pairs(QB._active) do
        local pool = QB._pools[kind]
        for i = #list, 1, -1 do
            local w = list[i]
            w:Hide()
            w:ClearAllPoints()
            pool[#pool + 1] = w
            list[i] = nil
        end
    end
end

local function acquire(kind, make)
    QB._pools[kind] = QB._pools[kind] or {}
    QB._active[kind] = QB._active[kind] or {}
    local w = table.remove(QB._pools[kind]) or make()
    w:Show()
    local active = QB._active[kind]
    active[#active + 1] = w
    return w
end

local ROW_TIPS = {
    place = function() return L["Click to set a TomTom waypoint here, or to open the map here without TomTom"] end,
    quest = function() return L["Click to open this quest"] end,
    chain = function() return L["Find this quest in EQ's Chain Guide"] end,
    rep   = function() return L["The reputation this quest gives, as the quest data lists it and before bonuses such as Diplomacy. Other related factions can gain or lose some too."] end,
    repLoss = function() return L["Worked out from the gain, as the Aldor and the Scryers each lose a tenth more than the other gains."] end,
}
-- Rows a click does nothing on, so they take no highlight
local STILL = { text = true, rep = true, repLoss = true }

local function rowClick(self)
    if self._zoneQuestID then
        local QLink = ns:GetSubsystem("QuestLink")
        if QLink and QLink:WantsShare() and QLink:Share(self._zoneQuestID) then return end
        QB:OpenFromZone(self._zoneQuestID)
    elseif self._questID then
        local QLink = ns:GetSubsystem("QuestLink")
        if QLink and QLink:WantsShare() and QLink:Share(self._questID) then return end
        -- A quest linked from a page the Zones page opened opens there too, with Back to the zone
        if QB._mode == "zones" and QB._zoneQuest then QB:OpenFromZone(self._questID) else QB:Select(self._questID) end
    elseif self._mapID then
        QB:GoTo(self._mapID, self._px, self._py, self._title)
    elseif self._chainID then
        local CG = ns:GetSubsystem("ChainGuide")
        if CG then
            -- Hidden first, so the guide does not open behind this window
            if QB.frame then QB.frame:Hide() end
            CG:Open()
            CG:NavigateChain(self._chainID, self._chainQuest)
        end
    end
end

local function makeRow(ctx, content, kind)
    local r = CreateFrame("Button", nil, content)
    r:SetHeight(ROW_H)
    if not STILL[kind] then
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(ctx:Color("hover"))
        r:SetScript("OnClick", rowClick)
    end
    local _, edges = ctx:Paint(r, nil, "divider", "T")
    r.div = edges[1]
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW_ICON, ROW_ICON)
    r.icon:SetPoint("LEFT", r, "LEFT", ROW_PAD, 0)
    r.text = ctx:CreateText(r, "", "label")
    r.value = ctx:CreateText(r, "", "hint")
    r.value:SetPoint("RIGHT", r, "RIGHT", -ROW_PAD, 0)
    r.value:SetWordWrap(false)
    if ROW_TIPS[kind] then ctx:AttachTooltip(r, ROW_TIPS[kind]()) end
    -- Rows are reused for other quests, so this kind reads its tooltip at each hover
    if kind == "zq" then
        r:SetScript("OnEnter", function(s) ctx:ShowTooltip(s, s._tipTitle, s._tipBody) end)
        r:SetScript("OnLeave", function() ctx:HideTooltip() end)
    end
    return r
end

local function makeCard(ctx, content)
    local c = CreateFrame("Frame", nil, content)
    ctx:Paint(c, "surface", "surfaceBorder")
    return c
end

local function setResizeHintSeen(f)
    local cfg = browserCfg()
    if cfg then cfg.resizeHintSeen = true end
    if f.resizeHint then f.resizeHint:Hide() end
end

function QB:Build()
    if self.frame then return end
    local Options = ns:GetSubsystem("Options")
    local ctx = Options.ui
    self._ctx = ctx

    local f = ctx:CreateWindow({
        name = "EQQuestBrowserFrame", title = L["Quest Browser"],
        width = DEFAULT_W, height = DEFAULT_H, minWidth = MIN_W, minHeight = MIN_H,
        sidebarWidth = SIDEBAR_W, gripTip = L["Drag to resize"],
        getSize = function()
            local cfg = browserCfg()
            if cfg then return cfg.width, cfg.height end
        end,
        setSize = function(w, h)
            local cfg = browserCfg()
            if cfg then cfg.width, cfg.height = w, h end
        end,
        getMaximized = function()
            local cfg = browserCfg()
            return cfg and cfg.maximized or false
        end,
        setMaximized = function(on)
            local cfg = browserCfg()
            if cfg then cfg.maximized = on or nil end
        end,
        onResize = function(win)
            setResizeHintSeen(win)
            self:RenderBody()
        end,
    })
    self.frame = f

    f.resizeHint = ctx:CreateText(f.grip, L["Drag to resize"], "hint")
    f.resizeHint:SetPoint("RIGHT", f.grip, "LEFT", -HINT_GAP, 0)
    local cfg = browserCfg()
    if cfg and cfg.resizeHintSeen then f.resizeHint:Hide() end

    local side = f.sidebar
    f.nav = ctx:CreateNav(side, {
        { id = "quests", title = L["Quests"], icon = BROWSER_ICON },
        { id = "zones",  title = L["Zones"],  icon = ctx:Texture("icon-map") },
    }, function(id) self:SetMode(id) end)
    f.nav:Select(self._mode or "quests")
    local _, _, _, _, navY = f.nav:GetPoint(1)
    local top = -(math.abs(navY or 0) + f.nav:GetHeight() + FIELD_GAP)

    f._search = ctx:CreateSearchField(side, L["Find quest"], function() self:RenderList() end,
        L["Find quest"], L["Type part of a quest's name or its ID. Put the name in quotes to match the whole title."])
    f._search:SetPoint("TOPLEFT", side, "TOPLEFT", SIDE_PAD, top)
    f._search:SetPoint("TOPRIGHT", side, "TOPRIGHT", -SIDE_PAD, top)
    -- The library field answers only Enter, and this one filters as you type, an empty field included
    f._search.box:HookScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        local Events = ns:GetSubsystem("Events")
        if Events and Events.Debounce then
            Events:Debounce("eq.questbrowser.search", 0.25, function() QB:RenderList() end)
        else
            QB:RenderList()
        end
    end)

    f._scopeDD = ctx:CreateDropdown(side, nil, scopeOptions,
        function() return QB._scope or "all" end,
        function(v) QB._scope = v; QB:RenderList() end)
    f._scopeDD:SetPoint("TOPLEFT", f._search, "BOTTOMLEFT", 0, -FIELD_GAP)
    f._scopeDD:SetPoint("TOPRIGHT", f._search, "BOTTOMRIGHT", 0, -FIELD_GAP)

    f._zoneCB = ctx:CreateCheckbox(side, L["This zone only"],
        function() return QB._zoneOnly == true end,
        function(v) QB._zoneOnly = v; QB:RenderList() end,
        L["Only list quests that can be picked up on the map you are standing in."])
    f._zoneCB:SetPoint("TOPLEFT", f._scopeDD, "BOTTOMLEFT", 0, -CHECK_GAP)

    f._count = ctx:CreateText(side, "", "hint")
    f._count:SetPoint("TOPLEFT", f._zoneCB, "BOTTOMLEFT", 0, -COUNT_GAP)
    f._count:SetPoint("RIGHT", side, "RIGHT", -SIDE_PAD, 0)

    f._list = ctx:CreateList(side, function(id)
        local QLink = ns:GetSubsystem("QuestLink")
        if QLink and QLink:WantsShare() and QLink:Share(id) then return end
        QB:Select(id)
    end)
    f._list:SetPoint("TOPLEFT", f._count, "BOTTOMLEFT", -SIDE_PAD, -LIST_GAP)
    f._list:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)

    f._continentDD = ctx:CreateDropdown(side, nil, function() return self:ContinentOptions() end,
        function() return self._continent end,
        function(v) self._continent = v; self:RenderZoneList() end)
    f._continentDD:SetPoint("TOPLEFT", side, "TOPLEFT", SIDE_PAD, top)
    f._continentDD:SetPoint("TOPRIGHT", side, "TOPRIGHT", -SIDE_PAD, top)
    f._zoneList = ctx:CreateList(side, function(key) self:SelectZone(key) end)
    f._zoneList:SetPoint("TOPLEFT", f._continentDD, "BOTTOMLEFT", -SIDE_PAD, -LIST_GAP)
    f._zoneList:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", 0, 0)

    local area = ctx:CreateScrollArea(f.body, { clearGrip = true })
    area:SetAllPoints(f.body)
    f._area = area
    local content = area.content
    content._controls = {}
    f._content = content

    f._title = ctx:CreateText(content, "", "title")
    f._title:SetWordWrap(true)
    f._meta = ctx:CreateText(content, "", "hint")
    f._statusIcon = content:CreateTexture(nil, "ARTWORK")
    f._statusIcon:SetSize(STATUS_ICON, STATUS_ICON)
    f._status = ctx:CreateText(content, "", "label")
    f._status:SetWordWrap(true)
    f._zoneNote = ctx:CreateText(content, "", "hint")
    f._zoneNote:SetWordWrap(true)
    f._hide = ctx:CreateCheckbox(content, L["Hide from the map"],
        function()
            local A = avail()
            return A and A.IsHidden and A:IsHidden(QB:ShownQuest())
        end,
        function(v)
            local A = avail()
            local id = QB:ShownQuest()
            if A and A.SetHidden and id then A:SetHidden(id, v) end
        end,
        nil)
    f._hide:HookScript("OnEnter", function()
        local tip = L["Takes this quest's gold quest marker off your world map and minimap, and out of the \"Available to you\" list, for this character only. You can also Shift-click a gold quest marker on the world map, with no chat box open, to pick which of its quests to hide. Pick \"Hidden by you\" in the menu above the quest list to see the quests you hid."]
        if ns.HAS_CLASSIC_SPAWNS and C_SuperTrack then
            tip = tip .. " " .. L["WoW Forever itself still marks the quest giver when you are near, and a chain you track in the Chain Guide still marks its next step."]
        end
        ctx:ShowTooltip(f._hide, L["Hide from the map"], tip)
    end)
    f._hide:HookScript("OnLeave", function() ctx:HideTooltip() end)
    f._directions = ctx:CreateButton(content, L["Get Directions"], nil, function() QB:GetDirections() end)
    f._empty = ctx:CreateEmptyState(f.body, L["Pick a quest on the left."])
    f._empty:SetPoint("TOP", f.body, "CENTER", 0, 8)

    f._back = ctx:CreateButton(content, L["Back"], nil, function() QB:BackToZone() end)
    -- The count's tooltip sits on a frame of its own, shown and hidden with the line, so it never lingers on a quest's page
    f._zoneProgHit = CreateFrame("Frame", nil, content)
    f._zoneProg = ctx:CreateText(f._zoneProgHit, "", "label")
    f._zoneProg:SetPoint("TOPLEFT", f._zoneProgHit, "TOPLEFT")
    f._zonePct = ctx:CreateText(content, "", "hint")
    f._zoneBar = ctx:CreateProgressBar(content, 100)
    ctx:AttachTooltip(f._zoneProgHit, nil,
        L["Counts the quests your character has done, has in its quest log or can still take. Repeatable quests, dailies and quests closed to you are left out."])
    f._zoneEmpty = ctx:CreateEmptyState(f.body, L["Pick a zone on the left."])
    f._zoneEmpty:SetPoint("TOP", f.body, "CENTER", 0, 8)

    -- Quest, level, skill and reputation events drop the index. A daily reset or a season's start has none, so it shows at the next open
    local Events = ns:GetSubsystem("Events")
    if Events and Events.On then
        local function changed()
            self._index = nil
            if not (self.frame:IsShown() and self._mode == "zones" and Events.Debounce) then return end
            Events:Debounce("eq.questbrowser.zones", 0.5, function()
                if not (self.frame:IsShown() and self._mode == "zones") then return end
                self:RenderZoneList()
                self:RenderBody()
            end)
        end
        for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "PLAYER_LEVEL_UP",
                                 "PLAYER_LEVEL_CHANGED", "SKILL_LINES_CHANGED", "UPDATE_FACTION" }) do
            Events:On(event, changed)
        end
    end
    self:ShowMode()
end

local function zoneName(mapID)
    local D = data()
    return D and D:ZoneName(mapID) or nil
end

local function playerMap()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    return ok and id or nil
end

local _listRows = {}

function QB:RenderList()
    local f = self.frame
    if not f then return end
    local D = data()
    if not (D and D:Loaded()) then
        f._count:SetText(L["No quest data on this version of the game."])
        f._list:SetRows({})
        return
    end

    local mapID = self._zoneOnly and playerMap() or nil
    f:SetSection(mapID and zoneName(mapID) or nil)

    local rows, matched = D:Query({
        text  = f._search:GetText(),
        scope = self._scope or "all",
        mapID = mapID,
        limit = MAX_ROWS,
    })
    local shown = #rows
    if matched > shown then
        f._count:SetText((L["%d quests (showing the first %d)"]):format(matched, shown))
    else
        f._count:SetText((L["%d quests"]):format(matched))
    end

    -- A quest the map would not mark now, by its rules, its filters or a hide, is dimmed unless it is in your log, and done ones carry a check
    local A = avail()
    for i = #_listRows, shown + 1, -1 do _listRows[i] = nil end
    for i = 1, shown do
        local q = rows[i]
        local available = A and A:Explain(q.id) == true
        local inLog = A and A:InLog(q.id)
        local done = A and A:IsCompleted(q.id)
        local row = _listRows[i] or {}
        _listRows[i] = row
        row.key, row.text = q.id, q.name or ("Quest #" .. tostring(q.id))
        row.value = q.level > 0 and tostring(q.level) or "-"
        row.selected = (q.id == self._selected)
        row.muted = not (available or inLog)
        row.icons = done and DONE_ICONS or nil
    end
    f._list:SetRows(_listRows)
end

local _y, _width = 0, 0

-- The scroll frame's own width, which leaves room for the bars, so the content never scrolls sideways
local function contentWidth(f)
    local w = f._area.scroll:GetWidth() or 0
    if w <= 0 then w = (f.body:GetWidth() or 0) - BAR_ROOM end
    if w <= 0 then w = DEFAULT_W - SIDEBAR_W - BAR_ROOM end
    return w
end

local function placeRow(ctx, card, kind, prevRow, y)
    local r = acquire("row_" .. kind, function() return makeRow(ctx, QB.frame._content, kind) end)
    r:SetFrameLevel(card:GetFrameLevel() + 1)
    r:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -y)
    r:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, -y)
    r.div:SetShown(prevRow ~= nil)
    r._questID, r._mapID, r._px, r._py, r._title, r._chainID, r._chainQuest = nil, nil, nil, nil, nil, nil, nil
    r._zoneQuestID, r._tipTitle, r._tipBody = nil, nil, nil
    r.icon:Hide()
    r.text:ClearAllPoints()
    r.text:SetPoint("LEFT", r, "LEFT", ROW_PAD, 0)
    r.text:SetPoint("RIGHT", r.value, "LEFT", -ROW_ICON_GAP, 0)
    r.text:SetWordWrap(false)
    r.text:SetTextColor(ctx:Color("text"))
    r.value:SetText("")
    r:SetHeight(ROW_H)
    return r
end

local function withIcon(ctx, r, file, color)
    r.icon:SetTexture(file)
    if color then r.icon:SetVertexColor(ctx:Color(color)) else r.icon:SetVertexColor(1, 1, 1, 1) end
    r.icon:Show()
    r.text:SetPoint("LEFT", r.icon, "RIGHT", ROW_ICON_GAP, 0)
end

local function group(ctx, title, build)
    local content = QB.frame._content
    _y = _y + GROUP_GAP
    local label = acquire("label", function() return ctx:CreateText(content, "", "groupLabel") end)
    label:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    label:SetText(title)
    _y = _y + (label:GetStringHeight() or 12) + LABEL_GAP
    local card = acquire("card", function() return makeCard(ctx, content) end)
    card:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    card:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -_y)
    local h = build(card)
    card:SetHeight(math.max(1, h))
    _y = _y + h
end

local function textRows(ctx, card, lines)
    local y, prev = 0, nil
    local w = _width - PAD_SIDE * 2 - ROW_PAD * 2
    for _, text in ipairs(lines) do
        local r = placeRow(ctx, card, "text", prev, y)
        r.text:ClearAllPoints()
        r.text:SetPoint("TOPLEFT", r, "TOPLEFT", ROW_PAD, -TEXT_PAD)
        r.text:SetWidth(w)
        r.text:SetWordWrap(true)
        r.text:SetTextColor(ctx:Color("label"))
        r.text:SetText(text)
        local h = math.max(ROW_H, (r.text:GetStringHeight() or 13) + TEXT_PAD * 2)
        r:SetHeight(h)
        y, prev = y + h, r
    end
    return y
end

local function placeRows(ctx, card, list, questTitle)
    local y, prev = 0, nil
    for _, p in ipairs(list) do
        local r = placeRow(ctx, card, "place", prev, y)
        local label = p.name or (p.kind and sourceText(p.kind)) or zoneName(p.mapID) or ("map " .. tostring(p.mapID))
        if not p.name then r.text:SetTextColor(ctx:Color("label")) end
        r.text:SetText(label)
        local value = ("%s  %.1f, %.1f"):format(zoneName(p.mapID) or ("map " .. tostring(p.mapID)), p.x * 100, p.y * 100)
        if p.points and p.points > 1 then value = value .. SEP .. (L["%d locations"]):format(p.points) end
        r.value:SetText(value)
        r._mapID, r._px, r._py, r._title = p.mapID, p.x, p.y, questTitle
        y, prev = y + ROW_H, r
    end
    return y
end

local function refRows(ctx, card, list)
    local y, prev = 0, nil
    for _, q in ipairs(list) do
        -- Only a quest the data can describe gets a link, since one it cannot would clear the pane
        local r = placeRow(ctx, card, q.known ~= false and "quest" or "text", prev, y)
        if q.done then withIcon(ctx, r, ctx:Texture("check"), "muted") end
        r.text:SetText(q.name or ("Quest #" .. tostring(q.id)))
        if q.known ~= false then r._questID = q.id else r.text:SetTextColor(ctx:Color("muted")) end
        y, prev = y + ROW_H, r
    end
    return y
end

-- Signed rather than colored, as History's deltas are, so the card adds no color of its own
local function repRows(ctx, card, list)
    local y, prev = 0, nil
    for _, e in ipairs(list) do
        local r = placeRow(ctx, card, e.derived and "repLoss" or "rep", prev, y)
        r.text:SetText(e.name or (L["faction %d"]):format(e.faction))
        r.value:SetText(("%+d"):format(e.amount))
        y, prev = y + ROW_H, r
    end
    return y
end

-- What else one NPC offers and takes in, the right column saying which
local function moreRows(ctx, card, list)
    local y, prev = 0, nil
    for _, q in ipairs(list) do
        local r = placeRow(ctx, card, q.known and "quest" or "text", prev, y)
        if q.done then withIcon(ctx, r, ctx:Texture("check"), "muted") end
        r.text:SetText(q.level > 0 and ("[%d] %s"):format(q.level, q.name) or q.name)
        if q.known then r._questID = q.id else r.text:SetTextColor(ctx:Color("muted")) end
        local does = {}
        if q.starts then does[#does + 1] = L["Starts"] end
        if q.ends then does[#does + 1] = L["Turn in"] end
        r.value:SetText(table.concat(does, SEP))
        y, prev = y + ROW_H, r
    end
    return y
end

local function statusOf(record, available, reason)
    if record.failed then return L["Failed, so you can take it again."], GOSSIP_AVAILABLE end
    if available then return L["You can pick this up now."], GOSSIP_AVAILABLE end
    local text = reason and reasonText(reason) or L["Not available to you right now."]
    if record.completed then return text, "check" end
    if record.inLog then return text, GOSSIP_ACTIVE end
    return text, nil
end

-- Only for a quest that can still get a gold quest marker, and always for one already hidden so it can be shown again
local function hideOffered(A, record)
    if not (A and A.SetHidden) then return false end
    if A:IsHidden(record.id) then return true end
    if not record.starts or (record.completed and not record.isRepeatable) then return false end
    if record.maxLevel and UnitLevel and (UnitLevel("player") or 0) > record.maxLevel then return false end
    if A.RuledOut and A:RuledOut(record.id) then return false end
    return A:CanEverTake(record.id) ~= false and not A:Ended(record.id)
end

function QB:RenderDetails()
    local f = self.frame
    if not f then return end
    local ctx = self._ctx
    release()
    local content = f._content
    _width = contentWidth(f)
    _y = PAD_TOP

    local D = data()
    local fromZone = self._mode == "zones" and self._zoneQuest or nil
    local questID = fromZone or self._selected
    local record = questID and D and D:Record(questID)
    local available, reason = record and record.available, record and record.reason
    -- Opened from a zone, the page says what its row says, which leaves the map's display filters out
    local row = record and fromZone and self:ZoneRow(questID)
    if row then
        available = row.status == "available"
        if row.status == "done" then reason = "completed"
        elseif row.status == "log" then reason = "in your quest log"
        elseif row.status == "notYet" or row.status == "closed" then reason = row.reason end
    end
    local parts = { f._title, f._meta, f._statusIcon, f._status, f._directions }
    for _, p in ipairs({ f._zoneProgHit, f._zonePct, f._zoneBar, f._zoneEmpty }) do p:Hide() end
    f._back:SetShown(record ~= nil and fromZone ~= nil)
    if not record then
        for _, p in ipairs(parts) do p:Hide() end
        f._zoneNote:Hide()
        f._hide:Hide()
        f._empty:Show()
        f._area:SetContentSize(_width, 1)
        return
    end
    for _, p in ipairs(parts) do p:Show() end
    f._empty:Hide()
    self._record = record

    if fromZone then
        if f._back.Fit then f._back:Fit() end
        f._back:ClearAllPoints()
        f._back:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
        _y = _y + f._back:GetHeight() + STATUS_GAP
    end

    local kind = D:Waypoint(record)
    f._directions:SetShown(kind ~= nil)
    if f._directions.Fit then f._directions:Fit() end
    f._directions:ClearAllPoints()
    f._directions:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -PAD_TOP)
    local textW = _width - PAD_SIDE * 2 - (kind and (f._directions:GetWidth() + BUTTON_GAP) or 0)

    f._title:ClearAllPoints()
    f._title:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    f._title:SetWidth(textW)
    f._title:SetText(record.name)
    _y = _y + (f._title:GetStringHeight() or 15)

    local bits = { "#" .. record.id }
    if record.level then bits[#bits + 1] = (L["Level %d"]):format(record.level) end
    if record.reqLevel and record.maxLevel and record.maxLevel > record.reqLevel then
        bits[#bits + 1] = (L["Requires level %d to %d"]):format(record.reqLevel, record.maxLevel)
    elseif record.reqLevel then
        bits[#bits + 1] = (L["Requires level %d"]):format(record.reqLevel)
    end
    _y = _y + META_GAP
    f._meta:ClearAllPoints()
    f._meta:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    f._meta:SetText(table.concat(bits, SEP))
    _y = _y + (f._meta:GetStringHeight() or 12)

    local status, icon = statusOf(record, available, reason)
    _y = _y + STATUS_GAP
    local textLeft = PAD_SIDE
    if icon then
        f._statusIcon:SetTexture(icon == "check" and ctx:Texture("check") or icon)
        if icon == "check" then f._statusIcon:SetVertexColor(ctx:Color("muted")) else f._statusIcon:SetVertexColor(1, 1, 1, 1) end
        f._statusIcon:ClearAllPoints()
        f._statusIcon:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
        f._statusIcon:Show()
        textLeft = PAD_SIDE + STATUS_ICON + ROW_ICON_GAP
    else
        f._statusIcon:Hide()
    end
    f._status:ClearAllPoints()
    f._status:SetPoint("TOPLEFT", content, "TOPLEFT", textLeft, -_y)
    f._status:SetWidth(textW - (textLeft - PAD_SIDE))
    f._status:SetTextColor(ctx:Color((available or record.failed) and "text" or "label"))
    f._status:SetText(status)
    _y = _y + math.max(STATUS_ICON, f._status:GetStringHeight() or 13)

    local tags = {}
    if record.isInstance   then tags[#tags + 1] = L["Dungeon or raid"] end
    if record.isRepeatable then tags[#tags + 1] = L["Repeatable"] end
    if record.isEvent      then tags[#tags + 1] = L["World event"] end
    if record.isClassQuest then tags[#tags + 1] = L["Class quest"] end
    if record.isProfession then tags[#tags + 1] = L["Profession"] end
    if record.isBreadcrumb then tags[#tags + 1] = L["Breadcrumb"] end
    if #tags > 0 then
        _y = _y + TAG_GAP
        local prev
        for _, text in ipairs(tags) do
            local t = acquire("tag", function() return ctx:CreateTag(content, "", "outline") end)
            t:SetText(text)
            if prev then t:SetPoint("LEFT", prev, "RIGHT", TAG_SPACING, 0)
            else t:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y) end
            prev = t
        end
        _y = _y + prev:GetHeight()
    end

    local CS = ns:GetSubsystem("ChainGuideClassicSource")
    local note = CS and CS:ZoneNotice(record.id)
    f._zoneNote:SetShown(note ~= nil)
    if note then
        _y = _y + TAG_GAP
        f._zoneNote:ClearAllPoints()
        f._zoneNote:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
        f._zoneNote:SetWidth(_width - PAD_SIDE * 2)
        f._zoneNote:SetText(note)
        _y = _y + (f._zoneNote:GetStringHeight() or 12)
    end

    local canHide = hideOffered(avail(), record)
    f._hide:SetShown(canHide)
    if canHide then
        _y = _y + TAG_GAP
        f._hide:ClearAllPoints()
        f._hide:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
        f._hide:Refresh()
        _y = _y + f._hide:GetHeight()
    end

    local reqs = {}
    if record.races   then reqs[#reqs + 1] = (L["Races: %s"]):format(table.concat(record.races, ", ")) end
    if record.classes then reqs[#reqs + 1] = (L["Classes: %s"]):format(table.concat(record.classes, ", ")) end
    if record.skill then
        local skill = record.skill
        if skill.name and skill.value <= 1 then
            reqs[#reqs + 1] = (L["Requires %s"]):format(skill.name)
        elseif skill.name then
            reqs[#reqs + 1] = (L["Requires %1$s at rank %2$d"]):format(skill.name, skill.value)
        else
            reqs[#reqs + 1] = (L["Requires a profession at rank %d"]):format(skill.value)
        end
    end
    if record.minRep then
        local who = record.minRep.name or (L["faction %d"]):format(record.minRep.faction)
        reqs[#reqs + 1] = (L["Requires %s with %s"]):format(record.minRep.standing or tostring(record.minRep.value), who)
    end
    if record.maxRep then
        local who = record.maxRep.name or (L["faction %d"]):format(record.maxRep.faction)
        reqs[#reqs + 1] = (L["Only below %s with %s"]):format(record.maxRep.standing or tostring(record.maxRep.value), who)
    end
    if #reqs > 0 then group(ctx, L["Requirements"], function(card) return textRows(ctx, card, reqs) end) end
    if record.rep then group(ctx, L["Reputation"], function(card) return repRows(ctx, card, record.rep) end) end

    if record.starts then group(ctx, L["Starts"], function(card) return placeRows(ctx, card, record.starts, record.name) end) end
    if record.objectives then group(ctx, L["Objectives"], function(card) return placeRows(ctx, card, record.objectives, record.name) end) end
    if record.turnIn then group(ctx, L["Turn in"], function(card) return placeRows(ctx, card, record.turnIn, record.name) end) end

    if record.pre and #record.pre > 0 then
        group(ctx, record.preMode == "all" and L["Finish all of these first"] or L["Finish one of these first"],
            function(card) return refRows(ctx, card, record.pre) end)
    end
    local AD = avail() and avail().Data and avail():Data()
    local function known(ref)
        return { id = ref.id, name = ref.name, done = ref.done, known = AD ~= nil and AD.gates[ref.id] ~= nil }
    end
    if record.parent then group(ctx, L["Part of"], function(card) return refRows(ctx, card, { known(record.parent) }) end) end
    if record.leadsTo and #record.leadsTo > 0 then group(ctx, L["Leads to"], function(card) return refRows(ctx, card, record.leadsTo) end) end
    if record.breadcrumbs and #record.breadcrumbs > 0 then
        group(ctx, L["Breadcrumb quests that lead here"], function(card) return refRows(ctx, card, record.breadcrumbs) end)
    end
    if record.excl and #record.excl > 0 then group(ctx, L["Instead of"], function(card) return refRows(ctx, card, record.excl) end) end

    local chainID = CS and CS:ChainForQuest(record.id)
    local Database = chainID and ns:GetSubsystem("ChainGuideDatabase")
    local chain = Database and Database.chains[chainID]
    if chain then
        group(ctx, L["Chain"], function(card)
            local r = placeRow(ctx, card, "chain", nil, 0)
            withIcon(ctx, r, ctx:Texture("icon-chain"), "accentHi")
            r.text:SetText(chain.name)
            r._chainID, r._chainQuest = chainID, record.id
            return ROW_H
        end)
    end
    -- Last, as a busy quest giver's lists run long
    for _, g in ipairs(record.moreFrom or {}) do
        group(ctx, (L["More from %s"]):format(g.name), function(card) return moreRows(ctx, card, g.rows) end)
    end

    f._area:SetContentSize(_width, _y + PAD_BOTTOM)
end

local function dungeonKey()
    local D = data()
    return D and D.DUNGEON_KEY or 10000000
end

local function battlegroundKey()
    local D = data()
    return D and D.BATTLEGROUND_KEY or 20000000
end

local _areaName = {}
local function areaName(areaID)
    local cached = _areaName[areaID]
    if cached ~= nil then return cached or nil end
    local name
    if C_Map and C_Map.GetAreaInfo then
        local ok, got = pcall(C_Map.GetAreaInfo, areaID)
        if ok and type(got) == "string" and got ~= "" then name = got end
    end
    _areaName[areaID] = name or false
    return name
end

local CONTINENT_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Continent) or 2
local ZONE_TYPE = (Enum and Enum.UIMapType and Enum.UIMapType.Zone) or 3

-- The continent a zone is on, else its highest map below the world, as WoW Forever's Zephras Isle is on no continent
local _continent = {}
local function continentOf(mapID)
    local cached = _continent[mapID]
    if cached ~= nil then return cached or nil end
    local id, found, top = mapID, false, false
    if C_Map and C_Map.GetMapInfo then
        for _ = 1, 8 do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            if not (ok and type(info) == "table") then break end
            if info.mapType == CONTINENT_TYPE then found = id break end
            if type(info.mapType) == "number" and info.mapType > CONTINENT_TYPE then top = id end
            if not info.parentMapID or info.parentMapID == 0 then break end
            id = info.parentMapID
        end
    end
    _continent[mapID] = found or top
    return _continent[mapID] or nil
end

local function groupKeyOf(key)
    if key == "battleground" then return "battlegrounds" end
    if type(key) ~= "number" then return "other" end
    if key >= battlegroundKey() then return "battlegrounds" end
    if key >= dungeonKey() then return "dungeons" end
    return continentOf(key) or "other"
end

local function entryName(key)
    if type(key) == "number" then
        if key >= battlegroundKey() then return areaName(key - battlegroundKey()) or L["Battlegrounds"] end
        if key >= dungeonKey() then return areaName(key - dungeonKey()) or L["Dungeon or raid"] end
        return zoneName(key) or ("map " .. tostring(key))
    end
    if key == "class" then return (UnitClass and UnitClass("player")) or L["Class quest"] end
    if key == "profession" then return L["Professions"] end
    if key == "event" then return L["World events"] end
    if key == "battleground" then return L["Battlegrounds"] end
    return L["Other"]
end

local function levelText(e)
    if not e.minLevel then return nil end
    if e.minLevel == e.maxLevel then return (L["Level %d"]):format(e.minLevel) end
    return (L["Level %d–%d"]):format(e.minLevel, e.maxLevel)
end

-- A heading whose every quest is closed to this character, such as the other faction's capital, is left out
local function shownEntry(e)
    if e.total > 0 then return true end
    for _, q in ipairs(e.quests) do
        if q.status ~= "closed" then return true end
    end
    return false
end

function QB:Index()
    if not self._index then
        local D = data()
        self._index = (D and D.ZoneIndex and D:ZoneIndex()) or {}
    end
    return self._index
end

-- The menu asks for its options as it is made, which must not build the index for the quest list
function QB:ContinentOptions()
    if self._mode ~= "zones" then return {} end
    local seen, continents, hasDungeons, hasBattlegrounds, hasOther = {}, {}, false, false, false
    for key, e in pairs(self:Index()) do
        if shownEntry(e) then
            local g = groupKeyOf(key)
            if type(g) == "number" then
                if not seen[g] then seen[g] = true; continents[#continents + 1] = g end
            elseif g == "dungeons" then hasDungeons = true
            elseif g == "battlegrounds" then hasBattlegrounds = true
            else hasOther = true end
        end
    end
    table.sort(continents)
    local options = {}
    for _, c in ipairs(continents) do options[#options + 1] = { value = c, label = zoneName(c) or ("map " .. tostring(c)) } end
    if hasDungeons then options[#options + 1] = { value = "dungeons", label = L["Dungeon and raid quests"] } end
    if hasBattlegrounds then options[#options + 1] = { value = "battlegrounds", label = L["Battlegrounds"] } end
    if hasOther then options[#options + 1] = { value = "other", label = L["Other"] } end
    return options
end

-- The zone you stand in, from a cave or a building up to its zone
local function playerZone()
    local id = playerMap()
    if not (id and C_Map and C_Map.GetMapInfo) then return nil end
    for _ = 1, 8 do
        local ok, info = pcall(C_Map.GetMapInfo, id)
        if not (ok and type(info) == "table") then return nil end
        if info.mapType == ZONE_TYPE then return id end
        if not info.parentMapID or info.parentMapID == 0 then return nil end
        id = info.parentMapID
    end
    return nil
end

function QB:EnsureZoneDefaults()
    if self._continent then return end
    local here = playerZone()
    local e = here and self:Index()[here]
    if e and shownEntry(e) then
        self._zone = self._zone or here
        self._continent = groupKeyOf(here)
        self._scrollToZone = true
        return
    end
    local options = self:ContinentOptions()
    self._continent = options[1] and options[1].value
end

local function entryOrder(a, b)
    local ga, gb = GROUP_ORDER[a.key], GROUP_ORDER[b.key]
    if ga or gb then return (ga or 0) < (gb or 0) end
    if (a.minLevel or 999) ~= (b.minLevel or 999) then return (a.minLevel or 999) < (b.minLevel or 999) end
    local na, nb = entryName(a.key), entryName(b.key)
    if na ~= nb then return na < nb end
    return tostring(a.key) < tostring(b.key)
end

function QB:RenderZoneList()
    local f = self.frame
    if not f then return end
    local entries = {}
    for key, e in pairs(self:Index()) do
        if shownEntry(e) and groupKeyOf(key) == self._continent then entries[#entries + 1] = e end
    end
    table.sort(entries, entryOrder)
    local rows, at = {}, nil
    for i, e in ipairs(entries) do
        local name = entryName(e.key)
        if e.key == self._zone then at = i end
        rows[i] = {
            key = e.key, text = name,
            value = e.total > 0 and ("%d / %d"):format(e.done, e.total) or "",
            selected = e.key == self._zone,
            icons = (e.total > 0 and e.done == e.total) and DONE_ICONS or nil,
            tip = { name, levelText(e) },
        }
    end
    f._zoneList:SetRows(rows)
    -- Your own zone is brought into view once, and asked again while the list has no height yet
    if self._scrollToZone and at and f._zoneList:ScrollToRow(at) then self._scrollToZone = nil end
    if f._continentDD.Refresh then f._continentDD:Refresh() end
end

-- What a quest still needs, short enough for the row's right end. The tooltip has the whole sentence
local function shortReason(q)
    local r = q.reason
    if r == "too low level" then
        local A = avail()
        local req = A and A:RequiredLevel(q.id)
        return req and (L["Requires level %d"]):format(req) or nil
    end
    if r == "prerequisite" or r == "breadcrumb in your log" then return L["Earlier quest first"] end
    if r == "reputation" then return L["Reputation"] end
    if r == "profession" then return L["Profession"] end
    if r == "holiday quest" then return L["World event"] end
    if r == "daily done today" then return L["Done today"] end
    return nil
end

local STATUS_GROUPS = {
    { status = "log",       title = function() return L["In your quest log"] end },
    { status = "available", title = function() return L["Available to you"] end },
    { status = "notYet",    title = function() return L["Not yet"] end },
    { status = "done",      title = function() return L["Completed"] end },
    { status = "closed",    title = function() return L["Not for you"] end },
}

local function statusSentence(q)
    if q.status == "available" then return L["You can pick this up now."] end
    if q.status == "log" then return reasonText("in your quest log") end
    if q.status == "done" then return reasonText("completed") end
    return q.reason and reasonText(q.reason) or L["Not available to you right now."]
end

local function zoneRows(ctx, card, list)
    local A = avail()
    local y, prev = 0, nil
    for _, q in ipairs(list) do
        local r = placeRow(ctx, card, "zq", prev, y)
        if q.status == "available" then withIcon(ctx, r, GOSSIP_AVAILABLE)
        elseif q.status == "log" then withIcon(ctx, r, GOSSIP_ACTIVE)
        elseif q.status == "done" then withIcon(ctx, r, ctx:Texture("check"), "muted") end
        local name = (A and A:Title(q.id)) or q.sortName
        r.text:SetText(name)
        if q.status == "notYet" or q.status == "closed" then r.text:SetTextColor(ctx:Color("muted")) end
        local value = (q.status == "notYet" and shortReason(q)) or (q.repeatable and L["Repeatable"])
                      or (q.level > 0 and (L["Level %d"]):format(q.level)) or ""
        r.value:SetText(value)
        r._zoneQuestID, r._tipTitle = q.id, name
        r._tipBody = statusSentence(q) .. "\n" .. L["Click to open this quest"]
        y, prev = y + ROW_H, r
    end
    return y
end

function QB:RenderZone()
    local f = self.frame
    if not f then return end
    local ctx = self._ctx
    release()
    local content = f._content
    _width = contentWidth(f)
    _y = PAD_TOP
    for _, p in ipairs({ f._statusIcon, f._status, f._zoneNote, f._hide, f._directions, f._empty, f._back }) do p:Hide() end

    local e = self._zone and self:Index()[self._zone]
    f:SetSection(e and entryName(e.key) or nil)
    if not e then
        for _, p in ipairs({ f._title, f._meta, f._zoneProgHit, f._zonePct, f._zoneBar }) do p:Hide() end
        f._zoneEmpty:Show()
        f._area:SetContentSize(_width, 1)
        return
    end
    f._zoneEmpty:Hide()
    for _, p in ipairs({ f._title, f._zoneProgHit, f._zonePct, f._zoneBar }) do p:Show() end

    f._title:ClearAllPoints()
    f._title:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    f._title:SetWidth(_width - PAD_SIDE * 2)
    f._title:SetText(entryName(e.key))
    _y = _y + (f._title:GetStringHeight() or 15)

    local levels = levelText(e)
    f._meta:SetShown(levels ~= nil)
    if levels then
        _y = _y + META_GAP
        f._meta:ClearAllPoints()
        f._meta:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
        f._meta:SetText(levels)
        _y = _y + (f._meta:GetStringHeight() or 12)
    end

    _y = _y + STATUS_GAP
    f._zoneProg:SetText((L["%d of %d done"]):format(e.done, e.total))
    f._zoneProgHit:ClearAllPoints()
    f._zoneProgHit:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    f._zoneProgHit:SetSize(math.max(1, f._zoneProg:GetStringWidth() or 1), math.max(1, f._zoneProg:GetStringHeight() or 13))
    f._zonePct:ClearAllPoints()
    f._zonePct:SetPoint("TOPRIGHT", content, "TOPRIGHT", -PAD_SIDE, -_y)
    local frac = e.total > 0 and e.done / e.total or 0
    f._zonePct:SetText(("%d%%"):format(math.floor(frac * 100 + 0.5)))
    _y = _y + (f._zoneProg:GetStringHeight() or 13) + PROGRESS_GAP
    f._zoneBar:ClearAllPoints()
    f._zoneBar:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    f._zoneBar:SetWidth(math.max(1, _width - PAD_SIDE * 2))
    f._zoneBar:SetProgress(frac)
    _y = _y + f._zoneBar:GetHeight()

    for _, g in ipairs(STATUS_GROUPS) do
        local list = {}
        for _, q in ipairs(e.quests) do if q.status == g.status then list[#list + 1] = q end end
        if #list > 0 then
            group(ctx, g.title() .. SEP .. #list, function(card) return zoneRows(ctx, card, list) end)
        end
    end
    f._area:SetContentSize(_width, _y + PAD_BOTTOM)
end

function QB:RenderBody()
    if self._mode == "zones" and not self._zoneQuest then self:RenderZone() else self:RenderDetails() end
end

function QB:ShownQuest()
    if self._mode == "zones" and self._zoneQuest then return self._zoneQuest end
    return self._selected
end

-- A quest's row in the zone index, for a page opened from the Zones page
function QB:ZoneRow(questID)
    local D = data()
    local key = D and D.ZoneOf and D:ZoneOf(questID)
    local e = key and self:Index()[key]
    for _, q in ipairs(e and e.quests or {}) do
        if q.id == questID then return q end
    end
    return nil
end

function QB:ShowMode()
    local f = self.frame
    if not f then return end
    local quests = self._mode ~= "zones"
    for _, w in ipairs({ f._search, f._scopeDD, f._zoneCB, f._count, f._list }) do w:SetShown(quests) end
    f._continentDD:SetShown(not quests)
    f._zoneList:SetShown(not quests)
end

function QB:SetMode(mode)
    self._mode = mode
    local f = self.frame
    if not f then return end
    f.nav:Select(mode)
    self:ShowMode()
    if mode == "zones" then
        self._zoneQuest = nil
        self:EnsureZoneDefaults()
        self:RenderZoneList()
    else
        self:RenderList()
    end
    self:RenderBody()
    f._area:ScrollTo(0, 0)
end

function QB:SelectZone(key)
    self._zone, self._zoneQuest = key, nil
    self:RenderZoneList()
    self:RenderBody()
    if self.frame then self.frame._area:ScrollTo(0, 0) end
end

function QB:OpenFromZone(questID)
    self._zoneQuest = questID
    self:RenderBody()
    if self.frame then self.frame._area:ScrollTo(0, 0) end
end

function QB:BackToZone()
    self._zoneQuest = nil
    self:RenderBody()
    if self.frame then self.frame._area:ScrollTo(0, 0) end
end

function QB:Select(questID)
    self._selected = questID
    self:RenderList()
    self:RenderDetails()
    if self.frame then self.frame._area:ScrollTo(0, 0) end
end

local function showMap(mapID)
    local wm = _G.WorldMapFrame
    if wm and wm.SetMapID then
        if not wm:IsShown() and _G.ToggleWorldMap then _G.ToggleWorldMap() end
        pcall(wm.SetMapID, wm, mapID)
    end
end

-- The arrow, else the map. questID only for a quest in your log, whose arrow then follows it
function QB:GoTo(mapID, x, y, title, questID)
    local Arrow = ns:GetSubsystem("QuestArrow")
    if Arrow and Arrow:Available() and Arrow:Set(mapID, x, y, title, questID) then return end
    self:ShowMap(mapID)
end

-- after runs once the map is open, which in combat is when combat ends
function QB:ShowMap(mapID, after)
    -- Held until combat ends, as the Chain Guide's is: Forever's map pins call the protected SetPassThroughButtons as they appear
    if InCombatLockdown() then
        local Events = ns:GetSubsystem("Events")
        if Events and Events.RunWhenOutOfCombat then
            Events:RunWhenOutOfCombat("eq.questbrowser.map", function() showMap(mapID); if after then after() end end)
        end
        return
    end
    showMap(mapID)
    if after then after() end
end

-- Where you pick the quest up, or its turn-in, or a quest in your log's own next step
function QB:GetDirections()
    local D = data()
    local record = self._record
    if not (D and record) then return end
    local kind, mapID, x, y = D:Waypoint(record)
    if kind then self:GoTo(mapID, x, y, record.name, kind == "quest" and record.id or nil) end
end

-- Over the world map, which Era and TBC draw at FULLSCREEN when it is large, and otherwise beside the other windows
local function placeStrata(f)
    local wm = _G.WorldMapFrame
    local over = wm and wm:IsShown() and wm.GetFrameStrata
                 and (wm:GetFrameStrata() == "FULLSCREEN" or wm:GetFrameStrata() == "FULLSCREEN_DIALOG")
    f:SetFrameStrata(over and "FULLSCREEN_DIALOG" or "DIALOG")
end

-- list opens the quest list, as a search does
function QB:Open(questID, list)
    if not self:Available() then return end
    self:Build()
    local wasShown = self.frame:IsShown()
    placeStrata(self.frame)
    self.frame:Show()
    -- Above the Chain Guide, which opens it from a card's right-click
    self.frame:Raise()
    self._index = nil
    -- A quest opened from elsewhere opens in the quest list, whichever page was showing
    if (questID or list) and self._mode == "zones" then
        self._mode = "quests"
        self.frame.nav:Select("quests")
        self:ShowMode()
        self.frame._area:ScrollTo(0, 0)
    end
    if questID then
        self:Select(questID)
    elseif self._mode == "zones" and wasShown then
        self:RenderZoneList()
        self:RenderBody()
    elseif self._mode == "zones" then
        self:SetMode("zones")
    else
        self:RenderList()
        self:RenderDetails()
    end
end

-- After a quest is hidden or shown again, so the list and the page agree with it
function QB:Refresh()
    local f = self.frame
    if not (f and f:IsShown()) then return end
    self._index = nil
    if self._mode == "zones" then self:RenderZoneList() else self:RenderList() end
    self:RenderBody()
end

function QB:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        return
    end
    self:Open()
end

-- Gated on the data table's own presence like every other Classic split here, never on a build
-- number. On retail the tables are not listed by the TOC, so the window has nothing to show and
-- the entry points hide themselves rather than opening an empty frame.
function QB:Available()
    local D = data()
    return (D and D:Loaded()) == true and ns:GetSubsystem("Options") ~= nil
end

function QB:Search(text)
    local query = text and text ~= ""
    self:Open(nil, query)
    if self.frame and query then
        self.frame._search:SetText(text)
        self:RenderList()
    end
end
