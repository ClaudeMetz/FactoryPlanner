require("mod-gui")
require("ui.util")
require("ui.listeners")
require("modal_dialog")
require("preferences_dialog")
require("ui.elements.actionbar")
require("ui.elements.subfactory_bar")
require("ui.elements.error_bar")
require("ui.elements.subfactory_pane")
require("ui.elements.production_pane")


-- Create the always-present GUI button to open the main dialog + devmode setup
function gui_init(player)
    local frame_flow = mod_gui.get_frame_flow(player)
    if not frame_flow["fp_button_toggle_interface"] then
        frame_flow.add
        {
            type = "button",
            name = "fp_button_toggle_interface",
            caption = "FP",
            tooltip = {"tooltip.open_main_dialog"},
            style = mod_gui.button_style
        }
    end

    ui_util.recalculate_main_dialog_dimensions(player)
    if global["devmode"] then run_dev_config() end
end


-- Toggles the visibility of the toggle-main-dialog-button
function toggle_button_interface(player)
    local enable = settings.get_player_settings(player)["fp_display_gui_button"].value
    mod_gui.get_frame_flow(player)["fp_button_toggle_interface"].style.visible = enable
end

-- Toggles the main dialog open and closed
function toggle_main_dialog(player)
    local center = player.gui.center
    local frame_recipe_dialog = center["fp_frame_recipe_dialog"]
    local recipe_dialog_open = (frame_recipe_dialog ~= nil and frame_recipe_dialog.style.visible)
    -- Won't toggle if a modal dialog is open
    if not center["fp_frame_modal_dialog"] and not recipe_dialog_open then
        local main_dialog = center["fp_main_dialog"]
        if main_dialog == nil then
            create_main_dialog(player)
            center["fp_main_dialog"].style.visible = true  -- Strangely isn't set right away
        else
            -- Only refresh it when you make it visible
            if not main_dialog.style.visible then refresh_main_dialog(player) end
            main_dialog.style.visible = (not main_dialog.style.visible)
        end
    end
end

-- Refreshes all variable GUI-panes (refresh-hierarchy, subfactory_bar refreshes everything below it)
function refresh_main_dialog(player)
    refresh_actionbar(player)
    refresh_subfactory_bar(player, true)
end

-- Recreates the main dialog, retaining it's visibility state
function reload_main_dialog(player)
    local main_dialog = player.gui.center["fp_main_dialog"]
    local visibility = main_dialog.style.visible
    main_dialog.destroy()
    create_main_dialog(player)
    player.gui.center["fp_main_dialog"].style.visible = visibility
end


-- Queues the caption of the general hint to be displayed on the next refresh
function queue_hint_message(player, message)
    global["queued_hint_message"] = message
end

-- Refreshes the general hint that is displayed next to the main dialog title
function refresh_hint_message(player)
    player.gui.center["fp_main_dialog"]["flow_titlebar"]["label_titlebar_hint"].caption = global["queued_hint_message"]
    global["queued_hint_message"] = ""
end


-- Constructs the main dialog
function create_main_dialog(player)
    local main_dialog = player.gui.center.add{type="frame", name="fp_main_dialog", direction="vertical"}
    main_dialog.style.minimal_width = global["main_dialog_dimensions"].width + 36
    main_dialog.style.minimal_height = global["main_dialog_dimensions"].height
    main_dialog.style.right_padding = 6

    add_titlebar_to(main_dialog)
    add_actionbar_to(main_dialog, player)
    add_subfactory_bar_to(main_dialog, player)
    add_error_bar_to(main_dialog, player)
    add_subfactory_pane_to(main_dialog, player)
    add_production_pane_to(main_dialog, player)
end


-- Creates the titlebar including name and exit-button
function add_titlebar_to(main_dialog)
    local titlebar = main_dialog.add{type="flow", name="flow_titlebar", direction="horizontal"}
    titlebar.style.vertical_align = "center"
    
    titlebar.add{type="label", name="label_titlebar_name", caption=" Factory Planner"}
    titlebar["label_titlebar_name"].style.font = "fp-font-bold-26p"
    titlebar["label_titlebar_name"].style.top_padding = 0

    local label_hint = titlebar.add{type="label", name="label_titlebar_hint", caption=global["queued_hint_message"]}
    label_hint.style.font = "fp-font-16p"
    label_hint.style.top_padding = 4
    label_hint.style.left_padding = 14
    ui_util.set_label_color(label_hint, "red")

    titlebar.add{type="flow", name="flow_titlebar_spacing", direction="horizontal"}
    titlebar["flow_titlebar_spacing"].style.horizontally_stretchable = true

    titlebar.add{type="button", name="fp_button_titlebar_preferences", caption={"label.preferences"}, style="fp_button_exit"}

    local button_exit = titlebar.add{type="button", name="fp_button_titlebar_exit", caption="X", style="fp_button_exit"}
    button_exit.style.width = 30
    button_exit.style.left_padding = 6
end