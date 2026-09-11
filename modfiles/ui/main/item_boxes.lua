local TLProduct = require("backend.data.TLProduct")
local SimpleItem = require("backend.data.SimpleItem")

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param category ItemCategory
---@param column_count integer
local function build_item_box(player, category, column_count)
    local item_boxes_elements = lib.globals.main_elements(player).item_boxes

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

---@class HandleItemBoxClickTags
---@field item_category ItemCategory
---@field item_id ObjectID
---@field item_index integer?
---@field context "item_boxes"
---@field flags GUIActionFlags

---@param player LuaPlayer
---@param factory Factory?
---@param show_floor_items boolean
---@param item_category ItemCategory
---@param tooltips table
---@return integer row_count
local function refresh_item_box(player, factory, show_floor_items, item_category, tooltips)
    local item_boxes_elements = lib.globals.main_elements(player).item_boxes  ---@as table<string, LuaGuiElement>

    local table_items = item_boxes_elements[item_category .. "_item_table"]
    table_items.clear()

    local valid_factory = (factory ~= nil and factory.valid)
    item_boxes_elements["ingredient_combinator_button"].visible = (valid_factory and item_category == "ingredient")
    if not valid_factory then return 0 end  ---@cast factory -nil

    local table_item_count = 0
    local current_floor = lib.context.get(player, "Floor")  ---@as Floor
    local floor = (show_floor_items) and current_floor or factory.top_floor
    local wrong_floor = (not show_floor_items and current_floor.level > 1)

    if item_category == "product" and (not show_floor_items or floor.level == 1) then
        for product in factory:iterator() do  ---@cast product.proto FPItemPrototype
            local style = "fflib_slot_button_default"

            local amount, number_tooltip = nil, nil
            local required_amount = product:get_required_amount()

            local special = (product.proto.type == "entity" and product.proto.special)
            local flags = {
                top_level = true,
                product = true,
                special = special,
                cursor = (product.proto.type ~= "entity"),
                archived = factory.archived,
                wrong_floor = wrong_floor,
                ingredient_only = product.proto.ingredient_only,
                move_left = (product.previous ~= nil),
                move_right = (product.next ~= nil),
                factoriopedia = (lib.get_factoriopedia_proto(product.proto) ~= nil)
            }

            if flags.special then
                amount = lib.format.button_number(required_amount)
                number_tooltip = lib.format.special_tooltip(product.proto.name, required_amount)
            else
                amount, number_tooltip = item_views.process_item(player, product.proto, required_amount, nil)
                if amount == -1 then goto skip_product end  -- an amount of -1 means it was below the margin of error
            end

            local satisfaction_line, percentage_string = lib.gui.calculate_satisfaction(
                product.amount, required_amount)

            if percentage_string == "0" then style = "fflib_slot_button_red"
            elseif percentage_string == "100" then style = "fflib_slot_button_green"
            else style = "fflib_slot_button_yellow" end

            local tooltip = {"", {"fp.tt_title", product.proto.localised_name}, "\n", number_tooltip,
                satisfaction_line}

            ---@type HandleItemBoxClickTags
            local tags = {mod="fp", on_gui_click="act_on_item_box", item_category=item_category, item_id=product.id,
                on_gui_hover="set_tooltip", context="item_boxes", flags=flags}
            local button = table_items.add{type="sprite-button", tags=tags--[[@as Tags]], number=amount, style=style,
                sprite=product.proto.sprite, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
            tooltips.item_boxes[button.index] = tooltip
            table_item_count = table_item_count + 1

            ::skip_product::
        end

        local tooltip = {"fp.add_top_level_product", {"fp.pl_" .. item_category, 1}}
        ---@class AddTopLevelItemTags
        ---@field item_category ItemCategory
        local tags = {mod="fp", on_gui_click="add_top_level_item", item_category=item_category}
        local button = table_items.add{type="sprite-button", tags=tags, sprite="utility/add",
            enabled=(not factory.archived), tooltip=tooltip, style="fp_sprite-button_inset",
            mouse_button_filter={"left"}}
        button.style.padding = 4
        button.style.margin = 4
        table_item_count = table_item_count + 1
    else
        for index, item in pairs(floor[item_category .. "s"]) do
            local amount, number_tooltip = nil, nil

            local special = (item.proto.type == "entity" and item.proto.special)
            local flags = {
                top_level = false,
                product = (item_category == "product"),
                special = special,
                cursor = (item.proto.type ~= "entity"),
                archived = factory.archived,
                wrong_floor = wrong_floor,
                ingredient_only = item.proto.ingredient_only,
                byproduct = (item_category == "byproduct"),
                factoriopedia = (lib.get_factoriopedia_proto(item.proto) ~= nil)
            }

            if flags.special then
                amount = lib.format.button_number(item.amount)
                number_tooltip = lib.format.special_tooltip(item.proto.name, item.amount)
            else
                amount, number_tooltip = item_views.process_item(player, item.proto, item.amount, nil)
                if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error
            end

            local style = (item_category == "byproduct") and "fflib_slot_button_red" or "fflib_slot_button_default"
            local tooltip = {"", {"fp.tt_title", item.proto.localised_name}, "\n", number_tooltip}

            ---@type HandleItemBoxClickTags
            local tags = {mod="fp", on_gui_click="act_on_item_box", item_category=item_category, item_id=item.id,
                item_index=index, on_gui_hover="set_tooltip", context="item_boxes", flags=flags}
            local button = table_items.add{type="sprite-button", tags=tags--[[@as Tags]], number=amount, style=style,
                sprite=item.proto.sprite, mouse_button_filter={"left-and-right"}, raise_hover_events=true}
            tooltips.item_boxes[button.index] = tooltip
            table_item_count = table_item_count + 1

            ::skip_item::
        end
    end

    return math.ceil(table_item_count / table_items.column_count)
end


---@param player LuaPlayer
---@param tags AddTopLevelItemTags
---@param event EventData.on_gui_click
local function handle_item_add(player, tags, event)
    local factory = lib.context.get(player, "Factory")  ---@as Factory

    if event.shift then  -- paste
        local dummy_product = TLProduct.init()
        lib.clipboard.dummy_paste(player, dummy_product, factory)
    elseif player.is_cursor_blueprint() then  -- import blueprint entities
        local blueprint = player.cursor_record or player.cursor_stack
        local timescale = lib.globals.preferences(player).timescale

        for _, entity in pairs(blueprint--[[@cast -nil]].cost_to_build) do
            local proto = prototyper.util.find("items", entity.name, "item")  ---@as FPItemPrototype
            local existing_item = factory:find({proto=proto})

            local amount = entity.count / timescale
            if existing_item then
                existing_item:add_required_amount(amount)
            else
                local product = TLProduct.init(proto)  -- defined_by = "amount"
                product.required_amount = amount
                factory:insert(product)
            end
        end

        solver.update(player)
        lib.gui.run_refresh(player, "factory")
    else
        lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=nil, item_category=tags.item_category}})
    end
end

---@param player LuaPlayer
---@param tags HandleItemBoxClickTags
---@param action string
local function handle_item_button_click(player, tags, action)
    local show_floor_items = lib.globals.preferences(player).show_floor_items

    local item
    if tags.item_id then
        item = OBJECT_INDEX[tags.item_id]  ---@as TLProduct
    else
        local floor  ---@type Floor
        if show_floor_items then floor = lib.context.get(player, "Floor")  ---@as Floor
        else floor = lib.context.get(player, "Factory")--[[@as Factory]].top_floor end
        -- Need to get items from the right floor depending on display settings
        item = floor[tags.item_category .. "s"][tags.item_index]  ---@as TLProduct
    end

    if action == "add_recipe" then
        local production_type = (tags.item_category == "byproduct") and "consume" or "produce"
        lib.gui.open_dialog(player, {dialog="recipe", modal_data={production_type=production_type,
            category_id=item.proto.category_id, product_id=item.proto.id}})

    elseif action == "edit" then
        lib.gui.open_dialog(player, {dialog="picker",
            modal_data={item_id=item.id, item_category=tags.item_category}})

    elseif action == "move_left" or action == "move_right" then
        local direction = (action == "move_left") and "previous" or "next"
        item.parent:shift(item, direction, 1)
        lib.gui.run_refresh(player, "item_boxes")

    elseif action == "copy" then
        local copyable_item = (item.class == "TLProduct") and item
            or SimpleItem.init(nil, item.proto--[[@as FPItemPrototype]], item.amount)
        lib.clipboard.copy(player, copyable_item)

    elseif action == "paste" then
        lib.clipboard.paste(player, item)

    elseif action == "delete" or action == "cut" then
        if action == "cut" then
            lib.clipboard.copy(player, item, true)
        end

        lib.context.get(player, "Factory")--[[@as Factory]]:remove(item)
        solver.update(player)
        lib.gui.run_refresh(player, "all")  -- make sure product icons are updated

    elseif action == "pipette" then
        lib.cursor.pipette_item(player, item.proto--[[@as FPItemPrototype]])

    elseif action == "put_into_combinator" then
        local amount = (item.class == "TLProduct") and item:get_required_amount() or item.amount
        lib.cursor.put_into_combinator(player, item.proto--[[@as FPItemPrototype]], amount)

    elseif action == "factoriopedia" then
        local proto = item.proto  ---@as FPItemPrototype
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(proto))
    end
end


---@param player LuaPlayer
local function put_ingredients_into_cursor(player, _, _)
    local preferences = lib.globals.preferences(player)
    local relevant_floor = (preferences.show_floor_items) and lib.context.get(player, "Floor")--[[@as Floor]]
        or lib.context.get(player, "Factory")--[[@as Factory]].top_floor

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
    lib.cursor.set_item_combinator(player, ingredient_filters)

    main_dialog.toggle(player)
end


---@param player LuaPlayer
local function refresh_item_boxes(player)
    local player_table = lib.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end

    local visible = not player_table.ui_state.districts_view
    main_elements.item_boxes.horizontal_flow.visible = visible
    if not visible then return end

    local factory = lib.context.get(player, "Factory")  ---@as Factory?
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

---@param player LuaPlayer
local function build_item_boxes(player)
    local main_elements = lib.globals.main_elements(player)
    main_elements.item_boxes = {}

    local parent_flow = main_elements.flows.right_vertical
    local flow_horizontal = parent_flow.add{type="flow", direction="horizontal"}
    flow_horizontal.style.horizontal_spacing = MAGIC_NUMBERS.frame_spacing
    main_elements.item_boxes["horizontal_flow"] = flow_horizontal

    local products_per_row = lib.globals.preferences(player).products_per_row
    build_item_box(player, "product", products_per_row)
    build_item_box(player, "byproduct", products_per_row)
    build_item_box(player, "ingredient", products_per_row * 2)

    refresh_item_boxes(player)
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

---@param flags GUIActionFlags
---@return boolean?
local function show_add_recipe(flags)
    return flags.top_level or not flags.product or flags.special
end

---@param flags GUIActionFlags
---@return boolean?
local function is_top_level_product(flags)
    return flags.top_level
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_move_left(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    if not flags.move_left then return false, {"fp.item_already_leftmost"} end
    return true
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_move_right(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    if not flags.move_right then return false, {"fp.item_already_rightmost"} end
    return true
end

listeners.gui = {
    on_gui_click = {
        {
            name = "add_top_level_item",
            handler = handle_item_add
        },
        {
            name = "act_on_item_box",
            actions_table = {
                add_recipe = {shortcut="left", core=true, show=show_add_recipe, enable=lib.actions.can_add_recipe},
                edit = {shortcut="control-left", core=true, show=is_top_level_product, enable=lib.actions.can_edit_factory},
                delete = {input="delete", show=is_top_level_product, enable=lib.actions.can_edit_factory},
                move_left = {show=is_top_level_product, enable=can_move_left},
                move_right = {show=is_top_level_product, enable=can_move_right},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", show=is_top_level_product, enable=lib.actions.can_edit_factory},
                cut = {shortcut="control-right", show=is_top_level_product, enable=lib.actions.can_edit_factory},
                pipette = {input="pipette", enable=lib.actions.can_pipette},
                put_into_combinator = {input="put_into_combinator", enable=lib.actions.can_put_into_combinator},
                factoriopedia = {shortcut="alt-left", enable=lib.actions.can_open_factoriopedia}
            },
            handler = handle_item_button_click
        },
        {
            name = "ingredients_to_combinator",
            timeout = 20,
            handler = put_ingredients_into_cursor
        }
    }
}  ---@as GUIListenerDefinition

listeners.player = {
    build_gui_element = function(player, event)
        ---@cast event BuildGUIElementEventData
        if event.trigger == "main_dialog" then
            build_item_boxes(player)
        end
    end,
    refresh_gui_element = function(player, event)
        ---@cast event RefreshGUIElementEventData
        local triggers = {item_boxes=true, production=true, factory=true, all=true}
        if triggers[event.trigger] then refresh_item_boxes(player) end
    end
}

return { listeners }
