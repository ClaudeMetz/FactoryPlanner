---@diagnostic disable

local helpers = require("helpers")
local category_a, category_b, category_c = "test-fuel-a", "test-fuel-b", "test-fuel-c"
local combined = category_a .. "|" .. category_b

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy
        data:extend{
            {type="fuel-category", name=category_a},
            {type="fuel-category", name=category_b},
            {type="fuel-category", name=category_c},
            {type="recipe-category", name="test-fuel-crafting"},
            {type="recipe", name="test-fuel-gear", categories={"test-fuel-crafting"},
                ingredients={{type="item", name="iron-plate", amount=2}},
                results={{type="item", name="iron-gear-wheel", amount=1}}}
        }

        for suffix, categories in pairs{a={category_a}, b={category_b},
            ab={category_a, category_b}, c={category_c}} do
            local fuel = deepcopy(data.raw.item.coal)
            fuel.name = "test-fuel-" .. suffix
            fuel.fuel_categories = categories
            fuel.fuel_value = (suffix == "ab") and "8MJ" or "4MJ"
            local recipe = {type="recipe", name=fuel.name, categories={"crafting"},
                ingredients={{type="item", name="coal", amount=1}},
                results={{type="item", name=fuel.name, amount=1}}}

            local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-1"])
            machine.name = "test-fuel-machine-" .. suffix
            machine.crafting_categories = {"test-fuel-crafting"}
            machine.energy_source = {type="burner", fuel_categories=categories, fuel_inventory_size=1}
            machine.fast_replaceable_group = nil
            machine.next_upgrade = nil
            data:extend{fuel, recipe, machine}
        end
    end,

    check = function(context)
        local find = prototyper.util.find
        for _, category in ipairs{category_a, category_b, combined} do
            assert(find("fuels", "test-fuel-ab", category), "Shared fuel must fit " .. category)
            assert(not find("fuels", "test-fuel-c", category), "Unrelated fuel must not fit " .. category)
        end
        assert(table_size(find("fuels", nil, combined).members) == 3,
            "Overlapping categories must not duplicate fuels")
        assert(not find("fuels", "test-fuel-a", category_b), "A-only fuel must not fit B")
        assert(not find("fuels", "test-fuel-b", category_a), "B-only fuel must not fit A")

        local player = game.players[1]
        local player_table = lib.globals.player_table(player)
        local previous = player_table.preferences.default_prototypes
        player_table.preferences.default_prototypes = {fuels=defaults.get_fallback("fuels")}
        local ok, message = xpcall(function()
            defaults.set(player, "fuels", {prototype="test-fuel-a"}, category_a)
            defaults.set(player, "fuels", {prototype="test-fuel-b"}, category_b)
            defaults.set(player, "fuels", {prototype="test-fuel-ab"}, combined)
            defaults.migrate(player_table)
            for category, name in pairs{[category_a]="test-fuel-a", [category_b]="test-fuel-b",
                [combined]="test-fuel-ab"} do
                assert(defaults.get(player, "fuels", category).proto.name == name,
                    "Migration must preserve the independent default for " .. category)
            end

            local line = context.classes.Line.init(find("recipes", "test-fuel-gear"), "produce")
            local function change_machine(suffix)
                line:change_machine_to_proto(player, helpers.find_machine("test-fuel-machine-" .. suffix))
                return line.machine.fuel
            end

            local fuel = change_machine("ab")
            assert(fuel.proto.name == "test-fuel-ab", "New machine must use its combination's default")
            for _, suffix in ipairs{"a", "b", "ab"} do
                assert(change_machine(suffix) == fuel, "Switching compatible machines must retain the fuel object")
                assert(fuel.proto == find("fuels", "test-fuel-ab", line.machine.proto.burner.combined_category),
                    "Switching must use the destination category's fuel prototype")
            end
            local filter = line.machine:compile_fuel_filter()
            assert(#filter[1].name == 3, "Picker must offer each compatible fuel once")

            -- Validation must also retain a shared fuel across category changes
            for _, suffix in ipairs{"b", "a", "ab"} do
                line.machine.proto = helpers.find_machine("test-fuel-machine-" .. suffix)
                assert(fuel:validate(player), "Shared fuel must validate in " .. suffix)
                assert(fuel.proto.combined_category == line.machine.proto.burner.combined_category)
            end
            line.machine.proto = helpers.find_machine("test-fuel-machine-c")
            assert(not fuel:validate(player), "Unrelated fuel must fail validation")
            assert(change_machine("c").proto.name == "test-fuel-c", "Incompatible fuel must use the new default")

            defaults.set_all(player, "fuels", {prototype="test-fuel-ab"})
            for _, category in ipairs{category_a, category_b, combined} do
                assert(defaults.get(player, "fuels", category).proto.name == "test-fuel-ab",
                    "Save for all must update every compatible combination")
            end
            assert(defaults.get(player, "fuels", category_c).proto.name == "test-fuel-c",
                "Save for all must preserve unrelated defaults")
        end, debug.traceback)
        player_table.preferences.default_prototypes = previous
        assert(ok, message)
    end
}
