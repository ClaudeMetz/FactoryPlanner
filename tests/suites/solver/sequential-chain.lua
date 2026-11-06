---@diagnostic disable
local helpers = require("helpers")
local chain = require("fixtures").chain
local build_factory, add_product, item_amount = chain.build, chain.product, chain.amount

return {
    testSequentialChainRates = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
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
        c.check(#top.products == 1, "top floor: expected only the requested gear output")
        c.done()
    end},
    testSequentialSurplusConsumption = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 5)

        solver.update(player, factory)
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        -- Request a coproduct so a consuming gear line can use the 10 plates/s surplus
        local coproduct_line = context.classes.Line.init(
            prototyper.util.find("recipes", "test-solver-plate-with-slag"))
        top:replace(plate_line, coproduct_line)
        coproduct_line:change_machine_to_proto(player,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        add_product(context.classes, factory, "test-solver-slag", 20)
        local consumer = context.classes.Line.init(
            prototyper.util.find("recipes", "test-solver-gear"))
        top:insert(consumer)
        consumer:change_machine_to_proto(player,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        solver.update(player, factory)
        c.check(helpers.approx(consumer.production_ratio, 5),
            "consuming line: expected all 10 surplus plates/s to make 5 gears/s")
        c.check(helpers.approx(product.amount, 10) and helpers.approx(item_amount(top.products, "test-solver-gear") or 0, 10),
            "top floor: requested products include the 5 extra gears/s in their total output")
        c.check(item_amount(top.products, "test-solver-plate") == nil,
            "top floor: consuming line must leave no surplus plates")
        c.done()
    end},
    testSequentialFixedMachineOutput = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 0)
        product.definition = {type="machines", machine_count=3.5}
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 3.5), "machine product: expected exactly 3.5 gear machines")
        c.check(helpers.approx(product.amount, 3.5), "machine product: expected 3.5 gears/s")
        c.check(helpers.approx(item_amount(gear_line.products, "test-solver-gear") or 0, 3.5),
            "machine product: the controlling line must show gears as a product")
        c.check(helpers.approx(plate_line.machine.amount, 3.5), "machine product: expected 3.5 upstream plate machines")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-ore") or 0, 14),
            "machine product: expected 14 ore/s")
        c.check(helpers.approx(item_amount(top.ingredients, "custom-electric-power") or 0, 700000),
            "machine product: expected 700kW total power draw")
        c.check(helpers.approx(item_amount(top.products, "test-solver-gear") or 0, 3.5),
            "machine product: top floor must include its calculated output")
        c.done()
    end},
    testSequentialMixedTargetsAndShortage = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 0)
        product.definition = {type="machines", machine_count=3.5}
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        solver.update(player, factory)
        -- The fixed plate count overrides internal demand; only the surplus is factory output
        product.definition = {type="amount", amount=5}
        local plates = add_product(context.classes, factory, "test-solver-plate", 0)
        plates.definition = {type="machines", machine_count=8}
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 5) and helpers.approx(product.amount, 5),
            "mixed definitions: expected the amount target to remain 5 gears/s")
        c.check(helpers.approx(plate_line.machine.amount, 8), "mixed definitions: expected exactly 8 plate machines")
        c.check(helpers.approx(plates.amount, 6), "mixed definitions: expected 16 minus 10 = 6 plates/s net output")
        c.check(helpers.approx(item_amount(plate_line.products, "test-solver-plate") or 0, 16),
            "mixed definitions: the controlling line must show all 16 plates/s as a product")
        c.check(helpers.approx(item_amount(top.products, "test-solver-plate") or 0, 6),
            "mixed definitions: top floor must include the net plate output")

        plates.definition.machine_count = 3
        solver.update(player, factory)
        c.check(helpers.approx(plate_line.machine.amount, 3), "shortage: expected exactly 3 plate machines")
        c.check(plates.amount == 0, "shortage: zero net output must be valid")
        c.check(helpers.approx(product.amount, 5), "shortage: the gear target must remain satisfied")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 4),
            "shortage: expected 4 imported plates/s")
        c.done()
    end},
    testSequentialFixedConsumerImports = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 0)
        product.definition = {type="machines", machine_count=3.5}
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        solver.update(player, factory)
        product.definition = {type="amount", amount=5}
        local plates = add_product(context.classes, factory, "test-solver-plate", 0)
        plates.definition = {type="machines", machine_count=8}
        -- A consuming line also obeys its fixed count, even if it must import ingredients
        top:move(plate_line, gear_line, "previous")
        gear_line.recipe.priority_item = prototyper.util.find("items", "test-solver-plate", "item")
        product.definition = {type="machines", machine_count=3.5}
        plates.definition.machine_count = 2
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 3.5) and helpers.approx(product.amount, 3.5),
            "fixed consumer: expected 3.5 gear machines producing 3.5 gears/s")
        c.check(helpers.approx(plate_line.machine.amount, 2) and plates.amount == 0,
            "fixed consumer: expected all output from 2 plate machines to be consumed")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 3),
            "fixed consumer: expected 3 imported plates/s beyond the 4 available")
        c.done()
    end},
    testSequentialFixedSubfloorOutput = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 0)
        product.definition = {type="machines", machine_count=3.5}
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        local subfloor = context.classes.Floor.init(2, top.solver)
        top:replace(gear_line, subfloor)
        top:remove(plate_line)
        subfloor:insert(gear_line)
        subfloor:insert(plate_line)
        lib.context.set(player, subfloor)
        solver.update(player, factory)
        c.check(helpers.approx(gear_line.machine.amount, 3.5) and helpers.approx(product.amount, 3.5),
            "subfloor: expected exactly 3.5 defining machines producing 3.5 gears/s")
        c.check(plate_line.machine_requirement == nil and helpers.approx(plate_line.machine.amount, 3.5),
            "subfloor: internal plate machines must follow demand")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-ore") or 0, 14)
            and helpers.approx(item_amount(top.ingredients, "custom-electric-power") or 0, 700000),
            "subfloor: expected 14 ore/s and 700kW at the factory level")
        c.check(helpers.approx(item_amount(subfloor.products, "test-solver-gear") or 0, 3.5),
            "subfloor: its summary must show the machine-defined output as a product")
        c.done()
    end},
    testSequentialSubfloorLocalConsumption = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate", "test-solver-gear"})
        local product = add_product(context.classes, factory, "test-solver-gear", 5)
        local plates = add_product(context.classes, factory, "test-solver-plate", 0)
        plates.definition = {type="machines", machine_count=8}
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        local internal = plate_line.next
        local subfloor = context.classes.Floor.init(2, top.solver)
        top:replace(plate_line, subfloor)
        top:remove(internal)
        subfloor:insert(plate_line)
        subfloor:insert(internal)
        internal.recipe.priority_item = prototyper.util.find("items", "test-solver-gear", "item")
        lib.context.set(player, subfloor)
        solver.update(player, factory)
        c.check(helpers.approx(plate_line.machine.amount, 8) and helpers.approx(product.amount, 5)
            and helpers.approx(plates.amount, 6), "mixed subfloor: expected 5 gears/s and 6 net plates/s")
        c.check(helpers.approx(item_amount(subfloor.products, "test-solver-plate") or 0, 16),
            "mixed subfloor: all 16 plates/s must appear as a product in its summary")

        -- Subfloors solve independently: the consumer uses all locally available plates,
        -- including those needed by the parent, which imports its 10 plates/s separately.
        internal.recipe.priority_item = nil
        solver.update(player, factory)
        c.check(helpers.approx(internal.machine.amount, 8) and plates.amount == 0
            and helpers.approx(product.amount, 13),
            "subfloor consumer: expected all 16 plates/s to add 8 gears/s to the parent's 5 gears/s")
        c.check(item_amount(subfloor.products, "test-solver-plate") == nil
            and helpers.approx(item_amount(subfloor.products, "test-solver-gear") or 0, 8),
            "subfloor consumer: its summary must show 8 gears/s and no remaining plates")
        c.check(helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 10),
            "subfloor consumer: the parent must import all 10 plates/s it needs")
        plates.definition.machine_count = 3
        solver.update(player, factory)
        c.check(helpers.approx(plate_line.machine.amount, 3) and helpers.approx(internal.machine.amount, 3)
            and plates.amount == 0 and helpers.approx(product.amount, 8)
            and helpers.approx(item_amount(top.ingredients, "test-solver-plate") or 0, 10),
            "scaled subfloor: expected 3 plate and gear machines, 8 total gears/s, and 10 imported plates/s")
        c.done()
    end},
    testSequentialNestedSurplusConsumption = {check=function(context)
        local c, player = helpers.collector(), context.player
        local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
        local product = add_product(context.classes, factory, "test-solver-gear", 5)

        solver.update(player, factory)
        local top = factory.top_floor
        local gear_line, plate_line = top.first, top.first.next
        -- Request a coproduct so a consuming gear line can use the 10 plates/s surplus
        local coproduct_line = context.classes.Line.init(
            prototyper.util.find("recipes", "test-solver-plate-with-slag"))
        top:replace(plate_line, coproduct_line)
        coproduct_line:change_machine_to_proto(player,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        add_product(context.classes, factory, "test-solver-slag", 20)
        local consumer = context.classes.Line.init(
            prototyper.util.find("recipes", "test-solver-gear"))
        top:insert(consumer)
        consumer:change_machine_to_proto(player,
            prototyper.util.find("machines", "test-solver-machine", "test-solver"))
        solver.update(player, factory)
        local consumer_floor = context.classes.Floor.init(2, top.solver)
        top:replace(consumer, consumer_floor)
        consumer_floor:insert(consumer)
        lib.context.set(player, consumer_floor)
        solver.update(player, factory)
        c.check(helpers.approx(consumer.machine.amount, 5) and helpers.approx(product.amount, 10),
            "consumer subfloor: expected parent surplus to pace 5 gear machines")
        consumer.recipe.priority_item = prototyper.util.find("items", "test-solver-plate", "item")
        local outer_floor = context.classes.Floor.init(2, top.solver)
        top:replace(coproduct_line, outer_floor)
        top:remove(consumer_floor)
        outer_floor:insert(coproduct_line)
        outer_floor:insert(consumer_floor)
        consumer_floor.level = 3
        solver.update(player, factory)
        c.check(helpers.approx(consumer.machine.amount, 10) and helpers.approx(product.amount, 15),
            "nested consumer subfloor: ingredient priority must consume all 20 locally produced plates/s")
        c.done()
    end},
}
