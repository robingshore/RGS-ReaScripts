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

local function GetFirstSelectedItemFadeIn(include_snap_offset)
    local item_count = reaper.CountSelectedMediaItems(0)
    local first_edge = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_POSITION")
    local first_item = reaper.GetSelectedMediaItem(0,0)
    local first_fadein_length = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_FADEINLEN")
    local first_fadein_end = first_edge + first_fadein_length
    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local fadein_length = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
            local fadein_end = item_start + fadein_length
            if item_start < first_edge then 
                first_edge = item_start 
                first_item = item
                first_fadein_length = fadein_length
                first_fadein_end = fadein_end
            end
        end
    end
    return first_fadein_end, first_fadein_length, first_item
end

local function GetShortestSelectedFadeIn()
    local item_count = reaper.CountSelectedMediaItems(0)
    local shortest_fadein = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_FADEINLEN")
    local shortest_fadein_item =reaper.GetSelectedMediaItem(0,0)
    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetMediaItem(0, i)
            local fadein_length = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
            if fadein_length < shortest_fadein then 
                shortest_fadein = fadein_length
                shortest_fadein_item  = item
            end
        end
    end
    return shortest_fadein, shortest_fadein_item
end

local function TrimFadeins(nudge)
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0,i)
        fadein_length = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN")
        reaper.SetMediaItemInfo_Value(item,"D_FADEINLEN", fadein_length + nudge)
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
        local first_fadein_end = GetFirstSelectedItemFadeIn()
        local shortest_fadein = GetShortestSelectedFadeIn()
        local initial_cur_pos = reaper.GetCursorPosition()
        reaper.SetEditCurPos(first_fadein_end, false, false)
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
        local nudge = first_fadein_end - reaper.GetCursorPosition()
        reaper.SetEditCurPos(initial_cur_pos, false, false)

        if nudge < shortest_fadein then
            TrimFadeins(-nudge)
        end
    end
end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















