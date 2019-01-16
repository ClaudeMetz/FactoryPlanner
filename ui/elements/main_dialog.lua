require("mod-gui")
require("ui.util")
require("titlebar")
require("actionbar")
require("subfactory_bar")
require("recipe_pane")
require("production_pane")


-- Create the always-present GUI button to open the main dialog
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

    -- Temporary for dev puroposes
    if global["devmode"] then
        local id = add_subfactory(nil, "iron-plate")
        global["subfactories"][id]["products"][1] = {name="iron-plate", amount_required = 120, amount_produced = 0, gui_position = 1}
        global["subfactories"][id]["products"][2] = {name="iron-plate", amount_required = 35, amount_produced = 0, gui_position = 2}

        add_subfactory("Beta", nil)
        add_subfactory("Gamma", "copper-plate")
        
        update_subfactory_order()
    end
end

-- Toggles the visibility of always-present GUI button to open the main dialog
function toggle_button_interface(player)
    local enable = settings.get_player_settings(player)["fp_display_gui_button"].value
    mod_gui.get_frame_flow(player)["fp_button_toggle_interface"].style.visible = enable
end


-- Toggles the main dialog open and closed
function toggle_main_dialog(player)
    -- Won't toggle if a modal dialog is open
    if not player.gui.center["frame_modal_dialog"] then
        local main_dialog = player.gui.center["main_dialog"]
        if main_dialog == nil then
            create_main_dialog(player)
        elseif main_dialog.style.visible == false then
            main_dialog.style.visible = true
        else
            main_dialog.style.visible = false
        end
    end
end

-- Refreshes all variable GUI-panes
function refresh_main_dialog(player)
    refresh_actionbar(player)
    refresh_subfactory_bar(player)
    refresh_recipe_pane(player)
end

-- Constructs the main dialog
function create_main_dialog(player)
    local main_dialog = player.gui.center.add{type="frame", name="main_dialog", direction="vertical"}
    main_dialog.style.width = global["main_dialog_dimensions"].width
    main_dialog.style.right_padding = 6

    add_titlebar_to(main_dialog)
    add_actionbar_to(main_dialog)
    add_subfactory_bar_to(main_dialog, player)
    add_recipe_pane_to(main_dialog, player)
end