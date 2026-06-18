-- @noindex
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local ext_state_section = "RGS Action Flash"
local cast = false
local action_viewer_command_id = reaper.NamedCommandLookup("_RSe34ad571dfe95f03c993434d61b42768113c6231")
if reaper.HasExtState(ext_state_section, "cast") then
    cast = ToBoolean(reaper.GetExtState(ext_state_section, "cast"))
end

if reaper.GetToggleCommandStateEx(0, action_viewer_command_id) == 1 then
    cast = not cast
    reaper.SetExtState(ext_state_section, "cast", tostring(cast), true)
else 
    reaper.Main_OnCommandEx(action_viewer_command_id, 0)
end

if cast then
    reaper.set_action_options(4)
else
    reaper.set_action_options(8)
end