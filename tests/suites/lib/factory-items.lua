---@diagnostic disable

local migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_16")
local old_migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_4")
local Realm = script and require("__factoryplanner__.backend.data.Realm")

local function fixture(context, isolated)
    local player = game.players[1]
    local district = context.classes.District.init()
    local realm = isolated and Realm.init() or lib.globals.player_table(player).realm
    realm:insert(district)
    local factory = context.classes.Factory.init("factory-item-test", "sequential")
    district:insert(factory)
    lib.context.set(player, factory)
    local item = context.classes.FactoryItem.init(prototyper.util.find("items", "iron-plate", "item"))
    factory:insert(item)
    return player, factory, item, realm
end


return {
    definitions = {check=function(context)
        local player, factory, item = fixture(context)
        local belt = prototyper.util.find("belts", "transport-belt")
        for _, definition in ipairs{
            {type="amount", amount=90},
            {type="belts", belt_count=2, belt_proto=belt, belt_stack=2}
        } do
            item.definition = definition
            local expected = (definition.type == "amount") and 90
                or 4 * belt.throughput
            assert(item:get_defined_amount() == expected)
            local packed_factory = factory:pack(false)
            local factory_copy = context.classes.Factory.unpack(packed_factory)
            assert(factory_copy:validate(player))
            assert(factory_copy.first.definition.type == definition.type)
            assert(factory_copy.first:get_defined_amount() == expected)
            local packed = item:pack(true)
            local restored = context.classes.FactoryItem.unpack(packed)
            assert(restored:validate(player))
            assert(restored.definition.type == definition.type and restored:get_defined_amount() == expected)
            restored.definition.type = "amount"
            assert(packed.definition.type == definition.type, "Unpacking must not mutate the snapshot")
            lib.clipboard.copy(player, item)
            assert(lib.clipboard.paste(player, item))
            item = factory.first
            assert(item.definition.type == definition.type)
            item:add_defined_amount(30)
            assert(item:get_defined_amount() == expected + 30)
        end
        local max_stack = prototypes.utility_constants.max_belt_stack_size
        item.definition = {type="belts", belt_count=2, belt_proto=belt, belt_stack=max_stack * 2}
        local expected = item:get_defined_amount()
        assert(item:validate(player) and item:get_defined_amount() == expected)
        assert(item.definition.belt_stack == max_stack and item.definition.belt_count == 4)
    end},
    migration = {check=function(context)
        local player, factory, item, realm = fixture(context, true)
        local pt = {realm=realm}
        local belt = prototyper.util.find("belts", "transport-belt")
        for _, source_class in ipairs{"TLProduct", "FactoryItem"} do
            for _, mode in ipairs{"amount", "belts"} do
                item.definition = nil
                item.defined_by, item.required_amount = mode, 3
                item.belt_proto = (mode == "belts") and belt or nil
                if source_class == "TLProduct" then
                    old_migration.player_table(pt)
                    item = factory.first
                end
                item.belt_stack = (mode == "belts") and 2 or nil
                item.amount = 7
                local packed = {products={{class=source_class,
                    proto=prototyper.util.simplify_prototype(item.proto, "type"),
                    defined_by=mode, required_amount=3, belt_stack=item.belt_stack,
                    belt_proto=(mode == "belts") and prototyper.util.simplify_prototype(belt, nil)}}}
                migration.player_table(pt)
                migration.packed_factory(packed)
                migration.player_table(pt)
                migration.packed_factory(packed)
                item = factory.first
                local restored = context.classes.FactoryItem.unpack(packed.products[1])
                assert(restored:validate(player))
                assert(item.class == "FactoryItem" and item.definition.type == mode and item.amount == 7)
                assert(item:get_defined_amount() == restored:get_defined_amount())
                assert(item:get_defined_amount() == ((mode == "amount") and 3 or 6 * belt.throughput))
                assert(not packed.products[1].required_amount and not packed.products[1].defined_by)
                assert(not item.required_amount and not item.belt_proto)
            end
        end
    end},
    picker = {check=function(context)
        local player, factory, item = fixture(context)
        local preferences = lib.globals.preferences(player)
        local previous_unit = preferences.belts_or_lanes
        main_dialog.rebuild(player, false)
        compact_dialog.rebuild(player, false)
        for _, unit in ipairs{"belts", "lanes"} do
            preferences.belts_or_lanes = unit
            for _, mode in ipairs{"amount", "belts"} do
                item.definition = (mode == "amount") and {type="amount", amount=90}
                    or {type="belts", belt_count=2, belt_stack=2,
                        belt_proto=prototyper.util.find("belts", "transport-belt")}
                local expected = item:get_defined_amount()
                lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
                local e = lib.globals.modal_elements(player)
                assert(e.item_amount_textfield.enabled == (mode == "amount"))
                assert(e.belt_amount_textfield.enabled == (mode == "belts"))
                if mode == "belts" then
                    assert(tonumber(e.belt_amount_textfield.text) == ((unit == "lanes") and 4 or 2))
                    assert(e.belt_stack_dropdown.selected_index == 2)
                end
                assert(e.dialog_submit_button.enabled)
                lib.gui.close_dialog(player, "submit")
                assert(item.definition.type == mode and math.abs(item:get_defined_amount() - expected) < 0.0001)
                assert((item.definition.belt_proto ~= nil) == (mode == "belts"))
            end
        end
        preferences.belts_or_lanes = previous_unit
    end}
}
