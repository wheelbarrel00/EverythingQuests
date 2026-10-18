local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local HEADER_PADDING = 16
local SIDEBAR_PADDING = 8
local SIDEBAR_TOP = 12
local ICON_SIZE = 16
local ICON_GAP = 10
local ACCENT_SQUARE = 10
local CLOSE_SIZE = 32
local SCROLLBAR_INSET = 9
local SCROLLBAR_BOTTOM = 8
local TWO_LINE_BUTTON = 44
local CHILD_GAP = 2
local GUIDE_INSET = 4
local SEARCH_GAP = 12
local PATH_SEP = " > "
local FLASH_ALPHA = 0.3
local FLASH_HOLD = 0.4
local FLASH_FADE = 1.2

local TAB_FIELDS = {
    id = "string", title = "string", order = "number", build = "function",
    refresh = "function", icon = "string", footer = "function",
    preview = "function", previewRefresh = "function",
    group = "boolean", parent = "string", header = "function",
}

-- A group is only a row in the sidebar, so it takes none of a page's fields.
local PAGE_FIELDS = { "build", "refresh", "footer", "header", "preview", "parent" }

local function tabById(ctx, id)
    for _, t in ipairs(ctx._tabs or {}) do
        if t.id == id then return t end
    end
end

function Context:RegisterTab(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or type(def.title) ~= "string"
            or (type(def.build) ~= "function" and not def.group) then
        error("EverythingUI: RegisterTab needs id, title and build", 2)
    end
    for key, v in pairs(def) do
        if TAB_FIELDS[key] ~= type(v) then
            error(("EverythingUI: RegisterTab got a bad or unknown field %s"):format(tostring(key)), 2)
        end
    end
    if def.previewRefresh and not def.preview then
        error("EverythingUI: RegisterTab got previewRefresh with no preview", 2)
    end
    if tabById(self, def.id) then
        error(("EverythingUI: RegisterTab got the id %s twice"):format(def.id), 2)
    end
    if def.group then
        for _, key in ipairs(PAGE_FIELDS) do
            if def[key] ~= nil then
                error(("EverythingUI: RegisterTab's group %s takes no %s"):format(def.id, key), 2)
            end
        end
    end
    if def.parent then
        local p = tabById(self, def.parent)
        if not (p and p.group) then
            error(("EverythingUI: RegisterTab's parent %s is not a group registered before it"):format(def.parent), 2)
        end
    end
    local tabs = self._tabs
    if not tabs then tabs = {} self._tabs = tabs end
    def._seq = #tabs + 1
    tabs[#tabs + 1] = def
    -- Lua's sort is not stable, so a tie in order falls back to registration order.
    table.sort(tabs, function(a, b)
        local oa, ob = a.order or 100, b.order or 100
        if oa ~= ob then return oa < ob end
        return a._seq < b._seq
    end)
end

-- Only the page's own row carries the active fill.
local function paintNav(ctx, t, active)
    if t.group then
        local b = t._nav
        kit.Style(ctx, b.label, "nav", active and "text" or nil)
        if b.icon then b.icon:SetVertexColor(ctx:Color(active and "accentHi" or "navText")) end
    else
        kit.PaintNav(ctx, t._nav, active)
    end
end

-- Only the group holding the page on screen can be open. Each row hangs from the one above it, so an
-- open group pushes the rows under it down.
local function layoutNav(ctx)
    local sp = lib.tokens.spacing
    local current = tabById(ctx, ctx._current)
    local open = current and current.parent
    local prev
    local function place(b, gap)
        b:ClearAllPoints()
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -gap)
        else
            b:SetPoint("TOPLEFT", SIDEBAR_PADDING, -(ctx._navTop or SIDEBAR_TOP))
        end
        prev = b
    end
    for _, t in ipairs(ctx._tabs or {}) do
        if not t.parent then
            place(t._nav, sp.navItemGap)
            if t.group then
                local isOpen = (t.id == open) and not t._collapsed
                t._nav.chevron:SetTexture(ctx:Texture(isOpen and "chevron-down" or "chevron-right"))
                for i, k in ipairs(t._kids) do
                    k._nav:SetShown(isOpen)
                    if isOpen then place(k._nav, i == 1 and CHILD_GAP or 0) end
                end
                local guide = t._guide
                guide:SetShown(isOpen)
                guide:ClearAllPoints()
                guide:SetPoint("TOPLEFT", t._kids[1]._nav, "TOPLEFT", sp.navItemPadding + ICON_SIZE / 2 - 1, -GUIDE_INSET)
                guide:SetHeight(#t._kids * sp.navChildHeight - GUIDE_INSET * 2)
            end
        end
    end
end

local function fillPage(ctx, t)
    if not t._built then
        t._content._controls = {}
        t.build(ctx, t._content)
        t._built = true
    end
    if t._footer and not t._footerBuilt then
        t.footer(ctx, t._footer)
        t._footerBuilt = true
    end
    if t._header and not t._headerBuilt then
        t.header(ctx, t._header)
        t._headerBuilt = true
    end
end

local function plain(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("%s+", " ")
    return (s:match("^ *(.-) *$"))
end

-- string.lower folds ASCII only, so the capitals of the Latin-1 and Cyrillic letters the family's languages
-- use are folded by hand (UTF-8: A-grave to Thorn but the multiplication sign, then U+0400 to U+042F).
local function fold(s)
    s = s:lower():gsub("\195([\128-\158])", function(c)
        local b = c:byte()
        if b ~= 151 then return "\195" .. string.char(b + 32) end
    end)
    s = s:gsub("\208([\128-\175])", function(c)
        local b = c:byte()
        if b < 144 then return "\209" .. string.char(b + 16) end
        if b < 160 then return "\208" .. string.char(b + 32) end
        return "\209" .. string.char(b - 32)
    end)
    return s
end

-- A setting is a control the page refreshes, and a button counts by its caption. A text row is neither.
local function labelOf(control, settings)
    local fs
    if settings[control] then
        fs = control.label
    elseif control.text and control.GetObjectType and control:GetObjectType() == "Button" then
        fs = control.text
    end
    local s = fs and fs.GetText and fs:GetText()
    if type(s) ~= "string" then return nil end
    s = plain(s)
    if s == "" then return nil end
    return s
end

local function settingsOf(frame)
    local set = {}
    for _, c in ipairs(frame._controls or {}) do set[c] = true end
    return set
end

-- In the sidebar's order. A group's pages are ordered among themselves, so _tabs alone can put them first.
local function pagesInOrder(ctx)
    local pages = {}
    for _, t in ipairs(ctx._tabs or {}) do
        if t.group then
            for _, k in ipairs(t._kids) do pages[#pages + 1] = k end
        elseif not t.parent then
            pages[#pages + 1] = t
        end
    end
    return pages
end

-- A setting a tab anchored to a card row by hand, such as a list's second column, is found right after that row.
local function besideRows(content)
    local isRow, rowControl, beside = {}, {}, {}
    for _, card in ipairs(content._euiCards or {}) do
        for _, row in ipairs(card._rows) do isRow[row], rowControl[row.control] = true, true end
    end
    for _, c in ipairs(content._controls or {}) do
        local rel = not rowControl[c] and c:GetNumPoints() > 0 and select(2, c:GetPoint(1))
        if rel and isRow[rel] then
            local list = beside[rel] or {}
            beside[rel] = list
            list[#list + 1] = c
        end
    end
    return beside
end

-- Every shown card and row of each built page, and the controls of each strip and footer.
local function gather(ctx)
    local found = {}
    local function add(t, text, path, scroll, flash)
        found[#found + 1] = { tab = t.id, text = text, path = path, scroll = scroll, flash = flash }
    end
    for _, t in ipairs(pagesInOrder(ctx)) do
        if t._built then
            local group = t.parent and tabById(ctx, t.parent)
            local path = group and (group.title .. PATH_SEP .. t.title) or t.title
            local content = t._content
            local settings = settingsOf(content)
            local beside = besideRows(content)
            for _, card in ipairs(content._euiCards or {}) do
                if card:IsShown() then
                    local title = card.label and card.label:GetText()
                    title = title and plain(title) or ""
                    local cardPath = path
                    if title ~= "" then
                        cardPath = path .. PATH_SEP .. title
                        add(t, title, path, card, card.panel)
                    end
                    for _, row in ipairs(card._rows) do
                        if row.control:IsShown() then
                            local label = labelOf(row.control, settings)
                            if label then add(t, label, cardPath, row, row) end
                            for _, c in ipairs(beside[row] or {}) do
                                local sideLabel = c:IsShown() and labelOf(c, settings)
                                if sideLabel then add(t, sideLabel, cardPath, row, row) end
                            end
                        end
                    end
                end
            end
            for _, bar in ipairs({ t._header or false, t._footer or false }) do
                if bar then
                    local barSettings = settingsOf(bar)
                    for _, c in ipairs({ bar:GetChildren() }) do
                        local label = c:IsShown() and labelOf(c, barSettings)
                        if label then add(t, label, path, nil, c) end
                    end
                end
            end
        end
    end
    return found
end

-- Every word is in the name, its card's or its page's: names where each starts a word, then names holding them all,
-- then places with a word only their card or page has. A word may sit inside another, as Chinese writes no spaces.
local function match(ctx, text)
    local words = {}
    for w in fold(text):gmatch("%S+") do words[#words + 1] = w end
    local tiers = { {}, {}, {} }
    for _, m in ipairs(gather(ctx)) do
        local own, all = fold(m.text), fold(m.path .. " " .. m.text)
        local starts = " " .. own:gsub("%p", " ")
        local tier = 1
        for _, w in ipairs(words) do
            if not all:find(w, 1, true) then tier = nil break end
            if not own:find(w, 1, true) then
                tier = 3
            elseif tier == 1 and not starts:find(" " .. w, 1, true) then
                tier = 2
            end
        end
        if tier then
            local list = tiers[tier]
            list[#list + 1] = m
        end
    end
    local out = tiers[1]
    for i = 2, 3 do
        for _, m in ipairs(tiers[i]) do out[#out + 1] = m end
    end
    return out
end

local function flash(ctx, frame)
    local tex = frame._euiFlash
    if not tex then
        tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        local r, g, b = ctx:Color("accent")
        tex:SetColorTexture(r, g, b, FLASH_ALPHA)
        frame._euiFlash = tex
    end
    local driver = ctx._flashDriver
    if not driver then
        driver = CreateFrame("Frame", nil, ctx._window)
        driver:Hide()
        driver:SetScript("OnUpdate", function(d, elapsed)
            d.t = d.t + elapsed
            local a = 1
            if d.t > FLASH_HOLD then a = 1 - (d.t - FLASH_HOLD) / FLASH_FADE end
            if a <= 0 then
                d.tex:Hide()
                d:Hide()
                return
            end
            d.tex:SetAlpha(a)
        end)
        ctx._flashDriver = driver
    end
    if driver.tex and driver.tex ~= tex then driver.tex:Hide() end
    driver.tex, driver.t = tex, 0
    tex:SetAlpha(1)
    tex:Show()
    driver:Show()
end

local function jump(ctx, m)
    local t = tabById(ctx, m.tab)
    local group = t and t.parent and tabById(ctx, t.parent)
    if group then group._collapsed = nil end
    ctx:SelectTab(m.tab)
    if m.scroll then ctx:ScrollIntoView(m.scroll) end
    flash(ctx, m.flash)
end

-- Every page is built the first time a search runs, since a page is otherwise built only when first opened.
-- None is refreshed: a refresh can do real work, such as asking each provider for its entries.
local function showResults(ctx, text)
    local results = ctx._results
    if not results:IsShown() then
        for _, t in ipairs(ctx._tabs or {}) do
            if not t.group then fillPage(ctx, t) end
        end
        local current = tabById(ctx, ctx._current)
        if current and current._holder then
            current._holder:Hide()
            if current._footer then current._footer:Hide() end
        end
        results:Show()
        ctx._window.section:SetText(ctx.opts.labels.searchTitle)
    end
    local matches = match(ctx, text)
    ctx._matches = matches
    local rows = {}
    for i, m in ipairs(matches) do rows[i] = { key = i, text = m.text, value = m.path } end
    results.list:SetRows(rows)
    results.list:ScrollToRow(1)
    results.empty:SetShown(#rows == 0)
end

local function searchChanged(ctx, text)
    if text ~= "" then
        showResults(ctx, text)
    elseif ctx._results:IsShown() then
        ctx:SelectTab(ctx._current)
    end
end

local function buildResults(ctx, area)
    local sp = lib.tokens.spacing
    local results = CreateFrame("Frame", nil, area)
    results:SetAllPoints()
    results:Hide()
    ctx._matches = {}
    local list = ctx:CreateList(results, function(key)
        local m = ctx._matches[key]
        if m then jump(ctx, m) end
    end)
    list:SetPoint("TOPLEFT", sp.contentSides, -sp.contentTop)
    list:SetPoint("BOTTOMRIGHT", -sp.contentSides, 0)
    results.list = list
    results.empty = ctx:CreateEmptyState(results, ctx.opts.labels.searchEmpty)
    ctx._results = results
end

local function buildHeader(ctx, f)
    local opts = ctx.opts
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(lib.tokens.spacing.headerHeight)
    kit.Fill(ctx, header, "chrome")
    kit.Edge(ctx, header, "divider", "B")

    local square = header:CreateTexture(nil, "ARTWORK")
    square:SetSize(ACCENT_SQUARE, ACCENT_SQUARE)
    square:SetPoint("LEFT", HEADER_PADDING, 0)
    square:SetColorTexture(ctx:Color("accent"))

    local title = kit.Text(ctx, header, "title")
    title:SetPoint("LEFT", square, "RIGHT", ICON_GAP, 0)
    title:SetText(opts.title)

    local slash = kit.Text(ctx, header, "nav", "muted")
    slash:SetPoint("LEFT", title, "RIGHT", 8, 0)
    slash:SetText("/")

    local section = kit.Text(ctx, header, "nav", "muted")
    section:SetPoint("LEFT", slash, "RIGHT", 8, 0)
    f.section = section

    local close = CreateFrame("Button", nil, header)
    close:SetSize(CLOSE_SIZE, CLOSE_SIZE)
    close:SetPoint("RIGHT", -SIDEBAR_PADDING, 0)
    kit.Highlight(ctx, close)
    local x = kit.Icon(ctx, close, "close", ICON_SIZE, "navText")
    x:SetPoint("CENTER")
    close:SetScript("OnClick", function() f:Hide() end)
    f.close = close

    local version = kit.Text(ctx, header, "hint", "muted")
    version:SetPoint("RIGHT", close, "LEFT", -SIDEBAR_PADDING, 0)
    version:SetText("v" .. opts.version)
end

local function buildSidebar(ctx, f, sidebar)
    local sp = lib.tokens.spacing
    local width = sp.sidebarWidth - SIDEBAR_PADDING * 2
    local searchLabel = ctx.opts.labels.search
    if searchLabel then
        local field = ctx:CreateSearchField(sidebar, searchLabel, function()
            local m = ctx._matches[1]
            if m then jump(ctx, m) end
        end, nil, nil, function(text) searchChanged(ctx, text) end)
        field:SetPoint("TOPLEFT", SIDEBAR_PADDING, -SIDEBAR_TOP)
        field:SetPoint("TOPRIGHT", -SIDEBAR_PADDING, -SIDEBAR_TOP)
        f.search = field
        ctx._navTop = SIDEBAR_TOP + sp.fieldHeight + SEARCH_GAP
    end
    for _, t in ipairs(ctx._tabs or {}) do
        local b = kit.NavItem(ctx, sidebar, width, t.title, not t.parent and t.icon or nil)
        local id = t.id
        b:SetScript("OnClick", function() ctx:SelectTab(id) end)
        t._nav = b
        if t.group then
            local group = t
            -- The group holding the page on screen shuts and opens in place, so the page stays where it is
            b:SetScript("OnClick", function()
                local current = tabById(ctx, ctx._current)
                if current and current.parent == id then
                    group._collapsed = not group._collapsed
                    layoutNav(ctx)
                else
                    ctx:SelectTab(id)
                end
            end)
            local kids = {}
            for _, k in ipairs(ctx._tabs) do
                if k.parent == id then kids[#kids + 1] = k end
            end
            t._kids = kids
            local chevron = kit.Icon(ctx, b, "chevron-right", sp.chevron, "muted")
            chevron:SetPoint("RIGHT", -sp.navItemPadding, 0)
            b.label:SetPoint("RIGHT", chevron, "LEFT", -ICON_GAP, 0)
            b.chevron = chevron
            local guide = kit.Line(ctx, sidebar, "inputBorder", "ARTWORK")
            guide._euiAxis = "v"
            kit.SnapLines({ guide })
            t._guide = guide
        elseif t.parent then
            b:SetHeight(sp.navChildHeight)
            b.label:ClearAllPoints()
            b.label:SetPoint("LEFT", sp.navItemPadding + ICON_SIZE + ICON_GAP, 0)
            b.label:SetPoint("RIGHT", -sp.navItemPadding, 0)
            b.label:SetWordWrap(false)
        end
        paintNav(ctx, t, false)
    end
    layoutNav(ctx)

    local opts = ctx.opts
    if opts.discord then
        local labels = opts.labels
        local d = ctx:CreateButton(sidebar, labels.discord, width, function() opts.discord() end)
        d:SetPoint("BOTTOMLEFT", SIDEBAR_PADDING, SIDEBAR_TOP)
        local icon = kit.Icon(ctx, d, "icon-discord", ICON_SIZE, "navText")
        icon:SetPoint("LEFT", sp.navItemPadding, 0)
        d.text:ClearAllPoints()
        d.text:SetPoint("LEFT", icon, "RIGHT", ICON_GAP, 0)
        d.text:SetPoint("RIGHT", -sp.navItemPadding, 0)
        d.text:SetJustifyH("LEFT")
        kit.TwoLines(d.text)
        -- A label too long for one line (de, fr and ru, 2026-10-05) takes a second, and the button
        -- grows for it upward from its bottom anchor. Measured again on screen, like a fitted button.
        function d.Fit()
            local wrapped = (d.text:GetStringHeight() or 0) > lib.tokens.typography.value.size * 1.5
            d:SetHeight(wrapped and TWO_LINE_BUTTON or sp.buttonHeight)
        end
        d.Fit()
        local fits = sidebar._euiFit or {}
        sidebar._euiFit = fits
        fits[#fits + 1] = d
        ctx:AttachTooltip(d, labels.discordTipTitle, labels.discordTip)
        f.discord = d
    end
end

local function buildPage(ctx, t, area, footer)
    local sp = lib.tokens.spacing
    local width = sp.windowWidth - sp.sidebarWidth - sp.contentSides * 2
    local holder = CreateFrame("Frame", nil, area)
    holder:SetAllPoints()
    holder:Hide()
    -- A tab with a preview gives the panel its right side, so its column is that much narrower.
    local side = t.preview and sp.previewWidth or 0
    -- A header strip stays put above the scrolling column, as the footer does below it.
    local strip = t.header and sp.stripHeight or 0
    local scroll, content, bar = kit.Scroll(ctx, holder)
    scroll:SetPoint("TOPLEFT", sp.contentSides, -(sp.contentTop + strip))
    scroll:SetPoint("BOTTOMRIGHT", -(sp.contentSides + side), 0)
    bar:SetPoint("TOPRIGHT", -(SCROLLBAR_INSET + side), -(sp.contentTop + strip))
    bar:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_INSET + side), SCROLLBAR_BOTTOM)
    content:SetWidth(width - side)
    content._controls = {}
    content._euiColumn = true
    t._holder, t._scroll, t._content = holder, scroll, content
    if t.header then
        local hb = CreateFrame("Frame", nil, holder)
        hb:SetPoint("TOPLEFT")
        hb:SetPoint("TOPRIGHT", -side, 0)
        hb:SetHeight(strip)
        kit.Edge(ctx, hb, "divider", "B")
        hb._controls = {}
        t._header = hb
    end
    if t.preview then
        -- In the tab's holder, so it shows and hides with the tab.
        local panel = CreateFrame("Frame", nil, holder)
        panel:SetPoint("TOPRIGHT")
        panel:SetPoint("BOTTOMRIGHT")
        panel:SetWidth(side)
        kit.Fill(ctx, panel, "chrome")
        kit.Edge(ctx, panel, "divider", "L")
        t._preview = panel
    end
    if t.footer then
        local actions = CreateFrame("Frame", nil, footer)
        actions:SetPoint("TOPLEFT", sp.contentSides, 0)
        actions:SetPoint("BOTTOMRIGHT", -sp.contentSides, 0)
        actions:Hide()
        actions._controls = {}
        t._footer = actions
    end
end

local function buildTabs(ctx, area, footer)
    for _, t in ipairs(ctx._tabs or {}) do
        if not t.group then buildPage(ctx, t, area, footer) end
    end
end

-- Before any frame is made, or a window left half built fails on every later open.
local function checkGroups(ctx, level)
    for _, t in ipairs(ctx._tabs or {}) do
        if t.group then
            local found = false
            for _, k in ipairs(ctx._tabs) do
                if k.parent == t.id then found = true break end
            end
            if not found then error(("EverythingUI: the group %s has no tabs in it"):format(t.id), level + 1) end
        end
    end
end

function Context:BuildSettings(name)
    if self._window then return self._window end
    checkGroups(self, 2)
    local sp = lib.tokens.spacing

    local f = CreateFrame("Frame", name, UIParent)
    self._window = f
    f:SetSize(sp.windowWidth, sp.windowHeight)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    -- Not toplevel, or a click on it would cover Blizzard's color picker, which shares its strata
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    -- This frame persists no position, so a window dragged off screen would stay there for
    -- every later show.
    f:SetClampedToScreen(true)
    f:Hide()
    kit.CloseOnEscape(f)

    -- The tooltip, the dropdown list and the color picker hang off UIParent rather than this
    -- frame, so none goes away on its own and each would be left floating over the game world.
    -- The list and the picker are shared by every family addon, so only one this window opened
    -- is closed.
    local getTip = self.opts.tooltip
    f:HookScript("OnHide", function()
        local tip = getTip()
        if tip then tip:Hide() end
        local list = lib.shared.popup
        if list and list.owner == f then list:Hide() end
        -- Closing the window mid-edit has to CANCEL the picker, not merely hide it. The live
        -- preview writes on every drag frame, so hiding alone commits whatever color the
        -- wheel was last sitting on. Captured before the Hide, which clears it.
        local picker = lib.shared.colorPicker
        if picker and picker.owner == f and ColorPickerFrame and ColorPickerFrame:IsShown() then
            local cancelPending = picker.cancel
            ColorPickerFrame:Hide()
            if cancelPending then cancelPending() end
        end
        if f.search then f.search.box:ClearFocus() end
        local driver = self._flashDriver
        if driver then
            driver:Hide()
            if driver.tex then driver.tex:Hide() end
        end
    end)

    kit.Fill(self, f, "bg")
    kit.Edge(self, f, "inputBorder")
    buildHeader(self, f)

    local sidebar = CreateFrame("Frame", nil, f)
    sidebar:SetPoint("TOPLEFT", 0, -sp.headerHeight)
    sidebar:SetPoint("BOTTOMLEFT")
    sidebar:SetWidth(sp.sidebarWidth)
    kit.Fill(self, sidebar, "chrome")
    kit.Edge(self, sidebar, "divider", "R")
    f.sidebar = sidebar

    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", sp.sidebarWidth, 0)
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(sp.footerHeight)
    kit.Fill(self, footer, "chrome")
    kit.Edge(self, footer, "divider", "T")
    f.footer = footer

    local area = CreateFrame("Frame", nil, f)
    area:SetPoint("TOPLEFT", sp.sidebarWidth, -sp.headerHeight)
    area:SetPoint("BOTTOMRIGHT", 0, sp.footerHeight)
    f.area = area

    buildSidebar(self, f, sidebar)
    buildTabs(self, area, footer)
    if f.search then buildResults(self, area) end

    local first
    for _, t in ipairs(self._tabs or {}) do
        if not t.parent then first = t break end
    end
    local get = self.opts.getLastTab
    local want = (get and get()) or (first and first.id)
    self:SelectTab(tabById(self, want) and want or (first and first.id))
    return f
end

-- Run once the tab is on screen: its content is sized again and measured (MeasureContent), and so
-- are its footer, its header strip and the sidebar, a frame later.
local function settle(ctx, t)
    ctx:MeasureContent(t._content)
    local footer, header = t._footer, t._header
    local sidebar = ctx._window and ctx._window.sidebar
    C_Timer.After(0, function()
        if footer then kit.Refit(footer) end
        if header then kit.Refit(header) end
        if sidebar then kit.Refit(sidebar) end
    end)
end

local function refreshIn(frame)
    for _, c in ipairs(frame and frame._controls or {}) do
        if c.Refresh then c:Refresh() end
    end
end

-- Each page has a strip and a footer of its own, so a setting changed from another page's copy is read again.
local function refreshControls(t)
    refreshIn(t._content)
    refreshIn(t._header)
    refreshIn(t._footer)
end

local function showPage(ctx, f, t)
    fillPage(ctx, t)
    if t.refresh then t.refresh(ctx, t._content) end
    refreshControls(t)
    if t._preview then
        if not t._previewBuilt then
            t.preview(ctx, t._preview)
            t._previewBuilt = true
        end
        if t.previewRefresh then t.previewRefresh(ctx, t._preview) end
    end
    t._holder:Show()
    if t._footer then t._footer:Show() end
    local group = t.parent and tabById(ctx, t.parent)
    f.section:SetText(group and (group.title .. " / " .. t.title) or t.title)
    settle(ctx, t)
    return group
end

function Context:SelectTab(id)
    local f = self._window
    if not f then return end
    -- Any page shown ends a search, and the results go before the text so clearing it reopens nothing.
    if self._results then self._results:Hide() end
    if f.search and f.search.box:GetText() ~= "" then f.search:SetText("") end
    local asked = tabById(self, id)
    if asked and asked.group then id = asked._last or asked._kids[1].id end
    local was = self._current
    local group
    for _, t in ipairs(self._tabs or {}) do
        if not t.group then
            local isSel = (t.id == id)
            paintNav(self, t, isSel)
            if isSel then
                group = showPage(self, f, t)
            else
                t._holder:Hide()
                if t._footer then t._footer:Hide() end
            end
        end
    end
    if group then
        group._last = id
        -- Another of its pages opens a shut group, and the page shown again by a strip or a footer leaves it shut
        if id ~= was then group._collapsed = nil end
    end
    for _, t in ipairs(self._tabs or {}) do
        if t.group then paintNav(self, t, t == group) end
    end
    local set = self.opts.setLastTab
    if set then set(id) end
    self._current = id
    layoutNav(self)
end

-- The UIParent-units idiom a tracker uses does not apply here: this frame persists no
-- position, so there is nothing stored to be in the wrong units.
function Context:ApplyWindowScale()
    local f = self._window
    if not f then return end
    local get = self.opts.getWindowScale
    local s = get and get()
    if type(s) ~= "number" or s <= 0 then s = 1 end

    -- The window is a fixed size. On a default 768-unit UIParent anything past about 1.06
    -- pushes the close button off the top edge, and since this re-applies on every open the
    -- broken state would survive closing the window.
    local sp = lib.tokens.spacing
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local wasCapped = false
    if uw and uh and uw > 0 and uh > 0 then
        local capped = math.min(s, uw / sp.windowWidth, uh / sp.windowHeight)
        -- Written back, or the slider goes on reporting a number the window never had: at a
        -- 768-unit UIParent every step from about 1.07 up rendered identically while the
        -- readout still said 1.40. The ceiling moves with the player's UI Scale.
        local set = self.opts.setWindowScale
        if capped < s and set then
            set(capped)
            wasCapped = true
        end
        s = capped
    end

    -- SetScale re-reads the anchor offsets in the new scale, so a dragged window jumps
    -- unless its center is restored.
    local cx, cy = f:GetCenter()
    local oldEff = f:GetEffectiveScale()
    f:SetScale(s)
    if cx and cy and oldEff then
        local newEff = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * oldEff / newEff, cy * oldEff / newEff)
    end
    kit.SnapAll(self)
    -- A scale changed from inside the open window leaves the tab on screen sized at the old one.
    if f:IsShown() then
        for _, t in ipairs(self._tabs or {}) do
            if t.id == self._current and t._built then
                -- The scale slider on screen still reads the number that was capped until it is read again.
                if wasCapped then refreshControls(t) end
                settle(self, t)
            end
        end
    end
end

function Context:ToggleSettings()
    if not self._window then checkGroups(self, 2) end
    local f = self:BuildSettings()
    if f:IsShown() then
        f:Hide()
    else
        self:ApplyWindowScale()
        self:SelectTab(self._current)
        f:Show()
        -- Over a main window, which is toplevel and may have come forward since
        f:Raise()
    end
end
