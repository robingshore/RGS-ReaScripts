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
    nudge_amount = 1
else
    nudge_amount = tonumber(reaper.GetExtState("RGS_Nudge","nudge_value"))
end
--------------------------Functions------------------------------------------------
local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end

local function GetSelectedVisibleRegionsOrMarkers()
    local selected_visible_markers = {}
    local marker_count = reaper.GetNumRegionsOrMarkers(0)
    if marker_count>0 then
        for i = 0, marker_count -1 do
            local marker = reaper.GetRegionOrMarker(0, i, "")
            local lane = reaper.GetRegionOrMarkerInfo_Value(0, marker, "I_LANENUMBER")
            if reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_UISEL") == 1 and
               reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_HIDDEN") == 0 and
               reaper.GetSetProjectInfo(0, "RULER_LANE_HIDDEN:"..tostring(lane), 0, false) == 0
            then
               table.insert(selected_visible_markers, marker)
            end
        end
        return selected_visible_markers
    end
end
-----------------Main----------------------------

local function Main()
    ------------Get initital Cursor position and Selected Markers & Regions
    local cur_pos_1 = reaper.GetCursorPosition()
    local selected_markers = GetSelectedVisibleRegionsOrMarkers()
    if #selected_markers>0 then
        reaper.Undo_BeginBlock()
        ------------Get Nudge Value in seconds
        local first_marker_position = reaper.GetRegionOrMarkerInfo_Value(0, selected_markers[1], "D_STARTPOS")
        reaper.SetEditCurPos(first_marker_position, false, false)
        reaper.ApplyNudge(0, snap, 6, nudge_unit, nudge_amount, false, 0)
        local nudge =  reaper.GetCursorPosition() - first_marker_position
        reaper.SetEditCurPos(cur_pos_1, false, false)
        ------------Nudge Selected Markers and Regions
        for i = 1, #selected_markers do
            local marker = selected_markers[i]
            if reaper.GetRegionOrMarkerInfo_Value(0, marker, "B_ISREGION") == 1 then
                local end_position = reaper.GetRegionOrMarkerInfo_Value(0, marker, "D_ENDPOS")
                reaper.SetRegionOrMarkerInfo_Value(0, marker, "D_ENDPOS", end_position + nudge)
            end
            local start_position = reaper.GetRegionOrMarkerInfo_Value(0, marker, "D_STARTPOS")
            reaper.SetRegionOrMarkerInfo_Value(0, marker, "D_STARTPOS", start_position + nudge)
        end
        reaper.Undo_EndBlock("Nudge Visible Selected Markers and Regions Right",0)
    end
end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















