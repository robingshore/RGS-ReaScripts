-- @noindex
--------------------------Get External Variables ----------------------------------
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local nudge_cursor_with_razors =  ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_cursor_with_razors"))
local nudge_time_sel_with_razors = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_time_sel_with_razors")) -- Also nudge the time selection when nudging razor edits
local nudge_razor_contents_items = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_items"))
local nudge_razor_contents_envelopes = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_envelopes"))
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
--------------------------Functions------------------------------------------------
local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end

local function GetSelectedRegions()
    local selected_regions = {}
    local region_count = reaper.GetNumRegionsOrMarkers(0)
    if region_count>0 then
        for i = 0, region_count -1 do
            local region = reaper.GetRegionOrMarker(0, i, "")
            if reaper.GetRegionOrMarkerInfo_Value(0, region, "B_UISEL") == 1 and reaper.GetRegionOrMarkerInfo_Value(0, region, "B_ISREGION") == 1 then
               table.insert(selected_regions, region)
            end
        end
        return selected_regions
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
-----------------Main----------------------------

local function Main()
    ------------Get initital Cursor position and Selected Regions
    local cur_pos_1 = reaper.GetCursorPosition()
    local selected_regions = GetSelectedRegions()
    if #selected_regions>0 then
        ------------Get Nudge Value in seconds
        local first_region_position = reaper.GetRegionOrMarkerInfo_Value(0, selected_regions[1], "D_STARTPOS")
        reaper.SetEditCurPos(first_region_position, false, false)
        reaper.ApplyNudge(0, snap, 6, nudge_unit, nudge_amount, true, 0)
        local nudge =  first_region_position - reaper.GetCursorPosition() 
        reaper.SetEditCurPos(cur_pos_1, false, false)
        ------------Nudge Selected Region starts
        reaper.Undo_BeginBlock()
        for i = 1, #selected_regions do
            local region = selected_regions[i]
            local start_position = reaper.GetRegionOrMarkerInfo_Value(0, region, "D_STARTPOS")
            reaper.SetRegionOrMarkerInfo_Value(0, region, "D_STARTPOS", start_position - nudge)
        end
        reaper.Undo_EndBlock("Nudge All Selected Regions Start Left",0)

    end
end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















