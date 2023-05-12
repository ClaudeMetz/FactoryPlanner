-- This file contains functionality to rig the interface for various setups
-- that make for good screenshots. It provides a remote interface that its
-- companion scenario calls to actually take the screenshots.

-- This code is terrible and uses some functions completely inappropriately,
-- but it needs to do that to manipulate the interface because GUI events
-- can't be raised manually anymore.

local mod_gui = require("mod-gui")

local function return_dimensions(scene, frame)
    local dimensions = {actual_size=frame.actual_size, location=frame.location}
    -- We do this on teardown so the frame has time to adjust all its sizes
    remote.call("screenshotter_output", "return_dimensions", scene, dimensions)
end

local function open_modal(player, type, modal_data)
    main_dialog.toggle(player)
    data_util.get("main_elements", player).main_frame.location = player.display_resolution  -- hack city
    modal_dialog.enter(player, {type=type, modal_data=modal_data, skip_dimmer=true})
end

local function modal_teardown(player, scene)
    return_dimensions(scene, data_util.get("modal_elements", player).modal_frame)
    modal_dialog.exit(player, "cancel")
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
        settings.get_player_settings(player)["fp_products_per_row"] = {value = 5}
        settings.get_player_settings(player)["fp_subfactory_list_rows"] = {value = 18}

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
        local export_string = "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"
        data_util.add_subfactories_by_string(player, export_string)

        local trash = Factory.get_by_gui_position(player_table.factory, "Subfactory", 5)
        Factory.remove(player_table.factory, trash)
        Factory.add(player_table.archive, trash)

        local hotness = Factory.get_by_gui_position(player_table.factory, "Subfactory", 3)
        ui_util.context.set_subfactory(player, hotness)
        solver.update(player, hotness)
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
        local translation_progress = mod_gui.get_frame_flow(player)["flib_translation_progress"]
        if translation_progress then translation_progress.visible = false end
        main_dialog.toggle(player)
    end,
    teardown_01_main_interface = function(player)
        local main_frame = data_util.get("main_elements", player).main_frame
        return_dimensions("01_main_interface", main_frame)
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
        local line = Collection.get_by_gui_position(floor.Line, 2)  --[[@as unknown]]
        local modal_data = {object=line.machine, line=line}
        open_modal(player, "machine", modal_data)
    end,
    teardown_05_machine = (function(player) modal_teardown(player, "05_machine") end),

    setup_06_import = function(player)
        open_modal(player, "import", nil)

        local export_string = "eNrtWt+P4jYQ/lfcPG+2hG2ra6Q+tJUqVepJp+Ohqu5Q5DiT3Wn9I7UdVIT43ztOzIK4RRDKHnBF4gHb4/HM941n7CSLRJmqmIF1aHSSJ9l9dv/tKLlL4J/GWF/QqAOf5Iuk5A5WAt+TQC2xpPboPqNfaHPhjZ03kmsNdq1qeZe4tuxHEVySf1gkmqug6wOqxx/Qg/oatQPrwU7Ze2O8I3UeFTjBJcl9N7pLtPFhbkIj76ypWtHZZMo/QZB4vqBV+kYhJHdB8lfSS9Kr5s9GShoOXpKsN01RS2Ns0PIbatinrZPZpU3CDGSSZ+vxXzrdy3XHZAXBnHqfAZgokOT1/P/i75rwpneKFKZOIGgBacPFX1P2B/AnNum7vtqNS8reUaAx03rmaCKwqIWtFX/UKfvx7xYtMM5qdE/MG1a2KCs2abCieLO90O8oZZhX8lLOmQaomDI0C2mccVrAKNJrUPsdbFBE03RvQmf0dId/pMChaiTWCFWSe9sCuThvwpSAS4CQK9PSUnn2hvy10HlQFaveRVJBTeRURTmnSbF7a1ZJYVVEk2ouHcQQiMT1y66oWnm0nJ4ypgiTrVgKWWCAuAWBTSf0X7AV3MNjiMI8EZbXHvVjsH2toojo9z2bMf++NyAwQpIzWKmsTLC9g5UUgRWgPX+krmxE0CsunqJz23aTWlClJBPSKJU+DDG6NrRWIVGhf16f8nMroYg5um+5Q4Nzhn6e9nP2W7I5aTNMv1kj9rZT9VIgxZFdoRS9EM8aQTV+XjgZakE+2l5hQt5u5Jq3EfJlCHwuQh371Oc4ssfJuimi4IaHb46E2TWUSg7Gt5PeXHZ8cmDHA4H9KUIRMvjBu9NylNe4FcevvxVfqLOD+Btt8Tc+dGMMIjCUvdR5vM6MeqMxYgNhfYsirVurecfDjcxrJfOFin3j86g6PL7COryOmelRF7XxJxe1QcHHqxmnQ3aVCrSiRX87aN8O2reD9tkP2n2BN5pK/Fk2Zv//VuFPU+GFaQjKVPDyc5f2a+Hx9Bs/O/nGz7ZiJXuVWHEeQKaNJNf2+hyeMJ+zFg+9hmwa/CXvd+cJ0bS0B1yzbxxe6pMS1Rji0aYdmftQKbkjCJ2RWJ2fSYU6pO/KopQDDb+Ue9kL2fvusCP4+Ngj+OlPig9HXwUHPT4gQU8cltzurdNPoND57r3dWQ4XnQGCd/VN+0HmXkaueXgVCvtNaJBwsUaAcyG/7gFnS/pMhAYrbPfOsnvRPdDiy7yLP1xOIrjku/j4mu/i08/+UYR7/ixhyr7sT0Kmy38BcOORig=="
        local modal_elements = data_util.get("modal_elements", player)
        modal_elements.import_textfield.text = export_string

        local textfield_handler = get_handler(import_dialog.gui_events.on_gui_text_changed, "import_string")
        textfield_handler(player, nil, {element=modal_elements.import_textfield, text=export_string})

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
    return {"09_settings"}
end

local function execute_action(player_index, action_name)
    local player = game.get_player(player_index)
    actions[action_name](player)
end

remote.add_interface("screenshotter_input", {
    initial_setup = initial_setup,
    execute_action = execute_action
})
