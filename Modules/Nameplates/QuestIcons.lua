local _, ns = ...

local QI = ns:RegisterSubsystem("NameplateQuestIcons", {})

local ICON_SIZE    = 24
local DEFAULT_TEXT = 13
local SPACING      = 3
-- Slots per plate. The creature scan stops at the same count, which also limits an Era or TBC mob tooltip
local MAX_ICON_SLOTS = 4

local function cfg()
    local DB = ns:GetSubsystem("DB")
    local g = (DB and DB.db.profile.general) or {}
    return (g.npIconSize or ICON_SIZE), (g.npIconTextSize or DEFAULT_TEXT), (g.npIconPlacement or "RIGHT"),
           (g.npIconOffsetX or 0), (g.npIconOffsetY or 0)
end

-- Midnight restricted APIs can hand back secret values that error if indexed or compared
local _issecret = _G.issecretvalue
local function ok(v)
    if _issecret then return not _issecret(v) end
    return true
end

local PLACEMENT = {
    RIGHT  = { point = "LEFT",   rel = "RIGHT",  x = 4,  y = 0, side = true },
    LEFT   = { point = "RIGHT",  rel = "LEFT",   x = -4, y = 0, side = true },
    TOP    = { point = "BOTTOM", rel = "TOP",    x = 0,  y = 4 },
    BOTTOM = { point = "TOP",    rel = "BOTTOM", x = 0,  y = -4 },
}

local function isShown(frame)
    if type(frame) ~= "table" or not frame.IsShown then return false end
    local shown = frame:IsShown()
    return ok(shown) and shown == true
end

-- EllesmereUI draws its own health bar on Blizzard's nameplate at a width of its own, and shares its plates through this global, keyed by nameplate token
local function ellesmereBar(unit, plate)
    local eui = unit and _G.EllesmereNameplates_NS
    if type(eui) ~= "table" then return nil end
    local ep = (type(eui.plates) == "table" and eui.plates[unit])
        or (type(eui.friendlyPlates) == "table" and eui.friendlyPlates[unit])
    if type(ep) ~= "table" or ep.nameplate ~= plate then return nil end
    local bar = ep.health
    if not isShown(bar) then return nil end
    return bar, eui, ep
end

-- EllesmereUI's WoW Forever level box or Classic border end on that side, which move with its plate's scale and are drawn at a friendly bar's own height
local function ellesmereEdge(ep, right)
    -- Taken even hidden, as EllesmereUI hides it between units and on game objects but clears the field when the box is switched off
    local box = right and ep._fvLevelBox
    if type(box) == "table" then return box, "EllesmereUI level box" end
    local art = ep._classicHealthArt
    local cap = type(art) == "table" and art[right and 3 or 1]
    if isShown(cap) then return cap, "EllesmereUI border end" end
    return nil
end

-- The room EllesmereUI reports, for a plate whose box or border it has not built yet
local function ellesmereRoom(eui, side)
    if type(eui.NP_ClassicSide) ~= "function" then return 0 end
    local done, room = pcall(eui.NP_ClassicSide, side)
    if done and type(room) == "number" and room > 0 then return room end
    return 0
end

-- WoW Forever draws its level badge right of the health bar, so the icons start after it (retail, Era and TBC show theirs only on players' plates, which get no icons)
local function rightOf(plate)
    if not ns.HAS_CLASSIC_SPAWNS then return plate end
    local uf = plate.UnitFrame
    local badge = type(uf) == "table" and uf.PlayerLevelDiffFrame
    local shown = badge and badge:IsVisible()
    -- Never measured, as Forever refuses to measure the badge in combat, though anchoring to it worked there
    if ok(shown) and shown then return badge end
    return plate
end

-- The count text sits on the nameplate too, so a refused or secret width falls back to an estimate
local function textWidth(fs, label, textSize)
    local done, w = pcall(fs.GetStringWidth, fs)
    if done and ok(w) and type(w) == "number" then return math.ceil(w) end
    return math.ceil(#label * textSize * 0.6)
end

local function anchorFrame(f, plate, placement, offX, offY, unit)
    local p = PLACEMENT[placement] or PLACEMENT.RIGHT
    local right = p == PLACEMENT.RIGHT
    local x, to, name = p.x, nil, nil
    if p.side then
        local bar, eui, ep = ellesmereBar(unit, plate)
        if bar then
            to, name = ellesmereEdge(ep, right)
            if not to then
                to, name = bar, "EllesmereUI bar"
                local room = ellesmereRoom(eui, right and "right" or "left")
                x = x + (right and room or -room)
            end
        end
    end
    if not to then
        to = (right and rightOf(plate)) or plate
        name = (to == plate) and "nameplate" or "level badge"
    end
    f.anchorName = name
    f:ClearAllPoints()
    f:SetPoint(p.point, to, p.rel, x + (offX or 0), p.y + (offY or 0))
end

-- The numeric fallbacks were read on a live client
local LT = Enum and Enum.TooltipDataLineType
local QUEST_TITLE     = (LT and LT.QuestTitle)     or 17
local QUEST_OBJECTIVE = (LT and LT.QuestObjective) or 8

local KILL_WORDS = { "slain", "slay", "kill", "defeat", "destroy", "eliminat", "wound" }
local CHAT_WORDS = { "speak", "talk" }
local function objType(text, hasItem, otype)
    if hasItem then return "ITEM" end
    if otype == "item" then return "LOOT" end
    if not text then return "DEFAULT" end
    local l = text:lower()
    for i = 1, #KILL_WORDS do if l:find(KILL_WORDS[i], 1, true) then return "KILL" end end
    for i = 1, #CHAT_WORDS do if l:find(CHAT_WORDS[i], 1, true) then return "CHAT" end end
    return "DEFAULT"
end

-- Nameplate addons with quest icons of their own, so EQ's start off beside them until the player picks
local function rivalAddon()
    local f = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G["IsAddOnLoaded"]
    if not f then return nil end
    if f("ElvUI") then return "ElvUI" end
    if f("EllesmereUINameplates") then return "EllesmereUI" end
    return nil
end

local activeQuests = {}   -- quest title -> objective text -> entry, for the tooltip path
local questObjList = {}   -- questID -> { entry, ... } in quest log order
local questObjSlot = {}   -- questID -> objective type -> index within that type -> entry
local npcQuests    = {}   -- creature id -> { { quest, slot, otype }, ... }
local itemQuests   = {}   -- lowercased item name -> { entry, ... }
local _logRows = {}

-- Compared whole, as a character class would split the three-byte full-width colon and could eat the tail of another character
local NAME_SEPARATORS = { ":", "\239\188\154" }

-- The item's name is the objective text less its count, last on Era and TBC ("Okra: 0/14") and first on Forever
local function objectiveItemName(text)
    local name, found = text:gsub("%s*%d+%s*/%s*%d+%s*$", "")
    if found == 0 then
        local lead, n = text:gsub("^%s*%d+%s*/%s*%d+%s+", "")
        if n == 0 then return text end
        return lead
    end
    name = name:gsub("%s+$", "")
    for i = 1, #NAME_SEPARATORS do
        local sep = NAME_SEPARATORS[i]
        if name:sub(-#sep) == sep then
            name = name:sub(1, -#sep - 1):gsub("%s+$", "")
            break
        end
    end
    if name == "" then return text end
    return name
end

local function indexItem(text, entry)
    local key = objectiveItemName(text):lower()
    local list = itemQuests[key]
    if not list then list = {}; itemQuests[key] = list end
    list[#list + 1] = entry
end

-- Read at call time from Provider.lua, so the map pins and the mob table share one kind map with no load-order dependency
local function kindType(k) return ns.QUEST_KIND_TYPE and ns.QUEST_KIND_TYPE[k] end

local function rebuildCache()
    wipe(activeQuests)
    wipe(questObjList)
    wipe(questObjSlot)
    wipe(npcQuests)
    wipe(itemQuests)
    if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then
        return
    end
    local rows, last = ns.Compat.CollectQuestLog(_logRows)
    for i = 1, last do
        local info = rows[i]
        if info and not info.isHeader and info.questID and info.title then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            if objectives then
                local itemTexture
                if GetQuestLogSpecialItemInfo then
                    local _, tex = GetQuestLogSpecialItemInfo(i)
                    itemTexture = tex
                end
                local objMap, objList, objSlot
                local typeSeen = {}
                for _, o in ipairs(objectives) do
                    -- Finished objectives count too, so one completing never renumbers the rest under the mob table's index
                    local otype = o.type
                    local slot
                    if otype then
                        slot = typeSeen[otype] or 0
                        typeSeen[otype] = slot + 1
                    end
                    local text = (not o.finished) and o.text
                    if text and text ~= "" then
                        local entry
                        if o.type == "progressbar" then
                            local p = tonumber(text:match("([%d%.]+)%%"))
                            if p and p <= 100 then
                                entry = { value = math.ceil(100 - p), isPercent = true }
                            end
                        else
                            local need, have = o.numRequired, o.numFulfilled
                            if need and have then
                                local diff = math.floor(need - have)
                                if diff > 0 then entry = { value = diff, isPercent = false } end
                            end
                        end
                        if entry then
                            entry.type        = objType(text, itemTexture, otype)
                            entry.itemTexture = itemTexture
                            -- Carried for the tooltip, which names the objective and looks up the group's progress on it
                            entry.text        = text
                            entry.title       = info.title
                            entry.questID     = info.questID
                            entry.otype       = otype
                            entry.slot        = slot
                            objMap = objMap or {}
                            objMap[text] = entry
                            objList = objList or {}
                            objList[#objList + 1] = entry
                            if otype == "item" then indexItem(text, entry) end
                        end
                    end
                    -- A finished objective is false, not a gap, so its mob never falls back to another objective it does not serve
                    if slot then
                        objSlot = objSlot or {}
                        local byIdx = objSlot[otype]
                        if not byIdx then byIdx = {}; objSlot[otype] = byIdx end
                        byIdx[slot] = (text and text ~= "" and objMap and objMap[text]) or false
                    end
                end
                if objMap then
                    activeQuests[info.title] = objMap
                    questObjList[info.questID] = objList
                    questObjSlot[info.questID] = objSlot
                end
            end
        end
    end

    -- Inverted over the quest log only, so a nameplate is one lookup. Absent on retail
    local mobsByQuest = ns.CLASSIC_QUEST_NPCS
    if not mobsByQuest then return end
    for questID in pairs(questObjList) do
        local list = mobsByQuest[questID]
        if list then
            for i = 1, #list do
                local v = list[i]
                local creatureID = v % 10000000
                local t = npcQuests[creatureID]
                if not t then t = {}; npcQuests[creatureID] = t end
                t[#t + 1] = {
                    quest = questID,
                    slot  = math.floor(v / 100000000),
                    otype = kindType(math.floor((v % 100000000) / 10000000)),
                }
            end
        end
    end
end

local _scanSeen = {}

-- Vehicles share the creature id space and can carry objectives, so only Creature and Vehicle GUIDs count
local function creatureIDFromUnit(unit)
    local guid = UnitGUID(unit)
    if not (guid and ok(guid)) then return nil end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    return tonumber(id)
end

-- Each row names one objective, so a mob claims one icon per objective it serves
local function scanByCreature(unit, out)
    local creatureID = creatureIDFromUnit(unit)
    local rows = creatureID and npcQuests[creatureID]
    if not rows then return 0 end
    wipe(_scanSeen)
    local count = 0
    for i = 1, #rows do
        local row = rows[i]
        local byType = row.otype and questObjSlot[row.quest]
        local byIdx  = byType and byType[row.otype]
        local entry
        if byIdx then
            -- false is a finished objective and nil an index past the client's list, and neither guesses another objective
            entry = byIdx[row.slot] or nil
        else
            -- No objectives of this type to line up against, so show the quest's first open one
            local list = questObjList[row.quest]
            entry = list and list[1]
        end
        if entry and not _scanSeen[entry] then
            _scanSeen[entry] = true
            count = count + 1
            out[count] = entry
            if count >= MAX_ICON_SLOTS then return count end
        end
    end
    return count
end

local function scanInto(unit, out)
    wipe(out)
    -- Era and TBC unit tooltips carry no quest lines (measured), so the creature id is the route there. Retail and Forever read the tooltip
    if not ns.Has.TooltipDataUnit then return scanByCreature(unit, out) end
    local data = C_TooltipInfo.GetUnit(unit)
    local lines = data and data.lines
    if not lines then return 0 end

    -- Dedup by entry instead of filtering the QuestPlayer line, as objMap only holds your own quests, so a party member's line can only echo one of yours
    wipe(_scanSeen)
    local count, objMap = 0, nil
    for i = 2, #lines do
        local line = lines[i]
        local text = line and line.leftText
        if ok(text) and text and text ~= "" then
            local lt = line.type
            if lt == QUEST_TITLE then
                objMap = activeQuests[text]
            elseif lt == QUEST_OBJECTIVE and objMap then
                local entry = objMap[text]
                if entry and not _scanSeen[entry] then
                    _scanSeen[entry] = true
                    count = count + 1
                    out[count] = entry
                end
            end
        end
    end
    return count
end

local MEDIA   = "Interface\\AddOns\\EverythingQuests\\Media\\Textures\\"
local EQ_LOGO = MEDIA .. "eq-logo-v3.tga"
-- The world quest pins' round mask, so a square Blizzard icon reads as a marker rather than an aura
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The two Blizzard icons were checked present, and the same art, on Era, TBC, WoW Forever and retail
local KILL_ICONS = {
    skull  = { tex = MEDIA .. "skull.tga" },
    badge  = { tex = MEDIA .. "slay.tga" },
    swords = { tex = "Interface\\Icons\\Ability_DualWield", round = true },
}
local LOOT_ICONS = {
    logo  = { tex = EQ_LOGO },
    badge = { tex = MEDIA .. "loot.tga" },
    pack  = { tex = "Interface\\Icons\\INV_Misc_Bag_07", round = true },
}
local CHAT_ICON = { tex = "Interface\\WorldMap\\ChatBubble_64.PNG", coord = { 0, 0.5, 0.5, 1 } }
-- The same art on all four clients, unlike the elite dragon and the rare mob marks
local BOSS_ICON = { atlas = "bossbanner-skullcircle" }
local ELITE_LOOKS = { none = true, crown = true, ring = true, boss = true }
local CROWN_TEX, RING_TEX = MEDIA .. "np-crown.tga", MEDIA .. "np-ring.tga"
-- Sized to tools/gen_npmarkers.py's art, so the ring's dark inner line falls just inside the icon's edge
local CROWN_SCALE, CROWN_SINK, RING_SCALE = 0.46, 0.20, 1.25

-- A find is remembered, as each GetAtlasInfo answer is a new table. A miss answers nil and costs nothing to ask again
local bossArtFound = false
local function hasBossArt()
    if bossArtFound then return true end
    local get = C_Texture and C_Texture.GetAtlasInfo
    bossArtFound = (get and get(BOSS_ICON.atlas) ~= nil) and true or false
    return bossArtFound
end

local function choices()
    local DB = ns:GetSubsystem("DB")
    local g = (DB and DB.db.profile.general) or {}
    local look = ELITE_LOOKS[g.npEliteLook] and g.npEliteLook or "crown"
    if look == "boss" and not hasBossArt() then look = "crown" end
    return KILL_ICONS[g.npKillIcon] or KILL_ICONS.skull, LOOT_ICONS[g.npLootIcon] or LOOT_ICONS.logo, look
end

-- Elites and bosses outside instances, bosses only inside, where nearly every mob is elite
local function eliteMarked(unit, hostile)
    if not (hostile and unit and UnitClassification) then return false end
    local c = UnitClassification(unit)
    if not ok(c) then return false end
    if c == "worldboss" then return true end
    if UnitIsBossMob then
        local boss = UnitIsBossMob(unit)
        if ok(boss) and boss == true then return true end
    end
    if c ~= "elite" and c ~= "rareelite" then return false end
    local inside = IsInInstance and IsInInstance()
    if not ok(inside) then return false end
    return not inside
end

local function setRound(ic, round)
    if round == (ic.masked or false) then return end
    local mask = ic.mask
    if not mask then
        local parent = ic:GetParent()
        if not (parent.CreateMaskTexture and ic.AddMaskTexture) then return end
        mask = parent:CreateMaskTexture()
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(ic)
        ic.mask = mask
    end
    if round then ic:AddMaskTexture(mask) else ic:RemoveMaskTexture(mask) end
    ic.masked = round
end

local function paint(ic, def, itemTexture, roundItem)
    if def and def.atlas then
        setRound(ic, false)
        ic:SetAtlas(def.atlas)
    elseif itemTexture then
        -- Round inside a ring, which the square item's corners would otherwise poke past
        setRound(ic, roundItem and true or false)
        ic:SetTexture(itemTexture); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    else
        def = def or LOOT_ICONS.logo
        -- Masked before the slice, the order Blizzard's RingedFrameTemplate.lua uses
        setRound(ic, def.round and true or false)
        ic:SetTexture(def.tex)
        if def.round then ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        elseif def.coord then ic:SetTexCoord(unpack(def.coord))
        else ic:SetTexCoord(0, 1, 0, 1) end
    end
end

local function decorate(ic, ring, crown, size)
    if ring then
        local r = ic.ring
        if not r then
            r = ic:GetParent():CreateTexture(nil, "OVERLAY", nil, 1)
            r:SetTexture(RING_TEX)
            ic.ring = r
        end
        r:ClearAllPoints()
        r:SetSize(size * RING_SCALE, size * RING_SCALE)
        r:SetPoint("CENTER", ic, "CENTER")
        r:Show()
    elseif ic.ring then
        ic.ring:Hide()
    end
    if crown then
        local c = ic.crown
        if not c then
            c = ic:GetParent():CreateTexture(nil, "OVERLAY", nil, 2)
            c:SetTexture(CROWN_TEX)
            ic.crown = c
        end
        c:ClearAllPoints()
        c:SetSize(size * CROWN_SCALE, size * CROWN_SCALE)
        c:SetPoint("BOTTOM", ic, "TOP", 0, -size * CROWN_SINK)
        c:Show()
    elseif ic.crown then
        ic.crown:Hide()
    end
end

local function clearSlot(ic)
    ic:Hide()
    ic.text:SetText("")
    ic.text:Hide()
    if ic.ring then ic.ring:Hide() end
    if ic.crown then ic.crown:Hide() end
end

local function place(f, ic, x, def, itemTexture, ring, crown, iconSize, textSize, label)
    ic:SetSize(iconSize, iconSize)
    ic.text:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    paint(ic, def, itemTexture, ring)
    local pad = ring and math.floor(iconSize * (RING_SCALE - 1) / 2 + 0.5) or 0
    ic:ClearAllPoints()
    ic:SetPoint("LEFT", f, "LEFT", x + pad, 0)
    ic:Show()
    decorate(ic, ring, crown, iconSize)
    local advance = iconSize + 2 * pad
    ic.text:ClearAllPoints()
    ic.text:SetPoint("LEFT", ic, "RIGHT", 2 + pad, 0)
    if label then
        ic.text:SetText(label)
        ic.text:Show()
        advance = advance + 2 + textWidth(ic.text, label, textSize)
    end
    return x + advance + SPACING
end

local function buildSlot(frame, iconSize, textSize)
    local ic = frame:CreateTexture(nil, "OVERLAY")
    ic:SetSize(iconSize, iconSize)
    ic:Hide()
    ic.text = frame:CreateFontString(nil, "OVERLAY")
    ic.text:SetFont(STANDARD_TEXT_FONT, textSize, "OUTLINE")
    ic.text:SetTextColor(1, 0.94, 0.6)
    ic.text:SetPoint("LEFT", ic, "RIGHT", 2, 0)
    ic.text:Hide()
    return ic
end

local function getIconFrame(plate, unit)
    local f = plate.EQQuestIcons
    if f then return f end
    local iconSize, textSize, placement, offX, offY = cfg()
    f = CreateFrame("Frame", nil, plate)
    f:SetFrameStrata("HIGH")
    f:SetSize(iconSize, iconSize)
    anchorFrame(f, plate, placement, offX, offY, unit)
    f.slots = {}
    for i = 1, MAX_ICON_SLOTS do f.slots[i] = buildSlot(f, iconSize, textSize) end
    plate.EQQuestIcons = f
    return f
end

local function hideFrame(plate)
    local f = plate and plate.EQQuestIcons
    if not f then return end
    for i = 1, #f.slots do clearSlot(f.slots[i]) end
    f:Hide()
    f.guid, f.hostile = nil, nil
end

local function render(plate, list, count, hostile, unit)
    local f = getIconFrame(plate, unit)
    -- Re-read size and placement every pass, as Blizzard pools nameplates and a frame recycled while off-screen carries stale option values
    local iconSize, textSize, placement, offX, offY = cfg()
    anchorFrame(f, plate, placement, offX, offY, unit)
    f:SetHeight(iconSize)
    f.hostile = hostile and true or false
    for i = 1, #f.slots do clearSlot(f.slots[i]) end
    if not count or count == 0 then f:Hide(); return end

    local killDef, lootDef, look = choices()
    local marked = look ~= "none" and eliteMarked(unit, hostile)
    local x, shown = 0, 0
    for i = 1, count do
        local q = list[i]
        if q and (q.isPercent or (q.value and q.value > 0)) then
            local ic = f.slots[shown + 1]
            if not ic then break end
            shown = shown + 1

            -- The keywords match only English, so an unattackable unit is someone to talk to and an attackable one that no keyword matched is a kill. Item objectives and a usable item keep theirs
            local qtype = q.type
            if not hostile then
                if qtype ~= "LOOT" and qtype ~= "ITEM" then qtype = "CHAT" end
            elseif qtype == "DEFAULT" then
                qtype = "KILL"
            end

            local def, item
            if qtype == "KILL" then
                def = (marked and look == "boss") and BOSS_ICON or killDef
            elseif qtype == "LOOT" then
                def = lootDef
            elseif qtype == "CHAT" then
                def = CHAT_ICON
            elseif qtype == "ITEM" then
                item = q.itemTexture
            end
            local mark = marked and qtype ~= "CHAT"
            local ring = mark and (look == "ring" or (look == "boss" and qtype ~= "KILL"))
            local crown = mark and look == "crown"

            local label
            if q.isPercent or (q.value and q.value > 1) then
                label = q.isPercent and (q.value .. "%") or tostring(q.value)
            end
            x = place(f, ic, x, def, item, ring, crown, iconSize, textSize, label)
        end
    end

    if shown > 0 then
        f:SetWidth(math.max(1, x - SPACING))
        f:Show()
    else
        f:Hide()
    end
end

local PICKS = {
    npKillIcon  = { KILL_ICONS,  "skull" },
    npLootIcon  = { LOOT_ICONS,  "logo" },
    npEliteLook = { ELITE_LOOKS, "crown" },
}

-- A saved pick the tables no longer know reads as its default, so the dropdown never shows a raw key
function QI:Picked(key)
    local pick = PICKS[key]
    if not pick then return nil end
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.general[key]
    if v ~= nil and pick[1][v] then
        if v == "boss" and not hasBossArt() then return "crown" end
        return v
    end
    return pick[2]
end

function QI:PaintSample(frame, iconSize)
    frame.slots = frame.slots or {}
    for i = 1, 3 do
        frame.slots[i] = frame.slots[i] or buildSlot(frame, iconSize, DEFAULT_TEXT)
        clearSlot(frame.slots[i])
    end
    local killDef, lootDef, look = choices()
    local gap = math.floor(iconSize * 0.5 + 0.5)
    local x = place(frame, frame.slots[1], 0, killDef, nil, false, false, iconSize, DEFAULT_TEXT) + gap
    x = place(frame, frame.slots[2], x, lootDef, nil, false, false, iconSize, DEFAULT_TEXT) + gap
    if look ~= "none" then
        x = place(frame, frame.slots[3], x, look == "boss" and BOSS_ICON or killDef, nil,
                  look == "ring", look == "crown", iconSize, DEFAULT_TEXT) + gap
    end
    return x - SPACING - gap
end

-- Read by /eqsprobe tooltip, so a missing marker can be told from a mob that is not elite
function QI:DescribeUnit(unit)
    if not unit then return nil end
    local c = UnitClassification and UnitClassification(unit)
    local boss = UnitIsBossMob and UnitIsBossMob(unit)
    local inside = IsInInstance and IsInInstance()
    local hostile = UnitCanAttack and UnitCanAttack("player", unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    local f = plate and plate.EQQuestIcons
    local _, _, look = choices()
    local function show(v) return ok(v) and tostring(v) or "secret" end
    return ("classification=%s bossMob=%s inInstance=%s attackable=%s look=%s marked=%s anchor=%s rival=%s"):format(
        show(c), UnitIsBossMob and show(boss) or "absent", show(inside), show(hostile), look,
        tostring(look ~= "none" and eliteMarked(unit, hostile)),
        (isShown(f) and f.anchorName) or "no icons shown",
        tostring(rivalAddon()))
end

local activePlates = {}

local function updatePlate(unit, event)
    if not (QI.enabled and unit) then return end
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    if UnitIsPlayer(unit) then hideFrame(plate); return end

    local guid = UnitGUID(unit)
    if not ok(guid) then return end

    local f = getIconFrame(plate, unit)
    f.list = f.list or {}
    local count
    if f.guid ~= guid then
        f.guid = guid
        count = scanInto(unit, f.list)
        f.count = count
    elseif event == "QUEST_LOG_UPDATE" then
        count = scanInto(unit, f.list)
        f.count = count
    else
        count = f.count
    end
    render(plate, f.list, count, UnitCanAttack("player", unit), unit)
end

local function refreshAllPlates(event)
    for unit in pairs(activePlates) do updatePlate(unit, event) end
end

local function questLogRefresh()
    rebuildCache()
    refreshAllPlates("QUEST_LOG_UPDATE")
end

-- A nameplate addon can hide Blizzard's unit frame or add its own bar in its handler after EQ's, so the anchor is read again a frame later
local _recheck, _recheckQueued = {}, false
local function recheckAnchors()
    _recheckQueued = false
    local _, _, placement, offX, offY = cfg()
    for unit in pairs(_recheck) do
        _recheck[unit] = nil
        local plate = activePlates[unit] and C_NamePlate.GetNamePlateForUnit(unit)
        local f = plate and plate.EQQuestIcons
        if f then anchorFrame(f, plate, placement, offX, offY, unit) end
    end
end

local function queueRecheck(unit)
    _recheck[unit] = true
    if not _recheckQueued then
        _recheckQueued = true
        C_Timer.After(0, recheckAnchors)
    end
end

local function onPlateAdded(_, unit)
    if not unit then return end
    activePlates[unit] = true
    updatePlate(unit, "NAME_PLATE_UNIT_ADDED")
    queueRecheck(unit)
end
-- A unit turning hostile or friendly keeps its plate, and EllesmereUI swaps its own bar on a flag or name change, and outside instances on a faction change too
local function onUnitChanged(event, unit)
    if not (unit and activePlates[unit]) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local f = plate and plate.EQQuestIcons
    if f and f.hostile ~= nil and f.hostile ~= (UnitCanAttack("player", unit) and true or false) then updatePlate(unit, event) end
    if _G.EllesmereNameplates_NS then queueRecheck(unit) end
end
local function onPlateRemoved(_, unit)
    if not unit then return end
    activePlates[unit] = nil
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    hideFrame(plate)
end
local function onQuestLogUpdate()
    local Events = ns:GetSubsystem("Events")
    if Events and Events.Throttle then
        Events:Throttle("nameplateQuestIcons", 0.5, questLogRefresh)
    else
        questLogRefresh()
    end
end

local CACHE_EVENTS = {
    QUEST_LOG_UPDATE = onQuestLogUpdate,
    QUEST_ACCEPTED   = onQuestLogUpdate,
    QUEST_REMOVED    = onQuestLogUpdate,
}
local PLATE_EVENTS = {
    NAME_PLATE_UNIT_ADDED   = onPlateAdded,
    NAME_PLATE_UNIT_REMOVED = onPlateRemoved,
    UNIT_FACTION            = onUnitChanged,
    UNIT_FLAGS              = onUnitChanged,
    UNIT_NAME_UPDATE        = onUnitChanged,
}

-- One cache for the nameplate icons and the tooltip lines, so the two never describe an objective differently
local _holders, _holderCount = {}, 0

function QI:HoldCache(id, want)
    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    want = want and true or false
    -- A repeated call returns here so each consumer counts once toward the holder count
    if (_holders[id] and true or false) == want then return end
    _holders[id] = want or nil
    _holderCount = _holderCount + (want and 1 or -1)

    if want and _holderCount == 1 then
        for event, fn in pairs(CACHE_EVENTS) do Events:On(event, fn) end
        rebuildCache()
    elseif (not want) and _holderCount == 0 then
        for event, fn in pairs(CACHE_EVENTS) do Events:Off(event, fn) end
        wipe(activeQuests)
        wipe(questObjList)
        wipe(questObjSlot)
        wipe(npcQuests)
        wipe(itemQuests)
    end
end

-- The same scan the plates run, so the tooltip names the objective the icon is counting.
function QI:UnitObjectives(unit, out)
    if not unit then wipe(out); return 0 end
    return scanInto(unit, out)
end

function QI:CreatureID(unit)
    return unit and creatureIDFromUnit(unit) or nil
end

-- Matched on the client's own objective text, so it works in every language with no shipped name table
function QI:ItemObjectives(itemName, out)
    wipe(out)
    if type(itemName) ~= "string" or itemName == "" then return 0 end
    local list = itemQuests[itemName:lower()]
    if not list then return 0 end
    for i = 1, #list do out[i] = list[i] end
    return #list
end

-- Read by /eqsprobe tooltip. An empty index and an unheld cache look identical from outside.
function QI:CacheHeld()
    return _holderCount > 0
end
function QI:IndexedItemNames()
    local n = 0
    for _ in pairs(itemQuests) do n = n + 1 end
    return n
end

-- The objective text, not the lowercased key, so /eqsprobe names something the player can look for
function QI:WantedItems(out, max)
    local n = 0
    for _, list in pairs(itemQuests) do
        local e = list[1]
        if e and e.text then
            n = n + 1
            out[n] = e.text
            if max and n >= max then return n end
        end
    end
    return n
end

function QI:IsEnabled()
    local DB = ns:GetSubsystem("DB")
    local v = DB and DB.db.profile.general.questNameplateIcons
    if v == nil then return not rivalAddon() end
    return v and true or false
end

function QI:ApplyEnabled()
    local on = self:IsEnabled()
    if on == self.enabled then return end
    self.enabled = on

    self:HoldCache("nameplates", on)

    local Events = ns:GetSubsystem("Events")
    if not Events then return end
    if on then
        for event, fn in pairs(PLATE_EVENTS) do Events:On(event, fn) end
        if C_NamePlate and C_NamePlate.GetNamePlates then
            for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
                local unit = plate.namePlateUnitToken
                if unit then activePlates[unit] = true end
            end
        end
        refreshAllPlates("ENABLE")
    else
        for event, fn in pairs(PLATE_EVENTS) do Events:Off(event, fn) end
        for unit in pairs(activePlates) do
            local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
            hideFrame(plate)
        end
        wipe(activePlates)
    end
end

function QI:ApplyLayout()
    if not self.enabled then return end
    refreshAllPlates("LAYOUT")
end

function QI:OnEnable()
    self.enabled = false
    self:ApplyEnabled()

    -- Uses EQ's own Dialog (not Blizzard StaticPopup) to stay clear of the Quit/Logout taint.
    local DB = ns:GetSubsystem("DB")
    local g  = DB and DB.db.profile.general
    local rival = rivalAddon()
    if g and g.questNameplateIcons == nil and not g.npConflictAsked and rival then
        g.npConflictAsked = true
        C_Timer.After(4, function()
            local Dialog = ns:GetSubsystem("Dialog")
            if not Dialog then return end
            Dialog:Show({
                title = "Everything Quests",
                text = ns.L["Everything Quests can show quest icons on nameplates, with how many of each you still need.\n\n%s is installed and shows quest icons of its own, so the Everything Quests icons are off for now, to avoid showing two of each. Which would you like to use?"]:format(rival),
                button1 = "Everything Quests",
                button2 = rival,
                onAccept = function()
                    g.questNameplateIcons = true
                    QI:ApplyEnabled()
                end,
                onCancel = function()
                    g.questNameplateIcons = false
                    QI:ApplyEnabled()
                end,
            })
        end)
    end
end
