-- @noindex
--------------------------Debug & Testing -----------------------------------

----- Console Message Function-----------
--reaper.ShowConsoleMsg("")

local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end

--------------------Functions-------------------------
local function SaveRazorEdits(table)
    for i = 0, reaper.CountTracks(0)-1 do
        _ , table[reaper.GetTrack(0,i)] = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0,i), "P_RAZOREDITS_EXT", "", false)
    end
end

local function LoadRazorEdits(table)
    for i = 0, reaper.CountTracks(0)-1 do
        reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0,i), "P_RAZOREDITS_EXT", table[reaper.GetTrack(0,i)] , true)
    end
end


local function RazorExists()
    for i = 0, reaper.CountTracks(0)-1 do
        local _, razor_edits = reaper.GetSetMediaTrackInfo_String(reaper.GetTrack(0, i) , "P_RAZOREDITS_EXT", "", false)
        if razor_edits ~= "" then return true end
    end
    return false
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
        end
    end

    return areaMap
end



local function CountRazorItems()
    local razor_item_count = 0
    local razor_edits = GetRazorEdits()
        for r = 1, #razor_edits do
            local razor = razor_edits[r]
            razor_item_count = razor_item_count + #razor.items
        end
    return razor_item_count
end

local function GetRazorItemInfo()
    local items ={}
    local razor_edits = GetRazorEdits()
    for r = 1, #razor_edits do
        local razor = razor_edits[r]
        if #razor.items > 0 then     
            for i = 1 , #razor.items do
                local item_info ={} 
                local _, chunk = reaper.GetItemStateChunk(razor.items[i], "", false)
                item_info.chunk = chunk
                item_info.track = razor.track
                table.insert (items, item_info)
            end
        end
    end
    return items
end

local function DeleteRazorItems()
    local razor_edits = GetRazorEdits()
        for r = 1, #razor_edits do
        local razor = razor_edits[r]
            if #razor.items > 0 then
                for i = 1 , #razor.items do
                reaper.DeleteTrackMediaItem(razor.track,razor.items[i])
                end
            end
        end
end

local function RestoreItems(items)
     for i = 1, #items do
        local restored_item = reaper.AddMediaItemToTrack(items[i].track)
        reaper.SetItemStateChunk(restored_item, items[i].chunk)
    end
end

-----------------Main----------------------------
local function Main()
    local initial_razor_edits = {}
    SaveRazorEdits(initial_razor_edits)
    if CountRazorItems() == 0 then
        reaper.Main_OnCommand(40006, 0) -- delete
    else
        local items = GetRazorItemInfo()
        DeleteRazorItems()
        reaper.Main_OnCommand(40006, 0) -- delete
        RestoreItems(items)
    end
    LoadRazorEdits(initial_razor_edits)
end
--------Run----------------------------


reaper.Undo_BeginBlock()

if RazorExists() then

    if reaper.GetToggleCommandState(42459) == 1 then -- 42459 Options: Razor edits in media item lane affect all track envelopes
        Main()
    else 
        reaper.Main_OnCommand(42459, 0) -- 42459 Options: Razor edits in media item lane affect all track envelopes
        Main()
        reaper.Main_OnCommand(42459, 0) -- 42459 Options: Razor edits in media item lane affect all track envelopes
    end
   
end

reaper.Undo_EndBlock("Delete Automation From Razor Areas", 0)

reaper.UpdateArrange()






