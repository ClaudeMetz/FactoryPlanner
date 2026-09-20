---@diagnostic disable

local migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_16")
local old_migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_4")
local Realm = script and require("__factoryplanner__.backend.data.Realm")

return {migration = {check=function(context)
    local classes, player = context.classes, game.players[1]
    local realm = Realm.init()
    local factory = classes.Factory.init("factory-item-migration", "sequential")
    realm.first:insert(factory)
    local item = classes.FactoryItem.init(prototyper.util.find("items", "iron-plate", "item"))
    factory:insert(item)
    local belt = prototyper.util.find("belts", "transport-belt")

    for _, mode in ipairs{"amount", "belts"} do
        item.defined_by, item.required_amount = mode, 3
        item.belt_proto = (mode == "belts") and belt or nil
        old_migration.player_table({realm=realm})
        item = factory.first
        item.belt_stack = (mode == "belts") and 2 or nil
        item.amount = 7
        local packed = {products={{class="TLProduct", proto=prototyper.util.simplify_prototype(item.proto, "type"),
            defined_by=mode, required_amount=3, belt_proto=(mode == "belts") and prototyper.util.simplify_prototype(belt, nil),
            belt_stack=item.belt_stack}}}

        migration.player_table({realm=realm})
        migration.packed_factory(packed)
        migration.player_table({realm=realm})
        migration.packed_factory(packed)
        item = factory.first
        local restored = classes.FactoryItem.unpack(packed.products[1])
        assert(restored:validate(player))
        assert(item.class == "FactoryItem" and item.defined_by == mode)
        assert(item.required_amount == 3 and item.amount == 7)
        assert(item:get_required_amount() == ((mode == "amount") and 3 or 6 * belt.throughput))
        assert(item:get_required_amount() == restored:get_required_amount())
        assert(item.belt_stack == restored.belt_stack)
        assert(item:pack(false).class == "FactoryItem")
    end
end}}
