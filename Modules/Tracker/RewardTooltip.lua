-- Draws on the private PinTooltip, never the shared GameTooltip - our taint left on the shared singleton can make the next Blizzard tooltip throw during layout

local _, ns = ...

local RT = ns:RegisterSubsystem("TrackerRewardTooltip", {})

local Util = ns.Util

local function pickAnchor(owner)
    local cx = owner.GetCenter and select(1, owner:GetCenter())
    if not cx then return "ANCHOR_RIGHT" end
    local ownerPx  = cx * (owner:GetEffectiveScale() or 1)
    local screenMid = (UIParent:GetWidth() * (UIParent:GetEffectiveScale() or 1)) / 2
    return ownerPx > screenMid and "ANCHOR_LEFT" or "ANCHOR_RIGHT"
end

function RT:Show(owner, questID)
    if not (owner and questID) then return end
    local tip = Util.PinTooltip()
    if not tip then return end

    local QR = ns:GetSubsystem("QuestRewards")
    if not QR then return end

    tip:SetOwner(owner, pickAnchor(owner))
    tip:SetText(Util.QuestTitle(questID, true) or "", 1.0, 0.82, 0.0, 1, true)

    QR:RenderObjectives(tip, questID)
    QR:RenderRewards(tip, questID)

    tip:Show()
end

function RT:Hide()
    local tip = Util.PinTooltip()
    if tip then tip:Hide() end
end
