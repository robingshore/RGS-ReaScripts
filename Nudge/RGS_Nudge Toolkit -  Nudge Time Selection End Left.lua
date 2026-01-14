-- @noindex
local nudge_unit
local nudge_amount
local snap = reaper.GetExtState("RGS_Nudge", "snap_to_unit")
if snap == "true" then
    snap = 2 
else
    snap = 0
end
if not reaper.HasExtState("RGS_Nudge","nudge_unit_number") then
    nudge_unit = 2 --  0=ms, 1=seconds, 2=grid, 3=256th notes, ..., 15=whole notes, 16=measures.beats (1.15 = 1 measure + 1.5 beats), 17=samples, 18=frames, 19=pixels, 20=item lengths, 21=item selections
else
    nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge","nudge_unit_number"))
end
if not reaper.HasExtState("RGS_Nudge","nudge_value") then
    if nudge_unit == 16 then
        nudge_amount = "0.1.0"
    else
        nudge_amount = 1
    end
else
    if nudge_unit == 16 then
        nudge_amount = reaper.GetExtState("RGS_Nudge","nudge_value")
    else
        nudge_amount = tonumber(reaper.GetExtState("RGS_Nudge","nudge_value"))
    end
end
----------------Functions---------------------
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param).."\n")
end

local function ApplyNudgeRGS(project, nudgeflag, nudgewhat, nudgeunits, value, reverse, copies)
    if nudgeunits == 16 then
    local bar_value, beat_value, sub_beat_value = value:match("([^%.]+)%.([^%.]+)%.([^%.]+)")
    bar_value = tonumber(bar_value)
    beat_value = tonumber(beat_value)
    sub_beat_value = tonumber(sub_beat_value)

        if sub_beat_value > 0 then
            reaper.ApplyNudge(project, 0, nudgewhat, nudgeunits, bar_value, reverse, copies)
            for i = 1, beat_value do
                reaper.ApplyNudge(project, 0, nudgewhat, nudgeunits, 0.1, reverse, copies)
            end
            reaper.ApplyNudge(project, nudgeflag, nudgewhat, nudgeunits, sub_beat_value/1000, reverse, copies)
        elseif beat_value > 0 then
            reaper.ApplyNudge(project, 0, nudgewhat, nudgeunits, bar_value, reverse, copies)
            for i = 1, beat_value -1 do
                reaper.ApplyNudge(project, 0, nudgewhat, nudgeunits, 0.1, reverse, copies)
            end
            reaper.ApplyNudge(project, nudgeflag, nudgewhat, nudgeunits, 0.1, reverse, copies)
        else
            reaper.ApplyNudge(project, nudgeflag, nudgewhat, nudgeunits, bar_value, reverse, copies)
        end
    else
        reaper.ApplyNudge(project, nudgeflag, nudgewhat, nudgeunits, value, reverse, copies)
    end
end


-----------------Main----------------------------

local function Main()
    local selection_start, selection_end = reaper.GetSet_LoopTimeRange(false,false,0,0, false)
    if selection_end > selection_start then
        local cur_pos_1 = reaper.GetCursorPosition()
        reaper.SetEditCurPos(selection_end,false, false)
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
        if reaper.GetCursorPosition()> selection_start then
            reaper.GetSet_LoopTimeRange(true,false,selection_start,reaper.GetCursorPosition(), false)
        end
        reaper.SetEditCurPos(cur_pos_1, false, false)
    end
end

--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















