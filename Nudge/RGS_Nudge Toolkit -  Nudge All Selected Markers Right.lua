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

local function GetSelectedMarkers()
    local selected_markers = {}
    local marker_count = reaper.GetNumRegionsOrMarkers(0)
    if marker_count>0 then
        for i = 0, marker_count -1 do
            local marker = reaper.GetRegionOrMarker(0, i, "")
            if reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_UISEL") == 1 and reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_ISREGION") == 0 then
               table.insert(selected_markers, marker)
            end
        end
        return selected_markers
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
    ------------Get initital Cursor position and Selected Markers
    local cur_pos_1 = reaper.GetCursorPosition()
    local selected_markers = GetSelectedMarkers()
    if #selected_markers>0 then
        reaper.Undo_BeginBlock()
        ------------Get Nudge Value in seconds
        local first_marker_position = reaper.GetRegionOrMarkerInfo_Value(0, selected_markers[1], "D_STARTPOS")
        reaper.SetEditCurPos(first_marker_position, false, false)
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, false, 0)
        local nudge = reaper.GetCursorPosition() - first_marker_position
        reaper.SetEditCurPos(cur_pos_1, false, false)
        ------------Nudge Selected Markers
        for i = 1, #selected_markers do
            local marker = selected_markers[i]
            local start_position = reaper.GetRegionOrMarkerInfo_Value(0, marker, "D_STARTPOS")
            reaper.SetRegionOrMarkerInfo_Value(0, marker, "D_STARTPOS", start_position + nudge)
        end
        reaper.Undo_EndBlock("Nudge All Selected Markers Right",0)
    end
end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















