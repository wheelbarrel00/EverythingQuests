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

local TAB_FIELDS = {
    id = "string", title = "string", order = "number", build = "function",
    refresh = "function", icon = "string", footer = "function",
    preview = "function", previewRefresh = "function",
}

function Context:RegisterTab(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or type(def.title) ~= "string"
            or type(def.build) ~= "function" then
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
    local tabs = self._tabs
    if not tabs then tabs = {} self._tabs = tabs end
    tabs[#tabs + 1] = def
    table.sort(tabs, function(a, b) return (a.order or 100) < (b.order or 100) end)
end

local function paintNav(ctx, t, active)
    local b = t._nav
    b.active:SetShown(active)
    kit.Style(ctx, b.label, active and "navActive" or "nav")
    if b.icon then b.icon:SetVertexColor(ctx:Color(active and "accentHi" or "navText")) end
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
    local prev
    for _, t in ipairs(ctx._tabs or {}) do
        local b = CreateFrame("Button", nil, sidebar)
        b:SetSize(width, sp.navItemHeight)
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -sp.navItemGap)
        else
            b:SetPoint("TOPLEFT", SIDEBAR_PADDING, -SIDEBAR_TOP)
        end
        b.active = kit.Fill(ctx, b, "accentSoft")
        b.active:Hide()
        kit.Highlight(ctx, b)
        b.label = kit.Text(ctx, b, "nav")
        if t.icon then
            b.icon = b:CreateTexture(nil, "ARTWORK")
            b.icon:SetSize(ICON_SIZE, ICON_SIZE)
            b.icon:SetPoint("LEFT", sp.navItemPadding, 0)
            b.icon:SetTexture(t.icon)
            b.label:SetPoint("LEFT", b.icon, "RIGHT", ICON_GAP, 0)
        else
            b.label:SetPoint("LEFT", sp.navItemPadding, 0)
        end
        b.label:SetPoint("RIGHT", -sp.navItemPadding, 0)
        b.label:SetWordWrap(false)
        b.label:SetText(t.title)
        local id = t.id
        b:SetScript("OnClick", function() ctx:SelectTab(id) end)
        t._nav = b
        paintNav(ctx, t, false)
        prev = b
    end

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
        d.text:SetWordWrap(false)
        ctx:AttachTooltip(d, labels.discordTipTitle, labels.discordTip)
        f.discord = d
    end
end

local function buildTabs(ctx, area, footer)
    local sp = lib.tokens.spacing
    local width = sp.windowWidth - sp.sidebarWidth - sp.contentSides * 2
    for _, t in ipairs(ctx._tabs or {}) do
        local holder = CreateFrame("Frame", nil, area)
        holder:SetAllPoints()
        holder:Hide()
        -- A tab with a preview gives the panel its right side, so its column is that much narrower.
        local side = t.preview and sp.previewWidth or 0
        local scroll, content, bar = kit.Scroll(ctx, holder)
        scroll:SetPoint("TOPLEFT", sp.contentSides, -sp.contentTop)
        scroll:SetPoint("BOTTOMRIGHT", -(sp.contentSides + side), 0)
        bar:SetPoint("TOPRIGHT", -(SCROLLBAR_INSET + side), -sp.contentTop)
        bar:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_INSET + side), SCROLLBAR_BOTTOM)
        content:SetWidth(width - side)
        content._controls = {}
        content._euiColumn = true
        t._holder, t._scroll, t._content = holder, scroll, content
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
            t._footer = actions
        end
    end
end

function Context:BuildSettings(name)
    if self._window then return self._window end
    local sp = lib.tokens.spacing

    local f = CreateFrame("Frame", name, UIParent)
    self._window = f
    f:SetSize(sp.windowWidth, sp.windowHeight)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
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

    local tabs = self._tabs or {}
    local get = self.opts.getLastTab
    local want = (get and get()) or (tabs[1] and tabs[1].id)
    local found = false
    for _, t in ipairs(tabs) do
        if t.id == want then found = true break end
    end
    self:SelectTab(found and want or (tabs[1] and tabs[1].id))
    return f
end

-- Run once the tab is on screen: its content is sized again and measured (MeasureContent), and so
-- is its footer, a frame later.
local function settle(ctx, t)
    ctx:MeasureContent(t._content)
    local footer = t._footer
    if footer then C_Timer.After(0, function() kit.Refit(footer) end) end
end

function Context:SelectTab(id)
    local f = self._window
    if not f then return end
    for _, t in ipairs(self._tabs or {}) do
        local isSel = (t.id == id)
        paintNav(self, t, isSel)
        if isSel then
            if not t._built then
                t._content._controls = {}
                t.build(self, t._content)
                t._built = true
            end
            if t._footer and not t._footerBuilt then
                t.footer(self, t._footer)
                t._footerBuilt = true
            end
            if t.refresh then t.refresh(self, t._content) end
            for _, c in ipairs(t._content._controls or {}) do
                if c.Refresh then c:Refresh() end
            end
            if t._preview then
                if not t._previewBuilt then
                    t.preview(self, t._preview)
                    t._previewBuilt = true
                end
                if t.previewRefresh then t.previewRefresh(self, t._preview) end
            end
            t._holder:Show()
            if t._footer then t._footer:Show() end
            f.section:SetText(t.title)
            settle(self, t)
        else
            t._holder:Hide()
            if t._footer then t._footer:Hide() end
        end
    end
    local set = self.opts.setLastTab
    if set then set(id) end
    self._current = id
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
    if uw and uh and uw > 0 and uh > 0 then
        local capped = math.min(s, uw / sp.windowWidth, uh / sp.windowHeight)
        -- Written back, or the slider goes on reporting a number the window never had: at a
        -- 768-unit UIParent every step from about 1.07 up rendered identically while the
        -- readout still said 1.40. The ceiling moves with the player's UI Scale.
        local set = self.opts.setWindowScale
        if capped < s and set then set(capped) end
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
            if t.id == self._current and t._built then settle(self, t) end
        end
    end
end

function Context:ToggleSettings()
    local f = self:BuildSettings()
    if f:IsShown() then
        f:Hide()
    else
        self:ApplyWindowScale()
        self:SelectTab(self._current)
        f:Show()
    end
end
