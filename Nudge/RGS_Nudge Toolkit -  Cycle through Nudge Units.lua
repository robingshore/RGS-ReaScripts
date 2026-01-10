-- @noindex
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param).."\n")
end

if reaper.HasExtState("RGS_Nudge","selected_nudge_unit") then
    local nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge","selected_nudge_unit"))
    local number_of_nudge_units = tonumber(reaper.GetExtState("RGS_Nudge","number_of_nudge_units"))
    if nudge_unit < number_of_nudge_units then

        nudge_unit = nudge_unit + 1
    else
        nudge_unit = 1
    end
    if reaper.HasExtState("RGS_Nudge","unit_"..tostring(nudge_unit).."_nudge_value") then 
        nudge_amount = tonumber(reaper.GetExtState("RGS_Nudge","unit_"..tostring(nudge_unit).."_nudge_value"))
        if not nudge_amount then
            nudge_amount = reaper.GetExtState("RGS_Nudge","unit_"..tostring(nudge_unit).."_nudge_value")
            reaper.SetExtState("RGS_Nudge","nudge_value",nudge_amount,true)
        else
            reaper.SetExtState("RGS_Nudge","nudge_value",string.format("%.17f", nudge_amount),true)
        end
    end
    reaper.SetExtState("RGS_Nudge","selected_nudge_unit", tostring(nudge_unit),true)
    reaper.SetExtState("RGS_Nudge", "follow_ruler", "false",true)
else
    reaper.SetExtState("RGS_Nudge","selected_nudge_unit", tostring(1),true)
    reaper.SetExtState("RGS_Nudge", "follow_ruler", "false",true)

end