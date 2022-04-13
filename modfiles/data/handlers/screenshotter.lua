-- This file contains functionality to rig the interface for various setups
-- that make for good screenshots. It provides a remote interface that its
-- companion scenario calls to actually take the screenshots.

-- This code is terrible and uses some functions completely inappropriately,
-- but it needs to do that to manipulate the interface because GUI events
-- can't be raised manually anymore.

local function open_modal(player, type, modal_data)
    main_dialog.toggle(player)
    data_util.get("main_elements", player).main_frame.location = player.display_resolution  -- hack city
    modal_dialog.enter(player, {type=type, modal_data=modal_data, skip_dimmer=true})
end

local function return_dimensions(scene, frame)
    local dimensions = {actual_size=frame.actual_size, location=frame.location}
    -- We do this on teardown so the frame has time to adjust all its sizes
    remote.call("screenshotter", "return_dimensions", scene, dimensions)
end

local function modal_teardown(player, scene)
    local ui_state = data_util.get("ui_state", player)

    return_dimensions(scene, ui_state.modal_data.modal_elements.modal_frame)
    modal_dialog.exit(player, "cancel")

    ui_util.properly_center_frame(player, ui_state.main_elements.main_frame, ui_state.main_dialog_dimensions)
    main_dialog.toggle(player)
end

local function get_handler(table, name)
    for _, handler_table in pairs(table) do
        if handler_table.name == name then return handler_table.handler end
    end
end

local function set_machine_default(player, proto_name, category_name)
    local category_id = global.all_machines.map[category_name]
    local proto_id = global.all_machines.categories[category_id].map[proto_name]
    prototyper.defaults.set(player, "machines", proto_id, category_id)
end

local actions = {
    player_setup = function(player)
        local player_table = data_util.get("table", player)

        -- Mod settings
        settings.get_player_settings(player)["fp_display_gui_button"] = {value = false}
        settings.get_player_settings(player)["fp_products_per_row"] = {value = 6}
        settings.get_player_settings(player)["fp_subfactory_list_rows"] = {value = 16}

        -- Preferences
        player_table.preferences.recipe_filters = {disabled = true, hidden = false}
        player_table.preferences.ignore_barreling_recipes = true
        player_table.preferences.ignore_recycling_recipes = true
        player_table.preferences.done_column = true
        player_table.preferences.mb_defaults = {  -- naughty use of the prototyper function
            machine = prototyper.util.get_new_prototype_by_name("modules", "productivity-module-3", "productivity"),
            machine_secondary = nil,
            beacon = prototyper.util.get_new_prototype_by_name("modules", "speed-module-3", "speed"),
            beacon_count = 8
        }

        local proto_id = global.all_belts.map["fast-transport-belt"]
        prototyper.defaults.set(player, "belts", proto_id)
        set_machine_default(player, "electric-mining-drill", "basic-solid")
        set_machine_default(player, "steel-furnace", "smelting")
        set_machine_default(player, "assembling-machine-2", "crafting")
        set_machine_default(player, "assembling-machine-3", "advanced-crafting")
        set_machine_default(player, "assembling-machine-2", "crafting-with-fluid")

        -- Subfactories
        local import_string = "eNrtWW1v2yAQ/isen+MqSfdS5ds2adKkTaraD9O0VRbG5+Y2DB7gaFHU/77DJk3apHPcpk1f8i2Gh+O5uwcOwowVOksmYCxqxUZscDA4GPZZj8HfUhuXUK8Fx0YzlnILAXD4hgA5F06baSm5UmCWh+YSU/ruH7w76LOLHrNV2oARLBv9mDHFC2/qRGtnCY/CTz1jblr6ZnRQUGsAobJgHE1AhhwWYAWX1P62TwjtvEFG4GOjs0rUPHX6CwTZHc1oRPORCMmtR35uTM8/P2opqdt77q3rMsml1sZb+YIK2qzVmJusSZiAZKPBov9Tbfti0XA6j8uUWi+jclqAJH+n7IX4+x34ODoVCErAqzY1lI3fNGdsmyFxycXv/4gjjo5JoZGuXGQJClEYFy1M/VRx9P5PhQYiHuVox5HTUVqhzKLTEjOSn2lA31BKPy7lqZxGCiCLCk2jkPojThPoguxqVO6GFJH2abjTvrHFI1o2WJQSc4SMjZypoHclJOSxgZp0lvBCV6qeKYOckpQl6ZRwobk3/zEaHPVD3kO2GrPz/MwZX5xtU0jk8zUB+f2gA9yAwLIG3SV2gjs499IbMWF47lCde+4LE0mIbtOyLPSThgChSb04gbnJTHvuOZeWPkowApTj59Q06JMACy7GwbnrvMksFKkkCnFAxYddSOea5kokFugu5/9KrCVsqrYJumlc1EPap14eVEchyOn1IkRh9jXKCT03aafhkIhViyF8hEmBhz3hujuhp4V/XiYBuET+aD73Oru2pLW9cXxq9LLt4WpgFi0fAhW/BW6sdMNRPkVZD+9B1msqUyeR9deIrFMy/HYfW4dPc6d5likBb9qgiPPKKF7HdJ+Yx5CYNQVnn5sby/OVujPcRt25Y0Eersv/2a1uBsOVm0EnIfFswumAl8UCjajQ7Q95+0PeMzvkNUVMKypjOxF583tfxVb9FLqksMSC7v2wz8lG1av7ghpsfacZ3DXv1gHIuJTEutUd/7fdLutN1yPwMuGnsg6to+jEqdng6rXPx0PchItSU05MXCemzcOUWwqH1RKz3WelQOW3yMyglB2J7+x8v2aH7G12/Bve9vi3/SvF4Z2vlAR0lI+Um9a6NoYCrasfHHZSjGsCgtc1RLlOdJ/KHtAsDo3ko9ECrPV7WIuj19A7So5nYeoHk/q1rSPjR3I/O3yQBbrz+9nwnu5nZw/0ytn2sGkvHxpfzEM3f94v3GcX/wDBKHAm"
        data_util.add_subfactories_by_string(player, import_string)
        main_dialog.refresh(player, "all")

        local trash = Factory.get_by_gui_position(player_table.factory, "Subfactory", 5)
        Factory.remove(player_table.factory, trash)
        Factory.add(player_table.archive, trash)

        local hotness = Factory.get_by_gui_position(player_table.factory, "Subfactory", 3)
        ui_util.context.set_subfactory(player, hotness)
        calculation.update(player, hotness)
        main_dialog.refresh(player, "all")

        -- Research
        player.force.technologies["oil-processing"].researched=true
        player.force.technologies["coal-liquefaction"].researched=true

        -- Player inventory
        player.insert{name="assembling-machine-3", count=9}
        player.insert{name="assembling-machine-2", count=1}
        player.insert{name="electric-mining-drill", count=29}
        player.insert{name="speed-module-3", count=14}
        player.insert{name="speed-module-2", count=1}
        player.insert{name="chemical-plant", count=6}
    end,

    setup_01_main_interface = function(player)
        main_dialog.toggle(player)
    end,
    teardown_01_main_interface = function(player)
        local main_frame = data_util.get("main_elements", player).main_frame
        return_dimensions("01_main_interface", main_frame)
        main_dialog.toggle(player)
    end,

    setup_02_item_picker = function(player)
        local modal_data = {object=nil, item_category="product"}
        open_modal(player, "picker", modal_data)

        local modal_elements = data_util.get("modal_elements", player)
        modal_elements.search_textfield.text = "f"
        local search_handler = get_handler(modal_dialog.gui_events.on_gui_text_changed, "modal_searchfield")
        search_handler(player, nil, {text="f"})

        local group_handler = get_handler(picker_dialog.gui_events.on_gui_click, "select_picker_item_group")
        group_handler(player, {group_id=3}, nil)

        modal_elements.item_choice_button.sprite = "item/raw-fish"
        modal_elements.belt_amount_textfield.text = "0.5"
        modal_elements.belt_choice_button.elem_value = "fast-transport-belt"
        local belt_handler = get_handler(picker_dialog.gui_events.on_gui_elem_changed, "picker_choose_belt")
        belt_handler(player, nil, {elem_value="fast-transport-belt"})

        modal_elements.search_textfield.focus()
    end,
    teardown_02_item_picker = (function(player) modal_teardown(player, "02_item_picker") end),

    setup_03_recipe_picker = function(player)
        local product_proto = prototyper.util.get_new_prototype_by_name("items", "petroleum-gas", "fluid")
        local modal_data = {product_proto=product_proto, production_type="produce"}
        open_modal(player, "recipe", modal_data)
    end,
    teardown_03_recipe_picker = (function(player) modal_teardown(player, "03_recipe_picker") end),

    setup_04_beacon = function(player)
        local floor = data_util.get("context", player).floor
        local line = Collection.get_by_gui_position(floor.Line, 2)
        local modal_data = {object=line.beacon, line=line}
        open_modal(player, "beacon", modal_data)
    end,
    teardown_04_beacon = (function(player) modal_teardown(player, "04_beacon") end),

    setup_05_import = function(player)
        open_modal(player, "import", nil)

        local import_string = "eNrtWdtu2zAM/RVPz3GRuLsUeVsHDBiwAUX7MAxbYcgy3XKVJU+SgwVB/32UrTRpms5xb1m7vMUSRR2SR6QYzVip83QCxqJWbMxGe6O9ZMgGDH5X2riUZi04Np6xYxBYwaHWFySW7L3bG5FUxi2EVftv6LvgwmkzrSRXCsyyvkJiRt9DWjhklwNm66wVRrBs/H3GFC+9qmOtnSV5FB7PjLlp5YfRQUmjQQiVBeNoA1LksAQruKTxt0OS0M4rZCR8ZHReiwa8zn6CIL3jGa1oP1IhufWSn1rV888PWkqa9u7w2nWVFlJr47V8RgVd2hqZ27RJmIBk49Fi/mOj+3IxcDL3y5RGr7xyUoIke6fsP7H3G/Dz6EQgKAGvuthQtXbTnrFtl8QVFxd/IUccHRFDI127yJIoRGFdtFD1Q8XR+181Goh4VKA9j5yOshplHp1UmBP9TCv0FaX06zKeyWmkAPKo1LQKaT7itIEuSa9G5W4JEXGfljvtBzssomODZSWxQMjZ2JkaBtdcQhYbaEDnKS91rZqdcigoSHmaTUkuDA/mP8ajg2GIe4hWq3Yenzniy9OHJBLZvEIgnw96iJsmG3mh+/hOcAdnnnpjJgwvHKozj32hIg3ebUeWid6mQy9N7MUJzFXm2mMvuLT0UYERoBw/o6HRkAhYcnEejFvFTWqhzCRBiINUvN8HdKFpr1Riie5q/y+EWsKmbJugm8Zls6R76+VFjRcCnV4vXBR2X8OcMHMbd1oMqbipMbiPZDLgISesmhNmOvAXVRoEl8AfzPdep9dWdLY39k8jvaw7uemYxchhgOJT4MZMNxzlc6R18gi0XlOZepFsuIZkvYLh031sHT7PTPMiQwJetUERF7VRvPHpLjD/QmDWFJxdbG4tz9fqTvIQdeeeBTlZF//TO3UGyY3OoBeReD7hdMHLY4FG1Oh2l7zdJe+FXfLaIqYVlbGtkLz9vatiN+0UuiK3xIL6ftjFZKPq1f9AjR4804zuG3frAGRcSULdaY7/226b9abvFXgZ8HM5h9aRd+LMbNB67eLxFJ1wWWmKiYmbwHRZmHFL7rBaYr79qJSofIrMDUrZE/jW7vdrMuRgs+tfctfr38O3FPv3bilJ0FE8Mm4669o5lGhd8+CwlWLcABC8qSHK9YL7XHJAezg0ko1GC7DW57AOQ1ektxQcj8I0DybNa1tPxP9If7b/JAd06/1Z8kj92ekTvXJ2PWzaq4fGF/7QfXr5B3aFKGY="
        local modal_elements = data_util.get("modal_elements", player)
        modal_elements.import_textfield.text = import_string

        local textfield_handler = get_handler(import_dialog.gui_events.on_gui_text_changed, "import_string")
        textfield_handler(player, nil, {text=import_string})

        local import_handler = get_handler(import_dialog.gui_events.on_gui_click, "import_subfactories")
        import_handler(player, nil, nil)

        modal_elements.subfactory_checkboxes["tmp_1"].state = false
        modal_elements.subfactory_checkboxes["tmp_3"].state = false
        modal_elements.master_checkbox.state = false
    end,
    teardown_05_import = (function(player) modal_teardown(player, "05_import") end),

    setup_06_utility = function(player)
        open_modal(player, "utility", nil)
    end,
    teardown_06_utility = (function(player) modal_teardown(player, "06_utility") end),

    setup_07_preferences = function(player)
        open_modal(player, "preferences", nil)
    end,
    teardown_07_preferences = (function(player) modal_teardown(player, "07_preferences") end)
}

local function initial_setup()
    DEVMODE = false  -- desync city, but it's fiiine. Avoids any accidental artifacts.
end

local function execute_action(player_index, action_name)
    local player = game.get_player(player_index)
    actions[action_name](player)
end

remote.add_interface("factoryplanner", {
    initial_setup = initial_setup,
    execute_action = execute_action
})
