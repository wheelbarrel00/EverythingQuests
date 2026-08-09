-- LibMapPinHandler — taint-isolation proxy for MapCanvas data providers.
--
-- Why this exists:
--   When an addon calls WorldMapFrame:AddDataProvider(provider), the provider
--   is appended to the canvas's `dataProviders` table. Blizzard's
--   RefreshAllDataProviders / OnMapChanged then iterate that table via
--   secureexecuterange. Once an addon has touched it, secureexecuterange
--   asserts on the addon-tainted entries — surfacing as
--   "Blizzard_MapCanvas.lua:280: assertion failed!" with a stack rooted in
--   secureexecuterange. Disabling the addon makes the assertion go away;
--   nothing the provider's own code does will fix it because the taint is in
--   the table membership itself.
--
-- The pattern:
--   We build a parallel "shadow canvas" — an object that mimics the bits of
--   MapCanvasMixin a data provider needs (AcquirePin, SetPinTemplateType,
--   pinPools, etc.) but maintains its OWN dataProviders list. We then hook
--   Blizzard's canvas events (RefreshAllDataProviders, OnMapChanged, OnShow,
--   OnHide, …) and dispatch to OUR providers from the hook. Blizzard's
--   secureexecuterange only ever iterates Blizzard's clean table.
--
-- Public API:
--   local Lib = LibStub("LibMapPinHandler-1.0")
--   local shadow = Lib:GetShadowCanvas(WorldMapFrame)
--   shadow:AddDataProvider(myProvider)              -- same calling pattern
--   -- inside myProvider, self:GetMap() returns the shadow; AcquirePin works.
--
-- Bracket access (Lib[WorldMapFrame]) is also supported as an alternate
-- access pattern.

local MAJOR, MINOR = "LibMapPinHandler-1.0", 2
local Lib = LibStub:NewLibrary(MAJOR, MINOR)
if not Lib then return end

-- Build a closure that delegates calls back to the shadow canvas. Used so
-- hooksecurefunc fires our shadow's method when Blizzard's canvas method runs.
local function trampoline(canvas, methodName)
    return function(_self, ...) return canvas[methodName](canvas, ...) end
end

-- ─── Shadow-canvas mixin ───────────────────────────────────────────────
-- We borrow the mechanical pin-management methods from MapCanvasMixin so
-- providers calling self:GetMap():AcquirePin(...) reach a real pin pool.
-- Anything user-facing or coupled to Blizzard's internal state is
-- re-implemented as a passthrough below.
local ShadowCanvas = {}
local borrow = {
    "OnShow", "OnHide", "RefreshAllDataProviders",
    "CallMethodOnPinsAndDataProviders", "ReapplyPinFrameLevels", "SetGlobalPinScale",
    "AddDataProvider", "SetPinTemplateType",
    "EnumeratePinsByTemplate", "RemoveAllPinsByTemplate", "EnumerateAllPins",
    "AcquirePin", "RemovePin", "SetPinPosition",
    "GetCanvasScale", "GetCanvasZoomPercent", "ApplyPinPosition",
    "GetGlobalPinScale", "ExecuteOnAllPins", "CallMethodOnDataProviders",
    "GetPinTemplateType", "RegisterPin", "UnregisterPin",
}
for _, name in ipairs(borrow) do ShadowCanvas[name] = MapCanvasMixin[name] end

function ShadowCanvas:OnLoad(ownerMap)
    self.ownerMap = ownerMap

    -- MapCanvasMixin's pin methods rely on CallbackRegistry being initialized.
    -- Newer clients renamed it to CallbackRegistryMixin; older ones used
    -- CallbackRegistryBaseMixin. Both expose OnLoad with the same shape.
    local registry = CallbackRegistryMixin or CallbackRegistryBaseMixin
    registry.OnLoad(self)

    self.dataProviders            = {}
    self.dataProviderEventsCount  = {}
    self.pinPools                 = {}
    self.pinTemplateTypes         = {}
    self.ScrollContainer          = ownerMap.ScrollContainer

    -- Hook Blizzard's canvas lifecycle so our parallel provider list updates
    -- in lockstep with theirs. Each hook bridges to our same-named method.
    hooksecurefunc(ownerMap, "OnShow",                          trampoline(self, "OnShow"))
    hooksecurefunc(ownerMap, "OnHide",                          trampoline(self, "OnHide"))
    hooksecurefunc(ownerMap, "RefreshAllDataProviders",         trampoline(self, "RefreshAllDataProviders"))
    hooksecurefunc(ownerMap, "CallMethodOnPinsAndDataProviders", trampoline(self, "CallMethodOnPinsAndDataProviders"))
    hooksecurefunc(ownerMap, "ReapplyPinFrameLevels",           trampoline(self, "ReapplyPinFrameLevels"))
    hooksecurefunc(ownerMap, "SetGlobalPinScale",               trampoline(self, "SetGlobalPinScale"))
    hooksecurefunc(ownerMap, "OnMapChanged",                    trampoline(self, "OnMapChanged"))
end

local function dispatchMapChanged(provider) provider:OnMapChanged() end
function ShadowCanvas:OnMapChanged()
    secureexecuterange(self.dataProviders, dispatchMapChanged)
end

-- Passthroughs to the underlying real canvas. These cannot be borrowed from
-- MapCanvasMixin because they rely on Blizzard's internal members (canvas
-- frame, scroll container, lock-reasons), which we don't replicate.
function ShadowCanvas:GetOwner()                                 return self.ownerMap                                       end
function ShadowCanvas:GetCanvas()                                return self.ownerMap:GetCanvas()                           end
function ShadowCanvas:GetCanvasContainer()                       return self.ownerMap:GetCanvasContainer()                  end
function ShadowCanvas:GetMapID()                                 return self.ownerMap:GetMapID()                            end
function ShadowCanvas:EvaluateLockReasons()                                                                                 end
function ShadowCanvas:GetPinFrameLevelsManager()                 return self.ownerMap.pinFrameLevelsManager                 end

-- MEASURED 2026-08-09: ProcessGlobalPinMouseActionHandlers is nil on Classic Era 1.15.9 and a
-- function on retail, so this passthrough would raise there rather than no-op. Guarded so a
-- flavor without the handler loses the passthrough and not the pin.
function ShadowCanvas:ProcessGlobalPinMouseActionHandlers(...)
    if not self.ownerMap.ProcessGlobalPinMouseActionHandlers then return end
    return self.ownerMap:ProcessGlobalPinMouseActionHandlers(...)
end

-- ─── Public access ─────────────────────────────────────────────────────
local cache = {}                            -- frame -> shadow canvas (1:1, lifetime-of-session)

function Lib:GetShadowCanvas(frame)
    if not (frame and type(frame) == "table" and frame.GetObjectType) then return nil end
    local sc = cache[frame]
    if not sc then
        sc = CreateFromMixins(ShadowCanvas)
        sc:OnLoad(frame)
        cache[frame] = sc
    end
    return sc
end

setmetatable(Lib, {
    __index = function(self, key)
        if key and type(key) == "table" and key.GetObjectType then
            return self:GetShadowCanvas(key)
        end
    end,
})

return Lib
