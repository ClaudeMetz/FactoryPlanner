local Product = require("backend.data.Product")

-- ** LOCAL UTIL **
local function add_recipe(player, item_category, item_proto)
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]
    if floor.level > 1 then
        local message = {"fp.error_recipe_wrong_floor", {"fp.pu_" .. item_category, 1}}
        util.messages.raise(player, "error", message, 1)
    else
        local production_type = (item_category == "byproduct") and "consume" or "produce"
        util.raise.open_dialog(player, {dialog="recipe", modal_data={production_type=production_type,
            category_id=item_proto.category_id, product_id=item_proto.id}})
    end
end

local function build_item_box(player, category, column_count)
    local item_boxes_elements = util.globals.main_elements(player).item_boxes

    local window_frame = item_boxes_elements.horizontal_flow.add{type="frame", direction="vertical",
        style="inside_shallow_frame"}
    window_frame.style.top_padding = 6
    window_frame.style.bottom_padding = MAGIC_NUMBERS.frame_spacing

    local title_flow = window_frame.add{type="flow", direction="horizontal"}
    title_flow.style.vertical_align = "center"

    local label = title_flow.add{type="label", caption={"fp.pu_" .. category, 2}, style="caption_label"}
    label.style.left_padding = MAGIC_NUMBERS.frame_spacing
    label.style.bottom_margin = 4

    if category == "ingredient" then
        local button_combinator = title_flow.add{type="sprite-button", sprite="item/constant-combinator",
            tooltip={"fp.ingredients_to_combinator_tt"}, tags={mod="fp", on_gui_click="ingredients_to_combinator"},
            visible=false, mouse_button_filter={"left"}}
        button_combinator.style.size = 24
        button_combinator.style.padding = -2
        button_combinator.style.left_margin = 4
        item_boxes_elements["ingredient_combinator_button"] = button_combinator
    end

    local scroll_pane = window_frame.add{type="scroll-pane", style="fp_scroll-pane_slot_table"}
    scroll_pane.style.maximal_height = MAGIC_NUMBERS.item_box_max_rows * MAGIC_NUMBERS.item_button_size
    scroll_pane.style.horizontally_stretchable = false
    scroll_pane.style.vertically_stretchable = false

    local item_frame = scroll_pane.add{type="frame", style="slot_button_deep_frame"}
    item_frame.style.width = column_count * MAGIC_NUMBERS.item_button_size

    local table_items = item_frame.add{type="table", column_count=column_count, style="filter_slot_table"}
    item_boxes_elements[category .. "_item_table"] = table_items
end

local function refresh_item_box(player, factory, floor, item_category)
    local item_boxes_elements = util.globals.main_elements(player).item_boxes

    local table_items = item_boxes_elements[item_category .. "_item_table"]
    table_items.clear()

    if not factory or not factory.valid then
        item_boxes_elements["ingredient_combinator_button"].visible = false
        return 0
    end

    local table_item_count = 0
    local metadata = view_state.generate_metadata(player, factory)
    local default_style = (item_category == "byproduct") and "flib_slot_button_red" or "flib_slot_button_default"

    local shows_floor_items = (floor.parent.class ~= "Factory")
    local action = (shows_floor_items) and ("act_on_floor_item") or ("act_on_top_level_" .. item_category)
    local tutorial_tt = (util.globals.preferences(player).tutorial_mode)
        and util.actions.tutorial_tooltip(action, nil, player) or nil
    local real_products = (not shows_floor_items and item_category == "product")

    local function build_item(item, index)
        local required_amount = (item.class == "Product") and item:get_required_amount() or nil
        local amount, number_tooltip = view_state.process_item(metadata, item, required_amount, nil)
        if amount == -1 then return end  -- an amount of -1 means it was below the margin of error

        local style = default_style
        local satisfaction_line = ""  ---@type LocalisedString
        if item.class == "Product" and amount ~= nil and amount ~= "0" then
            local satisfied_percentage = (item.amount / required_amount) * 100
            local percentage_string = util.format.number(satisfied_percentage, 3)
            satisfaction_line = {"", "\n", {"fp.bold_label", (percentage_string .. "%")}, " ", {"fp.satisfied"}}

            if satisfied_percentage <= 0 then style = "flib_slot_button_red"
            elseif satisfied_percentage < 100 then style = "flib_slot_button_yellow"
            else style = "flib_slot_button_green" end
        end

        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local name_line, tooltip, enabled = nil, nil, true
        if item.proto.type == "entity" then  -- only relevant to ingredients
            name_line = {"fp.tt_title_with_note", item.proto.localised_name, {"fp.raw_ore"}}
            tooltip = {"", name_line, number_line, satisfaction_line}
            style = "flib_slot_button_transparent"
            enabled = false
        else
            name_line = {"fp.tt_title", item.proto.localised_name}
            tooltip = {"", name_line, number_line, satisfaction_line, tutorial_tt}
        end

        table_items.add{type="sprite-button", tooltip=tooltip, number=amount, style=style, sprite=item.proto.sprite,
            tags={mod="fp", on_gui_click=action, item_category=item_category, item_id=item.id, item_index=index},
            enabled=enabled, mouse_button_filter={"left-and-right"}}
        table_item_count = table_item_count + 1
    end

    if real_products then
        for product in factory:iterator() do
            build_item(product, nil)
        end
    else
        for index, item in floor[item_category .. "s"]:iterator() do
            build_item(item, index)
        end
    end

    if real_products then  -- meaning allow the user to add items of this type
        table_items.add{type="sprite-button", sprite="utility/add", enabled=(not factory.archived),
            tags={mod="fp", on_gui_click="add_top_level_item", item_category=item_category},
            tooltip={"", {"fp.add"}, " ", {"fp.pl_" .. item_category, 1}, "\n", {"fp.shift_to_paste"}},
            style="fp_sprite-button_inset_add_slot", mouse_button_filter={"left"}}
        table_item_count = table_item_count + 1
    end

    if item_category == "ingredient" then
        item_boxes_elements["ingredient_combinator_button"].visible = (table_item_count > 0)
    end

    local table_rows_required = math.ceil(table_item_count / table_items.column_count)
    return table_rows_required
end


local function handle_item_add(player, tags, event)
    if event.shift then  -- paste
        -- Add a temporary item that can then be replaced
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        local product = Product.init({})
        factory:insert(product)
        util.clipboard.paste(player, product)
    else
        util.raise.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category=tags.item_category}})
    end
end

local function handle_item_button_click(player, tags, action)
    local floor = util.context.get(player, "Floor")  --[[@as Floor]]
    local item = (tags.item_id) and OBJECT_INDEX[tags.item_id]
        or floor[tags.item_category .. "s"].items[tags.item_index]

    if action == "add_recipe" then
        add_recipe(player, tags.item_category, item.proto)

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="picker",
            modal_data={item_id=item.id, item_category=tags.item_category}})

    elseif action == "copy" then
        util.clipboard.copy(player, item)

    elseif action == "paste" then
        util.clipboard.paste(player, item)

    elseif action == "delete" then
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        factory:remove(item)
        solver.update(player, factory)
        util.raise.refresh(player, "all", nil)  -- make sure product icons are updated

    elseif action == "specify_amount" then
        -- Set the view state so that the amount shown in the dialog makes sense
        view_state.select(player, "items_per_timescale")
        util.raise.refresh(player, "subfactory", nil)

        local modal_data = {
            title = {"fp.options_item_title", {"fp.pl_ingredient", 1}},
            text = {"fp.options_item_text", item.proto.localised_name},
            submission_handler_name = "scale_subfactory_by_ingredient_amount",
            item_id = item.id,
            fields = {
                {
                    type = "numeric_textfield",
                    name = "item_amount",
                    caption = {"fp.options_item_amount"},
                    tooltip = {"fp.options_subfactory_ingredient_amount_tt"},
                    text = item.amount,
                    width = 140,
                    focus = true
                }
            }
        }
        util.raise.open_dialog(player, {dialog="options", modal_data=modal_data})

    elseif action == "put_into_cursor" then
        local amount = (item.class == "Product") and item:get_required_amount() or item.amount
        util.cursor.add_to_item_combinator(player, item.proto, amount)

    elseif action == "recipebook" then
        util.open_in_recipebook(player, item.proto.type, item.proto.name)
    end
end


local function put_ingredients_into_cursor(player, _, _)
    local show_floor_items = util.globals.preferences(player).show_floor_items
    local relevant_floor = (show_floor_items) and util.context.get(player, "Floor")
        or util.context.get(player, "Factory").top_floor  --[[@as Floor]]

    local ingredients = {}
    for _, ingredient in relevant_floor["ingredients"]:iterator() do
        if ingredient.proto.type == "item" then
            ingredients[ingredient.proto.name] = ingredient.amount
        end
    end

    local success = util.cursor.set_item_combinator(player, ingredients)
    if success then main_dialog.toggle(player) end
end


local function scale_subfactory_by_ingredient_amount(player, options, action)
    if action == "submit" then
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        local item = OBJECT_INDEX[util.globals.modal_data(player).item_id]

        if options.item_amount then
            -- The division is not pre-calculated to avoid precision errors in some cases
            local current_amount, target_amount = item.amount, options.item_amount
            for product in factory:iterator() do
                product.required_amount = product.required_amount * target_amount / current_amount
            end
        end

        solver.update(player, factory)
        util.raise.refresh(player, "subfactory", nil)
    end
end


local function refresh_item_boxes(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local factory = util.context.get(player, "Factory")  --[[@as Factory]]
    local relevant_floor = (player_table.preferences.show_floor_items) and
        util.context.get(player, "Floor") or factory.top_floor
    local prow_count = refresh_item_box(player, factory, relevant_floor, "product")
    local brow_count = refresh_item_box(player, factory, relevant_floor, "byproduct")
    local irow_count = refresh_item_box(player, factory, relevant_floor, "ingredient")

    local maxrow_count = math.max(prow_count, math.max(brow_count, irow_count))
    local actual_row_count = math.min(math.max(maxrow_count, 1), MAGIC_NUMBERS.item_box_max_rows)
    local item_table_height = actual_row_count * MAGIC_NUMBERS.item_button_size

    -- Set the heights for both the visible frame and the scroll pane containing it
    local item_boxes_elements = main_elements.item_boxes
    item_boxes_elements.product_item_table.parent.style.minimal_height = item_table_height
    item_boxes_elements.product_item_table.parent.parent.style.minimal_height = item_table_height
    item_boxes_elements.byproduct_item_table.parent.style.minimal_height = item_table_height
    item_boxes_elements.byproduct_item_table.parent.parent.style.minimal_height = item_table_height
    item_boxes_elements.ingredient_item_table.parent.style.minimal_height = item_table_height
    item_boxes_elements.ingredient_item_table.parent.parent.style.minimal_height = item_table_height
end

local function build_item_boxes(player)
    local main_elements = util.globals.main_elements(player)
    main_elements.item_boxes = {}

    local parent_flow = main_elements.flows.right_vertical
    local flow_horizontal = parent_flow.add{type="flow", direction="horizontal"}
    flow_horizontal.style.horizontal_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.item_boxes["horizontal_flow"] = flow_horizontal

    local products_per_row = util.globals.settings(player).products_per_row
    build_item_box(player, "product", products_per_row)
    build_item_box(player, "byproduct", products_per_row)
    build_item_box(player, "ingredient", products_per_row*2)

    refresh_item_boxes(player)
end


-- ** EVENTS **
local listeners = {}

listeners.gui = {
    on_gui_click = {
        {
            name = "add_top_level_item",
            handler = handle_item_add
        },
        {
            name = "act_on_top_level_product",
            modifier_actions = {
                add_recipe = {"left", {archive_open=false}},
                edit = {"right", {archive_open=false}},
                copy = {"shift-right"},
                paste = {"shift-left", {archive_open=false}},
                delete = {"control-right", {archive_open=false}},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_byproduct",
            modifier_actions = {
                add_recipe = {"left", {archive_open=false, matrix_active=true}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_ingredient",
            modifier_actions = {
                add_recipe = {"left", {archive_open=false}},
                specify_amount = {"right", {archive_open=false}},
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_item",
            modifier_actions = {
                copy = {"shift-right"},
                put_into_cursor = {"alt-left"},
                recipebook = {"alt-right", {recipebook=true}}
            },
            handler = handle_item_button_click
        },
        {
            name = "ingredients_to_combinator",
            timeout = 20,
            handler = put_ingredients_into_cursor
        }
    }
}

listeners.misc = {
    build_gui_element = (function(player, event)
        if event.trigger == "main_dialog" then
            build_item_boxes(player)
        end
    end),
    refresh_gui_element = (function(player, event)
        local triggers = {item_boxes=true, production=true, subfactory=true, all=true}
        if triggers[event.trigger] then refresh_item_boxes(player) end
    end)
}

listeners.global = {
    scale_subfactory_by_ingredient_amount = scale_subfactory_by_ingredient_amount
}

return { listeners }
