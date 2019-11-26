-- Handles populating the tutorial dialog
function open_tutorial_dialog(flow_modal_dialog)
    local player = game.get_player(flow_modal_dialog.player_index)

    flow_modal_dialog.parent.caption = {"fp.tutorial"}
    flow_modal_dialog.style.maximal_width = 700
    flow_modal_dialog.style.left_padding = 8
    flow_modal_dialog.style.right_padding = 8
    flow_modal_dialog.style.bottom_padding = 12

    local table_tutorial = flow_modal_dialog.add{type="table", name="table_tutorial", column_count=1}
    table_tutorial.style.bottom_margin = 8


    -- Interactive
    local interactive_title = table_tutorial.add{type="label", name="label_interactive_title",
      caption={"fp.interactive"}}
    interactive_title.style.font = "fp-font-bold-20p"
    interactive_title.style.top_margin = 4
    
    local interactive_table = table_tutorial.add{type="table", name="table_interactive", column_count=1}
    interactive_table.style.vertical_spacing = 14
    interactive_table.style.top_margin = 8
    interactive_table.style.left_margin = 10
    interactive_table.style.bottom_margin = 16

    -- Example subfactory
    local table_example_subfactory = interactive_table.add{type="table", name="table_example_subfactory", column_count=2}
    local other_mods_active = table_size(game.active_mods) > 2

    local button_example_subfactory = table_example_subfactory.add{type="button", name="fp_button_tutorial_add_example",
      caption={"fp.create_example"}, tooltip={"fp.example_subfactory"}, mouse_button_filter={"left"}}
    button_example_subfactory.enabled = not other_mods_active

    local label_example_subfactory = table_example_subfactory.add{type="label", name="label_example_subfactory", 
      caption={"fp.example_subfactory_info"}}
    ui_util.set_label_color(label_example_subfactory, "yellow")
    label_example_subfactory.style.left_margin = 10
    label_example_subfactory.visible = other_mods_active

    -- Tutorial Mode
    local switch = ui_util.switch.add_on_off(interactive_table, "tutorial_mode", get_preferences(player).tutorial_mode, 
      {"fp.tutorial_mode"}, {"fp.tutorial_mode_tt"})


    -- Interface
    local interface_title = table_tutorial.add{type="label", name="label_interface_title", caption={"fp.interface"}}
    interface_title.style.font = "fp-font-bold-20p"
    local label_interface = table_tutorial.add{type="label", name="label_tutorial_interface", caption={"fp.interface_text"}}
    label_interface.style.single_line = false

    local fnei_label = (remote.interfaces["fnei"] ~= nil) and {"fp.interface_controls_fnei"} or ""
    local label_controls = table_tutorial.add{type="label", name="label_tutorial_controls",
      caption={"", {"fp.interface_controls"}, fnei_label}}
    label_controls.style.single_line = false
    label_controls.style.margin = {6, 0, 16, 6}


    -- Usage
    local usage_title = table_tutorial.add{type="label", name="label_usage_title", caption={"fp.usage"}}
    usage_title.style.font = "fp-font-bold-20p"
    local label_usage = table_tutorial.add{type="label", name="label_tutorial_usage", caption={"fp.usage_text"}}
    label_usage.style.single_line = false
    label_usage.style.bottom_margin = 20


    -- Pro Tips
    local protips_title = table_tutorial.add{type="label", name="label_protips_title", caption={"fp.protips"}}
    protips_title.style.font = "fp-font-bold-20p"

    local protip_names = {"shortcuts", "line_fuel", "list_ordering", "hovering", "interface_size", "settings", 
      "recursive_subfloors", "views", "priority_product", "preferences", "up_down_grading", "archive", "machine_limits"}
    for _, name in ipairs(protip_names) do
        local label = table_tutorial.add{type="label", name="label_tutorial_" .. name, 
          caption={"", "- ", {"fp.pro_" .. name}}}
        label.style.single_line = false
        label.style.top_margin = 8
    end
end


-- Creates the example subfactory and shows it to the user
function handle_add_example_subfactory_click(player)
    local subfactory = constructor.example_subfactory(player)
    calculation.update(player, subfactory, false)
    exit_modal_dialog(player, "cancel", {})
end