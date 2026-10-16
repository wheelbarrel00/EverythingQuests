local _, ns = ...

local DBmod = ns:GetSubsystem("ChainGuideDatabase")

-- These task quests belong to no questline, so the order is the prerequisites in the client's task quest data (12.1.5)
DBmod:RegisterChain(9097945, {
    category      = ns.CAT.VOIDSTORM,
    nameFromQuest = 97945,
    items = {
        { type = "quest", id = 97945, x = 0, y = 0 },
        { type = "quest", id = 97978, x = 0, y = 1, connections = { 1 } },
        { type = "quest", id = 97981, x = 0, y = 2, connections = { 2 } },
        { type = "quest", id = 98379, x = 0, y = 3, connections = { 3 } },
        { type = "quest", id = 95373, x = 1, y = 3, connections = { 3 } },
        { type = "quest", id = 98390, x = 0, y = 4, connections = { 4 } },
    },
})
