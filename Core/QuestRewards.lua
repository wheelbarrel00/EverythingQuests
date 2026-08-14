local _, ns = ...

local QR = ns:RegisterSubsystem("QuestRewards", {})

local L = ns.L

local EQUIP_SLOTS = {
    INVTYPE_HEAD           = { "HEADSLOT" },
    INVTYPE_NECK           = { "NECKSLOT" },
    INVTYPE_SHOULDER       = { "SHOULDERSLOT" },
    INVTYPE_CLOAK          = { "BACKSLOT" },
    INVTYPE_CHEST          = { "CHESTSLOT" },
    INVTYPE_ROBE           = { "CHESTSLOT" },
    INVTYPE_WAIST          = { "WAISTSLOT" },
    INVTYPE_LEGS           = { "LEGSSLOT" },
    INVTYPE_FEET           = { "FEETSLOT" },
    INVTYPE_WRIST          = { "WRISTSLOT" },
    INVTYPE_HAND           = { "HANDSSLOT" },
    INVTYPE_FINGER         = { "FINGER0SLOT", "FINGER1SLOT" },
    INVTYPE_TRINKET        = { "TRINKET0SLOT", "TRINKET1SLOT" },
    INVTYPE_WEAPON         = { "MAINHANDSLOT", "SECONDARYHANDSLOT" },
    INVTYPE_2HWEAPON       = { "MAINHANDSLOT" },
    INVTYPE_WEAPONMAINHAND = { "MAINHANDSLOT" },
    INVTYPE_WEAPONOFFHAND  = { "SECONDARYHANDSLOT" },
    INVTYPE_RANGED         = { "MAINHANDSLOT" },
    INVTYPE_RANGEDRIGHT    = { "MAINHANDSLOT" },
    INVTYPE_SHIELD         = { "SECONDARYHANDSLOT" },
    INVTYPE_HOLDABLE       = { "SECONDARYHANDSLOT" },
}

local _slotID = {}
local function slotID(name)
    local id = _slotID[name]
    if id == nil then
        id = (GetInventorySlotInfo and GetInventorySlotInfo(name)) or false
        _slotID[name] = id
    end
    return id or nil
end

local function equipLocOf(itemID)
    if not itemID then return nil end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not instant then return nil end
    return select(4, instant(itemID))
end

local function detailedIlvl(link)
    if not (link and C_Item and C_Item.GetDetailedItemLevelInfo) then return nil end
    return C_Item.GetDetailedItemLevelInfo(link)
end

-- An equipLoc token is itself the name of a Blizzard global string, already localized
local function slotLabel(equipLoc)
    return (equipLoc and _G[equipLoc]) or ""
end

local function equippedComparison(equipLoc)
    local slots = EQUIP_SLOTS[equipLoc]
    if not slots then return nil end

    local lowest, hasEmpty
    for i = 1, #slots do
        local id = slotID(slots[i])
        if id then
            local link = GetInventoryItemLink and GetInventoryItemLink("player", id)
            if link then
                local il = detailedIlvl(link)
                if il and (not lowest or il < lowest) then lowest = il end
            else
                hasEmpty = true
            end
        end
    end
    return { lowest = lowest, hasEmpty = hasEmpty, multi = #slots > 1 }
end

local function addComparison(tip, equipLoc, rewardIlvl)
    if not (equipLoc and rewardIlvl and rewardIlvl > 0) then return end
    local cmp = equippedComparison(equipLoc)
    if not cmp then return end

    if cmp.hasEmpty then
        tip:AddLine("    " .. L["Equip — empty slot"], 0.2, 1.0, 0.2)
        return
    end
    if not cmp.lowest then return end

    local label = slotLabel(equipLoc)
    tip:AddLine(("    " .. L["Equipped: ilvl %d"]):format(cmp.lowest)
                .. (label ~= "" and ("  (" .. label .. ")") or ""), 0.7, 0.7, 0.7)

    local delta = rewardIlvl - cmp.lowest
    if delta > 0 then
        tip:AddLine(("    " .. L["+%d ilvl upgrade"]):format(delta), 0.2, 1.0, 0.2)
    elseif delta < 0 then
        tip:AddLine(("    " .. L["%d ilvl lower"]):format(delta), 1.0, 0.3, 0.3)
    else
        tip:AddLine("    " .. L["Same item level"], 1.0, 0.82, 0.0)
    end
end

local function addItem(tip, questID, kind, index, name, count, quality, itemID, rewardIlvl)
    local equipLoc = equipLocOf(itemID)
    if not rewardIlvl then
        local link = GetQuestLogItemLink and GetQuestLogItemLink(kind, index, questID)
        if link then rewardIlvl = detailedIlvl(link) end
    end

    local label = name
    if count and count > 1 then label = label .. " ×" .. count end
    if equipLoc and EQUIP_SLOTS[equipLoc] and rewardIlvl and rewardIlvl > 0 then
        label = label .. ("  |cff999999" .. L["ilvl %d"] .. "|r"):format(rewardIlvl)
    end

    local r, g, b = 1, 1, 1
    if quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
    tip:AddLine(label, r, g, b)

    addComparison(tip, equipLoc, rewardIlvl)
end

function QR:RenderObjectives(tip, questID)
    if not (tip and questID and C_QuestLog and C_QuestLog.GetQuestObjectives) then return false end
    local objs = C_QuestLog.GetQuestObjectives(questID)
    if not (objs and #objs > 0) then return false end
    local any = false
    for i = 1, #objs do
        local o = objs[i]
        if o and o.text and o.text ~= "" then
            local r, g, b = 0.95, 0.95, 0.95
            if o.finished then r, g, b = 0.40, 0.85, 0.40 end
            tip:AddLine("- " .. o.text, r, g, b, true)
            any = true
        end
    end
    return any
end

function QR:RenderRewards(tip, questID)
    if not (tip and questID) then return false end

    if C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end

    local hasReward = false

    -- MEASURED on Era: both of these IGNORE the questID and report whatever quest log entry is
    -- SELECTED, so they are asked only where the argument is honored.
    local byID = not (ns.Compat and ns.Compat.RewardXPNeedsSelection
                      and ns.Compat.RewardXPNeedsSelection())

    local money = (byID and GetQuestLogRewardMoney and GetQuestLogRewardMoney(questID)) or 0
    if money and money > 0 then
        tip:AddLine((GetCoinTextureString and GetCoinTextureString(money)) or tostring(money), 1, 1, 1)
        hasReward = true
    end

    local xp = (byID and GetQuestLogRewardXP and GetQuestLogRewardXP(questID)) or 0
    if xp and xp > 0 then
        tip:AddLine((L["%d XP"]):format(xp), 1, 1, 1)
        hasReward = true
    end

    local numItems = GetNumQuestLogRewards and GetNumQuestLogRewards(questID) or 0
    for i = 1, numItems do
        local name, _, count, quality, _, itemID, ilvl = GetQuestLogRewardInfo(i, questID)
        if name then
            addItem(tip, questID, "reward", i, name, count, quality, itemID, ilvl)
            hasReward = true
        end
    end

    local numChoices = GetNumQuestLogChoices and GetNumQuestLogChoices(questID) or 0
    if numChoices and numChoices > 0 then
        tip:AddLine(L["Choose one:"], 0.9, 0.8, 0.3)
        for i = 1, numChoices do
            local name, _, count, quality, _, itemID = GetQuestLogChoiceInfo(i, questID)
            if name then
                addItem(tip, questID, "choice", i, name, count, quality, itemID, nil)
                hasReward = true
            end
        end
    end

    local currencies = C_QuestLog and C_QuestLog.GetQuestRewardCurrencies
                       and C_QuestLog.GetQuestRewardCurrencies(questID)
    if currencies then
        for i = 1, #currencies do
            local c = currencies[i]
            local name = c and c.name
            if name then
                local count = c.totalRewardAmount
                local label = name
                if count and count > 1 then label = label .. " ×" .. count end
                tip:AddLine(label, 0.85, 0.85, 1.0)
                hasReward = true
            end
        end
    end

    return hasReward
end
