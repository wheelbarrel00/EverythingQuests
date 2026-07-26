local _, ns = ...

local IB = ns:RegisterSubsystem("TrackerItemButtons", {})

local BTN = 26
local ITEM_GAP = 6
local RANGE_THROTTLE = 0.25

-- Read padding from Blocks rather than mirroring a copy - a stale copy puts the button on the card border
local function blockPadding()
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if Blocks and Blocks.Padding then return Blocks:Padding() end
    return 6, 2
end

IB.buttons   = {}
local pool   = {}
local deferFns = {}
local wanted = {}
local stale  = {}
local container

local function getContainer()
    if container then return container end
    local Tracker = ns:GetSubsystem("Tracker")
    local content = Tracker and Tracker.frame and Tracker.frame.content
    if not content then return nil end
    container = CreateFrame("Frame", nil, content)
    container:SetAllPoints(content)
    container:SetFrameLevel((content:GetFrameLevel() or 0) + 20)
    return container
end

local function itemInfo(questID)
    if not (C_QuestLog and C_QuestLog.GetLogIndexForQuestID
            and GetQuestLogSpecialItemInfo) then return nil end
    local idx = C_QuestLog.GetLogIndexForQuestID(questID)
    if not idx then return nil end
    local link, icon, charges = GetQuestLogSpecialItemInfo(idx)
    if link and icon then return link, icon, charges, idx end
    return nil
end

-- IsQuestLogSpecialItemInRange returns 0 = out, 1 = in, nil = no range concept.
local function onRangeUpdate(self, elapsed)
    local t = (self._rangeTimer or 0) - elapsed
    if t > 0 then self._rangeTimer = t; return end
    self._rangeTimer = RANGE_THROTTLE

    local qid = self._questID
    if not (qid and IsQuestLogSpecialItemInRange
            and C_QuestLog and C_QuestLog.GetLogIndexForQuestID) then return end
    local idx = C_QuestLog.GetLogIndexForQuestID(qid)
    if not idx then return end
    if IsQuestLogSpecialItemInRange(idx) == 0 then
        self.icon:SetVertexColor(1.0, 0.3, 0.3)
    else
        self.icon:SetVertexColor(1.0, 1.0, 1.0)
    end
end

local function buildButton()
    local b = CreateFrame("Button", nil, container, "SecureActionButtonTemplate")
    b:SetSize(BTN, BTN)
    -- SecureActionButton needs both AnyDown and AnyUp - AnyUp alone frequently misses the secure use
    b:RegisterForClicks("AnyDown", "AnyUp")
    b:SetAttribute("type", "item")

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.count:SetPoint("BOTTOMRIGHT", -1, 1)

    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()

    b:SetScript("OnUpdate", onRangeUpdate)
    b:Hide()
    return b
end

function IB:_applySecure(questID)
    if not getContainer() then return end
    local DB    = ns:GetSubsystem("DB")
    local on    = not DB or DB.db.profile.tracker.showItemButtons ~= false
    local link  = on and itemInfo(questID) or nil
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    local block = Blocks and Blocks.byID and Blocks.byID[questID]
    local b     = self.buttons[questID]

    if not (link and block) then
        if b then
            b:Hide()
            b:ClearAllPoints()
            b._questID    = nil
            b._rangeTimer = nil
            self.buttons[questID] = nil
            pool[#pool + 1] = b
        end
        return
    end

    if not b then
        b = tremove(pool) or buildButton()
        self.buttons[questID] = b
    end
    b._questID    = questID
    b._rangeTimer = 0
    b:SetAttribute("item", link)
    b:ClearAllPoints()
    -- Anchor to the container, NOT the block - a secure anchor-family block makes
    -- Show/Hide/SetPoint on it ADDON_ACTION_BLOCKED in combat
    local cl, ct = container:GetLeft(), container:GetTop()
    local bl, bt = block:GetLeft(), block:GetTop()
    if cl and ct and bl and bt then
        local padX, padY = blockPadding()
        b:SetPoint("TOPLEFT", container, "TOPLEFT", (bl - cl) + padX, (bt - ct) - padY)
        b:Show()
    else
        b:Hide()
    end
end

local function paint(b, questID)
    local _, icon, charges, idx = itemInfo(questID)
    if not icon then return end
    b.icon:SetTexture(icon)
    if charges and charges > 1 then
        b.count:SetText(charges); b.count:Show()
    else
        b.count:SetText(""); b.count:Hide()
    end
    if idx and GetQuestLogSpecialItemCooldown then
        local s, d = GetQuestLogSpecialItemCooldown(idx)
        if s and d and d > 0 then b.cd:SetCooldown(s, d) else b.cd:Clear() end
    end
end

local function deferFn(questID)
    local f = deferFns[questID]
    if not f then
        f = function()
            IB:_applySecure(questID)
            -- Paint here too or the combat-end flush leaves the button blank until an unrelated render
            local b = IB.buttons[questID]
            if b and b:IsShown() then paint(b, questID) end
        end
        deferFns[questID] = f
    end
    return f
end

local function applySecure(questID)
    local Events = ns:GetSubsystem("Events")
    if Events and Events.InCombat and Events:InCombat() then
        Events:RunWhenOutOfCombat(questID, deferFn(questID))
    else
        IB:_applySecure(questID)
    end
end

-- Once the tracker chain has hosted a secure button its SetHeight/SetSize are combat-protected,
-- and retiring a button only hides it, so this never goes back to false
function IB:HasSecureButtons()
    return next(self.buttons) ~= nil or #pool > 0
end

function IB:Gutter()
    return BTN + ITEM_GAP
end

function IB:WantsButton(questID)
    local DB = ns:GetSubsystem("DB")
    local on = not DB or DB.db.profile.tracker.showItemButtons ~= false
    return (on and itemInfo(questID)) and true or false
end

function IB:Reposition()
    local Blocks = ns:GetSubsystem("TrackerBlocks")
    if not (Blocks and Blocks.byID) then return end
    local DB = ns:GetSubsystem("DB")
    local on = not DB or DB.db.profile.tracker.showItemButtons ~= false

    wipe(wanted)
    if on then
        for questID in pairs(Blocks.byID) do
            if itemInfo(questID) then wanted[questID] = true end
        end
    end

    local n = 0
    for questID in pairs(self.buttons) do
        if not wanted[questID] then n = n + 1; stale[n] = questID end
    end
    for i = 1, n do
        applySecure(stale[i])
        stale[i] = nil
    end

    for questID in pairs(wanted) do
        applySecure(questID)
        local b = self.buttons[questID]
        if b and b:IsShown() then paint(b, questID) end
    end
end
