local _, ns = ...

local H = ns:RegisterSubsystem("TrackerScenarioBonusHUD", {})

local FRAME_W   = 240
local PAD       = 8
local ROW_GAP   = 3
local ICON_SIZE = 12
local TITLE_H   = 18
local REWARD_FALLBACK = 133785   -- inv_misc_treasurechest01

H.rowPool    = {}
H.activeRows = {}

local function DBsub() return ns:GetSubsystem("DB") end

local function state()
    local db = DBsub()
    local p = db and db.db and db.db.profile and db.db.profile.tracker
    if not p then return nil end
    p.scenarioBonusHUD = p.scenarioBonusHUD or {}
    return p.scenarioBonusHUD
end

local function enabled()
    local st = state()
    return (st and st.enabled == true) or false
end

local function buildRow(parent)
    local row = CreateFrame("Frame", nil, parent)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON_SIZE, ICON_SIZE)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")

    row.reward = CreateFrame("Frame", nil, row)
    row.reward:SetSize(16, 16)
    row.reward:EnableMouse(true)
    row.reward.tex = row.reward:CreateTexture(nil, "ARTWORK")
    row.reward.tex:SetAllPoints()
    row.reward:SetScript("OnEnter", function(self)
        if not self.questID then return end
        local RT = ns:GetSubsystem("TrackerRewardTooltip")
        if RT and RT.Show then RT:Show(self, self.questID) end
    end)
    row.reward:SetScript("OnLeave", function()
        local RT = ns:GetSubsystem("TrackerRewardTooltip")
        if RT and RT.Hide then RT:Hide() end
    end)
    row.reward:Hide()

    return row
end

function H:_AcquireRow(parent)
    return ns.Util.AcquirePooled(self.rowPool, self.activeRows, parent, buildRow)
end

function H:_ReleaseRows()
    for i = #self.activeRows, 1, -1 do
        local row = self.activeRows[i]
        row:Hide()
        row:ClearAllPoints()
        row.icon:Hide()
        row.icon:ClearAllPoints()
        row.text:SetText("")
        row.text:ClearAllPoints()
        row.reward:Hide()
        row.reward:ClearAllPoints()
        row.reward.questID = nil
        row.reward.stepName = nil
        self.rowPool[#self.rowPool + 1] = row
        self.activeRows[i] = nil
    end
end

function H:ApplySettings()
    local f = self.frame
    if not f then return end
    local st = state() or {}
    f:ClearAllPoints()
    f:SetPoint(st.point or "CENTER", UIParent, st.relPoint or st.point or "CENTER",
               st.x or 0, st.y or -120)
    f:SetScale(st.scale or 1.0)
    if st.showBackground == false then
        f:SetBackdropColor(0, 0, 0, 0)
    else
        f:SetBackdropColor(0, 0, 0, st.locked and 0.40 or 0.55)
    end
    if st.showBorder == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        f:SetBackdropBorderColor(0.635, 0.000, 0.039, 1)
    end
end

function H:_SavePosition()
    local f, st = self.frame, state()
    if not (f and st) then return end
    local point, _, relPoint, x, y = f:GetPoint()
    st.point, st.relPoint, st.x, st.y = point, relPoint, x, y
end

function H:_ContextMenu()
    if not (MenuUtil and MenuUtil.CreateContextMenu and self.frame) then return end
    MenuUtil.CreateContextMenu(self.frame, function(_, root)
        root:CreateTitle(ns.L["Bonus Objectives"])
        local st = state() or {}
        root:CreateButton(st.locked and ns.L["Unlock (allow moving)"] or ns.L["Lock position"],
            function()
                local s = state(); if s then s.locked = not s.locked end
                H:ApplySettings()
            end)
        root:CreateButton(ns.L["Reset position"], function()
            local s = state()
            if s then s.point, s.relPoint, s.x, s.y = "CENTER", "CENTER", 0, -120 end
            H:ApplySettings()
        end)
        root:CreateDivider()
        root:CreateButton(ns.L["Cancel"], function() end)
    end)
end

-- Parented to UIParent so it stays outside the tracker's secure item-button chain and needs no combat gating
function H:_AcquireFrame()
    if self.frame then return self.frame end
    local f = CreateFrame("Frame", "EverythingQuestsScenarioBonusHUD", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, 40)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        local st = state()
        if st and st.locked then return end
        s:StartMoving()
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        H:_SavePosition()
    end)
    f:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then H:_ContextMenu() end
    end)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", PAD, -6)
    f.title:SetJustifyH("LEFT")
    f.title:SetText(ns.L["Bonus Objectives"])
    f.title:SetTextColor(0.92, 0.72, 0.02)

    self.frame = f
    self:ApplySettings()
    return f
end

local function setReward(row, questID, stepName)
    local btn = row.reward
    if not questID or questID == 0 then btn:Hide(); return end
    btn.questID  = questID
    btn.stepName = stepName
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    if HaveQuestRewardData and not HaveQuestRewardData(questID)
       and C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
        C_TaskQuest.RequestPreloadRewardData(questID)
    end
    local icon
    if GetQuestLogRewardInfo then
        icon = select(2, GetQuestLogRewardInfo(1, questID))
    end
    btn.tex:SetTexture(icon or REWARD_FALLBACK)
    btn:Show()
end

function H:_Render(model)
    if not (model and #model > 0) then
        if self.frame then self.frame:Hide() end
        return
    end
    local f = self:_AcquireFrame()
    self:_ReleaseRows()
    local Media = ns:GetSubsystem("Media")
    local y = TITLE_H + 6

    for i = 1, #model do
        local step = model[i]
        local hrow = self:_AcquireRow(f)
        hrow.icon:Hide()
        hrow.text:ClearAllPoints()
        hrow.text:SetPoint("LEFT", hrow, "LEFT", PAD, 0)
        hrow.text:SetPoint("RIGHT", hrow, "RIGHT", -26, 0)
        hrow.text:SetText(step.name or "")
        hrow.text:SetTextColor(0.92, 0.72, 0.02)
        setReward(hrow, step.rewardQuestID, step.name)
        hrow:ClearAllPoints()
        hrow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
        hrow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
        hrow:SetHeight(math.max(hrow.text:GetStringHeight(), 14))
        if Media and Media.ApplyTextShadow then Media:ApplyTextShadow(hrow.text) end
        y = y + hrow:GetHeight() + ROW_GAP

        local crit = step.criteria
        for c = 1, (crit and #crit or 0) do
            local info = crit[c]
            local crow = self:_AcquireRow(f)
            crow.reward:Hide()
            crow.icon:Show()
            crow.icon:ClearAllPoints()
            crow.icon:SetPoint("LEFT", crow, "LEFT", PAD + 6, 0)
            if info.completed then
                crow.icon:SetAtlas("ui-questtracker-tracker-check", false)
            else
                crow.icon:SetAtlas("ui-questtracker-objective-nub", false)
            end
            crow.text:ClearAllPoints()
            crow.text:SetPoint("LEFT", crow.icon, "RIGHT", 6, 0)
            crow.text:SetPoint("RIGHT", crow, "RIGHT", -6, 0)
            crow.text:SetText(info.text or "")
            if info.completed then
                crow.text:SetTextColor(0.27, 1.0, 0.27)
            else
                crow.text:SetTextColor(0.85, 0.85, 0.85)
            end
            crow:ClearAllPoints()
            crow:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, -y)
            crow:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, -y)
            crow:SetHeight(math.max(crow.text:GetStringHeight(), 14))
            if Media and Media.ApplyTextShadow then Media:ApplyTextShadow(crow.text) end
            y = y + crow:GetHeight() + ROW_GAP
        end
    end

    f:SetHeight(y + PAD - ROW_GAP)
    f:Show()
end

-- Non-delve scenarios that expose real bonus steps (delves report none).
function H:_GatherScenarioSteps()
    local steps = C_Scenario.GetBonusSteps and C_Scenario.GetBonusSteps()
    if not (steps and #steps > 0) then return nil end
    local model = {}
    for i = 1, #steps do
        local bonusStepIndex = steps[i]
        local name, description, numCriteria, _, _, _, shouldShow = C_Scenario.GetStepInfo(bonusStepIndex)
        if shouldShow then
            local step = {
                name = (name and name ~= "" and name) or description or "",
                rewardQuestID = C_Scenario.GetBonusStepRewardQuestID
                                and C_Scenario.GetBonusStepRewardQuestID(bonusStepIndex),
                criteria = {},
            }
            for c = 1, (numCriteria or 0) do
                local info = C_ScenarioInfo.GetCriteriaInfoByStep(bonusStepIndex, c)
                if info then
                    local desc = info.description or ""
                    local label = desc
                    if not info.isFormatted and not info.completed
                       and info.totalQuantity and info.totalQuantity > 0 then
                        label = ("%d/%d %s"):format(info.quantity or 0, info.totalQuantity, desc)
                    end
                    step.criteria[#step.criteria + 1] = { text = label, completed = info.completed }
                end
            end
            model[#model + 1] = step
        end
    end
    return (#model > 0) and model or nil
end

-- Delves expose no scenario bonus steps, so these vignette and player-aura IDs stand in - they churn each season
local NEMESIS_PACK_VIGNETTE = 7531
local RAGER_NAME_MATCH      = "voidfused"
local BANNER_INTERACT_SPELLS = { [1269411] = true, [1269412] = true, [1269416] = true }
local BANNER_BUFFS = {
    1271918, 1271945, 1272609, 1272666, 1272756, 1272769,
    1272809, 1272810, 1272813, 1272814, 1273058, 1273066,
}
local MSG_EVENTS = {
    CHAT_MSG_RAID_BOSS_EMOTE = true, CHAT_MSG_MONSTER_YELL = true,
    CHAT_MSG_MONSTER_EMOTE   = true, CHAT_MSG_MONSTER_SAY  = true,
    UI_INFO_MESSAGE          = true, CHAT_MSG_SYSTEM        = true,
}
local BANNER_RANK = { announced = 1, clicked = 2, buffed = 3, eliteUp = 4, grand = 5 }

local bannerState, ragerGUID
local nemesisSeen, nemesisSeenCount, nemesisRemaining = {}, 0, nil
local trackedDelve, delveTier

local function PlayerInDelve()
    return GetInstanceInfo and select(3, GetInstanceInfo()) == 208
end

local function ReadTier()
    if not (C_ScenarioInfo and C_ScenarioInfo.GetScenarioStepInfo
            and C_UIWidgetManager and C_UIWidgetManager.GetAllWidgetsBySetID) then return nil end
    local ok, stepInfo = pcall(C_ScenarioInfo.GetScenarioStepInfo)
    if not (ok and stepInfo and stepInfo.widgetSetID) then return nil end
    local VT = Enum and Enum.UIWidgetVisualizationType
    local getter = C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo
    if not (VT and VT.ScenarioHeaderDelves and getter) then return nil end
    local ok2, widgets = pcall(C_UIWidgetManager.GetAllWidgetsBySetID, stepInfo.widgetSetID)
    if not (ok2 and type(widgets) == "table") then return nil end
    for _, w in ipairs(widgets) do
        if w.widgetType == VT.ScenarioHeaderDelves then
            local ok3, hv = pcall(getter, w.widgetID)
            local tt = ok3 and hv and tonumber(hv.tierText)
            if tt then return tt end
        end
    end
    return nil
end

local function SetBannerState(s)
    if not BANNER_RANK[s] then return end
    if bannerState and BANNER_RANK[s] <= BANNER_RANK[bannerState] then return end
    bannerState = s
    H:QueueRefresh()
end

local function ScanVignettes()
    if not PlayerInDelve() then return end
    if not (C_VignetteInfo and C_VignetteInfo.GetVignettes) then return end
    local ok, vigs = pcall(C_VignetteInfo.GetVignettes)
    if not (ok and type(vigs) == "table") then return end
    local ragerSeen, packCount = false, 0
    for _, vguid in ipairs(vigs) do
        local ok2, v = pcall(C_VignetteInfo.GetVignetteInfo, vguid)
        if ok2 and v then
            if v.vignetteID == NEMESIS_PACK_VIGNETTE then
                packCount = packCount + 1
                local key = v.objectGUID
                if key and not nemesisSeen[key] then
                    nemesisSeen[key] = true
                    nemesisSeenCount = nemesisSeenCount + 1
                end
            end
            local nm = v.name
            if type(nm) == "string" then
                local ln = nm:lower()
                if ln:find(RAGER_NAME_MATCH, 1, true) then
                    ragerSeen, ragerGUID = true, vguid
                    SetBannerState("eliteUp")
                elseif ln:find("grand sanctified", 1, true) then
                    SetBannerState("grand")
                elseif ln:find("sanctified spoils", 1, true) then
                    SetBannerState("clicked")
                elseif ln:find("sanctified banner", 1, true) then
                    SetBannerState("announced")
                end
            end
        end
    end
    if ragerGUID and not ragerSeen and bannerState == "eliteUp" then
        SetBannerState("grand")
    end
    nemesisRemaining = packCount
end

local function HandleUnitAura()
    if not PlayerInDelve() then return end
    if bannerState and BANNER_RANK[bannerState] >= BANNER_RANK.buffed then return end
    if not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return end
    for _, sid in ipairs(BANNER_BUFFS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura then SetBannerState("buffed"); return end
    end
    for sid in pairs(BANNER_INTERACT_SPELLS) do
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, sid)
        if ok and aura then SetBannerState("clicked"); return end
    end
end

local function HandlePlayerCast(spellID)
    if not (spellID and PlayerInDelve()) then return end
    if BANNER_INTERACT_SPELLS[spellID] then SetBannerState("clicked") end
end

local function HandleMessage(event, a1, a2)
    if not PlayerInDelve() then return end
    local text = (event == "UI_INFO_MESSAGE") and a2 or a1
    if type(text) ~= "string" or text == "" then return end
    if text:lower():find("sanctified banner", 1, true) then SetBannerState("announced") end
end

-- Reset per-run state on delve change or exit so a new run never inherits the old packs or banner
local function CheckRun()
    if not PlayerInDelve() then trackedDelve = nil; return end
    local name = (GetInstanceInfo and GetInstanceInfo()) or "delve"
    if name ~= trackedDelve then
        trackedDelve = name
        delveTier = nil
        bannerState, ragerGUID = nil, nil
        nemesisRemaining, nemesisSeenCount = nil, 0
        wipe(nemesisSeen)
    end
end

function H:_GatherDelveModel()
    CheckRun()
    if not PlayerInDelve() then return nil end
    pcall(ScanVignettes)

    local crit = {}
    if nemesisSeenCount > 0 then
        if not delveTier then delveTier = ReadTier() end
        local tier = delveTier or 0
        local expected = 0
        if     tier >= 10 then expected = 4
        elseif tier >= 8  then expected = 3
        elseif tier >= 6  then expected = 2
        elseif tier >= 4  then expected = 1 end
        local total  = math.max(expected, nemesisSeenCount)
        local killed = math.max(0, nemesisSeenCount - (nemesisRemaining or 0))
        crit[#crit + 1] = {
            text = ("Nemesis Strongbox: %d/%d packs"):format(killed, total),
            completed = killed >= total,
        }
    end
    if bannerState == "grand" then
        crit[#crit + 1] = { text = "Sanctified Banner: Grand Spoils earned", completed = true }
    elseif bannerState == "buffed" or bannerState == "clicked" then
        crit[#crit + 1] = { text = "Sanctified Banner: bonus Spoils secured", completed = true }
    elseif bannerState == "eliteUp" then
        crit[#crit + 1] = { text = "Sanctified Banner: kill the Voidfused Rager", completed = false }
    elseif bannerState == "announced" then
        crit[#crit + 1] = { text = "Sanctified Banner: find it for bonus loot", completed = false }
    end

    if #crit == 0 then return nil end
    return { { name = ns.L["Delve Bonus Loot"], criteria = crit } }
end

function H:_ReconcileDelveEvents()
    local want = enabled() and PlayerInDelve() or false
    if want == self._delveEventsOn then return end
    self._delveEventsOn = want
    self:_SetDelveEvents(want)
end

function H:Refresh()
    if self._test then return end
    self:_ReconcileDelveEvents()
    if not enabled() then
        if self.frame then self.frame:Hide() end
        return
    end
    local model
    if PlayerInDelve() then
        model = self:_GatherDelveModel()
    else
        model = self:_GatherScenarioSteps()
    end
    self:_Render(model)
end

local function doQueuedRefresh()
    H._refreshPending = false
    H:Refresh()
end

function H:QueueRefresh()
    if not enabled() then return end
    if self._refreshPending then return end
    self._refreshPending = true
    C_Timer.After(0.25, doQueuedRefresh)
end

function H:SetEnabled(on)
    local st = state()
    if st then st.enabled = on and true or false end
    if on then
        self:Refresh()
    else
        self._test = false
        self:_ReconcileDelveEvents()
        self:_ReleaseRows()
        if self.frame then self.frame:Hide() end
    end
end

function H:SetScale(v)
    local st = state()
    if st then st.scale = v end
    self:ApplySettings()
end

function H:ToggleTest()
    if self._test then
        self._test = false
        self:Refresh()
    else
        self._test = true
        self:_Render({
            { name = "Bonus: Extra Credit", rewardQuestID = 999999, criteria = {
                { text = "Rescue the trapped villagers", completed = true },
                { text = "0/3 Hidden caches opened",      completed = false },
            } },
            { name = "Bonus: Swift Delver", rewardQuestID = 999999, criteria = {
                { text = "Finish within the time limit",  completed = false },
            } },
        })
    end
    print("|cffEBB706EQ BonusHUD|r test mode " ..
          (self._test and "ON (drag to position; run again to hide)" or "OFF"))
end

function H:Dump()
    local function p(s) print("|cffEBB706EQ BonusHUD|r " .. s) end
    p("enabled=" .. tostring(enabled()) .. "  test=" .. tostring(self._test and true or false))
    if GetInstanceInfo then
        local _, itype, diffID = GetInstanceInfo()
        p(("instance: type=%s difficultyID=%s (208=Delve)"):format(tostring(itype), tostring(diffID)))
    end
    p(("delve: inDelve=%s tier=%s banner=%s nemesisSeen=%s remaining=%s"):format(
        tostring(PlayerInDelve()), tostring(ReadTier()), tostring(bannerState),
        tostring(nemesisSeenCount), tostring(nemesisRemaining)))
    if C_Scenario.GetStepInfo then
        local sname, _, ncrit = C_Scenario.GetStepInfo()
        p(("current step: name=%s numCriteria=%s"):format(tostring(sname), tostring(ncrit)))
        if C_ScenarioInfo and C_ScenarioInfo.GetCriteriaInfo then
            for i = 1, math.min(ncrit or 0, 10) do
                local info = C_ScenarioInfo.GetCriteriaInfo(i)
                if info then
                    p(("  mainCrit[%d] %s done=%s %s/%s"):format(i, tostring(info.description),
                        tostring(info.completed), tostring(info.quantity), tostring(info.totalQuantity)))
                end
            end
        end
    end
    local steps = C_Scenario.GetBonusSteps and C_Scenario.GetBonusSteps()
    p("GetBonusSteps count=" .. tostring(steps and #steps or "nil"))
    if C_VignetteInfo and C_VignetteInfo.GetVignettes then
        local ok, vigs = pcall(C_VignetteInfo.GetVignettes)
        p("vignettes=" .. tostring(ok and type(vigs) == "table" and #vigs or "nil"))
        if ok and type(vigs) == "table" then
            for _, g in ipairs(vigs) do
                local ok2, v = pcall(C_VignetteInfo.GetVignetteInfo, g)
                if ok2 and v then
                    p(("  vig id=%s name=%s"):format(tostring(v.vignetteID), tostring(v.name)))
                end
            end
        end
    end
    if self.frame then p(("frame: shown=%s"):format(tostring(self.frame:IsShown())))
    else p("frame: not created") end
end

function H:_SetDelveEvents(on)
    local ef = self.ef
    if not ef then return end
    if on then
        pcall(ef.RegisterUnitEvent, ef, "UNIT_AURA", "player")
        pcall(ef.RegisterUnitEvent, ef, "UNIT_SPELLCAST_SUCCEEDED", "player")
        for ev in pairs(MSG_EVENTS) do pcall(ef.RegisterEvent, ef, ev) end
        pcall(ef.RegisterEvent, ef, "VIGNETTE_MINIMAP_UPDATED")
        pcall(ef.RegisterEvent, ef, "VIGNETTES_UPDATED")
    else
        pcall(ef.UnregisterAllEvents, ef)
    end
end

function H:OnEnable()
    local Events = ns:GetSubsystem("Events")
    if Events then
        local function refresh() H:QueueRefresh() end
        Events:On("SCENARIO_UPDATE",                     refresh)
        Events:On("SCENARIO_CRITERIA_UPDATE",            refresh)
        Events:On("SCENARIO_CRITERIA_SHOW_STATE_UPDATE", refresh)
        Events:On("SCENARIO_COMPLETED",                  refresh)
        Events:On("ACTIVE_DELVE_DATA_UPDATE",            refresh)
        Events:On("PLAYER_ENTERING_WORLD",               refresh)
        Events:On("ZONE_CHANGED_NEW_AREA",               refresh)
    end

    local ef = CreateFrame("Frame")
    self.ef = ef
    ef:SetScript("OnEvent", function(_, event, ...)
        if not (enabled() and PlayerInDelve()) then return end
        if event == "UNIT_AURA" then
            HandleUnitAura()
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            local _, _, spellID = ...
            HandlePlayerCast(spellID)
        elseif MSG_EVENTS[event] then
            pcall(HandleMessage, event, ...)
        else
            pcall(ScanVignettes)
            H:QueueRefresh()
        end
    end)

    if enabled() then
        self:Refresh()
    end
end
