local addonName = ...
local lib = LibStub("EverythingUI-1.0")
if lib.host ~= addonName then return end

local Context = lib.Context
local kit = lib.kit

local LABEL_INSET = 2
local TEXT_PADDING = 12

-- A card stacks its own rows and nothing else (decision 2). Satellites and two-column rows
-- stay hand-anchored to the row Add returns, and the tab anchors each card with its own
-- SetPoint chain. There is no layout engine wider than one card.

local function measure(card)
    local h = 0
    for _, row in ipairs(card._rows) do
        if row.control:IsShown() then h = h + row:GetHeight() end
    end
    card.panel:SetHeight(math.max(1, h))
    card:SetHeight(card._top + math.max(1, h))
    return h
end

-- A row follows its control: a tab hides or shows only the control and lays the card out again,
-- and the row's gap closes or opens with it. The control is not the row's child, so hiding the
-- row alone would leave the control drawn over whatever moved up into its place.
-- Every fitted row is measured again, except while Add lays the card out for its newest row: a
-- card of many text blocks would otherwise measure each one again for every row added after it.
local function layout(card, added)
    local y, first = 0, true
    local labelled = {}
    for _, row in ipairs(card._rows) do
        local shown = row.control:IsShown() and true or false
        row:SetShown(shown)
        if shown then
            if row.fitHeight and (not added or row == added) then
                row:SetHeight(row.control:Measure() + TEXT_PADDING * 2)
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  card.panel, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", card.panel, "TOPRIGHT", 0, -y)
            row.divider:SetShown(not first)
            first = false
            y = y + row:GetHeight()
            labelled[#labelled + 1] = row.control
        end
    end
    measure(card)
    if #labelled > 0 then card._ctx:AlignLabelColumn(unpack(labelled)) end
end

-- opts.dependent indents the row under its master and uses the shorter row. opts.height and
-- opts.fill are for rows that are not a control, such as a hint. opts.fitHeight sizes the row to
-- its control's Measure, such as a text block's, again on every Layout.
local function add(card, control, opts)
    local sp = lib.tokens.spacing
    opts = opts or {}
    if opts.fitHeight and not control.Measure then
        error("EverythingUI: a fitHeight row needs a control with a Measure method", 2)
    end
    local dependent = opts.dependent and true or false
    local row = CreateFrame("Frame", nil, card.panel)
    row.fitHeight = opts.fitHeight and true or false
    row:SetFrameLevel(card:GetFrameLevel())
    row:SetHeight(opts.height or (dependent and sp.dependentRowHeight or sp.rowHeight))
    row.divider = kit.Edge(card._ctx, row, "divider", "T")[1]
    row.control = control
    control:ClearAllPoints()
    control:SetPoint("LEFT", row, "LEFT", dependent and sp.dependentIndent or sp.rowPadding, 0)
    if control._euiFill or opts.fill then
        control:SetPoint("RIGHT", row, "RIGHT", -sp.rowPadding, 0)
    end
    control._euiDependent = dependent
    control._euiRow = row
    card._rows[#card._rows + 1] = row
    layout(card, row)
    return row
end

-- A group label over a surface panel. Built at the content's own frame level, so the controls
-- and satellites the tab anchors over it, which are the content's children one level up, draw
-- on top of the panel rather than under it.
function Context:CreateGroup(content, label)
    local sp = lib.tokens.spacing
    local level = content:GetFrameLevel()
    local card = CreateFrame("Frame", nil, content)
    card:SetFrameLevel(level)
    card._ctx, card._rows = self, {}

    local top = 0
    if label then
        local fs = kit.Text(self, card, "groupLabel")
        fs:SetPoint("TOPLEFT", LABEL_INSET, 0)
        fs:SetText(label)
        card.label = fs
        -- `<= 0` because 0 is truthy, and an unmeasured label would drop the panel onto it.
        local h = fs:GetStringHeight()
        if not h or h <= 0 then h = lib.tokens.typography.groupLabel.size end
        top = h + sp.groupLabelGap
    end
    card._top = top

    local panel = CreateFrame("Frame", nil, card)
    panel:SetFrameLevel(level)
    panel:SetPoint("TOPLEFT", 0, -top)
    panel:SetPoint("TOPRIGHT", 0, -top)
    kit.Fill(self, panel, "surface")
    kit.Edge(self, panel, "surfaceBorder")
    card.panel = panel

    card.Add, card.Layout, card.Measure = add, layout, measure
    measure(card)
    -- Listed on the content so its label column is aligned again once the tab is on screen.
    local cards = content._euiCards or {}
    content._euiCards = cards
    cards[#cards + 1] = card
    return card
end

-- A line across the card under any frame in one of its rows, for a break that is not between
-- two rows.
function Context:AddDivider(card, belowFrame)
    local row = belowFrame._euiRow or belowFrame
    local line = kit.Line(self, card.panel, "divider")
    line:SetPoint("TOPLEFT", row, "BOTTOMLEFT")
    line:SetPoint("TOPRIGHT", row, "BOTTOMRIGHT")
    return line
end
