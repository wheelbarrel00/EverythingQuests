local _, ns = ...
local L = ns.L

-- Everything the client cannot tell you about a quest you have not accepted. The data half lives
-- in QuestBrowserData, so this file only lays out what that returns.
local QB = ns:RegisterSubsystem("QuestBrowser", {})

local TITLE_BAR_H = 26
local TOOLBAR_H   = 26
local LIST_W      = 268
local ROW_H       = 26
local LINE_H      = 15
local MAX_ROWS    = 300

local YELLOW = ns.Util.color.buttonYellow
local RED    = ns.Util.color.brandRed
local MUTED  = ns.Util.color.muted
local DIM    = ns.Util.color.dim

local FONT_FILE = "Fonts\\ARIALN.TTF"
local function thin(fs)
    if not (fs and fs.GetFont and fs.SetFont) then return end
    local _, sz, fl = fs:GetFont()
    fs:SetFont(FONT_FILE, sz or 12, fl or "")
end

local function data()
    return ns:GetSubsystem("QuestBrowserData")
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

QB._rowPool,  QB._rowActive  = {}, {}
QB._linePool, QB._lineActive = {}, {}

local function listRowClick(self)
    QB:Select(self._questID)
end

local function buildListRow(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)
    r.sel = r:CreateTexture(nil, "BACKGROUND")
    r.sel:SetAllPoints()
    r.sel:SetColorTexture(RED[1], RED[2], RED[3], 0.45)
    r.sel:Hide()

    r.level = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.level:SetPoint("LEFT", 6, 0)
    r.level:SetWidth(28)
    r.level:SetJustifyH("RIGHT")

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.title:SetPoint("LEFT", r.level, "RIGHT", 6, 0)
    r.title:SetPoint("RIGHT", -6, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)

    thin(r.level); thin(r.title)
    r:SetScript("OnClick", listRowClick)
    return r
end

local function detailLineClick(self)
    if self._questID then
        QB:Select(self._questID)
    elseif self._mapID then
        QB:GoTo(self._mapID, self._px, self._py, self._title)
    end
end

local function detailLineEnter(self)
    if not (self._questID or self._mapID) then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    if self._questID then
        GameTooltip:SetText(L["Click to open this quest"], 1, 0.82, 0)
    else
        GameTooltip:SetText(L["Click to open the map here and set a waypoint"], 1, 0.82, 0)
    end
    GameTooltip:Show()
end

local function detailLineLeave() GameTooltip:Hide() end

local function buildDetailLine(parent)
    local d = CreateFrame("Button", nil, parent)
    d:SetHeight(LINE_H)
    d.hl = d:CreateTexture(nil, "HIGHLIGHT")
    d.hl:SetAllPoints()
    d.hl:SetColorTexture(1, 1, 1, 0.05)
    d.text = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d.text:SetPoint("LEFT", 0, 0)
    d.text:SetPoint("RIGHT", 0, 0)
    d.text:SetJustifyH("LEFT")
    thin(d.text)
    d:SetScript("OnClick", detailLineClick)
    d:SetScript("OnEnter", detailLineEnter)
    d:SetScript("OnLeave", detailLineLeave)
    return d
end

local function releaseRows()
    for i = #QB._rowActive, 1, -1 do
        local r = QB._rowActive[i]
        r:Hide()
        r:ClearAllPoints()
        r.sel:Hide()
        r._questID = nil
        QB._rowPool[#QB._rowPool + 1] = r
        QB._rowActive[i] = nil
    end
end

local function releaseLines()
    for i = #QB._lineActive, 1, -1 do
        local d = QB._lineActive[i]
        d:Hide()
        d:ClearAllPoints()
        d.hl:SetAlpha(1)
        d:EnableMouse(false)
        d.text:SetWordWrap(false)
        -- A pooled line keeps whatever font and height its last use gave it, so the title's large
        -- font would come back on an ordinary row further down the next quest.
        d.text:SetFontObject("GameFontHighlightSmall")
        thin(d.text)
        d:SetHeight(LINE_H)
        d._questID, d._mapID, d._px, d._py, d._title = nil, nil, nil, nil, nil
        QB._linePool[#QB._linePool + 1] = d
        QB._lineActive[i] = nil
    end
end

function QB:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "EQQuestBrowserFrame", UIParent, "BackdropTemplate")
    f:SetSize(760, 480)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(ns.Util.color.optionsBg))
    f:SetBackdropBorderColor(RED[1], RED[2], RED[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L["Quest Browser"])
    f.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(f.title)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() f:Hide() end)

    local search = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    search:SetSize(LIST_W - 26, 20)
    search:SetPoint("TOPLEFT", 18, -(TITLE_BAR_H + 12))
    search:SetAutoFocus(false)
    search:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    search:SetScript("OnTextChanged", function(_, userInput)
        if not userInput then return end
        local Events = ns:GetSubsystem("Events")
        if Events and Events.Debounce then
            Events:Debounce("eq.questbrowser.search", 0.25, function() QB:RenderList() end)
        else
            QB:RenderList()
        end
    end)
    f._search = search

    local scopeRow = CreateFrame("Frame", nil, f)
    scopeRow:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -6)
    scopeRow:SetSize(LIST_W, TOOLBAR_H)

    local Options = ns:GetSubsystem("Options")
    if Options and Options.CreateDropdown then
        local function listFn()
            return {
                { value = "all",       label = L["All quests"] },
                { value = "available", label = L["Available to you"] },
                { value = "log",       label = L["In your quest log"] },
                { value = "completed", label = L["Completed"] },
            }
        end
        local dd = Options:CreateDropdown(scopeRow, nil, listFn,
            function() return QB._scope or "all" end,
            function(v) QB._scope = v; QB:RenderList() end)
        dd:SetPoint("LEFT", scopeRow, "LEFT", 0, 0)
        dd:SetWidth(LIST_W - 10)
        f._scopeDD = dd
    end

    local zoneRow = CreateFrame("Frame", nil, f)
    zoneRow:SetPoint("TOPLEFT", scopeRow, "BOTTOMLEFT", 0, -2)
    zoneRow:SetSize(LIST_W, TOOLBAR_H)
    if Options and Options.CreateCheckbox then
        local cb = Options:CreateCheckbox(zoneRow, L["This zone only"],
            function() return QB._zoneOnly == true end,
            function(v) QB._zoneOnly = v; QB:RenderList() end,
            L["Only list quests that can be picked up on the map you are standing in."])
        cb:SetPoint("LEFT", zoneRow, "LEFT", 4, 0)
        f._zoneCB = cb
    end

    f._count = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f._count:SetPoint("TOPLEFT", zoneRow, "BOTTOMLEFT", 6, -2)
    f._count:SetJustifyH("LEFT")
    thin(f._count)

    local listTop = TITLE_BAR_H + 12 + 20 + 6 + TOOLBAR_H + 2 + TOOLBAR_H + 16
    local listScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 12, -listTop)
    -- Anchored top and bottom rather than sized, so the height is not a copy of the frame's own
    listScroll:SetPoint("BOTTOMLEFT", 12, 12)
    listScroll:SetWidth(LIST_W - 22)
    f._listScroll = listScroll

    local listCanvas = CreateFrame("Frame", nil, listScroll)
    listCanvas:SetSize(1, 1)
    listScroll:SetScrollChild(listCanvas)
    f._listCanvas = listCanvas

    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", 12 + LIST_W, -(TITLE_BAR_H + 8))
    divider:SetPoint("BOTTOMLEFT", 12 + LIST_W, 12)

    local detailScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", 12 + LIST_W + 14, -(TITLE_BAR_H + 12))
    detailScroll:SetPoint("BOTTOMRIGHT", -30, 12)
    f._detailScroll = detailScroll

    local detailCanvas = CreateFrame("Frame", nil, detailScroll)
    detailCanvas:SetSize(1, 1)
    detailScroll:SetScrollChild(detailCanvas)
    f._detailCanvas = detailCanvas

    self.frame = f
end

local function acquireRow(parent)
    return ns.Util.AcquirePooled(QB._rowPool, QB._rowActive, parent, buildListRow)
end

local function acquireLine(parent)
    return ns.Util.AcquirePooled(QB._linePool, QB._lineActive, parent, buildDetailLine)
end

function QB:RenderList()
    local f = self.frame
    if not f then return end
    releaseRows()

    local D = data()
    if not (D and D:Loaded()) then
        f._count:SetText(L["No quest data on this version of the game."])
        return
    end

    local mapID
    if self._zoneOnly and C_Map and C_Map.GetBestMapForUnit then
        local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
        if ok then mapID = id end
    end

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

    f._listCanvas:SetSize(f._listScroll:GetWidth() or LIST_W, math.max(1, shown * ROW_H))
    for i = 1, shown do
        local row = rows[i]
        local r = acquireRow(f._listCanvas)
        r:SetPoint("TOPLEFT",  f._listCanvas, "TOPLEFT",  0, -((i - 1) * ROW_H))
        r:SetPoint("TOPRIGHT", f._listCanvas, "TOPRIGHT", 0, -((i - 1) * ROW_H))
        r.level:SetText(row.level > 0 and tostring(row.level) or "-")
        r.level:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        r.title:SetText(row.name)
        r._questID = row.id
        if row.id == self._selected then
            r.sel:Show()
            r.title:SetTextColor(1, 1, 1)
        else
            r.sel:Hide()
            r.title:SetTextColor(0.85, 0.85, 0.85)
        end
    end
end

local _cursorY = 0

local function line(parent, text, opts)
    opts = opts or {}
    local d = acquireLine(parent)
    d:SetPoint("TOPLEFT",  parent, "TOPLEFT",  opts.indent or 0, -_cursorY)
    d:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -_cursorY)
    if opts.font then
        d.text:SetFontObject(opts.font)
        thin(d.text)
    end
    d.text:SetText(text or "")
    local c = opts.color
    if c then d.text:SetTextColor(c[1], c[2], c[3]) else d.text:SetTextColor(1, 1, 1) end
    if opts.wrap then
        d.text:SetWordWrap(true)
        -- Measured after the font and the text are both set, and only ever on a canvas that has
        -- already been given its width - a zero width canvas reports one line for everything.
        d:SetHeight(math.max(LINE_H, d.text:GetStringHeight() + 2))
    end
    if opts.questID or opts.mapID then
        d:EnableMouse(true)
        d._questID = opts.questID
        d._mapID, d._px, d._py, d._title = opts.mapID, opts.x, opts.y, opts.title
    else
        d.hl:SetAlpha(0)
    end
    _cursorY = _cursorY + d:GetHeight() + 1
    return d
end

local function gap(px) _cursorY = _cursorY + (px or 6) end

local function header(parent, text)
    gap(8)
    line(parent, text, { color = YELLOW })
end

local function places(parent, list, title, questTitle)
    if not list then return end
    header(parent, title)
    local D = data()
    for i = 1, #list do
        local p = list[i]
        local zone = D:ZoneName(p.mapID) or ("map " .. tostring(p.mapID))
        local text = ("%s  (%.1f, %.1f)"):format(zone, p.x * 100, p.y * 100)
        -- Its own key rather than the pin tooltip's "and %d more", which counts QUESTS. One
        -- English phrase covering two meanings is one manifest key, and translators only see one.
        if p.points and p.points > 1 then
            text = text .. "  -  " .. (L["%d locations"]):format(p.points)
        end
        local kindLine = p.kind and sourceText(p.kind)
        if kindLine then text = text .. "  -  " .. kindLine end
        line(parent, text, {
            indent = 10, color = MUTED,
            mapID = p.mapID, x = p.x, y = p.y, title = questTitle,
        })
    end
end

local function refs(parent, list, title)
    if not (list and #list > 0) then return end
    header(parent, title)
    for i = 1, #list do
        local q = list[i]
        local mark = q.done and "|cff44ff44+|r" or "|cffff5050-|r"
        -- Only a quest the data can describe gets a link. Clicking one it cannot would clear
        -- the pane to the empty state, which reads as the window losing your place.
        line(parent, ("%s  %s"):format(mark, q.name), {
            indent = 10, color = MUTED, questID = q.known and q.id or nil,
        })
    end
end

function QB:RenderDetails()
    local f = self.frame
    if not f then return end
    releaseLines()
    _cursorY = 0

    local canvas = f._detailCanvas
    -- Width first and height last. Every wrapped line measures itself against this canvas, so a
    -- canvas still one pixel wide reports a single line for a paragraph and the rows overlap.
    local width = f._detailScroll:GetWidth() or 400
    canvas:SetSize(width, 1)

    local D = data()
    local record = self._selected and D and D:Record(self._selected)
    if not record then
        line(canvas, L["Pick a quest on the left."], { color = DIM })
        canvas:SetHeight(math.max(1, _cursorY))
        return
    end
    self._record = record

    line(canvas, record.name, { color = YELLOW, wrap = true, font = "GameFontNormalLarge" })

    local bits = { ("|cff888888#%d|r"):format(record.id) }
    if record.level then bits[#bits + 1] = (L["Level %d"]):format(record.level) end
    if record.reqLevel then bits[#bits + 1] = (L["Requires level %d"]):format(record.reqLevel) end
    line(canvas, table.concat(bits, "   "), { color = MUTED })

    local status, color
    if record.available then
        status, color = L["You can pick this up now."], { 0.3, 1, 0.3 }
    elseif record.reason then
        status, color = reasonText(record.reason), { 1, 0.6, 0.3 }
        if not status then status = L["Not available to you right now."] end
    else
        status, color = L["Not available to you right now."], { 1, 0.6, 0.3 }
    end
    if record.failed then status = L["Failed, so you can take it again."] end
    line(canvas, status, { color = color, wrap = true })

    local tags = {}
    if record.isInstance   then tags[#tags + 1] = L["Dungeon or raid"] end
    if record.isRepeatable then tags[#tags + 1] = L["Repeatable"] end
    if record.isEvent      then tags[#tags + 1] = L["World event"] end
    if record.isClassQuest then tags[#tags + 1] = L["Class quest"] end
    if record.isProfession then tags[#tags + 1] = L["Profession"] end
    if #tags > 0 then
        line(canvas, table.concat(tags, ", "), { color = { 0.6, 0.8, 1 } })
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
    if #reqs > 0 then
        header(canvas, L["Requirements"])
        for i = 1, #reqs do line(canvas, reqs[i], { indent = 10, color = MUTED, wrap = true }) end
    end

    places(canvas, record.starts,     L["Starts"],     record.name)
    places(canvas, record.objectives, L["Objectives"], record.name)
    places(canvas, record.turnIn,     L["Turn in"],    record.name)

    if record.pre then
        refs(canvas, record.pre, record.preMode == "all" and L["Finish all of these first"] or L["Finish one of these first"])
    end
    if record.parent then refs(canvas, { record.parent }, L["Part of"]) end
    if record.chain  then refs(canvas, { record.chain },  L["Leads to"]) end
    refs(canvas, record.excl, L["Instead of"])

    canvas:SetHeight(math.max(1, _cursorY + 8))
end

function QB:Select(questID)
    self._selected = questID
    self:RenderList()
    self:RenderDetails()
    if self.frame then self.frame._detailScroll:SetVerticalScroll(0) end
end

-- Both effects on one click, because a browser row is asking "where is this" and the answer is
-- worth having on the map and on the arrow at the same time.
function QB:GoTo(mapID, x, y, title)
    local Arrow = ns:GetSubsystem("QuestArrow")
    if Arrow and Arrow.Set then Arrow:Set(mapID, x, y, title) end
    local wm = _G.WorldMapFrame
    if wm and wm.SetMapID then
        if not wm:IsShown() and _G.ToggleWorldMap then _G.ToggleWorldMap() end
        pcall(wm.SetMapID, wm, mapID)
    end
end

function QB:Open(questID)
    if not self:Available() then return end
    self:Build()
    self.frame:Show()
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
    return (D and D:Loaded()) == true
end

function QB:Search(text)
    self:Open()
    if self.frame and text and text ~= "" then
        self.frame._search:SetText(text)
        self:RenderList()
    end
end
