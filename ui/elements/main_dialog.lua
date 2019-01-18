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
        local p1 = add_subfactory_product(id, "electronic-circuit", 400)
        change_product_amount_produced(id, p1, 600)
        local p2 = add_subfactory_product(id, "advanced-circuit", 200)
        change_product_amount_produced(id, p2, 200)
        local p3 = add_subfactory_product(id, "processing-unit", 100)
        change_product_amount_produced(id, p3, 60)
        local p4 = add_subfactory_product(id, "rocket-control-unit", 40)
        change_product_amount_produced(id, p4, 0)

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


-- Constructs the main dialog
function create_main_dialog(player)
    local main_dialog = player.gui.center.add{type="frame", name="main_dialog", direction="vertical"}
    main_dialog.style.width = global["main_dialog_dimensions"].width
    main_dialog.style.right_padding = 6

    add_titlebar_to(main_dialog)
    add_actionbar_to(main_dialog)
    add_subfactory_bar_to(main_dialog, player)
    add_recipe_pane_to(main_dialog, player)
    add_production_pane_to(main_dialog, player)
end

-- Refreshes all variable GUI-panes
function refresh_main_dialog(player)
    refresh_actionbar(player)
    refresh_subfactory_bar(player)
    refresh_recipe_pane(player)
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


-- Sets up environment for opening a new modal dialog
function enter_modal_dialog(player)
    toggle_main_dialog(player)
end

-- Closes the modal dialog and reopens the main environment
function exit_modal_dialog(player, refresh)
    player.gui.center["frame_modal_dialog"].destroy()
    toggle_main_dialog(player)
    if refresh then refresh_main_dialog(player) end
end