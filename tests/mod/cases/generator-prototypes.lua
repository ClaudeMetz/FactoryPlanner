---@diagnostic disable

-- Covers every power generating machine configuration: setup defines the prototypes,
-- check asserts what the generator made of them.
--
-- Every generator lands in the single "electricity" recipe category, so they are all offered
-- as alternatives to each other. What differs is the fuel they take, which is why the fuel
-- category and the fuel list per machine are the interesting part of each one.
--
-- Machine speed is the machine's power output in watts, since the electricity recipe has an
-- energy of 1J. Note that the prototype docs require either a fluid box filter or an explicit
-- max_power_output, so this value is always derivable by the game.
--
-- Coverage, with the expected speed and fuel category of each:
--   heat, flat usage        1.155MW  fluid-heat-filter-test-gen-heat  (wastes 20.6% on 500°)
--   heat, capped output     500kW    fluid-heat-filter-test-gen-heat  (wastes 56.7% on 400°)
--   heat, scaling usage     1.155MW  fluid-heat-filter-test-gen-heat  (never wastes any)
--   heat, bounded box       1.155MW  fluid-heat-filter-test-gen-heat  (400° and 500° only)
--   heat, spent fluid       855kW    fluid-heat-filter-test-gen-spent (+ 6/s coolant)
--   heat, spent fallback    855kW    fluid-heat-filter-test-gen-spent (+ 12/s coolant)
--   burn, filtered          1.2MW    fluid-fuel-filter-test-gen-fuel
--   burn, unfiltered        1.8MW    fluid-fuel                       (1.2MW on the weak fuel)
--   burn, effectivity 0.5   600kW    fluid-fuel-filter-test-gen-fuel  (burns 1.2MW of fuel)
--   burner generator        1MW      chemical                         (burns 2MW of fuel)
--
-- Vanilla references, which need no setup: steam engine 900kW and steam turbine 5.82MW, both
-- in fluid-heat-filter-steam, offering steam at 165° and 500°.
--
-- The prototypes are deliberately not shared with the other cases, but they do load into the
-- same game, so generic categories ("fluid-fuel", "chemical") contain members from more than
-- one case: assert membership and targeted absences, never exclusive category contents.

local helpers = require("helpers")

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy

        -- ** FLUIDS **

        -- Burned for its heat, at (T - 15) * 500J per unit, so 92.5kJ at 200°, 192.5kJ at 400°
        -- and 242.5kJ at 500°. The recipes below produce it at each of those three.
        local heat_fluid = deepcopy(data.raw.fluid.steam)
        heat_fluid.name = "test-gen-heat"
        heat_fluid.default_temperature = 15
        heat_fluid.max_temperature = 500
        heat_fluid.heat_capacity = "0.5kJ"
        heat_fluid.fuel_value = nil

        -- Carries its own spent fluid, which a generator falls back to when it defines an output
        -- box but no spent_fluid of its own. Only ever produced at 300°, worth 142.5kJ per unit.
        local spent_source_fluid = deepcopy(heat_fluid)
        spent_source_fluid.name = "test-gen-spent"
        spent_source_fluid.spent_fluid = {name = "test-gen-coolant", amount = 2, temperature = 15}

        -- What the two spent fluid generators put out. Never hot, so it can't be a heat fuel
        -- itself, but it still needs a recipe of its own for the item to exist at 15°.
        local coolant_fluid = deepcopy(data.raw.fluid.water)
        coolant_fluid.name = "test-gen-coolant"
        coolant_fluid.auto_barrel = false

        -- Burned for their fuel value. Two of them, since the base game has no burnable fluid at
        -- all, and the unfiltered generator needs more than one to actually choose between.
        local fuel_fluid = deepcopy(data.raw.fluid["crude-oil"])
        fuel_fluid.name = "test-gen-fuel"
        fuel_fluid.fuel_value = "2MJ"
        fuel_fluid.auto_barrel = false

        local rich_fuel_fluid = deepcopy(data.raw.fluid["crude-oil"])
        rich_fuel_fluid.name = "test-gen-fuel-rich"
        rich_fuel_fluid.fuel_value = "3MJ"
        rich_fuel_fluid.auto_barrel = false

        data:extend{heat_fluid, spent_source_fluid, coolant_fluid, fuel_fluid, rich_fuel_fluid}


        -- ** RECIPES **

        -- Fluids only become fuel candidates when some recipe actually produces them, and heat
        -- fuels additionally need a variant above their default temperature to carry any energy
        local function fluid_recipe(name, result)
            return {
                type = "recipe",
                name = name,
                categories = {"crafting-with-fluid"},
                enabled = true,
                energy_required = 1,
                ingredients = {{type = "fluid", name = "water", amount = 10}},
                results = {result}
            }
        end

        data:extend{
            fluid_recipe("test-gen-heat-warm", {type = "fluid", name = "test-gen-heat", amount = 10, temperature = 200}),
            fluid_recipe("test-gen-heat-hot", {type = "fluid", name = "test-gen-heat", amount = 10, temperature = 400}),
            fluid_recipe("test-gen-heat-max", {type = "fluid", name = "test-gen-heat", amount = 10, temperature = 500}),
            fluid_recipe("test-gen-spent", {type = "fluid", name = "test-gen-spent", amount = 10, temperature = 300}),
            fluid_recipe("test-gen-coolant", {type = "fluid", name = "test-gen-coolant", amount = 10}),
            fluid_recipe("test-gen-fuel", {type = "fluid", name = "test-gen-fuel", amount = 10}),
            fluid_recipe("test-gen-fuel-rich", {type = "fluid", name = "test-gen-fuel-rich", amount = 10})
        }


        -- ** GENERATORS **

        local function input_box(extras)
            local box = {
                production_type = "input",
                volume = 200,
                pipe_covers = pipecoverspictures(),
                pipe_connections = {{flow_direction = "input", direction = defines.direction.south, position = {0, 1}}}
            }
            for key, value in pairs(extras or {}) do box[key] = value end
            return box
        end

        local function output_box()
            return {
                production_type = "output",
                volume = 200,
                pipe_covers = pipecoverspictures(),
                pipe_connections = {{flow_direction = "output", direction = defines.direction.north, position = {0, -1}}}
            }
        end

        -- All based on the steam engine, so they inherit its graphics and electric energy source
        local function test_generator(name, overrides)
            local generator = deepcopy(data.raw.generator["steam-engine"])
            generator.name = name
            generator.fast_replaceable_group = nil
            generator.next_upgrade = nil
            generator.effectivity = 1
            generator.maximum_temperature = 400
            generator.burns_fluid = false
            generator.scale_fluid_usage = false
            generator.max_power_output = nil
            generator.fluid_box = input_box{filter = "test-gen-heat"}
            for key, value in pairs(overrides) do generator[key] = value end
            return generator
        end

        data:extend{
            -- The baseline: 0.1/tick of a fluid worth 192.5kJ at the 400° it caps out at, so
            -- (400 - 15) * 0.1 * 500 * 60 = 1.155MW, consuming a flat 6 fluid/s.
            -- On 200° fluid it makes only 555kW, and on 500° it still makes 1.155MW while
            -- consuming the same 6/s, wasting 20.6% of what it takes in
            test_generator("test-generator-heat-flat", {
                fluid_usage_per_tick = 0.1
            }),

            -- Capped well below what the fluid delivers. On 400° it takes in 19.25kJ/tick while
            -- only being able to use 8.33kJ of it, so 56.7% is wasted
            test_generator("test-generator-heat-capped", {
                fluid_usage_per_tick = 0.1,
                max_power_output = "500kW"
            }),

            -- Scaling usage only matters above maximum_temperature: on 500° fluid it draws
            -- 4.76 fluid/s rather than the flat 6, making the same 1.155MW while wasting nothing
            test_generator("test-generator-heat-scaling", {
                fluid_usage_per_tick = 0.1,
                scale_fluid_usage = true
            }),

            -- The box only accepts 300°-500°, so of the three produced variants only 400° and 500°
            -- are offered. Shares its fuel category with the machines above, since bounds live on
            -- the machine rather than in the category name
            test_generator("test-generator-heat-bounded", {
                fluid_usage_per_tick = 0.1,
                fluid_box = input_box{filter = "test-gen-heat", minimum_temperature = 300, maximum_temperature = 500}
            }),

            -- Puts out spent fluid alongside its power, which is new to generators in 2.1. Capped at
            -- 300° it makes 855kW, and its own spec turns 6 fluid/s of input into 6 coolant/s
            test_generator("test-generator-heat-spent", {
                fluid_usage_per_tick = 0.1,
                maximum_temperature = 300,
                fluid_box = input_box{filter = "test-gen-spent"},
                spent_fluid = {name = "test-gen-coolant", amount = 1, temperature = 15},
                output_fluid_box = output_box()
            }),

            -- Same, but with no spent_fluid of its own, so it has to fall back to the one on the
            -- fluid it consumes. That specifies an amount of 2, so 6 fluid/s becomes 12 coolant/s
            test_generator("test-generator-heat-fallback", {
                fluid_usage_per_tick = 0.1,
                maximum_temperature = 300,
                fluid_box = input_box{filter = "test-gen-spent"},
                output_fluid_box = output_box()
            }),

            -- Burns its fluid for the fuel value instead: 0.01/tick of a 2MJ fluid is 20kJ/tick
            -- = 1.2MW, at 0.6 fluid/s. The temperature of the fluid is irrelevant here
            test_generator("test-generator-burn-filtered", {
                burns_fluid = true,
                fluid_usage_per_tick = 0.01,
                fluid_box = input_box{filter = "test-gen-fuel"}
            }),

            -- Unfiltered, so it must declare its output itself. Sized for the 3MJ fuel, which runs
            -- it at the full 1.8MW, while the 2MJ one only reaches 1.2MW on the same 0.6/s
            test_generator("test-generator-burn-open", {
                burns_fluid = true,
                fluid_usage_per_tick = 0.01,
                max_power_output = "1.8MW",
                fluid_box = input_box()
            }),

            -- Half of the fuel's energy comes out as power, so this makes 600kW while burning the
            -- same 1.2MW of fuel the filtered machine above does. Its pollution must follow the
            -- 1.2MW it burns, not the 600kW it puts out
            test_generator("test-generator-burn-lossy", {
                burns_fluid = true,
                effectivity = 0.5,
                fluid_usage_per_tick = 0.01,
                fluid_box = input_box{filter = "test-gen-fuel"},
                energy_source = {
                    type = "electric",
                    usage_priority = "secondary-output",
                    emissions_per_minute = {pollution = 10}
                }
            })
        }


        -- ** BURNER GENERATOR **

        -- Solid fuel equivalent. Its max energy usage is 2MW, the fuel it burns, which must not be
        -- mistaken for its 1MW output. Burns 0.5 coal/s and pollutes for the full 2MW
        local burner_generator = deepcopy(data.raw["burner-generator"]["burner-generator"])
        burner_generator.name = "test-burner-generator"
        burner_generator.hidden = false
        burner_generator.fast_replaceable_group = nil
        burner_generator.next_upgrade = nil
        burner_generator.max_power_output = "1MW"
        burner_generator.burner = {
            type = "burner",
            fuel_categories = {"chemical"},
            effectivity = 0.5,
            fuel_inventory_size = 1,
            emissions_per_minute = {pollution = 20}
        }

        data:extend{burner_generator}
    end,

    check = function()
        local c = helpers.collector()
        local find = prototyper.util.find

        -- Speed is the power output in watts, paired with the 1J electricity recipe
        local function generator(name, speed, fuel_category, burner)
            return helpers.check_machine(c, name, {category = "electricity",
                speed = speed, fuel_category = fuel_category, burner = burner})
        end

        generator("test-generator-heat-flat", 1155000, "fluid-heat-filter-test-gen-heat",
            {burns_fluid = false, scale_fluid_usage = false})
        generator("test-generator-heat-capped", 500000, "fluid-heat-filter-test-gen-heat")
        generator("test-generator-heat-scaling", 1155000, "fluid-heat-filter-test-gen-heat",
            {scale_fluid_usage = true})
        generator("test-generator-heat-bounded", 1155000, "fluid-heat-filter-test-gen-heat",
            {minimum_temperature = 300, maximum_temperature = 500})

        -- Spent fluid comes from the machine's own spec, or falls back to the fluid's
        local spent = generator("test-generator-heat-spent", 855000,
            "fluid-heat-filter-test-gen-spent", {produces_spent_fluid = true})
        c.check(spent and spent.burner.spent_fluid and spent.burner.spent_fluid.amount == 1,
            "heat-spent: expected own spent_fluid with amount 1")
        local fallback = generator("test-generator-heat-fallback", 855000,
            "fluid-heat-filter-test-gen-spent", {produces_spent_fluid = true})
        c.check(fallback and fallback.burner.spent_fluid == nil,
            "heat-fallback: expected no spent_fluid of its own")

        generator("test-generator-burn-filtered", 1200000, "fluid-fuel-filter-test-gen-fuel",
            {burns_fluid = true})
        local open = generator("test-generator-burn-open", 1800000, "fluid-fuel",
            {burns_fluid = true})
        c.check(open and open.burner.fluid_filter == nil,
            "burn-open: expected no fluid filter")
        generator("test-generator-burn-lossy", 600000, "fluid-fuel-filter-test-gen-fuel",
            {effectivity = 0.5})

        -- Speed is the output, effectivity carries the 2MW that is actually burned
        generator("test-burner-generator", 1000000, "chemical", {effectivity = 0.5})

        -- Vanilla references, generated without any setup
        generator("steam-engine", 900000, "fluid-heat-filter-steam")
        generator("steam-turbine", 5820000, "fluid-heat-filter-steam")

        -- The fuels the categories above offer
        local heat_fuel = find("fuels", "test-gen-heat", "fluid-heat-filter-test-gen-heat")
        c.check(heat_fuel and helpers.approx(heat_fuel.heat_capacity, 500),
            "test-gen-heat: expected heat fuel with capacity 500")
        local burn_fuel = find("fuels", "test-gen-fuel", "fluid-fuel-filter-test-gen-fuel")
        c.check(burn_fuel and helpers.approx(burn_fuel.fuel_value, 2e6),
            "test-gen-fuel: expected burnable fuel worth 2MJ")
        c.check(find("fuels", "test-gen-fuel", "fluid-fuel") ~= nil,
            "test-gen-fuel: missing from the unfiltered category")
        c.check(find("fuels", "test-gen-fuel-rich", "fluid-fuel") ~= nil,
            "test-gen-fuel-rich: missing from the unfiltered category")
        c.check(find("fuels", "steam", "fluid-heat-filter-steam") ~= nil,
            "steam: missing as a heat fuel")

        c.check(find("recipes", "impostor-electricity") ~= nil,
            "electricity recipe missing")

        c.done()
    end
}
