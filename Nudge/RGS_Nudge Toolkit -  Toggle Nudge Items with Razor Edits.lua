-- @noindex
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local nudge_razor_contents_items=  ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_items"))
if nudge_razor_contents_items then
    reaper.set_action_options(8)
else
    reaper.set_action_options(4)
end

nudge_razor_contents_items = tostring(not nudge_razor_contents_items)
reaper.SetExtState("RGS_Nudge", "nudge_razor_contents_items", nudge_razor_contents_items,true)