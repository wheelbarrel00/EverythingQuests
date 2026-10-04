local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/everything-quests"
local GITHUB_URL     = "https://github.com/wheelbarrel00/EverythingQuests"
local BUG_URL        = "https://github.com/wheelbarrel00/EverythingQuests/issues"

-- sub names the subsystem that serves the command, so a flavor without it does not list the command
local COMMANDS = {
    { cmd = "/eqs",          desc = L["Open or close the options window"] },
    { cmd = "/eqs chain",    desc = L["Open the Chain Guide"], sub = "ChainGuide" },
    { cmd = "/eqs history",  desc = L["Open the Quest History window"], sub = "HistoryFrame" },
    { cmd = "/eqs quests",   desc = L["Look up almost any quest in the game"], sub = "QuestBrowser" },
    { cmd = "/eqs session",  desc = L["Recap your current play session in chat"], sub = "Session" },
    { cmd = "/eqs discover", desc = L["List the current zone's quest chains in chat"], sub = "ChainGuideQuestLineSource" },
    { cmd = "/eqs whatsnew", desc = L["Show the What's New popup again"], sub = "WhatsNew" },
    { cmd = "/eqs about",    desc = L["Open this About tab"] },
}

-- Names are drawn raw, not through L[], so a row costs no locale key
local OTHER_ADDONS = {
    { name = "EQ Objective Tracker",
      cf   = "https://www.curseforge.com/wow/addons/eq-objective-tracker",
      gh   = "https://github.com/wheelbarrel00/EQObjectiveTracker" },
    { name = "Everything Delves",
      cf   = "https://www.curseforge.com/wow/addons/everything-delves",
      gh   = "https://github.com/wheelbarrel00/EverythingDelves" },
    { name = "Cooldown Master",
      cf   = "https://www.curseforge.com/wow/addons/cooldown-master",
      gh   = "https://github.com/wheelbarrel00/CooldownMaster" },
    { name = "Loot Pro",
      cf   = "https://www.curseforge.com/wow/addons/loot-pro",
      gh   = "https://github.com/wheelbarrel00/LootPro" },
}

local THANKS = "Spydawg2233, Zox, LightsBeacon, Fostot, DrahgunFyre, ChipW0lf, tanglies"

local CREDITS = {
    { name = "DrahgunFyre", tail = L[" for the many features, fixes, and reports that keep shaping Everything Quests."] },
    { name = "Zox",         tail = L[" for the many hours spent translating Everything Quests into French."] },
    { name = "Malevi4",     tail = L[" for the many hours spent translating Everything Quests into Russian."] },
    { name = "labrie75",    tail = L[" for the many hours spent translating Everything Quests into Korean."] },
    { name = "Keriaovo",    tail = L[" for the many hours spent translating Everything Quests into Simplified Chinese."] },
    { name = "BNS333",      tail = L[" for the many hours spent translating Everything Quests into Traditional Chinese."] },
    { name = "Stonetwist",  tail = L[" for the many hours spent translating Everything Quests into German."] },
}

local function colorCode(ui, name)
    local r, g, b = ui:Color(name)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
                                       math.floor(b * 255 + 0.5))
end

-- The Chain Guide's sources tell the three clients apart: retail's quest lines, Forever's own build
local function description()
    local lead
    if ns:GetSubsystem("ChainGuideQuestLineSource") then
        lead = L["Better questing across the whole game: markers for your quests on the world map, world quests with reward and faction filters, a guide to Midnight's quest chains, a history of every quest you turn in, and quest progress on nameplates."]
    elseif ns:GetSubsystem("ChainGuide") then
        lead = L["Better questing for WoW Forever: objective markers on the world map and minimap, every quest giver with something for you, a guide to the quest chains, a browser for almost any quest you have not picked up yet, and quest progress on tooltips and nameplates."]
    else
        lead = L["Better questing for Classic: objective markers on the world map and minimap, every quest giver with something for you, a browser for almost any quest you have not picked up yet, and quest progress on tooltips and nameplates."]
    end
    return lead .. " " .. L["Its objective tracker is EQ Objective Tracker, a separate addon that installs with it."]
end

local function introCard(self, content, stack)
    local card = stack(self:CreateGroup(content, nil))

    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ns.NAME, "Version"))
        or ns.VERSION or "?"
    -- The client names its own version, because a hardcoded one went stale and named the wrong game on Classic
    local clientVer = "?"
    if type(_G.GetBuildInfo) == "function" then
        local okBuild, v = pcall(GetBuildInfo)
        if okBuild and type(v) == "string" and v ~= "" then clientVer = v end
    end

    local blurb = self:CreateTextBlock(content)
    blurb:AddLine(L["Version %s"]:format(ver) .. " " .. L["by Wheelbarrel00"] .. "   "
        .. colorCode(self, "muted") .. L["for WoW %s"]:format(clientVer) .. "|r", "value")
    blurb:AddLine(description())
    card:Add(blurb, { fitHeight = true })

    local links = CreateFrame("Frame", nil, content)
    links:SetHeight(self:Spacing("buttonHeight"))
    local list = {
        { label = L["Join our Discord"], onClick = function() ns:ShowDiscord() end },
        { label = L["CurseForge"],       onClick = function() ns:ShowURL(CURSEFORGE_URL) end },
        { label = L["GitHub"],           onClick = function() ns:ShowURL(GITHUB_URL) end },
        { label = L["Report a Bug"],     onClick = function() ns:ShowURL(BUG_URL) end },
    }
    if ns:GetSubsystem("WhatsNew") then
        list[#list + 1] = { label = L["What's New"], onClick = function()
            local WN = ns:GetSubsystem("WhatsNew")
            if WN and WN.Show then WN:Show() end
        end }
    end
    local prev
    for _, lk in ipairs(list) do
        local b = self:CreateButton(content, lk.label, nil, lk.onClick)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", self:Spacing("buttonGap"), 0)
        else
            b:SetPoint("LEFT", links, "LEFT")
        end
        prev = b
    end
    card:Add(links, { fill = true })
end

local function commandsCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["Commands"]))
    for _, c in ipairs(COMMANDS) do
        if not c.sub or ns:GetSubsystem(c.sub) then
            local row = self:CreateTextRow(content, c.cmd, c.desc)
            row.label:SetTextColor(self:Color("text"))
            card:Add(row, { height = self:Spacing("listRowHeight") })
        end
    end
    if ns:GetSubsystem("Minimap") then
        local tip = self:CreateTextBlock(content)
        tip:AddLine(L["Tip: right-click the minimap button to open Options."], "hint")
        card:Add(tip, { fitHeight = true })
    end
end

local function tutorialsCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["Tutorials"]))
    local note = self:CreateTextBlock(content)
    note:AddLine(L["Video tutorials are coming soon."], "hint")
    card:Add(note, { fitHeight = true })
end

local function addonsCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["More Add-ons by Wheelbarrel00"]))
    for _, a in ipairs(OTHER_ADDONS) do
        local row = self:CreateTextRow(content, a.name, "")
        row.label:SetTextColor(self:Color("text"))
        card:Add(row)
        -- On the row's text column, which the card moves past its widest name in any client font
        local cf = self:CreateButton(content, L["CurseForge"], nil, function() ns:ShowURL(a.cf) end, nil, "ghost")
        cf:SetPoint("LEFT", row.text, "LEFT", 0, 0)
        local gh = self:CreateButton(content, L["GitHub"], nil, function() ns:ShowURL(a.gh) end, nil, "ghost")
        gh:SetPoint("LEFT", cf, "RIGHT", self:Spacing("buttonGap"), 0)
    end
end

local function thanksCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["Thanks"]))
    local bright = colorCode(self, "text")
    -- |r falls back to the line's own color, so only the names need an escape
    local community = self:CreateTextBlock(content)
    community:AddLine(L["Built with feedback, reports, and ideas from the community — especially "]
        .. bright .. THANKS .. "|r" .. L[". Thank you!"])
    card:Add(community, { fitHeight = true })
    for _, c in ipairs(CREDITS) do
        local credit = self:CreateTextBlock(content)
        credit:AddLine(L["Special thanks to "] .. bright .. c.name .. "|r" .. c.tail)
        card:Add(credit, { fitHeight = true })
    end
end

local function changelogCard(self, content, stack)
    local card = stack(self:CreateGroup(content, L["Changelog"]))
    local muted = colorCode(self, "muted")
    -- A raise here leaves the library's SelectTab with every tab hidden, so a version-less entry is skipped
    for _, entry in ipairs(ns.Changelog or {}) do
        if entry.version then
            local block = self:CreateTextBlock(content)
            block:AddLine(entry.version .. "   " .. muted .. (entry.date or "") .. "|r", "value")
            for _, sec in ipairs(entry.sections or {}) do
                block:AddLine(sec.head or "", "groupLabel", { gap = 10 })
                for _, item in ipairs(sec.items or {}) do
                    block:AddLine(item, "label", { bullet = "-" })
                end
            end
            card:Add(block, { fitHeight = true })
        end
    end
    card:Add(self:CreateButton(content, L["Older versions are on CurseForge"], nil,
        function() ns:ShowURL(CURSEFORGE_URL) end, nil, "ghost"))
end

Options:RegisterTab({
    id    = "about",
    title = L["About"],
    order = 60,
    build = function(self, content)
        local stack = Options.CardStack(self)
        introCard(self, content, stack)
        commandsCard(self, content, stack)
        tutorialsCard(self, content, stack)
        addonsCard(self, content, stack)
        thanksCard(self, content, stack)
        changelogCard(self, content, stack)
    end,
})
