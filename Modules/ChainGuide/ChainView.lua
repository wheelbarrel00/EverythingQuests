local _, ns = ...
local L = ns.L

local CV = ns:RegisterSubsystem("ChainGuideView", {})

local CELL_W        = 232
local CELL_H        = 46
local COL_PITCH     = 256
local ROW_PITCH     = 72
local GAP           = ROW_PITCH - CELL_H
local PAD_X         = 24
local PAD_Y         = 16
local FAN_PAD       = 8
local FAN_LINE_EDGE = 24
local LINE_PX       = 2
local LANE          = 6
local CROSS_GAP     = 5
local LANE_OFFSETS  = { 0, -LANE, LANE, -2 * LANE, 2 * LANE }
local PAIR          = 65536
local ICON_PX       = 16
local CARD_PAD      = 10
local TEXT_LEFT     = 34
local TITLE_TOP     = 7
local LINE2_TOP     = 26
local NEXT_EDGE     = 3
local TAG_GAP       = 6
local LINE2_MID     = LINE2_TOP + 8
local BRANCH_ALPHA  = 0.55
local HEAD_H        = 76
-- Clear of the window's three 32 px list buttons, which end at 116
local HEAD_LEFT     = 128
local HEAD_SIDE     = 24
local BUTTON_TOP    = 12
local META_TOP      = 48
local META_GAP      = 12
local PROGRESS_W    = 120
local SCROLL_LEAD   = 20
local SEP           = "  \226\128\162  "

local _metaParts = {}
local _nodes     = {}
local _resolved  = {}
local _statuses  = {}
local _reasons   = {}
local _revConn   = {}
local _slotLoserOf   = {}
local _slotWinner    = {}
local _titleRequested = {}
local _fanL, _fanT, _fanR, _fanB = {}, {}, {}, {}
local _segs, _segN = {}, 0
local _laneOff, _laneGroup = {}, {}
local _cuts = {}
local _linePx = LINE_PX

local function slotRank(s)
    if s == "complete" or s == "turnin" or s == "active" then return 4 end
    if s == "chainnav" or s == "available" then return 3 end
    if s == "pending"  then return 2 end
    return 1
end

-- The gossip window's quest icons, an unfinished quest's "?" dimmed
local GOSSIP_AVAILABLE = "Interface\\GossipFrame\\AvailableQuestIcon"
local GOSSIP_ACTIVE    = "Interface\\GossipFrame\\ActiveQuestIcon"
local ICON = {
    available = { file = GOSSIP_AVAILABLE, shade = 1 },
    active    = { file = GOSSIP_ACTIVE,    shade = 0.55 },
    turnin    = { file = GOSSIP_ACTIVE,    shade = 1 },
    complete  = { lib = "check",           color = "muted" },
    skipped   = { lib = "close",           color = "muted" },
    passed    = { lib = "close",           color = "muted" },
    chainnav  = { lib = "chevron-right",   color = "accentHi" },
}
local TITLE_COLOR = {
    complete = "muted", skipped = "muted", passed = "muted", branch = "muted", locked = "muted", pending = "label",
}

local function ui()
    local O = ns:GetSubsystem("Options")
    return O and O.ui
end

local function classicSource()
    return ns:GetSubsystem("ChainGuideClassicSource")
end

-- A quest the data knows only as a link between two others has no Quest Browser page to open
local function hasPage(questID)
    local A = ns:GetSubsystem("AvailableQuests")
    local D = A and A.Data and A:Data()
    return D and D.gates[questID] ~= nil or false
end

local function stripColor(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

CV.nodePool, CV.activeNodes = {}, {}
CV.barPool,  CV.activeBars  = {}, {}
CV.fanPool,  CV.activeFans  = {}, {}

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
    -- A generated chain's statuses move with every accept, turn-in and abandon, so an open window follows the log
    if classicSource() then
        local function logChanged() Events:Debounce("eq.chainview.log", 0.3, rerender) end
        Events:On("QUEST_ACCEPTED",   logChanged)
        Events:On("QUEST_REMOVED",    logChanged)
        Events:On("QUEST_TURNED_IN",  logChanged)
        Events:On("QUEST_LOG_UPDATE", logChanged)
    end
end

local nodeOnEnter, nodeOnLeave, nodeOnClick

local function buildNode(ctx, parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CELL_W, CELL_H)
    ctx:Paint(b, "surface", "surfaceBorder")

    b.hit = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.hit:SetAllPoints()
    b.hit:SetColorTexture(ctx:Color("accentSoft"))
    b.hit:Hide()

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(ctx:Color("hover"))

    b.nextEdge = b:CreateTexture(nil, "ARTWORK")
    b.nextEdge:SetPoint("TOPLEFT")
    b.nextEdge:SetPoint("BOTTOMLEFT")
    b.nextEdge:SetWidth(NEXT_EDGE)
    b.nextEdge:SetColorTexture(ctx:Color("accent"))
    b.nextEdge:Hide()

    b.statusIcon = b:CreateTexture(nil, "OVERLAY")
    b.statusIcon:SetSize(ICON_PX, ICON_PX)
    b.statusIcon:SetPoint("TOPLEFT", CARD_PAD, -(TITLE_TOP + 1))

    b.title = ctx:CreateText(b, "", "value")
    b.title:SetPoint("TOPLEFT", TEXT_LEFT, -TITLE_TOP)
    b.title:SetPoint("TOPRIGHT", -CARD_PAD, -TITLE_TOP)
    b.title:SetWordWrap(false)

    b.tag = ctx:CreateTag(b, "", "accent")
    b.tag:SetPoint("TOPLEFT", TEXT_LEFT, -LINE2_TOP)
    b.tag:Hide()

    b.subtitle = ctx:CreateText(b, "", "hint")
    b.subtitle:SetWordWrap(false)

    b:SetScript("OnEnter", nodeOnEnter)
    b:SetScript("OnLeave", nodeOnLeave)
    b:SetScript("OnClick", nodeOnClick)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return b
end

local propagateClicks

local function propagateActive()
    for _, b in ipairs(CV.activeNodes) do propagateClicks(b) end
end

-- Lets a press reach the canvas so a drag can start on a card, set once combat ends since the call is restricted
propagateClicks = function(b)
    if b._propagates or not b.SetPropagateMouseClicks then return end
    if InCombatLockdown() then
        local Events = ns:GetSubsystem("Events")
        if Events and Events.RunWhenOutOfCombat then Events:RunWhenOutOfCombat("eq.chainview.clicks", propagateActive) end
        return
    end
    b:SetPropagateMouseClicks(true)
    b._propagates = true
end

local function acquireNode(ctx, parent)
    local b = tremove(CV.nodePool)
    if not b then b = buildNode(ctx, parent) end
    propagateClicks(b)
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
        b._ref, b._chain, b._reason, b._status, b._navKind, b._index = nil, nil, nil, nil, nil, nil
        b.statusIcon:SetTexture(nil)
        b.statusIcon:SetTexCoord(0, 1, 0, 1)
        b.statusIcon:SetVertexColor(1, 1, 1, 1)
        b.hit:Hide()
        b.nextEdge:Hide()
        b.tag:Hide()
        b:SetAlpha(1)
        CV.nodePool[#CV.nodePool + 1] = b
        CV.activeNodes[i] = nil
    end
end

local function acquireBar(ctx, canvas)
    local t = tremove(CV.barPool) or canvas:CreateTexture(nil, "BACKGROUND")
    -- A bar lit under the mouse can be handed back by a render the mouse never left
    t:SetColorTexture(ctx:Color("borderStrong"))
    t:SetDrawLayer("BACKGROUND", 0)
    t:Show()
    CV.activeBars[#CV.activeBars + 1] = t
    return t
end

local function releaseBars()
    for i = #CV.activeBars, 1, -1 do
        local t = CV.activeBars[i]
        t:Hide()
        t:ClearAllPoints()
        t._s, t._d = nil, nil
        CV.barPool[#CV.barPool + 1] = t
        CV.activeBars[i] = nil
    end
end

local function acquireFan(ctx, canvas)
    local f = tremove(CV.fanPool)
    if not f then
        f = CreateFrame("Frame", nil, canvas)
        ctx:Paint(f, "chrome", "surfaceBorder")
    end
    -- On the canvas's own level, so the cards in it draw over it
    f:SetFrameLevel(canvas:GetFrameLevel())
    f:Show()
    CV.activeFans[#CV.activeFans + 1] = f
    return f
end

local function releaseFans()
    for i = #CV.activeFans, 1, -1 do
        local f = CV.activeFans[i]
        f:Hide()
        f:ClearAllPoints()
        CV.fanPool[#CV.fanPool + 1] = f
        CV.activeFans[i] = nil
    end
end

-- One straight run of a connector, in canvas units growing down, owned by the link from card s to card d
local function run(ctx, canvas, x1, y1, x2, y2, s, d)
    local bar = acquireBar(ctx, canvas)
    local half = _linePx / 2
    if x1 == x2 then
        bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", x1 - half, -math.min(y1, y2))
        bar:SetSize(_linePx, math.max(_linePx, math.abs(y2 - y1)))
    else
        bar:SetPoint("TOPLEFT", canvas, "TOPLEFT", math.min(x1, x2) - half, -(y1 - half))
        bar:SetSize(math.abs(x2 - x1) + _linePx, _linePx)
    end
    bar._s, bar._d = s, d
end

local function addSeg(x1, y1, x2, y2, s, d, role)
    _segN = _segN + 1
    local sg = _segs[_segN]
    if not sg then sg = {} _segs[_segN] = sg end
    sg.x1, sg.y1, sg.x2, sg.y2, sg.s, sg.d, sg.role = x1, y1, x2, y2, s, d, role
end

-- Down from the source, across in the gap above the child's row, and down into the child, so a split or a
-- merge shares one run. A lane moves the run up or down in that gap.
local function elbow(x1, y1, x2, y2, s, d, off)
    local mid = y2 - GAP / 2 + (off or 0)
    addSeg(x1, y1, x1, mid, s, d, "s")
    if x1 ~= x2 then addSeg(x1, mid, x2, mid, s, d, "h") end
    addSeg(x2, mid, x2, y2, s, d, "d")
end

-- Two cards side by side in one row, as a curated retail chain can place them, are joined straight across
local function link(sx, sy, dx, dy, s, d)
    if sy ~= dy then
        elbow(sx + CELL_W / 2, sy + CELL_H, dx + CELL_W / 2, dy, s, d, _laneOff[s * PAIR + d])
        return
    end
    local y = sy + CELL_H / 2
    if sx < dx then addSeg(sx + CELL_W, y, dx, y, s, d, "h") else addSeg(dx + CELL_W, y, sx, y, s, d, "h") end
end

local function byLoHi(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    return a.hi < b.hi
end

local function byLane(a, b)
    if a.lo ~= b.lo then return a.lo < b.lo end
    if a.hi ~= b.hi then return a.hi > b.hi end
    return a.dsts[1] < b.dsts[1]
end

-- A run that reads as one line but joins a source to a child it does not lead to
local function misleads(list, i, j)
    local srcs, dsts, have = {}, {}, {}
    for k = i, j do
        local l = list[k]
        srcs[l.s], dsts[l.d], have[l.s * PAIR + l.d] = true, true, true
    end
    for s in pairs(srcs) do
        for d in pairs(dsts) do
            if not have[s * PAIR + d] then return true end
        end
    end
    return false
end

-- Each set of children with the same sources gets its own lane, and sets whose spans meet take different ones
local function giveLanes(list, i, j, cols)
    local srcsOf, order = {}, {}
    for k = i, j do
        local l = list[k]
        local t = srcsOf[l.d]
        if not t then t = {} srcsOf[l.d] = t order[#order + 1] = l.d end
        t[#t + 1] = l.s
    end
    table.sort(order)
    local groups, byKey = {}, {}
    for _, d in ipairs(order) do
        local srcs = srcsOf[d]
        table.sort(srcs)
        local key = table.concat(srcs, ",")
        local g = byKey[key]
        if not g then
            g = { srcs = srcs, dsts = {}, src = {}, dst = {} }
            for _, s in ipairs(srcs) do g.src[s] = true end
            byKey[key] = g
            groups[#groups + 1] = g
        end
        g.dsts[#g.dsts + 1] = d
        g.dst[d] = true
    end
    for _, g in ipairs(groups) do
        local lo, hi = math.huge, -math.huge
        for _, s in ipairs(g.srcs) do lo, hi = math.min(lo, cols[s]), math.max(hi, cols[s]) end
        for _, d in ipairs(g.dsts) do lo, hi = math.min(lo, cols[d]), math.max(hi, cols[d]) end
        g.lo, g.hi = lo, hi
    end
    table.sort(groups, byLane)
    local placed = {}
    for _, g in ipairs(groups) do
        local lane, clash = 1, true
        while clash do
            clash = false
            for _, p in ipairs(placed) do
                if p.lane == lane and not (p.hi < g.lo or g.hi < p.lo) then clash = true break end
            end
            if clash then lane = lane + 1 end
        end
        g.lane = lane
        placed[#placed + 1] = g
        local off = LANE_OFFSETS[math.min(lane, #LANE_OFFSETS)]
        for _, s in ipairs(g.srcs) do
            for _, d in ipairs(g.dsts) do
                _laneOff[s * PAIR + d], _laneGroup[s * PAIR + d] = off, g
            end
        end
    end
end

-- Links into one row whose runs overlap or touch read as one line, so only a row where that line misleads
-- gets lanes, and every other row draws its runs where it always has
local function assignLanes(links, cols)
    wipe(_laneOff)
    wipe(_laneGroup)
    local byRow = {}
    for _, l in ipairs(links) do
        local list = byRow[l.row]
        if not list then list = {} byRow[l.row] = list end
        list[#list + 1] = l
    end
    for _, list in pairs(byRow) do
        table.sort(list, byLoHi)
        local i = 1
        while i <= #list do
            local j, hi = i, list[i].hi
            while j < #list and list[j + 1].lo <= hi do
                j = j + 1
                if list[j].hi > hi then hi = list[j].hi end
            end
            if misleads(list, i, j) then giveLanes(list, i, j, cols) end
            i = j + 1
        end
    end
end

local function joins(v, g)
    return (v.role == "s" and g.src[v.s]) or (v.role == "d" and g.dst[v.d]) or false
end

-- A lane breaks where a line that does not join it crosses, so the two never read as touching
local function drawSegs(ctx, canvas)
    for k = 1, _segN do
        local sg = _segs[k]
        local g = sg.role == "h" and sg.y1 == sg.y2 and sg.d and _laneGroup[sg.s * PAIR + sg.d]
        if g then
            local lo, hi, y = math.min(sg.x1, sg.x2), math.max(sg.x1, sg.x2), sg.y1
            wipe(_cuts)
            for m = 1, _segN do
                local v = _segs[m]
                if v.x1 == v.x2 and v.y1 ~= v.y2 and not joins(v, g) then
                    local vlo, vhi = math.min(v.y1, v.y2), math.max(v.y1, v.y2)
                    if v.x1 > lo and v.x1 < hi and vlo < y and vhi > y then _cuts[#_cuts + 1] = v.x1 end
                end
            end
            table.sort(_cuts)
            local x = lo
            for _, c in ipairs(_cuts) do
                if c - CROSS_GAP > x then run(ctx, canvas, x, y, c - CROSS_GAP, y, sg.s, sg.d) end
                x = math.max(x, c + CROSS_GAP)
            end
            if hi > x then run(ctx, canvas, x, y, hi, y, sg.s, sg.d) end
        else
            run(ctx, canvas, sg.x1, sg.y1, sg.x2, sg.y2, sg.s, sg.d)
        end
    end
end

-- The lines into and out of the card under the mouse take the accent, drawn over the rest. A fan's
-- quests share their one line, the one into the panel from its hub
function CV:LightLinks(index, hub)
    local ctx = ui()
    if not ctx then return end
    for _, bar in ipairs(self.activeBars) do
        local hot = index ~= nil and (bar._s == index or bar._d == index or (hub ~= nil and bar._s == hub and bar._d == nil))
        bar:SetColorTexture(ctx:Color(hot and "accentHi" or "borderStrong"))
        bar:SetDrawLayer("BACKGROUND", hot and 1 or 0)
    end
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

-- EQ's own tooltip, which the library hides when a drag starts and when the window closes
local function cardTip()
    return ns.Util.PinTooltip()
end

local function buildQuestTooltip(item, statusKey)
    local tip = cardTip()
    local title = ns.Util.QuestTitle(item.id) or item.name or ("Quest #" .. tostring(item.id))
    tip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    tip:SetText(title, 1, 0.82, 0)
    if statusKey == "complete" then
        tip:AddLine(L["Completed"], 0.5, 1, 0.5)
    elseif statusKey == "turnin" then
        tip:AddLine(L["Ready to turn in"], 1, 0.82, 0)
    elseif statusKey == "active" then
        tip:AddLine(L["In your quest log"], 1, 1, 1)
    elseif statusKey == "skipped" then
        tip:AddLine(L["Skipped"], 1.0, 0.65, 0.0)
        tip:AddLine(L["A later quest in this chain has already passed this one."], 0.7, 0.7, 0.7, true)
        tip:AddLine(L["May be worth going back to pick up."], 0.7, 0.7, 0.7, true)
    else
        tip:AddLine(L["Not started"], 0.7, 0.7, 0.7)
    end
    tip:AddLine("ID: " .. tostring(item.id), 0.5, 0.5, 0.5)

    -- GetQuestDifficultyLevel returns 0 until quest data is cached
    if item.id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel then
        local lvl = C_QuestLog.GetQuestDifficultyLevel(item.id)
        if lvl and lvl > 0 then
            local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
            if c then
                tip:AddLine((L["Level %d"]):format(lvl), c.r, c.g, c.b)
            else
                tip:AddLine((L["Level %d"]):format(lvl), 0.8, 0.8, 0.8)
            end
        end
    end

    if item.id then
        if QuestUtil and QuestUtil.GetQuestClassificationDetails then
            local cls, ctext = QuestUtil.GetQuestClassificationDetails(item.id, true)
            -- A Questline classification says nothing inside a chain
            local isPlainStoryline = Enum and Enum.QuestClassification
                                     and cls == Enum.QuestClassification.Questline
            if ctext and ctext ~= "" and not isPlainStoryline then
                tip:AddLine(ctext, 0.90, 0.78, 0.45)
            end
        end
        if C_QuestLog and C_QuestLog.GetQuestTagInfo then
            local tag = C_QuestLog.GetQuestTagInfo(item.id)
            if tag and tag.tagName and tag.tagName ~= "" then
                tip:AddLine(tag.tagName, 0.55, 0.75, 0.95)
            end
        end
    end

    local R = ns:GetSubsystem("History")
    if R and R.GetCompletionTime then
        local t = R:GetCompletionTime(item.id)
        if t then
            if t > 0 then
                tip:AddLine(L["Completed: "] .. date("%Y-%m-%d %H:%M", t), 0.55, 0.85, 0.55)
            else
                tip:AddLine(L["Completed (before tracking)"], 0.55, 0.85, 0.55)
            end
        end
    end

    local QR = ns:GetSubsystem("QuestRewards")
    if QR then
        -- Completed quests are gone from the log and the API reports their objectives as 0/N, so skip them
        if statusKey ~= "complete" then
            local hadObjectives = QR:RenderObjectives(tip, item.id)
            if hadObjectives then tip:AddLine(" ") end
        end
        QR:RenderRewards(tip, item.id)
    end

    tip:AddLine(" ")
    tip:AddLine(L["Shift-click to link in chat"], 0.6, 0.6, 0.6)
    tip:Show()
end

local function addPlace(header, p)
    if not p then return end
    local tip = cardTip()
    local QBD  = ns:GetSubsystem("QuestBrowserData")
    local QB   = ns:GetSubsystem("QuestBrowser")
    local zone = (QBD and QBD:ZoneName(p.mapID)) or ("map " .. tostring(p.mapID))
    local who  = p.name or (QB and QB.SourceText and QB:SourceText(p.kind))
    tip:AddLine(header, 0.92, 0.72, 0.02)
    tip:AddLine(who and (who .. "  -  " .. zone) or zone, 0.8, 0.8, 0.8, true)
end

-- Described from the shipped tables, as the Quest Browser's page is
local function buildClassicTooltip(item, statusKey, reason)
    local tip = cardTip()
    local CS = classicSource()
    local A  = ns:GetSubsystem("AvailableQuests")
    local QB = ns:GetSubsystem("QuestBrowser")
    tip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    tip:SetText(CS:Title(item.id), 1, 0.82, 0)
    if statusKey == "complete" then
        tip:AddLine(L["Completed"], 0.5, 1, 0.5)
    elseif statusKey == "turnin" then
        tip:AddLine(L["Ready to turn in"], 1, 0.82, 0)
    elseif statusKey == "active" then
        tip:AddLine(L["In your quest log"], 1, 1, 1)
    elseif statusKey == "available" then
        tip:AddLine(L["You can pick this up now."], 0.3, 1, 0.3)
    else
        local why = reason and QB and QB.ReasonText and QB:ReasonText(reason)
        if why then
            tip:AddLine(why, 1, 0.6, 0.3, true)
        else
            tip:AddLine(L["Not started"], 0.7, 0.7, 0.7)
        end
    end

    local lvl = A and A:QuestLevel(item.id)
    if lvl then
        local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
        if c then
            tip:AddLine((L["Level %d"]):format(lvl), c.r, c.g, c.b)
        else
            tip:AddLine((L["Level %d"]):format(lvl), 0.8, 0.8, 0.8)
        end
    end
    local req = A and A:RequiredLevel(item.id)
    if req and req > 1 then
        tip:AddLine((L["Requires level %d"]):format(req), 0.8, 0.8, 0.8)
    end

    addPlace(L["Starts"], CS:StartPoint(item.id))
    addPlace(L["Turn in"], CS:FinishPoint(item.id))
    tip:AddLine("ID: " .. tostring(item.id), 0.5, 0.5, 0.5)

    tip:AddLine(" ")
    tip:AddLine(L["Shift-click to link in chat"], 0.6, 0.6, 0.6)
    if QB and QB.Open and hasPage(item.id) then tip:AddLine(L["Right-click for quest details"], 0.6, 0.6, 0.6) end
    tip:Show()
end

local function buildChainNavTooltip(item)
    local tip = cardTip()
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local sub = Database and Database.chains[item.id]
    tip:SetOwner(UIParent, "ANCHOR_CURSOR_RIGHT")
    tip:SetText((sub and sub.name) or ("Chain #" .. tostring(item.id)), 0.92, 0.72, 0.02)
    if sub and sub.range then
        tip:AddLine((L["Level %d–%d"]):format(sub.range[1], sub.range[2]), 0.7, 0.7, 0.7)
    end
    tip:AddLine(L["Click to open this chain"], 1, 1, 1)
    tip:Show()
end

local function onNodeClickQuest(item, chain)
    -- Through QuestLink like every other producer, so a rebound chat-link modifier works here too
    local QLink = ns:GetSubsystem("QuestLink")
    if QLink and QLink:WantsShare() and QLink:Share(item.id) then return end
    local WP = ns:GetSubsystem("ChainGuideWaypoint")
    if WP and WP.GoTo then WP:GoTo(item.id, chain) end
end

local function onNodeClickChain(item)
    local CG = ns:GetSubsystem("ChainGuide")
    if CG and CG.NavigateChain then CG:NavigateChain(item.id) end
end

local function areaOf(node)
    local canvas = node:GetParent()
    return canvas and canvas._area
end

function nodeOnEnter(self)
    local area = areaOf(self)
    if area and area:IsPanGesture() then return end
    CV:LightLinks(self._index, self._fan)
    if self._navKind == "chain" then
        buildChainNavTooltip(self._ref)
    elseif self._chain and self._chain._generated and classicSource() then
        buildClassicTooltip(self._ref, self._status, self._reason)
    else
        buildQuestTooltip(self._ref, self._status)
    end
end

function nodeOnLeave()
    CV:LightLinks(nil)
    cardTip():Hide()
end

function nodeOnClick(self, button)
    local area = areaOf(self)
    if area and area:IsPanGesture() then return end
    -- Only a generated chain's quest has a Quest Browser page, so a right-click does nothing anywhere else
    if button == "RightButton" then
        if self._navKind ~= "chain" and self._chain and self._chain._generated and hasPage(self._ref.id) then
            local QB = ns:GetSubsystem("QuestBrowser")
            if QB and QB.Open then QB:Open(self._ref.id) end
        end
        return
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
    local minCol, maxCol, maxRow = 0, 0, 0
    for i = 1, n do
        local it = items[i]
        local col = it.x or depth[i] or 0
        local row = it.y
        if row == nil then
            row = rowCursor[col] or 0
            rowCursor[col] = row + 1
        end
        cols[i], rows[i] = col, row
        if col < minCol then minCol = col end
        if col > maxCol then maxCol = col end
        if row > maxRow then maxRow = row end
    end
    -- A curated layout can start left of the first column (Zul'Aman's 90483 sits at -0.5)
    if minCol < 0 then
        for i = 1, n do cols[i] = cols[i] - minCol end
        maxCol = maxCol - minCol
    end
    return cols, rows, maxCol, maxRow
end

local function showHeader(pane, on)
    pane._cvTitle:SetShown(on)
    pane._cvMeta:SetShown(on)
    pane._cvProgress:SetShown(on)
    pane._cvTrack:SetShown(on)
    if not on then pane._cvContinue:Hide() end
end

local function showEmpty(pane, text)
    pane._cvEmpty:SetText(text or "")
    pane._cvEmpty:SetShown(text ~= nil)
end

local function setMeta(pane, chain, complete, active, total, skipped, oneLevel)
    wipe(_metaParts)
    if chain.range then
        local lo, hi = chain.range[1], chain.range[2]
        if oneLevel and lo == hi then
            _metaParts[#_metaParts + 1] = (L["Level %d"]):format(lo)
        else
            _metaParts[#_metaParts + 1] = (L["Level %d–%d"]):format(lo, hi)
        end
    end
    if total > 0 then
        _metaParts[#_metaParts + 1] = (L["%d/%d done"]):format(complete, total)
        if active > 0 then _metaParts[#_metaParts + 1] = (L["%d active"]):format(active) end
        if skipped and skipped > 0 then
            _metaParts[#_metaParts + 1] = stripColor((L["|cffff9933%d skipped|r"]):format(skipped))
        end
    end
    local meta = pane._cvMeta
    meta:SetWidth(0)
    meta:SetText(table.concat(_metaParts, SEP))
    -- Cut short of the header's right edge, so the progress bar after it stays inside the window
    local room = (pane._cvHead:GetWidth() or 0) - HEAD_LEFT - HEAD_SIDE - META_GAP - PROGRESS_W
    if room > 0 and (meta:GetStringWidth() or 0) > room then meta:SetWidth(room) end
    pane._cvProgress:SetProgress(total > 0 and complete / total or 0)
end

function CV:Render(pane, chain, highlightQuestID, again)
    local ctx = ui()
    self:_ensureUI(pane, ctx)
    releaseNodes()
    releaseBars()
    releaseFans()

    local area = pane._cvArea
    pane._cvContinue:Hide()
    pane._cvContinue._nextID, pane._cvContinue._chain = nil, nil

    -- Scrolls only for a new chain or quest, a chain's first render with quests, or a quest named again
    local navChanged = again or (chain ~= pane._cvScrolledChain)
                       or (highlightQuestID ~= pane._cvScrolledHighlight)
                       or (chain ~= pane._cvRenderedChain)
    pane._cvScrolledChain     = chain
    pane._cvScrolledHighlight = highlightQuestID

    if not chain then
        showHeader(pane, false)
        area:SetContentSize(1, 1)
        local CG = ns:GetSubsystem("ChainGuide")
        showEmpty(pane, (CG and CG._railCollapsed) and L["Show the navigation panel to pick a chain."]
                        or L["Pick a chain on the left to view its quests."])
        return
    end
    showHeader(pane, true)

    local CG = ns:GetSubsystem("ChainGuide")
    pane._cvTrack._chainID = chain.id
    local tracking = CG and chain.id and CG:IsTrackingChain(chain.id)
    pane._cvTrack:SetText(tracking and L["Untrack"] or L["Track"])
    if pane._cvTrack.Fit then pane._cvTrack:Fit() end

    local Database   = ns:GetSubsystem("ChainGuideDatabase")
    local Characters = ns:GetSubsystem("ChainGuideCharacters")
    local QLS        = ns:GetSubsystem("ChainGuideQuestLineSource")
    if QLS then QLS:EnsureChainItems(chain) end
    Database:NormalizeChain(chain)

    pane._cvTitle:SetText(chain.name or "Chain")
    local items = chain.items
    if not items or #items == 0 then
        local complete, active, total = Characters:ChainProgress(chain)
        setMeta(pane, chain, complete, active, total)
        area:SetContentSize(1, 1)
        showEmpty(pane, L["(no quests defined for this chain yet)"])
        return
    end
    showEmpty(pane, nil)

    local cols, rows, maxCol, maxRow = computeLayout(items)
    local insetX = 0
    for i = 1, #items do
        if items[i].fan then insetX = FAN_PAD; break end
    end
    local contentW = maxCol * COL_PITCH + CELL_W + insetX * 2
    local contentH = maxRow * ROW_PITCH + CELL_H + insetX * 2
    -- A chain narrower than the view is centered in it
    local viewW = area.scroll and area.scroll:GetWidth() or 0
    local left = PAD_X + insetX
    -- Whole units, as an uncentered chain's are
    if viewW > contentW + PAD_X * 2 then left = math.floor((viewW - contentW) / 2) + insetX end
    local top = PAD_Y + insetX
    local function cellX(col) return left + col * COL_PITCH end
    local function cellY(row) return top + row * ROW_PITCH end

    local char = Database:CurrentCharacter()
    local CS = chain._generated and classicSource() or nil
    local A  = CS and ns:GetSubsystem("AvailableQuests")

    wipe(_resolved)
    wipe(_statuses)
    wipe(_reasons)
    for i = 1, #items do
        local resolved = Database:GetVariation(items[i], char)
        _resolved[i] = resolved
        if resolved.type == "chain" then
            _statuses[i] = "chainnav"
        elseif CS then
            _statuses[i], _reasons[i] = CS:Status(resolved.id)
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
        -- A generated chain's status already marks a quest whose later step is done, so only those count as skipped
        if CS then
            if _statuses[i] == "passed" then skippedCount = skippedCount + 1 end
        elseif _statuses[i] == "pending" and not _resolved[i].breadcrumb and not _slotLoserOf[i] then
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

    local complete, active, total = Characters:ChainProgress(chain)
    setMeta(pane, chain, complete, active, total, skippedCount, CS ~= nil)

    local WP       = ns:GetSubsystem("ChainGuideWaypoint")
    local nextStep = WP and WP.NextActionableStep and WP:NextActionableStep(chain)
    local nextID   = nextStep and nextStep.id

    wipe(_nodes)
    local nodes = _nodes
    local canvas = area.content
    local highlightRow, highlightCol, nextRow, nextCol
    for i = 1, #items do
        local resolved = _resolved[i]
        local node = acquireNode(ctx, canvas)
        node:SetPoint("TOPLEFT", canvas, "TOPLEFT", cellX(cols[i]), -cellY(rows[i]))

        local statusKey = _statuses[i]
        local title, line2
        local inLog, isNext = false, false
        if resolved.type == "chain" then
            local sub = Database.chains[resolved.id]
            title = (sub and sub.name) or ("Chain #" .. tostring(resolved.id))
            statusKey = "chainnav"
            if sub then
                local sc, _, st = Characters:ChainProgress(sub)
                if st > 0 then
                    line2 = (L["%d/%d done"]):format(sc, st)
                    if sc >= st then statusKey = "complete" end
                else
                    line2 = "View chain >"
                end
            else
                line2 = "View chain >"
            end
        else
            local id = resolved.id
            local lvl
            -- A generated chain takes its titles from the client and the shipped tables, so it never asks the server
            if CS then
                title = CS:Title(id)
                lvl   = A and A:QuestLevel(id)
            else
                local cached = ns.Util.QuestTitle(id)
                if (not cached) and id and not _titleRequested[id]
                   and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
                    _titleRequested[id] = true
                    C_QuestLog.RequestLoadQuestByID(id)
                end
                title = resolved.name or cached or ("Quest #" .. tostring(id))
                lvl   = id and C_QuestLog and C_QuestLog.GetQuestDifficultyLevel
                        and C_QuestLog.GetQuestDifficultyLevel(id)
            end
            local parts = {}
            if lvl and lvl > 0 then parts[#parts + 1] = (L["Level %d"]):format(lvl) end
            if statusKey == "passed" or statusKey == "skipped" then
                parts[#parts + 1] = L["Skipped"]
            elseif CS then
                local p = CS:StartPoint(id)
                if p and p.name then parts[#parts + 1] = p.name end
            end
            line2 = table.concat(parts, SEP)
            inLog = statusKey == "active" or statusKey == "turnin"
            isNext = id ~= nil and nextID ~= nil and id == nextID
        end

        if resolved.breadcrumb then
            line2 = L["(optional)"]
        end

        node.title:SetText(title)
        node.title:SetTextColor(ctx:Color((resolved.breadcrumb and "muted") or TITLE_COLOR[statusKey] or "text"))
        node:SetAlpha(statusKey == "branch" and BRANCH_ALPHA or 1)

        node.subtitle:ClearAllPoints()
        if inLog or isNext then
            node.tag:SetText(inLog and L["ON QUEST"] or L["NEXT"])
            node.tag:SetStyle(inLog and "outline" or "accent")
            node.tag:Show()
            node.subtitle:SetPoint("LEFT", node.tag, "RIGHT", TAG_GAP, 0)
        else
            node.subtitle:SetPoint("LEFT", node, "TOPLEFT", TEXT_LEFT, -LINE2_MID)
        end
        node.subtitle:SetPoint("RIGHT", node, "TOPRIGHT", -CARD_PAD, -LINE2_MID)
        node.subtitle:SetText(line2 or "")
        node.nextEdge:SetShown(isNext)

        local icon = ICON[statusKey]
        if icon and icon.file then
            node.statusIcon:SetTexture(icon.file)
            node.statusIcon:SetVertexColor(icon.shade, icon.shade, icon.shade, 1)
            node.statusIcon:Show()
        elseif icon then
            node.statusIcon:SetTexture(ctx:Texture(icon.lib))
            node.statusIcon:SetVertexColor(ctx:Color(icon.color))
            node.statusIcon:Show()
        else
            node.statusIcon:Hide()
        end

        node._index   = i
        node._fan     = items[i].fan
        node._ref     = resolved
        node._status  = statusKey
        node._reason  = _reasons[i]
        node._chain   = chain
        node._navKind = (resolved.type == "chain") and "chain" or "quest"

        if highlightQuestID and resolved.type ~= "chain" and resolved.id == highlightQuestID then
            node.hit:Show()
            highlightRow, highlightCol = rows[i], cols[i]
        end
        if isNext then nextRow, nextCol = rows[i], cols[i] end

        nodes[i] = node
        if _slotLoserOf[i] then
            node:Hide()
            nodes[i] = nil
        end
    end

    wipe(_fanL); wipe(_fanT); wipe(_fanR); wipe(_fanB)
    for i = 1, #items do
        local hub = items[i].fan
        if hub and nodes[i] and nodes[hub] then
            if not _fanL[hub] then
                _fanL[hub], _fanT[hub], _fanR[hub], _fanB[hub] = cols[i], rows[i], cols[i], rows[i]
            else
                _fanL[hub], _fanT[hub] = math.min(_fanL[hub], cols[i]), math.min(_fanT[hub], rows[i])
                _fanR[hub], _fanB[hub] = math.max(_fanR[hub], cols[i]), math.max(_fanB[hub], rows[i])
            end
        end
    end
    -- Whole screen pixels, so every line draws the same width wherever it falls
    _linePx = (PixelUtil and PixelUtil.GetNearestPixelSize and canvas.GetEffectiveScale)
              and PixelUtil.GetNearestPixelSize(LINE_PX, canvas:GetEffectiveScale(), LINE_PX) or LINE_PX
    _segN = 0
    -- One panel and one line for a wrapped fan, since a line to each of its quests would run through the rows above
    for hub in pairs(_fanL) do
        local fx, fy = cellX(_fanL[hub]) - FAN_PAD, cellY(_fanT[hub]) - FAN_PAD
        local fw = (_fanR[hub] - _fanL[hub]) * COL_PITCH + CELL_W + FAN_PAD * 2
        local fh = (_fanB[hub] - _fanT[hub]) * ROW_PITCH + CELL_H + FAN_PAD * 2
        local panel = acquireFan(ctx, canvas)
        panel:SetPoint("TOPLEFT", canvas, "TOPLEFT", fx, -fy)
        panel:SetSize(fw, fh)
        local hx = cellX(cols[hub]) + CELL_W / 2
        local lx = math.min(math.max(hx, fx + FAN_LINE_EDGE), fx + fw - FAN_LINE_EDGE)
        elbow(hx, cellY(rows[hub]) + CELL_H, lx, fy, hub, nil)
    end

    local links = {}
    for i = 1, #items do
        local it = items[i]
        if it.connections and nodes[i] and not (it.fan and _fanL[it.fan]) then
            for _, src in ipairs(it.connections) do
                if nodes[src] and rows[src] ~= rows[i] then
                    links[#links + 1] = { s = src, d = i, row = rows[i],
                                          lo = math.min(cols[src], cols[i]), hi = math.max(cols[src], cols[i]) }
                end
            end
        end
    end
    assignLanes(links, cols)
    for i = 1, #items do
        local it = items[i]
        if it.connections and nodes[i] and not (it.fan and _fanL[it.fan]) then
            for _, src in ipairs(it.connections) do
                if nodes[src] then
                    link(cellX(cols[src]), cellY(rows[src]), cellX(cols[i]), cellY(rows[i]), src, i)
                end
            end
        end
    end
    drawSegs(ctx, canvas)
    -- A render under the mouse sends no OnEnter, so the card with the mouse is entered again, lines and tooltip
    for i = 1, #items do
        if nodes[i] and nodes[i]:IsMouseMotionFocus() then nodeOnEnter(nodes[i]) break end
    end

    -- At least the view's size, since the wheel and the drag live on the content
    local viewH = area.scroll and area.scroll:GetHeight() or 0
    area:SetContentSize(math.max(contentW + PAD_X * 2, viewW), math.max(contentH + PAD_Y * 2, viewH))

    if nextStep and nextID then
        pane._cvContinue._nextID = nextID
        pane._cvContinue._chain  = chain
        if pane._cvContinue.Fit then pane._cvContinue:Fit() end
        pane._cvContinue:Show()
    end

    pane._cvRenderedChain = chain

    local scrollRow = highlightRow or nextRow
    local scrollCol = highlightRow and highlightCol or nextCol
    -- A generated chain opens at its top left corner, unless a search or link named a quest
    local topLeft = CS and not highlightRow
    if (scrollRow or topLeft) and navChanged then
        pane._cvScrollY = topLeft and 0 or math.max(0, cellY(scrollRow) - SCROLL_LEAD)
        pane._cvScrollX = topLeft and 0 or math.max(0, cellX(scrollCol or 0) - math.max(0, (viewW - CELL_W) * 0.5))
        C_Timer.After(0, pane._cvDoScroll)
    else
        C_Timer.After(0, pane._cvClampScroll)
    end
end

function CV:_ensureUI(pane, ctx)
    if pane._cvBuilt then return end
    pane._cvBuilt = true

    local head = CreateFrame("Frame", nil, pane)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(HEAD_H)
    ctx:Paint(head, nil, "divider", "B")
    pane._cvHead = head

    pane._cvContinue = ctx:CreateButton(head, L["Continue"], nil, onContinueClick, nil, "primary")
    pane._cvContinue:SetPoint("TOPRIGHT", head, "TOPRIGHT", -HEAD_SIDE, -BUTTON_TOP)
    pane._cvContinue:Hide()

    pane._cvTrack = ctx:CreateButton(head, L["Track"], nil, onTrackClick)
    pane._cvTrack:SetPoint("TOPRIGHT", pane._cvContinue, "TOPLEFT", -ctx:Spacing("buttonGap"), 0)
    ctx:AttachTooltip(pane._cvTrack, L["Track this chain"],
        L["Follow this chain — its quests pin on the world map (next step highlighted) and your waypoint auto-advances to the next step as you complete it. Works even with this window closed. Click again to stop."])

    pane._cvTitle = ctx:CreateText(head, "", "title")
    pane._cvTitle:SetPoint("LEFT", head, "TOPLEFT", HEAD_LEFT, -(BUTTON_TOP + 16))
    pane._cvTitle:SetPoint("RIGHT", pane._cvTrack, "LEFT", -META_GAP, 0)
    pane._cvTitle:SetWordWrap(false)

    pane._cvMeta = ctx:CreateText(head, "", "hint")
    pane._cvMeta:SetPoint("TOPLEFT", head, "TOPLEFT", HEAD_LEFT, -META_TOP)
    pane._cvMeta:SetWordWrap(false)

    pane._cvProgress = ctx:CreateProgressBar(head, PROGRESS_W)
    pane._cvProgress:SetPoint("LEFT", pane._cvMeta, "RIGHT", META_GAP, 0)

    local area = ctx:CreateScrollArea(pane, { pan = true, wheelStep = ROW_PITCH })
    area:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -1)
    area:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT")
    pane._cvArea = area

    pane._cvEmpty = ctx:CreateEmptyState(area, "")
    pane._cvEmpty:Hide()

    pane._cvDoScroll = function()
        if not area:IsShown() or area:IsPanGesture() then return end
        area:ScrollTo(pane._cvScrollX or 0, pane._cvScrollY or 0)
    end

    pane._cvClampScroll = function()
        if not area:IsShown() or area:IsPanGesture() then return end
        area:ClampScroll()
    end
end
