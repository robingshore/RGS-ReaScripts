-- @noindex
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local snap_to_unit=  ToBoolean(reaper.GetExtState("RGS_Nudge", "snap_to_unit"))
if snap_to_unit then
    reaper.set_action_options(8)
else
    reaper.set_action_options(4)
end

snap_to_unit = tostring(not snap_to_unit)


reaper.SetExtState("RGS_Nudge", "snap_to_unit", snap_to_unit,true)
