local Product = require("backend.data.Product")

-- ** LOCAL UTIL **
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

    local valid_factory = (factory ~= nil and factory.valid)
    item_boxes_elements["ingredient_combinator_button"].visible = (valid_factory and item_category == "ingredient")
    if not valid_factory then return 0 end

    local table_item_count = 0
    local floor = (show_floor_items) and util.context.get(player, "Floor") or factory.top_floor

    if item_category == "product" and (not show_floor_items or floor.level == 1) then
        for product in factory:iterator() do
            local action = (product.proto.special) and "act_on_top_level_special_product" or "act_on_top_level_product"
            local style = "fflib_slot_button_default"

            local amount, number_tooltip = nil, nil
            local required_amount = product:get_required_amount()

            if product.proto.type == "entity" and product.proto.special then
                number_tooltip = util.format.special_tooltip(product.proto.name, required_amount)
            else
                amount, number_tooltip = item_views.process_item(player, product, required_amount, nil)
                if amount == -1 then goto skip_product end  -- an amount of -1 means it was below the margin of error
            end

            --local satisfaction_line, percentage_string = nil, nil
            local satisfaction_line, percentage_string = util.gui.calculate_satisfaction(
                product.amount, required_amount)

            if percentage_string == "0" then style = "fflib_slot_button_red"
            elseif percentage_string == "100" then style = "fflib_slot_button_green"
            else style = "fflib_slot_button_yellow" end

            local tooltip = {"", {"fp.tt_title", product.proto.localised_name}, "\n", number_tooltip,
                satisfaction_line, "\n", MODIFIER_ACTIONS[action].tooltip}

            local button = table_items.add{type="sprite-button", number=amount, style=style,
                tags={mod="fp", on_gui_click=action, item_category=item_category, item_id=product.id,
                on_gui_hover="set_tooltip", context="item_boxes"}, sprite=product.proto.sprite,
                mouse_button_filter={"left-and-right"}, raise_hover_events=true}
            tooltips.item_boxes[button.index] = tooltip
            table_item_count = table_item_count + 1

            ::skip_product::
        end

        local button = table_items.add{type="sprite-button", sprite="utility/add", enabled=(not factory.archived),
            tags={mod="fp", on_gui_click="add_top_level_item", item_category=item_category},
            tooltip={"", {"fp.add"}, " ", {"fp.pl_" .. item_category, 1}, "\n", {"fp.shift_to_paste"}},
            style="fp_sprite-button_inset", mouse_button_filter={"left"}}
        button.style.padding = 4
        button.style.margin = 4
        table_item_count = table_item_count + 1
    else
        for index, item in pairs(floor[item_category .. "s"]) do
            local action = "act_on_floor_" .. item_category
            local amount, number_tooltip = nil, nil

            if item.proto.type == "entity" and item.proto.special then
                action = "act_on_floor_special"
                number_tooltip = util.format.special_tooltip(item.proto.name, item.amount)
            else
                amount, number_tooltip = item_views.process_item(player, item, nil, nil)
                if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error
            end

            local style = (item_category == "byproduct") and "fflib_slot_button_red" or "fflib_slot_button_default"
            local tooltip = {"", {"fp.tt_title", item.proto.localised_name}, "\n", number_tooltip,
                "\n", MODIFIER_ACTIONS[action].tooltip}

            local button = table_items.add{type="sprite-button", number=amount, style=style, sprite=item.proto.sprite,
                tags={mod="fp", on_gui_click=action, item_category=item_category, item_id=item.id, item_index=index,
                on_gui_hover="set_tooltip", context="item_boxes"}, mouse_button_filter={"left-and-right"},
                raise_hover_events=true}
            tooltips.item_boxes[button.index] = tooltip
            table_item_count = table_item_count + 1

            ::skip_item::
        end
    end

    return math.ceil(table_item_count / table_items.column_count)
end


local function handle_item_add(player, tags, event)
    if event.shift then  -- paste
        local factory = util.context.get(player, "Factory")  --[[@as Factory]]
        local dummy_product = Product.initDummy()
        util.clipboard.dummy_paste(player, dummy_product, factory)
    else
        util.gui.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category=tags.item_category}})
    end
end

local function handle_item_button_click(player, tags, action)
    local show_floor_items = util.globals.preferences(player).show_floor_items

    local item = nil
    if tags.item_id then
        item = OBJECT_INDEX[tags.item_id] --[[@as Product]]
    else
        -- Need to get items from the right floor depending on display settings
        local floor = (show_floor_items) and util.context.get(player, "Floor")
            or util.context.get(player, "Factory").top_floor
        item = floor[tags.item_category .. "s"][tags.item_index] --[[@as Product]]
    end

    if action == "add_recipe" then
        local floor = util.context.get(player, "Floor")  --[[@as Floor]]
        if floor.level > 1 and not show_floor_items then
            local message = {"fp.error_no_main_recipe_on_subfloor"}
            util.messages.raise(player, "error", message, 1)
        else
            local production_type = (tags.item_category == "byproduct") and "consume" or "produce"
            util.gui.open_dialog(player, {dialog="recipe", modal_data={production_type=production_type,
                category_id=item.proto.category_id, product_id=item.proto.id}})
        end

    elseif action == "edit" then
        util.gui.open_dialog(player, {dialog="picker",
            modal_data={item_id=item.id, item_category=tags.item_category}})

    elseif action == "move_left" or action == "move_right" then
        local direction = (action == "move_left") and "previous" or "next"
        item.parent:shift(item, direction, 1)
        util.gui.run_refresh(player, "item_boxes")

    elseif action == "copy" then
        local copyable_item = {class="SimpleItem", proto=item.proto, amount=item.amount}
        util.clipboard.copy(player, copyable_item)

    elseif action == "paste" then
        util.clipboard.paste(player, item)

    elseif action == "delete" then
        util.context.get(player, "Factory"):remove(item)
        solver.update(player)
        util.gui.run_refresh(player, "all")  -- make sure product icons are updated

    elseif action == "add_to_cursor" then
        local amount = (item.class == "Product") and item:get_required_amount() or item.amount
        if not item.proto.simplified then
            util.cursor.handle_item_click(player, item.proto --[[@as FPItemPrototype]], amount)
        end

    elseif action == "factoriopedia" then
        local name = (item.proto.temperature) and item.proto.base_name or item.proto.name
        player.open_factoriopedia_gui(prototypes[item.proto.type][name])
    end
end


local function put_ingredients_into_cursor(player, _, _)
    local preferences = util.globals.preferences(player)
    local relevant_floor = (preferences.show_floor_items) and util.context.get(player, "Floor")
        or util.context.get(player, "Factory").top_floor  --[[@as Floor]]

    local ingredient_filters = {}
    for _, ingredient in pairs(relevant_floor.ingredients) do
        local amount = ingredient.amount * preferences.timescale
        if amount > MAGIC_NUMBERS.margin_of_error and ingredient.proto.type ~= "entity" then
            table.insert(ingredient_filters, {
                type = ingredient.proto.type,
                name = ingredient.proto.base_name or ingredient.proto.name,
                quality = "normal",
                comparator = "=",
                count = math.ceil(amount - MAGIC_NUMBERS.margin_of_error)
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
                move_left = {limitations={archive_open=false}},
                move_right = {limitations={archive_open=false}},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", limitations={archive_open=false}},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_top_level_special_product",
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false}, show=true},
                edit = {shortcut="control-left", limitations={archive_open=false}, show=true},
                delete = {shortcut="control-right", limitations={archive_open=false}},
                move_left = {limitations={archive_open=false}},
                move_right = {limitations={archive_open=false}}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_product",
            actions_table = {
                copy = {shortcut="shift-right"},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_byproduct",
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false, matrix_active=true}, show=true},
                copy = {shortcut="shift-right"},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_ingredient",
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false}, show=true},
                copy = {shortcut="shift-right"},
                add_to_cursor = {shortcut="alt-right"},
                factoriopedia = {shortcut="alt-left"}
            },
            handler = handle_item_button_click
        },
        {
            name = "act_on_floor_special",
            actions_table = {
                add_recipe = {shortcut="left", limitations={archive_open=false}, show=true}
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

listeners.player = {
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
