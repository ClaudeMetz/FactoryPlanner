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
        local import_string = "eNrtWVtr2zAU/iuZnusuzrqxGfayQWGwwmieRglGlo9bbZKlSXJYCPnvO7KVxKQpidu0aVdDHyrp6Fy+c5UzJ1Ll6RSM5aokCYlP49OzmJwQ+KuVcSmeWnAkmZOMWggE7z8hQSF4huvhaYx/fk2ZU2amBS1LMGtWixNiq6w55WBJcjUnJZWe1xWX15+5A/mWlxaMAzMZXCrlLLJzXIJlVCDdh+EJKZXzdwme/DAqr1itk8p+AUPyZI5SmkXKBLWe8hvyRerl8qsSAo+9lUjrlE4LoZTxXL7zEnZxq2nu4iZgCoIk8fr8vOa9WG+MlxDMcHcFwFiCQKtnr8XetcN1YxQyjCzjUDKINGW/J4OfQG8G42brTWdcMLaQs1N+M8i8QxIysFxqwQsOOUmcqQCFzbS/4jX0xlCpqhIFxB9RsoE/FTeQp8vdOcmhQJjyNJvhpbC9cStDB6dBpYIKC8EZAcJG7BK0pUWLySG9i5hseNXnYwdyA4zrmugh2DLq4NrHQ0KYoYXj5bXXfc0iDeg3O+3ou2wU8B5ByiksWebK617DiozAMCgdvcateIjQS8pugnGbeiNbkJlAFaJAFb3ronShUFYquORuJR8rZSUgDdWyWdl9g3PK3Sxq7uzWpH2pHaZna8QualbbAimc3BVKwQq24ghSu1lqha/KyXBTwhitbWX9RYB84QOfMt9RbtscTnYYWeg0ELYs/HhPmK0GyPfGt6Zuix0dHNhRR2C/BCh8Ld07Ow3l4iWm4ujxU3FLx+vkv+GG/0b7JkYnB3LjC6vjT11Rm/97Lx7Gi+DlG86iojIlrd3Qp+RLdeaWht37815tePQC2/A6Zib3ejGNbr2YOgUfzacUZ+w8Ytywirt+zu7n7H7OPvqc3TR4VWKLP0pi9uPaITs8UxqhjBjNnrq19348pB+tAxCRFmj5zkLkP8Mes092fSK0FX6ePfIZzWp9j3wGPdI6zI0oM3t8yzhsNnYvqk3hOFAmFpWf+7cIUYLnUX26q17fgOSMirYLzv29xTFq9fBxPnRJrTBCTFSHyS5EMmqxVNYIHitGVgVb8tJ339xwITrq/Xqe1fEjP6sf8kOk1TwH48f3yeC1/AxL/29DJ4t/0glIrA=="
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

    setup_02_compact_interface = function(player)
        data_util.get("main_elements", player).main_frame.location = player.display_resolution  -- hack city
        view_state.select(player, 2)
        local toggle_handler = get_handler(title_bar.gui_events.on_gui_click, "switch_to_compact_view")
        toggle_handler(player, nil, nil)
    end,
    teardown_02_compact_interface = function(player)
        local compact_frame = data_util.get("compact_elements", player).compact_frame
        return_dimensions("02_compact_interface", compact_frame)
        local toggle_handler = get_handler(compact_dialog.gui_events.on_gui_click, "switch_to_main_view")
        toggle_handler(player, nil, nil)
    end,

    setup_03_item_picker = function(player)
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
        belt_handler(player, nil, {element=modal_elements.belt_choice_button, elem_value="fast-transport-belt"})

        modal_elements.search_textfield.focus()
    end,
    teardown_03_item_picker = (function(player) modal_teardown(player, "03_item_picker") end),

    setup_04_recipe_picker = function(player)
        local product_proto = prototyper.util.get_new_prototype_by_name("items", "petroleum-gas", "fluid")
        local modal_data = {product_proto=product_proto, production_type="produce"}
        open_modal(player, "recipe", modal_data)
    end,
    teardown_04_recipe_picker = (function(player) modal_teardown(player, "04_recipe_picker") end),

    setup_05_machine = function(player)
        local floor = data_util.get("context", player).floor
        local line = Collection.get_by_gui_position(floor.Line, 2)
        local modal_data = {object=line.machine, line=line}
        open_modal(player, "machine", modal_data)
    end,
    teardown_05_machine = (function(player) modal_teardown(player, "05_machine") end),

    setup_06_import = function(player)
        open_modal(player, "import", nil)

        local import_string = "eNrtWVtr2zAU/iuZnusuzrqxGfayQWGwwmieRglGlo9bbZKlSXJYCPnvO7KVxKQpidu0aVdDHyrp6Fy+c5UzJ1Ll6RSM5aokCYlP49OzmJwQ+KuVcSmeWnAkmZOMWggE7z8hQSF4huvhaYx/fk2ZU2amBS1LMGtWixNiq6w55WBJcjUnJZWe1xWX15+5A/mWlxaMAzMZXCrlLLJzXIJlVCDdh+EJKZXzdwme/DAqr1itk8p+AUPyZI5SmkXKBLWe8hvyRerl8qsSAo+9lUjrlE4LoZTxXL7zEnZxq2nu4iZgCoIk8fr8vOa9WG+MlxDMcHcFwFiCQKtnr8XetcN1YxQyjCzjUDKINGW/J4OfQG8G42brTWdcMLaQs1N+M8i8QxIysFxqwQsOOUmcqQCFzbS/4jX0xlCpqhIFxB9RsoE/FTeQp8vdOcmhQJjyNJvhpbC9cStDB6dBpYIKC8EZAcJG7BK0pUWLySG9i5hseNXnYwdyA4zrmugh2DLq4NrHQ0KYoYXj5bXXfc0iDeg3O+3ou2wU8B5ByiksWebK617DiozAMCgdvcateIjQS8pugnGbeiNbkJlAFaJAFb3ronShUFYquORuJR8rZSUgDdWyWdl9g3PK3Sxq7uzWpH2pHaZna8QualbbAimc3BVKwQq24ghSu1lqha/KyXBTwhitbWX9RYB84QOfMt9RbtscTnYYWeg0ELYs/HhPmK0GyPfGt6Zuix0dHNhRR2C/BCh8Ld07Ow3l4iWm4ujxU3FLx+vkv+GG/0b7JkYnB3LjC6vjT11Rm/97Lx7Gi+DlG86iojIlrd3Qp+RLdeaWht37815tePQC2/A6Zib3ejGNbr2YOgUfzacUZ+w8Ytywirt+zu7n7H7OPvqc3TR4VWKLP0pi9uPaITs8UxqhjBjNnrq19348pB+tAxCRFmj5zkLkP8Mes092fSK0FX6ePfIZzWp9j3wGPdI6zI0oM3t8yzhsNnYvqk3hOFAmFpWf+7cIUYLnUX26q17fgOSMirYLzv29xTFq9fBxPnRJrTBCTFSHyS5EMmqxVNYIHitGVgVb8tJ339xwITrq/Xqe1fEjP6sf8kOk1TwH48f3yeD//hl2svgHeOT7Fg=="
        local modal_elements = data_util.get("modal_elements", player)
        modal_elements.import_textfield.text = import_string

        local textfield_handler = get_handler(import_dialog.gui_events.on_gui_text_changed, "import_string")
        textfield_handler(player, nil, {element=modal_elements.import_textfield, text=import_string})

        local import_handler = get_handler(import_dialog.gui_events.on_gui_click, "import_subfactories")
        import_handler(player, nil, nil)

        modal_elements.subfactory_checkboxes["tmp_1"].state = false
        modal_elements.subfactory_checkboxes["tmp_3"].state = false
        modal_elements.master_checkbox.state = false
    end,
    teardown_06_import = (function(player) modal_teardown(player, "06_import") end),

    setup_07_utility = function(player)
        open_modal(player, "utility", nil)
    end,
    teardown_07_utility = (function(player) modal_teardown(player, "07_utility") end),

    setup_08_preferences = function(player)
        open_modal(player, "preferences", nil)
    end,
    teardown_08_preferences = (function(player) modal_teardown(player, "08_preferences") end)
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
