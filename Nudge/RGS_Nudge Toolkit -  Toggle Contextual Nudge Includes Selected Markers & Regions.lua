-- @noindex
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local include_markers =  ToBoolean(reaper.GetExtState("RGS_Nudge", "include_markers"))
if include_markers then
    reaper.set_action_options(8)
else
    reaper.set_action_options(4)
end

include_markers = tostring(not include_markers)
reaper.SetExtState("RGS_Nudge", "include_markers",include_markers,true)