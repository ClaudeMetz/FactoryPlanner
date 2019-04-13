-- Handles populating the tutorial dialog
function open_tutorial_dialog(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"label.tutorial"}
    flow_modal_dialog.style.maximal_width = 700
    flow_modal_dialog.style.left_padding = 8
    flow_modal_dialog.style.right_padding = 8
    flow_modal_dialog.style.bottom_padding = 12

    local table_tutorial = flow_modal_dialog.add{type="table", name="table_tutorial", column_count=1}
    table_tutorial.style.bottom_margin = 8

    -- Example subfactory
    local button_add_example = table_tutorial.add{type="button", name="fp_button_tutorial_add_example",
      caption={"button-text.create_example"}, tooltip={"tooltip.example_subfactory"}}
    button_add_example.style.left_margin = 8
    button_add_example.style.top_margin = 8
    button_add_example.style.bottom_margin = 16
    
    -- General Tips
    local interface_title = table_tutorial.add{type="label", name="label_interface_title", 
      caption={"", {"label.interface"}, ":"}}
    interface_title.style.font = "fp-font-bold-20p"
    local label_interface = table_tutorial.add{type="label", name="label_tutorial_interface", 
      caption={"tip.interface"}}
    label_interface.style.single_line = false
    label_interface.style.bottom_margin = 20

    local usage_title = table_tutorial.add{type="label", name="label_usage_title", caption={"", {"label.usage"}, ":"}}
    usage_title.style.font = "fp-font-bold-20p"
    local label_usage = table_tutorial.add{type="label", name="label_tutorial_usage", caption={"tip.usage"}}
    label_usage.style.single_line = false
    label_usage.style.bottom_margin = 20

    -- Pro Tips
    local protips_title = table_tutorial.add{type="label", name="label_protips_title", 
      caption={"", {"label.protips"}, ":"}}
    protips_title.style.font = "fp-font-bold-20p"

    local protip_names = {"hovering", "list_ordering", "machine_changing", "machine_preferences", "interface_width",
      "recursive_subfloors", "recipe_consolidation"}
    for _, name in ipairs(protip_names) do
        local label = table_tutorial.add{type="label", name="label_tutorial_" .. name, 
          caption={"", "- ", {"tip.pro_" .. name}}}
        label.style.single_line = false
        label.style.top_margin = 8
    end
end

-- No additional action needs to be taken when the tutorial dialog is closed
function close_tutorial_dialog(flow_modal_dialog, action, data)
end

-- No conditions needed for the tutorial dialog
function get_tutorial_condition_instructions()
    return {data = {}, conditions = {}}
end


-- Creates the example subfactory and shows it to the user
function handle_add_example_subfactory_click(player)
    local subfactory = data_util.add_example_subfactory(player)
    update_calculations(player, subfactory)
    exit_modal_dialog(player, "cancel", {})
end