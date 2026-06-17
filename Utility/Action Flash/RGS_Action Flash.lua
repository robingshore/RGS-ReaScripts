-- @description Action Flash
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0.0
-- @provides
--    [main] *.lua
--    Icons.otf
-- @about 
--  # Action Flash
--
--  **Action Flash** is a keystroke visualizer for Reaper. When Action Dlash is
--  active, anytime an action is triggered by keystroke in reaper, a small popup
--  window showing the keyboard shortcut and the action name will temporarily
--  flash on screen.
-- @changelog
--  - Initial Release


--------------------------Debug & Testing -----------------------------------
local function Msg(param)
  reaper.ShowConsoleMsg(tostring(param).."\n")
end

-----------------------------------------------------------------
local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
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

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.10.0.5'
local script_name = "Action Flash"
local _, script_path, _, action_viewer_command_id = reaper.get_action_context()
local script_dir  = script_path:match("^(.*[/\\])")

local ctx = ImGui.CreateContext(script_name)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_KeyRepeatDelay, .5)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_KeyRepeatRate, .1)

local focus_window = reaper.JS_Window_GetFocus()
local parent_window = reaper.JS_Window_GetParent(focus_window)
local foreground_window = reaper.JS_Window_GetForeground() 
local is_macos = reaper.GetOS():match('OS')

local full_screen = true
local maximized = false
local skip_frames = 0



local shortcut_cache = {}
local shortcut_cache_checksum
local kb_ini
local main_passthrough

local shortcut_queue = {}
local toggle_states = {}
toggle_states[-1] = nil
toggle_states[0] = reaper.LocalizeString("off", "actionlist")
toggle_states[1] = reaper.LocalizeString("on", "actionlist")

local cast_command_id = reaper.NamedCommandLookup("_RSd5f7807c9bf40d03d812cad2fb8e455cc78ac2a0")
local cast = true
local show_shortcut = true
local show_action = true
local show_toggle = true
local show_categories = true
local show_custom = true
local show_script = true
local fade_duration = 1
local hold_time = 1
local shortcut_font_size = 24
local action_font_size = 18
local toggle_font_size = 18
local bg_color = 0x0F0F0FAA
local text_color = -1
local window_width_slider = 1000
local reaper_viewport = ImGui.GetMainViewport(ctx)
local initial_x, initial_y = ImGui.Viewport_GetWorkCenter(reaper_viewport)
local center_x
local show_tooltip = false

local black = 0x000000FF
local grey = 0x808080FF
local tooltip_bg = 0xFFFFCAFF

local ext_state_section = "RGS Action Flash"

if reaper.HasExtState(ext_state_section, "cast") then
    cast = ToBoolean(reaper.GetExtState(ext_state_section, "cast"))
    show_shortcut = ToBoolean(reaper.GetExtState(ext_state_section, "show_shortcut"))
    show_action = ToBoolean(reaper.GetExtState(ext_state_section, "show_action"))
    show_toggle = ToBoolean(reaper.GetExtState(ext_state_section, "show_toggle"))
    show_categories = ToBoolean(reaper.GetExtState(ext_state_section, "show_categories"))
    show_custom = ToBoolean(reaper.GetExtState(ext_state_section, "show_custom"))
    show_script = ToBoolean(reaper.GetExtState(ext_state_section, "show_script"))
    fade_duration = tonumber(reaper.GetExtState(ext_state_section, "fade_duration"))
    hold_time = tonumber(reaper.GetExtState(ext_state_section, "hold_time"))
    shortcut_font_size = tonumber(reaper.GetExtState(ext_state_section, "shortcut_font_size"))
    action_font_size = tonumber(reaper.GetExtState(ext_state_section, "action_font_size"))
    toggle_font_size = tonumber(reaper.GetExtState(ext_state_section, "toggle_font_size"))
    bg_color = tonumber(reaper.GetExtState(ext_state_section, "bg_color"))
    text_color = tonumber(reaper.GetExtState(ext_state_section, "text_color"))
    window_width_slider = tonumber(reaper.GetExtState(ext_state_section, "window_width_slider"))
    initial_x = tonumber(reaper.GetExtState(ext_state_section, "initial_x"))
    initial_y = tonumber(reaper.GetExtState(ext_state_section, "initial_y"))
    center_x = tonumber(reaper.GetExtState(ext_state_section, "center_x"))
    show_tooltip = ToBoolean(reaper.GetExtState(ext_state_section, "show_tooltip"))
end

if cast then
    reaper.SetToggleCommandState(0, cast_command_id, 1)
else
    reaper.SetToggleCommandState(0, cast_command_id, 0)
end
reaper.RefreshToolbar2(0, cast_command_id)

local bg_color_r, bg_color_g, bg_color_b, bg_color_a = ImGui.ColorConvertU32ToDouble4(bg_color)
local hold_color_alpha_delta = 60/255
local hold_color = ImGui.ColorConvertDouble4ToU32(bg_color_r, bg_color_g, bg_color_b, math.min(bg_color_a + hold_color_alpha_delta, 1))
local bg_color_changed

local max_window_width = 1255
local min_window_width = 125
local border_color = 0xFA0F1FFF
local button_color = 0xFA424266
local button_color_hovered = 0xFA4242FF
local button_color_active = 0XFA0F1FFF
local menu_color_active = 0xFF5555FF

local fade_duration_changed = false
local frame_length = .03
local fade_step =  (frame_length)/fade_duration
local pause_fade = false
local shortcut_held = false

local shortcut_window_prefix = "Shortcut Window"
local custom_prefix = reaper.LocalizeString("Custom", "actions")
local script_prefix = reaper.LocalizeString("Script", "actions")

local item_spacing_x, item_spacing_y = ImGui.GetStyleVar(ctx, ImGui.StyleVar_ItemSpacing)
local window_flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoDocking| ImGui.WindowFlags_MenuBar| ImGui.WindowFlags_NoTitleBar
local settings_window_flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoDocking
local shortcut_window_flags = ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoTitleBar| ImGui.WindowFlags_NoResize
local color_edit_flags = ImGui.ColorEditFlags_NoInputs | ImGui.ColorEditFlags_AlphaBar
local bold_font = ImGui.CreateFont("Sans-serif", ImGui.FontFlags_Bold)
local icon_font = ImGui.CreateFontFromFile(script_dir.."Icons.otf",0)
ImGui.Attach(ctx, bold_font)
ImGui.Attach(ctx, icon_font)
local window_spacing = 5
local rounding = 18
local x_padding = 14
local y_padding = 8
local cast_button_width = ImGui.CalcTextSize(ctx, "Start") + ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)*2



local font_size_width = 20
local slider_width = 115

local pos_x = 0
local pos_y = 0

local show_settings_window = false
local settings_window_focused = false
local main_window_focused = true




local debug ={ 
    x_padding = x_padding,
    y_padding = y_padding,
    item_spacing_x = item_spacing_x
}
--------------------Functions-------------------------
local function Checksum(string)
    local sum = 0
    for i = 1, #string do 
        sum = (sum +string.byte(string,i) % 2^32)
    end
    return sum
end

local function ReadFile(path)
    local file = io.open(path, "r")
    if not file then return "" end
    local content = file:read("a")
    file:close()
    return content
end

local function GetLastFocusedWindow()
    local section_name = "Main Window"
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
            section_name = "Media Explorer"
            section_id = 32063
            return foreground_window, section_name, section_id
        end
    end

    if reaper.JS_Window_GetTitle(foreground_window):sub(1, #reaper.LocalizeString("Crossfade Editor", "common")) == reaper.LocalizeString("Crossfade Editor", "common")  then
        if reaper.GetToggleCommandState(41827) == 1 then
            section_name = "Crossfade Editor"
            section_id = 32065
            return foreground_window, section_name, section_id
        end
    end

    local midi_window_count, midi_window_list = reaper.JS_MIDIEditor_ListAll()
    if midi_window_count > 0 then
        for window in string.gmatch(midi_window_list,"([^,]+)") do
            if reaper.JS_Window_HandleFromAddress(tonumber(window)) == foreground_window then
                if reaper.MIDIEditor_GetMode(foreground_window) == 0 then
                    section_name = "MIDI Editor"
                    section_id = 32060
                elseif reaper.MIDIEditor_GetMode(foreground_window) == 1 then
                    section_name = "MIDI Event List"
                    section_id = 32061
                end
                return foreground_window, section_name,section_id
            end
        end
    end

    if reaper.JS_Window_GetTitle(parent_window) == reaper.LocalizeString("Media Explorer", "common") then
        if reaper.GetToggleCommandState(50124) == 1 then
            section_name = "Media Explorer"
            section_id = 32063
            return parent_window, section_name, section_id
        end
    end

    if reaper.JS_Window_GetTitle(parent_window):sub(1, #reaper.LocalizeString("Crossfade Editor", "common")) == reaper.LocalizeString("Crossfade Editor", "common") then
        if reaper.GetToggleCommandState(41827) == 1 then
            section_name = "Crossfade Editor"
            section_id = 32065
            return parent_window, section_name, section_id
        end
    end
        
    if midi_window_count > 0 then
        for window in string.gmatch(midi_window_list,"([^,]+)") do
            if reaper.JS_Window_HandleFromAddress(tonumber(window)) == parent_window then
                if reaper.MIDIEditor_GetMode(parent_window) == 0 then
                    section_name = "MIDI Editor"
                    section_id = 32060
                elseif reaper.MIDIEditor_GetMode(parent_window) == 1 then
                    section_name = "MIDI Event List"
                    section_id = 32061
                end
                return parent_window, section_name,section_id
            end
        end
    end
    if reaper.GetToggleCommandState(24852) == 1 or reaper.GetToggleCommandState(24802)== 1 then
        section_id = 100
        section_name = "Main (alt recording)"
    else
        local toggle_id = 24803
        local momentary_id = 24853
        for i = 1,16 do 
            if reaper.GetToggleCommandState(toggle_id) == 1 or reaper.GetToggleCommandState(momentary_id) == 1 then
                section_id = i
                section_name = "Main (alt-"..tostring(i)..")"
                break
            end
            toggle_id = toggle_id + 1
            momentary_id = momentary_id +1
        end
    end

    return parent_window, section_name, section_id
end

local focused_window, section_name, section_id = GetLastFocusedWindow()
local section = reaper.SectionFromUniqueID(section_id)

local function BuildShortcutCache(section_id)
    local section = reaper.SectionFromUniqueID(section_id)
    local cache = {}
    local  i = 0
    while true do
        local command_id = reaper.kbd_enumerateActions(section, i)
        if command_id == 0 then break end
        local shortcut_count =reaper.CountActionShortcuts(section, command_id)
        for idx  = 0, shortcut_count do
            local ok, description = reaper.GetActionShortcutDesc(section,command_id, idx)
            if ok and description ~= "" then
                cache[description] = command_id
            end
        end
        i = i+1
    end
    shortcut_cache[section_id] = cache
end

local function PassShortcut(section_id, window)
    local Keys = {}
    local Shifted_Keys = {}
    if is_macos then
        Keys = {
            ['0'] = ImGui.Key_0,
            ['1'] = ImGui.Key_1,
            ['2'] = ImGui.Key_2,
            ['3'] = ImGui.Key_3,
            ['4'] = ImGui.Key_4,
            ['5'] = ImGui.Key_5,
            ['6'] = ImGui.Key_6,
            ['7'] = ImGui.Key_7,
            ['8'] = ImGui.Key_8,
            ['9'] = ImGui.Key_9,
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
            [reaper.LocalizeString("ESC", "kb")] = ImGui.Key_Escape,
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
            [reaper.LocalizeString("Backspace", "kb")] = ImGui.Key_Backspace,
            [","] = ImGui.Key_Comma,
            [reaper.LocalizeString("Delete", "kb")] = ImGui.Key_Delete,
            [reaper.LocalizeString("Down", "kb")] = ImGui.Key_DownArrow,
            [reaper.LocalizeString("Return", "kb")] = ImGui.Key_Enter,
            [reaper.LocalizeString("End", "kb")] = ImGui.Key_End,
            ["="] = ImGui.Key_Equal,
            ["`"] = ImGui.Key_GraveAccent,
            [reaper.LocalizeString("Home", "kb")] = ImGui.Key_Home,
            ScrollLock = ImGui.Key_ScrollLock,
            [reaper.LocalizeString("Insert", "kb")] = ImGui.Key_Insert,
            ["-"] = ImGui.Key_Minus,
            [reaper.LocalizeString("Left", "kb")] = ImGui.Key_LeftArrow,
            ["["] = ImGui.Key_LeftBracket,
            ["."] = ImGui.Key_Period,
            [reaper.LocalizeString("Page Down", "kb")] = ImGui.Key_PageDown,
            [reaper.LocalizeString("Page Up", "kb")] = ImGui.Key_PageUp,
            [reaper.LocalizeString("Pause", "kb")] = ImGui.Key_Pause,
            ["]"] = ImGui.Key_RightBracket,
            [reaper.LocalizeString("Right", "kb")] = ImGui.Key_RightArrow,
            [";"] = ImGui.Key_Semicolon,
            ["/"] = ImGui.Key_Slash,
            [reaper.LocalizeString("Space", "kb")] = ImGui.Key_Space,
            [reaper.LocalizeString("Tab","kb")] = ImGui.Key_Tab,
            [reaper.LocalizeString("Up", "kb")] = ImGui.Key_UpArrow,
            [reaper.LocalizeString("NumPad 0", "kb")] = ImGui.Key_Keypad0,
            [reaper.LocalizeString("NumPad 1", "kb")] = ImGui.Key_Keypad1,
            [reaper.LocalizeString("NumPad 2", "kb")] = ImGui.Key_Keypad2,
            [reaper.LocalizeString("NumPad 3", "kb")] = ImGui.Key_Keypad3,
            [reaper.LocalizeString("NumPad 4", "kb")] = ImGui.Key_Keypad4,
            [reaper.LocalizeString("NumPad 5", "kb")] = ImGui.Key_Keypad5,
            [reaper.LocalizeString("NumPad 6", "kb")] = ImGui.Key_Keypad6,
            [reaper.LocalizeString("NumPad 7", "kb")] = ImGui.Key_Keypad7,
            [reaper.LocalizeString("NumPad 8", "kb")] = ImGui.Key_Keypad8,
            [reaper.LocalizeString("NumPad 9", "kb")] = ImGui.Key_Keypad9,
            [reaper.LocalizeString("NumPad +", "kb")] = ImGui.Key_KeypadAdd,
            [reaper.LocalizeString("NumPad .", "kb")] = ImGui.Key_KeypadDecimal,
            [reaper.LocalizeString("NumPad /", "kb")] = ImGui.Key_KeypadDivide,
            [reaper.LocalizeString("NumPad Enter", "kb")] = ImGui.Key_KeypadEnter,
            [reaper.LocalizeString("NumPad =", "kb")] = ImGui.Key_KeypadEqual,
            [reaper.LocalizeString("NumPad *", "kb")] = ImGui.Key_KeypadMultiply,
            [reaper.LocalizeString("NumPad -", "kb")] = ImGui.Key_KeypadSubtract,
            [reaper.LocalizeString("Clear", "kb")] = ImGui.Key_NumLock,
        }
    else
        Keys = {
            ['0'] = ImGui.Key_0,
            ['1'] = ImGui.Key_1,
            ['2'] = ImGui.Key_2,
            ['3'] = ImGui.Key_3,
            ['4'] = ImGui.Key_4,
            ['5'] = ImGui.Key_5,
            ['6'] = ImGui.Key_6,
            ['7'] = ImGui.Key_7,
            ['8'] = ImGui.Key_8,
            ['9'] = ImGui.Key_9,
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
            [reaper.LocalizeString("ESC", "kb")] = ImGui.Key_Escape,
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
            [reaper.LocalizeString("Backspace", "kb")] = ImGui.Key_Backspace,
            [","] = ImGui.Key_Comma,
            [reaper.LocalizeString("Delete", "kb")] = ImGui.Key_Delete,
            [reaper.LocalizeString("Down", "kb")] = ImGui.Key_DownArrow,
            [reaper.LocalizeString("Enter", "kb")] = ImGui.Key_Enter,
            [reaper.LocalizeString("End", "kb")] = ImGui.Key_End,
            ["="] = ImGui.Key_Equal,
            ["`"] = ImGui.Key_GraveAccent,
            [reaper.LocalizeString("Home", "kb")] = ImGui.Key_Home,
            ScrollLock= ImGui.Key_ScrollLock,
            [reaper.LocalizeString("Insert", "kb")] = ImGui.Key_Insert,
            ["-"] = ImGui.Key_Minus,
            [reaper.LocalizeString("Left", "kb")]= ImGui.Key_LeftArrow,
            ["["] = ImGui.Key_LeftBracket,
            ["."] = ImGui.Key_Period,
            [reaper.LocalizeString("Page Down", "kb")] = ImGui.Key_PageDown,
            [reaper.LocalizeString("Page Up", "kb")] = ImGui.Key_PageUp,
            [reaper.LocalizeString("Pause", "kb")] = ImGui.Key_Pause,
            ["]"] = ImGui.Key_RightBracket,
            [reaper.LocalizeString("Right","kb")] = ImGui.Key_RightArrow,
            [";"] = ImGui.Key_Semicolon,
            ["/"] = ImGui.Key_Slash,
            [reaper.LocalizeString("Space","kb")] = ImGui.Key_Space,
            [reaper.LocalizeString("Tab", "kb")] = ImGui.Key_Tab,
            [reaper.LocalizeString("Up", "kb")] = ImGui.Key_UpArrow,
            ["Num 0"] = ImGui.Key_Keypad0,
            ["Num 1"] = ImGui.Key_Keypad1,
            ["Num 2"] = ImGui.Key_Keypad2,
            ["Num 3"] = ImGui.Key_Keypad3,
            ["Num 4"] = ImGui.Key_Keypad4,
            ["Num 5"] = ImGui.Key_Keypad5,
            ["Num 6"] = ImGui.Key_Keypad6,
            ["Num 7"] = ImGui.Key_Keypad7,
            ["Num 8"] = ImGui.Key_Keypad8,
            ["Num 9"] = ImGui.Key_Keypad9,
            ["Num +"] = ImGui.Key_KeypadAdd,
            ["Num ."] = ImGui.Key_KeypadDecimal,
            ["Num /"] = ImGui.Key_KeypadDivide,
            ["Num Enter"] = ImGui.Key_KeypadEnter,
            ["Num ="] = ImGui.Key_KeypadEqual,
            ["Num *"] = ImGui.Key_KeypadMultiply,
            ["Num -"] = ImGui.Key_KeypadSubtract,
            [reaper.LocalizeString("Num Lock", "kb")] = ImGui.Key_NumLock,
            [reaper.LocalizeString("Caps Lock", "kb")] = ImGui.Key_CapsLock
        }
    end
        
    Shifted_Keys = {
        ['0'] = ")",
        ['1'] = "!",
        ['2'] = "@",
        ['3'] = "#",
        ['4'] = "$",
        ['5'] = "%",
        ['6'] = "^",
        ['7'] = "&",
        ['8'] = "*",
        ['9'] = "(",
        ["'"] = "\"",
        ["\\"] = "|",
        [","] = "<",
        ["="] = "+",
        ["`"] = "~",
        ["-"] = "_",
        ["["] = "{",
        ["."] = ">",
        ["]"] = "}",
        [";"] = ":",
        ["/"] = "?",
    }

    local Mods = {
        Ctrl = ImGui.Mod_Ctrl,
        Alt = ImGui.Mod_Alt,
        Shift = ImGui.Mod_Shift,
        Super = ImGui.Mod_Super,
    }

    local Nav_Keys ={ 
        ImGui.Key_LeftArrow,
        ImGui.Key_RightArrow,
        ImGui.Key_UpArrow,
        ImGui.Key_DownArrow,
        ImGui.Key_Tab,
        ImGui.Key_Escape,
        ImGui.Key_Home,
        ImGui.Key_End,
     }

     local Focused_Nav_Keys ={ 
        ImGui.Key_Space,
        ImGui.Key_Enter,
        ImGui.Key_KeypadEnter,
        ImGui.Key_Escape,
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

    local toggle_state

    for name , code in pairs(Keys) do
        if ImGui.IsKeyDown(ctx, code) then
            key_name = name
            key_code = code
        end
    end
    
--[[     for i = 1, #Nav_Keys do
        if ImGui.IsKeyDown(ctx, Nav_Keys[i]) then
            key_name = nil
        end
    end ]]

    
--[[ 
    if ImGui.IsAnyItemFocused(ctx) then
        for i = 1, #Focused_Nav_Keys do
            if ImGui.IsKeyDown(ctx, Focused_Nav_Keys[i]) then
                key_name = nil
            end
        end
    end ]]
    
    if not key_name then return end

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
            shortcut = shortcut..reaper.LocalizeString("Cmd+", "kb")
        else 
            shortcut = shortcut..reaper.LocalizeString("Ctrl+", "kb")
        end
    end
    if alt then
        if is_macos then
            shortcut = shortcut..reaper.LocalizeString("Opt+", "kb")
        else
            shortcut = shortcut..reaper.LocalizeString("Alt+", "kb")
        end
    end
    if shift then
        for original_name , shifted_name in pairs(Shifted_Keys) do
            if key_name == original_name then
                alt_key_name = shifted_name
                alt_shortcut = shortcut
            end
        end
        shortcut = shortcut..reaper.LocalizeString("Shift+", "kb")
    end
    if super then 
        if is_macos then
            shortcut =  shortcut..reaper.LocalizeString("Control+", "kb")
            if alt_shortcut then
                alt_shortcut =  alt_shortcut..reaper.LocalizeString("Control+", "kb")
            end
        else
            shortcut =  shortcut..reaper.LocalizeString("Win+", "kb")
            if alt_shortcut then
                alt_shortcut =  alt_shortcut..reaper.LocalizeString("Win+", "kb")
            end
        end
    end
    shortcut = shortcut..key_name
    if alt_shortcut then
        alt_shortcut = alt_shortcut..alt_key_name
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
                reaper.Main_OnCommandEx(command_id,0,0)
            end
        end
        if shortcut_cache[section_id][alt_shortcut] then shortcut = alt_shortcut end
        return shortcut, command_id
    end

    section_id = 0
    if reaper.GetToggleCommandState(24852) == 1 or reaper.GetToggleCommandState(24802)== 1 then
        section_id = 100
    else
        local toggle_id = 24803
        local momentary_id = 24853
        for i = 1,16 do 
            if reaper.GetToggleCommandState(toggle_id) == 1 or reaper.GetToggleCommandState(momentary_id) == 1 then
                section_id = i
                break
            end
            toggle_id = toggle_id + 1
            momentary_id = momentary_id +1
        end
    end

    if not shortcut_cache[section_id] then
        BuildShortcutCache(section_id)
    end

    command_id = shortcut_cache[section_id][shortcut] or shortcut_cache[section_id][alt_shortcut]
    if command_id then
        if ImGui.IsKeyPressed(ctx, key_code, true) then
            reaper.Main_OnCommandEx(command_id,0,0)
        end
        if shortcut_cache[section_id][alt_shortcut] then shortcut = alt_shortcut end
        return shortcut, command_id, true
    end
    if shortcut_cache[section_id][alt_shortcut] then shortcut = alt_shortcut end
    return shortcut
end

local function GetCastShortcut()
    local section = 0
    if reaper.GetToggleCommandState(24852) == 1 or reaper.GetToggleCommandState(24802)== 1 then
        section = 100
    else
        local toggle_id = 24803
        local momentary_id = 24853
        for i = 1,16 do 
            if reaper.GetToggleCommandState(toggle_id) == 1 or reaper.GetToggleCommandState(momentary_id) == 1 then
                section = i
                break
            end
            toggle_id = toggle_id + 1
            momentary_id = momentary_id +1
        end
    end
    local ok, cast_shortcut = reaper.GetActionShortcutDesc(section, cast_command_id, 0)
    if cast_shortcut == "" then
        cast_shortcut = nil
    end
    return cast_shortcut
end

local function GetReaperWindowPos()
    local hwnd = reaper.GetMainHwnd()
    local ok, left, top, right, bottom = reaper.JS_Window_GetClientRect(hwnd)
    if not ok then return 0, 0 end
    if is_macos then
        local _, screen_top, _, screen_bottom = reaper.JS_Window_GetViewportFromRect(left, top, right, bottom, true)
        return left, screen_top - top, right, screen_top - bottom
    else
        return left, top, right, bottom
    end    
end

local reaper_x, reaper_y, reaper_right, reaper_bottom = GetReaperWindowPos()

local function exit()
    reaper.set_action_options(8)
    reaper.SetExtState(ext_state_section, "cast", tostring(cast), true)
    reaper.SetExtState(ext_state_section, "show_shortcut", tostring(show_shortcut), true)
    reaper.SetExtState(ext_state_section, "show_action", tostring(show_action), true)
    reaper.SetExtState(ext_state_section, "show_toggle", tostring(show_toggle), true)
    reaper.SetExtState(ext_state_section, "show_categories", tostring(show_categories), true)
    reaper.SetExtState(ext_state_section, "show_custom", tostring(show_custom), true)
    reaper.SetExtState(ext_state_section, "show_script", tostring(show_script), true)
    reaper.SetExtState(ext_state_section, "fade_duration", tostring(fade_duration), true)
    reaper.SetExtState(ext_state_section, "hold_time", tostring(hold_time), true)
    reaper.SetExtState(ext_state_section, "shortcut_font_size", tostring(shortcut_font_size), true)
    reaper.SetExtState(ext_state_section, "action_font_size", tostring(action_font_size), true)
    reaper.SetExtState(ext_state_section, "toggle_font_size", tostring(toggle_font_size), true)
    reaper.SetExtState(ext_state_section, "bg_color", tostring(bg_color), true)
    reaper.SetExtState(ext_state_section, "text_color", tostring(text_color), true)
    reaper.SetExtState(ext_state_section, "window_width_slider", tostring(window_width_slider), true)
    reaper.SetExtState(ext_state_section, "initial_x", tostring(initial_x), true)
    reaper.SetExtState(ext_state_section, "initial_y", tostring(initial_y), true)
    reaper.SetExtState(ext_state_section, "center_x", tostring(center_x), true)
    reaper.SetExtState(ext_state_section, "show_tooltip", tostring(show_tooltip), true)
    reaper.SetToggleCommandState(0, cast_command_id, 0)
    reaper.RefreshToolbar2(0, cast_command_id)
end


----Main Function
local function loop()
     local reaper_visible = reaper.JS_Window_IsVisible(reaper.GetMainHwnd())
    if reaper_visible and skip_frames == 0 and not ImGui.ValidatePtr(ctx,"ImGui_Context*") then
        ctx = ImGui.CreateContext(script_name)
        bold_font = ImGui.CreateFont("Sans-serif", ImGui.FontFlags_Bold)
        icon_font = ImGui.CreateFontFromFile(script_dir.."Icons.otf",0)
        ImGui.Attach(ctx, bold_font)
        ImGui.Attach(ctx, icon_font)
    end
    if reaper_visible then 
        reaper_x, reaper_y, reaper_right, reaper_bottom = GetReaperWindowPos()
    else
        reaper_x, reaper_y, reaper_right, reaper_bottom = 0, 0, 0 , 0
    end
    
    local _, reaper_w, reaper_h = reaper.JS_Window_GetClientSize(reaper.GetMainHwnd())
    local screen_left, screen_top, screen_right, screen_bottom = reaper.JS_Window_GetViewportFromRect(reaper_x, reaper_y, reaper_right, reaper_bottom, false)
    local screen_w, screen_h = math.abs(screen_left + screen_right), math.abs(screen_top - screen_bottom)

    if (reaper_w == screen_w and reaper_h == screen_h) and not full_screen then
        maximized = true
        full_screen = true
    end

    if (reaper_w ~= screen_w or reaper_h ~= screen_h) and full_screen then
        full_screen = false
    end



    if skip_frames == 0 then
        if reaper_visible then
            if reaper.HasExtState(ext_state_section, "cast") then
                cast = ToBoolean(reaper.GetExtState(ext_state_section, "cast"))
            end

            shortcut_window_flags = shortcut_window_flags & ~ ImGui.WindowFlags_AlwaysAutoResize

            if hold_time < 0.003 then
                hold_time = 0.003
            end
            local left_mouse_button = reaper.JS_Mouse_GetState(1)
            local color_count
            if cast and (show_shortcut or show_action) then 
                ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, border_color)
                ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, border_color)
                ImGui.PushStyleColor(ctx, ImGui.Col_MenuBarBg,border_color)
                ImGui.PushStyleColor(ctx, ImGui.Col_Border, border_color)
                ImGui.PushStyleColor(ctx, ImGui.Col_Button,button_color)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,button_color_active)
                ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,button_color_hovered)
                --ImGui.PushStyleColor(ctx, ImGui.Col_Header,button_color)
                --ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive,button_color_active)
                ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered,menu_color_active)
                color_count = 8
            else
                ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0)
                if main_window_focused then
                    ImGui.PushStyleColor(ctx, ImGui.Col_MenuBarBg,ImGui.GetStyleColor(ctx, ImGui.Col_TitleBgActive))
                else
                    ImGui.PushStyleColor(ctx, ImGui.Col_MenuBarBg,ImGui.GetStyleColor(ctx, ImGui.Col_TitleBg))
                end

                color_count = 2
            end

            local visible, open = ImGui.Begin(ctx, script_name, true, window_flags)
            main_window_focused = ImGui.IsWindowFocused(ctx)
            local focused_window_name = reaper.JS_Window_GetTitle(reaper.JS_Window_GetParent(reaper.JS_Window_GetFocus()))
            if focused_window_name ~= script_name and focused_window_name:sub(1, #shortcut_window_prefix) ~= shortcut_window_prefix then
                focused_window, section_name, section_id = GetLastFocusedWindow()
                section = reaper.SectionFromUniqueID(section_id)
            end

            local class_name = reaper.JS_Window_GetClassName(reaper.JS_Window_GetFocus())
                
            local imgui_hwnd = reaper.JS_Window_FindTop(script_name, true)
            if reaper.JS_Window_GetForeground() ~= imgui_hwnd and left_mouse_button == 0 and cast and (show_shortcut or show_action) and not settings_window_focused and class_name ~= "Edit" and class_name ~= "combobox" and class_name ~= "SysTreeView32" then
                reaper.JS_Window_SetFocus(imgui_hwnd)
            end
            local action
            local command_id
            local shortcut
            local toggle_state
            if not ImGui.IsAnyItemActive(ctx) then
                shortcut, command_id, main_passthrough = PassShortcut(section_id, focused_window)
            end
                
            if shortcut ~= nil and command_id ~= cast_command_id and command_id ~= action_viewer_command_id and (show_shortcut or show_action) and cast then
                if main_passthrough then
                    section = reaper.SectionFromUniqueID(0)
                    if reaper.GetToggleCommandState(24852) == 1 or reaper.GetToggleCommandState(24802)== 1 then
                        section =reaper.SectionFromUniqueID(100)
                    else
                        local toggle_id = 24803
                        local momentary_id = 24853
                        for i = 1,16 do 
                            if reaper.GetToggleCommandState(toggle_id) == 1 or reaper.GetToggleCommandState(momentary_id) == 1 then
                                section = reaper.SectionFromUniqueID(i)
                                break
                            end
                            toggle_id = toggle_id + 1
                            momentary_id = momentary_id +1
                        end
                    end
                end
                if command_id then
                    action = reaper.kbd_getTextFromCmd(command_id, section)
                    toggle_state = reaper.GetToggleCommandStateEx(section_id, command_id)
                    toggle_state = toggle_states[toggle_state]
                end
                if action then
                    local t = {
                        shortcut = shortcut,
                        action = action,
                        start_time = reaper.time_precise(),
                        start_frame = ImGui.GetFrameCount(ctx),
                        visible = false,
                        open = true,
                        draw = true,
                        pos_x = 0,
                        pos_y = 0,
                        width = 0,
                        height = 0,
                        prev_x = 0,
                        prev_y = 0,
                        prev_width = 0,
                        prev_height = 0,
                        next_x = 0,
                        next_y = 0,
                        next_width = 0,
                        next_height = 0,
                        guid = reaper.genGuid(),
                        opacity = 1,
                        fade = false,
                        toggle_state = toggle_state
                    }
                    if #shortcut_queue < 1 then
                        shortcut_held = true
                        table.insert(shortcut_queue, t)
                    elseif shortcut_queue[#shortcut_queue].shortcut ~= shortcut  or ImGui.GetFrameCount(ctx) - shortcut_queue[#shortcut_queue].start_frame > 1  then
                        shortcut_held = false    
                        table.insert(shortcut_queue, t)
                    else
                        shortcut_held = true
                        shortcut_queue[#shortcut_queue].start_time = reaper.time_precise()
                        shortcut_queue[#shortcut_queue].start_frame = ImGui.GetFrameCount(ctx)
                    end
                end
            else
                shortcut_held = false
            end
            local cast_button_string = "Start"
            if  cast then
                cast_button_string = "Stop"
            end
            local main_window_width = ImGui.GetWindowWidth(ctx)
            ImGui.SetCursorPosX(ctx, main_window_width/2 - cast_button_width/2)
            if ImGui.Button(ctx, cast_button_string, cast_button_width) then
                cast = not cast
                reaper.SetExtState(ext_state_section, "cast", tostring(cast), true)
                if cast then
                    reaper.SetToggleCommandState(0, cast_command_id, 1)
                else
                    reaper.SetToggleCommandState(0, cast_command_id, 0)
                end
                reaper.RefreshToolbar2(0, cast_command_id)
            end
            
            if show_tooltip then
                local cast_shortcut = GetCastShortcut()
                if cast_shortcut then
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 4, 2)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text, black)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Border, black)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, tooltip_bg)
                    if ImGui.BeginItemTooltip(ctx) then
                        ImGui.PushFont(ctx, nil, 10)
                        ImGui.Text(ctx, cast_shortcut)
                        ImGui.PopFont(ctx)
                        ImGui.EndTooltip(ctx)
                    end
                    ImGui.PopStyleVar(ctx, 1)
                    ImGui.PopStyleColor(ctx, 3)
                end
            end
            
            if ImGui.BeginMenuBar(ctx) then
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 3, item_spacing_y)
                ImGui.SetCursorPosX(ctx,5 )
                ImGui.Text(ctx, script_name)
                ImGui.PushFont(ctx, icon_font, 9)
                ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx) + 4)
                ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx)+ 11)
                if ImGui.MenuItem(ctx, "a##settingsbutton") then
                    show_settings_window = true
                end
                ImGui.SetCursorPosY(ctx, ImGui.GetCursorPosY(ctx)+ 4)
                if ImGui.MenuItem(ctx, "b##close button") then
                    open = false
                end
                ImGui.PopFont(ctx)
                ImGui.PopStyleVar(ctx,1)
                ImGui.EndMenuBar(ctx)
            end

                

            ImGui.SetNextFrameWantCaptureKeyboard(ctx, true)
            
            if visible then
                ImGui.End(ctx)
            end
            ImGui.PopStyleColor(ctx,color_count) --border color

            if show_settings_window then
                local settings_visible, settings_open = ImGui.Begin(ctx, script_name.." Settings##SettingsWindow", true, settings_window_flags)
                if settings_visible then
                    settings_window_focused = ImGui.IsWindowFocused(ctx, ImGui.FocusedFlags_RootAndChildWindows)
                    ImGui.SetNextItemWidth(ctx, slider_width)
                    fade_duration_changed, fade_duration = ImGui.SliderDouble(ctx, "Fade duration", fade_duration, 0, 2, "%.2f seconds")
                    if fade_duration_changed then
                        fade_step =  (frame_length)/fade_duration
                    end
                    ImGui.SameLine(ctx)
                    ImGui.TextColored(ctx, grey, "(?)")
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 4, 2)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text, black)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Border, black)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, tooltip_bg)
                    if ImGui.BeginItemTooltip(ctx) then
                        ImGui.PushFont(ctx, nil, 10)
                        ImGui.Text(ctx, "How long the popup takes to fade out")
                        ImGui.PopFont(ctx)
                        ImGui.EndTooltip(ctx)
                    end
                    ImGui.PopStyleVar(ctx, 1)
                    ImGui.PopStyleColor(ctx, 3)
                    ImGui.SetNextItemWidth(ctx, slider_width)
                    _, hold_time = ImGui.SliderDouble(ctx,"Dwell time", hold_time, 0, 2, "%.2f Seconds")
                    ImGui.SameLine(ctx)
                    ImGui.TextColored(ctx, grey, "(?)")
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 4, 2)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Text, black)
                    ImGui.PushStyleColor(ctx, ImGui.Col_Border, black)
                    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, tooltip_bg)
                    if ImGui.BeginItemTooltip(ctx) then
                        ImGui.PushFont(ctx, nil, 10)
                        ImGui.Text(ctx, "How long the popup stays fully visible before fading")
                        ImGui.PopFont(ctx)
                        ImGui.EndTooltip(ctx)
                    end
                    ImGui.PopStyleVar(ctx, 1)
                    ImGui.PopStyleColor(ctx, 3)

                    ImGui.SetNextItemWidth(ctx, slider_width)
                    _, window_width_slider = ImGui.SliderInt(ctx, "Max popup width", window_width_slider, min_window_width, max_window_width, "%d", ImGui.SliderFlags_AlwaysClamp)
                    bg_color_changed, bg_color = ImGui.ColorEdit4(ctx, "Background color",bg_color, color_edit_flags)
                    if bg_color_changed then
                        bg_color_r, bg_color_g, bg_color_b, bg_color_a = ImGui.ColorConvertU32ToDouble4(bg_color)
                        hold_color = ImGui.ColorConvertDouble4ToU32(bg_color_r, bg_color_g, bg_color_b, math.min(bg_color_a + hold_color_alpha_delta, 1))
                    end
                    _, text_color = ImGui.ColorEdit4(ctx, "Text color",text_color, color_edit_flags)
                    ImGui.SetNextItemWidth(ctx, font_size_width)
                    _, shortcut_font_size = ImGui.DragInt(ctx, "Keyboard shortcut text size##shortcufontsize", shortcut_font_size, 1, 8, 72, nil, ImGui.SliderFlags_AlwaysClamp)
                    ImGui.SetNextItemWidth(ctx, font_size_width)
                    _, action_font_size = ImGui.DragInt(ctx, "Action text size##actionfontsize", action_font_size, 1, 8, 72, nil, ImGui.SliderFlags_AlwaysClamp)
                    ImGui.SetNextItemWidth(ctx, font_size_width)
                    _, toggle_font_size = ImGui.DragInt(ctx, "Toggle text size##actionfontsize", toggle_font_size, 1, 8, 72, nil, ImGui.SliderFlags_AlwaysClamp)
                    _, show_shortcut = ImGui.Checkbox(ctx, "Show keyboard shortcut", show_shortcut)
                    _, show_action = ImGui.Checkbox(ctx, "show action", show_action)
                    ImGui.Indent(ctx)
                    ImGui.BeginDisabled(ctx, not show_action)
                    _, show_toggle = ImGui.Checkbox(ctx, "Show toggle state", show_toggle)
                    _, show_categories = ImGui.Checkbox(ctx, "Show action category", show_categories)
                    _, show_custom = ImGui.Checkbox(ctx, "Show custom action and script prefixes", show_custom)
                    _, show_script = ImGui.Checkbox(ctx, "Show script file extensions", show_script)
                    ImGui.EndDisabled(ctx)
                    ImGui.Unindent(ctx)
                    _, show_tooltip = ImGui.Checkbox(ctx, "Show start/stop keyboard shortcut as tooltip", show_tooltip)
                end
                ImGui.End(ctx)
                
                if not settings_open then
                    show_settings_window = false
                    settings_window_focused = false
                end
            end
                


            
            if #shortcut_queue > 0  then
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, rounding)
                ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, x_padding, y_padding)
                ImGui.PushStyleColor(ctx, ImGui.Col_Text, text_color)
                for i = #shortcut_queue , 1, -1 do
                    local item_count = 0
                    local shortcut_width = 0
                    local shortcut_height = 0
                    local action_width = 0
                    local action_height = 0
                    local toggle_width = 0
                    local toggle_height = 0
                    local action = shortcut_queue[i].action
                    local window_width = window_width_slider
                    local wrap_width = window_width - x_padding * 2

                    

                    if not show_categories and action:sub(1, #custom_prefix) ~= custom_prefix and action:sub(1, #script_prefix) ~= script_prefix then
                        action = action:match(": (.*)") or action
                    end
                    if not show_custom then
                        action = action:match(custom_prefix..": (.*)") or action
                        action = action:match(script_prefix..": (.*)") or action
                    end
                    if not show_script then
                        action = action:match("^(.-)%.") or action
                    end
                    
                    if show_action then
                        if show_shortcut then
                            ImGui.PushFont(ctx, nil, action_font_size)
                        else
                            ImGui.PushFont(ctx, bold_font, action_font_size)
                        end
                        action_width, action_height  = ImGui.CalcTextSize(ctx, action, nil, nil, false,  wrap_width)
                        item_count = item_count + 1
                        ImGui.PopFont(ctx)
                    end
                    if show_shortcut then
                        ImGui.PushFont(ctx, bold_font, shortcut_font_size)
                        shortcut_width, shortcut_height = ImGui.CalcTextSize(ctx, shortcut_queue[i].shortcut,nil, nil, false, wrap_width)
                        item_count = item_count + 1
                        ImGui.PopFont(ctx)
                    end
                    if show_toggle and show_action then
                        if shortcut_queue[i].toggle_state then
                            ImGui.PushFont(ctx, nil, toggle_font_size)
                            toggle_width, toggle_height = ImGui.CalcTextSize(ctx, shortcut_queue[i].toggle_state, nil, nil, false, wrap_width)
                            item_count = item_count + 1
                            ImGui.PopFont(ctx)
                        end
                    end
                    item_count = math.max(item_count, 0)
                    local widest = math.max(action_width, shortcut_width, toggle_width, wrap_width)
                    local window_height = action_height + shortcut_height + toggle_height + y_padding*2 + item_spacing_y*(item_count -1)

                    if math.max(action_width, shortcut_width, toggle_width) + x_padding*2 < window_width then
                        widest = math.max(action_width, shortcut_width, toggle_width)
                        window_width = widest + x_padding*2
                    end
                    ImGui.SetNextWindowSize(ctx, window_width, window_height)

                    

                    if i == #shortcut_queue then
                        if shortcut_queue[i].start_frame == ImGui.GetFrameCount(ctx) then
                            if not center_x then
                                ImGui.SetNextWindowPos(ctx, initial_x, initial_y)
                                center_x = initial_x + window_width/2
                            else
                                ImGui.SetNextWindowPos(ctx, center_x - window_width/2, initial_y)
                            end
                        end
                    else
                        pos_x = center_x - window_width/2
                        pos_y = shortcut_queue[i+1].pos_y - window_spacing -  window_height
                        ImGui.SetNextWindowPos(ctx, pos_x, pos_y)
                    end
                    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, shortcut_queue[i].opacity)
                    if shortcut_held and i == #shortcut_queue  then
                        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, hold_color)
                    else
                        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, bg_color)
                    end
                    shortcut_queue[i].visible, shortcut_queue[i].open = ImGui.Begin(ctx, 'Shortcut Window'.. shortcut_queue[i].guid, true, shortcut_window_flags)
                    if shortcut_queue[i].visible then
                        if i == #shortcut_queue then 
                            if ImGui.IsWindowFocused(ctx) or ImGui.IsAnyItemActive(ctx) then
                                pause_fade = true
                            else
                                pause_fade = false
                            end
                        end
                        ImGui.PushTextWrapPos(ctx, 0)
                        if show_shortcut then
                            if shortcut_width < widest then
                                ImGui.Dummy(ctx, math.floor((widest/2) - (shortcut_width/2)) - item_spacing_x ,1)
                                ImGui.SameLine(ctx)
                            end
                            ImGui.PushFont(ctx, bold_font, shortcut_font_size)
                            ImGui.Text(ctx, shortcut_queue[i].shortcut)
                            ImGui.PopFont(ctx)
                        end
                        if show_action then
                            if action_width < widest then
                                ImGui.Dummy(ctx, math.floor((widest/2) - (action_width/2)) - item_spacing_x ,1)
                                ImGui.SameLine(ctx)
                            end
                            if show_shortcut then
                                ImGui.PushFont(ctx, nil, action_font_size)
                            else
                                ImGui.PushFont(ctx, bold_font, action_font_size)
                            end
                            ImGui.Text(ctx, action)
                            ImGui.PopFont(ctx)
                        end
                        if show_toggle and show_action then 
                            if shortcut_queue[i].toggle_state then
                                if toggle_width < widest then
                                    ImGui.Dummy(ctx, math.floor((widest/2) - (toggle_width/2)) - item_spacing_x ,1)
                                    ImGui.SameLine(ctx)
                                end
                                ImGui.PushFont(ctx, nil, toggle_font_size)
                                ImGui.Text(ctx, shortcut_queue[i].toggle_state)
                                ImGui.PopFont(ctx)
                            end
                        end
                        ImGui.PopTextWrapPos(ctx)
                        pos_x, pos_y = ImGui.GetWindowPos(ctx)
                        ImGui.End(ctx)
                    end
                    ImGui.PopStyleVar(ctx, 1) -- Alpha
                    ImGui.PopStyleColor(ctx, 1) -- BG Color, 
                    if i == #shortcut_queue then
                        initial_x, initial_y = pos_x, pos_y
                        center_x = initial_x + window_width/2
                    end
                    shortcut_queue[i].pos_x = pos_x
                    shortcut_queue[i].pos_y = pos_y
                    if reaper.time_precise() -  shortcut_queue[i].start_time >= hold_time then
                        shortcut_queue[i].fade = true
                    end
                    if shortcut_queue[i].fade and not pause_fade then
                        shortcut_queue[i].opacity = math.max(shortcut_queue[i].opacity - fade_step, 0)
                    end
                    if shortcut_queue[i].opacity == 0 then
                        table.remove(shortcut_queue, i)
                    end

                end
                ImGui.PopStyleVar(ctx, 2) -- rounding, padding
                ImGui.PopStyleColor(ctx, 1) -- text color

            end
            if open then
                reaper.defer(loop)
            end
        end
    end
    if maximized and is_macos then 
        skip_frames = 30
        maximized = false
    end

    skip_frames = math.max(0, skip_frames -1)
    if skip_frames> 0 or not reaper_visible then
        reaper.defer(loop)
    end
end

---Run------
--[[ profiler.attachToWorld() -- after all functions have been defined
profiler.run() ]]
reaper.set_action_options(1|4)
kb_ini = ReadFile(reaper.GetResourcePath() .. "/reaper-kb.ini")
shortcut_cache_checksum = Checksum(kb_ini)
reaper.defer(loop)
reaper.atexit(exit)