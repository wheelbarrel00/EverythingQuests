local _, ns = ...

local DD = ns:RegisterSubsystem("TrackerDragDrop", {})

DD.dragQuestID = nil
DD.dropIndex   = nil

local GHOST_THROTTLE_S = 1/30
local _ghostAccum      = 0

local function ghostOnUpdate(_, elapsed)
    _ghostAccum = _ghostAccum + elapsed
    if _ghostAccum < GHOST_THROTTLE_S then return end
    _ghostAccum = 0
    DD:UpdateDragVisuals()
end

local function ensureGhost()
    if DD.ghost then return DD.ghost end
    local g = CreateFrame("Frame", nil, UIParent)
    g:SetSize(220, 24)
    g:SetFrameStrata("TOOLTIP")
    g:Hide()

    local bg = g:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.92, 0.72, 0.02, 0.55)

    local border = g:CreateTexture(nil, "BORDER")
    border:SetAllPoints()
    border:SetColorTexture(0.635, 0.0, 0.039, 1)

    g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    g.text:SetPoint("LEFT",  4, 0)
    g.text:SetPoint("RIGHT", -4, 0)
    g.text:SetJustifyH("LEFT")
    g.text:SetWordWrap(false)
    g.text:SetTextColor(1, 1, 1, 1)

    DD.ghost = g
    return g
end

local function ensureIndicator()
    if DD.indicator then return DD.indicator end
    local i = CreateFrame("Frame", nil, UIParent)
    i:SetHeight(2)
    i:SetFrameStrata("TOOLTIP")
    i:Hide()
    local t = i:CreateTexture(nil, "OVERLAY")
    t:SetAllPoints()
    t:SetColorTexture(0.92, 0.72, 0.02, 1)
    DD.indicator = i
    return i
end

local function isManualMode()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.tracker.sortMode == "manual"
end

function DD:OnBlockDragStart(block)
    if not isManualMode() then return end
    if not block.questID then return end

    self.dragQuestID = block.questID

    local Cache = ns:GetSubsystem("Cache")
    local q = Cache and Cache:Get(block.questID)
    local title = (q and q.title) or ("Quest #" .. tostring(block.questID))

    local g = ensureGhost()
    g.text:SetText(title)
    g:Show()

    ensureIndicator():Show()

    _ghostAccum = 0
    g:SetScript("OnUpdate", ghostOnUpdate)
end

function DD:UpdateDragVisuals()
    if not self.dragQuestID then return end
    local g = self.ghost
    if not g then return end

    local cx, cy = GetCursorPosition()
    local s = g:GetEffectiveScale()
    g:ClearAllPoints()
    g:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / s + 12, cy / s - 24)

    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if not (Blocks and Blocks.active) then return end

    local active = Blocks.active
    local n = #active
    -- Divide the cursor by the BLOCKS' effective scale, not the ghost's - GetTop pairs with
    -- a frame's own scale, and the mismatch offsets the drop line by the Tracker Scale
    local blockScale = (n > 0 and active[1]:GetEffectiveScale()) or s
    local cursorScreenY = cy / blockScale
    local targetIndex = n + 1
    for i = 1, n do
        local b = active[i]
        local top = b:GetTop()
        if top and cursorScreenY > top - (b:GetHeight() * 0.5) then
            targetIndex = i
            break
        end
    end
    self.dropIndex = targetIndex

    local ind = self.indicator
    if not ind then return end
    ind:ClearAllPoints()
    if n == 0 then
        ind:Hide()
        return
    end
    if targetIndex <= n then
        local tgt = active[targetIndex]
        ind:SetPoint("BOTTOMLEFT",  tgt, "TOPLEFT",  0, 1)
        ind:SetPoint("BOTTOMRIGHT", tgt, "TOPRIGHT", 0, 1)
    else
        local last = active[n]
        ind:SetPoint("TOPLEFT",  last, "BOTTOMLEFT",  0, -1)
        ind:SetPoint("TOPRIGHT", last, "BOTTOMRIGHT", 0, -1)
    end
end

function DD:OnBlockDragStop()
    if self.ghost then
        self.ghost:Hide()
        self.ghost:SetScript("OnUpdate", nil)
    end
    if self.indicator then self.indicator:Hide() end

    if self.dragQuestID and self.dropIndex then
        self:Commit(self.dragQuestID, self.dropIndex)
    end
    self.dragQuestID, self.dropIndex = nil, nil
end

function DD:Commit(draggedQuestID, dropIndex)
    local DB = ns:GetSubsystem("DB")
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if not (DB and Blocks and Blocks.active) then return end

    local profile  = DB.db.profile.tracker
    local oldOrder = profile.manualOrder

    local seq = {}
    for i = 1, #Blocks.active do
        local qid = Blocks.active[i].questID
        if qid and qid ~= draggedQuestID then seq[#seq + 1] = qid end
    end

    local insertAt = math.min(math.max(dropIndex, 1), #seq + 1)
    table.insert(seq, insertAt, draggedQuestID)

    local visible = {}
    for i = 1, #seq do visible[seq[i]] = true end

    local Cache  = ns:GetSubsystem("Cache")
    local merged, si = {}, 1
    if oldOrder then
        local masterOld = {}
        for qid in pairs(oldOrder) do masterOld[#masterOld + 1] = qid end
        table.sort(masterOld, function(a, b) return oldOrder[a] < oldOrder[b] end)
        for i = 1, #masterOld do
            local qid = masterOld[i]
            if visible[qid] then
                if si <= #seq then
                    merged[#merged + 1] = seq[si]
                    si = si + 1
                end
            elseif not Cache or (Cache.Get and Cache:Get(qid) ~= nil) then
                merged[#merged + 1] = qid
            end
        end
    end
    while si <= #seq do
        merged[#merged + 1] = seq[si]
        si = si + 1
    end

    local order = {}
    for i = 1, #merged do order[merged[i]] = i end
    profile.manualOrder = order

    local Tracker = ns:GetSubsystem("Tracker")
    if Tracker then Tracker:Refresh() end
end

function DD:WireBlock(block)
    block:RegisterForDrag("LeftButton")
    block:SetScript("OnDragStart", function(b) DD:OnBlockDragStart(b) end)
    block:SetScript("OnDragStop",  function()  DD:OnBlockDragStop()    end)
end
