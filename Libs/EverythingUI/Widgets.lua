local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local FIELD_PAD = 10
local SEARCH_ICON = 14
local SEARCH_GAP = 8
local MAX_LETTERS = 64
local ROW_PAD = 12
local ROW_GAP = 8
local ROW_ICON = 12
local LIST_BOTTOM = 12
local SCROLLBAR_INSET = 3
local BAR_ROOM = 12
local TAG_HEIGHT = 16
local TAG_PAD = 6
local EMPTY_INSET = 40
local NAV_PAD = 8
local NAV_TOP = 12
local MULTI_PAD = 8

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

-- One line to type into, with a magnifier and a hint shown while it is empty and unfocused. Enter
-- hands the trimmed text to onSubmit and lets go of the keyboard, and Escape only lets go.
function Context:CreateSearchField(parent, placeholder, onSubmit, tipTitle, tipBody)
    if type(onSubmit) ~= "function" then error("EverythingUI: CreateSearchField needs onSubmit", 2) end
    local sp = lib.tokens.spacing
    local ctx = self
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(sp.fieldHeight)
    holder._euiFill = true
    kit.Fill(self, holder, "input")
    local edges = kit.Edge(self, holder, "inputBorder")

    local icon = kit.Icon(self, holder, "search", SEARCH_ICON, "muted")
    icon:SetPoint("LEFT", FIELD_PAD, 0)

    -- What is typed can be a name in any alphabet, so the field draws in the client's own font
    -- object rather than the UI font (decision 14).
    local box = CreateFrame("EditBox", nil, holder)
    box:SetPoint("LEFT", icon, "RIGHT", SEARCH_GAP, 0)
    box:SetPoint("RIGHT", -FIELD_PAD, 0)
    box:SetHeight(sp.fieldHeight)
    box:SetAutoFocus(false)
    box:SetMaxLetters(MAX_LETTERS)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(0, 0, 0, 0)

    local hint = kit.Text(self, holder, "label", "muted")
    hint:SetPoint("LEFT", box, "LEFT")
    hint:SetPoint("RIGHT", box, "RIGHT")
    hint:SetWordWrap(false)
    hint:SetText(placeholder or "")

    local function paint()
        local focused = box:HasFocus()
        hint:SetShown(not focused and box:GetText() == "")
        for _, line in ipairs(edges) do line:SetColorTexture(ctx:Color(focused and "borderStrong" or "inputBorder")) end
    end
    box:SetScript("OnEditFocusGained", paint)
    box:SetScript("OnEditFocusLost", paint)
    box:SetScript("OnTextChanged", paint)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(b)
        local text = trim(b:GetText())
        b:ClearFocus()
        if text ~= "" then onSubmit(text) end
    end)
    paint()

    holder.box = box
    holder.hint = hint
    function holder.GetText() return box:GetText() end
    function holder.SetText(_, s)
        box:SetText(s or "")
        paint()
    end
    if tipTitle or tipBody then self:AttachTooltip(box, tipTitle, tipBody) end
    return holder
end

-- A string a list row draws in the UI font, and its twin in the client's font object, which takes
-- over for text Barlow cannot draw (decision 14).
local function setRowText(ctx, row, s, style, color)
    local useData = kit.NeedsClientFont(s)
    kit.Style(ctx, row.text, style, color)
    row.data:SetTextColor(ctx:Color(color))
    row.text:SetText(s)
    row.data:SetText(s)
    row.text:SetShown(not useData)
    row.data:SetShown(useData)
end

local function newRow(ctx, list)
    local sp = lib.tokens.spacing
    local b = CreateFrame("Button", nil, list.content)
    b:SetHeight(sp.listRowHeight)
    b.selected = kit.Fill(ctx, b, "accentSoft")
    kit.Highlight(ctx, b)
    b.value = kit.Text(ctx, b, "hint")
    b.value:SetPoint("RIGHT", -ROW_PAD, 0)
    b.value:SetJustifyH("RIGHT")
    b.icons = {}
    b.text = kit.Text(ctx, b, "label")
    b.text:SetWordWrap(false)
    b.data = kit.DataText(b)
    b.data:SetWordWrap(false)
    return b
end

local function rowIcon(b, i)
    local t = b.icons[i]
    if not t then
        t = b:CreateTexture(nil, "ARTWORK")
        t:SetSize(ROW_ICON, ROW_ICON)
        b.icons[i] = t
    end
    return t
end

-- Every property a row can carry is set again on each paint, because rows are reused for whatever
-- the list shows next.
local function paintRow(ctx, list, b, row, index)
    b.selected:SetShown(row.selected == true)
    local color = (row.selected and "text") or (row.muted and "muted") or "label"
    setRowText(ctx, b, row.text or "", row.selected and "navActive" or "label", color)
    b.value:SetText(row.value or "")

    local right = b.value
    local edge = (row.value and row.value ~= "") and ROW_GAP or 0
    local shownIcons = 0
    for i, spec in ipairs(row.icons or {}) do
        local t = rowIcon(b, i)
        t:SetTexture(ctx:Texture(spec.name))
        t:SetVertexColor(ctx:Color(spec.color or "muted"))
        t:ClearAllPoints()
        t:SetPoint("RIGHT", right, "LEFT", -edge, 0)
        t:Show()
        right, edge = t, ROW_GAP
        shownIcons = i
    end
    for i = shownIcons + 1, #b.icons do b.icons[i]:Hide() end

    for _, fs in ipairs({ b.text, b.data }) do
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", ROW_PAD, 0)
        fs:SetPoint("RIGHT", right, (right == b.value and edge == 0) and "RIGHT" or "LEFT", -edge, 0)
    end

    local getTip = ctx.opts.tooltip
    if row.tip then
        local title, body = row.tip[1], row.tip[2]
        b:SetScript("OnEnter", function(s) kit.ShowTip(getTip, s, title, body, "ANCHOR_RIGHT") end)
        b:SetScript("OnLeave", function() getTip():Hide() end)
    else
        b:SetScript("OnEnter", nil)
        b:SetScript("OnLeave", nil)
    end
    b:SetScript("OnClick", function()
        if list.onClick then list.onClick(row.key, row, index) end
    end)
end

local ROW_FIELDS = {
    key = true, text = "string", value = "string", selected = "boolean", muted = "boolean",
    icons = "table", tip = "table",
}

local function checkRows(rows)
    if type(rows) ~= "table" then error("EverythingUI: SetRows needs a list", 3) end
    for i, row in ipairs(rows) do
        if type(row) ~= "table" or type(row.text) ~= "string" then
            error(("EverythingUI: SetRows row %d needs text"):format(i), 3)
        end
        for key, v in pairs(row) do
            local want = ROW_FIELDS[key]
            if not want or (want ~= true and type(v) ~= want) then
                error(("EverythingUI: SetRows row %d has a bad or unknown field %s"):format(i, tostring(key)), 3)
            end
        end
        if row.tip and type(row.tip[1]) ~= "string" and type(row.tip[2]) ~= "string" then
            error(("EverythingUI: SetRows row %d has a tip with no text"):format(i), 3)
        end
        for _, icon in ipairs(row.icons or {}) do
            if type(icon) ~= "table" or type(icon.name) ~= "string"
               or (icon.color ~= nil and type(icon.color) ~= "string") then
                error(("EverythingUI: SetRows row %d has an icon with no name"):format(i), 3)
            end
        end
    end
end

-- A scrolling list of 28 px rows: text, an optional value at the right end, optional small icons
-- before the value, a selected row in the accent's soft tint and the hover tint. onClick(key, row,
-- index) runs on a click. Rows are { key, text, value, selected, muted, icons = { { name, color } },
-- tip = { title, body } }.
function Context:CreateList(parent, onClick)
    local sp = lib.tokens.spacing
    local ctx = self
    local list = CreateFrame("Frame", nil, parent)
    local sf, content, bar = kit.Scroll(self, list)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT")
    bar:SetPoint("TOPRIGHT", -SCROLLBAR_INSET, 0)
    bar:SetPoint("BOTTOMRIGHT", -SCROLLBAR_INSET, LIST_BOTTOM)
    list.scroll, list.content, list.bar = sf, content, bar
    list.rows, list.onClick = {}, onClick
    list._shown = 0

    local function width()
        local w = sf:GetWidth() or 0
        if bar:IsShown() then w = w - BAR_ROOM end
        return math.max(1, w)
    end

    function list.SetRows(_, rows)
        checkRows(rows)
        for i, row in ipairs(rows) do
            local b = list.rows[i]
            if not b then
                b = newRow(ctx, list)
                list.rows[i] = b
            end
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * sp.listRowHeight)
            b:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(i - 1) * sp.listRowHeight)
            paintRow(ctx, list, b, row, i)
            b:Show()
        end
        for i = #rows + 1, #list.rows do list.rows[i]:Hide() end
        list._shown = #rows
        content:SetSize(width(), math.max(1, #rows * sp.listRowHeight + LIST_BOTTOM))
    end

    -- Brings a row into view, the least scroll that shows it whole. Answers false when the list has
    -- no height yet, so the host can ask again once it has one.
    function list.ScrollToRow(_, index)
        local view = sf:GetHeight() or 0
        if view <= 0 then return false end
        -- Updated first, as Blizzard's ItemTextFrame does before it reads the range of a child it resized.
        if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
        local max = math.floor(math.max(0, sf:GetVerticalScrollRange() or 0))
        bar:SetMinMaxValues(0, max)
        local rowH = sp.listRowHeight
        local top, bottom = (index - 1) * rowH, index * rowH
        local v = bar:GetValue()
        if top < v then v = top elseif bottom > v + view then v = bottom - view end
        bar:SetValue(math.min(max, math.max(0, v)))
        return true
    end

    -- The content takes the list's width once it has one, and again on every resize, whenever the bar
    -- comes or goes, and when the list shows, in case the bar came or went while it was hidden.
    local function fitWidth() content:SetWidth(width()) end
    list:SetScript("OnSizeChanged", fitWidth)
    list:HookScript("OnShow", fitWidth)
    bar:HookScript("OnShow", fitWidth)
    bar:HookScript("OnHide", fitWidth)
    return list
end

local TAG_STYLES = { accent = true, outline = true }

-- A small label, such as a quest's state: "accent" fills it with the accent, "outline" draws a
-- borderStrong edge.
function Context:CreateTag(parent, text, style)
    style = style or "outline"
    if not TAG_STYLES[style] then error(("EverythingUI: no tag style named %s"):format(tostring(style)), 2) end
    local tag = CreateFrame("Frame", nil, parent)
    tag:SetHeight(TAG_HEIGHT)
    local fill = kit.Fill(self, tag, "accent")
    local edges = kit.Edge(self, tag, "borderStrong")
    local fs = kit.Text(self, tag, "segment")
    fs:SetPoint("CENTER")
    tag.text = fs
    local ctx = self
    function tag.Fit()
        local w = fs:GetStringWidth()
        if not w or w <= 0 then w = 24 end
        tag:SetWidth(math.ceil(w) + TAG_PAD * 2)
    end
    function tag.SetStyle(_, s)
        if not TAG_STYLES[s] then error(("EverythingUI: no tag style named %s"):format(tostring(s)), 2) end
        fill:SetShown(s == "accent")
        for _, line in ipairs(edges) do line:SetShown(s == "outline") end
        fs:SetTextColor(ctx:Color(s == "accent" and "accentText" or "label"))
    end
    function tag.SetText(_, s)
        fs:SetText(s or "")
        tag:Fit()
    end
    tag:SetStyle(style)
    tag:SetText(text)
    return tag
end

-- A thin bar for a share, such as how much of a chain is done.
function Context:CreateProgressBar(parent, width)
    local sp = lib.tokens.spacing
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width or 120, sp.trackHeight)
    kit.Fill(self, bar, "track")
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("TOPLEFT")
    fill:SetPoint("BOTTOMLEFT")
    fill:SetColorTexture(self:Color("accent"))
    bar.fill = fill
    bar._progress = 0
    local function paint()
        local w = (bar:GetWidth() or 0) * bar._progress
        fill:SetWidth(math.max(w, 0.001))
        fill:SetShown(bar._progress > 0)
    end
    function bar.SetProgress(_, frac)
        frac = tonumber(frac) or 0
        bar._progress = math.min(1, math.max(0, frac))
        paint()
    end
    bar:SetScript("OnSizeChanged", paint)
    paint()
    return bar
end

-- The library's panel look on any frame a host draws itself: a fill in one color and a 1 px edge in
-- another, on the sides named ("TBLR" unless told), re-snapped with every other library line. Either
-- can be nil.
function Context:Paint(frame, fill, edge, sides)
    local f = fill and kit.Fill(self, frame, fill) or nil
    local e = edge and kit.Edge(self, frame, edge, sides) or {}
    return f, e
end

-- One muted line in the middle of a view that has nothing to show.
function Context:CreateEmptyState(parent, text)
    local fs = kit.Text(self, parent, "label", "muted")
    fs:SetPoint("LEFT", EMPTY_INSET, 0)
    fs:SetPoint("RIGHT", -EMPTY_INSET, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(true)
    fs:SetText(text or "")
    return fs
end

local NAV_FIELDS = { id = "string", title = "string", icon = "string" }

-- A main window's pages in its sidebar, drawn as the settings window's tabs are
function Context:CreateNav(parent, pages, onSelect)
    if type(pages) ~= "table" or #pages == 0 then error("EverythingUI: CreateNav needs a list of pages", 2) end
    if onSelect ~= nil and type(onSelect) ~= "function" then error("EverythingUI: CreateNav's onSelect must be a function", 2) end
    local ids = {}
    for i, p in ipairs(pages) do
        if type(p) ~= "table" or type(p.id) ~= "string" or type(p.title) ~= "string" then
            error(("EverythingUI: CreateNav page %d needs an id and a title"):format(i), 2)
        end
        if ids[p.id] then error(("EverythingUI: CreateNav page %d repeats the id %s"):format(i, p.id), 2) end
        ids[p.id] = true
        for key, v in pairs(p) do
            if NAV_FIELDS[key] ~= type(v) then
                error(("EverythingUI: CreateNav page %d has a bad or unknown field %s"):format(i, tostring(key)), 2)
            end
        end
    end
    local sp = lib.tokens.spacing
    local ctx = self
    local nav = CreateFrame("Frame", nil, parent)
    nav:SetPoint("TOPLEFT", NAV_PAD, -NAV_TOP)
    nav:SetPoint("TOPRIGHT", -NAV_PAD, -NAV_TOP)
    nav:SetHeight(#pages * sp.navItemHeight + (#pages - 1) * sp.navItemGap)
    nav.items = {}
    local width = math.max(1, (parent:GetWidth() or 0) - NAV_PAD * 2)
    local prev
    for _, p in ipairs(pages) do
        local b = kit.NavItem(ctx, nav, width, p.title, p.icon)
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -sp.navItemGap)
            b:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -sp.navItemGap)
        else
            b:SetPoint("TOPLEFT")
            b:SetPoint("TOPRIGHT")
        end
        local id = p.id
        b:SetScript("OnClick", function()
            nav:Select(id)
            if onSelect then onSelect(id) end
        end)
        kit.PaintNav(ctx, b, false)
        nav.items[id] = b
        prev = b
    end
    function nav.Select(_, id)
        if not nav.items[id] then error(("EverythingUI: CreateNav has no page %s"):format(tostring(id)), 2) end
        for key, b in pairs(nav.items) do kit.PaintNav(ctx, b, key == id) end
        nav._selected = id
    end
    function nav.GetSelected() return nav._selected end
    return nav
end

local MULTI_FIELDS = { readOnly = "boolean" }

-- In the client's font object (decision 14), since what it holds can be in any alphabet
function Context:CreateMultilineField(parent, opts)
    if opts ~= nil and type(opts) ~= "table" then error("EverythingUI: CreateMultilineField's opts must be a table", 2) end
    opts = opts or {}
    for key, v in pairs(opts) do
        if MULTI_FIELDS[key] ~= type(v) then
            error(("EverythingUI: CreateMultilineField got a bad or unknown field %s"):format(tostring(key)), 2)
        end
    end
    local ctx = self
    local holder = CreateFrame("Frame", nil, parent)
    holder._euiFill = true
    kit.Fill(self, holder, "input")
    local edges = kit.Edge(self, holder, "inputBorder")
    local sf, _, bar = kit.Scroll(self, holder)
    sf:SetPoint("TOPLEFT", MULTI_PAD, -MULTI_PAD)
    sf:SetPoint("BOTTOMRIGHT", -(MULTI_PAD + BAR_ROOM), MULTI_PAD)
    bar:SetPoint("TOPRIGHT", -SCROLLBAR_INSET, -MULTI_PAD)
    bar:SetPoint("BOTTOMRIGHT", -SCROLLBAR_INSET, MULTI_PAD)

    local box = CreateFrame("EditBox", nil, sf)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(GameFontHighlight)
    box:SetTextInsets(0, 0, 0, 0)
    box:SetWidth(1)
    sf:SetScrollChild(box)
    -- The box takes the scroll frame's width, so its lines wrap there rather than running past the edge.
    sf:SetScript("OnSizeChanged", function(_, w) box:SetWidth(math.max(1, w or 0)) end)

    local stored = ""
    local function paint()
        for _, line in ipairs(edges) do line:SetColorTexture(ctx:Color(box:HasFocus() and "borderStrong" or "inputBorder")) end
    end
    box:SetScript("OnEditFocusGained", paint)
    box:SetScript("OnEditFocusLost", paint)
    box:SetScript("OnEscapePressed", function(b) b:ClearFocus() end)
    box:SetScript("OnTextChanged", function(b, userInput)
        if opts.readOnly and userInput and b:GetText() ~= stored then
            b:SetText(stored)
            b:SetCursorPosition(0)
            b:HighlightText()
        end
    end)
    -- Keeps the cursor in view as it moves through the text, as Blizzard's scrolling edit boxes do.
    box:SetScript("OnCursorChanged", function(_, _, y, _, h)
        -- The range is read afresh, or a new last line clamps to the old one
        if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
        bar:SetMinMaxValues(0, math.floor(math.max(0, sf:GetVerticalScrollRange() or 0)))
        local top, view, v = -(y or 0), sf:GetHeight() or 0, sf:GetVerticalScroll() or 0
        if top < v then
            bar:SetValue(top)
        elseif top + (h or 0) > v + view then
            bar:SetValue(top + (h or 0) - view)
        end
    end)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() box:SetFocus() end)

    holder.box, holder.scroll, holder.bar = box, sf, bar
    function holder.SetText(_, s)
        stored = s or ""
        -- Sized now, since text laid out at the build width of 1 wraps a letter to a line
        local w = sf:GetWidth() or 0
        if w > 0 then box:SetWidth(w) end
        box:SetText(stored)
        box:SetCursorPosition(0)
        bar:SetValue(0)
    end
    function holder.GetText() return box:GetText() end
    -- Focus first, since taking the keyboard drops a selection made before it.
    function holder.SelectAll()
        box:SetFocus()
        box:HighlightText()
    end
    paint()
    return holder
end
