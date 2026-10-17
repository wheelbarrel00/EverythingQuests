local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

-- Hand-rolled rather than UIDropDownMenu: that was deprecated in favor of MenuUtil on
-- current retail but is still the only option on Classic, and every host loads on both.
local DEFAULT_WIDTH = 400
local PAD = 10
local POPUP_INSET = 4
local POPUP_GAP = 2
local BAR_ROOM = 12
local PREVIEW_SIZE = 14
local SWATCH_W, SWATCH_H = 60, 12
local SWATCH_GAP = 8
local SPEAKER = 20
local SPEAKER_GAP = 4
local SUFFIX_GAP = 8
-- A border sample is its own size: four EDGE_SIZE corners have to leave a visible straight run
-- between them or every edge file draws as the same corner blob.
local EDGE_W, EDGE_H, EDGE_SIZE = 28, 18, 6
-- The family's no-sound value, compared ignoring case (Cooldown Master saves "None"). Previewing
-- it can only ever be silent.
local NO_SOUND = "NONE"

local paintRows

-- One popup and one row pool serve every dropdown of every family addon for the session. Kept
-- in lib.shared, so a newer copy loading later finds the same popup rather than a second one.
local function popup(ctx)
    local shared = lib.shared
    if shared.popup then return shared.popup end
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetSize(240, 300)
    p:Hide()
    kit.Fill(ctx, p, "surface")
    p.edges = kit.Edge(ctx, p, "surfaceBorder")
    local sf, content, bar = kit.Scroll(ctx, p)
    sf:SetPoint("TOPLEFT", 1, -POPUP_INSET)
    sf:SetPoint("BOTTOMRIGHT", -1, POPUP_INSET)
    bar:SetPoint("TOPRIGHT", -3, -POPUP_INSET)
    bar:SetPoint("BOTTOMRIGHT", -3, POPUP_INSET)
    p.scroll, p.content, p.bar, p.rows, p.todo = sf, content, bar, {}, {}
    bar:HookScript("OnValueChanged", function() paintRows(p) end)
    kit.CloseOnEscape(p)

    -- A click anywhere outside the list closes it. Hooked rather than set, so the Escape
    -- handling's own OnShow hook survives.
    local closer = CreateFrame("Button", nil, UIParent)
    closer:SetAllPoints(UIParent)
    closer:SetFrameStrata("FULLSCREEN")
    closer:RegisterForClicks("AnyDown")
    closer:SetScript("OnClick", function() p:Hide() end)
    closer:Hide()
    p.closer = closer
    p:HookScript("OnShow", function() closer:Show() end)
    p:HookScript("OnHide", function()
        closer:Hide()
        local getTip = p.tooltip
        if getTip then getTip():Hide() end
    end)

    shared.popup = p
    return p
end

local function placeText(holder, left)
    local suffix = holder.suffix
    local after = suffix and (suffix:GetText() or "") ~= ""
    for _, fs in ipairs({ holder.text, holder.data }) do
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", left, 0)
        if after then
            fs:SetPoint("RIGHT", suffix, "LEFT", -SUFFIX_GAP, 0)
        else
            fs:SetPoint("RIGHT", -PAD, 0)
        end
    end
end

-- A face counts only when GetFont reads its own path back. A file that fails to load leaves the
-- string with no font at all, a path LibSharedMedia still names after its addon is gone makes
-- SetFont throw, and a face can also fail by returning false and keeping the PREVIOUS one.
local function previewFace(fs, path)
    if not path or path == "" then return false end
    return pcall(fs.SetFont, fs, path, PREVIEW_SIZE, "") and fs:GetFont() == path
end

-- SetFont in BOTH directions, because an explicit SetFont is what has to be undone and
-- SetFontObject was observed not undoing it: the shared popup's rows are pooled across every
-- dropdown, and a font list left its faces on the profile and sound lists that reused them.
-- A string Barlow cannot draw goes to the second string, which only ever has the client's font.
local function setLabel(ctx, holder, s, path, color)
    local themed, data = holder.text, holder.data
    local previewed = previewFace(themed, path)
    if not previewed then kit.Style(ctx, themed, "label") end
    local useData = not previewed and kit.NeedsClientFont(s)
    themed:SetTextColor(ctx:Color(color))
    data:SetTextColor(ctx:Color(color))
    themed:SetText(s)
    data:SetText(s)
    themed:SetShown(not useData)
    data:SetShown(useData)
end

-- Built on first use, since most lists never show a border. SetBackdrop rebuilds a NineSlice, so it
-- runs only when this frame's border changes.
local function paintEdge(holder, path)
    local edge = holder.edge
    if not edge then
        edge = CreateFrame("Frame", nil, holder, BackdropTemplateMixin and "BackdropTemplate" or nil)
        edge:SetSize(EDGE_W, EDGE_H)
        edge:SetPoint("LEFT", PAD, 0)
        holder.edge = edge
    end
    if path == "" then path = nil end
    if edge._path ~= path and edge.SetBackdrop then
        edge._path = path
        edge:SetBackdrop(path and { edgeFile = path, edgeSize = EDGE_SIZE } or nil)
        if path then edge:SetBackdropBorderColor(1, 1, 1, 1) end
    end
    edge:SetShown(path ~= nil)
end

-- One popup is shared by every dropdown, so a row that grew a swatch or a border has to give it
-- back when a plain list reuses it.
local function decorateRow(b, value, decorate, previewEdge)
    if decorate then
        if not b.swatch then
            b.swatchBg = b:CreateTexture(nil, "BACKGROUND")
            b.swatchBg:SetPoint("LEFT", PAD, 0)
            b.swatchBg:SetSize(SWATCH_W, SWATCH_H)
            b.swatchBg:SetColorTexture(0, 0, 0, 0.6)
            b.swatch = b:CreateTexture(nil, "ARTWORK")
            b.swatch:SetPoint("LEFT", PAD, 0)
            b.swatch:SetSize(SWATCH_W, SWATCH_H)
        end
        b.swatchBg:Show()
        b.swatch:Show()
        placeText(b, PAD + SWATCH_W + SWATCH_GAP)
        decorate(b, value)
    else
        if b.swatch then
            b.swatchBg:Hide()
            b.swatch:Hide()
        end
        placeText(b, previewEdge and (PAD + EDGE_W + SWATCH_GAP) or PAD)
    end
    if previewEdge then
        paintEdge(b, previewEdge(value))
    elseif b.edge then
        b.edge:Hide()
    end
end

local function newRow(ctx, p)
    local b = CreateFrame("Button", nil, p.content)
    b:SetHeight(lib.tokens.spacing.popupRowHeight)
    kit.Highlight(ctx, b)
    b.text = kit.Text(ctx, b, "label")
    b.text:SetWordWrap(false)
    b.data = kit.DataText(b)
    b.data:SetWordWrap(false)
    b.suffix = kit.Text(ctx, b, "hint")
    b.suffix:SetPoint("RIGHT", -PAD, 0)
    b.suffix:SetJustifyH("RIGHT")
    return b
end

-- Enough rows to fill the list plus one for a part-scrolled line (a row per option made 124 KB of
-- garbage per open of 495 textures on Era). Option i takes row (i - 1) % pool + 1, so only a row
-- coming into view is painted.
function paintRows(p)
    local opts, rows = p.opts, p.rows
    local sp = lib.tokens.spacing
    local rowH, pool = sp.popupRowHeight, sp.popupMaxRows + 1
    local first = math.floor((p.bar:GetValue() or 0) / rowH) + 1
    local last = math.min(#opts, first + pool - 1)
    for k = 1, #rows do
        if first + (k - first) % pool > last then
            rows[k]:Hide()
            rows[k]._index = nil
        end
    end
    local todo, n = p.todo, 0
    for i = first, last do
        local b = rows[(i - 1) % pool + 1]
        if b._index ~= i or b._open ~= p.opens then
            n = n + 1
            todo[n] = i
        end
    end
    local ctx, onPick, current = p.ctx, p.onPick, p.current
    local decorate, previewFont, previewEdge = p.decorate, p.previewFont, p.previewEdge
    local getTip = ctx.opts.tooltip
    for t = 1, n do
        local i = todo[t]
        local b = rows[(i - 1) % pool + 1]
        local opt = opts[i]
        local tip = getTip()
        local hadTip = tip:IsShown() and tip:IsOwned(b)
        -- Hidden and unmarked while painted, so a host callback raising partway never leaves a row
        -- showing at its new place with the option it had before.
        b:Hide()
        b._index = nil
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT",  p.content, "TOPLEFT",  0, -(i - 1) * rowH)
        b:SetPoint("TOPRIGHT", p.content, "TOPRIGHT", 0, -(i - 1) * rowH)
        b.suffix:SetText(opt.suffix or "")
        decorateRow(b, opt.value, decorate, previewEdge)
        -- Marked so 42 fonts or 27 sounds do not open with nothing saying which one is in use.
        local isActive = (opt.value == current)
        setLabel(ctx, b, opt.label, previewFont and previewFont(opt.value), isActive and "accentHi" or "text")
        -- Set rather than hooked, so a row that carried a tip in one list carries none into the next.
        if opt.tip then
            local title, body = opt.label, opt.tip
            -- Beside the list: above the hovered option it would cover the options over it.
            b:SetScript("OnEnter", function(s) kit.ShowTip(getTip, s, title, body, "ANCHOR_RIGHT") end)
            b:SetScript("OnLeave", function() getTip():Hide() end)
        else
            b:SetScript("OnEnter", nil)
            b:SetScript("OnLeave", nil)
        end
        -- The pick runs before the hide, as the dialog's buttons do, because a pick can reload the
        -- UI (a profile list does), and a ReloadUI from the dialog's Yes was blocked on retail 12.1
        -- while the dialog hid first.
        b:SetScript("OnClick", function()
            xpcall(function() onPick(opt.value) end, geterrorhandler())
            p:Hide()
        end)
        b:Show()
        -- A scroll of eleven rows or more in one frame can hand the row under a still cursor another
        -- option with no fresh OnEnter, so the tip it was showing follows the new option.
        if hadTip then
            if opt.tip then kit.ShowTip(getTip, b, opt.label, opt.tip, "ANCHOR_RIGHT") else tip:Hide() end
        end
        b._index, b._open = i, p.opens
    end
end

local function showList(ctx, anchor, opts, onPick, decorate, current, previewFont, previewEdge)
    local sp = lib.tokens.spacing
    local p = popup(ctx)
    -- The popup hangs off UIParent, so it does not inherit the window's scale. Matching the
    -- anchor also puts anchor and popup in one unit space, which the width arithmetic below
    -- depends on.
    local base = UIParent:GetEffectiveScale()
    p:SetScale((base and base > 0) and (anchor:GetEffectiveScale() / base) or 1)
    kit.SnapLines(p.edges)
    -- Closed with the window it opened in, a main window as well as the settings window.
    local owner = anchor
    while owner and not owner._euiWindow do owner = owner:GetParent() end
    p.owner = owner or ctx._window
    p.tooltip = ctx.opts.tooltip

    local rowH, maxRows = sp.popupRowHeight, sp.popupMaxRows
    local shown = math.min(#opts, maxRows)
    local h = shown * rowH + POPUP_INSET * 2
    p:SetHeight(h)
    p:ClearAllPoints()
    -- A list opened near the foot of a column is taller than the space under it, so it
    -- would render off the bottom of the screen. Compared in real pixels because anchor
    -- and popup can sit at different effective scales.
    if ((anchor:GetBottom() or 0) * anchor:GetEffectiveScale()) - (h * p:GetEffectiveScale()) < 0 then
        p:SetPoint("BOTTOMLEFT",  anchor, "TOPLEFT",  0, POPUP_GAP)
        p:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, POPUP_GAP)
    else
        p:SetPoint("TOPLEFT",  anchor, "BOTTOMLEFT",  0, -POPUP_GAP)
        p:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -POPUP_GAP)
    end
    local scrolls = #opts > maxRows
    p.scroll:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", scrolls and -BAR_ROOM or -1, POPUP_INSET)

    p.ctx, p.opts, p.onPick, p.current = ctx, opts, onPick, current
    p.decorate, p.previewFont, p.previewEdge = decorate, previewFont, previewEdge
    p.opens = (p.opens or 0) + 1
    local activeIndex
    for i = 1, #opts do
        if opts[i].value == current then activeIndex = i end
    end
    for k = #p.rows + 1, math.min(#opts, maxRows + 1) do p.rows[k] = newRow(ctx, p) end
    -- Hidden until painted, so a host callback raising partway leaves no row showing the last list
    -- with its pick still attached.
    for _, r in ipairs(p.rows) do r:Hide() end

    -- Taken from the anchor rather than the popup: the popup's own width is only two
    -- SetPoints old here and has not resolved yet.
    p.content:SetSize(math.max(1, (anchor:GetWidth() or 0) - (scrolls and (BAR_ROOM + 1) or 2)),
                      math.max(1, #opts * rowH))
    -- Over its window even when that window sits above the world map, so a click on it still closes the list
    local high = p.owner and p.owner.GetFrameStrata and p.owner:GetFrameStrata() == "FULLSCREEN_DIALOG"
    p.closer:SetFrameStrata(high and "FULLSCREEN_DIALOG" or "FULLSCREEN")
    p:Show()
    p.closer:Raise()
    p:Raise()

    -- One popup is shared by every dropdown and nothing else resets the offset, so a
    -- short list opened after a long one would inherit the long one's scroll position.
    local maxScroll = math.max(0, (#opts - shown) * rowH)
    local want = activeIndex
        and ((activeIndex - 1) * rowH - math.floor(maxRows / 2) * rowH)
        or 0
    want = math.min(math.max(0, want), maxScroll)
    p.bar:SetMinMaxValues(0, maxScroll)
    p.bar:SetShown(scrolls)
    p.bar:SetValue(want)
    paintRows(p)
end

-- options is a list of { value =, label = } pairs, or a function returning one that is
-- re-read on every open. An option's suffix, such as a level range, sits at the right end of its
-- row and of the closed field. The setter receives the VALUE, so a translated label can never
-- reach the profile and a setter never has to compare against a display string.
-- decorate(frame, value) draws a preview on the closed field and on every row. Passed by
-- pickers whose values are not self-describing, such as a status bar texture.
-- previewFont(value) returns a font file to draw that row's own label in, which is the only
-- preview a font list can have - a swatch cannot show a typeface.
-- onTest(value) adds a speaker button left of the field that replays the current pick.
-- previewEdge(value) returns a border's edge file, drawn as a small framed sample in the swatch's
-- place on the closed field and on every row. A dropdown takes decorate or previewEdge, not both.
function Context:CreateDropdown(content, label, options, getter, setter, tooltip, decorate, onTest, previewFont,
                                previewEdge)
    if previewEdge and type(previewEdge) ~= "function" then
        error("EverythingUI: CreateDropdown's previewEdge must be a function", 2)
    end
    if decorate and previewEdge then
        error("EverythingUI: CreateDropdown takes decorate or previewEdge, not both", 2)
    end
    local sp = lib.tokens.spacing
    local ctx = self
    local holder = CreateFrame("Frame", nil, content)
    holder:SetSize(DEFAULT_WIDTH, sp.fieldHeight)
    holder._euiFill = true

    local function resolveOptions()
        return (type(options) == "function") and (options() or {}) or options
    end

    local text = kit.Text(self, holder, "label")
    text:SetPoint("LEFT")
    text:SetWordWrap(false)
    text:SetText(label or "")
    holder.label = text

    local btn = CreateFrame("Button", nil, holder)
    btn:SetHeight(sp.fieldHeight)
    btn:SetPoint("RIGHT")
    kit.Fill(self, btn, "input")
    kit.Edge(self, btn, "inputBorder")
    kit.Highlight(self, btn)

    local speaker
    if onTest then
        speaker = CreateFrame("Button", nil, holder)
        speaker:SetSize(SPEAKER, SPEAKER)
        speaker:SetPoint("RIGHT", btn, "LEFT", -SPEAKER_GAP, 0)
        local icon = speaker:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexture("Interface\\Common\\VoiceChat-Speaker")
        icon:SetVertexColor(self:Color("navText"))
        kit.Highlight(self, speaker)
        speaker:SetScript("OnClick", function() onTest(getter()) end)
        self:AttachTooltip(speaker, label, self.opts.labels.testSound)
    end

    holder.SetLabelWidth = function(_, w)
        local left = label and (w + sp.controlGap) or 0
        if speaker then left = left + SPEAKER + SPEAKER_GAP end
        btn:SetPoint("LEFT", holder, "LEFT", left, 0)
    end
    holder:SetLabelWidth(sp.labelColumn)

    if decorate then
        btn.swatch = btn:CreateTexture(nil, "ARTWORK")
        btn.swatch:SetPoint("LEFT", PAD, 0)
        btn.swatch:SetSize(SWATCH_W, SWATCH_H)
    end
    btn.text = kit.Text(self, btn, "label")
    btn.data = kit.DataText(btn)
    local chevron = kit.Icon(self, btn, "chevron-down", sp.chevron, "muted")
    chevron:SetPoint("RIGHT", -PAD, 0)
    btn.suffix = kit.Text(self, btn, "hint")
    btn.suffix:SetPoint("RIGHT", chevron, "LEFT", -PAD, 0)
    btn.suffix:SetJustifyH("RIGHT")
    local function placeField()
        local after = (btn.suffix:GetText() or "") ~= ""
        for _, fs in ipairs({ btn.text, btn.data }) do
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", decorate and (PAD + SWATCH_W + SWATCH_GAP) or previewEdge and (PAD + EDGE_W + SWATCH_GAP)
                or PAD, 0)
            if after then
                fs:SetPoint("RIGHT", btn.suffix, "LEFT", -SUFFIX_GAP, 0)
            else
                fs:SetPoint("RIGHT", -(PAD + sp.chevron + PAD), 0)
            end
            fs:SetWordWrap(false)
        end
    end
    placeField()

    local function refresh()
        local current = getter()
        if decorate then decorate(btn, current) end
        if previewEdge then paintEdge(btn, previewEdge(current)) end
        -- Hidden rather than left to look broken.
        if speaker then speaker:SetShown(current ~= nil and tostring(current):upper() ~= NO_SOUND) end
        local shown, suffix = tostring(current or ""), ""
        for _, opt in ipairs(resolveOptions()) do
            if opt.value == current then
                shown, suffix = opt.label, opt.suffix or ""
                break
            end
        end
        btn.suffix:SetText(suffix)
        placeField()
        setLabel(ctx, btn, shown, previewFont and previewFont(current), "text")
    end
    refresh()

    btn:SetScript("OnClick", function()
        showList(ctx, btn, resolveOptions(), function(v)
            setter(v)
            refresh()
        end, decorate, getter(), previewFont, previewEdge)
    end)

    holder.button  = btn
    holder.speaker = speaker
    holder.Refresh = refresh
    if tooltip then self:AttachTooltip(holder, label, tooltip) end
    content._controls[#content._controls + 1] = holder
    return holder
end
