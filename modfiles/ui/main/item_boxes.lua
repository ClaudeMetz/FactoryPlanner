local FactoryItem = require("backend.data.FactoryItem")
local SimpleItem = require("backend.data.SimpleItem")

local MAX_ROWS = 4
local HORIZONTAL_PADDING = 8

-- ** LOCAL UTIL **
---@param player LuaPlayer
---@param category ItemCategory
local function build_item_box(player, category)
    local item_boxes_elements = lib.globals.main_elements(player).item_boxes

    local window_frame = item_boxes_elements.horizontal_flow.add{type="frame", direction="vertical",
        style="inside_shallow_frame"}
    window_frame.style.horizontally_stretchable = true
    window_frame.style.padding = {2, HORIZONTAL_PADDING, 8, HORIZONTAL_PADDING}

    local centering_flow = window_frame.add{type="flow", direction="horizontal"}
    centering_flow.style.horizontally_stretchable = true
    centering_flow.style.horizontal_spacing = 0

    centering_flow.add{type="empty-widget", style="fflib_horizontal_pusher"}
    local content_flow = centering_flow.add{type="flow", direction="vertical"}
    centering_flow.add{type="empty-widget", style="fflib_horizontal_pusher"}

    local title_flow = content_flow.add{type="flow", direction="horizontal"}
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

    local scroll_pane = content_flow.add{type="scroll-pane", style="shallow_scroll_pane"}
    scroll_pane.style.maximal_height = MAX_ROWS * MAGIC_NUMBERS.item_button_size

    local item_frame = scroll_pane.add{type="frame", style="slot_button_deep_frame"}

    item_boxes_elements[category .. "_item_frame"] = item_frame
end

---@class HandleItemBoxClickTags
---@field item_category ItemCategory
---@field item_id ObjectID?
---@field item_index integer?
---@field context "item_boxes"
---@field flags GUIActionFlags

---@class ItemBoxButton
---@field definition table
---@field tooltip LocalisedString?
---@field is_add_button boolean?
---@field proto FPItemPrototype?

---@param player LuaPlayer
---@param factory Factory?
---@param item_category ItemCategory
---@return ItemBoxButton[]
local function prepare_item_buttons(player, factory, item_category)
    if not factory or not factory.valid then return {} end

    local buttons = {}  ---@type ItemBoxButton[]
    local defined_items = {}  ---@type table<FPItemPrototype, ItemCategory>
    local floor = lib.context.get(player, "Floor")  ---@as Floor

    if floor.level == 1 then
        for item in factory:iterator() do
            defined_items[item.proto] = item.category
        end
    end

    ---@param item SimpleItem
    ---@param index integer
    ---@param target boolean
    local function add_calculated_item(item, index, target)
        local required_amount = item.required_amount or 0
        local part_amount = target and required_amount or (item.amount - required_amount)
        local tolerance = math.max(item.amount, required_amount) * MAGIC_NUMBERS.margin_of_error
        if part_amount <= tolerance and (target or item.amount ~= 0) then return end
        if not target and defined_items[item.proto] == item_category and part_amount == 0 then return end

        local amount, number_tooltip, secondary_amount

        local special = (item.proto.type == "entity" and item.proto.special)
        local flags = {
            top_level = false,
            top_floor = (floor.level == 1),
            can_define_target = lib.availability.can_define_factory_item(item.proto, item_category),
            defined_product = (defined_items[item.proto] == "product"),
            defined_ingredient = (defined_items[item.proto] == "ingredient"),
            product = (item_category == "product"),
            special = special,
            entity = (item.proto.type == "entity"),
            cursor = (item.proto.type ~= "entity"),
            archived = factory.archived,
            simplex = (floor.solver == "simplex"),
            can_produce = lib.availability.has_productive_recipe(item.proto, "produce"),
            can_consume = lib.availability.has_productive_recipe(item.proto, "consume"),
            consume = (item_category == "product"),
            target = target,
            factoriopedia = (lib.get_factoriopedia_proto(item.proto) ~= nil)
        }

        if flags.special then
            amount, number_tooltip = lib.format.special_amount(item.proto.name, part_amount)
        else
            amount, number_tooltip, secondary_amount = item_views.process_item(player, item.proto, part_amount, nil)
            if amount == -1 then return end  -- an amount of -1 means it was below the margin of error
        end

        local name_line = target
            and {"fp.tt_title_with_note", item.proto.localised_name, {"fp.target"}}
            or {"fp.tt_title", item.proto.localised_name}
        local tooltip = {"", name_line, "\n", number_tooltip}

        ---@type HandleItemBoxClickTags
        local tags = {mod="fp", on_gui_click="act_on_item_box", item_category=item_category,
            item_index=index, on_gui_hover="set_tooltip", context="item_boxes", flags=flags}
        local definition = {type="sprite-button", tags=tags--[[@as Tags]], number=amount,
            secondary_number=secondary_amount, sprite=item.proto.sprite,
            style=target and "fflib_slot_button_green" or "fflib_slot_button_default",
            mouse_button_filter={"left-and-right"}, raise_hover_events=true}
        table.insert(buttons, {definition=definition, tooltip=tooltip, proto=item.proto})
    end

    if floor.level == 1 then
        for item in factory:iterator({category=item_category}) do  ---@cast item.proto FPItemPrototype
            local style = "fflib_slot_button_green"

            local amount, number_tooltip, secondary_amount
            local required_amount = item:get_defined_amount()
            local display_amount = required_amount or item.amount

            local special = (item.proto.type == "entity" and item.proto.special)
            local flags = {
                top_level = true,
                product = (item_category == "product"),
                consume = (item_category == "ingredient"),
                special = special,
                entity = (item.proto.type == "entity"),
                cursor = (item.proto.type ~= "entity"),
                archived = factory.archived,
                simplex = (floor.solver == "simplex"),
                can_produce = lib.availability.has_productive_recipe(item.proto, "produce"),
                can_consume = lib.availability.has_productive_recipe(item.proto, "consume"),
                move_left = (factory:find({category=item_category}, item.previous, "previous") ~= nil),
                move_right = (factory:find({category=item_category}, item.next, "next") ~= nil),
                factoriopedia = (lib.get_factoriopedia_proto(item.proto) ~= nil)
            }

            if flags.special then
                amount, number_tooltip = lib.format.special_amount(item.proto.name, display_amount)
            else
                amount, number_tooltip, secondary_amount = item_views.process_item(player, item.proto,
                    display_amount, nil)
                if amount == -1 then goto skip_item end  -- an amount of -1 means it was below the margin of error
            end

            if not item.active then
                style = "fflib_slot_button_red"
            elseif required_amount ~= nil then
                local difference = item.amount - required_amount
                local tolerance = math.max(item.amount, required_amount) * MAGIC_NUMBERS.margin_of_error
                local shortfall = difference < -tolerance
                style = shortfall and "fflib_slot_button_yellow" or "fflib_slot_button_green"
            end

            local status_line = (not item.active)
                and {"fp.line_status", {"fp.target_disabled", {"fp.pu_" .. item_category, 1}}} or ""
            local tooltip = {"", {"fp.tt_title_with_note", item.proto.localised_name, {"fp.target"}},
                status_line, "\n", number_tooltip or ""}
            if item.definition.type == "machines" then
                local count = item.definition.machine_count
                table.insert(tooltip, {"", "\n", {"fp.item_defined_by_machines",
                    lib.format.number(count, 4), {"fp.pl_machine", count}}})
            end

            ---@type HandleItemBoxClickTags
            local tags = {mod="fp", on_gui_click="act_on_item_box", item_category=item_category, item_id=item.id,
                on_gui_hover="set_tooltip", context="item_boxes", flags=flags}
            local definition = {type="sprite-button", tags=tags--[[@as Tags]], number=amount,
                secondary_number=secondary_amount, style=style, sprite=item.proto.sprite,
                mouse_button_filter={"left-and-right"}, raise_hover_events=true}
            table.insert(buttons, {definition=definition, tooltip=tooltip, proto=item.proto})

            ::skip_item::
        end
    end

    for _, target in ipairs{true, false} do
        for index, item in pairs(floor[item_category .. "s"]) do
            if not target or defined_items[item.proto] ~= item_category then add_calculated_item(item, index, target) end
        end
    end

    if floor.level == 1 then
        local tooltip = {"fp.add_top_level_product", {"fp.pl_" .. item_category, 1}}  ---@type LocalisedString
        if item_category == "product" then
            tooltip = {"", tooltip, "\n", {"fp.add_blueprint_entities_tt"}}
        end
        ---@class AddTopLevelItemTags
        ---@field item_category ItemCategory
        local tags = {mod="fp", on_gui_click="add_top_level_item", item_category=item_category}
        local definition = {type="sprite-button", tags=tags, sprite="utility/add",
            enabled=(not factory.archived), tooltip=tooltip, style="fp_sprite-button_inset",
            mouse_button_filter={"left"}}
        table.insert(buttons, {definition=definition, is_add_button=true})
    end

    return buttons
end


---@param player LuaPlayer
---@param tags AddTopLevelItemTags
---@param event EventData.on_gui_click
local function handle_item_add(player, tags, event)
    local factory = lib.context.get(player, "Factory")  ---@as Factory

    if event.shift then  -- paste
        local dummy_product = FactoryItem.init(nil, tags.item_category)
        lib.clipboard.dummy_paste(player, dummy_product, factory)
    elseif tags.item_category == "product" and player.is_cursor_blueprint() then  -- import blueprint entities
        local blueprint = player.cursor_record or player.cursor_stack
        local timescale = lib.globals.preferences(player).timescale

        for _, entity in pairs(blueprint--[[@cast -nil]].cost_to_build) do
            local proto = prototyper.util.find("items", entity.name, "item")  ---@as FPItemPrototype
            local existing_item = factory:find({proto=proto})

            local amount = entity.count / timescale
            if existing_item then
                if existing_item.category == tags.item_category then
                    existing_item:add_defined_amount(amount)
                end
            else
                local product = FactoryItem.init(proto, tags.item_category)  -- definition.type = "amount"
                product.definition = {type="amount", amount=amount}
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
    local item  ---@type FactoryItem | SimpleItem
    if tags.item_id then
        item = OBJECT_INDEX[tags.item_id]  ---@as FactoryItem
    else
        local floor = lib.context.get(player, "Floor")  ---@as Floor
        item = floor[tags.item_category .. "s"][tags.item_index]  ---@as SimpleItem
    end

    local amount
    if item.class == "FactoryItem" then
        amount = item:get_defined_amount() or item.amount
    elseif tags.flags.target then
        amount = item.required_amount or 0
    else
        amount = item.amount - (item.required_amount or 0)
    end

    if action == "add_producing_recipe" or action == "add_consuming_recipe" then
        local production_type = tags.flags.consume and "consume" or "produce"
        lib.gui.open_dialog(player, {dialog="recipe", modal_data={production_type=production_type,
            category_id=item.proto.category_id, product_id=item.proto.id}})

    elseif action == "convert_to_target" then
        local factory = lib.context.get(player, "Factory")  ---@as Factory
        local target = FactoryItem.init(item.proto, tags.item_category)
        target.definition = {type="amount", amount=amount}
        factory:insert(target)

        solver.update(player)
        lib.gui.run_refresh(player, "factory_list")
        lib.gui.run_refresh(player, "production")

    elseif action == "adjust_weight" then
        solver_bar.add_item_weight(player, item.proto--[[@as FPItemPrototype]])

    elseif action == "edit" then
        lib.gui.open_dialog(player, {dialog="picker",
            modal_data={item_id=item.id, item_category=tags.item_category}})

    elseif action == "toggle" then  ---@cast item FactoryItem
        item.active = not item.active
        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "move_left" or action == "move_right" then  ---@cast item FactoryItem
        local direction = (action == "move_left") and "previous" or "next"
        item.parent:shift(item, direction, 1)

        solver.update(player)
        lib.gui.run_refresh(player, "production")

    elseif action == "copy" then
        local copyable_item = (item.class == "FactoryItem") and item
            or SimpleItem.init(nil, item.proto--[[@as FPItemPrototype]], amount)
        lib.clipboard.copy(player, copyable_item)

    elseif action == "paste" then
        lib.clipboard.paste(player, item)

    elseif action == "delete" or action == "cut" then  ---@cast item FactoryItem
        if action == "cut" then
            lib.clipboard.copy(player, item, true)
        end

        lib.context.get(player, "Factory")--[[@as Factory]]:remove(item)
        solver.update(player)
        lib.gui.run_refresh(player, "all")  -- make sure product icons are updated

    elseif action == "pipette" then
        lib.cursor.pipette_item(player, item.proto--[[@as FPItemPrototype]])

    elseif action == "put_into_combinator" then
        lib.cursor.put_into_combinator(player, item.proto--[[@as FPItemPrototype]], amount)

    elseif action == "factoriopedia" then
        local proto = item.proto  ---@as FPItemPrototype
        player.open_factoriopedia_gui(lib.get_factoriopedia_proto(proto))
    end
end


---@param player LuaPlayer
local function put_ingredients_into_cursor(player, _, _)
    local preferences = lib.globals.preferences(player)
    local relevant_floor = lib.context.get(player, "Floor")  ---@as Floor

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
---@param category ItemCategory
---@param buttons ItemBoxButton[]
---@param columns integer
---@param height number
local function render_item_box(player, category, buttons, columns, height)
    local elements = lib.globals.main_elements(player).item_boxes
    local item_frame = elements[category .. "_item_frame"]
    item_frame.clear()
    item_frame.style.width = columns * MAGIC_NUMBERS.item_button_size
    item_frame.style.minimal_height = height
    item_frame.parent.style.minimal_height = height

    local table_items = item_frame.add{type="table", column_count=columns, style="filter_slot_table"}
    elements[category .. "_item_table"] = table_items
    local tooltips = lib.globals.ui_state(player).tooltips.item_boxes
    for _, data in ipairs(buttons) do
        local button = table_items.add(data.definition)
        tooltips[button.index] = data.tooltip
        if data.proto then item_highlights.register(player, button, data.proto) end
        if data.is_add_button then
            button.style.padding = 4
            button.style.margin = 4
        end
    end
end

---@param player LuaPlayer
local function refresh_item_boxes(player)
    local player_table = lib.globals.player_table(player)

    local main_elements = player_table.ui_state.main_elements
    if main_elements.main_frame == nil then return end
    item_highlights.reset(player, "item_boxes")

    local visible = not player_table.ui_state.districts_view
    main_elements.item_boxes.horizontal_flow.visible = visible
    if not visible then return end

    local factory = lib.context.get(player, "Factory")  ---@as Factory?
    main_elements.item_boxes.ingredient_combinator_button.visible = (factory ~= nil and factory.valid)

    local tooltips = player_table.ui_state.tooltips
    tooltips.item_boxes = {}

    local products = prepare_item_buttons(player, factory, "product")
    local ingredients = prepare_item_buttons(player, factory, "ingredient")

    -- Keep room for both headings
    local available_width = main_dialog.get_content_width(player)
        - (4 * HORIZONTAL_PADDING) - MAGIC_NUMBERS.frame_spacing
    local total_columns = math.max(2, math.floor(available_width / MAGIC_NUMBERS.item_button_size))
    local minimum_columns = math.min(3, math.floor(total_columns / 2))

    local rows = 0  -- find the fewest rows that fit both groups
    local required_product_columns, required_ingredient_columns
    repeat
        rows = rows + 1
        required_product_columns = math.max(minimum_columns, math.ceil(#products / rows))
        required_ingredient_columns = math.max(minimum_columns, math.ceil(#ingredients / rows))
    until required_product_columns + required_ingredient_columns <= total_columns

    -- Divide spare columns equally between both groups
    local spare_columns = total_columns - required_product_columns - required_ingredient_columns
    local product_columns = required_product_columns + math.floor(spare_columns / 2)
    local ingredient_columns = total_columns - product_columns

    local height = math.min(rows, MAX_ROWS) * MAGIC_NUMBERS.item_button_size
    render_item_box(player, "product", products, product_columns, height)
    render_item_box(player, "ingredient", ingredients, ingredient_columns, height)
end

---@param player LuaPlayer
local function build_item_boxes(player)
    local main_elements = lib.globals.main_elements(player)
    main_elements.item_boxes = {}

    local parent_flow = main_elements.flows.right_vertical
    local flow_horizontal = parent_flow.add{type="flow", direction="horizontal"}
    flow_horizontal.style.horizontal_spacing = MAGIC_NUMBERS.frame_spacing
    flow_horizontal.style.horizontally_stretchable = true
    main_elements.item_boxes["horizontal_flow"] = flow_horizontal

    build_item_box(player, "product")
    build_item_box(player, "ingredient")

    refresh_item_boxes(player)
end


-- ** EVENTS **
local listeners = {}  ---@type ListenerDefinitions

---@param flags GUIActionFlags
---@return boolean?
local function show_add_recipe(flags)
    return flags.top_level or not flags.entity or flags.special
end

---@param flags GUIActionFlags
---@return boolean?
local function is_top_level_item(flags)
    return flags.top_level
end

---@param flags GUIActionFlags
---@return boolean?
local function show_convert_to_target(flags)
    return flags.top_floor
end

---@param flags GUIActionFlags
---@return boolean
---@return LocalisedString? warning
local function can_convert_to_target(flags)
    if flags.archived then return false, {"fp.factory_archived_edit"} end
    if flags.defined_product or flags.defined_ingredient then
        local category = flags.defined_product and "product" or "ingredient"
        return false, {"fp.item_already_defined_" .. category}
    end
    if not flags.can_define_target then return false, {"fp.item_cannot_be_defined"} end
    return true
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
                add_producing_recipe = {shortcut="left", core=true, enable=lib.actions.can_add_recipe,
                    show=function(flags) return not flags.consume and show_add_recipe(flags) end},
                add_consuming_recipe = {shortcut="left", core=true, enable=lib.actions.can_add_recipe,
                    show=function(flags) return flags.consume and show_add_recipe(flags) end},
                edit = {shortcut="control-left", core=true, show=is_top_level_item,
                    enable=lib.actions.can_edit_factory},
                toggle = {show=is_top_level_item, enable=lib.actions.can_edit_factory},
                convert_to_target = {shortcut="control-left", show=show_convert_to_target,
                    enable=can_convert_to_target},
                delete = {input="delete", show=is_top_level_item, enable=lib.actions.can_edit_factory},
                adjust_weight = {show=lib.actions.show_adjust_weight, enable=lib.actions.can_adjust_weight},
                move_left = {show=is_top_level_item, enable=can_move_left},
                move_right = {show=is_top_level_item, enable=can_move_right},
                copy = {shortcut="shift-right"},
                paste = {shortcut="shift-left", show=is_top_level_item, enable=lib.actions.can_edit_factory},
                cut = {shortcut="control-right", show=is_top_level_item, enable=lib.actions.can_edit_factory},
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
