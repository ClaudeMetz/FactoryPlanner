require("ui.dialogs.modal_dialog")
require("ui.event_handler")
require("ui.ui_util")

main_dialog = {}

-- ** LOCAL UTIL **
-- No idea how to write this so it works when in selection mode
local function handle_other_gui_opening(player)
    local frame_main_dialog = data_util.get("main_elements", player).main_frame
    if frame_main_dialog and frame_main_dialog.visible then
        frame_main_dialog.visible = false
        main_dialog.set_pause_state(player, frame_main_dialog)
    end
end

local function toggle_main_dialog(player)
    local ui_state = data_util.get("ui_state", player)

    if ui_state.modal_dialog_type == nil then  -- don't toggle if modal dialog is open
        local frame_main_dialog = ui_state.main_elements.main_frame
        if frame_main_dialog ~= nil then frame_main_dialog.visible = not frame_main_dialog.visible end
        --frame_main_dialog = main_dialog.refresh(player)

        player.opened = (frame_main_dialog.visible) and frame_main_dialog or nil
        main_dialog.set_pause_state(player, frame_main_dialog)
    end
end


-- ** TOP LEVEL **
main_dialog.gui_events = {
    on_gui_closed = {
        {
            name = "fp_frame_main_dialog",
            handler = (function(player, _)
                toggle_main_dialog(player)
            end)
        }
    },
    on_gui_click = {
        {
            name = "fp_button_toggle_interface",
            handler = (function(player, _, _)
                toggle_main_dialog(player)
            end)
        }
    }
}

main_dialog.misc_events = {
    on_gui_opened = (function(player, _)
        handle_other_gui_opening(player)
    end),

    on_player_display_resolution_changed = (function(player, _)
        main_dialog.rebuild(player)
    end),

    on_player_display_scale_changed = (function(player, _)
        main_dialog.rebuild(player)
    end),

    on_lua_shortcut = (function(player, event)
        if event.prototype_name == "fp_open_interface" then
            toggle_main_dialog(player)
        end
    end),

    fp_toggle_main_dialog = (function(player, _)
        toggle_main_dialog(player)
    end)
}


function main_dialog.rebuild(player)

end

function main_dialog.refresh(player, element_list)

end


-- Returns true when the main dialog is open while no modal dialogs are
function main_dialog.is_in_focus(player)
    local frame_main_dialog = data_util.get("main_elements", player).main_frame
    return (frame_main_dialog ~= nil and frame_main_dialog.visible
      and get_ui_state(player).modal_dialog_type == nil)
end

-- Sets the game.paused-state as is appropriate
function main_dialog.set_pause_state(player, frame_main_dialog, force_false)
    if not game.is_multiplayer() and player.controller_type ~= defines.controllers.editor then
        if get_preferences(player).pause_on_interface and not force_false then
            game.tick_paused = frame_main_dialog.visible  -- only pause when the main dialog is open
        else
            game.tick_paused = false
        end
    end
end