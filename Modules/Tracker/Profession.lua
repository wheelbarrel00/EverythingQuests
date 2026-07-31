local _, ns = ...
local L = ns.L

local P = ns:RegisterSubsystem("TrackerProfession", {})

local HEADER_H     = 18
local REAGENT_H    = 14
local ROW_GAP      = 2
local ICON_SIZE    = 16
local ICON_PAD     = 4
local LABEL_PAD    = 6
local REAGENT_INDENT = ICON_PAD + ICON_SIZE + LABEL_PAD

P.headerPool   = {}
P.reagentPool  = {}
P.activeHeaders  = {}
P.activeReagents = {}

-- GetRecipesTracked's only arg is isRecraft, and the same recipeID can appear in both lists, so key on the pair
local IS_RECRAFT = { false, true }

local function buildHeader(parent)
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(HEADER_H)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = r:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ICON_SIZE, ICON_SIZE)
    r.icon:SetPoint("LEFT", ICON_PAD, 0)

    r.title = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.title:SetPoint("LEFT", r.icon, "RIGHT", LABEL_PAD, 0)
    r.title:SetPoint("RIGHT", -4, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.title:SetTextColor(1.0, 0.82, 0.0)

    r:SetScript("OnClick", function(self, button)
        if not (self.recipeID and C_TradeSkillUI) then return end
        if button == "RightButton" then
            if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
            local recipeID, isRecraft = self.recipeID, self.isRecraft
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle(self.recipeName or "Recipe")
                root:CreateButton(L["Open in Profession"], function()
                    if C_TradeSkillUI.OpenRecipe then
                        C_TradeSkillUI.OpenRecipe(recipeID)
                    end
                end)
                root:CreateButton(L["Untrack Recipe"], function()
                    if C_TradeSkillUI.SetRecipeTracked then
                        -- Arg #3 is a required boolean - nil raises "bad argument #3"
                        C_TradeSkillUI.SetRecipeTracked(recipeID, false, isRecraft and true or false)
                    end
                end)
            end)
        else
            if C_TradeSkillUI.OpenRecipe then
                C_TradeSkillUI.OpenRecipe(self.recipeID)
            end
        end
    end)

    return r
end

local function buildReagent(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(REAGENT_H)

    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", REAGENT_INDENT, 0)
    r.text:SetPoint("RIGHT", -4, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)

    return r
end

local function acquireHeader(parent)
    return ns.Util.AcquirePooled(P.headerPool, P.activeHeaders, parent, buildHeader)
end

local function acquireReagent(parent)
    return ns.Util.AcquirePooled(P.reagentPool, P.activeReagents, parent, buildReagent)
end

local function releaseAll()
    for i = #P.activeHeaders, 1, -1 do
        local r = P.activeHeaders[i]
        r:Hide()
        r:ClearAllPoints()
        r.icon:SetTexture(nil)
        r.recipeID, r.isRecraft, r.recipeName = nil, nil, nil
        P.headerPool[#P.headerPool + 1] = r
        P.activeHeaders[i] = nil
    end
    for i = #P.activeReagents, 1, -1 do
        local r = P.activeReagents[i]
        r:Hide()
        r:ClearAllPoints()
        r.text:SetText("")
        P.reagentPool[#P.reagentPool + 1] = r
        P.activeReagents[i] = nil
    end
end

local function getTrackedRecipes()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked) then return {} end

    local results = {}
    local seen = {}
    for _, isRecraft in ipairs(IS_RECRAFT) do
        local list = C_TradeSkillUI.GetRecipesTracked(isRecraft)
        if list then
            for i = 1, #list do
                local entry = list[i]
                local rid = (type(entry) == "table") and entry.recipeID or entry
                local key = (isRecraft and "R" or "N") .. tostring(rid)
                if rid and not seen[key] then
                    seen[key] = true
                    results[#results + 1] = { recipeID = rid, isRecraft = isRecraft }
                end
            end
        end
    end
    return results
end

local BASIC_REAGENT = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0

local REAGENT_FMT = PROFESSIONS_TRACKER_REAGENT_FORMAT or "%s %s"
local COUNT_FMT   = PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT or "%d/%d"
local RANGE_FMT   = PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT or "%d-%d"

local function slotRequired(slot)
    if ProfessionsUtil and ProfessionsUtil.IsReagentSlotRequired then
        return ProfessionsUtil.IsReagentSlotRequired(slot)
    end
    return slot.reagentType == BASIC_REAGENT
end

local function slotModifying(slot)
    if ProfessionsUtil and ProfessionsUtil.IsReagentSlotModifyingRequired then
        return ProfessionsUtil.IsReagentSlotModifyingRequired(slot)
    end
    return false
end

local function slotQuantityRequired(slot, reagent)
    if slot.GetQuantityRequired then
        local ok, n = pcall(slot.GetQuantityRequired, slot, reagent)
        if ok and n then return n end
    end
    return slot.quantityRequired or 0
end

-- The reagent list is static per (recipeID, isRecraft) and GetRecipeSchematic allocates fresh multi-KB tables, so cache the extracted entries. Counts and names still resolve live per render
local _reagentCache = {}
local function getReagents(recipeID, isRecraft)
    local key = (isRecraft and "R" or "N") .. recipeID
    local cached = _reagentCache[key]
    if cached then return cached end
    local getSchematic = (ProfessionsUtil and ProfessionsUtil.GetRecipeSchematic)
                      or (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic)
    if not getSchematic then return {} end
    local ok, schematic = pcall(getSchematic, recipeID, isRecraft and true or false)
    if not ok or not schematic or not schematic.reagentSlotSchematics then return {} end

    local out = {}
    for i = 1, #schematic.reagentSlotSchematics do
        local slot = schematic.reagentSlotSchematics[i]
        local reagent = slot and slot.reagents and slot.reagents[1]
        if reagent and slotRequired(slot) then
            local isModifying = slotModifying(slot)
            local entry = {
                reagents   = slot.reagents,
                need       = slotQuantityRequired(slot, reagent),
                itemID     = (not isModifying) and reagent.itemID or nil,
                currencyID = (not isModifying) and reagent.currencyID or nil,
                slotText   = isModifying and slot.slotInfo and slot.slotInfo.slotText or nil,
            }
            if slot.IsVariableQuantityReagent and slot.GetVariableQuantityRange
               and slot:IsVariableQuantityReagent(reagent) then
                entry.varMin, entry.varMax = slot:GetVariableQuantityRange(reagent)
            end
            if (entry.slotText or entry.itemID or entry.currencyID)
               and (entry.need > 0 or entry.varMin) then
                -- Blizzard orders modifying-required slots ahead of the basic ones.
                tinsert(out, isModifying and 1 or #out + 1, entry)
            end
        end
    end
    -- Only reached with a loaded schematic, so caching an empty list is safe - unloaded recipes returned early and stay uncached so they retry
    _reagentCache[key] = out
    return out
end

-- Sums every quality tier under the game's own bank and warband rules, so a stack of only rank-2 or rank-3 still counts
local function reagentHave(entry)
    if ProfessionsUtil and ProfessionsUtil.AccumulateReagentsInPossession and entry.reagents then
        return ProfessionsUtil.AccumulateReagentsInPossession(entry.reagents) or 0
    end
    if entry.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(entry.currencyID)
        return (info and info.quantity) or 0
    end
    if entry.itemID and C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(entry.itemID, true, false, true, true) or 0
    end
    return 0
end

local function reagentName(entry)
    if entry.slotText then return entry.slotText end
    if entry.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(entry.currencyID)
        if info and info.name then return info.name end
    end
    if entry.itemID then
        if C_Item and C_Item.GetItemNameByID then
            local n = C_Item.GetItemNameByID(entry.itemID)
            if n then return n end
        end
        return "Item " .. tostring(entry.itemID)
    end
    return ""
end

function P:Render(content, contentWidth, yStart, collapsed)
    local recipes = getTrackedRecipes()
    local count = #recipes

    releaseAll()

    if collapsed or count == 0 then return 0, count end

    local Media = ns:GetSubsystem("Media")

    local DB = ns:GetSubsystem("DB")
    local t  = DB and DB.db and DB.db.profile and DB.db.profile.tracker
    local ovR, ovG, ovB
    if ns.Util and ns.Util.EffectiveTitleColor then ovR, ovG, ovB = ns.Util.EffectiveTitleColor(t) end
    local doneHex = "40ff40"
    if t and t.overrideCompleteGreen ~= false and ovR then
        doneHex = ("%02x%02x%02x"):format(
            math.floor(ovR * 255 + 0.5),
            math.floor(ovG * 255 + 0.5),
            math.floor(ovB * 255 + 0.5))
    end

    local Card = ns:GetSubsystem("TrackerCard")
    local cardOn, pad, borderSize = false, 0, 0
    local cardBg, cardBorder
    if Card then
        cardOn, pad, borderSize = Card:State(t)
        cardBg, cardBorder = Card:Colors(t)
    end

    local y = yStart
    for i = 1, count do
        local entry = recipes[i]
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(entry.recipeID)
        local name = (info and info.name) or ("Recipe #" .. tostring(entry.recipeID))
        local icon = info and info.icon

        local groupTop = y
        if cardOn then y = y + pad end
        local row = acquireHeader(content)
        row:SetWidth(math.max(1, contentWidth - pad * 2))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)

        if icon then
            row.icon:SetTexture(icon)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local label = name
        if entry.isRecraft then
            label = PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER
                and PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER:format(name)
                or (name .. " |cffaaaaaa(Recraft)|r")
        end
        row.title:SetText(label)
        row.recipeID   = entry.recipeID
        row.isRecraft  = entry.isRecraft
        row.recipeName = name
        if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end

        local lastBottom = y + HEADER_H
        y = y + HEADER_H + ROW_GAP

        local reagents = getReagents(entry.recipeID, entry.isRecraft)
        for j = 1, #reagents do
            local rg = reagents[j]
            local nm = reagentName(rg)

            -- Parented to the header row so the group card draws behind the text, anchored to content so placement is unchanged
            local rrow = acquireReagent(row)
            rrow:SetWidth(math.max(1, contentWidth - pad * 2))
            rrow:ClearAllPoints()
            rrow:SetPoint("TOPLEFT", content, "TOPLEFT", pad, -y)

            -- Variable-quantity slots depend on unreadable crafting-form choices, so show the range and never mark them satisfied
            local body, met
            if rg.varMin then
                body = format(REAGENT_FMT, format(RANGE_FMT, rg.varMin, rg.varMax), nm)
            else
                local have = reagentHave(rg)
                body = format(REAGENT_FMT, format(COUNT_FMT, have, rg.need), nm)
                met = have >= rg.need
            end

            local line
            if met then
                line = format("|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff%s%s|r", doneHex, body)
            else
                line = format("|cff999999- %s|r", body)
            end
            rrow.text:SetText(line)
            if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(rrow.text, -2) end

            lastBottom = y + REAGENT_H
            -- A negative Line Spacing can pull the advance under the row height, which would overrun a card fill
            local advance = REAGENT_H + ROW_GAP + ns.Util.LineSpacing()
            if cardOn then advance = math.max(advance, REAGENT_H) end
            y = y + advance
        end

        if cardOn then
            local groupBottom = lastBottom + pad
            Card:Draw(row, groupBottom - groupTop, pad, borderSize, cardBg, cardBorder)
            y = groupBottom + Card:Gap(ROW_GAP, true)
        elseif Card then
            Card:Clear(row)
        end
    end

    return y - yStart, count
end

function P:Dump()
    local tag = "|cffEBB706EQ Prof|r: "
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked) then
        print(tag .. "C_TradeSkillUI.GetRecipesTracked unavailable.")
        return
    end

    local hasUtil  = ProfessionsUtil ~= nil
    local hasReq   = hasUtil and ProfessionsUtil.IsReagentSlotRequired ~= nil
    local hasMod   = hasUtil and ProfessionsUtil.IsReagentSlotModifyingRequired ~= nil
    local hasAccum = hasUtil and ProfessionsUtil.AccumulateReagentsInPossession ~= nil
    print(format("%sAPI  ProfessionsUtil=%s  SlotRequired=%s  SlotModifying=%s  Accumulate=%s",
        tag, tostring(hasUtil), tostring(hasReq), tostring(hasMod), tostring(hasAccum)))

    local recipes = getTrackedRecipes()
    print(format("%s%d tracked recipe(s)  (normal + recraft)", tag, #recipes))

    for i = 1, #recipes do
        local e = recipes[i]
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(e.recipeID)
        print(format("%s[%d] %s  id=%d  isRecraft=%s", tag, i,
            (info and info.name) or "?", e.recipeID, tostring(e.isRecraft)))

        local rs = getReagents(e.recipeID, e.isRecraft)
        if #rs == 0 then print("       (no required reagent slots resolved)") end
        for j = 1, #rs do
            local rg = rs[j]
            local all = reagentHave(rg)
            local tier1 = 0
            if rg.itemID and C_Item and C_Item.GetItemCount then
                tier1 = C_Item.GetItemCount(rg.itemID, true, false, true, true) or 0
            end
            local kind = rg.slotText and "MODIFYING" or (rg.currencyID and "CURRENCY " or "basic    ")
            local note = ""
            if rg.itemID and all ~= tier1 then
                note = format("  <<< QUALITY FIX (old code showed %d)", tier1)
            end
            if rg.varMin then
                note = note .. format("  <<< VARIABLE %s-%s", tostring(rg.varMin), tostring(rg.varMax))
            end
            print(format("       %s %-34s have=%-5d need=%-4d qualityTiers=%d%s",
                kind, reagentName(rg), all, rg.need or 0, (rg.reagents and #rg.reagents) or 0, note))
        end
    end
end

local function recomputeHasTrackedRecipes()
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked) then
        P._hasTrackedRecipes = false
        return
    end
    local list = C_TradeSkillUI.GetRecipesTracked(false)
    if list and #list > 0 then P._hasTrackedRecipes = true; return end
    list = C_TradeSkillUI.GetRecipesTracked(true)
    P._hasTrackedRecipes = (list and #list > 0) or false
end

function P:OnEnable()
    local Events = ns:GetSubsystem("Events")
    local function refresh()
        local Tracker = ns:GetSubsystem("Tracker")
        if Tracker and Tracker.Refresh then Tracker:Refresh() end
    end
    local function recipeChanged()
        wipe(_reagentCache)
        recomputeHasTrackedRecipes()
        refresh()
    end
    Events:On("TRACKED_RECIPE_UPDATE",   recipeChanged)
    Events:On("TRADE_SKILL_LIST_UPDATE", recipeChanged)
    Events:On("PLAYER_ENTERING_WORLD",   recipeChanged)
    Events:On("BAG_UPDATE_DELAYED", function()
        if P._hasTrackedRecipes then refresh() end
    end)
end
