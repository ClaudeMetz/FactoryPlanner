require("mod-gui")
require("ui.elements.actionbar")
require("ui.elements.subfactory_bar")
require("ui.elements.error_bar")
require("ui.elements.subfactory_pane")
require("ui.elements.production_titlebar")
require("ui.elements.production_table")

-- Create the always-present GUI button to open the main dialog + devmode setup
function player_gui_init(player)
    local frame_flow = mod_gui.get_button_flow(player)
    if not frame_flow["fp_button_toggle_interface"] then
        frame_flow.add
        {
            type = "button",
            name = "fp_button_toggle_interface",
            caption = "FP",
            tooltip = {"tooltip.open_main_dialog"},
            style = mod_gui.button_style,
            mouse_button_filter = {"left"}
        }
    end

    -- Incorporates the mod setting for the visibility of the toggle-main-dialog-button
    toggle_button_interface(player)
end

-- Destroys all GUI's so they are loaded anew the next time they are shown
function player_gui_reset(player)
    local screen = player.gui.screen
    local guis = {
        mod_gui.get_button_flow(player)["fp_button_toggle_interface"],
        screen["fp_frame_main_dialog"],
        unpack(cached_dialogs)
    }
    for _, gui in pairs(guis) do
        if type(gui) == "string" then gui = screen[gui] end
        if gui ~= nil and gui.valid then gui.destroy() end
    end
end


-- Toggles the visibility of the toggle-main-dialog-button
function toggle_button_interface(player)
    local enable = get_settings(player).show_gui_button
    mod_gui.get_button_flow(player)["fp_button_toggle_interface"].visible = enable
end


-- Toggles the main dialog open and closed
function toggle_main_dialog(player)
    local screen = player.gui.screen
    -- Won't toggle if a modal dialog is open
    if get_ui_state(player).modal_dialog_type == nil then
        local main_dialog = screen["fp_frame_main_dialog"]
        local open = nil

        -- Create and open main dialog, if it doesn't exist yet
        if main_dialog == nil then
            main_dialog = create_main_dialog(player, true)
            ui_util.message.refresh(player)
            open = true

        -- Otherwise, toggle it
        else
            if main_dialog.visible then
                open = false
            else
                -- Only refresh it when you make it visible
                refresh_main_dialog(player)
                open = true
            end
        end

        main_dialog.visible = open
        player.opened = open and main_dialog or nil

        -- Don't pause in multiplayer or when the setting is disabled
        if game.is_multiplayer() or not get_settings(player).pause_on_interface then game.tick_paused = false
        else game.tick_paused = open end  -- only pause when the main dialog is open
    end
end

-- Changes the main dialog in reaction to a modal dialog being opened/closed
function toggle_modal_dialog(player, frame_modal_dialog)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]

    -- If the frame parameter is not nil, the given modal dialog has been opened
    if frame_modal_dialog ~= nil then
        player.opened = frame_modal_dialog
        main_dialog.ignored_by_interaction = true
    else
        player.opened = main_dialog
        main_dialog.ignored_by_interaction = false
        refresh_main_dialog(player)
    end
end


-- Refreshes the entire main dialog, optionally including it's dimensions
function refresh_main_dialog(player, refresh_dimensions)
    local main_dialog = player.gui.screen["fp_frame_main_dialog"]
    if refresh_dimensions and main_dialog ~= nil then
        -- Recreate the dialog to refresh dimensions
        local visible = main_dialog.visible
        main_dialog.destroy()
        create_main_dialog(player, visible)
    elseif main_dialog ~= nil then
        -- Refresh the elements on top of the hierarchy, which refresh everything below them
        refresh_actionbar(player)
        refresh_subfactory_bar(player, true)
    end
end

-- Constructs the main dialog
function create_main_dialog(player, visible)
    local dimensions = ui_util.recalculate_main_dialog_dimensions(player)
    local main_dialog = player.gui.screen.add{type="frame", name="fp_frame_main_dialog", direction="vertical"}
    ui_util.properly_center_frame(player, main_dialog, dimensions.width, dimensions.height)
    main_dialog.style.minimal_width = dimensions.width
    main_dialog.style.height = dimensions.height
    main_dialog.visible = visible

    add_titlebar_to(main_dialog)
    add_actionbar_to(main_dialog)
    add_subfactory_bar_to(main_dialog)
    add_error_bar_to(main_dialog)
    add_subfactory_pane_to(main_dialog)
    add_production_pane_to(main_dialog)

    return main_dialog
end

-- Creates the titlebar including name and exit-button
function add_titlebar_to(main_dialog)
    local titlebar = main_dialog.add{type="flow", name="flow_titlebar", direction="horizontal"}
    
    -- Title
    local label_title = titlebar.add{type="label", name="label_titlebar_name", caption=" Factory Planner"}
    label_title.style.font = "fp-font-bold-26p"

    -- Hint
    local label_hint = titlebar.add{type="label", name="label_titlebar_hint"}
    label_hint.style.font = "fp-font-16p"
    label_hint.style.top_margin = 8
    label_hint.style.left_margin = 14

    -- Spacer
    local flow_spacer = titlebar.add{type="flow", name="flow_titlebar_spacer", direction="horizontal"}
    flow_spacer.style.horizontally_stretchable = true

    -- Drag handle
    local handle = titlebar.add{type="empty-widget", name="empty-widget_titlebar_space", style="draggable_space"}
    handle.style.height = 34
    handle.style.width = 180
    handle.style.top_margin = 4
    handle.drag_target = main_dialog

    -- Buttonbar
    local flow_buttonbar = titlebar.add{type="flow", name="flow_titlebar_buttonbar", direction="horizontal"}
    flow_buttonbar.style.top_margin = 4

    flow_buttonbar.add{type="button", name="fp_button_titlebar_tutorial", caption={"label.tutorial"},
      style="fp_button_titlebar", mouse_button_filter={"left"}}
    flow_buttonbar.add{type="button", name="fp_button_titlebar_preferences", caption={"label.preferences"},
      style="fp_button_titlebar", mouse_button_filter={"left"}}

    local button_exit = flow_buttonbar.add{type="button", name="fp_button_titlebar_exit", caption="X",
      style="fp_button_titlebar", mouse_button_filter={"left"}}
    button_exit.style.font = "fp-font-bold-16p"
    button_exit.style.width = 34
    button_exit.style.left_margin = 2
end