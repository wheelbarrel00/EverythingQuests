local _, ns = ...
local L = ns.L

-- Everything Quests hands its tracker to EQ Objective Tracker and declares it as a required
-- dependency, so EQOT is always loaded and always loads FIRST. This puts EQ's own features
-- back onto the tracker: the Chain Guide header icon, the Get Directions entry on a quest's
-- right-click menu, and the route from EQ's options panel through to EQOT's.
local Bridge = ns:RegisterSubsystem("TrackerBridge", {})

local CHAIN_ICON = "Interface\\AddOns\\EverythingQuests\\Media\\chain.tga"
-- Same art as the minimap button, so the glyph already reads as "Everything Quests".
local EQ_ICON    = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\eq-logo-v3.tga"

-- Header icons lay out right to left from EQOT's cogwheel, so the chain sits beside the cog
-- and EQ's logo goes outside it.
local CHAIN_ORDER = 10
local EQ_ORDER    = 20

-- Ordered to land between Focus (30) and Open in Map & Quest Log (40), which is where this sat
-- when EQ drew the menu itself.
local DIRECTIONS_ORDER = 35

local function eqot()
    return _G.EQObjectiveTracker
end

-- '## Dependencies:' checks the addon FOLDER and cannot express a minimum version, so an
-- older EQOT with no API module satisfies the dependency and still lands here nil. Disabling
-- EQOT is not the case to guard against - that stops EQ loading at all.
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

    if not self:ChainIconEnabled() then
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

-- The tracker's cogwheel opens the TRACKER's options now, so without this there is no icon on
-- the tracker that reaches Everything Quests. The minimap button still does, but a user who
-- hides minimap buttons would be left with only /eqs.
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

    self:ApplyChainIcon()
    self:ApplyEQIcon()
end
