-- @description ReaSync
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1..2.0
-- @screenshot https://i.ibb.co/sp1FjbSt/Screenshot-2026-05-20-at-16-05-40.png
-- @about 
--  # ReaSync
--
--  **ReaSync** is a waveform matching tool for Reaper. ReaSync automatically repositions
--  selected audio items by matching them against a reference track. Originally designed 
--  for syncing dialog recordings, it may be useful for aligning any audio captured 
--  simultaneously from multiple sources or for realigning source recordings to a final 
--  edit. 
--  ## Features
--
--  - Adjustable match threshold to balance sensitivity vs. accuracy
--  - Match report with confidence scores for each item
--  - Option to move matched items to a new track
--## Limitations
--
--  - Matching accuracy depends on the length and content of the audio. Short clips
--  or items with little transient content (e.g. sustained pads, silence-heavy
--  recordings) may produce less reliable results. 
--  - ReaSync is intended to get items in the right place, not to achieve phase 
--  or sample-accurate alignment.
-- @changelog
--  - Fix crash when trying to sync very long items
-- @link Forum thread https://forum.cockos.com/showthread.php?t=309136
--  
--
--  

local ScriptName = "ReaSync"
local ScriptVersion = "1.2.0"

local show_debug_messages = false
local SR = 2000
local MAX_TABLE_HEIGHT = 500
local RAW_CONFIDENCE_SCALE_MAX = 8
local ANALYSIS_MAX_SEC = 15
local ANALYSIS_SCAN_STEP_SEC = 5
local FRAME_BUDGET = 0.01




local function TestVersion(version,version_min)
  local i = 0
  for num in string.gmatch(tostring(version),'%d+') do
    i = i + 1
    if version_min[i] and tonumber(num) > version_min[i] then
      return true
    elseif version_min[i] and tonumber(num) < version_min[i] then
      return false
    end
  end
  if i < #version_min then return false
  else return true end
end


local no_imgui
local no_js
local missing_dependencies = ""
if not reaper.ImGui_GetBuiltinPath then
    no_imgui = true
else    
    local _,_,imgui_version = reaper.ImGui_GetVersion()
    if not TestVersion(imgui_version,{0,10,0,5}) then
        no_imgui = true
    end
end

if no_imgui then
    missing_dependencies = "ReaImGui (version 0.10.0.5 or higher)\n"
end

if not reaper.JS_Window_GetTitle then
    no_js = true
    missing_dependencies =  missing_dependencies.."js_ReaScriptAPI\n" 
end

if missing_dependencies ~= "" then 
    reaper.MB("The following extensions are\nrequired to run this script:\n\n"..missing_dependencies.."\nPlease install the missing extensions\nand run the script again",ScriptName, 0)
    if reaper.ReaPack_BrowsePackages then
        if no_imgui then
            reaper.ReaPack_BrowsePackages("ReaImGui: ReaScript binding for Dear ImGui")
        end
        if no_js then
            reaper.ReaPack_BrowsePackages("js_ReaScriptAPI: API functions for ReaScripts")
        end
    end
    return
end




package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua"
local ImGui = require "imgui" "0.10.0.5"
local ctx = ImGui.CreateContext(ScriptName)

ImGui.SetConfigVar(ctx, ImGui.ConfigVar_KeyRepeatDelay, .5)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_KeyRepeatRate, .1)

local is_macos = reaper.GetOS():match("OS")

local shortcut_cache = {}
local shortcut_cache_checksum
local kb_ini



local processing_start_time
local main_window_flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_TopMost
local threshold_tooltip = "Items with a confidence score below this value will not be\nconsidered a match. Lower values are more forgiving (better\nfor short clips and alternate microphones) but may produce\nfalse matches. Higher values are stricter but may miss valid\nmatches"
local show_report = true
local move_to_new_track = true
local time_start, time_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
local time_start_string
local time_end_string
local time_length_string
local range_is_time_selection = false
local range_is_track = true
local track_combo_preview
local proj = reaper.EnumProjects(-1)
local dirty = reaper.IsProjectDirty(0)
local report_table
local use_first_selected_track = true
local track
local display_confidence_threshold = 7
local raw_confidence_threshold = (display_confidence_threshold / 10) * RAW_CONFIDENCE_SCALE_MAX
local threshold_slider = false
local report_selection = -1
local match_found = false
local match_track
local results = {}
local valid_items = {}
local invalid_items = {}
local processing = false
local processing_items = nil
local processing_index = 1
local processing_results = {}
local current_alignment = nil
local ref_track = nil
local finalize = false
local processing_time
local processing_time_string
local match_count = 0
local no_match_count = 0
local invalid_count = 0
local total_count





local function Msg(param)
    if show_debug_messages then
        reaper.ShowConsoleMsg(tostring(param) .. "\n")
    end
end

local function read_audio(item, start_t, duration)
    local take = reaper.GetActiveTake(item)
    if not take then
        return nil
    end
    local accessor = reaper.CreateTakeAudioAccessor(take)
    local accessor_start = reaper.GetAudioAccessorStartTime(accessor)
    local accessor_end = reaper.GetAudioAccessorEndTime(accessor)

    -- if no start/duration provided, read the whole item (clamped to ANALYSIS_MAX_SEC)
    if not start_t then
        start_t = accessor_start
    end
    if not duration then
        duration = math.min(accessor_end - accessor_start, ANALYSIS_MAX_SEC)
    end

    -- clamp to accessor bounds
    start_t = math.max(start_t, accessor_start)
    local end_t = math.min(start_t + duration, accessor_end)
    duration = end_t - start_t

    local samples = math.floor(duration * SR)
    if samples < 10 then
        reaper.DestroyAudioAccessor(accessor)
        return nil
    end
    local src = reaper.GetMediaItemTake_Source(take)
    local ch = math.max(1, reaper.GetMediaSourceNumChannels(src))
    local buf = reaper.new_array(samples * ch)
    reaper.GetAudioAccessorSamples(accessor, SR, ch, start_t, samples, buf)
    reaper.DestroyAudioAccessor(accessor)
    local t = buf.table()
    local mono = {}
    local idx = 1
    for i = 1, samples do
        local sum = 0
        for c = 1, ch do
            sum = sum + t[idx]
            idx = idx + 1
        end
        mono[i] = sum / ch
    end
    return mono
end

local function read_track_audio(track, start_time, duration, sr)
    local accessor = reaper.CreateTrackAudioAccessor(track)
    if not accessor then
        return nil
    end

    local samples = math.floor(duration * sr)
    if samples < 10 then
        reaper.DestroyAudioAccessor(accessor)
        return nil
    end
    local track_channels = reaper.GetMediaTrackInfo_Value(track, "I_NCHAN")
    local ch = math.max(1, math.floor(track_channels))

    local buf = reaper.new_array(samples * ch)

    local ok = reaper.GetAudioAccessorSamples(accessor, sr, ch, start_time, samples, buf)

    reaper.DestroyAudioAccessor(accessor)

    if not ok or ok == 0 then
        return nil
    end

    local t = buf.table()
    local mono = {}
    local idx = 1

    for i = 1, samples do
        local sum = 0

        for c = 1, ch do
            sum = sum + t[idx]
            idx = idx + 1
        end

        mono[i] = sum / ch
    end
    return mono
end

local function normalize(x)
    local maxv = 0
    for i = 1, #x do
        maxv = math.max(maxv, math.abs(x[i]))
    end
    if maxv < 1e-9 then
        return x
    end
    for i = 1, #x do
        x[i] = x[i] / maxv
    end
    return x
end

local function envelope(x, is_short)
    local out = {}
    local prev = 0
    local smooth = is_short and 0.7 or 0.9
    for i = 1, #x do
        local v = math.abs(x[i])
        prev = prev * smooth + v * (1 - smooth)
        out[i] = prev
    end
    return out
end

local function get_peaks(x)
    local peaks = {}
    local sorted = {}
    for i = 1, #x do
        sorted[i] = x[i]
    end
    table.sort(sorted)
    local percentile = 0.85
    -- adaptive threshold for short clips
    if #x < SR * 2 then
        percentile = 0.65
    elseif #x < SR * 4 then
        percentile = 0.75
    end
    local cutoff = sorted[math.floor(#sorted * percentile)]
    for i = 2, #x - 1 do
        if x[i] > cutoff and x[i] > x[i - 1] and x[i] > x[i + 1] then
            peaks[#peaks + 1] = i
        end
    end
    return peaks
end

local function quant(x)
    return math.floor(x / 3 + 0.5)
end

local function quant_coarse(x)
    return math.floor(x / 6 + 0.5)
end

local function build_hashes(peaks, is_short)
    local hashes = {}
    for i = 1, #peaks - 4 do
        local a = peaks[i]
        local step1 = is_short and 1 or 2
        local step2 = is_short and 2 or 4
        local b = peaks[i + step1]
        local c = peaks[i + step2]
        local dt1 = b - a
        local dt2 = c - b
        -- fine scale
        local q1 = quant(dt1)
        local q2 = quant(dt2)
        hashes[#hashes + 1] = {hash = q1 .. ":" .. q2, time = a}
        -- coarse scale
        local q1c = quant_coarse(dt1)
        local q2c = quant_coarse(dt2)
        hashes[#hashes + 1] = {hash = q1c .. ":" .. q2c, time = a}
    end
    return hashes
end

local function build_index(hashes)
    local index = {}
    for i = 1, #hashes do
        local h = hashes[i]
        if not index[h.hash] then
            index[h.hash] = {}
        end
        table.insert(index[h.hash], h.time)
    end
    return index
end

local function best_offset(votes)
    local best, best_score = nil, 0
    for k, v in pairs(votes) do
        -- neighborhood support window
        local support = (votes[k - 1] or 0) + (votes[k] or 0) + (votes[k + 1] or 0)
        -- emphasize center vote slightly
        local score = support + 0.2 * v
        if score > best_score then
            best_score = score
            best = k
        end
    end
    return best, best_score
end

local function table_size(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local function compute_confidence(votes, best_offset, total_votes)
    if not best_offset or total_votes < 1 then
        return 0
    end
    local center = votes[best_offset] or 0
    local left = votes[best_offset - 1] or 0
    local right = votes[best_offset + 1] or 0
    local cluster = center + left + right
    -- how spread out the vote space is
    local bins = math.max(1, table_size(votes))
    -- expected noise per bin
    local expected = total_votes / bins
    -- compare peak vs expected peak*, not total density
    local signal = cluster
    local noise = expected + 1e-6
    local snr = signal / noise
    -- compress so it doesn't explode on duplicates
    local confidence = snr / (1 + math.abs(math.log(snr + 1)))
    return confidence
end

local function match(query_hashes, ref_index)
    local votes = {}
    local total_votes = 0
    for i = 1, #query_hashes do
        local q = query_hashes[i]
        local ref_times = ref_index[q.hash]
        if ref_times then
            for j = 1, #ref_times do
                local offset = ref_times[j] - q.time
                votes[offset] = (votes[offset] or 0) + 1
                total_votes = total_votes + 1
            end
        end
    end
    local best_off, best_score = best_offset(votes)
    return best_off, best_score, votes, total_votes
end

local function is_silent(x)
    local sum = 0

    for i = 1, #x do
        sum = sum + math.abs(x[i])
    end

    return (sum / #x) < 1e-5
end

local function SelectAnalysisRegion(item)
    local take = reaper.GetActiveTake(item)
    if not take then return nil, 0 end

    local accessor = reaper.CreateTakeAudioAccessor(take)
    local accessor_start = reaper.GetAudioAccessorStartTime(accessor)
    local accessor_end = reaper.GetAudioAccessorEndTime(accessor)
    reaper.DestroyAudioAccessor(accessor)

    local total_len = accessor_end - accessor_start
    local max_sec = ANALYSIS_MAX_SEC
    local step_sec = ANALYSIS_SCAN_STEP_SEC

    -- short items: just read the whole thing
    if total_len <= max_sec then
        local q = read_audio(item, accessor_start, total_len)
        return q, 0
    end

    local best_start_sec = accessor_start
    local best_score = -1
    local best_segment = nil

    local scan_t = accessor_start
    while scan_t + max_sec <= accessor_end do
        local segment = read_audio(item, scan_t, max_sec)
        if segment then
            local seg_normalized = normalize(segment)
            local env = envelope(seg_normalized, false)
            local peaks = get_peaks(env)
            local score = #peaks
            if score > best_score then
                best_score = score
                best_start_sec = scan_t
                best_segment = segment
            end
        end
        scan_t = scan_t + step_sec
    end

    -- handle the case where no valid segment was found
    if not best_segment then
        local q = read_audio(item, accessor_start, max_sec)
        return q, 0
    end

    local offset_sec = best_start_sec - accessor_start
    return best_segment, offset_sec
end

local function compute_eta(state)
    local now = reaper.time_precise()
    local elapsed = now - state.start_real_time

    local range = state.search_end - state.search_start
    if range <= 0 then return nil end

    local progress = (state.current_t - state.search_start) / range
    progress = math.max(0, math.min(1, progress))

    if progress < 0.01 then
        return nil -- not enough data yet
    end

    local total_est = elapsed / progress
    local remaining = total_est - elapsed

    if remaining < 0 then remaining = 0 end

    return remaining, progress
end

local function GetGlobalETA(current_alignment)
    local now = reaper.time_precise()
    local elapsed = now - processing_start_time

    local total = #valid_items
    if total == 0 then return nil end

    -- completed full items
    local done = processing_index -1

    -- add partial progress of current item
    local partial = 0
    if current_alignment and current_alignment.search_end > current_alignment.search_start then
        partial = (current_alignment.current_t - current_alignment.search_start) / (current_alignment.search_end - current_alignment.search_start)
        partial = math.max(0, math.min(1, partial))
    end

    local progress = (done + partial) / total
    progress = math.max(0.0001, math.min(1, progress))

    local total_est = elapsed / progress
    local remaining = total_est - elapsed

    return remaining, progress
end

local function BeginAlignment(item, track, search_start, search_end)
    local track_len = reaper.GetProjectLength(0)

    search_start = search_start or 0
    search_end = search_end or track_len
    search_end = math.min(search_end, track_len)

    local q, analysis_offset_sec = SelectAnalysisRegion(item)

    if not q then
        return nil
    end

    local query_len_sec = #q / SR

    local is_short = query_len_sec < 2.0

    local step_sec = query_len_sec * 0.5
    local pad_sec = 0.5

    q = normalize(q)

    local eq = envelope(q, is_short)
    local peaks_q = get_peaks(eq)
    local qh = build_hashes(peaks_q, is_short)

    return {
        item = item,
        track = track,
        search_start = search_start,
        search_end = search_end,
        current_t = search_start,
        query_len_sec = query_len_sec,
        is_short = is_short,
        step_sec = step_sec,
        pad_sec = pad_sec,
        qh = qh,
        best_offset_samples = nil,
        best_offset_time = nil,
        best_score = 0,
        best_votes = nil,
        best_total = 0,
        found_audio = false,
        analysis_offset_sec = analysis_offset_sec,
        start_real_time = reaper.time_precise()
    }
end

local function ProcessAlignmentChunk(state)
    local frame_start = reaper.time_precise()
    while true do
        if state.current_t > math.min(state.search_end - state.query_len_sec, reaper.GetProjectLength(0) - state.query_len_sec) then
            return true
        end

        local r = read_track_audio(state.track, state.current_t, state.query_len_sec + state.pad_sec * 2, SR)

        if r and not is_silent(r) then
            state.found_audio = true

            r = normalize(r)

            local er = envelope(r)
            local peaks_r = get_peaks(er)

            if #peaks_r >= 5 then
                local rh = build_hashes(peaks_r, state.is_short)

                local index = build_index(rh)

                local offset, score, votes, total_votes = match(state.qh, index)

                if offset and score > state.best_score then
                    state.best_score = score

                    state.best_offset_samples = offset

                    state.best_offset_time = state.current_t + (offset / SR) - state.analysis_offset_sec

                    state.best_votes = votes
                    state.best_total = total_votes
                end
            end
        end

        state.current_t = state.current_t + state.step_sec
        if (reaper.time_precise() - frame_start) >= FRAME_BUDGET then
            break
        end
    end

    return false
end

local function FinishAlignment(state)
    if not state.found_audio then
        return -1, 0
    end

    local confidence = compute_confidence(state.best_votes, state.best_offset_samples, state.best_total)

    return state.best_offset_time, confidence
end

local function GetSelectedItems()
    local items = {}
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        table.insert(items, item)
    end
    return items
end

local function GetProjectGUID()
    local proj, proj_path = reaper.EnumProjects(-1)
    if proj_path == "" then
        proj_path = "unsaved"
    end
    local retval_guid, guid = reaper.GetProjExtState(0, "RGS_GUID", "GUID")
    local retval_path, path = reaper.GetProjExtState(0, "RGS_GUID", "path")
    if retval_guid == 0 or retval_path == 0 or proj_path ~= path then
        guid = reaper.genGuid()
        reaper.SetProjExtState(0, "RGS_GUID", "GUID", guid)
        reaper.SetProjExtState(0, "RGS_GUID", "path", proj_path)
    end
    return guid
end

local function ItemsExistInRange(track, time_start, time_end)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_start = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_start + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if item_start < time_end and item_end > time_start then
            return true
        end
    end
    return false
end

local function GetMediaType(source)
    local type = reaper.GetMediaSourceType(source)

    if type == "SECTION" then
        local parent = reaper.GetMediaSourceParent(source)
        return GetMediaType(parent)
    end
    if type == "LTC" then
        return "Timecode Generator"
    end
    if type == "CLICK" then
        return "Click Source"
    end
    return "Audio"
end

local function UnselectAllItems()
    for i = 0, reaper.CountMediaItems(0) - 1 do
        reaper.SetMediaItemSelected(reaper.GetMediaItem(0, i), false)
    end
end

local function SortReport(report, column, direction)
    local sort_field
    if column == 0 then
        sort_field = "name"
    end
    if column == 1 then
        sort_field = "note"
    end
    if column == 2 then
        sort_field = "position"
    end
    if column == 3 then
        sort_field = "display_confidence"
    end

    local function AscendingSort(a, b)
        local type_a = type(a[sort_field])
        local type_b = type(b[sort_field])

        if type_a ~= type_b then
            return type_a == "number"
        end
        return a[sort_field] < b[sort_field]
    end

    local function DescendingSort(a, b)
        local type_a = type(a[sort_field])
        local type_b = type(b[sort_field])

        if type_a ~= type_b then
            return type_a == "string"
        end
        return a[sort_field] > b[sort_field]
    end

    if direction == 1 then
        table.sort(report, AscendingSort)
    end

    if direction == 2 then
        table.sort(report, DescendingSort)
    end
    return report
end

local function Checksum(string)
    local sum = 0
    for i = 1, #string do
        sum = (sum + string.byte(string, i) % 2 ^ 32)
    end
    return sum
end


local function ReadFile(path)
    local file = io.open(path, "r")
    if not file then
        return ""
    end
    local content = file:read("a")
    file:close()
    return content
end

local function GetLastFocusedWindow()
    local section_id = 0
    if not ImGui.IsWindowFocused(ctx) then
        if reaper.JS_Window_GetTitle(reaper.JS_Window_GetParent(reaper.JS_Window_GetFocus())) ~= ScriptName then
            foreground_window = reaper.JS_Window_GetForeground()
            focus_window = reaper.JS_Window_GetFocus()
            parent_window = reaper.JS_Window_GetParent(focus_window)
        end
    end

    if reaper.JS_Window_GetTitle(foreground_window) == reaper.LocalizeString("Media Explorer", "common") then
        if reaper.GetToggleCommandState(50124) == 1 then
            section_id = 32063
            return foreground_window, section_id
        end
    end

    if
        reaper.JS_Window_GetTitle(foreground_window):sub(1, #reaper.LocalizeString("Crossfade Editor", "common")) ==
            reaper.LocalizeString("Crossfade Editor", "common")
     then
        if reaper.GetToggleCommandState(41827) == 1 then
            section_id = 32065
            return foreground_window, section_id
        end
    end

    local midi_window_count, midi_window_list = reaper.JS_MIDIEditor_ListAll()
    if midi_window_count > 0 then
        for window in string.gmatch(midi_window_list, "([^,]+)") do
            if reaper.JS_Window_HandleFromAddress(tonumber(window)) == foreground_window then
                if reaper.MIDIEditor_GetMode(foreground_window) == 0 then
                    section_id = 32060
                elseif reaper.MIDIEditor_GetMode(foreground_window) == 1 then
                    section_id = 32061
                end
                return foreground_window, section_id
            end
        end
    end

    if reaper.JS_Window_GetTitle(parent_window) == reaper.LocalizeString("Media Explorer", "common") then
        if reaper.GetToggleCommandState(50124) == 1 then
            section_id = 32063
            return parent_window, section_id
        end
    end

    if
        reaper.JS_Window_GetTitle(parent_window):sub(1, #reaper.LocalizeString("Crossfade Editor", "common")) ==
            reaper.LocalizeString("Crossfade Editor", "common")
     then
        if reaper.GetToggleCommandState(41827) == 1 then
            section_id = 32065
            return parent_window, section_id
        end
    end

    if midi_window_count > 0 then
        for window in string.gmatch(midi_window_list, "([^,]+)") do
            if reaper.JS_Window_HandleFromAddress(tonumber(window)) == parent_window then
                if reaper.MIDIEditor_GetMode(parent_window) == 0 then
                    section_id = 32060
                elseif reaper.MIDIEditor_GetMode(parent_window) == 1 then
                    section_id = 32061
                end
                return parent_window, section_id
            end
        end
    end

    if reaper.GetToggleCommandState(24852) == 1 or reaper.GetToggleCommandState(24802) == 1 then
        section_id = 100
    else
        local toggle_id = 24803
        local momentary_id = 24853
        for i = 1, 16 do
            if reaper.GetToggleCommandState(toggle_id) == 1 or reaper.GetToggleCommandState(momentary_id) == 1 then
                section_id = i
                break
            end
            toggle_id = toggle_id + 1
            momentary_id = momentary_id + 1
        end
    end

    return parent_window, section_id
end

local function BuildShortcutCache(section_id)
    local section = reaper.SectionFromUniqueID(section_id)
    local cache = {}
    local i = 0
    while true do
        local command_id = reaper.kbd_enumerateActions(section, i)
        if command_id == 0 then
            break
        end
        local shortcut_count = reaper.CountActionShortcuts(section, command_id)
        for idx = 0, shortcut_count - 1 do
            local ok, description = reaper.GetActionShortcutDesc(section, command_id, idx)
            if ok and description ~= "" then
                cache[description] = command_id
            end
        end
        i = i + 1
    end
    shortcut_cache[section_id] = cache
end

local function PassShortcut(section_id, window)
    if not ImGui.IsWindowFocused(ctx) then
        return
    end
    local Keys = {}
    if is_macos then
        Keys = {
            ["0"] = ImGui.Key_0,
            ["1"] = ImGui.Key_1,
            ["2"] = ImGui.Key_2,
            ["3"] = ImGui.Key_3,
            ["4"] = ImGui.Key_4,
            ["5"] = ImGui.Key_5,
            ["6"] = ImGui.Key_6,
            ["7"] = ImGui.Key_7,
            ["8"] = ImGui.Key_8,
            ["9"] = ImGui.Key_9,
            A = ImGui.Key_A,
            B = ImGui.Key_B,
            C = ImGui.Key_C,
            D = ImGui.Key_D,
            E = ImGui.Key_E,
            F = ImGui.Key_F,
            G = ImGui.Key_G,
            H = ImGui.Key_H,
            I = ImGui.Key_I,
            J = ImGui.Key_J,
            K = ImGui.Key_K,
            L = ImGui.Key_L,
            M = ImGui.Key_M,
            N = ImGui.Key_N,
            O = ImGui.Key_O,
            P = ImGui.Key_P,
            Q = ImGui.Key_Q,
            R = ImGui.Key_R,
            S = ImGui.Key_S,
            T = ImGui.Key_T,
            U = ImGui.Key_U,
            V = ImGui.Key_V,
            W = ImGui.Key_W,
            X = ImGui.Key_X,
            Y = ImGui.Key_Y,
            Z = ImGui.Key_Z,
            [reaper.JS_Localize("ESC", "kb")] = ImGui.Key_Escape,
            F1 = ImGui.Key_F1,
            F2 = ImGui.Key_F2,
            F3 = ImGui.Key_F3,
            F4 = ImGui.Key_F4,
            F5 = ImGui.Key_F5,
            F6 = ImGui.Key_F6,
            F7 = ImGui.Key_F7,
            F8 = ImGui.Key_F8,
            F9 = ImGui.Key_F9,
            F10 = ImGui.Key_F10,
            F11 = ImGui.Key_F11,
            F12 = ImGui.Key_F12,
            ["'"] = ImGui.Key_Apostrophe,
            ["\\"] = ImGui.Key_Backslash,
            [reaper.JS_Localize("Backspace", "kb")] = ImGui.Key_Backspace,
            [","] = ImGui.Key_Comma,
            [reaper.JS_Localize("Delete", "kb")] = ImGui.Key_Delete,
            [reaper.JS_Localize("Down", "kb")] = ImGui.Key_DownArrow,
            [reaper.JS_Localize("Return", "kb")] = ImGui.Key_Enter,
            [reaper.JS_Localize("End", "kb")] = ImGui.Key_End,
            ["="] = ImGui.Key_Equal,
            ["`"] = ImGui.Key_GraveAccent,
            [reaper.JS_Localize("Home", "kb")] = ImGui.Key_Home,
            ScrollLock = ImGui.Key_ScrollLock,
            [reaper.JS_Localize("Insert", "kb")] = ImGui.Key_Insert,
            ["-"] = ImGui.Key_Minus,
            [reaper.JS_Localize("Left", "kb")] = ImGui.Key_LeftArrow,
            ["["] = ImGui.Key_LeftBracket,
            ["."] = ImGui.Key_Period,
            [reaper.JS_Localize("Page Down", "kb")] = ImGui.Key_PageDown,
            [reaper.JS_Localize("Page Up", "kb")] = ImGui.Key_PageUp,
            [reaper.JS_Localize("Pause", "kb")] = ImGui.Key_Pause,
            ["]"] = ImGui.Key_RightBracket,
            [reaper.JS_Localize("Right", "kb")] = ImGui.Key_RightArrow,
            [";"] = ImGui.Key_Semicolon,
            ["/"] = ImGui.Key_Slash,
            [reaper.JS_Localize("Space", "kb")] = ImGui.Key_Space,
            Tab = ImGui.Key_Tab,
            Up = ImGui.Key_UpArrow,
            [reaper.JS_Localize("NumPad 0", "kb")] = ImGui.Key_Keypad0,
            [reaper.JS_Localize("NumPad 1", "kb")] = ImGui.Key_Keypad1,
            [reaper.JS_Localize("NumPad 2", "kb")] = ImGui.Key_Keypad2,
            [reaper.JS_Localize("NumPad 3", "kb")] = ImGui.Key_Keypad3,
            [reaper.JS_Localize("NumPad 4", "kb")] = ImGui.Key_Keypad4,
            [reaper.JS_Localize("NumPad 5", "kb")] = ImGui.Key_Keypad5,
            [reaper.JS_Localize("NumPad 6", "kb")] = ImGui.Key_Keypad6,
            [reaper.JS_Localize("NumPad 7", "kb")] = ImGui.Key_Keypad7,
            [reaper.JS_Localize("NumPad 8", "kb")] = ImGui.Key_Keypad8,
            [reaper.JS_Localize("NumPad 9", "kb")] = ImGui.Key_Keypad9,
            [reaper.JS_Localize("NumPad +", "kb")] = ImGui.Key_KeypadAdd,
            [reaper.JS_Localize("NumPad .", "kb")] = ImGui.Key_KeypadDecimal,
            [reaper.JS_Localize("NumPad /", "kb")] = ImGui.Key_KeypadDivide,
            [reaper.JS_Localize("NumPad Enter", "kb")] = ImGui.Key_KeypadEnter,
            [reaper.JS_Localize("NumPad =", "kb")] = ImGui.Key_KeypadEqual,
            [reaper.JS_Localize("NumPad *", "kb")] = ImGui.Key_KeypadMultiply,
            [reaper.JS_Localize("NumPad -", "kb")] = ImGui.Key_KeypadSubtract,
            [reaper.JS_Localize("Clear", "kb")] = ImGui.Key_NumLock
        }
    else
         Keys = {
            ["0"] = ImGui.Key_0,
            ["1"] = ImGui.Key_1,
            ["2"] = ImGui.Key_2,
            ["3"] = ImGui.Key_3,
            ["4"] = ImGui.Key_4,
            ["5"] = ImGui.Key_5,
            ["6"] = ImGui.Key_6,
            ["7"] = ImGui.Key_7,
            ["8"] = ImGui.Key_8,
            ["9"] = ImGui.Key_9,
            A = ImGui.Key_A,
            B = ImGui.Key_B,
            C = ImGui.Key_C,
            D = ImGui.Key_D,
            E = ImGui.Key_E,
            F = ImGui.Key_F,
            G = ImGui.Key_G,
            H = ImGui.Key_H,
            I = ImGui.Key_I,
            J = ImGui.Key_J,
            K = ImGui.Key_K,
            L = ImGui.Key_L,
            M = ImGui.Key_M,
            N = ImGui.Key_N,
            O = ImGui.Key_O,
            P = ImGui.Key_P,
            Q = ImGui.Key_Q,
            R = ImGui.Key_R,
            S = ImGui.Key_S,
            T = ImGui.Key_T,
            U = ImGui.Key_U,
            V = ImGui.Key_V,
            W = ImGui.Key_W,
            X = ImGui.Key_X,
            Y = ImGui.Key_Y,
            Z = ImGui.Key_Z,
            [reaper.JS_Localize("ESC", "kb")] = ImGui.Key_Escape,
            F1 = ImGui.Key_F1,
            F2 = ImGui.Key_F2,
            F3 = ImGui.Key_F3,
            F4 = ImGui.Key_F4,
            F5 = ImGui.Key_F5,
            F6 = ImGui.Key_F6,
            F7 = ImGui.Key_F7,
            F8 = ImGui.Key_F8,
            F9 = ImGui.Key_F9,
            F10 = ImGui.Key_F10,
            F11 = ImGui.Key_F11,
            F12 = ImGui.Key_F12,
            ["'"] = ImGui.Key_Apostrophe,
            ["\\"] = ImGui.Key_Backslash,
            [reaper.JS_Localize("Backspace", "kb")] = ImGui.Key_Backspace,
            [","] = ImGui.Key_Comma,
            [reaper.JS_Localize("Delete", "kb")] = ImGui.Key_Delete,
            [reaper.JS_Localize("Down", "kb")] = ImGui.Key_DownArrow,
            [reaper.JS_Localize("Enter", "kb")] = ImGui.Key_Enter,
            [reaper.JS_Localize("End", "kb")] = ImGui.Key_End,
            ["="] = ImGui.Key_Equal,
            ["`"] = ImGui.Key_GraveAccent,
            [reaper.JS_Localize("Home", "kb")] = ImGui.Key_Home,
            ScrollLock = ImGui.Key_ScrollLock,
            [reaper.JS_Localize("Insert", "kb")] = ImGui.Key_Insert,
            ["-"] = ImGui.Key_Minus,
            [reaper.JS_Localize("Left", "kb")] = ImGui.Key_LeftArrow,
            ["["] = ImGui.Key_LeftBracket,
            ["."] = ImGui.Key_Period,
            [reaper.JS_Localize("Page Down", "kb")] = ImGui.Key_PageDown,
            [reaper.JS_Localize("Page Up", "kb")] = ImGui.Key_PageUp,
            [reaper.JS_Localize("Pause", "kb")] = ImGui.Key_Pause,
            ["]"] = ImGui.Key_RightBracket,
            [reaper.JS_Localize("Right", "kb")] = ImGui.Key_RightArrow,
            [";"] = ImGui.Key_Semicolon,
            ["/"] = ImGui.Key_Slash,
            [reaper.JS_Localize("Space", "kb")] = ImGui.Key_Space,
            Tab = ImGui.Key_Tab,
            Up = ImGui.Key_UpArrow,
            [reaper.JS_Localize("Num 0", "kb")] = ImGui.Key_Keypad0,
            [reaper.JS_Localize("Num 1", "kb")] = ImGui.Key_Keypad1,
            [reaper.JS_Localize("Num 2", "kb")] = ImGui.Key_Keypad2,
            [reaper.JS_Localize("Num 3", "kb")] = ImGui.Key_Keypad3,
            [reaper.JS_Localize("Num 4", "kb")] = ImGui.Key_Keypad4,
            [reaper.JS_Localize("Num 5", "kb")] = ImGui.Key_Keypad5,
            [reaper.JS_Localize("Num 6", "kb")] = ImGui.Key_Keypad6,
            [reaper.JS_Localize("Num 7", "kb")] = ImGui.Key_Keypad7,
            [reaper.JS_Localize("Num 8", "kb")] = ImGui.Key_Keypad8,
            [reaper.JS_Localize("Num 9", "kb")] = ImGui.Key_Keypad9,
            [reaper.JS_Localize("Num +", "kb")] = ImGui.Key_KeypadAdd,
            [reaper.JS_Localize("Num .", "kb")] = ImGui.Key_KeypadDecimal,
            [reaper.JS_Localize("Num /", "kb")] = ImGui.Key_KeypadDivide,
            [reaper.JS_Localize("Num Enter", "kb")] = ImGui.Key_KeypadEnter,
            [reaper.JS_Localize("Num =", "kb")] = ImGui.Key_KeypadEqual,
            [reaper.JS_Localize("Num *", "kb")] = ImGui.Key_KeypadMultiply,
            [reaper.JS_Localize("Num -", "kb")] = ImGui.Key_KeypadSubtract,
            [reaper.JS_Localize("Clear", "kb")] = ImGui.Key_NumLock
        }
    end
    local Shifted_Keys = {
            ["0"] = ")",
            ["1"] = "!",
            ["2"] = "@",
            ["3"] = "#",
            ["4"] = "$",
            ["5"] = "%",
            ["6"] = "^",
            ["7"] = "&",
            ["8"] = "*",
            ["9"] = "(",
            ["'"] = '"',
            ["\\"] = "|",
            [","] = "<",
            ["="] = "+",
            ["`"] = "~",
            ["-"] = "_",
            ["["] = "{",
            ["."] = ">",
            ["]"] = "}",
            [";"] = ":",
            ["/"] = "?"
        }
    local Mods = {
        Ctrl = ImGui.Mod_Ctrl,
        Alt = ImGui.Mod_Alt,
        Shift = ImGui.Mod_Shift,
        Super = ImGui.Mod_Super
    }

    local Nav_Keys = {
        ImGui.Key_LeftArrow,
        ImGui.Key_RightArrow,
        ImGui.Key_UpArrow,
        ImGui.Key_DownArrow,
        ImGui.Key_Tab,
        ImGui.Key_Home,
        ImGui.Key_End
    }

    local Focused_Nav_Keys = {
        ImGui.Key_Space,
        ImGui.Key_Enter,
        ImGui.Key_KeypadEnter,
        ImGui.Key_Escape
    }

    local ctrl = false
    local shift = false
    local alt = false
    local super = false
    local shortcut = ""
    local alt_shortcut
    local key_name
    local alt_key_name
    local key_code

    for name, code in pairs(Keys) do
        if ImGui.IsKeyDown(ctx, code) then
            key_name = name
            key_code = code
        end
    end
    for i = 1, #Nav_Keys do
        if ImGui.IsKeyDown(ctx, Nav_Keys[i]) then
            key_name = nil
        end
    end
    if ImGui.IsAnyItemFocused(ctx) then
        for i = 1, #Focused_Nav_Keys do
            if ImGui.IsKeyDown(ctx, Focused_Nav_Keys[i]) then
                key_name = nil
            end
        end
    end

    if not key_name then
        return
    end

    for name, code in pairs(Mods) do
        if ImGui.IsKeyDown(ctx, code) then
            if name == "Ctrl" then
                ctrl = true
            elseif name == "Shift" then
                shift = true
            elseif name == "Alt" then
                alt = true
            elseif name == "Super" then
                super = true
            end
        end
    end
    if ctrl then
        if is_macos then
            shortcut = shortcut .. reaper.JS_Localize("Cmd+", "kb")
        else
            shortcut = shortcut .. reaper.JS_Localize("Ctrl+", "kb")
        end
    end
    if alt then
        if is_macos then
            shortcut = shortcut .. reaper.JS_Localize("Opt+", "kb")
        else
            shortcut = shortcut .. reaper.JS_Localize("Alt+", "kb")
        end
    end
    if shift then
        for original_name, shifted_name in pairs(Shifted_Keys) do
            if key_name == original_name then
                alt_key_name = shifted_name
                alt_shortcut = shortcut
            end
        end
        shortcut = shortcut .. reaper.JS_Localize("Shift+", "kb")
    end
    if super then
        if is_macos then
            shortcut = shortcut .. reaper.JS_Localize("Control+", "kb")
            if alt_shortcut then
                alt_shortcut = alt_shortcut .. reaper.JS_Localize("Control+", "kb")
            end
        else
            shortcut = shortcut .. reaper.JS_Localize("Win+", "kb")
            if alt_shortcut then
                alt_shortcut = alt_shortcut .. reaper.JS_Localize("Win+", "kb")
            end
        end
    end
    shortcut = shortcut .. key_name
    if alt_shortcut then
        alt_shortcut = alt_shortcut .. alt_key_name
    end

    local kb_ini = ReadFile(reaper.GetResourcePath() .. "/reaper-kb.ini")
    local current_checksum = Checksum(kb_ini)
    if current_checksum ~= shortcut_cache_checksum then
        shortcut_cache_checksum = current_checksum
        shortcut_cache = {}
    end
    if not shortcut_cache[section_id] then
        BuildShortcutCache(section_id)
    end

    local command_id = shortcut_cache[section_id][shortcut] or shortcut_cache[section_id][alt_shortcut]
    if command_id then
        if ImGui.IsKeyPressed(ctx, key_code, true) then
            if section_id == 32063 then
                reaper.JS_Window_OnCommand(window, command_id)
            elseif section_id == 32065 then
                reaper.CrossfadeEditor_OnCommand(command_id)
            elseif section_id == 32060 or section_id == 32061 then
                reaper.MIDIEditor_OnCommand(window, command_id)
            else
                reaper.Main_OnCommandEx(command_id, 0, 0)
            end
        end
        return shortcut, alt_shortcut, command_id
    end

    section_id = 0
    if reaper.GetToggleCommandState(24852) == 1 or reaper.GetToggleCommandState(24802) == 1 then
        section_id = 100
    else
        local toggle_id = 24803
        local momentary_id = 24853
        for i = 1, 16 do
            if reaper.GetToggleCommandState(toggle_id) == 1 or reaper.GetToggleCommandState(momentary_id) == 1 then
                section_id = i
                break
            end
            toggle_id = toggle_id + 1
            momentary_id = momentary_id + 1
        end
    end

    if not shortcut_cache[section_id] then
        BuildShortcutCache(section_id)
    end
    command_id = shortcut_cache[section_id][shortcut] or shortcut_cache[section_id][alt_shortcut]
    if command_id then
        if ImGui.IsKeyPressed(ctx, key_code, true) then
            reaper.Main_OnCommandEx(command_id, 0, 0)
        end
        return shortcut, alt_shortcut, command_id, true
    end
    return shortcut, alt_shortcut
end

local function Exit()
    reaper.set_action_options(8)
end


local guid = GetProjectGUID()
local guid_changed = false




local function Main()
    local focused_window, section_id = GetLastFocusedWindow()
    if use_first_selected_track then
        track = reaper.GetSelectedTrack(0, 0)
    end
    local proj2 = reaper.EnumProjects(-1)
    if dirty ~= reaper.IsProjectDirty(0) then
        if dirty == 1 then
            reaper.SetProjExtState(0, "RGS_GUID", "GUID", reaper.genGuid())
        end
        dirty = reaper.IsProjectDirty(0)
    end
    if guid ~= GetProjectGUID() then
        guid_changed = true
        guid = GetProjectGUID()
    end
    if proj ~= proj2 or guid_changed then -- project changed
        if processing then
            processing_results = {}
            results = {}
            valid_items = {}
            invalid_items = {}
            processing = false
            current_alignment = nil
            reaper.MB("Project changed\nSyncing has been canceled", ScriptName, 0)
        end

        track = reaper.GetSelectedTrack(0, 0)
        proj = proj2
        guid_changed = false
        report_table = nil
    end

    if not track then
        if reaper.CountTracks(0) < 1 then
            track_combo_preview = "<No tracks in project>"
        else
            track_combo_preview = "<Please select a reference track>"
        end
    else
        local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local track_number = string.format("%d", reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
        track_combo_preview = "[" .. track_number .. "] " .. track_name
    end

    if range_is_time_selection then
        time_start, time_end = reaper.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    end

    if range_is_track then
        if track then
            local item_count = reaper.CountTrackMediaItems(track)
            if item_count < 1 then
                time_start = 0
                time_end = 0
            else
                local first_item = reaper.GetTrackMediaItem(track, 0)
                local last_item = reaper.GetTrackMediaItem(track, item_count - 1)
                time_start = reaper.GetMediaItemInfo_Value(first_item, "D_POSITION")
                time_end = reaper.GetMediaItemInfo_Value(last_item, "D_POSITION") + reaper.GetMediaItemInfo_Value(last_item, "D_LENGTH")
            end
        end
    end

    if time_end - time_start <= 0 or (not track and range_is_track) then
        time_start_string = "--"
        time_end_string = "--"
        time_length_string = "--"
    else
        time_start_string = reaper.format_timestr_pos(time_start, "", -1)
        time_end_string = reaper.format_timestr_pos(time_end, "", -1)
        time_length_string = reaper.format_timestr_len(time_end - time_start, "", 0, -1)
    end

    if processing then
        if processing_index > #processing_items then
            processing = false
            Msg("Processing Complete")
        else
            local item = processing_items[processing_index].item
            if item then
                if not current_alignment then
                    current_alignment = BeginAlignment(item, ref_track, time_start, time_end)
                end
                if current_alignment then
                    local done = ProcessAlignmentChunk(current_alignment)
                    if done then
                        local position, raw_confidence = FinishAlignment(current_alignment)
                        local result = {
                            item = item,
                            position = position,
                            raw_confidence = raw_confidence,
                            name = processing_items[processing_index].name
                        }
                        table.insert(processing_results, result)
                        current_alignment = nil
                        processing_index = processing_index + 1
                    end
                else
                    processing_index = processing_index + 1
                end
            end
        end
    end

    if not processing and #processing_results > 0 then
        for i = 1, #processing_results do
            local result = processing_results[i]
            local raw_confidence = result.raw_confidence
            local position = result.position
            local note
            local display_confidence
            if raw_confidence >= raw_confidence_threshold then
                display_confidence =
                    string.format("%.2f", math.min(10, (raw_confidence / RAW_CONFIDENCE_SCALE_MAX) * 10))
                note = "Match found"
                match_found = true
                match_count = match_count + 1
            else
                note = "No matches found"
                position = nil
                no_match_count = no_match_count + 1
            end
            local t = {
                item = result.item,
                note = note,
                name = result.name,
                position = position or "--",
                raw_confidence = raw_confidence or "--",
                display_confidence = display_confidence or "--",
                index = i + #invalid_items
            }
            table.insert(results, t)
        end
        finalize = true
    end

    if finalize then
        reaper.Undo_BeginBlock()
        invalid_count = #invalid_items
        if match_found and move_to_new_track then
            local new_track_idx = reaper.GetMediaTrackInfo_Value(ref_track, "IP_TRACKNUMBER")
            reaper.InsertTrackInProject(0, new_track_idx, 0)
            match_track = reaper.GetTrack(0, new_track_idx)
            reaper.GetSetMediaTrackInfo_String(match_track, "P_NAME", "ReaSync Matches", true)
        end
        for i = 1, #results do
            if results[i].note == "Match found" then
                reaper.SetMediaItemInfo_Value(results[i].item, "D_POSITION", results[i].position)
                if move_to_new_track then
                    reaper.MoveMediaItemToTrack(results[i].item, match_track)
                end
            end
        end
        processing_time = reaper.time_precise() - processing_start_time
        processing_time_string = reaper.format_timestr_len(math.floor(processing_time), "",0,0)
        processing_time_string = string.sub(processing_time_string, 1, -5)
        if not match_found and not show_report then
            reaper.MB("No matches found", ScriptName, 0)
        end
        match_found = false
        if show_report then
            results = SortReport(results, 2, 1)
            report_table = results
        end
        processing_results = {}
        results = {}
        valid_items = {}
        invalid_items = {}
        finalize = false
        Msg(processing_time)
        reaper.Undo_EndBlock(ScriptName, 0)
    end

    local visible, open = ImGui.Begin(ctx, ScriptName, true, main_window_flags)
    if visible then
        if not ImGui.IsAnyItemActive(ctx) then
            PassShortcut(section_id, focused_window)
        end
        ImGui.PushFont(ctx, nil, ImGui.GetFontSize(ctx) + 1)
        ImGui.SeparatorText(ctx, "Reference Track##separator")
        ImGui.PopFont(ctx)
        ImGui.BeginDisabled(ctx, use_first_selected_track)
        if ImGui.BeginCombo(ctx, "##Reference track combo", track_combo_preview) then
            for i = 0, reaper.CountTracks(0) - 1 do
                local combo_track = reaper.GetTrack(0, i)
                local color = reaper.GetTrackColor(combo_track)
                local _, combo_track_name = reaper.GetSetMediaTrackInfo_String(combo_track, "P_NAME", "", false)
                ImGui.ColorButton(ctx, "##color" .. i, color, ImGui.ColorEditFlags_NoPicker | ImGui.ColorEditFlags_NoAlpha)
                ImGui.SameLine(ctx)
                if
                    ImGui.Selectable(ctx, "[" .. tostring(i + 1) .. "] " .. combo_track_name .. "##trackcombo", combo_track == track)
                 then
                    track = combo_track
                end
            end
            ImGui.EndCombo(ctx)
        end
        ImGui.EndDisabled(ctx)
        if ImGui.Checkbox(ctx, "Use first selected track", use_first_selected_track) then
            use_first_selected_track = not use_first_selected_track
        end
        ImGui.PushFont(ctx, nil, ImGui.GetFontSize(ctx) + 1)
        ImGui.SeparatorText(ctx, "Search Range##separator")
        ImGui.PopFont(ctx)
        if ImGui.RadioButton(ctx, "Entire Track", range_is_track) then
            range_is_time_selection = false
            range_is_track = true
        end
        ImGui.SameLine(ctx)
        if ImGui.RadioButton(ctx, "Time Selection", range_is_time_selection) then
            range_is_time_selection = true
            range_is_track = false
        end
        ImGui.Text(ctx, "Start")
        ImGui.SameLine(ctx, 0, 18)
        ImGui.InputText(ctx, "##StartTime", time_start_string, ImGui.InputTextFlags_ReadOnly)
        ImGui.Text(ctx, "End")
        ImGui.SameLine(ctx, 0, 23)
        ImGui.InputText(ctx, "##EndTime", time_end_string, ImGui.InputTextFlags_ReadOnly)
        ImGui.Text(ctx, "Length")
        ImGui.SameLine(ctx)
        ImGui.InputText(ctx, "##Length", time_length_string, ImGui.InputTextFlags_ReadOnly)
        ImGui.PushFont(ctx, nil, ImGui.GetFontSize(ctx) + 1)
        ImGui.SeparatorText(ctx, "Match Threshold")
        ImGui.PopFont(ctx)
        threshold_slider, display_confidence_threshold = ImGui.SliderDouble(ctx, "##Match threshold", display_confidence_threshold, 1, 10, "%.2f")
        if threshold_slider then
            raw_confidence_threshold = (display_confidence_threshold / 10) * RAW_CONFIDENCE_SCALE_MAX
        end
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, "(?)")
        ImGui.SetItemTooltip(ctx, threshold_tooltip)
        if ImGui.BeginItemTooltip(ctx) then
            ImGui.EndTooltip(ctx)
        end
        ImGui.NewLine(ctx)
        if ImGui.Button(ctx, "Sync", 70, 40) then
            processing_start_time = reaper.time_precise()
            local err
            ref_track = track
            local track_muted = false
            if track then
                _, track_muted = reaper.GetTrackUIMute(track)
            end
            if not track then
                err = "No reference track selected"
            elseif track_muted then
                err = "Reference track is muted"
            elseif reaper.CountSelectedMediaItems(0) < 1 then
                err = "No items selected"
            elseif time_length_string == "--" and range_is_time_selection then
                err = "No time selection"
            elseif not ItemsExistInRange(track, time_start, time_end) then
                err = "No audio within search range on reference track"
            end
            if err then
                reaper.MB(err, ScriptName, 0)
            else
                local items = GetSelectedItems()
                match_count = 0
                no_match_count = 0
                for i = 1, #items do
                    local item = items[i]
                    local item_length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local take = reaper.GetActiveTake(item)
                    local name
                    local type
                    local note
                    local item_on_ref_track = (ref_track == reaper.GetMediaItemTrack(item))
                    local item_too_long = (item_length >= time_end - time_start)
                    local muted = (reaper.GetMediaItemInfo_Value(item, "B_MUTE")) == 1
                    local empty_take = (take == nil)
                    local valid_item = false
                    if not empty_take then
                        _, name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                        if reaper.TakeIsMIDI(take) then
                            type = "MIDI"
                        else
                            local source = reaper.GetMediaItemTake_Source(take)
                            type = GetMediaType(source)
                        end
                        if type == "Audio" then
                            if not item_on_ref_track and not item_too_long and not muted then
                                valid_item = true
                                local t = {item = item, name = name}
                                table.insert(valid_items, t)
                            end
                        end
                    end
                    if not valid_item then
                        if item_on_ref_track then note = "Item is on reference track" end
                        if item_too_long and note then note = note .. ", item is longer than search range" end
                        if item_too_long and not note then note = "Item is longer than search range" end
                        if muted and note then note = note .. ", item is muted" end
                        if muted and not note then note = "Item is muted" end
                        if empty_take and note then note = note .. ", active take is empty" end
                        if empty_take and not note then note = "Active take is empty" end
                        if not empty_take and type ~= "Audio" and note then note = note .. ", " .. type end
                        if not empty_take and type ~= "Audio" and not note then note = type end
                        note = "Invalid Item: " .. note
                        local t = {item = item, note = note or "--", name = name or "--"}
                        table.insert(invalid_items, t)
                    end
                end
                for i = 1, #invalid_items do
                    local t = {
                        item = invalid_items[i].item,
                        note = invalid_items[i].note,
                        name = invalid_items[i].name,
                        position = "--",
                        raw_confidence = "--",
                        display_confidence = "--",
                        index = i
                    }
                    table.insert(results, t)
                end

                if #valid_items > 0 then
                    processing = true
                    processing_items = valid_items
                    processing_index = 1
                    processing_results = {}
                    current_alignment = nil
                    ref_track = track
                    match_found = false
                else
                    finalize = true
                end
            end
        end
        if ImGui.Checkbox(ctx, "Show report", show_report) then
            show_report = not show_report
        end
        if ImGui.Checkbox(ctx, "Move matches to new track", move_to_new_track) then
            move_to_new_track = not move_to_new_track
        end

        if processing then
            ImGui.OpenPopup(ctx, "ReaSync##processing")
            if ImGui.BeginPopupModal(ctx, "ReaSync##processing", nil, ImGui.WindowFlags_AlwaysAutoResize) then
                local total_items = math.max(1,#processing_items)
                local completed_items = processing_index - 1
                local current_item_progress = 0

                local time_remaining = GetGlobalETA(current_alignment)
                local time_elapsed =  reaper.time_precise()- processing_start_time
                local time_elapsed_string = reaper.format_timestr_len(math.floor(time_elapsed), "",0,0)
                time_elapsed_string = string.sub(time_elapsed_string, 1, -5)
                local time_remaining_string = reaper.format_timestr_len(math.floor(time_remaining), "",0,0)
                time_remaining_string = string.sub(time_remaining_string, 1, -5)
                if current_alignment then
                    local search_range = current_alignment.search_end - current_alignment.search_start
                    if search_range > 0 then 
                        current_item_progress = (current_alignment.current_t - current_alignment.search_start) / search_range
                        current_item_progress = math.max(0, math.min(1, current_item_progress))
                    end
                end
                local overall_progress = (completed_items + current_item_progress) / total_items
                overall_progress = math.max (0, math.min(1, overall_progress))
                ImGui.Text(ctx, "Estimated Time Remaining: "..time_remaining_string)
                ImGui.ProgressBar(ctx, overall_progress, 300, 20)
                ImGui.Text(ctx, string.format("Scanning item %d of %d", math.min(processing_index + #invalid_items, total_items + #invalid_items), total_items + #invalid_items))
                if processing_index <= #processing_items then
                    ImGui.SameLine(ctx)
                    ImGui.Text(ctx, processing_items[processing_index].name)
                end
                if total_items > 1 then
                    if current_alignment then
                        ImGui.Text(ctx, string.format("%.1f%%", current_item_progress*100))
                    else
                        ImGui.NewLine(ctx)
                    end
                end
                if ImGui.Button(ctx, "Cancel") then
                    processing_results = {}
                    results = {}
                    valid_items = {}
                    invalid_items = {}
                    processing = false
                    current_alignment = nil
                end
                ImGui.EndPopup(ctx)
            end
        end

        if report_table then
            local table_flags = ImGui.TableFlags_ScrollY | ImGui.TableFlags_SizingFixedFit | ImGui.TableFlags_Sortable
            local selectable_flags = ImGui.SelectableFlags_SpanAllColumns | ImGui.SelectableFlags_NoAutoClosePopups
            local _, track_name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
            local track_number = string.format("%d", reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
            ImGui.OpenPopup(ctx, ScriptName .. " Report")
            if ImGui.BeginPopupModal(ctx, ScriptName .. " Report", true, ImGui.WindowFlags_AlwaysAutoResize) then
                PassShortcut(section_id, focused_window)
                local table_height = math.min(MAX_TABLE_HEIGHT, (#report_table + 1) * 20)
                if ImGui.BeginTable(ctx, "Report Table", 4, table_flags, 0, table_height) then
                    PassShortcut(section_id, focused_window)
                    ImGui.TableSetupScrollFreeze(ctx, 0, 1)
                    ImGui.TableSetupColumn(ctx, "Name##column", ImGui.TableColumnFlags_DefaultSort)
                    ImGui.TableSetupColumn(ctx, "Notes##column")
                    ImGui.TableSetupColumn(ctx, "Match Position##column")
                    ImGui.TableSetupColumn(ctx, "Confidence##column")
                    ImGui.TableHeadersRow(ctx)

                    local _, sort_idx, user_id, direction = ImGui.TableGetColumnSortSpecs(ctx, 0)

                    if ImGui.TableNeedSort(ctx) then
                        report_table = SortReport(report_table, sort_idx, direction)
                    end
                    ImGui.TableNextRow(ctx)
                    for i = 1, #report_table do
                        local position = report_table[i].position
                        local position_string = position
                        if type(position) == "number" then
                            position_string = reaper.format_timestr_pos(position, "", -1)
                        else
                            position = nil
                        end
                        ImGui.TableNextColumn(ctx)
                        if ImGui.Selectable(ctx, report_table[i].name .. "##selectable" .. tostring(i), report_selection == report_table[i].index, selectable_flags) then
                            report_selection = report_table[i].index
                            UnselectAllItems()
                            if reaper.ValidatePtr2(0,report_table[i].item, "MediaItem*") then
                                reaper.SetMediaItemSelected(report_table[i].item, true)
                            end
                            position = position or reaper.GetMediaItemInfo_Value(report_table[i].item, "D_POSITION")
                            reaper.SetEditCurPos2(0, position, true, false)
                        end
                        ImGui.TableNextColumn(ctx)
                        ImGui.Text(ctx, report_table[i].note)
                        ImGui.TableNextColumn(ctx)
                        ImGui.Text(ctx, position_string)
                        ImGui.TableNextColumn(ctx)
                        ImGui.Text(ctx, report_table[i].display_confidence)
                    end
                    ImGui.EndTable(ctx)
                    ImGui.Separator(ctx)
                    ImGui.Text(ctx, "Syncing finished in "..processing_time_string)
                    ImGui.Text(ctx, "Number of items: "..tostring(#report_table))
                    ImGui.Text(ctx, "Matches found: " .. tostring (match_count))
                    if no_match_count > 0 then
                        ImGui.Text(ctx, "Failed to match: ".. tostring(no_match_count))
                    end
                    if invalid_count > 0 then 
                        ImGui.Text(ctx, "Invalid Items: "..invalid_count)
                    end
                end
                ImGui.EndPopup(ctx)
            else
                report_table = nil
                report_selection = -1
            end
        end
        ImGui.End(ctx)
    end
    if open then
        reaper.defer(Main)
    end
end
reaper.set_action_options(1 | 4)
kb_ini = ReadFile(reaper.GetResourcePath() .. "/reaper-kb.ini")
shortcut_cache_checksum = Checksum(kb_ini)
Main()
reaper.atexit(Exit)
