-- ** LOCAL UTIL **
local function generate_metadata(player, factory)
    local preferences = util.globals.preferences(player)

    local metadata = {
        archive_open = factory.archived,
        matrix_solver_active = (factory.matrix_free_items ~= nil),
        fold_out_subfloors = preferences.fold_out_subfloors,
        round_button_numbers = preferences.round_button_numbers,
        pollution_column = preferences.pollution_column,
        ingredient_satisfaction = preferences.ingredient_satisfaction,
        view_state_metadata = view_state.generate_metadata(player, factory),
        any_beacons_available = (next(global.prototypes.beacons) ~= nil)
    }

    if preferences.tutorial_mode then
        util.actions.tutorial_tooltip_list(metadata, player, {
            recipe_tutorial_tt = "act_on_line_recipe",
            machine_tutorial_tt = "act_on_line_machine",
            beacon_tutorial_tt = "act_on_line_beacon",
            module_tutorial_tt = "act_on_line_module",
            product_tutorial_tt = "act_on_line_product",
            byproduct_tutorial_tt = "act_on_line_byproduct",
            ingredient_tutorial_tt = "act_on_line_ingredient",
            fuel_tutorial_tt = "act_on_line_fuel"
        })
    end

    return metadata
end


-- ** BUILDERS **
local builders = {}

function builders.done(line, parent_flow, _)
    local relevant_line = (line.class == "Floor") and line.first or line

    parent_flow.add{type="checkbox", state=relevant_line.done, mouse_button_filter={"left"},
        tags={mod="fp", on_gui_checked_state_changed="checkmark_line", line_id=line.id}}
end

function builders.recipe(line, parent_flow, metadata, indent)
    local relevant_line = (line.class == "Floor") and line.first or line
    local recipe_proto = relevant_line.recipe_proto

    parent_flow.style.vertical_align = "center"
    parent_flow.style.horizontal_spacing = 3

    if indent > 0 then parent_flow.style.left_margin = indent * 18 end

    local function create_move_button(flow, direction, first_subfloor_line)
        local enabled = not (first_subfloor_line or metadata.archive_open)
        if direction == "next" and line.next == nil then enabled = false
        elseif direction == "previous" then
            if line.previous == nil then enabled = false
            elseif line.parent.level > 1 and line.previous == line.parent.first then enabled = false end
        end

        local endpoint = (direction == "previous") and {"fp.top"} or {"fp.bottom"}
        local up_down = (direction == "previous") and "up" or "down"
        local move_tooltip = (enabled) and {"fp.move_row_tt", {"fp.pl_recipe", 1}, {"fp." .. up_down}, endpoint} or ""

        flow.add{type="sprite-button", style="fp_button_move_row", sprite="fp_sprite_arrow_" .. up_down,
            tags={mod="fp", on_gui_click="move_line", direction=direction, line_id=line.id},
            tooltip=move_tooltip, enabled=enabled, mouse_button_filter={"left"}}
    end

    local move_flow = parent_flow.add{type="flow", direction="vertical"}
    move_flow.style.vertical_spacing = 0
    move_flow.style.top_padding = 2

    local first_subfloor_line = (line.parent.level > 1 and line.previous == nil)
    create_move_button(move_flow, "previous", first_subfloor_line)
    create_move_button(move_flow, "next", first_subfloor_line)

    local style, enabled, tutorial_tooltip = nil, true, ""
    local note = ""  ---@type LocalisedString
    if first_subfloor_line then
        style = "flib_slot_button_grey_small"
        enabled = false  -- first subfloor line is static
    else
        style = (relevant_line.active) and "flib_slot_button_default_small" or "flib_slot_button_red_small"
        note = (relevant_line.active) and "" or {"fp.recipe_inactive"}
        tutorial_tooltip = metadata.recipe_tutorial_tt

        if line.class == "Floor" then
            style = (relevant_line.active) and "flib_slot_button_blue_small" or "flib_slot_button_purple_small"
            note = {"fp.recipe_subfloor_attached"}

        elseif line.production_type == "input" then
            style = (relevant_line.active) and "flib_slot_button_yellow_small" or "flib_slot_button_orange_small"
            note = {"fp.recipe_consumes_byproduct"}
        end
    end

    local first_line = (note == "") and {"fp.tt_title", recipe_proto.localised_name}
        or {"fp.tt_title_with_note", recipe_proto.localised_name, note}
    local tooltip = {"", first_line, relevant_line.effects_tooltip, tutorial_tooltip}
    parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_recipe", line_id=line.id},
        enabled=enabled, sprite=recipe_proto.sprite, tooltip=tooltip, style=style,
        mouse_button_filter={"left-and-right"}}
end

function builders.percentage(line, parent_flow, metadata)
    local relevant_line = (line.class == "Floor") and line.first or line

    local enabled = (not metadata.archive_open and not metadata.matrix_solver_active)
    local textfield_percentage = parent_flow.add{type="textfield", text=tostring(relevant_line.percentage),
        tags={mod="fp", on_gui_text_changed="line_percentage", on_gui_confirmed="line_percentage", line_id=line.id},
        enabled=enabled}
    util.gui.setup_numeric_textfield(textfield_percentage, true, false)
    textfield_percentage.style.horizontal_align = "center"
    textfield_percentage.style.width = 55
end


local function add_module_flow(parent_flow, line, parent_type, metadata)
    for _, module in ipairs(ModuleSet.get_in_order(line[parent_type].module_set)) do
        local number_line = {"", "\n", module.amount, " ", {"fp.pl_module", module.amount}}
        local tooltip = {"", {"fp.tt_title", module.proto.localised_name}, number_line, module.effects_tooltip,
            metadata.module_tutorial_tt}

        parent_flow.add{type="sprite-button", sprite=module.proto.sprite, tooltip=tooltip,
            tags={mod="fp", on_gui_click="act_on_line_module", floor_id=line.parent.id, line_id=line.id,
            parent_type=parent_type, module_id=module.id}, number=module.amount, style="flib_slot_button_default_small",
            mouse_button_filter={"left-and-right"}}
    end
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
        local active, round_number = (line.production_ratio > 0), metadata.round_button_numbers
        local count, tooltip_line = util.format.machine_count(machine_count, active, round_number)

        local machine_limit = line.machine.limit
        local style, note = "flib_slot_button_default_small", nil
        if not metadata.matrix_solver_active and machine_limit ~= nil then
            if line.machine.force_limit then
                style = "flib_slot_button_pink_small"
                note = {"fp.machine_limit_force", machine_limit}
            elseif line.production_ratio < line.uncapped_production_ratio then
                style = "flib_slot_button_orange_small"
                note = {"fp.machine_limit_enforced", machine_limit}
            else
                style = "flib_slot_button_green_small"
                note = {"fp.machine_limit_set", machine_limit}
            end
        end

        if note ~= nil then table.insert(tooltip_line, {"", " - ", note}) end
        local tooltip = {"", {"fp.tt_title", line.machine.proto.localised_name}, "\n", tooltip_line,
            line.machine.effects_tooltip, metadata.machine_tutorial_tt}

        parent_flow.add{type="sprite-button", style=style, sprite=line.machine.proto.sprite, number=count,
            tags={mod="fp", on_gui_click="act_on_line_machine", floor_id=line.parent.id, line_id=line.id,
            type="machine"}, tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        add_module_flow(parent_flow, line, "machine", metadata)
        local module_set = line.machine.module_set
        if module_set.module_limit > module_set.module_count then
            local module_tooltip = {"", {"fp.add_machine_module"}, "\n", {"fp.shift_to_paste"}}
            local button = parent_flow.add{type="sprite-button", sprite="utility/add", tooltip=module_tooltip,
                tags={mod="fp", on_gui_click="add_machine_module", floor_id=line.parent.id, line_id=line.id},
                style="fp_sprite-button_inset_add", mouse_button_filter={"left"}, enabled=(not metadata.archive_open)}
            button.style.margin = 2
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
        local tooltip = {"", {"fp.add_beacon"}, "\n", {"fp.shift_to_paste"}}
        local button = parent_flow.add{type="sprite-button", sprite="utility/add", tooltip=tooltip,
            tags={mod="fp", on_gui_click="add_line_beacon", floor_id=line.parent.id, line_id=line.id},
            style="fp_sprite-button_inset_add", mouse_button_filter={"left"}, enabled=(not metadata.archive_open)}
        button.style.margin = 2
    else
        local plural_parameter = (beacon.amount == 1) and 1 or 2  -- needed because the amount can be decimal
        local number_line = {"", "\n", beacon.amount, " ", {"fp.pl_beacon", plural_parameter}}
        if beacon.total_amount then table.insert(number_line, {"", " - ", {"fp.in_total", beacon.total_amount}}) end
        local tooltip = {"", {"fp.tt_title", beacon.proto.localised_name}, number_line, beacon.effects_tooltip,
            metadata.beacon_tutorial_tt}

        local button_beacon = parent_flow.add{type="sprite-button", sprite=beacon.proto.sprite, number=beacon.amount,
            tags={mod="fp", on_gui_click="act_on_line_beacon", floor_id=line.parent.id, line_id=line.id, type="beacon"},
            style="flib_slot_button_default_small", tooltip=tooltip, mouse_button_filter={"left-and-right"}}

        if beacon.total_amount ~= nil then  -- add a graphical hint that a beacon total is set
            local sprite_overlay = button_beacon.add{type="sprite", sprite="fp_sprite_white_square"}
            sprite_overlay.ignored_by_interaction = true
        end

        add_module_flow(parent_flow, line, "beacon", metadata)
    end
end

function builders.power(line, parent_flow, metadata)
    local pollution_line = (metadata.pollution_column) and ""
        or {"", "\n", {"fp.pollution"}, ": ", util.format.SI_value(line.pollution, "P/m", 5)}
    parent_flow.add{type="label", caption=util.format.SI_value(line.power, "W", 3),
        tooltip={"", util.format.SI_value(line.power, "W", 5), pollution_line}}
end

function builders.pollution(line, parent_flow, _)
    parent_flow.add{type="label", caption=util.format.SI_value(line.pollution, "P/m", 3),
        tooltip=util.format.SI_value(line.pollution, "P/m", 5)}
end

function builders.products(line, parent_flow, metadata)
    for _, product in ipairs(Line.get_in_order(line, "Product")) do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (not line.subfloor) and line.machine.count or nil
        local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata,
            product, nil, machine_count)
        if amount == -1 then goto skip_product end  -- an amount of -1 means it was below the margin of error

        local style, note = "flib_slot_button_default_small", nil
        if not line.subfloor and not metadata.matrix_solver_active then
            -- We can check for identity because they reference the same table
            if line.Product.count > 1 and line.priority_product_proto == product.proto then
                style = "flib_slot_button_pink_small"
                note = {"fp.priority_product"}
            end
        end

        local name_line = (note == nil) and {"fp.tt_title", product.proto.localised_name}
            or {"fp.tt_title_with_note", product.proto.localised_name, note}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, metadata.product_tutorial_tt}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_product",
            floor_id=line.parent.id, line_id=line.id, class="Product", item_id=product.id},
            sprite=product.proto.sprite, style=style, number=amount,
            tooltip=tooltip, mouse_button_filter={"left-and-right"}}

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

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", {"fp.tt_title", byproduct.proto.localised_name}, number_line,
            metadata.byproduct_tutorial_tt}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_byproduct",
            floor_id=line.parent.id, line_id=line.id, class="Byproduct", item_id=byproduct.id},
            sprite=byproduct.proto.sprite, style="flib_slot_button_red_small", number=amount,
            tooltip=tooltip, mouse_button_filter={"left-and-right"}}

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

        local style, enabled, note = "flib_slot_button_green_small", true, nil
        local satisfaction_line = ""  ---@type LocalisedString

        if ingredient.proto.type == "entity" then
            style = "flib_slot_button_transparent_small"
            enabled = false
            note = {"fp.raw_ore"}

        elseif metadata.ingredient_satisfaction and ingredient.amount > 0 then
            local satisfaction_percentage = (ingredient.satisfied_amount / ingredient.amount) * 100
            local formatted_percentage = util.format.number(satisfaction_percentage, 3)

            -- We use the formatted percentage here because it smooths out the number to 3 places
            local satisfaction = tonumber(formatted_percentage)
            if satisfaction <= 0 then
                style = "flib_slot_button_red_small"
            elseif satisfaction < 100 then
                style = "flib_slot_button_yellow_small"
            end  -- else, it stays green

            satisfaction_line = {"", "\n", (formatted_percentage .. "%"), " ", {"fp.satisfied"}}
        end

        local name_line = (note == nil) and {"fp.tt_title", ingredient.proto.localised_name}
            or {"fp.tt_title_with_note", ingredient.proto.localised_name, note}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tutorial_tt = (enabled) and metadata.ingredient_tutorial_tt or ""
        local tooltip = {"", name_line, number_line, satisfaction_line, tutorial_tt}

        parent_flow.add{type="sprite-button", tags={mod="fp", on_gui_click="act_on_line_ingredient",
            floor_id=line.parent.id, line_id=line.id, class="Ingredient", item_id=ingredient.id},
            sprite=ingredient.proto.sprite, style=style, number=amount, tooltip=tooltip,
            enabled=enabled, mouse_button_filter={"left-and-right"}}

        ::skip_ingredient::
    end

    if not line.subfloor and line.machine.fuel then builders.fuel(line, parent_flow, metadata) end
end

-- This is not a standard builder function, as it gets called indirectly by the ingredient builder
function builders.fuel(line, parent_flow, metadata)
    local fuel = line.machine.fuel

    local amount, number_tooltip = view_state.process_item(metadata.view_state_metadata, fuel, nil, line.machine.count)
    if amount == -1 then return end  -- an amount of -1 means it was below the margin of error

    local satisfaction_line = ""  ---@type LocalisedString
    if metadata.ingredient_satisfaction and fuel.amount > 0 then
        local satisfaction_percentage = (fuel.satisfied_amount / fuel.amount) * 100
        local formatted_percentage = util.format.number(satisfaction_percentage, 3)
        satisfaction_line = {"", "\n", (formatted_percentage .. "%"), " ", {"fp.satisfied"}}
    end

    local name_line = {"fp.tt_title_with_note", fuel.proto.localised_name, {"fp.pl_fuel", 1}}
    local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
    local tooltip = {"", name_line, number_line, satisfaction_line, metadata.fuel_tutorial_tt}

    parent_flow.add{type="sprite-button", sprite=fuel.proto.sprite, style="flib_slot_button_cyan_small",
        tags={mod="fp", on_gui_click="act_on_line_fuel", floor_id=line.parent.id, line_id=line.id},
        number=amount, tooltip=tooltip, mouse_button_filter={"left-and-right"}}
end

function builders.line_comment(line, parent_flow, _)
    local relevant_line = (line.class == "Floor") and line.first or line
    local textfield_comment = parent_flow.add{type="textfield", text=(relevant_line.comment or ""),
        tags={mod="fp", on_gui_text_changed="line_comment", line_id=line.id}}
    textfield_comment.style.width = 250
    util.gui.setup_textfield(textfield_comment)
end


local all_production_columns = {
    -- name, caption, tooltip, alignment
    {name="done", caption="", tooltip={"fp.column_done_tt"}, alignment="center"},
    {name="recipe", caption={"fp.pu_recipe", 1}, alignment="left"},
    {name="percentage", caption="%", tooltip={"fp.column_percentage_tt"}, alignment="center"},
    --{name="machine", caption={"fp.pu_machine", 1}, alignment="left"},
    --{name="beacon", caption={"fp.pu_beacon", 1}, alignment="left"},
    {name="power", caption={"fp.u_power"}, alignment="center"},
    {name="pollution", caption={"fp.pollution"}, alignment="center"},
    --{name="products", caption={"fp.pu_product", 2}, alignment="left"},
    --{name="byproducts", caption={"fp.pu_byproduct", 2}, alignment="left"},
    --{name="ingredients", caption={"fp.pu_ingredient", 2}, alignment="left"},
    {name="line_comment", caption={"fp.column_comment"}, alignment="left"}
}

local function refresh_production_table(player)
    local main_elements = util.globals.main_elements(player)
    if main_elements.main_frame == nil then return end

    -- Determine the column_count first, because not all columns are nessecarily shown
    local preferences = util.globals.preferences(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    local production_table_elements = main_elements.production_table
    local subfactory_valid = (factory and factory.valid)
    local any_lines_present = (subfactory_valid) and (floor:count() > 0) or false

    local scroll_pane_production = production_table_elements.production_scroll_pane
    scroll_pane_production.visible = (subfactory_valid and any_lines_present)
    if not subfactory_valid then return end
    scroll_pane_production.clear()

    local production_columns = {}
    for _, column_data in ipairs(all_production_columns) do
        -- Explicit comparison needed here, as both true and nil columns should be shown
        if preferences[column_data.name .. "_column"] ~= false then
            table.insert(production_columns, column_data)
        end
    end

    local table_production = scroll_pane_production.add{type="table", column_count=(#production_columns+1),
        style="fp_table_production"}
    table_production.style.horizontal_spacing = 16
    table_production.style.padding = {6, 0, 0, 12}

    -- Column headers
    for index, column_data in ipairs(production_columns) do
        local caption = (column_data.tooltip) and {"fp.info_label", column_data.caption} or column_data.caption
        local label_column = table_production.add{type="label", caption=caption, tooltip=column_data.tooltip,
            style="bold_label"}
        label_column.style.bottom_margin = 6
        table_production.style.column_alignments[index] = column_data.alignment
    end

    -- Add pushers in both directions to make sure the table takes all available space
    local flow_pusher = table_production.add{type="flow"}
    flow_pusher.add{type="empty-widget", style="flib_vertical_pusher"}
    flow_pusher.add{type="empty-widget", style="flib_horizontal_pusher"}

    -- Generates some data that is relevant to several different builders
    local metadata = generate_metadata(player, factory)

    -- Production lines
    local function render_lines(render_floor, indent)
        for line in render_floor:iterator() do
            for _, column_data in ipairs(production_columns) do
                local flow = table_production.add{type="flow", direction="horizontal"}
                builders[column_data.name](line, flow, metadata, indent)
            end
            table_production.add{type="empty-widget"}

            if line.class == "Floor" and metadata.fold_out_subfloors then render_lines(line, indent + 1) end
        end
    end

    render_lines(floor, 0)
end

local function build_production_table(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.production_table = {}

    -- Can't do much here since the table needs to be destroyed on refresh anyways
    local flow_production_table = main_elements.production_box.production_table_flow
    local scroll_pane_production = flow_production_table.add{type="scroll-pane", direction="vertical",
        style="flib_naked_scroll_pane_no_padding"}
    scroll_pane_production.style.horizontally_stretchable = true
    scroll_pane_production.style.vertically_stretchable = false
    main_elements.production_table["production_scroll_pane"] = scroll_pane_production

    refresh_production_table(player)
end


-- ** EVENTS **
local listeners = {}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_production_table(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {production_table=true, production_detail=true, production=true, subfactory=true, all=true}
        if triggers[event.trigger] then refresh_production_table(player) end
    end)
}

return { listeners }
