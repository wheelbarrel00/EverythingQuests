local addonName, ns = ...

_G.EverythingQuests = ns
ns.NAME = addonName
ns.VERSION = "1.44.0"

ns.DISCORD_URL = "https://discord.gg/vm8K2WfQUE"

function ns:ShowDiscord()
    local D = self:GetSubsystem("Dialog")
    if not D then return end
    local L = ns.L
    D:Show({
        title       = L["Everything Quests Discord"],
        text        = L["Join the community for help, feedback, and updates.\nCopy the invite below (it's pre-selected — just press Ctrl+C):"],
        button1     = L["Close"],
        hasEditBox  = true,
        editBoxText = self.DISCORD_URL,
        highlightEditBox = true,
    })
end

function ns:ShowURL(url)
    local D = self:GetSubsystem("Dialog")
    if not (D and url) then return end
    local L = ns.L
    D:Show({
        title       = "Everything Quests",
        text        = L["Copy the link below (it's pre-selected — just press Ctrl+C):"],
        button1     = L["Close"],
        hasEditBox  = true,
        editBoxText = url,
        highlightEditBox = true,
    })
end

ns.subsystems = {}
ns.subsystemOrder = {}

function ns:RegisterSubsystem(name, tbl)
    if self.subsystems[name] then
        error(("EQ: subsystem %q already registered"):format(name))
    end
    self.subsystems[name] = tbl
    self.subsystemOrder[#self.subsystemOrder + 1] = name
    return tbl
end

function ns:GetSubsystem(name)
    return self.subsystems[name]
end

_G.BINDING_HEADER_EVERYTHINGQUESTS              = "Everything Quests"
_G.BINDING_NAME_EVERYTHINGQUESTS_TOGGLE_OPTIONS = "Toggle Options"
_G.BINDING_NAME_EVERYTHINGQUESTS_TOGGLE_CHAINGUIDE = "Toggle Chain Guide"

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    for _, name in ipairs(ns.subsystemOrder) do
        local sub = ns.subsystems[name]
        if sub.OnInitialize then xpcall(sub.OnInitialize, geterrorhandler(), sub) end
    end
    for _, name in ipairs(ns.subsystemOrder) do
        local sub = ns.subsystems[name]
        if sub.OnEnable then xpcall(sub.OnEnable, geterrorhandler(), sub) end
    end
end)
