-- @noindex
local show_debug_messages = false
local function Msg(param)
    if show_debug_messages then reaper.ShowConsoleMsg(tostring(param).."\n") end
end

local selected_tracks = {}
local track_count = reaper.CountSelectedTracks(0)
for i = 0, track_count - 1 do
    selected_tracks[i+1] = reaper.GetSelectedTrack(0, i)
end

local global_auto_mode = reaper.GetGlobalAutomationOverride()
local write_mode = 3
local loop_count = 1
local auto_mode_table

local clear_latches = 42026
local latch_preset = 55
local clear_latch_preset = 50756 + (latch_preset -1)
local save_latch_preset  = 50628 + (latch_preset -1)

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
    reaper.defer(Main)
    reaper.atexit(Exit)
end
