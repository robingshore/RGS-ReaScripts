-- @noindex
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param).."\n")
end

local nudge_change = .001 

if reaper.HasExtState("RGS_Nudge","nudge_value") and reaper.HasExtState("RGS_Nudge","nudge_unit_number") then
    local nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge","nudge_unit_number"))
    local nudge_amount = reaper.GetExtState("RGS_Nudge","nudge_value")
    if nudge_unit ~= 17 and nudge_unit~=16 then
        nudge_amount = tonumber(nudge_amount)
        if nudge_amount>= nudge_change then
            nudge_amount = nudge_amount-nudge_change
        end
        reaper.SetExtState("RGS_Nudge","nudge_value", tostring(nudge_amount),true)
        nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge","selected_nudge_unit"))
        reaper.SetExtState("RGS_Nudge","unit_"..tostring(nudge_unit).."_nudge_value", tostring(nudge_amount),true)
    end
end
