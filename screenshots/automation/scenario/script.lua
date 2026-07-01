---@diagnostic disable

local mod_gui = require("mod-gui")

-- This file contains functionality to rig the interface for various setups
-- that make for good screenshots.
-- This code is terrible and uses some functions completely inappropriately,
-- but it needs to do that to manipulate the interface because GUI events
-- can't be raised manually anymore.

local handler_requires = {"ui.base.compact_dialog", "ui.base.modal_dialog", "ui.main.title_bar",
    "ui.dialogs.picker_dialog", "ui.dialogs.porter_dialog"}
local handlers = {} -- Need to require these here since it can't be done inside an event
for _, path in pairs(handler_requires) do handlers[path] = require(path) end

local function get_handler(path, index, event, name)
    local gui_handlers = handlers[path][index].gui[event]
    for _, handler_table in pairs(gui_handlers) do
        if handler_table.name == name then return handler_table.handler end
    end
end

local function open_modal(player, dialog, modal_data)
    main_dialog.toggle(player)
    util.globals.main_elements(player).main_frame.location = player.display_resolution  -- hack city
    util.gui.open_dialog(player, {dialog=dialog, modal_data=modal_data, skip_dimmer=true})
end

local function modal_teardown(player, scene)
    local modal_frame = util.globals.modal_elements(player).modal_frame
    local dimensions = {actual_size=modal_frame.actual_size, location=modal_frame.location}
    storage.dimensions[scene] = dimensions
    util.gui.close_dialog(player, "cancel")
end


local function setup_player()
    local player = game.get_player(1)
    local player_table = util.globals.player_table(player)

    -- Factories
    local export_string = "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"
    util.porter.add_factories(player, export_string)

    local hotness = player_table.realm.first.first.next.next
    local trash = hotness.next.next
    trash.archived = true
    util.context.set(player, hotness)
    solver.update(player, hotness)
    util.gui.run_refresh(player, "all")

    -- Preferences
    player_table.preferences.display_gui_button = false
    player_table.preferences.products_per_row = 5
    player_table.preferences.factory_list_rows = 20
    player_table.preferences.compact_width_percentage = 22
    player_table.preferences.recipe_filters = {disabled = true, hidden = false}
    player_table.preferences.ignore_barreling_recipes = true
    player_table.preferences.ignore_recycling_recipes = true

    defaults.set(player, "belts", {prototype="fast-transport-belt"}, nil)
    defaults.set(player, "pumps", {prototype="pump", quality="epic"}, nil)

    -- Research
    player.force.technologies["advanced-oil-processing"].researched=true

    -- Player inventory
    player.insert{name="assembling-machine-3", count=9}
    player.insert{name="assembling-machine-2", count=1}
    player.insert{name="electric-mining-drill", count=29}
    player.insert{name="speed-module-3", count=14}
    player.insert{name="speed-module-2", count=1}
    player.insert{name="chemical-plant", count=6}
end

local scenes = {
    [1] = {
        setup = function(player)
            local translation_progress = mod_gui.get_frame_flow(player)["flib_translation_progress"]
            if translation_progress then translation_progress.visible = false end
            main_dialog.toggle(player)
        end,
        teardown = function(player)
            local main_frame = util.globals.main_elements(player).main_frame
            local dimensions = {actual_size=main_frame.actual_size, location=main_frame.location}
            storage.dimensions["01_main_interface"] = dimensions

            util.globals.preferences(player).factory_list_rows = 30
            main_dialog.rebuild(player, true)  -- avoid modal dialogs being squished
        end,
        name = "01_main_interface"
    },
    [2] = {
        setup = function(player)
            util.globals.main_elements(player).main_frame.location = player.display_resolution  -- hack city
            local toggle_handler = get_handler("ui.main.title_bar", 1, "on_gui_click", "switch_to_compact_view")
            toggle_handler(player, nil, nil)
        end,
        teardown = function(player)
            local compact_frame = util.globals.ui_state(player).compact_elements.compact_frame
            local dimensions = {actual_size=compact_frame.actual_size, location=compact_frame.location}
            storage.dimensions["02_compact_interface"] = dimensions

            local toggle_handler = get_handler("ui.base.compact_dialog", 2, "on_gui_click", "switch_to_main_view")
            toggle_handler(player, nil, nil)
        end,
        name = "02_compact_interface"
    },
    [3] = {
        setup = function(player)
            local modal_data = {item_id=nil, item_category="product"}
            open_modal(player, "picker", modal_data)

            local modal_elements = util.globals.modal_elements(player)
            modal_elements.search_textfield.text = "f"
            local search_handler = get_handler("ui.base.modal_dialog", 1, "on_gui_text_changed", "modal_searchfield")
            search_handler(player, nil, {text="f"})

            local group_handler = get_handler("ui.dialogs.picker_dialog", 1, "on_gui_click", "select_picker_item_group")
            group_handler(player, {group_id=3}, nil)

            modal_elements.item_choice_button.sprite = "item/raw-fish"
            modal_elements.belt_amount_textfield.text = "0.5"
            modal_elements.belt_choice_button.elem_value = "fast-transport-belt"
            local belt_handler = get_handler("ui.dialogs.picker_dialog", 1, "on_gui_elem_changed", "picker_choose_belt")
            belt_handler(player, nil, {element=modal_elements.belt_choice_button, elem_value="fast-transport-belt"})

            modal_elements.search_textfield.focus()
        end,
        teardown = (function(player) modal_teardown(player, "03_item_picker") end),
        name = "03_item_picker"
    },
    [4] = {
        setup = function(player)
            local product_proto = prototyper.util.find("items", "solid-fuel", "item")
            open_modal(player, "recipe", {category_id=product_proto.category_id,
                product_id=product_proto.id, production_type="produce"})
        end,
        teardown = (function(player) modal_teardown(player, "04_recipe_picker") end),
        name = "04_recipe_picker"
    },
    [5] = {
        setup = function(player)
            local floor = util.context.get(player, "Floor")
            open_modal(player, "machine", {machine_id=floor.first.next.machine.id})
        end,
        teardown = (function(player) modal_teardown(player, "05_machine") end),
        name = "05_machine"
    },
    [6] = {
        setup = function(player)
            open_modal(player, "import", nil)

            local export_string = "eNrtWt+P4jYQ/lfcPG+2hG2ra6Q+tJUqVepJp+Ohqu5Q5DiT3Wn9I7UdVIT43ztOzIK4RRDKHnBF4gHb4/HM941n7CSLRJmqmIF1aHSSJ9l9dv/tKLlL4J/GWF/QqAOf5Iuk5A5WAt+TQC2xpPboPqNfaHPhjZ03kmsNdq1qeZe4tuxHEVySf1gkmqug6wOqxx/Qg/oatQPrwU7Ze2O8I3UeFTjBJcl9N7pLtPFhbkIj76ypWtHZZMo/QZB4vqBV+kYhJHdB8lfSS9Kr5s9GShoOXpKsN01RS2Ns0PIbatinrZPZpU3CDGSSZ+vxXzrdy3XHZAXBnHqfAZgokOT1/P/i75rwpneKFKZOIGgBacPFX1P2B/AnNum7vtqNS8reUaAx03rmaCKwqIWtFX/UKfvx7xYtMM5qdE/MG1a2KCs2abCieLO90O8oZZhX8lLOmQaomDI0C2mccVrAKNJrUPsdbFBE03RvQmf0dId/pMChaiTWCFWSe9sCuThvwpSAS4CQK9PSUnn2hvy10HlQFaveRVJBTeRURTmnSbF7a1ZJYVVEk2ouHcQQiMT1y66oWnm0nJ4ypgiTrVgKWWCAuAWBTSf0X7AV3MNjiMI8EZbXHvVjsH2toojo9z2bMf++NyAwQpIzWKmsTLC9g5UUgRWgPX+krmxE0CsunqJz23aTWlClJBPSKJU+DDG6NrRWIVGhf16f8nMroYg5um+5Q4Nzhn6e9nP2W7I5aTNMv1kj9rZT9VIgxZFdoRS9EM8aQTV+XjgZakE+2l5hQt5u5Jq3EfJlCHwuQh371Oc4ssfJuimi4IaHb46E2TWUSg7Gt5PeXHZ8cmDHA4H9KUIRMvjBu9NylNe4FcevvxVfqLOD+Btt8Tc+dGMMIjCUvdR5vM6MeqMxYgNhfYsirVurecfDjcxrJfOFin3j86g6PL7COryOmelRF7XxJxe1QcHHqxmnQ3aVCrSiRX87aN8O2reD9tkP2n2BN5pK/Fk2Zv//VuFPU+GFaQjKVPDyc5f2a+Hx9Bs/O/nGz7ZiJXuVWHEeQKaNJNf2+hyeMJ+zFg+9hmwa/CXvd+cJ0bS0B1yzbxxe6pMS1Rji0aYdmftQKbkjCJ2RWJ2fSYU6pO/KopQDDb+Ue9kL2fvusCP4+Ngj+OlPig9HXwUHPT4gQU8cltzurdNPoND57r3dWQ4XnQGCd/VN+0HmXkaueXgVCvtNaJBwsUaAcyG/7gFnS/pMhAYrbPfOsnvRPdDiy7yLP1xOIrjku/j4mu/i08/+UYR7/ixhyr7sT0Kmy38BcOORig=="
            local modal_elements = util.globals.modal_elements(player)
            modal_elements.import_textfield.text = export_string

            local textfield_handler = get_handler("ui.dialogs.porter_dialog", 1, "on_gui_text_changed", "import_string")
            textfield_handler(player, nil, {element=modal_elements.import_textfield, text=export_string})

            local import_handler = get_handler("ui.dialogs.porter_dialog", 1, "on_gui_click", "import_factories")
            import_handler(player, nil, nil)

            local toggle = true
            for _, checkbox in pairs(modal_elements.factory_checkboxes) do
                checkbox.state = toggle
                toggle = not toggle
            end
            modal_elements.master_checkbox.state = false
        end,
        teardown = (function(player) modal_teardown(player, "06_import") end),
        name = "06_import"
    },
    [7] = {
        setup = function(player)
            open_modal(player, "utility", nil)
        end,
        teardown = (function(player) modal_teardown(player, "07_utility") end),
        name = "07_utility"
    },
    [8] = {
        setup = function(player)
            open_modal(player, "preferences", nil)
        end,
        teardown = (function(player) modal_teardown(player, "08_preferences") end),
        name = "08_preferences"
    }
}

local steps = {
    function(scene)
        scene.setup(game.get_player(1))
    end,
    function(scene)
        game.take_screenshot{path=(scene.name .. ".png"), show_gui=true, zoom=3}
    end,
    function(scene)
        scene.teardown(game.get_player(1))
    end
}

local function write_metadata_file()
    local frame_corners = {}

    for scene, dimensions in pairs(storage.dimensions) do
        local location, size = dimensions.location, dimensions.actual_size
        frame_corners[scene] = {
            top_left = {x = location.x, y = location.y},
            bottom_right = {x = location.x + size.width, y = location.y + size.height}
        }
    end

    local metadata = {frame_corners=frame_corners}
    helpers.write_file("metadata.json", helpers.table_to_json(metadata))
end


-- ** MAIN **
script.on_event(defines.events.on_game_created_from_scenario, function()
    game.autosave_enabled = false

    storage.scene = 1
    storage.step = 1

    storage.dimensions = {}
    storage.setup = false
end)

-- Runs through a series of steps, taking screenshots of various FP windows
-- Use nth_tick of 10 instead of on_tick to not shadow the main mod's on_tick
script.on_nth_tick(10, function(event)
    if storage.setup == false then
        setup_player()
        storage.setup = true
    end

    local scene, step = scenes[storage.scene], steps[storage.step]
    step(scene)  -- execute the current step
    storage.step = storage.step + 1

    if storage.step > 3 then
        storage.scene = storage.scene + 1
        storage.step = 1
    end

    if storage.scene > #scenes then  -- all done
        write_metadata_file()
        script.on_nth_tick(10, nil)
        print("screenshotter_done")  -- let script know to kill Factorio
    end
end)
