local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local INSET = 4
local PAD = 12
local DIVIDER_SLOT = 9
local MIN_WIDTH = 160
local MAX_WIDTH = 320

local ITEM_FIELDS = { kind = "string", text = "string", danger = "boolean", onClick = "function" }
local KINDS = { title = true, divider = true }

-- One menu serves every family addon for the session, as the dropdown list does, so two addons
-- can never have a menu open at once. Kept in lib.shared, so a newer copy finds the same frame.
local function menu(ctx)
    local shared = lib.shared
    if shared.menu then return shared.menu end
    local m = CreateFrame("Frame", nil, UIParent)
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetClampedToScreen(true)
    -- Takes the mouse so a click on its padding or on a title stops here rather than reaching
    -- whatever is under it.
    m:EnableMouse(true)
    m:Hide()
    kit.Fill(ctx, m, "surface")
    m.edges = kit.Edge(ctx, m, "surfaceBorder")
    m.rows = {}
    m.gen = 0
    kit.CloseOnEscape(m)

    -- A click anywhere outside the menu closes it, and that click still lands where it was aimed,
    -- as on Blizzard's own menu. A catcher over the screen took it instead, and in combat, where
    -- Escape stands down, that can be a click meant for an action button or a quest item. Probed
    -- once, because a client that lacks the event raises on it. Hooks rather than sets, so the
    -- Escape handling's own OnShow hook survives.
    if pcall(m.RegisterEvent, m, "GLOBAL_MOUSE_DOWN") then
        m:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        m:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() then self:Hide() end
        end)
        m:HookScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
        m:HookScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    else
        local closer = CreateFrame("Button", nil, UIParent)
        closer:SetAllPoints(UIParent)
        closer:SetFrameStrata("FULLSCREEN")
        closer:RegisterForClicks("AnyDown")
        closer:SetScript("OnClick", function() m:Hide() end)
        closer:Hide()
        m.closer = closer
        m:HookScript("OnShow", function() closer:Show() end)
        m:HookScript("OnHide", function() closer:Hide() end)
    end

    -- Closes once its owner is no longer visible, as Blizzard's own menu does, so a menu opened from
    -- the world map does not outlive the map.
    -- IsVisible can answer a secret value on retail, which addon code may not test, so that owner is left alone.
    m:SetScript("OnUpdate", function(self)
        if not self.owner then return end
        local visible = self.owner:IsVisible()
        if issecretvalue and issecretvalue(visible) then return end
        if not visible then self:Hide() end
    end)

    shared.menu = m
    return m
end

-- The action runs before the hide, the order Blizzard's own menu uses and the one the dialog
-- needs: hidden first, a ReloadUI from its Yes was blocked on retail 12.1. Through xpcall so a
-- raise cannot leave the menu on screen.
local function click(b)
    local m = b:GetParent()
    local gen = m.gen
    if b._onClick then xpcall(b._onClick, geterrorhandler()) end
    -- An action that opened the next menu keeps it up.
    if m.gen == gen then m:Hide() end
end

local function newRow(ctx, m)
    local b = CreateFrame("Button", nil, m)
    kit.Highlight(ctx, b)
    b.text = kit.Text(ctx, b, "label")
    b.data = kit.DataText(b)
    for _, fs in ipairs({ b.text, b.data }) do
        fs:SetPoint("LEFT", PAD, 0)
        fs:SetPoint("RIGHT", -PAD, 0)
        fs:SetWordWrap(false)
    end
    b.line = kit.Line(ctx, b, "divider")
    b.line:SetPoint("LEFT")
    b.line:SetPoint("RIGHT")
    b:SetScript("OnClick", click)
    return b
end

-- Every row is pooled and shared by every addon, so each one is painted whole on every open: a
-- title, a danger item or a divider must leave nothing on the row the next menu gets.
-- A string Barlow cannot draw goes to the second string, which only ever has the client's font.
local function paint(ctx, b, item)
    local kind = item.kind
    b._kind = kind
    b._onClick = item.onClick
    b:SetHeight(kind == "divider" and DIVIDER_SLOT or lib.tokens.spacing.menuItemHeight)
    b:EnableMouse(kind == nil)
    b.line:SetShown(kind == "divider")
    if kind == "divider" then
        b.text:Hide()
        b.data:Hide()
        return
    end
    local color = (kind == "title" and "muted") or (item.danger and "danger") or "text"
    kit.Style(ctx, b.text, kind == "title" and "groupLabel" or "label", color)
    b.data:SetTextColor(ctx:Color(color))
    local useData = kit.NeedsClientFont(item.text)
    b.text:SetText(item.text)
    b.data:SetText(item.text)
    b.text:SetShown(not useData)
    b.data:SetShown(useData)
end

local function layout(m)
    local y, widest = INSET, 0
    for i = 1, m.count do
        local b = m.rows[i]
        b:ClearAllPoints()
        -- One pixel in from each side, so a row's hover tint never paints over the edge.
        b:SetPoint("TOPLEFT", m, "TOPLEFT", 1, -y)
        b:SetPoint("TOPRIGHT", m, "TOPRIGHT", -1, -y)
        y = y + b:GetHeight()
        if b._kind ~= "divider" then
            local fs = b.data:IsShown() and b.data or b.text
            local w = fs:GetStringWidth() or 0
            if w > widest then widest = w end
        end
    end
    m:SetHeight(y + INSET)
    m:SetWidth(math.min(MAX_WIDTH, math.max(MIN_WIDTH, widest + PAD * 2 + 2)))
end

-- A context menu at the cursor. items is a list of { kind, text, danger, onClick }: kind is nil
-- for an item, "title" or "divider". An item with no onClick only closes the menu.
function Context:ShowMenu(items, owner)
    if type(items) ~= "table" or #items == 0 then
        error("EverythingUI: ShowMenu needs a list of items", 2)
    end
    if owner ~= nil and not (type(owner) == "table" and type(owner.IsVisible) == "function") then
        error("EverythingUI: ShowMenu's owner must be a frame", 2)
    end
    for i = 1, #items do
        local item = items[i]
        if type(item) ~= "table" then
            error(("EverythingUI: ShowMenu item %d is not a table"):format(i), 2)
        end
        for key, v in pairs(item) do
            if ITEM_FIELDS[key] ~= type(v) then
                error(("EverythingUI: ShowMenu item %d has a bad or unknown field %s"):format(i, tostring(key)), 2)
            end
        end
        if item.kind and not KINDS[item.kind] then
            error(("EverythingUI: ShowMenu item %d has an unknown kind %s"):format(i, item.kind), 2)
        end
        if item.kind ~= "divider" and not item.text then
            error(("EverythingUI: ShowMenu item %d needs text"):format(i), 2)
        end
    end

    local m = menu(self)
    m.gen = m.gen + 1
    m.owner = owner
    for i = 1, #items do
        local b = m.rows[i]
        if not b then
            b = newRow(self, m)
            m.rows[i] = b
        end
        paint(self, b, items[i])
        b:Show()
    end
    for i = #items + 1, #m.rows do m.rows[i]:Hide() end
    m.count = #items

    -- At UIParent's scale, as Blizzard's menu opens, whatever the scale of the frame clicked.
    -- Re-snapped on every open, because the UI scale can change between two.
    kit.SnapLines(m.edges)
    for i = 1, #items do kit.SnapLines({ m.rows[i].line }) end
    layout(m)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, y / scale)

    -- Tooltips draw on a strata above the menu, so the tip of the row clicked would sit over it.
    local tip = self.opts.tooltip()
    if tip then tip:Hide() end
    m:Show()
    m:Raise()
    -- Text measured while a tab was built has come out short of the text as drawn, so the menu is
    -- sized again a frame later, once it is on screen.
    C_Timer.After(0, function() if m:IsShown() then layout(m) end end)
end
