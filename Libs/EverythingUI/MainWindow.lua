local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local HEADER_PADDING = 16
local BUTTON_INSET = 8
local BUTTON_GAP = 2
local BUTTON_SIZE = 32
local ACCENT_SQUARE = 10
local TITLE_GAP = 10
local SECTION_GAP = 8
local GRIP_SIZE = 16
local GRIP_INSET = 2
local GRIP_LEVEL = 20
local SCREEN_MARGIN = 30
local SCROLLBAR_WIDTH = 6
local SCROLLBAR_INSET = 2
local MIN_THUMB = 24
local WHEEL_STEP = 48
local PAN_THRESHOLD = 5

local WINDOW_FIELDS = {
    name = "string", title = "string", width = "number", height = "number",
    minWidth = "number", minHeight = "number", sidebarWidth = "number",
    getSize = "function", setSize = "function",
    getMaximized = "function", setMaximized = "function",
    onResize = "function", gripTip = "string",
}

local function checkSpec(spec)
    if type(spec) ~= "table" or type(spec.title) ~= "string" then
        error("EverythingUI: CreateWindow needs a title", 3)
    end
    for key, v in pairs(spec) do
        if WINDOW_FIELDS[key] ~= type(v) then
            error(("EverythingUI: CreateWindow got a bad or unknown field %s"):format(tostring(key)), 3)
        end
    end
    for _, pair in ipairs({ { "getSize", "setSize" }, { "getMaximized", "setMaximized" }, { "minWidth", "minHeight" } }) do
        if (spec[pair[1]] == nil) ~= (spec[pair[2]] == nil) then
            error(("EverythingUI: CreateWindow's %s and %s come as a pair"):format(pair[1], pair[2]), 3)
        end
    end
end

-- The host's saved size, read in full: `spec.getSize and spec.getSize()` would keep only the width.
local function savedSize(spec)
    local w, h
    if spec.getSize then w, h = spec.getSize() end
    return w, h
end

local function clampSize(spec, w, h)
    if type(w) ~= "number" or w <= 0 then w = spec.width end
    if type(h) ~= "number" or h <= 0 then h = spec.height end
    return math.max(w, spec.minWidth or 0), math.max(h, spec.minHeight or 0)
end

-- The screen in the window's own units, since the window carries a scale of its own.
local function fitScreen(spec, f)
    local s = f:GetScale() or 1
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER")
    f:SetSize(math.max(UIParent:GetWidth() / s - SCREEN_MARGIN * 2, spec.minWidth or 0),
              math.max(UIParent:GetHeight() / s - SCREEN_MARGIN * 2, spec.minHeight or 0))
end

-- Cut to the screen, since the settings window was seen at a high scale to lose its header off the top edge.
local function fitNormal(spec, f)
    local scale = f:GetScale() or 1
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    if not (uw and uh and uw > 0 and uh > 0) then return end
    -- From the host's saved size when it keeps one, so a lower scale gives back what a higher one cut.
    local w, h
    if spec.getSize then w, h = clampSize(spec, savedSize(spec)) else w, h = f:GetWidth(), f:GetHeight() end
    local fw = math.max(math.min(w, uw / scale), spec.minWidth or 0)
    local fh = math.max(math.min(h, uh / scale), spec.minHeight or 0)
    if fw ~= f:GetWidth() or fh ~= f:GetHeight() then f:SetSize(fw, fh) end
end

local function fit(spec, f)
    if f._euiMaximized then fitScreen(spec, f) else fitNormal(spec, f) end
end

local function buildHeader(ctx, f, spec)
    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(lib.tokens.spacing.headerHeight)
    kit.Fill(ctx, header, "chrome")
    kit.Edge(ctx, header, "divider", "B")
    -- Dragged by its header, so a drag inside the window, such as panning a scroll area, never moves it.
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() if not f._euiMaximized then f:StartMoving() end end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local square = header:CreateTexture(nil, "ARTWORK")
    square:SetSize(ACCENT_SQUARE, ACCENT_SQUARE)
    square:SetPoint("LEFT", HEADER_PADDING, 0)
    square:SetColorTexture(ctx:Color("accent"))

    local title = kit.Text(ctx, header, "title")
    title:SetPoint("LEFT", square, "RIGHT", TITLE_GAP, 0)
    title:SetWordWrap(false)
    title:SetText(spec.title)
    f.title = title

    local slash = kit.Text(ctx, header, "nav", "muted")
    slash:SetPoint("LEFT", title, "RIGHT", SECTION_GAP, 0)
    slash:SetText("/")
    slash:Hide()
    f.slash = slash

    local section = kit.Text(ctx, header, "nav", "muted")
    section:SetPoint("LEFT", slash, "RIGHT", SECTION_GAP, 0)
    section:SetWordWrap(false)
    f.section = section

    local close = ctx:CreateIconButton(header, "close", BUTTON_SIZE)
    close:SetPoint("RIGHT", -BUTTON_INSET, 0)
    close:SetScript("OnClick", function() f:Hide() end)
    f.closeButton = close
    f.header = header
    f._euiHeaderButtons = { close }
end

local function placeHeaderButtons(f)
    local prev
    for _, b in ipairs(f._euiHeaderButtons) do
        b:ClearAllPoints()
        if prev then
            b:SetPoint("RIGHT", prev, "LEFT", -BUTTON_GAP, 0)
        else
            b:SetPoint("RIGHT", f.header, "RIGHT", -BUTTON_INSET, 0)
        end
        prev = b
    end
    -- The section name gives way to the buttons rather than running under them.
    f.section:SetPoint("RIGHT", prev, "LEFT", -SECTION_GAP, 0)
end

local function placeBody(f, spec)
    local top = lib.tokens.spacing.headerHeight
    local side = (f.sidebar and f.sidebar:IsShown()) and spec.sidebarWidth or 0
    f.body:ClearAllPoints()
    f.body:SetPoint("TOPLEFT", f, "TOPLEFT", side, -top)
    f.body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
end

local function setMaximized(ctx, f, spec, on, quiet)
    on = on and true or false
    if f._euiMaximized == on and not quiet then return end
    f._euiMaximized = on
    if f.maxButton then f.maxButton:GetNormalTexture():SetTexture(ctx:Texture(on and "restore" or "maximize")) end
    if on then
        local point, rel, relPoint, x, y = f:GetPoint(1)
        f._euiRestorePoint = point and { point, rel, relPoint, x, y } or nil
        fitScreen(spec, f)
    elseif not quiet then
        local w, h = clampSize(spec, savedSize(spec))
        f:SetSize(w, h)
        fitNormal(spec, f)
        f:ClearAllPoints()
        local p = f._euiRestorePoint
        if p then f:SetPoint(p[1], p[2], p[3], p[4], p[5]) else f:SetPoint("CENTER") end
        f._euiRestorePoint = nil
    end
    if spec.setMaximized and not quiet then spec.setMaximized(on) end
    if spec.onResize and not quiet then spec.onResize(f) end
end

local function buildGrip(ctx, f, spec)
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -GRIP_INSET, GRIP_INSET)
    grip:SetFrameLevel((f:GetFrameLevel() or 0) + GRIP_LEVEL)
    grip:SetNormalTexture(ctx:Texture("grip"))
    grip:GetNormalTexture():SetVertexColor(ctx:Color("muted"))
    kit.Highlight(ctx, grip)
    local fromW, fromH
    grip:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" then return end
        fromW, fromH = f:GetWidth(), f:GetHeight()
        f:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        if button ~= "LeftButton" or not fromW then return end
        f:StopMovingOrSizing()
        local w, h = f:GetWidth(), f:GetHeight()
        local startW, startH = fromW, fromH
        fromW, fromH = nil, nil
        -- A press that barely moves is a click, which saves nothing and leaves a maximized window
        -- maximized, so a size cut to fit the screen never becomes the player's.
        if math.abs(w - startW) < PAN_THRESHOLD and math.abs(h - startH) < PAN_THRESHOLD then
            if f._euiMaximized then fitScreen(spec, f) else f:SetSize(startW, startH) end
            return
        end
        -- Dragging the grip of a maximized window resizes it from where it stood, and the size let go of
        -- becomes its normal size.
        if f._euiMaximized then
            f._euiRestorePoint = nil
            setMaximized(ctx, f, spec, false, true)
            if spec.setMaximized then spec.setMaximized(false) end
        end
        if spec.setSize then spec.setSize(f:GetWidth(), f:GetHeight()) end
        if spec.onResize then spec.onResize(f) end
    end)
    if spec.gripTip then ctx:AttachTooltip(grip, nil, spec.gripTip) end
    f.grip = grip
end

-- A main window, such as a guide or a browser: the settings window's header, an optional sidebar and
-- a body, resizable and maximizable when the host asks.
function Context:CreateWindow(spec)
    checkSpec(spec)
    local sp = lib.tokens.spacing
    local ctx = self
    local s = {}
    for k, v in pairs(spec) do s[k] = v end
    s.width = s.width or sp.windowWidth
    s.height = s.height or sp.windowHeight
    spec = s

    local f = CreateFrame("Frame", spec.name, UIParent)
    f:SetSize(clampSize(spec, savedSize(spec)))
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    -- A click brings it in front of the other windows that share its strata
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f._euiWindow = true
    f._euiMaximized = false
    kit.CloseOnEscape(f)

    -- The tooltip and the dropdown list hang off UIParent, so neither goes away with the window.
    local getTip = self.opts.tooltip
    f:HookScript("OnHide", function()
        local tip = getTip()
        if tip then tip:Hide() end
        local list = lib.shared.popup
        if list and list.owner == f then list:Hide() end
    end)

    kit.Fill(self, f, "bg")
    kit.Edge(self, f, "inputBorder")
    buildHeader(self, f, spec)

    if spec.sidebarWidth then
        local sidebar = CreateFrame("Frame", nil, f)
        sidebar:SetPoint("TOPLEFT", 0, -sp.headerHeight)
        sidebar:SetPoint("BOTTOMLEFT")
        sidebar:SetWidth(spec.sidebarWidth)
        kit.Fill(self, sidebar, "chrome")
        kit.Edge(self, sidebar, "divider", "R")
        sidebar._controls = {}
        f.sidebar = sidebar
    end

    f.body = CreateFrame("Frame", nil, f)
    f.body._controls = {}
    placeBody(f, spec)

    if spec.getMaximized then
        local mx = self:CreateIconButton(f.header, "maximize", BUTTON_SIZE)
        mx:SetScript("OnClick", function() setMaximized(ctx, f, spec, not f._euiMaximized) end)
        f.maxButton = mx
        table.insert(f._euiHeaderButtons, mx)
    end
    placeHeaderButtons(f)

    if spec.minWidth then
        f:SetResizable(true)
        if f.SetResizeBounds then
            f:SetResizeBounds(spec.minWidth, spec.minHeight)
        elseif f.SetMinResize then
            f:SetMinResize(spec.minWidth, spec.minHeight)
        end
        buildGrip(self, f, spec)
    end

    function f.SetSection(_, text)
        f.section:SetText(text or "")
        f.slash:SetShown(text ~= nil and text ~= "")
    end

    -- Placed right to left, before the window's own buttons.
    function f.AddHeaderButton(_, icon, title, body, onClick)
        local b = ctx:CreateIconButton(f.header, icon, BUTTON_SIZE)
        if onClick then b:SetScript("OnClick", onClick) end
        if title or body then ctx:AttachTooltip(b, title, body) end
        table.insert(f._euiHeaderButtons, b)
        placeHeaderButtons(f)
        return b
    end

    function f.SetSidebarShown(_, on)
        if not f.sidebar then return end
        f.sidebar:SetShown(on and true or false)
        placeBody(f, spec)
    end

    function f.IsSidebarShown() return f.sidebar ~= nil and f.sidebar:IsShown() == true end
    function f.SetMaximized(_, on) setMaximized(ctx, f, spec, on) end
    function f.IsMaximized() return f._euiMaximized == true end

    -- Run by the host after a scale or screen change. A maximized window fills the screen again, and
    -- any other is cut to fit it.
    function f.Refit()
        fit(spec, f)
        kit.SnapAll(ctx)
    end

    if spec.getMaximized and spec.getMaximized() then setMaximized(ctx, f, spec, true, true) end
    f:HookScript("OnShow", function() fit(spec, f) end)
    return f
end

local function newBar(ctx, parent, orientation)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation(orientation)
    if orientation == "VERTICAL" then bar:SetWidth(SCROLLBAR_WIDTH) else bar:SetHeight(SCROLLBAR_WIDTH) end
    bar:EnableMouse(true)
    bar:SetThumbTexture(ctx:Texture("slider-thumb"))
    local thumb = bar:GetThumbTexture()
    thumb:SetVertexColor(ctx:Color("borderStrong"))
    thumb:SetSize(SCROLLBAR_WIDTH, SCROLLBAR_WIDTH)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()
    return bar, thumb
end

local function sizeThumb(bar, thumb, view, range, vertical)
    local length = vertical and (bar:GetHeight() or 0) or (bar:GetWidth() or 0)
    if view > 0 and length > 0 then
        local t = math.max(MIN_THUMB, length * view / (view + range))
        if vertical then thumb:SetHeight(t) else thumb:SetWidth(t) end
    end
end

local function cursor(frame)
    local scale = frame:GetEffectiveScale()
    if not scale or scale == 0 then return nil end
    local x, y = GetCursorPosition()
    return x / scale, y / scale
end

-- A view that scrolls both ways with slim bars, the mouse wheel (Shift for sideways), and, with
-- opts.pan, a left-button drag anywhere on its content. opts.clearGrip is for an area placed in the
-- bottom-right corner of a resizable window. A frame placed on the content can still
-- start a drag when it passes its clicks through (SetPropagateMouseClicks), and its own click then
-- asks IsPanGesture whether the press was a drag rather than a click.
function Context:CreateScrollArea(parent, opts)
    opts = opts or {}
    if type(opts) ~= "table" then error("EverythingUI: CreateScrollArea's opts must be a table", 2) end
    local ctx = self
    local area = CreateFrame("Frame", nil, parent)
    local sf = CreateFrame("ScrollFrame", nil, area)
    sf:SetPoint("TOPLEFT")
    sf:SetPoint("BOTTOMRIGHT", -(SCROLLBAR_WIDTH + SCROLLBAR_INSET * 2), SCROLLBAR_WIDTH + SCROLLBAR_INSET * 2)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(1, 1)
    sf:SetScrollChild(content)
    content._area = area
    area.scroll, area.content = sf, content

    -- In a window's corner the bars end short of its grip, or a press on their last pixels resizes the window
    local corner = opts.clearGrip and (GRIP_SIZE + GRIP_INSET + SCROLLBAR_INSET) or (SCROLLBAR_WIDTH + SCROLLBAR_INSET * 2)
    local vbar, vthumb = newBar(ctx, area, "VERTICAL")
    vbar:SetPoint("TOPRIGHT", -SCROLLBAR_INSET, 0)
    vbar:SetPoint("BOTTOMRIGHT", -SCROLLBAR_INSET, corner)
    local hbar, hthumb = newBar(ctx, area, "HORIZONTAL")
    hbar:SetPoint("BOTTOMLEFT", 0, SCROLLBAR_INSET)
    hbar:SetPoint("BOTTOMRIGHT", -corner, SCROLLBAR_INSET)
    area.vbar, area.hbar = vbar, hbar

    vbar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)
    hbar:SetScript("OnValueChanged", function(_, v) sf:SetHorizontalScroll(v) end)

    sf:SetScript("OnScrollRangeChanged", function(frame, xrange, yrange)
        -- Floored as Blizzard's own scroll frames floor it, so a fraction of a unit is no range at all.
        xrange, yrange = math.floor(math.max(0, xrange or 0)), math.floor(math.max(0, yrange or 0))
        vbar:SetMinMaxValues(0, yrange)
        hbar:SetMinMaxValues(0, xrange)
        vbar:SetShown(yrange > 0)
        hbar:SetShown(xrange > 0)
        sizeThumb(vbar, vthumb, frame:GetHeight() or 0, yrange, true)
        sizeThumb(hbar, hthumb, frame:GetWidth() or 0, xrange, false)
        if vbar:GetValue() > yrange then vbar:SetValue(yrange) end
        if hbar:GetValue() > xrange then hbar:SetValue(xrange) end
    end)

    function area.SetContentSize(_, w, h)
        content:SetSize(math.max(1, w or 1), math.max(1, h or 1))
        if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
    end

    -- Clamped to the range, so a target past the far edge lands on it.
    function area.ScrollTo(_, x, y)
        if sf.UpdateScrollChildRect then sf:UpdateScrollChildRect() end
        if x then hbar:SetValue(math.min(sf:GetHorizontalScrollRange() or 0, math.max(0, x))) end
        if y then vbar:SetValue(math.min(sf:GetVerticalScrollRange() or 0, math.max(0, y))) end
    end

    function area.GetScrollOffset() return sf:GetHorizontalScroll() or 0, sf:GetVerticalScroll() or 0 end

    -- Pulls back an offset that a wider view or a smaller content left past the new edge.
    function area.ClampScroll()
        local x, y = sf:GetHorizontalScroll() or 0, sf:GetVerticalScroll() or 0
        area:ScrollTo(x, y)
    end

    content:EnableMouseWheel(true)
    content:SetScript("OnMouseWheel", function(_, delta)
        local step = opts.wheelStep or WHEEL_STEP
        if IsShiftKeyDown() then
            area:ScrollTo((sf:GetHorizontalScroll() or 0) - delta * step, nil)
        else
            area:ScrollTo(nil, (sf:GetVerticalScroll() or 0) - delta * step)
        end
    end)

    local pan = {}
    area._pan = pan
    local function stopPan()
        pan.active = false
        content:SetScript("OnUpdate", nil)
        SetCursor(nil)
    end
    local function onUpdate()
        -- The button can be let go of off the frame, so the live button state is what ends a drag.
        if not IsMouseButtonDown("LeftButton") then stopPan() return end
        local x, y = cursor(content)
        if not x then return end
        local dx, dy = x - pan.lastX, y - pan.lastY
        pan.lastX, pan.lastY = x, y
        if not pan.moved then
            local tx, ty = x - pan.startX, y - pan.startY
            if tx * tx + ty * ty > PAN_THRESHOLD * PAN_THRESHOLD then
                pan.moved = true
                local tip = ctx.opts.tooltip()
                if tip then tip:Hide() end
            end
        end
        -- Scroll offsets grow downward while screen coordinates grow upward, hence the opposite signs.
        area:ScrollTo((sf:GetHorizontalScroll() or 0) - dx, (sf:GetVerticalScroll() or 0) + dy)
    end
    if opts.pan then
        content:EnableMouse(true)
        content:SetScript("OnMouseDown", function(_, button)
            if button ~= "LeftButton" then return end
            if (sf:GetHorizontalScrollRange() or 0) < 1 and (sf:GetVerticalScrollRange() or 0) < 1 then return end
            local x, y = cursor(content)
            if not x then return end
            pan.startX, pan.startY, pan.lastX, pan.lastY = x, y, x, y
            pan.moved, pan.active = false, true
            content:SetScript("OnUpdate", onUpdate)
            SetCursor("UI_MOVE_CURSOR")
        end)
        content:SetScript("OnMouseUp", function() if pan.active then stopPan() end end)
        content:SetScript("OnHide", function() if pan.active then stopPan() end end)
    end

    -- A click arrives between the press and the release, and the drag's own update may not have run
    -- in between, so the distance travelled is read again here.
    function area.IsPanGesture()
        if not pan.active then return false end
        if pan.moved then return true end
        local x, y = cursor(content)
        if not x then return false end
        local tx, ty = x - pan.startX, y - pan.startY
        return tx * tx + ty * ty > PAN_THRESHOLD * PAN_THRESHOLD
    end

    return area
end
