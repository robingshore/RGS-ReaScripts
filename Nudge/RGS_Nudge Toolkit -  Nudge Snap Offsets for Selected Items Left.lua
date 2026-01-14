-- @noindex



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

local function GetFirstSelectedItemSnapOffset()
    local item_count = reaper.CountSelectedMediaItems(0)
    local first_edge = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_POSITION")
    local first_item = reaper.GetSelectedMediaItem(0,0)
    local first_snap_offset = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_SNAPOFFSET")
    local first_snap_offset_time = first_edge + first_snap_offset
    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local snap_offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
            local snap_offset_time = item_start + snap_offset
            if item_start < first_edge then 
                first_edge = item_start
                first_item = item
                first_snap_offset = snap_offset
                first_snap_offset_time = snap_offset_time
            end
        end
    end
    return first_snap_offset_time, first_snap_offset, first_item
end

local function GetShortestSelectedSnapOffset()
    local item_count = reaper.CountSelectedMediaItems(0)
    local shortest_snap_offset = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_SNAPOFFSET")
    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local snap_offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
            if snap_offset < shortest_snap_offset then 
                shortest_snap_offset = snap_offset
            end
        end
    end
    return shortest_snap_offset
end

local function TrimSnapOffsets(nudge)
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0,i)
        local snap_offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
        reaper.SetMediaItemInfo_Value(item,"D_SNAPOFFSET", snap_offset - nudge)
    end
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
----------------------------------------
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
    nudge_amount = 1
else
    nudge_amount = tonumber(reaper.GetExtState("RGS_Nudge","nudge_value"))
end
-----------------Main----------------------------

local function Main()
     if reaper.CountSelectedMediaItems(0) > 0 then
        for i = 0, reaper.CountSelectedMediaItems(0) -1 do
            local item = reaper.GetSelectedMediaItem(0,i)
            if reaper.GetMediaItemInfo_Value(item, "C_LOCK") == 1 then return end
        end
        local first_snap_offset_time = GetFirstSelectedItemSnapOffset()
        local shortest_snap_offset = GetShortestSelectedSnapOffset()
        local initial_cur_pos = reaper.GetCursorPosition()
        reaper.SetEditCurPos(first_snap_offset_time, false, false)
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
        local nudge = first_snap_offset_time -reaper.GetCursorPosition()
        reaper.SetEditCurPos(initial_cur_pos, false, false)

        if nudge < shortest_snap_offset then
            TrimSnapOffsets(nudge)
        end
    end
end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















