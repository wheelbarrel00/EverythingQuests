-- Own frame instead of StaticPopup: that system recycles a small frame pool, so our
-- insecure button handlers could taint the frame the logout/quit dialog later reuses.

local _, ns = ...

local Dialog = ns:RegisterSubsystem("Dialog", {})

local RED    = ns.Util.color.brandRed
local YELLOW = ns.Util.color.buttonYellow

local function makeButton(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(110, 26)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.10, 0.10, 0.10, 0.95)
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    b:SetBackdropBorderColor(RED[1], RED[2], RED[3], 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("CENTER")
    b.text:SetTextColor(YELLOW[1], YELLOW[2], YELLOW[3])
    b:SetScript("OnEnter", function(s) s.bg:SetColorTexture(0.18, 0.18, 0.18, 0.95) end)
    b:SetScript("OnLeave", function(s) s.bg:SetColorTexture(0.10, 0.10, 0.10, 0.95) end)
    return b
end

local function fitButton(b, label)
    b.text:SetText(label or "")
    b:SetWidth(math.max(90, math.ceil(b.text:GetStringWidth()) + 28))
end

function Dialog:_finish(accepted)
    local opts = self.opts
    if not opts then return end          -- guard double-fire (button + escape)
    self.opts = nil
    local f = self.frame
    local text = (f and f.editBox:IsShown()) and f.editBox:GetText() or nil
    if f then f:Hide() end
    if accepted then
        if opts.onAccept then opts.onAccept(text) end
    elseif opts.onCancel then
        opts.onCancel()
    end
end

function Dialog:Build()
    if self.frame then return self.frame end

    local f = CreateFrame("Frame", "EQDialog", UIParent, "BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetSize(430, 160)
    f:SetPoint("CENTER")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0, 0, 0, 0.95)
    f:SetBackdropBorderColor(RED[1], RED[2], RED[3], 1)

    f:EnableKeyboard(true)
    f:SetPropagateKeyboardInput(true)
    f:SetScript("OnKeyDown", function(frame, key)
        if key == "ESCAPE" then
            frame:SetPropagateKeyboardInput(false)
            Dialog:_finish(false)
        else
            frame:SetPropagateKeyboardInput(true)
        end
    end)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -12)
    f.title:SetTextColor(RED[1], RED[2], RED[3])

    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("TOPLEFT", 18, -40)
    f.text:SetPoint("TOPRIGHT", -18, -40)
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(3)

    f.editBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    f.editBox:SetAutoFocus(false)
    f.editBox:SetSize(340, 22)
    f.editBox:SetPoint("TOP", f.text, "BOTTOM", 0, -12)
    f.editBox:SetScript("OnEscapePressed", function() Dialog:_finish(false) end)
    f.editBox:SetScript("OnEnterPressed", function() Dialog:_finish(true) end)
    f.editBox:Hide()

    f.accept = makeButton(f)
    f.accept:SetScript("OnClick", function() Dialog:_finish(true) end)

    f.cancel = makeButton(f)
    f.cancel:SetPoint("BOTTOMRIGHT", -18, 14)
    f.cancel:SetScript("OnClick", function() Dialog:_finish(false) end)

    self.frame = f
    return f
end

function Dialog:Show(opts)
    local f = self:Build()
    -- Cancel a dialog that is still up so its callbacks are not silently dropped
    if self.opts then self:_finish(false) end
    self.opts = opts

    f.title:SetText(opts.title or "Everything Quests")
    f.text:SetText(opts.text or "")

    fitButton(f.accept, opts.button1 or "OK")
    if opts.button2 then
        fitButton(f.cancel, opts.button2)
        f.cancel:Show()
    else
        f.cancel:Hide()
    end

    if opts.hasEditBox then
        f.editBox:Show()
        f.editBox:SetMaxLetters(opts.maxLetters or 0)
        f.editBox:SetText(opts.editBoxText or "")
        f.editBox:SetCursorPosition(0)
        f.editBox:SetFocus()
        if opts.highlightEditBox then f.editBox:HighlightText() end
    else
        f.editBox:Hide()
        f.editBox:ClearFocus()
    end

    f.accept:ClearAllPoints()
    if opts.button2 then
        f.accept:SetPoint("BOTTOMLEFT", 18, 14)
    else
        f.accept:SetPoint("BOTTOM", 0, 14)
    end

    local h = 46 + math.max(18, f.text:GetStringHeight())
              + (opts.hasEditBox and 34 or 0) + 50
    f:SetHeight(h)

    f:Show()
    f:Raise()
end
