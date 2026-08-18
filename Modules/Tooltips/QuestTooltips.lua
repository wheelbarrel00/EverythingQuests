local _, ns = ...

local QT = ns:RegisterSubsystem("QuestTooltips", {})

-- The same ceiling the nameplate icons use, so a mob never lists more on its tooltip than it
-- shows on its plate.
local MAX_QUESTS = 4

local TITLE_R, TITLE_G, TITLE_B = 1.00, 0.82, 0.00
local OBJ_R,   OBJ_G,   OBJ_B   = 0.85, 0.85, 0.85

local _entries    = {}
local _seenTitles = {}

-- Read by /eqsprobe tooltip. A route that installed and never fires reads exactly like a route
-- that was never installed, and the two have nothing in common to fix.
QT.route     = "none"
QT.unitCalls, QT.unitLines = 0, 0
QT.itemCalls, QT.itemLines = 0, 0

local function wanted()
    local DB = ns:GetSubsystem("DB")
    return not DB or DB.db.profile.general.questTooltips ~= false
end

-- The nameplate module owns the quest objective cache and its creature inversion. Asking it
-- rather than building a second one is what keeps a mob's plate and its tooltip agreeing.
local function objectiveCache()
    return ns:GetSubsystem("NameplateQuestIcons")
end

-- The tooltip is not touched until a line is certain, so a quest with nothing outstanding
-- cannot leave a stray blank separator behind.
local function addLines(tooltip, n)
    if n <= 0 then return 0 end
    wipe(_seenTitles)
    local added = 0
    for i = 1, n do
        local e = _entries[i]
        if e and e.title and e.text then
            if added == 0 then tooltip:AddLine(" ") end
            if not _seenTitles[e.title] then
                _seenTitles[e.title] = true
                tooltip:AddLine(e.title, TITLE_R, TITLE_G, TITLE_B)
            end
            tooltip:AddLine("- " .. e.text, OBJ_R, OBJ_G, OBJ_B)
            added = added + 1
            if added >= MAX_QUESTS then break end
        end
    end
    return added
end

-- OnTooltipSetItem can fire twice for one render, which would print the same lines twice. The
-- tooltip's own line count settles it: a genuine second render has cleared what the first pass
-- added, so the count is back below where that pass ended.
local function alreadyAdded(tooltip, key)
    if tooltip.eqTooltipKey ~= key then return false end
    local n = (type(tooltip.NumLines) == "function") and tooltip:NumLines() or 0
    return n >= (tooltip.eqTooltipLines or 0)
end

local function stamp(tooltip, key)
    tooltip.eqTooltipKey   = key
    tooltip.eqTooltipLines = (type(tooltip.NumLines) == "function") and tooltip:NumLines() or 0
end

local function onUnit(tooltip)
    QT.unitCalls = QT.unitCalls + 1
    if not (tooltip and wanted()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    -- Retail's own unit tooltip already carries these lines, so EQ would print a second copy of
    -- every one. The gate is the Classic mob table's presence, never a build number - only the
    -- flavor TOCs list that file.
    if not ns.CLASSIC_QUEST_NPCS then return end
    local QI = objectiveCache()
    if not (QI and QI.UnitObjectives) then return end
    if type(tooltip.GetUnit) ~= "function" then return end

    local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
    if not ok then return end
    -- GetUnit answers a name with no token for a plain world mouseover, which is the common
    -- case here rather than an edge one.
    if not unit and UnitExists and UnitExists("mouseover") then unit = "mouseover" end
    if not unit then return end

    local guid = UnitGUID and UnitGUID(unit)
    if not guid then return end
    if alreadyAdded(tooltip, guid) then return end

    local n = QI:UnitObjectives(unit, _entries)
    local added = addLines(tooltip, n)
    QT.unitLines = QT.unitLines + added
    -- Only a pass that ADDED something may stamp. Stamping a zero-add records the tooltip's own
    -- base count, and the next render of the same unit produces that identical count, so
    -- alreadyAdded reads base >= base and refuses to look again. The quest would then never
    -- appear on a mob whose tooltip was seen before the quest was accepted.
    if added > 0 then stamp(tooltip, guid) end
end

local function onItem(tooltip)
    QT.itemCalls = QT.itemCalls + 1
    if not (tooltip and wanted()) then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local QI = objectiveCache()
    if not (QI and QI.ItemObjectives) then return end
    if type(tooltip.GetItem) ~= "function" then return end

    local ok, name = pcall(tooltip.GetItem, tooltip)
    if not (ok and type(name) == "string" and name ~= "") then return end
    if alreadyAdded(tooltip, name) then return end

    local n = QI:ItemObjectives(name, _entries)
    local added = addLines(tooltip, n)
    QT.itemLines = QT.itemLines + added
    if added > 0 then stamp(tooltip, name) end
end

-- Blizzard removed the OnTooltipSetUnit and OnTooltipSetItem scripts in the 10.0.2 tooltip
-- rewrite and replaced them with TooltipDataProcessor. Classic kept the scripts and has neither
-- TooltipDataProcessor nor C_TooltipInfo, which is why Core/Compat.lua feature-detects
-- there, so presence decides the route rather than a build number.
local function installModern()
    local P = _G["TooltipDataProcessor"]
    local T = _G["Enum"] and _G["Enum"].TooltipDataType
    if type(P) ~= "table" or type(P.AddTooltipPostCall) ~= "function" then return false end
    if not (T and T.Unit and T.Item) then return false end
    -- Committed once the surface exists. Installing one half and then falling back would hook
    -- the other surface twice and double its lines.
    QT.route = "TooltipDataProcessor"
    pcall(P.AddTooltipPostCall, T.Unit, onUnit)
    pcall(P.AddTooltipPostCall, T.Item, onItem)
    return true
end

-- Recorded per hook rather than as one flag. HookScript raises on a script the frame does not
-- have, so a partial install is a real outcome, and one that reads exactly like a full one.
QT.hooks = {}

local function installLegacy()
    local any = false
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local tip = _G[name]
        if tip and type(tip.HookScript) == "function" then
            for script, fn in pairs({ OnTooltipSetUnit = onUnit, OnTooltipSetItem = onItem }) do
                local ok = pcall(tip.HookScript, tip, script, fn)
                QT.hooks[name .. ":" .. script] = ok
                if ok then any = true end
            end
        end
    end
    if any then QT.route = "OnTooltipSet scripts" end
    return any
end

function QT:ApplyEnabled()
    local on = wanted()
    local QI = objectiveCache()
    if QI and QI.HoldCache then QI:HoldCache("tooltips", on) end
    -- HookScript cannot be undone, so the hooks go in once and the option is read per tooltip
    -- rather than being wired to the installation.
    if on and self.route == "none" then
        if not installModern() then installLegacy() end
    end
end

function QT:OnEnable()
    self:ApplyEnabled()
end
