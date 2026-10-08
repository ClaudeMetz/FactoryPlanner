---@diagnostic disable

local helpers = require("helpers")

-- Reproduce fishing towers without depending on Maraxsis or Space Age assets.
return {
    setup = function()
        local icon = "__base__/graphics/icons/raw-fish.png"
        for _, name in ipairs{"fish", "crop", "orphan"} do
            data:extend{{
                type = "plant", name = "test-plant-" .. name,
                icon = icon, icon_size = 64, max_health = 100,
                hidden = name ~= "crop", growth_ticks = 12000,
                pictures = {filename = "__core__/graphics/empty.png", width = 1, height = 1},
                minable = {mining_time = 0.5, results = {{type="item", name="raw-fish", amount=5}}},
                collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
                selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
            }}
            if name ~= "orphan" then
                data:extend{{type="item", name="test-seed-" .. name, icon=icon, icon_size=64,
                    stack_size=100, plant_result="test-plant-" .. name}}
            end
        end
        for _, variant in ipairs{
            {name="all"}, {name="fish", seeds={"test-seed-fish"}},
            {name="crop", seeds={"test-seed-crop"}}, {name="none", seeds={}}
        } do
            local name = "test-tower-" .. variant.name
            data:extend{{
                type="agricultural-tower", name=name, icon=icon, icon_size=64,
                flags={"player-creation"}, max_health=100,
                minable={mining_time=0.5, result=name},
                collision_box={{-1.2, -1.2}, {1.2, 1.2}},
                selection_box={{-1.5, -1.5}, {1.5, 1.5}},
                radius=3, input_inventory_size=2, output_inventory_size=2,
                energy_source={type="electric", usage_priority="secondary-input"},
                energy_usage="100kW", crane_energy_usage="100kW",
                accepted_seeds=variant.seeds,
                surface_conditions={{property="pressure", min=1000}},
                crane={origin={0,0,1}, shadow_direction={1,0,1}, parts={{extendable_length={0,1,1}, extendable_length_grappler={0,0,1}}},
                    speed={arm={turn_rate=0.002, extension_speed=0.005},
                        grappler={vertical_turn_rate=0.002, horizontal_turn_rate=0.01,
                            extension_speed=0.01}}}
            }, {type="item", name=name, icon=icon, icon_size=64, stack_size=10, place_result=name}}
        end
    end,

    check = function()
        local c = helpers.collector()
        for _, name in ipairs{"fish", "crop"} do
            local recipe = prototyper.util.find("recipes", "impostor-test-plant-" .. name)
            c.check(recipe ~= nil, name .. ": planting recipe missing")
            if recipe then
                c.check(recipe.energy == 200, name .. ": incorrect growth time")
                c.check(recipe.products[1].name == "raw-fish" and recipe.products[1].amount == 5,
                    name .. ": incorrect harvest")
                c.check(recipe.ingredients[1].name == "test-seed-" .. name
                    and recipe.ingredients[1].amount == 1, name .. ": incorrect seed input")
                c.check(not recipe.location_restricted, name .. ": cultivated-only plant restricted")
                local machines = {}
                for _, category in pairs(storage.prototypes.machines) do
                    if category.name == recipe.combined_category then machines = category.members end
                end
                local found = {}
                for _, machine in pairs(machines) do
                    found[machine.name] = true
                    if machine.name == "test-tower-" .. name then
                        c.check(machine.speed == 48, name .. ": tower capacity changed")
                        c.check(machine.surface_conditions[1].min == 1000,
                            name .. ": tower surface restriction lost")
                    end
                end
                c.check(found["test-tower-all"], name .. ": unrestricted tower missing")
                c.check(found["test-tower-" .. name], name .. ": matching tower missing")
                local other = name == "fish" and "crop" or "fish"
                c.check(not found["test-tower-" .. other], name .. ": incompatible tower allowed")
                c.check(not found["test-tower-none"], name .. ": empty seed whitelist ignored")
            end
        end
        c.check(not prototyper.util.find("recipes", "impostor-test-plant-orphan"),
            "hidden plant without a seed should not produce a recipe")
        local yumako = prototyper.util.find("recipes", "impostor-yumako-tree")
        c.check(yumako ~= nil and yumako.location_restricted, "vanilla crop recipe lost")
        if yumako then
            local found = {}
            for _, category in pairs(storage.prototypes.machines) do
                if category.name == yumako.combined_category then
                    for _, machine in pairs(category.members) do found[machine.name] = true end
                end
            end
            c.check(found["agricultural-tower"], "vanilla tower missing for yumako")
            c.check(not found["test-tower-fish"], "fish-only tower allowed for yumako")
        end
        c.done()
    end
}
