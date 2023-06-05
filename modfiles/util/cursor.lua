local _cursor = {}

---@param player LuaPlayer
---@param blueprint_entities BlueprintEntity[]
local function set_cursor_blueprint(player, blueprint_entities)
    local script_inventory = game.create_inventory(1)
    local blank_slot = script_inventory[1]

    blank_slot.set_stack{name="fp_cursor_blueprint"}
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
---@param line FPLine
---@param object FPMachine | FPBeacon
---@return boolean success
function _cursor.set_entity(player, line, object)
    local entity_prototype = game.entity_prototypes[object.proto.name]
    if entity_prototype.has_flag("not-blueprintable") or not entity_prototype.has_flag("player-creation")
            or entity_prototype.items_to_place_this == nil then
        util.cursor.create_flying_text(player, {"fp.put_into_cursor_failed", entity_prototype.localised_name})
        return false
    end

    local module_list = {}
    for _, module in pairs(ModuleSet.get_in_order(object.module_set)) do
        module_list[module.proto.name] = module.amount
    end

    local blueprint_entity = {
        entity_number = 1,
        name = object.proto.name,
        position = {0, 0},
        items = module_list,
        recipe = (object.class == "Machine") and line.recipe.proto.name or nil
    }

    set_cursor_blueprint(player, {blueprint_entity})
    return true
end

---@param player LuaPlayer
---@param items { [string]: number }
---@return boolean success
function _cursor.set_item_combinator(player, items)
    local combinator_proto = game.entity_prototypes["constant-combinator"]
    if combinator_proto == nil then
        util.cursor.create_flying_text(player, {"fp.blueprint_no_combinator_prototype"})
        return false
    elseif not next(items) then
        util.cursor.create_flying_text(player, {"fp.impossible_to_blueprint_fluid"})
        return false
    end
    local filter_limit = combinator_proto.item_slot_count

    local blueprint_entities = {}  ---@type BlueprintEntity[]
    local current_combinator, current_filter_count = nil, 0
    local next_entity_number, next_position = 1, {0, 0}

    for proto_name, item_amount in pairs(items) do
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
            signal = {type = 'item', name = proto_name},
            count = math.max(item_amount, 1),  -- make sure amounts < 1 are not excluded
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
    return true
end

---@param player LuaPlayer
---@param proto FPItemPrototype | FPFuelPrototype
---@param amount number
function _cursor.add_to_item_combinator(player, proto, amount)
    if proto.type ~= "item" then
        util.cursor.create_flying_text(player, {"fp.impossible_to_blueprint_fluid"})
        return
    end

    local items = {}
    local blueprint_entities = player.get_blueprint_entities()
    if blueprint_entities ~= nil then
        for _, entity in pairs(blueprint_entities) do
            if entity.tags ~= nil and entity.tags["fp_item_combinator"] then
                for _, filter in pairs(entity.control_behavior.filters) do
                    items[filter.signal.name] = filter.count
                end
            end
        end
    end

    items[proto.name] = (items[proto.name] or 0) + amount
    util.cursor.set_item_combinator(player, items)  -- don't care about success here
end

return _cursor
