-- @description Save current envelope values to latch preset
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0.6
-- @provides
--    [main] RGS_Save current envelope values of selected tracks to latch preset*.lua
-- @about 
--  # Save current envelope values to latch preset
--  
--  This package provides a set of actions for capturing the current values of all armed automation
--  envelopes on the selected tracks (regardless of whether they are actively writing or latched) and
--  storing them into any of REAPER’s 64 automation latch preset slots.
--  
--  Once saved, these values can be instantly punched into other sections of the project using REAPER’s
--  built-in Load Latch Preset actions. The package includes one-click save actions for all 64 latch slots,
--  as well as a generalized action that prompts the user to choose a slot before saving.


local show_debug_messages = false

local selected_tracks = {}
local track_count = reaper.CountSelectedTracks(0)
for i = 0, track_count - 1 do
    selected_tracks[i+1] = reaper.GetSelectedTrack(0, i)
end


local global_auto_mode =reaper.GetGlobalAutomationOverride()
local write_mode = 3
local loop_count = 1
local auto_mode_table

local clear_latches = 42026
local clear_latch_preset = 50756
local save_latch_preset = 50628

local function Msg(param)
    if show_debug_messages then reaper.ShowConsoleMsg(tostring(param).."\n") end
end



local function GetSelectedTrackAutoModes()
    local auto_mode_table = {}
    for _, track in ipairs(selected_tracks) do
        if track then
            auto_mode_table[track] = reaper.GetTrackAutomationMode(track)
        end
    end
    return auto_mode_table
end

local function Exit()
    if auto_mode_table then
        for track, mode in pairs(auto_mode_table) do
            reaper.SetTrackAutomationMode(track, mode)
        end
        reaper.Main_OnCommand(clear_latches, 0)
    end
    reaper.SetGlobalAutomationOverride(global_auto_mode)
end


local function Main()
    
    if loop_count == 1 then
        reaper.SetGlobalAutomationOverride(-1)
        auto_mode_table = GetSelectedTrackAutoModes()
        reaper.SetAutomationMode(write_mode,true)
        loop_count = loop_count + 1
        reaper.defer(Main)
    elseif loop_count > 1 and loop_count <3 then
        loop_count = loop_count + 1
        reaper.defer(Main)
    elseif loop_count == 3 then
        loop_count = loop_count + 1
        reaper.Main_OnCommand(clear_latch_preset, 0)
        reaper.Main_OnCommand(save_latch_preset,0)
    end
end

if track_count > 0 then
    local ok, user_input = reaper.GetUserInputs("Save Latch Preset", 1, "Latch Preset (1-64)", "1")
    if ok then
        local latch_preset =  tonumber(user_input)
        if latch_preset 
        and latch_preset %1 == 0 
        and latch_preset>0 
        and latch_preset<65 then
            clear_latch_preset = clear_latch_preset + (latch_preset -1)
            save_latch_preset = save_latch_preset + (latch_preset-1)
            reaper.defer(Main)
            reaper.atexit(Exit)
        else
            reaper.MB("Latch preset must be a whole number between 1 and 64","Invalid Latch Preset",0)
            return
        end
    end
end


