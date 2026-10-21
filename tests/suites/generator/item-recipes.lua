---@diagnostic disable

local helpers = require("helpers")

return {
    setup = function()
        local deepcopy = require("util").table.deepcopy
        for _, suffix in ipairs{"input", "output", "both", "catalyst", "growing", "shrinking"} do
            local item = deepcopy(data.raw.item["iron-plate"])
            item.name = "test-eligibility-" .. suffix
            item.auto_recycle = false
            data:extend{item}
        end
        for _, suffix in ipairs{"fluid", "closed-fluid", "input-fluid", "bounded-fluid"} do
            local fluid = deepcopy(data.raw.fluid.water)
            fluid.name = "test-eligibility-" .. suffix
            fluid.default_temperature = 15
            fluid.max_temperature = 200
            fluid.auto_barrel = false
            data:extend{fluid}
        end
        local function item(suffix, amount)
            return {type="item", name="test-eligibility-" .. suffix, amount=amount}
        end
        local function fluid(suffix, amount, temperature)
            return {type="fluid", name="test-eligibility-" .. suffix, amount=amount, temperature=temperature}
        end
        local function recipe(suffix, ingredients, results, fluids)
            data:extend{{
                type="recipe", name="test-eligibility-" .. suffix, enabled=true, energy_required=1,
                categories={fluids and "crafting-with-fluid" or "crafting"},
                ingredients=ingredients, results=results, auto_recycle=false, allow_productivity=false
            }}
        end
        recipe("input-output", {item("input", 1)}, {item("output", 1)})
        recipe("both-source", {item("input", 1)}, {item("both", 1)})
        recipe("both-sink", {item("both", 1)}, {item("output", 1)})
        recipe("catalyst", {item("catalyst", 1)}, {item("catalyst", 1)})
        recipe("growing", {item("growing", 1)}, {item("growing", 2)})
        recipe("shrinking", {item("shrinking", 2)}, {item("shrinking", 1)})
        for _, temperature in ipairs{15, 100, 200} do
            recipe("fluid-" .. temperature, {item("input", 1)}, {fluid("fluid", 1, temperature)}, true)
        end
        local bounded = fluid("fluid", 1)
        bounded.maximum_temperature = 100
        recipe("reheat", {bounded}, {fluid("fluid", 1, 100)}, true)
        recipe("fixed-cycle", {fluid("fluid", 1, 100)}, {fluid("fluid", 1, 100)}, true)
        recipe("closed-cycle", {fluid("closed-fluid", 1)}, {fluid("closed-fluid", 1, 100)}, true)
        recipe("fluid-sink", {fluid("input-fluid", 1)}, {item("output", 1)}, true)
        local unavailable = fluid("bounded-fluid", 1)
        unavailable.minimum_temperature = 100
        recipe("bounded-sink", {unavailable}, {item("output", 1)}, true)
    end,
    check = function(context)
        local c = helpers.collector()
        local function find(suffix, type, temperature)
            local name = lib.temperature.name_with("test-eligibility-" .. suffix, temperature)
            return prototyper.util.find("items", name, type or "item")
        end
        local function check_capabilities(proto, produce, consume)
            c.check(lib.availability.has_productive_recipe(proto, "produce") == produce, proto.name .. ": production")
            c.check(lib.availability.has_productive_recipe(proto, "consume") == consume, proto.name .. ": consumption")
            c.check(lib.actions.can_add_recipe({can_produce=produce, can_consume=consume}) == produce,
                proto.name .. ": producing action")
            c.check(lib.actions.can_add_recipe({can_produce=produce, can_consume=consume, consume=true}) == consume,
                proto.name .. ": consuming action")
        end
        check_capabilities(find("input"), false, true)
        check_capabilities(find("output"), true, false)
        check_capabilities(find("both"), true, true)
        check_capabilities(find("catalyst"), false, false)
        check_capabilities(find("growing"), true, false)
        check_capabilities(find("shrinking"), false, true)
        check_capabilities(find("fluid", "fluid", 15), true, true)
        check_capabilities(find("fluid", "fluid", 100), true, false)
        check_capabilities(find("fluid", "fluid", 200), true, false)
        check_capabilities(find("closed-fluid", "fluid", 100), false, false)
        check_capabilities(find("input-fluid", "fluid", 15), false, true)
        check_capabilities(find("bounded-fluid", "fluid", 15), false, false)
        check_capabilities(find("fluid", "fluid"), true, true)

        local function mapped(suffix, temperature, direction)
            local proto = find("fluid", "fluid", temperature)
            local recipe = prototyper.util.find("recipes", "test-eligibility-" .. suffix)
            local recipes = RECIPE_MAPS[direction][proto.category_id][proto.id]
            return recipes and recipes[recipe.id] or false
        end
        c.check(mapped("reheat", 100, "produce"), "Reheating can produce the hot variant")
        c.check(mapped("reheat", 15, "consume"), "Reheating can consume the cold variant")
        c.check(not mapped("reheat", 100, "consume"), "Equal-temperature recycling does not consume the fluid")
        c.check(not mapped("reheat", 200, "consume"), "The ingredient temperature ceiling must be respected")
        c.check(not mapped("fixed-cycle", 100, "produce") and not mapped("fixed-cycle", 100, "consume"),
            "A fixed-temperature catalyst belongs to neither map")
        c.check(not lib.availability.can_define_factory_item(find("fluid", "fluid"), "ingredient"),
            "Targets require a fixed fluid temperature")
        c.check(lib.availability.can_define_factory_item(find("input-fluid", "fluid", 15), "ingredient"),
            "The default variant of an input-only fluid is a valid ingredient target")

        local factory = context.classes.Factory.init("target-eligibility-test", "sequential")
        local FactoryItem = context.classes.FactoryItem
        for _, category in ipairs{"product", "ingredient"} do
            for _, suffix in ipairs{"input", "output", "both", "catalyst"} do
                local proto = find(suffix)
                local target = FactoryItem.init(nil, category)
                factory:insert(target)
                local expected = (suffix == "both") or (category == "product" and suffix == "output")
                    or (category == "ingredient" and suffix == "input")
                c.check(lib.availability.can_define_factory_item(proto, category) == expected, suffix .. ": " .. category .. " eligibility")
                local success = target:paste(FactoryItem.init(proto, category))
                c.check(success == expected, suffix .. ": " .. category .. " paste")
                factory:remove(factory.first)
            end
        end

        local player = game.players[1]
        local resource = prototyper.util.find("items", "custom-iron-ore", "entity")
        c.check(lib.availability.has_productive_recipe(resource, "consume"), "Mining consumes resource deposits")
        c.check(not lib.availability.can_define_factory_item(resource, "ingredient"), "Hidden resource items stay out of the picker")
        c.check(lib.availability.is_item_unlocked(player.force, resource, "ingredient"),
            "Input-only entities use their consuming recipes to determine unlock status")

        local district = context.classes.District.init()
        lib.globals.player_table(player).realm:insert(district)
        district:insert(factory)
        lib.context.set(player, factory)
        main_dialog.rebuild(player, false)
        for _, category in ipairs{"product", "ingredient"} do
            lib.gui.open_dialog(player, {dialog="picker", modal_data={item_category=category}})
            local offered = {}
            for _, group in pairs(lib.globals.modal_elements(player).groups) do
                for _, subgroup in pairs(group.subgroup_tables) do
                    for _, button in pairs(subgroup) do
                        local proto = prototyper.util.find("items", button.tags.item_id, button.tags.category_id)
                        offered[proto] = true
                    end
                end
            end
            for _, suffix in ipairs{"input", "output", "both", "catalyst"} do
                local expected = (suffix == "both") or (category == "product" and suffix == "output")
                    or (category == "ingredient" and suffix == "input")
                c.check((offered[find(suffix)] == true) == expected, suffix .. ": " .. category .. " picker")
            end
            for _, name in ipairs{"blueprint", "blueprint-book", "deconstruction-planner", "upgrade-planner"} do
                local proto = prototyper.util.find("items", name, "item")
                c.check(proto ~= nil and not offered[proto], name .. ": spawnable tools stay out of the picker")
            end
            c.check(not offered[find("fluid", "fluid")], "The picker must not offer temperatureless fluids")
            lib.gui.close_dialog(player, "cancel")
        end
        c.done()
    end
}
