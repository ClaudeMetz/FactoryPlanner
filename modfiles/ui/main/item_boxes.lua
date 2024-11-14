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
    window_frame.style.padding = {4, 12, 12, 12}

    local title_flow = window_frame.add{type="flow", direction="horizontal"}
    title_flow.style.vertical_align = "center"

    local label = title_flow.add{type="label", caption={"fp.pu_" .. category, 2}, style="caption_label"}
    label.style.bottom_margin = 8

    if category == "ingredient" then
        local button_combinator = title_flow.add{type="sprite-button", sprite="item/constant-combinator",
            tooltip={"fp.ingredients_to_combinator_tt"}, tags={mod="fp", on_gui_click="ingredients_to_combinator"},
            visible=false, mouse_button_filter={"left"}}
        button_combinator.style.size = 24
        button_combinator.style.padding = -2
        button_combinator.style.left_margin = 4
        item_boxes_elements["ingredient_combinator_button"] = button_combinator
    end

    local scroll_pane = window_frame.add{type="scroll-pane", style="shallow_scroll_pane"}
    scroll_pane.style.maximal_height = MAGIC_NUMBERS.item_box_max_rows * MAGIC_NUMBERS.item_button_size

    local item_frame = scroll_pane.add{type="frame", style="slot_button_deep_frame"}
    item_frame.style.width = column_count * MAGIC_NUMBERS.item_button_size

    local table_items = item_frame.add{type="table", column_count=column_count, style="filter_slot_table"}
    item_boxes_elements[category .. "_item_table"] = table_items
end

local function refresh_item_box(player, factory, show_floor_items, item_category, tooltips)
    local item_boxes_elements = util.globals.main_elements(player).item_boxes

    local table_items = item_boxes_elements[item_category .. "_item_table"]
    table_items.clear()

    if factory == nil or not factory.valid then
        item_boxes_elements["ingredient_combinator_button"].visible = false
        return 0
    end
    local floor = (show_floor_items) and util.context.get(player, "Floor") or factory.top_floor

    local table_item_count = 0
    local default_style = (item_category == "byproduct") and "flib_slot_button_red" or "flib_slot_button_default"

    local shows_floor_items = (floor.parent.class ~= "Factory")
    local action = (shows_floor_items) and ("act_on_floor_item") or ("act_on_top_level_" .. item_category)
    local action_tooltip = MODIFIER_ACTIONS[action].tooltip
    local real_products = (not shows_floor_items and item_category == "product")

    local function build_item(item, index)
        local required_amount = (item.class == "Product") and item:get_required_amount() or nil
        local amount, number_tooltip = item_views.process_item(player, item, required_amount, nil)
        if amount == -1 then return end  -- an amount of -1 means it was below the margin of error

        local style = default_style
        local satisfaction_line = ""  ---@type LocalisedString
        if item.class == "Product" and amount ~= nil and amount ~= "0" then
            local satisfied_percentage = (item.amount / required_amount) * 100
            local percentage_string = util.format.number(satisfied_percentage, 3)
            satisfaction_line = {"", "\n", {"fp.bold_label", (percentage_string .. "%")}, " ", {"fp.satisfied"}}

            if percentage_string == "0" then style = "flib_slot_button_red"
            elseif percentage_string == "100" then style = "flib_slot_button_green"
            else style = "flib_slot_button_yellow" end
        end

        local name_line = {"fp.tt_title", item.proto.localised_name}
        local number_line = (number_tooltip) and {"", "\n", number_tooltip} or ""
        local tooltip = {"", name_line, number_line, satisfaction_line, "\n", action_tooltip}

        local button = table_items.add{type="sprite-button", number=amount, style=style, sprite=item.proto.sprite,
            tags={mod="fp", on_gui_click=action, item_category=item_category, item_id=item.id, item_index=index,
            on_gui_hover="set_tooltip", context="item_boxes"}, mouse_button_filter={"left-and-right"},
            raise_hover_events=true}
        tooltips.item_boxes[button.index] = tooltip
        table_item_count = table_item_count + 1
    end

    if real_products then
        for product in factory:iterator() do
            build_item(product, nil)
        end
    else
        for index, item in pairs(floor[item_category .. "s"]) do
            build_item(item, index)
        end
    end

    if real_products then  -- meaning allow the user to add items of this type
        local button = table_items.add{type="sprite-button", sprite="utility/add", enabled=(not factory.archived),
            tags={mod="fp", on_gui_click="add_top_level_item", item_category=item_category},
            tooltip={"", {"fp.add"}, " ", {"fp.pl_" .. item_category, 1}, "\n", {"fp.shift_to_paste"}},
            style="fp_sprite-button_inset", mouse_button_filter={"left"}}
        button.style.padding = 4
        button.style.margin = 4
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
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        local dummy_product = Product.init({})
        util.clipboard.dummy_paste(player, dummy_product, factory)
    else
        util.raise.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category=tags.item_category}})
    end
end

local function handle_item_button_click(player, tags, action)
    local item = nil
    if tags.item_id then
        item = OBJECT_INDEX[tags.item_id]
    else
        -- Need to get items from the right floor depending on display settings
        local show_floor_items = util.globals.preferences(player).show_floor_items
        local floor = (show_floor_items) and util.context.get(player, "Floor")
            or util.context.get(player, "Factory").top_floor
        item = floor[tags.item_category .. "s"][tags.item_index]
    end

    if action == "add_recipe" then
        add_recipe(player, tags.item_category, item.proto)

    elseif action == "edit" then
        util.raise.open_dialog(player, {dialog="picker",
            modal_data={item_id=item.id, item_category=tags.item_category}})

    elseif action == "copy" then
        if item.proto.type == "entity" then return end
        util.clipboard.copy(player, item)  -- TODO turn into SimpleItem object

    elseif action == "paste" then
        if item.proto.type == "entity" then return end
        util.clipboard.paste(player, item)

    elseif action == "delete" then
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        factory:remove(item)
        solver.update(player, factory)
        util.raise.refresh(player, "all")  -- make sure product icons are updated

    elseif action == "put_into_cursor" then
        if item.proto.type == "entity" then return end
        local amount = (item.class == "Product") and item:get_required_amount() or item.amount
        local timescale = util.globals.preferences(player).timescale
        util.cursor.add_to_item_combinator(player, item.proto, amount * timescale)

    elseif action == "factoriopedia" then
        if item.proto.type == "entity" then return end
        --util.open_in_factoriopedia(player, item.proto.type, item.proto.name)
    end
end


local function put_ingredients_into_cursor(player, _, _)
    local preferences = util.globals.preferences(player)
    local relevant_floor = (preferences.show_floor_items) and util.context.get(player, "Floor")
        or util.context.get(player, "Factory").top_floor  --[[@as Floor]]

    local ingredient_filters = {}
    for _, ingredient in pairs(relevant_floor.ingredients) do
        local amount = ingredient.amount * preferences.timescale
        if ingredient.proto.type ~= "entity" and amount > MAGIC_NUMBERS.margin_of_error then
            table.insert(ingredient_filters, {
                type = ingredient.proto.type,
                name = ingredient.proto.name,
                quality = "normal",
                comparator = "=",
                count = amount
            })
        end
    end
    util.cursor.set_item_combinator(player, ingredient_filters)

    main_dialog.toggle(player)
end


local function refresh_item_boxes(player)
    local player_table = util.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local visible = not player_table.ui_state.districts_view
    main_elements.item_boxes.horizontal_flow.visible = visible
    if not visible then return end

    local factory = util.context.get(player, "Factory")  --[[@as Factory?]]
    local show_floor_items = player_table.preferences.show_floor_items

    local tooltips = player_table.ui_state.tooltips
    tooltips.item_boxes = {}

    local prow_count = refresh_item_box(player, factory, show_floor_items, "product", tooltips)
    local brow_count = refresh_item_box(player, factory, show_floor_items, "byproduct", tooltips)
    local irow_count = refresh_item_box(player, factory, show_floor_items, "ingredient", tooltips)

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

    local products_per_row = util.globals.preferences(player).products_per_row
    build_item_box(player, "product", products_per_row)
    build_item_box(player, "byproduct", products_per_row)
    build_item_box(player, "ingredient", products_per_row * 2)

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
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false}, show=true},
                edit = {shortcut="control-left", limitations={archive_open=false}, show=true},
                delete = {shortcut="control-right", limitations={archive_open=false}},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                put_into_cursor = {shortcut="alt-right"},
                --factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_byproduct",
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false, matrix_active=true}, show=true},
                copy = {shortcut="shift-right"},
                put_into_cursor = {shortcut="alt-right"},
                --factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_ingredient",
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false}, show=true},
                copy = {shortcut="shift-right"},
                put_into_cursor = {shortcut="alt-right"},
                --factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_item",
            actions_table = {
                copy = {shortcut="shift-right"},
                put_into_cursor = {shortcut="alt-right"},
                --factoriopedia = {shortcut="alt-left"}
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
        local triggers = {item_boxes=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_item_boxes(player) end
    end)
}

return { listeners }
