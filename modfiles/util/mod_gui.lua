local mod_gui = require("mod-gui")

local _mod_gui = {}

-- Destroys the toggle-main-dialog-button if present
---@param player LuaPlayer
function _mod_gui.destroy(player)
    local button_flow = mod_gui.get_button_flow(player)
    local mod_gui_button = button_flow["fp_button_toggle_interface"]

    if mod_gui_button then
        -- parent.parent is to check that I'm not deleting a top level element. Now, I have no idea how that
        -- could ever be a top level element, but oh well, can't know everything now can we?
        if #button_flow.children_names == 1 and button_flow.parent.parent then
            -- Remove whole frame if FP is the last button in there
            button_flow.parent.destroy()
        else
            mod_gui_button.destroy()
        end
    end
end

-- Toggles the visibility of the toggle-main-dialog-button
---@param player LuaPlayer
function _mod_gui.toggle(player)
    local enable = util.globals.settings(player).show_gui_button

    local frame_flow = mod_gui.get_button_flow(player)
    local mod_gui_button = frame_flow["fp_button_toggle_interface"]

    if enable and not mod_gui_button then
        frame_flow.add{type="button", name="fp_button_toggle_interface", caption={"fp.toggle_interface"},
            tooltip={"fp.toggle_interface_tt"}, tags={mod="fp", on_gui_click="mod_gui_toggle_interface"},
            style=mod_gui.button_style, mouse_button_filter={"left"}}
    elseif mod_gui_button then  -- use the destroy function for possible cleanup reasons
        util.mod_gui.destroy(player)
    end
end

return _mod_gui
