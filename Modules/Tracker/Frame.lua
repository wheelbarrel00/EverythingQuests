local _, ns = ...
local L = ns.L

local Tracker = ns:RegisterSubsystem("Tracker", {})

local CONTENT_PAD      = 4
local SCROLLBAR_GUTTER = 26
local REFRESH_THROTTLE = 0.25
local DRAG_HANDLE_H    = 14
local GRIP_SIZE        = 14

local _popupSet = {}
local _visible  = {}
local _distScratch = {}
local DIST_TICK     = 2
local DIST_MOVE_EPS = 0.0025
local DIST_MAX_AGE  = 5
local SECTION_H        = 26
local HEADER_FONT_DELTA = 4
local WQ_PIN_FRACTION  = 0.40
local MIN_W, MIN_H     = 200, 100
local MAX_W, MAX_H     = 600, 2000

local HEADER_COLOR = { 0.93, 0.32, 0.10 }

-- World Quests is deliberately absent - it renders in its own capped scroll region and is placed by ApplyWorldQuestsPosition.
local REORDERABLE_IDS = { "zoneprogress", "campaign", "quests", "profession", "endeavors", "achievements" }
local REORDERABLE_SET = {}
for _, id in ipairs(REORDERABLE_IDS) do REORDERABLE_SET[id] = true end

-- Appending the reorderable ids missing from the save keeps a newly-added section from vanishing on an old profile.
local function reconcileSectionOrder(saved)
    local seen, out = {}, {}
    if type(saved) == "table" then
        for _, id in ipairs(saved) do
            if REORDERABLE_SET[id] and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    for _, id in ipairs(REORDERABLE_IDS) do
        if not seen[id] then out[#out + 1] = id end
    end
    return out
end

local function getHeaderColor()
    local DB = ns:GetSubsystem("DB")
    local t = DB and DB.db.profile.tracker
    if t and t.headerColorUseClass and ns.Util and ns.Util.GetPlayerClassColor then
        local r, g, b = ns.Util.GetPlayerClassColor()
        if r then return r, g, b end
    end
    if t and t.headerColor then
        local c = t.headerColor
        return c.r or HEADER_COLOR[1], c.g or HEADER_COLOR[2], c.b or HEADER_COLOR[3]
    end
    return HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3]
end

-- Card mode floors the gap - at the default spacing of 2 adjacent card borders touch and read as one block.
local CARD_MIN_GAP = 4

-- With the scroll bar hidden its gutter is dead space, so mirror the left inset to keep the column centred.
local function scrollGutter()
    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    if cfg and cfg.hideScrollBar == true then return CONTENT_PAD * 2 end
    return SCROLLBAR_GUTTER
end

local function getBlockGap()
    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db.profile.tracker
    local gap = (t and t.blockSpacing) or 4
    if t and t.blockLayout == "card" then return math.max(gap, CARD_MIN_GAP) end
    return gap
end

local function disableBlizzardTracker()
    if not ObjectiveTrackerFrame then return end
    ObjectiveTrackerFrame:UnregisterAllEvents()
    ObjectiveTrackerFrame:Hide()
    if not Tracker._hookedBlizz then
        ObjectiveTrackerFrame:HookScript("OnShow", function(f) f:Hide() end)
        Tracker._hookedBlizz = true
    end
end

function Tracker:_ApplyPosition(anchor, relativePoint, xOffset, yOffset)
    local f = self.frame
    if not f then return end
    f:ClearAllPoints()
    f:SetPoint(anchor or "CENTER", UIParent, relativePoint or anchor or "CENTER",
               xOffset or 0, yOffset or 0)
end

function Tracker:PersistPositionAndSize()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB.db.profile.tracker
    local f = self.frame
    if not f then return end

    cfg.width     = math.floor(f:GetWidth())
    cfg.maxHeight = math.floor(f:GetHeight())

    local point, _, relativePoint, x, y = f:GetPoint()
    if not point then return end

    cfg.anchor        = point
    cfg.relativePoint = relativePoint or point
    cfg.xOffset       = math.floor((x or 0) + 0.5)
    cfg.yOffset       = math.floor((y or 0) + 0.5)

    self:_ApplyPosition(cfg.anchor, cfg.relativePoint, cfg.xOffset, cfg.yOffset)
end

function Tracker:ApplyLockState()
    local f = self.frame
    if not (f and f.grip) then return end
    if InCombatLockdown() then
        local Ev = ns:GetSubsystem("Events")
        if Ev then
            self._applyLockDeferred = self._applyLockDeferred
                or function() self:ApplyLockState() end
            Ev:RunWhenOutOfCombat("trackerApplyLock", self._applyLockDeferred)
        end
        return
    end
    local DB = ns:GetSubsystem("DB")
    local locked = DB and DB.db and DB.db.profile.general
                   and DB.db.profile.general.lockTracker
    if locked and f._eqDragging then
        f:StopMovingOrSizing()
        f._eqDragging = nil
    end
    f.grip:SetAlpha(locked and 0 or 1)
    f.grip:EnableMouse(not locked)
end

function Tracker:BuildFrame()
    local DB = ns:GetSubsystem("DB")
    local cfg = DB.db.profile.tracker

    local f = CreateFrame("Frame", "EQTrackerFrame", UIParent)
    f:SetSize(cfg.width, cfg.maxHeight)
    f:SetScale(cfg.scale)
    self.frame = f
    self:_ApplyPosition(cfg.anchor, cfg.relativePoint or cfg.anchor,
                        cfg.xOffset, cfg.yOffset)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    end
    f:SetClampedToScreen(true)

    local bgFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bgFrame:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    bgFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    bgFrame:SetHeight(cfg.maxHeight)
    bgFrame:SetFrameLevel(math.max(0, f:GetFrameLevel() - 1))
    f.bgFrame = bgFrame

    f.background = bgFrame:CreateTexture(nil, "BACKGROUND")
    f.background:SetAllPoints()
    f.background:Hide()

    f._borderSize = math.max(1, cfg.borderSize or 1)
    bgFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = f._borderSize })
    bgFrame:SetBackdropColor(0, 0, 0, 0)
    bgFrame:SetBackdropBorderColor(0, 0, 0, 0)

    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT")
    drag:SetHeight(DRAG_HANDLE_H)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    local dragHint = drag:CreateTexture(nil, "OVERLAY")
    dragHint:SetAllPoints()
    dragHint:SetColorTexture(1, 1, 1, 0)
    drag:SetScript("OnEnter", function()
        dragHint:SetColorTexture(1, 1, 1, 0.15)
        local DBs = ns:GetSubsystem("DB")
        local locked = DBs and DBs.db.profile.general and DBs.db.profile.general.lockTracker
        GameTooltip:SetOwner(drag, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Everything Quests", 0.92, 0.72, 0.02)
        if locked then
            GameTooltip:AddLine(L["Tracker locked"], 1, 0.3, 0.3)
            GameTooltip:AddLine(L["Move and resize are off. Uncheck \"Lock tracker\" in /eqs > General."], 0.8, 0.8, 0.8, true)
        else
            GameTooltip:AddLine(L["Drag to move the tracker"], 1, 1, 1)
            GameTooltip:AddLine(L["/eqs for options"], 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    drag:SetScript("OnLeave", function()
        dragHint:SetColorTexture(1, 1, 1, 0)
        GameTooltip:Hide()
    end)
    local function stopDrag()
        if not f._eqDragging then return end
        if InCombatLockdown() then
            local Ev = ns:GetSubsystem("Events")
            if Ev then Ev:RunWhenOutOfCombat("trackerStopDrag", stopDrag) end
            return
        end
        f._eqDragging = nil
        f:StopMovingOrSizing()
        self:PersistPositionAndSize()
    end

    drag:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        local DBs = ns:GetSubsystem("DB")
        if DBs and DBs.db.profile.general and DBs.db.profile.general.lockTracker then return end
        f:StartMoving()
        f._eqDragging = true
    end)
    drag:SetScript("OnDragStop", stopDrag)

    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    for i, len in ipairs({ 12, 8, 4 }) do
        local g = grip:CreateTexture(nil, "OVERLAY")
        g:SetColorTexture(1, 1, 1, 0.5)
        g:SetSize(len, 1)
        g:SetPoint("BOTTOMRIGHT", -2, 2 + (i - 1) * 3)
    end
    grip:SetScript("OnMouseDown", function()
        if InCombatLockdown() then return end
        local DBs = ns:GetSubsystem("DB")
        if DBs and DBs.db.profile.general and DBs.db.profile.general.lockTracker then return end
        f:StartSizing("BOTTOMRIGHT")
        f._eqDragging = true
    end)
    grip:SetScript("OnMouseUp", stopDrag)

    local scenarioContainer = CreateFrame("Frame", nil, f)
    scenarioContainer:SetPoint("TOPLEFT",  CONTENT_PAD, -DRAG_HANDLE_H)
    -- Reserve the quest list's scroll-bar gutter so the banner aligns with the scrolled quest text.
    scenarioContainer:SetPoint("TOPRIGHT", -(SCROLLBAR_GUTTER - CONTENT_PAD), -DRAG_HANDLE_H)
    scenarioContainer:SetHeight(1)
    f.scenarioContainer = scenarioContainer
    scenarioContainer:SetScript("OnSizeChanged", function() self:Refresh() end)

    local eventsRegion = CreateFrame("Frame", "EQTrackerEventsRegion", f)
    eventsRegion:SetHeight(1)
    eventsRegion:Hide()
    f.eventsRegion = eventsRegion

    local eventsScroll = CreateFrame("ScrollFrame", "EQTrackerEventsScroll", eventsRegion, "UIPanelScrollFrameTemplate")
    eventsScroll:SetPoint("TOPLEFT",     eventsRegion, "TOPLEFT",  0, -(SECTION_H + 2))
    eventsScroll:SetPoint("BOTTOMRIGHT", eventsRegion, "BOTTOMRIGHT", 0, 0)
    local eventsContent = CreateFrame("Frame", nil, eventsScroll)
    eventsContent:SetSize(cfg.width - SCROLLBAR_GUTTER, 1)
    eventsScroll:SetScrollChild(eventsContent)
    f.eventsScroll  = eventsScroll
    f.eventsContent = eventsContent

    local eBg = f:CreateTexture(nil, "BORDER")
    local eBar = eventsScroll.ScrollBar or eventsScroll.scrollBar
    if eBar then
        eBg:SetPoint("TOPLEFT",     eBar, "TOPLEFT",    -1, 0)
        eBg:SetPoint("BOTTOMRIGHT", eBar, "BOTTOMRIGHT", 1, 0)
    else
        eBg:SetPoint("TOPLEFT",     eventsScroll, "TOPRIGHT",    0, 1)
        eBg:SetPoint("BOTTOMRIGHT", eventsRegion, "BOTTOMRIGHT", -2, 0)
    end
    eBg:Hide()
    f.eventsScrollBarBG = eBg

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    -- scroll and eventsRegion are anchored by ApplyWorldQuestsPosition per the Top/Bottom setting - do not hard-anchor them here.

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(cfg.width - SCROLLBAR_GUTTER, 1)
    scroll:SetScrollChild(content)

    f:SetScript("OnSizeChanged", function() self:Refresh() end)

    local sbBG = f:CreateTexture(nil, "BORDER")
    local sBar = scroll.ScrollBar or scroll.scrollBar
    if sBar then
        sbBG:SetPoint("TOPLEFT",     sBar, "TOPLEFT",    -1, 0)
        sbBG:SetPoint("BOTTOMRIGHT", sBar, "BOTTOMRIGHT", 1, 0)
    else
        sbBG:SetPoint("TOPLEFT",     scroll,  "TOPRIGHT",    0, 1)
        sbBG:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", -2, GRIP_SIZE + 2)
    end
    sbBG:Hide()
    f.scrollBarBG = sbBG

    f.scroll = scroll
    f.content = content

    self:ApplyWorldQuestsPosition()

    local WHEEL_STEP = 24
    local function wheelScroll(sf, delta)
        local range = sf:GetVerticalScrollRange() or 0
        if range <= 0 then return end
        local new = (sf:GetVerticalScroll() or 0) - delta * WHEEL_STEP
        if new < 0 then new = 0 elseif new > range then new = range end
        sf:SetVerticalScroll(new)
    end
    for _, sf in ipairs({ scroll, eventsScroll }) do
        sf:EnableMouseWheel(true)
        sf:SetScript("OnMouseWheel", wheelScroll)
    end

    f.drag    = drag
    f.grip    = grip

    local ICON_SZ = 13
    local function makeHeaderIcon(texture, tip, onClick)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(ICON_SZ, ICON_SZ)
        b:SetFrameLevel(f:GetFrameLevel() + 10)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture(texture)
        t:SetTexCoord(0, 1, 0, 1)
        t:SetAlpha(0.85)
        b:SetScript("OnEnter", function(self2)
            t:SetAlpha(1)
            GameTooltip:SetOwner(self2, "ANCHOR_BOTTOMLEFT")
            GameTooltip:AddLine(tip)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function()
            t:SetAlpha(0.85)
            GameTooltip:Hide()
        end)
        b:SetScript("OnClick", onClick)
        return b
    end
    local cogBtn = makeHeaderIcon("Interface\\AddOns\\EverythingQuests\\Media\\cogwheel.tga", L["Open the options panel"], function()
        local O = ns:GetSubsystem("Options"); if O then O:Toggle() end
    end)
    cogBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -1)
    cogBtn._dbKey = "showOptionsIcon"
    local guideBtn = makeHeaderIcon("Interface\\AddOns\\EverythingQuests\\Media\\chain.tga", L["Open the Chain Guide"], function()
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Toggle() end
    end)
    guideBtn:SetPoint("RIGHT", cogBtn, "LEFT", -3, 0)
    guideBtn._dbKey = "showChainGuideIcon"
    f.headerIcons = { cogBtn, guideBtn }

    self.frame = f

    self:ApplyLockState()

    self:BuildSectionHeaders(content)
    self:ApplyHeaderIcons()
end

function Tracker:ApplyHeaderIcons()
    local f = self.frame
    if not (f and f.headerIcons) then return end
    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    for i = 1, #f.headerIcons do
        local b = f.headerIcons[i]
        if cfg and b._dbKey and cfg[b._dbKey] == false then b:Hide() else b:Show() end
    end
end

local HAIRLINE_ALPHA  = 0.85
local HAIRLINE_HEIGHT = 2
local function buildHairline(parent)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.92, 0.72, 0.02, HAIRLINE_ALPHA)
    line:SetHeight(HAIRLINE_HEIGHT)
    line:SetPoint("BOTTOMLEFT", 0, 0)
    line:SetPoint("BOTTOMRIGHT", 0, 0)
    return line
end

local function scaleCollapse(fs, extra)
    if not fs then return end
    if not fs._baseFont then
        local file, sz, fl = fs:GetFont()
        if file then fs._baseFont = { file, sz, fl } end
    end
    local base = fs._baseFont
    if base then fs:SetFont(base[1], math.max(6, base[2] + extra), base[3] or "") end
end

local function makeSectionHeader(parent, id, title, onToggle)
    local h = CreateFrame("Button", nil, parent)
    h:SetHeight(SECTION_H)
    h:RegisterForClicks("LeftButtonUp")

    -- White base so ApplyHeaderBar can tint it, and BACKGROUND keeps it under the hairline and the label.
    h.bar = h:CreateTexture(nil, "BACKGROUND")
    h.bar:SetColorTexture(1, 1, 1, 1)
    h.bar:SetPoint("LEFT",  h, "LEFT",  0, 0)
    h.bar:SetPoint("RIGHT", h, "RIGHT", 0, 0)
    h.bar:Hide()

    -- The mask affects the bar's alpha only, so the gradient survives it.
    if h.CreateMaskTexture then
        h.barMask = h:CreateMaskTexture(nil, "BACKGROUND")
        h.barMask:SetTexture("Interface\\AddOns\\EverythingQuests\\Media\\Textures\\headerbar-softmask.tga",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        h.barMask:SetAllPoints(h.bar)
    end

    h.hairline = buildHairline(h)

    h.text = h:CreateFontString(nil, "OVERLAY", "ObjectiveTrackerHeaderFont")
    if not h.text:GetFont() then h.text:SetFontObject("GameFontNormalLarge") end
    h.text:SetPoint("LEFT", 4, 0)
    h.text:SetText(title)
    h.text:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.collapse = h:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    h.collapse:SetPoint("RIGHT", -4, 0)
    h.collapse:SetTextColor(HEADER_COLOR[1], HEADER_COLOR[2], HEADER_COLOR[3])

    h.count = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    h.count:SetPoint("RIGHT", h.collapse, "LEFT", -6, 0)
    h.count:SetTextColor(0.92, 0.72, 0.02)

    h:SetScript("OnClick", onToggle)
    h.sectionID = id
    return h
end

function Tracker:BuildSectionHeaders(content)
    self.sectionFrames = {}

    local titles = {
        zoneprogress = L["Zone"],
        campaign     = L["Campaign"],
        quests       = L["Quests"],
        profession   = L["Profession"],
        endeavors    = L["Endeavors"],
        achievements = L["Achievements"],
        events       = L["World Quests"],
    }
    self._sectionTitles = titles

    for _, sid in ipairs({ "zoneprogress", "campaign", "quests", "profession", "endeavors", "achievements", "events" }) do
        local h = makeSectionHeader(content, sid, titles[sid], function()
            self:ToggleSectionCollapsed(sid)
        end)
        self.sectionFrames[sid] = h
    end

    self:ApplySectionOrder()

    local eh = self.sectionFrames["events"]
    if eh and self.frame and self.frame.eventsRegion then
        eh:SetParent(self.frame.eventsRegion)
        eh:ClearAllPoints()
        eh:SetPoint("TOPLEFT",  self.frame.eventsRegion, "TOPLEFT",  0, 0)
        eh:SetPoint("TOPRIGHT", self.frame.eventsRegion, "TOPRIGHT", 0, 0)
    end

    self:ApplyHeaderBars()
    self:ApplyHeaderDividers()
end

function Tracker:GetInContentOrder()
    local DB = ns:GetSubsystem("DB")
    local saved = DB and DB.db.profile.tracker and DB.db.profile.tracker.sectionOrder
    return reconcileSectionOrder(saved)
end

function Tracker:ApplySectionOrder()
    local titles = self._sectionTitles or {}
    local list = {}
    for _, id in ipairs(self:GetInContentOrder()) do
        list[#list + 1] = { id = id, title = titles[id] }
    end
    -- World Quests stays in the list so its header still builds, but the render loop skips it and its region is anchored separately.
    list[#list + 1] = { id = "events", title = titles["events"] }
    self.sectionList = list
end

function Tracker:MoveSection(id, delta)
    local order = self:GetInContentOrder()
    local idx
    for i = 1, #order do
        if order[i] == id then idx = i; break end
    end
    if not idx then return end
    local j = idx + delta
    if j < 1 or j > #order then return end
    order[idx], order[j] = order[j], order[idx]
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.tracker then DB.db.profile.tracker.sectionOrder = order end
    self:ApplySectionOrder()
    self:Refresh()
end

-- Guard on the last gutter - SetPoint fires scenarioContainer's OnSizeChanged, which calls Refresh, so an unguarded re-inset re-enters every pass.
function Tracker:ApplyContentInset()
    local f = self.frame
    if not (f and f.scenarioContainer) then return end
    local gutter = scrollGutter()
    if f._contentGutter == gutter then return end
    f._contentGutter = gutter
    f.scenarioContainer:SetPoint("TOPLEFT",  CONTENT_PAD, -DRAG_HANDLE_H)
    f.scenarioContainer:SetPoint("TOPRIGHT", -(gutter - CONTENT_PAD), -DRAG_HANDLE_H)
end

function Tracker:ApplyWorldQuestsPosition()
    local f = self.frame
    if not f then return end
    local scroll = f.scroll
    local region = f.eventsRegion
    local scen   = f.scenarioContainer
    if not (scroll and region and scen) then return end

    -- scroll is in the item-button protected ancestor chain, so re-anchoring it in combat is a protected move.
    local IB = ns:GetSubsystem("TrackerItemButtons")
    if InCombatLockdown() and IB and IB.HasSecureButtons and IB:HasSecureButtons() then
        local Ev = ns:GetSubsystem("Events")
        if Ev and Ev.RunWhenOutOfCombat then
            self._applyWQPos = self._applyWQPos or function() self:ApplyWorldQuestsPosition() end
            Ev:RunWhenOutOfCombat("trackerApplyWQPos", self._applyWQPos)
        end
        return
    end

    local DB  = ns:GetSubsystem("DB")
    local pos = (DB and DB.db.profile.tracker and DB.db.profile.tracker.worldQuestsPosition) or "bottom"

    scroll:ClearAllPoints()
    region:ClearAllPoints()
    if pos == "top" then
        region:SetPoint("TOPLEFT",  scen,   "BOTTOMLEFT",  0, -2)
        region:SetPoint("TOPRIGHT", scen,   "BOTTOMRIGHT", 0, -2)
        scroll:SetPoint("TOPLEFT",  region, "BOTTOMLEFT",  0, -2)
    else
        scroll:SetPoint("TOPLEFT",  scen,   "BOTTOMLEFT",  0, -2)
        region:SetPoint("TOPLEFT",  scroll, "BOTTOMLEFT",  0, -2)
        region:SetPoint("TOPRIGHT", scroll, "BOTTOMRIGHT", 0, -2)
    end
end

function Tracker:SetWorldQuestsPosition(pos)
    local DB = ns:GetSubsystem("DB")
    if DB and DB.db.profile.tracker then DB.db.profile.tracker.worldQuestsPosition = pos end
    self:ApplyWorldQuestsPosition()
    self:Refresh()
end

-- The bar is a child of the header and tracks it, so this only runs on build and on option changes, never per-render.
function Tracker:ApplyHeaderBar(h)
    if not (h and h.bar) then return end
    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    if not (cfg and cfg.headerBar) then
        h.bar:Hide()
        return
    end
    local c = cfg.headerBarColor or { r = 0.80, g = 0.60, b = 0.20, a = 0.85 }
    local r, g, b, a = c.r or 0.80, c.g or 0.60, c.b or 0.20, c.a or 0.85
    h.bar:SetHeight(cfg.headerBarHeight or 22)
    if h.bar.SetGradient then
        -- SetGradient VERTICAL takes min=bottom then max=top, so the darker shade goes first. Cached ColorMixins keep slider drags from churning GC.
        local k = 0.4
        if h._barC1 then h._barC1:SetRGBA(r, g, b, a) else h._barC1 = CreateColor(r, g, b, a) end
        if h._barC2 then h._barC2:SetRGBA(r * k, g * k, b * k, a) else h._barC2 = CreateColor(r * k, g * k, b * k, a) end
        if (cfg.headerBarStyle or 1) == 2 then
            h.bar:SetGradient("VERTICAL", h._barC2, h._barC1)
        else
            h.bar:SetGradient("HORIZONTAL", h._barC1, h._barC2)
        end
    end
    if h.barMask then
        local wantSoft = cfg.headerBarSoftEdges and true or false
        if wantSoft then
            -- Strength is inverted - lower values oversize the mask so the bar samples its solid interior, and the bottom stays flush so that edge never feathers.
            local s    = cfg.headerBarSoftEdgeStrength or 10
            local extX = 30 * (10 - s) / 9
            local extY = 8  * (10 - s) / 9
            h.barMask:ClearAllPoints()
            h.barMask:SetPoint("TOPLEFT",     h.bar, "TOPLEFT",     -extX,  extY)
            h.barMask:SetPoint("BOTTOMRIGHT", h.bar, "BOTTOMRIGHT",  extX,  0)
            if not h._barMasked then h.bar:AddMaskTexture(h.barMask); h._barMasked = true end
        elseif h._barMasked then
            h.bar:RemoveMaskTexture(h.barMask); h._barMasked = false
        end
    end
    h.bar:Show()
end

function Tracker:ApplyHeaderBars()
    if not self.sectionFrames then return end
    for _, h in pairs(self.sectionFrames) do
        self:ApplyHeaderBar(h)
    end
end

function Tracker:ApplyHeaderDivider(h)
    if not (h and h.hairline) then return end
    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local c   = cfg and cfg.headerDividerColor
    h.hairline:SetColorTexture((c and c.r) or 0.92, (c and c.g) or 0.72,
        (c and c.b) or 0.02, (c and c.a) or HAIRLINE_ALPHA)
end

function Tracker:ApplyHeaderDividers()
    if not self.sectionFrames then return end
    for _, h in pairs(self.sectionFrames) do
        self:ApplyHeaderDivider(h)
    end
end

function Tracker:IsSectionCollapsed(id)
    local DB = ns:GetSubsystem("DB")
    if not DB then return false end
    DB.char.sectionsCollapsed = DB.char.sectionsCollapsed or {}
    if id == "quests" and DB.char.trackerCollapsed ~= nil and DB.char.sectionsCollapsed.quests == nil then
        return DB.char.trackerCollapsed
    end
    return DB.char.sectionsCollapsed[id] == true
end

function Tracker:ToggleSectionCollapsed(id)
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    DB.char.sectionsCollapsed = DB.char.sectionsCollapsed or {}
    DB.char.sectionsCollapsed[id] = not self:IsSectionCollapsed(id)
    if id == "quests" then
        DB.char.trackerCollapsed = DB.char.sectionsCollapsed[id]
    end
    self:Render()
end

function Tracker:Refresh()
    if not self.frame then return end
    local Events = ns:GetSubsystem("Events")
    if not (Events and Events.Debounce) then return end
    local thunk = self._refreshThunk
    if not thunk then
        thunk = function() self:Render() end
        self._refreshThunk = thunk
    end
    Events:Debounce("eq.tracker.refresh", REFRESH_THROTTLE, thunk)
end

function Tracker:DebugSize()
    local f = self.frame
    if not f then print("|cffEBB706EQ TrackerDebug|r: tracker not built.") return end
    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local function h(fr) return fr and math.floor((fr:GetHeight() or 0) + 0.5) or -1 end
    local function shown(fr) return (fr and fr:IsShown()) and "shown" or "hidden" end

    print("|cffEBB706EQ TrackerDebug|r (paste this to share):")
    print(("  frame h=%d w=%d scale=%.2f  cfg.maxHeight=%s  inCombat=%s"):format(
        h(f), math.floor((f:GetWidth() or 0) + 0.5), f:GetScale() or 1,
        tostring(cfg and cfg.maxHeight), tostring(InCombatLockdown())))
    print(("  bgFrame h=%d (%s)  background=%s  showBackground=%s showBorder=%s"):format(
        h(f.bgFrame), shown(f.bgFrame), shown(f.background),
        tostring(cfg and cfg.showBackground), tostring(cfg and cfg.showBorder)))
    print(("  content(questH)=%d  scrollViewport=%d  scenario h=%d (%s)  wqRegion h=%d (%s)"):format(
        h(f.content), h(f.scroll), h(f.scenarioContainer), shown(f.scenarioContainer),
        h(f.eventsRegion), shown(f.eventsRegion)))

    local nWatch = (C_QuestLog and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) or -1
    local nLog = 0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for i = 1, C_QuestLog.GetNumQuestLogEntries() do
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden then nLog = nLog + 1 end
        end
    end
    local Cache, nCache = ns:GetSubsystem("Cache"), 0
    if Cache and Cache.All then for _ in pairs(Cache:All()) do nCache = nCache + 1 end end
    print(("  quests: log=%d  watched=%d  cache=%d  showOnlyWatched=%s  sortMode=%s"):format(
        nLog, nWatch, nCache, tostring(cfg and cfg.showOnlyWatched), tostring(cfg and cfg.sortMode)))

    local nDist = 0
    for _ in pairs(_distScratch) do nDist = nDist + 1 end
    local posMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = posMap and C_Map.GetPlayerMapPosition
                and C_Map.GetPlayerMapPosition(posMap, "player")
    local px, py
    if pos then px, py = pos:GetXY() end
    print(("  distance: api=%s  harvested=%d  map=%s  pos=%s"):format(
        tostring((C_QuestLog and C_QuestLog.GetDistanceSqToQuest) ~= nil), nDist,
        tostring(posMap), (px and py) and ("%.3f, %.3f"):format(px, py) or "nil"))

    local V = ns:GetSubsystem("TrackerVisibility")
    if V and V.DebugState then V:DebugState() end
end

function Tracker:ToggleCollapsed()
    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    DB.char.trackerCollapsed = not DB.char.trackerCollapsed
    self:Render()
end

function Tracker:ToggleHidden(questID)
    if not (questID and C_QuestLog) then return end
    local watched = C_QuestLog.GetQuestWatchType
                    and C_QuestLog.GetQuestWatchType(questID) ~= nil
    if watched and C_QuestLog.RemoveQuestWatch then
        C_QuestLog.RemoveQuestWatch(questID)
    elseif (not watched) and C_QuestLog.AddQuestWatch then
        C_QuestLog.AddQuestWatch(questID, Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual)
    end
end

function Tracker:_RenderQuestGroup(content, contentWidth, yStart, collapsed, wantCampaign)
    local DB      = ns:GetSubsystem("DB")
    local Cache   = ns:GetSubsystem("Cache")
    local Filters = ns:GetSubsystem("TrackerFilters")
    local Sort    = ns:GetSubsystem("TrackerSort")
    local Blocks  = ns:GetSubsystem("TrackerBlocks")
    local AC      = ns:GetSubsystem("TrackerAutoComplete")

    local profile = DB.db.profile.tracker
    local quests  = Cache:All()

    -- Quests with a complete auto-quest popup are drawn as popup boxes, so exclude them here to avoid a duplicate block - but only while popups are enabled.
    wipe(_popupSet)
    if AC and AC.FillCompleteSet and profile.showQuestPopups ~= false then
        AC:FillCompleteSet(_popupSet)
    end

    wipe(_visible)
    local zoneSet = profile.filters.onlyCurrentZone and Filters:CurrentZoneQuests() or nil
    local visible, count, total = _visible, 0, 0
    for questID, q in pairs(quests) do
        if (q.isCampaign and true or false) == wantCampaign and not _popupSet[questID] then
            total = total + 1
            if Filters:Visible(questID, q, nil, zoneSet) then
                count = count + 1
                visible[count] = q
            end
        end
    end

    if collapsed then return 0, count, total end

    table.sort(visible, Sort.For(profile.sortMode, profile.manualOrder))

    local y = yStart
    local gap = getBlockGap()

    for i = 1, count do
        local q = visible[i]
        local b = Blocks:AcquireFor(content, q.questID)
        b:SetWidth(contentWidth)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        Blocks:RenderQuest(b, q, profile.simplifyMode)
        y = y + b:GetHeight() + gap
    end

    return y - yStart, count, total
end

function Tracker:_RenderCampaignSection(content, contentWidth, yStart, collapsed)
    return self:_RenderQuestGroup(content, contentWidth, yStart, collapsed, true)
end

function Tracker:_RenderQuestsSection(content, contentWidth, yStart, collapsed)
    return self:_RenderQuestGroup(content, contentWidth, yStart, collapsed, false)
end

function Tracker:_RenderProfessionSection(content, contentWidth, yStart, collapsed)
    local Profession = ns:GetSubsystem("TrackerProfession")
    if not Profession or not Profession.Render then return 0, 0 end
    return Profession:Render(content, contentWidth, yStart, collapsed)
end

function Tracker:_RenderEndeavorsSection(content, contentWidth, yStart, collapsed)
    local Endeavors = ns:GetSubsystem("TrackerEndeavors")
    if not Endeavors or not Endeavors.Render then return 0, 0 end
    return Endeavors:Render(content, contentWidth, yStart, collapsed)
end

function Tracker:_RenderEventsSection(content, contentWidth, yStart, collapsed)
    local Events = ns:GetSubsystem("TrackerEvents")
    if not Events or not Events.Render then return 0, 0 end
    return Events:Render(content, contentWidth, yStart, collapsed)
end

function Tracker:_RenderZoneProgressSection(content, contentWidth, yStart, collapsed)
    local ZP = ns:GetSubsystem("TrackerZoneProgress")
    if not ZP or not ZP.Render then return 0, 0 end
    return ZP:Render(content, contentWidth, yStart, collapsed)
end

function Tracker:_RenderAchievementsSection(content, contentWidth, yStart, collapsed)
    local Achievements = ns:GetSubsystem("TrackerAchievements")
    if not Achievements or not Achievements.Render then return 0, 0 end
    return Achievements:Render(content, contentWidth, yStart, collapsed)
end

local SECTION_RENDERERS = {
    zoneprogress = "_RenderZoneProgressSection",
    campaign     = "_RenderCampaignSection",
    quests       = "_RenderQuestsSection",
    profession   = "_RenderProfessionSection",
    endeavors    = "_RenderEndeavorsSection",
    achievements = "_RenderAchievementsSection",
    events       = "_RenderEventsSection",
}

local function applyTrackerScale()
    local DB      = ns:GetSubsystem("DB")
    local Tracker = ns:GetSubsystem("Tracker")
    local fr = Tracker and Tracker.frame
    local sc = DB and DB.db.profile.tracker.scale
    if fr and sc and sc > 0 and fr:GetScale() ~= sc and not InCombatLockdown() then
        fr:SetScale(sc)
    end
end

local function setScrollBarHidden(sf, hidden)
    if not sf then return end
    local bar = sf.ScrollBar or sf.scrollBar
    if not bar then return end
    bar._eqHidden = hidden
    if not bar._eqShowHook then
        bar._eqShowHook = true
        bar:HookScript("OnShow", function(b) if b._eqHidden then b:Hide() end end)
    end
    if hidden then
        if bar:IsShown() then bar:Hide() end
    else
        bar:SetShown((sf:GetVerticalScrollRange() or 0) > 0.5)
    end
end

local function scrollArrowButtons(bar)
    local name = bar.GetName and bar:GetName()
    local up = bar.ScrollUpButton or bar.Back
        or (name and _G[name .. "ScrollUpButton"])
    local down = bar.ScrollDownButton or bar.Forward
        or (name and _G[name .. "ScrollDownButton"])
    return up, down
end

local function setArrowHidden(btn, hidden)
    if not btn then return end
    btn._eqArrowHidden = hidden
    if not btn._eqArrowHook then
        btn._eqArrowHook = true
        btn:HookScript("OnShow", function(b) if b._eqArrowHidden then b:Hide() end end)
    end
    if hidden then
        if btn:IsShown() then btn:Hide() end
    else
        if not btn:IsShown() then btn:Show() end
    end
end

local function applyScrollBarSkin(sf, cfg)
    if not (sf and cfg) then return end
    local bar = sf.ScrollBar or sf.scrollBar
    if not bar then return end
    local on = cfg.skinScrollBar == true
    local c  = cfg.scrollBarThumbColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.90 }
    local w  = cfg.scrollBarThumbWidth

    local thumbTex = bar.GetThumbTexture and bar:GetThumbTexture()
    if thumbTex then
        if not bar._eqThumbCaptured then
            bar._eqThumbCaptured = true
            bar._eqThumbAtlas = thumbTex.GetAtlas and thumbTex:GetAtlas() or nil
            bar._eqThumbW     = thumbTex:GetWidth()
        end
        if on then
            thumbTex:SetTexture(nil)
            thumbTex:SetColorTexture(c.r or 0.60, c.g or 0.60, c.b or 0.65, c.a or 0.90)
            if w and w > 0 then thumbTex:SetWidth(w) end
        elseif bar._eqThumbSkinned then
            if bar._eqThumbAtlas then thumbTex:SetAtlas(bar._eqThumbAtlas, true) end
            if bar._eqThumbW and bar._eqThumbW > 0 then thumbTex:SetWidth(bar._eqThumbW) end
        end
        bar._eqThumbSkinned = on
    else
        local tf = bar.Thumb or (bar.Track and bar.Track.Thumb)
        if tf then
            local skin = tf._eqSkinTex
            if on then
                if not skin then
                    skin = tf:CreateTexture(nil, "OVERLAY")
                    skin:SetAllPoints(tf)
                    tf._eqSkinTex = skin
                end
                skin:SetColorTexture(c.r or 0.60, c.g or 0.60, c.b or 0.65, c.a or 0.90)
                skin:Show()
                if w and w > 0 then tf:SetWidth(w) end
            elseif skin then
                skin:Hide()
            end
        end
    end

    local up, down = scrollArrowButtons(bar)
    setArrowHidden(up,   cfg.hideScrollArrows == true)
    setArrowHidden(down, cfg.hideScrollArrows == true)
end

local function samplePlayerPos()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not (mapID and C_Map.GetPlayerMapPosition) then return mapID, nil, nil end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return mapID, nil, nil end
    local x, y = pos:GetXY()
    return mapID, x, y
end

function Tracker:_DistanceMoved(mapID, x, y)
    if mapID ~= self._distMapID then return true end
    if not (x and y) then return false end
    if not (self._distX and self._distY) then return true end
    return math.abs(x - self._distX) > DIST_MOVE_EPS
        or math.abs(y - self._distY) > DIST_MOVE_EPS
end

function Tracker:_UpdateDistanceSort(sortMode)
    local Sort = ns:GetSubsystem("TrackerSort")
    if not Sort then return end
    if sortMode ~= "distance" or not (C_QuestLog and C_QuestLog.GetDistanceSqToQuest) then
        Sort.SetDistances(nil)
        return
    end

    local mapID, px, py = samplePlayerPos()
    local stale = (GetTime() - (self._distStamp or 0)) >= DIST_MAX_AGE
    if self._distHarvested and not stale and not self:_DistanceMoved(mapID, px, py) then
        Sort.SetDistances(_distScratch)
        return
    end

    wipe(_distScratch)
    local Cache = ns:GetSubsystem("Cache")
    if Cache and Cache.All then
        -- Complete quests resolve to their turn-in POI, so skipping them would pin ready-to-turn-in quests to the bottom.
        for id in pairs(Cache:All()) do
            local distSq, onContinent = C_QuestLog.GetDistanceSqToQuest(id)
            if distSq and onContinent and distSq == distSq then
                _distScratch[id] = distSq
            end
        end
    end
    self._distHarvested = true
    self._distStamp     = GetTime()
    self._distMapID, self._distX, self._distY = mapID, px, py
    Sort.SetDistances(_distScratch)
end

function Tracker:_EnsureDistanceTicker(sortMode)
    if sortMode == "distance" then
        if not self._distTicker then
            self._distTicker = C_Timer.NewTicker(DIST_TICK, function()
                local DB = ns:GetSubsystem("DB")
                local mode = DB and DB.db.profile.tracker and DB.db.profile.tracker.sortMode
                if mode ~= "distance" then
                    self:_EnsureDistanceTicker(nil)
                    return
                end
                local f = self.frame
                if not (f and f:IsShown() and f:GetAlpha() > 0) then return end
                if InCombatLockdown and InCombatLockdown() then return end
                local mapID, px, py = samplePlayerPos()
                if self:_DistanceMoved(mapID, px, py) then
                    self:Refresh()
                end
            end)
        end
    elseif self._distTicker then
        self._distTicker:Cancel()
        self._distTicker = nil
    end
end

function Tracker:Render()
    local f = self.frame
    if not f then return end
    local content = f.content
    if not content then return end

    self:ApplyContentInset()

    if f._eqHidden or not f:IsShown() then
        f._pendingRender = true
        return
    end
    f._pendingRender = nil

    local _Blocks = ns:GetSubsystem("TrackerBlocks")
    if _Blocks and _Blocks.BeginRenderPass then _Blocks:BeginRenderPass() end
    local _AQP = ns:GetSubsystem("TrackerAutoQuestPopup")
    if _AQP and _AQP.ReleaseAll then _AQP:ReleaseAll() end

    local DB = ns:GetSubsystem("DB")
    if DB and f.background and f.bgFrame then
        local cfg = DB.db.profile.tracker
        local c = cfg.backgroundColor or { r = 0, g = 0, b = 0, a = 0.6 }
        f.background:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.6)
        local bsz = math.max(1, cfg.borderSize or 1)
        if f._borderSize ~= bsz then
            f._borderSize = bsz
            f.bgFrame:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = bsz })
            f.bgFrame:SetBackdropColor(0, 0, 0, 0)
        end
        if cfg.showBorder then
            local bc = cfg.borderColor or { r = 0.635, g = 0.000, b = 0.039, a = 1 }
            f.bgFrame:SetBackdropBorderColor(bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 1)
        else
            f.bgFrame:SetBackdropBorderColor(0, 0, 0, 0)
        end
        local hideBar = cfg.hideScrollBar == true
        if f.scrollBarBG then
            if cfg.scrollBarBg ~= false and not hideBar then
                local s = cfg.scrollBarBgColor or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
                f.scrollBarBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
                f.scrollBarBG:Show()
            else
                f.scrollBarBG:Hide()
            end
        end
        if cfg.scale and cfg.scale > 0 and f:GetScale() ~= cfg.scale then
            local Ev = ns:GetSubsystem("Events")
            if Ev and Ev.InCombat and Ev:InCombat() then
                Ev:RunWhenOutOfCombat("trackerSetScale", applyTrackerScale)
            else
                f:SetScale(cfg.scale)
            end
        end
    end

    -- Secure-gated - content is in the item button's protected ancestor chain, like the content:SetHeight below.
    local _IBw = ns:GetSubsystem("TrackerItemButtons")
    local _secureW = InCombatLockdown() and _IBw and _IBw.HasSecureButtons and _IBw:HasSecureButtons()
    local liveContentW = math.max(1, math.floor((f:GetWidth() or 0) + 0.5) - scrollGutter())
    if not _secureW and math.floor((content:GetWidth() or 0) + 0.5) ~= liveContentW then
        content:SetWidth(liveContentW)
    end

    local contentWidth = content:GetWidth()
    if contentWidth <= 0 then contentWidth = 280 end

    local hr, hg, hb = getHeaderColor()
    local gap = getBlockGap()
    local headerGap = SECTION_H + math.max(0, 2 + ns.Util.HeaderSpacing())

    local y = 0
    local sectionTops = {}
    local sections = self.sectionList or {}

    do
        local sortMode = self.frame and DB and DB.db.profile.tracker
                         and DB.db.profile.tracker.sortMode
        self:_UpdateDistanceSort(sortMode)
        self:_EnsureDistanceTicker(sortMode)
    end

    local DB = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local sectionVisible = {
        campaign     = true,
        quests       = true,
        endeavors    = true,
        profession   = not cfg or cfg.showProfessionSection   ~= false,
        achievements = not cfg or cfg.showAchievementsSection ~= false,
        events       = not cfg or cfg.showWorldQuestsSection  ~= false,
        zoneprogress = cfg and cfg.showZoneProgressBar == true
                       and (cfg.zoneProgressLocation or "floating") == "tracker",
    }

    local scenarioH = (f.scenarioContainer and f.scenarioContainer:GetHeight()) or 1
    local available = (f:GetHeight() or 0) - DRAG_HANDLE_H - scenarioH - 2 - (GRIP_SIZE + 2)
    if available < 1 then available = 1 end
    local fraction  = (cfg and cfg.worldQuestsPinnedMaxFraction) or WQ_PIN_FRACTION

    for _, def in ipairs(sections) do
      if def.id ~= "events" then
        local headerFrame = self.sectionFrames[def.id]
        if headerFrame and not sectionVisible[def.id] then
            local rendererName = SECTION_RENDERERS[def.id]
            if rendererName and self[rendererName] then
                self[rendererName](self, content, contentWidth, 0, true)
            end
            headerFrame:Hide()
            headerFrame = nil
        end
        if headerFrame then
            local rendererName = SECTION_RENDERERS[def.id]
            local sectionCollapsed = self:IsSectionCollapsed(def.id)

            local probeY = y + headerGap

            local popupH, popupCount = 0, 0
            local AQP = (def.id == "campaign" or def.id == "quests")
                        and ns:GetSubsystem("TrackerAutoQuestPopup") or nil
            if AQP and (not cfg or cfg.showQuestPopups ~= false) then
                local wantCampaign = (def.id == "campaign")
                if sectionCollapsed then
                    popupCount = (AQP.Count and AQP:Count(wantCampaign)) or 0
                else
                    popupH, popupCount = AQP:Render(content, contentWidth, probeY, wantCampaign)
                    popupH     = popupH or 0
                    popupCount = popupCount or 0
                end
            end

            local sectionHeight, sectionCount, sectionTotal = 0, 0, nil
            if rendererName and self[rendererName] then
                sectionHeight, sectionCount, sectionTotal = self[rendererName](self, content, contentWidth, probeY + popupH, sectionCollapsed)
            end
            sectionHeight = sectionHeight + popupH
            sectionCount  = (sectionCount or 0) + popupCount
            if type(sectionTotal) == "number" then
                sectionTotal = sectionTotal + popupCount
            end

            if sectionCount and sectionCount > 0 then
                headerFrame:Show()
                headerFrame:ClearAllPoints()
                headerFrame:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
                headerFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)
                local _M = ns:GetSubsystem("Media")
                if (def.id == "campaign" or def.id == "quests")
                   and type(sectionTotal) == "number"
                   and (not cfg or cfg.showQuestTotal ~= false) then
                    headerFrame.count:SetText(sectionCount .. "/" .. sectionTotal)
                else
                    headerFrame.count:SetText(tostring(sectionCount))
                end
                local headerDelta = (cfg and cfg.headerSizeDelta) or HEADER_FONT_DELTA
                local headerExtra = headerDelta - HEADER_FONT_DELTA
                if _M and _M.ApplyTrackerFont then
                    _M:ApplyTrackerFont(headerFrame.count, -2 + headerExtra)
                end
                headerFrame.count:SetTextColor(hr, hg, hb)
                headerFrame.collapse:SetText(sectionCollapsed and "+" or "–")
                local Media = ns:GetSubsystem("Media")
                if headerFrame.text then
                    if Media and Media.ApplyTrackerFont then
                        Media:ApplyTrackerFont(headerFrame.text, headerDelta)
                    end
                    headerFrame.text:SetTextColor(hr, hg, hb)
                end
                if headerFrame.collapse then
                    scaleCollapse(headerFrame.collapse, headerExtra)
                    headerFrame.collapse:SetTextColor(hr, hg, hb)
                    if Media and Media.ApplyTextShadow then Media:ApplyTextShadow(headerFrame.collapse) end
                end
                if def.id == "zoneprogress" then
                    local ZP = ns:GetSubsystem("TrackerZoneProgress")
                    if ZP and ZP.HeaderInfo then
                        local zname, zcount = ZP:HeaderInfo()
                        if headerFrame.text  then headerFrame.text:SetText(zname or "") end
                        if headerFrame.count then headerFrame.count:SetText(zcount or "") end
                    end
                end
                sectionTops[#sectionTops + 1] = y
                y = y + headerGap + sectionHeight + gap
            else
                headerFrame:Hide()
            end
        end
      end
    end

    local questContentH = y

    -- Quests get vertical-space priority so a trailing section is never left header-without-body, and wqFloor keeps the WQ region from vanishing.
    local eventsCap
    if cfg and cfg.worldQuestsHeightOverride then
        local wqWant   = SECTION_H + 2 + math.max(0, cfg.worldQuestsHeight or 0)
        local questMin = SECTION_H + 2 + 40
        eventsCap = math.max(0, math.min(wqWant, available - questMin))
    else
        local wqFloor    = SECTION_H + 2 + 40
        local questWants = math.min(questContentH, math.max(1, available - wqFloor))
        eventsCap = math.max(0, math.min(math.floor(available * fraction), available - questWants))
    end

    local _IB = ns:GetSubsystem("TrackerItemButtons")
    local secureLocked = InCombatLockdown()
        and _IB and _IB.HasSecureButtons and _IB:HasSecureButtons()
    if secureLocked then
        local Ev = ns:GetSubsystem("Events")
        if Ev and Ev.RunWhenOutOfCombat then
            self._deferredRender = self._deferredRender or function() self:Render() end
            Ev:RunWhenOutOfCombat("trackerDeferredRender", self._deferredRender)
        end
    else
        content:SetHeight(math.max(1, questContentH))
    end

    local wqRegionH = self:_RenderPinnedEvents(eventsCap) or 0

    -- Only snap the clip up when the cut lands inside a header's own row - snapping when a body merely overflows would collapse the viewport to the sections above.
    local scrollH = math.min(questContentH, available - wqRegionH)
    if scrollH < questContentH then
        for i = #sectionTops, 1, -1 do
            local top = sectionTops[i]
            if top > 0 and top < scrollH then
                if scrollH - top < headerGap then scrollH = top end
                break
            end
        end
    end
    if scrollH < 1 then scrollH = 1 end

    if f.scroll and not secureLocked then
        local scrollW = math.max(1, (f:GetWidth() or 0) - scrollGutter())
        f.scroll:SetSize(scrollW, scrollH)
        if f.scroll.UpdateScrollChildRect then f.scroll:UpdateScrollChildRect() end
    end

    do
        local DB2 = ns:GetSubsystem("DB")
        local tcfg = DB2 and DB2.db.profile.tracker
        local hideBar = tcfg and tcfg.hideScrollBar == true
        setScrollBarHidden(f.scroll, hideBar)
        setScrollBarHidden(f.eventsScroll, hideBar)
        if tcfg then
            applyScrollBarSkin(f.scroll, tcfg)
            applyScrollBarSkin(f.eventsScroll, tcfg)
        end
    end

    if _Blocks and _Blocks.Sweep then _Blocks:Sweep() end

    if _IB and _IB.Reposition then _IB:Reposition() end

    if f.bgFrame and cfg then
        local maxH = cfg.maxHeight or f:GetHeight() or 600
        local isEmpty = (questContentH <= 0) and (wqRegionH <= 0) and (scenarioH <= 1)
        if isEmpty then
            f.bgFrame:Hide()
            f.background:Hide()
        else
            -- Span the full dragged frame, not the content, so the bordered window never collapses while the grip sits far below.
            f.bgFrame:SetHeight(f:GetHeight() or maxH)
            if cfg.showBackground then f.background:Show() else f.background:Hide() end
            if cfg.showBackground or cfg.showBorder then f.bgFrame:Show() else f.bgFrame:Hide() end
        end
    end
end

-- In TOP mode the protected quest scroll hangs off this region, so resizing it in combat blocks. BOTTOM mode has nothing protected below and needs no gate.
function Tracker:_SetEventsRegionHeight(region, h)
    local DB  = ns:GetSubsystem("DB")
    local pos = (DB and DB.db.profile.tracker and DB.db.profile.tracker.worldQuestsPosition) or "bottom"
    if pos == "top" then
        local IB = ns:GetSubsystem("TrackerItemButtons")
        if InCombatLockdown() and IB and IB.HasSecureButtons and IB:HasSecureButtons() then
            local Ev = ns:GetSubsystem("Events")
            if Ev and Ev.RunWhenOutOfCombat then
                self._deferredRender = self._deferredRender or function() self:Render() end
                Ev:RunWhenOutOfCombat("trackerDeferredRender", self._deferredRender)
            end
            return
        end
    end
    region:SetHeight(h)
end

function Tracker:_RenderPinnedEvents(eventsCap)
    local f = self.frame
    if not f then return 0 end
    local region   = f.eventsRegion
    local escroll   = f.eventsScroll
    local econtent = f.eventsContent
    local header   = self.sectionFrames and self.sectionFrames["events"]
    if not (region and escroll and econtent) then return 0 end

    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db.profile.tracker
    local sectionOn = not cfg or cfg.showWorldQuestsSection ~= false
    local collapsed = self:IsSectionCollapsed("events")
    local Events    = ns:GetSubsystem("TrackerEvents")

    econtent:SetWidth(math.max(1, escroll:GetWidth()))
    local ewidth = econtent:GetWidth()
    if ewidth <= 0 then ewidth = 280 end

    local function collapseRegion()
        if header then header:Hide() end
        escroll:Hide()
        if f.eventsScrollBarBG then f.eventsScrollBarBG:Hide() end
        self:_SetEventsRegionHeight(region, 1)
        region:Hide()
    end

    if not sectionOn then
        if Events and Events.Render then Events:Render(econtent, ewidth, 0, true) end
        collapseRegion()
        return 0
    end

    local heightUsed, count = 0, 0
    if Events and Events.Render then
        heightUsed, count = Events:Render(econtent, ewidth, 0, collapsed)
    end

    if not count or count == 0 then
        collapseRegion()
        return 0
    end

    region:Show()

    if header then
        header:Show()
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT",  region, "TOPLEFT",  0, 0)
        header:SetPoint("TOPRIGHT", region, "TOPRIGHT", 0, 0)
        header.count:SetText(tostring(count))
        header.collapse:SetText(collapsed and "+" or "–")
        local hr, hg, hb = getHeaderColor()
        local headerDelta = (cfg and cfg.headerSizeDelta) or HEADER_FONT_DELTA
        local headerExtra = headerDelta - HEADER_FONT_DELTA
        local Media = ns:GetSubsystem("Media")
        if header.text then
            if Media and Media.ApplyTrackerFont then
                Media:ApplyTrackerFont(header.text, headerDelta)
            end
            header.text:SetTextColor(hr, hg, hb)
        end
        if header.collapse then
            scaleCollapse(header.collapse, headerExtra)
            header.collapse:SetTextColor(hr, hg, hb)
            if Media and Media.ApplyTextShadow then Media:ApplyTextShadow(header.collapse) end
        end
        if header.count then
            if Media and Media.ApplyTrackerFont then
                Media:ApplyTrackerFont(header.count, -2 + headerExtra)
            end
            header.count:SetTextColor(hr, hg, hb)
        end
    end

    if collapsed then
        escroll:Hide()
        if f.eventsScrollBarBG then f.eventsScrollBarBG:Hide() end
        self:_SetEventsRegionHeight(region, SECTION_H + 2)
        return SECTION_H + 2
    end

    escroll:Show()
    econtent:SetHeight(math.max(1, heightUsed))

    local capViewport = (eventsCap or 0) - (SECTION_H + 2)
    if capViewport < 30 then capViewport = 30 end
    local viewport = math.min(heightUsed, capViewport)
    if viewport < 1 then viewport = 1 end
    self:_SetEventsRegionHeight(region, SECTION_H + 2 + viewport)

    if escroll.UpdateScrollChildRect then escroll:UpdateScrollChildRect() end

    if f.eventsScrollBarBG then
        local needsBar = heightUsed > viewport + 0.5
        if needsBar and (not cfg or (cfg.scrollBarBg ~= false and cfg.hideScrollBar ~= true)) then
            local s = (cfg and cfg.scrollBarBgColor) or { r = 0.60, g = 0.60, b = 0.65, a = 0.25 }
            f.eventsScrollBarBG:SetColorTexture(s.r or 0.60, s.g or 0.60, s.b or 0.65, s.a or 0.25)
            f.eventsScrollBarBG:Show()
        else
            f.eventsScrollBarBG:Hide()
        end
    end

    return SECTION_H + 2 + viewport
end

local function abandonQuest(questID)
    if not (questID and C_QuestLog and C_QuestLog.SetSelectedQuest
        and C_QuestLog.SetAbandonQuest and C_QuestLog.GetAbandonQuest) then
        return
    end
    if InCombatLockdown and InCombatLockdown() then return end

    local oldSelected = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest() or 0
    C_QuestLog.SetSelectedQuest(questID)
    C_QuestLog.SetAbandonQuest()

    local abandonID = C_QuestLog.GetAbandonQuest()
    local title = (QuestUtils_GetQuestName and QuestUtils_GetQuestName(abandonID))
                  or (C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(abandonID))
                  or "this quest"

    local items = C_QuestLog.GetAbandonQuestItems and C_QuestLog.GetAbandonQuestItems()
    if items and #items > 0 and StaticPopupDialogs and StaticPopupDialogs.ABANDON_QUEST_WITH_ITEMS then
        StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", title, table.concat(items, ", "))
    else
        StaticPopup_Show("ABANDON_QUEST", title)
    end

    C_QuestLog.SetSelectedQuest(oldSelected or 0)
end

local function setPinned(DB, questID, value)
    DB.char.pinned[questID] = value or nil
    if value then DB.char.hidden[questID] = nil end
    local C = ns:GetSubsystem("Cache")
    if C then C.dirtyObjectives = true end
    local T = ns:GetSubsystem("Tracker")
    if T and T.Refresh then T:Refresh() end
end

local function setWatched(questID, watch)
    if watch then
        if C_QuestLog.AddQuestWatch then
            C_QuestLog.AddQuestWatch(questID, Enum and Enum.QuestWatchType and Enum.QuestWatchType.Manual)
        end
    elseif C_QuestLog.RemoveQuestWatch then
        C_QuestLog.RemoveQuestWatch(questID)
    end
end

function Tracker:AbandonQuest(questID)
    abandonQuest(questID)
end

function Tracker:SetWatched(questID, watch)
    setWatched(questID, watch)
end

local function openQuestDetailsPopup(questID)
    if not questID then return end

    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_QuestLog")
    end

    if QuestMapQuestOptions_OpenQuestDetails then
        QuestMapQuestOptions_OpenQuestDetails(questID)
        return
    end

    if not QuestLogPopupDetailFrame then return end
    local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                and C_QuestLog.GetLogIndexForQuestID(questID)
    if not idx then return end

    QuestLogPopupDetailFrame.questID = questID
    if C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(questID)
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("ABANDON_QUEST")
        StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS")
    end
    if QuestMapFrame_UpdateQuestDetailsButtons then
        QuestMapFrame_UpdateQuestDetailsButtons()
    end
    if QuestLogPopupDetailFrame_Update then
        QuestLogPopupDetailFrame_Update(true)
    end
    QuestLogPopupDetailFrame:Show()
end

function Tracker:ShowBlockMenu(block, questID)
    if not (block and questID) then return end

    local DB = ns:GetSubsystem("DB")
    if not DB then return end
    local pinned  = DB.char.pinned[questID] == true
    local watched = C_QuestLog and C_QuestLog.GetQuestWatchType
                    and C_QuestLog.GetQuestWatchType(questID) ~= nil
    local focused = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID() == questID
    local title   = ns.Util.QuestTitle(questID, true)

    if not (MenuUtil and MenuUtil.CreateContextMenu) then return end

    MenuUtil.CreateContextMenu(block, function(_owner, root)
        root:CreateTitle(title)

        if pinned then
            root:CreateButton(L["Unpin from tracker"], function()
                setPinned(DB, questID, false)
            end)
        else
            root:CreateButton(L["Pin to tracker"], function()
                setPinned(DB, questID, true)
            end)
        end

        if watched then
            root:CreateButton(L["Untrack Quest"], function()
                setWatched(questID, false)
            end)
        else
            root:CreateButton(L["Track Quest"], function()
                setWatched(questID, true)
            end)
        end

        if focused then
            root:CreateButton(L["Unfocus"], function()
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                    C_SuperTrack.SetSuperTrackedQuestID(0)
                end
            end)
        else
            root:CreateButton(L["Focus"], function()
                if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                    C_SuperTrack.SetSuperTrackedQuestID(questID)
                end
            end)
        end

        root:CreateButton(L["Get Directions"], function()
            local WP = ns:GetSubsystem("ChainGuideWaypoint")
            if WP and WP.GoTo then WP:GoTo(questID) end
        end)

        root:CreateButton(L["Open in Map & Quest Log"], function()
            if C_AddOns and C_AddOns.LoadAddOn then
                C_AddOns.LoadAddOn("Blizzard_QuestLog")
            end
            if QuestMapFrame_OpenToQuestDetails then
                QuestMapFrame_OpenToQuestDetails(questID)
            elseif ToggleQuestLog then
                ToggleQuestLog()
            end
        end)

        root:CreateButton(L["Pop Out Quest Details"], function()
            openQuestDetailsPopup(questID)
        end)

        root:CreateButton(L["Search on Wowhead"], function()
            ns:ShowURL("https://www.wowhead.com/quest=" .. tostring(questID))
        end)

        root:CreateDivider()

        root:CreateButton("|cffff5050" .. L["Abandon Quest"] .. "|r", function()
            abandonQuest(questID)
        end)

        root:CreateDivider()
        root:CreateButton(L["Cancel"], function() end)
    end)
end

function Tracker:OnInitialize()
    disableBlizzardTracker()
    self:BuildFrame()
end

function Tracker:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh() self:Refresh() end
    Events:On("QUEST_LOG_UPDATE",         refresh)
    Events:On("QUEST_ACCEPTED",           refresh)
    Events:On("QUEST_REMOVED",            refresh)
    Events:On("QUEST_TURNED_IN",          refresh)
    Events:On("QUEST_AUTOCOMPLETE",       refresh)
    Events:On("QUEST_WATCH_LIST_CHANGED", refresh)
    Events:On("SUPER_TRACKING_CHANGED",   refresh)
    Events:On("ZONE_CHANGED_NEW_AREA",    refresh)
    Events:On("PLAYER_ENTERING_WORLD",    refresh)
    self:Refresh()

    local DBs   = ns:GetSubsystem("DB")
    local cache = DBs and DBs.chainCache
    if cache and not cache._shownMoveHint then
        cache._shownMoveHint = true
        C_Timer.After(4, function()
            local Dialog = ns:GetSubsystem("Dialog")
            if Dialog then
                Dialog:Show({
                    title = "Everything Quests",
                    text = L["Drag the top edge of the tracker to move it.\n\nType |cffEBB706/eqs|r for options."],
                    button1 = OKAY,
                })
            end
        end)
    end
end
