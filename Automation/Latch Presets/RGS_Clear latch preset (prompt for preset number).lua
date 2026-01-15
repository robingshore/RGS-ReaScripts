-- @description Save/Load/Clear latch presets with prompt for preset number
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0.1
-- @provides
--    [main] RGS_Load latch preset for all tracks (prompt for preset number).lua
--    [main] RGS_Load latch preset for selected tracks (prompt for preset number).lua
--    [main] RGS_Save latch preset for all tracks (prompt for preset number).lua
--    [main] RGS_Save latch preset for selected tracks (prompt for preset number).lua

-- @about 
--  # Save/Load/Clear latch presets with prompt for preset number
--
--  This is a set of actions meant to streamline working with REAPER's 64
--  latch presets. The actions prompt for a preset number, allowing you to
--  save, load, or clear any latch preset without relying on 64 separae actions
--  per function.

local show_debug_messages = false
local function Msg(param)
    if show_debug_messages then reaper.ShowConsoleMsg(tostring(param).."\n") end
end


local clear_latch_preset = 50756

local ok, user_input = reaper.GetUserInputs("Clear Latch Preset", 1, "Latch Preset (1-64)", "1")
if ok then
    local latch_preset =  tonumber(user_input)
    if latch_preset 
    and latch_preset %1 == 0 
    and latch_preset>0 
    and latch_preset<65 then
        clear_latch_preset = clear_latch_preset + (latch_preset -1)
        reaper.Main_OnCommand(clear_latch_preset,0)
        reaper.MB("Latch preset "..tostring(latch_preset).." cleared", "Latch Preset Cleared",0)
    else
        reaper.MB("Latch preset must be a whole number between 1 and 64","Invalid Latch Preset",0)
        return
    end
end



