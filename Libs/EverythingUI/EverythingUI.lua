local MAJOR, MINOR = "EverythingUI-1.0", 21
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local addonName = ...

-- Every later library file returns unless this names its own host, so a copy that lost
-- the version check changes nothing.
lib.host = addonName
-- Only valid because every host vendors the library at exactly Libs\EverythingUI\.
lib.media = "Interface\\AddOns\\" .. addonName .. "\\Libs\\EverythingUI\\Media\\"
