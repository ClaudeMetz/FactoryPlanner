---@diagnostic disable

-- Copy, Cut, and Paste coverage for lib.clipboard, including immutable snapshots,
-- GUI dispatch, and removal that changes the original parent.
local helpers = require("helpers")
local fixtures = require("fixtures")
local SimpleItem = script and require("__factoryplanner__.backend.data.SimpleItem")

local function fixture(context)
    local classes, player = context.classes, game.players[1]
    local factory = fixtures.factory(context, "clipboard-test")
    local product = classes.FactoryItem.init("product", prototyper.util.find("items", "iron-gear-wheel", "item"))
    product.definition.amount = 12
    factory:insert(product)
    return classes, player, factory, product
end

local function add_line(classes, player, floor, recipe_name)
    local line = classes.Line.init(prototyper.util.find("recipes", recipe_name or "iron-gear-wheel"))
    floor:insert(line)
    line:change_machine_to_proto(player, helpers.find_machine("assembling-machine-2"))
    return line
end

local function add_module(classes, object, amount)
    local module = classes.Module.init(prototyper.util.find("modules", "speed-module", "speed"),
        amount, defaults.get_fallback("qualities").proto)
    object.module_set:insert(module)
    object.module_set:normalize({effects=true})
    return module
end

local function add_beacon(classes, line)
    local beacon = classes.Beacon.init(line, prototyper.util.find("beacons", "beacon"))
    beacon.amount = 3
    add_module(classes, beacon, 2)
    line:set_beacon(beacon)
    return beacon
end

return {
    copy_snapshots = {check=function(context)
        for _, subfloor in ipairs{false, true} do
            local classes, player, factory = fixture(context)
            local source = subfloor and classes.Floor.init(2, factory.top_floor.solver) or nil
            if source then factory.top_floor:insert(source) end
            local line = add_line(classes, player, source or factory.top_floor)
            source = source or line
            line.comment = "Copied configuration"
            local beacon = add_beacon(classes, line)
            solver.update(player, factory)
            lib.clipboard.copy(player, source)
            local clip = lib.globals.player_table(player).clipboard
            assert(source.parent == factory.top_floor and factory.top_floor:count() == 1,
                "Copy must leave its source in place")

            line.comment = "Changed after copy"
            beacon.amount = 1
            beacon.module_set.first:set_amount(1)
            for i = 1, 2 do
                assert(lib.clipboard.paste(player, factory.top_floor))
                local pasted = factory.top_floor:find_last()
                local pasted_line = subfloor and pasted.first or pasted
                assert(pasted ~= source and pasted_line ~= line)
                assert(pasted_line.comment == "Copied configuration")
                assert(pasted_line.beacon.amount == 3 and pasted_line.beacon.module_set.first.amount == 2,
                    "Paste must restore the snapshot, independent of source and earlier pastes")
                pasted_line.comment = "Changed after paste"
                pasted_line.beacon.module_set.first:set_amount(1)
                assert(factory.top_floor:count() == i + 1)
            end
            assert(lib.globals.player_table(player).clipboard == clip, "Paste must retain the clipboard")
        end
    end},
    product_item_compatibility = {check=function(context)
        local classes, player, factory, product = fixture(context)
        lib.clipboard.copy(player, SimpleItem.init(nil, product.proto, 23))
        assert(lib.clipboard.paste(player, product))
        assert(factory.first.definition.type == "amount" and factory.first.definition.amount == 23,
            "ordinary items must still paste as rate-defined products")

        local coal = classes.FactoryItem.init("product", prototyper.util.find("items", "coal", "item"))
        factory:insert(coal)
        lib.clipboard.copy(player, coal)
        local smelting = classes.Line.init(prototyper.util.find("recipes", "iron-plate"))
        factory.top_floor:insert(smelting)
        smelting:change_machine_to_proto(player, helpers.find_machine("stone-furnace"))
        assert(lib.clipboard.paste(player, smelting.machine.fuel))
        assert(smelting.machine.fuel.proto.name == "coal", "products must still paste as fuels")

        local steam = classes.FactoryItem.init("product", prototyper.util.find("items",
            lib.temperature.name_with("steam", 165), "fluid"))
        assert(steam.proto.temperature == 165)
        factory:insert(steam)
        lib.clipboard.copy(player, steam)
        local liquefaction = classes.Line.init(prototyper.util.find("recipes", "coal-liquefaction"))
        factory.top_floor:insert(liquefaction)
        liquefaction:change_machine_to_proto(player, helpers.find_machine("oil-refinery"))
        local target = SimpleItem.init(liquefaction, prototyper.util.find("items", "steam", "fluid"))
        liquefaction.recipe:set_temperature("steam", nil)
        assert(lib.clipboard.paste(player, target))
        assert(liquefaction.recipe.temperatures.steam == 165,
            "fluid products must still paste their temperature onto recipe ingredients")
    end},
    paste_failures = {check=function(context)
        local classes, player, factory, product = fixture(context)
        local line = add_line(classes, player, factory.top_floor)
        local player_table = lib.globals.player_table(player)
        player_table.clipboard = nil
        assert(not lib.clipboard.paste(player, product))
        assert(factory.first == product and factory:count() == 1 and player_table.clipboard == nil)

        lib.clipboard.copy(player, line)
        local clip = player_table.clipboard
        assert(not lib.clipboard.paste(player, product), "a recipe cannot be pasted onto a product")
        assert(factory.first == product and product.definition.amount == 12 and player_table.clipboard == clip)
        lib.clipboard.dummy_paste(player, classes.FactoryItem.init("product"), factory)
        assert(factory:count() == 1 and factory.first == product, "failed dummy paste must remove its placeholder")
        assert(player_table.clipboard == clip)

        for _, category in ipairs{"product", "ingredient"} do
            local existing = classes.FactoryItem.init(category, prototyper.util.find("items", "iron-plate", "item"))
            existing.active = false
            factory:insert(existing)
            local source = SimpleItem.init(nil, existing.proto, 5)
            local success, reason = product:paste(source)
            assert(not success and reason == "already_exists_as_" .. category,
                "Duplicate paste errors must identify the existing side, including disabled targets")
            lib.clipboard.copy(player, source)
            assert(not lib.clipboard.paste(player, product))
            assert(factory:count() == 2 and factory.first == product)
            factory:remove(existing)
        end
    end},
}
