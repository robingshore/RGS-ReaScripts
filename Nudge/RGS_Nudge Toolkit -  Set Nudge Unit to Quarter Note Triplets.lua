-- @noindex
local function Msg(param)
    reaper.ShowConsoleMsg(tostring(param) .. "\n")
end
local command_ids = {
    "_RS9c354c8892928e875e71c2b5cfaed2b12eac1ff9",
    "_RS8fe160e0a71a47c69d9443d9f3dfb2290e85c519",
    "_RS5eeeb4f5575b1dd73d05429ba442c8ca2f2edb57",
    "_RS0c4e114b9c7e5ab9e75a779f2374d6ae40b0b835",
    "_RS6f4b859018b3caee45216cf9603de13f1c64393e",
    "_RS41ee7fa6cbdae6935e4f2d124afb6ecb601b904c",
    "_RSb5164b0de0d03b9e4143fa41eafe528c7d032665",
    "_RS2e73a76e3656855b74cbbd9f6a71a1591d4dec4c",
    "_RS7fa5ccc3b6e6553dd7d4e0ab82d918987ae44809",
    "_RSd6af6a9ee632154344de220b776287b254ab406c",
    "_RSf951ec45648c65b1baad3d2e48b1618b0c4545bd",
    "_RSa56f66b91b5ac7f56219f70fbba5eb7942b8f954",
    "_RSee623759a51e82624b0a85f61ec1a6305d153ed7",
    "_RS25ab542dfe4bf64628da31991d23297fabc2f9dd",
    "_RSed403bfba96d9aeb39105c0dd44787609b4d76f6",
    "_RS6a6178e0ec51798a5427524ef1058ac4206c0b0b",
    "_RS8b1f863c4cb0b6884f6ac9afebe862ef7478790c",
    "_RSdf91ccd381825e3f96794bab03165f05d2630a6c",
    "_RSbd82fa4c8e299b1b9b67a79d5b386704d21bbabd",
    "_RS6f744f0eb06777db3feaba50bcc49bbce161348d"
}
local nudge_unit = 10
local unit_number = 12

if nudge_unit ~= tonumber(reaper.GetExtState("RGS_Nudge", "selected_nudge_unit")) then
    for i = 1, #command_ids do
        local command_id = reaper.NamedCommandLookup(command_ids[i])
        reaper.SetToggleCommandState(0, command_id, 0)
        reaper.RefreshToolbar2(0, command_id)
    end
    reaper.set_action_options(4)
    reaper.SetExtState("RGS_Nudge", "nudge_unit_number", tostring(unit_number), true)

    reaper.SetExtState("RGS_Nudge", "selected_nudge_unit", tostring(nudge_unit), true)
    reaper.SetExtState("RGS_Nudge", "follow_ruler", "false", true)

    if reaper.HasExtState("RGS_Nudge", "unit_" .. tostring(nudge_unit) .. "_nudge_value") then
        local nudge_amount =
            tonumber(reaper.GetExtState("RGS_Nudge", "unit_" .. tostring(nudge_unit) .. "_nudge_value"))
        reaper.SetExtState("RGS_Nudge", "nudge_value", string.format("%.17f", nudge_amount), true)
    end
end
