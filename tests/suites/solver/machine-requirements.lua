---@diagnostic disable
local machine_fixture = require("fixtures").machine

local cases = {
    testMachineRequirementPrecedence = {check=function(context)
        local f = machine_fixture(context)
        local classes = context.classes

        solver.update(f.player, f.factory)
        assert(f.first.machine_requirement.count == 3.5 and f.second.machine_requirement == nil)
        assert(f.first.machine.amount == 3.5 and f.second.machine.amount == 0, "First factory product must win")
        f.iron.active = false
        solver.update(f.player, f.factory)
        assert(f.first.machine_requirement.count == 8 and f.first.machine.amount == 8,
            "Disabled products must not take precedence over active machine targets")
        for _, product in ipairs(f.top.products) do
            if product.proto == f.iron.proto then
                assert(product.amount > 0 and product.required_amount == 0,
                    "Output of a disabled target must remain incidental output")
            end
        end
        f.copper.active = false
        solver.update(f.player, f.factory)
        assert(f.first.machine.amount == 0 and f.first.machine_requirement == nil)
        f.iron.active, f.copper.active = true, true
        f.factory:shift(f.copper, "previous", 1)
        solver.update(f.player, f.factory)
        assert(f.first.machine_requirement.count == 8 and f.first.machine.amount == 8)
        f.factory:shift(f.iron, "previous", 1)
    end},
    testMachineRequirementInstantRecipes = {check=function(context)
        local f = machine_fixture(context)
        local classes = context.classes
        -- Generated recipes can have zero duration, although native recipe prototypes cannot
        local instant = f.add_line(f.top)
        instant.recipe.proto = lib.flib.shallow_copy(instant.recipe.proto)
        instant.recipe.proto.energy = 0
        f.top:move(instant, f.first, "previous")
        solver.update(f.player, f.factory)
        assert(instant.machine_requirement == nil and f.first.machine_requirement.count == 3.5)
        f.first.active, f.second.active = false, false
        solver.update(f.player, f.factory)
        assert(instant.machine_requirement == nil and f.first.machine_requirement == nil
            and f.second.machine_requirement == nil, "Instant-only matches must leave machine definitions unassigned")
        f.iron.definition = {type="amount", amount=1}
        solver.update(f.player, f.factory)
        assert(f.iron.amount == 1 and instant.production_ratio > 0 and instant.machine.amount == 0)
        f.iron.definition = {type="machines", machine_count=3.5}
        f.first.active, f.second.active = true, true
    end},
    testMachineRequirementDisabledMatch = {check=function(context)
        local f = machine_fixture(context)
        local classes = context.classes

        f.top:move(f.second, f.first, "previous")
        solver.update(f.player, f.factory)
        assert(f.second.machine_requirement.count == 3.5 and f.first.machine_requirement == nil)
        f.second.active = false
        solver.update(f.player, f.factory)
        assert(f.second.machine_requirement == nil and f.first.machine_requirement == nil,
            "Disabling the first match must not transfer its machine target")
        assert(f.second.machine.amount == 0 and f.first.machine.amount == 0 and f.iron.amount == 0 and f.copper.amount == 0,
            "A disabled machine target must leave both matching recipes idle")
        f.first.active = false
        solver.update(f.player, f.factory)
        assert(f.first.machine_requirement == nil and f.second.machine_requirement == nil)
        f.first.active = true
        f.second.active = true
        assert(f.second.production_ratio == 0, "Previously disabled line must start with no production")
        solver.update(f.player, f.factory)
        assert(f.second.machine_requirement.count == 3.5 and f.first.machine_requirement == nil,
            "Re-enabling the first match must restore its machine target")
        assert(f.second.machine.amount == 3.5, "A usable line must qualify even without existing production")
    end},
    testMachineRequirementDefiningRecipe = {check=function(context)
        local f = machine_fixture(context)
        local classes = context.classes
        f.top:move(f.second, f.first, "previous")
        solver.update(f.player, f.factory)
        local subfloor = classes.Floor.init(2, f.top.solver)
        f.top:replace(f.second, subfloor)
        subfloor:insert(f.second)
        local internal = f.add_line(subfloor)
        lib.context.set(f.player, subfloor)
        solver.update(f.player, f.factory)
        assert(f.second.machine_requirement.count == 3.5 and f.first.machine_requirement == nil,
            "A subfloor's defining recipe must retain its requirement")
        f.second.active = false
        solver.update(f.player, f.factory)
        assert(f.second.machine_requirement == nil and internal.machine_requirement == nil
            and f.first.machine_requirement == nil,
            "Disabling a defining recipe must not transfer its machine target")
        f.top:remove(f.first)
        solver.update(f.player, f.factory)
        assert(f.second.machine_requirement == nil and internal.machine_requirement == nil,
            "Internal subfloor recipes must not be selected")
        f.second.active = true
        f.top:insert(f.first, subfloor, "previous")
    end},
    testMachineRequirementTemperature = {check=function(context)
        local f = machine_fixture(context)
        local classes = context.classes
        local cold = f.add_line(f.top, "test-machine-steam-165")
        local hot = f.add_line(f.top, "test-machine-steam-500")
        local hot_proto = prototyper.util.find("items", hot.recipe.products[1].name, "fluid")
        local steam = f.add_product(hot_proto, 2)
        solver.update(f.player, f.factory)
        assert(hot.machine_requirement.count == 2 and cold.machine_requirement == nil)
        f.factory:remove(steam)
        solver.update(f.player, f.factory)
        assert(hot.machine_requirement == nil, "Removing a product must clear its old assignment")
    end},
}

-- Mixed rate and machine targets
do
    local helpers = require("helpers")
    local fixture = require("fixtures").target_item

    cases.testMixedTargetRates = {check=function(context)
        local player, factory, item = fixture(context)
        item.definition = {type="machines", machine_count=5}
        local output = context.classes.FactoryItem.init(prototyper.util.find("items", "copper-plate", "item"), "product")
        output.definition = {type="amount", amount=10}
        factory:insert(output)
        -- Exercise result calculation through the public solver entry point.
        -- Five stone furnaces make 5 / 3.2 iron plates/s; copper has a separate amount target.
        local function add_smelting_line(recipe_name)
            local line = context.classes.Line.init(prototyper.util.find("recipes", recipe_name))
            factory.top_floor:insert(line)
            line:change_machine_to_proto(player, helpers.find_machine("stone-furnace"))
            return line
        end
        local iron_line = add_smelting_line("iron-plate")
        add_smelting_line("copper-plate")
        solver.update(player, factory)
        assert(helpers.approx(iron_line.machine.amount, 5))
        assert(helpers.approx(item.amount, 5 / 3.2) and helpers.approx(output.amount, 10))
        assert(#factory.top_floor.products == 2, "Calculated outputs must include both factory products once")
    end}
end

return cases
