-- @description Cut/Copy/Delete Automation From Razor Selection
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0.1
-- @provides
--    [main] RGS_Cut Automation from Razor Selection.lua
--    [main] RGS_Delete Automation from Razor Selection.lua
-- @about 
--  # Cut/Copy/Delete Automation From Razor Selection
--  
--  This is a set of actions for cutting, copying, and deleting.track automation using
--  razor selections. These actions are designed to replicate Pro Tools’ 
--  “Cut/Copy/Clear Special – All Automation” commands inside REAPER.
--  
--  When a Razor selection contains both media items and automation, media items are
--  ignored entirely. Only automation data within the Razor area is cut, copied, or cleared, 
--  even if envelopes are hidden, or shown in the media lane.

--  Automation that is cut or copied can then be pasted using REAPER’s native Paste action, 
--  integrating seamlessly into existing workflows.
--------------------------Debug & Testing -----------------------------------
local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end

--------------------Functions-------------------------

local function RazorExists()
    for i = 0, reaper.CountTracks(0)-1 do
        local _, razor_edits = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i) , "P_RAZOREDITS_EXT", "", false)
        if razor_edits ~= "" then return true end
    end
    return false
end

local function GetGUIDFromEnvelope(envelope)
    local ret2, envelopeChunk = reaper.GetEnvelopeStateChunk(envelope, "")
    local guid = envelopeChunk:match("GUID {(%S+)}")
    if not guid then return nil end
    return "{" .. guid .. "}"
end

local function GetItemsInRange(track, areaStart, areaEnd)
    local items = {}
    local itemCount = reaper.CountTrackMediaItems(track)
    for k = 0, itemCount - 1 do 
        local item = reaper.GetTrackMediaItem(track, k)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local itemEndPos = pos+length

        --check if item is in area bounds
        if (itemEndPos > areaStart and itemEndPos <= areaEnd) or
            (pos >= areaStart and pos < areaEnd) or
            (pos <= areaStart and itemEndPos >= areaEnd) then
                table.insert(items,item)
        end
    end

    return items
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
                local isEnvelope = GUID and GUID ~= '""'
                --get item/envelope data
                local items = {}
                local envelopeName, envelope
                local envelopePoints
                
                if not isEnvelope then
                    items = GetItemsInRange(track, areaStart, areaEnd)
                else
                    if isEnvelope then
                        envelope = reaper.GetTrackEnvelopeByChunkName(track, GUID:sub(2, -2))
                    end

                    if envelope then 
                        local _, envName = reaper.GetEnvelopeName(envelope)
                        envelopeName = envName
                        envelopePoints = GetEnvelopePointsInRange(envelope, areaStart, areaEnd)
                    else
                       envelopeName = nil
                       envelopePoints = {}
                    end
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
                    GUID = isEnvelope and GUID:sub(2, -2) or nil
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
                local isEnvelope = GUID and GUID ~= '""'
        
                --get item/envelope data
                local items = {}
                local envelopeName, envelope
                local envelopePoints
                
                 if not isEnvelope then
                    items = GetItemsInRange(track, areaStart, areaEnd)
                else
                    if isEnvelope then
                        envelope = reaper.GetTrackEnvelopeByChunkName(track, GUID:sub(2, -2))
                    end

                    if envelope then 
                        local _, envName = reaper.GetEnvelopeName(envelope)
                        envelopeName = envName
                        envelopePoints = GetEnvelopePointsInRange(envelope, areaStart, areaEnd)
                    else
                       envelopeName = nil
                       envelopePoints = {}
                    end
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
                    GUID = isEnvelope and GUID:sub(2, -2) or nil
                }
        
                table.insert(areaMap, areaData)
        
                j = j + 3
            end
            end  ---OLD WAY END
        end
    end

    return areaMap
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
            str = str .. ' "" '..areaTop.. " "..areaBottom
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
            if envGUID and GUID ~= '""' and envGUID:sub(2,-2) == GUID then
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

-----------------Main----------------------------
local function Main()
    reaper.Undo_BeginBlock2(0)
    local hidden_envelopes = {}
    local media_lane_envelopes = {}
    ---Store razor edits in table
    local razors = GetRazorEdits()
    ---Clear razor edits
    for i = 0, reaper.CountTracks(0) -1 do
        local track = reaper.GetTrack(0, i)
        reaper.GetSetMediaTrackInfo_String(track, "P_RAZOREDITS", "", true)
    end
    for i = 1, #razors do
        local razor_data = razors[i]
        if razor_data.isEnvelope and razor_data.envelope then
            local _, visible = reaper.GetSetEnvelopeInfo_String(razor_data.envelope,"VISIBLE", "",false)
            local _, show_lane = reaper.GetSetEnvelopeInfo_String(razor_data.envelope,"SHOWLANE", "",false)
            if visible == "0" then
                reaper.GetSetEnvelopeInfo_String(razor_data.envelope,"VISIBLE", "1",true)
                table.insert(hidden_envelopes, razor_data.envelope)
            end
            if show_lane == "0" then
                reaper.GetSetEnvelopeInfo_String(razor_data.envelope,"SHOWLANE", "1",true)
                table.insert(media_lane_envelopes, razor_data.envelope)
            end
            SetEnvelopeRazorEdit(razor_data.envelope, razor_data.areaStart, razor_data.areaEnd, false)
        end
    end
    reaper.Main_OnCommand(40057, 0) -- copy
    for i = 1 , #razors do
        local razor_data = razors[i]
        if not razor_data.isEnvelope then
            SetTrackRazorEdit(razor_data.track, razor_data.areaStart, razor_data.areaEnd, false, razor_data.areaTop, razor_data.areaBottom)
        end
    end
    for i = 1, #hidden_envelopes do
        local env = hidden_envelopes[i]
        reaper.GetSetEnvelopeInfo_String(env,"VISIBLE", "0" ,true)
    end
    for i = 1, #media_lane_envelopes do
        local env = media_lane_envelopes[i]
        reaper.GetSetEnvelopeInfo_String(env,"SHOWLANE", "0" ,true)
    end
    reaper.Undo_EndBlock2(0,"Copy Automation", -1)
end



--------Run----------------------------
reaper.PreventUIRefresh(1)
if RazorExists() then
    if reaper.GetToggleCommandState(42459) == 1 then -- 42459 Options: Razor edits in media item lane affect all track envelopes
        Main()
    else 
        reaper.Main_OnCommand(42459, 0) -- 42459 Options: Razor edits in media item lane affect all track envelopes
        Main()
        reaper.Main_OnCommand(42459, 0) -- 42459 Options: Razor edits in media item lane affect all track envelopes
    end
else
    reaper.ShowMessageBox("No razor areas present. Nothing was copied", "Warning", 0)   
end
reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()







