-- @noindex
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param).."\n")
end

local nudge_change = .01

if reaper.HasExtState("RGS_Nudge","nudge_value") and reaper.HasExtState("RGS_Nudge","nudge_unit_number") then
    local nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge","nudge_unit_number"))
    local nudge_amount = reaper.GetExtState("RGS_Nudge","nudge_value")
    if nudge_unit ~= 17 then
        if nudge_unit ~= 16 then 
            nudge_amount = tonumber(nudge_amount)
            nudge_amount = nudge_amount + nudge_change
        else
            local bar_value, beat_value, sub_beat_value = nudge_amount:match("([^%.]+)%.([^%.]+)%.([^%.]+)")
            bar_value = tonumber(bar_value)
            beat_value = tonumber(beat_value)
            sub_beat_value = tonumber(sub_beat_value)
            if sub_beat_value < 100 - (nudge_change * 100) then
                sub_beat_value = sub_beat_value + (nudge_change * 100)
            end
            nudge_amount = tostring(bar_value.."."..beat_value.."."..string.format("%02d",sub_beat_value))
        end
        reaper.SetExtState("RGS_Nudge","nudge_value", tostring(nudge_amount),true)
        nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge","selected_nudge_unit"))
        reaper.SetExtState("RGS_Nudge","unit_"..tostring(nudge_unit).."_nudge_value", tostring(nudge_amount),true)
    end
end