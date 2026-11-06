---@diagnostic disable
local helpers = require("helpers")
local arrange = require("fixtures").input

local checks = {}
checks.InputPacing = function(context, solver_name)
    local build = arrange(context)
    local c, player, classes = helpers.collector(), context.player, context.classes
    local f = build.factory(solver_name)
    local plate = build.line(f.top_floor, "plate")
    local ore = build.target(f, "iron-ore", "ingredient", 20)
    solver.update(player, f)
    c.close(ore.amount, 20, solver_name .. " ingredient achieved amount")
    c.close(plate.machine.amount, 10, solver_name .. " input-paced machines")
    c.close(assert(build.find(f.top_floor.ingredients, "iron-ore"), "Missing ore allocation").required_amount, 20, solver_name .. " top allocation")
    c.close(build.find(plate.ingredients, "iron-ore").target_amount, 20, solver_name .. " line allocation")
    c.done()
end

checks.InputDefinitionsAndSubfloors = function(context, solver_name)
    local build = arrange(context)
    local c, player, classes = helpers.collector(), context.player, context.classes
    local f = build.factory(solver_name)
    local plate = build.line(f.top_floor, "plate")
    local ore = build.target(f, "iron-ore", "ingredient", 20)
    solver.update(player, f)
    local copper = build.line(f.top_floor, "copper")
    local output = build.target(f, "copper-plate", "product", 10)
    solver.update(player, f)
    c.close(output.amount, 10, solver_name .. " mixed product target")
    c.close(ore.amount, 20, solver_name .. " mixed ingredient target")
    f.top_floor:remove(copper)
    output.proto = prototyper.util.find("items", "iron-plate", "item")
    ore.active = false
    solver.update(player, f)
    c.close(ore.amount, 20, solver_name .. " disabled target still reports actual consumption")
    c.close(assert(build.find(f.top_floor.ingredients, "iron-ore"), "Missing ore allocation").required_amount, 0, solver_name .. " disabled top allocation")
    c.close(build.find(plate.ingredients, "iron-ore").target_amount, 0, solver_name .. " disabled line allocation")
    output.active = false
    ore.active = true
    ore.definition = {type="machines", machine_count=3.5}
    solver.update(player, f)
    c.close(plate.machine.amount, 3.5, solver_name .. " machine-defined ingredient")
    c.close(ore.amount, 7, solver_name .. " machine-defined consumption")
    c.check(plate.machine_requirement and plate.machine_requirement.count == 3.5,
        solver_name .. " ingredient machine assignment")

    local belt = prototyper.util.find("belts", "transport-belt")
    ore.definition = {type="belts", belt_proto=belt, belt_stack=1, belt_count=20 / belt.throughput}
    solver.update(player, f)
    c.close(ore.amount, 20, solver_name .. " belt-defined consumption")
    ore.definition = {type="machines", machine_count=3.5}

    local subfloor = classes.Floor.init(2, solver_name)
    f.top_floor:replace(plate, subfloor)
    subfloor:insert(plate)
    lib.context.set(player, subfloor)
    solver.update(player, f)
    c.close(plate.machine.amount, 3.5, solver_name .. " attached machine-defined ingredient")
    c.close(build.find(subfloor.ingredients, "iron-ore").required_amount, 7, solver_name .. " subfloor allocation")
    c.close(build.find(plate.ingredients, "iron-ore").target_amount, 7, solver_name .. " nested line allocation")
    ore.definition = {type="amount", amount=20}
    solver.update(player, f)
    c.close(ore.amount, 20, solver_name .. " amount-defined subfloor")
    c.close(plate.machine.amount, 10, solver_name .. " scaled defining recipe")
    ore.active = false
    solver.update(player, f)
    c.close(ore.amount, 0, solver_name .. " cleared target amount")
    c.close(build.find(plate.ingredients, "iron-ore").target_amount, 0, solver_name .. " cleared line allocation")

    c.done()
end

checks.InputDisposal = function(context, solver_name)
    local build = arrange(context)
    local c, player, classes = helpers.collector(), context.player, context.classes
    local f = build.factory(solver_name)
    local sink = build.line(f.top_floor, "sink")
    local ore = build.target(f, "iron-ore", "ingredient", 20)
    solver.update(player, f)
    c.close(ore.amount, 20, solver_name .. " disposal without outputs")
    c.close(sink.machine.amount, 10, solver_name .. " disposal machines")

    c.done()
end

checks.InputFluidTemperature = function(context, solver_name)
    local build = arrange(context)
    local c, player, classes = helpers.collector(), context.player, context.classes
    local f = build.factory(solver_name)
    local steam = build.line(f.top_floor, "steam")
    steam.recipe:set_temperature("steam", 165)
    if solver_name == "gaussian" then steam.active = false end
    local hot = build.line(f.top_floor, "steam")
    hot.recipe:set_temperature("steam", 500)
    local steam_target = build.target(f, lib.temperature.name_with("steam", 500), "ingredient", 0, "fluid")
    steam_target.definition = {type="machines", machine_count=4}
    solver.update(player, f)
    c.close(steam.machine.amount, 0, solver_name .. " mismatched temperature must not claim machine target")
    c.close(hot.machine.amount, 4, solver_name .. " matching fluid machine target")
    c.close(steam_target.amount, 8, solver_name .. " fluid target consumption")
    c.close(build.find(hot.ingredients, "steam").target_amount, 8, solver_name .. " fluid line allocation")

    c.done()
end

checks.InputIntermediateAllocation = function(context, solver_name)
    local build = arrange(context)
    local c, player, classes = helpers.collector(), context.player, context.classes
    local f = build.factory(solver_name)
    local consumer = build.line(f.top_floor, "consumer")
    build.line(f.top_floor, "plate")
    local plates = build.target(f, "iron-plate", "ingredient", 10)
    local unused_source = build.target(f, "iron-ore", "ingredient", 0)
    unused_source.definition = {type="machines", machine_count=0}
    solver.update(player, f)
    c.close(plates.amount, 10, solver_name .. " net intermediate consumption")
    c.close(consumer.machine.amount, 10, solver_name .. " intermediate consumption")

    -- The target covers only external consumption; internally supplied plates are additional line throughput
    unused_source.definition.machine_count = 3
    local source = f.top_floor:find_last()
    f.top_floor:move(source, consumer, "previous")
    local inner = classes.Floor.init(2, solver_name)
    f.top_floor:replace(consumer, inner)
    inner:insert(consumer)
    lib.context.set(player, inner)
    solver.update(player, f)
    c.close(plates.amount, 10, solver_name .. " net consumption with internal supply")
    c.close(consumer.machine.amount, 13, solver_name .. " consumption with internal supply")
    local imported_plates = build.find(inner.ingredients, "iron-plate")
    c.close(imported_plates.target_amount, 10, solver_name .. " subfloor external target share")
    c.close(imported_plates.required_amount, 13, solver_name .. " subfloor full parent requirement")
    c.close(build.find(consumer.ingredients, "iron-plate").target_amount, 13,
        solver_name .. " defining line contribution to local floor requirement")
    c.done()
end

checks.InputExcessAndShortage = function(context, solver_name)
    local build = arrange(context)
    local c, player, classes = helpers.collector(), context.player, context.classes
    local f = build.factory(solver_name)
    local plate = build.line(f.top_floor, "plate")
    local ore = build.target(f, "iron-ore", "ingredient", 10)
    local output = build.target(f, "iron-plate", "product", 0)
    output.definition = {type="machines", machine_count=8}
    solver.update(player, f)
    c.close(ore.amount, 16, solver_name .. " excess consumption")
    local calculated = build.find(f.top_floor.ingredients, "iron-ore")
    c.close(calculated.required_amount, 10, solver_name .. " capped target share")
    c.close(calculated:get_remaining_amount(), 6, solver_name .. " excess consumption remainder")
    output.definition.machine_count = 3
    solver.update(player, f)
    c.close(ore.amount, 6, solver_name .. " partial consumption")
    calculated = build.find(f.top_floor.ingredients, "iron-ore")
    c.close(calculated.required_amount, 6, solver_name .. " partial target allocation")
    c.close(calculated:get_remaining_amount(), 0, solver_name .. " no duplicated partial consumption")
    c.done()
end

local cases = {}
for name, check in pairs(checks) do
    for _, solver_name in ipairs{"sequential", "simplex", "gaussian"} do
        if name ~= "InputExcessAndShortage" or solver_name ~= "gaussian" then
            cases["test" .. name .. "_" .. solver_name] = {check=function(context) check(context, solver_name) end}
        end
    end
end
return cases
