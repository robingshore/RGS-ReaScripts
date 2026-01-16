--@ noindex
local ScriptName = "Back and Play Settings"
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
if not reaper.ImGui_GetBuiltinPath then
    no_imgui = true
else    
    local _,_,imgui_version = reaper.ImGui_GetVersion()
    if not TestVersion(imgui_version,{0,9,2}) then
        no_imgui = true
    end
end

if no_imgui then
     reaper.MB("ReaImGui (version 0.9.2 or higher) is required to run this script.\n\n Please install the missing extension\nand run the script again",ScriptName, 0)
    if reaper.ReaPack_BrowsePackages then
        reaper.ReaPack_BrowsePackages("ReaImGui: ReaScript binding for Dear ImGui")
    end
    return
end

package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9.2'
local ctx = ImGui.CreateContext('Back and play settings##context')
local font = ImGui.CreateFont('sans-serif', 12)
local title_font = ImGui.CreateFont('sans-serif', 12, ImGui.FontFlags_Bold)
local focus = true
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, title_font)

local show_debug_messages = true
local function Msg(param)
    if show_debug_messages then reaper.ShowConsoleMsg(tostring(param).."\n") end
end

local function ToBoolean(str)
    local bool = false
    if str == "true" or str == true then
        bool = true
    end
    return bool
end





local back_amount = 2
local reset_cursor = true
local extstate_section = "RGS Back and Play"
local extstate_key = "Back Amount"
local extstate_key2 = "Reset cursor"

if reaper.HasExtState(extstate_section,extstate_key) then
    back_amount = tonumber(reaper.GetExtState(extstate_section, extstate_key))
end

if reaper.HasExtState(extstate_section,extstate_key2) then
    reset_cursor = ToBoolean(reaper.GetExtState(extstate_section, extstate_key2))
end

local slider_flags = ImGui.SliderFlags_AlwaysClamp
local window_flags = ImGui.WindowFlags_NoCollapse | ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoScrollbar| ImGui.WindowFlags_AlwaysAutoResize

local function loop()
    
    

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding,  5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)

    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg,                  0x202020FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border,                    0x6E6E8080)
    ImGui.PushStyleColor(ctx, ImGui.Col_BorderShadow,              0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg,                   0x333333FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive,             0x3E3E3EFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrab,             0x696969FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabHovered,      0x696969FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ScrollbarGrabActive,       0x828282FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark,                 0xFFFFFFFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,                   0x8989898A)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered,            0x8989898A)
    
   

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowTitleAlign, 0.5, 0.5)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding,     4, 6)


    ImGui.PushFont(ctx,title_font)

    if focus then
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xE6E6E6FF)
    else
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0x808080FF)
    end

    
    local visible, open = ImGui.Begin(ctx, 'Back and Play Settings##window', true,window_flags)

    

    if ImGui.IsWindowFocused(ctx) then
        focus = true
    else
        focus = false
    end
    
    
    ImGui.PopFont(ctx)
    ImGui.PushFont(ctx,font)

    
  if visible then

    ImGui.PopStyleColor(ctx,1)
    ImGui.PopStyleVar(ctx, 2)
    
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding,   6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding,   3)    --ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameBorderSize, 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding,    4)


    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding,   1)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,        0x3030308A)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x3030308A)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive,  0x3030308A)

    


    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, "Back Amount:")
    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 40)
    back_amount_slider, back_amount = ImGui.DragDouble(ctx, "Seconds##back_amount_slider", back_amount, .01,  .01, 60,"%.2f", slider_flags)
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopStyleColor(ctx, 3)
    ImGui.Spacing(ctx)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding,     4, 1)
    reset_check_box, reset_cursor = ImGui.Checkbox(ctx,"##Reset Edit Cursor",reset_cursor)
    ImGui.SameLine(ctx)
    ImGui.Text(ctx, "Reset Edit Cursor")
    ImGui.PopStyleVar(ctx, 1)
    
    
    if back_amount_slider then reaper.SetExtState(extstate_section,extstate_key, tostring(back_amount),true) end
    if reset_check_box then reaper.SetExtState(extstate_section,extstate_key2, tostring(reset_cursor),true) end
    
    
    
    ImGui.PopStyleVar(ctx, 5)
    ImGui.PopStyleColor(ctx, 11)
    ImGui.PopFont(ctx)
    ImGui.End(ctx)
  end 
  if open then
    reaper.defer(loop)
  end
end

reaper.defer(loop)
reaper.set_action_options(1)














