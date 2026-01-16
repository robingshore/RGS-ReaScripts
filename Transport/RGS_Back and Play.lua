-- @description Back and Play
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0.1
-- @provides
--    [main] RGS_Back and Play Settings.lua
-- @about 
--  #Back and Play
--  
-- A REAPER implementation of Pro Tools’ Back and Play feature.
-- This package includes the main Back and Play action, plus a companion settings script
-- for configuring the rewind amount.
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param).."\n")
  end


local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local extstate_section = "RGS Back and Play"
local extstate_key = "Back Amount"
local extstate_key2 = "Reset cursor"

local play_state = reaper.GetPlayState()
local play_position = reaper.GetPlayPosition()
local back_amount = 2
local reset_cursor = true
local cursor_position = reaper.GetCursorPosition()

if reaper.HasExtState(extstate_section,extstate_key) then
    back_amount = tonumber(reaper.GetExtState(extstate_section, extstate_key))
end

if reaper.HasExtState(extstate_section,extstate_key2) then 
    reset_cursor = ToBoolean(reaper.GetExtState(extstate_section, extstate_key2))
end

if play_state&1 == 1 then
    if play_state&4 == 4 then
        reaper.CSurf_OnRecord()
        reaper.SetEditCurPos(play_position-back_amount,false, true)
    else
        reaper.SetEditCurPos(play_position-back_amount,false, true)
    end
else
    if play_state&4 == 4 then
        if reaper.GetToggleCommandState(41819) == 1 then --Pre-roll: Toggle pre-roll on record
            reaper.Main_OnCommand(40667,0) -- Transport: Stop (save all recorded media)
            reaper.Main_OnCommand(41819,0)
            reaper.SetEditCurPos(cursor_position-back_amount,false, true)
            reaper.CSurf_OnRecord()
            reaper.Main_OnCommand(41819,0)
        else
            reaper.Main_OnCommand(40667,0) -- Transport: Stop (save all recorded media)
            reaper.SetEditCurPos(cursor_position-back_amount,false, true)
            reaper.CSurf_OnRecord()
        end
    else
        if reaper.GetToggleCommandState(41818) == 1 then -- Pre-roll: Toggle pre-roll on play
            reaper.Main_OnCommand(41818,0)
            reaper.SetEditCurPos(cursor_position-back_amount,false, true)
            reaper.OnPlayButton()
            reaper.Main_OnCommand(41818,0)
        else
            reaper.SetEditCurPos(cursor_position-back_amount,false, true)
            reaper.OnPlayButton()
        end
    end
   
end

if not reset_cursor then 
    reaper.SetEditCurPos(cursor_position,false,false)
end


