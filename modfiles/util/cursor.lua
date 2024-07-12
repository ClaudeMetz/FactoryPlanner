local _cursor = {}

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
                -- This should be from defines.inventory depending on the entity, but this somehow works
                inventory = 4,
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
---@param item_signals Signal[]
function _cursor.set_item_combinator(player, item_signals)
    local filters, slot_index = {}, 1
    for _, signal in pairs(item_signals) do
        table.insert(filters, {
            index = slot_index,
            type = signal.signal.type,
            name = signal.signal.name,
            count = math.max(signal.count, 1)  -- make sure amounts < 1 are not excluded
        })
        slot_index = slot_index + 1
    end

    local blueprint_entity = {
        entity_number = 1,
        name = "constant-combinator",
        position = {0, 0},
        control_behavior = {
            -- TODO outer 'sections' will be renamed to logistic_sections
            sections = { sections = {
                {
                    index = 1,
                    filters = filters
                }
            } }
        }
    }

    set_cursor_blueprint(player, {blueprint_entity})
end

---@param player LuaPlayer
---@param proto FPItemPrototype | FPFuelPrototype
---@param amount number
function _cursor.add_to_item_combinator(player, proto, amount)
    local item_signals, filter_matched = {}, false

    local function parse_filters(filters)
        for _, filter in pairs(filters) do
            local count = filter.count
            if proto.type == (filter.type or "item") and proto.name == filter.name then
                filter_matched = true
                count = count + amount
            end

            table.insert(item_signals, {
                signal = {
                    type = filter.type,
                    name = filter.name,
                },
                count = count
            })
        end
    end

    if not player.is_cursor_empty() then
        local cursor = player.cursor_stack  --[[@cast cursor -nil]]
        if cursor.is_blueprint and cursor.is_blueprint_setup() then
            local entities = cursor.get_blueprint_entities()
            if entities and #entities == 1 and entities[1].name == "constant-combinator" then
                -- TODO outer 'sections' will be renamed to logistic_sections
                local sections = entities[1].control_behavior.sections
                if sections and sections.sections and #sections.sections == 1 then
                    local section = sections.sections[1]
                    if not section.group then
                        parse_filters(section.filters)
                    end
                end
            end
        end
    end

    if not filter_matched then
        table.insert(item_signals, {
            signal = {
                type = proto.type,
                name = proto.name,
            },
            count = amount
        })
    end

    _cursor.set_item_combinator(player, item_signals)
end

return _cursor
