production_table = {}

-- ** LOCAL UTIL **
local function generate_metadata(player)
    local ui_state = data_util.get("ui_state", player)
    local metadata = {
        context = ui_state.context,
        archive_open = (ui_state.flags.archive_open)
    }

    if data_util.get("preferences", player).tutorial_mode then
        metadata.recipe_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "recipe", true, true, true)
    end

    return metadata
end

-- ** BUILDERS **
local builders = {}

function builders.recipe(_, line, parent_flow, metadata)
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
    local recipe_proto = relevant_line.recipe.proto

    local style, tooltip, enabled = "flib_standalone_slot_button_default", recipe_proto.localised_name, true
    -- Make the first line of every subfloor un-interactable, it stays constant
    if metadata.context.floor.level > 1 and line.gui_position == 1 then
        style = "flib_standalone_slot_button_blue"
        enabled = false
    else
        if line.subfloor then
            tooltip = {"fp.annotated_title", tooltip, {"fp.recipe_subfloor_attached"}}
            style = "flib_standalone_slot_button_blue"
        end

        tooltip = {"fp.two_word_title", tooltip, metadata.recipe_tutorial_tooltip or ""}
    end

    parent_flow.add{type="sprite-button", name="fp_sprite-button_production_recipe_" .. line.id,
      sprite=recipe_proto.sprite, tooltip=tooltip, enabled=enabled, style=style, mouse_button_filter={"left-and-right"}}
end

function builders.percentage(_, line, parent_flow, metadata)
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)

    local textfield_percentage = parent_flow.add{type="textfield", name="fp_textfield_production_percentage_"
      .. line.id, text=relevant_line.percentage, enabled=(not metadata.archive_open)}
    ui_util.setup_numeric_textfield(textfield_percentage, true, false)
    textfield_percentage.style.horizontal_align = "center"
    textfield_percentage.style.width = 55
end

function builders.machine(parent_flow, line)

end

function builders.beacon(parent_flow, line)

end

function builders.energy(parent_flow, line)

end

function builders.pollution(parent_flow, line)

end

function builders.products(parent_flow, line)

end

function builders.byproducts(parent_flow, line)

end

function builders.ingredients(parent_flow, line)

end

function builders.line_comment(parent_flow, line)

end


-- ** TOP LEVEL **
local all_production_columns = {
    {name="recipe", caption={"fp.pu_recipe", 1}, tooltip=nil, minimal_width=0, alignment="center"},
    {name="percentage", caption={"fp.info_label", "%"}, tooltip={"fp.column_percentage_tt"}, minimal_width=0, alignment="center"},
    {name="machine", caption={"fp.pu_machine", 1}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="beacon", caption={"fp.pu_beacon", 1}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="energy", caption={"fp.u_energy"}, tooltip=nil, minimal_width=0, alignment="center"},
    {name="pollution", caption={"fp.u_pollution"}, tooltip=nil, minimal_width=0, alignment="center"},
    {name="products", caption={"fp.pu_product", 2}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="byproducts", caption={"fp.pu_byproduct", 2}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="ingredients", caption={"fp.pu_ingredient", 2}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="line_comment", caption={"fp.column_comment"}, tooltip=nil, minimal_width=0, alignment="left"},
}

function production_table.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.production_table = {}

    -- Can't do much here since the table needs to be destroyed on refresh anyways
    local frame_vertical = main_elements.production_box.vertical_frame
    local scroll_pane_production = frame_vertical.add{type="scroll-pane", direction="vertical"}
    scroll_pane_production.style.horizontally_stretchable = true
    main_elements.production_table["production_scroll_pane"] = scroll_pane_production

    production_table.refresh(player)
end

function production_table.refresh(player)
    -- Determine the column_count first, because not all columns are nessecarily shown
    local preferences = data_util.get("preferences", player)
    local context = data_util.get("context", player)
    local production_columns, column_count = {}, 0

    for _, column_data in ipairs(all_production_columns) do
        -- Explicit comparison needed here, as both true and nil columns should be shown
        if preferences[column_data.name .. "_column"] ~= false then
            column_count = column_count + 1
            production_columns[column_count] = column_data
        end
    end

    local production_table_elements = data_util.get("main_elements", player).production_table
    local scroll_pane_production = production_table_elements.production_scroll_pane
    scroll_pane_production.clear()

    local table_production = scroll_pane_production.add{type="table", column_count=column_count}
    table_production.style.horizontal_spacing = 12
    table_production.style.margin = {6, 18, 0, 18}
    production_table_elements["table"] = table_production

    -- Column headers
    for index, column_data in ipairs(production_columns) do
        local label_column = table_production.add{type="label", caption=column_data.caption,
          tooltip=column_data.tooltip, style="bold_label"}
        label_column.style.minimal_width = column_data.minimal_width
        label_column.style.bottom_margin = 6
        table_production.style.column_alignments[index] = column_data.alignment
    end

    -- Generates some data that is relevant to several different builders
    local metadata = generate_metadata(player)

    -- Production lines
    for _, line in ipairs(Floor.get_in_order(context.floor, "Line")) do
        -- TODO add metadata per line as well
        for _, column_data in ipairs(production_columns) do
            local flow = table_production.add{type="flow", name="flow_" .. column_data.name .. "_" .. line.id,
              direction="horizontal"}
            builders[column_data.name](player, line, flow, metadata)
        end
    end
end