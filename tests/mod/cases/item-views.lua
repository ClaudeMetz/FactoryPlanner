---@diagnostic disable

local migration = script and require("__factoryplanner__.backend.migrations.migration_2_1_15")

local function with_player(check)
    local player = game.players[1]
    local player_table = lib.globals.player_table(player)
    local old_preferences, old_ui, old_context = player_table.preferences, player_table.ui_state, player_table.context
    player_table.preferences = lib.flib.deep_copy(old_preferences)
    player_table.preferences.item_views = item_views.default_preferences()
    player_table.ui_state = lib.flib.deep_copy(old_ui)
    player_table.ui_state.main_elements, player_table.ui_state.compact_elements = {}, {}
    player_table.context = lib.flib.deep_copy(old_context)
    item_views.rebuild_data(player)
    local ok, message = xpcall(check, debug.traceback, player, player_table)
    local ui = player_table.ui_state
    if ui.modal_dialog_type then lib.gui.close_dialog(player, "cancel") end
    for _, frame in pairs{ui.main_elements.main_frame, ui.compact_elements.compact_frame} do
        if frame.valid then frame.destroy() end
    end
    player_table.preferences, player_table.ui_state, player_table.context = old_preferences, old_ui, old_context
    assert(ok, message)
end

return {
    with_player = with_player,
    migration = {check=function()
        local previous = {
            views = {
                {name="wagons_per_timescale", enabled=true},
                {name="throughput", enabled=false},
                {name="items_per_timescale", enabled=true},
                {name="items_per_second_per_machine", enabled=false},
                {name="stacks_per_timescale", enabled=false},
                {name="rockets_per_timescale", enabled=false}
            },
            selected_index = 3
        }
        local player_table = {preferences={item_views=previous}}
        migration.player_table(player_table)
        assert(previous.selected.primary == "items_per_timescale" and previous.selected_index == nil)
        migration.player_table(player_table) -- repeated configuration changes before the next release
        lib.preferences.reload(player_table)
        local refreshed = player_table.preferences.item_views
        assert(refreshed == previous, "Reload must preserve the saved item-view preferences")
        assert(refreshed.selected.primary == "items_per_timescale")
        assert(refreshed.views[1].name == "wagons_per_timescale" and refreshed.views[1].enabled)
        assert(not refreshed.views[2].enabled and not refreshed.views[4].enabled)
    end},

    selection = {check=function(context)
        with_player(function(player, player_table)
            local district = context.classes.District.init()
            player_table.realm:insert(district)
            local factory = context.classes.Factory.init("item-view-selection", "sequential")
            district:insert(factory)
            lib.context.set(player, factory)
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)
            local ui, prefs = player_table.ui_state, player_table.preferences.item_views

            local function dispatch(element, event_name)
                ui.last_action = nil
                script.get_event_handler(event_name){
                    name=event_name, tick=game.tick, player_index=player.index, element=element,
                    button=defines.mouse_button_type.left, control=false, alt=false, shift=false
                }
            end

            local function assert_selection(name)
                assert(prefs.selected.primary == name)
                for _, elements in ipairs{ui.main_elements, ui.compact_elements} do
                    local selected = 0
                    for _, button in pairs(elements.views_flow.table_views.children) do
                        if button.toggled then
                            assert(button.tags.view_name == name and button.visible)
                            selected = selected + 1
                        end
                    end
                    assert(selected == 1, "Both selectors must keep exactly the named selection")
                end
            end

            local function find_element(parent, handler, index)
                for _, child in pairs(parent.children) do
                    local tags = child.tags
                    if (tags.on_gui_click == handler and tags.index == index and tags.direction == "up")
                            or (tags.on_gui_checked_state_changed == handler and tags.name == index) then
                        return child
                    end
                    local found = find_element(child, handler, index)
                    if found then return found end
                end
            end

            dispatch(ui.main_elements.views_flow.table_views.children[2], defines.events.on_gui_click)
            assert_selection("throughput")
            local amount = item_views.process_item(player, {type="item"}, defaults.get(player, "belts").proto.throughput)

            lib.gui.open_dialog(player, {dialog="preferences"})
            local function move_up(index)
                local button = find_element(lib.globals.modal_elements(player).views_table, "move_preferences_view", index)
                assert(button and button.enabled)
                dispatch(button, defines.events.on_gui_click)
            end
            move_up(2) -- move the selected view
            assert(prefs.views[1].name == "throughput")
            assert_selection("throughput")
            move_up(2) -- move another view across the selection
            assert(prefs.views[2].name == "throughput")
            assert_selection("throughput")
            assert(item_views.process_item(player, {type="item"}, defaults.get(player, "belts").proto.throughput) == amount,
                "Reordering must retain the view used to format items")

            local checkbox = find_element(lib.globals.modal_elements(player).views_table, "toggle_preference_view", "throughput")
            assert(checkbox and checkbox.enabled)
            checkbox.state = false
            dispatch(checkbox, defines.events.on_gui_checked_state_changed)
            assert_selection("items_per_second_per_machine")
            lib.gui.close_dialog(player, "cancel")

            for _, compact in ipairs{false, true} do
                ui.compact_view = compact
                local elements = compact and ui.compact_elements or ui.main_elements
                dispatch(elements.views_flow.table_views.children[1], defines.events.on_gui_click)
                assert_selection("items_per_timescale")
                item_views.cycle_views(player, "reverse")
                assert_selection("items_per_second_per_machine")
                item_views.cycle_views(player, "standard")
                assert_selection("items_per_timescale")
                item_views.cycle_views(player, "standard")
                assert_selection("items_per_second_per_machine")
            end
            player_table.realm:remove(district)
        end)
    end}
}
