-- @noindex

--------------------Functions-------------------------
local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end


-----------------Main----------------------------
local function Main()
    local track_count = reaper.CountSelectedTracks(0)
    for i = 0 , track_count -1 do
        local vis
        local track = reaper.GetSelectedTrack(0, i)
        local send_count = reaper.GetTrackNumSends(track, 0x10000000)
        for j = 0, send_count -1 do
            local env = reaper.GetTrackSendInfo_Value(track, 0, j, "P_ENV:<PANENV")
            if reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
                _, vis = reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "", false) -- Check if envelope are already visible
            end
            if vis == "1" then break end
        end
        if vis == "1" then -- Hide all envelopes if any are already visible
            for j = 0, send_count -1 do
                local env = reaper.GetTrackSendInfo_Value(track, 0, j, "P_ENV:<PANENV")
                if reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
                    reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "0", true)
                end
            end
        else
            for j = 0, send_count -1 do --show  envelopes if all are hidden
                local env = reaper.GetTrackSendInfo_Value(track, 0, j, "P_ENV:<PANENV")
                if reaper.ValidatePtr2(0, env, "TrackEnvelope*") then
                    reaper.GetSetEnvelopeInfo_String(env, "ACTIVE", "1", true)
                    reaper.GetSetEnvelopeInfo_String(env, "VISIBLE", "1", true)
                end
            end
        end
    end
        
end
--------Run----------------------------
reaper.PreventUIRefresh(1)

reaper.Undo_BeginBlock()
Main()
reaper.Undo_EndBlock("Show/Hide Send Envelopes", -1) -- End of the undo block. Leave it at the bottom of your main function.
reaper.TrackList_AdjustWindows(true)
reaper.UpdateArrange()
reaper.PreventUIRefresh(-1)






                 















