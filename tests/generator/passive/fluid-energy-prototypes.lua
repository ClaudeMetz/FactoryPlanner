---@diagnostic disable

-- Sets up prototypes covering every fluid energy source configuration, old and new.
-- Inert until called; wire it up via `require("fluid-energy-prototypes")()` from data.lua,
-- or split the sections into individual suite setups once checks exist for them.
--
-- Coverage:
--   burns_fluid=true   unfiltered box              -> category "fluid-fuel" (pre-existing behavior)
--   burns_fluid=true   filtered box, flat usage    -> category "fluid-fuel-filter-test-oil"
--   burns_fluid=false  filtered box, capped scale  -> category "fluid-heat-filter-test-heat-fluid"
--   burns_fluid=false  unfiltered box              -> category "fluid-heat", all heatable fluids
--   burns_fluid=false  usage derived by the game from the source's maximum_temperature
--   fluid box temperature bounds, with and without a filter (they bind either way)
--   two machines sharing a category with different bounds
--   solid burner in the same crafting category (regression, must be untouched)
--   heatable fluid never produced hot / hidden fluid (both must not become heat fuels)

local deepcopy = require("util").table.deepcopy

return function()
    -- ** FLUIDS **

    -- Burned for its heat; produced at 200° and 400° by the recipes below.
    -- Energy per unit: (T - 15) * 500J -> 92.5kJ at 200°, 192.5kJ at 400°
    local heat_fluid = deepcopy(data.raw.fluid.steam)
    heat_fluid.name = "test-heat-fluid"
    heat_fluid.default_temperature = 15
    heat_fluid.max_temperature = 500
    heat_fluid.heat_capacity = "0.5kJ"
    heat_fluid.fuel_value = nil

    -- Has heat capacity, but is only ever produced at its default temperature,
    -- so it must not be offered as a heat fuel
    local cold_fluid = deepcopy(data.raw.fluid.water)
    cold_fluid.name = "test-cold-fluid"
    cold_fluid.heat_capacity = "1kJ"

    -- Produced hot, but hidden, so it must not be offered as a heat fuel either
    local hidden_fluid = deepcopy(heat_fluid)
    hidden_fluid.name = "test-hidden-fluid"
    hidden_fluid.hidden = true

    -- Burned for its fuel value
    local oil_fluid = deepcopy(data.raw.fluid["crude-oil"])
    oil_fluid.name = "test-oil"
    oil_fluid.fuel_value = "2MJ"

    -- Second burnable fluid, since the base game has none: without it, the filtered and
    -- unfiltered burn machines would offer the same single-fuel list
    local diesel_fluid = deepcopy(data.raw.fluid["crude-oil"])
    diesel_fluid.name = "test-diesel"
    diesel_fluid.fuel_value = "3MJ"

    data:extend{heat_fluid, cold_fluid, hidden_fluid, oil_fluid, diesel_fluid}


    -- ** RECIPES **

    -- Fluids only become fuel candidates when some recipe actually produces them,
    -- and heat fuels additionally need a variant above their default temperature
    local function fluid_recipe(name, results)
        return {
            type = "recipe",
            name = name,
            categories = {"crafting-with-fluid"},
            enabled = true,
            energy_required = 1,
            ingredients = {{type = "fluid", name = "water", amount = 10}},
            results = results
        }
    end

    data:extend{
        fluid_recipe("test-heat-fluid-warm", {{type = "fluid", name = "test-heat-fluid", amount = 10, temperature = 200}}),
        fluid_recipe("test-heat-fluid-hot", {{type = "fluid", name = "test-heat-fluid", amount = 10, temperature = 400}}),
        fluid_recipe("test-cold-fluid", {{type = "fluid", name = "test-cold-fluid", amount = 10}}),
        fluid_recipe("test-hidden-fluid", {{type = "fluid", name = "test-hidden-fluid", amount = 10, temperature = 300}}),
        fluid_recipe("test-oil", {{type = "fluid", name = "test-oil", amount = 10}}),
        fluid_recipe("test-diesel", {{type = "fluid", name = "test-diesel", amount = 10}}),
        -- The machines below need a recipe in their category to be generated at all
        {
            type = "recipe-category",
            name = "test-fluid-powered"
        },
        {
            type = "recipe",
            name = "test-fluid-powered-gear",
            categories = {"test-fluid-powered"},
            enabled = true,
            energy_required = 1,
            ingredients = {{type = "item", name = "iron-plate", amount = 2}},
            results = {{type = "item", name = "iron-gear-wheel", amount = 1}}
        }
    }


    -- ** MACHINES **

    -- All 75kW crafters, so they want 1250J per tick at full speed
    local function test_machine(name, energy_source)
        local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-1"])
        machine.name = name
        machine.crafting_categories = {"test-fluid-powered"}
        machine.energy_source = energy_source
        machine.fast_replaceable_group = nil
        machine.next_upgrade = nil
        return machine
    end

    local function input_box(extras)
        local box = {
            production_type = "input",
            volume = 200,
            pipe_covers = pipecoverspictures(),
            pipe_connections = {{flow_direction = "input", direction = defines.direction.north, position = {0, -1}}}
        }
        for key, value in pairs(extras or {}) do box[key] = value end
        return box
    end

    data:extend{
        -- Old case: unfiltered burning, scaling with demand -> "fluid-fuel",
        -- offering both test-oil and test-diesel, sorted by fuel value
        test_machine("test-machine-burn-open", {
            type = "fluid",
            burns_fluid = true,
            scale_fluid_usage = true,
            fluid_box = input_box()
        }),

        -- Filtered burning at a flat rate -> "fluid-fuel-filter-test-oil", offering only test-oil
        -- Always consumes 0.5/tick = 30/s regardless of demand, wasting the excess energy
        test_machine("test-machine-burn-filtered", {
            type = "fluid",
            burns_fluid = true,
            fluid_usage_per_tick = 0.5,
            emissions_per_minute = {pollution = 4},
            fluid_box = input_box{filter = "test-oil"}
        }),

        -- Filtered heat with a scaling cap -> "fluid-heat-filter-test-heat-fluid"
        -- Cap delivers 0.005 * 92500 = 462.5J/tick at 200° (37% speed), 962.5J at 400° (77% speed)
        test_machine("test-machine-heat-capped", {
            type = "fluid",
            burns_fluid = false,
            scale_fluid_usage = true,
            fluid_usage_per_tick = 0.005,
            fluid_box = input_box{filter = "test-heat-fluid"}
        }),

        -- Unfiltered heat, uncapped -> "fluid-heat", offering every heatable fluid: vanilla steam
        -- at 165°/500° (which sorts first on its lower heat capacity, making it the default fuel)
        -- and test-heat-fluid at 200°/400°, but neither test-cold-fluid nor test-hidden-fluid
        test_machine("test-machine-heat-open", {
            type = "fluid",
            burns_fluid = false,
            scale_fluid_usage = true,
            fluid_box = input_box()
        }),

        -- No usage set, so the game derives it from the source's maximum_temperature:
        -- 1250 / ((300 - 15) * 500) ~ 0.00877/tick. Covers non-scaling flat consumption, and
        -- that the maximum_temperature itself must not restrict the offered temperatures
        test_machine("test-machine-heat-derived", {
            type = "fluid",
            burns_fluid = false,
            maximum_temperature = 300,
            fluid_box = input_box{filter = "test-heat-fluid"}
        }),

        -- Same category as test-machine-heat-capped, but the box only accepts 300°-500°,
        -- so of the produced variants only 400° remains selectable here
        test_machine("test-machine-heat-bounded", {
            type = "fluid",
            burns_fluid = false,
            scale_fluid_usage = true,
            fluid_box = input_box{filter = "test-heat-fluid", minimum_temperature = 300, maximum_temperature = 500}
        }),

        -- Box bounds without a filter still bind, despite what the prototype docs say
        test_machine("test-machine-heat-bounded-open", {
            type = "fluid",
            burns_fluid = false,
            scale_fluid_usage = true,
            fluid_box = input_box{minimum_temperature = 300}
        }),

        -- Solid burner in the same crafting category, which must be entirely unaffected
        test_machine("test-machine-solid", {
            type = "burner",
            fuel_categories = {"chemical"},
            fuel_inventory_size = 1
        })
    }
end
