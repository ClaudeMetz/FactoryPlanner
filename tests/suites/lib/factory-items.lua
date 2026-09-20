---@diagnostic disable

local migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_16")
local old_migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_4")
local Realm = script and require("__factoryplanner__.backend.data.Realm")

local function fixture(context, isolated)
    local player = game.players[1]
    local district = context.classes.District.init()
    local realm = isolated and Realm.init() or lib.globals.player_table(player).realm
    realm:insert(district)
    local factory = context.classes.Factory.init("factory-item-test", "sequential")
    district:insert(factory)
    lib.context.set(player, factory)
    local item = context.classes.FactoryItem.init(prototyper.util.find("items", "iron-plate", "item"))
    factory:insert(item)
    return player, factory, item, realm
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
    migration = {check=function(context)
        local player, factory, item, realm = fixture(context, true)
        local pt = {realm=realm}
        local belt = prototyper.util.find("belts", "transport-belt")
        for _, source_class in ipairs{"TLProduct", "FactoryItem"} do
            for _, mode in ipairs{"amount", "belts"} do
                item.definition = nil
                item.defined_by, item.required_amount = mode, 3
                item.belt_proto = (mode == "belts") and belt or nil
                if source_class == "TLProduct" then
                    old_migration.player_table(pt)
                    item = factory.first
                end
                item.belt_stack = (mode == "belts") and 2 or nil
                item.amount = 7
                local packed = {top_floor={lines={}}, products={{class=source_class,
                    proto=prototyper.util.simplify_prototype(item.proto, "type"),
                    defined_by=mode, required_amount=3, belt_stack=item.belt_stack,
                    belt_proto=(mode == "belts") and prototyper.util.simplify_prototype(belt, nil)}}}
                migration.player_table(pt)
                migration.packed_factory(packed)
                migration.player_table(pt)
                migration.packed_factory(packed)
                item = factory.first
                local restored = context.classes.FactoryItem.unpack(packed.products[1])
                assert(restored:validate(player))
                assert(item.class == "FactoryItem" and item.definition.type == mode and item.amount == 7)
                assert(item:get_defined_amount() == restored:get_defined_amount())
                assert(item:get_defined_amount() == ((mode == "amount") and 3 or 6 * belt.throughput))
                assert(not packed.products[1].required_amount and not packed.products[1].defined_by)
                assert(not item.required_amount and not item.belt_proto)
            end
        end
    end},
    machine_limits = {check=function(context)
        for _, case in ipairs{
            {name="exact", count=2.5, expected=2.5},
            {name="cap", count=2.5, cap=true},
            {name="later recipe"},
            {name="subfloor", count=2.5, subfloor=true, expected=2.5},
            {name="multiple outputs", count=2.5, recipe="advanced-oil-processing", item="petroleum-gas", type="fluid"},
            {name="unmatched output", count=2.5, item="copper-plate"},
            {name="existing definition", count=2.5, existing=4, expected=4},
            {name="zero", count=0},
            {name="infinite", count=math.huge}
        } do
            local player, factory, item, realm = fixture(context, true)
            item.proto = prototyper.util.find("items", case.item or "iron-plate", case.type or "item")
            item.definition = case.existing and {type="machines", machine_count=case.existing}
                or {type="amount", amount=7}
            local top = factory.top_floor
            local first = context.classes.Line.init(prototyper.util.find("recipes", case.recipe or "iron-plate"))
            local second = context.classes.Line.init(prototyper.util.find("recipes", "iron-plate"))
            local internal = context.classes.Line.init(prototyper.util.find("recipes", "iron-plate"))
            top:insert(first)
            top:insert(second)
            local subfloor = context.classes.Floor.init(2)
            local defining = case.subfloor and first or second
            top:replace(defining, subfloor)
            subfloor:insert(defining)
            subfloor:insert(internal)
            for _, line in ipairs{first, second, internal} do line:change_machine_to_default(player) end
            local packed = factory:pack(false)
            local packed_subfloor = packed.top_floor.lines[case.subfloor and 1 or 2]
            local packed_first = case.subfloor and packed_subfloor.lines[1] or packed.top_floor.lines[1]
            local packed_second = case.subfloor and packed.top_floor.lines[2] or packed_subfloor.lines[1]
            for _, machine in ipairs{first.machine, packed_first.machine} do
                machine.limit, machine.force_limit = case.count, not case.cap
            end
            for _, machine in ipairs{second.machine, internal.machine, packed_second.machine,
                    packed_subfloor.lines[2].machine} do
                machine.limit, machine.force_limit, machine.hard_limit = 9, true, true
            end
            for _ = 1, 2 do
                migration.player_table{realm=realm}
                migration.packed_factory(packed)
                for _, product in ipairs{factory.first, packed.products[1]} do
                    assert(product.definition.machine_count == case.expected, case.name)
                    if not case.expected then
                        assert(product.definition.type == "amount" and product.definition.amount == 7, case.name)
                    end
                end
                for _, machine in ipairs{first.machine, second.machine, internal.machine, packed_first.machine,
                        packed_second.machine, packed_subfloor.lines[2].machine} do
                    assert(machine.limit == nil and machine.force_limit == nil and machine.hard_limit == nil, case.name)
                end
            end
        end
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
