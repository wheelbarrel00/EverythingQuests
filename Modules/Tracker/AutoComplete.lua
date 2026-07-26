local _, ns = ...

local AC = ns:RegisterSubsystem("TrackerAutoComplete", {})

function AC:FillCompleteSet(out)
    wipe(out)
    if not GetNumAutoQuestPopUps then return out end
    for i = 1, GetNumAutoQuestPopUps() do
        local qid, popType = GetAutoQuestPopUp(i)
        if qid and popType == "COMPLETE" then out[qid] = true end
    end
    return out
end
