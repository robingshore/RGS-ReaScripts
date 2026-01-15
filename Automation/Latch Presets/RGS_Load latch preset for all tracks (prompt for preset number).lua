-- @noindex
local show_debug_messages = false
local function Msg(param)
    if show_debug_messages then reaper.ShowConsoleMsg(tostring(param).."\n") end
end


local load_latch_preset = 50564

local ok, user_input = reaper.GetUserInputs("Load Latch Preset", 1, "Latch Preset (1-64)", "1")
if ok then
    local latch_preset =  tonumber(user_input)
    if latch_preset 
    and latch_preset %1 == 0 
    and latch_preset>0 
    and latch_preset<65 then
        load_latch_preset = load_latch_preset + (latch_preset -1)
        reaper.Main_OnCommand(load_latch_preset,0)
        --reaper.MB("Latch preset "..tostring(latch_preset).." loaded for selected tracks", "Latch Preset Loaded",0)
    else
        reaper.MB("Latch preset must be a whole number between 1 and 64","Invalid Latch Preset",0)
        return
    end
end



