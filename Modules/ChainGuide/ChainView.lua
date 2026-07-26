local _, ns = ...
local L = ns.L

local CV = ns:RegisterSubsystem("ChainGuideView", {})

local PAD            = 10
local HEADER_H       = 44
local CELL_W         = 210
local CELL_H         = 34
local COL_PITCH      = 224
local ROW_PITCH      = 72
local STATUS_ICON_PX = 14
local CONNECTOR_PX   = 3

local PAN_CLICK_THRESH    = 5
local PAN_CLICK_THRESH_SQ = PAN_CLICK_THRESH * PAN_CLICK_THRESH
local WHEEL_STEP          = ROW_PITCH

local _metaParts = {}
local _nodes     = {}
local _resolved  = {}
local _statuses  = {}
local _revConn   = {}
local _chainComplete = {}
local _slotLoserOf   = {}
local _slotWinner    = {}
local _titleRequested = {}

local function slotRank(s)
    if s == "complete" or s == "turnin" or s == "active" then return 4 end
    if s == "chainnav" then return 3 end
    if s == "pending"  then return 2 end
    return 1
end

local STATUS = {
    complete = { atlas = "common-icon-checkmark",                color = { 0.55, 0.55, 0.55 } },
    turnin   = { atlas = "QuestTurnin",                          color = { 1.00, 0.82, 0.00 } },
    active   = { atlas = "Quest-Available",                      color = { 1.00, 1.00, 1.00 } },
    pending  = { atlas = nil,                                    color = { 0.78, 0.78, 0.78 } },
    skipped  = { atlas = "common-icon-redx",                     color = { 1.00, 0.65, 0.00 } },
    chainnav = { atlas = "Garr_LevelUpgradeArrow",               color = { 0.92, 0.72, 0.02 } },
    locked   = { atlas = nil,                                    color = { 0.45, 0.45, 0.45 } },
}

CV.nodePool, CV.activeNodes = {}, {}
CV.linePool, CV.activeLines = {}, {}
CV.dotPool,  CV.activeDots  = {}, {}

function CV:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    local function rerender()
        local CG = ns:GetSubsystem("ChainGuide")
        if CG and CG.frame and CG.frame:IsShown() and CG.RenderCurrent then
            CG:RenderCurrent()
        end
    end
    Events:On("QUEST_DATA_LOAD_RESULT", function()
        Events:Debounce("eq.chainview.dataload", 0.15, rerender)
    end)
    Events:On("QUESTLINE_UPDATE", function()
        Events:Debounce("eq.chainview.dataload", 0.15, rerender)
    end)
end

local function safeSetAtlas(tex, atlas)
    if not atlas then tex:SetTexture(nil); return false end
    if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        tex:SetAtlas(atlas, false)
        return true
    end
    tex:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    tex:SetTexCoord(0, 1, 0, 1)
    return false
end

local nodeOnEnter, nodeOnLeave, nodeOnClick

local function buildNode(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(CELL_W, CELL_H)

    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.08, 0.08, 0.08, 0.95)

    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetAllPoints()
    b.border:SetColorTexture(0.20, 0.20, 0.20, 1)

    b.inner = b:CreateTexture(nil, "ARTWORK")
    b.inner:SetPoint("TOPLEFT", 1, -1)
    b.inner:SetPoint("BOTTOMRIGHT", -1, 1)
    b.inner:SetColorTexture(0.05, 0.05, 0.05, 0.95)

    b.statusIcon = b:CreateTexture(nil, "OVERLAY")
    b.statusIcon:SetSize(STATUS_ICON_PX, STATUS_ICON_PX)
    b.statusIcon:SetPoint("TOPLEFT", 4, -3)

    b.title = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.title:SetPoint("TOPLEFT",  STATUS_ICON_PX + 7, -3)
    b.title:SetPoint("TOPRIGHT", -6, -3)
    b.title:SetJustifyH("LEFT")
    b.title:SetWordWrap(false)
    b.title:SetMaxLines(1)

    b.subtitle = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.subtitle:SetPoint("BOTTOMLEFT",  6, 4)
    b.subtitle:SetPoint("BOTTOMRIGHT", -6, 4)
    b.subtitle:SetJustifyH("LEFT")
    b.subtitle:SetWordWrap(false)

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.06)

    b.searchGlow = b:CreateTexture(nil, "BACKGROUND", nil, -2)
    b.searchGlow:SetPoint("TOPLEFT", -3, 3)
    b.searchGlow:SetPoint("BOTTOMRIGHT", 3, -3)
    b.searchGlow:SetColorTexture(0.92, 0.72, 0.02, 0.95)
    b.searchGlow:Hide()

    b:SetScript("OnEnter", nodeOnEnter)
    b:SetScript("OnLeave", nodeOnLeave)
    b:SetScript("OnClick", nodeOnClick)

    -- Propagate to the canvas so a drag-pan can start on a node - nodeOnClick suppresses pan-gesture clicks
    if b.SetPropagateMouseClicks then b:SetPropagateMouseClicks(true) end

    return b
end

local function acquireNode(parent)
    local b = tremove(CV.nodePool)
    if not b then b = buildNode(parent) end
    b:SetParent(parent)
    b:ClearAllPoints()
    b:Show()
    CV.activeNodes[#CV.activeNodes + 1] = b
    return b
end

local function releaseNodes()
    for i = #CV.activeNodes, 1, -1 do
        local b = CV.activeNodes[i]
        b:Hide()
        b:ClearAllPoints()
        b._ref, b._chain = nil, nil
        b.statusIcon:SetTexture(nil)
        b.statusIcon:SetVertexColor(1, 1, 1, 1)
        b.border:SetColorTexture(0.20, 0.20, 0.20, 1)
        if b.searchGlow then b.searchGlow:Hide() end
        CV.nodePool[#CV.nodePool + 1] = b
        CV.activeNodes[i] = nil
    end
end

local function acquireLine(parent)
    local line = tremove(CV.linePool)
    if not line then
        line = parent:CreateLine(nil, "BACKGROUND")
        line:SetThickness(CONNECTOR_PX)
    else
        line:SetParent(parent)
    end
    line:Show()
    CV.activeLines[#CV.activeLines + 1] = line
    return line
end

local function releaseLines()
    for i = #CV.activeLines, 1, -1 do
        local line = CV.activeLines[i]
        line:Hide()
        line:ClearAllPoints()
        line:SetColorTexture(1, 1, 1, 1)
        CV.linePool[#CV.linePool + 1] = line
        CV.activeLines[i] = nil
    end
end

local DOT_PX = 9
local function acquireDot(parent)
    local d = tremove(CV.dotPool)
    if not d then
        d = parent:CreateTexture(nil, "ARTWORK")
        d:SetSize(DOT_PX, DOT_PX)
    else
        d:SetParent(parent)
    end
    d:Show()
    CV.activeDots[#CV.activeDots + 1] = d
    return d
end

local function releaseDots()
    for i = #CV.activeDots, 1, -1 do
        local d = CV.activeDots[i]
        d:Hide()
        d:ClearAllPoints()
        CV.dotPool[#CV.dotPool + 1] = d
        CV.activeDots[i] = nil
    end
end

local EDGE_DONE = { 0.22, 0.42, 0.25, 0.55 }
local EDGE_TODO = { 0.52, 0.52, 0.56, 0.70 }

local _centerX = 0

local function segment(canvas, x1, y1, x2, y2, r, g, b, a)
    local line = acquireLine(canvas)
    line:SetStartPoint("TOPLEFT", canvas, x1, y1)
    line:SetEndPoint(  "TOPLEFT", canvas, x2, y2)
    line:SetColorTexture(r, g, b, a)
end

local function cellCenterX(col) return col * COL_PITCH + CELL_W * 0.5 end
local function cellCenterY(row) return -(row * ROW_PITCH + CELL_H * 0.5) end

local function prereqComplete(items, idx, Characters)
    if items[idx].type == "chain" then return _chainComplete[idx] end
    return Characters:IsQuestCompleted(_resolved[idx].id)
end

local function statusForQuestItem(item, Characters)
    if Characters:IsQuestCompleted(item.id) then return "complete" end
    if Characters:IsQuestActive(item.id) then
        if C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(item.id) then
            return "turnin"
        end
        return "active"
    end
    return "pending"
end

local function buildQuestTooltip(item, statusKey)
    local title = ns.Util.QuestTitle(item.id) or item.name or ("Quest #" .. tostring(item.id))
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText(title, 1, 0.82, 0)
    if statusKey == "complete" then
        GameTooltip:AddLine(L["Completed"], 0.5, 1, 0.5)
    elseif statusKey == "turnin" then
        GameTooltip:AddLine(L["Ready to turn in"], 1, 0.82, 0)
    elseif statusKey == "active" then
        GameTooltip:AddLine(L["In your quest log"], 1, 1, 1)
    elseif statusKey == "skipped" then
        GameTooltip:AddLine(L["Skipped"], 1.0, 0.65, 0.0)
        GameTooltip:AddLine(L["A later quest in this chain has already passed this one."], 0.7, 0.7, 0.7, true)
        GameTooltip:AddLine(L["May be worth going back to pick up."], 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(L["Not started"], 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine("ID: " .. tostring(item.id), 0.5, 0.5, 0.5)

    -- GetQuestDifficultyLevel returns 0 until quest data is cached
    if item.id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local lvl = C_QuestLog.GetQuestDifficultyLevel(item.id)
        if lvl and lvl > 0 then
            local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
            if c then
                GameTooltip:AddLine((L["Level %d"]):format(lvl), c.r, c.g, c.b)
            else
                GameTooltip:AddLine((L["Level %d"]):format(lvl), 0.8, 0.8, 0.8)
            end
        end
    end

    if item.id then
        if QuestUtil and QuestUtil.GetQuestClassificationDetails then
            local cls, ctext = QuestUtil.GetQuestClassificationDetails(item.id, true)
            local isPlainStoryline = Enum and Enum.QuestClassification
                                     and cls == Enum.QuestClassification.Questline  -- suppress: every chain member is Questline
            if ctext and ctext ~= "" and not isPlainStoryline then
                GameTooltip:AddLine(ctext, 0.90, 0.78, 0.45)
            end
        end
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local tag = C_QuestLog.GetQuestTagInfo(item.id)
            if tag and tag.tagName and tag.tagName ~= "" then
                GameTooltip:AddLine(tag.tagName, 0.55, 0.75, 0.95)
            end
        end
    end

    local R = ns:GetSubsystem("History")
    if R and R.GetCompletionTime then
        local t = R:GetCompletionTime(item.id)
        if t then
            if t > 0 then
                GameTooltip:AddLine(L["Completed: "] .. date("%Y-%m-%d %H:%M", t), 0.55, 0.85, 0.55)
            else
                GameTooltip:AddLine(L["Completed (before tracking)"], 0.55, 0.85, 0.55)
            end
        end
    end

    local QR = ns:GetSubsystem("QuestRewards")
    if QR then
        -- Completed quests are gone from the log and the API reports their objectives as 0/N, so skip them
        if statusKey ~= "complete" then
            local hadObjectives = QR:RenderObjectives(GameTooltip, item.id)
            if hadObjectives then GameTooltip:AddLine(" ") end
        end
        QR:RenderRewards(GameTooltip, item.id)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L["Shift-click to link in chat"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function buildChainNavTooltip(item)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local sub = Database and Database.chains[item.id]
    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    GameTooltip:SetText((sub and sub.name) or ("Chain #" .. tostring(item.id)), 0.92, 0.72, 0.02)
    if sub and sub.range then
        GameTooltip:AddLine((L["Level %d–%d"]):format(sub.range[1], sub.range[2]), 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(L["Click to open this chain"], 1, 1, 1)
    GameTooltip:Show()
end

local function onNodeClickQuest(item, chain)
    if IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
        local title = ns.Util.QuestTitle(item.id)
        if title then
            ChatEdit_InsertLink(("[%s]"):format(title))
            return
        end
    end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.GoTo then WP:GoTo(item.id, chain) end
end

local function onNodeClickChain(item)
    local CG = ns:GetSubsystem("ChainGuide")
    if CG and CG.NavigateChain then CG:NavigateChain(item.id) end
end

function nodeOnEnter(self)
    local canvas = self:GetParent()
    local pane = canvas and canvas._pane
    if pane and pane._panning then return end
    if self._navKind == "chain" then
        buildChainNavTooltip(self._ref)
    else
        buildQuestTooltip(self._ref, self._status)
    end
end

function nodeOnLeave()
    GameTooltip:Hide()
end

function nodeOnClick(self)
    local canvas = self:GetParent()
    local pane = canvas and canvas._pane
    if pane and pane._panning then
        if pane._panMoved then return end
        -- OnUpdate may not have run between press and click, so re-check live travel (order is OnMouseDown then OnClick then OnMouseUp)
        if pane._panStartX then
            local scale = canvas:GetEffectiveScale()
            if scale and scale ~= 0 then
                local cx, cy = GetCursorPosition()
                local tx = cx / scale - pane._panStartX
                local ty = cy / scale - pane._panStartY
                if (tx * tx + ty * ty) > PAN_CLICK_THRESH_SQ then return end
            end
        end
    end
    if self._navKind == "chain" then
        onNodeClickChain(self._ref)
    else
        onNodeClickQuest(self._ref, self._chain)
    end
end

local function onContinueClick(self)
    if not self._nextID then return end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.GoTo then WP:GoTo(self._nextID, self._chain) end
end

local function onTrackClick(self)
    local id = self._chainID
    if not id then return end
    local CG = ns:GetSubsystem("ChainGuide")
    if not CG then return end
    if CG:IsTrackingChain(id) then
        CG:ClearTrackedChainID()
    else
        CG:SetTrackedChainID(id)
    end
end

local function stopPan(canvas)
    local pane = canvas._pane
    if pane then pane._panning = false end
    canvas:SetScript("OnUpdate", nil)
    if SetCursor then SetCursor(nil) end
end

local function canvasOnUpdate(self)
    local pane = self._pane
    if not (pane and pane._panning) then return end
    -- Button can be released off-frame, so live button state is the authoritative stop signal
    if not (IsMouseButtonDown and IsMouseButtonDown("LeftButton")) then stopPan(self); return end

    local scale = self:GetEffectiveScale()
    if not scale or scale == 0 then return end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local dx = cx - pane._panLastX
    local dy = cy - pane._panLastY
    pane._panLastX, pane._panLastY = cx, cy

    if not pane._panMoved then
        local tx, ty = cx - pane._panStartX, cy - pane._panStartY
        if (tx * tx + ty * ty) > PAN_CLICK_THRESH_SQ then
            pane._panMoved = true
            if GameTooltip then GameTooltip:Hide() end
        end
    end

    local sc = pane._cvScroll
    if not sc then return end
    -- Scroll Y grows down while screen Y grows up, hence the opposite signs on the two axes
    local hmax = sc:GetHorizontalScrollRange() or 0
    local vmax = sc:GetVerticalScrollRange()   or 0
    sc:SetHorizontalScroll(math.max(0, math.min(hmax, (sc:GetHorizontalScroll() or 0) - dx)))
    sc:SetVerticalScroll(  math.max(0, math.min(vmax, (sc:GetVerticalScroll()   or 0) + dy)))
end

local function canvasOnMouseDown(self, button)
    if button ~= "LeftButton" then return end
    local pane = self._pane
    if not pane then return end
    local sc = pane._cvScroll
    if not sc then return end
    if (sc:GetHorizontalScrollRange() or 0) <= 0 and (sc:GetVerticalScrollRange() or 0) <= 0 then
        return
    end
    local scale = self:GetEffectiveScale()
    if not scale or scale == 0 then return end
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    pane._panLastX,  pane._panLastY  = cx, cy
    pane._panStartX, pane._panStartY = cx, cy
    pane._panMoved = false
    pane._panning  = true
    self:SetScript("OnUpdate", canvasOnUpdate)
    if SetCursor then SetCursor("UI_MOVE_CURSOR") end
end

local function canvasOnMouseUp(self)
    if self._pane and self._pane._panning then stopPan(self) end
end

local function canvasOnHide(self)
    if self._pane and self._pane._panning then stopPan(self) end
end

-- Wheel lives on the scroll child because enabling mouse on the parent would steal mouse focus
local function canvasOnMouseWheel(self, delta)
    local pane = self._pane
    local sc = pane and pane._cvScroll
    if not sc then return end
    if IsShiftKeyDown and IsShiftKeyDown() then
        local hmax = sc:GetHorizontalScrollRange() or 0
        sc:SetHorizontalScroll(math.max(0, math.min(hmax, (sc:GetHorizontalScroll() or 0) - delta * WHEEL_STEP)))
    else
        local vmax = sc:GetVerticalScrollRange() or 0
        sc:SetVerticalScroll(math.max(0, math.min(vmax, (sc:GetVerticalScroll() or 0) - delta * WHEEL_STEP)))
    end
end

local function computeLayout(items)
    local n = #items
    local cols, rows = {}, {}

    local depth = {}
    local visiting = {}
    local function getDepth(i)
        if depth[i] then return depth[i] end
        if visiting[i] then return 0 end
        visiting[i] = true
        local it = items[i]
        local d = 0
        if it.connections then
            for _, src in ipairs(it.connections) do
                if items[src] then
                    d = math.max(d, getDepth(src) + 1)
                end
            end
        end
        visiting[i] = nil
        depth[i] = d
        return d
    end
    for i = 1, n do getDepth(i) end

    local rowCursor = {}
    local maxCol, maxRow = 0, 0
    for i = 1, n do
        local it = items[i]
        local col = it.x or depth[i] or 0
        local row = it.y
        if row == nil then
            row = rowCursor[col] or 0
            rowCursor[col] = row + 1
        end
        cols[i], rows[i] = col, row
        if col > maxCol then maxCol = col end
        if row > maxRow then maxRow = row end
    end
    return cols, rows, maxCol, maxRow
end

function CV:Render(pane, chain, highlightQuestID)
    self:_ensureUI(pane)
    releaseNodes()
    releaseLines()
    releaseDots()

    pane._cvContinue:Hide()
    pane._cvContinue._nextID, pane._cvContinue._chain = nil, nil

    -- Only genuine navigations auto-scroll, not passive re-renders - _cvRenderedChain is set on the success path so a cold navigation's first non-empty render still counts as one
    local navChanged = (chain ~= pane._cvScrolledChain)
                       or (highlightQuestID ~= pane._cvScrolledHighlight)
                       or (chain ~= pane._cvRenderedChain)
    pane._cvScrolledChain     = chain
    pane._cvScrolledHighlight = highlightQuestID

    if not chain then
        pane._cvHeader:SetText("")
        pane._cvMeta:SetText(L["Pick a chain on the left to view its quests."])
        pane._cvMeta:SetTextColor(0.6, 0.6, 0.6)
        pane._cvEmpty:Hide()
        pane._cvCanvas:SetSize(1, 1)
        pane._cvTrack:Hide()
        return
    end

    local CG = ns:GetSubsystem("ChainGuide")
    pane._cvTrack._chainID = chain.id
    local tracking = CG and chain.id and CG:IsTrackingChain(chain.id)
    pane._cvTrack:SetText(tracking and L["Untrack"] or L["Track"])
    if pane._cvTrack.text then
        if tracking then
            pane._cvTrack.text:SetTextColor(0.27, 0.85, 0.27)
        else
            pane._cvTrack.text:SetTextColor(0.92, 0.72, 0.02)
        end
    end
    pane._cvTrack:Show()

    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local QLS        = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)

    local items = chain.items
    if not items or #items == 0 then
        pane._cvHeader:SetText(chain.name or "Chain")
        local complete, active, total = Characters:ChainProgress(chain)
        wipe(_metaParts)
        if chain.range then
            _metaParts[#_metaParts + 1] = (L["Level %d–%d"]):format(chain.range[1], chain.range[2])
        end
        if total > 0 then
            _metaParts[#_metaParts + 1] = (L["%d/%d done"]):format(complete, total)
            if active > 0 then _metaParts[#_metaParts + 1] = (L["%d active"]):format(active) end
        end
        pane._cvMeta:SetText(table.concat(_metaParts, "  •  "))
        pane._cvMeta:SetTextColor(0.75, 0.75, 0.75)
        pane._cvCanvas:SetSize(1, 1)
        pane._cvEmpty:Show()
        return
    end
    pane._cvEmpty:Hide()

    local cols, rows, maxCol, maxRow = computeLayout(items)
    _centerX = (maxCol * 0.5) * COL_PITCH + CELL_W * 0.5
    local char = Database:CurrentCharacter()

    wipe(_resolved)
    wipe(_statuses)
    for i = 1, #items do
        local resolved = Database:GetVariation(items[i], char)
        _resolved[i] = resolved
        if resolved.type == "chain" then
            _statuses[i] = "chainnav"
        else
            _statuses[i] = statusForQuestItem(resolved, Characters)
        end
    end

    wipe(_slotLoserOf)
    wipe(_slotWinner)
    for i = 1, #items do
        local key = rows[i] * 4096 + cols[i]
        local cur = _slotWinner[key]
        if not cur then
            _slotWinner[key] = i
        elseif slotRank(_statuses[i]) > slotRank(_statuses[cur]) then
            _slotLoserOf[cur] = i
            _slotWinner[key] = i
        else
            _slotLoserOf[i] = cur
        end
    end

    wipe(_revConn)
    for j = 1, #items do
        local jt = items[j]
        if jt.connections then
            for _, src in ipairs(jt.connections) do
                local list = _revConn[src]
                if not list then list = {}; _revConn[src] = list end
                list[#list + 1] = j
            end
        end
    end
    local skippedCount = 0
    for i = 1, #items do
        if _statuses[i] == "pending" and not _resolved[i].breadcrumb and not _slotLoserOf[i] then
            local consumers = _revConn[i]
            if consumers then
                for k = 1, #consumers do
                    local s = _statuses[consumers[k]]
                    if s == "complete" or s == "turnin" or s == "active" then
                        _statuses[i] = "skipped"
                        skippedCount = skippedCount + 1
                        break
                    end
                end
            end
        end
    end

    pane._cvHeader:SetText(chain.name or "Chain")
    local complete, active, total = Characters:ChainProgress(chain)
    wipe(_metaParts)
    if chain.range then
        _metaParts[#_metaParts + 1] = (L["Level %d–%d"]):format(chain.range[1], chain.range[2])
    end
    if total > 0 then
        _metaParts[#_metaParts + 1] = (L["%d/%d done"]):format(complete, total)
        if active > 0 then _metaParts[#_metaParts + 1] = (L["%d active"]):format(active) end
        if skippedCount > 0 then
            _metaParts[#_metaParts + 1] = (L["|cffff9933%d skipped|r"]):format(skippedCount)
        end
    end
    pane._cvMeta:SetText(table.concat(_metaParts, "  •  "))
    pane._cvMeta:SetTextColor(0.75, 0.75, 0.75)

    local WP       = ns:GetSubsystem("ChainGuideWaypoint")
    local nextStep = WP and WP.NextActionableStep and WP:NextActionableStep(chain)
    local nextID   = nextStep and nextStep.id

    wipe(_nodes)
    wipe(_chainComplete)
    local nodes = _nodes
    local highlightRow
    local nextRow
    local highlightCol, nextCol
    for i = 1, #items do
        local resolved = _resolved[i]
        local node = acquireNode(pane._cvCanvas)
        node:SetPoint("TOPLEFT", pane._cvCanvas, "TOPLEFT",
            cols[i] * COL_PITCH,
            -(rows[i] * ROW_PITCH))

        local statusKey, title, subtitle
        if resolved.type == "chain" then
            local sub = Database.chains[resolved.id]
            title    = (sub and sub.name) or ("Chain #" .. tostring(resolved.id))
            statusKey = "chainnav"
            if sub then
                local sc, _, st = Characters:ChainProgress(sub)
                if st > 0 then
                    subtitle = (L["%d/%d done"]):format(sc, st)
                    if sc >= st then statusKey = "complete"; _chainComplete[i] = true end
                else
                    subtitle = "View chain >"
                end
            else
                subtitle = "View chain >"
            end
        else
            local cached = ns.Util.QuestTitle(resolved.id)
            if (not cached) and resolved.id and not _titleRequested[resolved.id]
               and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
                _titleRequested[resolved.id] = true
                C_QuestLog.RequestLoadQuestByID(resolved.id)
            end
            title = resolved.name or cached or ("Quest #" .. tostring(resolved.id))
            statusKey = _statuses[i]

            local id  = resolved.id
            local lvl = id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel
                        and C_QuestLog.GetQuestDifficultyLevel(id)
            if lvl and lvl > 0 then
                subtitle = (L["Lv %d  •  ID %d"]):format(lvl, id)
            elseif id then
                subtitle = ("ID %d"):format(id)
            else
                subtitle = ""
            end
            if statusKey == "active" or statusKey == "turnin" then
                subtitle = "|cff4db8ff" .. L["ON QUEST"] .. "|r  •  " .. subtitle
            elseif id and nextID and id == nextID then
                subtitle = "|cffEBB706" .. L["NEXT"] .. "|r  •  " .. subtitle
            end
        end

        node.title:SetText(title)
        node.title:SetTextColor(unpack(STATUS[statusKey].color))
        node.subtitle:SetText(subtitle or ("ID " .. tostring(resolved.id)))

        if STATUS[statusKey].atlas then
            safeSetAtlas(node.statusIcon, STATUS[statusKey].atlas)
            node.statusIcon:Show()
        else
            node.statusIcon:Hide()
        end

        if resolved.breadcrumb then
            node.title:SetTextColor(0.55, 0.55, 0.40)
            node.subtitle:SetText(L["(optional)"])
        end

        node._ref     = resolved
        node._status  = statusKey
        node._chain   = chain
        node._navKind = (resolved.type == "chain") and "chain" or "quest"

        if highlightQuestID and resolved.type ~= "chain" and resolved.id == highlightQuestID then
            node.searchGlow:Show()
            highlightRow = rows[i]
            highlightCol = cols[i]
        end

        if nextID and resolved.type ~= "chain" and resolved.id == nextID then
            node.border:SetColorTexture(0.92, 0.72, 0.02, 1)
            nextRow = rows[i]
            nextCol = cols[i]
        end

        nodes[i] = node

        if _slotLoserOf[i] then
            node:Hide()
            nodes[i] = nil
        end
    end

    local canvas = pane._cvCanvas
    local gapParSet, gapParList, gapKidList, gapEdgeN, gapDone = {}, {}, {}, {}, {}
    for i = 1, #items do
        local it = items[i]
        if it.connections then
            local R = rows[i]
            if not gapParSet[R] then
                gapParSet[R] = {}; gapParList[R] = {}; gapKidList[R] = {}
                gapEdgeN[R] = 0; gapDone[R] = true
            end
            local pset = gapParSet[R]
            local counted = false
            for _, src in ipairs(it.connections) do
                if nodes[src] and nodes[i] then
                    if not pset[src] then
                        pset[src] = true
                        local pl = gapParList[R]; pl[#pl + 1] = src
                    end
                    gapEdgeN[R] = gapEdgeN[R] + 1
                    if not prereqComplete(items, src, Characters) then gapDone[R] = false end
                    counted = true
                end
            end
            if counted then local kl = gapKidList[R]; kl[#kl + 1] = i end
        end
    end

    for R, parList in pairs(gapParList) do
        local kidList = gapKidList[R]
        local nP, nC = #parList, #kidList
        if nP >= 2 and nC >= 2 and gapEdgeN[R] == nP * nC then
            local dotRow = (rows[parList[1]] + R) * 0.5
            local dotX, dotY = _centerX, cellCenterY(dotRow)
            for k = 1, nP do
                local p  = parList[k]
                local pc = prereqComplete(items, p, Characters) and EDGE_DONE or EDGE_TODO
                segment(canvas, cellCenterX(cols[p]), cellCenterY(rows[p]), dotX, dotY, pc[1], pc[2], pc[3], pc[4])
            end
            local gc = gapDone[R] and EDGE_DONE or EDGE_TODO
            for k = 1, nC do
                local ch = kidList[k]
                segment(canvas, dotX, dotY, cellCenterX(cols[ch]), cellCenterY(rows[ch]), gc[1], gc[2], gc[3], gc[4])
            end
            local dot = acquireDot(canvas)
            dot:SetPoint("CENTER", canvas, "TOPLEFT", dotX, dotY)
            dot:SetColorTexture(gc[1], gc[2], gc[3], 1)
        else
            for k = 1, nC do
                local ch = kidList[k]
                local cxp, cyp = cellCenterX(cols[ch]), cellCenterY(rows[ch])
                for _, src in ipairs(items[ch].connections) do
                    if nodes[src] and nodes[ch] then
                        local pc = prereqComplete(items, src, Characters) and EDGE_DONE or EDGE_TODO
                        segment(canvas, cellCenterX(cols[src]), cellCenterY(rows[src]), cxp, cyp, pc[1], pc[2], pc[3], pc[4])
                    end
                end
            end
        end
    end

    local canvasW = maxCol * COL_PITCH + CELL_W
    local canvasH = maxRow * ROW_PITCH + CELL_H
    pane._cvCanvas:SetSize(math.max(canvasW, 1), math.max(canvasH, 1))

    if nextStep and nextID then
        pane._cvContinue._nextID = nextID
        pane._cvContinue._chain  = chain
        pane._cvContinue:Show()
    end

    pane._cvRenderedChain = chain

    local scrollRow = highlightRow or nextRow
    local scrollCol = highlightRow and highlightCol or nextCol
    if scrollRow and navChanged then
        pane._cvScrollY = scrollRow * ROW_PITCH
        pane._cvScrollX = (scrollCol or 0) * COL_PITCH
        C_Timer.After(0, pane._cvDoScroll)
    end
end

function CV:_ensureUI(pane)
    if pane._cvBuilt then return end
    pane._cvBuilt = true

    local Options = ns:GetSubsystem("Options")
    pane._cvContinue = Options:CreateYellowButton(pane, L["Continue"], onContinueClick)
    pane._cvContinue:SetSize(110, 24)
    pane._cvContinue:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -PAD, -PAD)
    pane._cvContinue:Hide()

    pane._cvTrack = Options:CreateYellowButton(pane, L["Track"], onTrackClick)
    pane._cvTrack:SetSize(96, 24)
    pane._cvTrack:SetPoint("TOPRIGHT", pane._cvContinue, "TOPLEFT", -6, 0)
    pane._cvTrack:Hide()
    Options:AttachTooltip(pane._cvTrack, L["Track this chain"],
        L["Follow this chain — its quests pin on the world map (next step highlighted) and your waypoint auto-advances to the next step as you complete it. Works even with this window closed. Click again to stop."])

    pane._cvHeader = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pane._cvHeader:SetPoint("TOPLEFT",  PAD, -PAD)
    pane._cvHeader:SetPoint("TOPRIGHT", pane._cvTrack, "TOPLEFT", -8, 0)
    pane._cvHeader:SetJustifyH("LEFT")
    pane._cvHeader:SetWordWrap(false)
    pane._cvHeader:SetTextColor(1.0, 0.82, 0.0)

    pane._cvMeta = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._cvMeta:SetPoint("TOPLEFT",  pane._cvHeader, "BOTTOMLEFT",  0, -2)
    pane._cvMeta:SetPoint("TOPRIGHT", pane._cvHeader, "BOTTOMRIGHT", 0, -2)
    pane._cvMeta:SetJustifyH("LEFT")
    pane._cvMeta:SetTextColor(0.7, 0.7, 0.7)

    local scroll = CreateFrame("ScrollFrame", nil, pane, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     PAD, -HEADER_H)
    scroll:SetPoint("BOTTOMRIGHT", -PAD - 20, PAD)
    pane._cvScroll = scroll

    pane._cvDoScroll = function()
        local sc = pane._cvScroll
        if not (sc and sc:IsShown()) then return end
        if pane._panning then return end
        if sc.UpdateScrollChildRect then sc:UpdateScrollChildRect() end
        local maxv = sc:GetVerticalScrollRange() or 0
        sc:SetVerticalScroll(math.min(maxv, math.max(0, (pane._cvScrollY or 0) - 20)))
        local maxh   = sc:GetHorizontalScrollRange() or 0
        local viewW  = sc:GetWidth() or 0
        local targetX = (pane._cvScrollX or 0) - math.max(0, (viewW - CELL_W) * 0.5)
        sc:SetHorizontalScroll(math.min(maxh, math.max(0, targetX)))
    end

    local canvas = CreateFrame("Frame", nil, scroll)
    canvas:SetSize(1, 1)
    scroll:SetScrollChild(canvas)
    pane._cvCanvas = canvas

    canvas._pane = pane
    canvas:EnableMouse(true)
    canvas:EnableMouseWheel(true)
    canvas:SetScript("OnMouseDown",  canvasOnMouseDown)
    canvas:SetScript("OnMouseUp",    canvasOnMouseUp)
    canvas:SetScript("OnMouseWheel", canvasOnMouseWheel)
    canvas:SetScript("OnHide",       canvasOnHide)

    pane._cvEmpty = pane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pane._cvEmpty:SetPoint("TOPLEFT", scroll, "TOPLEFT", PAD, -PAD)
    pane._cvEmpty:SetTextColor(0.55, 0.55, 0.55)
    pane._cvEmpty:SetText(L["(no quests defined for this chain yet)"])
    pane._cvEmpty:Hide()
end
