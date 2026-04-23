-- @noindex

local ScriptName = "Contextual Nudge Left"
local no_sws
if not reaper.SNM_GetIntConfigVar then
    no_sws = true
end

if no_sws then
     reaper.MB("SWS/S&M extension is\nrequired to run this script.\n\nPlease install the missing extension\nand run the script again",ScriptName, 0)
    if reaper.ReaPack_BrowsePackages then
        reaper.ReaPack_BrowsePackages("SWS/S&M extension")
    end
    return
end
------------------------------------Get Nudge Values and Settings------------------



local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end

local nudge_cursor_with_razors =  ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_cursor_with_razors"))
local nudge_time_sel_with_razors = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_time_sel_with_razors")) -- Also nudge the ti1me selection when nudging razor edits
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
--------------------Functions-------------------------
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param).."\n")
end


local function MsgTable(table)
    for key, value in pairs(table) do
    Msg(tostring(key).." ".. tostring(value))
    end
end 

local function UnselectAllTracks()
  local first_track = reaper.GetTrack(0, 0)
  reaper.SetOnlyTrackSelected(first_track)
  reaper.SetTrackSelected(first_track, false)
end

local function SaveTrackSelection(table)
      for i = 0, reaper.CountSelectedTracks(0)-1 do
        table[i+1] = reaper.GetSelectedTrack(0, i)
      end
end      

local function LoadTrackSelection(table)
    UnselectAllTracks()
    for index, track in ipairs(table) do
        reaper.SetTrackSelected(track, true)
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

local function GetGUIDFromEnvelope(envelope)
    local ret2, envelopeChunk = reaper.GetEnvelopeStateChunk(envelope, "")
    local GUID = "{" ..  string.match(envelopeChunk, "GUID {(%S+)}") .. "}"
    return GUID
end

local function RazorExists()
    for i = 0, reaper.CountTracks(0)-1 do
        local _, razor_edits = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i) , "P_RAZOREDITS_EXT", "", false)
        if razor_edits ~= "" then return true end
    end
    return false
end

local function SetTrackRazorEdit(track, areaStart, areaEnd, clearSelection, areaTop, areaBottom)
    if clearSelection == nil then clearSelection = false end
        
    
    if clearSelection then
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS_EXT', '', false)
    
        --parse string, all this string stuff could probably be written better
        local TRstr = {}
            
        for s in area:gmatch('[^,]+')do
          table.insert(TRstr, s)
        end
        
        for i=1, #TRstr do
        
          local rect = TRstr[i]
          TRstr[i] = {}
          for j in rect:gmatch("%S+") do
            table.insert(TRstr[i], j)
          end
          
        end
        
        --strip existing selections across the track
        local finalStr = ''
        for i = 1, #TRstr do
            if #TRstr[i] > 2 and TRstr[i][3] ~= '""' then
              finalStr = finalStr..TRstr[i][1]..' '..TRstr[i][2]..' '..TRstr[i][3]..','
            end
        end
        --insert razor edit 
        local REstr = tostring(areaStart) .. ' ' .. tostring(areaEnd) .. ' ""'..tostring(areaTop)..' '..tostring(areaBottom)
        finalStr = finalStr..REstr
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS_EXT', finalStr, true)
        return ret
    else
           
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS_EXT', '', false)
        local str = area ~= '' and area .. ',' or ''
        str = str .. tostring(areaStart) .. ' ' .. tostring(areaEnd)
        if areaTop then
            str = str .. ' "" '..areaTop..areaBottom
        end
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS_EXT', str, true)
        return ret
    end
end

local function SetEnvelopeRazorEdit(envelope, areaStart, areaEnd, clearSelection, GUID)
    local GUID = GUID == nil and GetGUIDFromEnvelope(envelope) or GUID
    local track = reaper.Envelope_GetParentTrack(envelope)

    if clearSelection then
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
    
        --parse string
        local str = {}
        for j in string.gmatch(area, "%S+") do
            table.insert(str, j)
        end
        
        --strip existing selections across the envelope
        local j = 1
        while j <= #str do
            local envGUID = str[j+2]
            if GUID ~= '""' and envGUID:sub(2,-2) == GUID then 
                str[j] = ''
                str[j+1] = ''
                str[j+2] = ''
            end

            j = j + 3
        end

        --insert razor edit
        local REstr = tostring(areaStart) .. ' ' .. tostring(areaEnd) .. ' ' .. GUID
        table.insert(str, REstr)

        local finalStr = ''
        for i = 1, #str do
            local space = i == 1 and '' or ' '
            finalStr = finalStr .. space .. str[i]
        end

        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', finalStr, true)
        return ret
    else         
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)

        local str = area ~= nil and area .. ' ' or ''
        str = str .. tostring(areaStart) .. ' ' .. tostring(areaEnd) .. ' ' .. GUID
        
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', str, true)
        return ret
    end
end

local function GetEnvelopePointsInRange(envelopeTrack, areaStart, areaEnd)
    local envelopePoints = {}

    for i = 1, reaper.CountEnvelopePoints(envelopeTrack) do
        local retval, time, value, shape, tension, selected = reaper.GetEnvelopePoint(envelopeTrack, i - 1)

        if time >= areaStart and time <= areaEnd then --point is in range
            envelopePoints[#envelopePoints + 1] = {
                id = i-1 ,
                time = time,
                value = value,
                shape = shape,
                tension = tension,
                selected = selected
            }
        end
    end

    return envelopePoints
end

local function GetItemsInRange(track, areaStart, areaEnd, areaTop, areaBottom)
    local items = {}
    local itemCount = reaper.CountTrackMediaItems(track)
    local itemTop, itemBottom
    
    for k = 0, itemCount - 1 do 
        local item = reaper.GetTrackMediaItem(track, k)
        local lock = reaper.GetMediaItemInfo_Value(item, "C_LOCK")
        
        if lock ~= 1 then
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local itemEndPos = pos+length
            
            if areaBottom ~= nil then
            itemTop = reaper.GetMediaItemInfo_Value(item, "F_FREEMODE_Y")
            itemBottom = itemTop + reaper.GetMediaItemInfo_Value(item, "F_FREEMODE_H")
            --msg("area: "..tostring(areaTop).." "..tostring(areaBottom).."\n".."item: "..itemTop.." "..itemBottom.."\n\n")
            end
            
            --check if item is in area bounds
            if itemEndPos > areaStart and pos < areaEnd then
            
            if areaBottom and itemTop then
                if itemTop < areaBottom - 0.001 and itemBottom > areaTop + 0.001 then
                table.insert(items,item)
                end
            else
                table.insert(items,item)
            end
            
            end
        end -- if lock
    end --end for cycle

    return items
end

local function GetRazorEdits()
    local trackCount = reaper.CountTracks(0)
    local areaMap = {}
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local mode = reaper.GetMediaTrackInfo_Value(track,"I_FREEMODE")
        if mode ~= 0 then
        ----NEW WAY----
        
            local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS_EXT', '', false)
            
        if area ~= '' then
            --PARSE STRING and CREATE TABLE
            local TRstr = {}
            
            for s in area:gmatch('[^,]+')do
                table.insert(TRstr, s)
            end
            
            for i=1, #TRstr do
            
                local rect = TRstr[i]
                TRstr[i] = {}
                for j in rect:gmatch("%S+") do
                table.insert(TRstr[i], j)
                end
                
            end
        
            --FILL AREA DATA
            local i = 1
            while i <= #TRstr do
                --area data
                local areaStart = tonumber(TRstr[i][1])
                local areaEnd = tonumber(TRstr[i][2])
                local GUID = TRstr[i][3]
                local areaTop = tonumber(TRstr[i][4])
                local areaBottom = tonumber(TRstr[i][5])
                local isEnvelope = GUID ~= '""'

                --get item/envelope data
                local items = {}
                local envelopeName, envelope
                local envelopePoints
                
                if not isEnvelope then
                    items = GetItemsInRange(track, areaStart, areaEnd, areaTop, areaBottom)
                else
                    envelope = reaper.GetTrackEnvelopeByChunkName(track, GUID:sub(2, -2))
                    local ret, envName = reaper.GetEnvelopeName(envelope)

                    envelopeName = envName
                    envelopePoints = GetEnvelopePointsInRange(envelope, areaStart, areaEnd)
                end

                local areaData = {
                    areaStart = areaStart,
                    areaEnd = areaEnd,
                    areaTop = areaTop,
                    areaBottom = areaBottom,
                    
                    track = track,
                    items = items,
                    
                    --envelope data
                    isEnvelope = isEnvelope,
                    envelope = envelope,
                    envelopeName = envelopeName,
                    envelopePoints = envelopePoints,
                    GUID = GUID:sub(2, -2)
                }

                table.insert(areaMap, areaData)

                i=i+1
            end
            end
        else  
        
        ---OLD WAY for backward compatibility-------
        
            local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
            
            if area ~= '' then
            --PARSE STRING
            local str = {}
            for j in string.gmatch(area, "%S+") do
                table.insert(str, j)
            end
        
            --FILL AREA DATA
            local j = 1
            while j <= #str do
                --area data
                local areaStart = tonumber(str[j])
                local areaEnd = tonumber(str[j+1])
                local GUID = str[j+2]
                local isEnvelope = GUID ~= '""'
        
                --get item/envelope data
                local items = {}
                local envelopeName, envelope
                local envelopePoints
                
                if not isEnvelope then
                    items = GetItemsInRange(track, areaStart, areaEnd)
                else
                    envelope = reaper.GetTrackEnvelopeByChunkName(track, GUID:sub(2, -2))
                    local ret, envName = reaper.GetEnvelopeName(envelope)
        
                    envelopeName = envName
                    envelopePoints = GetEnvelopePointsInRange(envelope, areaStart, areaEnd)
                end
        
                local areaData = {
                    areaStart = areaStart,
                    areaEnd = areaEnd,
                    
                    track = track,
                    items = items,
                    
                    --envelope data
                    isEnvelope = isEnvelope,
                    envelope = envelope,
                    envelopeName = envelopeName,
                    envelopePoints = envelopePoints,
                    GUID = GUID:sub(2, -2)
                }
        
                table.insert(areaMap, areaData)
        
                j = j + 3
            end
            end  ---OLD WAY END
        end
    end

    return areaMap
end

local function GetRazorTracks()
    local razor_tracks = {}
    for i = 0 , reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, razor_string = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i) , "P_RAZOREDITS_EXT", "", false)
        if razor_string ~= "" then
            table.insert(razor_tracks, track)
        end
    end 
    return razor_tracks
end

local function GetTrackRazorEdits(track)
    local razor_areas = GetRazorEdits()
    local track_razor_edits = {}
    for r = 1, #razor_areas do
        razor_data = razor_areas[r]
            if razor_data.track == track then
                table.insert(track_razor_edits, razor_areas[r])
            end
    end
    return track_razor_edits
end

local function UnselectAllItems()
    for  i = 0, reaper.CountMediaItems(0)- 1 do
        reaper.SetMediaItemSelected(reaper.GetMediaItem(0, i), false)
    end
end

local function SplitAtRazorEdges()
    local razors = GetRazorEdits()
    for r = 1, #razors do
        local razor_data = razors[r]
        local razor_items = razor_data.items
        for i = 1, #razor_items do
            local item = razor_items[i]
            local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if item_start < razor_data.areaStart then
                local new_item = reaper.SplitMediaItem(item, razor_data.areaStart)
                if new_item then
                    local new_item_start = reaper.GetMediaItemInfo_Value(new_item, "D_POSITION")
                    local new_item_end = new_item_start + reaper.GetMediaItemInfo_Value(new_item, "D_LENGTH")
                    if new_item_start < razor_data.areaEnd and new_item_end > razor_data.areaEnd then
                        reaper.SplitMediaItem(new_item, razor_data.areaEnd)
                    end
                end
            end
            if item_end > razor_data.areaEnd then
                reaper.SplitMediaItem(item, razor_data.areaEnd)
            end
        end
    end
end

local function GetFirstRazorEdge()
    if RazorExists() then
        local first_edge = math.huge
        local razor_edits = GetRazorEdits()
        for r = 1, #razor_edits do
            local razor_edit_data = razor_edits[r]
            if razor_edit_data.areaStart < first_edge then
                first_edge = razor_edit_data.areaStart
            end
        end
        return first_edge
    end
end

local function TrimNudgesLeft()
    local new_razors = GetRazorEdits()
    for n = 1, #new_razors do
        local new_data = new_razors[n]
        local new_items = new_data.items 
        for i = 1 , #new_items do
            local item = new_items[i]
            local item_is_new = true
            for r = 1, #razors do 
                local razor_data = razors[r]
                local old_items =  razor_data.items
                for _ , v in pairs(old_items) do
                    if v == item then
                        item_is_new = false
                    end
                end
            end
            if item_is_new then
                local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if item_start > new_data.areaStart and item_end < new_data.areaEnd then
                    reaper.DeleteTrackMediaItem(new_data.track, item)
                else
                    local item_right = reaper.SplitMediaItem(item, new_data.areaStart)
                    if not item_right then 
                        reaper.DeleteTrackMediaItem(new_data.track, item)
                    else
                        local item_right_start = reaper.GetMediaItemInfo_Value(item_right, "D_POSITION")
                        local item_right_end = item_right_start + reaper.GetMediaItemInfo_Value(item_right, "D_LENGTH")
                        if item_right_end > new_data.areaEnd then
                            local new_item_right = reaper.SplitMediaItem(item_right, new_data.areaEnd)
                            reaper.DeleteTrackMediaItem(new_data.track, item_right)
                        else
                            reaper.DeleteTrackMediaItem(new_data.track, item_right)
                        end
                    end
                end
            end   
        end
    end
    if reaper.GetToggleCommandState(40041) == 1 then-- Prevent rogue fades when trim behind and auto crossfade are both enabled
        reaper.ApplyNudge(0, 0, 0, 1,.0000001, true, 0)
        reaper.ApplyNudge(0, 0, 0, 1,.0000001, false, 0)
    end
end

local function RippleAllTrimNudgesLeft()
    local razor_tracks = GetRazorTracks()
    for t = 1, #razor_tracks do 
        local track = razor_tracks[t]
        local new_razors = GetTrackRazorEdits(track)
        --for n = 1, #new_razors do
            local new_data = new_razors[1]
            local new_items = new_data.items 
            for i = 1 , #new_items do
                local item = new_items[i]
                local item_is_new = true
                for r = 1, #razors do 
                    local razor_data = razors[r]
                    local old_items =  razor_data.items
                    for _ , v in pairs(old_items) do
                        if v == item then
                            item_is_new = false
                        end
                    end
                end
                if item_is_new then
                    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    if item_start < GetFirstRazorEdge() + nudge then
                        if item_start > new_data.areaStart and item_end < new_data.areaEnd then
                            reaper.DeleteTrackMediaItem(new_data.track, item)
                        else
                            local item_right = reaper.SplitMediaItem(item, new_data.areaStart)
                            if not item_right then 
                                reaper.DeleteTrackMediaItem(new_data.track, item)
                            else
                                local item_right_start = reaper.GetMediaItemInfo_Value(item_right, "D_POSITION")
                                local item_right_end = item_right_start + reaper.GetMediaItemInfo_Value(item_right, "D_LENGTH")
                                if item_right_end > new_data.areaEnd then
                                    local new_item_right = reaper.SplitMediaItem(item_right, new_data.areaEnd)
                                    reaper.DeleteTrackMediaItem(new_data.track, item_right)
                                else
                                    reaper.DeleteTrackMediaItem(new_data.track, item_right)
                                end
                            end
                        end
                    end
                end   
            end
        --end
        if reaper.GetToggleCommandState(40041) == 1 then-- Prevent rogue fades when trim behind and auto crossfade are both enabled
            reaper.ApplyNudge(0, 0, 0, 1,.0000001, true, 0)
            reaper.ApplyNudge(0, 0, 0, 1,.0000001, false, 0)
        end
    end
end

local function RippleTrackTrimNudgesLeft()
    local razor_tracks = GetRazorTracks()
    for t = 1, #razor_tracks do 
        local track = razor_tracks[t]
        local new_razors = GetTrackRazorEdits(track)
        --for n = 1, #new_razors do
            local new_data = new_razors[1]
            local new_items = new_data.items 
            for i = 1 , #new_items do
                local item = new_items[i]
                local item_is_new = true
                for r = 1, #razors do 
                    local razor_data = razors[r]
                    local old_items =  razor_data.items
                    for _ , v in pairs(old_items) do
                        if v == item then
                            item_is_new = false
                        end
                    end
                end
                if item_is_new then
                    local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    --if item_start < GetFirstRazorEdge() + nudge then
                        if item_start > new_data.areaStart and item_end < new_data.areaEnd then
                            reaper.DeleteTrackMediaItem(new_data.track, item)
                        else
                            local item_right = reaper.SplitMediaItem(item, new_data.areaStart)
                            if not item_right then 
                                reaper.DeleteTrackMediaItem(new_data.track, item)
                            else
                                local item_right_start = reaper.GetMediaItemInfo_Value(item_right, "D_POSITION")
                                local item_right_end = item_right_start + reaper.GetMediaItemInfo_Value(item_right, "D_LENGTH")
                                if item_right_end > new_data.areaEnd then
                                    local new_item_right = reaper.SplitMediaItem(item_right, new_data.areaEnd)
                                    reaper.DeleteTrackMediaItem(new_data.track, item_right)
                                else
                                    reaper.DeleteTrackMediaItem(new_data.track, item_right)
                                end
                            end
                        end
                    --end
                end   
            end
        --end
        if reaper.GetToggleCommandState(40041) == 1 then-- Prevent rogue fades when trim behind and auto crossfade are both enabled
            reaper.ApplyNudge(0, 0, 0, 1,.0000001, true, 0)
            reaper.ApplyNudge(0, 0, 0, 1,.0000001, false, 0)
        end
    end
end

local function AutoItemSelected()
    local ret_val = false
    for i = 0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, i)
        for j = 0, reaper.CountTrackEnvelopes(track)-1 do
            local env = reaper.GetTrackEnvelope(track, j)
            local _, env_vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
            if tonumber(env_vis) == 1 then
                for k = 0, reaper.CountAutomationItems(env) - 1 do
                    if reaper.GetSetAutomationItemInfo(env ,k, "D_UISEL", 0, false) ~=0 then
                        ret_val = true
                        return ret_val
                    end
                end
            end
        end
    end
    return ret_val
end

local function GetFirstSelectedAutoItemEdge()
    if AutoItemSelected() then
        local first_edge = math.huge
        for i = 0, reaper.CountTracks(0)-1 do
            local track = reaper.GetTrack(0, i)
            for j = 0, reaper.CountTrackEnvelopes(track)-1 do
                local env = reaper.GetTrackEnvelope(track, j)
                local _, env_vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
                if tonumber(env_vis) == 1 then
                    for k = 0, reaper.CountAutomationItems(env) - 1 do
                        if reaper.GetSetAutomationItemInfo(env ,k, "D_UISEL", 0, false) ~=0 then
                            local edge = reaper.GetSetAutomationItemInfo(env ,k, "D_POSITION", 0, false)
                            if edge < first_edge then
                                first_edge = edge
                            end
                        end
                    end
                end
            end
        end
        return first_edge
    end
end

local function GetFirstSelectedItemEdge(include_snap_offset)
    local item_count = reaper.CountSelectedMediaItems(0)
    local first_edge = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_POSITION")
    local first_item = reaper.GetSelectedMediaItem(0,0)
    if include_snap_offset then
        first_edge = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_POSITION") + reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_SNAPOFFSET")
    end
    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_offset = 0
            if include_snap_offset then
                item_offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
            end
            local item_start = item_position + item_offset
            if item_start < first_edge then 
                first_edge = item_start 
                first_item = item
            end
        end
    end
    return first_edge, first_item
end

local function NudgeAutoItems(nudge_amount, move_with_media_items)
    if move_with_media_items == 0 then
        for i = 0, reaper.CountTracks(0)-1 do
            local track = reaper.GetTrack(0, i)
            for j = 0, reaper.CountTrackEnvelopes(track)-1 do
                local env = reaper.GetTrackEnvelope(track, j)
                local _, env_vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
                if tonumber(env_vis) == 1 then
                    for k = 0, reaper.CountAutomationItems(env) - 1 do
                        if reaper.GetSetAutomationItemInfo(env ,k, "D_UISEL", 0, false) ~=0 then
                            local position = reaper.GetSetAutomationItemInfo(env,k,"D_POSITION", 0, false )    
                            reaper.GetSetAutomationItemInfo(env,k,"D_POSITION", position + nudge_amount, true)
                        end
                    end
                end
            end
        end
    else
        for i = 0, reaper.CountTracks(0)-1 do
            local track = reaper.GetTrack(0, i)
            for j = 0, reaper.CountTrackEnvelopes(track)-1 do
                local env = reaper.GetTrackEnvelope(track, j)
                local _, env_vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
                if tonumber(env_vis) == 1 then
                    for k = 0, reaper.CountAutomationItems(env) - 1 do
                        if reaper.GetSetAutomationItemInfo(env ,k, "D_UISEL", 0, false) ~=0 then
                            local move_item = true
                            local auto_item_start = reaper.GetSetAutomationItemInfo(env,k,"D_POSITION", 0, false )
                            local auto_item_length = reaper.GetSetAutomationItemInfo(env,k,"D_LENGTH",0,false)
                            local auto_item_end = auto_item_length + auto_item_start
                            for l = 0, reaper.CountTrackMediaItems(track) -1 do
                                local item = reaper.GetTrackMediaItem(track, l)
                                if reaper.GetMediaItemInfo_Value(item, "B_UISEL") == 1 then
                                    move_item = false
                                    break
                                end
                            end
                            if move_item then
                                reaper.GetSetAutomationItemInfo(env,k,"D_POSITION", auto_item_start + nudge_amount, true)
                            end
                        end
                    end
                end
            end
        end
    end

end

-----------------Main----------------------------
local function Main()
    ------------Get initital Cursor position and Selected Envelope
    local cur_pos_1 = reaper.GetCursorPosition()

        
    ----------------- Get Nudge Value in seconds
    ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, false, 0)
    local nudge =  reaper.GetCursorPosition() - cur_pos_1
    reaper.SetEditCurPos(cur_pos_1, false, false)
    reaper.Undo_BeginBlock()
    if RazorExists() then
        local selected_envelope = reaper.GetSelectedEnvelope(0)
        local selected_tracks = {}
        SaveTrackSelection(selected_tracks)
        ----------Check if earliest razor edit is less than one nudge away from start of time line
        if GetFirstRazorEdge() > nudge then

            -- re-get nudge value if nudge snapping is turned on
            if snap == 2 then
                reaper.SetEditCurPos(GetFirstRazorEdge(), false, false)
                ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
                nudge = GetFirstRazorEdge() - reaper.GetCursorPosition()
                reaper.SetEditCurPos(cur_pos_1, false, false) 
            end

            ------- Get Ripple editing mode, split items at razor edges, store razor edits in a table, clear all razors and unselect all items
            local ripple_state = reaper.SNM_GetIntConfigVar("projripedit", 3)
            if nudge_razor_contents_items then 
                local razors = GetRazorEdits()
                for i = 1 , #razors do SplitAtRazorEdges() end
            end
            razors = GetRazorEdits()
            if nudge_razor_contents_items then UnselectAllItems() end
            for i = 0, reaper.CountTracks(0) -1 do
                local track = reaper.GetTrack(0, i)
                reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
            end
            
            
            for r = 1, #razors do 
                local razor_data = razors[r]
                if razor_data.isEnvelope then
                    
                    ----Nudge envelope razor edits
                    SetEnvelopeRazorEdit(razor_data.envelope , razor_data.areaStart - nudge, razor_data.areaEnd - nudge, false )
                    
                    if nudge_razor_contents_envelopes then
                        local _, env_vis = reaper.GetSetEnvelopeInfo_String(razor_data.envelope, "VISIBLE", "", false)
                        local _, env_lane = reaper.GetSetEnvelopeInfo_String(razor_data.envelope, "SHOWLANE", "", false)
                        if reaper.CountAutomationItems(razor_data.envelope) > 0 then
                            if tonumber(env_vis) == 0 then
                                reaper.GetSetEnvelopeInfo_String(razor_data.envelope, "VISIBLE", "1", true)
                                reaper.GetSetEnvelopeInfo_String(razor_data.envelope, "SHOWLANE", env_lane, true)
                            end
                            -------- Select AIs that are in the razor areas
                            for i = 0, reaper.CountAutomationItems(razor_data.envelope) -1 do
                                local item_start = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", 0, false)
                                local item_length = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", 0, false)
                                local item_end = item_start + item_length
                                if item_start <= razor_data.areaEnd and item_end > razor_data.areaStart then
                                    reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_UISEL", 1, true)
                                end
                            end

                            ------------Split AIs at razor edges
                            reaper.SetEditCurPos(razor_data.areaStart, false, false)
                            reaper.Main_OnCommand(42087, -1) -- Envelope: Split automation items
                            reaper.SetEditCurPos(razor_data.areaEnd, false, false)
                            reaper.Main_OnCommand(42087, -1) -- Envelope: Split automation items
                            reaper.SetEditCurPos(cur_pos_1, false, false)
                            
                            ----------------Nudge AIS
                            if ripple_state == 0 then
                                local AIs_to_delete = {}
                                local index_mod = 1
                                for i = reaper.CountAutomationItems(razor_data.envelope) -1, 0 , -1 do
                                    local item_start = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", 0, false)
                                    local item_length = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", 0, false)
                                    local item_end = item_start + item_length
                                    local item_offset = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_STARTOFFS", 0, false)
                                    local gap = item_start - (razor_data.areaStart - nudge)
                                    reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_UISEL", 0, true)
                                    if item_start + .000001 < razor_data.areaEnd and item_end - .000001 > razor_data.areaStart then
                                        --Msg("AI is completely enclosed by initial razor area")
                                        if item_start + .000001 > razor_data.areaStart then
                                            index_mod = index_mod +1
                                        end
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", item_start - nudge, true)
                                    elseif math.abs(item_start - (razor_data.areaStart - nudge)) < .000001 and math.abs(item_end - (razor_data.areaEnd-nudge)) <.000001 then
                                        --Msg("AI is equal to nudged razor area")
                                        table.insert(AIs_to_delete, i)
                                    elseif math.abs(item_start - (razor_data.areaStart - nudge)) < .000001 and item_end < razor_data.areaEnd-nudge then
                                        --Msg("start of AI is equal to start of nudged razor area, end of AI is within nudged razor area")
                                        table.insert(AIs_to_delete, i)
                                    elseif math.abs(item_start - (razor_data.areaStart - nudge)) < .000001 and item_end > razor_data.areaEnd-nudge then
                                        --Msg("start of AI is equal to start of nudged razor area, end of AI is outside of nudged razor area")
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", razor_data.areaEnd - nudge, true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", (item_length - (razor_data.areaEnd-razor_data.areaStart)), true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_STARTOFFS", item_offset + (razor_data.areaEnd-razor_data.areaStart), true)
                                    elseif item_start< razor_data.areaStart-nudge and math.abs(item_end - (razor_data.areaEnd-nudge)) <.000001 then
                                        --Msg("Start of AI is before nudged razor area, end of AI is equal to end of nudged razor area")
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH",(razor_data.areaStart-nudge) - item_start, true)
                                    elseif item_start>razor_data.areaStart-nudge and math.abs(item_end - (razor_data.areaEnd-nudge)) <.000001 then
                                        --Msg("Start of AI is within nudged razor areaa, end of AI is equal to end of nudged razor area")
                                        table.insert(AIs_to_delete, i)
                                    elseif (item_start > razor_data.areaStart - nudge and  item_start < razor_data.areaEnd - nudge) and item_end > razor_data.areaEnd - nudge then
                                        --Msg("Start of AI within nudged razor area end of AI is outside of nudged razor area")
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", razor_data.areaEnd - nudge, true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", (item_length - (razor_data.areaEnd-razor_data.areaStart) + gap), true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_STARTOFFS", item_offset + (razor_data.areaEnd-razor_data.areaStart) - gap, true)
                                    elseif item_start < razor_data.areaStart - nudge and item_end > razor_data.areaEnd - nudge then
                                        --Msg("Nudged razor area is completely enclosed by AI")
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_UISEL", 1, true)
                                        reaper.SetEditCurPos(razor_data.areaStart - nudge, false, false)
                                        reaper.Main_OnCommand(42087, -1) -- Envelope: Split automation items
                                        reaper.SetEditCurPos(cur_pos_1, false, false)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i+1, "D_LENGTH", (item_length - (razor_data.areaEnd-razor_data.areaStart) + gap), true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i+1, "D_POSITION", razor_data.areaEnd - nudge, true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i+1, "D_UISEL", 0, true)
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i+1, "D_STARTOFFS", item_offset + (razor_data.areaEnd-razor_data.areaStart) - gap, true)
                                    elseif item_start < razor_data.areaStart - nudge and (item_end > razor_data.areaStart - nudge and item_end < razor_data.areaEnd - nudge) then
                                        --Msg("Start of AI is before nudged razor area and end of AI is within nudged razor area")
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", item_length - (item_end - (razor_data.areaStart - nudge)) , true)
                                    elseif item_start > razor_data.areaStart - nudge  and item_end < razor_data.areaEnd - nudge then
                                        --Msg("AI is completely enclosed by nudged razor area")
                                        table.insert(AIs_to_delete, i)
                                    end  
                                end
                                if #AIs_to_delete > 0 then
                                    --Msg(#AIs_to_delete.." Automation Items will be deleted")
                                    for i = #AIs_to_delete, 1, -1 do
                                        
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, AIs_to_delete[i], "D_UISEL", 1, true)
                                        reaper.Main_OnCommand(42086, -1)
    
                                    end
                                end
                            end

                        end
                        if ripple_state == 0 then
                             ---------------- Move automation items to temp track so that source pool data is preserved
                            local temp_track
                            local temp_env
                            local automation_items = {}
                            if reaper.CountAutomationItems(razor_data.envelope) > 0 then
                                for i = 0, reaper.CountAutomationItems(razor_data.envelope) - 1 do
                                    AutoItem = {}
                                    AutoItem.pool = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POOL_ID", 0, false)
                                    AutoItem.position = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", 0, false)
                                    AutoItem.length = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", 0, false)
                                    AutoItem.startoffs = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_STARTOFFS", 0, false)
                                    AutoItem.playrate = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_PLAYRATE", 0, false)
                                    AutoItem.baseline = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_BASELINE", 0, false)
                                    AutoItem.amplitude = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_AMPLITUDE", 0, false)
                                    AutoItem.loopsrc = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LOOPSRC", 0, false)
                                    AutoItem.pool_qnlen = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POOLQNLEN", 0, false)
                                    AutoItem.idx = i 
                                    table.insert(automation_items, AutoItem)                            
                                end
                                --Msg("Track Inserted")
                                reaper.InsertTrackAtIndex(reaper.GetNumTracks(), false)
                                temp_track = reaper.GetTrack(0,reaper.GetNumTracks() -1 )

                                for i = 0, reaper.GetNumTracks() -1 do
                                    local track = reaper.GetTrack(0,i)
                                    reaper.SetMediaTrackInfo_Value(track,"I_SELECTED",0)
                                end

                                reaper.SetMediaTrackInfo_Value(temp_track,"I_SELECTED",1)
                                reaper.Main_OnCommand(40406,-1) --activate volume envelope
                                temp_env = reaper.GetTrackEnvelope(temp_track,0)


                                for i = 1, #automation_items do
                                    local newItemIdx = reaper.InsertAutomationItem(temp_env, automation_items[i].pool, automation_items[i].position, automation_items[i].length)
                                    reaper.GetSetAutomationItemInfo(temp_env, newItemIdx, "D_UISEL", 0, true)
                                end

                                for i = #automation_items, 1, -1 do
                                    local idx= automation_items[i].idx
                                    reaper.GetSetAutomationItemInfo(razor_data.envelope, idx, "D_UISEL", 1, true)
                                    reaper.Main_OnCommand(42086, -1) -- Envelope: Delete automation items
                                end
                            end

                            --Get Values for edge points
                            local retval, initial_leading_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaStart-.0005, 0, 0)
                            local retval, initial_start_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaStart, 0, 0)
                            local retval, initial_end_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaEnd, 0, 0)
                            local retval, initial_trailing_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaEnd+.0005, 0, 0)
                            local retval, nudged_start_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaStart - nudge -.0005, 0, 0)
                            local retval, nudged_end_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaEnd-nudge +.0005, 0, 0)

                            ----------------Restore Automation Items from temp track and delete track temp
                            for i = 1, #automation_items do
                                local newItemIdx = reaper.InsertAutomationItem(razor_data.envelope, automation_items[i].pool, automation_items[i].position, automation_items[i].length)
                                reaper.GetSetAutomationItemInfo(razor_data.envelope, newItemIdx, "D_STARTOFFS", automation_items[i].startoffs, true)
                                reaper.GetSetAutomationItemInfo(razor_data.envelope, newItemIdx, "D_PLAYRATE", automation_items[i].playrate, true)
                                reaper.GetSetAutomationItemInfo(razor_data.envelope, newItemIdx, "D_AMPLITUDE", automation_items[i].amplitude, true)
                                reaper.GetSetAutomationItemInfo(razor_data.envelope, newItemIdx, "D_LOOPSRC", automation_items[i].loopsrc, true)
                                reaper.GetSetAutomationItemInfo(razor_data.envelope, newItemIdx, "D_POOLQNLEN", automation_items[i].pool_qnlen, false)
                                reaper.GetSetAutomationItemInfo(razor_data.envelope, newItemIdx, "D_UISEL", 0, true)
                             end
                        
                            if temp_track then
                                reaper.DeleteTrack(temp_track)
                            end

                            -- Store points in table then delete them from envelope 
                            local points = razor_data.envelopePoints
                            reaper.DeleteEnvelopePointRange(razor_data.envelope, razor_data.areaStart - .0005, razor_data.areaEnd +.0005)
                            reaper.DeleteEnvelopePointRange(razor_data.envelope, razor_data.areaStart -nudge - .0005, razor_data.areaEnd -nudge +.0005)

                            --insert edge points

                            local start_shape = 0
                            local end_shape = 0
                            if #points > 0 then
                                start_shape = points[1].shape
                                end_shape = points[#points].shape
                            else
                                local start_point = reaper.GetEnvelopePointByTime(razor_data.envelope, razor_data.areaStart)
                                local end_point = start_point + 1
                                 _, _, _, start_shape = reaper.GetEnvelopePoint(razor_data.envelope, start_point)
                                 _, _, _, end_shape = reaper.GetEnvelopePoint(razor_data.envelope, end_point)
                            end

                            if razor_data.areaEnd - nudge < razor_data.areaStart then
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart, initial_leading_value, start_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd, initial_leading_value, start_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd + .0005, initial_trailing_value, end_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart - nudge -.0005, nudged_start_value, start_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart - nudge, initial_start_value, start_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd - nudge, initial_end_value, end_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd - nudge + .0005, nudged_end_value, end_shape, 0, false, true)
                            else
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd , initial_end_value, end_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd - nudge, initial_end_value, end_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart - nudge, initial_start_value, start_shape, 0, false, true)
                                reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart - nudge - .0005, nudged_start_value, start_shape, 0, false, true)
                            end
                            

                            ----restore points at nudged position
                            for i = 1 , #points do
                                reaper.InsertEnvelopePoint(razor_data.envelope, points[i].time - nudge, points[i].value, points[i].shape, points[i].tension, false, true)
                            end
                            reaper.Envelope_SortPoints(razor_data.envelope)
                            
                            ---Prevent Snail trail of points
                            
                            reaper.SetCursorContext(2, razor_data.envelope)
                            reaper.Main_OnCommand(43588,0) -- Envelope: Remove unnecessary points
                        end
                        reaper.GetSetEnvelopeInfo_String(razor_data.envelope, "VISIBLE", env_vis, true)
                        reaper.GetSetEnvelopeInfo_String(razor_data.envelope, "SHOWLANE", env_lane, true)

                    end
                else
                    ------- Nudge track razor areas
                    SetTrackRazorEdit(razor_data.track, razor_data.areaStart - nudge, razor_data.areaEnd - nudge, false, razor_data.areaTop, razor_data.areaBottom)

                    if nudge_razor_contents_items then

                        ---------------------- Select items within razor edit areas 
                        local items = razor_data.items
                        for i =  1, #items do
                            reaper.SetMediaItemSelected(items[i], true)
                        end
                    end
                end
            end

            if ripple_state == 2 then -- All track ripple
                 
                 ---- Trim behind
                if (reaper.GetToggleCommandState(42421) == 1 or reaper.GetToggleCommandState(41117) == 1) then -- Options: Always trim content behind razor edits (otherwise, follow media item editing preferences) and Options: Trim content behind media items when editing 
                  RippleAllTrimNudgesLeft()
                end
                UnselectAllItems()
                --Insert and select empty item at earliest razor edit edge
                local first_razor_edge = GetFirstRazorEdge() + nudge -.00000001
                local ripple_item = reaper.AddMediaItemToTrack(reaper.GetTrack(0, 0))
                reaper.SetMediaItemPosition(ripple_item, first_razor_edge, false)
                reaper.SetMediaItemSelected(ripple_item, true)
                --nudge empty item
                ApplyNudgeRGS(0, snap, 0, nudge_unit, nudge_amount, true, 0)
                --delete empty item
                reaper.DeleteTrackMediaItem(reaper.GetTrack(0,0), ripple_item)

            end

            if ripple_state == 1 then -- per track ripple

                ---- Trim behind
                if (reaper.GetToggleCommandState(42421) == 1 or reaper.GetToggleCommandState(41117) == 1) then -- Options: Always trim content behind razor edits (otherwise, follow media item editing preferences) and Options: Trim content behind media items when editing 
                   RippleTrackTrimNudgesLeft()
                end
                
                UnselectAllItems()

                --Insert and select empty item at earliest razor edge on each track
                local first_edges_per_track = {}
                local temp_items = {}
                local razor_tracks = GetRazorTracks()
                for t =1 , #razor_tracks do
                    local track = razor_tracks[t]
                    local track_razors = GetTrackRazorEdits(track)
                    first_edges_per_track[track] =  track_razors[1].areaStart + nudge -.00000001
                end
                for track , edge in pairs(first_edges_per_track) do
                    local ripple_item = reaper.AddMediaItemToTrack(track)
                    reaper.SetMediaItemPosition(ripple_item, edge, false)
                    reaper.SetMediaItemSelected(ripple_item, true)
                    temp_items[track] = ripple_item
                end



                --Nudge empty items
                ApplyNudgeRGS(0, snap, 0, nudge_unit, nudge_amount, true, 0)
                
                --Delete empty items
                for track, item in pairs(temp_items) do
                    reaper.DeleteTrackMediaItem(track, item)
                end
            end


            if ripple_state == 0 and nudge_razor_contents_items then -- no ripple
                local move_points = reaper.GetToggleCommandState(40070) --Options: Move envelope points with media items
                if nudge_razor_contents_envelopes and move_points == 1 then
                    reaper.Main_OnCommand(40070, -1)
                end
                
                ---Nudge Selected Items
                reaper.ApplyNudge(0, 0, 0, 1, nudge, true, 0)
                ---- Trim behind
                if reaper.GetToggleCommandState(42421) == 1 or reaper.GetToggleCommandState(41117) == 1 then -- Options: Always trim content behind razor edits (otherwise, follow media item editing preferences) and Options: Trim content behind media items when editing 
                   TrimNudgesLeft()
                end

                if nudge_razor_contents_envelopes and move_points == 1 then
                    reaper.Main_OnCommand(40070, -1)
                end
            end

            if nudge_cursor_with_razors then
                reaper.SetEditCurPos(cur_pos_1 - nudge, true, false)
            end
            
            if nudge_time_sel_with_razors then
               local time_start, time_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
               reaper.GetSet_LoopTimeRange(true, false, time_start - nudge, time_end - nudge, false)
            end
        end
        LoadTrackSelection(selected_tracks)
        reaper.SetCursorContext(2, selected_envelope)
    end


    

    if not RazorExists() and reaper.CountSelectedMediaItems(0) > 0 and AutoItemSelected() then
        
        local first_selected_item_edge, first_selected_item = GetFirstSelectedItemEdge()
        local snap_offset = reaper.GetMediaItemInfo_Value(first_selected_item,"D_SNAPOFFSET")
        local first_selected_item_edge = first_selected_item_edge + snap_offset
        local first_selected_auto_edge = GetFirstSelectedAutoItemEdge()
         local first_selected_is_auto = false
         if first_selected_auto_edge < first_selected_item_edge then
            first_selected_item_edge = first_selected_auto_edge
            first_selected_is_auto = true
        end
        local move_points = reaper.GetToggleCommandState(40070) --Options: Move envelope points with media items
        
        -- re-get nudge value if nudge snapping is turned on
        if snap == 2 then
            reaper.SetEditCurPos(first_selected_item_edge, false, false)
            ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
            nudge = first_selected_item_edge - reaper.GetCursorPosition()
            reaper.SetEditCurPos(cur_pos_1,false,false)
        end
        
        if first_selected_item_edge > nudge then
            if first_selected_is_auto and snap == 2 then
                reaper.ApplyNudge(0,0,0,1,nudge,true,0)
            else
                ApplyNudgeRGS(0, snap, 0, nudge_unit, nudge_amount, true, 0)
            end
            NudgeAutoItems(-nudge, move_points)
        end
    end


    if not RazorExists() and reaper.CountSelectedMediaItems(0) == 0 and AutoItemSelected() then
        local first_selected_auto_edge = GetFirstSelectedAutoItemEdge()
         -- re-get nudge value if nudge snapping is turned on
        if snap == 2 then
            reaper.SetEditCurPos(first_selected_auto_edge, false, false)
            ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
            nudge = first_selected_auto_edge - reaper.GetCursorPosition()
            reaper.SetEditCurPos(cur_pos_1,false,false)
        end
        if first_selected_auto_edge > nudge then
            NudgeAutoItems(-nudge, 0)
        end
    end 

    if not RazorExists() and reaper.CountSelectedMediaItems(0)>0 and not AutoItemSelected() then
        ApplyNudgeRGS(0, snap, 0, nudge_unit, nudge_amount, true, 0)
    end

    if not RazorExists() and reaper.CountSelectedMediaItems(0) == 0 and not AutoItemSelected() then
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, true, 0)
    end
    reaper.Undo_EndBlock("Contextual Nudge Left", -1)

end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















