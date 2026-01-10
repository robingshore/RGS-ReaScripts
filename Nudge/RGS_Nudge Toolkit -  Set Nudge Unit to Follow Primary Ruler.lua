-- @noindex

local debug = false
local function Msg(param)
    if debug == true then
        reaper.ShowConsoleMsg(tostring(param) .. "\n")
    end
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

local nudge_units = {}

local unit_table_minutes_seconds = {
    ruler = 0,
    unit_number = 1,
    action_id = "_RS9c354c8892928e875e71c2b5cfaed2b12eac1ff9"
}
table.insert(nudge_units, unit_table_minutes_seconds)

local unit_table_beats = {
    ruler = 2,
    unit_number = 16,
    action_id = "_RS8fe160e0a71a47c69d9443d9f3dfb2290e85c519"
}
table.insert(nudge_units, unit_table_beats)

local unit_table_seconds = {
    ruler = 3,
    unit_number = 1,
    action_id = "_RS5eeeb4f5575b1dd73d05429ba442c8ca2f2edb57"
}
table.insert(nudge_units, unit_table_seconds)

local unit_table_samples = {
    ruler = 4,
    unit_number = 17,
    action_id = "_RS0c4e114b9c7e5ab9e75a779f2374d6ae40b0b835"
}
table.insert(nudge_units, unit_table_samples)

local unit_table_timecode = {
    ruler = 5,
    unit_number = 18,
    action_id = "_RS6f4b859018b3caee45216cf9603de13f1c64393e"
}
table.insert(nudge_units, unit_table_timecode)

local unit_table_frames = {
    ruler = 8,
    unit_number = 18,
    action_id = "_RS41ee7fa6cbdae6935e4f2d124afb6ecb601b904c"
}
table.insert(nudge_units, unit_table_frames)

local unit_table_whole_notes = {
    ruler = -1,
    unit_number = 15,
    action_id = "_RSb5164b0de0d03b9e4143fa41eafe528c7d032665"
}
table.insert(nudge_units, unit_table_whole_notes)

local unit_table_half_notes = {
    ruler = -1,
    unit_number = 14,
    action_id = "_RS2e73a76e3656855b74cbbd9f6a71a1591d4dec4c"
}
table.insert(nudge_units, unit_table_half_notes)

local unit_table_quarter_notes = {
    ruler = -1,
    unit_number = 13,
    action_id = "_RS7fa5ccc3b6e6553dd7d4e0ab82d918987ae44809"
}
table.insert(nudge_units, unit_table_quarter_notes)

local unit_table_quarter_note_triplets = {
    ruler = -1,
    unit_number = 12,
    action_id = "_RSd6af6a9ee632154344de220b776287b254ab406c"
}
table.insert(nudge_units, unit_table_quarter_note_triplets)

local unit_table_eighth_notes = {
    ruler = -1,
    unit_number = 11,
    action_id = "_RSf951ec45648c65b1baad3d2e48b1618b0c4545bd"
}
table.insert(nudge_units, unit_table_eighth_notes)

local unit_table_eighth_note_triplets = {
    ruler = -1,
    unit_number = 10,
    action_id = "_RSa56f66b91b5ac7f56219f70fbba5eb7942b8f954"
}
table.insert(nudge_units, unit_table_eighth_note_triplets)

local unit_table_sixteenth_notes = {
    ruler = -1,
    is_note = true,
    action_id = "_RSee623759a51e82624b0a85f61ec1a6305d153ed7"
}
table.insert(nudge_units, unit_table_sixteenth_notes)

local unit_table_sixteenth_note_triplets = {
    ruler = -1,
    unit_number = 8,
    action_id = "_RS25ab542dfe4bf64628da31991d23297fabc2f9dd"
}
table.insert(nudge_units, unit_table_sixteenth_note_triplets)

local unit_table_thirtysecond_notes = {
    ruler = -1,
    unit_number = 7,
    action_id = "_RSed403bfba96d9aeb39105c0dd44787609b4d76f6"
}
table.insert(nudge_units, unit_table_thirtysecond_notes)

local unit_table_thirtysecond_note_triplets = {
    ruler = -1,
    unit_number = 6,
    action_id = "_RS6a6178e0ec51798a5427524ef1058ac4206c0b0b"
}
table.insert(nudge_units, unit_table_thirtysecond_note_triplets)

local unit_table_sixtyfourth_notes = {
    ruler = -1,
    unit_number = 5,
    action_id = "_RS8b1f863c4cb0b6884f6ac9afebe862ef7478790c"
}
table.insert(nudge_units, unit_table_sixtyfourth_notes)

local unit_table_hundredtwentyeighth_notes = {
    ruler = -1,
    unit_number = 4,
    action_id = "_RSdf91ccd381825e3f96794bab03165f05d2630a6c"
}
table.insert(nudge_units, unit_table_hundredtwentyeighth_notes)

local unit_table_twohundredfiftysixth_notes = {
    ruler = -1,
    unit_number = 3,
    action_id = "_RSbd82fa4c8e299b1b9b67a79d5b386704d21bbabd"
}
table.insert(nudge_units, unit_table_twohundredfiftysixth_notes)

local nudge_unit
local unit_number
local ruler_unit = GetPrimaryRulerTimeMode()

reaper.set_action_options(4)
reaper.SetExtState("RGS_Nudge", "follow_ruler", "true", true)

for i = 1, #nudge_units do
    local command_id = reaper.NamedCommandLookup(nudge_units[i].action_id)
    if nudge_units[i].ruler == ruler_unit then
        nudge_unit = i
        unit_number = nudge_units[i].unit_number
    end
    reaper.SetToggleCommandState(0, command_id, 0)
    reaper.RefreshToolbar2(0, command_id)
end

reaper.SetExtState("RGS_Nudge", "nudge_unit_number", tostring(unit_number), true)
reaper.SetExtState("RGS_Nudge", "selected_nudge_unit", tostring(nudge_unit), true)
reaper.SetExtState("RGS_Nudge", "follow_ruler", "true", true)
--reaper.SetExtState("RGS_Nudge", "ruler_switched", "true",true)

if reaper.HasExtState("RGS_Nudge", "unit_" .. tostring(nudge_unit) .. "_nudge_value") then
    local nudge_amount = tonumber(reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(nudge_unit) .. "_nudge_value"))
    reaper.SetExtState("RGS_Nudge", "nudge_value", string.format("%.17f", nudge_amount), true)
end

local string = "{"
for i = 1, #nudge_units do
    string = string.."\""..nudge_units[i].action_id.."\","

end
Msg(string)