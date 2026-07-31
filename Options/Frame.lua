local _, ns = ...
local L = ns.L

local Options = ns:RegisterSubsystem("Options", {})
Options.tabs = {}
Options.tabOrder = {}

local TAB_BG_ACTIVE   = ns.Util.color.tabActive
local TAB_BG_INACTIVE = ns.Util.color.tabInactive
local FRAME_BG        = ns.Util.color.optionsBg
local HEADER_RED      = ns.Util.color.headerRed
local YELLOW          = ns.Util.color.buttonYellow
local TAB_HEIGHT      = 28
local TAB_PADDING_X   = 18

function Options:AddTab(id, label, builder)
    self.tabs[id] = { id = id, label = label, builder = builder }
    self.tabOrder[#self.tabOrder + 1] = id
end

local function styleTabButton(btn, active)
    local c = active and TAB_BG_ACTIVE or TAB_BG_INACTIVE
    btn.bg:SetColorTexture(c[1], c[2], c[3], c[4])
    btn.text:SetTextColor(1, 1, 1, 1)
end

function Options:Build()
    if self.frame then return end
    local f = CreateFrame("Frame", "EQOptionsFrame", UIParent, "BackdropTemplate")
    f:SetSize(1020, 720)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(unpack(FRAME_BG))
    f:SetBackdropBorderColor(0.635, 0.000, 0.039, 1.0)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText("Everything Quests")
    f.title:SetTextColor(unpack(HEADER_RED))
    f.title:SetFont(f.title:GetFont(), 25, "OUTLINE")

    f.version = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.version:SetPoint("TOPRIGHT", -34, -14)
    f.version:SetText("v" .. (ns.VERSION or "1.37.0"))
    f.version:SetTextColor(unpack(YELLOW))

    f.discord = CreateFrame("Button", nil, f)
    f.discord.icon = f.discord:CreateTexture(nil, "OVERLAY")
    f.discord.icon:SetSize(16, 16)
    f.discord.icon:SetPoint("LEFT", 0, 0)
    f.discord.icon:SetTexture("Interface\\AddOns\\EverythingQuests\\Media\\Textures\\discord.tga")
    f.discord.text = f.discord:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.discord.text:SetPoint("LEFT", f.discord.icon, "RIGHT", 5, 0)
    f.discord.text:SetText(L["Join our Discord!"])
    f.discord.text:SetTextColor(unpack(YELLOW))
    f.discord:SetSize(16 + 5 + f.discord.text:GetStringWidth() + 4, 18)
    f.discord:SetPoint("TOPLEFT", 14, -15)
    f.discord:SetScript("OnClick", function() ns:ShowDiscord() end)
    f.discord:SetScript("OnEnter", function(s)
        s.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(s, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Join our Discord"], YELLOW[1], YELLOW[2], YELLOW[3])
        GameTooltip:AddLine("Click to copy the invite link.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    f.discord:SetScript("OnLeave", function(s)
        s.text:SetTextColor(unpack(YELLOW))
        GameTooltip:Hide()
    end)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -8, -10)
    local closeBg = close:CreateTexture(nil, "BACKGROUND")
    closeBg:SetAllPoints()
    closeBg:SetColorTexture(0, 0, 0, 0.9)
    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    closeText:SetPoint("CENTER")
    closeText:SetText("X")
    closeText:SetTextColor(1, 1, 1, 1)
    close:SetScript("OnClick", function() f:Hide() end)

    f.tabStrip = CreateFrame("Frame", nil, f)
    f.tabStrip:SetPoint("TOPLEFT", 12, -44)
    f.tabStrip:SetPoint("TOPRIGHT", -12, -44)
    f.tabStrip:SetHeight(TAB_HEIGHT)

    f.tabButtons = {}
    f.tabContent = CreateFrame("Frame", nil, f)
    f.tabContent:SetPoint("TOPLEFT", 12, -44 - TAB_HEIGHT - 6)
    f.tabContent:SetPoint("BOTTOMRIGHT", -12, 12)

    self.frame = f
    self:RebuildTabs()
end

function Options:RebuildTabs()
    local f = self.frame
    if not f then return end
    for _, b in pairs(f.tabButtons) do b:Hide() end

    local x = 0
    for _, id in ipairs(self.tabOrder) do
        local tab = self.tabs[id]
        local btn = f.tabButtons[id]
        if not btn then
            btn = CreateFrame("Button", nil, f.tabStrip)
            btn:SetHeight(TAB_HEIGHT)
            btn.bg = btn:CreateTexture(nil, "BACKGROUND")
            btn.bg:SetAllPoints()
            btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            btn.text:SetPoint("CENTER")
            btn:SetScript("OnClick", function() Options:SelectTab(id) end)
            f.tabButtons[id] = btn
        end
        btn.text:SetText(tab.label)
        btn:SetWidth(btn.text:GetStringWidth() + TAB_PADDING_X * 2)
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", f.tabStrip, "LEFT", x, 0)
        x = x + btn:GetWidth() + 4
        styleTabButton(btn, false)
        btn:Show()
    end
    local DB = ns:GetSubsystem("DB")
    local saved = DB and DB.char.lastOptionsTab
    local active = (saved and self.tabs[saved]) and saved or self.tabOrder[1]
    if self.tabs[active] then self:SelectTab(active) end
end

function Options:SelectTab(id)
    local f = self.frame
    if not f then return end
    for tabId, btn in pairs(f.tabButtons) do
        styleTabButton(btn, tabId == id)
    end
    if self.activeContent then self.activeContent:Hide() end
    local tab = self.tabs[id]
    if tab and tab.builder then
        if not tab.scrollFrame then
            local scroll = CreateFrame("ScrollFrame", nil, f.tabContent, "UIPanelScrollFrameTemplate")
            scroll:SetPoint("TOPLEFT", 0, 0)
            scroll:SetPoint("BOTTOMRIGHT", -24, 0)
            scroll:EnableMouseWheel(true)
            scroll:SetScript("OnMouseWheel", function(sf, delta)
                local range = sf:GetVerticalScrollRange()
                local v = math.min(range, math.max(0, sf:GetVerticalScroll() - delta * 40))
                sf:SetVerticalScroll(v)
            end)
            local child = CreateFrame("Frame", nil, scroll)
            child:SetSize(1, 1500)
            scroll:SetScrollChild(child)
            scroll:SetScript("OnSizeChanged", function(_, w) if w and w > 0 then child:SetWidth(w) end end)
            if scroll:GetWidth() > 0 then child:SetWidth(scroll:GetWidth()) end
            tab.scrollFrame  = scroll
            tab.contentFrame = child
            tab.builder(child)
            -- Measured next frame - the layout has not resolved yet, so the height would be wrong now
            C_Timer.After(0, function()
                local top = child:GetTop()
                if not top then return end
                local lowest = top
                for _, c in ipairs({ child:GetChildren() }) do
                    local b = c:GetBottom()
                    if b and b < lowest then lowest = b end
                end
                child:SetHeight((top - lowest) + 28)
            end)
        end
        tab.scrollFrame:Show()
        self.activeContent = tab.scrollFrame
    end
    local DB = ns:GetSubsystem("DB")
    if DB then DB.char.lastOptionsTab = id end
end

function Options:ApplyWindowScale()
    local f = self.frame
    if not f then return end
    local DB = ns:GetSubsystem("DB")
    local s = DB and DB.db and DB.db.global and DB.db.global.optionsWindowScale
    if type(s) ~= "number" or s <= 0 then s = 1 end
    -- SetScale re-reads anchor offsets in the new scale, so a dragged window jumps unless its center is restored
    local cx, cy = f:GetCenter()
    local oldEff = f:GetEffectiveScale()
    f:SetScale(s)
    if cx and cy and oldEff then
        local newEff = f:GetEffectiveScale()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx * oldEff / newEff, cy * oldEff / newEff)
    end
end

function Options:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function Options:Show()
    self:Build()
    self:ApplyWindowScale()
    self.frame:Show()
    self.frame:Raise()
    local CG = ns:GetSubsystem("ChainGuide")
    if CG and CG.frame and CG.frame:IsShown() then CG.frame:Hide() end
end

function Options:RegisterBlizzardCategory()
    if self._blizzCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Everything Quests")
    title:SetTextColor(unpack(HEADER_RED))

    local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    ver:SetText(L["Version %s"]:format(ns.VERSION or ""))
    ver:SetTextColor(unpack(YELLOW))

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", 0, -18)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["Everything Quests opens its full options in a dedicated window. Click the button below, or type |cffEBB706/eqs|r in chat."])

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(240, 26)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    btn:SetText(L["Open Everything Quests Options"])
    btn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        Options:Show()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Everything Quests")
    Settings.RegisterAddOnCategory(category)
    self._blizzCategory = category
end

function Options:OnEnable()
    self:RegisterBlizzardCategory()
end

function Options:CreateSectionHeader(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetTextColor(unpack(HEADER_RED))
    fs:SetText(text)
    return fs
end

function Options:CreateYellowButton(parent, label, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(160, 28)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.9)
    local txt = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("CENTER")
    txt:SetText(label)
    txt:SetTextColor(unpack(YELLOW))
    b.text = txt
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

local function stripEscapes(s)
    if not s then return "" end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

function Options:AttachTooltip(frame, title, body)
    if not frame or (not title and not body) then return end
    title = (title and title ~= "") and stripEscapes(title) or nil

    if frame.GetObjectType and frame:GetObjectType() == "FontString" then
        local overlay = CreateFrame("Frame", nil, frame:GetParent())
        overlay:SetAllPoints(frame)
        frame = overlay
    elseif frame.label and frame.GetObjectType and frame:GetObjectType() == "CheckButton" then
        local w = frame.label:GetStringWidth() or 0
        if w > 0 then frame:SetHitRectInsets(0, -(w + 8), 0, 0) end
    end

    local targets = { frame }
    if frame.slider then targets[#targets + 1] = frame.slider end
    if frame.button then targets[#targets + 1] = frame.button end

    for _, t in ipairs(targets) do
        if t.EnableMouse then t:EnableMouse(true) end
        t:HookScript("OnEnter", function(s)
            GameTooltip:SetOwner(s, "ANCHOR_RIGHT")
            -- GameTooltip:SetText arg 5 is alpha, not wrap (wrap is 6th) - pass 1 or the title goes invisible
            if title then GameTooltip:SetText(title, YELLOW[1], YELLOW[2], YELLOW[3], 1, true) end
            if body and body ~= "" then GameTooltip:AddLine(body, 0.82, 0.82, 0.82, true) end
            GameTooltip:Show()
        end)
        t:HookScript("OnLeave", function() GameTooltip:Hide() end)
    end
end

function Options:CreateCheckbox(parent, label, getter, setter, tooltip)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)

    local txt = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    txt:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    txt:SetText(label)
    txt:SetTextColor(1, 1, 1)
    cb.label = txt

    cb:SetChecked((getter and getter()) or false)
    cb:SetScript("OnClick", function(btn)
        if setter then setter(btn:GetChecked() and true or false) end
    end)
    if tooltip then self:AttachTooltip(cb, label, tooltip) end
    return cb
end

-- Tooltips hook each option BUTTON, not the wide container - a container hover only fires on the uncovered sliver and anchors mid-screen
function Options:CreateRadioGroup(parent, label, options, getter, setter, maxWidth, pad, tipTitle, tipBody)
    local container = CreateFrame("Frame", nil, parent)

    local labelFS
    if label then
        labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelFS:SetPoint("TOPLEFT")
        labelFS:SetText(label)
        labelFS:SetTextColor(1, 1, 1)
    end

    local buttons = {}
    local function paint(active)
        for _, b in ipairs(buttons) do
            local isActive = (b.value == active)
            if isActive then
                b.bg:SetColorTexture(0.635, 0.0, 0.039, 1)
                b.txt:SetTextColor(1, 1, 1, 1)
            else
                b.bg:SetColorTexture(0.10, 0.10, 0.10, 0.9)
                b.txt:SetTextColor(0.92, 0.72, 0.02, 1)
            end
        end
    end

    local BTN_H, ROW_GAP, BTN_GAP = 24, 4, 4
    local PAD = pad or 18
    local rowAnchor  = labelFS or container
    local rowOffsetY = labelFS and -4 or 0
    local x, y, maxX = 0, 0, 0
    for _, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
        btn:SetHeight(BTN_H)
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        txt:SetPoint("CENTER")
        txt:SetText(opt.label)
        local w = math.max(40, txt:GetStringWidth() + PAD)
        btn:SetWidth(w)
        if maxWidth and x > 0 and (x + w) > maxWidth then
            x, y = 0, y + BTN_H + ROW_GAP
        end
        btn:SetPoint("TOPLEFT", rowAnchor, labelFS and "BOTTOMLEFT" or "TOPLEFT", x, rowOffsetY - y)
        btn.bg, btn.txt, btn.value = bg, txt, opt.value
        btn:SetScript("OnClick", function(b)
            if setter then setter(b.value) end
            paint(b.value)
        end)
        if tipTitle or tipBody then
            btn:HookScript("OnEnter", function(b)
                GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
                if tipTitle then GameTooltip:SetText(tipTitle, YELLOW[1], YELLOW[2], YELLOW[3], 1, true) end
                if tipBody and tipBody ~= "" then GameTooltip:AddLine(tipBody, 0.82, 0.82, 0.82, true) end
                GameTooltip:Show()
            end)
            btn:HookScript("OnLeave", function() GameTooltip:Hide() end)
        end
        x = x + w + BTN_GAP
        if x > maxX then maxX = x end
        buttons[#buttons + 1] = btn
    end

    paint(getter and getter())
    container:SetSize(maxWidth or maxX, 50 + y)
    return container
end

function Options:CreateDropdown(parent, label, options, getter, setter, onTest, onItemRender)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local function resolveOptions()
        return (type(options) == "function") and (options() or {}) or options
    end

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local speaker
    if onTest then
        speaker = CreateFrame("Button", nil, container)
        speaker:SetSize(20, 20)
        speaker:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
        local sicon = speaker:CreateTexture(nil, "ARTWORK")
        sicon:SetAllPoints()
        sicon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
        speaker:SetHighlightTexture("Interface\\Common\\VoiceChat-Speaker", "ADD")
        speaker:SetScript("OnClick", function()
            onTest(getter and getter())
        end)
    end

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetHeight(22)
    if speaker then
        btn:SetPoint("TOPLEFT", speaker, "TOPRIGHT", 4, 0)
    else
        btn:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -4)
    end
    btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", 6, 0)
    btn.text:SetTextColor(unpack(YELLOW))
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(unpack(YELLOW))

    local function syncLabel()
        local current = getter and getter()
        for _, opt in ipairs(resolveOptions()) do
            if opt.value == current then btn.text:SetText(opt.label); return end
        end
        btn.text:SetText(tostring(current or ""))
    end

    btn:SetScript("OnClick", function(b)
        if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
        MenuUtil.CreateContextMenu(b, function(_, root)
            for _, opt in ipairs(resolveOptions()) do
                local entry = root:CreateButton(opt.label, function()
                    if setter then setter(opt.value) end
                    syncLabel()
                end)
                if onItemRender and entry and entry.AddInitializer then
                    entry:AddInitializer(function(buttonFrame)
                        onItemRender(buttonFrame, opt)
                    end)
                end
            end
        end)
    end)

    syncLabel()
    container.button = btn
    container.sync   = syncLabel
    return container
end

function Options:CreateFontDropdown(parent, label, options, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetHeight(22)
    btn:SetPoint("TOPLEFT",  labelFS, "BOTTOMLEFT", 0, -4)
    btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT",  6, 0)
    btn.text:SetPoint("RIGHT", -22, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWordWrap(false)
    btn.text:SetTextColor(unpack(YELLOW))
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(unpack(YELLOW))

    local ROW_H, MAX_VISIBLE = 22, 10
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:Hide()
    local pbg = popup:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.04, 0.04, 0.04, 0.98)
    local border = popup:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.30, 0.30, 0.30, 1)

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)

    local rows = {}
    local function setCurrentLabel()
        local current = getter and getter()
        for _, opt in ipairs(options) do
            if opt.value == current then btn.text:SetText(opt.label); return end
        end
        btn.text:SetText(tostring(current or ""))
    end

    local function rebuildRows()
        local Media = ns:GetSubsystem("Media")
        for _, row in ipairs(rows) do row:Hide() end
        for i, opt in ipairs(options) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, scrollChild)
                row:SetHeight(ROW_H)
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.10)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.text:SetPoint("LEFT",  6, 0)
                row.text:SetPoint("RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            row.text:SetText(opt.label)
            row.text:SetTextColor(unpack(YELLOW))
            local file = Media and Media.GetFontFile and Media:GetFontFile(opt.value)
            if file then
                local ok = pcall(row.text.SetFont, row.text, file, 13, "")
                if not ok then row.text:SetFont(STANDARD_TEXT_FONT, 13, "") end
            end
            row:SetScript("OnClick", function()
                if setter then setter(opt.value) end
                popup:Hide()
                setCurrentLabel()
            end)
            row:Show()
        end
        scrollChild:SetSize(math.max(1, scroll:GetWidth()), math.max(1, #options * ROW_H))
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide(); return end
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT",  btn, "BOTTOMLEFT",  0, -2)
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        local visible = math.min(#options, MAX_VISIBLE)
        popup:SetHeight(visible * ROW_H + 8)
        popup:Show()
        rebuildRows()
    end)

    popup:SetScript("OnShow", function(self)
        self._closer = self._closer or CreateFrame("Button", nil, UIParent)
        self._closer:SetAllPoints(UIParent)
        self._closer:SetFrameStrata("FULLSCREEN")
        self._closer:RegisterForClicks("AnyDown")
        self._closer:SetScript("OnClick", function() self:Hide() end)
        self._closer:Show()
    end)
    popup:SetScript("OnHide", function(self)
        if self._closer then self._closer:Hide() end
    end)

    setCurrentLabel()
    container.button = btn
    container.sync   = setCurrentLabel
    return container
end

function Options:CreateStatusBarDropdown(parent, label, options, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetHeight(22)
    btn:SetPoint("TOPLEFT",  labelFS, "BOTTOMLEFT", 0, -4)
    btn:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    btn.swatch = btn:CreateTexture(nil, "ARTWORK")
    btn.swatch:SetPoint("LEFT", 6, 0)
    btn.swatch:SetSize(60, 12)
    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("LEFT", 74, 0)
    btn.text:SetPoint("RIGHT", -22, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetWordWrap(false)
    btn.text:SetTextColor(unpack(YELLOW))
    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.arrow:SetPoint("RIGHT", -6, 0)
    btn.arrow:SetText("v")
    btn.arrow:SetTextColor(unpack(YELLOW))

    local ROW_H, MAX_VISIBLE = 22, 12
    local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:Hide()
    local pbg = popup:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints()
    pbg:SetColorTexture(0.04, 0.04, 0.04, 0.98)
    local border = popup:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.30, 0.30, 0.30, 1)

    local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)
    local scrollChild = CreateFrame("Frame", nil, scroll)
    scrollChild:SetSize(1, 1)
    scroll:SetScrollChild(scrollChild)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(sf, delta)
        local range = sf:GetVerticalScrollRange()
        local cur = sf:GetVerticalScroll()
        sf:SetVerticalScroll(math.min(range, math.max(0, cur - delta * ROW_H * 2)))
    end)

    local function applySwatch(tex, value)
        local Media = ns:GetSubsystem("Media")
        local file = Media and Media.GetStatusBarFile and Media:GetStatusBarFile(value)
        if file then
            tex:SetTexture(file)
            tex:SetVertexColor(0.26, 0.42, 1.0)
            tex:Show()
        else
            tex:Hide()
        end
    end

    local function setCurrentLabel()
        local current = getter and getter()
        applySwatch(btn.swatch, current)
        for _, opt in ipairs(options) do
            if opt.value == current then btn.text:SetText(opt.label); return end
        end
        btn.text:SetText(tostring(current or ""))
    end

    local rows = {}
    local function rebuildRows()
        for _, row in ipairs(rows) do row:Hide() end
        for i, opt in ipairs(options) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, scrollChild)
                row:SetHeight(ROW_H)
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.10)
                row.swatchBg = row:CreateTexture(nil, "BACKGROUND")
                row.swatchBg:SetPoint("LEFT", 6, 0)
                row.swatchBg:SetSize(60, 12)
                row.swatchBg:SetColorTexture(0, 0, 0, 0.6)
                row.swatch = row:CreateTexture(nil, "ARTWORK")
                row.swatch:SetPoint("LEFT", 6, 0)
                row.swatch:SetSize(60, 12)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                row.text:SetPoint("LEFT", 74, 0)
                row.text:SetPoint("RIGHT", -6, 0)
                row.text:SetJustifyH("LEFT")
                row.text:SetWordWrap(false)
                rows[i] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  scrollChild, "TOPLEFT",  0, -(i - 1) * ROW_H)
            row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -(i - 1) * ROW_H)
            row.text:SetText(opt.label)
            row.text:SetTextColor(unpack(YELLOW))
            applySwatch(row.swatch, opt.value)
            row:SetScript("OnClick", function()
                if setter then setter(opt.value) end
                popup:Hide()
                setCurrentLabel()
            end)
            row:Show()
        end
        scrollChild:SetSize(math.max(1, scroll:GetWidth()), math.max(1, #options * ROW_H))
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then popup:Hide(); return end
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT",  btn, "BOTTOMLEFT",  0, -2)
        popup:SetPoint("TOPRIGHT", btn, "BOTTOMRIGHT", 0, -2)
        local visible = math.min(#options, MAX_VISIBLE)
        popup:SetHeight(visible * ROW_H + 8)
        popup:Show()
        rebuildRows()
    end)

    popup:SetScript("OnShow", function(self)
        self._closer = self._closer or CreateFrame("Button", nil, UIParent)
        self._closer:SetAllPoints(UIParent)
        self._closer:SetFrameStrata("FULLSCREEN")
        self._closer:RegisterForClicks("AnyDown")
        self._closer:SetScript("OnClick", function() self:Hide() end)
        self._closer:Show()
    end)
    popup:SetScript("OnHide", function(self)
        if self._closer then self._closer:Hide() end
    end)

    setCurrentLabel()
    container.button = btn
    container.sync   = setCurrentLabel
    return container
end

function Options:CreateSlider(parent, label, min, max, step, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 44)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("TOPLEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local valueFS = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueFS:SetPoint("TOPRIGHT")
    valueFS:SetTextColor(unpack(YELLOW))

    local function chooseFormat(s)
        if not s or s >= 1 then return "%d" end
        local decimals = math.max(1, math.ceil(-math.log10(s)))
        return "%." .. decimals .. "f"
    end
    local valueFmt = chooseFormat(step)
    local function formatValue(v)
        return valueFmt:format(v)
    end

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -8)
    slider:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, -22)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    if slider.Low  then slider.Low:SetText("")  end
    if slider.High then slider.High:SetText("") end
    if slider.Text then slider.Text:SetText("") end

    slider:SetValue(getter and getter() or min)
    valueFS:SetText(formatValue(slider:GetValue()))

    slider:SetScript("OnValueChanged", function(_, v)
        local stepped = step and (math.floor((v - min) / step + 0.5) * step + min) or v
        valueFS:SetText(formatValue(stepped))
        if setter then setter(stepped) end
    end)

    container.slider = slider
    return container
end

-- Skipped when another UI already adds a class-color button to the picker, to avoid a duplicate
local function elvUILoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("ElvUI")) and true or false
end

local _classColorButton
local _activeColorApply
local _activeReopen

local function ensureClassColorButton()
    if _classColorButton ~= nil then return _classColorButton or nil end
    if elvUILoaded() or not ColorPickerFrame then _classColorButton = false; return nil end
    local b = Options:CreateYellowButton(ColorPickerFrame, _G.CLASS or "Class", function()
        local getCC = ns.Util and ns.Util.GetPlayerClassColor
        if not getCC then return end
        local r, g, bl = getCC()
        if not r or not _activeReopen then return end
        -- SetColorRGB does not reliably move the 10.2.5+ picker, so re-open it seeded with the class color
        local a = (ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()) or 1
        _activeReopen(r, g, bl, a)
        if _activeColorApply then _activeColorApply() end
    end)
    b:SetSize(90, 22)
    b:SetPoint("TOPLEFT", ColorPickerFrame, "TOPRIGHT", 6, -34)
    b:Hide()
    ColorPickerFrame:HookScript("OnHide", function()
        if _classColorButton then _classColorButton:Hide() end
        _activeColorApply = nil
        _activeReopen = nil
    end)
    _classColorButton = b
    return b
end

function Options:CreateColorPicker(parent, label, getter, setter)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 22)

    local labelFS = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelFS:SetPoint("LEFT")
    labelFS:SetText(label)
    labelFS:SetTextColor(1, 1, 1)

    local btn = CreateFrame("Button", nil, container, "BackdropTemplate")
    btn:SetSize(44, 20)
    btn:SetPoint("LEFT", labelFS, "RIGHT", 8, 0)
    local border = btn:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.92, 0.72, 0.02, 1)
    local underlay = btn:CreateTexture(nil, "BORDER")
    underlay:SetPoint("TOPLEFT", 2, -2)
    underlay:SetPoint("BOTTOMRIGHT", -2, 2)
    underlay:SetColorTexture(0, 0, 0, 1)
    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetPoint("TOPLEFT", 2, -2)
    swatch:SetPoint("BOTTOMRIGHT", -2, 2)

    local function paint()
        local c = getter and getter() or { r = 1, g = 1, b = 1, a = 1 }
        swatch:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
    end
    paint()

    btn:SetScript("OnClick", function()
        local c = getter and getter() or { r = 1, g = 1, b = 1, a = 1 }
        -- cancelFunc's prev arg changed shape in the 10.2.5 picker overhaul (alpha unreliable), so restore from this snapshot
        local orig = { r = c.r or 0, g = c.g or 0, b = c.b or 0, a = c.a or 1 }
        local function applyColor(restore)
            local r, g, b, a
            if restore then
                r, g, b, a = restore.r, restore.g, restore.b, restore.a
            elseif ColorPickerFrame and ColorPickerFrame.GetColorRGB then
                r, g, b = ColorPickerFrame:GetColorRGB()
                -- GetColorAlpha arrived in 10.0 and OpacitySliderFrame was removed at the same time
                if ColorPickerFrame.GetColorAlpha then
                    a = ColorPickerFrame:GetColorAlpha()
                elseif OpacitySliderFrame then
                    a = 1 - OpacitySliderFrame:GetValue()
                else
                    a = c.a or 1
                end
            else
                r, g, b, a = c.r, c.g, c.b, c.a
            end
            if setter then setter({ r = r, g = g, b = b, a = a }) end
            paint()
        end
        if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
            local function openWith(nr, ng, nb, na)
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = nr, g = ng, b = nb,
                    opacity = na, hasOpacity = true,
                    swatchFunc = function() applyColor() end,
                    opacityFunc = function() applyColor() end,
                    cancelFunc  = function() applyColor(orig) end,
                })
                _activeColorApply = applyColor
                _activeReopen = openWith
                local classBtn = ensureClassColorButton()
                if classBtn then classBtn:Show() end
            end
            openWith(c.r or 0, c.g or 0, c.b or 0, c.a or 1)
        end
    end)

    container.button = btn
    container.label  = labelFS
    container.paint  = paint
    return container
end

local function eqSlashHandler(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "chain" then
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Toggle() end
        return
    elseif msg == "history" then
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Toggle then HF:Toggle() end
        return
    elseif msg == "session" then
        local Sess = ns:GetSubsystem("Session")
        if Sess and Sess.Print then Sess:Print() end
        return
    elseif msg == "whatsnew chat" then
        local WN = ns:GetSubsystem("WhatsNew")
        if WN and WN.PrintChatLink then WN:PrintChatLink() end
        return
    elseif msg == "whatsnew" or msg == "changes" then
        local WN = ns:GetSubsystem("WhatsNew")
        if WN and WN.Show then WN:Show() end
        return
    elseif msg == "about" then
        Options:Show()
        Options:SelectTab("about")
        return
    elseif msg:match("^discover") then
        local hint = msg:match("^discover%s+(.+)$")
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.PrintCurrentZone then QLS:PrintCurrentZone(hint) end
        return
    elseif msg == "wqdebug" then
        Options:DumpWorldQuestSources()
        return
    elseif msg == "scenario" then
        Options:DumpScenarioInfo()
        return
    elseif msg == "bonushud" then
        local Hud = ns:GetSubsystem("TrackerScenarioBonusHUD")
        if Hud and Hud.Dump then Hud:Dump() end
        return
    elseif msg == "bonushud test" then
        local Hud = ns:GetSubsystem("TrackerScenarioBonusHUD")
        if Hud and Hud.ToggleTest then Hud:ToggleTest() end
        return
    elseif msg == "profdebug" then
        local Prof = ns:GetSubsystem("TrackerProfession")
        if Prof and Prof.Dump then Prof:Dump() end
        return
    elseif msg == "trackerdebug" then
        local T = ns:GetSubsystem("Tracker")
        if T and T.DebugSize then T:DebugSize() end
        return
    elseif msg == "questobj" then
        Options:DumpQuestObjectives()
        return
    elseif msg == "autopopup" then
        Options:DumpAutoQuestPopups()
        return
    elseif msg == "dir" then
        Options:DumpDirections()
        return
    elseif msg == "questzone" then
        if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
            print("|cffEBB706EQ QuestZone|r: quest log API unavailable.")
            return
        end
        local function mapName(m)
            if m and m > 0 and C_Map and C_Map.GetMapInfo then
                local mi = C_Map.GetMapInfo(m)
                return (mi and mi.name) or "?"
            end
            return "-"
        end
        local n = C_QuestLog.GetNumQuestLogEntries()
        local header = "(none)"
        local pMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local onMapSet = {}
        if pMap and C_QuestLog.GetQuestsOnMap then
            for _, e in ipairs(C_QuestLog.GetQuestsOnMap(pMap) or {}) do
                if e.questID then onMapSet[e.questID] = true end
            end
        end
        print(("|cffEBB706EQ QuestZone|r zone=|cff66ccff%s|r  playerMap=%s(%s) — 'only current zone' shows a quest when onMap=Y or hdr==zone:"):format(
            tostring(GetZoneText and GetZoneText() or "?"), tostring(pMap), mapName(pMap)))
        print(("   %d entries — id title | hdr | onMap | Task=GetQuestZoneID | UiMap=GetQuestUiMapID:"):format(n))
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    header = info.title or "(unnamed)"
                elseif not info.isHidden then
                    local qid = info.questID
                    local tz  = C_TaskQuest and C_TaskQuest.GetQuestZoneID and C_TaskQuest.GetQuestZoneID(qid)
                    local ok, um = pcall(function() return GetQuestUiMapID and GetQuestUiMapID(qid) end)
                    if not ok then um = "ERR" end
                    print(("   %s %s | hdr=|cff66ccff%s|r | onMap=%s | Task=%s(%s) | UiMap=%s(%s)"):format(
                        tostring(qid), tostring(info.title), tostring(header),
                        onMapSet[qid] and "|cff44ff44Y|r" or "|cff888888n|r",
                        tostring(tz), mapName(tz), tostring(um), mapName(tonumber(um))))
                end
            end
        end
        return
    elseif msg == "chaindump" then
        local DBm = ns:GetSubsystem("ChainGuideDatabase")
        local H   = ns:GetSubsystem("ChainGuideHistory")
        local state   = H and H.Current and H:Current()
        local chainID = state and state.type == "chain" and state.id
        local chain   = chainID and DBm and DBm.chains[chainID]
        if not chain then
            print("|cffEBB706EQ ChainDump|r: open the Chain Guide and select a chain first.")
            return
        end
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
        DBm:NormalizeChain(chain)
        print(("|cffEBB706EQ ChainDump|r |cffffffff%s|r  chainID=|cff66ccff%s|r questlineID=|cff66ccff%s|r category=|cff66ccff%s|r"):format(
            chain.name or "?", tostring(chain.id), tostring(chain.questlineID), tostring(chain.category)))
        local items = chain.items or {}
        print(("  %d item(s) (copy/paste this to share):"):format(#items))
        for i = 1, #items do
            local it = items[i]
            local nm
            if it.type == "chain" then
                local sub = DBm.chains[it.id]
                nm = (sub and sub.name) or "?"
            else
                nm = (ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(it.id)) or "?"
            end
            print(("    [%d] %s id=%s x=%s y=%s  %s"):format(
                i, it.type or "quest", tostring(it.id), tostring(it.x), tostring(it.y), nm))
        end
        return
    elseif msg == "campdump" then
        local DBm = ns:GetSubsystem("ChainGuideDatabase")
        if not (C_CampaignInfo and C_CampaignInfo.GetChapterIDs
                and C_QuestLine and C_QuestLine.GetQuestLineQuests) then
            print("|cffEBB706EQ CampDump|r: campaign/questline API unavailable on this build.")
            return
        end
        local camps = {}
        if DBm then
            for _, cat in pairs(DBm.categories) do
                if cat.campaignID then camps[#camps + 1] = { id = cat.campaignID, name = cat.name } end
            end
        end
        if #camps == 0 then
            print("|cffEBB706EQ CampDump|r: no campaign categories registered.")
            return
        end
        table.sort(camps, function(a, b) return a.id < b.id end)
        for c = 1, #camps do
            local camp = camps[c]
            local chapters = C_CampaignInfo.GetChapterIDs(camp.id) or {}
            print(("|cffEBB706EQ CampDump|r |cffffffff%s|r  campaignID=|cff66ccff%d|r  %d chapter(s):"):format(
                camp.name or "?", camp.id, #chapters))
            for i = 1, #chapters do
                local chID = chapters[i]
                local ci = C_CampaignInfo.GetCampaignChapterInfo
                           and C_CampaignInfo.GetCampaignChapterInfo(chID)
                local quests = C_QuestLine.GetQuestLineQuests(chID) or {}
                print(("    [%d] questlineID=|cff66ccff%d|r %s  (%d quest(s))"):format(
                    i, chID, (ci and ci.name) or "?", #quests))
                if #quests > 0 then
                    print("        " .. table.concat(quests, ", "))
                end
            end
        end
        return
    elseif msg:match("^campfind") then
        local filter = msg:match("^campfind%s+(.+)$")
        if not (C_CampaignInfo and C_CampaignInfo.GetCampaignInfo) then
            print("|cffEBB706EQ CampFind|r: campaign API unavailable on this build.")
            return
        end
        local DBm = ns:GetSubsystem("ChainGuideDatabase")
        local known = {}
        if DBm then
            for _, cat in pairs(DBm.categories) do
                if cat.campaignID then known[cat.campaignID] = cat.name or "?" end
            end
        end
        local seen, ids = {}, {}
        local function add(id)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
        if C_CampaignInfo.GetAvailableCampaigns then
            for _, id in ipairs(C_CampaignInfo.GetAvailableCampaigns() or {}) do add(id) end
        end
        -- GetAvailableCampaigns does not return every campaign - the live run missed both registered ones
        if C_CampaignInfo.GetCampaignID and C_QuestLog
           and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID then
                    add(C_CampaignInfo.GetCampaignID(info.questID))
                end
            end
        end
        table.sort(ids)
        local needle = filter and filter:gsub("[^%w]", "")
        print(("|cffEBB706EQ CampFind|r %d campaign(s) visible%s:"):format(
            #ids, needle and (" \194\183 filter '" .. filter .. "'") or ""))
        local shown = 0
        for c = 1, #ids do
            local id   = ids[c]
            local ci   = C_CampaignInfo.GetCampaignInfo(id)
            local name = (ci and ci.name) or "?"
            local flat = name:lower():gsub("[^%w]", "")
            if not needle or flat:find(needle, 1, true) then
                shown = shown + 1
                local chapters = (C_CampaignInfo.GetChapterIDs and C_CampaignInfo.GetChapterIDs(id)) or {}
                print(("  campaignID=|cff66ccff%d|r |cffffffff%s|r  %d chapter(s)  %s"):format(
                    id, name, #chapters,
                    known[id] and ("|cff44ff44registered as '" .. known[id] .. "'|r")
                              or "|cffff6666NOT registered|r"))
                for i = 1, #chapters do
                    local chID = chapters[i]
                    local chi  = C_CampaignInfo.GetCampaignChapterInfo
                                 and C_CampaignInfo.GetCampaignChapterInfo(chID)
                    local quests = (C_QuestLine and C_QuestLine.GetQuestLineQuests
                                    and C_QuestLine.GetQuestLineQuests(chID)) or {}
                    print(("    [%d] questlineID=|cff66ccff%d|r %s  (%d quest(s))"):format(
                        i, chID, (chi and chi.name) or "?", #quests))
                end
                if not known[id] then
                    print(("    paste into _Index.lua:  campaignID = %d, name = \"%s\""):format(id, name))
                end
            end
        end
        if shown == 0 then
            print("  (nothing matched \194\183 run |cffffffff/eqs campfind|r with no filter to list them all)")
        end
        return
    elseif msg:match("^zonedump") then
        local hint = msg:match("^zonedump%s+(.+)$")
        local DBm  = ns:GetSubsystem("ChainGuideDatabase")
        if not (hint and DBm and ns.QUESTLINE_ROUTING
                and C_QuestLine and C_QuestLine.GetQuestLineQuests) then
            print("|cffEBB706EQ ZoneDump|r: usage |cffffffff/eqs zonedump <zone>|r (eversong, zulaman, harandar, voidstorm, arator)")
            return
        end
        local lower = hint:lower():gsub("[^%w]", "")
        local catID, catName
        for id, cat in pairs(DBm.categories) do
            local cn = (cat.name or ""):lower():gsub("[^%w]", "")
            if cn ~= "" and (cn == lower or cn:find(lower, 1, true) or lower:find(cn, 1, true)) then
                catID, catName = id, cat.name
                break
            end
        end
        if not catID then
            print(("|cffEBB706EQ ZoneDump|r: no category matches '%s'."):format(hint))
            return
        end
        local qls = {}
        for qlID, entry in pairs(ns.QUESTLINE_ROUTING) do
            local ecat = (type(entry) == "table") and entry.cat or entry
            if ecat == catID then
                qls[#qls + 1] = { id = qlID, name = (type(entry) == "table") and entry.name or nil }
            end
        end
        table.sort(qls, function(a, b) return a.id < b.id end)
        print(("|cffEBB706EQ ZoneDump|r |cffffffff%s|r  categoryID=|cff66ccff%d|r  %d questline(s):"):format(
            catName or "?", catID, #qls))
        for i = 1, #qls do
            local q = qls[i]
            local quests = C_QuestLine.GetQuestLineQuests(q.id) or {}
            print(("    [%d] questlineID=|cff66ccff%d|r %s  (%d quest(s))"):format(
                i, q.id, q.name or "?", #quests))
            if #quests > 0 then
                print("        " .. table.concat(quests, ", "))
            end
        end
        return
    elseif msg:match("^zonebar") then
        local ZP = ns:GetSubsystem("TrackerZoneProgress")
        if msg:match("debug") then
            ns.zoneBarDebug = not ns.zoneBarDebug
            print("|cffEBB706EQ ZoneBar|r debug " .. (ns.zoneBarDebug and "ON" or "OFF"))
        end
        if ZP and ZP.PrintStatus then ZP:PrintStatus() end
        return
    elseif msg == "skindebug" then
        local T = ns:GetSubsystem("Tracker")
        local f = T and T.frame
        local sf = f and f.scroll
        local bar = sf and (sf.ScrollBar or sf.scrollBar)
        if not bar then print("|cffEBB706EQ Skin|r: no scroll bar found"); return end
        print(("|cffEBB706EQ Skin|r bar: %s  name=%s"):format(bar:GetObjectType(), bar:GetName() or "(unnamed)"))
        print(("  GetThumbTexture=%s thumbTex=%s"):format(
            tostring(bar.GetThumbTexture ~= nil),
            tostring(bar.GetThumbTexture and bar:GetThumbTexture())))
        print(("  .Thumb=%s  .Track=%s"):format(tostring(bar.Thumb), tostring(bar.Track)))
        print(("  up: .ScrollUpButton=%s .Back=%s   down: .ScrollDownButton=%s .Forward=%s"):format(
            tostring(bar.ScrollUpButton), tostring(bar.Back),
            tostring(bar.ScrollDownButton), tostring(bar.Forward)))
        return
    elseif msg:match("^profile") then
        local rest = msg:match("^profile%s*(.*)$") or ""
        local Profiler = ns:GetSubsystem("Profiler")
        if not Profiler then return end
        if rest == "" or rest == "show" then
            Profiler:Show()
        elseif rest == "reset" then
            Profiler:Reset()
            print("|cffEBB706EQ Profile|r reset")
        elseif rest:match("^memhog") then
            Profiler:ToggleMemHog()
            print("|cffEBB706EQ Profile|r memhog "
                  .. (Profiler.memhog and Profiler.memhog.active and "ON" or "OFF"))
        elseif rest:match("^mem%s+on") then
            Profiler:SetMemoryMode(true)
            print("|cffEBB706EQ Profile|r memory mode ON — collectgarbage forced at boundaries (expensive; toggle off when done)")
        elseif rest:match("^mem%s+off") then
            Profiler:SetMemoryMode(false)
            print("|cffEBB706EQ Profile|r memory mode OFF")
        elseif rest:match("^auto%s+on") then
            local wrapped, missing = Profiler:AutoInstrument(true)
            print(("|cffEBB706EQ Profile|r auto-instrument ON \194\183 wrapped %d hot path%s%s"):format(
                wrapped, wrapped == 1 and "" or "s",
                missing > 0 and (", " .. missing .. " missing (subsystem not loaded)") or ""))
            print("  Use /eqs profile show after playing for a few minutes; /eqs profile auto off to unwrap")
        elseif rest:match("^auto%s+off") then
            local n = Profiler:AutoInstrument(false)
            print(("|cffEBB706EQ Profile|r auto-instrument OFF \194\183 unwrapped %d method%s"):format(
                n, n == 1 and "" or "s"))
        elseif rest:match("^auto%s+list") or rest == "auto" then
            local list = Profiler:ListWrapped()
            if #list == 0 then
                print("|cffEBB706EQ Profile|r auto-instrument is OFF (nothing wrapped)")
            else
                print(("|cffEBB706EQ Profile|r currently wrapped (%d):"):format(#list))
                for _, k in ipairs(list) do print("  " .. k) end
            end
        else
            print("|cffEBB706EQ Profile|r usage: /eqs profile [show | reset | mem on | mem off | memhog | auto on | auto off | auto list]")
        end
        return
    end
    local ok, err = pcall(function() Options:Toggle() end)
    if not ok then
        print(L["|cffEBB706Everything Quests|r: couldn't open Options \226\128\148 %s"]:format(tostring(err)))
    end
end

-- "/eq" is Blizzard's secure /equip and is dispatched before SlashCmdList, so an "/eq" handler is unreachable and risks taint
SLASH_EVERYTHINGQUESTS1 = "/eqs"
SLASH_EVERYTHINGQUESTS2 = "/everythingquests"
SlashCmdList["EVERYTHINGQUESTS"] = eqSlashHandler

function Options:DumpScenarioInfo()
    local function line(label, value) print(("|cffEBB706EQ Scenario|r %s: %s"):format(label, tostring(value))) end

    if C_Scenario and C_Scenario.GetInfo then
        local name, currentStage, numStages, _, _, _, _, _, _, scenarioType, _, textureKit = C_Scenario.GetInfo()
        line("scenarioName", name or "(nil)")
        line("scenarioType", scenarioType or "(nil)")
        line("textureKit",   textureKit or "(nil)")
        line("stage",        tostring(currentStage or "?") .. " / " .. tostring(numStages or "?"))
    else
        line("C_Scenario.GetInfo", "unavailable")
    end

    if C_Scenario and C_Scenario.GetStepInfo then
        local stepName = C_Scenario.GetStepInfo()
        line("stepName", stepName or "(nil)")
    end

    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local si = C_ScenarioInfo.GetScenarioInfo()
        line("GetScenarioInfo.name", (si and si.name) or "(nil)")
    end

    if GetInstanceInfo then
        local instName, instType, diffID, diffName = GetInstanceInfo()
        line("instance name",  instName or "(nil)")
        line("instance type",  instType or "(nil)")
        line("difficulty",     tostring(diffName) .. " (id " .. tostring(diffID) .. ")")
    end

    do
        local instName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
        local si = C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo and C_ScenarioInfo.GetScenarioInfo()
        local sName = C_Scenario and C_Scenario.GetInfo and select(1, C_Scenario.GetInfo()) or nil
        local proposed = (instName and instName ~= "" and instName)
                         or (si and si.name)
                         or sName
        line("<- proposed name line", proposed or "(none)")
    end

    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        line("map", ((info and info.name) or "?") .. " (id " .. tostring(mapID) .. ")")
    end
end

function Options:DumpQuestObjectives()
    local function p(s) print("|cffEBB706EQ QuestObj|r " .. s) end
    if not C_QuestLog then p("C_QuestLog unavailable"); return end

    local num     = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
    local savedID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    local getText = _G.GetQuestLogQuestText
    local shown   = 0

    for i = 1, num do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            local id      = info.questID
            local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil
            if watched then
                local objs     = (C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)) or {}
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
                local ready    = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)
                p(("[%d] %s | obj=%d complete=%s ready=%s"):format(
                    id, info.title or "?", #objs, tostring(complete), tostring(ready)))
                for j = 1, #objs do
                    local o = objs[j]
                    p(("    obj%d type=%s finished=%s text=%q"):format(
                        j, tostring(o.type), tostring(o.finished), tostring(o.text)))
                end
                if #objs == 0 then
                    local compText = C_QuestLog.GetQuestLogCompletionText
                                     and C_QuestLog.GetQuestLogCompletionText(id)
                    p(("    completionText=%q"):format(tostring(compText)))
                    if getText and C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(id)
                        local _, objText = getText()
                        p(("    objectivesText=%q"):format(tostring(objText)))
                    end
                end
                shown = shown + 1
            end
        end
    end

    if savedID and savedID ~= 0 and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(savedID)
    end
    if shown == 0 then p("no watched quests found") end
end

function Options:DumpDirections()
    local function p(s) print("|cffEBB706EQ Dir|r " .. s) end
    if not C_Map then p("C_Map unavailable"); return end

    local pMap   = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pPos   = pMap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pMap, "player")
    local ppx, ppy
    if pPos then ppx, ppy = pPos:GetXY() end
    local pCont, pWorld
    if pPos and C_Map.GetWorldPosFromMapPos then
        pCont, pWorld = C_Map.GetWorldPosFromMapPos(pMap, pPos)
    end

    local function yards(mapID, x, y)
        if not (pWorld and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
        local c, w = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not w or c ~= pCont then return nil end
        local wx, wy = w:GetXY()
        local px, py = pWorld:GetXY()
        local dx, dy = px - wx, py - wy
        return math.sqrt(dx * dx + dy * dy)
    end

    local function line(label, mapID, x, y)
        if not (mapID and x and y) then
            p(("  %-20s |cffff5555none|r"):format(label))
            return
        end
        local d = yards(mapID, x, y)
        p(("  %-20s map %d  %.1f, %.1f%s"):format(
            label, mapID, x * 100, y * 100,
            d and ("  |cff88ff88%.0f yds|r"):format(d) or "  |cff888888(off-continent)|r"))
    end

    local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID()
    if (not questID or questID == 0) and C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex
       and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() > 0 then
        questID = C_QuestLog.GetQuestIDForQuestWatchIndex(1)
    end
    if not questID or questID == 0 then
        p("no super-tracked or watched quest — super-track the quest you're testing, then re-run")
        return
    end

    local title = (ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(questID, true)) or tostring(questID)
    p(("|cffffffff%s|r (id %d)"):format(title, questID))
    p(("  %-20s map %s  %.1f, %.1f"):format("player at", tostring(pMap), (ppx or 0) * 100, (ppy or 0) * 100))

    local logIdx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                   and C_QuestLog.GetLogIndexForQuestID(questID)
    p("  active in log:       " .. (logIdx and "YES (live objective wins)" or "no (giver coords only)"))

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        line("GetNextWaypoint", C_QuestLog.GetNextWaypoint(questID))
    end
    if pMap and C_QuestLog and C_QuestLog.GetNextWaypointForMap then
        local fx, fy = C_QuestLog.GetNextWaypointForMap(questID, pMap)
        line("NextWaypointForMap", pMap, fx, fy)
    end

    local st = ns.CHAINGUIDE_QUEST_COORDS and ns.CHAINGUIDE_QUEST_COORDS[questID]
    line("bundled coords", st and st.m, st and st.x, st and st.y)

    local DB = ns:GetSubsystem("DB")
    local ce = DB and DB.chainCache and DB.chainCache.questCoords and DB.chainCache.questCoords[questID]
    line("harvested cache", ce and ce.m, ce and ce.x, ce and ce.y)

    local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local ready    = C_QuestLog and C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)
    p(("  state:               complete=%s readyForTurnIn=%s"):format(tostring(complete), tostring(ready)))

    local poiFn = _G["QuestPOIGetIconInfo"]
    if poiFn then
        local _, px, py = poiFn(questID)
        line("QuestPOIGetIconInfo", px and pMap, px, py)
    else
        p("  QuestPOIGetIconInfo  |cff888888(API absent)|r")
    end

    if C_QuestLog and C_QuestLog.GetQuestsOnMap and pMap then
        local hit
        for _, e in ipairs(C_QuestLog.GetQuestsOnMap(pMap) or {}) do
            if e.questID == questID then hit = e; break end
        end
        if hit then line("GetQuestsOnMap", pMap, hit.x, hit.y)
        else p("  GetQuestsOnMap       |cff888888(quest not listed on this map)|r") end
    else
        p("  GetQuestsOnMap       |cff888888(API absent)|r")
    end

    local W = ns:GetSubsystem("ChainGuideWaypoint")
    if logIdx then
        p("  => WINNER:           super-track the quest -> Blizzard's live objective / turn-in POI"
          .. (TomTom and " (+ TomTom pin at the live objective, or turn-in via GetQuestsOnMap)" or ""))
    elseif W and W.Resolve then
        line("=> WINNER", W:Resolve(questID))
    end
end

function Options:DumpAutoQuestPopups()
    local function p(s) print("|cffEBB706EQ AutoPopup|r " .. s) end

    local function has(name) return _G[name] and "yes" or "no" end
    p(("API: GetNumAutoQuestPopUps=%s GetAutoQuestPopUp=%s RemoveAutoQuestPopUp=%s"):format(
        has("GetNumAutoQuestPopUps"), has("GetAutoQuestPopUp"), has("RemoveAutoQuestPopUp")))
    p(("API: ShowQuestOffer=%s ShowQuestComplete=%s"):format(
        has("ShowQuestOffer"), has("ShowQuestComplete")))
    p(("API (C_): C_QuestLog.GetNumAutoQuestPopUps=%s"):format(
        (C_QuestLog and C_QuestLog.GetNumAutoQuestPopUps) and "yes" or "no"))

    local getNum = _G.GetNumAutoQuestPopUps
                   or (C_QuestLog and C_QuestLog.GetNumAutoQuestPopUps)
    local getPop = _G.GetAutoQuestPopUp
                   or (C_QuestLog and C_QuestLog.GetAutoQuestPopUp)
    if not (getNum and getPop) then
        p("no usable GetNumAutoQuestPopUps/GetAutoQuestPopUp — engine API moved or unavailable")
        return
    end

    local n = getNum() or 0
    p(("active popups: %d"):format(n))
    for i = 1, n do
        local questID, popUpType = getPop(i)
        local title = questID and (
            (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
            or (QuestUtils_GetQuestName and QuestUtils_GetQuestName(questID)))
        p(("  [%d] questID=%s type=%q title=%q"):format(
            i, tostring(questID), tostring(popUpType), tostring(title or "?")))
    end
    if n == 0 then
        p("none right now — run this while a 'Quest Discovered!'/'Quest Complete!' box is up")
    end
end

function Options:DumpWorldQuestSources()
    local function info(line) print("|cffEBB706EQ WQ:|r " .. line) end
    local function quest(qid, suffix)
        local title = (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID
                       and C_TaskQuest.GetQuestInfoByQuestID(qid))
                      or (C_QuestLog and C_QuestLog.GetTitleForQuestID
                          and C_QuestLog.GetTitleForQuestID(qid))
                      or "?"
        return ("    [%d] %s%s"):format(qid, title, suffix or "")
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapInfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    info(("player map: %s (id %s)"):format(mapInfo and mapInfo.name or "?", tostring(mapID)))

    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches then
        local n = C_QuestLog.GetNumWorldQuestWatches() or 0
        info(("GetNumWorldQuestWatches: %d"):format(n))
        for i = 1, n do
            local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if qid then print(quest(qid)) end
        end
    end

    local Watch = ns:GetSubsystem("WQWatchPersist")
    if Watch and Watch.GetTrackedQuests then
        local list = Watch:GetTrackedQuests() or {}
        info(("WQWatchPersist:GetTrackedQuests: %d"):format(#list))
        for _, qid in ipairs(list) do print(quest(qid)) end
    end

    local taskFn = C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID)
    info(("TaskQuest API: %s"):format(
        (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and "GetQuestsOnMap")
        or (C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID and "GetQuestsForPlayerByMapID (deprecated)")
        or "none available"))
    if taskFn and mapID then
        local m, depth = mapID, 0
        while m and depth < 5 do
            local list = taskFn(m) or {}
            local mi = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
            info(("TaskQuest@map %d (%s): %d entries"):format(m, mi and mi.name or "?", #list))
            for i = 1, #list do
                local q = list[i]
                local qid = q and (q.questId or q.questID)
                if qid then
                    print(quest(qid, q.inProgress and "  |cff44ff44(inProgress)|r" or "  |cff666666(idle)|r"))
                    if q.inProgress and C_QuestLog and C_QuestLog.GetQuestObjectives then
                        local objs = C_QuestLog.GetQuestObjectives(qid) or {}
                        if #objs == 0 then
                            print("        |cff999999(no objectives loaded yet)|r")
                        else
                            for k = 1, #objs do
                                local o = objs[k]
                                print(("        - %s%s"):format(
                                    o.text or "?",
                                    o.finished and "  |cff44ff44[done]|r" or ""))
                            end
                        end
                    end
                end
            end
            m = mi and mi.parentMapID
            depth = depth + 1
        end
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        info(("QuestLog entries: %d"):format(n))
        for i = 1, n do
            local qi = C_QuestLog.GetInfo(i)
            if qi and qi.questID and not qi.isHeader and not qi.isHidden then
                local flags = {}
                if qi.isTask    then flags[#flags + 1] = "task"    end
                if qi.isBounty  then flags[#flags + 1] = "bounty"  end
                if qi.isOnMap   then flags[#flags + 1] = "onMap"   end
                if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(qi.questID) then
                    flags[#flags + 1] = "wq"
                end
                if C_QuestLog.GetQuestWatchType
                   and C_QuestLog.GetQuestWatchType(qi.questID) then
                    flags[#flags + 1] = "watched"
                end
                if #flags > 0 then
                    print(("    [%d] %s  |cff5c9eff{%s}|r"):format(
                        qi.questID, qi.title or "?", table.concat(flags, ",")))
                end
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetActiveThreatMaps then
        local maps = C_QuestLog.GetActiveThreatMaps() or {}
        info(("GetActiveThreatMaps: %d"):format(#maps))
        for _, m in ipairs(maps) do print("    map " .. tostring(m)) end
    end
end
