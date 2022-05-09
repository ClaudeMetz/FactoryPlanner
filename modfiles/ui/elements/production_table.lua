production_table = {}

-- ** LOCAL UTIL **
local function generate_metadata(player)
    local ui_state = data_util.get("ui_state", player)
    local preferences = data_util.get("preferences", player)

    local subfactory = ui_state.context.subfactory
    local mining_productivity = (subfactory.mining_productivity ~= nil) and
      (subfactory.mining_productivity / 100) or player.force.mining_drill_productivity_bonus

    local metadata = {
        archive_open = (ui_state.flags.archive_open),
        solver_type = subfactory.solver_type,
        mining_productivity = mining_productivity,
        round_button_numbers = preferences.round_button_numbers,
        pollution_column = preferences.pollution_column,
        ingredient_satisfaction = preferences.ingredient_satisfaction,
        view_state_metadata = view_state.generate_metadata(player, subfactory, 4, true),
        any_beacons_available = (table_size(global.all_beacons.map) > 0)
    }

    if preferences.tutorial_mode then
        -- Choose the right type of tutorial text right here if possible
        local element_types
        if metadata.solver_type == "traditional" then
          element_types = {
            ["machine"] = "machine",
            ["product"] = "product",
            ["byproduct"] = "byproduct",
            ["ingredient"] = "ingredient",
            ["ingredient_entity"] = "ingredient_entity",
          }
        elseif metadata.solver_type == "matrix" then
          element_types = {
            ["machine"] = "machine_matrix",
            ["product"] = nil,
            ["byproduct"] = "byproduct_matrix",
            ["ingredient"] = "ingredient_matrix",
            ["ingredient_entity"] = nil,
          }
        elseif metadata.solver_type == "interior_point" then
          element_types = {
            ["machine"] = "machine",
            ["product"] = "product_matrix",
            ["byproduct"] = nil,
            ["ingredient"] = "ingredient_matrix",
            ["ingredient_entity"] = nil,
          }
        end

        metadata.production_toggle_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "production_toggle",
          false, false, true)
        metadata.producing_recipe_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "producing_recipe",
          true, true, true)
        metadata.consuming_recipe_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "consuming_recipe",
          true, true, true)
        metadata.machine_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, element_types["machine"],
          false, true, true)
        metadata.beacon_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "beacon", false, true, true)
        metadata.module_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "module", false, true, true)
        metadata.product_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, element_types["product"], true, true, true)
        metadata.byproduct_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, element_types["byproduct"],
         true, true, true)
        metadata.ingredient_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, element_types["ingredient"],
          true, true, true)
        metadata.ingredient_entity_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, element_types["ingredient_entity"],
          true, true, true)
        metadata.fuel_tutorial_tooltip = ui_util.generate_tutorial_tooltip(player, "fuel", true, true, true)
    end

    return metadata
end

-- ** BUILDERS **
local builders = {}

function builders.toggle(line, parent_flow, metadata)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    parent_flow.add{type="checkbox", tags={mod="fp", on_gui_click="toggle_line", line_id=line.id},
      state=relevant_line.active, tooltip=metadata.production_toggle_tutorial_tooltip,
      enabled=(not metadata.archive_open), mouse_button_filter={"left"}}
end

function builders.done(line, parent_flow, _)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

    local sprite = (relevant_line.done) and "utility/check_mark" or "fp_sprite_check_mark_green"
    local style = (relevant_line.done) and "fp_button_slot_green" or "flib_slot_default"

    local button = parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="checkmark_line", line_id=line.id},
      sprite=sprite, style=style, mouse_button_filter={"left"}, tooltip=nil}
    button.style.size = 24
    button.style.padding = 0
end

function builders.recipe(line, parent_flow, metadata)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line
    local recipe_proto = relevant_line.recipe.proto

    local style, enabled = "flib_slot_button_default_small", true
    local indication, tutorial_tooltip = "", metadata.producing_recipe_tutorial_tooltip
    -- Make the first line of every subfloor un-interactable, it stays constant
    if line.parent.level > 1 and line.gui_position == 1 then
        style = "flib_slot_button_grey_small"
        enabled = false
        tutorial_tooltip = ""
    elseif line.subfloor then
        style = "flib_slot_button_blue_small"
        indication = {"fp.newline", {"fp.notice", {"fp.recipe_subfloor_attached"}}}
    elseif line.recipe.production_type == "consume" then
        style = "flib_slot_button_red_small"
        indication = {"fp.newline", {"fp.notice", {"fp.recipe_consumes_byproduct"}}}
        tutorial_tooltip = metadata.consuming_recipe_tutorial_tooltip
    end

    local tooltip = {"", recipe_proto.localised_name, indication, tutorial_tooltip}
    parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_recipe", line_id=line.id},
      enabled=enabled, sprite=recipe_proto.sprite, tooltip=tooltip, style=style, mouse_button_filter={"left-and-right"}}
end

function builders.percentage(line, parent_flow, metadata)
    local relevant_line = (line.subfloor) and line.subfloor.defining_line or line

    local enabled = (not metadata.archive_open)
    local textfield_percentage = parent_flow.add{type="textfield", text=tostring(relevant_line.percentage),
      tags={mod="fp", on_gui_text_changed="line_percentage", on_gui_confirmed="line_percentage", line_id=line.id},
      enabled=enabled}
    ui_util.setup_numeric_textfield(textfield_percentage, true, false)
    textfield_percentage.style.horizontal_align = "center"
    textfield_percentage.style.width = 55
end

function builders.machine(line, parent_flow, metadata)
    local machine_count = line.machine.count
    parent_flow.style.horizontal_spacing = 2

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
        if metadata.solver_type ~= "matrix" and machine_limit ~= nil then
            if line.machine.force_limit then
                style = "flib_slot_button_pink_small"
                indication = {"fp.newline", {"fp.notice", {"fp.machine_limit_force", machine_limit}}}
            elseif line.production_ratio < line.uncapped_production_ratio then
                style = "flib_slot_button_orange_small"
                indication = {"fp.newline", {"fp.notice", {"fp.machine_limit_enforced", machine_limit}}}
            else
                style = "flib_slot_button_green_small"
                indication = {"fp.newline", {"fp.notice", {"fp.machine_limit_set", machine_limit}}}
            end
        end

        local machine_proto = line.machine.proto
        local effects_tooltip = line.machine.effects_tooltip
        if machine_proto.mining then  -- Dynamically generate effects tooltip to include mining productivity
            local module_effects = table.shallow_copy(line.total_effects)
            module_effects.productivity = module_effects.productivity + metadata.mining_productivity
            effects_tooltip = data_util.format_module_effects(module_effects, 1, true)
        end

        local plural_parameter = (machine_count == "1") and 1 or 2
        local number_line = {"fp.newline", {"fp.two_word_title", tooltip_count, {"fp.pl_machine", plural_parameter}}}
        local tutorial_tooltip = metadata.machine_tutorial_tooltip
        local tooltip = {"", machine_proto.localised_name, number_line, indication, effects_tooltip, tutorial_tooltip}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_machine", line_id=line.id},
          style=style, sprite=machine_proto.sprite, number=machine_count, tooltip=tooltip,
          mouse_button_filter={"left-and-right"}}

        -- Modules - can only be added to machines that have any module slots
        if machine_proto.module_limit == 0 then return end

        local separator = parent_flow.add{type="line", direction="vertical"}
        separator.style.padding = {2, 0}

        for _, module in ipairs(Machine.get_in_order(line.machine, "Module")) do
            number_line = {"fp.newline", {"fp.two_word_title", module.amount, {"fp.pl_module", module.amount}}}
            tooltip = {"", module.proto.localised_name, number_line, module.effects_tooltip,
              metadata.module_tutorial_tooltip}
            -- The above variables don't need to be-initialized

            parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_module", line_id=line.id,
              module_id=module.id}, sprite=module.proto.sprite, tooltip=tooltip, number=module.amount,
              style="flib_slot_button_default_small", mouse_button_filter={"left-and-right"}}
        end

        if Machine.empty_slot_count(line.machine) > 0 then
            parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="add_line_module", line_id=line.id},
              sprite="utility/add", style="fp_sprite-button_inset_production", tooltip={"fp.add_module"},
              enabled=(not metadata.archive_open), mouse_button_filter={"left"}}
        end
    end
end

function builders.beacon(line, parent_flow, metadata)
    -- Some mods might remove all beacons, in which case no beacon buttons should be added
    if not metadata.any_beacons_available then return end
    -- Beacons only work on machines that have some allowed_effects
    if line.subfloor ~= nil or line.machine.proto.allowed_effects == nil then return end

    local beacon = line.beacon
    if beacon == nil then
        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="add_line_beacon", line_id=line.id},
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

        local button_beacon = parent_flow.add{type="sprite-button", sprite=beacon.proto.sprite, number=beacon.amount,
          tags={mod="fp", on_gui_click="act_on_line_beacon", line_id=line.id}, style="flib_slot_button_default_small",
          tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        if beacon.total_amount ~= nil then  -- add a graphical hint that a beacon total is set
            local sprite_overlay = button_beacon.add{type="sprite", sprite="fp_sprite_white_square"}
            sprite_overlay.ignored_by_interaction = true
        end

        -- Module
        local separator = parent_flow.add{type="line", direction="vertical"}
        separator.style.padding = {2, 0}
        separator.style.margin = {0, -2}

        for _, module in ipairs(Beacon.get_in_order(beacon, "Module")) do
            local module_proto, module_amount = module.proto, module.amount

            -- Can use simplified number line because module amount is an integer
            number_line = {"fp.newline", {"fp.two_word_title", module_amount, {"fp.pl_module", module_amount}}}
            tooltip = {"", module_proto.localised_name, number_line, module.effects_tooltip}
            -- The above variables don't need to be initialized

            parent_flow.add{type="sprite-button", sprite=module_proto.sprite, tooltip=tooltip, enabled=false,
              number=module_amount, style="flib_slot_button_default_small"}
        end
    end
end

function builders.power(line, parent_flow, metadata)
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
          product, nil, machine_count, not line.subfloor)
        if amount == "0" and line.subfloor then goto skip_product end  -- amount can't be -1 for products

        local style, enabled = "flib_slot_button_default_small", false
        local indication_string, tutorial_tooltip = "", ""

        if metadata.solver_type == "traditional" and not line.subfloor then
            -- We can check for identity because they reference the same table
            if line.priority_product_proto == product.proto then
                style = "flib_slot_button_pink_small"
                indication_string = {"fp.indication", {"fp.priority_product"}}
            end
            enabled = true
            tutorial_tooltip = metadata.product_tutorial_tooltip
        else
            enabled = (metadata.solver_type ~= "matrix")
            tutorial_tooltip = metadata.product_tutorial_tooltip
        end

        local name_line = {"fp.two_word_title", product.proto.localised_name, indication_string}
        local number_line = (number_tooltip) and {"fp.newline", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, tutorial_tooltip}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_item", line_id=line.id,
          class="Product", item_id=product.id}, sprite=product.proto.sprite, style=style, number=amount,
          tooltip=tooltip, enabled=enabled, mouse_button_filter={"left-and-right"}}

        ::skip_product::
    end
end

function builders.byproducts(line, parent_flow, metadata)
    for _, byproduct in ipairs(Line.get_in_order(line, "Byproduct")) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
          byproduct, nil, machine_count, not line.subfloor)
        if amount == -1 then goto skip_byproduct end  -- an amount of -1 means it was below the margin of error

        local enabled = (metadata.solver_type ~= "traditional" or not line.subfloor)
        local number_line = (number_tooltip) and {"fp.newline", number_tooltip} or ""
        local tutorial_tooltip = enabled and metadata.byproduct_tutorial_tooltip or ""
        local tooltip = {"", byproduct.proto.localised_name, number_line, tutorial_tooltip}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_item", line_id=line.id,
          class="Byproduct", item_id=byproduct.id}, sprite=byproduct.proto.sprite, style="flib_slot_button_red_small",
          number=amount, tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        ::skip_byproduct::
    end
end

function builders.ingredients(line, parent_flow, metadata)
    for _, ingredient in ipairs(Line.get_in_order(line, "Ingredient")) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
          ingredient, nil, machine_count, not line.subfloor)
        if amount == -1 then goto skip_ingredient end  -- an amount of -1 means it was below the margin of error

        local style, enabled = "flib_slot_button_green_small", true
        local satisfaction_line, indication_string = "", ""
        local tutorial_tooltip = metadata.ingredient_tutorial_tooltip

        if ingredient.proto.type == "entity" then
            style = "flib_slot_button_default_small"
            enabled = (metadata.solver_type == "traditional")
            indication_string = {"fp.indication", {"fp.raw_ore"}}
            tutorial_tooltip = metadata.ingredient_entity_tutorial_tooltip

        elseif metadata.ingredient_satisfaction and ingredient.amount > 0 then
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
        local tooltip = {"", name_line, number_line, satisfaction_line, tutorial_tooltip}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_item", line_id=line.id,
          class="Ingredient", item_id=ingredient.id}, sprite=ingredient.proto.sprite, style=style, number=amount,
          tooltip=tooltip, enabled=enabled, mouse_button_filter={"left-and-right"}}

        ::skip_ingredient::
    end

    if not line.subfloor and line.machine.fuel then builders.fuel(line, parent_flow, metadata) end
end

-- This is not a standard builder function, as it gets called indirectly by the ingredient builder
function builders.fuel(line, parent_flow, metadata)
    local fuel = line.machine.fuel

    local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
      fuel, nil, line.machine.count, not line.subfloor)
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

    parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_fuel", line_id=line.id},
      sprite=fuel.proto.sprite, style="flib_slot_button_cyan_small", number=amount,
      tooltip=tooltip, mouse_button_filter={"left-and-right"}}
end

function builders.line_comment(line, parent_flow, _)
    local textfield_comment = parent_flow.add{type="textfield", tags={mod="fp", on_gui_text_changed="line_comment",
      line_id=line.id}, text=(line.comment or "")}
      textfield_comment.style.width = 250
    ui_util.setup_textfield(textfield_comment)
end


-- ** TOP LEVEL **
local all_production_columns = {
    {name="toggle", caption="", tooltip={"fp.column_toggle_tt"}, minimal_width=0, alignment="center"},
    {name="done", caption="", tooltip={"fp.column_done_tt"}, minimal_width=0, alignment="center"},
    {name="recipe", caption={"fp.pu_recipe", 1}, tooltip=nil, minimal_width=0, alignment="center"},
    {name="percentage", caption="%", tooltip={"fp.column_percentage_tt"}, minimal_width=0, alignment="center"},
    {name="machine", caption={"fp.pu_machine", 1}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="beacon", caption={"fp.pu_beacon", 1}, tooltip=nil, minimal_width=0, alignment="left"},
    {name="power", caption={"fp.u_power"}, tooltip=nil, minimal_width=0, alignment="center"},
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
    local subfactory = ui_state.context.subfactory

    local production_table_elements = ui_state.main_elements.production_table
    local subfactory_valid = (subfactory and subfactory.valid)
    local any_lines_present = (subfactory_valid) and (subfactory.selected_floor.Line.count > 0) or false

    production_table_elements.production_scroll_pane.visible = (subfactory_valid and any_lines_present)
    if not subfactory_valid then return end

    local show_column = {}
    if subfactory.solver_type == "interior_point" then
        show_column = {["percentage"]=false, ["byproducts"]=false}
    elseif subfactory.solver_type == "matrix" then
        show_column = {["percentage"]=false}
    end

    local production_columns, column_count = {}, 0
    for _, column_data in ipairs(all_production_columns) do
        -- Explicit comparison needed here, as both true and nil columns should be shown
        local name = column_data.name
        if show_column[name] ~= false and preferences[name .. "_column"] ~= false then
            column_count = column_count + 1
            production_columns[column_count] = column_data
        end
    end
    column_count = column_count + 1

    local scroll_pane_production = production_table_elements.production_scroll_pane
    scroll_pane_production.clear()

    local table_production = scroll_pane_production.add{type="table", column_count=column_count,
      style="fp_table_production"}
    table_production.style.horizontal_spacing = 16
    table_production.style.padding = {6, 0, 0, 12}
    production_table_elements["table"] = table_production

    -- Column headers
    for index, column_data in ipairs(production_columns) do
        local caption = (column_data.tooltip) and {"fp.info_label", column_data.caption} or column_data.caption
        local label_column = table_production.add{type="label", caption=caption, tooltip=column_data.tooltip,
          style="bold_label"}
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
