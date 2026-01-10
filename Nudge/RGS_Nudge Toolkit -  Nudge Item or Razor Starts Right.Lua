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
----------------Functions------------------------
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

local function RazorExists()
    for i = 0, reaper.CountTracks(0)-1 do
        local _, razor_edits = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i) , "P_RAZOREDITS_EXT", "", false)
        if razor_edits ~= "" then return true end
    end
    return false
end

local function GetGUIDFromEnvelope(envelope)
    local ret2, envelopeChunk = reaper.GetEnvelopeStateChunk(envelope, "")
    local GUID = "{" ..  string.match(envelopeChunk, "GUID {(%S+)}") .. "}"
    return GUID
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

local function GetShortestSelectedItem()
    local item_count = reaper.CountSelectedMediaItems(0)
    local shortest_length = reaper.GetMediaItemInfo_Value(reaper.GetSelectedMediaItem(0, 0), "D_LENGTH")
    local shortest_item = reaper.GetSelectedMediaItem(0,0)
    if item_count > 1 then
        for i = 1, item_count - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local item_length= reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if item_length < shortest_length then 
                shortest_length = item_length
                shortest_item = item
            end
        end
    end
    return shortest_length, shortest_item
end

local function GetShortestSelectedAutoItem()
    if AutoItemSelected() then
        local shortest_length = math.huge
        for i = 0, reaper.CountTracks(0)-1 do
            local track = reaper.GetTrack(0, i)
            for j = 0, reaper.CountTrackEnvelopes(track)-1 do
                local env = reaper.GetTrackEnvelope(track, j)
                local _, env_vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
                if tonumber(env_vis) == 1 then
                    for k = 0, reaper.CountAutomationItems(env) - 1 do
                        if reaper.GetSetAutomationItemInfo(env ,k, "D_UISEL", 0, false) ~=0 then
                            local length = reaper.GetSetAutomationItemInfo(env ,k, "D_LENGTH", 0, false)
                            if length < shortest_length then
                                shortest_length = length
                            end
                        end
                    end
                end
            end
        end
        return shortest_length
    end
end


local function TrimAutoItemsStart(trim_amount)
    for i = 0, reaper.CountTracks(0)-1 do
        local track = reaper.GetTrack(0, i)
        for j = 0, reaper.CountTrackEnvelopes(track)-1 do
            local env = reaper.GetTrackEnvelope(track, j)
            local _, env_vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false)
            if tonumber(env_vis) == 1 then
                for k = 0, reaper.CountAutomationItems(env) - 1 do
                    if reaper.GetSetAutomationItemInfo(env ,k, "D_UISEL", 0, false) ~=0 then
                        local position = reaper.GetSetAutomationItemInfo(env,k,"D_POSITION", 0, false )
                        local length = reaper.GetSetAutomationItemInfo(env,k,"D_LENGTH", 0, false )
                        local start_offset = reaper.GetSetAutomationItemInfo(env,k,"D_STARTOFFS", 0, false)
                        reaper.GetSetAutomationItemInfo(env,k,"D_POSITION", position + trim_amount, true)
                        reaper.GetSetAutomationItemInfo(env,k,"D_LENGTH" , length - trim_amount, true )
                        reaper.GetSetAutomationItemInfo(env,k,"D_STARTOFFS", start_offset+trim_amount, true)

                    end
                end
            end
        end
    end
end
-----------------Main----------------------------

local function Main()
    if RazorExists() then
        local initial_cur_pos = reaper.GetCursorPosition()
        reaper.SetEditCurPos(GetFirstRazorEdge(), false, false)
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, false, 0)
        local nudge = reaper.GetCursorPosition() - GetFirstRazorEdge()
        reaper.SetEditCurPos(initial_cur_pos, false, false)

        local razors = GetRazorEdits()

        for i = 1, #razors do 
            local razor_data = razors[i]
            local length = razor_data.areaEnd - razor_data.areaStart
            if length <= nudge then
                return
            end
        end
        
        for i = 0, reaper.CountTracks(0) -1 do
            local track = reaper.GetTrack(0, i)
            reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
        end
        
        for i = 1, #razors do 
            local razor_data = razors[i]
            if razor_data.isEnvelope then
                SetEnvelopeRazorEdit(razor_data.envelope, razor_data.areaStart + nudge, razor_data.areaEnd, false)
            else
                SetTrackRazorEdit(razor_data.track, razor_data.areaStart + nudge,razor_data.areaEnd, false, razor_data.areaTop, razor_data.areaBottom)
            end
        end

    elseif reaper.CountSelectedMediaItems(0) > 0 then
        if AutoItemSelected() then
            local first_item_edge, first_item = GetFirstSelectedItemEdge(false)
            local shortest_item_length = GetShortestSelectedItem()
            local shortest_auto_item_length = GetShortestSelectedAutoItem()
            local initial_cur_pos = reaper.GetCursorPosition()
            reaper.SetEditCurPos(first_item_edge, false, false)
            ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, false, 0)
            local nudge = reaper.GetCursorPosition() - first_item_edge
            reaper.SetEditCurPos(initial_cur_pos, false, false)

            if nudge < shortest_item_length and nudge < shortest_auto_item_length  then
                TrimAutoItemsStart(nudge)
                ApplyNudgeRGS(0, snap, 1, nudge_unit, nudge_amount, false, 0)
            end
        else
            ApplyNudgeRGS(0, snap, 1, nudge_unit, nudge_amount, false, 0)
        end
    elseif AutoItemSelected() then
        local first_auto_item_edge = GetFirstSelectedAutoItemEdge()
        local shortest_auto_item_length = GetShortestSelectedAutoItem()
        local initial_cur_pos = reaper.GetCursorPosition()
        reaper.SetEditCurPos(first_auto_item_edge, false, false)
        ApplyNudgeRGS(0, snap, 6, nudge_unit, nudge_amount, false, 0)
        local nudge = reaper.GetCursorPosition() - first_auto_item_edge
        reaper.SetEditCurPos(initial_cur_pos, false, false)
        if nudge < shortest_auto_item_length then
            TrimAutoItemsStart(nudge)
        end
    end 
end


--------Run----------------------------
reaper.PreventUIRefresh(1)
Main()
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()










                 















