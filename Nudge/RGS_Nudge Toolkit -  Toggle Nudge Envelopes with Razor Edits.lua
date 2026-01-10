-- @noindex
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local nudge_razor_contents_envelopes =  ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_envelopes"))
if nudge_razor_contents_envelopes then
    reaper.set_action_options(8)
else
    reaper.set_action_options(4)
end
nudge_razor_contents_envelopes = tostring(not nudge_razor_contents_envelopes)
reaper.SetExtState("RGS_Nudge", "nudge_razor_contents_envelopes", nudge_razor_contents_envelopes,true)