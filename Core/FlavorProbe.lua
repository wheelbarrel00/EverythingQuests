local _, ns = ...

-- Globals go through _G by name (no .luacheckrc entry needed), and nothing here may become a runtime branch

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

-- select('#') rather than #, since a nil in any slot would read as a shorter return
local function countAndPack(...)
    return select("#", ...), { ... }
end

local function val(v)
    if type(v) == "string" and #v > 40 then return ("%q..(%d)"):format(v:sub(1, 40), #v) end
    return ("%s(%s)"):format(tostring(v), type(v))
end

-- Sparse quest-id keyed tables have no border, so # answers 0 on a full table
local function countKeys(t)
    if type(t) ~= "table" then return "n/a" end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- A pin may sit at any stored spawn point, so the nearest point of every table is reported
local function nearestStored(questID, gotX, gotY, mapID)
    local best, source
    local function consider(x, y, tag)
        local d = math.max(math.abs(gotX - x), math.abs(gotY - y))
        if not best or d < best then best, source = d, tag end
    end

    -- Gated on the stored map, as Provider's reader is, or another zone's point reads as a misplaced pin
    local coords = ns.CLASSIC_QUEST_COORDS
    local packed = coords and coords[questID]
    if packed and (not mapID or math.floor(packed / 1e8) == mapID) then
        local rest = packed % 1e8
        consider(math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, "single-point")
    end

    local turnIn = ns.CLASSIC_QUEST_TURNIN and ns.CLASSIC_QUEST_TURNIN[questID]
    local tList = turnIn and mapID and turnIn[mapID]
    if tList then
        for i = 1, #tList do
            local rest = tList[i] % 1e8
            consider(math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, "turn-in")
        end
    end

    local spawnsTbl = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    local byMap = spawnsTbl and spawnsTbl[questID]
    if byMap then
        local list = mapID and byMap[mapID]
        if list then
            -- % 1e8 strips the objective mask and kind that sit above the coordinate
            for i = 1, #list do
                local rest = list[i] % 1e8
                consider(math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, "spawn")
            end
        end
    end

    local avail = ns.CLASSIC_QUEST_AVAILABLE
    local aList = avail and avail.start and avail.start[questID]
    aList = aList and mapID and aList[mapID]
    if aList then
        for i = 1, #aList do
            local rest = aList[i] % 1e8
            consider(math.floor(rest / 1e4) / 1e4, (rest % 1e4) / 1e4, "available")
        end
    end

    return best, source
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

-- Takes the function itself, since a LibStub library is never a global
local function dumpCall(label, fn, ...)
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

local function callDump(label, path, ...)
    return dumpCall(label, resolve(path), ...)
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

-- Reports the type, as present() answers MISSING for a table valued name on every flavor
local function kinds(paths)
    local parts = {}
    for _, p in ipairs(paths) do
        parts[#parts + 1] = ("%s=%s"):format(p, type(resolve(p)))
    end
    emit(parts, 2)
end

-- Bounded by a ceiling and the first nil title, never GetNumQuestLogEntries, which counts only visible rows on Classic
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
        -- The count is a floor, never the bound - see the note above.
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

-- Discovered from _G, since C_QuestLog.GetQuestsOnMap answers an empty table on Classic
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

    -- Re-read after the update calls, since an empty first reading may only mean nothing primed it yet
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
    -- The whole title ladder once GetTitleForQuestID is gone. Its curated fallback is Midnight data Classic lacks
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

    -- QuestAuto guards on GetNumActiveQuests and then calls GetActiveTitle and SelectActiveQuest
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

-- Printed by name, extras included, since a renamed field looks the same as an absent one to a caller
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

    -- Era lacks C_QuestLog.GetInfo, so these bare globals are its only row source. Compat reads them by position
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

        -- Position 6 reads nil on every incomplete quest, so only a walk of the whole log can confirm it
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
            line("    nothing in the log has a non-nil [6]. Take a quest to READY TO TURN IN")
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

-- Copied off MapCanvasMixin by LibMapPinHandler at load. A hand copy of its borrow table, so it can go short
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

-- hooksecurefunc raises on a missing method, so one absent name costs GetShadowCanvas the whole call
local CANVAS_HOOKED = {
    "OnShow", "OnHide", "RefreshAllDataProviders", "CallMethodOnPinsAndDataProviders",
    "ReapplyPinFrameLevels", "SetGlobalPinScale", "OnMapChanged",
}

-- Not RegisterForClicks, a Button method from SetPinTemplateType that read MISSING on retail too
local PIN_METHODS = {
    "UseFrameLevelType", "SetScalingLimits", "SetPosition", "ApplyCurrentPosition",
    "OnAcquired", "OnReleased",
}

local function decodePacked(v)
    return math.floor(v / 1e8), math.floor(v % 1e8 / 1e4) / 1e4, (v % 1e4) / 1e4
end

-- Read from the loaded tables, since Era and TBC store different map ids against the same globals
local _coordMaps

local function coordMapIDs()
    if _coordMaps then return _coordMaps end
    local seen = {}
    local coords = ns.CLASSIC_QUEST_COORDS
    if type(coords) == "table" then
        for _, packed in pairs(coords) do seen[math.floor(packed / 1e8)] = true end
    end
    -- Appended, as ipairs would stop at a failed spawn build and drop the tables after it
    local sources = {}
    local spawnsAll = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    sources[#sources + 1] = spawnsAll
    sources[#sources + 1] = ns.CLASSIC_QUEST_TURNIN
    sources[#sources + 1] = ns.CLASSIC_QUEST_AVAILABLE and ns.CLASSIC_QUEST_AVAILABLE.start
    for _, tbl in ipairs(sources) do
        if type(tbl) == "table" then
            for _, byMap in pairs(tbl) do
                if type(byMap) == "table" then
                    for mapID in pairs(byMap) do seen[mapID] = true end
                end
            end
        end
    end
    _coordMaps = {}
    for id in pairs(seen) do _coordMaps[#_coordMaps + 1] = id end
    table.sort(_coordMaps)
    return _coordMaps
end

local function mapBlocks(ids)
    local parts, s, p = {}, nil, nil
    for i = 1, #ids do
        local m = ids[i]
        if not s then s, p = m, m
        elseif m == p + 1 then p = m
        else parts[#parts + 1] = (s == p) and tostring(s) or (s .. "-" .. p); s, p = m, m end
    end
    if s then parts[#parts + 1] = (s == p) and tostring(s) or (s .. "-" .. p) end
    return table.concat(parts, ", ")
end

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
        line("WorldMapFrame members the shadow passes through:")
        kinds({
            "WorldMapFrame.ScrollContainer", "WorldMapFrame.pinFrameLevelsManager",
            "WorldMapFrame.GetCanvas", "WorldMapFrame.GetCanvasContainer",
            "WorldMapFrame.ProcessGlobalPinMouseActionHandlers",
        })
    end

    -- A string Pin.lua passes to UseFrameLevelType, not a global, so the manager is dumped instead
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

    -- Only creating a pin tests Pin.xml's inherits. The mixin shows too, as a TOC without MapPOI fails for another reason
    local okPin, err = pcall(CreateFrame, "BUTTON", nil, UIParent, "EQQuestPinTemplate")
    line("EQQuestPinTemplate creates: %s%s   EQQuestPinMixin=%s", tostring(okPin),
         okPin and "" or (" - " .. tostring(err):sub(1, 50)),
         _G["EQQuestPinMixin"] and "loaded" or "ABSENT, MapPOI is not in this TOC")

    local mapIDs = coordMapIDs()
    -- Hoisted, because the per-quest decode below names maps with it too.
    local getMapInfo = resolve("C_Map.GetMapInfo")
    if #mapIDs == 0 then
        line("UiMapIDs: no coordinate table is loaded, so there is no block to validate.")
    else
        line("UiMapIDs actually stored by this TOC's data (%d ids): %s",
             #mapIDs, mapBlocks(mapIDs))
        if type(getMapInfo) ~= "function" then
            line("  C_Map.GetMapInfo: ABSENT - no map id can be validated on this client")
        else
            local resolved, dead, sample = 0, {}, {}
            for i = 1, #mapIDs do
                local id = mapIDs[i]
                local ok, info = pcall(getMapInfo, id)
                if ok and type(info) == "table" and info.name then
                    resolved = resolved + 1
                    if #sample < 6 then sample[#sample + 1] = ("%d=%s"):format(id, info.name) end
                else
                    dead[#dead + 1] = tostring(id)
                end
            end
            line("  resolved %d of %d", resolved, #mapIDs)
            emit(sample, 2)
            if #dead > 0 then
                line("  UNRESOLVED (%d) - any quest stored against these gets no pin:", #dead)
                emit(dead, 6)
            end
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
        -- Not UNRESOLVED when nothing can resolve, which would read as a bad map id
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

-- All three tracked sources on the same quests, raw first, as one answering false for every quest looks like a working filter
local function trackedSourceReadings()
    local Cache = ns:GetSubsystem("Cache")
    if not (Cache and Cache.All) then
        line("    no Cache to read, so the tracked sources cannot be compared")
        return
    end

    local watchType = resolve("C_QuestLog.GetQuestWatchType")
    local bare      = resolve("IsQuestWatched")
    local byID      = resolve("GetQuestLogIndexByID")
    local TS        = ns.Compat.TrackedSet()
    local numWatch  = resolve("GetNumQuestWatches")
    local blizzard  = ns.Compat.BlizzardTrackerInUse()

    line("    SOURCES  C_QuestLog.GetQuestWatchType=%s  bare IsQuestWatched=%s  EQOT TrackedSet=%s  Blizzard's tracker in use=%s",
         type(watchType), type(bare), TS and "present" or "absent", tostring(blizzard))
    line("    EQ READS: %s",
         (type(watchType) == "function" and "C_QuestLog.GetQuestWatchType")
         or (blizzard and "bare IsQuestWatched, Blizzard's list or a quest addon's replacement")
         or (TS and "EQOT TrackedSet:IsTracked") or "nothing - every quest is cannot-tell")
    if type(numWatch) == "function" then
        local ok, n = pcall(numWatch)
        -- Raw only. EQOT measured 0 here on 1.15.9 while its window ran, so there 0 proves nothing
        line("    GetNumQuestWatches() raw=%s   %s", ok and tostring(n) or "RAISED",
             blizzard and "(Blizzard's own list, or 0 if another quest tracker empties it)"
                 or "(EQOT's window keeps this list empty - not evidence by itself)")
    end

    local rows, agree, disagree, bareTrue, tsTrue, tsKnown = 0, 0, 0, 0, 0, 0
    local total = 0
    for id, q in pairs(Cache:All()) do
        total = total + 1
        local wt, bw, ts, idx
        if type(watchType) == "function" then
            local ok, v = pcall(watchType, id)
            wt = ok and (v ~= nil) or nil
        end
        -- Resolved here, not cached on the quest, as EQ reads the bare global only under Blizzard's tracker
        if type(byID) == "function" then
            local ok, v = pcall(byID, id)
            if ok and v and v ~= 0 then idx = v end
        end
        if type(bare) == "function" and idx then
            local ok, v = pcall(bare, idx)
            if ok then bw = v and true or false end
        end
        if TS and TS.IsTracked then
            local ok, v = pcall(TS.IsTracked, TS, id)
            if ok then ts = v end
        end
        if bw then bareTrue = bareTrue + 1 end
        if ts ~= nil then tsKnown = tsKnown + 1 end
        if ts then tsTrue = tsTrue + 1 end
        if bw ~= nil and ts ~= nil then
            if bw == ts then agree = agree + 1 else disagree = disagree + 1 end
        end
        if rows < 10 then
            rows = rows + 1
            line("    raw q=%-6s idx=%-4s watchType=%-5s bareIsQuestWatched=%-5s EQOT=%-5s  EQ reads=%s",
                 tostring(id), tostring(idx), tostring(wt), tostring(bw),
                 tostring(ts), tostring(q.isWatched))
        end
    end
    if total > rows then line("    ...%d more quest(s) not printed", total - rows) end

    line("    TOTALS  quests=%d  bare says tracked=%d  EQOT says tracked=%d of %d it knows",
         total, bareTrue, tsTrue, tsKnown)

    -- A regression watch on the bare global, which EQ reads only under Blizzard's tracker
    if disagree > 0 then
        line("    the bare global and EQOT DISAGREE on %d quest(s), agree on %d. Expected on this",
             disagree, agree)
        line("      flavor: EQOT owns the gesture and keeps Blizzard's list empty. EQ asks EQOT.")
    end
    if type(bare) == "function" and total > 0 and bareTrue == 0 and tsTrue > 0 then
        line("    the bare global calls EVERY quest untracked while EQOT names %d tracked. That is",
             tsTrue)
        line("      the emptied list, and reading it would hide every owned pin. Do not wire it up.")
    end
    if TS and tsKnown == 0 and total > 0 then
        line("    EQOT knows none of them yet - its set is nil until its provider seeds it or the")
        line("      player first toggles, and nil means SHOW. Not a fault.")
    elseif blizzard and type(watchType) ~= "function" then
        line("    Blizzard's tracker is in use, so EQOT leaves that list alone and the bare global")
        line("      is the answer, unless another quest addon replaced it with its own list.")
    elseif not TS then
        line("    NO EQOT TrackedSet here. On Classic that leaves nothing able to answer, so every")
        line("      quest reads cannot-tell and the filter correctly hides nothing.")
    end
end

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
    -- The open map is what _DoRefresh reads. The player's zone stands in with the map closed
    local target = openMap or playerMap
    line("world map shown=%s  open mapID=%s  player mapID=%s  -> counting against %s",
         tostring(shown), tostring(openMap), tostring(playerMap), tostring(target))
    if not shown then
        line("_DoRefresh early-returns while the map is CLOSED. Re-run with it OPEN.")
    end

    -- The type prints beside the factor, since a zone map and an unanswered client both read 1
    if target then
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(target)
        local mapType = type(info) == "table" and info.mapType or nil
        line("map type=%s (0 cosmic, 1 world, 2 continent, 3 zone)  pin size factor=%s",
             tostring(mapType),
             tostring(ns.MapPinTypeScale and ns.MapPinTypeScale(target) or "n/a"))
        if mapType == nil then
            line("  the client reported NO map type, so the factor fell back to full size")
        end
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
    if MP._ownedOff then
        line("  NOTE: \"Show quest pins on the world map\" is OFF, so pins for quests you are")
        line("  carrying are suppressed. Available quest pins have their own checkbox and are")
        line("  unaffected, so a non-zero available count below is correct here.")
    end
    -- Available pins get their own term, or they read as the spawn table failing for that many quests
    line("  ...of those from the objective SPAWN map=%s, TURN-IN table=%s, available quests=%s, single-point/Blizzard=%s",
         tostring(MP._spawnPins), tostring(MP._turnInPins), tostring(MP._availPins),
         tostring((MP._pins or 0) - (MP._spawnPins or 0) - (MP._availPins or 0)
                  - (MP._turnInPins or 0)))
    line("  turn-in table loaded=%s  quests in it=%s",
         tostring(ns.CLASSIC_QUEST_TURNIN ~= nil), tostring(countKeys(ns.CLASSIC_QUEST_TURNIN)))
    -- Zero with a high spawn count means the spread filter is not running
    line("  spawn points thinned by minimum separation=%s", tostring(MP._spawnThinned))
    -- A pin held back for Blizzard's own marker and a quest with no point here leave the same gap
    line("  Blizzard's own markers: stage %q, quests it marks here=%s, EQ pins yielded to them=%s, owned ring=%s",
         tostring(MP._blizzardStage), tostring(countKeys(MP._blizzardMarks)), tostring(MP._yielded),
         tostring(ns.QuestPinRingWanted and ns.QuestPinRingWanted(false)))
    -- Switched off, hiding nothing and no source answering all draw the same map. The rows below separate them
    local DB = ns:GetSubsystem("DB")
    local onlyTracked = (DB and DB.db.profile.map and DB.db.profile.map.onlyTrackedPins) == true
    -- Refusals, not pins removed. Section 3 has the on-this-map count
    line("  only markers for tracked quests=%s   quest(s) refused by it=%s",
         tostring(onlyTracked), tostring(MP._untrackedHidden))
    if onlyTracked then
        local Cache = ns:GetSubsystem("Cache")
        local watched, untracked, unknown = 0, 0, 0
        if Cache and Cache.All then
            for _, q in pairs(Cache:All()) do
                if q.isWatched == nil then unknown = unknown + 1
                elseif q.isWatched then watched = watched + 1
                else untracked = untracked + 1 end
            end
        end
        line("    of the quests in Cache: tracked=%d untracked=%d CANNOT TELL=%d",
             watched, untracked, unknown)
        if unknown > 0 then
            line("    a cannot-tell quest is SHOWN, which is the fail-open working. Read the raw")
            line("    rows below before concluding anything about WHY it cannot tell.")
        end
        trackedSourceReadings()
    end

    if ns.QuestPinFadeState then
        local fadeOn, fadedN, liveN = ns.QuestPinFadeState()
        line("  fade markers over the player=%s   pin(s) currently dimmed=%d of %d live",
             tostring(fadeOn), fadedN, liveN)
        if fadeOn then
            -- Unreadable restores full alpha, so a fade dimming nothing may mean no position was read
            local px, py
            if ns.PlayerPositionOn then px, py = ns.PlayerPositionOn(MP._mapID) end
            line("    player position on the OPEN map %s: %s",
                 tostring(MP._mapID),
                 px and ("%.4f, %.4f"):format(px, py)
                     or "nil - not this map, or an instance. Nothing is dimmed, correctly.")
        end
    end

    -- Tooltips aggregate off this record, so a count below pins acquired means a missed record() call
    line("  pins recorded for tooltip aggregation=%s  (must equal pins acquired above)",
         tostring(MP._drawnN))
    -- Read BEFORE the loader runs, or this reports the state the probe just created
    local wasBuilt = ns.CLASSIC_QUEST_SPAWNS ~= nil
    local spawnsNow = ns.Compat and ns.Compat.ClassicSpawns and ns.Compat.ClassicSpawns()
    line("  spawn data present=%s  built before this section=%s  builds ok=%s  quests=%s",
         tostring(ns.HAS_CLASSIC_SPAWNS == true), tostring(wasBuilt),
         tostring(spawnsNow ~= nil), tostring(countKeys(spawnsNow)))
    if wasBuilt then
        line("  (a full /eqsprobe and any world map draw both build it, so true is expected here)")
    end
    -- "never ran" and "cannot tell" are different claims and only one of them is evidence.
    if MP._refreshes == nil then
        line("  (no counters on this Provider.lua - it predates this diagnostic)")
    elseif MP._refreshes == 0 then
        line("  the refresh NEVER RAN. Nothing downstream of it can be the cause.")
    elseif (MP._pins or 0) > 0 then
        line("  pins WERE acquired. IF you cannot see any, that makes it a DRAW problem and")
        line("  not a data one - suspect the frame level in 2 below. If you can see them,")
        line("  this line means nothing.")
    end
    if MP.provider then
        local okMap, pmap = pcall(MP.provider.GetMap, MP.provider)
        line("  provider:GetMap()=%s  its mapID=%s",
             okMap and type(pmap) or "RAISED",
             (okMap and type(pmap) == "table" and pmap.GetMapID) and tostring(pmap:GetMapID()) or "n/a")
    end

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
             found and "YES" or "NO", #names)
        emit(names, 2)
        if type(mgr.GetValidFrameLevel) == "function" then
            callDump("  GetValidFrameLevel('PIN_FRAME_LEVEL_QUEST_PING')",
                     "WorldMapFrame.pinFrameLevelsManager.GetValidFrameLevel",
                     mgr, "PIN_FRAME_LEVEL_QUEST_PING")

            -- Where our level sits among the client's own types. An undefined type falls back to a base under the map's layers
            local ours = mgr:GetValidFrameLevel("PIN_FRAME_LEVEL_QUEST_PING")
            local rows, below, above = {}, 0, 0
            for i = 1, #names do
                local ok, lvl = pcall(mgr.GetValidFrameLevel, mgr, names[i])
                if ok and type(lvl) == "number" then
                    rows[#rows + 1] = { name = names[i], lvl = lvl }
                    if type(ours) == "number" then
                        if lvl > ours then above = above + 1 else below = below + 1 end
                    end
                end
            end
            table.sort(rows, function(a, b) return a.lvl > b.lvl end)
            line("  every DEFINED type's level, highest first - ours is %s:", tostring(ours))
            local top = {}
            for i = 1, math.min(12, #rows) do
                top[#top + 1] = ("%s=%d"):format(rows[i].name:gsub("PIN_FRAME_LEVEL_", ""),
                                                 rows[i].lvl)
            end
            emit(top, 2)
            -- A plain reading, not a verdict, or it would contradict section 4's applied level
            if type(ours) == "number" then
                line("  the NAME resolves to %d, and %d defined type(s) sit above that.",
                     ours, above)
            end
            if found then
                line("  the client DEFINES that name, so EQ leaves the level to Blizzard.")
            else
                local applied = (rows[1] and rows[1].lvl + 1) or ns.MAPPOI_FALLBACK_LEVEL
                local overApplied = 0
                for i = 1, #rows do
                    if rows[i].lvl >= applied then overApplied = overApplied + 1 end
                end
                if overApplied == 0 then
                    line("  the name is UNDEFINED here, so EQ forces %d, above all %d definitions.",
                         applied, #rows)
                    line("  Section 4 confirms what each pin ended up with.")
                else
                    line("  EQ forces %d and %d defined type(s) still sit at or above it -",
                         applied, overApplied)
                    line("  those can cover the pins. Check section 4 for the level that stuck.")
                end
            end
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
            line("  Cache is EMPTY - the problem is upstream of MapPOI entirely.")
        elseif withCoord == 0 then
            line("  none of your quests are in the table - it is objective data for Era")
        elseif onTarget == 0 then
            line("  every match is stored on ANOTHER map. Open the map to one of these:")
            emit(samples, 3)
        end
    end

    -- Measured too, since a zero-width canvas stacks every pin in one corner
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
                    -- normalized * canvas:GetWidth() / pin:GetScale(), as a SetPoint offset is read in the frame's own scale
                    if pin.questID and cw and ch and cw > 0 and ch > 0 then
                        local ps = pin:GetScale() or 1
                        local gotX, gotY = (ox or 0) * ps / cw, -(oy or 0) * ps / ch
                        local off, source = nearestStored(pin.questID, gotX, gotY, pin.mapID)
                        if off then
                            line("     scale %.4f  implied %.4f,%.4f  nearest stored %s point off by %.4f  %s",
                                 ps, gotX, gotY, source, off,
                                 off < 0.005 and "MATCH" or "NOT A STORED POINT")
                        else
                            line("     scale %.4f  implied %.4f,%.4f  (quest not in either table)",
                                 ps, gotX, gotY)
                        end
                    end
                end
                local icon = pin.icon
                line("     icon=%s texture=%s", type(icon),
                     (icon and icon.GetTexture and tostring(icon:GetTexture())) or "n/a")
                -- The one reading that separates an override that never ran from one that was overwritten
                local want = pin.eqWantedLevel
                local got = pin:GetFrameLevel()
                if want == nil then
                    line("     eqWantedLevel is NIL - Pin.lua never set a level on this pin")
                elseif want ~= got then
                    line("     EQ asked for level %s, frame reports %s - SOMETHING OVERWROTE IT",
                         tostring(want), tostring(got))
                else
                    line("     level %s is EQ's own, and it stuck", tostring(want))
                end
            end
        end
    end)
    if not okEnum then
        line("  enumeration RAISED - %s", tostring(err):sub(1, 70))
        return
    end
    line("  enumerated %d pin(s), %d shown", n, drawn)
    if n == 0 then
        -- An empty pool after a refresh that acquired nothing is section 3's answer, not a release bug
        if not MP or (MP._pins or 0) == 0 then
            line("  nothing was acquired in the first place, so there is nothing to release.")
            line("  Section 3 above says why - on a continent or world map the honest answer is")
            line("  that the data stores zone rows only, and zero pins is CORRECT there.")
        else
            line("  the pool is EMPTY even though AcquirePin was called %d time(s) - the pins are",
                 MP._pins)
            line("  being released again, so suspect a second refresh calling RemoveAllData.")
        end
        return
    end

    -- True only at this zoom. Both axes print, as the canvas is not square. The count is Pin's own
    if firstPin and firstPin.NearbyQuestCount and cw and ch and cw > 0 and ch > 0 then
        local reach = (firstPin:GetWidth() or 0) * (firstPin:GetScale() or 1)
                      * (ns.MAPPOI_TOOLTIP_RADIUS_PINS or 1)
        line("  tooltip aggregation reach=%.1f canvas units at this zoom"
             .. "  (%.4f of the map in x, %.4f in y)", reach, reach / cw, reach / ch)
        local okAgg, cnt = pcall(firstPin.NearbyQuestCount, firstPin)
        line("  pin 1 (quest %s) would aggregate %s OTHER quest(s) into its tooltip",
             tostring(firstPin.questID), okAgg and tostring(cnt) or "RAISED")
    end

    line("5. the two premises behind the offset arithmetic:")
    if firstPin then
        local _, rel = firstPin:GetPoint(1)
        line("  pin's anchor frame IS GetCanvas(): %s", tostring(rel == cv))
        if rel ~= cv and rel and rel.GetWidth then
            line("  DIFFERENT FRAME. anchor frame is %.0f x %.0f, GetCanvas() is %.0f x %.0f",
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

        -- A known input: 0.5,0.5 must land at half of whatever this client multiplies by
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

        -- Own units, then times each frame's own effective scale, the only comparable form
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
            -- The virtual screen is 768 units tall at scale 1, so this is real pixels: is it big enough to see
            local _, physH = 0, 0
            if type(_G["GetPhysicalScreenSize"]) == "function" then
                _, physH = _G["GetPhysicalScreenSize"]()
            end
            if physH and physH > 0 then
                local px = (pr - pl) * physH / 768
                line("    display is %d px tall, so the pin draws at about %.0f x %.0f REAL pixels",
                     physH, px, px)
                if px < 12 then
                    line("    that is tiny. Correctly placed and effectively invisible.")
                end

                line("    LOOK AT about %.0f, %.0f pixels from your screen's TOP-LEFT",
                     (pl + pr) / 2 * physH / 768, (768 - (pt + pb) / 2) * physH / 768)
                line("    then MOUSE OVER that spot. A tooltip there means the pin is live")
                line("      and only its ART is missing, which is a different bug entirely.")
            end

            -- At high zoom most of the canvas is off screen, so a low visible count is expected
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

        -- The frame is proven, so the art is next. A texture can be zero sized, hidden or clear under a shown parent
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

        -- A buried pin and a hidden one read alike from the pin, so this looks at what shares the canvas above it
        line("  5b. frames on the canvas at or above the pin's level, which would COVER it:")
        local pinLevel = firstPin:GetFrameLevel() or 0
        -- The pin's own parent, since enumerating WorldMapFrame found nothing and passed a canvas it never read
        local pinParent = (firstPin.GetParent and firstPin:GetParent()) or canvas
        local okKids, kidErr = pcall(function()
            local kids = { pinParent:GetChildren() }
            local over, overShown, ours = 0, 0, 0
            for i = 1, #kids do
                local k = kids[i]
                local lvl = (k.GetFrameLevel and k:GetFrameLevel()) or -1
                -- EQ's own pins are counted apart, keyed on eqPin, since eqWantedLevel is nil wherever EQ defers the level
                if lvl >= pinLevel and k.eqPin then
                    ours = ours + 1
                elseif lvl >= pinLevel then
                    over = over + 1
                    local vis = k.IsShown and k:IsShown()
                    if vis then overShown = overShown + 1 end
                    if over <= 8 then
                        local w = (k.GetWidth and k:GetWidth()) or 0
                        local h = (k.GetHeight and k:GetHeight()) or 0
                        line("     %-28s level=%d strata=%s shown=%s  %dx%d",
                             (k.GetName and k:GetName()) or "unnamed", lvl,
                             tostring(k.GetFrameStrata and k:GetFrameStrata()),
                             tostring(vis), w, h)
                    end
                end
            end
            line("     %d of %d sibling frame(s) under %s sit at or above level %d, %d shown"
                 .. "  (EQ's own pins excluded: %d)",
                 over, #kids, (pinParent.GetName and pinParent:GetName()) or "unnamed",
                 pinLevel, overShown, ours)
            if overShown == 0 then
                line("     nothing shown above the pins among their own siblings. That does not")
                line("     rule out a cover from a higher strata elsewhere, only from here.")
            else
                line("     something IS above them. A full-canvas one that is shown would")
                line("     explain art that flashes and then disappears.")
            end
        end)
        if not okKids then
            line("     could not enumerate canvas children - %s", tostring(kidErr):sub(1, 50))
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
            if pin.questID and cw and ch and cw > 0 and ch > 0 then
                checked = checked + 1
                local ps = pin:GetScale() or 1
                local gotX, gotY = (ax or 0) * ps / cw, -(ay or 0) * ps / ch
                local off = nearestStored(pin.questID, gotX, gotY, pin.mapID)
                if off and off < 0.005 then nowMatch = nowMatch + 1 end
                line("    q=%s  before %.1f,%.1f  after %.1f,%.1f  -> %.4f,%.4f  %s",
                     tostring(pin.questID), bx or 0, by or 0, ax or 0, ay or 0, gotX, gotY,
                     (off and off < 0.005) and "MATCH" or "NOT A STORED POINT")
            end
        end
    end)
    if not okApply then
        line("  re-apply RAISED - %s", tostring(applyErr):sub(1, 70))
        return
    end
    if haveApply == 0 then
        line("  MapCanvasPinMixin has no ApplyCurrentPosition on this client - the fix in")
        line("  LibMapPinHandler cannot work and needs a different re-anchor call.")
    else
        line("  %d pin(s) moved, %d of %d sit on a stored point", moved, nowMatch, checked)
        if nowMatch == checked and checked > 0 then
            line("  every pin is where the data says it should be. Nothing to fix here.")
        elseif moved == 0 then
            line("  re-applying moved nothing, so the anchors were already settled. If some")
            line("  pins read NOT A STORED POINT, check section 5's direct ApplyPinPosition")
            line("  reading BEFORE suspecting the placement - the comparison has been the bug")
            line("  every time so far.")
        else
            line("  re-applying MOVED pins, which means something had left them stale.")
        end
    end
end

-- Unmissable size and strata. The scale stays, since the anchor offset is divided by it
function Probe:Flare(mode)
    mode = (mode or ""):match("^(%S*)") or ""
    if mode == "" then mode = "all" end
    if not (mode == "all" or mode == "size" or mode == "strata" or mode == "reset"
            or mode == "eqart" or mode == "solid" or mode == "level") then
        out("flare: use size, strata, level, eqart, solid, reset, or no argument for all")
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
            -- eqart differs from all only in what the icon paints, so the two compare one variable
            local big  = (mode == "all" or mode == "size" or mode == "eqart")
            local high = (mode == "all" or mode == "strata" or mode == "eqart")

            pin:SetSize(big and 120 or 28, big and 120 or 28)
            if mode == "level" then
                -- Level only, since strata would move both at once, and TOOLTIP strata draws over the whole UI
                if base then pin:SetFrameStrata(base:GetFrameStrata()) end
                pin:SetFrameLevel(9000)
            elseif high then
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
                if mode == "eqart" then
                    pin.icon:SetTexture(
                        "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\loot.tga")
                    pin.icon:SetVertexColor(1, 1, 1, 1)
                elseif mode == "solid" or mode == "all" then
                    pin.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
                    pin.icon:SetVertexColor(1, 0, 1, 1)
                else
                    -- From the pin's own isComplete, or a turn-in marker would come back as an available one
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
        line("the pool is empty - open the world map on a zone with quests first.")
        return
    end

    line("applied to %d pin(s).", n)
    if mode == "all" then
        line("  MAGENTA BLOCKS -> the frames render, so the fault is size, strata or art.")
        line("  Then run 'flare eqart' - same size, same strata, only the ART differs.")
    elseif mode == "level" then
        line("  shipped size AND shipped strata, level raised 2000 -> 9000.")
        line("  VISIBLE -> the fix is a frame LEVEL bump, which is safe and stays inside")
        line("     the map. NOT visible -> only a strata change works, and the occluder is")
        line("     in a strata above the canvas rather than merely a higher level in it.")
    elseif mode == "solid" then
        -- Texture only, the one mode that separates frames not drawing from art not readable
        line("  SHIPPED size and strata, ring hidden, icon = solid magenta.")
        line("  Count what you see:")
        line("    ~%d magenta dots -> the frames all draw and the fault is the ART", n)
        line("    only a handful    -> the frames really are not drawing, and every")
        line("                         texture theory including mine is wrong")
    elseif mode == "eqart" then
        line("  120x120 at TOOLTIP/9000, painted with EQ's OWN loot.tga.")
        line("  This is the A side of an A/B with 'flare all', which is identical except")
        line("  that it paints a BLIZZARD texture. Magenta visible here but EQ art blank")
        line("  means the FILE does not draw, and nothing about frames or placement.")
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

-- What EQ writes onto a tooltip. Call counts print beside the install, as a route that never fires looks uninstalled
local function tooltipWriteRoute()
    out("tooltip lines EQ adds - Modules/Tooltips/QuestTooltips.lua")

    local processor = resolve("TooltipDataProcessor")
    local enumType  = resolve("Enum.TooltipDataType")
    line("TooltipDataProcessor: %s   AddTooltipPostCall: %s",
         type(processor), type(processor) == "table" and type(processor.AddTooltipPostCall) or "n/a")
    line("Enum.TooltipDataType.Unit=%s .Item=%s",
         val(type(enumType) == "table" and enumType.Unit),
         val(type(enumType) == "table" and enumType.Item))
    local gt = _G["GameTooltip"]
    line("GameTooltip:HookScript=%s  ProcessInfo=%s  GetUnit=%s  GetItem=%s",
         type(gt) == "table" and type(gt.HookScript) or "no GameTooltip",
         type(gt) == "table" and type(gt.ProcessInfo) or "n/a",
         type(gt) == "table" and type(gt.GetUnit) or "n/a",
         type(gt) == "table" and type(gt.GetItem) or "n/a")
    if type(processor) == "table" and not (type(gt) == "table" and type(gt.ProcessInfo) == "function") then
        line("  the processor is here but GameTooltip cannot run its post-calls, so EQ takes the script hooks")
    end

    local QT = ns:GetSubsystem("QuestTooltips")
    if not QT then
        line("QuestTooltips subsystem NOT loaded - this TOC does not list the module")
        return
    end
    -- Before any route verdict, since a switched-off option and a dead hook look identical in every counter
    local DB = ns:GetSubsystem("DB")
    local optionOn = not DB or DB.db.profile.general.questTooltips ~= false
    line("option 'Show quest progress on tooltips': %s", optionOn and "ON" or "OFF")
    line("route installed: %s", tostring(QT.route))
    if QT.route == "none" then
        if not optionOn then
            line("  nothing installed because the OPTION IS OFF. That is not a route problem.")
        else
            line("  nothing installed, and the option is on, so neither route above resolved.")
        end
    end
    if type(QT.hooks) == "table" then
        local names = {}
        for k in pairs(QT.hooks) do names[#names + 1] = k end
        table.sort(names)
        for i = 1, #names do
            line("  hook %-34s %s", names[i], tostring(QT.hooks[names[i]]))
        end
    end
    -- Counters only. They tick on a hover, and the live test below is what decides
    line("unit tooltips rendered so far=%d, EQ added %d objective line(s)", QT.unitCalls or 0, QT.unitLines or 0)
    line("item tooltips rendered so far=%d, EQ added %d objective line(s)", QT.itemCalls or 0, QT.itemLines or 0)
    line("lines added for group members to unit and item tooltips so far=%d  (member lines, and the spacer, title and +N lines around them)",
         QT.partyLines or 0)

    line("mob table loaded: %s", tostring(ns.CLASSIC_QUEST_NPCS ~= nil))
    if ns.Has and ns.Has.TooltipDataUnit then
        line("  unit lines are OFF here BY DESIGN - this client draws its own quest lines from its tooltip data")
    end

    local QI = ns:GetSubsystem("NameplateQuestIcons")
    if QI and QI.CacheHeld then
        local indexed = QI.IndexedItemNames and QI:IndexedItemNames() or 0
        line("shared objective cache held: %s   item names indexed: %d",
             tostring(QI:CacheHeld()), indexed)
        if indexed == 0 then
            line("  0 with the cache held means no quest in your log wants an item.")
        end
    else
        line("shared objective cache: NameplateQuestIcons not loaded, so both halves are inert")
    end
end

-- Drives a real render, since a passive counter cannot tell a dead hook from nothing hovered yet
local function tooltipLiveTest()
    local QT = ns:GetSubsystem("QuestTooltips")
    local gt = _G["GameTooltip"]
    if not QT then return end
    if type(gt) ~= "table" or type(gt.SetOwner) ~= "function" then
        line("no GameTooltip to drive - the live test cannot run")
        return
    end

    out("live hook test - EQ drives a real tooltip rather than waiting for you to hover one")
    local parent = _G["UIParent"]

    local unitsBefore, unitLinesBefore = QT.unitCalls or 0, QT.unitLines or 0
    local unitExists = resolve("UnitExists")
    local driveUnit
    if type(unitExists) == "function" then
        -- mouseover is usually gone by the time a slash command is typed, but it costs nothing
        if unitExists("target") then driveUnit = "target"
        elseif unitExists("mouseover") then driveUnit = "mouseover" end
    end

    if driveUnit then
        pcall(gt.SetOwner, gt, parent, "ANCHOR_NONE")
        pcall(gt.ClearLines, gt)
        local ok = pcall(gt.SetUnit, gt, driveUnit)
        local fired = (QT.unitCalls or 0) > unitsBefore
        line("SetUnit(%s): call %s, hook fired=%s, EQ added %d objective line(s)",
             driveUnit, ok and "ok" or "RAISED", tostring(fired),
             (QT.unitLines or 0) - unitLinesBefore)
        if not fired and QT.route == "none" then
            line("  the hook did not fire because NOTHING IS INSTALLED - see the route line at the")
            line("  top of this section. Switch the option on before reading this as a defect.")
        elseif not fired then
            line("  the unit hook did NOT fire while a route IS installed. That is the ROUTE, not")
            line("  the data. Data problems show as fired=true with 0 lines.")
        elseif ns.Has and ns.Has.TooltipDataUnit then
            line("  0 lines is CORRECT here - this client writes its own unit quest lines.")
        end
        pcall(gt.Hide, gt)
    elseif unitsBefore > 0 then
        -- The counters above already settle this, so a bare no-target line would send the reader hunting
        line("SetUnit: no target - and none needed. %d unit tooltip(s) have already rendered",
             unitsBefore)
        line("  and EQ added %d objective line(s) to them, so the unit hook DOES fire on this client.",
             unitLinesBefore)
    else
        line("SetUnit: no target, and no unit tooltip has rendered yet, so the unit hook is")
        line("  still unproven. Target any mob and run this again.")
    end

    -- Searches the bags for an item the log wants, reported apart from the result, as none found is not a failure
    local getNum  = resolve("C_Container.GetContainerNumSlots") or resolve("GetContainerNumSlots")
    local getLink = resolve("C_Container.GetContainerItemLink") or resolve("GetContainerItemLink")
    local QI = ns:GetSubsystem("NameplateQuestIcons")
    if not (type(getNum) == "function" and type(getLink) == "function"
            and QI and QI.ItemObjectives and type(gt.SetBagItem) == "function") then
        line("SetBagItem: no container API to search the bags with")
        return
    end

    -- Bag 5 is retail's reagent bag, where herbs and ore go, and the scan below covers it too
    local scratch, foundBag, foundSlot, foundName = {}, nil, nil, nil
    for bag = 0, 5 do
        local okN, slots = pcall(getNum, bag)
        for slot = 1, (okN and tonumber(slots) or 0) do
            local okL, link = pcall(getLink, bag, slot)
            local name = okL and type(link) == "string" and link:match("|h%[(.-)%]|h")
            if name and QI:ItemObjectives(name, scratch) > 0 then
                foundBag, foundSlot, foundName = bag, slot, name
                break
            end
        end
        if foundBag then break end
    end

    if not foundBag then
        line("SetBagItem: nothing in your bags matches an objective, so there is nothing here")
        line("  to drive. That is a missing ITEM, not a missing hook.")
        if (QT.itemCalls or 0) > 0 then
            line("  %d item tooltip(s) have already rendered and EQ added %d objective line(s), so the",
                 QT.itemCalls or 0, QT.itemLines or 0)
            line("  item hook fires either way.")
        end
        -- Names the wanted items, since the index already knows them
        local wanted = {}
        local n = QI.WantedItems and QI:WantedItems(wanted, 6) or 0
        if n > 0 then
            line("  loot any ONE of these, then hover it in your bags and run this again:")
            for i = 1, n do line("    %s", tostring(wanted[i])) end
        end
        return
    end

    local itemsBefore, itemLinesBefore = QT.itemCalls or 0, QT.itemLines or 0
    pcall(gt.SetOwner, gt, parent, "ANCHOR_NONE")
    pcall(gt.ClearLines, gt)
    local okI = pcall(gt.SetBagItem, gt, foundBag, foundSlot)
    local firedI = (QT.itemCalls or 0) > itemsBefore
    line("SetBagItem(%d,%d) %q: call %s, hook fired=%s, EQ added %d objective line(s)",
         foundBag, foundSlot, tostring(foundName), okI and "ok" or "RAISED",
         tostring(firedI), (QT.itemLines or 0) - itemLinesBefore)
    if not firedI and QT.route == "none" then
        line("  nothing is installed - see the route line at the top. Not a route defect.")
    elseif not firedI then
        line("  the item hook did NOT fire, and that item IS wanted by a quest in your log,")
        line("  so the match is not the fault. The route is.")
    elseif (QT.itemLines or 0) == itemLinesBefore then
        line("  the hook fired and EQ added nothing. onItem stands aside when the option above is off, or")
        line("  when the client's own item data tags a quest line (the next section, retail and Forever")
        line("  only). Otherwise the item's name or its quest data did not reach EQ's lines.")
    end
    pcall(gt.Hide, gt)
end

-- GetBagItem returns the client's own lines unrendered. EQ only annotates an item named by a live objective
local function tooltipBlizzardBagLines()
    local getNum  = resolve("C_Container.GetContainerNumSlots") or resolve("GetContainerNumSlots")
    local getLink = resolve("C_Container.GetContainerItemLink") or resolve("GetContainerItemLink")
    local getQ    = resolve("C_Container.GetContainerItemQuestInfo")
                    or resolve("GetContainerItemQuestInfo")
    local getBag  = resolve("C_TooltipInfo.GetBagItem")

    out("what BLIZZARD already writes on a bag quest item - where it tags a quest line, onItem adds nothing")
    -- The client's line tag is authoritative, text only a fallback. The default numbers match Blizzard's TooltipDataLineType enum
    local LT = _G["Enum"] and _G["Enum"].TooltipDataLineType
    local Q_TITLE  = (LT and LT.QuestTitle) or 17
    local Q_OBJ    = (LT and LT.QuestObjective) or 8
    local Q_PLAYER = (LT and LT.QuestPlayer) or 18
    local function questTyped(ty) return ty == Q_TITLE or ty == Q_OBJ or ty == Q_PLAYER end
    line("line types: QuestTitle=%s QuestObjective=%s QuestPlayer=%s (%s)",
         tostring(Q_TITLE), tostring(Q_OBJ), tostring(Q_PLAYER),
         LT and "from Enum.TooltipDataLineType" or "numeric fallback, Enum absent")
    if type(getBag) ~= "function" then
        line("C_TooltipInfo.GetBagItem: ABSENT on this client, so this section cannot run.")
        line("  That is expected on Era and TBC, whose item hooks pass no data, so the tag gate never applies there.")
        return
    end
    if not (type(getNum) == "function" and type(getLink) == "function") then
        line("no container API to search the bags with")
        return
    end

    local titles = {}
    local collect = ns.Compat and ns.Compat.CollectQuestLog
    if type(collect) == "function" then
        local rows = {}
        -- CollectQuestLog returns the table first, so through pcall the index is the third value
        local okC, _t, last = pcall(collect, rows)
        for i = 1, (okC and tonumber(last) or 0) do
            local r = rows[i]
            -- Headers carry a title too, and a zone name would fake a duplication verdict
            if r and not r.isHeader and r.title and r.title ~= "" then titles[r.title] = true end
        end
    end

    -- Starters and objective items both count. Objective-named items go first, as only they are annotated and the print cap is short
    local QI = ns:GetSubsystem("NameplateQuestIcons")
    local indexedNames = (QI and QI.IndexedItemNames) and QI:IndexedItemNames() or 0
    local scratch = {}
    local objCand, otherCand = {}, {}
    local seen, items, sample, objSeen = 0, 0, nil, 0
    for bag = 0, 5 do
        local okN, slots = pcall(getNum, bag)
        for slot = 1, (okN and tonumber(slots) or 0) do
            local okL, link = pcall(getLink, bag, slot)
            local name = okL and type(link) == "string" and link:match("|h%[(.-)%]|h")
            local isQuest, questID
            local isObjective = false
            if name and QI and QI.ItemObjectives then
                isObjective = QI:ItemObjectives(name, scratch) > 0
            end
            if name then
                items = items + 1
                if type(getQ) == "function" then
                    local okQ, info = pcall(getQ, bag, slot)
                    if okQ then
                        if type(info) == "table" then
                            isQuest, questID, sample = info.isQuestItem, info.questID,
                                sample or ("table isQuestItem=" .. tostring(info.isQuestItem)
                                           .. " questID=" .. tostring(info.questID)
                                           .. " isActive=" .. tostring(info.isActive))
                        else
                            isQuest = info
                            sample = sample or (type(info) .. " " .. tostring(info))
                        end
                    else
                        sample = sample or "RAISED"
                    end
                end
            end
            if name and isObjective then objSeen = objSeen + 1 end
            if name and (isQuest or questID or isObjective) then
                seen = seen + 1
                local into = isObjective and objCand or otherCand
                into[#into + 1] = { bag = bag, slot = slot, name = name,
                                    questID = questID, isObjective = isObjective }
            end
        end
    end

    -- Raw readings beside the count, since none found cannot tell an empty bag from a wrong question
    if seen == 0 then
        line("no quest items found. RAW: %d item(s) scanned in bags 0-5, quest info API %s",
             items, type(getQ) == "function" and "present" or "ABSENT")
        line("  first reading it returned: %s", tostring(sample))
        line("  objective index holds %d item name(s), cache held=%s", indexedNames,
             tostring(QI and QI.CacheHeld and QI:CacheHeld()))
        if indexedNames == 0 then
            line("  the index is EMPTY, so no item could have matched an objective whatever")
            line("  you were carrying. That is a held-cache question, not a bag question.")
        end
        if items > 0 and type(getQ) ~= "function" then
            line("  the bags are NOT empty, so this is a MISSING API and not a missing item.")
        elseif items > 0 then
            line("  the bags are NOT empty, so either nothing carries quest info or the")
            line("  detector is wrong. Compare the reading above against a '!' item.")
        end
        return
    end

    local SHOW_CAP, LINE_CAP = 6, 14
    local shown, objShown, objVerdicts = 0, 0, 0
    local function inspect(c)
        shown = shown + 1
        if c.isObjective then objShown = objShown + 1 end
        local okD, data = pcall(getBag, c.bag, c.slot)
        local rows = (okD and type(data) == "table") and data.lines or nil
        line("[%d] %s  questID=%s  bag=%d slot=%d%s", shown, tostring(c.name),
             tostring(c.questID), c.bag, c.slot,
             c.isObjective and "  MATCHES AN OBJECTIVE - this is the decisive one" or "")
        if not rows then
            line("    GetBagItem returned no lines")
            return
        end
        local typed = 0
        for i = 1, #rows do
            if rows[i] and questTyped(rows[i].type) then typed = typed + 1 end
        end
        local flagged = 0
        local read = math.min(#rows, LINE_CAP)
        for i = 1, read do
            local t = rows[i] and rows[i].leftText
            local ty = rows[i] and rows[i].type
            if type(t) == "string" and t ~= "" then
                -- A starter shares its quest's name, so line 1 would otherwise read as duplicating a title
                local isOwnName = (t == c.name)
                local isQuestTyped = questTyped(ty)
                local prog = t:match("%d+%s*/%s*%d+") and " has COUNT" or ""
                local ttl  = (titles[t] and not isOwnName) and " is a QUEST TITLE" or ""
                if prog ~= "" or ttl ~= "" then flagged = flagged + 1 end
                line("    type=%s %s%s%s%s", tostring(ty), t, prog, ttl,
                     isQuestTyped and "  CLIENT TAGGED THIS A QUEST LINE" or "")
            end
        end
        -- Untagged quest text sits low, so a truncated read can prove it but never its absence
        if read < #rows then
            line("    read %d of %d line(s) for text, and the tag of every line", read, #rows)
            if typed == 0 and flagged == 0 then
                line("    NO VERDICT: no line is tagged, and untagged quest text may sit below what was read.")
                return
            end
        end
        -- Counted where a verdict prints, as an item that reached none is not evidence
        if c.isObjective then objVerdicts = objVerdicts + 1 end
        if typed > 0 and c.isObjective then
            line("    VERDICT: the client TAGS %d line(s) here as quest lines on", typed)
            line("    an item that matches an objective. onItem sees the tag and adds nothing here.")
        elseif typed > 0 then
            line("    VERDICT: the client tags %d quest line(s) here, but EQ never", typed)
            line("    annotates this item - it is not an objective. No clash.")
        elseif flagged > 0 and c.isObjective then
            line("    VERDICT: the client writes quest text on an item EQ DOES")
            line("    annotate, so EQ would DUPLICATE it. onItem needs a gate.")
        elseif flagged > 0 then
            line("    VERDICT: the client writes quest text here, but EQ never")
            line("    annotates this item - it is not an objective. No clash.")
        elseif c.isObjective then
            line("    VERDICT: no quest title and no count from the client on an")
            line("    item EQ DOES annotate. Nothing to duplicate. No gate needed.")
        else
            line("    VERDICT: no quest title and no count in the client's own")
            line("    lines for this item, so EQ has nothing to duplicate here.")
        end
    end

    for i = 1, #objCand do
        if shown >= SHOW_CAP then break end
        inspect(objCand[i])
    end
    for i = 1, #otherCand do
        if shown >= SHOW_CAP then break end
        inspect(otherCand[i])
    end

    line("%d candidate(s) of %d item(s) scanned, %d inspected, %d of those objective items.",
         seen, items, shown, objShown)
    if objSeen > objShown then
        line("  %d further objective item(s) were found but not inspected - the cap is %d.",
             objSeen - objShown, SHOW_CAP)
    end
    if objVerdicts > 0 then
        line("DECISIVE: %d objective item(s) above reached a verdict, which is exactly what",
             objVerdicts)
        line("  onItem annotates. Those VERDICT lines settle whether the client and EQ both write the quest.")
    elseif objShown > 0 then
        line("NOT DECISIVE. %d objective item(s) were inspected but none reached a verdict, so", objShown)
        line("  there is nothing above that settles the question. Read the NO VERDICT lines.")
    else
        line("NOT DECISIVE YET. No item whose NAME matches a live objective was inspected, and")
        line("  onItem annotates nothing else. So the verdicts above show what the client writes")
        line("  on the WRONG class of item.")
        line("  objective index holds %d item name(s), cache held=%s", indexedNames,
             tostring(QI and QI.CacheHeld and QI:CacheHeld()))
        if indexedNames == 0 then
            line("  The index is EMPTY, so the detector could not have matched anything whatever")
            line("  you were carrying. Fix that before concluding the bags are wrong.")
        else
            line("  Carry an objective item and run this again.")
        end
    end
end

function Probe:Tooltip()
    tooltipWriteRoute()
    tooltipLiveTest()
    tooltipBlizzardBagLines()
    out("unit tooltip scrape - TARGET a quest mob before this section")

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

-- RegisterEvent raises on an unknown event. This is what EQ would ask for on a client that knew them all
local EVENTS = {
    "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_MONEY",
    "PLAYER_REGEN_ENABLED", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
    "QUEST_LOG_UPDATE", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE",
    "QUEST_GREETING", "GOSSIP_SHOW", "QUEST_WATCH_LIST_CHANGED",
    "QUEST_DATA_LOAD_RESULT", "QUESTLINE_UPDATE", "SUPER_TRACKING_CHANGED",
    "TASK_PROGRESS_UPDATE", "WORLD_QUEST_COMPLETED_BY_SPELL",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "UPDATE_FACTION", "ZONE_CHANGED_NEW_AREA",
    "QUEST_ACCEPT_CONFIRM", "GROUP_JOINED", "GROUP_LEFT", "GROUP_ROSTER_UPDATE",
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

    -- What Core/Events.lua actually refused this session, the reading that explains a silent subsystem
    local Events = ns:GetSubsystem("Events")
    line(Events and Events.DebugLine and Events:DebugLine() or "events: subsystem unavailable")
end

local FONTS = {
    "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge",
    "GameFontHighlight", "GameFontHighlightSmall", "GameFontDisableSmall",
    "ChatFontNormal", "GameFontWhiteSmall",
}

-- Created, not looked up in _G, since only creating one proves the template inherits
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

    local MC = ns:GetSubsystem("MapCoords")
    if MC then
        -- The stage and counts split a readout that never ran from one that could not resolve a position
        line("MapCoords stage=%s  map updates=%s  minimap updates=%s",
             tostring(MC._stage), tostring(MC._mapUpdates), tostring(MC._minimapUpdates))
        line("  last rendered   map=%s  minimap=%s",
             MC._lastMapText and ("%q"):format(MC._lastMapText) or "nil",
             MC._lastMinimapText and ("%q"):format(MC._lastMinimapText) or "nil")
    else
        line("MapCoords: not loaded by this TOC")
    end

    -- EQ renders every countdown through these, so this is what a player sees. Korean spells them as words
    line("0. the client's own time abbreviations, and what EQ renders from them:")
    for _, name in ipairs({ "DAY_ONELETTER_ABBR", "HOUR_ONELETTER_ABBR",
                            "MINUTE_ONELETTER_ABBR", "SECOND_ONELETTER_ABBR" }) do
        line("  %-22s %s", name, val(resolve(name)))
    end
    local U = ns.Util
    if U and U.WQTimeShort then
        line("  WQTimeShort  2 days=%q  5 hours=%q  30 mins=%q",
             U.WQTimeShort(2880), U.WQTimeShort(300), U.WQTimeShort(30))
        line("  WQTimeLong   90 mins=%q     FmtDuration 3725s=%q",
             U.WQTimeLong(90), U.FmtDuration(3725))
        line("  A bare number with no unit means the global was missing AND the fallback ran.")
    end

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
    for _, name in ipairs({ "EQObjectiveTracker", "TomTom", "ElvUI" }) do
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

local minimapLogAgainstRows, minimapGivers

-- AddMinimapIconMap answers false rather than raising, so the conversion is called over the whole dataset
function Probe:Minimap()
    out("minimap objective pins")

    -- EQ's module first, since any addon's HereBeDragons fills the shared LibStub slot
    line("1. EQ's module:")
    local MM = ns:GetSubsystem("MinimapQuestPins")
    if not MM then
        line("  MinimapQuestPins subsystem ABSENT - Modules/Minimap/QuestPins.lua is not listed")
        line("  by this TOC. On retail that is correct and deliberate. On Classic it is a bug.")
        return
    end

    local HBDP = LibStub and LibStub("HereBeDragons-Pins-2.0", true)
    local HBD  = LibStub and LibStub("HereBeDragons-2.0", true)
    line("2. the library, as LibStub answers it:")
    line("  HereBeDragons-Pins-2.0=%s  HereBeDragons-2.0=%s",
         HBDP and "present" or "ABSENT", HBD and "present" or "ABSENT")
    line("  minor version in use=%s  (the newest copy loaded by ANY addon, not necessarily EQ's)",
         tostring(select(2, LibStub:GetLibrary("HereBeDragons-Pins-2.0", true))))
    if not HBDP then
        line("  the module is listed but the library is not - nothing can draw")
        return
    end
    line("  last rebuild stage=%q  mapID=%s", tostring(MM._stage), tostring(MM._mapID))
    -- Counted apart, as a silent rejection looks exactly like having nothing to draw
    line("  icons registered=%s  REJECTED by HereBeDragons=%s",
         tostring(MM._registered), tostring(MM._rejected))
    line("  quests yielded to Blizzard's own minimap marker=%s  (tracked, on Blizzard's rows: %s)",
         tostring(MM._yielded), tostring(countKeys(MM._blizzardMarks)))

    line("3. can HereBeDragons place the player at all:")
    if HBD then
        dumpCall("  GetPlayerWorldPosition()", HBD.GetPlayerWorldPosition, HBD)
        dumpCall("  GetPlayerZone()", HBD.GetPlayerZone, HBD)
    end
    -- Without a player position HBD hides every pin, which explains an empty minimap alone
    local px = HBD and HBD.GetPlayerWorldPosition and HBD:GetPlayerWorldPosition()
    if not px then
        line("  no player world position - HBD hides EVERY pin in this state. Nothing below")
        line("  can produce a visible icon until this answers.")
    end

    line("4. the conversion, called on the player's own map:")
    local here = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    line("  C_Map.GetBestMapForUnit('player')=%s  name=%s", tostring(here),
         (here and C_Map.GetMapInfo and C_Map.GetMapInfo(here) and C_Map.GetMapInfo(here).name)
         or "n/a")
    if here and HBD then
        dumpCall("  GetWorldCoordinatesFromZone(0.5, 0.5, here)",
                 HBD.GetWorldCoordinatesFromZone, HBD, 0.5, 0.5, here)
    end

    -- The map ids the pins section checks with C_Map, asked of HBD, a separate question
    local mapIDs = coordMapIDs()
    line("5. the dataset's own map ids (%d), through HereBeDragons: %s",
         #mapIDs, mapBlocks(mapIDs))
    if HBD and HBD.GetWorldCoordinatesFromZone and #mapIDs > 0 then
        local okIDs, badIDs = 0, {}
        for i = 1, #mapIDs do
            local x = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, mapIDs[i])
            if x then okIDs = okIDs + 1 else badIDs[#badIDs + 1] = tostring(mapIDs[i]) end
        end
        line("  convertible: %d of %d", okIDs, #mapIDs)
        if #badIDs > 0 then
            line("  NOT convertible - every quest whose spawns land here gets no minimap pin:")
            emit(badIDs, 8)
        end
    end

    minimapLogAgainstRows(MM, here)
    minimapGivers(MM, HBDP)
end

-- No Lua call lists the engine's minimap markers, so this prints each quest's state to compare by eye
function minimapLogAgainstRows(MM, here)
    line("6. the quest log on the player's map, against Blizzard's own rows:")
    local Cache = ns:GetSubsystem("Cache")
    local Provider = ns:GetSubsystem("MapPOIProvider")
    if not (here and Cache and Cache.All and Provider and Provider.PointsFor) then
        line("  no player map, Cache or provider - nothing to list")
        return
    end
    local rowOf = {}
    local rowsFn = resolve("C_QuestLog.GetQuestsOnMap")
    local rows = type(rowsFn) == "function" and rowsFn(here)
    if type(rows) == "table" then
        for i = 1, #rows do
            if rows[i] and rows[i].questID then rowOf[rows[i].questID] = rows[i] end
        end
    end
    local watchFn = resolve("C_QuestLog.GetQuestWatchType")
    local superFn = resolve("C_SuperTrack.GetSuperTrackedQuestID")
    -- Nil is the call's own answer for nothing super-tracked, so only an absent call reads n/a
    line("  Blizzard rows on map %s: %s   super-tracked quest=%s   questPOI=%s",
         tostring(here), tostring(countKeys(rowOf)),
         tostring(type(superFn) == "function" and (superFn() or "none") or "n/a"),
         tostring(GetCVar and GetCVar("questPOI")))
    local filteredOut = resolve("C_Minimap.IsFilteredOut")
    local poiFilter = Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter.QuestPOIs
    line("  minimap tracking menu, quest markers: %s",
         (type(filteredOut) == "function" and poiFilter)
             and (filteredOut(poiFilter) and "OFF (filtered out)" or "on") or "n/a")
    if MM._mapID ~= here then
        line("  the held-back marks below come from the last minimap rebuild, on map %s, not this one",
             tostring(MM._mapID))
    end
    line("  quest    done   watch        Blizzard row   EQ minimap pins")
    local ids = {}
    for qid in pairs(Cache:All()) do ids[#ids + 1] = qid end
    table.sort(ids)
    for _, qid in ipairs(ids) do
        local q = Cache:All()[qid]
        local row = rowOf[qid]
        local n, _, source = Provider:PointsFor(qid, here, q)
        local watch = "n/a"
        if type(watchFn) == "function" then
            local w = watchFn(qid)
            watch = w == nil and "not watched" or tostring(w)
        end
        -- PointsFor answers before the minimap's own yield, which drops these two sources
        local held = n and n > 0 and (source == "turnin" or source == "single")
                     and MM._blizzardMarks and MM._blizzardMarks[qid]
        line("  %-8s %-6s %-12s %-14s %s (%s)", tostring(qid), tostring(q and q.isComplete), watch,
             row and type(row.x) == "number" and ("%.2f, %.2f"):format(row.x * 100, row.y * 100) or "none",
             held and "0" or tostring(n),
             held and (tostring(source) .. ", held back for Blizzard's marker") or tostring(source))
    end
end

-- Measures GIVER_RANGE: walk toward a giver and note the distance printed when the game's mark appears
function minimapGivers(MM, HBDP)
    line("7. EQ's quest giver and hand-in pins the game also marks (held back within %s yards, a guess):",
         tostring(MM._giverRange))
    local hidden = resolve("C_Minimap.IsTrackingHiddenQuests")
    if type(hidden) ~= "function" then
        line("  this client has no minimap quest giver tracking call, so nothing is held back")
        return
    end
    local account = resolve("C_Minimap.IsTrackingAccountCompletedQuests")
    line("  minimap tracking menu, low-level quests: %s   account-completed quests: %s",
         hidden() and "on" or "off",
         type(account) == "function" and (account() and "on" or "off") or "n/a")
    local givers = MM._givers or {}
    line("  giver pins=%d   held back right now=%s", #givers, tostring(MM._giversHeld))
    for i = 1, math.min(#givers, 12) do
        local f = givers[i]
        local ok, _, dist = pcall(HBDP.GetVectorToIcon, HBDP, f)
        if not ok or (_G.issecretvalue and _G.issecretvalue(dist)) then dist = nil end
        line("  %-29s %s yards   %s",
             f.avail and ("quests " .. table.concat(f.avail, ",")) or ("hand-in " .. tostring(f.questID)),
             type(dist) == "number" and ("%.0f"):format(dist) or "unknown",
             f.held and "held back" or "shown")
    end
end

-- Unresolved art draws nothing while reading healthy. A texture added mid-session needs a full restart
function Probe:Media()
    out("EQ's own texture files - do they resolve")
    local BASE = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\"
    local FILES = {
        "skull.tga", "slay.tga", "loot.tga", "object.tga", "entrance.tga",
        "eq-logo-v3.tga", "discord.tga", "headerbar-softmask.tga",
    }

    local probeFrame = CreateFrame("Frame")
    local tex = probeFrame:CreateTexture(nil, "ARTWORK")

    local function handleFor(path)
        tex:SetTexture(nil)
        local ok = pcall(tex.SetTexture, tex, path)
        if not ok then return nil, "RAISED" end
        return tex:GetTexture(), nil
    end

    -- Both controls matter: Blizzard assets have positive FileDataIDs and addon files negative ones
    local good = handleFor("Interface\\Buttons\\WHITE8X8")
    local bogus = handleFor(BASE .. "this-file-does-not-exist-eqprobe.tga")
    line("  control, a real BLIZZARD texture : %s", tostring(good))
    line("  control, a path that CANNOT exist: %s", tostring(bogus))

    local conclusive = (type(bogus) ~= "number")
    if not conclusive then
        line("  the impossible path answers a number too, so this client gives a handle to")
        line("  ANY path and a handle proves nothing. Sizes below are the usable signal.")
    end

    for i = 1, #FILES do
        local got, raised = handleFor(BASE .. FILES[i])
        -- A loaded texture reports its own size, a second reading beside the handle
        local w, h = tex:GetWidth(), tex:GetHeight()
        line("  %-24s handle=%-12s %s", FILES[i], tostring(got or raised or "nil"),
             (conclusive and got == nil) and "NOT FOUND" or "handle given")
        line("      texture object reports %sx%s", tostring(w), tostring(h))
    end

    line("  DO NOT read a negative handle as missing - see the controls above.")
    line("  To find out whether EQ's own art actually DRAWS, open the world map and run")
    line("  /eqsprobe flare all   (Blizzard texture, magenta)  then")
    line("  /eqsprobe flare eqart (EQ's own tga, same size and strata).")
    line("  Magenta visible but EQ art not = the file is the problem, not the drawing.")
end

-- Every gate reports whether it could run, and refusals count by reason, as never ran looks like refused
function Probe:Available()
    out("available quest pins")

    line("1. EQ's module and its data:")
    local A = ns:GetSubsystem("AvailableQuests")
    if not A then
        line("  AvailableQuests subsystem ABSENT - Modules/MapPOI/Available.lua is not listed by")
        line("  this TOC. On retail that is correct: Blizzard draws its own available markers.")
        return
    end
    local D = ns.CLASSIC_QUEST_AVAILABLE
    if not D then
        line("  the module is loaded but ns.CLASSIC_QUEST_AVAILABLE is NIL - the data file is")
        line("  not listed by this TOC, so nothing can be drawn")
        return
    end
    -- countKeys answers the string "n/a" for a non-table, so these are %s rather than %d
    line("  quests with a start point=%s  with names=%s", countKeys(D.start), countKeys(D.names))
    line("  gate rows: pre=%s preAll=%s excl=%s chain=%s parent=%s minRep=%s",
         countKeys(D.pre), countKeys(D.preAll), countKeys(D.excl),
         countKeys(D.chain), countKeys(D.parent), countKeys(D.minRep))

    line("2. this character, as the gates read it:")
    -- The same client calls the module makes, so a wrong reading here is the one the pins get
    local raceName, raceToken, raceID = UnitRace("player")
    local className, classToken, classID = UnitClass("player")
    line("  level=%s  race=%s/%s/%s  class=%s/%s/%s  faction=%s",
         tostring(UnitLevel("player")),
         tostring(raceName), tostring(raceToken), tostring(raceID),
         tostring(className), tostring(classToken), tostring(classID),
         tostring(UnitFactionGroup and UnitFactionGroup("player")))
    if type(raceID) ~= "number" or raceID < 1 or raceID > 31 or type(classID) ~= "number" then
        line("  a numeric id is missing or the race id is above 31, so the module tries the token table.")
        line("  A race with no bit there is gated by faction, and with no faction it draws nothing.")
    end

    line("3. the gates that need a live client call:")
    -- GetQuestsCompleted answers a SET, so # finds a border of 0 and says nothing
    local completed = {}
    if type(_G.GetQuestsCompleted) == "function" then
        pcall(_G.GetQuestsCompleted, completed)
        line("  GetQuestsCompleted: present, %s completed quest(s)", countKeys(completed))
    else
        line("  GetQuestsCompleted: ABSENT - falls back to IsQuestFlaggedCompleted per quest")
    end
    local rangeName = "GetQuestGreenRange"
    local green = resolve(rangeName)
    if not green then
        rangeName = "UnitQuestTrivialLevelRange"
        green = resolve(rangeName)
    end
    if green then
        local ok, r = pcall(green, "player")
        line("  %s: present, returns %s -> quests below level %s are hidden%s", rangeName,
             tostring(ok and r), tostring(A:TrivialFloor()),
             rangeName == "UnitQuestTrivialLevelRange" and " (a range under 4 counts as 4, as in Blizzard's own colors)" or "")
    else
        line("  GetQuestGreenRange and UnitQuestTrivialLevelRange: both ABSENT - the low level filter cannot judge, so it hides NOTHING")
    end
    local repByID = resolve("GetFactionInfoByID")
    line("  reputation: C_Reputation.GetFactionDataByID=%s  GetFactionInfoByID=%s",
         (C_Reputation and type(C_Reputation.GetFactionDataByID) == "function") and "present" or "absent",
         repByID and "present" or "absent")
    line("  A reputation gate that cannot be read shows the quest rather than hiding it.")
    line("  requiredSkill is SHIPPED but never enforced - no reliable skill id lookup here.")

    -- A lunar table that ran out shows its quests like a running event, so coverage is printed
    local H = ns:GetSubsystem("QuestHolidays")
    if H and H.ProbeLines then
        for _, l in ipairs(H:ProbeLines()) do line("  %s", l) end
    end

    line("4. the last pass:")
    -- The pass is lazy, so a cold run would read as every quest ruled out
    A:All()
    line("  stage=%q  quests considered=%s  AVAILABLE=%s  race route=%s",
         tostring(A._stage), tostring(A._resolved), tostring(A._availableN), tostring(A._raceRoute))
    line("  gates that actually ran: raceClass=%s trivial=%s reputation=%s highLevel=%s season=%s",
         tostring(A._gatesRun.raceClass), tostring(A._gatesRun.trivial),
         tostring(A._gatesRun.reputation), tostring(A._gatesRun.highLevel),
         tostring(A._gatesRun.season))
    local reasons = {}
    for why, n in pairs(A._reason) do reasons[#reasons + 1] = ("%s=%d"):format(why, n) end
    table.sort(reasons)
    line("  ruled out by: %s", #reasons > 0 and table.concat(reasons, "  ") or "nothing")

    line("5. on the map the player is standing in:")
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then
        line("  no map for the player")
        return
    end
    local n = A:PointsFor(mapID)
    local totalQuests = 0
    for i = 1, n do totalQuests = totalQuests + #A._locQuests[i] end
    line("  mapID=%s  pins=%d  quests behind them=%d", tostring(mapID), n, totalQuests)
    line("  Pins are merged BY LOCATION, so more quests than pins is correct - one giver with")
    line("  several quests is one pin. Equal counts everywhere means the merge is not running.")
    -- A filter on with no table loaded looks like a filter that matched nothing
    line("  category table loaded=%s  quests in it=%s",
         tostring(ns.CLASSIC_QUEST_CATEGORY ~= nil), tostring(countKeys(ns.CLASSIC_QUEST_CATEGORY)))
    do
        local DB = ns:GetSubsystem("DB")
        local map = DB and DB.db.profile.map
        line("  filters: dungeon/raid=%s repeatable=%s profession=%s",
             tostring(map and map.hideDungeonQuests == true),
             tostring(map and map.hideRepeatableQuests == true),
             tostring(map and map.hideProfessionQuests == true))
    end
    line("6. what the WORLD MAP last drew, which is a different question:")
    local P = ns:GetSubsystem("MapPOIProvider")
    if not P then
        line("  MapPOIProvider subsystem ABSENT")
        return
    end
    -- What was last drawn, which a shut map skips, unlike section 5's direct ask
    line("  last stage=%q  mapID=%s  available=%s of %s pin(s)",
         tostring(P._stage), tostring(P._mapID),
         tostring(P._availPins), tostring(P._pins))
    -- The stage alone, as _mapID is nil for every early return, not just a shut map
    if P._stage == "world map not shown" then
        line("  The world map was CLOSED, so 0 pins and mapID=nil are the correct readings here")
        line("  and say nothing about drawing. Open the world map on a ZONE map, then rerun.")
    elseif P._mapID == nil and P._stage ~= "ran" then
        line("  The refresh returned early at the stage above, so these numbers say nothing")
        line("  about drawing. That stage is the thing to explain, not the pin count.")
    elseif not (WorldMapFrame and WorldMapFrame:IsShown()) then
        line("  The world map is closed NOW, so these are the numbers from when it last was.")
    end
end

-- MUTATES the selected quest log entry and puts it back. Run with the quest log closed
function Probe:XP()
    out("quest reward XP - does the argument mean anything on this flavor")

    line("1. what exists at all:")
    present({
        "GetQuestLogRewardXP", "GetQuestLogRewardMoney", "GetNumQuestLogRewards",
        "SelectQuestLogEntry", "GetQuestLogSelection",
        "C_QuestLog.SetSelectedQuest", "C_QuestLog.GetSelectedQuest",
        "C_QuestLog.GetQuestRewardXP", "GetQuestLogRewardTitle",
    })

    -- Index and questID, as the selection is set by index and EQ's call passes an id
    local rows = {}
    local flatTitle = resolve("GetQuestLogTitle")
    local getInfo   = resolve("C_QuestLog.GetInfo")
    for i = 1, MAX_LOG_SCAN do
        local idx, qid, title
        if type(flatTitle) == "function" then
            local ok, t1, _, _, isHeader, _, _, _, questID = pcall(flatTitle, i)
            if not ok or t1 == nil then break end
            if not isHeader and questID and questID ~= 0 then idx, qid, title = i, questID, t1 end
        elseif type(getInfo) == "function" then
            local ok, info = pcall(getInfo, i)
            if not ok or type(info) ~= "table" then break end
            if not info.isHeader and info.questID and info.questID ~= 0 then
                idx, qid, title = i, info.questID, info.title
            end
        else
            break
        end
        if idx then
            rows[#rows + 1] = { idx = idx, qid = qid, title = title }
            if #rows >= 2 then break end
        end
    end

    line("2. the two quest log rows this test uses:")
    for i = 1, #rows do
        line("  index %s  questID %s  %q", tostring(rows[i].idx), tostring(rows[i].qid),
             tostring(rows[i].title))
    end
    if #rows < 2 then
        line("  NEED TWO quests in the log to tell the two shapes apart. Pick up another and rerun.")
        return
    end

    local xpFn     = resolve("GetQuestLogRewardXP")
    local moneyFn  = resolve("GetQuestLogRewardMoney")
    local selectFn = resolve("SelectQuestLogEntry")
    local getSel   = resolve("GetQuestLogSelection")
    if type(xpFn) ~= "function" then
        line("GetQuestLogRewardXP is ABSENT - nothing below can be measured on this flavor.")
        return
    end

    -- One call per reading, as asking twice could disagree
    local function ask(...)
        local n, packed = countAndPack(pcall(xpFn, ...))
        if not packed[1] then return nil, ("RAISED %s"):format(tostring(packed[2])) end
        return packed[2], ("%d value(s), [1]=%s"):format(n - 1, val(packed[2]))
    end

    local before = nil
    if type(getSel) == "function" then
        local ok, sel = pcall(getSel)
        if ok then before = sel end
    end
    line("  selection before the test: %s", tostring(before))

    line("3. WITHOUT touching the selection:")
    local a0, a0Text = ask(rows[1].qid)
    line("  GetQuestLogRewardXP(%d) -> %s", rows[1].qid, a0Text)
    local b0, b0Text = ask(rows[2].qid)
    line("  GetQuestLogRewardXP(%d) -> %s", rows[2].qid, b0Text)
    local _, n0Text = ask()
    line("  GetQuestLogRewardXP()   -> %s", n0Text)

    local a1, b1, aNo, bNo
    if type(selectFn) == "function" then
        line("4. WITH the selection moved to each quest in turn:")
        pcall(selectFn, rows[1].idx)
        local aText, aNoText
        a1, aText = ask(rows[1].qid)
        aNo, aNoText = ask()
        line("  selected index %d: with id -> %s", rows[1].idx, aText)
        line("                     no arg  -> %s", aNoText)
        pcall(selectFn, rows[2].idx)
        local bText, bNoText
        b1, bText = ask(rows[2].qid)
        bNo, bNoText = ask()
        line("  selected index %d: with id -> %s", rows[2].idx, bText)
        line("                     no arg  -> %s", bNoText)
        if before then
            pcall(selectFn, before)
            line("  selection restored to %s", tostring(before))
        else
            line("  selection was NOT restored - GetQuestLogSelection gave nothing to restore to")
        end
    else
        line("4. SelectQuestLogEntry is ABSENT, so the selection half cannot be tested here.")
    end

    dumpCall("  GetQuestLogRewardMoney(first questID)", moneyFn, rows[1].qid)

    -- Every number above is printed raw, so this reading can be checked rather than trusted.
    line("5. what that means:")
    -- Equal answers happen at max level or equal rewards, so only a moving selection proves the argument ignored
    if a0 ~= nil and b0 ~= nil and a0 ~= b0 then
        line("  the ARGUMENT is respected - two ids gave %s and %s with no selection change.",
             tostring(a0), tostring(b0))
        line("  Core/QuestRewards.lua's GetQuestLogRewardXP(questID) is correct on this flavor.")
    elseif aNo ~= nil and bNo ~= nil and aNo ~= bNo then
        line("  the SELECTION drives it - the no-arg call answered %s then %s as the selection moved.",
             tostring(aNo), tostring(bNo))
        line("  Passing a questID is meaningless here. Reading XP costs a SelectQuestLogEntry,")
        line("  which moves the player's own quest log, so it must be saved and restored.")
    elseif a0 == 0 and b0 == 0 and (aNo == 0 or aNo == nil) then
        line("  everything answered 0. At MAX LEVEL a quest awards no XP, so this is expected")
        line("  there and says nothing about the signature. Rerun below max level.")
    else
        line("  INCONCLUSIVE. The two quests may simply award the same XP (%s vs %s).",
             tostring(a0), tostring(b0))
        line("  Rerun with two quests of clearly different levels.")
    end
    line("  a1/b1 with id under matching selection: %s / %s", tostring(a1), tostring(b1))
end

-- Missing data, a dropped query and a refusing gate each report separately
function Probe:QuestBrowser()
    out("quest browser")

    local QB = ns:GetSubsystem("QuestBrowser")
    local QBD = ns:GetSubsystem("QuestBrowserData")
    if not (QB and QBD) then
        line("  QuestBrowser subsystem ABSENT - Modules/QuestBrowser/ is not listed by this TOC.")
        line("  On retail that is correct: Blizzard's own quest log already describes any quest.")
        return
    end
    line("1. the data behind it:")
    line("  QuestBrowserData:Loaded()=%s", tostring(QBD:Loaded()))
    if not QBD:Loaded() then
        line("  the modules loaded but the Classic tables did not - see /eqsprobe available")
        return
    end
    line("  window built=%s  shown=%s  selected=%s",
         tostring(QB.frame ~= nil),
         tostring(QB.frame ~= nil and QB.frame:IsShown() or false),
         tostring(QB._selected))

    line("2. an empty query, which is every quest the table names:")
    local rows, matched = QBD:Query({ limit = 5 })
    line("  matched=%s  rows returned=%s", tostring(matched), tostring(#rows))
    for i = 1, #rows do
        line("  [%s] %s  level=%s", tostring(rows[i].id), tostring(rows[i].name), tostring(rows[i].level))
    end
    -- Query reuses its table, so section 4 reads this id, not rows[1]
    local firstID = rows[1] and rows[1].id
    if matched == 0 then
        line("  ZERO with a loaded table - the query is dropping everything, not the data")
    end

    line("3. the map the player is standing on:")
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if mapID then
        local _, here = QBD:Query({ mapID = mapID, limit = 1 })
        line("  mapID=%s name=%s  quests starting here=%s",
             tostring(mapID), tostring(QBD:ZoneName(mapID)), tostring(here))
        line("  This counts quests that START here, not quests that mention the zone. Zero on an")
        line("  INSTANCE map is correct - no instance map is in the data. Zero in a CAPITAL is not:")
        line("  the capitals carry the largest start counts in the whole table.")
    else
        line("  no map for the player")
    end

    line("4. one full record, so every decode is exercised at once:")
    local pick = QB._selected or firstID
    local r = pick and QBD:Record(pick)
    if not r then
        line("  no record for %s", tostring(pick))
        return
    end
    line("  #%s %q  level=%s  requires=%s", tostring(r.id), tostring(r.name),
         tostring(r.level), tostring(r.reqLevel))
    line("  available=%s  reason=%s  completed=%s  inLog=%s",
         tostring(r.available), tostring(r.reason), tostring(r.completed), tostring(r.inLog))
    line("  races=%s  classes=%s",
         r.races and table.concat(r.races, "/") or "any",
         r.classes and table.concat(r.classes, "/") or "any")
    line("  starts=%s  objective maps=%s  turn-in maps=%s",
         tostring(r.starts and #r.starts or 0),
         tostring(r.objectives and #r.objectives or 0),
         tostring(r.turnIn and #r.turnIn or 0))
    if r.starts then
        for i = 1, math.min(3, #r.starts) do
            local s = r.starts[i]
            line("   start on %s (%s) at %.4f, %.4f kind=%s",
                 tostring(s.mapID), tostring(QBD:ZoneName(s.mapID)), s.x, s.y, tostring(s.kind))
        end
    end

    line("5. the gate and the window have to agree:")
    local A = ns:GetSubsystem("AvailableQuests")
    if A then
        line("  map pass stage=%q", tostring(A._stage))
        local gateSays = A:IsAvailable(r.id)
        line("  AvailableQuests:IsAvailable=%s  record.available=%s", tostring(gateSays), tostring(r.available))
        -- IsAvailable's set is empty by design with the option off, so the match is judged only after a run
        if A._stage == "ran" then
            line("  MATCH=%s", tostring(gateSays == (r.available == true)))
            line("  A mismatch means the browser and the map pins are answering from different code.")
        else
            line("  NOT COMPARED - the map pass did not run, so IsAvailable is empty for every")
            line("  quest BY DESIGN. Only the browser's own answer means anything in this state.")
        end
    end
end

function Probe:Group()
    out("party quest progress")

    local Comms = ns:GetSubsystem("GroupComms")
    local Data  = ns:GetSubsystem("GroupData")
    if not (Comms and Data) then
        line("GroupComms/GroupData: not loaded by this TOC - nothing else here means anything")
        return
    end

    local DB  = ns:GetSubsystem("DB")
    local cfg = DB and DB.db and DB.db.profile and DB.db.profile.group
    line("1. settings")
    line("  share progress   %s", tostring(cfg and cfg.partyProgress))
    line("  read other addons %s", tostring(cfg and cfg.readPeerAddons))

    line("2. the transport")
    -- Asked of the shipped resolver, so the probe cannot resolve LibStub differently from the addon.
    local lib = Comms.Transport and Comms:Transport()
    line("  LibStub           %s", type(LibStub))
    line("  AceComm-3.0       %s", lib and "resolved" or "ABSENT - nothing can be sent or read")
    line("  ChatThrottleLib   %s  version %s",
         type(_G["ChatThrottleLib"]),
         tostring(_G["ChatThrottleLib"] and _G["ChatThrottleLib"].version))
    local reg = _G["C_ChatInfo"] and _G["C_ChatInfo"].IsAddonMessagePrefixRegistered
    if type(reg) == "function" then
        for _, row in ipairs(Comms:Prefixes()) do
            local ok, yes = pcall(reg, row.prefix)
            line("  prefix %-10s registered=%s", row.label, ok and tostring(yes) or "RAISED")
        end
    else
        line("  IsAddonMessagePrefixRegistered is ABSENT, so registration cannot be read back")
    end
    if Comms.PeerListenerPresent then
        line("  another listener on the interop prefix: %s",
             Comms:PeerListenerPresent() and "yes" or "no")
    end

    line("3. the group")
    local bg = "unreadable"
    if type(UnitInBattleground) == "function" then
        -- Bound to locals, because tostring() with no argument raises when the call returns nothing.
        local ok, yes = pcall(UnitInBattleground, "player")
        bg = ok and tostring(yes) or "RAISED"
    end
    line("  IsInGroup=%s  IsInRaid=%s  GetNumGroupMembers=%s  battleground=%s",
         tostring(IsInGroup()), tostring(IsInRaid()), tostring(GetNumGroupMembers()), bg)
    if not IsInGroup() then
        line("  NOT IN A GROUP. Everything below reads empty for that reason and not another.")
    end

    line("4. what has been received")
    local names = Data:PlayerNames()
    line("  players sharing   %d", #names)
    for _, who in ipairs(names) do
        line("    %-16s class=%s", who, tostring(Data:Class(who)))
    end
    local Cache = ns:GetSubsystem("Cache")
    if not Cache then
        line("  Cache is ABSENT, so your own quests could not be compared against the store")
    else
        local quests, rows, mine = 0, 0, 0
        for questID in pairs(Cache:All()) do
            mine = mine + 1
            local n = Data:CountForQuest(questID)
            if n > 0 then quests = quests + 1; rows = rows + n end
        end
        line("  of your %d quests, %d also held by someone else, %d party rows in total",
             mine, quests, rows)
    end
    line("  store revision    %d", Data.revision)
    line("  A player count above zero with zero rows on your own quests is NORMAL - it means")
    line("  they are working quests you do not have, which nothing draws yet.")
end

local SECTIONS = {
    media   = Probe.Media,
    group   = Probe.Group,
    xp      = Probe.XP,
    available = Probe.Available,
    questbrowser = Probe.QuestBrowser,
    map     = Probe.Map,
    poi     = Probe.POI,
    pins    = Probe.Pins,
    mappoi  = Probe.MapPOI,
    minimap = Probe.Minimap,
    flare   = Probe.Flare,
    quest   = Probe.Quest,
    port    = Probe.Port,
    tooltip = Probe.Tooltip,
    events  = Probe.Events,
    ui      = Probe.UI,
    misc    = Probe.Misc,
}

-- For the offline harness, whose hardcoded list would pass a section nobody added
function Probe:SectionNames()
    return pairs(SECTIONS)
end

-- A raising section must not end the run or vanish, which would read as finding nothing
local function runSection(self, name, fn, arg)
    local ok, err = pcall(fn, self, arg)
    if not ok then
        out("section %q RAISED and was cut short - %s", name, tostring(err))
    end
end

function Probe:Run(msg)
    -- The rest passes through as a mode, like `flare size`
    local which, rest = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if which ~= "" and SECTIONS[which] then
        runSection(self, which, SECTIONS[which], rest)
        return
    end
    if which ~= "" then
        out("unknown section %q - use media, map, poi, pins, mappoi, minimap, available, questbrowser, group, flare, quest, port, tooltip, xp, events, ui, misc, or none for all",
            which)
        return
    end
    out("EQ %s - full flavor probe", tostring(ns.VERSION))
    for _, name in ipairs({ "misc", "port", "media", "map", "poi", "pins", "minimap", "available", "questbrowser", "group", "quest", "events", "ui" }) do
        runSection(self, name, SECTIONS[name])
    end
    -- tooltip, mappoi, flare and xp need setup, and flare and xp mutate, so a blind run leaves them out
    out("run /eqsprobe tooltip separately with a quest mob targeted, /eqsprobe mappoi with the world map OPEN, and /eqsprobe xp with TWO quests in the log")
end

SLASH_EQSPROBE1 = "/eqsprobe"
SlashCmdList["EQSPROBE"] = function(msg) Probe:Run(msg) end
