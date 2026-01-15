-- @noindex

local no_sws
local ScriptName = "Nudge Start of Razor or Item Selection to Cursor"
if not reaper.SNM_GetIntConfigVar then
    no_sws = true
end

if no_sws then
     reaper.MB("SWS/S&M extension is\nrequired to run this script.\nPlease install the missing extension\nand run the script again",ScriptName, 0)
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


local nudge_time_sel_with_razors = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_time_sel_with_razors")) -- Also nudge the ti1me selection when nudging razor edits
local nudge_razor_contents_items = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_items"))
local nudge_razor_contents_envelopes = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_envelopes"))

    
--------------------Functions-------------------------
local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
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

local function RazorExistsOnSelectedTracks()
    for i = 0, reaper.CountSelectedTracks(0)-1 do
        local _, razor_edits = reaper.GetSetMediaTrackInfo_String(reaper.GetSelectedTrack(0, i) , "P_RAZOREDITS_EXT", "", false)
        if razor_edits ~= "" then return true end
    end
    return false
end

local function SetTrackRazorEdit(track, areaStart, areaEnd, clearSelection)
    if clearSelection == nil then clearSelection = false end
    
    if clearSelection then
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', '', false)
    
        --parse string, all this string stuff could probably be written better
        local str = {}
        for j in string.gmatch(area, "%S+") do
            table.insert(str, j)
        end
        
        --strip existing selections across the track
        local j = 1
        while j <= #str do
            local GUID = str[j+2]
            if GUID == '""' then 
                str[j] = ''
                str[j+1] = ''
                str[j+2] = ''
            end

            j = j + 3
        end

        --insert razor edit 
        local REstr = tostring(areaStart) .. ' ' .. tostring(areaEnd) .. ' ""'
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
        str = str .. tostring(areaStart) .. ' ' .. tostring(areaEnd) .. '  ""'
        
        local ret, area = reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', str, true)
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

local function GetFirstSelectedItemEdge()
    local item_count = reaper.CountSelectedMediaItems(0)
    local first_edge = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_POSITION") + reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_SNAPOFFSET")

    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_offset = reaper.GetMediaItemInfo_Value(item, "D_SNAPOFFSET")
            local item_start = item_position + item_offset
            if item_start < first_edge then first_edge = item_start end
        end
    end

    return first_edge
end

local function TrimNudgesRight()
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
                reaper.SplitMediaItem(item, new_data.areaEnd)
                local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                if item_start > new_data.areaStart then
                    reaper.DeleteTrackMediaItem(new_data.track, item)
                else
                    item_right = reaper.SplitMediaItem(item, new_data.areaStart)

                    if item_right then 
                        reaper.DeleteTrackMediaItem(new_data.track, item_right)
                    else
                        if not (math.abs(item_end - new_data.areaStart) < .000000001) then
                            reaper.DeleteTrackMediaItem(new_data.track, item)
                        end

                    end
                end
            end   
        end
    end
    if reaper.GetToggleCommandState(40041) == 1 then-- Prevent rogue fades when trim behind and auto crossfade are both enabled
        reaper.ApplyNudge(0, 0, 0, 1,.00000001, false, 0)
        reaper.ApplyNudge(0, 0, 0, 1,.0000000101, true, 0)
    end
end

local function TrimNudgesLeft()
    local new_razors = GetRazorEdits()
    for n = #new_razors, 1, -1 do
        local new_data = new_razors[n]
        local new_items = new_data.items 
        for i = #new_items , 1, -1  do
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
                        if not (math.abs(item_end - new_data.areaStart) < .000000001) then
                            reaper.SplitMediaItem(item, new_data.areaEnd)
                            reaper.DeleteTrackMediaItem(new_data.track, item)
                        end
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
            for i = #new_items , 1 , -1  do
                local item = new_items[i]
                local item_is_new = true
                for r = #razors , 1, -1 do 
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
                                if not (math.abs(item_end - new_data.areaStart) < .000000001) then
                                    reaper.SplitMediaItem(item, new_data.areaEnd)
                                    reaper.DeleteTrackMediaItem(new_data.track, item)
                                end
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
            for i = #new_items, 1 , -1 do
                local item = new_items[i]
                local item_is_new = true
                for r = #razors , 1, -1 do 
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
                                if not (math.abs(item_end - new_data.areaStart) < .000000001) then
                                    reaper.SplitMediaItem(item, new_data.areaEnd)
                                    reaper.DeleteTrackMediaItem(new_data.track, item)
                                end
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
-----------------Main----------------------------
local function Main()
    reaper.Undo_BeginBlock()
    
    local cursor = reaper.GetCursorPosition() 
    local first_edge = cursor
    local nudge_reverse = false
    
    
    if RazorExists() then first_edge = GetFirstRazorEdge() end
    if not RazorExists() and reaper.CountSelectedMediaItems(0) > 0 then first_edge = GetFirstSelectedItemEdge() end
    
    ----------------- Get Nudge Direction and nudge value in seconds
    if first_edge > cursor then 
        nudge_reverse = true
        nudge = first_edge - cursor
    end
    if first_edge < cursor then nudge = cursor - first_edge end
    if first_edge == cursor  then return end





    if RazorExists() then
        local selected_envelope = reaper.GetSelectedEnvelope(0)
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

                if not nudge_reverse then

                    ----Nudge envelope razor edits
                    SetEnvelopeRazorEdit(razor_data.envelope , razor_data.areaStart + nudge, razor_data.areaEnd + nudge, false )
                    
                    if nudge_razor_contents_envelopes then
                        if ripple_state == 0 then
                            --Get Values for edge points
                            local retval, start_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaStart, 0, 0)
                            local retval, end_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaEnd, 0, 0)
                            local retval, trailing_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaEnd+nudge +.0005, 0, 0)
                            
                            -- Store points in table then delete them from envelope 
                            local points = razor_data.envelopePoints
                            reaper.DeleteEnvelopePointRange(razor_data.envelope, razor_data.areaStart, razor_data.areaEnd + nudge)

                            --Insert Edge Points
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
                            
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart + nudge, start_value, start_shape, 0, false, true)
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart, start_value, start_shape, 0, false, true)
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd + nudge, end_value, end_shape, 0, false, true)
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd + nudge + .0005, trailing_value, end_shape, 0, false, true)

                            
                            --restore points at nudged position
                            for i = 1, #points do
                                reaper.InsertEnvelopePoint(razor_data.envelope, points[i].time + nudge, points[i].value, points[i].shape, points[i].tension, false, true)
                            end
                            reaper.Envelope_SortPoints(razor_data.envelope)

                            --prevent Snail trail of points

                            reaper.SetCursorContext(2, razor_data.envelope)
                            reaper.Main_OnCommand(43588,0) -- Envelope: Remove unnecessary points
                        end


                        if reaper.CountAutomationItems(razor_data.envelope) > 0 then
                            -------- Select AIs that are in the razor areas
                            for i = 0, reaper.CountAutomationItems(razor_data.envelope) -1 do
                                local item_start = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", 0, false)
                                local item_length = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", 0, false)
                                local item_end = item_start + item_length
                                if item_start <= razor_data.areaEnd and item_end > razor_data.areaStart then
                                    reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_UISEL", 1, true)
                                end
                            end

                            ----------------------------Split AIs at razor edges
                            reaper.SetEditCurPos(razor_data.areaStart, false, false)
                            reaper.Main_OnCommand(42087, -1) -- Envelope: Split automation items
                            reaper.SetEditCurPos(razor_data.areaEnd, false, false)
                            reaper.Main_OnCommand(42087, -1) -- Envelope: Split automation items
                            reaper.SetEditCurPos(cursor, false, false)
                            
                            -------------------Nudge AIs
                            if ripple_state == 0 then
                                for i = 0, reaper.CountAutomationItems(razor_data.envelope) -1 do
                                    local item_start = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", 0, false)
                                    local item_length = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", 0, false)
                                    local item_end = item_start + item_length
                                    if item_start < razor_data.areaEnd and item_end > razor_data.areaStart then
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", item_start + nudge, true)
                                    end
                                end
                            end
                        end
                    end
                else
                     SetEnvelopeRazorEdit(razor_data.envelope , razor_data.areaStart - nudge, razor_data.areaEnd - nudge, false )
                    
                    if nudge_razor_contents_envelopes then
                        if ripple_state == 0 then
                            --Get Values for edge points
                            local retval, start_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaStart, 0, 0)
                            local retval, end_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaEnd, 0, 0)
                            local retval, trailing_value = reaper.Envelope_Evaluate(razor_data.envelope, razor_data.areaStart - nudge -.0005, 0, 0)
                            
                            -- Store points in table then delete them from envelope 
                            local points = razor_data.envelopePoints
                            reaper.DeleteEnvelopePointRange(razor_data.envelope, razor_data.areaStart - nudge, razor_data.areaEnd)

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

                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd , end_value, end_shape, 0, false, true)
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaEnd - nudge, end_value, end_shape, 0, false, true)
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart - nudge, start_value, start_shape, 0, false, true)
                            reaper.InsertEnvelopePoint(razor_data.envelope, razor_data.areaStart - nudge - .0005, trailing_value, start_shape, 0, false, true)
                            

                            ----restore points at nudged position
                            for i = 1 , #points do
                                reaper.InsertEnvelopePoint(razor_data.envelope, points[i].time - nudge, points[i].value, points[i].shape, points[i].tension, false, true)
                            end
                            reaper.Envelope_SortPoints(razor_data.envelope)
                            
                            ---Prevent Snail trail of points
                            --[[ local last_point = reaper.GetEnvelopePointByTime(razor_data.envelope, razor_data.areaEnd - nudge)
                            local _, _, last_value = reaper.GetEnvelopePoint(razor_data.envelope, last_point)
                            local points_to_delete = {} 
                            for p =  last_point + 2, reaper.CountEnvelopePoints(razor_data.envelope) - 1  do
                                local _, _,  value = reaper.GetEnvelopePoint(razor_data.envelope, p)
                                if value == last_value then
                                    table.insert(points_to_delete, p)
                                else
                                    break
                                end
                            end
                            for d = #points_to_delete, 1, -1 do
                                reaper.DeleteEnvelopePointEx(razor_data.envelope, -1, points_to_delete[d])
                            end ]]
                            reaper.SetCursorContext(2, razor_data.envelope)
                            reaper.Main_OnCommand(43588,0) -- Envelope: Remove unnecessary points
                            
                        end

                    

                        if reaper.CountAutomationItems(razor_data.envelope) > 0 then
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
                            reaper.SetEditCurPos(cursor, false, false)
                            
                            ----------------Nudge AIS
                            if ripple_state == 0 then
                                for i = 0, reaper.CountAutomationItems(razor_data.envelope) -1 do
                                    local item_start = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", 0, false)
                                    local item_length = reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_LENGTH", 0, false)
                                    local item_end = item_start + item_length
                                    if item_start < razor_data.areaEnd and item_end > razor_data.areaStart then
                                        reaper.GetSetAutomationItemInfo(razor_data.envelope, i, "D_POSITION", item_start - nudge, true)
                                    end
                                end
                            end
                        end
                    end
                end

            else
                --------------------Nudge Razor Track Areas
                if not nudge_reverse then
                    SetTrackRazorEdit(razor_data.track, razor_data.areaStart + nudge, razor_data.areaEnd + nudge, false)
                else
                    SetTrackRazorEdit(razor_data.track, razor_data.areaStart - nudge, razor_data.areaEnd - nudge, false)
                end

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
            if not nudge_reverse then
                UnselectAllItems()
                --Insert and select empty item at earliest razor edit edge
                local first_razor_edge = GetFirstRazorEdge()
                local ripple_item = reaper.AddMediaItemToTrack(reaper.GetTrack(0, 0))
                reaper.SetMediaItemPosition(ripple_item, first_razor_edge - nudge -.00000001, false)
                reaper.SetMediaItemSelected(ripple_item, true)
                
                --nudge empty item
                reaper.ApplyNudge(0, 0, 0, 1, nudge, false, 0)
                --delete empty item
                reaper.DeleteTrackMediaItem(reaper.GetTrack(0,0), ripple_item)
            else
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
                reaper.ApplyNudge(0, 0, 0, 1, nudge, true, 0)
                --delete empty item
                reaper.DeleteTrackMediaItem(reaper.GetTrack(0,0), ripple_item)
            end
        end

        if ripple_state == 1  then -- per track ripple
            if not nudge_reverse then
            
                UnselectAllItems()
                --Insert and select empty item at earliest razor edge on each track
                local first_edges_per_track = {}
                local temp_items = {}
                local razor_tracks = GetRazorTracks()
                for t =1 , #razor_tracks do
                    local track = razor_tracks[t]
                    local track_razors = GetTrackRazorEdits(track)
                    first_edges_per_track[track] =  track_razors[1].areaStart - nudge -.00000001
                end
                for track , edge in pairs(first_edges_per_track) do
                    local ripple_item = reaper.AddMediaItemToTrack(track)
                    reaper.SetMediaItemPosition(ripple_item, edge, false)
                    reaper.SetMediaItemSelected(ripple_item, true)
                    temp_items[track] = ripple_item
                end

                --Nudge empty items
                reaper.ApplyNudge(0, 0, 0, 1, nudge, false, 0)

                --Delete empty items
                for track, item in pairs(temp_items) do
                    reaper.DeleteTrackMediaItem(track, item)
                end
            
            else
            
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
                reaper.ApplyNudge(0, 0, 0, 1, nudge, true, 0)
                
                --Delete empty items
                for track, item in pairs(temp_items) do
                    reaper.DeleteTrackMediaItem(track, item)
                end
            end
        end


        if ripple_state == 0 and nudge_razor_contents_items then -- no ripple
            local move_points = reaper.GetToggleCommandState(40070) --Options: Move envelope points with media items
            if nudge_razor_contents_envelopes and move_points == 1 then
                reaper.Main_OnCommand(40070, -1)
            end
            reaper.ApplyNudge(0, 0, 0, 1, nudge, nudge_reverse, 0)
            if reaper.GetToggleCommandState(42421) == 1 or reaper.GetToggleCommandState(41117) == 1 then  -- Options: Always trim content behind razor edits (otherwise, follow media item editing preferences) and Options: Trim content behind media items when editing 
                if not nudge_reverse then
                    TrimNudgesRight()
                else
                    TrimNudgesLeft()
                end
            end
            if nudge_razor_contents_envelopes and move_points == 1 then
                reaper.Main_OnCommand(40070, -1)
            end
        end
        
        if nudge_time_sel_with_razors then
           local time_start, time_end = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
           if not nudge_reverse then
                reaper.GetSet_LoopTimeRange(true, false, time_start + nudge, time_end + nudge, false)
            else
                reaper.GetSet_LoopTimeRange(true, false, time_start - nudge, time_end - nudge, false)
            end
        end
        reaper.SetCursorContext(2,selected_envelope )
    end

    if not RazorExists() and reaper.CountSelectedMediaItems(0) > 0 then
        reaper.ApplyNudge(0, 0, 0, 1, nudge, nudge_reverse, 0)
    end

    reaper.Undo_EndBlock("Nudge First Edge of Razor or Items to Cursor", -1)
end
--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()


                 















