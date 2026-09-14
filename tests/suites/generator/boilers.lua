---@diagnostic disable

-- Covers every boiler configuration: setup defines the prototypes, check asserts
-- what the generator made of them.
--
-- A boiler recipe describes one conversion: a fluid coming in within some temperature range,
-- and a fluid going out at one fixed temperature. It is named after that conversion alone, so
-- boilers that can carry out the same one share a single recipe and are offered as alternatives
-- to each other. Each boiler is its own machine category, which is what those recipes list.
--
-- The two modes differ only in where the outgoing temperature comes from. "output-to-separate-pipe"
-- uses the target_temperature verbatim, and is the only mode that reads the output fluidbox at
-- all. "heat-fluid-inside" has no target and tops the fluid out at its own maximum instead,
-- lowered by the input fluidbox's maximum_temperature where that is set.
--
-- Machine speed is the boiler's energy consumption in watts. The energy a recipe needs is worked
-- out per unit as (goal - input temperature) * heat_capacity, so it depends on the temperature
-- picked for the ingredient, and the solver replaces the recipe's own energy with it. That energy
-- is still a placeholder 1 rather than 0, as recipes without any energy get no machines at all.
--
-- Coverage:
--   separate pipe, in and out filtered      cold 15-100 -> steam 165, 5 out per 1 in
--   separate pipe, same conversion, twin    shares the recipe above, adding a second machine
--   separate pipe, fluid energy source      shares it too, once its fuel box is ignored
--   separate pipe, no output filter         wide 0-300 -> wide 300, capped at the target
--   separate pipe, unfiltered input         one recipe per fluid, skipping ones already hotter
--   heat in place, filtered                 wide 0-500 -> wide 500, the fluid's own maximum
--   heat in place, box caps the maximum     wide 0-300 -> wide 300, shares the separate pipe one
--   heat in place, unfiltered input         one recipe per fluid that can be heated at all
--   heat in place, mode left unspecified    defaults to this mode rather than being ignored
--   an input no pipe can connect to         internal to the entity, so no recipe at all
--   an output no pipe can connect to        still read, since only the input has to be reachable
--   a fluid that can never be heated        max_temperature equal to default, so never offered
--   a parameter and a hidden fluid          heatable, but neither may ever be offered either

local helpers = require("helpers")

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy

        -- ** FLUIDS **

        -- The everyday input, worth 1kJ per degree. Boiled to 165° it takes (165 - 15) * 1000J,
        -- so 150kJ per unit, and a 1.5MW boiler gets through 10 of them a second
        local cold_fluid = deepcopy(data.raw.fluid.water)
        cold_fluid.name = "test-boil-cold"
        cold_fluid.default_temperature = 15
        cold_fluid.max_temperature = 100
        cold_fluid.heat_capacity = "1kJ"
        cold_fluid.auto_barrel = false

        -- What the filtered boilers put out. Its heat capacity is a fifth of the input's, so five
        -- units come out for every one that goes in, which is where the ratio in the recipes is from
        local steam_fluid = deepcopy(data.raw.fluid.steam)
        steam_fluid.name = "test-boil-steam"
        steam_fluid.default_temperature = 15
        steam_fluid.max_temperature = 1000
        steam_fluid.heat_capacity = "0.2kJ"
        steam_fluid.fuel_value = nil

        -- Has room to be heated a long way, so it can show both what a target temperature does and
        -- what topping out at the fluid's own maximum does, without another fluid being involved
        local wide_fluid = deepcopy(data.raw.fluid.steam)
        wide_fluid.name = "test-boil-wide"
        wide_fluid.default_temperature = 0
        wide_fluid.max_temperature = 500
        wide_fluid.heat_capacity = "0.5kJ"
        wide_fluid.fuel_value = nil

        -- Already hotter than the 165° target below, so the unfiltered separate pipe boiler has
        -- nothing to do with it and must not offer a recipe consuming it
        local hot_fluid = deepcopy(data.raw.fluid.steam)
        hot_fluid.name = "test-boil-hot"
        hot_fluid.default_temperature = 500
        hot_fluid.max_temperature = 1000
        hot_fluid.heat_capacity = "0.5kJ"
        hot_fluid.fuel_value = nil

        -- Leaves max_temperature unset, which makes it equal to default_temperature, so this fluid
        -- can never be heated at all. Boilers heating in place must skip it entirely
        local flat_fluid = deepcopy(data.raw.fluid.water)
        flat_fluid.name = "test-boil-flat"
        flat_fluid.default_temperature = 25
        flat_fluid.max_temperature = nil
        flat_fluid.heat_capacity = "1kJ"
        flat_fluid.auto_barrel = false

        -- Burned by the boiler with a fluid energy source, purely so that its fuel fluidbox exists
        local fuel_fluid = deepcopy(data.raw.fluid["crude-oil"])
        fuel_fluid.name = "test-boil-fuel"
        fuel_fluid.fuel_value = "2MJ"
        fuel_fluid.auto_barrel = false

        -- Both are as heatable as the wide fluid they copy, so an unfiltered boiler would happily
        -- take them if they weren't skipped. A parameter is only a placeholder for blueprints, and
        -- a hidden fluid isn't something the player ever gets to handle, so neither may be offered
        local parameter_fluid = deepcopy(wide_fluid)
        parameter_fluid.name = "test-boil-parameter"
        parameter_fluid.parameter = true
        parameter_fluid.auto_barrel = false

        local hidden_fluid = deepcopy(wide_fluid)
        hidden_fluid.name = "test-boil-hidden"
        hidden_fluid.hidden = true
        hidden_fluid.auto_barrel = false

        data:extend{cold_fluid, steam_fluid, wide_fluid, hot_fluid, flat_fluid, fuel_fluid,
            parameter_fluid, hidden_fluid}


        -- ** RECIPES **

        -- Fluids need a recipe producing them to exist as items at all, and the temperatures a
        -- boiler ingredient can be set to come from the variants other recipes produce
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
            fluid_recipe("test-boil-cold", {type = "fluid", name = "test-boil-cold", amount = 10}),
            fluid_recipe("test-boil-steam", {type = "fluid", name = "test-boil-steam", amount = 10}),
            fluid_recipe("test-boil-wide", {type = "fluid", name = "test-boil-wide", amount = 10}),
            fluid_recipe("test-boil-hot", {type = "fluid", name = "test-boil-hot", amount = 10, temperature = 500}),
            fluid_recipe("test-boil-flat", {type = "fluid", name = "test-boil-flat", amount = 10}),
            fluid_recipe("test-boil-fuel", {type = "fluid", name = "test-boil-fuel", amount = 10})
        }


        -- ** BOILERS **

        local function input_box(extras)
            local box = {
                production_type = "input-output",
                volume = 200,
                pipe_covers = pipecoverspictures(),
                pipe_connections = {{flow_direction = "input-output", direction = defines.direction.west, position = {-1, 0.5}}}
            }
            for key, value in pairs(extras or {}) do box[key] = value end
            return box
        end

        local function output_box(extras)
            local box = {
                production_type = "output",
                volume = 200,
                pipe_covers = pipecoverspictures(),
                pipe_connections = {{flow_direction = "output", direction = defines.direction.east, position = {1, 0.5}}}
            }
            for key, value in pairs(extras or {}) do box[key] = value end
            return box
        end

        -- Overrides travel in a table, which a nil can't be part of, so removing one of the defaults
        -- the helper sets below takes a marker of its own
        local REMOVE = {}

        -- All based on the vanilla boiler, so they inherit its graphics and burner energy source.
        -- 1.5MW each, which is the speed every one of them is expected to end up with
        local function test_boiler(name, overrides)
            local boiler = deepcopy(data.raw.boiler.boiler)
            boiler.name = name
            boiler.fast_replaceable_group = nil
            boiler.next_upgrade = nil
            boiler.energy_consumption = "1.5MW"
            boiler.mode = "output-to-separate-pipe"
            boiler.target_temperature = 165
            boiler.fluid_box = input_box{filter = "test-boil-cold"}
            boiler.output_fluid_box = output_box{filter = "test-boil-steam"}
            for key, value in pairs(overrides) do
                if value == REMOVE then boiler[key] = nil else boiler[key] = value end
            end
            return boiler
        end

        data:extend{
            -- The baseline, and the vanilla arrangement: one fluid in, another out, at a fixed
            -- temperature. Takes cold at 15° to 100°, puts out steam at exactly 165°
            test_boiler("test-boiler-separate", {}),

            -- A different entity doing the very same thing. It must not produce a second recipe,
            -- it must attach itself to the one above so both are offered for it
            test_boiler("test-boiler-twin", {}),

            -- Burns a fluid rather than an item, which puts a third fluidbox on the entity with a
            -- production type that looks just like the boiler's own input. That box has to be
            -- ignored, which shows up as this sharing the same recipe as the two above
            test_boiler("test-boiler-fluid-burner", {
                energy_source = {
                    type = "fluid",
                    burns_fluid = true,
                    effectivity = 1,
                    fluid_usage_per_tick = 0.01,
                    fluid_box = {
                        production_type = "input",
                        volume = 200,
                        pipe_covers = pipecoverspictures(),
                        pipe_connections = {{flow_direction = "input", direction = defines.direction.south, position = {0, 0.5}}},
                        filter = "test-boil-fuel"
                    }
                }
            }),

            -- No filter on the output, so the fluid stays itself and simply comes out hotter. The
            -- ingredient stops at the 300° target, as anything hotter going in could not be heated
            test_boiler("test-boiler-same-fluid", {
                target_temperature = 300,
                fluid_box = input_box{filter = "test-boil-wide"},
                output_fluid_box = output_box()
            }),

            -- Takes anything at all and makes steam of it, so it gets a recipe per fluid that is
            -- ever colder than 165°. Notably not one for the hot fluid, which starts out at 500°
            test_boiler("test-boiler-open", {
                fluid_box = input_box()
            }),

            -- Heats its fluid where it sits, with no target temperature of its own, so the fluid
            -- goes all the way to the 500° maximum it declares. The output box is never looked at
            test_boiler("test-boiler-inside", {
                mode = "heat-fluid-inside",
                target_temperature = REMOVE,
                fluid_box = input_box{filter = "test-boil-wide"},
                output_fluid_box = output_box()
            }),

            -- Same, but its fluidbox refuses anything above 300°, which is what the fluid now tops
            -- out at. That makes this the identical conversion to test-boiler-same-fluid above, and
            -- the two share a recipe despite being in different modes
            test_boiler("test-boiler-inside-capped", {
                mode = "heat-fluid-inside",
                target_temperature = REMOVE,
                fluid_box = input_box{filter = "test-boil-wide", maximum_temperature = 300},
                output_fluid_box = output_box()
            }),

            -- Unfiltered and heating in place, so it gets a recipe for every fluid with any room
            -- above its default temperature, each going to that fluid's own maximum. The flat
            -- fluid has no such room and must be left out
            test_boiler("test-boiler-inside-open", {
                mode = "heat-fluid-inside",
                target_temperature = REMOVE,
                fluid_box = input_box(),
                output_fluid_box = output_box()
            }),

            -- Its input only takes a connection category of its own, which no pipe carries. That
            -- makes it a part of some larger entity that the player can never feed, so it must
            -- produce no recipes at all, not one per fluid like the unfiltered boilers above
            test_boiler("test-boiler-special-input", {
                fluid_box = input_box{pipe_connections = {{flow_direction = "input-output",
                    direction = defines.direction.west, position = {-1, 0.5},
                    connection_category = "test-boil-special"}}}
            }),

            -- The other way around: pipes reach the input, only the output is special. That output
            -- is still what comes out, so this ends up doing the very same conversion as the
            -- baseline boiler and shares its recipe, rather than putting out its input fluid
            test_boiler("test-boiler-special-output", {
                output_fluid_box = output_box{filter = "test-boil-steam",
                    pipe_connections = {{flow_direction = "output",
                        direction = defines.direction.east, position = {1, 0.5},
                        connection_category = "test-boil-special"}}}
            }),

            -- Says nothing about its mode, which makes it heat in place rather than being skipped
            -- for the target temperature it consequently doesn't have
            test_boiler("test-boiler-no-mode", {
                mode = REMOVE,
                target_temperature = REMOVE,
                fluid_box = input_box{filter = "test-boil-cold"},
                output_fluid_box = output_box()
            })
        }
    end,

    check = function()
        local c = helpers.collector()
        local find = prototyper.util.find

        -- Every boiler in its own category, at its energy consumption as speed
        local boilers = {"separate", "twin", "fluid-burner", "same-fluid", "open",
            "inside", "inside-capped", "inside-open", "no-mode", "special-output"}
        for _, suffix in ipairs(boilers) do
            local name = "test-boiler-" .. suffix
            helpers.check_machine(c, name, {category = "boiler-" .. name, speed = 1500000})
        end

        -- The fluid burner's fuel box maps to a burner instead of passing as the input
        helpers.check_machine(c, "test-boiler-fluid-burner",
            {fuel_category = "fluid-fuel-filter-test-boil-fuel"})

        -- Recipes are named for the conversion and shared by every boiler doing it
        local function check_recipe(name, categories)
            local proto = find("recipes", name)
            if not proto then
                c.check(false, name .. ": missing")
                return nil
            end
            for _, category in ipairs(categories) do
                c.check(proto.categories[category] ~= nil,
                    name .. ": missing category " .. category)
            end
            return proto
        end

        local baseline = check_recipe("impostor-boil-test-boil-cold-15-100-test-boil-steam-165",
            {"boiler-test-boiler-separate", "boiler-test-boiler-twin",
             "boiler-test-boiler-fluid-burner", "boiler-test-boiler-open",
             "boiler-test-boiler-special-output"})
        if baseline then
            c.check(helpers.approx(baseline.products[1].amount, 5),
                "baseline: expected 5 steam out per cold in")
            c.check(baseline.products[1].temperature == 165,
                "baseline: expected steam at exactly 165")
            c.check(baseline.energy == 1,
                "baseline: expected placeholder energy 1, replaced by the solver")
        end

        -- Different modes achieving the same conversion share a recipe
        check_recipe("impostor-boil-test-boil-wide-0-300-test-boil-wide-300",
            {"boiler-test-boiler-same-fluid", "boiler-test-boiler-inside-capped"})
        check_recipe("impostor-boil-test-boil-wide-0-500-test-boil-wide-500",
            {"boiler-test-boiler-inside", "boiler-test-boiler-inside-open"})
        -- No mode set defaults to heating in place rather than being skipped
        check_recipe("impostor-boil-test-boil-cold-15-100-test-boil-cold-100",
            {"boiler-test-boiler-no-mode"})

        -- A boiler no pipe can feed is a part of a bigger entity, and offers nothing on its own,
        -- which takes its machine with it. Its unfiltered input would otherwise boil every fluid
        c.check(helpers.find_machine("test-boiler-special-input") == nil,
            "unreachable input: machine must not be offered")

        -- Fluids that must never be offered anywhere
        for _, recipe_proto in pairs(storage.prototypes.recipes) do
            c.check(recipe_proto.categories["boiler-test-boiler-special-input"] == nil,
                "unreachable input: recipe offered anyway: " .. recipe_proto.name)
            c.check(not recipe_proto.name:find("test%-boil%-parameter"),
                "parameter fluid offered: " .. recipe_proto.name)
            c.check(not recipe_proto.name:find("test%-boil%-hidden"),
                "hidden fluid offered: " .. recipe_proto.name)
            c.check(not recipe_proto.name:find("^impostor%-boil%-test%-boil%-hot%-.*steam"),
                "already-hot fluid boiled to steam: " .. recipe_proto.name)
        end
        -- An unreachable output is still the fluid that comes out, so the boiler above must not
        -- have fallen back to putting out its own input fluid instead
        c.check(find("recipes", "impostor-boil-test-boil-cold-15-100-test-boil-cold-165") == nil,
            "unreachable output: fell back to the input fluid")

        -- The flat fluid has no room above its default temperature
        c.check(find("recipes", "impostor-boil-test-boil-flat-25-25-test-boil-flat-25") == nil,
            "flat fluid must not be heatable in place")

        c.done()
    end
}
