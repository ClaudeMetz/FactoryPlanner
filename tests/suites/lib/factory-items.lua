---@diagnostic disable

local helpers = require("helpers")

local function fixture(context)
    local player = game.players[1]
    local district = context.classes.District.init()
    lib.globals.player_table(player).realm:insert(district)
    local factory = context.classes.Factory.init("factory-item-test", "sequential")
    district:insert(factory)
    lib.context.set(player, factory)
    local item = context.classes.FactoryItem.init(prototyper.util.find("items", "iron-plate", "item"))
    factory:insert(item)
    return player, factory, item
end

local function dispatch(player, element, event_name)
    lib.globals.ui_state(player).last_action = nil
    script.get_event_handler(event_name){name=event_name, tick=game.tick, player_index=player.index,
        element=element, button=defines.mouse_button_type.left, control=false, alt=false, shift=false}
end


return {
    definitions = {check=function(context)
        local player, factory, item = fixture(context)
        local belt = prototyper.util.find("belts", "transport-belt")
        for _, definition in ipairs{
            {type="amount", amount=90},
            {type="belts", belt_count=2, belt_proto=belt, belt_stack=2},
            {type="machines", machine_count=2.5}
        } do
            item.definition = definition
            local expected
            if definition.type == "amount" then expected = 90
            elseif definition.type == "belts" then expected = 4 * belt.throughput end
            assert(item:get_defined_amount() == expected)
            local packed_factory = factory:pack(false)
            local factory_copy = context.classes.Factory.unpack(packed_factory)
            assert(factory_copy:validate(player))
            assert(factory_copy.first.definition.type == definition.type)
            assert(factory_copy.first:get_defined_amount() == expected)
            assert(factory_copy.first.definition.machine_count == definition.machine_count)
            local packed = item:pack(true)
            local restored = context.classes.FactoryItem.unpack(packed)
            assert(restored:validate(player))
            assert(restored.definition.type == definition.type and restored:get_defined_amount() == expected)
            assert(restored.definition.machine_count == definition.machine_count)
            restored.definition.type = "amount"
            assert(packed.definition.type == definition.type, "Unpacking must not mutate the snapshot")
            lib.clipboard.copy(player, item)
            assert(lib.clipboard.paste(player, item))
            item = factory.first
            assert(item.definition.type == definition.type)
            assert(item.definition.machine_count == definition.machine_count)
            item:add_defined_amount(30)
            if definition.type == "machines" then
                assert(item:get_defined_amount() == nil and item.definition.machine_count == 2.5)
            else
                assert(item:get_defined_amount() == expected + 30)
            end
        end
        local max_stack = prototypes.utility_constants.max_belt_stack_size
        item.definition = {type="belts", belt_count=2, belt_proto=belt, belt_stack=max_stack * 2}
        local expected = item:get_defined_amount()
        assert(item:validate(player) and item:get_defined_amount() == expected)
        assert(item.definition.belt_stack == max_stack and item.definition.belt_count == 4)
    end},
    toggle = {check=function(context)
        local player, factory, item = fixture(context)
        local line = context.classes.Line.init(prototyper.util.find("recipes", "iron-plate"))
        factory.top_floor:insert(line)
        line:change_machine_to_proto(player, helpers.find_machine("stone-furnace"))
        main_dialog.rebuild(player, false)
        compact_dialog.rebuild(player, false)

        local function product_button()
            return lib.globals.main_elements(player).item_boxes.product_item_table.children[1]
        end
        local function menu_toggle()
            local button = product_button()
            lib.globals.ui_state(player).last_action = nil
            script.get_event_handler(defines.events.on_gui_click){
                name=defines.events.on_gui_click, tick=game.tick, player_index=player.index,
                element=button, button=defines.mouse_button_type.right, control=false, alt=false, shift=false,
                cursor_display_location={x=0, y=0}}
            local menu = lib.globals.ui_state(player).context_menu
            assert(menu, "Right-click must open the product context menu")
            for _, action in pairs(menu.children[1].children) do
                if action.tags.action == "toggle" then return action end
            end
            error("Product context menu must offer Toggle")
        end
        local belt = prototyper.util.find("belts", "transport-belt")
        for _, solver_name in ipairs{"sequential", "simplex", "gaussian"} do
            factory.top_floor.solver = solver_name
            for _, definition in ipairs{
                {type="amount", amount=10},
                {type="belts", belt_count=1, belt_proto=belt, belt_stack=1},
                {type="machines", machine_count=5}
            } do
                item.definition, item.active = definition, true
                solver.update(player, factory)
                local expected = line.machine.amount
                assert(expected > 0, "Active products must drive production")
                lib.gui.run_refresh(player, "production")
                dispatch(player, menu_toggle(), defines.events.on_gui_click)
                assert(item.active == false and item.definition == definition)
                assert(line.machine.amount == 0 and line.machine_requirement == nil)
                assert(product_button().style.name == "fflib_slot_button_red")
                local packed = factory:pack(false)
                local restored = context.classes.Factory.unpack(packed)
                assert(restored:validate(player) and restored.first.active == false)
                lib.clipboard.copy(player, item)
                assert(lib.clipboard.paste(player, item))
                item = factory.first
                assert(item.active == false and item.definition.type == definition.type)
                dispatch(player, menu_toggle(), defines.events.on_gui_click)
                assert(item.active == true and helpers.approx(line.machine.amount, expected))
                assert(product_button().style.name == "fflib_slot_button_green")
            end
        end
        for _, close_action in ipairs{"cancel", "submit", "submit"} do
            local active = item.active
            lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
            local button = lib.globals.modal_elements(player).active_button
            assert(button and button.toggled == active)
            button.toggled = not active
            assert(item.active == active, "Editing the toggle must wait for submission")
            lib.gui.close_dialog(player, close_action)
            local expected = active
            if close_action == "submit" then expected = not active end
            assert(item.active == expected)
            assert((line.machine.amount > 0) == expected)
        end
        for _, create_factory in ipairs{false, true} do
            lib.gui.open_dialog(player, {dialog="picker",
                modal_data={item_category="product", create_factory=create_factory}})
            assert(lib.globals.modal_elements(player).active_button == nil,
                "The active toggle must only be offered when editing")
            lib.gui.close_dialog(player, "cancel")
        end

        factory.archived = true
        lib.gui.run_refresh(player, "production")
        assert(not menu_toggle().enabled, "Archived targets must not be toggleable")
        modal_dialog.close_context_menu(player)
        factory.archived = false
    end},
    picker = {check=function(context)
        local player, factory, item = fixture(context)
        local preferences = lib.globals.preferences(player)
        local previous_unit = preferences.belts_or_lanes
        main_dialog.rebuild(player, false)
        compact_dialog.rebuild(player, false)
        for _, unit in ipairs{"belts", "lanes"} do
            preferences.belts_or_lanes = unit
            for _, mode in ipairs{"amount", "belts"} do
                item.definition = (mode == "amount") and {type="amount", amount=90}
                    or {type="belts", belt_count=2, belt_stack=2,
                        belt_proto=prototyper.util.find("belts", "transport-belt")}
                local expected = item:get_defined_amount()
                lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
                local e = lib.globals.modal_elements(player)
                assert(e.item_amount_textfield.enabled == (mode == "amount"))
                assert(e.belt_amount_textfield.enabled == (mode == "belts"))
                if mode == "belts" then
                    assert(tonumber(e.belt_amount_textfield.text) == ((unit == "lanes") and 4 or 2))
                    assert(e.belt_stack_dropdown.selected_index == 2)
                end
                assert(e.dialog_submit_button.enabled)
                lib.gui.close_dialog(player, "submit")
                assert(item.definition.type == mode and math.abs(item:get_defined_amount() - expected) < 0.0001)
                assert((item.definition.belt_proto ~= nil) == (mode == "belts"))
                lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
                e = lib.globals.modal_elements(player)
                assert(not e.machine_count_checkbox.state and not e.machine_count_textfield.enabled)
                e.machine_count_checkbox.state = true
                dispatch(player, e.machine_count_checkbox, defines.events.on_gui_checked_state_changed)
                assert(not e.item_amount_textfield.enabled and not e.belt_amount_textfield.enabled)
                assert(not e.belt_choice_button.enabled and not e.belt_stack_dropdown.enabled)
                assert(e.item_amount_textfield.text == "" and e.belt_amount_textfield.text == "")
                assert(e.belt_choice_button.elem_value == nil)
                assert(e.belt_stack_dropdown.selected_index == preferences.belt_stack)
                assert(e.machine_count_textfield.enabled and not e.dialog_submit_button.enabled)
                e.machine_count_textfield.text = "2+3"
                dispatch(player, e.machine_count_textfield, defines.events.on_gui_text_changed)
                assert(e.dialog_submit_button.enabled)
                dispatch(player, e.machine_count_textfield, defines.events.on_gui_confirmed)
                assert(e.machine_count_textfield.text == "5")
                dispatch(player, e.machine_count_textfield, defines.events.on_gui_confirmed)
                assert(item.definition.type == "machines" and item.definition.machine_count == 5)
                assert(item:get_defined_amount() == nil and item.definition.belt_proto == nil)
                lib.gui.open_dialog(player, {dialog="picker", modal_data={item_id=item.id, item_category="product"}})
                e = lib.globals.modal_elements(player)
                assert(e.machine_count_checkbox.state and e.machine_count_textfield.enabled)
                assert(e.machine_count_textfield.text == "5" and e.dialog_submit_button.enabled)
                assert(e.item_amount_textfield.text == "" and not e.item_amount_textfield.enabled)
                assert(e.belt_choice_button.elem_value == nil and not e.belt_choice_button.enabled)
                e.machine_count_checkbox.state = false
                dispatch(player, e.machine_count_checkbox, defines.events.on_gui_checked_state_changed)
                assert(e.item_amount_textfield.enabled and not e.belt_amount_textfield.enabled)
                assert(e.item_amount_textfield.text == "" and e.belt_amount_textfield.text == "")
                assert(not e.machine_count_textfield.enabled and not e.dialog_submit_button.enabled)
                e.item_amount_textfield.text = "60"
                dispatch(player, e.item_amount_textfield, defines.events.on_gui_text_changed)
                lib.gui.close_dialog(player, "submit")
                assert(item.definition.type == "amount" and item.definition.machine_count == nil)
                assert(item:get_defined_amount() == 60 / preferences.timescale)
            end
        end
        preferences.belts_or_lanes = previous_unit

        item.definition = {type="machines", machine_count=5}
        for _, amount in ipairs{0, 12} do
            item.amount = amount
            lib.gui.run_refresh(player, "item_boxes")
            local button = lib.globals.main_elements(player).item_boxes.product_item_table.children[1]
            local expected = item_views.process_item(player, item.proto, amount, nil)
            assert(button.number == expected and button.style.name == "fflib_slot_button_green")
            local tooltip = lib.globals.ui_state(player).tooltips.item_boxes[button.index]
            local machine_definition = tooltip[#tooltip][3]
            assert(machine_definition[1] == "fp.item_defined_by_machines" and machine_definition[2] == "5")
            assert(machine_definition[3][1] == "fp.pl_machine" and machine_definition[3][2] == 5)
        end
        local output = context.classes.FactoryItem.init(prototyper.util.find("items", "copper-plate", "item"))
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
}
