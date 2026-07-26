local _, ns = ...

local DBmod = ns:RegisterSubsystem("ChainGuideDatabase", {})

DBmod.expansions = {}
DBmod.categories = {}
DBmod.chains = {}

function DBmod:RegisterExpansion(id, def) self.expansions[id] = def end
function DBmod:RegisterCategory(id, def)  self.categories[id]  = def end
function DBmod:RegisterChain(id, def)
    def.id = id
    self.chains[id] = def
end

function DBmod:CurrentCharacter()
    if self._char then return self._char end
    local _, classFile = UnitClass and UnitClass("player")
    local _, raceFile  = UnitRace and UnitRace("player")
    self._char = {
        faction = UnitFactionGroup and UnitFactionGroup("player"),
        class   = classFile,
        race    = raceFile,
    }
    return self._char
end

function DBmod:NormalizeChain(chain)
    if not chain or chain._normalized then return chain end
    chain._normalized = true
    if not chain.items then
        local items = {}
        local quests = chain.quests or {}
        for i = 1, #quests do
            items[i] = {
                type = "quest",
                id   = quests[i],
                x    = 0,
                y    = i - 1,
                connections = (i > 1) and { i - 1 } or nil,
            }
        end
        chain.items = items
    end
    self:ApplyOverlay(chain)
    return chain
end

function DBmod:ApplyOverlay(chain)
    if not chain or chain._overlayApplied then return end
    local items = chain.items
    if not items or #items == 0 then return end          -- don't latch _overlayApplied - retry when items arrive
    local overlays = ns.CHAINGUIDE_OVERLAYS
    local overlay  = overlays and (overlays[chain.questlineID] or overlays[chain.id])
    if not overlay then chain._overlayApplied = true; return end

    local idIndex = {}
    for i = 1, #items do
        local it = items[i]
        if it and it.id then idIndex[it.id] = i end
    end

    if overlay.layout then
        for qid, lay in pairs(overlay.layout) do
            local idx = idIndex[qid]
            if idx then
                local it = items[idx]
                if lay.x ~= nil then it.x = lay.x end
                if lay.y ~= nil then it.y = lay.y end
                if lay.optional   ~= nil then it.optional   = lay.optional end
                if lay.breadcrumb ~= nil then it.breadcrumb = lay.breadcrumb end
            end
        end
    end

    if overlay.connections then
        for qid, prereqs in pairs(overlay.connections) do
            local idx = idIndex[qid]
            if idx then
                local conn = {}
                for j = 1, #prereqs do
                    local pidx = idIndex[prereqs[j]]
                    if pidx then conn[#conn + 1] = pidx end
                end
                if #conn > 0 then items[idx].connections = conn end
            end
        end
    end

    if overlay.embed then
        for e = 1, #overlay.embed do
            local em = overlay.embed[e]
            if em and em.chainID then
                local node = { type = "chain", id = em.chainID, x = em.x, y = em.y }
                if em.connections then
                    local conn = {}
                    for j = 1, #em.connections do
                        local pidx = idIndex[em.connections[j]]
                        if pidx then conn[#conn + 1] = pidx end
                    end
                    if #conn > 0 then node.connections = conn end
                end
                items[#items + 1] = node
            end
        end
    end

    chain._overlayApplied = true
end

function DBmod:GetVariation(item, character)
    if not item.variations then return item end
    character = character or self:CurrentCharacter()
    for i = 1, #item.variations do
        local v = item.variations[i]
        if self:RestrictionsMatch(v.restrictions, character) then
            return {
                type        = v.type or item.type,
                id          = v.id   or item.id,
                name        = v.name or item.name,
                x           = item.x,
                y           = item.y,
                connections = item.connections,
                breadcrumb  = item.breadcrumb,
                optional    = item.optional,
                _variant    = true,
            }
        end
    end
    return item
end

function DBmod:RestrictionsMatch(r, c)
    if not r then return true end
    if r.faction and r.faction ~= c.faction then return false end
    if r.race    and r.race    ~= c.race    then return false end
    if r.class   and r.class   ~= c.class   then return false end
    return true
end
