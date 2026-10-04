local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local BUTTON_PADDING = 14
local BOTTOM_PADDING = 24
local DEFAULT_WIDTH = 400
local SLIDER_HIT = 16
local DIM_ALPHA = 0.4
local MAX_SEGMENTS = 3
local SATELLITE_GAP = 16
-- The widest reach any of the host's satellite groups used before they were measured, so a
-- failed measure cannot land a satellite further left than it already sat.
local SATELLITE_FLOOR = 192
local PICKER_GAP = 8
local ICON_SIZE = 16
local TEXT_GAP = 4
local BULLET_INDENT = 12

local function stripEscapes(s)
    if not s then return "" end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Tabs anchor their own cards, so they need the same gaps the library draws with.
function Context:Spacing(name)
    local v = lib.tokens.spacing[name]
    if v == nil then
        error(("EverythingUI: no spacing named %s"):format(tostring(name)), 2)
    end
    return v
end

function Context:AttachTooltip(frame, title, body)
    if not frame or (not title and not body) then return end
    title = (title and title ~= "") and stripEscapes(title) or nil

    if frame.GetObjectType and frame:GetObjectType() == "FontString" then
        local overlay = CreateFrame("Frame", nil, frame:GetParent())
        overlay:SetAllPoints(frame)
        frame = overlay
    elseif frame.label and frame.GetObjectType and frame:GetObjectType() == "CheckButton" then
        local w = frame.label:GetStringWidth() or 0
        if w > 0 then frame:SetHitRectInsets(0, -(w + lib.tokens.spacing.checkboxGap), 0, 0) end
    end

    local targets = { frame }
    if frame.slider then targets[#targets + 1] = frame.slider end
    if frame.button then targets[#targets + 1] = frame.button end

    local getTip = self.opts.tooltip
    -- Placed off the control's own frame whichever part is hovered, so a slider's track and its
    -- label open the tooltip in one place rather than two.
    local anchor = frame
    for _, t in ipairs(targets) do
        if t.EnableMouse then t:EnableMouse(true) end
        t:HookScript("OnEnter", function() kit.ShowTip(getTip, anchor, title, body) end)
        t:HookScript("OnLeave", function() getTip():Hide() end)
    end
end

local BUTTON_STYLES = { secondary = true, primary = true, ghost = true, danger = true }

function Context:CreateButton(content, label, width, onClick, tooltip, style)
    style = style or "secondary"
    if not BUTTON_STYLES[style] then
        error(("EverythingUI: no button style named %s"):format(tostring(style)), 2)
    end
    local b = CreateFrame("Button", nil, content)
    b:SetHeight(lib.tokens.spacing.buttonHeight)
    local text = kit.Text(self, b, "value", (style == "primary" and "accentText") or (style == "danger" and "danger") or "navText")
    text:SetPoint("CENTER")
    text:SetText(label)
    b.text = text
    if style == "primary" then
        kit.Fill(self, b, "accent")
    elseif style == "secondary" then
        kit.Edge(self, b, "navText")
    elseif style == "danger" then
        kit.Edge(self, b, "danger")
    end
    kit.Highlight(self, b, style == "danger" and "dangerSoft" or nil)
    -- Keeps btn:SetText() working without a Blizzard template. Without it a caller relabeling a
    -- button would fail silently.
    b.SetText = function(_, s) text:SetText(s) end
    if width then
        b:SetWidth(width)
    else
        local function fit()
            -- `<= 0` as well as nil, because 0 is truthy in Lua and an unmeasured string would size
            -- the button to its padding alone.
            local w = text:GetStringWidth()
            if not w or w <= 0 then w = 90 end
            b:SetWidth(w + BUTTON_PADDING * 2)
        end
        fit()
        -- Listed on its parent so kit.Refit can size it again once it is on screen.
        b.Fit = fit
        local fits = content._euiFit or {}
        content._euiFit = fits
        fits[#fits + 1] = b
    end
    if onClick then b:SetScript("OnClick", onClick) end
    if tooltip then self:AttachTooltip(b, label, tooltip) end
    return b
end

-- Every helper returns an UNANCHORED frame. A card stacks the rows it is given and the tab
-- anchors everything else, including the cards, with its own SetPoint chain.
function Context:CreateHeading(content, text)
    local fs = kit.Text(self, content, "groupLabel")
    fs:SetText(text)
    return fs
end

-- A line of text in one of the type styles, such as a hint, or the name on a list row.
function Context:CreateText(content, text, style)
    local fs = kit.Text(self, content, style or "label")
    fs:SetText(text)
    return fs
end

-- Each line spans the block from its indent, so it wraps at the block's width, and the next line
-- starts under the height its text measures now.
local function measureBlock(block)
    local y = 0
    for i, line in ipairs(block._lines) do
        if i > 1 then y = y + (line.gap or TEXT_GAP) end
        local x = line.indent + (line.bullet and BULLET_INDENT or 0)
        if line.bullet then
            line.bullet:ClearAllPoints()
            line.bullet:SetPoint("TOPLEFT", block, "TOPLEFT", line.indent, -y)
        end
        line.fs:ClearAllPoints()
        -- Anchored across the block before its height is read: a wrapping string reports its
        -- wrapped height only once it has a width.
        line.fs:SetPoint("TOPLEFT", block, "TOPLEFT", x, -y)
        line.fs:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, -y)
        local h = line.fs:GetStringHeight()
        -- `<= 0` as well as nil, because 0 is truthy and a string not laid out yet would put the
        -- next line on top of it.
        if not h or h <= 0 then h = line.size end
        y = y + h
    end
    block:SetHeight(math.max(1, y))
    return y
end

-- A line Barlow cannot draw takes the client's font whole (decision 14), decided once when it is added.
local function lineString(ctx, block, text, style, color)
    if kit.NeedsClientFont(text) then
        local fs = kit.DataText(block)
        fs:SetTextColor(ctx:Color(color or lib.tokens.typography[style].color))
        return fs
    end
    return kit.Text(ctx, block, style, color)
end

-- opts.indent moves a line in, opts.gap is the space above it, opts.color overrides its style's
-- color, and opts.bullet hangs that string at the indent with the text wrapping clear of it.
local function addLine(block, text, style, opts)
    opts = opts or {}
    style = style or "label"
    local ctx = block._ctx
    local fs = lineString(ctx, block, text, style, opts.color)
    fs:SetWordWrap(true)
    fs:SetText(text)
    local line = { fs = fs, indent = opts.indent or 0, gap = opts.gap,
                   size = lib.tokens.typography[style].size }
    if opts.bullet then
        line.bullet = kit.Text(ctx, block, style, opts.color)
        line.bullet:SetText(opts.bullet)
    end
    block._lines[#block._lines + 1] = line
    measureBlock(block)
    return fs
end

-- Wrapped text, line under line, sized to what the text measures. In a card row added with
-- { fitHeight = true } it is measured again each time the card is laid out, which kit.Refit does
-- once the tab is on screen, because a wrapped height read while a tab is built can be wrong.
function Context:CreateTextBlock(content)
    local block = CreateFrame("Frame", nil, content)
    block:SetSize(DEFAULT_WIDTH, 1)
    block._euiFill = true
    block._ctx, block._lines = self, {}
    block.AddLine, block.Measure = addLine, measureBlock
    return block
end

-- A square button showing one of the library's icons: navText, borderStrong while the button is
-- disabled, and the hover tint. flip turns the icon upside down, so one chevron serves both ways.
function Context:CreateIconButton(parent, icon, size, flip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    local path = self:Texture(icon)
    b:SetNormalTexture(path)
    b:SetDisabledTexture(path)
    for _, t in ipairs({ b:GetNormalTexture(), b:GetDisabledTexture() }) do
        t:ClearAllPoints()
        t:SetPoint("CENTER")
        t:SetSize(ICON_SIZE, ICON_SIZE)
        if flip then t:SetTexCoord(0, 1, 1, 0) end
    end
    b:GetNormalTexture():SetVertexColor(self:Color("navText"))
    b:GetDisabledTexture():SetVertexColor(self:Color("borderStrong"))
    kit.Highlight(self, b)
    return b
end

function Context:CreateCheckbox(content, label, getter, setter, tooltip, icon)
    if icon ~= nil and type(icon) ~= "string" then
        error("EverythingUI: CreateCheckbox's icon must be a texture path", 2)
    end
    local sp = lib.tokens.spacing
    local ctx = self
    local cb = CreateFrame("CheckButton", nil, content)
    cb:SetSize(sp.checkbox, sp.checkbox)
    local fill = cb:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints()
    local edges = kit.Edge(self, cb, "borderStrong")
    local mark = kit.Icon(self, cb, "check", sp.checkbox, "accentText")
    mark:SetPoint("CENTER")
    kit.Highlight(self, cb)

    cb.label = kit.Text(self, cb, "label")
    cb.label:SetPoint("LEFT", cb, "RIGHT", sp.checkboxGap, 0)
    cb.label:SetText(label)
    if icon then
        cb.icon = cb:CreateTexture(nil, "ARTWORK")
        cb.icon:SetSize(ICON_SIZE, ICON_SIZE)
        cb.icon:SetPoint("LEFT", cb, "RIGHT", sp.checkboxGap, 0)
        cb.icon:SetTexture(icon)
        cb.label:SetPoint("LEFT", cb.icon, "RIGHT", sp.checkboxGap, 0)
    end

    -- Painted by hand rather than through a checked texture, because a checked box changes
    -- its fill and its edge as well as showing the mark.
    local function paint()
        local on = cb:GetChecked() and true or false
        fill:SetColorTexture(ctx:Color(on and "accent" or "input"))
        for _, line in ipairs(edges) do line:SetColorTexture(ctx:Color(on and "accent" or "borderStrong")) end
        mark:SetShown(on)
    end
    -- A tab that puts the box back by hand, after a cancelled dialog, has to repaint it too.
    local setChecked = cb.SetChecked
    cb.SetChecked = function(btn, v)
        setChecked(btn, v)
        paint()
    end

    -- Widened here rather than only in AttachTooltip, or a checkbox built without a tooltip
    -- has a label the mouse cannot click while its neighbors' labels work.
    local labelW = cb.label:GetStringWidth() or 0
    if labelW > 0 then cb:SetHitRectInsets(0, -(labelW + sp.checkboxGap), 0, 0) end
    cb:SetChecked(getter() and true or false)
    -- No repaint of the host's UI here. Every setter that needs one does it itself, and an
    -- unconditional one rebuilt the host's whole feed twice per click.
    cb:SetScript("OnClick", function(btn)
        paint()
        setter(btn:GetChecked() and true or false)
    end)
    cb.Refresh = function(btn) btn:SetChecked(getter() and true or false) end
    if tooltip then self:AttachTooltip(cb, label, tooltip) end
    -- After the tooltip, which widens the click area by the label alone.
    if icon then cb:SetHitRectInsets(0, -(labelW + ICON_SIZE + sp.checkboxGap * 2), 0, 0) end
    content._controls[#content._controls + 1] = cb
    return cb
end

-- Decimals follow the step, so a 0.05 step reads 1.05 and a step of 1 reads 16.
local function chooseFormat(s)
    if not s or s >= 1 then return "%d" end
    return "%." .. math.max(1, math.ceil(-math.log10(s))) .. "f"
end

-- A labelled row: the label in its column, and the control from the column's edge to the
-- right. SetLabelWidth moves the control, which is how AlignLabelColumn lines a group up.
local function labelledHolder(ctx, content, label)
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(DEFAULT_WIDTH, lib.tokens.spacing.fieldHeight)
    holder._euiFill = true
    local text = kit.Text(ctx, holder, "label")
    text:SetPoint("LEFT")
    text:SetWordWrap(false)
    text:SetText(label or "")
    holder.label = text
    return holder
end

local function columnEdge(label, w)
    if not label then return 0 end
    return w + lib.tokens.spacing.controlGap
end

-- A label in the label column and a line of text after it, for a two-column list such as a command
-- and what it does. AlignLabelColumn lines the second column up across the card.
function Context:CreateTextRow(content, label, text)
    local holder = labelledHolder(self, content, label)
    local value = kit.Text(self, holder, "label")
    value:SetPoint("RIGHT")
    value:SetWordWrap(false)
    value:SetText(text or "")
    holder.text = value
    holder.SetLabelWidth = function(_, w)
        value:SetPoint("LEFT", holder, "LEFT", columnEdge(label, w), 0)
    end
    holder:SetLabelWidth(lib.tokens.spacing.labelColumn)
    return holder
end

-- Built by hand rather than from OptionsSliderTemplate, whose name and children have
-- moved between flavors. This works everywhere and needs no template at all.
function Context:CreateSlider(content, label, minV, maxV, step, getter, setter, tooltip, format)
    if format ~= nil and type(format) ~= "function" then
        error("EverythingUI: CreateSlider's format must be a function", 2)
    end
    local sp = lib.tokens.spacing
    local holder = labelledHolder(self, content, label)

    local value = kit.Text(self, holder, "value")
    value:SetPoint("RIGHT")
    value:SetWidth(sp.valueColumn)
    value:SetJustifyH("RIGHT")

    local valueFmt = chooseFormat(step)
    -- A range reaching below zero is an offset, so a positive value carries its sign.
    local function formatValue(v)
        if format then return format(v) end
        local s = valueFmt:format(v)
        if minV < 0 and (tonumber(s) or 0) > 0 then s = "+" .. s end
        return s
    end

    local slider = CreateFrame("Slider", nil, holder)
    slider:SetOrientation("HORIZONTAL")
    slider:SetHeight(SLIDER_HIT)
    slider:SetPoint("RIGHT", holder, "RIGHT", -(sp.valueColumn + sp.controlGap), 0)
    slider:SetMinMaxValues(minV, maxV)
    slider:SetValueStep(step)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture(self:Texture("slider-thumb"))
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(sp.thumbWidth, sp.thumbHeight)
    thumb:SetVertexColor(self:Color("text"))
    -- Above the fill, which ends at the thumb's center and would otherwise cross it.
    thumb:SetDrawLayer("OVERLAY")

    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    track:SetHeight(sp.trackHeight)
    track:SetColorTexture(self:Color("track"))
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetHeight(sp.trackHeight)
    fill:SetColorTexture(self:Color("accent"))

    holder.SetLabelWidth = function(_, w)
        slider:SetPoint("LEFT", holder, "LEFT", columnEdge(label, w), 0)
    end
    holder:SetLabelWidth(sp.labelColumn)

    -- Refresh runs on every tab view. Without this guard SetValue would clamp a saved
    -- value that sits outside the range and dispatch the clamped result straight back
    -- to setter, rewriting a profile the user never touched.
    local suppress = false

    slider:SetValue(getter() or minV)
    value:SetText(formatValue(slider:GetValue()))
    slider:SetScript("OnValueChanged", function(_, v)
        local stepped = step and (math.floor((v - minV) / step + 0.5) * step + minV) or v
        value:SetText(formatValue(stepped))
        if not suppress then setter(stepped) end
    end)

    -- A caller's format can end in a word, such as "No limit", whose translation outruns the column,
    -- so the readout is as wide as the wider of the two ends, measured again once the tab is on screen.
    if format then
        local function fitValue()
            local shown, widest = value:GetText(), sp.valueColumn
            value:SetWidth(0)
            for _, v in ipairs({ minV, maxV }) do
                value:SetText(format(v))
                local w = value:GetStringWidth() or 0
                if w > widest then widest = math.ceil(w) end
            end
            value:SetText(shown)
            value:SetWidth(widest)
            slider:SetPoint("RIGHT", holder, "RIGHT", -(widest + sp.controlGap), 0)
        end
        fitValue()
        holder.Fit = fitValue
        local fits = content._euiFit or {}
        content._euiFit = fits
        fits[#fits + 1] = holder
    end

    holder.slider = slider
    holder.value = value
    holder.Refresh = function()
        suppress = true
        slider:SetValue(getter() or minV)
        suppress = false
        value:SetText(formatValue(slider:GetValue()))
    end

    if tooltip then self:AttachTooltip(holder, label, tooltip) end
    content._controls[#content._controls + 1] = holder
    return holder, slider
end

-- options is a list of { value =, label = } pairs. The value is what reaches the setter,
-- so a translated label can never end up in the profile. Three choices or fewer that fit the
-- row draw as a segmented control. More, or a translation too wide for the row, draw as a
-- dropdown, which hands the setter the same values.
function Context:CreateRadioGroup(content, label, options, getter, setter, maxWidth, pad,
                                  tipTitle, tipBody)
    local sp = lib.tokens.spacing
    local ctx = self
    if #options > MAX_SEGMENTS then
        return self:CreateDropdown(content, label, options, getter, setter, tipBody)
    end

    local holder = labelledHolder(self, content, label)
    local inset = sp.border + sp.segmentGap
    local track = CreateFrame("Frame", nil, holder)
    track:SetHeight(sp.segmentHeight + inset * 2)
    kit.Fill(self, track, "input")
    kit.Edge(self, track, "inputBorder")

    local buttons = {}
    local function paint(active)
        for _, b in ipairs(buttons) do
            local on = (b.value == active)
            b.fill:SetShown(on)
            b.txt:SetTextColor(ctx:Color(on and "accentText" or "navText"))
        end
    end

    local segPad = pad or sp.segmentPadding
    local x = inset
    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, track)
        btn:SetHeight(sp.segmentHeight)
        btn.fill = kit.Fill(self, btn, "accent")
        kit.Highlight(self, btn)
        btn.txt = kit.Text(self, btn, "segment")
        btn.txt:SetPoint("CENTER")
        btn.txt:SetText(opt.label)
        -- `<= 0` because 0 is truthy, and an unmeasured label would draw a sliver of a button.
        local tw = btn.txt:GetStringWidth()
        if not tw or tw <= 0 then tw = 40 end
        local w = tw + segPad * 2
        btn:SetWidth(w)
        btn:SetPoint("LEFT", track, "LEFT", x, 0)
        btn.value = opt.value
        btn:SetScript("OnClick", function(b)
            if setter then setter(b.value) end
            paint(b.value)
        end)
        -- A per-option tip titles itself with that option's own label. Without one the
        -- group's shared tooltip is used, which is what every existing caller passes.
        if opt.tip then
            self:AttachTooltip(btn, opt.label, opt.tip)
        elseif tipTitle or tipBody then
            self:AttachTooltip(btn, tipTitle, tipBody)
        end
        x = x + w + ((i < #options) and sp.segmentGap or 0)
        buttons[#buttons + 1] = btn
    end
    local natural = x + inset
    track:SetWidth(natural)

    local avail = (content.GetWidth and content:GetWidth() or 0) - sp.rowPadding * 2
        - columnEdge(label, sp.labelColumn)
    if avail <= 0 then avail = maxWidth or natural end
    if natural > avail then
        -- Too wide for the row in this language, so the choice is offered as a list instead.
        holder:Hide()
        return self:CreateDropdown(content, label, options, getter, setter, tipBody)
    end

    holder.SetLabelWidth = function(_, w)
        track:SetPoint("LEFT", holder, "LEFT", columnEdge(label, w), 0)
    end
    holder:SetLabelWidth(sp.labelColumn)
    holder.buttons = buttons

    paint(getter and getter())
    holder.Refresh = function() paint(getter and getter()) end
    content._controls[#content._controls + 1] = holder
    return holder
end

-- Dims a control whose master switch is off. Deliberately does NOT disable the mouse:
-- AttachTooltip's hover lives on these same frames, and a control that cannot say why it is
-- grayed is worse than one that is simply lit. The value stays editable and takes effect
-- when its master is switched back on.
function Context:SetDependent(control, on)
    if control then control:SetAlpha(on and 1 or DIM_ALPHA) end
end

-- A checkbox frame is only its box, and its label hangs OUTSIDE it. SetHitRectInsets widens
-- the mouse rect and never GetWidth, so the frame's right edge says nothing about where its
-- text ends, and anything placed beside one at a hardcoded offset collides the moment a label
-- outruns the number that was guessed. A translation does that on every flavor - "Show header
-- bars" is about half again as wide in French and Russian as in English.
--
-- Each argument is a { checkbox, satellite } pair. They land in ONE column past the widest
-- label in the group, so a short label does not pull its own satellite left out of line.
function Context:AlignSatelliteColumn(...)
    local gap = lib.tokens.spacing.checkboxGap
    local rows = { ... }
    local reach = 0
    for _, row in ipairs(rows) do
        local cb  = row[1]
        local lbl = cb and cb.label
        local w   = (lbl and lbl:GetStringWidth()) or 0
        -- The label gap is the checkbox's own, and the box width is read off the frame rather
        -- than written here again, so neither can drift from CreateCheckbox.
        if w > 0 then
            local r = (cb:GetWidth() or 0) + gap + w
            if r > reach then reach = r end
        end
    end
    -- A string that has not been laid out answers 0, and 0 is truthy, so this has to test the
    -- value.
    if reach <= 0 then reach = SATELLITE_FLOOR end

    for _, row in ipairs(rows) do
        row[2]:ClearAllPoints()
        row[2]:SetPoint("LEFT", row[1], "LEFT", reach + SATELLITE_GAP, 0)
    end
end

-- Lines a run of pickers up as a table: labels flush left, every swatch in one column just
-- past the widest label. Right-aligning each label off its own swatch instead straightens the
-- swatches but leaves the labels ragged.
function Context:AlignPickerColumn(...)
    local pickers = { ... }
    local widest = 0
    for _, p in ipairs(pickers) do
        local w = p.label:GetStringWidth() or 0
        if w > widest then widest = w end
    end
    for _, p in ipairs(pickers) do
        p.label:ClearAllPoints()
        p.label:SetPoint("LEFT", p, "LEFT", 0, 0)
        p.button:ClearAllPoints()
        p.button:SetPoint("TOP",  p, "TOP", 0, -1)
        p.button:SetPoint("LEFT", p, "LEFT", widest + PICKER_GAP, 0)
        -- A translated label can outrun the width the holder is built at, which would leave the
        -- swatch hanging past the holder's right edge.
        local need = widest + PICKER_GAP + p.button:GetWidth()
        if need > p:GetWidth() then p:SetWidth(need) end
    end
end

-- One label column for every labelled control in a group: the token's width, or the widest
-- translated label if that is wider. A dependent row starts further in, so its column is
-- shortened by the extra indent and its control stays in line with the rows above. A control
-- built with no label measures 0 here and keeps no column in its own SetLabelWidth.
function Context:AlignLabelColumn(...)
    local sp = lib.tokens.spacing
    local extra = sp.dependentIndent - sp.rowPadding
    local controls = {}
    for _, c in ipairs({ ... }) do
        if c.SetLabelWidth then controls[#controls + 1] = c end
    end
    local widest = sp.labelColumn
    for _, c in ipairs(controls) do
        local w = c.label:GetStringWidth() or 0
        if c._euiDependent then w = w + extra end
        if w > widest then widest = w end
    end
    for _, c in ipairs(controls) do
        c:SetLabelWidth(c._euiDependent and (widest - extra) or widest)
    end
    return widest
end

-- A hand-anchored column resolves nothing until the next frame, so its height is unknowable
-- at build time. Run per view rather than once per build, because the window is built at login
-- with the whole window hidden - GetTop() is nil there and a one-shot measure would leave the tab
-- unscrollable until a reload. Exposed because a tab that re-anchors its own column at runtime
-- has to re-measure without waiting for the next tab switch.
function Context:MeasureContent(content)
    C_Timer.After(0, function()
        local top = content:GetTop()
        if not top then return end
        kit.Refit(content)
        local lowest = top

        -- Regions as well as children. A FontString is not a child, so a children-only
        -- walk measures a tab whose lowest element is a heading or a label as empty.
        local function consider(o)
            if not (o and o.IsShown and o:IsShown() and o.GetBottom) then return end
            local bottom = o:GetBottom()
            if bottom and bottom < lowest then lowest = bottom end
        end
        for _, child  in ipairs({ content:GetChildren() }) do consider(child) end
        for _, region in ipairs({ content:GetRegions()  }) do consider(region) end

        content:SetHeight((top - lowest) + BOTTOM_PADDING)
    end)
end
