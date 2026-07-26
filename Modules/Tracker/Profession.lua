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

local INCLUDE_ACCOUNT = { false, true }

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
                        -- arg #3 (isRecraft) is a REQUIRED boolean — the API
                        -- raises "bad argument #3" on nil, which is exactly
                        -- what isRecraft is for a normal (non-recraft) tracked
                        -- recipe. Coerce to a real boolean.
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
    for _, includeAccount in ipairs(INCLUDE_ACCOUNT) do
        local list = C_TradeSkillUI.GetRecipesTracked(includeAccount)
        if list then
            for i = 1, #list do
                local entry = list[i]
                local rid, isRecraft
                if type(entry) == "table" then
                    rid, isRecraft = entry.recipeID, entry.isRecraft
                else
                    rid = entry
                end
                if rid and not seen[rid] then
                    seen[rid] = true
                    results[#results + 1] = { recipeID = rid, isRecraft = isRecraft and true or false }
                end
            end
        end
    end
    return results
end

local BASIC_REAGENT = (Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic) or 0

-- The reagent list is static per (recipeID, isRecraft). GetRecipeSchematic returns
-- fresh multi-KB nested tables, and BAG_UPDATE_DELAYED drives renders while farming,
-- so cache the extracted list. Item counts stay live (fetched per render below).
local _reagentCache = {}
local function getReagents(recipeID, isRecraft)
    local key = (isRecraft and "R" or "") .. recipeID
    local cached = _reagentCache[key]
    if cached then return cached end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then return {} end
    local ok, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, isRecraft and true or false)
    if not ok or not schematic or not schematic.reagentSlotSchematics then return {} end

    local out = {}
    for i = 1, #schematic.reagentSlotSchematics do
        local slot = schematic.reagentSlotSchematics[i]
        if slot and slot.reagentType == BASIC_REAGENT and slot.reagents and slot.reagents[1] then
            local need = slot.quantityRequired or 0
            local itemID = slot.reagents[1].itemID
            if itemID and need > 0 then
                out[#out + 1] = { itemID = itemID, need = need }
            end
        end
    end
    -- Reached only with a valid loaded schematic, so cache even an empty list
    -- (a reagent-less or not-learned account recipe) - the early return above
    -- leaves unloaded recipes uncached so they still retry.
    _reagentCache[key] = out
    return out
end

local function getItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID, true, false, true, true) or 0
    end
    return 0
end

local function getItemName(itemID)
    if C_Item and C_Item.GetItemNameByID then
        local n = C_Item.GetItemNameByID(itemID)
        if n then return n end
    end
    return "Item " .. tostring(itemID)
end

function P:Render(content, contentWidth, yStart, collapsed)
    local recipes = getTrackedRecipes()
    local count = #recipes

    releaseAll()

    if collapsed or count == 0 then return 0, count end

    local Media = ns:GetSubsystem("Media")
    local y = yStart
    for i = 1, count do
        local entry = recipes[i]
        local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(entry.recipeID)
        local name = (info and info.name) or ("Recipe #" .. tostring(entry.recipeID))
        local icon = info and info.icon

        local row = acquireHeader(content)
        row:SetWidth(contentWidth)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        if icon then
            row.icon:SetTexture(icon)
            row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        else
            row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        end

        local label = name
        if entry.isRecraft then label = label .. " |cffaaaaaa(Recraft)|r" end
        row.title:SetText(label)
        row.recipeID   = entry.recipeID
        row.isRecraft  = entry.isRecraft
        row.recipeName = name
        if Media and Media.ApplyTrackerTitleFont then Media:ApplyTrackerTitleFont(row.title) end

        y = y + HEADER_H + ROW_GAP

        local reagents = getReagents(entry.recipeID, entry.isRecraft)
        for j = 1, #reagents do
            local rg = reagents[j]
            local have = getItemCount(rg.itemID)
            local nm = getItemName(rg.itemID)

            local rrow = acquireReagent(content)
            rrow:SetWidth(contentWidth)
            rrow:ClearAllPoints()
            rrow:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

            local met = have >= rg.need
            local line
            if met then
                line = format("|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t |cff40ff40%d/%d %s|r", have, rg.need, nm)
            else
                line = format("|cff999999- %d/%d %s|r", have, rg.need, nm)
            end
            rrow.text:SetText(line)
            if Media and Media.ApplyTrackerFont then Media:ApplyTrackerFont(rrow.text, -2) end

            y = y + REAGENT_H + ROW_GAP + ns.Util.LineSpacing()
        end
    end

    return y - yStart, count
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
