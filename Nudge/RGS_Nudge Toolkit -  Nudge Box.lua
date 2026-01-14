-- @description Nudge Toolkit
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0
-- @screenshot https://i.ibb.co/LzWpMDRt/Nudge-Box-screenshot.gif
-- @provides
--    [main] *.lua
-- @about 
--  # Nudge Toolkit
--
--  **Nudge Toolkit** is a comprehensive suite of ReaScripts designed to replace and
--  greatly expand REAPER’s native nudge features. The package includes **70+ tightly
--  integrated scripts** for nudging a wide range of elements in REAPER, along with
--  actions for toggling and managing nudge-related settings.

--  ## Highlights

--  - **Nudge almost anything** -  razor selections, media items, automation items,
--  fades, snap offsets, item contents, item start/end positions, loop points,
--  time selections, and the edit cursor. *Support for nudging markers and regions
--  is coming soon.*
--  
--  - **Nudge Box** - A compact, customizable GUI for viewing and editing the current
--  nudge amount and unit.Clicking the word “Nudge” opens quick access to additional
--  settings and features.Nudge Box can be styled to match your REAPER theme and is
--  designed to live in the transport bar, though it can be freely positioned anywhere
--  on screen.
--  
--  - **Contextual Nudge** - “Smart” nudge actions that automatically adapt to your
--  current selection. Contextual Nudge actions use the following priority order:
--  **razor edits → media & automation items → edit cursor.**
--  
--  - Toggleable options to move razor edits with or without their contents.
--  
--  - Fully respects REAPER’s ripple editing, trim behind, and snap settings.

local ScriptName = "Nudge Box"
local ScriptVersion = "1.0"

local debug = false
local profiler

if debug then
    profiler = dofile(reaper.GetResourcePath() ..
    '/Scripts/ReaTeam Scripts/Development/cfillion_Lua profiler.lua')
    reaper.defer = profiler.defer
end

local function Msg(param)
    if debug then
        reaper.ShowConsoleMsg(tostring(param) .. "\n")
    end
end
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
    if not TestVersion(imgui_version,{0,10,0,2}) then
        no_imgui = true
    end
end

if no_imgui then
    missing_dependencies = "ReaImGui (version 0.10.0.2 or higher)\n"
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
local ImGui = require "imgui" "0.10.0.2"
local ctx = ImGui.CreateContext(ScriptName)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_KeyRepeatDelay, .5)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_KeyRepeatRate, .1)

local is_macos = reaper.GetOS():match("OS")


local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end


local nudge_value
local selected_nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge", "selected_nudge_unit")) or 1
local actual_frame_rate = reaper.TimeMap_curFrameRate(0)
local frame_rate = actual_frame_rate
if math.abs(frame_rate  - 24 / 1.001) < 0.001 then
    frame_rate = 24
end
if math.abs(frame_rate  - 30 / 1.001) < 0.001 then
    frame_rate = 30
end
--Preset Tables
local minutes_seconds_presets = {
    {name = "1 Second", value = 1},
    {name = "500 msec", value = .5},
    {name = "100 msec", value = .1},
    {name = "10 msec", value = .01},
    {name = "1 msec", value = .001}
}
local seconds_presets = {
    {name = "1 Second", value = 1},
    {name = "500 msec", value = .5},
    {name = "100 msec", value = .1},
    {name = "10 msec", value = .01},
    {name = "1 msec", value = .001}
}
local frames_presets = {
    {name = "1 sec", value = frame_rate},
    {name = "6 frames", value = 6},
    {name = "1 frame", value = 1},
    {name = "1/2 frame", value = .5},
    {name = "1/4 frame", value = .25},
    {name = "1 sub-frame", value = .01}
}
local timecode_presets = {
    {name = "1 sec", value = frame_rate},
    {name = "6 frames", value = 6},
    {name = "1 frame", value = 1},
    {name = "1/2 frame", value = .5},
    {name = "1/4 frame", value = .25},
    {name = "1 sub-frame", value = .01}
}
local samples_presets = {
    {name = "10000 Samples", value = 10000},
    {name = "1000 Samples", value = 1000},
    {name = "100 Samples", value = 100},
    {name = "10 Samples", value = 10},
    {name = "2 Samples", value = 2},
    {name = "1 Samples", value = 1}
}
local beats_presets = {
    {name = "1 Bar", value = "1.0.0"},
    {name = "1 Beat", value = "0.1.0"}
}
--Nudge Unit Tables
local nudge_units = {}
local unit_table_minutes_seconds = {
    unit = "Minutes:Second",
    format = "",
    speed = 1,
    min = 0,
    selected = false,
    presets = minutes_seconds_presets,
    ruler = 0,
    snap_unit = "Second",
    unit_number = 1,
    is_note = false,
    action_id = "_RS9c354c8892928e875e71c2b5cfaed2b12eac1ff9"
}
table.insert(nudge_units, unit_table_minutes_seconds)
local unit_table_beats = {
    unit = "Measures.Beat",
    format = "%.6f",
    speed = 1,
    min = 0,
    selected = false,
    presets = beats_presets,
    ruler = 2,
    snap_unit = "Bar",
    unit_number = 16,
    is_note = false,
    action_id = "_RS8fe160e0a71a47c69d9443d9f3dfb2290e85c519"
}
table.insert(nudge_units, unit_table_beats)
local unit_table_seconds = {
    unit = "Second",
    format = "%.3f",
    speed = .01,
    min = 0,
    selected = false,
    presets = seconds_presets,
    ruler = 3,
    snap_unit = "Second",
    unit_number = 1,
    is_note = false,
    action_id = "_RS5eeeb4f5575b1dd73d05429ba442c8ca2f2edb57"
}
table.insert(nudge_units, unit_table_seconds)
local unit_table_samples = {
    unit = "Sample",
    format = "%.0f",
    speed = .5,
    min = 0,
    selected = false,
    presets = samples_presets,
    ruler = 4,
    snap_unit = "Sample",
    unit_number = 17,
    is_note = false,
    action_id = "_RS0c4e114b9c7e5ab9e75a779f2374d6ae40b0b835"
}
table.insert(nudge_units, unit_table_samples)
local unit_table_timecode = {
    unit = "Hours:Minutes:Seconds:Frames.Subframe",
    format = "",
    speed = 1,
    min = 0,
    selected = false,
    presets = timecode_presets,
    ruler = 5,
    snap_unit = "Frame",
    unit_number = 18,
    is_note = false,
    action_id = "_RS6f4b859018b3caee45216cf9603de13f1c64393e"
}
table.insert(nudge_units, unit_table_timecode)
local unit_table_frames = {
    unit = "Frame",
    format = "%.2f",
    speed = 1,
    min = 0,
    selected = false,
    presets = frames_presets,
    ruler = 8,
    snap_unit = "Frame",
    unit_number = 18,
    is_note = false,
    action_id = "_RS41ee7fa6cbdae6935e4f2d124afb6ecb601b904c"
}
table.insert(nudge_units, unit_table_frames)
local unit_table_whole_notes = {
    unit = "𝅝",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 15,
    is_note = true,
    action_id = "_RSb5164b0de0d03b9e4143fa41eafe528c7d032665"
}
table.insert(nudge_units, unit_table_whole_notes)
local unit_table_half_notes = {
    unit = "𝅗𝅥",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 14,
    is_note = true,
    action_id = "_RS2e73a76e3656855b74cbbd9f6a71a1591d4dec4c"
}
table.insert(nudge_units, unit_table_half_notes)
local unit_table_quarter_notes = {
    unit = "𝅘𝅥",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 13,
    is_note = true,
    action_id = "_RS7fa5ccc3b6e6553dd7d4e0ab82d918987ae44809"
}
table.insert(nudge_units, unit_table_quarter_notes)
local unit_table_quarter_note_triplets = {
    unit = "𝅘𝅥₃",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 12,
    is_note = true,
    action_id = "_RSd6af6a9ee632154344de220b776287b254ab406c"
}
table.insert(nudge_units, unit_table_quarter_note_triplets)
local unit_table_eighth_notes = {
    unit = "𝅘𝅥𝅮",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 11,
    is_note = true,
    action_id = "_RSf951ec45648c65b1baad3d2e48b1618b0c4545bd"
}
table.insert(nudge_units, unit_table_eighth_notes)
local unit_table_eighth_note_triplets = {
    unit = "𝅘𝅥𝅮₃",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 10,
    is_note = true,
    action_id = "_RSa56f66b91b5ac7f56219f70fbba5eb7942b8f954"
}
table.insert(nudge_units, unit_table_eighth_note_triplets)
local unit_table_sixteenth_notes = {
    unit = "𝅘𝅥𝅯",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 9,
    is_note = true,
    action_id = "_RSee623759a51e82624b0a85f61ec1a6305d153ed7"
}
table.insert(nudge_units, unit_table_sixteenth_notes)
local unit_table_sixteenth_note_triplets = {
    unit = "𝅘𝅥𝅯₃",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 8,
    is_note = true,
    action_id = "_RS25ab542dfe4bf64628da31991d23297fabc2f9dd"
}
table.insert(nudge_units, unit_table_sixteenth_note_triplets)
local unit_table_thirtysecond_notes = {
    unit = "𝅘𝅥𝅰",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 7,
    is_note = true,
    action_id = "_RSed403bfba96d9aeb39105c0dd44787609b4d76f6"
}
table.insert(nudge_units, unit_table_thirtysecond_notes)
local unit_table_thirtysecond_note_triplets = {
    unit = "𝅘𝅥𝅰₃",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 6,
    is_note = true,
    action_id = "_RS6a6178e0ec51798a5427524ef1058ac4206c0b0b"
}
table.insert(nudge_units, unit_table_thirtysecond_note_triplets)
local unit_table_sixtyfourth_notes = {
    unit = "𝅘𝅥𝅱",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 5,
    is_note = true,
    action_id = "_RS8b1f863c4cb0b6884f6ac9afebe862ef7478790c"
}
table.insert(nudge_units, unit_table_sixtyfourth_notes)
local unit_table_hundredtwentyeighth_notes = {
    unit = "𝅘𝅥𝅲",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 4,
    is_note = true,
    action_id = "_RSdf91ccd381825e3f96794bab03165f05d2630a6c"
}
table.insert(nudge_units, unit_table_hundredtwentyeighth_notes)
local unit_table_twohundredfiftysixth_notes = {
    unit = "¹⁄₂₅₆ Note",
    format = "%g",
    speed = 1,
    min = 0,
    selected = false,
    presets = nil,
    ruler = -1,
    snap_unit = "Note",
    unit_number = 3,
    is_note = true,
    action_id = "_RSbd82fa4c8e299b1b9b67a79d5b386704d21bbabd"
}
table.insert(nudge_units, unit_table_twohundredfiftysixth_notes)
for i = 1, #nudge_units do
    if i == selected_nudge_unit then
        nudge_units[i].selected = true
    end
end
reaper.SetExtState("RGS_Nudge", "number_of_nudge_units", tostring(#nudge_units), true)



local window_name = ScriptName .. " " .. ScriptVersion
local focus_window = reaper.JS_Window_GetFocus()
local parent_window = reaper.JS_Window_GetParent(focus_window)
local foreground_window = reaper.JS_Window_GetForeground()
local shortcut_cache = {}
local shortcut_cache_checksum
local kb_ini
local gui_w = 172
local gui_h = 36
local max_int = 2147483647
local tiny_number = 10 ^ (-15)

local hour_max = max_int
local minute_max = max_int
local second_max = max_int
local msecond_max = max_int
local tc_hour_max = max_int
local tc_minute_max = max_int
local tc_second_max = max_int
local frame_max = max_int
local subframe_max = max_int
local beat_max = max_int
local sub_beat_max = 99
local bar_max = max_int

local hour_dragging
local minute_dragging
local second_dragging
local msecond_dragging
local tc_hour_dragging
local tc_minute_dragging
local tc_second_dragging
local frame_dragging
local subframe_dragging

local hour_typing
local minute_typing
local second_typing
local msecond_typing
local tc_hour_typing
local tc_minute_typing
local tc_second_typing
local frame_typing
local subframe_typing

local hour_highlighted
local minute_highlighted
local second_highlighted
local msecond_highlighted
local tc_hour_highlighted
local tc_minute_highlighted
local tc_second_highlighted
local frame_highlighted
local subframe_highlighted

local ruler_unit
local ruler_switched
local unit_switched = true

local msecond_value
local second_value
local minute_value
local hour_value
local tc_hour_value
local tc_minute_value
local tc_second_value
local frame_value
local subframe_value
local beat_value
local sub_beat_value
local bar_value

local msecond_width
local second_width
local minute_width
local hour_width
local tc_hour_width
local tc_minute_width
local tc_second_width
local frame_width
local subframe_width
local beat_width
local sub_beat_width
local bar_width

local msecond_margin = 3
local second_margin = 3
local minute_margin = 3
local hour_margin = 3
local tc_hour_margin = 3
local tc_minute_margin = 3
local tc_second_margin = 3
local frame_margin = 3
local subframe_margin = 3
local beat_margin = 3
local sub_beat_margin = 3
local bar_margin = 3

local minutes_seconds_activated
local tc_activated


local nudge_cursor_with_razors_id = reaper.NamedCommandLookup("_RSc8220f9335ba4d60493c3be0c03c04d3b2f53bfe")
local nudge_razor_contents_envelopes_id = reaper.NamedCommandLookup("_RS1cb9fc67e73cda9bb5ba105a2c909af60be3971f")
local nudge_razor_contents_items_id = reaper.NamedCommandLookup("_RS4196752bb5ed47556e1472ffe96d94528c0271c1")
local nudge_time_sel_with_razors_id = reaper.NamedCommandLookup("_RS518677f0a0791db4e7a780b4a39c3fd405404831")
local snap_to_unit_id = reaper.NamedCommandLookup("_RS55ef93581912d8fe43cffaeb9534142d7ae98c6e")
local ruler_command_id = reaper.NamedCommandLookup("_RS6f744f0eb06777db3feaba50bcc49bbce161348d")

local reaper_vp = ImGui.GetMainViewport(ctx)
local old_reaper_x, old_reaper_y = ImGui.Viewport_GetPos(reaper_vp)

local font_names ={}
if is_macos then
    font_names = {
        "Sans-serif",
        "Serif",
        "Monospace",
        "American Typewriter",
        "Arial",
        "Baskerville",
        "Big Caslon",
        "Brush Script MT",
        "Comic Sans MS",
        "Copperplate",
        "Courier New",
        "Futura",
        "Geneva",
        "Georgia",
        "Gill Sans",
        "Helvetica",
        "Herculanum",
        "Impact",
        "Lucida Grande",
        "Marker Felt",
        "Monaco",
        "Optima",
        "Palatino",
        "Papyrus",
        "Trebuchet MS",
        "Times New Roman",
        "Verdana",
    }
else
    font_names ={
        "Sans-serif",
        "Serif",
        "Monospace",
        "Arial",
        "Bahnschrift",
        "Calibri",
        "Calisto MT",
        "Cambria",
        "Candara",
        "Century Gothic",
        "Comic Sans MS",
        "Consolas",
        "Constantia",
        "Copperplate Gothic",
        "Corbel",
        "Courier New",
        "Franklin Gothic",
        "Gabriola",
        "Georgia",
        "Impact",
        "Lucida Sans",
        "Palatino",
        "Tahoma",
        "Times New Roman",
        "Trebuchet MS",
        "Verdana"

    }
end
local longest_font_name = 1
local fonts = {}
local bold_fonts = {}

for i = 1, #font_names do
    local font = ImGui.CreateFont(font_names[i], ImGui.FontFlags_None)
    local bold_font = ImGui.CreateFont(font_names[i], ImGui.FontFlags_Bold)
    table.insert(fonts, font)
    table.insert(bold_fonts, bold_font)
    local width = ImGui.CalcTextSize(ctx, font_names[i])
    local longest_width = ImGui.CalcTextSize(ctx, font_names[longest_font_name])
    if width > longest_width then
        longest_font_name = i
    end
end

local bg_color = tonumber(reaper.GetExtState("RGS_Nudge","bg_color")) or 0x242424FF
local rounding = tonumber(reaper.GetExtState("RGS_Nudge","rounding")) or 5
local padding_x = tonumber(reaper.GetExtState("RGS_Nudge","padding_x")) or 10
local padding_y = tonumber(reaper.GetExtState("RGS_Nudge","padding_y")) or 10
local main_font
local main_font_size
if is_macos then
    main_font = tonumber(reaper.GetExtState("RGS_Nudge", "main_font_mac")) or 16
    main_font_size = tonumber(reaper.GetExtState("RGS_Nudge","main_font_size_mac")) or 11
else
    main_font = tonumber(reaper.GetExtState("RGS_Nudge", "main_font")) or 6
    main_font_size = tonumber(reaper.GetExtState("RGS_Nudge","main_font_size")) or 10
end

if is_macos then
   
else
   
end
local main_font_color = tonumber(reaper.GetExtState("RGS_Nudge","main_font_color")) or 0x969696FF
local main_font_bold
if not reaper.HasExtState("RGS_Nudge","main_font_bold") then
    main_font_bold = false
else
    main_font_bold = ToBoolean(reaper.GetExtState("RGS_Nudge","main_font_bold"))
end

local menu_bg_color = tonumber(reaper.GetExtState("RGS_Nudge","menu_bg_color")) or 0x262626DA
local menu_rounding = tonumber(reaper.GetExtState("RGS_Nudge","menu_rounding")) or 6
local menu_padding_x = tonumber(reaper.GetExtState("RGS_Nudge","menu_padding_x")) or 8
local menu_padding_y = tonumber(reaper.GetExtState("RGS_Nudge","menu_padding_y")) or 8
local menu_font
local menu_font_size
if is_macos then
    menu_font = tonumber(reaper.GetExtState("RGS_Nudge","menu_font_mac")) or 1
    menu_font_size = tonumber(reaper.GetExtState("RGS_Nudge","menu_font_size_mac")) or 12
else
    menu_font = tonumber(reaper.GetExtState("RGS_Nudge","menu_font_mac")) or 1
    menu_font_size = tonumber(reaper.GetExtState("RGS_Nudge","menu_font_size_mac")) or 12
end
local menu_font_color =  tonumber(reaper.GetExtState("RGS_Nudge","menu_font_color")) or 0xE3E3E3FF
local menu_font_bold
if not reaper.HasExtState("RGS_Nudge","menu_font_bold") then
    menu_font_bold = true
else
    menu_font_bold = ToBoolean(reaper.GetExtState("RGS_Nudge","menu_font_bold"))
end

local window_flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoDocking
local settings_window_flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoCollapse|ImGui.WindowFlags_NoDocking
local font_combo_flags = ImGui.ComboFlags_HeightSmall
local font_color_flags = ImGui.ColorEditFlags_NoInputs
local bg_color_flags = ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_AlphaBar


local show_settings = false

--Functions
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
    return content
end

local function FollowReaper()
    local reaper_x, reaper_y = ImGui.Viewport_GetPos(reaper_vp)
    if reaper_x == old_reaper_x and reaper_y == old_reaper_y then
        return
    end

    local pos_x, pos_y = ImGui.GetWindowPos(ctx)
    local delta_x, delta_y = reaper_x - old_reaper_x, reaper_y - old_reaper_y
    ImGui.SetWindowPos(ctx, pos_x + delta_x, pos_y + delta_y)
    old_reaper_x, old_reaper_y = reaper_x, reaper_y
end

local function GetLastFocusedWindow()
    local section_id = 0
    if not ImGui.IsWindowFocused(ctx) then
        if reaper.JS_Window_GetTitle(reaper.JS_Window_GetParent(reaper.JS_Window_GetFocus())) ~= script_name then
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
        for idx = 0, shortcut_count do
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

local function GetPrimaryRulerTimeMode()
    local _, ruler_time_mode = reaper.get_config_var_string("projtimemode")
    local ruler_time_mode_hex = string.format("%x", ruler_time_mode)
    local primary_ruler_time_mode = tonumber("0x" .. string.sub(ruler_time_mode_hex, -1))
    if
        primary_ruler_time_mode == 1 or primary_ruler_time_mode == 6 or primary_ruler_time_mode == 7 or
            primary_ruler_time_mode == 10
     then
        primary_ruler_time_mode = 2
    end
    if primary_ruler_time_mode == 11 then
        primary_ruler_time_mode = 0
    end
    return primary_ruler_time_mode
end

local function exit()
    reaper.set_action_options(8)
    reaper.SetExtState("RGS_Nudge", "bg_color", tostring(bg_color), true)
    reaper.SetExtState("RGS_Nudge", "rounding", tostring(rounding), true)
    reaper.SetExtState("RGS_Nudge", "padding_x", tostring(padding_x), true)
    reaper.SetExtState("RGS_Nudge", "padding_y", tostring(padding_y), true)
    if is_macos then
        reaper.SetExtState("RGS_Nudge", "main_font_mac", tostring(main_font), true)
        reaper.SetExtState("RGS_Nudge", "main_font_size_mac", tostring(main_font_size), true)
        reaper.SetExtState("RGS_Nudge", "menu_font_mac", tostring(menu_font), true)
        reaper.SetExtState("RGS_Nudge", "menu_font_size_mac", tostring(menu_font_size), true)
    else
        reaper.SetExtState("RGS_Nudge", "main_font", tostring(main_font), true)
        reaper.SetExtState("RGS_Nudge", "main_font_size", tostring(main_font_size), true)
        reaper.SetExtState("RGS_Nudge", "menu_font", tostring(menu_font), true)
        reaper.SetExtState("RGS_Nudge", "menu_font_size", tostring(menu_font_size), true)
    end

    reaper.SetExtState("RGS_Nudge", "main_font_color", tostring(main_font_color), true)
    reaper.SetExtState("RGS_Nudge", "main_font_bold", tostring(main_font_bold), true)
    reaper.SetExtState("RGS_Nudge", "menu_bg_color", tostring(menu_bg_color), true)
    reaper.SetExtState("RGS_Nudge", "menu_rounding", tostring(menu_rounding), true)
    reaper.SetExtState("RGS_Nudge", "menu_padding_x", tostring(menu_padding_x), true)
    reaper.SetExtState("RGS_Nudge", "menu_padding_y", tostring(menu_padding_y), true)
    reaper.SetExtState("RGS_Nudge", "menu_font", tostring(menu_font), true)
    reaper.SetExtState("RGS_Nudge", "menu_font_size", tostring(menu_font_size), true)
    reaper.SetExtState("RGS_Nudge", "menu_font_color", tostring(menu_font_color), true)
    reaper.SetExtState("RGS_Nudge", "menu_font_bold", tostring(menu_font_bold), true)
end

local function loop()
    local focused_window, section_id = GetLastFocusedWindow()
    local nudge_cursor_with_razors = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_cursor_with_razors"))
    local nudge_time_sel_with_razors = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_time_sel_with_razors"))
    local nudge_razor_contents_items = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_items"))
    local nudge_razor_contents_envelopes = ToBoolean(reaper.GetExtState("RGS_Nudge", "nudge_razor_contents_envelopes"))
    local snap_to_unit = ToBoolean(reaper.GetExtState("RGS_Nudge", "snap_to_unit"))
    local follow_ruler = ToBoolean(reaper.GetExtState("RGS_Nudge", "follow_ruler"))
    if not reaper.HasExtState("RGS_Nudge", "nudge_value") then
        if not nudge_units[selected_nudge_unit].is_note then
            nudge_value = nudge_units[selected_nudge_unit].presets[1].value
        else
            nudge_value = 1
        end
    elseif nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
        nudge_value = reaper.GetExtState("RGS_Nudge", "nudge_value")
    else
        nudge_value = tonumber(reaper.GetExtState("RGS_Nudge", "nudge_value"))
    end
    if selected_nudge_unit ~= tonumber(reaper.GetExtState("RGS_Nudge", "selected_nudge_unit")) then
        unit_switched = true
    end
    if not reaper.HasExtState("RGS_Nudge", "selected_nudge_unit") then
        selected_nudge_unit = 1
    elseif unit_switched or reaper.GetExtState("RGS_Nudge", "unit_switched") == "true" then
        Msg("Unit Switched")
        reaper.DeleteExtState("RGS_Nudge", "unit_switched", true)
        selected_nudge_unit = tonumber(reaper.GetExtState("RGS_Nudge", "selected_nudge_unit"))
        if nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
            nudge_value = reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value")
        else
            nudge_value = tonumber(reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value"))
        end
        for i = 1, #nudge_units do
            nudge_units[i].selected = false
        end
        nudge_units[selected_nudge_unit].selected = true
        unit_switched = false
    end


    ImGui.SetNextWindowSize(ctx, gui_w, gui_h, ImGui.Cond_FirstUseEver)

    for i = 1, #fonts do
        ImGui.PushFont(ctx, fonts[i], main_font_size)
        ImGui.PopFont(ctx)
        ImGui.PushFont(ctx, bold_fonts[i], main_font_size)
        ImGui.PopFont(ctx)
    end

    if main_font_bold then
        ImGui.PushFont(ctx, bold_fonts[main_font], main_font_size)
    else
        ImGui.PushFont(ctx, fonts[main_font], main_font_size)
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, padding_x, padding_y)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, rounding)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, menu_rounding)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowMinSize, 8, 8)
    local style_count = 5

    ImGui.PushStyleColor(ctx, ImGui.Col_Text, main_font_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0XFFFFFF45)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, menu_bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ResizeGrip, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ResizeGripActive, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_ResizeGripHovered, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_SeparatorActive, bg_color)
    ImGui.PushStyleColor(ctx, ImGui.Col_SeparatorHovered, bg_color)

    local color_count = 12
    --Begin

    local visible, open = ImGui.Begin(ctx, window_name, true, window_flags)

    if ruler_unit ~= GetPrimaryRulerTimeMode() then
        ruler_switched = true
    end

    -- Switch selected unit to ruler unit if Option to follow ruler is on
    if follow_ruler and ruler_switched then
        ruler_unit = GetPrimaryRulerTimeMode()
        for i = 1, #nudge_units do
            nudge_units[i].selected = false
            if nudge_units[i].ruler == ruler_unit then
                selected_nudge_unit = i
                reaper.SetExtState("RGS_Nudge", "selected_nudge_unit", tostring(selected_nudge_unit), true)                
                if not reaper.HasExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value") then
                    if not nudge_units[selected_nudge_unit].is_note then
                        nudge_value = nudge_units[selected_nudge_unit].presets[1].value
                    else
                        nudge_value = 1
                    end
                elseif nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
                    nudge_value = reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value")
                else
                    nudge_value = tonumber(reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value"))
                end
            end
        end
        ruler_switched = false
    end

    --Refresh Frame Presets if frame rate has changes
    if actual_frame_rate ~= reaper.TimeMap_curFrameRate(0) then
        actual_frame_rate = reaper.TimeMap_curFrameRate(0)
        frame_rate = actual_frame_rate
        if math.abs(frame_rate  - 24 / 1.001) < 0.001 then
            frame_rate = 24
        end
        if math.abs(frame_rate  - 30 / 1.001) < 0.001 then
            frame_rate = 30
        end
        frames_presets[1].value = frame_rate
        for i = 1, #nudge_units do
            if nudge_units[i].unit == "Frame" then
                nudge_units[i].presets = frames_presets
            end
        end
        timecode_presets[1].value = frame_rate
        for i = 1, #nudge_units do
            if nudge_units[i].unit == "Hours:Minutes:Seconds:Frames.Subframe" then
                nudge_units[i].presets = timecode_presets
            end
        end
    end
    --UI Body
    if visible then
        if not ImGui.IsAnyItemActive(ctx) then
            PassShortcut(section_id, focused_window)
        end
        if ImGui.Button(ctx, "Nudge") then
            ImGui.OpenPopup(ctx, "nudge_popup")
        end
        --Popup Menu

        --ImGui.SetNextWindowPos(ctx, menu_x, menu_y)
        if menu_font_bold then
            ImGui.PushFont(ctx, bold_fonts[menu_font], menu_font_size)
        else
            ImGui.PushFont(ctx, fonts[menu_font], menu_font_size)
        end
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, menu_padding_x, menu_padding_y)
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, menu_font_color)
        if ImGui.BeginPopup(ctx, "nudge_popup", ImGui.WindowFlags_NoMove) then
            -- Presets
            if nudge_units[selected_nudge_unit].presets then
                for i = 1, #nudge_units[selected_nudge_unit].presets do
                    local label = nudge_units[selected_nudge_unit].presets[i].name
                    local preset_selected = false
                    local preset_value = nudge_units[selected_nudge_unit].presets[i].value
                    if nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
                        if nudge_value == preset_value then
                            preset_selected = true
                        end
                    elseif math.abs(nudge_value - preset_value) < tiny_number then
                        preset_selected = true
                    end
                    if ImGui.MenuItem(ctx, label, "", preset_selected) then
                        nudge_value = preset_value
                    end
                end
                ImGui.Separator(ctx)
            end
            --Nudge Unit
            if ImGui.MenuItem(ctx, "Use Primary Ruler Time Format", "", ToBoolean(follow_ruler)) then
                follow_ruler = true
                ruler_switched = true
                reaper.SetToggleCommandState(0, ruler_command_id, 1)
                reaper.RefreshToolbar2(0, ruler_command_id)
                reaper.SetExtState("RGS_Nudge", "follow_ruler", tostring(follow_ruler), true)
                for i = 1, #nudge_units do
                    local command_id = reaper.NamedCommandLookup(nudge_units[i].action_id)
                    reaper.SetToggleCommandState(0, command_id, 0)
                    reaper.RefreshToolbar2(0, command_id)
                end
            end

            for i = 1, #nudge_units do
                if not nudge_units[i].is_note then
                    local label = nudge_units[i].unit .. "s"
                    if ImGui.MenuItem(ctx, label, "", nudge_units[i].selected) then
                        selected_nudge_unit = i
                        local command_id = reaper.NamedCommandLookup(nudge_units[i].action_id)
                        reaper.SetExtState("RGS_Nudge", "selected_nudge_unit", tostring(selected_nudge_unit), true)
                        for j = 1, #nudge_units do
                            local command_id = reaper.NamedCommandLookup(nudge_units[j].action_id)
                            nudge_units[j].selected = false
                            reaper.SetToggleCommandState(0, command_id, 0)
                            reaper.RefreshToolbar2(0, command_id)
                        end
                        reaper.SetToggleCommandState(0, ruler_command_id, 0)
                        reaper.RefreshToolbar2(0, ruler_command_id)
                        reaper.SetToggleCommandState(0, command_id, 1)
                        reaper.RefreshToolbar2(0, command_id)
                        nudge_units[i].selected = true
                        follow_ruler = false
                        reaper.SetExtState("RGS_Nudge", "follow_ruler", tostring(follow_ruler), true)
                        if not reaper.HasExtState("RGS_Nudge","unit_" .. tostring(selected_nudge_unit) .. "_nudge_value") then
                            if not nudge_units[selected_nudge_unit].is_note then
                                nudge_value = nudge_units[selected_nudge_unit].presets[1].value
                            else
                                nudge_value = 1
                            end
                        elseif nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
                            nudge_value = reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value")
                        else
                            nudge_value = tonumber(reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value"))
                        end
                    end
                end
            end
            if ImGui.BeginMenu(ctx, "Notes") then
                ImGui.PushFont(ctx, nil, menu_font_size + 5)
                for i = 1, #nudge_units do
                    if nudge_units[i].is_note then
                        local label = nudge_units[i].unit
                        local command_id = reaper.NamedCommandLookup(nudge_units[i].action_id)
                        if ImGui.MenuItem(ctx, label, "", nudge_units[i].selected) then
                            selected_nudge_unit = i
                            reaper.SetExtState("RGS_Nudge", "selected_nudge_unit", tostring(selected_nudge_unit), true)
                            for j = 1, #nudge_units do
                                local command_id = reaper.NamedCommandLookup(nudge_units[j].action_id)
                                nudge_units[j].selected = false
                                reaper.SetToggleCommandState(0, command_id, 0)
                                reaper.RefreshToolbar2(0, command_id)
                            end
                            reaper.SetToggleCommandState(0, command_id, 1)
                            reaper.RefreshToolbar2(0, command_id)
                            reaper.SetToggleCommandState(0, ruler_command_id, 0)
                            reaper.RefreshToolbar2(0, ruler_command_id)
                            nudge_units[i].selected = true
                            follow_ruler = false
                            reaper.SetExtState("RGS_Nudge", "follow_ruler", tostring(follow_ruler), true)
                            if not reaper.HasExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value") then
                                nudge_value = 1
                            else
                                nudge_value = tonumber(reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value"))
                            end
                        end
                    end
                end
                ImGui.PopFont(ctx)
                ImGui.EndMenu(ctx)
            end

            if follow_ruler == true then
                nudge_units[selected_nudge_unit].selected = false
            end

            -- Options
            ImGui.Separator(ctx)
            do
                local snap_string = "Snap to " .. nudge_units[selected_nudge_unit].snap_unit
                if nudge_units[selected_nudge_unit].unit ~= "Sample" then
                    if ImGui.MenuItem(ctx, snap_string, "", ToBoolean(snap_to_unit)) then
                        if snap_to_unit then
                            reaper.SetToggleCommandState(0, snap_to_unit_id, 0)
                            reaper.RefreshToolbar2(0, snap_to_unit_id)
                        else
                            reaper.SetToggleCommandState(0, snap_to_unit_id, 1)
                            reaper.RefreshToolbar2(0, snap_to_unit_id)
                        end

                        snap_to_unit = not snap_to_unit
                        reaper.SetExtState("RGS_Nudge", "snap_to_unit", tostring(snap_to_unit), true)
                    end
                end
            end
            if ImGui.MenuItem(ctx, "Nudge cursor with razor edits", "", ToBoolean(nudge_cursor_with_razors)) then
                if nudge_cursor_with_razors then
                    reaper.SetToggleCommandState(0, nudge_cursor_with_razors_id, 0)
                    reaper.RefreshToolbar2(0, nudge_cursor_with_razors_id)
                else
                    reaper.SetToggleCommandState(0, nudge_cursor_with_razors_id, 1)
                    reaper.RefreshToolbar2(0, nudge_cursor_with_razors_id)
                end

                nudge_cursor_with_razors = not nudge_cursor_with_razors
                reaper.SetExtState("RGS_Nudge", "nudge_cursor_with_razors", tostring(nudge_cursor_with_razors), true)
            end
            if ImGui.MenuItem(ctx, "Nudge time selection with razor edits", "", ToBoolean(nudge_time_sel_with_razors)) then
                if nudge_time_sel_with_razors then
                    reaper.SetToggleCommandState(0, nudge_time_sel_with_razors_id, 0)
                    reaper.RefreshToolbar2(0, nudge_time_sel_with_razors_id)
                else
                    reaper.SetToggleCommandState(0, nudge_time_sel_with_razors_id, 1)
                    reaper.RefreshToolbar2(0, nudge_time_sel_with_razors_id)
                end
                nudge_time_sel_with_razors = not nudge_time_sel_with_razors
                reaper.SetExtState("RGS_Nudge","nudge_time_sel_with_razors",tostring(nudge_time_sel_with_razors),true)
            end
            if ImGui.MenuItem(ctx, "Nudge items with razor edits", "", ToBoolean(nudge_razor_contents_items)) then
                if nudge_razor_contents_items then
                    reaper.SetToggleCommandState(0, nudge_razor_contents_items_id, 0)
                    reaper.RefreshToolbar2(0, nudge_razor_contents_items_id)
                else
                    reaper.SetToggleCommandState(0, nudge_razor_contents_items_id, 1)
                    reaper.RefreshToolbar2(0, nudge_razor_contents_items_id)
                end
                nudge_razor_contents_items = not nudge_razor_contents_items
                reaper.SetExtState("RGS_Nudge", "nudge_razor_contents_items", tostring(nudge_razor_contents_items), true)
            end
            if ImGui.MenuItem(ctx, "Nudge envelopes with razor edits", "", ToBoolean(nudge_razor_contents_envelopes)) then
                if nudge_razor_contents_envelopes then
                    reaper.SetToggleCommandState(0, nudge_razor_contents_envelopes_id, 0)
                    reaper.RefreshToolbar2(0, nudge_razor_contents_envelopes_id)
                else
                    reaper.SetToggleCommandState(0, nudge_razor_contents_envelopes_id, 1)
                    reaper.RefreshToolbar2(0, nudge_razor_contents_envelopes_id)
                end
                nudge_razor_contents_envelopes = not nudge_razor_contents_envelopes
                reaper.SetExtState("RGS_Nudge", "nudge_razor_contents_envelopes", tostring(nudge_razor_contents_envelopes), true)
            end

            ImGui.Separator(ctx)
            if ImGui.MenuItem(ctx, "Settings") then
                show_settings = true
            end

            ImGui.EndPopup(ctx)
        end
        ImGui.PopFont(ctx)
        ImGui.PopStyleColor(ctx, 1)
        ImGui.PopStyleVar(ctx, 1)
        --Sliders
        ImGui.SameLine(ctx)
        -- HH:MM:SS:FF Slider
        if nudge_units[selected_nudge_unit].unit == "Hours:Minutes:Seconds:Frames.Subframe" then
            --Minutes:Second Slider
            -- Set other modes to inactive
            minutes_seconds_activated = false
            --Get Drop Frame State
            local _, frame_rate_drop = reaper.TimeMap_curFrameRate(0)

            local nudge_value_integer = math.modf(nudge_value)
            --- set Timecode Unit values when Timecode mode is made active
            if not tc_activated then
                subframe_value = math.floor((nudge_value * 100) % 100)
                frame_value = nudge_value_integer % frame_rate
                tc_second_value = math.floor(nudge_value_integer / frame_rate) - 60 * (math.floor(nudge_value / (frame_rate * 60)))
                tc_minute_value = math.floor(nudge_value_integer / (frame_rate * 60)) - 60 * (math.floor(nudge_value_integer / (frame_rate * 3600)))
                tc_hour_value = math.floor(nudge_value_integer / (frame_rate * 3600))
                tc_activated = true
                Msg("Timecode Activated")
            end
            --Minimums (depend on larger units)
            local tc_hour_min = 0
            local tc_minute_min = -(tc_hour_value * 60)
            local tc_second_min = -(tc_minute_value * 60 + tc_hour_value * 3600)
            local frame_min = -(tc_second_value * frame_rate + tc_minute_value * 60 * frame_rate + tc_hour_value * 3600 * frame_rate)
            local subframe_min = -(frame_value * 100 + tc_second_value * frame_rate * 100 + tc_minute_value * 6000 * frame_rate + tc_hour_value * 360000 * frame_rate)

            --Initialize Unit Widths
            if not subframe_width then
                subframe_width = ImGui.CalcTextSize(ctx, string.format("%02d", subframe_value))
            end
            if not frame_width then
                frame_width = ImGui.CalcTextSize(ctx, string.format("%02d", frame_value))
            end
            if not tc_second_width then
                tc_second_width = ImGui.CalcTextSize(ctx, string.format("%02d", tc_second_value))
            end
            if not tc_minute_width then
                tc_minute_width = ImGui.CalcTextSize(ctx, string.format("%02d", tc_minute_value))
            end
            if not tc_hour_width then
                tc_hour_width = ImGui.CalcTextSize(ctx, string.format("%02d", tc_hour_value))
            end

            -- Per Unit State Trackers
            local tc_hour_changed, tc_minute_changed, tc_second_changed, frame_changed, subframe_changed = false, false, false, false, false
            local tc_hour_typed, tc_minute_typed, tc_second_typed, frame_typed, subframe_typed = false, false, false, false, false
            local tc_hour_deactivated, tc_minute_deactivated, tc_second_deactivated, frame_deactivated, subframe_deactivated = false, false, false, false, false
            local tc_hour_currently_dragging, tc_minute_currently_dragging, tc_second_currently_dragging, frame_currently_dragging, subframe_currently_dragging = false, false, false, false, false

            --Hour Slider
            ImGui.SetNextItemWidth(ctx, tc_hour_width + tc_hour_margin)
            tc_hour_changed, tc_hour_value = ImGui.DragInt(ctx, "##tc_hourslider", tc_hour_value, .1, tc_hour_min, tc_hour_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            tc_hour_width = ImGui.CalcTextSize(ctx, string.format("%02d", tc_hour_value))
            tc_hour_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            tc_hour_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ":")

            --Minute Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, tc_minute_width + tc_minute_margin)
            tc_minute_changed, tc_minute_value = ImGui.DragInt(ctx, "##tc_minuteslider", tc_minute_value, .1, tc_minute_min, tc_minute_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            tc_minute_width = ImGui.CalcTextSize(ctx, string.format("%02d", tc_minute_value))
            tc_minute_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            tc_minute_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ":")

            --Second Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, tc_second_width + tc_second_margin)
            tc_second_changed, tc_second_value = ImGui.DragInt(ctx, "##tc_secondslider", tc_second_value, .1, tc_second_min, tc_second_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            tc_second_width = ImGui.CalcTextSize(ctx, string.format("%02d", tc_second_value))
            tc_second_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            tc_second_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
            ImGui.SameLine(ctx, 0, 0)
            if frame_rate_drop then
                ImGui.Text(ctx, ";")
            else
                ImGui.Text(ctx, ":")
            end

            --Frame Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, frame_width + frame_margin)
            frame_changed, frame_value = ImGui.DragInt(ctx, "##frameslider", frame_value, .1, frame_min, frame_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            frame_width = ImGui.CalcTextSize(ctx, string.format("%02d", frame_value))
            frame_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            frame_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ".")

            --Subframe Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, subframe_width + subframe_margin)
            subframe_changed, subframe_value = ImGui.DragInt(ctx, "##subframeslider", subframe_value, .1, subframe_min, subframe_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            subframe_width = ImGui.CalcTextSize(ctx, string.format("%02d", subframe_value))
            subframe_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            subframe_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)

            --Set Hour State Flags
            if tc_hour_changed and tc_hour_currently_dragging and not tc_hour_highlighted then
                tc_hour_dragging = true
            end
            if tc_hour_changed and not tc_hour_currently_dragging then
                tc_hour_typing = true
            end
            if tc_hour_deactivated then
                if tc_hour_dragging then
                    tc_hour_dragging = false
                else
                    tc_hour_typed = true
                end
                tc_hour_typing = false
                tc_hour_highlighted = false
            end
            if not tc_hour_currently_dragging then
                tc_hour_dragging = false
            end
            if tc_hour_typing and tc_hour_dragging then
                tc_hour_highlighted = true
                tc_hour_dragging = false
            end
            if tc_hour_currently_dragging then
                tc_hour_typing = false
            end

            --Set Minute State Flags
            if tc_minute_changed and tc_minute_currently_dragging and not tc_minute_highlighted then
                tc_minute_dragging = true
            end
            if tc_minute_changed and not tc_minute_currently_dragging then
                tc_minute_typing = true
            end
            if tc_minute_deactivated then
                if tc_minute_dragging then
                    tc_minute_dragging = false
                else
                    tc_minute_typed = true
                end
                tc_minute_typing = false
                tc_minute_highlighted = false
            end
            if not tc_minute_currently_dragging then
                tc_minute_dragging = false
            end
            if tc_minute_typing and tc_minute_dragging then
                tc_minute_highlighted = true
                tc_minute_dragging = false
            end
            if tc_minute_currently_dragging then
                tc_minute_typing = false
            end

            --Set Second State Flags
            if tc_second_changed and tc_second_currently_dragging and not tc_second_highlighted then
                tc_second_dragging = true
            end
            if tc_second_changed and not tc_second_currently_dragging then
                tc_second_typing = true
            end
            if tc_second_deactivated then
                if tc_second_dragging then
                    tc_second_dragging = false
                else
                    tc_second_typed = true
                end
                tc_second_typing = false
                tc_second_highlighted = false
            end
            if not tc_second_currently_dragging then
                tc_second_dragging = false
            end
            if tc_second_typing and tc_second_dragging then
                tc_second_highlighted = true
                tc_second_dragging = false
            end
            if tc_second_currently_dragging then
                tc_second_typing = false
            end

            --Set Frame State Flags
            if frame_changed and frame_currently_dragging and not frame_highlighted then
                frame_dragging = true
            end
            if frame_changed and not frame_currently_dragging then
                frame_typing = true
            end
            if frame_deactivated then
                if frame_dragging then
                    frame_dragging = false
                else
                    frame_typed = true
                end
                frame_typing = false
                frame_highlighted = false
            end
            if not frame_currently_dragging then
                frame_dragging = false
            end
            if frame_typing and frame_dragging then
                frame_highlighted = true
                frame_dragging = false
            end
            if frame_currently_dragging then
                frame_typing = false
            end

            --Set Subframe State Flags
            if subframe_changed and subframe_currently_dragging and not subframe_highlighted then
                subframe_dragging = true
            end
            if subframe_changed and not subframe_currently_dragging then
                subframe_typing = true
            end
            if subframe_deactivated then
                if subframe_dragging then
                    subframe_dragging = false
                else
                    subframe_typed = true
                end
                subframe_typing = false
                subframe_highlighted = false
            end
            if not subframe_currently_dragging then
                subframe_dragging = false
            end
            if subframe_typing and subframe_dragging then
                subframe_highlighted = true
                subframe_dragging = false
            end
            if subframe_currently_dragging then
                subframe_typing = false
            end

            --Recompute Nudge Value depending on State (prevents continuous rollover when typing or highlighting)
            if tc_hour_dragging then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                tc_hour_margin = 3
            end
            if tc_hour_typed then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                tc_hour_margin = 3
            end
            if tc_hour_typing then
                tc_hour_margin = 8
            end
            if tc_minute_dragging then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                tc_minute_margin = 3
            end
            if tc_minute_typed then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                tc_minute_margin = 3
            end
            if tc_minute_typing then
                tc_minute_margin = 10
            end
            if tc_second_dragging then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                tc_second_margin = 3
            end
            if tc_second_typed then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                tc_second_margin = 3
            end
            if tc_second_typing then
                tc_second_margin = 10
            end
            if frame_dragging then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                frame_margin = 3
            end
            if frame_typed then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                frame_margin = 3
            end
            if frame_typing then
                frame_margin = 10
            end
            if subframe_dragging then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                subframe_margin = 3
            end
            if subframe_typed then
                nudge_value = (tc_hour_value * frame_rate * 60 * 60) + (tc_minute_value * frame_rate * 60) + (tc_second_value * frame_rate) + frame_value + (subframe_value / 100)
                subframe_margin = 3
            end
            if subframe_typing then
                subframe_margin = 10
            end
            --Total Nudge Value Slider
            if debug then
                _, nudge_value = ImGui.DragDouble(ctx, "##tc_slider", nudge_value, 1, 0, math.huge, "%.2f")
            end
            --Resync Unit Values from Nudge Value
            nudge_value_integer = math.modf(nudge_value)
            subframe_value = math.floor((nudge_value * 100) % 100)
            frame_value = nudge_value_integer % frame_rate
            tc_second_value = math.floor(nudge_value_integer / frame_rate) - 60 * (math.floor(nudge_value / (frame_rate * 60)))
            tc_minute_value = math.floor(nudge_value_integer / (frame_rate * 60)) - 60 * (math.floor(nudge_value_integer / (frame_rate * 3600)))
            tc_hour_value = math.floor(nudge_value_integer / (frame_rate * 3600))
        elseif nudge_units[selected_nudge_unit].unit == "Minutes:Second" then
            -- Set other modes to inactive
            tc_activated = false
            
            local nudge_value_integer = math.modf(nudge_value)
            -- set hour, minute, second, and milliseconds value when Minutes:Seconds mode is made active
            if not minutes_seconds_activated then
                msecond_value = math.floor((nudge_value * 1000) % 1000)
                second_value = nudge_value_integer % 60
                minute_value = math.floor(nudge_value_integer / 60) - 60 * (math.floor(nudge_value_integer / 3600))
                hour_value = math.floor(nudge_value_integer / 3600)
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                minutes_seconds_activated = true
            end
            --Minimums (depend on larger units)
            local hour_min = 0
            local minute_min = -(hour_value * 60)
            local second_min = -(minute_value * 60 + hour_value * 3600)
            local msecond_min = -(second_value * 1000 + minute_value * 60000 + hour_value * 3600000)

            --Initialize Unit Widths
            local minute_string_format = "%d"
            if hour_value > 0. then
                minute_string_format = "%02d"
            end
            if not msecond_width then
                msecond_width = ImGui.CalcTextSize(ctx, string.format("%03d", msecond_value))
            end
            if not second_width then
                second_width = ImGui.CalcTextSize(ctx, string.format("%02d", second_value))
            end
            if not minute_width then
                minute_width = ImGui.CalcTextSize(ctx, string.format(minute_string_format, minute_value))
            end
            if not hour_width then
                hour_width = ImGui.CalcTextSize(ctx, string.format("%d", hour_value))
            end

            -- Per Unit State Trackers
            local hour_changed, minute_changed, second_changed, msecond_changed = false, false, false, false
            local hour_typed, minute_typed, second_typed, msecond_typed = false, false, false, false
            local hour_deactivated, minute_deactivated, second_deactivated, msecond_deactivated = false, false, false, false
            local hour_currently_dragging, minute_currently_dragging, second_currently_dragging, msecond_currently_dragging = false, false, false, false

            --Hour Slider
            if hour_value > 0 then
                ImGui.SetNextItemWidth(ctx, hour_width + hour_margin)
                hour_changed, hour_value = ImGui.DragInt( ctx, "##hourslider", hour_value, .1, hour_min, hour_max, "%d", ImGui.SliderFlags_AlwaysClamp)
                hour_width = ImGui.CalcTextSize(ctx, string.format("%d", hour_value))
                hour_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
                hour_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
                ImGui.SameLine(ctx, 0, 0)
                ImGui.Text(ctx, ":")
            end

            --Minute Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, minute_width + minute_margin)
            minute_changed, minute_value = ImGui.DragInt( ctx, "##minuteslider", minute_value, .1, minute_min, minute_max, minute_string_format, ImGui.SliderFlags_AlwaysClamp)
            minute_width = ImGui.CalcTextSize(ctx, string.format(minute_string_format, minute_value))
            minute_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            minute_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ":")

            --Seconds Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, second_width + second_margin)
            second_changed, second_value = ImGui.DragInt( ctx, "##secondslider", second_value, .1, second_min, second_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            second_width = ImGui.CalcTextSize(ctx, string.format("%02d", second_value))
            second_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            second_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ":")

            --Milliseconds Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, msecond_width + msecond_margin)
            msecond_changed, msecond_value = ImGui.DragInt( ctx, "##msecondslider", msecond_value, .1, msecond_min, msecond_max, "%03d", ImGui.SliderFlags_AlwaysClamp)
            msecond_width = ImGui.CalcTextSize(ctx, string.format("%03d", msecond_value))
            msecond_deactivated = ImGui.IsItemDeactivatedAfterEdit(ctx)
            msecond_currently_dragging = ImGui.IsItemActive(ctx) and ImGui.IsMouseDragging(ctx, 0)

            --Set Hour State Flags
            if hour_changed and hour_currently_dragging and not hour_highlighted then
                hour_dragging = true
            end
            if hour_changed and not hour_currently_dragging then
                hour_typing = true
            end
            if hour_deactivated then
                if hour_dragging then
                    hour_dragging = false
                else
                    hour_typed = true
                end
                hour_typing = false
                hour_highlighted = false
            end
            if not hour_currently_dragging then
                hour_dragging = false
            end
            if hour_typing and hour_dragging then
                hour_highlighted = true
                hour_dragging = false
            end
            if hour_currently_dragging then
                hour_typing = false
            end

            --Set Minute State Flags
            if minute_changed and minute_currently_dragging and not minute_highlighted then
                minute_dragging = true
            end
            if minute_changed and not minute_currently_dragging then
                minute_typing = true
            end
            if minute_deactivated then
                if minute_dragging then
                    minute_dragging = false
                else
                    minute_typed = true
                end
                minute_typing = false
                minute_highlighted = false
            end
            if not minute_currently_dragging then
                minute_dragging = false
            end
            if minute_typing and minute_dragging then
                minute_highlighted = true
                minute_dragging = false
            end
            if minute_currently_dragging then
                minute_typing = false
            end

            --Set Second State Flags
            if second_changed and second_currently_dragging and not second_highlighted then
                second_dragging = true
            end
            if second_changed and not second_currently_dragging then
                second_typing = true
            end
            if second_deactivated then
                if second_dragging then
                    second_dragging = false
                else
                    second_typed = true
                end
                second_typing = false
                second_highlighted = false
            end
            if not second_currently_dragging then
                second_dragging = false
            end
            if second_typing and second_dragging then
                second_highlighted = true
                second_dragging = false
            end
            if second_currently_dragging then
                second_typing = false
            end

            --Set Millisecond State Flags
            if msecond_changed and msecond_currently_dragging and not msecond_highlighted then
                msecond_dragging = true
            end
            if msecond_changed and not msecond_currently_dragging then
                msecond_typing = true
            end
            if msecond_deactivated then
                if msecond_dragging then
                    msecond_dragging = false
                else
                    msecond_typed = true
                end
                msecond_typing = false
                msecond_highlighted = false
            end
            if not msecond_currently_dragging then
                msecond_dragging = false
            end
            if msecond_typing and msecond_dragging then
                msecond_highlighted = true
                msecond_dragging = false
            end
            if msecond_currently_dragging then
                msecond_typing = false
            end

            --Normalize Unit Values and Recompute Nudge Value depending on State (prevents continuous rollover when typing or highlighting)
            if hour_dragging then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                hour_margin = 3
            end
            if hour_typed then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                hour_margin = 3
            end
            if hour_typing then
                hour_margin = 8
            end

            if minute_dragging then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                minute_margin = 3
            end
            if minute_typed then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                minute_margin = 3
            end
            if minute_typing then
                minute_margin = 10
            end

            if second_dragging then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                second_margin = 3
            end
            if second_typed then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                second_margin = 3
            end
            if second_typing then
                second_margin = 10
            end

            if msecond_dragging then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                msecond_margin = 3
            end
            if msecond_typed then
                nudge_value = (hour_value * 60 * 60) + (minute_value * 60) + second_value + (msecond_value / 1000)
                msecond_margin = 3
            end
            if msecond_typing then
                msecond_margin = 10
            end

            --Total nudge value slider
            if debug then
                _, nudge_value = ImGui.DragDouble(ctx, "##minsec_slider", nudge_value, 1, 0, math.huge, "%.3f")
            end

            --Resync values from Nudge Value
            nudge_value_integer = math.modf(nudge_value)
            msecond_value = math.floor((nudge_value * 1000) % 1000)
            second_value = nudge_value_integer % 60
            minute_value = math.floor(nudge_value_integer / 60) - 60 * (math.floor(nudge_value_integer / 3600))
            hour_value = math.floor(nudge_value_integer / 3600)
        elseif nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
            -- Set other modes to inactive
            minutes_seconds_activated = false
            tc_activated = false

            bar_value, beat_value, sub_beat_value = nudge_value:match("([^%.]+)%.([^%.]+)%.([^%.]+)")

            --Minimums
            local bar_min = 0
            local beat_min = 0
            local sub_beat_min = 0

            --Initialize Unit Widths
            if not sub_beat_width then
                sub_beat_width = ImGui.CalcTextSize(ctx, string.format("%d", sub_beat_value))
            end
            if not beat_width then
                beat_width = ImGui.CalcTextSize(ctx, string.format("%d", beat_value))
            end
            if not bar_width then
                bar_width = ImGui.CalcTextSize(ctx, string.format("%d", bar_value))
            end

            --Bar Slider
            ImGui.SetNextItemWidth(ctx, bar_width + bar_margin)
            bar_changed, bar_value = ImGui.DragInt(ctx, "##barslider", bar_value, .1, bar_min, bar_max, "%d", ImGui.SliderFlags_AlwaysClamp)
            bar_width = ImGui.CalcTextSize(ctx, string.format("%d", bar_value))
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ".")

            --Beat Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, beat_width + beat_margin)
            beat_changed, beat_value = ImGui.DragInt(ctx, "##beatslider", beat_value, .1, beat_min, beat_max, "%d", ImGui.SliderFlags_AlwaysClamp)
            beat_width = ImGui.CalcTextSize(ctx, string.format("%d", beat_value))
            ImGui.SameLine(ctx, 0, 0)
            ImGui.Text(ctx, ".")

            --Subbeat Slider
            ImGui.SameLine(ctx, 0, 0)
            ImGui.SetNextItemWidth(ctx, sub_beat_width + sub_beat_margin)
            sub_beat_changed, sub_beat_value = ImGui.DragInt(ctx, "##sub_beatslider", sub_beat_value, .1, sub_beat_min, sub_beat_max, "%02d", ImGui.SliderFlags_AlwaysClamp)
            sub_beat_width = ImGui.CalcTextSize(ctx, string.format("%02d", sub_beat_value))

            --Set Nudge Value String
            nudge_value = tostring(bar_value .. "." .. beat_value .. "." .. string.format("%02d", sub_beat_value))

            --Total Nudge Value Display
            if debug then
                ImGui.Text(ctx, nudge_value)
            end
        else
            minutes_seconds_activated = false
            tc_activated = false
            local speed = nudge_units[selected_nudge_unit].speed
            local nudge_min = nudge_units[selected_nudge_unit].min
            local string_format = nudge_units[selected_nudge_unit].format
            local unit_label = nudge_units[selected_nudge_unit].unit
            local slider_flags = ImGui.SliderFlags_NoRoundToFormat
            local slider_width = ImGui.CalcTextSize(ctx, string.format(string_format, nudge_value)) + 3
            ImGui.SetNextItemWidth(ctx, slider_width)
            _, nudge_value = ImGui.DragDouble(ctx, "##nudge_value", nudge_value, speed, nudge_min, math.huge, string_format, slider_flags)
            ImGui.SameLine(ctx, 0, 3)
            if nudge_units[selected_nudge_unit].is_note and nudge_units[selected_nudge_unit].unit ~= "¹⁄₂₅₆Note" then
                --ImGui.AlignTextToFramePadding(ctx)
                ImGui.PushFont(ctx, nil, main_font_size + 2)
            elseif nudge_value ~= 1 then
                unit_label = unit_label .. "s"
            end
            if nudge_units[selected_nudge_unit].unit == "¹⁄₂₅₆Note" then
                unit_label = "   " .. unit_label
            end

            ImGui.Text(ctx, unit_label)
            if nudge_units[selected_nudge_unit].is_note and nudge_units[selected_nudge_unit].unit ~= "¹⁄₂₅₆Note" then
                ImGui.PopFont(ctx)
            end
        end

        ImGui.PopStyleColor(ctx, color_count)
        ImGui.PopStyleVar(ctx, style_count)
        ImGui.PopFont(ctx)

        FollowReaper()
        ImGui.End(ctx)
    end
     if show_settings then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, menu_font_color)
        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, menu_bg_color)
        if menu_font_bold then
            ImGui.PushFont(ctx, bold_fonts[menu_font], menu_font_size)
        else
            ImGui.PushFont(ctx, fonts[menu_font], menu_font_size)
        end
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, menu_padding_x, menu_padding_y)
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, menu_rounding)
        local style_count = 2
        local color_count = 2

        local settings_visible, settings_open = ImGui.Begin(ctx, "Settings##window", true, settings_window_flags)

        if settings_visible then
            ImGui.SeparatorText(ctx, "Main##main_separator")
            local width = ImGui.CalcTextSize(ctx, font_names[longest_font_name]) + 50
            ImGui.SetNextItemWidth(ctx, width)
            if ImGui.BeginCombo(ctx, "Font##fontcombo", font_names[main_font], font_combo_flags) then
                for i = 1, #fonts do
                    ImGui.PushFont(ctx, fonts[i], menu_font_size)
                    local selected = false
                    if main_font == i then
                        selected = true
                    end
                    if ImGui.Selectable(ctx, font_names[i] .. "##fontselectable" .. tostring(i), selected) then
                        main_font = i
                    end

                    ImGui.PopFont(ctx)
                end
                ImGui.EndCombo(ctx)
            end
            _, main_font_bold = ImGui.Checkbox(ctx, "Bold##mainfontbold",main_font_bold)
            local menu_font_size_width = ImGui.CalcTextSize(ctx, "24") + 5
            ImGui.SetNextItemWidth(ctx, menu_font_size_width)
            _, main_font_size = ImGui.DragInt(ctx, "Font Size", main_font_size, 1, 8, 72, nil, ImGui.SliderFlags_AlwaysClamp)
            _, main_font_color = ImGui.ColorEdit4(ctx, "Font Color", main_font_color, font_color_flags)
            _, bg_color = ImGui.ColorEdit4(ctx, "BG Color", bg_color, bg_color_flags)
            _, rounding = ImGui.SliderInt(ctx, "Rounding", rounding, 0, 100)
            _, padding_x, padding_y = ImGui.SliderInt2(ctx, "Window Padding", padding_x, padding_y, 0, 50)
            ImGui.SeparatorText(ctx, "Menu##menu_separator")
            ImGui.SetNextItemWidth(ctx, width)
            if ImGui.BeginCombo(ctx, "Font##menufontcombo", font_names[menu_font], font_combo_flags) then
                for i = 1, #fonts do
                    ImGui.PushFont(ctx, fonts[i], menu_font_size)
                    local selected = false
                    if menu_font == i then
                        selected = true
                    end
                    if ImGui.Selectable(ctx, font_names[i] .. "##menufontselectable" .. tostring(i), selected) then
                        menu_font = i
                    end

                    ImGui.PopFont(ctx)
                end
                ImGui.EndCombo(ctx)
            end
            _, menu_font_bold = ImGui.Checkbox(ctx, "Bold##menufontbold",menu_font_bold)
            ImGui.SetNextItemWidth(ctx, menu_font_size_width)
            _, menu_font_size = ImGui.DragInt(ctx, "Font Size##menufontsize", menu_font_size, 1, 8, 72, nil, ImGui.SliderFlags_AlwaysClamp)
            _, menu_font_color = ImGui.ColorEdit4(ctx, "Font Color##menufontcolor", menu_font_color, font_color_flags)
            _, menu_bg_color = ImGui.ColorEdit4(ctx, "BG Color##menubgcolor", menu_bg_color, bg_color_flags)
            _, menu_rounding = ImGui.SliderInt(ctx, "Rounding##menurounding", menu_rounding, 0, 100)
            _, menu_padding_x, menu_padding_y = ImGui.SliderInt2(ctx, "Window Padding##menupadding", menu_padding_x, menu_padding_y, 0, 50)
        end
        ImGui.PopFont(ctx)
        ImGui.PopStyleVar(ctx, style_count)
        ImGui.PopStyleColor(ctx, color_count)
        ImGui.End(ctx)

        if not settings_open then
            show_settings = false
        end
    end
    if nudge_units[selected_nudge_unit].unit == "Measures.Beat" then
        reaper.SetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value", nudge_value, true)
        reaper.SetExtState("RGS_Nudge", "nudge_value", nudge_value, true)
    else
        reaper.SetExtState("RGS_Nudge", "unit_" .. tostring(selected_nudge_unit) .. "_nudge_value", string.format("%.17f", nudge_value), true)
        reaper.SetExtState("RGS_Nudge", "nudge_value", string.format("%.17f", nudge_value), true)
    end
    reaper.SetExtState("RGS_Nudge", "nudge_unit_number", nudge_units[selected_nudge_unit].unit_number, true)
    if open then
        reaper.defer(loop)
    end
end
if debug then 
    profiler.attachToWorld() -- after all functions have been defined
    profiler.run()
end


reaper.set_action_options(1 | 4)
kb_ini = ReadFile(reaper.GetResourcePath() .. "/reaper-kb.ini")
shortcut_cache_checksum = Checksum(kb_ini)
reaper.defer(loop)
reaper.atexit(exit)
