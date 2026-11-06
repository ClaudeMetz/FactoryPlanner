---@diagnostic disable
local fixtures = require("fixtures")
local helpers = require("helpers")

local effects = {
    RecipeProductivity = {type="change-recipe-productivity", recipe="iron-gear-wheel", change=0.25},
    MiningProductivity = {type="mining-drill-productivity-bonus", modifier=0.25},
    LabProductivity = {type="laboratory-productivity", modifier=0.25},
    LabSpeed = {type="laboratory-speed", modifier=0.25}
}

local function setup()
    for name, effect in pairs(effects) do
        local tech = table.deepcopy(data.raw.technology.automation)
        tech.name = "test-research-change-" .. name
        tech.prerequisites = nil
        tech.effects = {effect}
        data:extend{tech}
    end
end

local function dispatch(technology, researched)
    technology.researched = researched
    local event = researched and defines.events.on_research_finished or defines.events.on_research_reversed
    local handler = assert(script.get_event_handler(event), "Research event must be registered")
    handler{name=event, tick=game.tick, research=technology, by_script=true}
end

local function run_scheduled(factory)
    local tick = assert(factory.tick_of_solver_update, "Research change must schedule recalculation")
    local event = assert(storage.nth_tick_events[tick], "Scheduled recalculation must exist")
    GLOBAL_HANDLERS[event.handler_name](event.metadata)
    assert(factory.tick_of_solver_update == nil, "Recalculation must clear its pending update")
end

local function arrange(context, name, custom)
    local player, force = context.player, context.player.force
    local technology = force.technologies["test-research-change-" .. name]
    context.set(technology, "researched", false)
    local recipe, machine, target, item_type, bonus_key
    if name == "RecipeProductivity" then
        recipe, machine, target = "iron-gear-wheel", "assembling-machine-2", "iron-gear-wheel"
        bonus_key = recipe
    elseif name == "MiningProductivity" then
        context.set(force, "mining_drill_productivity_bonus", 0)
        recipe, machine, target = "impostor-iron-ore", "electric-mining-drill", "iron-ore"
        bonus_key = "custom-mining"
    else
        context.set(force, "laboratory_speed_modifier", 0)
        context.set(force, "laboratory_productivity_bonus", 0)
        recipe = "impostor-research-test-research-pack-1-1020"
        machine, target, item_type = "test-research-lab-restricted", "custom-research-1020", "entity"
        bonus_key = "custom-research"
    end

    local factory = fixtures.factory(context, "research-change")
    fixtures.target(context, factory, target, "product", {type="amount", amount=10}, item_type)
    local subfloor = context.classes.Floor.init(2, "sequential")
    factory.top_floor:insert(subfloor)
    local line = fixtures.line(context, subfloor, recipe, helpers.find_machine(machine))
    if custom then factory.productivity_boni[bonus_key] = MAGIC_NUMBERS.effect_precision / 2 end
    solver.update(player, factory, true)
    assert(subfloor.solver_result_cache, "The fixture must have a cached subfloor")
    return factory, subfloor, line, technology, bonus_key
end

local cases = {}
for name in pairs(effects) do
    cases["testResearchReversal_" .. name] = {check=function(context)
        local factory, subfloor, line, technology = arrange(context, name)
        local baseline = line.machine.amount
        assert(baseline > 0, "The fixture must produce output")
        local cache = subfloor.solver_result_cache
        dispatch(technology, true)
        run_scheduled(factory)
        assert(subfloor.solver_result_cache ~= cache, "Research completion must invalidate the subfloor cache")
        assert(helpers.approx(line.machine.amount, baseline / 1.25),
            "Research completion must reduce required machines by the new bonus")
        cache = subfloor.solver_result_cache
        dispatch(technology, false)
        run_scheduled(factory)
        assert(subfloor.solver_result_cache ~= cache, "Research reversal must invalidate the subfloor cache")
        assert(helpers.approx(line.machine.amount, baseline), "Research reversal must restore the original machine count")
    end}
    if name ~= "LabSpeed" then
        cases["testResearchCustomOverride_" .. name] = {check=function(context)
            local factory, _, line, technology, bonus_key = arrange(context, name, true)
            local baseline, override = line.machine.amount, factory.productivity_boni[bonus_key]
            for _, researched in ipairs{true, false} do
                dispatch(technology, researched)
                run_scheduled(factory)
                assert(factory.productivity_boni[bonus_key] == override, "Research changes must preserve the custom bonus")
                assert(helpers.approx(line.machine.amount, baseline), "The custom bonus must keep controlling production")
            end
        end}
    end
end

cases.testResearchOtherForce = {check=function(context)
    local factory = arrange(context, "RecipeProductivity")
    local technology = game.forces.enemy.technologies["test-research-change-RecipeProductivity"]
    context.set(technology, "researched", false)
    for _, researched in ipairs{true, false} do
        dispatch(technology, researched)
        assert(factory.tick_of_solver_update == nil, "Another force's research must not schedule this player's factories")
    end
end}

cases.testResearchUnrelatedEffect = {check=function(context)
    local factory = arrange(context, "RecipeProductivity")
    local technology = context.player.force.technologies.automation
    context.set(technology, "researched", false)
    for _, researched in ipairs{true, false} do
        dispatch(technology, researched)
        assert(factory.tick_of_solver_update == nil, "Recipe unlocks alone must not schedule solver updates")
    end
end}

return {setup=setup, cases=cases}
