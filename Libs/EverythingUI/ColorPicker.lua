local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local CLASS_BUTTON_W = 90
local SWATCH_INSET = 2
local CLEAR_GAP = 8

-- One picker serves every family addon, so its session state lives in lib.shared, where a newer
-- copy loading later finds it rather than starting over.
local state = lib.shared.colorPicker or {}
lib.shared.colorPicker = state

-- Which way the opacity control reads is a property of the CLIENT, so it is settled once per
-- session rather than per swatch. nil means no open has produced an unambiguous reading yet,
-- and latching false there would be a wrong answer rather than an absent one.
-- That answer is state.alphaInverted, absent until an open settles it.

-- An alpha the two conventions disagree about, for when the one being opened does not.
local PROBE_ALPHA = 0.25

-- Skipped when ElvUI is loaded, which puts its own class-color button on the picker.
local function elvUILoaded()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    return (f and f("ElvUI")) and true or false
end

local function classColor()
    local classFile = UnitClass and select(2, UnitClass("player"))
    local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r, c.g, c.b end
end

-- Installed independently of the class button, which ElvUI suppresses. These outlive a picker
-- that has closed unless something clears them, and a stale cancel would revert an already
-- committed color the next time the options window hides over an open picker.
local function ensurePickerHook()
    if state.hooked or not ColorPickerFrame then return end
    state.hooked = true
    ColorPickerFrame:HookScript("OnHide", function()
        if state.classButton then state.classButton:Hide() end
        state.apply, state.reopen, state.cancel, state.owner = nil, nil, nil, nil
    end)
end

local function ensureClassColorButton(ctx)
    if state.classButton ~= nil then return state.classButton or nil end
    -- The box is asked as well as ElvUI: ColorPPBoxA is ColorPickerPlus's name and ElvUI is
    -- one fork of it, so testing for ElvUI alone puts a second Class button on the picker.
    if elvUILoaded() or _G.ColorPPBoxA or not ColorPickerFrame then
        state.classButton = false
        return nil
    end
    local b = ctx:CreateButton(ColorPickerFrame, _G.CLASS or "Class", CLASS_BUTTON_W, function()
        local reopen = state.reopen
        if not reopen then return end
        local r, g, bl = classColor()
        if not r then return end
        -- SetColorRGB does not reliably move the 10.2.5+ picker, so re-open it seeded instead.
        -- The reopen takes an addon-space alpha. With no box calibrate latches false, so the
        -- conversion below is a no-op while the gate above holds and insurance if it widens.
        local raw = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha()
        local a = 1
        if type(raw) == "number" then
            a = state.alphaInverted and (1 - raw) or raw
        end
        reopen(r, g, bl, a)
        if state.apply then state.apply() end
    end)
    -- It hangs beside the picker over the game world, so it carries a fill of its own.
    kit.Fill(ctx, b, "surface")
    b:SetPoint("TOPLEFT", ColorPickerFrame, "TOPRIGHT", 6, -34)
    b:Hide()
    state.classButton = b
    return b
end

-- SetupColorPickerAndShow is what both shipped flavors answer - Blizzard's Classic picker
-- carries its own copy of the mixin. The field-assignment form below is the older
-- fallback. Feature-detect, never version-detect.
function Context:ShowColorPicker(r, g, b, a, hasAlpha, onChange, onCancel)
    local ctx = self
    local cp = ColorPickerFrame
    if not cp then return end
    -- Snapshotted before the first open, so Cancel after a Class click still restores the
    -- color the picker was opened on rather than the seeded class color.
    local origR, origG, origB, origA = r, g, b, a

    -- ElvUI's alpha box and the slider under it disagree about which end is opaque on 1.15.9:
    -- a slider at 0.85 shows 15, and its Class button writes 0 meaning opaque, which this addon
    -- stored as transparent. Whether Blizzard or ElvUI has it backwards is UNMEASURED.

    -- The alpha the picker addon's box is SHOWING, as a fraction. nil covers a box that is
    -- absent, unreadable, or reporting a percentage outside 0 to 100.
    local function shownAlpha()
        local box = _G.ColorPPBoxA
        local pct = box and box.GetText and tonumber(box:GetText())
        if pct and pct >= 0 and pct <= 100 then return pct / 100 end
        return nil
    end

    local function rawAlpha()
        if cp.GetColorAlpha then return cp:GetColorAlpha() end
        if OpacitySliderFrame then return OpacitySliderFrame:GetValue() end
        return nil
    end

    local function apply()
        local nr, ng, nb = cp:GetColorRGB()
        local na = 1
        if hasAlpha then
            local raw = rawAlpha()
            if type(raw) == "number" then
                na = state.alphaInverted and (1 - raw) or raw
            end
        end
        onChange(nr, ng, nb, na)
    end
    -- onCancel restores the caller's PREVIOUS value. Falling back to the seeded channels
    -- is wrong when there was no value to begin with: an unset color seeds white, so
    -- Cancel would write white into a profile the user never edited.
    local function cancel()
        if onCancel then onCancel() else onChange(origR, origG, origB, origA) end
    end

    -- The control's own value for an addon-space alpha. Once the convention is known the seed
    -- goes in right way round, which is what spares every later open a corrective write.
    local function controlValue(v)
        if state.alphaInverted then return 1 - v end
        return v
    end

    -- Seeding is not a user gesture and must not commit. ElvUI defers an opacityFunc on any
    -- write that crosses a percent boundary, which stores a color the user never picked.
    local function setControl(v)
        local fn = cp.opacityFunc
        cp.opacityFunc = nil
        OpacitySliderFrame:SetValue(v)
        cp.opacityFunc = fn
    end

    -- Settles state.alphaInverted on the first open that can answer. No box at all is taken as
    -- the game's own picker. A reading at an alpha near 0.5 cannot tell the two conventions apart,
    -- so it probes where they differ rather than guessing.
    local function calibrate(na)
        if state.alphaInverted ~= nil or not (hasAlpha and OpacitySliderFrame) then return end
        if not _G.ColorPPBoxA then state.alphaInverted = false return end
        local shown = shownAlpha()
        if not shown then return end
        local inverted = math.abs(shown - (1 - na)) < 0.01
        local straight = math.abs(shown - na) < 0.01
        if inverted ~= straight then
            state.alphaInverted = inverted
            return
        end
        setControl(PROBE_ALPHA)
        local probed = shownAlpha()
        if not probed then return end
        inverted = math.abs(probed - (1 - PROBE_ALPHA)) < 0.01
        straight = math.abs(probed - PROBE_ALPHA) < 0.01
        -- A probe fitting both conventions or neither is no answer, so the flag stays unset.
        if inverted ~= straight then state.alphaInverted = inverted end
    end

    local function openWith(nr, ng, nb, na)
        -- Re-seeding a picker that is still open skips OnShow, which is where BOTH flavors load
        -- the opacity control - so it commits the PREVIOUS swatch's alpha, can leave an alpha
        -- picker with no opacity control at all, and leaves the calibration below reading stale.
        if cp:IsShown() then cp:Hide() end
        if cp.SetupColorPickerAndShow then
            cp:SetupColorPickerAndShow({
                r = nr, g = ng, b = nb,
                opacity = controlValue(na), hasOpacity = hasAlpha and true or false,
                swatchFunc = apply, opacityFunc = apply, cancelFunc = cancel,
            })
        else
            cp.func, cp.opacityFunc, cp.cancelFunc = apply, apply, cancel
            cp.hasOpacity = hasAlpha and true or false
            cp.opacity = controlValue(na)
            cp:SetColorRGB(nr, ng, nb)
            cp:Hide()
            cp:Show()
        end
        calibrate(na)
        -- The first open of a session seeds before it can know which way the control reads, and
        -- calibrating may have moved it to probe. This is what puts it where the answer says.
        if hasAlpha and OpacitySliderFrame and OpacitySliderFrame:GetValue() ~= controlValue(na) then
            setControl(controlValue(na))
        end
        -- Set after the open: the re-seed Hide above and the legacy branch both fire the OnHide
        -- hook that clears these. The owner is the window that closes this picker with itself.
        state.apply, state.reopen, state.cancel, state.owner = apply, openWith, cancel, ctx._window
        ensurePickerHook()
        local classBtn = ensureClassColorButton(ctx)
        if classBtn then classBtn:Show() end
    end

    openWith(r, g, b, a)
end

-- A labelled row: the label on the left and the swatch at the right end, where a slider's value
-- ends. Its own width fits label, Clear and swatch, so a tab can hang it at the right end of a
-- checkbox's row as that box's color.
function Context:CreateColorPicker(content, label, getter, setter, tooltip, hasAlpha, onClear)
    local sp = lib.tokens.spacing
    local ctx = self
    local clearLabel = self.opts.labels.clear
    if onClear and not clearLabel then
        error("EverythingUI: a clearable color picker needs opts.labels.clear", 2)
    end
    local holder = CreateFrame("Frame", nil, content)
    holder:SetHeight(sp.fieldHeight)
    holder._euiFill = true

    local text = kit.Text(self, holder, "label")
    text:SetPoint("LEFT")
    text:SetWordWrap(false)
    text:SetText(label)
    holder.label = text

    local swatch = CreateFrame("Button", nil, holder)
    swatch:SetSize(sp.swatchWidth, sp.swatchHeight)
    swatch:SetPoint("RIGHT")
    kit.Fill(self, swatch, "input")
    kit.Edge(self, swatch, "borderStrong")
    -- The color is drawn with its own alpha, so it needs something opaque behind it or a
    -- translucent swatch composites against the card under it and reads washed out.
    local underlay = swatch:CreateTexture(nil, "BORDER")
    underlay:SetPoint("TOPLEFT", SWATCH_INSET, -SWATCH_INSET)
    underlay:SetPoint("BOTTOMRIGHT", -SWATCH_INSET, SWATCH_INSET)
    underlay:SetColorTexture(0, 0, 0, 1)
    local tex = swatch:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", SWATCH_INSET, -SWATCH_INSET)
    tex:SetPoint("BOTTOMRIGHT", -SWATCH_INSET, SWATCH_INSET)
    kit.Highlight(self, swatch)

    local clear
    local function paint()
        local c = getter()
        local isSet = (c and c.r ~= nil) and true or false
        if isSet then
            tex:SetColorTexture(c.r, c.g or 0, c.b or 0, c.a or 1)
        else
            tex:SetColorTexture(ctx:Color("track"))
        end
        if clear then clear:SetShown(isSet) end
    end

    -- Only clearable pickers get the button, so an unset swatch stays distinguishable
    -- from a deliberately black one.
    local width = (text:GetStringWidth() or 0) + CLEAR_GAP + sp.swatchWidth
    if onClear then
        clear = self:CreateButton(holder, clearLabel, nil, function()
            onClear()
            paint()
        end, nil, "ghost")
        clear:SetPoint("RIGHT", swatch, "LEFT", -CLEAR_GAP, 0)
        -- Room for Clear is kept while it is hidden, so the label does not move when it shows.
        width = width + clear:GetWidth() + CLEAR_GAP
    end
    holder:SetWidth(width)
    paint()

    swatch:SetScript("OnClick", function()
        local c = getter()
        -- Copied rather than aliased: the setter may hand this same table straight back.
        local prev = c and { r = c.r, g = c.g, b = c.b, a = c.a } or nil
        local function commit(v)
            setter(v)
            paint()
        end
        c = c or {}
        ctx:ShowColorPicker(c.r or 1, c.g or 1, c.b or 1, c.a or 1, hasAlpha,
            function(nr, ng, nb, na) commit({ r = nr, g = ng, b = nb, a = na }) end,
            function() commit(prev) end)
    end)

    -- The row is hoverable across its whole width for the tooltip, and the swatch sits at the far
    -- end of it, so the click has to work across the gap too.
    holder:EnableMouse(true)
    holder:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then swatch:Click() end
    end)

    holder.button  = swatch
    holder.clear   = clear
    holder.paint   = paint
    holder.Refresh = paint
    if tooltip then self:AttachTooltip(holder, label, tooltip) end
    content._controls[#content._controls + 1] = holder
    return holder
end
