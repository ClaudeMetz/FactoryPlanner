---@diagnostic disable

local with_player = require("suite.items").with_player

local function find_pump_picker(parent)
    for _, child in pairs(parent.children) do
        if child.tags.on_gui_elem_changed == "select_preference_box_default"
                and child.tags.data_type == "pumps" then return child end
        local found = find_pump_picker(child)
        if found then return found end
    end
end

local throughput_views = {}

function throughput_views.case(pump_available)
    return {
        setup = function()
            if not pump_available then
                for _, proto in pairs(data.raw.pump) do proto.hidden = true end
            end
        end,
        check = function(context)
            with_player(function(player, player_table)
                local prefs = player_table.preferences
                prefs.item_views.selected.primary = "throughput"
                for _, view in ipairs(prefs.item_views.views) do view.enabled = view.name == "throughput" end

                local district = context.classes.District.init()
                player_table.realm:insert(district)
                local factory = context.classes.Factory.init("throughput-views", "sequential")
                district:insert(factory)
                lib.context.set(player, factory)
                main_dialog.rebuild(player, false)
                compact_dialog.rebuild(player, false)

                local belt_rate = defaults.get(player, "belts").proto.throughput
                local pump = defaults.get_optional(player, "pumps")
                for _, unit in ipairs{"belts", "lanes"} do
                    for _, stack in ipairs{1, 4} do
                        prefs.belts_or_lanes, prefs.belt_stack = unit, stack
                        item_views.rebuild_data(player)
                        local rate = belt_rate * stack / (unit == "lanes" and 2 or 1)
                        local amount, tooltip = item_views.process_item(player, {type="item"}, rate)
                        assert(amount == 1 and tooltip[4][1] == "fp.pl_" .. unit:sub(1, -2))
                        if pump_available then
                            local pump_rate = prototypes.entity[pump.proto.name].get_pumping_speed(pump.quality.name) * 60
                            amount, tooltip = item_views.process_item(player, {type="fluid"}, pump_rate)
                            assert(amount == 1 and tooltip[4][1] == "fp.pl_pump")
                        else
                            amount, tooltip = item_views.process_item(player, {type="fluid"}, 100)
                            assert(amount == nil and tooltip == nil, "Missing pumps must leave fluid amounts blank")
                        end
                    end
                end

                item_views.rebuild_interface(player)
                item_views.cycle_views(player, "standard")
                item_views.cycle_views(player, "reverse")
                assert(prefs.item_views.selected.primary == "throughput", "Missing pumps must not drop the throughput selection")
                for _, elements in ipairs{player_table.ui_state.main_elements, player_table.ui_state.compact_elements} do
                    for _, button in pairs(elements.views_flow.table_views.children) do
                        local selected = button.tags.view_name == "throughput"
                        assert(button.visible == selected and button.toggled == selected)
                    end
                end

                lib.gui.open_dialog(player, {dialog="preferences"})
                local picker = find_pump_picker(lib.globals.modal_elements(player).modal_frame)
                assert(picker and picker.enabled == pump_available)
                if pump_available then
                    assert(picker.elem_value.name == pump.proto.name)
                else
                    assert(picker.elem_value == nil and picker.tooltip[1] == "fp.preference_no_default_prototype")
                    assert(picker.tooltip[2][1] == "fp.pl_pump")
                end
                lib.gui.close_dialog(player, "cancel")
                player_table.realm:remove(district)
            end)
        end
    }
end

return throughput_views
