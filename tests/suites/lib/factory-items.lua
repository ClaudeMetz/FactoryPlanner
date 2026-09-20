---@diagnostic disable

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
            assert(button.number == expected and button.style.name == "fflib_slot_button_blue")
            local tooltip = lib.globals.ui_state(player).tooltips.item_boxes[button.index]
            assert(tooltip[5] == "", "Calculated output must not show target satisfaction")
            local machine_definition = tooltip[#tooltip][3]
            assert(machine_definition[1] == "fp.item_defined_by_machines" and machine_definition[2] == "5")
            assert(machine_definition[3][1] == "fp.pl_machine" and machine_definition[3][2] == 5)
        end
        local output = context.classes.FactoryItem.init(prototyper.util.find("items", "copper-plate", "item"))
        output.definition = {type="amount", amount=10}
        factory:insert(output)
        local factory_data = solver.generate_factory_data(player, factory)
        local targets = factory_data.floor_data_map[factory.top_floor.id].products
        assert(#targets == 1 and targets[1].name == "copper-plate" and targets[1].amount == 10)
        solver.set_factory_result{
            player_index=player.index, factory_id=factory.id,
            products={["item/copper-plate"]=10}, byproducts={["item/iron-plate"]=12}, ingredients={}
        }
        assert(item.amount == 12 and output.amount == 10)
        assert(#factory.top_floor.byproducts == 0, "Machine-defined output must not also appear as a byproduct")
    end}
}
