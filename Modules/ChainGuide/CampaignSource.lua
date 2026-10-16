
local _, ns = ...
local L = ns.L

local CS = ns:RegisterSubsystem("ChainGuideCampaignSource", {})

local CAMPAIGN_CHAIN_OFFSET = 6000000
local CAMPAIGN_MAP_OFFSET = 7000000

CS._discovered = {}

function CS:Reset()
    local Database = ns:GetSubsystem("ChainGuideDatabase")
    if Database then
        for chainID, chain in pairs(Database.chains) do
            if chain._campaignSourced then Database.chains[chainID] = nil end
        end
    end
    self._discovered = {}
    self._chapterSet = nil
end

function CS:IsChapterQuestline(qlID)
    local set = self._chapterSet
    if set == nil then
        set = {}
        local complete = true
        if C_CampaignInfo and C_CampaignInfo.GetChapterIDs then
            local Database = ns:GetSubsystem("ChainGuideDatabase")
            if Database then
                for _, cat in pairs(Database.categories) do
                    if cat.campaignID then
                        local ch = C_CampaignInfo.GetChapterIDs(cat.campaignID)
                        if ch and #ch > 0 then
                            for _, id in ipairs(ch) do set[id] = true end
                        else
                            complete = false
                        end
                    end
                end
            end
        end
        -- A campaign with no chapters yet has not loaded, so the set is kept only once every campaign answers
        if complete then self._chapterSet = set end
    end
    return set[qlID] or false
end

function CS:EnsureCampaignChains(catID)
    if self._discovered[catID] then return end
    if not (C_CampaignInfo and C_CampaignInfo.GetChapterIDs) then return end

    local Database = ns:GetSubsystem("ChainGuideDatabase")
    local cat = Database and Database.categories[catID]
    if not cat then return end

    -- Only authored campaignID categories - deriving one from the quest log misfiles its chapters under an unrelated zone
    local campaignID = cat.campaignID
    if not campaignID then
        self._discovered[catID] = true
        return
    end

    local chapters = C_CampaignInfo.GetChapterIDs(campaignID)
    if not chapters or #chapters == 0 then return end

    local mapItems = {}
    for i = 1, #chapters do
        local chapterID = chapters[i]
        local chainID   = CAMPAIGN_CHAIN_OFFSET + chapterID
        if not Database.chains[chainID] then
            local ci = C_CampaignInfo.GetCampaignChapterInfo
                       and C_CampaignInfo.GetCampaignChapterInfo(chapterID)
            Database:RegisterChain(chainID, {
                category         = catID,
                name             = (ci and ci.name) or ("Chapter " .. i),
                -- A campaign chapter ID is also a questline ID, so EnsureChainItems can fill items from it
                questlineID      = chapterID,
                items            = {},
                _campaignSourced = true,
                _campaignOrder   = i,
            })
        end
        mapItems[i] = {
            type        = "chain",
            id          = chainID,
            x           = 0,
            y           = i - 1,
            connections = (i > 1) and { i - 1 } or nil,
        }
    end

    local mapChainID = CAMPAIGN_MAP_OFFSET + campaignID
    if not Database.chains[mapChainID] then
        Database:RegisterChain(mapChainID, {
            category         = catID,
            name             = L["Campaign Map"],
            items            = mapItems,
            _campaignSourced = true,
            _campaignOrder   = 0,
            _campaignMap     = true,
        })
    end

    self._discovered[catID] = true
end
