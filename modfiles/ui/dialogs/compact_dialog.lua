require("ui.elements.view_state")
require("ui.elements.compact_subfactory")

compact_dialog = {}

local frame_dimensions = {width = 0.245, height = 0.8}  -- as a percentage of the screen
local frame_location = {x = 10, y = 63}  -- absolute, relative to 1080p with scale 1

-- ** LOCAL UTIL **
-- Set frame dimensions in a relative way, taking player resolution and scaling into account
local function set_compact_frame_dimensions(player, frame)
    local resolution, scale = player.display_resolution, player.display_scale
    local actual_resolution = {width=math.ceil(resolution.width / scale), height=math.ceil(resolution.height / scale)}
    frame.style.width = actual_resolution.width * frame_dimensions.width
    frame.style.maximal_height = actual_resolution.height * frame_dimensions.height
end

local function set_compact_frame_location(player, frame)
    local scale = player.display_scale
    frame.location = {frame_location.x * scale, frame_location.y * scale}
end

local function rebuild_compact_dialog(player, default_visibility)
    local ui_state = data_util.get("ui_state", player)
    local compact_elements = ui_state.compact_elements

    local interface_visible = default_visibility
    local compact_frame = compact_elements.compact_frame
    -- Delete the existing interface if there is one
    if compact_frame ~= nil then
        if compact_frame.valid then
            interface_visible = compact_frame.visible
            compact_frame.destroy()
        end

        ui_state.compact_elements = {}  -- reset all compact element references
        compact_elements = ui_state.compact_elements
    end

    local frame_compact_dialog = player.gui.screen.add{type="frame", direction="vertical",
      visible=interface_visible, name="fp_frame_compact_dialog"}
    set_compact_frame_location(player, frame_compact_dialog)
    set_compact_frame_dimensions(player, frame_compact_dialog)
    compact_elements["compact_frame"] = frame_compact_dialog

    -- Title bar
    local flow_title_bar = frame_compact_dialog.add{type="flow", direction="horizontal",
      tags={mod="fp", on_gui_click="place_compact_dialog"}}
    flow_title_bar.style.horizontal_spacing = 8
    flow_title_bar.drag_target = frame_compact_dialog

    flow_title_bar.add{type="label", caption={"mod-name.factoryplanner"}, style="frame_title",
      ignored_by_interaction=true}
    flow_title_bar.add{type="empty-widget", style="flib_titlebar_drag_handle",
      ignored_by_interaction=true}

    local button_switch = flow_title_bar.add{type="sprite-button", style="frame_action_button",
      tags={mod="fp", on_gui_click="switch_to_main_view"}, tooltip={"fp.switch_to_main_view"},
      sprite="fp_sprite_arrow_right_light", hovered_sprite="fp_sprite_arrow_right_dark",
      clicked_sprite="fp_sprite_arrow_right_dark", mouse_button_filter={"left"}}
    button_switch.style.padding = 2

    local button_close = flow_title_bar.add{type="sprite-button", tags={mod="fp", on_gui_click="close_compact_dialog"},
      sprite="utility/close_white", hovered_sprite="utility/close_black", clicked_sprite="utility/close_black",
      tooltip={"fp.close_interface"}, style="frame_action_button", mouse_button_filter={"left"}}
    button_close.style.padding = 1

    -- Compact subfactory - handled in different file
    compact_subfactory.build(player)

    return frame_compact_dialog
end


-- ** TOP LEVEL **
function compact_dialog.toggle(player)
    local ui_state = data_util.get("ui_state", player)
    local frame_compact_dialog = ui_state.compact_elements.compact_frame
    -- Doesn't set player.opened so other GUIs like the inventory can be opened when building

    if frame_compact_dialog == nil or not frame_compact_dialog.valid then
        rebuild_compact_dialog(player, true)  -- refreshes on its own
    else
        local new_dialog_visibility = not frame_compact_dialog.visible
        frame_compact_dialog.visible = new_dialog_visibility

        if new_dialog_visibility then compact_subfactory.refresh(player) end
    end
end

function compact_dialog.is_in_focus(player)
    local frame_compact_dialog = data_util.get("compact_elements", player).compact_frame
    return (frame_compact_dialog ~= nil and frame_compact_dialog.valid and frame_compact_dialog.visible)
end


-- ** EVENTS **
compact_dialog.gui_events = {
    on_gui_click = {
        {
            name = "switch_to_main_view",
            handler = (function(player, _, _)
                data_util.get("flags", player).compact_view = false
                compact_dialog.toggle(player)

                main_dialog.toggle(player)
                main_dialog.refresh(player, "production")
            end)
        },
        {
            name = "close_compact_dialog",
            handler = (function(player, _, _)
                compact_dialog.toggle(player)
            end)
        },
        {
            name = "place_compact_dialog",
            handler = (function(player, _, event)
                if event.button == defines.mouse_button_type.middle then
                    local ui_state = data_util.get("ui_state", player)
                    local frame_compact_dialog = ui_state.compact_elements.compact_frame
                    set_compact_frame_location(player, frame_compact_dialog)
                end
            end)
        }
    }
}

compact_dialog.misc_events = {
    on_player_display_resolution_changed = (function(player, _)
        rebuild_compact_dialog(player, false)
    end),

    on_player_display_scale_changed = (function(player, _)
        rebuild_compact_dialog(player, false)
    end),

    on_lua_shortcut = (function(player, event)
        if event.prototype_name == "fp_open_interface" and data_util.get("flags", player).compact_view then
            compact_dialog.toggle(player)
        end
    end),

    fp_toggle_interface = (function(player, _)
        if data_util.get("flags", player).compact_view then compact_dialog.toggle(player) end
    end),

    fp_floor_up = (function(player, _)
        if compact_dialog.is_in_focus(player) then
            local floor_changed = ui_util.context.change_floor(player, "up")
            if floor_changed then compact_subfactory.refresh(player) end
        end
    end)
}
