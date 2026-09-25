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
    local factory = classes.Factory.init("test-factory", "sequential")
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
    local product = classes.FactoryItem.init(prototyper.util.find("items", item_name, "item"))
    product.definition.amount = amount  -- per second
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
            test_item("test-solver-slag", "stone"),
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

        local coproduct_recipe = deepcopy(data.raw.recipe["test-solver-plate"])
        coproduct_recipe.name = "test-solver-plate-with-slag"
        coproduct_recipe.main_product = "test-solver-plate"
        table.insert(coproduct_recipe.results, {type="item", name="test-solver-slag", amount=1})
        data:extend{coproduct_recipe}

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

        -- Request a coproduct so a consuming gear line can use the 10 plates/s surplus
        local coproduct_line = context.classes.Line.init(
            prototyper.util.find("recipes", "test-solver-plate-with-slag"), "produce")
        top:replace(plate_line, coproduct_line)
        coproduct_line:change_machine_to_proto(player,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        add_product(context.classes, factory, "test-solver-slag", 20)
        local consumer = context.classes.Line.init(
            prototyper.util.find("recipes", "test-solver-gear"), "consume")
        top:insert(consumer)
        consumer:change_machine_to_proto(player,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        solver.update(player, factory)
        c.check(helpers.approx(consumer.production_ratio, 5),
            "consuming line: expected all 10 surplus plates/s to make 5 gears/s")
        c.check(helpers.approx(item_amount(top.byproducts, "test-solver-gear") or 0, 5),
            "top floor: expected 5 surplus gears/s")
        c.check(item_amount(top.byproducts, "test-solver-plate") == nil,
            "top floor: consuming line must leave no surplus plates")

        -- A machine definition drives production even without an output amount target
        factory = build_factory(context.classes, player, {"test-solver-gear", "test-solver-plate"})
        product = add_product(context.classes, factory, "test-solver-gear", 0)
        product.definition = {type="machines", machine_count=3.5}
        top = factory.top_floor
        gear_line, plate_line = top.first, top.first.next
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 3.5), "machine product: expected exactly 3.5 gear machines")
        c.check(helpers.approx(product.amount, 3.5), "machine product: expected 3.5 gears/s")
        c.check(helpers.approx(item_amount(gear_line.products, "test-solver-gear") or 0, 3.5)
            and item_amount(gear_line.byproducts, "test-solver-gear") == nil,
            "machine product: the controlling line must show gears as a product")
        c.check(helpers.approx(plate_line.machine.amount, 3.5), "machine product: expected 3.5 upstream plate machines")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-ore") or 0, 14),
            "machine product: expected 14 ore/s")
        c.check(helpers.approx(item_amount(top.ingredients, "custom-electric-power") or 0, 700000),
            "machine product: expected 700kW total power draw")
        c.check(item_amount(top.byproducts, "test-solver-gear") == nil,
            "machine product: output must not also appear as a byproduct")

        -- The fixed plate count overrides internal demand; only the surplus is factory output
        product.definition = {type="amount", amount=5}
        local plates = add_product(context.classes, factory, "test-solver-plate", 0)
        plates.definition = {type="machines", machine_count=8}
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 5) and helpers.approx(product.amount, 5),
            "mixed definitions: expected the amount target to remain 5 gears/s")
        c.check(helpers.approx(plate_line.machine.amount, 8), "mixed definitions: expected exactly 8 plate machines")
        c.check(helpers.approx(plates.amount, 6), "mixed definitions: expected 16 minus 10 = 6 plates/s net output")
        c.check(helpers.approx(item_amount(plate_line.products, "test-solver-plate") or 0, 16)
            and item_amount(plate_line.byproducts, "test-solver-plate") == nil,
            "mixed definitions: the controlling line must show all 16 plates/s as a product")
        c.check(item_amount(top.byproducts, "test-solver-plate") == nil,
            "mixed definitions: net plate output must not also appear as a byproduct")

        plates.definition.machine_count = 3
        solver.update(player, factory)
        c.check(helpers.approx(plate_line.machine.amount, 3), "shortage: expected exactly 3 plate machines")
        c.check(plates.amount == 0, "shortage: zero net output must be valid")
        c.check(helpers.approx(product.amount, 5), "shortage: the gear target must remain satisfied")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 4),
            "shortage: expected 4 imported plates/s")

        -- A consuming line also obeys its fixed count, even if it must import ingredients
        top:move(plate_line, gear_line, "previous")
        gear_line.recipe.production_type = "consume"
        product.definition = {type="machines", machine_count=3.5}
        plates.definition.machine_count = 2
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 3.5) and helpers.approx(product.amount, 3.5),
            "fixed consumer: expected 3.5 gear machines producing 3.5 gears/s")
        c.check(helpers.approx(plate_line.machine.amount, 2) and plates.amount == 0,
            "fixed consumer: expected all output from 2 plate machines to be consumed")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 3),
            "fixed consumer: expected 3 imported plates/s beyond the 4 available")

        -- Attaching a subfloor preserves the defining recipe's count and includes its upstream demand
        factory = build_factory(context.classes, player, {"test-solver-gear", "test-solver-plate"})
        product = add_product(context.classes, factory, "test-solver-gear", 0)
        product.definition = {type="machines", machine_count=3.5}
        top = factory.top_floor
        gear_line, plate_line = top.first, top.first.next
        local subfloor = context.classes.Floor.init(2, top.solver)
        top:replace(gear_line, subfloor)
        top:remove(plate_line)
        subfloor:insert(gear_line)
        subfloor:insert(plate_line)
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 3.5) and helpers.approx(product.amount, 3.5),
            "subfloor: expected exactly 3.5 defining machines producing 3.5 gears/s")
        c.check(plate_line.machine_requirement == nil and helpers.approx(plate_line.machine.amount, 3.5),
            "subfloor: internal plate machines must follow demand")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-ore") or 0, 14)
            and helpers.approx(item_amount(top.ingredients, "custom-electric-power") or 0, 700000),
            "subfloor: expected 14 ore/s and 700kW at the factory level")
        c.check(helpers.approx(item_amount(subfloor.products, "test-solver-gear") or 0, 3.5)
            and item_amount(subfloor.byproducts, "test-solver-gear") == nil,
            "subfloor: its summary must show the machine-defined output as a product")

        -- A fixed subfloor can supply a parent recipe and export the remaining production
        factory = build_factory(context.classes, player,
            {"test-solver-gear", "test-solver-plate", "test-solver-gear"})
        product = add_product(context.classes, factory, "test-solver-gear", 5)
        plates = add_product(context.classes, factory, "test-solver-plate", 0)
        plates.definition = {type="machines", machine_count=8}
        top = factory.top_floor
        gear_line, plate_line = top.first, top.first.next
        local internal = plate_line.next
        subfloor = context.classes.Floor.init(2, top.solver)
        top:replace(plate_line, subfloor)
        top:remove(internal)
        subfloor:insert(plate_line)
        subfloor:insert(internal)
        solver.update(player, factory)
        c.check(helpers.approx(plate_line.machine.amount, 8) and helpers.approx(product.amount, 5)
            and helpers.approx(plates.amount, 6), "mixed subfloor: expected 5 gears/s and 6 net plates/s")
        c.check(helpers.approx(item_amount(subfloor.products, "test-solver-plate") or 0, 16)
            and item_amount(subfloor.byproducts, "test-solver-plate") == nil,
            "mixed subfloor: all 16 plates/s must appear as a product in its summary")
        internal.recipe.production_type = "consume"
        solver.update(player, factory)
        c.check(helpers.approx(internal.machine.amount, 3) and plates.amount == 0
            and helpers.approx(item_amount(top.byproducts, "test-solver-gear") or 0, 3),
            "subfloor consumer: expected all 6 surplus plates/s to become 3 surplus gears/s")
        c.check(helpers.approx(item_amount(subfloor.products, "test-solver-plate") or 0, 10),
            "subfloor consumer: its summary must show only the 10 plates/s remaining after internal consumption")
        plates.definition.machine_count = 3
        solver.update(player, factory)
        c.check(helpers.approx(plate_line.machine.amount, 3) and plates.amount == 0
            and helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 4),
            "short subfloor: expected 3 defining machines and 4 imported plates/s")

        c.done()
    end
}
