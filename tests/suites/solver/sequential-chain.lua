---@diagnostic disable

-- Runs a hand-computable setup through the full solver stack: factory objects built
-- the way the GUI would build them, solved for real, results checked against
-- pen-and-paper numbers.
--
-- Setup keeps its prototypes deliberately plain, with every number chosen so the
-- expected results can be worked out by hand:
--
--   2 test-solver-ore -> 1 test-solver-plate (0.5s) -> half of 2 per test-solver-gear (1s)
--
-- The machine crafts at speed 1 and draws a flat 100kW with no drain, so a line of N
-- machines consumes exactly N * 100kW. Keep these prototypes boring: the generator's
-- own edge cases are covered by the other cases, and anything clever here couples
-- solver expectations to generator behavior. A change in the checked numbers means
-- solver behavior changed.

local helpers = require("helpers")

-- Builds a factory in a fresh district with one line per recipe name, in order
local function build_factory(classes, player, recipe_names)
    local district = classes.District.init()
    local factory = classes.Factory.init("test-factory", false)
    district:insert(factory)

    for _, recipe_name in ipairs(recipe_names) do
        local line = classes.Line.init(prototyper.util.find("recipes", recipe_name), "produce")
        factory.top_floor:insert(line)
        line.machine = classes.Machine.init(line,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        line.machine:summarize_effects()
        line.machine:normalize_fuel(player)
    end

    return factory
end

local function add_product(classes, factory, item_name, amount)
    local product = classes.TLProduct.init(prototyper.util.find("items", item_name, "item"))
    product.required_amount = amount  -- per second
    factory:insert(product)
    return product
end

-- Returns the amount of the named item in an object's item list, or nil
local function item_amount(item_list, name)
    for _, item in pairs(item_list) do
        if item.proto.name == name then return item.amount end
    end
    return nil
end

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy

        local function test_item(name, base)
            local item = deepcopy(data.raw.item[base])
            item.name = name
            return item
        end

        data:extend{
            test_item("test-solver-ore", "iron-ore"),
            test_item("test-solver-plate", "iron-plate"),
            test_item("test-solver-gear", "iron-gear-wheel"),
            {
                type = "recipe-category",
                name = "test-solver"
            },
            {
                type = "recipe",
                name = "test-solver-plate",
                categories = {"test-solver"},
                enabled = true,
                energy_required = 0.5,
                ingredients = {{type = "item", name = "test-solver-ore", amount = 2}},
                results = {{type = "item", name = "test-solver-plate", amount = 1}}
            },
            {
                type = "recipe",
                name = "test-solver-gear",
                categories = {"test-solver"},
                enabled = true,
                energy_required = 1,
                ingredients = {{type = "item", name = "test-solver-plate", amount = 2}},
                results = {{type = "item", name = "test-solver-gear", amount = 1}}
            }
        }

        local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
        machine.name = "test-solver-machine"
        machine.crafting_categories = {"test-solver"}
        machine.crafting_speed = 1
        machine.energy_usage = "100kW"
        -- Drain is zeroed explicitly, since crafting machines otherwise default to usage / 30
        machine.energy_source = {type = "electric", usage_priority = "secondary-input", drain = "0W"}
        machine.module_slots = 0
        machine.allowed_effects = nil
        machine.effect_receiver = nil
        machine.fast_replaceable_group = nil
        machine.next_upgrade = nil

        data:extend{machine}
    end,

    check = function(context)
        local c = helpers.collector()
        local player = game.players[1]

        local factory = build_factory(context.classes, player,
            {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 5)

        solver.update(player, factory)

        -- 5 gear/s at 1 craft/s per machine -> 5 machines demanding 10 plates/s
        local gear_line = factory.top_floor.first
        c.check(helpers.approx(gear_line.production_ratio, 5),
            string.format("gear line: expected ratio 5, got %g", gear_line.production_ratio))
        c.check(helpers.approx(gear_line.machine.amount, 5),
            string.format("gear line: expected 5 machines, got %g", gear_line.machine.amount))

        -- 10 plates/s at 2 crafts/s per machine -> 5 machines drawing 20 ore/s
        local plate_line = gear_line.next
        c.check(helpers.approx(plate_line.production_ratio, 10),
            string.format("plate line: expected ratio 10, got %g", plate_line.production_ratio))
        c.check(helpers.approx(plate_line.machine.amount, 5),
            string.format("plate line: expected 5 machines, got %g", plate_line.machine.amount))

        -- Each line of 5 machines draws 500kW
        c.check(helpers.approx(item_amount(plate_line.ingredients, "custom-electric-power") or 0, 500000),
            "plate line: expected 500kW of power draw")

        -- Top level: the demand is fully satisfied by ore and power alone
        c.check(helpers.approx(product.amount, 5),
            string.format("product: expected 5 gears satisfied, got %g", product.amount))
        local top = factory.top_floor
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-ore") or 0, 20),
            "top floor: expected 20 ore/s")
        c.check(helpers.approx(item_amount(top.ingredients, "custom-electric-power") or 0, 1e6),
            "top floor: expected 1MW total power draw")
        c.check(#top.byproducts == 0, "top floor: expected no byproducts")

        c.done()
    end
}
