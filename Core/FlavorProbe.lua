local _, ns = ...

-- Temporary cross-flavor measurement command for the Classic port. Every probed global is
-- reached through _G with a variable name, so probing a new one needs no .luacheckrc entry.
-- Nothing here may become a runtime branch: the build number is reported, never tested.

local Probe = {}
ns.FlavorProbe = Probe

local PREFIX = "|cffEBB706EQ Probe|r "

local function out(fmt, ...)
    if select("#", ...) > 0 then
        print(PREFIX .. fmt:format(...))
    else
        print(PREFIX .. fmt)
    end
end

local function line(fmt, ...)
    if select("#", ...) > 0 then
        print("  " .. fmt:format(...))
    else
        print("  " .. fmt)
    end
end

local function resolve(path)
    local obj = _G
    for part in path:gmatch("[^.]+") do
        if type(obj) ~= "table" then return nil end
        obj = obj[part]
    end
    return obj
end

-- Counted with select('#') rather than '#' on the table: a probed function returning nil in
-- any slot leaves a hole, and '#' finds a border rather than the count, so a tuple would
-- print short and read as a genuinely shorter return.
local function countAndPack(...)
    return select("#", ...), { ... }
end

local function val(v)
    if type(v) == "string" and #v > 40 then return ("%q..(%d)"):format(v:sub(1, 40), #v) end
    return ("%s(%s)"):format(tostring(v), type(v))
end

local function emit(list, per)
    local buf = {}
    for i = 1, #list do
        buf[#buf + 1] = list[i]
        if #buf == per or i == #list then
            line(table.concat(buf, "   "))
            for k = #buf, 1, -1 do buf[k] = nil end
        end
    end
end

-- Existence alone answers "yes" for a stub the client kept with no system behind it, which
-- is how a capability probe gets mistaken for a content probe. Anything load bearing is
-- CALLED here and its real returns are printed.
local function callDump(label, path, ...)
    local fn = resolve(path)
    if type(fn) ~= "function" then
        line("%s: ABSENT", label)
        return nil
    end
    local n, packed = countAndPack(pcall(fn, ...))
    if not packed[1] then
        line("%s: RAISED - %s", label, tostring(packed[2]))
        return nil
    end
    local parts = {}
    for i = 2, n do parts[#parts + 1] = ("[%d]=%s"):format(i - 1, val(packed[i])) end
    line("%s: %s", label, #parts > 0 and table.concat(parts, " ") or "no return values")
    return packed[2]
end

local function present(paths)
    local missing, have = {}, {}
    for _, p in ipairs(paths) do
        local t = (type(resolve(p)) == "function") and have or missing
        t[#t + 1] = p
    end
    line("MISSING (%d):", #missing)
    emit(missing, 2)
    line("present (%d):", #have)
    emit(have, 2)
end

-- ⛔ present() answers "is this a FUNCTION", so anything table valued routed through it reads
-- MISSING on every flavor. The first `pins` run did exactly that to five mixins and reported
-- them absent on RETAIL, where MapPOI provably works - the retail control is the only reason
-- that was caught. Report the TYPE for anything that is not expected to be a function.
local function kinds(paths)
    local parts = {}
    for _, p in ipairs(paths) do
        parts[#parts + 1] = ("%s=%s"):format(p, type(resolve(p)))
    end
    emit(parts, 2)
end

-- Bounded by a ceiling and terminated on the first nil title, never by GetNumQuestLogEntries.
-- That counts only VISIBLE rows on Classic, so a collapsed header hides quests that stay
-- perfectly addressable by index.
local MAX_LOG_SCAN = 75

local function collectQuests(limit)
    local ids, titles = {}, {}

    local flatTitle = resolve("GetQuestLogTitle")
    if type(flatTitle) == "function" then
        for i = 1, MAX_LOG_SCAN do
            local ok, t1, _, _, isHeader, _, _, _, questID = pcall(flatTitle, i)
            if not ok or t1 == nil then break end
            if not isHeader and questID and questID ~= 0 then
                ids[#ids + 1] = questID
                titles[#titles + 1] = t1
                if #ids >= limit then break end
            end
        end
        if #ids > 0 then return ids, titles, "GetQuestLogTitle" end
    end

    local getInfo = resolve("C_QuestLog.GetInfo")
    if type(getInfo) == "function" then
        local numEntries = resolve("C_QuestLog.GetNumQuestLogEntries")
        local reported = 0
        if type(numEntries) == "function" then
            local ok, n = pcall(numEntries)
            if ok and type(n) == "number" then reported = n end
        end
        -- The count is a floor, never the bound - see the note above. This branch used to
        -- loop to it, which is the very thing that makes a probe under-report on Classic.
        for i = 1, reported + MAX_LOG_SCAN do
            local ok2, info = pcall(getInfo, i)
            if not (ok2 and type(info) == "table") then
                if i > reported then break end
            elseif not info.isHeader and info.questID and info.questID ~= 0 then
                ids[#ids + 1] = info.questID
                titles[#titles + 1] = info.title
                if #ids >= limit then break end
            end
        end
        return ids, titles, "C_QuestLog.GetInfo"
    end

    return ids, titles, "none"
end

-- The headline question of the whole port. Modules/MapPOI, the Chain Guide waypoint and Get
-- Directions all resolve a quest to coordinates, and every one of them starts here.
function Probe:Map()
    out("map and coordinates")

    local mapID = callDump("C_Map.GetBestMapForUnit('player')", "C_Map.GetBestMapForUnit", "player")
    callDump("C_Map.GetMapInfo(map)", "C_Map.GetMapInfo", mapID)
    callDump("C_Map.GetPlayerMapPosition(map,'player')", "C_Map.GetPlayerMapPosition", mapID, "player")
    callDump("GetZoneText()", "GetZoneText")

    local onMap = callDump("C_QuestLog.GetQuestsOnMap(map)", "C_QuestLog.GetQuestsOnMap", mapID)
    if type(onMap) == "table" then
        line("  GetQuestsOnMap returned %d row(s)", #onMap)
        for i = 1, math.min(#onMap, 5) do
            local e = onMap[i]
            if type(e) == "table" then
                line("  [%d] questID=%s x=%s y=%s", i, tostring(e.questID), tostring(e.x), tostring(e.y))
            else
                line("  [%d] %s", i, val(e))
            end
        end
    end

    local ids, titles, source = collectQuests(5)
    line("quest log source: %s, sampled %d quest(s)", source, #ids)
    for i = 1, #ids do
        line("  id=%s  %s", tostring(ids[i]), tostring(titles[i]):sub(1, 30))
        callDump(("  GetNextWaypointForMap(%s,%s)"):format(tostring(ids[i]), tostring(mapID)),
                 "C_QuestLog.GetNextWaypointForMap", ids[i], mapID)
        callDump(("  GetNextWaypoint(%s)"):format(tostring(ids[i])),
                 "C_QuestLog.GetNextWaypoint", ids[i])
        callDump(("  GetNextWaypointText(%s)"):format(tostring(ids[i])),
                 "C_QuestLog.GetNextWaypointText", ids[i])
    end

    line("coordinate api surface:")
    present({
        "C_QuestLog.GetQuestsOnMap", "C_QuestLog.GetNextWaypointForMap",
        "C_QuestLog.GetNextWaypoint", "C_QuestLog.GetNextWaypointText",
        "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition", "C_Map.GetMapInfo",
        "C_Map.GetMapChildrenInfo", "C_Map.GetWorldPosFromMapPos",
        "C_SuperTrack.SetSuperTrackedQuestID", "C_SuperTrack.GetSuperTrackedQuestID",
        "C_QuestLog.GetDistanceSqToQuest", "QuestPOIGetIconInfo", "GetQuestPOIs",
    })
end

-- Classic kept a POI api of its own and C_QuestLog.GetQuestsOnMap is a stub that answers an
-- empty table forever, so the names are discovered from _G rather than assumed. Whether any
-- of them yields per-quest coordinates decides whether map pins need a quest database.
local function scanGlobals(pattern)
    local hits = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:find(pattern) then
            hits[#hits + 1] = ("%s=%s"):format(k, type(v))
        end
    end
    table.sort(hits)
    return hits
end

function Probe:POI()
    out("quest poi and waypoint surface")

    local mapID
    local bestMap = resolve("C_Map.GetBestMapForUnit")
    if type(bestMap) == "function" then
        local ok, v = pcall(bestMap, "player")
        mapID = ok and v or nil
    end
    line("map %s  zone %s", tostring(mapID), tostring(GetZoneText and GetZoneText()))

    for _, pat in ipairs({ "POI", "Waypoint", "WayPoint" }) do
        local hits = scanGlobals(pat)
        line("_G names containing %q (%d):", pat, #hits)
        emit(hits, 2)
    end

    local ids, titles = collectQuests(5)
    line("per quest, the Classic poi calls:")
    for i = 1, #ids do
        line("  id=%s  %s", tostring(ids[i]), tostring(titles[i]):sub(1, 30))
        callDump("    QuestPOIGetIconInfo", "QuestPOIGetIconInfo", ids[i])
        callDump("    GetQuestPOILeaderBoard", "GetQuestPOILeaderBoard", ids[i])
    end

    line("map wide poi calls:")
    callDump("  GetNumQuestPOIs()", "GetNumQuestPOIs")
    callDump("  GetQuestPOIs()", "GetQuestPOIs")
    callDump("  QuestPOIUpdateIcons()", "QuestPOIUpdateIcons")
    callDump("  SetMapForQuestPOIs(map)", "SetMapForQuestPOIs", mapID)
    callDump("  C_QuestLog.SetMapForQuestPOIs(map)", "C_QuestLog.SetMapForQuestPOIs", mapID)

    -- Re-read after the update calls. An empty first reading only proves the data was not
    -- there YET if something has to prime it.
    local again = callDump("  GetQuestsOnMap(map) AFTER the above",
                           "C_QuestLog.GetQuestsOnMap", mapID)
    if type(again) == "table" then
        line("    rows now: %d", #again)
        for i = 1, math.min(#again, 5) do
            local e = again[i]
            if type(e) == "table" then
                line("    [%d] questID=%s x=%s y=%s", i, tostring(e.questID),
                     tostring(e.x), tostring(e.y))
            end
        end
    end

    line("waypoint sinks:")
    present({
        "SetUserWaypoint", "C_Map.SetUserWaypoint", "C_Map.GetUserWaypoint",
        "C_Map.CanSetUserWaypointOnMap", "TomTom.AddWaypoint",
    })
end

function Probe:Quest()
    out("quest api by EQ module")

    local ids = collectQuests(2)
    local sample = ids[1]
    line("sample questID: %s", tostring(sample))

    line("History - Modules/History/Recorder.lua:")
    callDump("  GetTitleForQuestID(sample)", "C_QuestLog.GetTitleForQuestID", sample)
    callDump("  IsQuestFlaggedCompleted(sample)", "C_QuestLog.IsQuestFlaggedCompleted", sample)
    -- QuestUtils_GetQuestName carries the whole title ladder once GetTitleForQuestID is gone,
    -- and the curated table it falls back to is Midnight data no Classic TOC lists.
    callDump("  QuestUtils_GetQuestName(sample)", "QuestUtils_GetQuestName", sample)
    present({
        "C_QuestLog.GetQuestsCompleted", "GetQuestsCompleted",
        "C_QuestLog.GetAllCompletedQuestIDs", "C_QuestLog.RequestLoadQuestByID",
        "GetQuestLogRewardMoney", "GetQuestLogRewardXP", "GetNumQuestLogRewards",
        "C_QuestInfoSystem.GetQuestClassification", "C_QuestLog.GetQuestTagInfo",
        "QuestUtils_GetQuestName", "C_Timer.NewTimer", "GetMoney", "GetServerTime",
    })

    line("Nameplates - Modules/Nameplates/QuestIcons.lua:")
    callDump("  GetQuestObjectives(sample)", "C_QuestLog.GetQuestObjectives", sample)
    present({
        "C_QuestLog.GetQuestObjectives", "GetQuestLogLeaderBoard",
        "GetNumQuestLeaderBoards", "C_NamePlate.GetNamePlateForUnit",
        "C_NamePlate.GetNamePlates", "C_TooltipInfo.GetUnit", "issecretvalue",
    })

    -- The bare globals matter as much as the C_GossipInfo ones. QuestAuto.lua:49 guards on
    -- GetNumActiveQuests and then calls GetActiveTitle and SelectActiveQuest, its siblings.
    line("QuestAuto - Modules/QuestAuto.lua:")
    present({
        "C_GossipInfo.GetActiveQuests", "C_GossipInfo.GetAvailableQuests",
        "C_GossipInfo.SelectAvailableQuest", "C_GossipInfo.SelectActiveQuest",
        "AcceptQuest", "CompleteQuest", "GetQuestReward", "GetNumQuestChoices",
        "GetNumAvailableQuests", "SelectAvailableQuest", "GetActiveTitle",
        "GetNumActiveQuests", "SelectActiveQuest", "IsQuestCompletable", "DeclineQuest",
        "IsAltKeyDown", "hooksecurefunc", "SetItemRef",
    })

    line("ChainGuide and WorldQuests - expected absent on Classic:")
    present({
        "C_QuestLine.GetAvailableQuestLines", "C_QuestLine.GetQuestLineQuests",
        "C_QuestLine.GetQuestLineInfo", "C_CampaignInfo.GetCampaignID",
        "C_CampaignInfo.GetCampaignInfo", "C_CampaignInfo.GetCampaignChapterInfo",
        "C_TaskQuest.GetQuestsOnMap", "C_TaskQuest.GetQuestInfoByQuestID",
        "C_TaskQuest.GetQuestTimeLeftMinutes", "C_QuestLog.IsWorldQuest",
        "QuestUtils_IsQuestWorldQuest",
    })
end

-- Fields are printed by NAME because a return count cannot answer "is this row usable".
-- Anything the client hands back that is not in the expected set is printed too, since a
-- renamed field looks identical to an absent one from the caller's side.
local function dumpFields(label, t, order)
    if type(t) ~= "table" then
        line("%s: %s", label, val(t))
        return
    end
    local parts, seen = {}, {}
    for _, k in ipairs(order) do
        if t[k] ~= nil then
            parts[#parts + 1] = ("%s=%s"):format(k, val(t[k]))
            seen[k] = true
        end
    end
    local extra = {}
    for k, v in pairs(t) do
        if not seen[k] then extra[#extra + 1] = ("%s=%s"):format(tostring(k), val(v)) end
    end
    table.sort(extra)
    line("%s: %d of %d expected field(s) present", label, #parts, #order)
    emit(parts, 2)
    if #extra > 0 then
        line("  NOT in the expected set (%d):", #extra)
        emit(extra, 2)
    end
end

local GETINFO_FIELDS = {
    "questID", "title", "isHeader", "isHidden", "isCollapsed", "level", "frequency",
    "isOnMap", "isAutoComplete", "isTask", "isBounty", "isStory", "campaignID",
    "difficultyLevel", "startEvent", "isComplete", "suggestedGroup", "questLogIndex",
}

local OBJECTIVE_FIELDS = {
    "text", "type", "finished", "numFulfilled", "numRequired",
}

-- The questions that gate the port. Every one of these is a CALL, because each has already
-- been shown to be unanswerable by asking whether a name exists.
function Probe:Port()
    out("port blockers - called, not merely looked up")

    line("1. C_QuestLog.GetInfo - the sole quest row source for Cache and Nameplates:")
    local getInfo = resolve("C_QuestLog.GetInfo")
    if type(getInfo) ~= "function" then
        line("  ABSENT - Compat.CollectQuestLog falls back to the flat globals in 1b.")
    else
        local found = false
        for i = 1, MAX_LOG_SCAN do
            local ok, info = pcall(getInfo, i)
            if ok and type(info) == "table" and not info.isHeader and info.questID then
                dumpFields(("  GetInfo(%d)"):format(i), info, GETINFO_FIELDS)
                found = true
                break
            end
            if ok and info == nil and i > 1 then break end
        end
        if not found then line("  called cleanly but no non-header row was found") end
    end

    -- Era has neither C_QuestLog.GetInfo nor C_QuestLog.GetNumQuestLogEntries, so these
    -- pre-namespace globals are the only row source there. Positions are printed rather
    -- than named because Compat's flat row reads them BY POSITION.
    line("1b. the flat quest log globals - the only row source where GetInfo is absent:")
    callDump("  GetNumQuestLogEntries()", "GetNumQuestLogEntries")
    local flatTitle = resolve("GetQuestLogTitle")
    if type(flatTitle) ~= "function" then
        line("  GetQuestLogTitle: ABSENT")
    else
        local shown = 0
        for i = 1, MAX_LOG_SCAN do
            local cnt, packed = countAndPack(pcall(flatTitle, i))
            if not packed[1] or packed[2] == nil then break end
            local parts = {}
            for k = 2, cnt do parts[#parts + 1] = ("[%d]=%s"):format(k - 1, val(packed[k])) end
            line("  GetQuestLogTitle(%d) -> %d value(s)", i, cnt - 1)
            emit(parts, 2)
            shown = shown + 1
            if shown >= 3 then break end
        end
        if shown == 0 then line("  called cleanly but index 1 returned nothing") end

        -- ⛔ Position 6 is isComplete in the 17-value layout, and it reads nil on every
        -- INCOMPLETE quest - so a sample of three incomplete rows can never confirm it. Walk
        -- the whole log and print position 6 beside the title, which makes a completed quest
        -- prove the position instead of a signature lookup doing it.
        line("  1c. position 6 (isComplete?) across the whole log:")
        local anyComplete = false
        for i = 1, MAX_LOG_SCAN do
            local cnt, packed = countAndPack(pcall(flatTitle, i))
            if not packed[1] or packed[2] == nil then break end
            local title, isHeader, p6 = packed[2], packed[5], packed[7]
            if not isHeader then
                if p6 ~= nil then anyComplete = true end
                line("    %-28s [6]=%s  [8]=%s", tostring(title):sub(1, 28),
                     val(p6), tostring(packed[9]))
            end
            if cnt < 9 then break end
        end
        if not anyComplete then
            line("    ⛔ nothing in the log has a non-nil [6]. Take a quest to READY TO TURN IN")
            line("    and re-run - only that can confirm which position carries isComplete.")
        end
    end

    line("2. 3-arg xpcall - Core/Init.lua drives every OnInitialize through it:")
    local received
    local okx = xpcall(function(a) received = a end, function() end, "SENTINEL")
    line("  ok=%s  callee received %s", tostring(okx), val(received))
    if received ~= "SENTINEL" then
        line("  WARNING: the third argument did not arrive. Every subsystem would")
        line("  initialize with no self and EQ would load inert.")
    end

    line("3. GetQuestsCompleted - the SHAPE decides whether a backfill walk finds anything:")
    local completed = resolve("GetQuestsCompleted")
    if type(completed) ~= "function" then
        line("  ABSENT")
    else
        local ok, t = pcall(completed)
        if not ok or type(t) ~= "table" then
            line("  returned %s", val(t))
        else
            local pairsN, firstK, firstV = 0, nil, nil
            for k, v in pairs(t) do
                pairsN = pairsN + 1
                if firstK == nil then firstK, firstV = k, v end
            end
            line("  #t=%d  pairs=%d  first key=%s value=%s", #t, pairsN, val(firstK), val(firstV))
            if #t == 0 and pairsN > 0 then
                line("  SET shape - keyed questID to true. An index walk finds nothing here.")
            elseif #t > 0 then
                line("  ARRAY shape - an index walk is correct.")
            end
        end
    end
    callDump("  C_QuestLog.GetAllCompletedQuestIDs()", "C_QuestLog.GetAllCompletedQuestIDs")

    line("4. GetQuestObjectives row fields - numRequired/numFulfilled drive Nameplates:")
    local ids = collectQuests(1)
    local sample = ids[1]
    local getObj = resolve("C_QuestLog.GetQuestObjectives")
    if type(getObj) == "function" and sample then
        local ok, objs = pcall(getObj, sample)
        if ok and type(objs) == "table" and objs[1] then
            dumpFields(("  objective[1] of %s"):format(tostring(sample)), objs[1], OBJECTIVE_FIELDS)
            line("  objective count: %d", #objs)
        else
            line("  returned %s for quest %s", val(objs), tostring(sample))
        end
    else
        line("  no sample quest, or the function is absent")
    end

    line("5. ns.Has and ns.Compat, resolved on this client:")
    if ns.Has then
        line("  Has.QuestDataRequest=%s  Has.TooltipDataUnit=%s",
             tostring(ns.Has.QuestDataRequest), tostring(ns.Has.TooltipDataUnit))
    else
        line("  ns.Has is absent - Core/Compat.lua did not load")
    end
    if ns.Compat and ns.Compat.CollectQuestLog then
        local rows, last = ns.Compat.CollectQuestLog({})
        local filled = 0
        for i = 1, last do if rows[i] then filled = filled + 1 end end
        -- Whichever count source this client has. Era keeps only the bare global.
        local counter = resolve("C_QuestLog.GetNumQuestLogEntries") or resolve("GetNumQuestLogEntries")
        local okn, n = pcall(counter)
        line("  CollectQuestLog: highest index=%d  rows filled=%d  reported count=%s",
             last, filled, okn and tostring(n) or "no count source")
        if okn and type(n) == "number" and last > n then
            line("  the walk found %d row(s) PAST the reported count - the floor rule is earning its keep",
                 last - n)
        end
    end

    line("6. names reached from files that load on every flavor:")
    present({
        "MenuUtil.CreateContextMenu", "C_Timer.After", "C_Timer.NewTimer",
        "GameTooltip_Hide", "QuestUtils_GetQuestName", "hooksecurefunc", "SetItemRef",
        "BreakUpLargeNumbers", "GetServerTime", "UnitLevel", "GetMoney",
    })

    local host = CreateFrame("Frame")
    host:Hide()
    local slider = nil
    local okSlider = pcall(function()
        slider = CreateFrame("Slider", nil, host, "OptionsSliderTemplate")
    end)
    line("  Slider:SetObeyStepOnDrag = %s",
         (okSlider and slider and type(slider.SetObeyStepOnDrag)) or "no slider")

    -- History re-fonts about 45 strings with this and renders blank rather than ugly if it fails
    local madeFS, fs = pcall(host.CreateFontString, host, nil, "OVERLAY", "GameFontNormal")
    if madeFS and fs then
        local okFont, applied = pcall(fs.SetFont, fs, "Fonts\\ARIALN.TTF", 12, "")
        line("  SetFont Fonts\\ARIALN.TTF: pcall=%s returned=%s", tostring(okFont), val(applied))
    else
        line("  SetFont Fonts\\ARIALN.TTF: could not create a FontString to test with")
    end
    host:SetParent(nil)
end

-- Modules/MapPOI draws no pins of its own. It rides Blizzard's map canvas through
-- LibMapPinHandler, which COPIES these names off MapCanvasMixin at load. A copy of a nil
-- stores nil and fails later at the call site, far from the cause, so the list is read out
-- here instead. ⚠ It is duplicated from LibMapPinHandler.lua's `borrow` table - if that one
-- grows, this one is silently short.
local CANVAS_BORROWED = {
    "OnShow", "OnHide", "RefreshAllDataProviders",
    "CallMethodOnPinsAndDataProviders", "ReapplyPinFrameLevels", "SetGlobalPinScale",
    "AddDataProvider", "SetPinTemplateType",
    "EnumeratePinsByTemplate", "RemoveAllPinsByTemplate", "EnumerateAllPins",
    "AcquirePin", "RemovePin", "SetPinPosition",
    "GetCanvasScale", "GetCanvasZoomPercent", "ApplyPinPosition",
    "GetGlobalPinScale", "ExecuteOnAllPins", "CallMethodOnDataProviders",
    "GetPinTemplateType", "RegisterPin", "UnregisterPin",
}

-- hooksecurefunc RAISES on a method the frame does not have, so one absent name here costs
-- GetShadowCanvas the whole call rather than one hook.
local CANVAS_HOOKED = {
    "OnShow", "OnHide", "RefreshAllDataProviders", "CallMethodOnPinsAndDataProviders",
    "ReapplyPinFrameLevels", "SetGlobalPinScale", "OnMapChanged",
}

-- ⚠ RegisterForClicks is deliberately NOT here. Pin.lua calls it, but it is a Button WIDGET
-- method that the pin gets from SetPinTemplateType(.., "BUTTON") - it was never on this mixin,
-- and listing it reported MISSING on retail too.
-- ApplyCurrentPosition is what re-anchors a pin after the canvas resizes, so it is as load
-- bearing as the placement call itself.
local PIN_METHODS = {
    "UseFrameLevelType", "SetScalingLimits", "SetPosition", "ApplyCurrentPosition",
    "OnAcquired", "OnReleased",
}

-- Every row of the Classic coordinate table falls in one contiguous UiMapID block, measured
-- across both generated tables: 46 distinct ids, none outside this range. Whether THIS client
-- resolves them is the question that decides whether the dataset is usable at all - a table
-- of ids the client does not know places every pin nowhere.
local COORD_MAP_MIN, COORD_MAP_MAX = 1411, 1459

local function decodePacked(v)
    return math.floor(v / 1e8), math.floor(v % 1e8 / 1e4) / 1e4, (v % 1e4) / 1e4
end

-- Modules/MapPOI is the last module with no Classic path at all, and the reason is a data
-- source rather than a capability. This section asks the OTHER half: assuming the data, does
-- the canvas EQ hangs its pins on exist on this flavor.
function Probe:Pins()
    out("map canvas and pin surface - what Modules/MapPOI rides on")

    local canvas = _G["WorldMapFrame"]
    line("WorldMapFrame: %s  shown=%s", type(canvas),
         type(canvas) == "table" and tostring(canvas.IsShown and canvas:IsShown()) or "n/a")
    if type(canvas) == "table" then
        callDump("  WorldMapFrame:GetMapID()", "WorldMapFrame.GetMapID", canvas)
    end

    line("mixins MapPOI and the pin library are built from (TABLES, so type is reported):")
    kinds({
        "MapCanvasMixin", "MapCanvasPinMixin", "MapCanvasDataProviderMixin",
        "CallbackRegistryMixin", "CallbackRegistryBaseMixin",
    })
    line("helpers they call:")
    present({ "CreateFromMixins", "secureexecuterange", "hooksecurefunc" })

    local mixin = _G["MapCanvasMixin"]
    if type(mixin) ~= "table" then
        line("MapCanvasMixin is ABSENT - LibMapPinHandler cannot build a shadow canvas here.")
    else
        local missing, have = {}, {}
        for _, name in ipairs(CANVAS_BORROWED) do
            local t = (type(mixin[name]) == "function") and have or missing
            t[#t + 1] = name
        end
        line("MapCanvasMixin methods LibMapPinHandler copies - MISSING (%d of %d):",
             #missing, #CANVAS_BORROWED)
        emit(missing, 3)
        line("  present (%d):", #have)
        emit(have, 3)
    end

    if type(canvas) == "table" then
        local missing = {}
        for _, name in ipairs(CANVAS_HOOKED) do
            if type(canvas[name]) ~= "function" then missing[#missing + 1] = name end
        end
        line("WorldMapFrame methods hooksecurefunc'd - MISSING (%d of %d):",
             #missing, #CANVAS_HOOKED)
        emit(missing, 3)
        if #missing > 0 then
            line("  each of those RAISES inside GetShadowCanvas, so the whole call fails.")
        end
        -- Every one of these is reached by a ShadowCanvas passthrough, which calls it on the
        -- OWNER frame. A nil here raises at that call rather than at load.
        line("WorldMapFrame members the shadow passes through:")
        kinds({
            "WorldMapFrame.ScrollContainer", "WorldMapFrame.pinFrameLevelsManager",
            "WorldMapFrame.GetCanvas", "WorldMapFrame.GetCanvasContainer",
            "WorldMapFrame.ProcessGlobalPinMouseActionHandlers",
        })
    end

    -- ⚠ PIN_FRAME_LEVEL_QUEST_PING is NOT a global - Pin.lua passes it as a STRING LITERAL to
    -- UseFrameLevelType, and the manager resolves it. Probing _G for it reported nil on retail
    -- too. What actually matters is whether this client's manager knows that name, so the
    -- manager is dumped instead of a global being looked up.
    local mgr = type(canvas) == "table" and canvas.pinFrameLevelsManager or nil
    if type(mgr) ~= "table" then
        line("pinFrameLevelsManager: %s - cannot check the frame level Pin.lua asks for", type(mgr))
    else
        local keys = {}
        for k, v in pairs(mgr) do keys[#keys + 1] = ("%s=%s"):format(tostring(k), type(v)) end
        table.sort(keys)
        line("pinFrameLevelsManager holds %d key(s):", #keys)
        emit(keys, 3)
    end

    local pinMixin = _G["MapCanvasPinMixin"]
    if type(pinMixin) == "table" then
        local missing = {}
        for _, name in ipairs(PIN_METHODS) do
            if type(pinMixin[name]) ~= "function" then missing[#missing + 1] = name end
        end
        line("MapCanvasPinMixin methods Modules/MapPOI/Pin.lua calls - MISSING (%d of %d):",
             #missing, #PIN_METHODS)
        emit(missing, 3)
    end

    local stub = _G["LibStub"]
    local lib
    if type(stub) == "table" and type(stub.GetLibrary) == "function" then
        local okLib, res = pcall(stub.GetLibrary, stub, "LibMapPinHandler-1.0", true)
        lib = okLib and res or nil
    end
    line("LibMapPinHandler-1.0: %s", lib and "registered" or "NOT registered - not in this TOC")
    if lib and type(canvas) == "table" then
        local okShadow, shadow = pcall(lib.GetShadowCanvas, lib, canvas)
        if not okShadow then
            line("  GetShadowCanvas RAISED - %s", tostring(shadow):sub(1, 70))
        else
            line("  GetShadowCanvas: %s  AcquirePin=%s  AddDataProvider=%s", type(shadow),
                 type(shadow) == "table" and type(shadow.AcquirePin) or "n/a",
                 type(shadow) == "table" and type(shadow.AddDataProvider) or "n/a")
        end
    end

    -- The pin template lives in Modules/MapPOI/Pin.xml. Creating one is the only test that
    -- covers the XML's inherits resolving on this client as well as the template existing.
    -- ⚠ A TOC that does not list MapPOI fails this for a reason that has nothing to do with
    -- the flavor, so EQQuestPinMixin is reported beside it - that global says whether the
    -- module was loaded at all, which is what tells the two apart.
    local okPin, err = pcall(CreateFrame, "BUTTON", nil, UIParent, "EQQuestPinTemplate")
    line("EQQuestPinTemplate creates: %s%s   EQQuestPinMixin=%s", tostring(okPin),
         okPin and "" or (" - " .. tostring(err):sub(1, 50)),
         _G["EQQuestPinMixin"] and "loaded" or "ABSENT, MapPOI is not in this TOC")

    -- The dataset half. Not "does C_Map exist" - does this client resolve the specific
    -- UiMapIDs the generated table stores.
    line("UiMapIDs %d-%d, the block the Classic coordinate table uses:", COORD_MAP_MIN, COORD_MAP_MAX)
    local getMapInfo = resolve("C_Map.GetMapInfo")
    if type(getMapInfo) ~= "function" then
        line("  C_Map.GetMapInfo: ABSENT - no map id can be validated on this client")
    else
        local resolved, dead, sample = 0, {}, {}
        for id = COORD_MAP_MIN, COORD_MAP_MAX do
            local ok, info = pcall(getMapInfo, id)
            if ok and type(info) == "table" and info.name then
                resolved = resolved + 1
                if #sample < 6 then sample[#sample + 1] = ("%d=%s"):format(id, info.name) end
            else
                dead[#dead + 1] = tostring(id)
            end
        end
        line("  resolved %d of %d", resolved, COORD_MAP_MAX - COORD_MAP_MIN + 1)
        emit(sample, 2)
        if #dead > 0 then
            line("  UNRESOLVED (%d) - any quest stored against these gets no pin:", #dead)
            emit(dead, 6)
        end
    end

    local coords = ns.CLASSIC_QUEST_COORDS
    if type(coords) ~= "table" then
        line("ns.CLASSIC_QUEST_COORDS: not loaded - the data file is not listed in this TOC")
        return
    end
    local n = 0
    for _ in pairs(coords) do n = n + 1 end
    line("ns.CLASSIC_QUEST_COORDS: %d row(s), decoded against this client:", n)
    local shown = 0
    for qid, packed in pairs(coords) do
        local m, x, y = decodePacked(packed)
        -- Not "UNRESOLVED" when there is nothing to resolve WITH - that reads as a bad map id
        -- rather than an unanswerable question.
        local name = "cannot check, no C_Map.GetMapInfo"
        if type(getMapInfo) == "function" then
            local ok, info = pcall(getMapInfo, m)
            name = (ok and type(info) == "table" and info.name) or "UNRESOLVED"
        end
        line("  quest %s -> map %d (%s) %.4f, %.4f", tostring(qid), m, name, x, y)
        shown = shown + 1
        if shown >= 5 then break end
    end
end

-- ⛔ Every capability in the `pins` section answered yes on Era and NO PIN APPEARED. That is
-- no longer a capability question, so nothing here looks a name up: this walks the provider's
-- own decisions and COUNTS them. A stage that reports zero is the stage that is wrong.
function Probe:MapPOI()
    out("Modules/MapPOI - why a pin did or did not appear")

    local canvas = _G["WorldMapFrame"]
    local shown = type(canvas) == "table" and canvas.IsShown and canvas:IsShown() and true or false
    local openMap
    if shown and canvas.GetMapID then openMap = canvas:GetMapID() end
    local playerMap
    local best = resolve("C_Map.GetBestMapForUnit")
    if type(best) == "function" then
        local ok, v = pcall(best, "player")
        playerMap = ok and v or nil
    end
    -- The open map is what _DoRefresh actually reads. The player's zone is only a stand in so
    -- the section still says something useful with the map closed.
    local target = openMap or playerMap
    line("world map shown=%s  open mapID=%s  player mapID=%s  -> counting against %s",
         tostring(shown), tostring(openMap), tostring(playerMap), tostring(target))
    if not shown then
        line("⚠ _DoRefresh early-returns while the map is CLOSED. Re-run with it OPEN.")
    end

    line("1. is the provider attached at all:")
    local MP = ns:GetSubsystem("MapPOIProvider")
    if not MP then
        line("  MapPOIProvider subsystem ABSENT - Provider.lua is not in this TOC")
        return
    end
    line("  attached=%s  provider=%s  shadow=%s", tostring(MP.attached),
         type(MP.provider), type(MP.shadow))
    line("  _DoRefresh ran %s time(s), last stage %q, last mapID=%s, pins acquired=%s",
         tostring(MP._refreshes), tostring(MP._stage), tostring(MP._mapID), tostring(MP._pins))
    -- "never ran" and "cannot tell" are different claims and only one of them is evidence.
    if MP._refreshes == nil then
        line("  (no counters on this Provider.lua - it predates this diagnostic)")
    elseif MP._refreshes == 0 then
        line("  ⛔ the refresh NEVER RAN. Nothing downstream of it can be the cause.")
    elseif (MP._pins or 0) > 0 then
        line("  ⛔ pins WERE acquired and you cannot see them - this is a DRAW problem,")
        line("  not a data one. Suspect the frame level in 2 below.")
    end
    if MP.provider then
        local okMap, pmap = pcall(MP.provider.GetMap, MP.provider)
        line("  provider:GetMap()=%s  its mapID=%s",
             okMap and type(pmap) or "RAISED",
             (okMap and type(pmap) == "table" and pmap.GetMapID) and tostring(pmap:GetMapID()) or "n/a")
    end

    -- ⛔ Pin.lua:12 passes this name as a STRING to UseFrameLevelType. A client that does not
    -- DEFINE it cannot place the pin, and nothing raises - the pin is simply never positioned.
    line("2. the frame level Pin.lua asks for, in the manager's own definitions:")
    local mgr = type(canvas) == "table" and canvas.pinFrameLevelsManager or nil
    local defs = type(mgr) == "table" and mgr.definitions or nil
    if type(defs) ~= "table" then
        line("  pinFrameLevelsManager.definitions is %s", type(defs))
    else
        local names, found = {}, false
        for k, v in pairs(defs) do
            local name = type(v) == "table" and (v.pinFrameLevelType or v.name) or k
            names[#names + 1] = tostring(name)
            if tostring(name) == "PIN_FRAME_LEVEL_QUEST_PING" then found = true end
        end
        table.sort(names)
        line("  PIN_FRAME_LEVEL_QUEST_PING defined: %s   (%d definition(s))",
             found and "YES" or "⛔ NO", #names)
        emit(names, 2)
        if type(mgr.GetValidFrameLevel) == "function" then
            callDump("  GetValidFrameLevel('PIN_FRAME_LEVEL_QUEST_PING')",
                     "WorldMapFrame.pinFrameLevelsManager.GetValidFrameLevel",
                     mgr, "PIN_FRAME_LEVEL_QUEST_PING")
        end
    end

    line("3. the data the refresh would find, counted:")
    local Cache = ns:GetSubsystem("Cache")
    local coords = ns.CLASSIC_QUEST_COORDS
    if not Cache then
        line("  Cache subsystem ABSENT")
    elseif type(coords) ~= "table" then
        line("  ns.CLASSIC_QUEST_COORDS not loaded")
    else
        local logged, withCoord, onTarget, samples = 0, 0, 0, {}
        for qid in pairs(Cache:All()) do
            logged = logged + 1
            local packed = coords[qid]
            if packed then
                withCoord = withCoord + 1
                local m = math.floor(packed / 1e8)
                if m == target then
                    onTarget = onTarget + 1
                elseif #samples < 6 then
                    samples[#samples + 1] = ("q%d->map%d"):format(qid, m)
                end
            end
        end
        line("  quests in Cache: %d", logged)
        line("  of those, in the coord table: %d", withCoord)
        line("  of those, stored on map %s: %d", tostring(target), onTarget)
        if logged == 0 then
            line("  ⛔ Cache is EMPTY - the problem is upstream of MapPOI entirely.")
        elseif withCoord == 0 then
            line("  ⛔ none of your quests are in the table - it is objective data for Era")
        elseif onTarget == 0 then
            line("  ⛔ every match is stored on ANOTHER map. Open the map to one of these:")
            emit(samples, 3)
        end
    end

    -- ⛔ Once pins ARE acquired, every remaining hypothesis is about one frame's state, and
    -- guessing between them is what the last two rounds cost. Read the pin instead.
    -- ApplyPinPosition anchors as normalizedX * canvas:GetWidth(), so a canvas measuring zero
    -- stacks every pin in one corner - which is why the canvas is measured here too.
    line("4. the acquired pins themselves:")
    local shadow = MP.shadow
    if type(shadow) ~= "table" or type(shadow.EnumeratePinsByTemplate) ~= "function" then
        line("  no shadow canvas to enumerate")
        return
    end
    local cw, ch
    local okCanvas, cv = pcall(shadow.GetCanvas, shadow)
    if okCanvas and type(cv) == "table" and cv.GetWidth then
        cw, ch = cv:GetWidth(), cv:GetHeight()
        line("  canvas %s  %.0f x %.0f  shown=%s  scale=%.2f",
             (cv.GetName and cv:GetName()) or "unnamed", cw or 0, ch or 0,
             tostring(cv.IsShown and cv:IsShown()), (cv.GetEffectiveScale and cv:GetEffectiveScale()) or 0)
    else
        line("  GetCanvas() did not answer a frame")
    end

    local drawn, n, firstPin = 0, 0, nil
    local okEnum, err = pcall(function()
        for pin in shadow:EnumeratePinsByTemplate("EQQuestPinTemplate") do
            n = n + 1
            firstPin = firstPin or pin
            if pin:IsShown() then drawn = drawn + 1 end
            if n <= 8 then
                local parent = pin.GetParent and pin:GetParent()
                line("  pin %d q=%s shown=%s visible=%s alpha=%.2f level=%s strata=%s",
                     n, tostring(pin.questID), tostring(pin:IsShown()), tostring(pin:IsVisible()),
                     pin:GetAlpha() or -1, tostring(pin:GetFrameLevel()),
                     tostring(pin:GetFrameStrata()))
                line("     size=%.0fx%.0f  points=%d  parent=%s",
                     pin:GetWidth() or 0, pin:GetHeight() or 0, pin:GetNumPoints() or 0,
                     parent and ((parent.GetName and parent:GetName()) or "unnamed") or "NONE")
                if (pin:GetNumPoints() or 0) > 0 then
                    local p, rel, rp, ox, oy = pin:GetPoint(1)
                    line("     %s -> %s %s  ofs %.1f, %.1f", tostring(p),
                         rel and ((rel.GetName and rel:GetName()) or "unnamed") or "nil",
                         tostring(rp), ox or 0, oy or 0)
                    -- ⛔ MEASURED: ApplyPinPosition anchors at
                    -- normalized * canvas:GetWidth() / PIN:GetScale(), because a SetPoint offset
                    -- is read in the anchored frame's OWN coordinate space. Leaving the pin
                    -- scale out of this division is what made seven correctly placed pins read
                    -- as "off by 0.3" for three rounds.
                    local packed = coords and pin.questID and coords[pin.questID]
                    if packed and cw and ch and cw > 0 and ch > 0 then
                        local ps = pin:GetScale() or 1
                        local gotX, gotY = (ox or 0) * ps / cw, -(oy or 0) * ps / ch
                        local rest = packed % 1e8
                        local wantX = math.floor(rest / 1e4) / 1e4
                        local wantY = (rest % 1e4) / 1e4
                        local off = math.max(math.abs(gotX - wantX), math.abs(gotY - wantY))
                        line("     scale %.4f  implied %.4f,%.4f  table %.4f,%.4f  %s",
                             ps, gotX, gotY, wantX, wantY,
                             off < 0.005 and "MATCH" or ("⛔ OFF BY %.4f"):format(off))
                    end
                end
                local icon = pin.icon
                line("     icon=%s texture=%s", type(icon),
                     (icon and icon.GetTexture and tostring(icon:GetTexture())) or "n/a")
            end
        end
    end)
    if not okEnum then
        line("  enumeration RAISED - %s", tostring(err):sub(1, 70))
        return
    end
    line("  enumerated %d pin(s), %d shown", n, drawn)
    if n == 0 then
        line("  ⛔ the pool is EMPTY even though AcquirePin was called - the pins are being")
        line("  released again, so suspect a second refresh calling RemoveAllData.")
        return
    end

    -- ⛔ Every pin implied the SAME divisor while the canvas reported another, which cannot be
    -- a stale size - a stale size drifts, it does not stay exact across eight pins. So the two
    -- premises get measured instead of reasoned about: is the frame the pins are anchored TO
    -- the same object GetCanvas() answers, and what does ApplyPinPosition actually multiply by.
    line("5. the two premises behind the offset arithmetic:")
    if firstPin then
        local _, rel = firstPin:GetPoint(1)
        line("  pin's anchor frame IS GetCanvas(): %s", tostring(rel == cv))
        if rel ~= cv and rel and rel.GetWidth then
            line("  ⛔ DIFFERENT FRAME. anchor frame is %.0f x %.0f, GetCanvas() is %.0f x %.0f",
                 rel:GetWidth() or 0, rel:GetHeight() or 0, cw or 0, ch or 0)
        end
        if rel and rel.GetScale then
            line("  anchor frame scale=%.3f effective=%.3f  parent=%s",
                 rel:GetScale() or 0, (rel.GetEffectiveScale and rel:GetEffectiveScale()) or 0,
                 (rel.GetParent and rel:GetParent() and "yes") or "none")
        end
        local cont = shadow.ScrollContainer
        if cont and cont.GetWidth then
            line("  ScrollContainer %.0f x %.0f", cont:GetWidth() or 0, cont:GetHeight() or 0)
        end

        -- The one call that cannot be argued with: hand it a known input and read the output.
        -- 0.5,0.5 must land at half of whatever this client multiplies by.
        local okAP = pcall(shadow.ApplyPinPosition, shadow, firstPin, 0.5, 0.5)
        if okAP then
            local _, _, _, hx, hy = firstPin:GetPoint(1)
            local ps = firstPin:GetScale() or 1
            line("  ApplyPinPosition(pin, 0.5, 0.5) -> ofs %.1f, %.1f", hx or 0, hy or 0)
            line("  multiplier %.1f x %.1f;  canvas %.0f x %.0f / pin scale %.4f = %.1f x %.1f",
                 (hx or 0) * 2, -(hy or 0) * 2, cw or 0, ch or 0, ps,
                 (cw or 0) / ps, (ch or 0) / ps)
            line("  -> the offset is in the PIN's coordinate space, hence the /scale")
        else
            line("  ApplyPinPosition RAISED when called directly")
        end
        if firstPin.ApplyCurrentPosition then firstPin:ApplyCurrentPosition() end

        -- ⛔ The placement is arithmetically correct, so the remaining question is purely
        -- WHERE ON SCREEN the pin lands and whether anything covers it. GetLeft/GetTop are in
        -- screen coordinates already scaled, so they can be compared frame to frame directly.
        -- ⛔ GetLeft and friends answer in the frame's OWN scale units, NOT screen units, so
        -- comparing two frames' rects without multiplying each by its own effective scale is
        -- meaningless. Doing exactly that is what produced a bogus "it is CLIPPED" verdict
        -- here - the third derived verdict in this section to fail on a coordinate space.
        line("  rectangles, RAW (own units) then x effective scale (comparable):")
        local function rect(label, f)
            if not (f and f.GetLeft and f:GetLeft()) then
                line("    %-16s no rect (not laid out)", label)
                return
            end
            local s = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
            line("    %-16s raw L=%.0f R=%.0f B=%.0f T=%.0f  scale=%.4f  strata=%s level=%s",
                 label, f:GetLeft(), f:GetRight(), f:GetBottom(), f:GetTop(), s,
                 tostring(f.GetFrameStrata and f:GetFrameStrata()),
                 tostring(f.GetFrameLevel and f:GetFrameLevel()))
            line("    %-16s cmp L=%.1f R=%.1f B=%.1f T=%.1f  %.1f x %.1f units",
                 "", f:GetLeft() * s, f:GetRight() * s, f:GetBottom() * s, f:GetTop() * s,
                 (f:GetRight() - f:GetLeft()) * s, (f:GetTop() - f:GetBottom()) * s)
        end
        rect("pin", firstPin)
        rect("canvas", cv)
        rect("ScrollContainer", shadow.ScrollContainer)
        rect("WorldMapFrame", canvas)

        local box = shadow.ScrollContainer
        if firstPin:GetLeft() and box and box.GetLeft and box:GetLeft() then
            local ps = firstPin:GetEffectiveScale() or 1
            local cs = box:GetEffectiveScale() or 1
            local pl, pr = firstPin:GetLeft() * ps, firstPin:GetRight() * ps
            local pb, pt = firstPin:GetBottom() * ps, firstPin:GetTop() * ps
            local cl, cr = box:GetLeft() * cs, box:GetRight() * cs
            local cb, ct = box:GetBottom() * cs, box:GetTop() * cs
            local inside = pl >= cl and pr <= cr and pb >= cb and pt <= ct
            line("    pin inside the ScrollContainer: %s", tostring(inside))
            line("    pin sits at %.1f%% across, %.1f%% down the container",
                 ((pl + pr) / 2 - cl) / (cr - cl) * 100, (ct - (pt + pb) / 2) / (ct - cb) * 100)
            -- The virtual screen is 768 units tall at scale 1, so this converts to real pixels
            -- and answers the question the containment test cannot: is it big enough to SEE.
            local _, physH = 0, 0
            if type(_G["GetPhysicalScreenSize"]) == "function" then
                _, physH = _G["GetPhysicalScreenSize"]()
            end
            if physH and physH > 0 then
                local px = (pr - pl) * physH / 768
                line("    display is %d px tall, so the pin draws at about %.0f x %.0f REAL pixels",
                     physH, px, px)
                if px < 12 then
                    line("    ⛔ that is tiny. Correctly placed and effectively invisible.")
                end
                -- Actionable rather than descriptive: a place on screen to actually look at.
                line("    ▶ LOOK AT about %.0f, %.0f pixels from your screen's TOP-LEFT",
                     (pl + pr) / 2 * physH / 768, (768 - (pt + pb) / 2) * physH / 768)
                line("    ▶ then MOUSE OVER that spot. A tooltip there means the pin is live")
                line("      and only its ART is missing, which is a different bug entirely.")
            end

            -- ⛔ Only pin 1 was ever containment tested, and at 2.1x zoom most of the canvas is
            -- outside the window - so "1 of 7 visible" may be entirely expected. Count them.
            local within = 0
            pcall(function()
                for pin in shadow:EnumeratePinsByTemplate("EQQuestPinTemplate") do
                    local s = pin:GetEffectiveScale() or 1
                    if pin:GetLeft() and pin:GetLeft() * s >= cl and pin:GetRight() * s <= cr
                       and pin:GetBottom() * s >= cb and pin:GetTop() * s <= ct then
                        within = within + 1
                    end
                end
            end)
            line("    %d of %d pin(s) fall inside the visible window at this zoom", within, n)
        end

        -- The frame is proven correct, so the remaining suspect is the ART inside it. A
        -- texture can be sized zero, hidden or fully transparent while its parent reads shown.
        local function texLine(label, t)
            if type(t) ~= "table" then
                line("    %-6s absent (%s)", label, type(t))
                return
            end
            line("    %-6s shown=%s alpha=%.2f  %.1f x %.1f  layer=%s  texture=%s",
                 label, tostring(t.IsShown and t:IsShown()), (t.GetAlpha and t:GetAlpha()) or -1,
                 (t.GetWidth and t:GetWidth()) or 0, (t.GetHeight and t:GetHeight()) or 0,
                 tostring(t.GetDrawLayer and t:GetDrawLayer()),
                 tostring(t.GetTexture and t:GetTexture()))
        end
        line("  the pin's own textures:")
        texLine("icon", firstPin.icon)
        texLine("ring", firstPin.ring)
        if firstPin.numberText then
            line("    %-6s shown=%s text=%q", "number",
                 tostring(firstPin.numberText:IsShown()),
                 tostring(firstPin.numberText:GetText() or ""))
        end
    end

    line("6. call ApplyCurrentPosition on each pin and re-read the anchor:")
    local haveApply = 0
    local moved, nowMatch, checked = 0, 0, 0
    local okApply, applyErr = pcall(function()
        for pin in shadow:EnumeratePinsByTemplate("EQQuestPinTemplate") do
            if type(pin.ApplyCurrentPosition) ~= "function" then
                return
            end
            haveApply = haveApply + 1
            local _, _, _, bx, by = pin:GetPoint(1)
            pin:ApplyCurrentPosition()
            local _, _, _, ax, ay = pin:GetPoint(1)
            if math.abs((ax or 0) - (bx or 0)) > 0.5 or math.abs((ay or 0) - (by or 0)) > 0.5 then
                moved = moved + 1
            end
            local packed = coords and pin.questID and coords[pin.questID]
            if packed and cw and ch and cw > 0 and ch > 0 then
                checked = checked + 1
                local ps = pin:GetScale() or 1
                local rest = packed % 1e8
                local wantX = math.floor(rest / 1e4) / 1e4
                local wantY = (rest % 1e4) / 1e4
                local off = math.max(math.abs((ax or 0) * ps / cw - wantX),
                                     math.abs(-(ay or 0) * ps / ch - wantY))
                if off < 0.005 then nowMatch = nowMatch + 1 end
                line("    q=%s  before %.1f,%.1f  after %.1f,%.1f  -> %.4f,%.4f  %s",
                     tostring(pin.questID), bx or 0, by or 0, ax or 0, ay or 0,
                     (ax or 0) * ps / cw, -(ay or 0) * ps / ch,
                     off < 0.005 and "MATCH" or "still off")
            end
        end
    end)
    if not okApply then
        line("  re-apply RAISED - %s", tostring(applyErr):sub(1, 70))
        return
    end
    if haveApply == 0 then
        line("  ⛔ MapCanvasPinMixin has no ApplyCurrentPosition on this client - the fix in")
        line("  LibMapPinHandler cannot work and needs a different re-anchor call.")
    else
        line("  %d pin(s) moved, %d of %d now match the table", moved, nowMatch, checked)
        if nowMatch == checked and checked > 0 then
            line("  ✅ re-applying IS the fix. If pins were still wrong before this, the")
            line("  OnSizeChanged hook did not fire - reload and check again.")
        else
            line("  ⛔ re-applying did NOT correct them, so ApplyPinPosition on this flavor is")
            line("  not dividing by canvas:GetWidth(). Measure that formula before fixing.")
        end
    end
end

-- ⛔ Every reading says the pins are correctly placed, shown, opaque, 40 REAL pixels and inside
-- the visible window - and they are not on screen. Another measurement of the same kind cannot
-- break that tie, so this stops measuring and makes them impossible to miss instead.
-- A magenta block APPEARS  -> the frame renders, and the ICON ART is the fault.
-- Nothing appears          -> the frame does not render, whatever the API reports about it.
-- ⚠ Size and strata only. The SCALE is deliberately left alone: the anchor offset is divided
-- by it, so changing the scale would move every pin and confuse the very thing being tested.
function Probe:Flare(mode)
    mode = (mode or ""):match("^(%S*)") or ""
    if mode == "" then mode = "all" end
    if not (mode == "all" or mode == "size" or mode == "strata" or mode == "reset") then
        out("flare: use size, strata, reset, or no argument for all")
        return
    end
    out("flare %s - /reload also undoes it", mode)

    local MP = ns:GetSubsystem("MapPOIProvider")
    local shadow = MP and MP.shadow
    if not (type(shadow) == "table" and type(shadow.EnumeratePinsByTemplate) == "function") then
        line("no shadow canvas yet - open the world map on a zone with quests, then re-run")
        return
    end
    local base = type(shadow.GetCanvas) == "function" and shadow:GetCanvas() or nil

    local n = 0
    local ok, err = pcall(function()
        for pin in shadow:EnumeratePinsByTemplate("EQQuestPinTemplate") do
            n = n + 1
            local big  = (mode == "all" or mode == "size")
            local high = (mode == "all" or mode == "strata")

            pin:SetSize(big and 120 or 28, big and 120 or 28)
            if high then
                pin:SetFrameStrata("TOOLTIP")
                pin:SetFrameLevel(9000)
            elseif base then
                pin:SetFrameStrata(base:GetFrameStrata())
                pin:SetFrameLevel(2000)
            end

            if pin.ring then pin.ring:Hide() end
            if pin.icon then
                pin.icon:ClearAllPoints()
                if big then
                    pin.icon:SetAllPoints(pin)
                else
                    pin.icon:SetSize(18, 18)
                    pin.icon:SetPoint("CENTER")
                end
                if mode == "all" then
                    pin.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
                    pin.icon:SetVertexColor(1, 0, 1, 1)
                else
                    -- ⛔ Restore from the pin's OWN isComplete, not a hardcoded icon. The first
                    -- version forced the available icon in every mode, which silently turned a
                    -- correct turn-in "?" back into a "!" and read as a second bug.
                    pin.icon:SetTexture(pin.isComplete
                        and "Interface\\GossipFrame\\ActiveQuestIcon"
                        or  "Interface\\GossipFrame\\AvailableQuestIcon")
                    pin.icon:SetVertexColor(1, 1, 1, 1)
                end
                pin.icon:Show()
            end
            pin:Show()
        end
    end)
    if not ok then
        line("RAISED - %s", tostring(err):sub(1, 70))
        return
    end
    if n == 0 then
        line("⛔ the pool is empty - open the world map on a zone with quests first.")
        return
    end

    line("applied to %d pin(s).", n)
    if mode == "all" then
        line("  MAGENTA BLOCKS -> the frames render, so the fault is size, strata or art.")
        line("  Then run 'flare size' and 'flare strata' to tell WHICH.")
    elseif mode == "size" then
        line("  120x120, real icon, at the SHIPPED strata and level 2000.")
        line("  VISIBLE -> size is the fault.  NOT visible -> strata is.")
    elseif mode == "strata" then
        line("  shipped 28x28 and real icon, raised to TOOLTIP / 9000.")
        line("  VISIBLE -> strata is the fault.  NOT visible -> size is.")
    else
        line("  restored to the shipped 28x28 icon 18x18, canvas strata, level 2000.")
        line("  This is what a normal login looks like.")
    end
end

-- The Nameplates rewire rests on a CONTENT question no capability probe can answer: does a
-- Classic unit tooltip carry quest title and objective lines for your own quests at all?
function Probe:Tooltip()
    out("unit tooltip scrape - target a mob you have a quest for first")

    local unitExists = resolve("UnitExists")
    local unitName   = resolve("UnitName")
    local unit = (type(unitExists) == "function" and unitExists("target")) and "target" or nil
    if not unit then
        line("no target. Target a quest mob and run /eqsprobe tooltip again.")
        return
    end
    line("target: %s", tostring(type(unitName) == "function" and unitName("target") or "?"))

    local modern = resolve("C_TooltipInfo.GetUnit")
    if type(modern) ~= "function" then
        line("C_TooltipInfo.GetUnit: ABSENT - the scrape below is the only path")
    else
        local ok, data = pcall(modern, unit)
        local lines
        if ok and type(data) == "table" and type(data.lines) == "table" then
            lines = data.lines
        end
        if not lines then
            line("C_TooltipInfo.GetUnit: returned no lines")
        else
            line("C_TooltipInfo.GetUnit: %d line(s)", #lines)
            for i = 1, math.min(#lines, 12) do
                local l = lines[i]
                line("  [%d] type=%s %s", i, tostring(l and l.type), val(l and l.leftText))
            end
        end
    end

    local tip = _G["EQProbeScanTip"]
    if not tip then
        local okTip = pcall(function()
            tip = CreateFrame("GameTooltip", "EQProbeScanTip", nil, "GameTooltipTemplate")
        end)
        if not okTip or not tip then
            line("GameTooltipTemplate would not create - the scrape path is unavailable")
            return
        end
    end
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    local okSet = pcall(tip.SetUnit, tip, unit)
    if not okSet then
        line("GameTooltip:SetUnit RAISED")
        return
    end
    local n = tip:NumLines() or 0
    line("GameTooltip:SetUnit + TextLeft scrape: %d line(s)", n)
    for i = 1, math.min(n, 12) do
        local fs = _G["EQProbeScanTipTextLeft" .. i]
        line("  [%d] %s", i, fs and val(fs:GetText()) or "no FontString at this index")
    end
    tip:Hide()

    -- A tooltip with no quest lines proves nothing if the target was an ITEM-DROP objective:
    -- the client has no mob-to-item mapping, so only a type="monster" kill objective is a
    -- fair test of the capability. Name the qualifying quests rather than make the tester
    -- guess which mob counts.
    local getObj = resolve("C_QuestLog.GetQuestObjectives")
    if type(getObj) ~= "function" then return end
    line("what EQ needs to match, from your quest log:")
    local ids, titles = collectQuests(25)
    local kills, shown = 0, 0
    for i = 1, #ids do
        local okO, objs = pcall(getObj, ids[i])
        if okO and type(objs) == "table" then
            for k = 1, #objs do
                local o = objs[k]
                local isKill = type(o) == "table" and o.type == "monster"
                if isKill then kills = kills + 1 end
                if shown < 12 then
                    shown = shown + 1
                    line("  %s %s | %s | type=%s", isKill and "KILL" or "    ",
                         tostring(titles[i]):sub(1, 26),
                         tostring(o and o.text):sub(1, 32),
                         tostring(o and o.type))
                end
            end
        end
    end
    if kills == 0 then
        line("NONE of your objectives are type=monster. Pick up a kill quest first, or this")
        line("section cannot tell an absent capability from an item-drop objective.")
    else
        line("%d objective(s) are type=monster - target one of THOSE for a fair test.", kills)
    end
end

-- RegisterEvent RAISES on an event the client does not know rather than quietly no-opping.
-- Core/Events.lua pcalls it and refuses the listener, so an absent event costs that feature
-- and not the load. This list is what EQ would ask for on a client that knew all of them.
local EVENTS = {
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY",
    "PLAYER_REGEN_ENABLED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_GREETING", "GOSSIP_SHOW", "QUEST_WATCH_LIST_CHANGED",
    "QUEST_DATA_LOAD_RESULT", "QUESTLINE_UPDATE", "SUPER_TRACKING_CHANGED",
    "TASK_PROGRESS_UPDATE", "WORLD_QUEST_COMPLETED_BY_SPELL",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
}

function Probe:Events()
    out("events EQ registers (%d)", #EVENTS)
    local frame = CreateFrame("Frame")
    local bad, ok = {}, {}
    for _, e in ipairs(EVENTS) do
        local worked = pcall(frame.RegisterEvent, frame, e)
        if worked then
            ok[#ok + 1] = e
            pcall(frame.UnregisterEvent, frame, e)
        else
            bad[#bad + 1] = e
        end
    end
    frame:UnregisterAllEvents()
    frame:SetParent(nil)
    line("RAISES (%d) - Core/Events.lua refuses the listener for each one:", #bad)
    emit(bad, 2)
    line("accepted (%d):", #ok)
    emit(ok, 3)

    -- The scratch test above says what WOULD raise. This says what Core/Events.lua actually
    -- turned away this session, which is the reading that explains a silent subsystem.
    local Events = ns:GetSubsystem("Events")
    line(Events and Events.DebugLine and Events:DebugLine() or "events: subsystem unavailable")
end

local FONTS = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisableSmall",
    "ChatFontNormal", "GameFontWhiteSmall",
}

-- CreateFontString RAISES when the inherited template is absent, so the object is not just
-- looked up in _G, it is actually inherited.
local TEMPLATES = {
    { "BackdropTemplate",          "Frame"       },
    { "UIPanelScrollFrameTemplate","ScrollFrame" },
    { "UIPanelCloseButton",        "Button"      },
    { "UIPanelButtonTemplate",     "Button"      },
    { "UICheckButtonTemplate",     "CheckButton" },
    { "InputBoxTemplate",          "EditBox"     },
    { "SearchBoxTemplate",         "EditBox"     },
    { "OptionsSliderTemplate",     "Slider"      },
    { "GameTooltipTemplate",       "GameTooltip" },
}

function Probe:UI()
    out("font objects and frame templates")

    local host = CreateFrame("Frame")
    host:Hide()

    local fonts = {}
    for _, name in ipairs(FONTS) do
        local exists = _G[name] ~= nil
        local drew = pcall(host.CreateFontString, host, nil, "OVERLAY", name)
        fonts[#fonts + 1] = ("%s=%s/%s"):format(name, exists and "g" or "NIL",
                                                drew and "ok" or "RAISED")
    end
    line("font objects (global/CreateFontString):")
    emit(fonts, 2)

    line("frame templates:")
    for _, t in ipairs(TEMPLATES) do
        local name, kind = t[1], t[2]
        local worked, err = pcall(CreateFrame, kind, nil, host, name)
        if worked then
            line("  %-28s %-12s ok", name, kind)
        else
            line("  %-28s %-12s RAISED - %s", name, kind, tostring(err):sub(1, 60))
        end
    end

    line("BackdropTemplateMixin=%s  SetBackdrop=%s",
         type(_G["BackdropTemplateMixin"]), type(host.SetBackdrop))

    host:SetParent(nil)
end

function Probe:Misc()
    out("environment")

    local build = _G["GetBuildInfo"]
    if type(build) == "function" then
        local _, info = countAndPack(build())
        line("client %s.%s  interface %s  locale %s",
             tostring(info[1]), tostring(info[2]), tostring(info[4]),
             tostring(GetLocale and GetLocale()))
    end

    local addons = {}
    for _, name in ipairs({ "EQObjectiveTracker", "Questie", "TomTom", "ElvUI" }) do
        addons[#addons + 1] = ("%s=%s"):format(name, tostring(_G[name] ~= nil))
    end
    line("globals: %s", table.concat(addons, "  "))

    present({
        "C_AddOns.IsAddOnLoaded", "IsAddOnLoaded", "C_Timer.After",
        "C_Item.GetItemInfo", "GetItemInfo", "C_CurrencyInfo.GetCoinTextureString",
        "GetCoinTextureString", "C_Texture.GetAtlasInfo", "issecretvalue",
        "C_Map.GetBestMapForUnit", "SetUserWaypoint", "C_Map.SetUserWaypoint",
    })

    local eqot = _G["EQObjectiveTracker"]
    if type(eqot) == "table" and type(eqot.GetModule) == "function" then
        local ok, api = pcall(eqot.GetModule, eqot, "API")
        line("EQOT API module: %s  AddMenuItem=%s  AddHeaderIcon=%s",
             ok and type(api) or "unreachable",
             ok and type(api) == "table" and type(api.AddMenuItem) or "n/a",
             ok and type(api) == "table" and type(api.AddHeaderIcon) or "n/a")
    else
        line("EQOT API module: EQObjectiveTracker global absent")
    end
end

local SECTIONS = {
    map     = Probe.Map,
    poi     = Probe.POI,
    pins    = Probe.Pins,
    mappoi  = Probe.MapPOI,
    flare   = Probe.Flare,
    quest   = Probe.Quest,
    port    = Probe.Port,
    tooltip = Probe.Tooltip,
    events  = Probe.Events,
    ui      = Probe.UI,
    misc    = Probe.Misc,
}

-- A section that raises must not cost the rest of the run, and must not vanish quietly
-- either - a missing section reads as a section that found nothing.
local function runSection(self, name, fn, arg)
    local ok, err = pcall(fn, self, arg)
    if not ok then
        out("section %q RAISED and was cut short - %s", name, tostring(err))
    end
end

function Probe:Run(msg)
    -- The remainder is passed through so a section can take a mode - `flare size` is the one
    -- that needs it, to change a single variable at a time.
    local which, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if which ~= "" and SECTIONS[which] then
        runSection(self, which, SECTIONS[which], rest)
        return
    end
    if which ~= "" then
        out("unknown section %q - use map, poi, pins, mappoi, flare, quest, port, tooltip, events, ui, misc, or none for all",
            which)
        return
    end
    out("EQ %s - full flavor probe", tostring(ns.VERSION))
    for _, name in ipairs({ "misc", "port", "map", "poi", "pins", "quest", "events", "ui" }) do
        runSection(self, name, SECTIONS[name])
    end
    -- tooltip, mappoi and flare are left out of the full run on purpose. Each needs something
    -- set up first - a targeted quest mob, an open world map - so in a blind run each would
    -- report the setup it lacks and read as a capability that is missing. flare also MUTATES.
    out("run /eqsprobe tooltip separately with a quest mob targeted, and /eqsprobe mappoi with the world map OPEN")
end

SLASH_EQSPROBE1 = "/eqsprobe"
SlashCmdList["EQSPROBE"] = function(msg) Probe:Run(msg) end
