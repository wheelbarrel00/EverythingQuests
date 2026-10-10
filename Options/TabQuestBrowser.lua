local _, ns = ...
local L = ns.L

local Options = ns:GetSubsystem("Options")

Options:RegisterTab({
    id    = "questBrowser",
    title = L["Quest Browser"],
    order = 45,
    build = function(self, content)
        local card = Options.CardStack(self)(self:CreateGroup(content, L["Quest Browser"]))
        local open = self:CreateButton(content, L["Open Quest Browser"], nil, function()
            local QB = Options:QuestBrowser()
            if QB then QB:Open() end
        end)
        self:AttachTooltip(open, L["Quest Browser"],
            L["Look up almost any quest in the game, including ones you have never picked up. Shows the level and race and class requirements, where it starts and turns in, what has to be finished first, and why you cannot take it yet. Also on /eqs quests, or right-click a gold quest marker on the map."])
        card:Add(open)
    end,
})
