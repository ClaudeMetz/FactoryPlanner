production_table = {}

-- ** LOCAL UTIL **
local function generate_metadata(player)
    local ui_state = data_util.get("ui_state", player)
    local preferences = data_util.get("preferences", player)

    local metadata = {
        archive_open = (ui_state.flags.archive_open),
        round_button_numbers = preferences.round_button_numbers,
        pollution_column = preferences.pollution_column,
        ingredient_satisfaction = preferences.ingredient_satisfaction,
        view_state_metadata = view_state.generate_metadata(player, ui_state.context.subfactory, 4, true)
    }

    if preferences.tutorial_mode then
        metadata.recipe_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "recipe", true, true, true)
        metadata.machine_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "machine", false, true, true)
        metadata.beacon_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "beacon", false, true, true)
        metadata.module_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "module", false, true, true)
        metadata.product_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "product", false, true, true)
        metadata.byproduct_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "byproduct", false, true, true)
        metadata.ingredient_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "ingredient", false, true, true)
        metadata.fuel_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "fuel", false, true, true)
    end

    return metadata
end

-- ** BUILDERS **
local builders = {}

function builders.recipe(line, parent_flow, metadata)
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)
    local recipe_proto = relevant_line.recipe.proto

    local style, tooltip, enabled = "flib_slot_button_default_small", recipe_proto.localised_name, true
    -- Make the first line of every subfloor un-interactable, it stays constant
    if line.parent.level > 1 and line.gui_position == 1 then
        style = "flib_slot_button_blue_small"
        enabled = false
    else
        local indication = ""
        if line.subfloor then
            indication = {"fp.newline", {"fp.notice", {"fp.recipe_subfloor_attached"}}}
            style = "flib_slot_button_blue_small"
        end

        tooltip = {"", tooltip, indication, metadata.recipe_tutorial_tooltip or ""}
    end

    parent_flow.add{type="sprite-button", name="fp_sprite-button_production_recipe_" .. line.id, enabled=enabled,
      sprite=recipe_proto.sprite, tooltip=tooltip, style=style, mouse_button_filter={"left-and-right"}}
end

function builders.percentage(line, parent_flow, metadata)
    local relevant_line = (line.subfloor == nil) and line or Floor.get(line.subfloor, "Line", 1)

    local textfield_percentage = parent_flow.add{type="textfield", name="fp_textfield_production_percentage_"
      .. line.id, text=relevant_line.percentage, enabled=(not metadata.archive_open)}
    ui_util.setup_numeric_textfield(textfield_percentage, true, false)
    textfield_percentage.style.horizontal_align = "center"
    textfield_percentage.style.width = 55
end

function builders.machine(line, parent_flow, metadata)
    local machine_count = line.machine.count

    if line.subfloor then  -- add a button that shows the total of all machines on the subfloor
        -- Machine count doesn't need any special formatting in this case because it'll always be an integer
        local tooltip = {"fp.subfloor_machine_count", machine_count, {"fp.pl_machine", machine_count}}
        parent_flow.add{type="sprite-button", sprite="fp_generic_assembler", style="flib_slot_button_default_small",
          enabled=false, number=machine_count, tooltip=tooltip}
    else
        -- Machine
        machine_count = ui_util.format_number(machine_count, 4)
        local tooltip_count = machine_count
        if machine_count == "0" and line.production_ratio > 0 then
            tooltip_count = "<0.0001"
            machine_count = "0.01"  -- shows up as 0.0 on the button
        end
        if metadata.round_button_numbers then machine_count = math.ceil(machine_count) end

        local style, indication, machine_limit = "flib_slot_button_default_small", "", line.machine.limit
        if machine_limit ~= nil then
            if line.machine.hard_limit then
                style = "flib_slot_button_cyan_small"
                indication = {"fp.newline", {"fp.notice", {"fp.machine_limit_hard", machine_limit}}}
            elseif line.production_ratio < line.uncapped_production_ratio then
                style = "flib_slot_button_yellow_small"
                indication = {"fp.newline", {"fp.notice", {"fp.machine_limit_enforced", machine_limit}}}
            else
                style = "flib_slot_button_green_small"
                indication = {"fp.newline", {"fp.notice", {"fp.machine_limit_set", machine_limit}}}
            end
        end

        local machine_proto = line.machine.proto
        local plural_parameter = (machine_count == "1") and 1 or 2
        local number_line = {"fp.newline", {"fp.two_word_title", tooltip_count, {"fp.pl_machine", plural_parameter}}}
        local tooltip = {"", machine_proto.localised_name, number_line, indication, line.machine.effects_tooltip,
          metadata.machine_tutorial_tooltip}

        parent_flow.add{type="sprite-button", name="fp_sprite-button_production_machine_" .. line.id, style=style,
          sprite=machine_proto.sprite, number=machine_count, tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        -- Modules - can only be added to machines that have any module slots
        if machine_proto.module_limit == 0 then return end

        local separator = parent_flow.add{type="line", direction="vertical"}
        separator.style.padding = {4, 0}

        for _, module in ipairs(Machine.get_in_order(line.machine, "Module")) do
            number_line = {"fp.newline", {"fp.two_word_title", module.amount, {"fp.pl_module", module.amount}}}
            tooltip = {"", module.proto.localised_name, number_line, module.effects_tooltip,
              metadata.module_tutorial_tooltip}
            -- The above variables don't need to be-initialized

            parent_flow.add{type="sprite-button", name="fp_sprite-button_production_machine_Module_" .. line.id
              .. "_" .. module.id, sprite=module.proto.sprite, tooltip=tooltip, number=module.amount,
              style="flib_slot_button_default_small", mouse_button_filter={"left-and-right"}}
        end

        if Machine.empty_slot_count(line.machine) > 0 then
            parent_flow.add{type="sprite-button", name="fp_sprite-button_production_add_module_" .. line.id,
              sprite="utility/add", style="fp_sprite-button_inset_production", tooltip={"fp.add_module"},
              mouse_button_filter={"left"}, enabled=(not metadata.archive_open)}
        end
    end
end

function builders.beacon(line, parent_flow, metadata)
    -- Beacons only work on machines that have some allowed_effects
    if line.subfloor ~= nil or line.machine.proto.allowed_effects == nil then return end

    local beacon = line.beacon
    if beacon == nil then
        parent_flow.add{type="sprite-button", name="fp_sprite-button_production_add_beacon_" .. line.id,
            sprite="utility/add", style="fp_sprite-button_inset_production", tooltip={"fp.add_beacon"},
            mouse_button_filter={"left"}, enabled=(not metadata.archive_open)}
    else
        -- Beacon
        local plural_parameter = (beacon.amount == 1) and 1 or 2  -- needed because the amount can be decimal
        local number_line = {"fp.newline", {"fp.two_word_title", beacon.amount, {"fp.pl_beacon", plural_parameter}}}
        local indication = (beacon.total_amount) and
            {"fp.newline", {"fp.notice", {"fp.beacon_total_indication", beacon.total_amount}}} or ""
        local tooltip = {"", beacon.proto.localised_name, number_line, indication, beacon.effects_tooltip,
          metadata.beacon_tutorial_tooltip}

        local button_beacon = parent_flow.add{type="sprite-button", name="fp_sprite-button_production_beacon_"
            .. line.id, sprite=beacon.proto.sprite, number=beacon.amount, style="flib_slot_button_default_small",
            tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        if beacon.total_amount ~= nil then  -- add a graphical hint that a beacon total is set
            local sprite_overlay = button_beacon.add{type="sprite", sprite="fp_sprite_white_square"}
            sprite_overlay.ignored_by_interaction = true
        end

        -- Module
        local separator = parent_flow.add{type="line", direction="vertical"}
        separator.style.padding = {4, 0}
        local module_proto, module_amount = beacon.module.proto, beacon.module.amount

        -- Can use simplified number line because module amount is an integer
        number_line = {"fp.newline", {"fp.two_word_title", module_amount, {"fp.pl_module", module_amount}}}
        tooltip = {"", module_proto.localised_name, number_line}
        -- The above variables don't need to be-initialized

        parent_flow.add{type="sprite-button", sprite=module_proto.sprite, tooltip=tooltip, enabled=false,
          number=module_amount, style="flib_slot_button_default_small"}
    end
end

function builders.energy(line, parent_flow, metadata)
    local pollution_line = (metadata.pollution_column) and ""
      or {"fp.newline", {"fp.name_value", {"fp.u_pollution"}, ui_util.format_SI_value(line.pollution, "P/m", 5)}}
    parent_flow.add{type="label", caption=ui_util.format_SI_value(line.energy_consumption, "W", 3),
      tooltip={"", ui_util.format_SI_value(line.energy_consumption, "W", 5), pollution_line}}
end

function builders.pollution(line, parent_flow, _)
    parent_flow.add{type="label", caption=ui_util.format_SI_value(line.pollution, "P/m", 3),
      tooltip=ui_util.format_SI_value(line.pollution, "P/m", 5)}
end

function builders.products(line, parent_flow, metadata)
    for _, product in ipairs(Line.get_in_order(line, "Product")) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
          product, nil, machine_count)
        if amount == -1 then goto skip_product end  -- an amount of -1 means it was below the margin of error

        local style = "flib_slot_button_default_small"
        local indication_string, tutorial_tooltip = "", ""

        if not line.subfloor then
            -- We can check for identity because they reference the same table
            if line.priority_product_proto == product.proto then
                style = "flib_slot_button_green_small"
                indication_string = {"fp.indication", {"fp.priority_product"}}
            end
            tutorial_tooltip = metadata.product_tutorial_tooltip
        end

        local name_line = {"fp.two_word_title", product.proto.localised_name, indication_string}
        local number_line = (number_tooltip) and {"fp.newline", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, tutorial_tooltip}

        parent_flow.add{type="sprite-button", name="fp_sprite-button_production_item_Product_" .. line.id
          .. "_" .. product.id, sprite=product.proto.sprite, style=style, number=amount,
          tooltip=tooltip, enabled=(not line.subfloor), mouse_button_filter={"left-and-right"}}

        ::skip_product::
    end
end

function builders.byproducts(line, parent_flow, metadata)
    for _, byproduct in ipairs(Line.get_in_order(line, "Byproduct")) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
          byproduct, nil, machine_count)
        if amount == -1 then goto skip_byproduct end  -- an amount of -1 means it was below the margin of error

        local number_line = (number_tooltip) and {"fp.newline", number_tooltip} or ""
        local tutorial_tooltip = (not line.subfloor) and metadata.byproduct_tutorial_tooltip or ""
        local tooltip = {"", byproduct.proto.localised_name, number_line, tutorial_tooltip}

        parent_flow.add{type="sprite-button", name="fp_sprite-button_production_item_Byproduct_" .. line.id
          .. "_" .. byproduct.id, sprite=byproduct.proto.sprite, style="flib_slot_button_red_small", number=amount,
          tooltip=tooltip, enabled=(not line.subfloor), mouse_button_filter={"left-and-right"}}

        ::skip_byproduct::
    end
end

function builders.ingredients(line, parent_flow, metadata)
    for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
          ingredient, nil, machine_count)
        if amount == -1 then goto skip_ingredient end  -- an amount of -1 means it was below the margin of error

        local style = "flib_slot_button_green_small"
        local satisfaction_line, indication_string = "", ""

        if ingredient.proto.type == "entity" then
            style = "flib_slot_button_default_small"
            indication_string = {"fp.indication", {"fp.raw_ore"}}

        elseif metadata.ingredient_satisfaction then
            local satisfaction_percentage = (ingredient.satisfied_amount / ingredient.amount) * 100
            local formatted_percentage = ui_util.format_number(satisfaction_percentage, 3)

            -- We use the formatted percentage here because it smooths out the number to 3 places
            local satisfaction = tonumber(formatted_percentage)
            if satisfaction <= 0 then
                style = "flib_slot_button_red_small"
            elseif satisfaction < 100 then
                style = "flib_slot_button_yellow_small"
            end  -- else, it stays green

            satisfaction_line = {"fp.newline", {"fp.two_word_title", (formatted_percentage .. "%"), {"fp.satisfied"}}}
        end

        local name_line = {"fp.two_word_title", ingredient.proto.localised_name, indication_string}
        local number_line = (number_tooltip) and {"fp.newline", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, satisfaction_line, metadata.ingredient_tutorial_tooltip}

        parent_flow.add{type="sprite-button", name="fp_sprite-button_production_item_Ingredient_" .. line.id
          .. "_" .. ingredient.id, sprite=ingredient.proto.sprite, style=style, number=amount,
          tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        ::skip_ingredient::
    end

    if not line.subfloor and line.machine.fuel then builders.fuel(line, parent_flow, metadata) end
end

-- This is not a standard builder function, as it gets called indirectly by the ingredient builder
function builders.fuel(line, parent_flow, metadata)
    local fuel = line.machine.fuel

    local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata, fuel, nil, line.machine.count)
    if amount == -1 then return end  -- an amount of -1 means it was below the margin of error

    local satisfaction_line = ""
    if metadata.ingredient_satisfaction then
        local satisfaction_percentage = (fuel.satisfied_amount / fuel.amount) * 100
        local formatted_percentage = ui_util.format_number(satisfaction_percentage, 3)
        satisfaction_line = {"fp.newline", {"fp.two_word_title", (formatted_percentage .. "%"), {"fp.satisfied"}}}
    end

    local name_line = {"fp.annotated_title", fuel.proto.localised_name, {"fp.pu_fuel", 1}}
    local number_line = (number_tooltip) and {"fp.newline", number_tooltip} or ""
    local tooltip = {"", name_line, number_line, satisfaction_line, metadata.fuel_tutorial_tooltip}

    parent_flow.add{type="sprite-button", name="fp_sprite-button_production_fuel_" .. line.id,
      sprite=fuel.proto.sprite, style="flib_slot_button_cyan_small", number=amount,
      tooltip=tooltip, mouse_button_filter={"left-and-right"}}
end

function builders.line_comment(line, parent_flow, _)
    local textfield_name = "fp_textfield_production_comment_" .. line.id
    local textfield_comment = parent_flow.add{type="textfield", name=textfield_name, text=(line.comment or "")}
    ui_util.setup_textfield(textfield_comment)
    textfield_comment.style.width = 160
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
    {name="line_comment", caption={"fp.column_comment"}, tooltip=nil, minimal_width=0, alignment="left"}
}

function production_table.build(player)
    local main_elements = data_util.get("main_elements", player)
    main_elements.production_table = {}

    -- Can't do much here since the table needs to be destroyed on refresh anyways
    local frame_vertical = main_elements.production_box.vertical_frame
    local scroll_pane_production = frame_vertical.add{type="scroll-pane", direction="vertical",
      style="flib_naked_scroll_pane_no_padding"}
    scroll_pane_production.style.horizontally_stretchable = true
    main_elements.production_table["production_scroll_pane"] = scroll_pane_production

    production_table.refresh(player)
end

function production_table.refresh(player)
    -- Determine the column_count first, because not all columns are nessecarily shown
    local preferences = data_util.get("preferences", player)
    local ui_state = data_util.get("ui_state", player)
    if ui_state.context.subfactory == nil then return end

    local production_columns, column_count = {}, 0
    for _, column_data in ipairs(all_production_columns) do
        -- Explicit comparison needed here, as both true and nil columns should be shown
        if preferences[column_data.name .. "_column"] ~= false then
            column_count = column_count + 1
            production_columns[column_count] = column_data
        end
    end
    column_count = column_count + 1

    local production_table_elements = data_util.get("main_elements", player).production_table
    local scroll_pane_production = production_table_elements.production_scroll_pane
    scroll_pane_production.clear()

    local table_production = scroll_pane_production.add{type="table", column_count=column_count,
      style="fp_table_production"}
    table_production.style.horizontal_spacing = 16
    table_production.style.padding = {6, 0, 0, 12}
    production_table_elements["table"] = table_production

    -- Column headers
    for index, column_data in ipairs(production_columns) do
        local label_column = table_production.add{type="label", caption=column_data.caption,
          tooltip=column_data.tooltip, style="bold_label"}
        label_column.style.minimal_width = column_data.minimal_width
        label_column.style.bottom_margin = 6
        table_production.style.column_alignments[index] = column_data.alignment
    end
    table_production.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Generates some data that is relevant to several different builders
    local metadata = generate_metadata(player)

    -- Production lines
    for _, line in ipairs(Floor.get_in_order(ui_state.context.floor, "Line")) do
        for _, column_data in ipairs(production_columns) do
            local flow = table_production.add{type="flow", direction="horizontal"}
            builders[column_data.name](line, flow, metadata)
        end
        table_production.add{type="empty-widget"}
    end
end