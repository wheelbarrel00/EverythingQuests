local _, ns = ...
local L = ns.L

local Options = ns:RegisterSubsystem("Options", {})

local HEADER_RED = ns.Util.color.headerRed
local YELLOW     = ns.Util.color.buttonYellow

local EUI = LibStub("EverythingUI-1.0")

local TAB_ICONS = {
    general = "icon-general", map = "icon-map", worldQuests = "icon-globe",
    chainGuide = "icon-chain", history = "icon-history", about = "icon-about",
}

local ui = EUI:NewContext({
    id      = "EQ",
    title   = "Everything Quests",
    version = ns.VERSION or "2.2.0",
    accent  = EUI.tokens.accents.EQ.accent,
    L       = L,
    tooltip = ns.Util.PinTooltip,
    discord = function() ns:ShowDiscord() end,
    -- Looked up here, not in the library, because the locale scanner skips Libs/ and would drop these keys
    labels  = {
        discord         = L["Join our Discord!"],
        discordTipTitle = L["Join our Discord"],
        discordTip      = L["Click to copy the invite link."],
    },
    getLastTab = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.char and DB.char.lastOptionsTab
    end,
    setLastTab = function(id)
        local DB = ns:GetSubsystem("DB")
        if DB and DB.char then DB.char.lastOptionsTab = id end
    end,
    getWindowScale = function()
        local DB = ns:GetSubsystem("DB")
        return DB and DB.db and DB.db.global and DB.db.global.optionsWindowScale
    end,
    setWindowScale = function(v)
        local DB = ns:GetSubsystem("DB")
        if DB and DB.db and DB.db.global then DB.db.global.optionsWindowScale = v end
    end,
})
Options.ui = ui

local function iconFor(id)
    return TAB_ICONS[id] and ui:Texture(TAB_ICONS[id])
end

-- Tab files load after this one and register themselves, so the nav lists only what the TOC loaded
function Options:RegisterTab(def)
    ui:RegisterTab({
        id      = def.id,
        title   = def.title,
        order   = def.order,
        icon    = iconFor(def.id),
        footer  = def.footer,
        build   = def.build,
        refresh = def.refresh,
    })
end

-- Each card anchors to the last one placed, so a card this client leaves out leaves no gap
function Options.CardStack(ctx)
    local prev
    return function(card)
        if prev then
            card:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -ctx:Spacing("groupGap"))
            card:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -ctx:Spacing("groupGap"))
        else
            card:SetPoint("TOPLEFT")
            card:SetPoint("TOPRIGHT")
        end
        prev = card
        return card
    end
end

function Options:Build()
    if self.frame then return end
    local f = ui:BuildSettings("EQOptionsFrame")
    -- Left edge, because EQ Objective Tracker's options window is the same size and centers
    f:ClearAllPoints()
    f:SetPoint("LEFT", UIParent, "LEFT", 16, 0)
    self.frame = f
end

function Options:SelectTab(id)
    ui:SelectTab(id)
end

function Options:ApplyWindowScale()
    ui:ApplyWindowScale()
end

function Options:Toggle()
    self:Build()
    if self.frame:IsShown() then self.frame:Hide() else self:Show() end
end

function Options:Show()
    self:Build()
    -- ToggleSettings would close a window that is already open
    if not self.frame:IsShown() then ui:ToggleSettings() end
    self.frame:Raise()
    local CG = ns:GetSubsystem("ChainGuide")
    if CG and CG.frame and CG.frame:IsShown() then CG.frame:Hide() end
end

function Options:RegisterBlizzardCategory()
    if self._blizzCategory then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return
    end

    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Everything Quests")
    title:SetTextColor(unpack(HEADER_RED))

    local ver = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    ver:SetText(L["Version %s"]:format(ns.VERSION or ""))
    ver:SetTextColor(unpack(YELLOW))

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", ver, "BOTTOMLEFT", 0, -18)
    desc:SetWidth(560)
    desc:SetJustifyH("LEFT")
    desc:SetText(L["Everything Quests opens its full options in a dedicated window. Click the button below, or type |cffEBB706/eqs|r in chat."])

    local btn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    btn:SetSize(240, 26)
    btn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -18)
    btn:SetText(L["Open Everything Quests Options"])
    btn:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel.IsShown and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        Options:Show()
    end)

    local category = Settings.RegisterCanvasLayoutCategory(panel, "Everything Quests")
    Settings.RegisterAddOnCategory(category)
    self._blizzCategory = category
end

function Options:OnEnable()
    self:RegisterBlizzardCategory()
end

local function eqSlashHandler(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "chain" then
        local CG = ns:GetSubsystem("ChainGuide"); if CG then CG:Toggle() end
        return
    elseif msg == "history" then
        local HF = ns:GetSubsystem("HistoryFrame")
        if HF and HF.Toggle then HF:Toggle() end
        return
    elseif msg == "quests" or msg:match("^quests%s") then
        local QB = ns:GetSubsystem("QuestBrowser")
        if not (QB and QB.Available and QB:Available()) then
            print(L["|cffEBB706EQ|r: the quest browser needs the Classic quest data, which this version of the game does not load."])
            return
        end
        QB:Search(msg:match("^quests%s+(.+)$"))
        return
    elseif msg == "session" then
        local Sess = ns:GetSubsystem("Session")
        if Sess and Sess.Print then Sess:Print() end
        return
    elseif msg == "whatsnew chat" then
        local WN = ns:GetSubsystem("WhatsNew")
        if WN and WN.PrintChatLink then WN:PrintChatLink() end
        return
    elseif msg == "whatsnew" or msg == "changes" then
        local WN = ns:GetSubsystem("WhatsNew")
        if WN and WN.Show then WN:Show() end
        return
    elseif msg == "about" then
        Options:Show()
        Options:SelectTab("about")
        return
    elseif msg:match("^flavorprobe") then
        if ns.FlavorProbe then ns.FlavorProbe:Run(msg:match("^flavorprobe%s+(.+)$")) end
        return
    elseif msg:match("^discover") then
        local hint = msg:match("^discover%s+(.+)$")
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.PrintCurrentZone then QLS:PrintCurrentZone(hint) end
        return
    elseif msg == "wqdebug" then
        Options:DumpWorldQuestSources()
        return
    elseif msg == "scenario" then
        Options:DumpScenarioInfo()
        return
    elseif msg == "questobj" then
        Options:DumpQuestObjectives()
        return
    elseif msg == "autopopup" then
        Options:DumpAutoQuestPopups()
        return
    elseif msg == "dir" then
        Options:DumpDirections()
        return
    elseif msg == "questzone" then
        if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
            print("|cffEBB706EQ QuestZone|r: quest log API unavailable.")
            return
        end
        local function mapName(m)
            if m and m > 0 and C_Map and C_Map.GetMapInfo then
                local mi = C_Map.GetMapInfo(m)
                return (mi and mi.name) or "?"
            end
            return "-"
        end
        local n = C_QuestLog.GetNumQuestLogEntries()
        local header = "(none)"
        local pMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local onMapSet = {}
        if pMap and C_QuestLog.GetQuestsOnMap then
            for _, e in ipairs(C_QuestLog.GetQuestsOnMap(pMap) or {}) do
                if e.questID then onMapSet[e.questID] = true end
            end
        end
        print(("|cffEBB706EQ QuestZone|r zone=|cff66ccff%s|r  playerMap=%s(%s) — 'only current zone' shows a quest when onMap=Y or hdr==zone:"):format(
            tostring(GetZoneText and GetZoneText() or "?"), tostring(pMap), mapName(pMap)))
        print(("   %d entries — id title | hdr | onMap | Task=GetQuestZoneID | UiMap=GetQuestUiMapID:"):format(n))
        for i = 1, n do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    header = info.title or "(unnamed)"
                elseif not info.isHidden then
                    local qid = info.questID
                    local tz  = C_TaskQuest and C_TaskQuest.GetQuestZoneID and C_TaskQuest.GetQuestZoneID(qid)
                    local ok, um = pcall(function() return GetQuestUiMapID and GetQuestUiMapID(qid) end)
                    if not ok then um = "ERR" end
                    print(("   %s %s | hdr=|cff66ccff%s|r | onMap=%s | Task=%s(%s) | UiMap=%s(%s)"):format(
                        tostring(qid), tostring(info.title), tostring(header),
                        onMapSet[qid] and "|cff44ff44Y|r" or "|cff888888n|r",
                        tostring(tz), mapName(tz), tostring(um), mapName(tonumber(um))))
                end
            end
        end
        return
    elseif msg == "chaindump" then
        local DBm = ns:GetSubsystem("ChainGuideDatabase")
        local H   = ns:GetSubsystem("ChainGuideHistory")
        local state   = H and H.Current and H:Current()
        local chainID = state and state.type == "chain" and state.id
        local chain   = chainID and DBm and DBm.chains[chainID]
        if not chain then
            print("|cffEBB706EQ ChainDump|r: open the Chain Guide and select a chain first.")
            return
        end
        local QLS = ns:GetSubsystem("ChainGuideQuestLineSource")
        if QLS and QLS.EnsureChainItems then QLS:EnsureChainItems(chain) end
        DBm:NormalizeChain(chain)
        print(("|cffEBB706EQ ChainDump|r |cffffffff%s|r  chainID=|cff66ccff%s|r questlineID=|cff66ccff%s|r category=|cff66ccff%s|r"):format(
            chain.name or "?", tostring(chain.id), tostring(chain.questlineID), tostring(chain.category)))
        local items = chain.items or {}
        print(("  %d item(s) (copy/paste this to share):"):format(#items))
        for i = 1, #items do
            local it = items[i]
            local nm
            if it.type == "chain" then
                local sub = DBm.chains[it.id]
                nm = (sub and sub.name) or "?"
            else
                nm = (ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(it.id)) or "?"
            end
            print(("    [%d] %s id=%s x=%s y=%s  %s"):format(
                i, it.type or "quest", tostring(it.id), tostring(it.x), tostring(it.y), nm))
        end
        return
    elseif msg == "campdump" then
        local DBm = ns:GetSubsystem("ChainGuideDatabase")
        if not (C_CampaignInfo and C_CampaignInfo.GetChapterIDs
                and C_QuestLine and C_QuestLine.GetQuestLineQuests) then
            print("|cffEBB706EQ CampDump|r: campaign/questline API unavailable on this build.")
            return
        end
        local camps = {}
        if DBm then
            for _, cat in pairs(DBm.categories) do
                if cat.campaignID then camps[#camps + 1] = { id = cat.campaignID, name = cat.name } end
            end
        end
        if #camps == 0 then
            print("|cffEBB706EQ CampDump|r: no campaign categories registered.")
            return
        end
        table.sort(camps, function(a, b) return a.id < b.id end)
        for c = 1, #camps do
            local camp = camps[c]
            local chapters = C_CampaignInfo.GetChapterIDs(camp.id) or {}
            print(("|cffEBB706EQ CampDump|r |cffffffff%s|r  campaignID=|cff66ccff%d|r  %d chapter(s):"):format(
                camp.name or "?", camp.id, #chapters))
            for i = 1, #chapters do
                local chID = chapters[i]
                local ci = C_CampaignInfo.GetCampaignChapterInfo
                           and C_CampaignInfo.GetCampaignChapterInfo(chID)
                local quests = C_QuestLine.GetQuestLineQuests(chID) or {}
                print(("    [%d] questlineID=|cff66ccff%d|r %s  (%d quest(s))"):format(
                    i, chID, (ci and ci.name) or "?", #quests))
                if #quests > 0 then
                    print("        " .. table.concat(quests, ", "))
                end
            end
        end
        return
    elseif msg:match("^campfind") then
        local filter = msg:match("^campfind%s+(.+)$")
        if not (C_CampaignInfo and C_CampaignInfo.GetCampaignInfo) then
            print("|cffEBB706EQ CampFind|r: campaign API unavailable on this build.")
            return
        end
        local DBm = ns:GetSubsystem("ChainGuideDatabase")
        local known = {}
        if DBm then
            for _, cat in pairs(DBm.categories) do
                if cat.campaignID then known[cat.campaignID] = cat.name or "?" end
            end
        end
        local seen, ids = {}, {}
        local function add(id)
            if id and id > 0 and not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
        if C_CampaignInfo.GetAvailableCampaigns then
            for _, id in ipairs(C_CampaignInfo.GetAvailableCampaigns() or {}) do add(id) end
        end
        -- GetAvailableCampaigns does not return every campaign - the live run missed both registered ones
        if C_CampaignInfo.GetCampaignID and C_QuestLog
           and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
            for i = 1, C_QuestLog.GetNumQuestLogEntries() do
                local info = C_QuestLog.GetInfo(i)
                if info and not info.isHeader and info.questID then
                    add(C_CampaignInfo.GetCampaignID(info.questID))
                end
            end
        end
        table.sort(ids)
        local needle = filter and filter:gsub("[^%w]", "")
        print(("|cffEBB706EQ CampFind|r %d campaign(s) visible%s:"):format(
            #ids, needle and (" \194\183 filter '" .. filter .. "'") or ""))
        local shown = 0
        for c = 1, #ids do
            local id   = ids[c]
            local ci   = C_CampaignInfo.GetCampaignInfo(id)
            local name = (ci and ci.name) or "?"
            local flat = name:lower():gsub("[^%w]", "")
            if not needle or flat:find(needle, 1, true) then
                shown = shown + 1
                local chapters = (C_CampaignInfo.GetChapterIDs and C_CampaignInfo.GetChapterIDs(id)) or {}
                print(("  campaignID=|cff66ccff%d|r |cffffffff%s|r  %d chapter(s)  %s"):format(
                    id, name, #chapters,
                    known[id] and ("|cff44ff44registered as '" .. known[id] .. "'|r")
                              or "|cffff6666NOT registered|r"))
                for i = 1, #chapters do
                    local chID = chapters[i]
                    local chi  = C_CampaignInfo.GetCampaignChapterInfo
                                 and C_CampaignInfo.GetCampaignChapterInfo(chID)
                    local quests = (C_QuestLine and C_QuestLine.GetQuestLineQuests
                                    and C_QuestLine.GetQuestLineQuests(chID)) or {}
                    print(("    [%d] questlineID=|cff66ccff%d|r %s  (%d quest(s))"):format(
                        i, chID, (chi and chi.name) or "?", #quests))
                end
                if not known[id] then
                    print(("    paste into _Index.lua:  campaignID = %d, name = \"%s\""):format(id, name))
                end
            end
        end
        if shown == 0 then
            print("  (nothing matched \194\183 run |cffffffff/eqs campfind|r with no filter to list them all)")
        end
        return
    elseif msg:match("^zonedump") then
        local hint = msg:match("^zonedump%s+(.+)$")
        local DBm  = ns:GetSubsystem("ChainGuideDatabase")
        if not (hint and DBm and ns.QUESTLINE_ROUTING
                and C_QuestLine and C_QuestLine.GetQuestLineQuests) then
            print("|cffEBB706EQ ZoneDump|r: usage |cffffffff/eqs zonedump <zone>|r (eversong, zulaman, harandar, voidstorm, arator)")
            return
        end
        local lower = hint:lower():gsub("[^%w]", "")
        local catID, catName
        for id, cat in pairs(DBm.categories) do
            local cn = (cat.name or ""):lower():gsub("[^%w]", "")
            if cn ~= "" and (cn == lower or cn:find(lower, 1, true) or lower:find(cn, 1, true)) then
                catID, catName = id, cat.name
                break
            end
        end
        if not catID then
            print(("|cffEBB706EQ ZoneDump|r: no category matches '%s'."):format(hint))
            return
        end
        local qls = {}
        for qlID, entry in pairs(ns.QUESTLINE_ROUTING) do
            local ecat = (type(entry) == "table") and entry.cat or entry
            if ecat == catID then
                qls[#qls + 1] = { id = qlID, name = (type(entry) == "table") and entry.name or nil }
            end
        end
        table.sort(qls, function(a, b) return a.id < b.id end)
        print(("|cffEBB706EQ ZoneDump|r |cffffffff%s|r  categoryID=|cff66ccff%d|r  %d questline(s):"):format(
            catName or "?", catID, #qls))
        for i = 1, #qls do
            local q = qls[i]
            local quests = C_QuestLine.GetQuestLineQuests(q.id) or {}
            print(("    [%d] questlineID=|cff66ccff%d|r %s  (%d quest(s))"):format(
                i, q.id, q.name or "?", #quests))
            if #quests > 0 then
                print("        " .. table.concat(quests, ", "))
            end
        end
        return
    elseif msg:match("^profile") then
        local rest = msg:match("^profile%s*(.*)$") or ""
        local Profiler = ns:GetSubsystem("Profiler")
        if not Profiler then return end
        if rest == "" or rest == "show" then
            Profiler:Show()
        elseif rest == "reset" then
            Profiler:Reset()
            print("|cffEBB706EQ Profile|r reset")
        elseif rest:match("^memhog") then
            Profiler:ToggleMemHog()
            print("|cffEBB706EQ Profile|r memhog "
                  .. (Profiler.memhog and Profiler.memhog.active and "ON" or "OFF"))
        elseif rest:match("^mem%s+on") then
            Profiler:SetMemoryMode(true)
            print("|cffEBB706EQ Profile|r memory mode ON — collectgarbage forced at boundaries (expensive; toggle off when done)")
        elseif rest:match("^mem%s+off") then
            Profiler:SetMemoryMode(false)
            print("|cffEBB706EQ Profile|r memory mode OFF")
        elseif rest:match("^auto%s+on") then
            local wrapped, missing = Profiler:AutoInstrument(true)
            print(("|cffEBB706EQ Profile|r auto-instrument ON \194\183 wrapped %d hot path%s%s"):format(
                wrapped, wrapped == 1 and "" or "s",
                missing > 0 and (", " .. missing .. " missing (subsystem not loaded)") or ""))
            print("  Use /eqs profile show after playing for a few minutes; /eqs profile auto off to unwrap")
        elseif rest:match("^auto%s+off") then
            local n = Profiler:AutoInstrument(false)
            print(("|cffEBB706EQ Profile|r auto-instrument OFF \194\183 unwrapped %d method%s"):format(
                n, n == 1 and "" or "s"))
        elseif rest:match("^auto%s+list") or rest == "auto" then
            local list = Profiler:ListWrapped()
            if #list == 0 then
                print("|cffEBB706EQ Profile|r auto-instrument is OFF (nothing wrapped)")
            else
                print(("|cffEBB706EQ Profile|r currently wrapped (%d):"):format(#list))
                for _, k in ipairs(list) do print("  " .. k) end
            end
        else
            print("|cffEBB706EQ Profile|r usage: /eqs profile [show | reset | mem on | mem off | memhog | auto on | auto off | auto list]")
        end
        return
    end
    local ok, err = pcall(function() Options:Toggle() end)
    if not ok then
        print(L["|cffEBB706Everything Quests|r: couldn't open Options \226\128\148 %s"]:format(tostring(err)))
    end
end

-- "/eq" is Blizzard's secure /equip and is dispatched before SlashCmdList, so an "/eq" handler is unreachable and risks taint
SLASH_EVERYTHINGQUESTS1 = "/eqs"
SLASH_EVERYTHINGQUESTS2 = "/everythingquests"
SlashCmdList["EVERYTHINGQUESTS"] = eqSlashHandler

function Options:DumpScenarioInfo()
    local function line(label, value) print(("|cffEBB706EQ Scenario|r %s: %s"):format(label, tostring(value))) end

    if C_Scenario and C_Scenario.GetInfo then
        local name, currentStage, numStages, _, _, _, _, _, _, scenarioType, _, textureKit = C_Scenario.GetInfo()
        line("scenarioName", name or "(nil)")
        line("scenarioType", scenarioType or "(nil)")
        line("textureKit",   textureKit or "(nil)")
        line("stage",        tostring(currentStage or "?") .. " / " .. tostring(numStages or "?"))
    else
        line("C_Scenario.GetInfo", "unavailable")
    end

    if C_Scenario and C_Scenario.GetStepInfo then
        local stepName = C_Scenario.GetStepInfo()
        line("stepName", stepName or "(nil)")
    end

    if C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo then
        local si = C_ScenarioInfo.GetScenarioInfo()
        line("GetScenarioInfo.name", (si and si.name) or "(nil)")
    end

    if GetInstanceInfo then
        local instName, instType, diffID, diffName = GetInstanceInfo()
        line("instance name",  instName or "(nil)")
        line("instance type",  instType or "(nil)")
        line("difficulty",     tostring(diffName) .. " (id " .. tostring(diffID) .. ")")
    end

    do
        local instName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
        local si = C_ScenarioInfo and C_ScenarioInfo.GetScenarioInfo and C_ScenarioInfo.GetScenarioInfo()
        local sName = C_Scenario and C_Scenario.GetInfo and select(1, C_Scenario.GetInfo()) or nil
        local proposed = (instName and instName ~= "" and instName)
                         or (si and si.name)
                         or sName
        line("<- proposed name line", proposed or "(none)")
    end

    if C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        line("map", ((info and info.name) or "?") .. " (id " .. tostring(mapID) .. ")")
    end
end

function Options:DumpQuestObjectives()
    local function p(s) print("|cffEBB706EQ QuestObj|r " .. s) end
    if not C_QuestLog then p("C_QuestLog unavailable"); return end

    local num     = (C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries()) or 0
    local savedID = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    local getText = _G.GetQuestLogQuestText
    local shown   = 0

    for i = 1, num do
        local info = C_QuestLog.GetInfo and C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            local id      = info.questID
            local watched = C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(id) ~= nil
            if watched then
                local objs     = (C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)) or {}
                local complete = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id)
                local ready    = C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(id)
                p(("[%d] %s | obj=%d complete=%s ready=%s"):format(
                    id, info.title or "?", #objs, tostring(complete), tostring(ready)))
                for j = 1, #objs do
                    local o = objs[j]
                    p(("    obj%d type=%s finished=%s text=%q"):format(
                        j, tostring(o.type), tostring(o.finished), tostring(o.text)))
                end
                if #objs == 0 then
                    local compText = C_QuestLog.GetQuestLogCompletionText
                                     and C_QuestLog.GetQuestLogCompletionText(id)
                    p(("    completionText=%q"):format(tostring(compText)))
                    if getText and C_QuestLog.SetSelectedQuest then
                        C_QuestLog.SetSelectedQuest(id)
                        local _, objText = getText()
                        p(("    objectivesText=%q"):format(tostring(objText)))
                    end
                end
                shown = shown + 1
            end
        end
    end

    if savedID and savedID ~= 0 and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(savedID)
    end
    if shown == 0 then p("no watched quests found") end
end

function Options:DumpDirections()
    local function p(s) print("|cffEBB706EQ Dir|r " .. s) end
    if not C_Map then p("C_Map unavailable"); return end

    local pMap   = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pPos   = pMap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pMap, "player")
    local ppx, ppy
    if pPos then ppx, ppy = pPos:GetXY() end
    local pCont, pWorld
    if pPos and C_Map.GetWorldPosFromMapPos then
        pCont, pWorld = C_Map.GetWorldPosFromMapPos(pMap, pPos)
    end

    local function yards(mapID, x, y)
        if not (pWorld and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
        local c, w = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
        if not w or c ~= pCont then return nil end
        local wx, wy = w:GetXY()
        local px, py = pWorld:GetXY()
        local dx, dy = px - wx, py - wy
        return math.sqrt(dx * dx + dy * dy)
    end

    local function line(label, mapID, x, y)
        if not (mapID and x and y) then
            p(("  %-20s |cffff5555none|r"):format(label))
            return
        end
        local d = yards(mapID, x, y)
        p(("  %-20s map %d  %.1f, %.1f%s"):format(
            label, mapID, x * 100, y * 100,
            d and ("  |cff88ff88%.0f yds|r"):format(d) or "  |cff888888(off-continent)|r"))
    end

    local questID = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID
                    and C_SuperTrack.GetSuperTrackedQuestID()
    if (not questID or questID == 0) and C_QuestLog and C_QuestLog.GetQuestIDForQuestWatchIndex
       and C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches() > 0 then
        questID = C_QuestLog.GetQuestIDForQuestWatchIndex(1)
    end
    if not questID or questID == 0 then
        p("no super-tracked or watched quest — super-track the quest you're testing, then re-run")
        return
    end

    local title = (ns.Util and ns.Util.QuestTitle and ns.Util.QuestTitle(questID, true)) or tostring(questID)
    p(("|cffffffff%s|r (id %d)"):format(title, questID))
    p(("  %-20s map %s  %.1f, %.1f"):format("player at", tostring(pMap), (ppx or 0) * 100, (ppy or 0) * 100))

    local logIdx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID
                   and C_QuestLog.GetLogIndexForQuestID(questID)
    p("  active in log:       " .. (logIdx and "YES (live objective wins)" or "no (giver coords only)"))

    if C_QuestLog and C_QuestLog.GetNextWaypoint then
        line("GetNextWaypoint", C_QuestLog.GetNextWaypoint(questID))
    end
    if pMap and C_QuestLog and C_QuestLog.GetNextWaypointForMap then
        local fx, fy = C_QuestLog.GetNextWaypointForMap(questID, pMap)
        line("NextWaypointForMap", pMap, fx, fy)
    end

    local st = ns.CHAINGUIDE_QUEST_COORDS and ns.CHAINGUIDE_QUEST_COORDS[questID]
    line("bundled coords", st and st.m, st and st.x, st and st.y)

    local DB = ns:GetSubsystem("DB")
    local ce = DB and DB.chainCache and DB.chainCache.questCoords and DB.chainCache.questCoords[questID]
    line("harvested cache", ce and ce.m, ce and ce.x, ce and ce.y)

    local complete = C_QuestLog and C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID)
    local ready    = C_QuestLog and C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID)
    p(("  state:               complete=%s readyForTurnIn=%s"):format(tostring(complete), tostring(ready)))

    local poiFn = _G["QuestPOIGetIconInfo"]
    if poiFn then
        local _, px, py = poiFn(questID)
        line("QuestPOIGetIconInfo", px and pMap, px, py)
    else
        p("  QuestPOIGetIconInfo  |cff888888(API absent)|r")
    end

    if C_QuestLog and C_QuestLog.GetQuestsOnMap and pMap then
        local hit
        for _, e in ipairs(C_QuestLog.GetQuestsOnMap(pMap) or {}) do
            if e.questID == questID then hit = e; break end
        end
        if hit then line("GetQuestsOnMap", pMap, hit.x, hit.y)
        else p("  GetQuestsOnMap       |cff888888(quest not listed on this map)|r") end
    else
        p("  GetQuestsOnMap       |cff888888(API absent)|r")
    end

    local W = ns:GetSubsystem("ChainGuideWaypoint")
    if logIdx then
        p("  => WINNER:           super-track the quest -> Blizzard's live objective / turn-in POI"
          .. (TomTom and " (+ TomTom pin at the live objective, or turn-in via GetQuestsOnMap)" or ""))
    elseif W and W.Resolve then
        line("=> WINNER", W:Resolve(questID))
    end
end

function Options:DumpAutoQuestPopups()
    local function p(s) print("|cffEBB706EQ AutoPopup|r " .. s) end

    local function has(name) return _G[name] and "yes" or "no" end
    p(("API: GetNumAutoQuestPopUps=%s GetAutoQuestPopUp=%s RemoveAutoQuestPopUp=%s"):format(
        has("GetNumAutoQuestPopUps"), has("GetAutoQuestPopUp"), has("RemoveAutoQuestPopUp")))
    p(("API: ShowQuestOffer=%s ShowQuestComplete=%s"):format(
        has("ShowQuestOffer"), has("ShowQuestComplete")))
    p(("API (C_): C_QuestLog.GetNumAutoQuestPopUps=%s"):format(
        (C_QuestLog and C_QuestLog.GetNumAutoQuestPopUps) and "yes" or "no"))

    local getNum = _G.GetNumAutoQuestPopUps
                   or (C_QuestLog and C_QuestLog.GetNumAutoQuestPopUps)
    local getPop = _G.GetAutoQuestPopUp
                   or (C_QuestLog and C_QuestLog.GetAutoQuestPopUp)
    if not (getNum and getPop) then
        p("no usable GetNumAutoQuestPopUps/GetAutoQuestPopUp — engine API moved or unavailable")
        return
    end

    local n = getNum() or 0
    p(("active popups: %d"):format(n))
    for i = 1, n do
        local questID, popUpType = getPop(i)
        local title = questID and (
            (C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID))
            or (QuestUtils_GetQuestName and QuestUtils_GetQuestName(questID)))
        p(("  [%d] questID=%s type=%q title=%q"):format(
            i, tostring(questID), tostring(popUpType), tostring(title or "?")))
    end
    if n == 0 then
        p("none right now — run this while a 'Quest Discovered!'/'Quest Complete!' box is up")
    end
end

function Options:DumpWorldQuestSources()
    local function info(line) print("|cffEBB706EQ WQ:|r " .. line) end
    local function quest(qid, suffix)
        local title = (C_TaskQuest and C_TaskQuest.GetQuestInfoByQuestID
                       and C_TaskQuest.GetQuestInfoByQuestID(qid))
                      or (C_QuestLog and C_QuestLog.GetTitleForQuestID
                          and C_QuestLog.GetTitleForQuestID(qid))
                      or "?"
        return ("    [%d] %s%s"):format(qid, title, suffix or "")
    end

    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapInfo = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    info(("player map: %s (id %s)"):format(mapInfo and mapInfo.name or "?", tostring(mapID)))

    if C_QuestLog and C_QuestLog.GetNumWorldQuestWatches then
        local n = C_QuestLog.GetNumWorldQuestWatches() or 0
        info(("GetNumWorldQuestWatches: %d"):format(n))
        for i = 1, n do
            local qid = C_QuestLog.GetQuestIDForWorldQuestWatchIndex(i)
            if qid then print(quest(qid)) end
        end
    end

    local Watch = ns:GetSubsystem("WQWatchPersist")
    if Watch and Watch.GetTrackedQuests then
        local list = Watch:GetTrackedQuests() or {}
        info(("WQWatchPersist:GetTrackedQuests: %d"):format(#list))
        for _, qid in ipairs(list) do print(quest(qid)) end
    end

    local taskFn = C_TaskQuest and (C_TaskQuest.GetQuestsOnMap or C_TaskQuest.GetQuestsForPlayerByMapID)
    info(("TaskQuest API: %s"):format(
        (C_TaskQuest and C_TaskQuest.GetQuestsOnMap and "GetQuestsOnMap")
        or (C_TaskQuest and C_TaskQuest.GetQuestsForPlayerByMapID and "GetQuestsForPlayerByMapID (deprecated)")
        or "none available"))
    if taskFn and mapID then
        local m, depth = mapID, 0
        while m and depth < 5 do
            local list = taskFn(m) or {}
            local mi = C_Map.GetMapInfo and C_Map.GetMapInfo(m)
            info(("TaskQuest@map %d (%s): %d entries"):format(m, mi and mi.name or "?", #list))
            for i = 1, #list do
                local q = list[i]
                local qid = q and (q.questId or q.questID)
                if qid then
                    print(quest(qid, q.inProgress and "  |cff44ff44(inProgress)|r" or "  |cff666666(idle)|r"))
                    if q.inProgress and C_QuestLog and C_QuestLog.GetQuestObjectives then
                        local objs = C_QuestLog.GetQuestObjectives(qid) or {}
                        if #objs == 0 then
                            print("        |cff999999(no objectives loaded yet)|r")
                        else
                            for k = 1, #objs do
                                local o = objs[k]
                                print(("        - %s%s"):format(
                                    o.text or "?",
                                    o.finished and "  |cff44ff44[done]|r" or ""))
                            end
                        end
                    end
                end
            end
            m = mi and mi.parentMapID
            depth = depth + 1
        end
    end

    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries then
        local n = C_QuestLog.GetNumQuestLogEntries() or 0
        info(("QuestLog entries: %d"):format(n))
        for i = 1, n do
            local qi = C_QuestLog.GetInfo(i)
            if qi and qi.questID and not qi.isHeader and not qi.isHidden then
                local flags = {}
                if qi.isTask    then flags[#flags + 1] = "task"    end
                if qi.isBounty  then flags[#flags + 1] = "bounty"  end
                if qi.isOnMap   then flags[#flags + 1] = "onMap"   end
                if QuestUtils_IsQuestWorldQuest and QuestUtils_IsQuestWorldQuest(qi.questID) then
                    flags[#flags + 1] = "wq"
                end
                if C_QuestLog.GetQuestWatchType
                   and C_QuestLog.GetQuestWatchType(qi.questID) then
                    flags[#flags + 1] = "watched"
                end
                if #flags > 0 then
                    print(("    [%d] %s  |cff5c9eff{%s}|r"):format(
                        qi.questID, qi.title or "?", table.concat(flags, ",")))
                end
            end
        end
    end

    if C_QuestLog and C_QuestLog.GetActiveThreatMaps then
        local maps = C_QuestLog.GetActiveThreatMaps() or {}
        info(("GetActiveThreatMaps: %d"):format(#maps))
        for _, m in ipairs(maps) do print("    map " .. tostring(m)) end
    end
end
