local _, ns = ...
local L = ns.L

local math_max, math_min = math.max, math.min

local GOLD  = "|cffEBB706"
local MUTED = "|cffb3b3b3"
local WHITE = "|cffe6e6e6"
local CLOSE = "|r"

local CURSEFORGE_URL = "https://www.curseforge.com/wow/addons/everything-quests"
local GITHUB_URL     = "https://github.com/wheelbarrel00/EverythingQuests"
local BUG_URL        = "https://github.com/wheelbarrel00/EverythingQuests/issues"

-- sub names the subsystem that serves the command, so a flavor that does not load that
-- module lists no command it would silently ignore
local COMMANDS = {
    { cmd = "/eqs",          desc = L["Open or close the options window"] },
    { cmd = "/eqs chain",    desc = L["Open the Chain Guide"], sub = "ChainGuide" },
    { cmd = "/eqs history",  desc = L["Open the Quest History window"], sub = "HistoryFrame" },
    { cmd = "/eqs session",  desc = L["Recap your current play session in chat"], sub = "Session" },
    { cmd = "/eqs discover", desc = L["List the current zone's quest chains in chat"], sub = "ChainGuideQuestLineSource" },
    { cmd = "/eqs whatsnew", desc = L["Show the What's New popup again"], sub = "WhatsNew" },
    { cmd = "/eqs about",    desc = L["Open this About tab"] },
}

local OTHER_ADDONS = {
    { name = "Everything Delves",
      cf   = "https://www.curseforge.com/wow/addons/everything-delves",
      gh   = "https://github.com/wheelbarrel00/EverythingDelves" },
    { name = "Loot Pro",
      cf   = "https://www.curseforge.com/wow/addons/loot-pro",
      gh   = "https://github.com/wheelbarrel00/LootPro" },
}

local THANKS = "Spydawg2233, Zox, LightsBeacon, Fostot, DrahgunFyre, ChipW0lf, tanglies"

ns:GetSubsystem("Options"):AddTab("about", L["About"], function(content)
    local Options = ns:GetSubsystem("Options")

    local scroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = self:GetVerticalScrollRange() or 0
        local new = math_min(maxScroll, math_max(0, (self:GetVerticalScroll() or 0) - delta * 36))
        self:SetVerticalScroll(new)
    end)

    -- The live width is not resolved at build time, so width and wrap are constants sized to the 1020-wide window
    local SC_W, WRAP, LEFT = 940, 900, 4
    local sc = CreateFrame("Frame", nil, scroll)
    sc:SetSize(SC_W, 1)
    scroll:SetScrollChild(sc)

    local Y = -6

    local function header(text)
        local fs = Options:CreateSectionHeader(sc, text)
        fs:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
        local line = sc:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetColorTexture(0.30, 0.30, 0.30, 0.8)
        line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
        line:SetWidth(WRAP - LEFT)
        Y = Y - 28
    end

    local function body(text, indent, size)
        size = size or 12
        local fs = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT + (indent or 0), Y)
        fs:SetFont(fs:GetFont(), size)
        fs:SetWidth(WRAP - (indent or 0))
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetText(text)
        local h = fs:GetStringHeight() or size
        if h < size then h = size end
        Y = Y - h - 4
    end

    local function gap(px) Y = Y - (px or 8) end

    local function makeLink(label, onClick)
        local b = CreateFrame("Button", nil, sc)
        b:SetHeight(16)
        local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("LEFT", b, "LEFT", 0, 0)
        t:SetText(label)
        t:SetTextColor(0.92, 0.72, 0.02)
        b.text = t
        b:SetWidth((t:GetStringWidth() or 40) + 2)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(s) s.text:SetTextColor(1, 1, 1) end)
        b:SetScript("OnLeave", function(s) s.text:SetTextColor(0.92, 0.72, 0.02) end)
        return b
    end

    local function linkRow(links)
        local prev
        for i, lk in ipairs(links) do
            local b = makeLink(lk.label, lk.onClick)
            if i == 1 then
                b:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
            else
                local sep = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                sep:SetText(MUTED .. "  |  " .. CLOSE)
                sep:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                b:SetPoint("LEFT", sep, "RIGHT", 2, 0)
            end
            prev = b
        end
        Y = Y - 24
    end

    local ver = (C_AddOns and C_AddOns.GetAddOnMetadata
                 and C_AddOns.GetAddOnMetadata(ns.NAME, "Version"))
                 or ns.VERSION or "?"

    local title = sc:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
    title:SetFont(title:GetFont(), 22, "OUTLINE")
    title:SetText("Everything Quests")
    title:SetTextColor(0.635, 0.000, 0.039)   -- #a2000a brand red
    Y = Y - 28

    local sub = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sub:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
    sub:SetText(GOLD .. "v" .. ver .. CLOSE
        .. MUTED .. "    " .. L["by Wheelbarrel00"]
        .. "    -    " .. L["for WoW Midnight (12.0.x)"] .. CLOSE)
    Y = Y - 22

    body(WHITE .. L["A unified replacement for the Blizzard quest experience: a custom tracker, world-map overlays, quest history, and a Midnight chain guide."] .. CLOSE)
    gap(10)

    local links = {
        { label = L["Join our Discord"], onClick = function() ns:ShowDiscord() end },
        { label = L["CurseForge"],       onClick = function() ns:ShowURL(CURSEFORGE_URL) end },
        { label = L["GitHub"],           onClick = function() ns:ShowURL(GITHUB_URL) end },
        { label = L["Report a Bug"],     onClick = function() ns:ShowURL(BUG_URL) end },
    }
    if ns:GetSubsystem("WhatsNew") then
        links[#links + 1] = { label = L["What's New"], onClick = function()
            local WN = ns:GetSubsystem("WhatsNew"); if WN and WN.Show then WN:Show() end
        end }
    end
    linkRow(links)
    gap(8)

    header(L["Commands"])
    for _, c in ipairs(COMMANDS) do
        if not c.sub or ns:GetSubsystem(c.sub) then
            local cmd = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            cmd:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
            cmd:SetText(GOLD .. c.cmd .. CLOSE)
            local d = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            d:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT + 120, Y)
            d:SetText(WHITE .. c.desc .. CLOSE)
            Y = Y - 18
        end
    end
    gap(2)
    if ns:GetSubsystem("Minimap") then
        body(MUTED .. L["Tip: right-click the minimap button to open Options."] .. CLOSE, 0, 11)
    end
    gap(10)

    header(L["Tutorials"])
    body(MUTED .. L["Video tutorials are coming soon."] .. CLOSE)
    gap(10)

    header(L["More Add-ons by Wheelbarrel00"])
    for _, a in ipairs(OTHER_ADDONS) do
        local n = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        n:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
        n:SetText(WHITE .. a.name .. CLOSE)
        local cfLink = makeLink(L["CurseForge"], function() ns:ShowURL(a.cf) end)
        cfLink:SetPoint("LEFT", n, "LEFT", 180, 0)
        local sep = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sep:SetText(MUTED .. "  |  " .. CLOSE)
        sep:SetPoint("LEFT", cfLink, "RIGHT", 2, 0)
        local ghLink = makeLink(L["GitHub"], function() ns:ShowURL(a.gh) end)
        ghLink:SetPoint("LEFT", sep, "RIGHT", 2, 0)
        Y = Y - 20
    end
    gap(10)

    header(L["Thanks"])
    body(WHITE .. L["Built with feedback, reports, and ideas from the community — especially "]
        .. GOLD .. THANKS .. CLOSE .. WHITE .. L[". Thank you!"] .. CLOSE)
    body(WHITE .. L["Special thanks to "] .. GOLD .. "DrahgunFyre" .. CLOSE .. WHITE
        .. L[" for the many features, fixes, and reports that keep shaping Everything Quests."] .. CLOSE)
    body(WHITE .. L["Special thanks to "] .. GOLD .. "Zox" .. CLOSE .. WHITE
        .. L[" for the many hours spent translating Everything Quests into French."] .. CLOSE)
    body(WHITE .. L["Special thanks to "] .. GOLD .. "Malevi4" .. CLOSE .. WHITE
        .. L[" for the many hours spent translating Everything Quests into Russian."] .. CLOSE)
    body(WHITE .. L["Special thanks to "] .. GOLD .. "labrie75" .. CLOSE .. WHITE
        .. L[" for the many hours spent translating Everything Quests into Korean."] .. CLOSE)
    gap(10)

    header(L["Changelog"])
    for _, entry in ipairs(ns.Changelog or {}) do
        local vh = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        vh:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
        vh:SetFont(vh:GetFont(), 13, "OUTLINE")
        vh:SetText(GOLD .. "v" .. entry.version .. CLOSE
            .. MUTED .. "    " .. (entry.date or "") .. CLOSE)
        Y = Y - 18
        for _, sec in ipairs(entry.sections or {}) do
            local sh = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            sh:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT + 10, Y)
            sh:SetFont(sh:GetFont(), 11, "OUTLINE")
            sh:SetTextColor(0.635, 0.000, 0.039)   -- #a2000a brand red
            sh:SetText(sec.head)
            Y = Y - 16
            for _, item in ipairs(sec.items or {}) do
                body(WHITE .. "- " .. item .. CLOSE, 18, 11)
            end
            gap(2)
        end
        gap(8)
    end

    local older = makeLink(L["Older versions are on CurseForge"],
        function() ns:ShowURL(CURSEFORGE_URL) end)
    older:SetPoint("TOPLEFT", sc, "TOPLEFT", LEFT, Y)
    Y = Y - 28

    sc:SetHeight(math_max(1, -Y + 10))
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
end, true)
