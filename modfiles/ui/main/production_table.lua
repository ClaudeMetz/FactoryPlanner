-- ** LOCAL UTIL **
local function generate_metadata(player, factory)
    local preferences = util.globals.preferences(player)
    local tooltips = util.globals.ui_state(player).tooltips
    tooltips.production_table = {}

    local metadata = {
        archive_open = factory.archived,
        matrix_solver_active = (factory.matrix_free_items ~= nil),
        fold_out_subfloors = preferences.fold_out_subfloors,
        round_button_numbers = preferences.round_button_numbers,
        ingredient_satisfaction = preferences.ingredient_satisfaction,
        player = player,
        tooltips = tooltips.production_table,
        district = factory.parent
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

local function format_effects_tooltip(tooltip)
    if #tooltip > 1 then return {"", "\n\n", tooltip}
    else return "" end
end


-- ** BUILDERS **
local builders = {}

function builders.move(line, parent_flow, metadata)
    local function create_move_button(flow, direction, first_subfloor_line)
        local enabled = not (first_subfloor_line or metadata.archive_open)
        if direction == "next" and line.next == nil then enabled = false
        elseif direction == "previous" then
            if line.previous == nil then enabled = false
            elseif line.parent.level > 1 and line.previous == line.parent.first then enabled = false end
        end

        local endpoint = (direction == "next") and {"fp.bottom"} or {"fp.top"}
        local up_down = (direction == "next") and "down" or "up"
        local move_tooltip = (enabled) and {"", {"fp.move_object", {"fp.pl_recipe", 1}, {"fp." .. up_down}},
            {"fp.move_object_instructions", endpoint}} or ""

        local button = flow.add{type="sprite-button", style="fp_sprite-button_move", sprite="fp_arrow_" .. up_down,
            tags={mod="fp", on_gui_click="move_line", direction=direction, line_id=line.id, on_gui_hover="set_tooltip",
            context="production_table"}, enabled=enabled, mouse_button_filter={"left"}, raise_hover_events=true}
        button.style.size = {18, 14}
        button.style.padding = -1
        metadata.tooltips[button.index] = move_tooltip
    end

    local move_flow = parent_flow.add{type="flow", direction="vertical"}
    move_flow.style.vertical_spacing = 0
    move_flow.style.top_padding = 2

    local first_subfloor_line = (line.parent.level > 1 and line.previous == nil)
    create_move_button(move_flow, "previous", first_subfloor_line)
    create_move_button(move_flow, "next", first_subfloor_line)
end

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
    local first_subfloor_line = (line.parent.level > 1 and line.previous == nil)

    local style, enabled, surface_info = nil, true, {""}
    local note = ""  ---@type LocalisedString
    if first_subfloor_line then
        style = "flib_slot_button_transparent_small"
        enabled = false  -- first subfloor line is static
    else
        local surface_compatibility = relevant_line:get_surface_compatibility()
        local line_active = (relevant_line.active and surface_compatibility.overall)
        style = (line_active) and "flib_slot_button_default_small" or "flib_slot_button_red_small"
        note = (relevant_line.active) and "" or {"fp.recipe_inactive"}

        if not surface_compatibility.recipe then
            table.insert(surface_info, {"fp.blocking_condition", {"fp.pl_recipe", 1}})
        end
        if not surface_compatibility.machine then
            table.insert(surface_info, {"fp.blocking_condition", {"fp.pl_machine", 1}})
        end

        if line.class == "Floor" then
            style = (line_active) and "flib_slot_button_blue_small" or "flib_slot_button_purple_small"
            note = {"fp.recipe_subfloor_attached"}

        elseif line.production_type == "consume" then
            style = (line_active) and "flib_slot_button_yellow_small" or "flib_slot_button_orange_small"
            note = {"fp.recipe_consumes_byproduct"}
        end
    end

    local first_line = (note == "") and {"fp.tt_title", recipe_proto.localised_name}
        or {"fp.tt_title_with_note", recipe_proto.localised_name, note}
    local tooltip = {"", first_line, surface_info, format_effects_tooltip(relevant_line.effects_tooltip),
        metadata.recipe_tutorial_tt}
    local button = parent_flow.add{type="sprite-button", enabled=enabled, sprite=recipe_proto.sprite,style=style,
        tags={mod="fp", on_gui_click="act_on_line_recipe", line_id=line.id, on_gui_hover="set_tooltip",
        context="production_table"}, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
    metadata.tooltips[button.index] = tooltip
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


local function add_module_flow(parent_flow, module_set, metadata)
    for module in module_set:iterator() do
        local title_line = (not module.quality_proto.always_show) and {"fp.tt_title", module.proto.localised_name}
            or {"fp.tt_title_with_note", module.proto.localised_name, module.quality_proto.rich_text}
        local number_line = {"", "\n", module.amount, " ", {"fp.pl_module", module.amount}}
        local tooltip = {"", title_line, number_line, format_effects_tooltip(module.effects_tooltip),
            metadata.module_tutorial_tt}

        local button = parent_flow.add{type="sprite-button", sprite=module.proto.sprite, number=module.amount,
            tags={mod="fp", on_gui_click="act_on_line_module", module_id=module.id, on_gui_hover="set_tooltip",
            context="production_table"}, style="flib_slot_button_default_small",
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip
    end
end

function builders.machine(line, parent_flow, metadata)
    parent_flow.style.horizontal_spacing = 2

    if line.class == "Floor" then  -- add a button that shows the total of all machines on the subfloor
        -- Machine count doesn't need any special formatting in this case because it'll always be an integer
        local machine_count = line.machine_count
        local tooltip = {"fp.subfloor_machine_count", machine_count, {"fp.pl_machine", machine_count}}
        parent_flow.add{type="sprite-button", sprite="fp_generic_assembler", style="flib_slot_button_default_small",
        enabled=false, number=machine_count, tooltip=tooltip}
    else
        local machine = line.machine
        local machine_proto = machine.proto
        local count, tooltip_line = util.format.machine_count(machine.amount, metadata.round_button_numbers)

        local machine_limit = machine.limit
        local style, note = "flib_slot_button_default_small", nil
        if not metadata.matrix_solver_active and machine_limit ~= nil then
            if machine.force_limit then
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
        local title_line = (not machine.quality_proto.always_show) and {"fp.tt_title", machine_proto.localised_name}
        or {"fp.tt_title_with_note", machine_proto.localised_name, machine.quality_proto.rich_text}
        local tooltip = {"", title_line, tooltip_line, format_effects_tooltip(machine.effects_tooltip),
            metadata.machine_tutorial_tt}

        local button = parent_flow.add{type="sprite-button", sprite=machine_proto.sprite, number=count,
            tags={mod="fp", on_gui_click="act_on_line_machine", machine_id=machine.id, on_gui_hover="set_tooltip",
            context="production_table"}, style=style, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        if machine:uses_effects() then
            add_module_flow(parent_flow, machine.module_set, metadata)
            local module_set = machine.module_set
            if module_set.module_limit > module_set.module_count then
                local module_tooltip = {"", {"fp.add_machine_module"}, "\n", {"fp.shift_to_paste"}}
                local module_button = parent_flow.add{type="sprite-button", sprite="utility/add",
                    tooltip=module_tooltip, tags={mod="fp", on_gui_click="add_machine_module", machine_id=machine.id},
                    style="fp_sprite-button_inset", mouse_button_filter={"left"},
                    enabled=(not metadata.archive_open)}
                module_button.style.margin = 2
                module_button.style.padding = 4
            end
        end
    end
end

function builders.beacon(line, parent_flow, metadata)
    if line.class == "Floor" or not line.machine:uses_effects() then return end

    local beacon = line.beacon
    if beacon == nil then
        local tooltip = {"", {"fp.add_beacon"}, "\n", {"fp.shift_to_paste"}}
        local button = parent_flow.add{type="sprite-button", sprite="utility/add", tooltip=tooltip,
            tags={mod="fp", on_gui_click="add_line_beacon", line_id=line.id}, style="fp_sprite-button_inset",
            mouse_button_filter={"left"}, enabled=(not metadata.archive_open)}
        button.style.margin = 2
        button.style.padding = 4
    else
        local title_line = (not beacon.quality_proto.always_show) and {"fp.tt_title", beacon.proto.localised_name}
            or {"fp.tt_title_with_note", beacon.proto.localised_name, beacon.quality_proto.rich_text}
        local plural_parameter = (beacon.amount == 1) and 1 or 2  -- needed because the amount can be decimal
        local number_line = {"", "\n", beacon.amount, " ", {"fp.pl_beacon", plural_parameter}}
        if beacon.total_amount then table.insert(number_line, {"", " - ", {"fp.in_total", beacon.total_amount}}) end
        local tooltip = {"", title_line, number_line, format_effects_tooltip(beacon.effects_tooltip),
            metadata.beacon_tutorial_tt}

        local button_beacon = parent_flow.add{type="sprite-button", sprite=beacon.proto.sprite, number=beacon.amount,
            tags={mod="fp", on_gui_click="act_on_line_beacon", beacon_id=beacon.id, on_gui_hover="set_tooltip",
            context="production_table"}, style="flib_slot_button_default_small",
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button_beacon.index] = tooltip

        if beacon.total_amount ~= nil then  -- add a graphical hint that a beacon total is set
            local sprite_overlay = button_beacon.add{type="sprite", sprite="fp_white_square"}
            sprite_overlay.ignored_by_interaction = true
        end

        add_module_flow(parent_flow, line.beacon.module_set, metadata)
    end
end

function builders.power(line, parent_flow, metadata)
    local tooltip = {"", util.format.SI_value(line.power, "W", 5), "\n",
        util.gui.format_emissions(line.emissions, metadata.district)}
    parent_flow.add{type="label", caption=util.format.SI_value(line.power, "W", 3), tooltip=tooltip}
end


local function add_catalysts(flow, line, category, metadata)
    if line.class == "Floor" then return end
    for _, item in pairs(line.recipe_proto.catalysts[category]) do
        local item_proto = prototyper.util.find("items", item.name, item.type)  --[[@as FPItemPrototype]]

        local amount, number_tooltip = item_views.process_item(metadata.player, {proto=item_proto},
            (item.amount * line.production_ratio), line.machine.amount)
        local title_line = {"fp.tt_title_with_note", item_proto.localised_name, {"fp.catalyst"}}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""

        flow.add{type="sprite-button", sprite=item_proto.sprite, number=amount,
            tooltip={"", title_line, number_line}, style="flib_slot_button_blue_small"}
    end
end

function builders.products(line, parent_flow, metadata)
    for index, product in line["products"]:iterator() do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (line.class ~= "Floor") and line.machine.amount or nil
        local amount, number_tooltip = item_views.process_item(metadata.player, product, nil, machine_count)
        if amount == -1 then goto skip_product end  -- an amount of -1 means it was below the margin of error

        local style, note = "flib_slot_button_default_small", nil
        if line.class ~= "Floor" and not metadata.matrix_solver_active then
            if line.priority_product == product.proto then
                style = "flib_slot_button_pink_small"
                note = {"fp.priority_product"}
            end
        end

        local name_line = (note == nil) and {"fp.tt_title", product.proto.localised_name}
            or {"fp.tt_title_with_note", product.proto.localised_name, note}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, metadata.product_tutorial_tt}

        local button = parent_flow.add{type="sprite-button", sprite=product.proto.sprite, style=style,
            tags={mod="fp", on_gui_click="act_on_line_product", line_id=line.id, item_index=index,
            on_gui_hover="set_tooltip", context="production_table"}, number=amount,
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        ::skip_product::
    end

    add_catalysts(parent_flow, line, "products", metadata)
end

function builders.byproducts(line, parent_flow, metadata)
    for index, byproduct in line["byproducts"]:iterator() do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (line.class ~= "Floor") and line.machine.amount or nil
        local amount, number_tooltip = item_views.process_item(metadata.player, byproduct, nil, machine_count)
        if amount == -1 then goto skip_byproduct end  -- an amount of -1 means it was below the margin of error

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", {"fp.tt_title", byproduct.proto.localised_name}, number_line,
            metadata.byproduct_tutorial_tt}

        local button = parent_flow.add{type="sprite-button", sprite=byproduct.proto.sprite,
            tags={mod="fp", on_gui_click="act_on_line_byproduct", line_id=line.id, item_index=index,
            on_gui_hover="set_tooltip", context="production_table"}, number=amount,
            mouse_button_filter={"left-and-right"}, style="flib_slot_button_red_small", raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        ::skip_byproduct::
    end
end

function builders.ingredients(line, parent_flow, metadata)
    for index, ingredient in line["ingredients"]:iterator() do
        -- items/s/machine does not make sense for lines with subfloors, show items/s instead
        local machine_count = (line.class ~= "Floor") and line.machine.amount or nil
        local amount, number_tooltip = item_views.process_item(metadata.player, ingredient, nil, machine_count)
        if amount == -1 then goto skip_ingredient end  -- an amount of -1 means it was below the margin of error

        local style = "flib_slot_button_green_small"
        local satisfaction_line = ""  ---@type LocalisedString

        if ingredient.proto.type == "entity" then
            style = "flib_slot_button_transparent_small"
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

        local name_line = {"fp.tt_title", ingredient.proto.localised_name}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, satisfaction_line, metadata.ingredient_tutorial_tt}

        local button = parent_flow.add{type="sprite-button", sprite=ingredient.proto.sprite, style=style,
            tags={mod="fp", on_gui_click="act_on_line_ingredient", line_id=line.id, item_index=index,
            on_gui_hover="set_tooltip", context="production_table"}, number=amount,
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        metadata.tooltips[button.index] = tooltip

        ::skip_ingredient::
    end

    add_catalysts(parent_flow, line, "ingredients", metadata)

    if line.class ~= "Floor" and line.machine.fuel then builders.fuel(line, parent_flow, metadata) end
end

-- This is not a standard builder function, as it gets called indirectly by the ingredient builder
function builders.fuel(line, parent_flow, metadata)
    local fuel = line.machine.fuel

    local amount, number_tooltip = item_views.process_item(metadata.player, fuel, nil, line.machine.amount)
    if amount == -1 then return end  -- an amount of -1 means it was below the margin of error

    local satisfaction_line = ""  ---@type LocalisedString
    if metadata.ingredient_satisfaction and fuel.amount > 0 then
        local satisfaction_percentage = (fuel.satisfied_amount / fuel.amount) * 100
        local formatted_percentage = util.format.number(satisfaction_percentage, 3)
        satisfaction_line = {"", "\n", (formatted_percentage .. "%"), " ", {"fp.satisfied"}}
    end

    local name_line = {"fp.tt_title_with_note", fuel.proto.localised_name, {"fp.pu_fuel", 1}}
    local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
    local tooltip = {"", name_line, number_line, satisfaction_line, metadata.fuel_tutorial_tt}

    local button = parent_flow.add{type="sprite-button", sprite=fuel.proto.sprite, style="flib_slot_button_cyan_small",
        tags={mod="fp", on_gui_click="act_on_line_fuel", fuel_id=fuel.id, on_gui_hover="set_tooltip",
        context="production_table"},  number=amount, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
    metadata.tooltips[button.index] = tooltip
end

function builders.line_comment(line, parent_flow, _)
    local relevant_line = (line.class == "Floor") and line.first or line
    local textfield_comment = parent_flow.add{type="textfield", text=(relevant_line.comment or ""),
        tags={mod="fp", on_gui_text_changed="line_comment", line_id=line.id}}
    textfield_comment.style.width = 250
    textfield_comment.lose_focus_on_confirm = true
end


local all_production_columns = {
    -- name, caption, tooltip, alignment
    {name="move", caption="", alignment="center"},
    {name="done", caption="", tooltip={"fp.column_done_tt"}, alignment="center"},
    {name="recipe", caption={"fp.pu_recipe", 1}, alignment="center"},
    {name="percentage", caption="% ", tooltip={"fp.column_percentage_tt"}, alignment="center"},
    {name="machine", caption={"fp.pu_machine", 1}, alignment="left"},
    {name="beacon", caption={"fp.pu_beacon", 1}, alignment="left"},
    {name="power", caption={"fp.u_power"}, alignment="center"},
    {name="products", caption={"fp.pu_product", 2}, alignment="left"},
    {name="byproducts", caption={"fp.pu_byproduct", 2}, alignment="left"},
    {name="ingredients", caption={"fp.pu_ingredient", 2}, alignment="left"},
    {name="line_comment", caption={"fp.column_comment"}, alignment="left"}
}

local function refresh_production_table(player)
    local main_elements = util.globals.main_elements(player)
    if main_elements.main_frame == nil then return end

    -- Determine the column_count first, because not all columns are nessecarily shown
    local preferences = util.globals.preferences(player)
    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]

    local factory_valid = (factory and factory.valid)
    local any_lines_present = (factory_valid) and (floor:count() > 0) or false

    local scroll_pane_production = main_elements.production_box.production_scroll_pane
    scroll_pane_production.visible = (factory_valid and any_lines_present) or false
    if not factory_valid then return end
    scroll_pane_production.clear()

    local production_columns = {}
    for _, column_data in ipairs(all_production_columns) do
        -- Explicit preferences comparison needed here, as both true and nil columns should be shown
        -- Some mods might remove all beacons, in which case the column shouldn't be shown at all
        if preferences[column_data.name .. "_column"] ~= false and (next(storage.prototypes.beacons) ~= nil) then
            table.insert(production_columns, column_data)
        end
    end

    local table_production = scroll_pane_production.add{type="table", column_count=(#production_columns+1),
        style="fp_table_production"}
    table_production.style.horizontal_spacing = 12
    table_production.style.padding = {6, 0, 0, 12}

    -- Column headers
    for index, column_data in ipairs(production_columns) do
        local caption = (column_data.tooltip) and {"", column_data.caption, "[img=info]"} or column_data.caption
        local label_column = table_production.add{type="label", caption=caption, tooltip=column_data.tooltip,
            style="bold_label"}
        label_column.style.bottom_margin = 6
        table_production.style.column_alignments[index] = column_data.alignment
    end

    -- Add pusher to make sure the table takes all available space
    table_production.add{type="empty-widget", style="flib_horizontal_pusher"}

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
    -- No building necessary as production_box sets everything up
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
        local triggers = {production_table=true, production_detail=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_production_table(player) end
    end)
}

return { listeners }
