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
        local p1 = add_product(id, "electronic-circuit", 400)
        change_product_amount_produced(id, p1, 600)
        local p2 = add_product(id, "advanced-circuit", 200)
        change_product_amount_produced(id, p2, 200)
        local p3 = add_product(id, "processing-unit", 100)
        change_product_amount_produced(id, p3, 60)
        local p4 = add_product(id, "rocket-control-unit", 40)
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
            player.gui.center["main_dialog"].style.visible = true  -- Strangely isn't set right away
        else
            main_dialog.style.visible = (not main_dialog.style.visible)
        end
    end
end


-- Opens a barebone modal dialog and calls upon the given function to populate it
function enter_modal_dialog(player, type, args)
    global["modal_dialog_type"] = type
    toggle_main_dialog(player)
    local flow_modal_dialog = create_base_modal_dialog(player, args.no_submit_button)
    _G["open_" .. type .. "_dialog"](flow_modal_dialog, args)
end

-- Handles the closing process of a modal dialog, reopening the main dialog thereafter
function exit_modal_dialog(player, submission)
    local frame_modal_dialog = player.gui.center["frame_modal_dialog"]
    local type = global["modal_dialog_type"]
    if not submission then
        -- Run cleanup if necessary
        local cleanup = _G["cleanup_" .. type .. "_dialog"]
        if cleanup ~= nil then cleanup() end

        global["modal_dialog_type"] = nil
        frame_modal_dialog.destroy()
        toggle_main_dialog(player)
    else
        local flow_modal_dialog = frame_modal_dialog["flow_modal_dialog"]

        -- First checks if the entered data is correct
        local data = _G["check_" .. type .. "_data"](flow_modal_dialog)
        if data ~= nil then  -- meaning correct data has been entered
            global["modal_dialog_type"] = nil
            _G["submit_" .. type .. "_dialog"](flow_modal_dialog, data)
            frame_modal_dialog.destroy()
            toggle_main_dialog(player)
            refresh_main_dialog(player)
        end
    end
end

-- Creates barebones modal dialog
function create_base_modal_dialog(player, no_submit_button)
    local frame_modal_dialog = player.gui.center.add{type="frame", name="frame_modal_dialog", direction="vertical"}
    local flow_modal_dialog = frame_modal_dialog.add{type="flow", name="flow_modal_dialog", direction="vertical"}

    local button_bar = frame_modal_dialog.add{type="flow", name="flow_modal_dialog_button_bar", direction="horizontal"}
    button_bar.add{type="button", name="button_modal_dialog_cancel", caption={"button-text.cancel"}, 
      style="fp_button_with_spacing"}
    button_bar.add{type="flow", name="flow_modal_dialog_spacer", direction="horizontal"}
    button_bar["flow_modal_dialog_spacer"].style.width = 40
    if no_submit_button ~= true then
        button_bar.add{type="button", name="button_modal_dialog_submit", caption={"button-text.submit"}, 
          style="fp_button_with_spacing"}
    end

    return flow_modal_dialog
end