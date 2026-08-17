-- luacheck configuration for Everything Quests (World of Warcraft addon).
-- WoW ships a Lua 5.1 client. Run from the repo root: `luacheck .`
-- Keep `read_globals` roughly in sync with .luarc.json's diagnostics.globals
-- (that list is for the Lua language server; this one is for luacheck).

std               = "lua51"
max_line_length   = false   -- changelog / locale strings are intentionally long
codes             = true
-- docs/ is gitignored local tooling and generated scratch, never shipped, and it is written
-- for standalone Lua rather than the WoW environment - linting it only moves the baseline.
exclude_files     = { "Libs/", "*TRANSLATE-ME*.lua", "Locales/*TRANSLATE-ME*.lua", "docs/" }

-- WoW callbacks are written as `function obj:Method()` / `function(self, ...)`;
-- an unused or shadowed implicit `self` is idiomatic here, not a smell. The
-- codebase also marks deliberately-unused locals/args with a leading underscore.
ignore = { "212/self", "431/self", "432/self", "21./^_", "231/^_", "241/^_" }

-- Globals the addon itself defines or writes.
globals = {
    "EverythingQuests",
    "EverythingQuestsDB", "EverythingQuestsCharDB", "EverythingQuestsChainCache",
    "EverythingQuestsHistory", "EverythingQuestsHistoryBackups",
    "SlashCmdList", "SLASH_EVERYTHINGQUESTS1", "SLASH_EVERYTHINGQUESTS2", "SLASH_EQSPROBE1",
    "EQQuestPinMixin", "EQWorldQuestPinMixin", "EQChainPinMixin",
    "BINDING_HEADER_EVERYTHINGQUESTS",
}

-- WoW client API (read-only). Mirror of .luarc.json plus a few the addon uses.
read_globals = {
    -- frames & fonts
    "CreateFrame", "UIParent", "WorldFrame", "GameTooltip", "GameTooltip_Hide",
    "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall", "GameFontHighlightSmall",
    "GameFontNormalLarge", "GameFontDisable", "GameFontDisableSmall", "GameFontWhiteSmall",
    "QuestFont", "QuestFont_Large", "QuestFont_Super_Huge", "ObjectiveTrackerHeaderFont",
    "STANDARD_TEXT_FONT",
    "WorldMapFrame", "QuestMapFrame", "QuestLogFrame", "FlightMapFrame", "Minimap",
    "QuestLogPopupDetailFrame", "ChatFrame1", "DEFAULT_CHAT_FRAME",
    "EditModeManagerFrame", "SettingsPanel",
    -- C_ namespaces
    "C_Timer", "C_QuestLog", "C_TaskQuest", "C_Map", "C_SuperTrack", "C_Texture",
    "C_Scenario", "C_ScenarioInfo", "C_TradeSkillUI", "C_AddOns", "C_ChatInfo",
    "C_Container", "C_Item", "C_Spell", "C_PerksActivities", "C_CurrencyInfo",
    "C_Reputation", "C_QuestInfoSystem", "C_QuestLine", "C_PvP", "C_LFGList", "C_CreatureInfo",
    "C_Garrison", "C_FactionInfo", "C_MajorFactions", "C_TaxiMap", "C_GossipInfo",
    "C_CampaignInfo", "C_AreaPoiInfo", "C_Minimap", "C_ChallengeMode",
    "C_VignetteInfo", "C_UnitAuras", "C_UIWidgetManager",
    -- functions
    "hooksecurefunc", "issecurevariable", "InCombatLockdown", "secureexecuterange",
    "IsModifiedClick", "IsAltKeyDown", "IsInGroup", "IsQuestCompletable",
    "QuestMapFrame_OpenToQuestDetails", "QuestUtil", "ProfessionsUtil", "QuestUtils_GetQuestName",
    "QuestUtils_IsQuestWorldQuest", "QuestMapQuestOptions_OpenQuestDetails",
    "QuestMapFrame_UpdateQuestDetailsButtons", "QuestMapFrame_GetDetailQuestID",
    "QuestLogPopupDetailFrame_Show", "QuestLogPopupDetailFrame_Update",
    "QuestLogPushQuest", "QuestPOIGetIconInfo",
    "GetNumAutoQuestPopUps", "GetAutoQuestPopUp", "RemoveAutoQuestPopUp",
    "ShowQuestComplete", "ShowQuestOffer", "SetNormalAtlas",
    "StaticPopup_Show", "StaticPopup_Hide", "StaticPopupDialogs",
    "ShowUIPanel", "HideUIPanel", "ReloadUI", "OpenQuestLog", "ToggleQuestLog",
    "OpenWorldMap", "SearchBoxTemplate_OnTextChanged", "ChatEdit_InsertLink",
    "GetTime", "time", "date", "GetCVar", "SetCVar", "GetLocale", "GetRealmName",
    "GetCursorPosition", "GetInstanceInfo", "GetQuestUiMapID", "GetQuestID",
    "UnitName", "UnitClass", "UnitRace", "UnitFactionGroup", "UnitLevel", "UnitGUID",
    "UnitOnTaxi", "GetZoneText", "GetSubZoneText", "GetMinimapZoneText", "GetMinimapShape",
    "GetMoney", "GetCoinTextureString", "BreakUpLargeNumbers",
    "GetItemInfo", "GetItemIcon", "GetItemQualityColor",
    "GetQuestLogRewardMoney", "GetQuestLogRewardInfo", "GetNumQuestLogRewards",
    "GetQuestLogRewardXP",
    "HaveQuestData", "HaveQuestRewardData", "GetQuestLogQuestText",
    "AcceptQuest", "DeclineQuest", "CompleteQuest", "GetNumQuestChoices", "GetQuestReward",
    "GetNumActiveQuests", "GetNumAvailableQuests", "GetActiveTitle", "GetAvailableTitle",
    "SelectActiveQuest", "SelectAvailableQuest",
    "GetQuestDifficultyColor", "GetQuestTagInfo",
    "OpenAchievementFrameToAchievement", "RemoveTrackedAchievement", "GetTrackedAchievements",
    "LFGListUtil_FindQuestGroup", "PlaySound", "PlaySoundFile",
    -- mixins / helpers
    "Mixin", "CreateFromMixins", "CallbackRegistryMixin", "CallbackRegistryBaseMixin",
    "MapCanvasMixin", "MapCanvasPinMixin", "MapCanvasDataProviderMixin",
    "WorldMap_WorldQuestDataProviderMixin", "PlayerLocation", "UiMapPoint",
    "CreateVector2D", "CreateColor", "PIN_FRAME_LEVEL_AREA_POI", "PIN_FRAME_LEVEL_QUEST_PING",
    "LibStub", "Settings", "MenuUtil", "Menu", "TomTom",
    -- constants / enums / colors
    "Enum", "SOUNDKIT", "FACTION_BAR_COLORS",
    "LE_QUEST_FREQUENCY_DAILY", "LE_QUEST_FREQUENCY_WEEKLY",
    "ERR_QUEST_COMPLETE_S", "SEARCH", "OKAY",
    "PROFESSIONS_TRACKER_REAGENT_FORMAT", "PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT",
    "PROFESSIONS_TRACKER_REAGENT_RANGE_FORMAT", "PROFESSIONS_CRAFTING_FORM_RECRAFTING_HEADER",
    -- WoW global string / table extensions and misc
    "wipe", "tinsert", "tremove", "tContains", "tIndexOf", "CopyTable", "ipairs_reverse",
    "strsplit", "strjoin", "strtrim", "strrep", "gsub", "format", "tostringall", "bit",
    "debugstack", "geterrorhandler", "securecall", "GetBuildInfo",
    -- additional API surfaced by luacheck across the full codebase
    "debugprofilestop", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage",
    "GetServerTime", "IsInInstance", "IsShiftKeyDown", "IsMouseButtonDown", "SetCursor",
    "UnitIsPlayer", "UnitCanAttack", "UnitExists", "C_NamePlate", "C_TooltipInfo", "C_ContentTracking",
    "GetInventorySlotInfo", "GetInventoryItemLink", "GetItemInfoInstant",
    "GetQuestLogItemLink", "GetQuestLogChoiceInfo", "GetNumQuestLogChoices",
    "GetQuestLogSpecialItemInfo", "GetQuestLogSpecialItemCooldown", "IsQuestLogSpecialItemInRange",
    "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo",
}
