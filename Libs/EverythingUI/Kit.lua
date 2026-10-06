local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

-- Internal building blocks shared by the component files. Replaced whole by each winning copy,
-- together with every method that uses them.
local kit = {}
lib.kit = kit

-- State every family addon shares for the session: the dropdown popup and its row pool, the
-- color picker hook and its alpha calibration, and the context menu. Created once and kept by
-- every later copy.
lib.shared = lib.shared or {}

local SCROLLBAR_WIDTH = 6
local WHEEL_STEP = 48
local MIN_THUMB = 24
-- Tooltip titles stay gold (decision 8). Every other piece of text in the panel is themed.
local TOOLTIP_TITLE = { 0.92, 0.72, 0.02 }
local TIP_GAP = 4
local NAV_ICON = 16
local NAV_ICON_GAP = 10

function kit.Pixel(frame)
    local scale = frame:GetEffectiveScale()
    if PixelUtil and PixelUtil.GetNearestPixelSize then
        return PixelUtil.GetNearestPixelSize(1, scale, 1)
    end
    if GetPhysicalScreenSize and scale and scale > 0 then
        local _, h = GetPhysicalScreenSize()
        if h and h > 0 then return 768 / h / scale end
    end
    return 1
end

local function snapLine(line)
    local px = kit.Pixel(line._euiOwner)
    if line._euiAxis == "h" then line:SetHeight(px) else line:SetWidth(px) end
end

local function register(ctx, line)
    local lines = ctx._lines
    if not lines then lines = {} ctx._lines = lines end
    lines[#lines + 1] = line
end

-- A 1 px edge on any of a frame's four sides ("T", "B", "L", "R"). Registered on the context
-- so ApplyWindowScale can re-snap it: a line sized for one scale blurs or vanishes at another.
-- Returns the lines, in the order of sides.
function kit.Edge(ctx, frame, color, sides, layer)
    local r, g, b, a = ctx:Color(color)
    local made = {}
    sides = sides or "TBLR"
    for i = 1, #sides do
        local side = sides:sub(i, i)
        local t = frame:CreateTexture(nil, layer or "BORDER")
        t:SetColorTexture(r, g, b, a)
        if side == "T" then
            t:SetPoint("TOPLEFT") t:SetPoint("TOPRIGHT")
        elseif side == "B" then
            t:SetPoint("BOTTOMLEFT") t:SetPoint("BOTTOMRIGHT")
        elseif side == "L" then
            t:SetPoint("TOPLEFT") t:SetPoint("BOTTOMLEFT")
        else
            t:SetPoint("TOPRIGHT") t:SetPoint("BOTTOMRIGHT")
        end
        t._euiOwner = frame
        t._euiAxis = (side == "T" or side == "B") and "h" or "w"
        snapLine(t)
        register(ctx, t)
        made[#made + 1] = t
    end
    return made
end

-- A free 1 px horizontal line on a frame, anchored by the caller.
function kit.Line(ctx, frame, color, layer)
    local t = frame:CreateTexture(nil, layer or "BORDER")
    t:SetColorTexture(ctx:Color(color))
    t._euiOwner = frame
    t._euiAxis = "h"
    snapLine(t)
    register(ctx, t)
    return t
end

function kit.SnapAll(ctx)
    for _, line in ipairs(ctx._lines or {}) do snapLine(line) end
end

function kit.SnapLines(lines)
    for _, line in ipairs(lines) do snapLine(line) end
end

-- Just above the control, centered over the tab's column it sits in. Beside a full-width row it
-- covered whatever sits past the column, the preview panel on a tab that has one. Centered on the
-- column rather than on the control, so a swatch at a row's end opens it over the column too, and
-- an indented row, whose center sits right of the column's, opens it in the same place as the rest.
-- A frame outside a tab's column, such as a footer or sidebar button, is centered on itself. anchor
-- keeps a caller's own placement, as the dropdown list's option tips do.
function kit.ShowTip(getTip, owner, title, body, anchor)
    local tip = getTip()
    if anchor then
        tip:SetOwner(owner, anchor)
    else
        tip:SetOwner(owner, "ANCHOR_NONE")
        tip:ClearAllPoints()
        local column = owner:GetParent()
        local dx = 0
        if column and column._euiColumn then
            local ox, cx = owner:GetCenter(), column:GetCenter()
            -- Measured in the window's scale and offset in the tooltip's, which hangs off UIParent.
            if ox and cx then dx = (cx - ox) * owner:GetEffectiveScale() / tip:GetEffectiveScale() end
        end
        tip:SetPoint("BOTTOM", owner, "TOP", dx, TIP_GAP)
    end
    -- SetText arg 5 is alpha, not wrap - wrap is 6th. Pass 1 or the title is invisible.
    if title then tip:SetText(title, TOOLTIP_TITLE[1], TOOLTIP_TITLE[2], TOOLTIP_TITLE[3], 1, true) end
    if body and body ~= "" then tip:AddLine(body, 0.82, 0.82, 0.82, true) end
    tip:Show()
end

-- Every codepoint past ASCII that all three Barlow faces draw, as inclusive ranges, read from the
-- fonts' own cmap tables. The font files never change, since media file names are API.
local BARLOW = {
    0x00A0, 0x0113, 0x0116, 0x012B, 0x012D, 0x0131, 0x0133, 0x0137, 0x0139, 0x013E, 0x0140, 0x0148,
    0x014A, 0x014D, 0x014F, 0x017E, 0x018F, 0x018F, 0x0192, 0x0192, 0x01A0, 0x01A1, 0x01AF, 0x01B0,
    0x01CD, 0x01CE, 0x01D4, 0x01D4, 0x01E5, 0x01E5, 0x01E7, 0x01E7, 0x01E9, 0x01E9, 0x01EF, 0x01EF,
    0x01FF, 0x01FF, 0x0218, 0x021B, 0x021F, 0x021F, 0x0228, 0x0229, 0x0237, 0x0237, 0x0259, 0x0259,
    0x0292, 0x0292, 0x02BB, 0x02BC, 0x02C6, 0x02C7, 0x02C9, 0x02C9, 0x02D8, 0x02DD, 0x0300, 0x0304,
    0x0306, 0x030C, 0x0312, 0x0313, 0x031B, 0x031B, 0x0323, 0x0323, 0x0326, 0x0328, 0x0335, 0x0338,
    0x0394, 0x0394, 0x03A9, 0x03A9, 0x03BC, 0x03BC, 0x03C0, 0x03C0, 0x1E80, 0x1E85, 0x1EA0, 0x1EF9,
    0x2010, 0x2010, 0x2013, 0x2014, 0x2018, 0x201A, 0x201C, 0x201E, 0x2020, 0x2022, 0x2026, 0x2026,
    0x2030, 0x2030, 0x2032, 0x2033, 0x2039, 0x203A, 0x2044, 0x2044, 0x2074, 0x2079, 0x20A3, 0x20A3,
    0x20AC, 0x20AC, 0x20BA, 0x20BA, 0x20BD, 0x20BD, 0x2113, 0x2113, 0x2122, 0x2122, 0x2126, 0x2126,
    0x212E, 0x212E, 0x215B, 0x215E, 0x2202, 0x2202, 0x2206, 0x2206, 0x220F, 0x220F, 0x2211, 0x2212,
    0x2215, 0x2215, 0x2219, 0x221A, 0x221E, 0x221E, 0x222B, 0x222B, 0x2248, 0x2248, 0x2260, 0x2260,
    0x2264, 0x2265, 0x25CA, 0x25CA, 0x27E9, 0x27E9, 0xFB01, 0xFB02,
}

local function barlowDraws(cp)
    local lo, hi = 1, #BARLOW / 2
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if cp < BARLOW[mid * 2 - 1] then
            hi = mid - 1
        elseif cp > BARLOW[mid * 2] then
            lo = mid + 1
        else
            return true
        end
    end
    return false
end

-- A string holding any character Barlow cannot draw goes to the client's font whole (decision 14).
-- Decided per character: a byte-range test sent an em dash, which Barlow draws, to the client's
-- font. Bytes that are not well-formed UTF-8 go there too, since Barlow would draw nothing.
function kit.NeedsClientFont(s)
    if type(s) ~= "string" then return false end
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        if b < 0x80 then
            i = i + 1
        else
            local len, cp
            if b >= 0xC2 and b <= 0xDF then
                len, cp = 2, b - 0xC0
            elseif b >= 0xE0 and b <= 0xEF then
                len, cp = 3, b - 0xE0
            elseif b >= 0xF0 and b <= 0xF4 then
                len, cp = 4, b - 0xF0
            else
                return true
            end
            for k = 1, len - 1 do
                local c = s:byte(i + k)
                if not c or c < 0x80 or c > 0xBF then return true end
                cp = cp * 64 + (c - 0x80)
            end
            if not barlowDraws(cp) then return true end
            i = i + len
        end
    end
    return false
end

-- Player data such as a profile name can be in any alphabet. The client's font object carries
-- a face for each one, and a SetFont on this string would drop that, so it never gets one.
function kit.DataText(parent, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFontObject(GameFontHighlight)
    fs:SetShadowOffset(0, 0)
    fs:SetJustifyH("LEFT")
    return fs
end

function kit.Fill(ctx, frame, color, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints()
    t:SetColorTexture(ctx:Color(color))
    return t
end

-- A texture on the HIGHLIGHT layer is shown and hidden by the Button itself, so hover needs
-- no script. Without one these read as labels rather than as something clickable.
function kit.Highlight(ctx, frame, color)
    local t = frame:CreateTexture(nil, "HIGHLIGHT")
    t:SetAllPoints()
    t:SetColorTexture(ctx:Color(color or "hover"))
    return t
end

-- A file that fails to load leaves the string with no font at all, and SetFont's return value is
-- only documented for EditBox, so success is read back with GetFont.
function kit.Style(ctx, fs, style, color)
    local file, size, flags = ctx:Font(style)
    fs:SetFont(file, size, flags)
    if not fs:GetFont() then fs:SetFontObject(GameFontHighlight) end
    fs:SetShadowOffset(0, 0)
    fs:SetTextColor(ctx:Color(color or lib.tokens.typography[style].color))
end

function kit.Text(ctx, parent, style, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    kit.Style(ctx, fs, style, color)
    fs:SetJustifyH("LEFT")
    return fs
end

function kit.Icon(ctx, parent, name, size, color)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetSize(size, size)
    t:SetTexture(ctx:Texture(name))
    t:SetVertexColor(ctx:Color(color))
    return t
end

-- One page in a sidebar's list: the settings window's tabs and a main window's pages draw alike. A
-- title that outruns the item breaks onto a second line, which its 36 px fits (frFR, 2026-10-05).
function kit.NavItem(ctx, parent, width, title, icon)
    local sp = lib.tokens.spacing
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, sp.navItemHeight)
    b.active = kit.Fill(ctx, b, "accentSoft")
    b.active:Hide()
    kit.Highlight(ctx, b)
    b.label = kit.Text(ctx, b, "nav")
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(NAV_ICON, NAV_ICON)
        b.icon:SetPoint("LEFT", sp.navItemPadding, 0)
        b.icon:SetTexture(icon)
        b.label:SetPoint("LEFT", b.icon, "RIGHT", NAV_ICON_GAP, 0)
    else
        b.label:SetPoint("LEFT", sp.navItemPadding, 0)
    end
    b.label:SetPoint("RIGHT", -sp.navItemPadding, 0)
    kit.TwoLines(b.label)
    b.label:SetText(title)
    return b
end

function kit.PaintNav(ctx, b, active)
    b.active:SetShown(active)
    kit.Style(ctx, b.label, active and "navActive" or "nav")
    if b.icon then b.icon:SetVertexColor(ctx:Color(active and "accentHi" or "navText")) end
end

-- Wraps at its width onto two lines at most
function kit.TwoLines(fs)
    fs:SetWordWrap(true)
    if fs.SetMaxLines then fs:SetMaxLines(2) end
end

-- Widths read off a string while a tab is built have come out short of the text as drawn (the
-- Tracker tab, 2026-10-02: a button's text and a slider's label ran past their room), and a tab can be
-- built at login, before its window is scaled or shown. So whatever a frame sizes from a string is
-- sized again here, once the tab is on screen: each card's label column, each fitted button, each
-- formatted slider readout, each color picker's width and each column of pickers lined up together.
function kit.Refit(frame)
    for _, card in ipairs(frame._euiCards or {}) do card:Layout() end
    for _, b in ipairs(frame._euiFit or {}) do b:Fit() end
end

-- Escape-to-close WITHOUT UISpecialFrames, and it must stay that way. Blizzard's panel
-- manager walks that list by NAME and does _G[name], so an addon frame in it taints
-- UIParentPanelManager on every single Escape press. That taint reaches the panel manager's own
-- state and from there the panels it owns, the world map among them. The taint log named
-- EQOTOptionsFrame at UIParentPanelManager.lua:1044, which is what this closes. It did NOT cause
-- the 2026-07-30 map pin blocked action - that reproduced with this already fixed - so do not
-- read it as the cause of anything else. The rule stands on the taint vector alone.
-- SetPropagateKeyboardInput is itself protected in combat, so the handler stands down there
-- and Escape just falls through to the default UI.
function kit.CloseOnEscape(frame)
    frame:EnableKeyboard(false)
    local function arm()
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    -- Its own frame, since a menu sets the window's OnEvent
    local wait = CreateFrame("Frame")
    wait:SetScript("OnEvent", function(w)
        w:UnregisterEvent("PLAYER_REGEN_ENABLED")
        arm()
    end)
    frame._euiEscapeWait = wait
    frame:HookScript("OnShow", function()
        -- Deferred rather than dropped, as a dialog's is, or a window shown in combat never took Escape
        if InCombatLockdown() then
            wait:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        arm()
    end)
    frame:HookScript("OnHide", function(f)
        f:EnableKeyboard(false)
        wait:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end)
    frame:SetScript("OnKeyDown", function(f, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            f:SetPropagateKeyboardInput(false)
            f:Hide()
        else
            f:SetPropagateKeyboardInput(true)
        end
    end)
end

-- A plain ScrollFrame with a slim draggable thumb and no arrow buttons. The thumb is the
-- library's own texture, because a Slider takes a texture file on every flavor.
function kit.Scroll(ctx, parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)

    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(SCROLLBAR_WIDTH)
    bar:EnableMouse(true)
    bar:SetThumbTexture(ctx:Texture("slider-thumb"))
    local thumb = bar:GetThumbTexture()
    thumb:SetVertexColor(ctx:Color("borderStrong"))
    thumb:SetSize(SCROLLBAR_WIDTH, MIN_THUMB)
    bar:SetMinMaxValues(0, 0)
    bar:SetValue(0)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(_, v) sf:SetVerticalScroll(v) end)

    sf:SetScript("OnScrollRangeChanged", function(self, _, yrange)
        -- Floored as Blizzard's own scroll frames floor it, so a fraction of a unit is no range at all.
        yrange = math.floor(math.max(0, yrange or 0))
        bar:SetMinMaxValues(0, yrange)
        bar:SetShown(yrange > 0)
        local view, length = self:GetHeight() or 0, bar:GetHeight() or 0
        -- Sized from the bar's own length. The bar is shorter than the view, so a thumb sized
        -- from the view came out longer than its track whenever the range was a few pixels.
        if view > 0 and length > 0 then
            thumb:SetHeight(math.max(MIN_THUMB, length * view / (view + yrange)))
        end
        if bar:GetValue() > yrange then bar:SetValue(yrange) end
    end)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
        local _, max = bar:GetMinMaxValues()
        bar:SetValue(math.min(max, math.max(0, bar:GetValue() - delta * WHEEL_STEP)))
    end)
    return sf, child, bar
end
