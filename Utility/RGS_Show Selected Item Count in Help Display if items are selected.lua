-- @description Show selected item count in help display if any items are selected
-- @author Robin Shore
-- @donation https://paypal.me/robingshore
-- @version 1.0.1
-- @about 
--  # Show Selected Item Count in help Display if any items are selected
--  
--  This is a  lighttweight utility meant to be left running in the background. When
--  media items are selected, it temporarily replaces the info display text below the TCP
--  with a live count of the selected items.

local function SetToggle(state)
    local _, _, sectionID, cmdID, _, _, _ = reaper.get_action_context()
    reaper.SetToggleCommandState(sectionID, cmdID, state or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
end

function Main()
  local selected_items = reaper.CountSelectedMediaItems(0)
   local s = selected_items == 1 and "" or "s"
  if selected_items > 0 then
    reaper.Help_Set(selected_items.." Media item"..s.." selected", true)
  end
    reaper.defer(Main)
end

SetToggle(1)
reaper.set_action_options(1)
Main()
reaper.atexit(SetToggle)
