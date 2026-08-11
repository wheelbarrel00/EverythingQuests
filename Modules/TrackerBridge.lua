local _, ns = ...
local L = ns.L

-- EQOT is a required dependency, so it is always loaded and always loads first. This puts EQ's
-- own features back onto its tracker.
local Bridge = ns:RegisterSubsystem("TrackerBridge", {})

local CHAIN_ICON = "Interface\\AddOns\\EverythingQuests\\Media\\chain.tga"
-- Same art as the minimap button, so the glyph already reads as "Everything Quests".
local EQ_ICON    = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\eq-logo-v3.tga"

-- Header icons lay out right to left from EQOT's cogwheel, so the chain sits beside the cog
-- and EQ's logo goes outside it.
local CHAIN_ORDER = 10
local EQ_ORDER    = 20

-- Lands between Focus (30) and Open in Map & Quest Log (40).
local DIRECTIONS_ORDER = 35

local function eqot()
    return _G.EQObjectiveTracker
end

-- '## Dependencies:' cannot express a minimum version, so an older EQOT with no API module
-- satisfies it and still lands here nil.
local function api()
    local T = eqot()
    local mod = T and T.GetModule and T:GetModule("API")
    if not (mod and mod.AddMenuItem) then return nil end
    return mod
end

local function warnMissing()
    print("|cffEBB706EQ|r: " .. L["EQ Objective Tracker is not loaded, so the tracker is unavailable."])
end

function Bridge:ChainIconEnabled()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.general.showChainGuideIcon ~= false
end

-- Add and remove rather than dim, because the icon's visibility is EQ's setting and lives in
-- EQ's profile - EQOT's own dbKey mechanism can only read keys EQOT knows about.
function Bridge:ApplyChainIcon()
    local A = api()
    if not A then return end

    -- The Chain Guide is Midnight-only, so elsewhere the icon would sit there doing nothing.
    if not self:ChainIconEnabled() or not ns:GetSubsystem("ChainGuide") then
        A:RemoveHeaderIcon("eq-chainguide")
        return
    end

    A:AddHeaderIcon({
        id      = "eq-chainguide",
        texture = CHAIN_ICON,
        tooltip = L["Open the Chain Guide"],
        order   = CHAIN_ORDER,
        onClick = function()
            local CG = ns:GetSubsystem("ChainGuide")
            if CG then CG:Toggle() end
        end,
    })
end

function Bridge:EQIconEnabled()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.general.showEQIcon ~= false
end

-- The tracker's cogwheel opens EQOT's options, so without this there is no icon on the tracker
-- that reaches Everything Quests.
function Bridge:ApplyEQIcon()
    local A = api()
    if not A then return end

    if not self:EQIconEnabled() then
        A:RemoveHeaderIcon("eq-options")
        return
    end

    A:AddHeaderIcon({
        id      = "eq-options",
        texture = EQ_ICON,
        tooltip = L["Open the Everything Quests options"],
        order   = EQ_ORDER,
        onClick = function()
            local O = ns:GetSubsystem("Options")
            if O then O:Toggle() end
        end,
    })
end

function Bridge:OpenTrackerOptions()
    local T = eqot()
    local Options = T and T.GetModule and T:GetModule("Options")
    if Options and Options.Toggle then
        Options:Toggle()
        return true
    end
    warnMissing()
    return false
end

function Bridge:OnEnable()
    local A = api()
    if not A then
        warnMissing()
        return
    end

    if ns:GetSubsystem("ChainGuideWaypoint") then
        A:AddMenuItem({
            id         = "eq-directions",
            providerID = "quests",
            label      = L["Get Directions"],
            order      = DIRECTIONS_ORDER,
            onClick    = function(_, questID)
                local WP = ns:GetSubsystem("ChainGuideWaypoint")
                if WP and WP.GoTo then WP:GoTo(questID) end
            end,
        })
    end

    self:ApplyChainIcon()
    self:ApplyEQIcon()
end
