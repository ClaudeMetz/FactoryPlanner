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
            or entity_prototype.items_to_place_this == nil then
        _cursor.create_flying_text(player, {"fp.put_into_cursor_failed", entity_prototype.localised_name})
        return false
    end

    local items_list, slot_index = {}, 0
    if object.proto.effect_receiver.uses_module_effects then
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
    if #items_list == 0 and object.proto.prototype_category ~= "assembling_machine" then
        player.cursor_ghost = {
            name = object.proto.name,
            quality = object.quality_proto.name
        }
    else  -- if it's more complex, it needs a blueprint
        local blueprint_entity = {
            entity_number = 1,
            name = object.proto.name,
            position = {0, 0},
            quality = object.quality_proto.name,
            items = items_list,
            recipe = (object.class == "Machine") and line.recipe_proto.name or nil
        }
        set_cursor_blueprint(player, {blueprint_entity})
    end

    return true
end

---@param player LuaPlayer
---@param item_filters LogisticFilter[]
function _cursor.set_item_combinator(player, item_filters)
    local slot_index = 1
    for _, filter in pairs(item_filters) do
        filter.count = math.max(filter.count, 1)  -- make sure amounts < 1 are not excluded
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
---@param blueprint_entity BlueprintEntity
---@param item_proto FPItemPrototype | FPFuelPrototype
---@param amount number
local function add_to_item_combinator(player, blueprint_entity, item_proto, amount)
    local timescale = util.globals.preferences(player).timescale
    local item_signals, filter_matched = {}, false

    do
        if not blueprint_entity then goto skip_cursor end
        if not blueprint_entity.name == "constant-combinator" then goto skip_cursor end

        local sections = blueprint_entity.control_behavior.sections
        if not (sections and sections.sections and #sections.sections == 1) then goto skip_cursor end

        local section = sections.sections[1]
        if section.group then goto skip_cursor end

        for _, filter in pairs(section.filters) do
            if item_proto.type == (filter.type or "item") and item_proto.name == filter.name then
                filter.count = filter.count + (amount * timescale)
                filter_matched = true
            end
            table.insert(item_signals, filter)
        end

        ::skip_cursor::
    end

    if not filter_matched then
        table.insert(item_signals, {
            type = item_proto.type,
            name = item_proto.name,
            quality = "normal",
            comparator = "=",
            count = amount * timescale
        })
    end

    _cursor.set_item_combinator(player, item_signals)
end

---@param player LuaPlayer
---@param cursor_entity CursorEntityData
---@param item_proto FPItemPrototype
local function set_filter_on_inserter(player, cursor_entity, item_proto)
    local entity_proto = (cursor_entity.type == "entity") and cursor_entity.entity
        or prototypes.entity[cursor_entity.entity.name]

    if item_proto.type == "fluid" then
        _cursor.create_flying_text(player, {"fp.inserter_only_filters_items"})
        return
    end

    if not entity_proto.filter_count then
        _cursor.create_flying_text(player, {"fp.inserter_has_no_filters"})
        return
    end

    local new_filter = {
        index = 1,
        name = item_proto.name,
        quality = "normal",
        comparator = "="
    }

    if cursor_entity.type == "blueprint" then
        local blueprint_entity = cursor_entity.entity

        local filter_count = #blueprint_entity.filters
        if filter_count == entity_proto.filter_count then
            _cursor.create_flying_text(player, {"fp.inserter_filter_limit_reached"})
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


---@alias CursorEntityType "none" | "blueprint" | "entity"
---@alias CursorEntity BlueprintEntity | LuaEntityPrototype
---@alias CursorEntityData { type: CursorEntityType, entity: CursorEntity?, quality: string? }

---@param player LuaPlayer
---@return CursorEntityData? cursor_entity
local function parse_cursor_entity(player)
    local no_entity = {type="none", entity=nil, quality=nil}

    if player.is_cursor_empty() then return no_entity end
    local cursor = player.cursor_stack  --[[@cast cursor -nil]]

    if cursor.is_blueprint and cursor.is_blueprint_setup() then
        local entities = cursor.get_blueprint_entities()
        if not (entities and #entities == 1) then return no_entity end
        return {type="blueprint", entity=entities[1], quality=entities[1].quality}
    else
        local valid_for_read, cursor_ghost = cursor.valid_for_read, player.cursor_ghost
        local prototype = (valid_for_read) and cursor.prototype or cursor_ghost.name

        local place_result = prototype.place_result
        if not place_result then return no_entity end

        local quality = (valid_for_read) and cursor.quality.name or cursor_ghost.quality.name
        return {type="entity", entity=place_result, quality=quality}
    end
end

---@param player LuaPlayer
---@param item_proto FPItemPrototype | FPFuelPrototype
---@param amount number
function _cursor.handle_item_click(player, item_proto, amount)
    local cursor_entity = parse_cursor_entity(player)

    if cursor_entity.type == "entity" and cursor_entity.entity.type == "inserter" then
        set_filter_on_inserter(player, cursor_entity, item_proto)

    elseif cursor_entity.type == "blueprint" then
        local entity_proto = prototypes.entity[cursor_entity.entity.name]
        if entity_proto.type == "inserter" then
            set_filter_on_inserter(player, cursor_entity, item_proto)
        else
            add_to_item_combinator(player, cursor_entity.entity, item_proto, amount)
        end
    else
        add_to_item_combinator(player, nil, item_proto, amount)
    end
end

return _cursor
