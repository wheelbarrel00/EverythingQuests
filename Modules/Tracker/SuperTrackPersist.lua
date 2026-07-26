local _, ns = ...

local STP = ns:RegisterSubsystem("TrackerSuperTrackPersist", {})

local function shouldRestore()
    local DB = ns:GetSubsystem("DB")
    return DB and DB.db.profile.general
           and DB.db.profile.general.restoreSuperTrackOnLogin == true
end

function STP:OnEnable()
    if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    local Events = ns:GetSubsystem("Events")
    if not Events then return end

    Events:On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin)
        -- Only a fresh login - /reload and zone changes must leave the current super-track untouched
        if not isInitialLogin then return end
        if shouldRestore() then return end
        C_Timer.After(0.5, function()
            C_SuperTrack.SetSuperTrackedQuestID(0)
        end)
    end)
end
