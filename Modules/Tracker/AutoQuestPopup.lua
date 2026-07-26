local _, ns = ...
local L = ns.L

local S = ns:RegisterSubsystem("TrackerAutoQuestPopup", {})

local PAD        = 7
local LINE_GAP   = 2
local BOX_GAP    = 6
local ICON_SIZE  = 34
local BORDER = { 0.82, 0.65, 0.13, 0.55 }
local HILITE = { 0.95, 0.78, 0.20, 0.95 }

S.pool   = {}
S.active = {}

local _iconQ = {}

local function getNum()
    return (GetNumAutoQuestPopUps and GetNumAutoQuestPopUps()) or 0
end

local function popupTitle(questID)
    return ns.Util.QuestTitle(questID, true)
end

local function onBoxClick(box)
    local questID, ptype = box.questID, box.popUpType
    if not questID then return end
    if ptype == "COMPLETE" then
        if ShowQuestComplete then pcall(ShowQuestComplete, questID) end
    else
        if ShowQuestOffer then pcall(ShowQuestOffer, questID) end
    end
    if RemoveAutoQuestPopUp then pcall(RemoveAutoQuestPopUp, questID) end
    local Tracker = ns:GetSubsystem("Tracker")
    if Tracker and Tracker.Refresh then Tracker:Refresh() end
end

local function buildBox()
    local box = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
    box:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    box:SetBackdropColor(0, 0, 0, 0.85)
    box:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4])
    box:RegisterForClicks("LeftButtonUp")
    box:SetScript("OnClick", onBoxClick)
    box:SetScript("OnEnter", function(b) b:SetBackdropBorderColor(HILITE[1], HILITE[2], HILITE[3], HILITE[4]) end)
    box:SetScript("OnLeave", function(b) b:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], BORDER[4]) end)

    box.iconHolder = CreateFrame("Frame", nil, box)
    box.iconHolder:SetSize(ICON_SIZE, ICON_SIZE)
    box.iconHolder:SetPoint("LEFT", box, "LEFT", 10, 0)

    box.iconGlow = box.iconHolder:CreateTexture(nil, "BACKGROUND")
    box.iconGlow:SetSize(44, 44)
    box.iconGlow:SetPoint("CENTER")
    box.iconGlow:SetBlendMode("ADD")
    box.iconGlow:SetAlpha(0.5)

    box.icon = box.iconHolder:CreateTexture(nil, "ARTWORK", nil, 0)
    box.icon:SetSize(30, 30)
    box.icon:SetPoint("CENTER")

    box.iconBang = box.iconHolder:CreateTexture(nil, "ARTWORK", nil, 1)
    box.iconBang:SetSize(30, 30)
    box.iconBang:SetPoint("CENTER")

    -- No "!" exists in the atlas set, so it is a font overlay - the atlas fallback renders a "?" that reads as a turn-in
    box.bang = box.iconHolder:CreateFontString(nil, "OVERLAY")
    box.bang:SetPoint("CENTER", box.icon, "CENTER", 0, 0)
    box.bang:SetFont(STANDARD_TEXT_FONT, 22, "OUTLINE")
    box.bang:SetTextColor(1, 0.82, 0)
    box.bang:SetText("!")

    box.header = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    box.header:SetJustifyH("CENTER")
    box.header:SetTextColor(0.92, 0.72, 0.02)

    box.title = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    box.title:SetJustifyH("CENTER")
    box.title:SetTextColor(1, 1, 1)

    box.hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.hint:SetJustifyH("CENTER")
    box.hint:SetText(L["Click to view quest"])

    box.header:SetPoint("TOP", box, "TOP", 0, -PAD)
    box.title:SetPoint("TOP", box.header, "BOTTOM", 0, -LINE_GAP)
    box.hint:SetPoint("TOP", box.title, "BOTTOM", 0, -LINE_GAP)

    return box
end

local function acquire(parent)
    return ns.Util.AcquirePooled(S.pool, S.active, parent, buildBox)
end

function S:ReleaseAll()
    for i = #S.active, 1, -1 do
        local box = S.active[i]
        box:Hide()
        box:ClearAllPoints()
        box.questID   = nil
        box.popUpType = nil
        S.pool[#S.pool + 1] = box
        S.active[i] = nil
    end
end

local function isCampaignQuest(questID)
    local Cache  = ns:GetSubsystem("Cache")
    local quests = Cache and Cache.All and Cache:All()
    local q = quests and quests[questID]
    return (q and q.isCampaign) and true or false
end

function S:Count(wantCampaign)
    local n = getNum()
    if n == 0 then return 0 end
    local want, c = wantCampaign and true or false, 0
    for i = 1, n do
        local questID = GetAutoQuestPopUp and GetAutoQuestPopUp(i)
        if questID and isCampaignQuest(questID) == want then c = c + 1 end
    end
    return c
end

-- Appends only - the caller releases every box once per pass, then calls this once per section
function S:Render(content, contentWidth, yStart, wantCampaign)
    if not content then return 0, 0 end
    local n = getNum()
    if n == 0 then return 0, 0 end

    local want   = wantCampaign and true or false
    local textW  = math.max(40, (contentWidth or 0) - 16)
    local y      = yStart or 0
    local startY = y
    local rendered = 0

    local Blocks = ns:GetSubsystem("TrackerBlocks")
    for i = 1, n do
        local questID, popUpType
        if GetAutoQuestPopUp then questID, popUpType = GetAutoQuestPopUp(i) end
        if questID and isCampaignQuest(questID) == want then
            rendered = rendered + 1
            local box = acquire(content)
            box.questID   = questID
            box.popUpType = popUpType

            box.header:SetText(popUpType == "COMPLETE" and L["Quest Complete!"] or L["Quest Discovered!"])
            box.title:SetText(popupTitle(questID))

            _iconQ.classification = nil
            _iconQ.isComplete     = false
            _iconQ.noBang         = true
            if Blocks and Blocks.ApplyQuestIcon then
                Blocks:ApplyQuestIcon(box.iconGlow, box.icon, box.iconBang, _iconQ, false)
            end

            box.header:SetWidth(textW)
            box.title:SetWidth(textW)
            box.hint:SetWidth(textW)

            local h = PAD + box.header:GetStringHeight()
                      + LINE_GAP + box.title:GetStringHeight()
                      + LINE_GAP + box.hint:GetStringHeight() + PAD
            if h < ICON_SIZE + PAD * 2 then h = ICON_SIZE + PAD * 2 end
            box:SetHeight(h)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -y)
            box:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -y)

            y = y + h + BOX_GAP
        end
    end

    return y - startY, rendered
end
