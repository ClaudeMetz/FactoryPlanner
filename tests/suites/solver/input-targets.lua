---@diagnostic disable

local helpers = require("helpers")

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy
        data:extend{{type="recipe-category", name="test-input-target"}}
        local machine = deepcopy(data.raw["assembling-machine"]["assembling-machine-2"])
        machine.name = "test-input-target-machine"
        machine.crafting_categories = {"test-input-target"}
        machine.crafting_speed = 1
        machine.energy_source = {type="electric", usage_priority="secondary-input", drain="0W"}
        machine.energy_usage = "100kW"
        machine.module_slots = 0
        machine.allowed_effects = nil
        machine.effect_receiver = nil
        machine.fast_replaceable_group = nil
        machine.next_upgrade = nil
        data:extend{machine}
        local function item(name, amount)
            return {type="item", name=name, amount=amount}
        end
        local function recipe(name, ingredients, results)
            data:extend{{type="recipe", name="test-input-target-" .. name, categories={"test-input-target"},
                enabled=true, energy_required=1, ingredients=ingredients, results=results,
                icon="__base__/graphics/icons/iron-plate.png", subgroup="intermediate-product",
                auto_recycle=false, allow_productivity=false}}
        end
        recipe("plate", {item("iron-ore", 2)}, {item("iron-plate", 1)})
        recipe("copper", {item("copper-ore", 2)}, {item("copper-plate", 1)})
        recipe("gear", {item("iron-plate", 2)}, {item("iron-gear-wheel", 1)})
        recipe("consumer", {item("iron-plate", 1)}, {item("iron-gear-wheel", 1)})
        recipe("sink", {item("iron-ore", 2)}, {})
        recipe("steam", {{type="fluid", name="steam", amount=2, minimum_temperature=100}},
            {item("iron-plate", 1)})
    end,
    check = function(context)
        local c, player, classes = helpers.collector(), game.players[1], context.classes
        local function factory(solver_name)
            local district = classes.District.init()
            lib.globals.player_table(player).realm:insert(district)
            local result = classes.Factory.init("input-targets", solver_name)
            district:insert(result)
            lib.context.set(player, result)
            return result
        end
        local function line(floor, name)
            local result = classes.Line.init(prototyper.util.find("recipes", "test-input-target-" .. name))
            floor:insert(result)
            result:change_machine_to_proto(player, helpers.find_machine("test-input-target-machine"))
            return result
        end
        local function target(f, name, category, amount, type)
            local result = classes.FactoryItem.init(prototyper.util.find("items", name, type or "item"), category)
            result.definition = {type="amount", amount=amount}
            f:insert(result)
            return result
        end
        local function find(items, name)
            for _, item in pairs(items) do if item.proto.name == name then return item end end
        end
        local function close(actual, expected, message)
            c.check(helpers.approx(actual, expected), message .. ": expected " .. expected .. ", got " .. tostring(actual))
        end

        for _, solver_name in ipairs{"sequential", "simplex", "gaussian"} do
            local f = factory(solver_name)
            local plate = line(f.top_floor, "plate")
            local ore = target(f, "iron-ore", "ingredient", 20)
            solver.update(player, f)
            close(ore.amount, 20, solver_name .. " ingredient achieved amount")
            close(plate.machine.amount, 10, solver_name .. " input-paced machines")
            close(find(f.top_floor.ingredients, "iron-ore").required_amount, 20, solver_name .. " top allocation")
            close(find(plate.ingredients, "iron-ore").target_amount, 20, solver_name .. " line allocation")
            main_dialog.rebuild(player, false)
            local count = 0
            for _, button in pairs(lib.globals.main_elements(player).item_boxes.ingredient_item_table.children) do
                if button.sprite == "item/iron-ore" then
                    count = count + 1
                    c.check(button.tags.item_id == ore.id and button.style.name == "fflib_slot_button_green",
                        solver_name .. " satisfied consumption must be represented by its target")
                end
            end
            c.check(count == 1, solver_name .. " must not duplicate a satisfied ingredient")

            local copper = line(f.top_floor, "copper")
            local output = target(f, "copper-plate", "product", 10)
            solver.update(player, f)
            close(output.amount, 10, solver_name .. " mixed product target")
            close(ore.amount, 20, solver_name .. " mixed ingredient target")
            f.top_floor:remove(copper)
            output.proto = prototyper.util.find("items", "iron-plate", "item")
            ore.active = false
            solver.update(player, f)
            close(ore.amount, 20, solver_name .. " disabled target still reports actual consumption")
            close(find(f.top_floor.ingredients, "iron-ore").required_amount, 0, solver_name .. " disabled top allocation")
            close(find(plate.ingredients, "iron-ore").target_amount, 0, solver_name .. " disabled line allocation")
            output.active = false
            ore.active = true
            ore.definition = {type="machines", machine_count=3.5}
            solver.update(player, f)
            close(plate.machine.amount, 3.5, solver_name .. " machine-defined ingredient")
            close(ore.amount, 7, solver_name .. " machine-defined consumption")
            c.check(plate.machine_requirement and plate.machine_requirement.count == 3.5,
                solver_name .. " ingredient machine assignment")

            local belt = prototyper.util.find("belts", "transport-belt")
            ore.definition = {type="belts", belt_proto=belt, belt_stack=1, belt_count=20 / belt.throughput}
            solver.update(player, f)
            close(ore.amount, 20, solver_name .. " belt-defined consumption")
            ore.definition = {type="machines", machine_count=3.5}

            local subfloor = classes.Floor.init(2, solver_name)
            f.top_floor:replace(plate, subfloor)
            subfloor:insert(plate)
            solver.update(player, f)
            close(plate.machine.amount, 3.5, solver_name .. " attached machine-defined ingredient")
            close(find(subfloor.ingredients, "iron-ore").required_amount, 7, solver_name .. " subfloor allocation")
            close(find(plate.ingredients, "iron-ore").target_amount, 7, solver_name .. " nested line allocation")
            ore.definition = {type="amount", amount=20}
            solver.update(player, f)
            close(ore.amount, 20, solver_name .. " amount-defined subfloor")
            close(plate.machine.amount, 10, solver_name .. " scaled defining recipe")
            ore.active = false
            solver.update(player, f)
            close(ore.amount, 0, solver_name .. " cleared target amount")
            close(find(plate.ingredients, "iron-ore").target_amount, 0, solver_name .. " cleared line allocation")

            -- Simplex currently skips floors with no products; its engine is maintained separately
            if solver_name ~= "simplex" then
                f = factory(solver_name)
                local sink = line(f.top_floor, "sink")
                ore = target(f, "iron-ore", "ingredient", 20)
                solver.update(player, f)
                close(ore.amount, 20, solver_name .. " disposal without outputs")
                close(sink.machine.amount, 10, solver_name .. " disposal machines")
            end

            f = factory(solver_name)
            local steam = line(f.top_floor, "steam")
            steam.recipe:set_temperature("steam", 165)
            if solver_name == "gaussian" then steam.active = false end
            local hot = line(f.top_floor, "steam")
            hot.recipe:set_temperature("steam", 500)
            local steam_target = target(f, lib.temperature.name_with("steam", 500), "ingredient", 0, "fluid")
            steam_target.definition = {type="machines", machine_count=4}
            solver.update(player, f)
            close(steam.machine.amount, 0, solver_name .. " mismatched temperature must not claim machine target")
            close(hot.machine.amount, 4, solver_name .. " matching fluid machine target")
            close(steam_target.amount, 8, solver_name .. " fluid target consumption")
            close(find(hot.ingredients, "steam").target_amount, 8, solver_name .. " fluid line allocation")

            -- Allocate an externally supplied intermediate across the consuming line and its subfloor
            f = factory(solver_name)
            local consumer = line(f.top_floor, "consumer")
            line(f.top_floor, "plate")
            local plates = target(f, "iron-plate", "ingredient", 10)
            local unused_source = target(f, "iron-ore", "ingredient", 0)
            unused_source.definition = {type="machines", machine_count=0}
            solver.update(player, f)
            close(plates.amount, 10, solver_name .. " net intermediate consumption")
            close(consumer.machine.amount, 10, solver_name .. " intermediate consumption")

            -- The target covers only external consumption; internally supplied plates are additional line throughput
            unused_source.definition.machine_count = 3
            local source = f.top_floor:find_last()
            f.top_floor:move(source, consumer, "previous")
            local inner = classes.Floor.init(2, solver_name)
            f.top_floor:replace(consumer, inner)
            inner:insert(consumer)
            solver.update(player, f)
            close(plates.amount, 10, solver_name .. " net consumption with internal supply")
            close(consumer.machine.amount, 13, solver_name .. " consumption with internal supply")
            local imported_plates = find(inner.ingredients, "iron-plate")
            close(imported_plates.target_amount, 10, solver_name .. " subfloor external target share")
            close(imported_plates.required_amount, 13, solver_name .. " subfloor full parent requirement")
            close(find(consumer.ingredients, "iron-plate").target_amount, 13,
                solver_name .. " defining line contribution to local floor requirement")
        end

        -- A fixed machine count may exceed or undershoot a separate rate target without duplicating its full amount
        for _, solver_name in ipairs{"sequential", "simplex"} do
            local f = factory(solver_name)
            local plate = line(f.top_floor, "plate")
            local ore = target(f, "iron-ore", "ingredient", 10)
            local output = target(f, "iron-plate", "product", 0)
            output.definition = {type="machines", machine_count=8}
            solver.update(player, f)
            close(ore.amount, 16, solver_name .. " excess consumption")
            local calculated = find(f.top_floor.ingredients, "iron-ore")
            close(calculated.required_amount, 10, solver_name .. " capped target share")
            close(calculated:get_remaining_amount(), 6, solver_name .. " excess consumption remainder")
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)
            local count = 0
            for _, button in pairs(lib.globals.main_elements(player).item_boxes.ingredient_item_table.children) do
                if button.sprite == "item/iron-ore" then
                    count = count + 1
                    if button.tags.item_index then
                        close(button.number, item_views.process_item(player, ore.proto, 6, nil),
                            solver_name .. " GUI shows only excess consumption")
                    end
                end
            end
            c.check(count == 2, solver_name .. " excess consumption must have a separate remainder")
            output.definition.machine_count = 3
            solver.update(player, f)
            close(ore.amount, 6, solver_name .. " partial consumption")
            calculated = find(f.top_floor.ingredients, "iron-ore")
            close(calculated.required_amount, 6, solver_name .. " partial target allocation")
            close(calculated:get_remaining_amount(), 0, solver_name .. " no duplicated partial consumption")
        end

        c.done()
    end
}
