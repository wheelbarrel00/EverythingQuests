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

-- The gate returns its refusal as a stable English key. Mapping it here with a literal L key per
-- branch is what keeps the phrase visible to the locale scanner - a computed L[reason] lookup
-- would work in game and never reach a translator.
local function reasonText(reason)
    if reason == "completed"            then return L["You have already completed this quest."] end
    if reason == "in your quest log"    then return L["This quest is already in your quest log."] end
    if reason == "holiday quest"        then return L["Part of a world event, so it is only offered while that event is running."] end
    if reason == "race or class"        then return L["Your race or class cannot take this quest."] end
    if reason == "too low level"        then return L["You do not meet the required level yet."] end
    if reason == "low level"            then return L["Too far below your level to be worth showing. Turn off the low level filter to see it."] end
    if reason == "high level"           then return L["The game colors this quest red for you, so it is out of reach for now. Turn off the high level filter to see it."] end
    if reason == "prerequisite"         then return L["An earlier quest has to be finished first."] end
    if reason == "later step done"      then return L["A later step of this chain is already done or in your log."] end
    if reason == "took another branch"  then return L["You took a different branch of this quest line."] end
    if reason == "reputation"           then return L["Your reputation standing does not allow it."] end
    if reason == "dungeon or raid quest" then return L["Hidden by your dungeon and raid filter."] end
    if reason == "repeatable quest"     then return L["Hidden by your repeatable quest filter."] end
    if reason == "profession quest"     then return L["Hidden by your profession quest filter."] end
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
    place = function() return L["Click to open the map here and set a waypoint"] end,
    quest = function() return L["Click to open this quest"] end,
    chain = function() return L["Find this quest in EQ's Chain Guide"] end,
}

local function rowClick(self)
    if self._questID then
        local QLink = ns:GetSubsystem("QuestLink")
        if QLink and QLink:WantsShare() and QLink:Share(self._questID) then return end
        QB:Select(self._questID)
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
    if kind ~= "text" then
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
            self:RenderDetails()
        end,
    })
    self.frame = f

    f.resizeHint = ctx:CreateText(f.grip, L["Drag to resize"], "hint")
    f.resizeHint:SetPoint("RIGHT", f.grip, "LEFT", -HINT_GAP, 0)
    local cfg = browserCfg()
    if cfg and cfg.resizeHintSeen then f.resizeHint:Hide() end

    local side = f.sidebar
    f._search = ctx:CreateSearchField(side, L["Find quest"], function() self:RenderList() end,
        L["Find quest"], L["Type part of a quest's name or its ID. Put the name in quotes to match the whole title."])
    f._search:SetPoint("TOPLEFT", side, "TOPLEFT", SIDE_PAD, -SIDE_PAD)
    f._search:SetPoint("TOPRIGHT", side, "TOPRIGHT", -SIDE_PAD, -SIDE_PAD)
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

    local area = ctx:CreateScrollArea(f.body, {})
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
    f._directions = ctx:CreateButton(content, L["Get Directions"], nil, function() QB:GetDirections() end)
    f._empty = ctx:CreateEmptyState(f.body, L["Pick a quest on the left."])
    f._empty:SetPoint("TOP", f.body, "CENTER", 0, 8)
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

    -- Quests you can neither take now nor have in your log are dimmed, and done ones carry a check
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

local function statusOf(record)
    if record.failed then return L["Failed, so you can take it again."], GOSSIP_AVAILABLE end
    if record.available then return L["You can pick this up now."], GOSSIP_AVAILABLE end
    local text = record.reason and reasonText(record.reason) or L["Not available to you right now."]
    if record.completed then return text, "check" end
    if record.inLog then return text, GOSSIP_ACTIVE end
    return text, nil
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
    local record = self._selected and D and D:Record(self._selected)
    local parts = { f._title, f._meta, f._statusIcon, f._status, f._directions }
    if not record then
        for _, p in ipairs(parts) do p:Hide() end
        f._empty:Show()
        f._area:SetContentSize(_width, 1)
        return
    end
    for _, p in ipairs(parts) do p:Show() end
    f._empty:Hide()
    self._record = record

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
    if record.reqLevel then bits[#bits + 1] = (L["Requires level %d"]):format(record.reqLevel) end
    _y = _y + META_GAP
    f._meta:ClearAllPoints()
    f._meta:SetPoint("TOPLEFT", content, "TOPLEFT", PAD_SIDE, -_y)
    f._meta:SetText(table.concat(bits, SEP))
    _y = _y + (f._meta:GetStringHeight() or 12)

    local status, icon = statusOf(record)
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
    f._status:SetTextColor(ctx:Color(record.available and "text" or "label"))
    f._status:SetText(status)
    _y = _y + math.max(STATUS_ICON, f._status:GetStringHeight() or 13)

    local tags = {}
    if record.isInstance   then tags[#tags + 1] = L["Dungeon or raid"] end
    if record.isRepeatable then tags[#tags + 1] = L["Repeatable"] end
    if record.isEvent      then tags[#tags + 1] = L["World event"] end
    if record.isClassQuest then tags[#tags + 1] = L["Class quest"] end
    if record.isProfession then tags[#tags + 1] = L["Profession"] end
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

    local reqs = {}
    if record.races   then reqs[#reqs + 1] = (L["Races: %s"]):format(table.concat(record.races, ", ")) end
    if record.classes then reqs[#reqs + 1] = (L["Classes: %s"]):format(table.concat(record.classes, ", ")) end
    if record.skill then
        -- The skill line id has no name lookup on this client, so the rank is all that can be
        -- stated without inventing a profession name.
        reqs[#reqs + 1] = (L["Requires a profession at rank %d"]):format(record.skill.value)
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
    if record.chain then group(ctx, L["Leads to"], function(card) return refRows(ctx, card, { known(record.chain) }) end) end
    if record.excl and #record.excl > 0 then group(ctx, L["Instead of"], function(card) return refRows(ctx, card, record.excl) end) end

    local CS = ns:GetSubsystem("ChainGuideClassicSource")
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

    f._area:SetContentSize(_width, _y + PAD_BOTTOM)
end

function QB:Select(questID)
    self._selected = questID
    self:RenderList()
    self:RenderDetails()
    if self.frame then self.frame._area:ScrollTo(0, 0) end
end

-- Both effects on one click, because a browser row is asking "where is this" and the answer is
-- worth having on the map and on the arrow at the same time.
local function showMap(mapID)
    local wm = _G.WorldMapFrame
    if wm and wm.SetMapID then
        if not wm:IsShown() and _G.ToggleWorldMap then _G.ToggleWorldMap() end
        pcall(wm.SetMapID, wm, mapID)
    end
end

function QB:GoTo(mapID, x, y, title)
    local Arrow = ns:GetSubsystem("QuestArrow")
    if Arrow and Arrow.Set then Arrow:Set(mapID, x, y, title) end
    -- Held until combat ends, as the Chain Guide's is: Forever's map pins call the protected SetPassThroughButtons as they appear
    if InCombatLockdown() then
        local Events = ns:GetSubsystem("Events")
        if Events and Events.RunWhenOutOfCombat then
            Events:RunWhenOutOfCombat("eq.questbrowser.map", function() showMap(mapID) end)
        end
        return
    end
    showMap(mapID)
end

-- Where you pick the quest up, or its turn-in, or a quest in your log's own next step
function QB:GetDirections()
    local D = data()
    local record = self._record
    if not (D and record) then return end
    local kind, mapID, x, y = D:Waypoint(record)
    if kind then self:GoTo(mapID, x, y, record.name) end
end

-- Over the world map, which Era and TBC draw at FULLSCREEN when it is large, and otherwise beside the other windows
local function placeStrata(f)
    local wm = _G.WorldMapFrame
    local over = wm and wm:IsShown() and wm.GetFrameStrata
                 and (wm:GetFrameStrata() == "FULLSCREEN" or wm:GetFrameStrata() == "FULLSCREEN_DIALOG")
    f:SetFrameStrata(over and "FULLSCREEN_DIALOG" or "DIALOG")
end

function QB:Open(questID)
    if not self:Available() then return end
    self:Build()
    placeStrata(self.frame)
    self.frame:Show()
    -- Above the Chain Guide, which opens it from a card's right-click
    self.frame:Raise()
    if questID then
        self:Select(questID)
    else
        self:RenderList()
        self:RenderDetails()
    end
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
    self:Open()
    if self.frame and text and text ~= "" then
        self.frame._search:SetText(text)
        self:RenderList()
    end
end
