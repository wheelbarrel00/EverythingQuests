local _, ns = ...
local L = ns.L

local HF = ns:RegisterSubsystem("HistoryFrame", {})

local TITLE_BAR_H = 22
local TAB_BAR_H   = 28
local TOOLBAR_H   = 30
local ROW_H       = 36

local HEATMAP_DAYS = 91
local HEATMAP_ROWS = 7
local HEATMAP_COLS = 13
local CELL_SIZE    = 16
local CELL_GAP     = 3

local YELLOW      = ns.Util.color.buttonYellow
local HEADER_RED  = ns.Util.color.brandRed
local MUTED       = ns.Util.color.muted
local DIM         = ns.Util.color.dim

local FONT_FILE = "Fonts\\ARIALN.TTF"
local function thin(fs)
    if not (fs and fs.GetFont and fs.SetFont) then return end
    local _, sz, fl = fs:GetFont()
    fs:SetFont(FONT_FILE, sz or 12, fl or "")
end

local function fmtTime(t)
    if not t or t == 0 then return L["(before tracking)"] end
    return date("%Y-%m-%d %H:%M", t)
end

HF._rowPool   = {}
HF._rowActive = {}

local findChainForQuest

local function rowOnMouseUp(self, button)
    local kind = self._kind
    if kind == "history" then
        if button ~= "RightButton" then return end
        local chainID = findChainForQuest(self._questID)
        if chainID then
            local CG = ns:GetSubsystem("ChainGuide")
            if CG then
                if CG.Open          then CG:Open()                end
                if CG.NavigateChain then CG:NavigateChain(chainID) end
            end
        else
            print((L["|cffEBB706EQ History|r: |cffffffff%s|r isn't part of any chain in the Chain Guide."]):format(
                self._fullName or ("Quest #" .. tostring(self._questID))))
        end
    elseif kind == "timeline" then
        if button == "RightButton" then
            local CG = ns:GetSubsystem("ChainGuide")
            if CG then
                if CG.Open          then CG:Open()              end
                if CG.NavigateChain then CG:NavigateChain(self._chainID) end
            end
            return
        end
        HF._timelineOpen[self._chainID] = not HF._timelineOpen[self._chainID]
        HF:_renderTimeline()
    end
end

local function rowOnEnter(self)
    local kind = self._kind
    if kind == "history" then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetText(self._fullName or ("Quest #" .. tostring(self._questID)), 1, 1, 1, 1, true)
        GameTooltip:AddLine(L["Right-click to open in the Chain Guide"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    elseif kind == "timeline" then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        GameTooltip:SetText(self._chainName or L["Chain"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Click to expand"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Right-click to open in the Chain Guide"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end
end

local function rowOnLeave() GameTooltip:Hide() end

local function buildRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_H)
    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.title:SetHeight(15)
    r.title:SetPoint("TOPLEFT",  6, -5)
    r.title:SetPoint("TOPRIGHT", -160, -5)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)

    r.meta = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.meta:SetHeight(11)
    r.meta:SetPoint("TOPLEFT",  r.title, "BOTTOMLEFT",  0, -2)
    r.meta:SetPoint("TOPRIGHT", r.title, "BOTTOMRIGHT", 0, -2)
    r.meta:SetJustifyH("LEFT")
    r.meta:SetWordWrap(false)

    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.right:SetPoint("RIGHT", -8, 0)
    r.right:SetJustifyH("RIGHT")
    r.right:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])

    thin(r.title); thin(r.meta); thin(r.right)

    r:SetScript("OnMouseUp", rowOnMouseUp)
    r:SetScript("OnEnter",   rowOnEnter)
    r:SetScript("OnLeave",   rowOnLeave)
    return r
end

local function acquireRow(parent)
    return ns.Util.AcquirePooled(HF._rowPool, HF._rowActive, parent, buildRow)
end

local function releaseAllRows()
    for i = #HF._rowActive, 1, -1 do
        local r = HF._rowActive[i]
        r:Hide()
        r:ClearAllPoints()
        r.title:SetText("")
        r.meta:SetText("")
        r.right:SetText("")
        r.right:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        r:EnableMouse(false)
        r._kind = nil
        r._questID, r._fullName = nil, nil
        r._chainID, r._chainName = nil, nil
        HF._rowPool[#HF._rowPool + 1] = r
        HF._rowActive[i] = nil
    end
end

function HF:Build()
    if self.frame then return end

    local f = CreateFrame("Frame", "EQHistoryFrame", UIParent, "BackdropTemplate")
    f:SetSize(700, 460)
    f:SetPoint("CENTER")
    -- One strata above the Options frame so History pops over it when opened from the History tab
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
    f:SetBackdropBorderColor(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 1)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -10)
    f.title:SetText(L["Quest History"])
    f.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(f.title)

    f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.close:SetPoint("TOPRIGHT", -4, -4)
    f.close:SetScript("OnClick", function() f:Hide() end)

    local function makeTitleButton(label, width, onClick)
        local b = CreateFrame("Button", nil, f, "BackdropTemplate")
        b:SetSize(width, 20)
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        b.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(b.text)
        b:SetScript("OnClick", onClick)
        return b
    end

    f.export = makeTitleButton(L["Export"], 70, function() HF:_openExportPopup() end)
    f.export:SetPoint("RIGHT", f.close, "LEFT", -2, 0)

    f.rescan = makeTitleButton(L["Re-scan names"], 110, function()
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
    f.rescan:SetPoint("RIGHT", f.export, "LEFT", -4, 0)
    f.rescan:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Re-scan for quest names"], 1, 0.82, 0, 1, true)
        GameTooltip:AddLine(L["Asks the server for the name of any \"Quest #12345\" entries. They'll fill in over the next minute or two as responses arrive."], 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    f.rescan:SetScript("OnLeave", GameTooltip_Hide)

    local tabRow = CreateFrame("Frame", nil, f)
    tabRow:SetPoint("TOPLEFT",  10, -(TITLE_BAR_H + 14))
    tabRow:SetPoint("TOPRIGHT", -10, -(TITLE_BAR_H + 14))
    tabRow:SetHeight(TAB_BAR_H)
    f._tabRow = tabRow

    self._tabs = {}
    local function makeTab(id, label)
        local b = CreateFrame("Button", nil, tabRow)
        b:SetSize(110, TAB_BAR_H - 4)
        b.bg = b:CreateTexture(nil, "BACKGROUND")
        b.bg:SetAllPoints()
        b.bg:SetColorTexture(0, 0, 0, 0.5)
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.08)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        b.text:SetPoint("CENTER")
        b.text:SetText(label)
        thin(b.text)
        b:SetScript("OnClick", function() HF:SwitchTab(id) end)
        b._id = id
        return b
    end
    self._tabs.quests   = makeTab("quests",   L["Quests"])
    self._tabs.streak   = makeTab("streak",   L["Streak"])
    self._tabs.timeline = makeTab("timeline", L["Chain Timeline"])
    self._tabs.activity = makeTab("activity", L["Activity"])
    self._tabs.totals   = makeTab("totals",   L["Stats"])
    self._tabs.session  = makeTab("session",  L["This Session"])
    self._tabs.quests:SetPoint("LEFT", tabRow, "LEFT", 0, 0)
    self._tabs.streak:SetPoint("LEFT", self._tabs.quests, "RIGHT", 4, 0)
    self._tabs.timeline:SetPoint("LEFT", self._tabs.streak, "RIGHT", 4, 0)
    self._tabs.activity:SetPoint("LEFT", self._tabs.timeline, "RIGHT", 4, 0)
    self._tabs.totals:SetPoint("LEFT", self._tabs.activity, "RIGHT", 4, 0)
    self._tabs.session:SetPoint("LEFT", self._tabs.totals, "RIGHT", 4, 0)

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT",     10, -(TITLE_BAR_H + 14 + TAB_BAR_H + 4))
    content:SetPoint("BOTTOMRIGHT", -10, 10)
    f._content = content

    self.frame = f
    self:_buildPanes(content)
    self:SwitchTab("quests")
end

function HF:_buildPanes(content)
    self._panes = {
        quests   = self:_buildQuestsPane(content),
        streak   = self:_buildStreakPane(content),
        timeline = self:_buildTimelinePane(content),
        activity = self:_buildHeatmapPane(content),
        totals   = self:_buildTotalsPane(content),
        session  = self:_buildSessionPane(content),
    }
end

function HF:SwitchTab(id)
    if not self._panes then return end
    for k, pane in pairs(self._panes) do
        if k == id then pane:Show() else pane:Hide() end
    end
    for k, b in pairs(self._tabs) do
        if k == id then
            b.bg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.85)
            b.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        else
            b.bg:SetColorTexture(0, 0, 0, 0.5)
            b.text:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    self._activeTab = id
    self:Render()
end

function HF:_buildQuestsPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    local Options = ns:GetSubsystem("Options")

    local row1 = CreateFrame("Frame", nil, pane)
    row1:SetPoint("TOPLEFT", 0, 0)
    row1:SetPoint("TOPRIGHT", 0, 0)
    row1:SetHeight(TOOLBAR_H)

    local search = CreateFrame("EditBox", nil, row1, "SearchBoxTemplate")
    search:SetSize(220, 20)
    search:SetPoint("LEFT", row1, "LEFT", 6, 0)
    search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function(eb, userInput)
        if SearchBoxTemplate_OnTextChanged then SearchBoxTemplate_OnTextChanged(eb) end
        if not userInput then return end
        local Events = ns:GetSubsystem("Events")
        if Events and Events.Debounce then
            Events:Debounce("eq.history.search", 0.2, function() HF:Render() end)
        else
            HF:Render()
        end
    end)
    pane._search = search

    local charLabel = row1:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charLabel:SetPoint("LEFT", search, "RIGHT", 14, 0)
    charLabel:SetText(L["Character:"])
    thin(charLabel)

    local charDD
    if Options and Options.CreateDropdown then
        local function listFn()
            local R = ns:GetSubsystem("History")
            local out = { { value = "all", label = L["All characters"] } }
            if R then
                local chars = R:GetCharacters()
                for i = 1, #chars do
                    out[#out + 1] = { value = chars[i], label = chars[i] }
                end
            end
            return out
        end
        local function curFn() return HF._charFilter or "all" end
        local function setFn(v) HF._charFilter = v; HF:Render() end
        charDD = Options:CreateDropdown(row1, nil, listFn, curFn, setFn)
        charDD:SetPoint("LEFT", charLabel, "RIGHT", 4, 0)
        charDD:SetWidth(180)
    end
    pane._charDD = charDD

    pane._count = row1:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pane._count:SetPoint("RIGHT", row1, "RIGHT", -6, 0)
    pane._count:SetText("")
    thin(pane._count)

    local row2 = CreateFrame("Frame", nil, pane)
    row2:SetPoint("TOPLEFT",  row1, "BOTTOMLEFT",  0, -2)
    row2:SetPoint("TOPRIGHT", row1, "BOTTOMRIGHT", 0, -2)
    row2:SetHeight(TOOLBAR_H)

    local dateLabel = row2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dateLabel:SetPoint("LEFT", row2, "LEFT", 6, 0)
    dateLabel:SetText(L["Date:"])
    thin(dateLabel)

    local DATE_OPTIONS = {
        { value = "all",   label = L["All time"] },
        { value = "today", label = L["Today"] },
        { value = "7d",    label = L["Past 7 days"] },
        { value = "30d",   label = L["Past 30 days"] },
    }
    local dateDD
    if Options and Options.CreateDropdown then
        local function listFn() return DATE_OPTIONS end
        local function curFn()  return HF._dateFilter or "all" end
        local function setFn(v) HF._dateFilter = v; HF:Render() end
        dateDD = Options:CreateDropdown(row2, nil, listFn, curFn, setFn)
        dateDD:SetPoint("LEFT", dateLabel, "RIGHT", 4, 0)
        dateDD:SetWidth(130)
    end
    pane._dateDD = dateDD

    local typeLabel = row2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    typeLabel:SetPoint("LEFT", dateDD or dateLabel, "RIGHT", 14, 0)
    typeLabel:SetText(L["Type:"])
    thin(typeLabel)

    local CLASS_OPTIONS = {
        { value = "all",        label = L["All types"]   },
        { value = "campaign",   label = L["Campaign"]    },
        { value = "questline",  label = L["Questline"]   },
        { value = "calling",    label = L["Calling"]     },
        { value = "recurring",  label = L["Recurring"]   },
        { value = "worldquest", label = L["World Quest"] },
        { value = "other",      label = L["Other"]       },
    }
    local classDD
    if Options and Options.CreateDropdown then
        local function listFn() return CLASS_OPTIONS end
        local function curFn()  return HF._classFilter or "all" end
        local function setFn(v) HF._classFilter = v; HF:Render() end
        classDD = Options:CreateDropdown(row2, nil, listFn, curFn, setFn)
        classDD:SetPoint("LEFT", typeLabel, "RIGHT", 4, 0)
        classDD:SetWidth(150)
    end
    pane._classDD = classDD

    local sortLabel = row2:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sortLabel:SetPoint("LEFT", classDD or typeLabel, "RIGHT", 14, 0)
    sortLabel:SetText(L["Sort:"])
    thin(sortLabel)

    local SORT_OPTIONS = {
        { value = "date", label = L["Date"] },
        { value = "name", label = L["Name"] },
        { value = "type", label = L["Type"] },
    }
    local sortDD
    if Options and Options.CreateDropdown then
        local function listFn() return SORT_OPTIONS end
        local function curFn()  return HF._sortBy or "date" end
        local function setFn(v) HF._sortBy = v; HF:Render() end
        sortDD = Options:CreateDropdown(row2, nil, listFn, curFn, setFn)
        sortDD:SetPoint("LEFT", sortLabel, "RIGHT", 4, 0)
        sortDD:SetWidth(90)
    end
    pane._sortDD = sortDD

    local dirBtn = CreateFrame("Button", nil, row2)
    dirBtn:SetSize(22, 20)
    dirBtn:SetPoint("LEFT", sortDD or sortLabel, "RIGHT", 2, 0)
    local dirHL = dirBtn:CreateTexture(nil, "HIGHLIGHT")
    dirHL:SetAllPoints()
    dirHL:SetColorTexture(1, 1, 1, 0.10)
    local arrow = dirBtn:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(16, 16)
    arrow:SetPoint("CENTER")
    arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    local function syncArrow()
        if (HF._sortDir or "desc") == "asc" then
            arrow:SetTexCoord(0, 1, 0, 1)
        else
            arrow:SetTexCoord(0, 1, 1, 0)
        end
    end
    syncArrow()
    dirBtn:SetScript("OnClick", function()
        HF._sortDir = ((HF._sortDir or "desc") == "desc") and "asc" or "desc"
        syncArrow()
        HF:Render()
    end)
    dirBtn:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Sort direction"], 1, 1, 1)
        GameTooltip:AddLine(L["Click to flip ascending / descending."], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    dirBtn:SetScript("OnLeave", GameTooltip_Hide)
    pane._dirBtn = dirBtn

    if Options and Options.CreateCheckbox then
        local function get() return HF._hideBackfilled and true or false end
        local function set(v) HF._hideBackfilled = v and true or false; HF:Render() end
        local hideCB = Options:CreateCheckbox(row2,
            L["Hide undated  |cffaaaaaa(backfilled)|r"],
            get, set)
        hideCB:ClearAllPoints()
        hideCB.label:ClearAllPoints()
        hideCB.label:SetPoint("RIGHT", row2, "RIGHT", -6, 1)
        hideCB:SetPoint("RIGHT", hideCB.label, "LEFT", -4, -1)
        pane._hideCB = hideCB
    end

    local listTop = TOOLBAR_H * 2 + 4
    local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     0, -listTop)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    pane._scroll = scroll

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._canvas = canvas

    pane._empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._empty:SetPoint("CENTER")
    pane._empty:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._empty:SetText(L["(no matching quests)"])
    pane._empty:Hide()
    thin(pane._empty)

    return pane
end

-- Assigns the forward-declared upvalue - do NOT re-local this function
function findChainForQuest(questID)
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
                if it and it.type == "quest" and it.id == questID then
                    return chainID
                end
            end
        end
    end
    return nil
end

function HF:_renderQuests()
    local pane = self._panes.quests
    local R = ns:GetSubsystem("History")
    releaseAllRows()
    if not R then return end

    local searchText = pane._search and pane._search:GetText() or ""
    -- SearchBoxTemplate stores its placeholder as the text when unfocused.
    if searchText == SEARCH then searchText = "" end

    local entries = R:Query({
        search         = searchText,
        char           = HF._charFilter,
        dateRange      = HF._dateFilter,
        classification = HF._classFilter,
        hideBackfilled = HF._hideBackfilled,
        sortBy         = HF._sortBy or "date",
        sortDir        = HF._sortDir or "desc",
    })

    local n = #entries
    if pane._count then pane._count:SetText((L["%d entries"]):format(n)) end

    if n == 0 then
        pane._empty:Show()
        pane._canvas:SetSize(1, 1)
        return
    end
    pane._empty:Hide()

    local MAX = 500
    local shown = math.min(n, MAX)
    local canvasW = pane._scroll:GetWidth() or 600
    pane._canvas:SetSize(canvasW, shown * (ROW_H + 2))

    for i = 1, shown do
        local e = entries[i]
        local row = acquireRow(pane._canvas)
        row:SetPoint("TOPLEFT",  pane._canvas, "TOPLEFT",  0, -((i - 1) * (ROW_H + 2)))
        row:SetPoint("TOPRIGHT", pane._canvas, "TOPRIGHT", 0, -((i - 1) * (ROW_H + 2)))

        row.title:SetText(e.n or ("Quest #" .. tostring(e.q)))
        if e.t and e.t == 0 then
            row.title:SetTextColor(DIM[1], DIM[2], DIM[3])
        else
            row.title:SetTextColor(1, 1, 1)
        end

        local meta = e.c or ""
        if e.z and e.z ~= "" then meta = meta .. "  •  " .. e.z end
        row.meta:SetText(meta)
        row.right:SetText(fmtTime(e.t))

        row:EnableMouse(true)
        row._kind     = "history"
        row._questID  = e.q
        row._fullName = e.n
    end

    if n > MAX then
        local which = L["first"]
        if (HF._sortBy or "date") == "date" then
            which = (HF._sortDir == "asc") and L["oldest"] or L["newest"]
        end
        pane._count:SetText((L["%d entries (showing %s %d)"]):format(n, which, MAX))
    end
end

function HF:_buildStreakPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    local function bigStat(yOffset)
        local label = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 30, yOffset)
        label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        thin(label)

        local value = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        value:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(value)
        return label, value
    end

    pane._currentLabel, pane._currentValue = bigStat(-20)
    pane._currentLabel:SetText(L["Current daily streak"])

    pane._bestLabel, pane._bestValue = bigStat(-80)
    pane._bestLabel:SetText(L["Best daily streak"])

    pane._totalLabel, pane._totalValue = bigStat(-140)
    pane._totalLabel:SetText(L["Total quests recorded with a date"])

    pane._note = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._note:SetPoint("TOPLEFT", 30, -210)
    pane._note:SetPoint("TOPRIGHT", -30, -210)
    pane._note:SetJustifyH("LEFT")
    pane._note:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._note:SetText(
        L["Streak counts consecutive days (local time) with at least one quest turn-in across any character on the account. Today or yesterday keeps the streak alive - you don't lose it until a whole day passes with no activity."])
    thin(pane._note)

    return pane
end

function HF:_renderStreak()
    local pane = self._panes.streak
    local R = ns:GetSubsystem("History")
    if not R then return end
    local s = R:Streak()
    pane._currentValue:SetText((L["%d days"]):format(s.current))
    pane._bestValue:SetText((L["%d days"]):format(s.best))
    pane._totalValue:SetText(("%d"):format(s.total))
end

function HF:_buildTimelinePane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._intro = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT", 6, -4)
    pane._intro:SetPoint("TOPRIGHT", -22, -4)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText(
        L["Chains where you have at least one completed quest. Click a chain to expand and see per-quest completion dates."])
    thin(pane._intro)

    local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     0, -28)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)
    pane._scroll = scroll
    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._canvas = canvas

    pane._empty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._empty:SetPoint("CENTER")
    pane._empty:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._empty:SetText(L["(no chain quests recorded yet)"])
    pane._empty:Hide()
    thin(pane._empty)

    HF._timelineOpen = HF._timelineOpen or {}
    return pane
end

local MARKER_COLLAPSED = "|TInterface\\Buttons\\UI-PlusButton-Up:14:14|t "
local MARKER_EXPANDED  = "|TInterface\\Buttons\\UI-MinusButton-Up:14:14|t "
local MARKER_COMPLETE  = "|A:common-icon-checkmark:14:14|a "

function HF:_renderTimeline()
    local pane = self._panes.timeline
    local R         = ns:GetSubsystem("History")
    local Database  = ns:GetSubsystem("ChainGuideDatabase")
    local QLS       = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS        = ns:GetSubsystem("ChainGuideCampaignSource")
    releaseAllRows()
    if not (R and Database) then return end

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
                    if t and t ~= nil then
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

    if #sorted == 0 then
        pane._empty:Show()
        pane._canvas:SetSize(1, 1)
        return
    end
    pane._empty:Hide()

    table.sort(sorted, function(a, b)
        if a.latest ~= b.latest then return a.latest > b.latest end
        return (a.chain.name or "") < (b.chain.name or "")
    end)

    local canvasW = pane._scroll:GetWidth() or 600
    local y = 0
    for i = 1, #sorted do
        local rec = sorted[i]
        local chain = rec.chain
        local row = acquireRow(pane._canvas)
        row:SetPoint("TOPLEFT",  pane._canvas, "TOPLEFT",  0, -y)
        row:SetPoint("TOPRIGHT", pane._canvas, "TOPRIGHT", 0, -y)
        local marker  = HF._timelineOpen[rec.id] and MARKER_EXPANDED or MARKER_COLLAPSED
        local check   = (rec.doneN >= rec.total) and MARKER_COMPLETE or ""
        row.title:SetText(marker .. check .. (chain.name or ("Chain #" .. tostring(rec.id))))
        row.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        row.meta:SetText((L["%d of %d quests recorded"]):format(rec.doneN, rec.total))
        row.right:SetText(fmtTime(rec.latest))
        row:EnableMouse(true)
        row._kind      = "timeline"
        row._chainID   = rec.id
        row._chainName = chain.name
        y = y + ROW_H + 2

        if HF._timelineOpen[rec.id] then
            for j = 1, #chain.items do
                local it = chain.items[j]
                if it and it.type == "quest" then
                    local sub = acquireRow(pane._canvas)
                    sub._kind = "sub"
                    sub:EnableMouse(false)
                    sub:SetPoint("TOPLEFT",  pane._canvas, "TOPLEFT",  24, -y)
                    sub:SetPoint("TOPRIGHT", pane._canvas, "TOPRIGHT", 0, -y)
                    local t = completion[it.id]
                    local title = ns.Util.QuestTitle(it.id) or it.name or ("Quest #" .. tostring(it.id))
                    sub.title:SetText(title)
                    sub.meta:SetText("ID " .. tostring(it.id))
                    if t and t ~= nil then
                        sub.title:SetTextColor(1, 1, 1)
                        sub.right:SetText(fmtTime(t))
                    else
                        sub.title:SetTextColor(DIM[1], DIM[2], DIM[3])
                        sub.right:SetText("—")
                        sub.right:SetTextColor(DIM[1], DIM[2], DIM[3])
                    end
                    y = y + ROW_H + 2
                end
            end
        end
    end
    pane._canvas:SetSize(canvasW, math.max(y, 1))
end

function HF:_buildHeatmapPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._intro = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT",  30, -12)
    pane._intro:SetPoint("TOPRIGHT", -30, -12)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText((L["Quest turn-ins per day over the last %d days. Brighter = busier. Hover a cell for the date and count. The bottom-right cell is today."]):format(HEATMAP_DAYS - 1))
    thin(pane._intro)

    local gridW = HEATMAP_COLS * (CELL_SIZE + CELL_GAP) - CELL_GAP
    local gridH = HEATMAP_ROWS * (CELL_SIZE + CELL_GAP) - CELL_GAP
    pane._grid = CreateFrame("Frame", nil, pane)
    pane._grid:SetSize(gridW, gridH)
    pane._grid:SetPoint("TOP", 0, -56)

    pane._cells = {}
    for i = 1, HEATMAP_DAYS do
        local cell = CreateFrame("Frame", nil, pane._grid)
        cell:SetSize(CELL_SIZE, CELL_SIZE)
        cell:EnableMouse(true)
        local col = math.floor((i - 1) / HEATMAP_ROWS)
        local row = (i - 1) % HEATMAP_ROWS
        cell:SetPoint("TOPLEFT", col * (CELL_SIZE + CELL_GAP), -(row * (CELL_SIZE + CELL_GAP)))

        cell.bg = cell:CreateTexture(nil, "ARTWORK")
        cell.bg:SetAllPoints()
        cell.bg:SetColorTexture(0.15, 0.15, 0.15, 1)

        cell:SetScript("OnEnter", function(cf)
            if not cf._day then return end
            GameTooltip:SetOwner(cf, "ANCHOR_CURSOR_RIGHT")
            GameTooltip:SetText(date("!%A, %Y-%m-%d", cf._day * 86400), 1, 1, 1)
            local c = cf._count or 0
            GameTooltip:AddLine((L["%d quest%s turned in"]):format(c, c == 1 and "" or "s"),
                YELLOW[1], YELLOW[2], YELLOW[3])
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", GameTooltip_Hide)
        pane._cells[i] = cell
    end

    local legend = CreateFrame("Frame", nil, pane)
    legend:SetSize(180, CELL_SIZE)
    legend:SetPoint("TOP", pane._grid, "BOTTOM", 0, -18)

    local lessLabel = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lessLabel:SetText(L["Less"])
    lessLabel:SetPoint("LEFT")
    thin(lessLabel)

    local swatches = {}
    for i = 1, 5 do
        local sw = legend:CreateTexture(nil, "ARTWORK")
        sw:SetSize(CELL_SIZE - 2, CELL_SIZE - 2)
        local prev = (i == 1) and lessLabel or swatches[i - 1]
        sw:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        local intensity = (i - 1) / 4
        sw:SetColorTexture(
            0.15 + (YELLOW[1] - 0.15) * intensity,
            0.15 + (YELLOW[2] - 0.15) * intensity,
            0.15 + (YELLOW[3] - 0.15) * intensity,
            1)
        swatches[i] = sw
    end
    local moreLabel = legend:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    moreLabel:SetText(L["More"])
    moreLabel:SetPoint("LEFT", swatches[5], "RIGHT", 4, 0)
    thin(moreLabel)

    pane._totalValue = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pane._totalValue:SetPoint("TOP", legend, "BOTTOM", 0, -28)
    pane._totalValue:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(pane._totalValue)

    pane._totalLabel = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._totalLabel:SetPoint("TOP", pane._totalValue, "BOTTOM", 0, -2)
    pane._totalLabel:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._totalLabel:SetText((L["total turn-ins in the last %d days"]):format(HEATMAP_DAYS - 1))
    thin(pane._totalLabel)

    pane._busiestValue = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._busiestValue:SetPoint("TOP", pane._totalLabel, "BOTTOM", 0, -12)
    pane._busiestValue:SetTextColor(0.85, 0.85, 0.85)
    thin(pane._busiestValue)

    return pane
end

function HF:_renderHeatmap()
    local pane = self._panes.activity
    local R = ns:GetSubsystem("History")
    if not (pane and R and R.DayCounts) then return end

    local counts, today = R:DayCounts(HEATMAP_DAYS)
    local maxCount, total, busiestDay, busiestCount = 0, 0, nil, 0
    for d, c in pairs(counts) do
        total = total + c
        if c > maxCount then maxCount = c end
        if c > busiestCount then busiestCount = c; busiestDay = d end
    end

    for i = 1, HEATMAP_DAYS do
        local cell = pane._cells[i]
        local day = today - (HEATMAP_DAYS - i)
        local count = counts[day] or 0
        cell._day   = day
        cell._count = count

        local intensity
        if count == 0 then
            intensity = 0
        else
            intensity = math.max(0.25, math.min(1.0, count / math.max(maxCount, 1)))
        end
        cell.bg:SetColorTexture(
            0.15 + (YELLOW[1] - 0.15) * intensity,
            0.15 + (YELLOW[2] - 0.15) * intensity,
            0.15 + (YELLOW[3] - 0.15) * intensity,
            1)
    end

    pane._totalValue:SetText(tostring(total))
    if busiestDay and busiestCount > 0 then
        pane._busiestValue:SetText(
            (L["Busiest day: %s (%d quests)"]):format(date("!%Y-%m-%d", busiestDay * 86400), busiestCount))
    else
        pane._busiestValue:SetText(" ")
    end
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

local STATS_MAX_BARS = 30
local CARD_W, CARD_H, CARD_GAP = 210, 70, 12
local BAR_GAP = 3

local function formatMetric(key, v)
    v = v or 0
    if key == "gold" then return fmtMoney(v) end
    if key == "xp"   then return fmtBigNumber(v) .. " XP" end
    return fmtBigNumber(v) .. (v == 1 and " quest" or " quests")
end

local function fmtDelta(key, d)
    if d == 0 then return "|cff888888no change|r" end
    local mag = (key == "gold") and fmtMoney(math.abs(d)) or fmtBigNumber(math.abs(d))
    if key == "xp" then mag = mag .. " XP" end
    if d > 0 then return "|cff55dd55+" .. mag .. "|r" end
    return "|cffdd5555-" .. mag .. "|r"
end

local function makeToggleButton(parent, label, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 22)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.08)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    thin(b.text)
    function b:SetActive(on)
        if on then
            self.bg:SetColorTexture(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 0.85)
            self.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        else
            self.bg:SetColorTexture(0, 0, 0, 0.5)
            self.text:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    b:SetActive(false)
    return b
end

local function makeCard(parent)
    local c = CreateFrame("Frame", nil, parent)
    c:SetSize(CARD_W, CARD_H)
    local bg = c:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.4)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.label:SetPoint("TOPLEFT", 8, -6)
    thin(c.label)
    c.value = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    c.value:SetPoint("TOPLEFT", 8, -22)
    c.value:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(c.value)
    c.delta = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.delta:SetPoint("BOTTOMLEFT", 8, 6)
    thin(c.delta)
    return c
end

local function barOnEnter(self)
    if not self._rangeText then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(self._rangeText, 1, 1, 1)
    GameTooltip:AddLine(self._valueText or "", YELLOW[1], YELLOW[2], YELLOW[3])
    GameTooltip:Show()
end

function HF:_buildTotalsPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._segTotals = makeToggleButton(pane, L["Totals"], 80)
    pane._segTotals:SetPoint("TOPLEFT", 12, -8)
    pane._segTrends = makeToggleButton(pane, L["Trends"], 80)
    pane._segTrends:SetPoint("LEFT", pane._segTotals, "RIGHT", 4, 0)
    pane._segTotals:SetScript("OnClick", function() HF:_switchStatsView("totals") end)
    pane._segTrends:SetScript("OnClick", function() HF:_switchStatsView("trends") end)

    local tvw = CreateFrame("Frame", nil, pane)
    tvw:SetPoint("TOPLEFT",     0, -34)
    tvw:SetPoint("BOTTOMRIGHT", 0, 0)
    pane._totalsView = tvw

    pane._intro = tvw:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT",  30, -4)
    pane._intro:SetPoint("TOPRIGHT", -30, -4)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText(L["Account-wide quest rewards. Totals count only quests turned in while reward tracking was on; older entries didn't capture XP or gold."])
    thin(pane._intro)

    local function pairBlock(yOffset, labelText, big)
        local label = tvw:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 30, yOffset)
        label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        label:SetText(labelText)
        thin(label)

        local value = tvw:CreateFontString(nil, "OVERLAY",
            big and "GameFontNormalLarge" or "GameFontHighlight")
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        value:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(value)
        return value
    end

    pane._totalQuests = pairBlock(-30,  L["Total quests with reward data"], true)
    pane._totalGold   = pairBlock(-78,  L["Total gold earned"],             true)
    pane._totalXP     = pairBlock(-126, L["Total XP earned"],               true)

    local h2 = tvw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h2:SetPoint("TOPLEFT", 30, -180)
    h2:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    h2:SetText(L["By character"])
    thin(h2)
    pane._charHeader = h2

    pane._charRows = {}

    pane._topXP = tvw:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pane._topXP:SetPoint("BOTTOMLEFT",  30,   8)
    pane._topXP:SetPoint("BOTTOMRIGHT", -30,  8)
    pane._topXP:SetJustifyH("LEFT")
    pane._topXP:SetTextColor(1, 1, 1)
    thin(pane._topXP)

    pane._topGold = tvw:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    pane._topGold:SetPoint("BOTTOMLEFT",  pane._topXP, "TOPLEFT",  0, 4)
    pane._topGold:SetPoint("BOTTOMRIGHT", pane._topXP, "TOPRIGHT", 0, 4)
    pane._topGold:SetJustifyH("LEFT")
    pane._topGold:SetTextColor(1, 1, 1)
    thin(pane._topGold)

    local h3 = tvw:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h3:SetPoint("BOTTOMLEFT", pane._topGold, "TOPLEFT", 0, 6)
    h3:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    h3:SetText(L["Top single-quest rewards"])
    thin(h3)
    pane._topHeader = h3

    pane._trendsView = self:_buildTrendsView(pane)

    self._statsView      = "totals"
    self._trendGran      = "daily"
    self._trendMetric    = "gold"
    self._trendCharFilter = "all"
    pane._segTotals:SetActive(true)
    pane._trendsView:Hide()

    return pane
end

local function ensureCharRow(pane, idx)
    local r = pane._charRows[idx]
    if r then return r end
    local host = pane._totalsView or pane
    r = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r:SetTextColor(0.92, 0.92, 0.92)
    r:SetJustifyH("LEFT")
    r:SetPoint("TOPLEFT",  host, "TOPLEFT",  40, -200 - (idx - 1) * 14)
    r:SetPoint("TOPRIGHT", host, "TOPRIGHT", -30, -200 - (idx - 1) * 14)
    thin(r)
    pane._charRows[idx] = r
    return r
end

function HF:_renderTotals()
    local pane = self._panes.totals
    local R = ns:GetSubsystem("History")
    if not (pane and R and R.Totals) then return end
    local t = R:Totals()

    pane._totalQuests:SetText(fmtBigNumber(t.totalCount))
    pane._totalGold:SetText(fmtMoney(t.totalMoney))
    pane._totalXP:SetText(fmtBigNumber(t.totalXP) .. " XP")

    local chars = {}
    for k, v in pairs(t.byChar) do
        chars[#chars + 1] = { key = k, rec = v }
    end
    table.sort(chars, function(a, b) return a.rec.count > b.rec.count end)

    local MAX_VISIBLE = 8
    local shown = math.min(#chars, MAX_VISIBLE)
    for i = 1, shown do
        local row = ensureCharRow(pane, i)
        local c = chars[i]
        row:SetText((L["%s  \194\183  %s quests  \194\183  %s  \194\183  %s XP"]):format(
            c.key,
            fmtBigNumber(c.rec.count),
            fmtMoney(c.rec.money),
            fmtBigNumber(c.rec.xp)))
        row:Show()
    end
    for i = shown + 1, #pane._charRows do
        pane._charRows[i]:Hide()
    end

    if t.topGold then
        pane._topGold:SetText((L["Biggest gold:  |cffffffff%s|r  \194\183  %s"]):format(
            t.topGold.n or ("Quest #" .. tostring(t.topGold.q)),
            fmtMoney(t.topGold.m)))
    else
        pane._topGold:SetText(L["Biggest gold:  (none yet)"])
    end
    if t.topXP then
        pane._topXP:SetText((L["Biggest XP:    |cffffffff%s|r  \194\183  %s XP"]):format(
            t.topXP.n or ("Quest #" .. tostring(t.topXP.q)),
            fmtBigNumber(t.topXP.xp)))
    else
        pane._topXP:SetText(L["Biggest XP:    (none yet)"])
    end
end

function HF:_buildTrendsView(pane)
    local Options = ns:GetSubsystem("Options")
    local tv = CreateFrame("Frame", nil, pane)
    tv:SetPoint("TOPLEFT",     0, -34)
    tv:SetPoint("BOTTOMRIGHT", 0, 0)
    tv:Hide()

    tv._granDaily  = makeToggleButton(tv, L["Daily"], 60)
    tv._granDaily:SetPoint("TOPLEFT", 12, -4)
    tv._granWeekly = makeToggleButton(tv, L["Weekly"], 60)
    tv._granWeekly:SetPoint("LEFT", tv._granDaily, "RIGHT", 4, 0)
    tv._granDaily:SetScript("OnClick",  function() HF:_switchTrendGran("daily")  end)
    tv._granWeekly:SetScript("OnClick", function() HF:_switchTrendGran("weekly") end)

    local charLabel = tv:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    charLabel:SetPoint("LEFT", tv._granWeekly, "RIGHT", 16, 0)
    charLabel:SetText(L["Show:"])
    thin(charLabel)
    if Options and Options.CreateDropdown then
        local function listFn()
            local R = ns:GetSubsystem("History")
            local out = { { value = "all", label = L["All characters"] } }
            if R then
                local chars = R:GetCharacters()
                for i = 1, #chars do
                    out[#out + 1] = { value = chars[i], label = chars[i] }
                end
            end
            return out
        end
        local function curFn() return HF._trendCharFilter or "all" end
        local function setFn(v) HF._trendCharFilter = v; HF:_renderTrends() end
        tv._charDD = Options:CreateDropdown(tv, nil, listFn, curFn, setFn)
        tv._charDD:SetPoint("LEFT", charLabel, "RIGHT", 4, 0)
        tv._charDD:SetWidth(170)
    end

    tv._mGold  = makeToggleButton(tv, L["Gold"], 64)
    tv._mGold:SetPoint("TOPRIGHT", -12, -4)
    tv._mXP    = makeToggleButton(tv, L["XP"], 64)
    tv._mXP:SetPoint("RIGHT", tv._mGold, "LEFT", -4, 0)
    tv._mCount = makeToggleButton(tv, L["Quests"], 64)
    tv._mCount:SetPoint("RIGHT", tv._mXP, "LEFT", -4, 0)
    tv._mGold:SetScript("OnClick",  function() HF:_switchTrendMetric("gold")  end)
    tv._mXP:SetScript("OnClick",    function() HF:_switchTrendMetric("xp")    end)
    tv._mCount:SetScript("OnClick", function() HF:_switchTrendMetric("count") end)

    tv._cards = {}
    for i = 1, 3 do
        local card = makeCard(tv)
        if i == 1 then
            card:SetPoint("TOPLEFT", 12, -34)
        else
            card:SetPoint("LEFT", tv._cards[i - 1], "RIGHT", CARD_GAP, 0)
        end
        tv._cards[i] = card
    end

    local chart = CreateFrame("Frame", nil, tv)
    chart:SetPoint("TOPLEFT",     12, -(34 + CARD_H + 14))
    chart:SetPoint("BOTTOMRIGHT", -12, 46)
    local cbg = chart:CreateTexture(nil, "BACKGROUND")
    cbg:SetAllPoints()
    cbg:SetColorTexture(1, 1, 1, 0.03)
    tv._chart = chart

    tv._bars = {}
    for i = 1, STATS_MAX_BARS do
        local bar = CreateFrame("Frame", nil, chart)
        bar:EnableMouse(true)
        bar.fill = bar:CreateTexture(nil, "ARTWORK")
        bar.fill:SetAllPoints()
        bar:SetScript("OnEnter", barOnEnter)
        bar:SetScript("OnLeave", GameTooltip_Hide)
        bar:Hide()
        tv._bars[i] = bar
    end

    tv._axisL = tv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tv._axisL:SetPoint("TOPLEFT", chart, "BOTTOMLEFT", 0, -2)
    thin(tv._axisL)
    tv._axisR = tv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tv._axisR:SetPoint("TOPRIGHT", chart, "BOTTOMRIGHT", 0, -2)
    tv._axisR:SetJustifyH("RIGHT")
    thin(tv._axisR)

    tv._caveat = tv:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tv._caveat:SetPoint("BOTTOMLEFT",  12, 8)
    tv._caveat:SetPoint("BOTTOMRIGHT", -12, 8)
    tv._caveat:SetJustifyH("LEFT")
    tv._caveat:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    tv._caveat:SetText(L["Gold is all income (loot, vendor, rewards) tracked forward from when this version was installed \226\128\148 past periods may read 0. XP and quest counts come from quest turn-ins."])
    thin(tv._caveat)

    return tv
end

function HF:_switchStatsView(view)
    local pane = self._panes and self._panes.totals
    if not pane then return end
    self._statsView = view
    if view == "trends" then
        pane._totalsView:Hide()
        pane._trendsView:Show()
    else
        pane._trendsView:Hide()
        pane._totalsView:Show()
    end
    pane._segTotals:SetActive(view == "totals")
    pane._segTrends:SetActive(view == "trends")
    self:_renderStats()
end

function HF:_switchTrendGran(gran)
    self._trendGran = gran
    self:_renderTrends()
end

function HF:_switchTrendMetric(metric)
    self._trendMetric = metric
    self:_renderTrends()
end

function HF:_renderStats()
    if self._statsView == "trends" then
        self:_renderTrends()
    else
        self:_renderTotals()
    end
end

function HF:_renderTrends()
    local pane = self._panes and self._panes.totals
    local tv   = pane and pane._trendsView
    local R    = ns:GetSubsystem("History")
    if not (tv and R and R.Trends) then return end

    local gran   = self._trendGran   or "daily"
    local metric = self._trendMetric or "gold"
    local data   = R:Trends(gran, self._trendCharFilter)
    local periods = data.periods
    local n = #periods
    if n == 0 then return end

    local cur  = periods[n]
    local prev = periods[n - 1] or { xp = 0, gold = 0, count = 0 }
    local curLabel  = (gran == "weekly") and L["This week"] or L["Today"]
    local prevLabel = (gran == "weekly") and L["last week"] or L["yesterday"]
    local CARD_DEFS = {
        { key = "count", name = L["Quests"] },
        { key = "xp",    name = L["XP"] },
        { key = "gold",  name = L["Gold"] },
    }
    for i = 1, 3 do
        local d    = CARD_DEFS[i]
        local card = tv._cards[i]
        card.label:SetText((L["%s \226\128\148 %s"]):format(d.name, curLabel))
        card.value:SetText(formatMetric(d.key, cur[d.key] or 0))
        local delta = (cur[d.key] or 0) - (prev[d.key] or 0)
        card.delta:SetText((L["%s vs %s"]):format(fmtDelta(d.key, delta), prevLabel))
    end

    local maxV = (metric == "xp" and data.maxXP)
              or (metric == "gold" and data.maxGold)
              or data.maxCount
    local chart = tv._chart
    local cw = chart:GetWidth()
    local ch = chart:GetHeight()
    if not cw or cw <= 1 then cw = (tv:GetWidth() or 660) - 24 end
    if not ch or ch <= 1 then ch = 180 end
    local barW = (cw - (n - 1) * BAR_GAP) / n

    for i = 1, STATS_MAX_BARS do
        local bar = tv._bars[i]
        if i <= n then
            local p = periods[i]
            local v = (metric == "xp" and p.xp) or (metric == "gold" and p.gold) or p.count
            local h = 0
            if maxV > 0 and v > 0 then h = math.max(2, (v / maxV) * (ch - 4)) end
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", chart, "BOTTOMLEFT", (i - 1) * (barW + BAR_GAP), 0)
            bar:SetSize(math.max(barW, 1), math.max(h, 1))
            bar.fill:SetColorTexture(YELLOW[1], YELLOW[2], YELLOW[3], v > 0 and 0.9 or 0.12)
            local rng = p.label
            if gran == "weekly" then rng = rng .. " \226\128\147 " .. date("!%b %d", p.day1 * 86400) end
            bar._rangeText = rng
            bar._valueText = formatMetric(metric, v)
            bar:Show()
        else
            bar:Hide()
        end
    end

    tv._axisL:SetText(periods[1].label)
    tv._axisR:SetText(periods[n].label)

    tv._granDaily:SetActive(gran == "daily")
    tv._granWeekly:SetActive(gran == "weekly")
    tv._mCount:SetActive(metric == "count")
    tv._mXP:SetActive(metric == "xp")
    tv._mGold:SetActive(metric == "gold")
end

function HF:_buildSessionPane(parent)
    local pane = CreateFrame("Frame", nil, parent)
    pane:SetAllPoints()
    pane:Hide()

    pane._intro = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._intro:SetPoint("TOPLEFT",  30, -12)
    pane._intro:SetPoint("TOPRIGHT", -30, -12)
    pane._intro:SetJustifyH("LEFT")
    pane._intro:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
    pane._intro:SetText(L["Your quest activity this play session. A session starts when you log in and continues across /reload; it resets the next time you log in fresh."])
    thin(pane._intro)

    local function pairBlock(yOffset, labelText)
        local label = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", 30, yOffset)
        label:SetTextColor(MUTED[1], MUTED[2], MUTED[3])
        label:SetText(labelText)
        thin(label)
        local value = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        value:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        value:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
        thin(value)
        return value
    end

    pane._played = pairBlock(-46,  L["Played this session"])
    pane._quests = pairBlock(-100, L["Quests completed"])
    pane._xp     = pairBlock(-154, L["Quest XP earned"])
    pane._gold   = pairBlock(-208, L["Quest gold earned"])
    pane._levels = pairBlock(-262, L["Level-ups"])

    return pane
end

function HF:_renderSession()
    local pane = self._panes.session
    local Sess = ns:GetSubsystem("Session")
    if not (pane and Sess and Sess.Summary) then return end
    local sm = Sess:Summary()

    pane._played:SetText(ns.Util.FmtDuration(sm.played))

    local rate = sm.perHour and (L["   |cffaaaaaa(%.1f / hour)|r"]):format(sm.perHour) or ""
    pane._quests:SetText(fmtBigNumber(sm.quests) .. rate)

    pane._xp:SetText(fmtBigNumber(sm.xp) .. " XP")
    pane._gold:SetText(fmtMoney(sm.gold))

    if sm.levelUps > 0 then
        pane._levels:SetText((L["%d   |cffaaaaaa(%d to %d)|r"]):format(
            sm.levelUps, sm.startLevel, sm.curLevel))
    else
        pane._levels:SetText("0")
    end
end

function HF:Render()
    if not self.frame or not self.frame:IsShown() then return end
    local t = self._activeTab
    if t == "quests"   then self:_renderQuests() end
    if t == "streak"   then self:_renderStreak() end
    if t == "timeline" then self:_renderTimeline() end
    if t == "activity" then self:_renderHeatmap() end
    if t == "totals"   then self:_renderStats()  end
    if t == "session"  then self:_renderSession() end
end

function HF:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Open() end
end

function HF:Open()
    self:Build()
    self.frame:Show()
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
    local R = ns:GetSubsystem("History")
    if not R then return "(history unavailable)" end
    local pane = self._panes.quests
    local searchText = pane._search and pane._search:GetText() or ""
    if searchText == SEARCH then searchText = "" end
    local entries = R:Query({
        search         = searchText,
        char           = HF._charFilter,
        dateRange      = HF._dateFilter,
        classification = HF._classFilter,
        hideBackfilled = HF._hideBackfilled,
        sortBy         = HF._sortBy or "date",
        sortDir        = HF._sortDir or "desc",
    })
    local lines = { ("# Quest History — %d entries"):format(#entries) }
    lines[#lines + 1] = "# date | character | quest | type | zone"
    for i = 1, #entries do
        local e = entries[i]
        local d = (e.t and e.t > 0) and date("%Y-%m-%d %H:%M", e.t) or L["(before tracking)"]
        lines[#lines + 1] = ("%s | %s | %s | %s | %s"):format(
            d, e.c or "?", e.n or ("Quest #" .. tostring(e.q)), e.k or "?", e.z or "")
    end
    return table.concat(lines, "\n")
end

function HF:_exportStreak()
    local R = ns:GetSubsystem("History")
    if not R then return "(history unavailable)" end
    local s = R:Streak()
    return ("Quest History — Streak\n\nCurrent daily streak: %d days\nBest daily streak: %d days\nTotal dated entries: %d"):format(
        s.current, s.best, s.total)
end

function HF:_exportTimeline()
    local R        = ns:GetSubsystem("History")
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (R and Database) then return "(history or chain guide unavailable)" end
    local completion = R:CompletionMap()
    local sorted = {}
    for chainID, chain in pairs(Database.chains) do
        if chain.items and #chain.items > 0 then
            local doneN, latest, questTotal = 0, 0, 0
            for i = 1, #chain.items do
                local it = chain.items[i]
                if it and it.type == "quest" then
                    questTotal = questTotal + 1
                    if completion[it.id] then
                        doneN = doneN + 1
                        if completion[it.id] > latest then latest = completion[it.id] end
                    end
                end
            end
            if doneN > 0 then
                sorted[#sorted + 1] = { id = chainID, chain = chain, doneN = doneN, latest = latest, total = questTotal }
            end
        end
    end
    table.sort(sorted, function(a, b) return a.latest > b.latest end)
    local lines = { "# Chain Timeline — chains with at least one recorded completion" }
    for _, rec in ipairs(sorted) do
        lines[#lines + 1] = ("## %s — %d of %d quests"):format(
            rec.chain.name or ("Chain #" .. tostring(rec.id)), rec.doneN, rec.total)
        for j = 1, #rec.chain.items do
            local it = rec.chain.items[j]
            if it and it.type == "quest" then
                local t = completion[it.id]
                local title = ns.Util.QuestTitle(it.id) or it.name or ("Quest #" .. tostring(it.id))
                local when = t and ((t > 0 and date("%Y-%m-%d", t)) or L["(before tracking)"]) or "—"
                lines[#lines + 1] = ("  - %s [%s]"):format(title, when)
            end
        end
    end
    return table.concat(lines, "\n")
end

function HF:_exportActivity()
    local R = ns:GetSubsystem("History")
    if not (R and R.DayCounts) then return "(history unavailable)" end
    local counts, today = R:DayCounts(HEATMAP_DAYS)
    local lines = { ("# Activity — last %d days"):format(HEATMAP_DAYS) }
    lines[#lines + 1] = "# date | turn-ins"
    for i = HEATMAP_DAYS, 1, -1 do
        local day = today - (i - 1)
        lines[#lines + 1] = ("%s | %d"):format(date("!%Y-%m-%d", day * 86400), counts[day] or 0)
    end
    return table.concat(lines, "\n")
end

function HF:_exportTotals()
    local R = ns:GetSubsystem("History")
    if not (R and R.Totals) then return "(history unavailable)" end
    local t = R:Totals()
    local lines = {
        "Quest History — Totals",
        "",
        ("Total quests with reward data: %d"):format(t.totalCount),
        ("Total gold earned: %s"):format(fmtMoneyText(t.totalMoney)),
        ("Total XP earned: %d"):format(t.totalXP),
        "",
        "By character:",
    }
    local chars = {}
    for k, v in pairs(t.byChar) do chars[#chars + 1] = { key = k, rec = v } end
    table.sort(chars, function(a, b) return a.rec.count > b.rec.count end)
    for _, c in ipairs(chars) do
        lines[#lines + 1] = ("  %s — %d quests, %s, %d XP"):format(
            c.key, c.rec.count, fmtMoneyText(c.rec.money), c.rec.xp)
    end
    if t.topGold then
        lines[#lines + 1] = ""
        lines[#lines + 1] = ("Biggest single gold reward: %s (%s)"):format(
            t.topGold.n or ("Quest #" .. tostring(t.topGold.q)), fmtMoneyText(t.topGold.m))
    end
    if t.topXP then
        lines[#lines + 1] = ("Biggest single XP reward: %s (%d XP)"):format(
            t.topXP.n or ("Quest #" .. tostring(t.topXP.q)), t.topXP.xp)
    end
    return table.concat(lines, "\n")
end

function HF:_exportTrends()
    local R = ns:GetSubsystem("History")
    if not (R and R.Trends) then return "(history unavailable)" end
    local gran  = self._trendGran or "daily"
    local scope = self._trendCharFilter
    local data  = R:Trends(gran, scope)
    local scopeLabel = (not scope or scope == "all" or scope == "") and "all characters" or scope
    local lines = {
        ("Quest History — Trends (%s, %s)"):format(gran == "weekly" and "weekly" or "daily", scopeLabel),
        "",
        "# period | quests | xp | gold",
    }
    for i = 1, #data.periods do
        local p = data.periods[i]
        local period = (gran == "weekly")
            and (date("!%Y-%m-%d", p.day0 * 86400) .. " – " .. date("!%Y-%m-%d", p.day1 * 86400))
            or  date("!%Y-%m-%d", p.day0 * 86400)
        lines[#lines + 1] = ("%s | %d | %d | %s"):format(
            period, p.count, p.xp, fmtMoneyText(p.gold))
    end
    return table.concat(lines, "\n")
end

function HF:_exportSession()
    local Sess = ns:GetSubsystem("Session")
    if not (Sess and Sess.Summary) then return "(session unavailable)" end
    local sm = Sess:Summary()
    local lines = {
        "Everything Quests - This Session",
        "",
        ("Played: %s"):format(ns.Util.FmtDuration(sm.played)),
        ("Quests completed: %d%s"):format(sm.quests,
            sm.perHour and ((" (%.1f/hour)"):format(sm.perHour)) or ""),
        ("Quest XP earned: %d"):format(sm.xp),
        ("Quest gold earned: %s"):format(fmtMoneyText(sm.gold)),
    }
    if sm.levelUps > 0 then
        lines[#lines + 1] = ("Level-ups: %d (%d to %d)"):format(
            sm.levelUps, sm.startLevel, sm.curLevel)
    end
    return table.concat(lines, "\n")
end

function HF:_exportForTab(tabId)
    if tabId == "quests"   then return self:_exportQuests()   end
    if tabId == "streak"   then return self:_exportStreak()   end
    if tabId == "timeline" then return self:_exportTimeline() end
    if tabId == "activity" then return self:_exportActivity() end
    if tabId == "totals"   then
        if self._statsView == "trends" then return self:_exportTrends() end
        return self:_exportTotals()
    end
    if tabId == "session"  then return self:_exportSession()  end
    return "(nothing to export)"
end

function HF:_buildExportPopup()
    if self._exportPopup then return self._exportPopup end

    local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    p:SetSize(540, 380)
    p:SetPoint("CENTER")
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetMovable(true)
    p:EnableMouse(true)
    p:RegisterForDrag("LeftButton")
    p:SetScript("OnDragStart", p.StartMoving)
    p:SetScript("OnDragStop",  p.StopMovingOrSizing)
    p:SetClampedToScreen(true)
    p:Hide()
    p:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0.02, 0.02, 0.02, 0.97)
    p:SetBackdropBorderColor(HEADER_RED[1], HEADER_RED[2], HEADER_RED[3], 1)

    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT", 12, -10)
    p.title:SetText(L["Export"])
    p.title:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    thin(p.title)

    p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    p.hint:SetPoint("TOPLEFT", 12, -32)
    p.hint:SetText(L["Press Ctrl+A to select all, then Ctrl+C to copy."])
    thin(p.hint)

    p.close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    p.close:SetPoint("TOPRIGHT", -4, -4)
    p.close:SetScript("OnClick", function() p:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -52)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    p._scroll = scroll

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject("ChatFontNormal")
    edit:SetWidth(scroll:GetWidth())
    edit:SetScript("OnEscapePressed", function() p:Hide() end)
    scroll:SetScrollChild(edit)
    p._edit = edit

    self._exportPopup = p
    return p
end

function HF:_openExportPopup()
    local p = self:_buildExportPopup()
    local text = self:_exportForTab(self._activeTab) or ""
    p._edit:SetText(text)
    p._edit:HighlightText()
    p._edit:SetFocus()
    p:Show()
end
