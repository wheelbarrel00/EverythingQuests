local _, ns = ...

local DBmod = ns:GetSubsystem("ChainGuideDatabase")

ns.EXP_MIDNIGHT = 11

DBmod:RegisterExpansion(ns.EXP_MIDNIGHT, {
    name = "Midnight",
    icon = nil,
    minLevel = 80,
    maxLevel = 90,
})

ns.CAT = {
    CAMPAIGN          = 1100,
    EVERSONG_WOODS    = 1101,
    ZULAMAN           = 1102,
    HARANDAR          = 1103,
    VOIDSTORM         = 1104,
    ARATOR            = 1105,
    WAR_LIGHT_SHADOW  = 1106,
    CURSE_OF_ULATEK   = 1107,
    VOID_ACROPOLIS    = 1108,
    SUNSTRIDER_OMNIUM = 1109,
    COILED_ISLE       = 1110,
}

DBmod:RegisterCategory(ns.CAT.CAMPAIGN,         { expansion = ns.EXP_MIDNIGHT, name = "Midnight Campaign", mapIDs = {}, campaignID = 270, order = 10 })
DBmod:RegisterCategory(ns.CAT.WAR_LIGHT_SHADOW, { expansion = ns.EXP_MIDNIGHT, name = "The War of Light and Shadow", mapIDs = {}, campaignID = 284, order = 20 })
DBmod:RegisterCategory(ns.CAT.CURSE_OF_ULATEK,  { expansion = ns.EXP_MIDNIGHT, name = "The Curse of Ula'tek", mapIDs = { 2424 }, campaignID = 324, order = 25 })
DBmod:RegisterCategory(ns.CAT.EVERSONG_WOODS,   { expansion = ns.EXP_MIDNIGHT, name = "Eversong Woods", mapIDs = { 2393 }, order = 30 })
DBmod:RegisterCategory(ns.CAT.ZULAMAN,          { expansion = ns.EXP_MIDNIGHT, name = "Zul'Aman",       mapIDs = { 2437 }, order = 40 })
DBmod:RegisterCategory(ns.CAT.HARANDAR,         { expansion = ns.EXP_MIDNIGHT, name = "Harandar",       mapIDs = { 2413 }, order = 50 })
DBmod:RegisterCategory(ns.CAT.ARATOR,           { expansion = ns.EXP_MIDNIGHT, name = "Arator",         mapIDs = {}, order = 60 })
DBmod:RegisterCategory(ns.CAT.VOIDSTORM,        { expansion = ns.EXP_MIDNIGHT, name = "Voidstorm",      mapIDs = { 2405 }, order = 70 })
DBmod:RegisterCategory(ns.CAT.SUNSTRIDER_OMNIUM, { expansion = ns.EXP_MIDNIGHT, name = "The Sunstrider Omnium", mapIDs = {}, order = 85 })
DBmod:RegisterCategory(ns.CAT.VOID_ACROPOLIS,   { expansion = ns.EXP_MIDNIGHT, name = "Void Acropolis", mapIDs = { 2599 }, order = 90 })
DBmod:RegisterCategory(ns.CAT.COILED_ISLE,      { expansion = ns.EXP_MIDNIGHT, name = "The Coiled Isle", mapIDs = { 2512 }, order = 95 })
