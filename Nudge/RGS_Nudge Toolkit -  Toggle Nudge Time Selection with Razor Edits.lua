-- @noindex
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local nudge_time_sel_with_razors=  ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_time_sel_with_razors"))

if nudge_time_sel_with_razors then
    reaper.set_action_options(8)
else
    reaper.set_action_options(4)
end

nudge_time_sel_with_razors = tostring(not nudge_time_sel_with_razors)
reaper.SetExtState("RGS_Nudge", "nudge_time_sel_with_razors", nudge_time_sel_with_razors,true)