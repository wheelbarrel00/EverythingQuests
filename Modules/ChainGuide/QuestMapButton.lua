local _, ns = ...
local L = ns.L
local QMB = ns:RegisterSubsystem("ChainGuideQuestMapButton", {})

local function findChainFor(questID)
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if not (Database and Database.chains and questID) then return nil end

    local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
    local CS  = ns:GetSubsystem("ChainGuideCampaignSource")

    if Database.categories then
        for catID in pairs(Database.categories) do
            if QLS and QLS.EnsureZoneChains    then QLS:EnsureZoneChains(catID)    end
            if CS  and CS.EnsureCampaignChains then CS:EnsureCampaignChains(catID) end
        end
    end
    if QLS and QLS.EnsureChainItems then
        for _, chain in pairs(Database.chains) do
            QLS:EnsureChainItems(chain)
        end
    end

    for chainID, chain in pairs(Database.chains) do
        Database:NormalizeChain(chain)
        local items = chain.items
        if items then
            for i = 1, #items do
                local it = items[i]
                if it then
                    if it.type == "quest" and it.id == questID then
                        return chainID
                    end
                    local vars = it.variations
                    if vars then
                        for j = 1, #vars do
                            if vars[j].id == questID then return chainID end
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function currentDetailQuestID()
    if QuestMapFrame and QuestMapFrame.DetailsFrame then
        local df = QuestMapFrame.DetailsFrame
        if df.GetCurrentQuestID then
            local q = df:GetCurrentQuestID()
            if q and q > 0 then return q end
        end
        if df.questID and df.questID > 0 then return df.questID end
    end
    if QuestMapFrame_GetDetailQuestID then
        local q = QuestMapFrame_GetDetailQuestID()
        if q and q > 0 then return q end
    end
    if GetQuestID then
        local q = GetQuestID()
        if q and q > 0 then return q end
    end
    return nil
end

local function onClick()
    local qid = currentDetailQuestID()
    if not qid then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cffEBB706EQ Chain:|r couldn't read the displayed quest. Try clicking the quest in the list again.")
        return
    end

    local chainID = findChainFor(qid)
    if chainID then
        local CG = ns:GetSubsystem("ChainGuide")
        if CG then
            if CG.Open          then CG:Open()                end
            if CG.NavigateChain then CG:NavigateChain(chainID) end
        end
        return
    end

    local title = ns.Util.QuestTitle(qid, true)
    local url = "https://www.wowhead.com/quest=" .. tostring(qid)
    DEFAULT_CHAT_FRAME:AddMessage(
        ("|cffEBB706EQ:|r no chain yet for |cffffffff%s|r — |cffaaccff%s|r")
        :format(title, url))
end

local _button
local function ensureButton()
    if _button then return _button end
    if not (QuestMapFrame and QuestMapFrame.DetailsFrame) then return nil end

    local parent = QuestMapFrame.DetailsFrame
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(54, 20)
    local abandon = parent.AbandonButton
    if abandon then
        b:SetPoint("RIGHT", abandon, "LEFT", -4, 0)
    else
        b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -36)
    end
    b:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 0) + 20)

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.55)

    local border = b:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.635, 0.0, 0.039, 1)

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.10)

    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(L["Chain"])
    b.text:SetTextColor(0.92, 0.72, 0.02)

    b:SetScript("OnClick", onClick)
    -- Hovering from the map's DetailsFrame can leave taint on the shared GameTooltip and trip the next AreaPOI tooltip, so use the private tooltip
    b:SetScript("OnEnter", function(self)
        local tip = ns.Util.PinTooltip()
        tip:SetOwner(self, "ANCHOR_TOPLEFT")
        tip:SetText(L["Find this quest in EQ's Chain Guide"], 1, 1, 1)
        tip:AddLine(
            L["Falls back to a Wowhead link in chat if EQ doesn't have a chain for this quest yet."],
            0.7, 0.7, 0.7, true)
        tip:Show()
    end)
    b:SetScript("OnLeave", function() ns.Util.PinTooltip():Hide() end)

    _button = b
    return b
end

function QMB:OnEnable()
    if ensureButton() then return end
    if WorldMapFrame and WorldMapFrame.HookScript then
        WorldMapFrame:HookScript("OnShow", ensureButton)
    end
end
