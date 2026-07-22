local _cursor = {}

---@param player LuaPlayer
---@param text LocalisedString
function _cursor.create_flying_text(player, text)
    player.create_local_flying_text{text=text, create_at_cursor=true}
end


---@param player LuaPlayer
---@param blueprint_entities BlueprintEntity[]
local function set_cursor_blueprint(player, blueprint_entities)
    local script_inventory = game.create_inventory(1)
    local blank_slot = script_inventory[1]

    blank_slot.set_stack{name="blueprint"}
    blank_slot.set_blueprint_entities(blueprint_entities)
    player.clear_cursor()
    player.add_to_clipboard(blank_slot)
    player.activate_paste()
    script_inventory.destroy()
end


---@param player LuaPlayer
---@param line Line
---@param object Machine | Beacon
---@return boolean success
function _cursor.set_entity(player, line, object)
    local entity_prototype = prototypes.entity[object.proto.name]
    if entity_prototype.has_flag("not-blueprintable") or not entity_prototype.has_flag("player-creation")
            or not object.proto.built_by_item then
        _cursor.create_flying_text(player, {"fp.put_into_cursor_failed", entity_prototype.localised_name})
        return false
    end

    local items_list, slot_index = {}, 0
    if object.class == "Beacon" or object:uses_effects() then
        local inventory = defines.inventory[object.proto.prototype_category .. "_modules"]
        for module in object.module_set:iterator() do
            local inventory_list = {}
            for i = 1, module.amount do
                table.insert(inventory_list, {
                    inventory = inventory,
                    stack = slot_index
                })
                slot_index = slot_index + 1
            end

            table.insert(items_list, {
                id = {
                    name = module.proto.name,
                    quality = module.quality_proto.name
                },
                items = {
                    in_inventory = inventory_list
                }
            })
        end
    end

    -- Put item directly into the cursor if it's simple
    if #items_list == 0 and object.proto.prototype_category ~= "crafter" then
        player.cursor_ghost = {
            name = object.proto.built_by_item.name,
            quality = object.quality_proto.name
        }  ---@as ItemIDAndQualityIDPair
    else  -- if it's more complex, it needs a blueprint
        local blueprint_entity = {
            entity_number = 1,
            name = object.proto.name,
            position = {0, 0},
            quality = object.quality_proto.name,
            items = items_list,
            recipe = (object.class == "Machine") and line.recipe.proto.name or nil
        }
        set_cursor_blueprint(player, {blueprint_entity})
    end

    return true
end

---@param player LuaPlayer
---@param item_filters BlueprintLogisticFilter[]
function _cursor.set_item_combinator(player, item_filters)
    local slot_index = 1
    for _, filter in pairs(item_filters) do
        -- Make sure amounts < 1 are not excluded, and the int32 limit is not exceeded
        filter.count = math.min(math.max(filter.count, 1)--[[@cast -nil]], 2^31 - 1)
        filter.index = slot_index
        slot_index = slot_index + 1
    end

    local blueprint_entity = {
        entity_number = 1,
        name = "constant-combinator",
        position = {0, 0},
        control_behavior = {
            sections = {
                sections = {
                    {
                        index = 1,
                        filters = item_filters
                    }
                }
            }
        }
    }

    set_cursor_blueprint(player, {blueprint_entity})
end


---@param player LuaPlayer
---@param blueprint_entity BlueprintEntity?
---@param item_proto FPItemPrototype | FPFuelPrototype
---@param amount number
local function add_to_item_combinator(player, blueprint_entity, item_proto, amount)
    local timescale = lib.globals.preferences(player).timescale
    local item_signals, filter_matched = {}, false
    local item_name = item_proto.base_name or item_proto.name

    do
        if not blueprint_entity then goto skip_cursor end
        if not blueprint_entity.name == "constant-combinator" then goto skip_cursor end

        local control_behavior = blueprint_entity.control_behavior
        if not control_behavior then goto skip_cursor end

        local sections = control_behavior.sections
        if not (sections and sections.sections and #sections.sections == 1) then goto skip_cursor end

        local section = sections--[[@cast -nil]].sections--[[@cast -nil]][1]
        if section--[[@cast -nil]].group then goto skip_cursor end

        for _, filter in pairs(section--[[@cast -nil]].filters--[[@cast -nil]]) do
            if item_proto.type == (filter.type or "item") and item_name == filter.name then
                filter.count = filter.count + (amount * timescale)  ---@as int32
                filter_matched = true
            end
            table.insert(item_signals, filter)
        end

        ::skip_cursor::
    end

    if not filter_matched then
        table.insert(item_signals, {
            type = item_proto.type,
            name = item_name,
            quality = "normal",
            comparator = "=",
            count = math.ceil(amount * timescale - MAGIC_NUMBERS.margin_of_error)
        })
    end

    _cursor.set_item_combinator(player, item_signals)
end


---@param player LuaPlayer
---@param cursor_entity CursorEntityData
---@param item_proto FPItemPrototype | FPFuelPrototype
local function set_filter_on_inserter(player, cursor_entity, item_proto)
    local entity_proto = (cursor_entity.type == "entity") and cursor_entity.entity
        or prototypes.entity[cursor_entity.entity--[[@cast -nil]].name]

    if item_proto.type == "fluid" then
        _cursor.create_flying_text(player, {"fp.entity_only_filters_items", entity_proto.localised_name})
        return
    end

    if not entity_proto.filter_count then
        ---@diagnostic disable-next-line: undefined-field
        _cursor.create_flying_text(player, {"fp.entity_has_no_filters", entity_proto.localised_name})
        return
    end

    local new_filter = {
        index = 1,
        name = item_proto.name,
        quality = "normal",
        comparator = "="
    }

    if cursor_entity.type == "blueprint" then
        local blueprint_entity = cursor_entity.entity  ---@as BlueprintEntity
        blueprint_entity.filters = blueprint_entity.filters or {}
        blueprint_entity.use_filters = true

        local filter_count = #blueprint_entity.filters
        if filter_count == entity_proto.filter_count then
            _cursor.create_flying_text(player, {"fp.entity_filter_limit_reached", entity_proto.localised_name})
        else
            -- Silently drop any duplicates
            for _, filter in pairs(blueprint_entity.filters) do
                if filter.name == item_proto.name then return end
            end

            new_filter.index = filter_count + 1
            table.insert(blueprint_entity.filters, new_filter)
            set_cursor_blueprint(player, {blueprint_entity})
        end
    else
        set_cursor_blueprint(player, {
            {
                entity_number = 1,
                name = entity_proto.name,
                position = {0, 0},
                quality = cursor_entity.quality,
                use_filters = true,
                filters = { new_filter }
            }
        })
    end
end

---@param player LuaPlayer
---@param cursor_entity CursorEntityData
---@param item_proto FPItemPrototype | FPFuelPrototype
local function set_filter_on_splitter(player, cursor_entity, item_proto)
    local entity_proto = (cursor_entity.type == "entity") and cursor_entity.entity
        or prototypes.entity[cursor_entity.entity--[[@cast -nil]].name]

    if item_proto.type == "fluid" then
        _cursor.create_flying_text(player, {"fp.entity_only_filters_items", entity_proto.localised_name})
        return
    end

    local new_filter = {
        index = 1,
        name = item_proto.name,
        quality = "normal",
        comparator = "="
    }

    if cursor_entity.type == "blueprint" then
        local blueprint_entity = cursor_entity.entity  ---@as BlueprintEntity
        blueprint_entity.filter = new_filter
        set_cursor_blueprint(player, {blueprint_entity})
    else
        set_cursor_blueprint(player, {
            {
                entity_number = 1,
                name = entity_proto.name,
                position = {0, 0},
                quality = cursor_entity.quality,
                filter = new_filter
            }
        })
    end
end


---@param player LuaPlayer
---@param cursor_entity CursorEntityData
---@param item_proto FPItemPrototype | FPFuelPrototype
---@return boolean applicable
local function set_filter(player, cursor_entity, item_proto)
    local entity_proto  ---@type LuaEntityPrototype

    if cursor_entity.type == "entity" then
        ---@cast cursor_entity.entity LuaEntityPrototype
        entity_proto = cursor_entity.entity
    elseif cursor_entity.type == "blueprint" then
        ---@cast cursor_entity.entity BlueprintEntity
        entity_proto = prototypes.entity[cursor_entity.entity.name]
    end

    local type = entity_proto.type
    if type == "inserter" or type == "loader" or type == "loader-1x1" then
        set_filter_on_inserter(player, cursor_entity, item_proto)
        return true
    elseif type == "splitter" or type == "lane-splitter" then
        set_filter_on_splitter(player, cursor_entity, item_proto)
        return true
    end

    return false
end


---@param player LuaPlayer
---@return LuaItemPrototype?
function _cursor.parse_cursor_item(player)
    if player.is_cursor_empty() then return nil end
    local cursor = player.cursor_stack  ---@cast cursor -nil

    local valid_for_read, cursor_ghost = cursor.valid_for_read, player.cursor_ghost  ---@as ItemIDAndQualityIDPair
    local prototype = (valid_for_read) and cursor.prototype or cursor_ghost.name  ---@as LuaItemPrototype

    return prototype
end

---@alias CursorEntityType "none" | "blueprint" | "entity"
---@alias CursorEntity BlueprintEntity | LuaEntityPrototype
---@alias CursorEntityData { type: CursorEntityType, entity: CursorEntity?, quality: string? }

---@param player LuaPlayer
---@return CursorEntityData cursor_entity
local function parse_cursor_entity(player)
    local no_entity = {type="none", entity=nil, quality=nil}

    if player.is_cursor_empty() then return no_entity end
    local cursor = player.cursor_stack  ---@cast cursor -nil

    if cursor.is_blueprint and cursor.is_blueprint_setup() then
        local entities = cursor.get_blueprint_entities()
        if not (entities and #entities == 1) then return no_entity end
        return {type="blueprint", entity=entities--[[@cast -nil]][1],
                quality=entities--[[@cast -nil]][1]--[[@cast -nil]].quality}
    else
        local valid_for_read = cursor.valid_for_read
        local cursor_ghost = player.cursor_ghost  ---@as ItemIDAndQualityIDPair
        local prototype = (valid_for_read) and cursor.prototype or cursor_ghost.name  ---@as LuaItemPrototype

        local place_result = prototype.place_result
        if not place_result then return no_entity end

        local quality = (valid_for_read) and cursor.quality or cursor_ghost.quality
        return {type="entity", entity=place_result, quality=quality--[[@cast -nil]].name}
    end
end

---@param player LuaPlayer
---@param item_proto FPItemPrototype | FPFuelPrototype
---@param amount number
function _cursor.handle_item_click(player, item_proto, amount)
    local cursor_entity = parse_cursor_entity(player)

    local applicable = set_filter(player, cursor_entity, item_proto)
    if applicable then return end

    local blueprint_entity = (cursor_entity.type == "blueprint") and cursor_entity.entity or nil
    add_to_item_combinator(player, blueprint_entity--[[@as BlueprintEntity?]], item_proto, amount)
end

return _cursor
