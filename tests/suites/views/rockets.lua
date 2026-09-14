---@diagnostic disable

local with_player = require("suite.items").with_player

local function find_silo_picker(parent)
    for _, child in pairs(parent.children) do
        if child.tags.on_gui_elem_changed == "select_preference_box_default"
                and child.tags.data_type == "silos" then return child end
        local found = find_silo_picker(child)
        if found then return found end
    end
end

return {
    setup = function()
        for _, proto in pairs(data.raw["rocket-silo"]) do proto.launch_to_space_platforms = false end
    end,
    check = function(context)
        with_player(function(player, player_table)
            player_table.preferences.timescale = 60
            local prefs = player_table.preferences.item_views
            prefs.selected.primary = "rockets_per_timescale"
            for _, view in ipairs(prefs.views) do view.enabled = view.name == "rockets_per_timescale" end

            local district = context.classes.District.init()
            player_table.realm:insert(district)
            local factory = context.classes.Factory.init("rocket-views", "sequential")
            district:insert(factory)
            lib.context.set(player, factory)
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)

            assert(prefs.selected.primary == "items_per_timescale")
            for _, view in ipairs(prefs.views) do
                assert(view.enabled == (view.name == "items_per_timescale"))
            end
            assert(item_views.process_item(player, {type="item"}, 2) == 120)

            lib.gui.open_dialog(player, {dialog="preferences"})
            local modal = lib.globals.modal_elements(player)
            local picker = find_silo_picker(modal.modal_frame)
            assert(picker and not picker.enabled and picker.elem_value == nil)
            assert(picker.tooltip[1] == "fp.preference_no_default_prototype")

            local checkbox
            for _, child in pairs(modal.views_table.children) do
                if child.tags.name == "rockets_per_timescale" then checkbox = child end
            end
            assert(checkbox and not checkbox.enabled and not checkbox.state)
            assert(checkbox.tooltip[1] == "fp.preference_no_default_prototype")
            lib.gui.close_dialog(player, "cancel")

            player_table.realm:remove(district)
        end)
    end
}
