---@diagnostic disable

local with_player = require("suite.items").with_player

local function find_control(parent, category)
    for _, child in pairs(parent.children) do
        if child.tags.on_gui_elem_changed == "select_preference_box_default"
                and child.tags.category_id == category then return child end
        local found = find_control(child, category)
        if found then return found end
    end
end

local function check_selection(player, cargo_available, fluid_available, expected_selection)
    local ui, prefs = lib.globals.ui_state(player), lib.globals.preferences(player).item_views
    local available = cargo_available or fluid_available
    expected_selection = expected_selection or (available and "wagons_per_timescale" or "items_per_timescale")
    assert(prefs.selected.primary == expected_selection)
    for _, view in ipairs(prefs.views) do
        assert(view.enabled == (view.name == expected_selection), "Only the selected view should remain enabled in this fixture")
    end
    for _, elements in ipairs{ui.main_elements, ui.compact_elements} do
        local visible, selected = 0, 0
        for _, button in pairs(elements.views_flow.table_views.children) do
            if button.visible then visible = visible + 1 end
            if button.toggled then
                selected = selected + 1
                assert(button.visible and button.tags.view_name == prefs.selected.primary)
            end
        end
        assert(visible == 1 and selected == 1, "Both selectors must show the enabled and selected view")
    end
    for _, entry in ipairs{{"cargo-wagon", "item", cargo_available}, {"fluid-wagon", "fluid", fluid_available}} do
        local amount, tooltip = item_views.process_item(player, {type=entry[2], stack_size=100}, 2)
        if expected_selection == "items_per_timescale" then
            assert(amount == 120, "The items/minute selection must control formatting")
        elseif not entry[3] then
            assert(amount == nil and tooltip == nil, "Missing wagon types must leave amounts blank without a warning")
        else
            local default = defaults.get_optional(player, "wagons", entry[1])
            local proto = prototypes.entity[default.proto.name]
            local capacity = entry[1] == "cargo-wagon"
                and proto.get_inventory_size(defines.inventory.cargo_wagon, default.quality.name) * 100
                or proto.get_fluid_capacity(default.quality.name)
            amount = item_views.process_item(player, {type=entry[2], stack_size=100}, capacity / 60)
            assert(amount == 1, "Available wagons must still produce wagon counts")
        end
    end
    lib.gui.open_dialog(player, {dialog="preferences"})
    local modal = lib.globals.modal_elements(player)
    for _, entry in ipairs{{"cargo-wagon", cargo_available}, {"fluid-wagon", fluid_available}} do
        local control = find_control(modal.modal_frame, entry[1])
        assert(control and control.enabled == entry[2])
        if entry[2] then
            assert(prototypes.entity[control.elem_value.name].type == entry[1], "Controls must resolve category names, not fixed IDs")
        else
            assert(control.elem_value == nil)
        end
    end
    for _, element in pairs(modal.views_table.children) do
        if element.type == "checkbox" and element.tags.name == "wagons_per_timescale" then
            assert(element.state == (expected_selection == "wagons_per_timescale"))
            if not available then assert(not element.enabled) end
        end
    end
    lib.gui.close_dialog(player, "cancel")
end

local function fixture(player, player_table, context)
    player_table.preferences.timescale = 60
    local prefs = player_table.preferences.item_views
    prefs.selected.primary = "wagons_per_timescale"
    for _, view in ipairs(prefs.views) do view.enabled = view.name == "wagons_per_timescale" end
    -- Exercise cycling before either interface has been opened.
    player_table.ui_state.views_data = nil
    item_views.cycle_views(player, "standard")
    local district = context.classes.District.init()
    player_table.realm:insert(district)
    local factory = context.classes.Factory.init("wagon-views", "sequential")
    district:insert(factory)
    lib.context.set(player, factory)
    main_dialog.rebuild(player, false)
    compact_dialog.rebuild(player, false)
    return district
end

local wagon_views = {}

function wagon_views.case(cargo_available, fluid_available)
    return {
        setup = function()
            for _, entry in ipairs{{"cargo-wagon", cargo_available}, {"fluid-wagon", fluid_available}} do
                if not entry[2] then
                    for _, proto in pairs(data.raw[entry[1]]) do proto.hidden = true end
                    data.raw["item-with-entity-data"][entry[1]].hidden = true
                end
            end
        end,
        check = function(context)
            with_player(function(player, player_table)
                local district = fixture(player, player_table, context)
                check_selection(player, cargo_available, fluid_available)
                for _, compact in ipairs{false, true} do
                    player_table.ui_state.compact_view = compact
                    item_views.cycle_views(player, "standard")
                    item_views.cycle_views(player, "reverse")
                    local expected = (cargo_available or fluid_available) and "wagons_per_timescale" or "items_per_timescale"
                    assert(player_table.preferences.item_views.selected.primary == expected)
                end
                player_table.realm:remove(district)
            end)
        end
    }
end

wagon_views.restoration = {check=function(context)
    local original, original_map = storage.prototypes.wagons, PROTOTYPE_MAPS.wagons
    local ok, message = xpcall(function()
        with_player(function(player, player_table)
            local district = fixture(player, player_table, context)
            -- Simulate the catalog/migration/rebuild sequence on configuration changes.
            storage.prototypes.wagons, PROTOTYPE_MAPS.wagons = {}, {}
            defaults.migrate(player_table)
            item_views.rebuild_data(player)
            item_views.rebuild_interface(player)
            check_selection(player, false, false)
            storage.prototypes.wagons, PROTOTYPE_MAPS.wagons = original, original_map
            defaults.migrate(player_table)
            item_views.rebuild_data(player)
            item_views.rebuild_interface(player)
            check_selection(player, true, true, "items_per_timescale")

            -- Keep another enabled view instead of enabling items/time unnecessarily.
            local prefs = player_table.preferences.item_views
            prefs.selected.primary = "wagons_per_timescale"
            for _, view in ipairs(prefs.views) do
                view.enabled = view.name == "wagons_per_timescale" or view.name == "throughput"
            end
            storage.prototypes.wagons, PROTOTYPE_MAPS.wagons = {}, {}
            defaults.migrate(player_table)
            item_views.rebuild_data(player)
            assert(prefs.selected.primary == "throughput")
            for _, view in ipairs(prefs.views) do
                assert(view.enabled == (view.name == "throughput"))
            end
            storage.prototypes.wagons, PROTOTYPE_MAPS.wagons = original, original_map
            defaults.migrate(player_table)
            item_views.rebuild_data(player)
            assert(prefs.selected.primary == "throughput", "Returning wagons must not restore a dropped selection")
            player_table.realm:remove(district)
        end)
    end, debug.traceback)
    storage.prototypes.wagons, PROTOTYPE_MAPS.wagons = original, original_map
    assert(ok, message)
end}

return wagon_views
