---@diagnostic disable

local item_listeners = script and require("__factoryplanner__.ui.main.item_boxes")[1]

local function find_button(parent, action, id_key, id)
    for _, child in pairs(parent.children) do
        if child.tags.on_gui_click == action and child.tags[id_key] == id then return child end
        local found = find_button(child, action, id_key, id)
        if found then return found end
    end
end

return {
    setup = function()
        data:extend{{
            type="recipe", name="test-machine-requirements", enabled=true, energy_required=1, main_product="iron-plate",
            ingredients={{type="item", name="iron-ore", amount=1}},
            results={{type="item", name="iron-plate", amount=1}, {type="item", name="copper-plate", amount=1}}
        }}
        for _, temperature in ipairs{165, 500} do
            data:extend{{
                type="recipe", name="test-machine-steam-" .. temperature, enabled=true,
                categories={"crafting-with-fluid"}, energy_required=1,
                ingredients={{type="item", name="iron-ore", amount=1}},
                results={{type="fluid", name="steam", amount=1, temperature=temperature}}
            }}
        end
    end,
    check = function(context)
        local classes, player = context.classes, game.players[1]
        local district = classes.District.init()
        lib.globals.player_table(player).realm:insert(district)
        local factory = classes.Factory.init("machine-requirements", "sequential")
        district:insert(factory)
        local top = factory.top_floor
        lib.context.set(player, factory)

        local function add_line(floor, recipe_name)
            local line = classes.Line.init(prototyper.util.find("recipes", recipe_name or "test-machine-requirements"))
            floor:insert(line)
            line:change_machine_to_proto(player, prototyper.util.find("machines", "assembling-machine-2", "crafting"))
            return line
        end
        local function add_product(proto, count)
            local product = classes.FactoryItem.init(proto)
            product.definition = {type="machines", machine_count=count}
            factory:insert(product)
            return product
        end
        local first, second = add_line(top), add_line(top)
        local iron = add_product(prototyper.util.find("items", "iron-plate", "item"), 3.5)
        local copper = add_product(prototyper.util.find("items", "copper-plate", "item"), 8)

        local data = solver.generate_factory_data(player, factory)
        assert(first.machine_requirement.count == 3.5 and second.machine_requirement == nil)
        assert(first.machine_requirement.product_proto == iron.proto, "First factory product must win")
        assert(data.line_data_map[first.id].machine_requirement == first.machine_requirement)
        assert(data.line_data_map[first.id].machine_limit == nil, "New requirements must not enable old solver limits")
        assert(first:pack(false).machine_requirement == nil and first:pack(true).machine_requirement == nil)
        factory:shift(copper, "previous", 1)
        solver.generate_factory_data(player, factory)
        assert(first.machine_requirement.count == 8 and first.machine_requirement.product_proto == copper.proto)
        factory:shift(iron, "previous", 1)

        -- Generated recipes can have zero duration, although native recipe prototypes cannot
        local instant = add_line(top)
        instant.recipe.proto = lib.flib.shallow_copy(instant.recipe.proto)
        instant.recipe.proto.energy = 0
        top:move(instant, first, "previous")
        data = solver.generate_factory_data(player, factory)
        assert(instant.recipe.proto.energy <= MAGIC_NUMBERS.minimum_energy)
        assert(instant.machine_requirement == nil and first.machine_requirement.count == 3.5)
        assert(data.line_data_map[instant.id] ~= nil, "Instant recipes must remain available for amount targets")
        first.active, second.active = false, false
        solver.generate_factory_data(player, factory)
        assert(instant.machine_requirement == nil and first.machine_requirement == nil
            and second.machine_requirement == nil, "Instant-only matches must leave machine definitions unassigned")
        iron.definition = {type="amount", amount=1}
        solver.update(player, factory)
        assert(iron.amount == 1 and instant.production_ratio > 0 and instant.machine.amount == 0)
        iron.definition = {type="machines", machine_count=3.5}
        first.active, second.active = true, true
        top:remove(instant)

        top:move(second, first, "previous")
        solver.generate_factory_data(player, factory)
        assert(second.machine_requirement.count == 3.5 and first.machine_requirement == nil)
        second.active = false
        data = solver.generate_factory_data(player, factory)
        assert(second.machine_requirement == nil and first.machine_requirement.count == 3.5)
        assert(data.line_data_map[second.id] == nil, "Blocked matches must be skipped")
        first.active = false
        solver.generate_factory_data(player, factory)
        assert(first.machine_requirement == nil and second.machine_requirement == nil)
        first.active = true
        second.active = true
        solver.generate_factory_data(player, factory)
        assert(second.machine_requirement.count == 3.5 and first.machine_requirement == nil,
            "Re-enabling an earlier match must move the requirement back")
        assert(second.production_ratio == 0, "A usable line must qualify even without existing production")

        local subfloor = classes.Floor.init(2)
        top:replace(second, subfloor)
        subfloor:insert(second)
        local internal = add_line(subfloor)
        solver.generate_factory_data(player, factory)
        assert(second.machine_requirement.count == 3.5 and first.machine_requirement == nil,
            "A subfloor's defining recipe must retain its requirement")
        second.active = false
        solver.generate_factory_data(player, factory)
        assert(second.machine_requirement == nil and internal.machine_requirement == nil
            and first.machine_requirement.count == 3.5, "A blocked defining recipe must allow the next top-floor match")
        top:remove(first)
        solver.generate_factory_data(player, factory)
        assert(second.machine_requirement == nil and internal.machine_requirement == nil,
            "Internal subfloor recipes must not be selected")
        second.active = true
        top:insert(first, subfloor, "previous")

        local cold = add_line(top, "test-machine-steam-165")
        local hot = add_line(top, "test-machine-steam-500")
        local hot_proto = prototyper.util.find("items", hot.recipe.products[1].name, "fluid")
        local steam = add_product(hot_proto, 2)
        solver.generate_factory_data(player, factory)
        assert(hot.machine_requirement.count == 2 and cold.machine_requirement == nil)
        factory:remove(steam)
        solver.generate_factory_data(player, factory)
        assert(hot.machine_requirement == nil, "Removing a product must clear its old assignment")

        solver.update(player, factory)
        assert(first.machine_requirement.count == 3.5)
        -- A producing line appears in compact view; its tooltip must still show only the configured count
        first.production_ratio, first.machine.amount = 7, 7
        main_dialog.rebuild(player, false)
        compact_dialog.rebuild(player, false)
        local ui = lib.globals.ui_state(player)
        local button = find_button(ui.main_elements.main_frame, "act_on_line_machine", "machine_id", first.machine.id)
        assert(button and button.style.name == "fflib_slot_button_blue")
        local tooltip = ui.tooltips.production_table[button.index]
        assert(tooltip[3][3][1] == "fp.machine_requirement" and tooltip[3][3][2] == "3.5")
        assert(tooltip[3][3][4] == nil, "Tooltip must only show the fixed limit")
        local compact_button = find_button(ui.compact_elements.compact_frame,
            "act_on_compact_machine", "line_id", first.id)
        assert(compact_button and compact_button.style.name == "fflib_slot_button_blue")
        local compact_tooltip = ui.tooltips.compact_dialog[compact_button.index]
        assert(compact_tooltip[3][3][1] == "fp.machine_requirement" and compact_tooltip[3][3][2] == "3.5")

        for _, listener in ipairs(item_listeners.gui.on_gui_click) do
            if listener.name == "act_on_item_box" then
                listener.handler(player, {item_id=copper.id}, "move_left")
                assert(first.machine_requirement.count == 8, "Moving a product must refresh the chosen count")
                listener.handler(player, {item_id=copper.id}, "move_right")
                assert(first.machine_requirement.count == 3.5)
            end
        end

        lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=first.machine.id}})
        local elements = lib.globals.modal_elements(player)
        assert(elements.limit_textfield == nil and elements.force_limit_switch == nil)
        lib.gui.close_dialog(player, "submit")
        lib.gui.open_dialog(player, {dialog="machine", modal_data={machine_id=first.machine.id}})
        lib.gui.close_dialog(player, "cancel")

        iron.definition = {type="amount", amount=1}
        factory:remove(copper)
        solver.generate_factory_data(player, factory)
        assert(first.machine_requirement == nil, "Changing definitions must clear old assignments")
        lib.gui.run_refresh(player, "production")
        button = find_button(ui.main_elements.main_frame, "act_on_line_machine", "machine_id", first.machine.id)
        assert(button.style.name == "fflib_slot_button_default")
    end
}
