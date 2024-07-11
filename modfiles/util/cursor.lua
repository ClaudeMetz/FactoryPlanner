local _cursor = {}

---@param player LuaPlayer
---@param blueprint_entities BlueprintEntity[]
local function set_cursor_blueprint(player, blueprint_entities)
    local script_inventory = game.create_inventory(1)
    local blank_slot = script_inventory[1]

    blank_slot.set_stack{name="blueprint"}
    -- TODO This is somehow broken, probably an API bug
    blank_slot.set_blueprint_entities(blueprint_entities)
    player.add_to_clipboard(blank_slot)
    player.activate_paste()
    script_inventory.destroy()
end


---@param player LuaPlayer
---@param text LocalisedString
function _cursor.create_flying_text(player, text)
    player.create_local_flying_text{text=text, create_at_cursor=true}
end

---@param player LuaPlayer
---@param line Line
---@param object Machine | Beacon
---@return boolean success
function _cursor.set_entity(player, line, object)
    local entity_prototype = game.entity_prototypes[object.proto.name]
    if entity_prototype.has_flag("not-blueprintable") or not entity_prototype.has_flag("player-creation")
            or entity_prototype.items_to_place_this == nil then
        _cursor.create_flying_text(player, {"fp.put_into_cursor_failed", entity_prototype.localised_name})
        return false
    end

    local items_list, slot_index = {}, 0
    for module in object.module_set:iterator() do
        local inventory_list = {}
        for i = 1, module.amount do
            table.insert(inventory_list, {
                inventory = 4,  -- this should be from defines.inventory depending on the entity,
                                -- but it seemingly works this way. Not sure.
                stack = slot_index
            })
            slot_index = slot_index + 1
        end

        table.insert(items_list, {
            id = {
                name = module.proto.name
            },
            items = {
                in_inventory = inventory_list
            }
        })
    end

    local blueprint_entity = {
        entity_number = 1,
        name = object.proto.name,
        position = {0, 0},
        items = items_list,
        recipe = (object.class == "Machine") and line.recipe_proto.name or nil
    }

    set_cursor_blueprint(player, {blueprint_entity})
    return true
end

---@param player LuaPlayer
---@param item_signals { [SignalID]: number }
function _cursor.set_item_combinator(player, item_signals)
    local combinator_proto = game.entity_prototypes["constant-combinator"]
    local filter_limit = combinator_proto.item_slot_count

    local blueprint_entities = {}  ---@type BlueprintEntity[]
    local current_combinator, current_filter_count = nil, 0
    local next_entity_number, next_position = 1, {0, 0}

    for signal, amount in pairs(item_signals) do
        if not current_combinator or current_filter_count == filter_limit then
            current_combinator = {
                entity_number = next_entity_number,
                name = "constant-combinator",
                tags = {fp_item_combinator = true},
                position = next_position,
                control_behavior = {filters = {}},
                connections = {{green = {}}}  -- filled in below
            }
            table.insert(blueprint_entities, current_combinator)

            next_entity_number = next_entity_number + 1
            next_position = {next_position[1] + 1, 0}
            current_filter_count = 0
        end

        current_filter_count = current_filter_count + 1
        table.insert(current_combinator.control_behavior.filters, {
            signal = signal,
            count = math.max(amount, 1),  -- make sure amounts < 1 are not excluded
            index = current_filter_count
        })
    end

    ---@param main_entity BlueprintEntity
    ---@param other_entity BlueprintEntity
    local function connect_if_entity_exists(main_entity, other_entity)
        if other_entity ~= nil then
            local entry = {entity_id = other_entity.entity_number}
            table.insert(main_entity.connections[1].green, entry)
        end
    end

    for index, entity in ipairs(blueprint_entities) do
        connect_if_entity_exists(entity, blueprint_entities[index-1])
        if not next(entity.connections[1].green) then entity.connections = nil end
    end

    set_cursor_blueprint(player, blueprint_entities)
end

---@param player LuaPlayer
---@param proto FPItemPrototype | FPFuelPrototype
---@param amount number
function _cursor.add_to_item_combinator(player, proto, amount)
    local blueprint_entities = player.get_blueprint_entities()
    local item_signals = {}

    if blueprint_entities ~= nil then
        for _, entity in pairs(blueprint_entities) do
            if entity.tags ~= nil and entity.tags["fp_item_combinator"] then
                for _, filter in pairs(entity.control_behavior.filters) do
                    item_signals[filter.signal] = filter.count
                end
            end
        end
    end

    local signal = {type=proto.type, name=proto.name}
    item_signals[signal] = (item_signals[signal] or 0) + amount  -- add to existing if applicable
    _cursor.set_item_combinator(player, item_signals)
end

return _cursor
