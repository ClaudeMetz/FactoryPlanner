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
    lib.globals.main_elements(player).main_frame.location = player.display_resolution  -- hack city
    lib.gui.open_dialog(player, {dialog=dialog, modal_data=modal_data, skip_dimmer=true})
end

local function modal_teardown(player, scene)
    local modal_frame = lib.globals.modal_elements(player).modal_frame
    local dimensions = {actual_size=modal_frame.actual_size, location=modal_frame.location}
    storage.dimensions[scene] = dimensions
    lib.gui.close_dialog(player, "cancel")
end


local function setup_player()
    local player = game.get_player(1)
    local player_table = lib.globals.player_table(player)

    -- Factories
    local export_string = "eNrtWUtvGjEQ/iupz2waSKVKSLn00FMqVUkvFUIrr3cWRvVjY3tREOW/d7xeEpeHGtS0CMINZsbz+sbj8XrB4LE21ufKlA48Gy5YwR2wIRtc9i/7H1mPgYQZ91BmlqN0Kafiwhs7ryXXGuyKc00cC2Iu5DMtSD80XKKfpyRXcwEZnyT2liu1CGRrtGBCchesfo7GaJXmKiwYoZrcoAf1vmgs2c9QO7Ae7Pjizhjvgn4jZ60TDh4a0B65JKri3uJjXlmAPKwn7QsyW8gGaova5474etKRtfHBE0YLa2vKRnicURh5YTRGiY7cyXtT55U0xoZcPjnfEnqMUgmSDfv0CzW0K5bL3ouCXBk3OnMCQVPiKHs/xhffgU8v7iPp3QGCTjD6dvs1kuM6b0IOukh2+E+SgqprEqIesuAZUUruee7nNXSkFktUtcQKoWRDbxsgH0qoKItlXoSlXJlG+7b2Hhq0RO4ow8FyvC8so50yg20yt0SJVY/B52fGXaTsk4009qhwR/TPKlbikRLMUc5qsNw3tisy0mvIx2HFpYMe4wFQiKpIE1hBhdLuw/7VVSgWMQ0hJZF86UiboRAfVEFJmWTdumzwO6rC8soTfy26TnpHeF27yNfNaWNVW9GpqiiMu3RVhgLMJSr0q5ip3zUS8q7nPUXZUu8h1FGUWO1RJoxSEMqJsXTH7g99aKNnnE8fZ7Rhc3s87+q3gHZ6TGbRyGnD/pPmQuGtUXyigarcnesg+BqzgiKraCjlAs57/ygwH/8d6ryccZrhykygFQ36E0H9+rS3/mid/7K+vp6WVGQ9E52pf56I1V3nA1VyuNYBF0anCfgUKZsBFitGai0S/6ffrw6cq4H243bEWt6hoRpEqF755KELujixLnQeQPYpA2FqQiATvDhPoG+yAJwHkFktKWHHiP+WATrt3ArkEQ+eJzhxDM4Tx1udOJynJpAV9kg/ccVGeTRtpmrC+0PyMBH+bzv/W1vpeTkFhWLDg6Bvq/XlQb+aqtpQXdmsLa6jPsAU6jDFlBblGiIFd8R3RmJ5wgcZVBW2b1vJB9EkCc/sQ/fF682+OP7TsyxV1I2rsQQb7ly9zq0bCRPQJbfz8Uk8P3vL3fRoIhkvfwHLQGzQ"
    lib.porter.add_factories(player, export_string)

    local hotness = player_table.realm.first.first.next
    local trash = hotness.next.next
    trash.archived = true
    lib.context.set(player, hotness)
    solver.update(player, hotness)
    lib.gui.run_refresh(player, "all")

    -- Preferences
    player_table.preferences.show_gui_button = false
    lib.gui.toggle_mod_gui(player)
    player_table.preferences.products_per_row = 5
    player_table.preferences.factory_list_rows = 20
    player_table.preferences.compact_width_percentage = 22
    player_table.preferences.recipe_filters = {disabled = true, hidden = false}
    player_table.preferences.ignore_barreling_recipes = true
    player_table.preferences.ignore_recycling_recipes = true

    defaults.set(player, "belts", {prototype="fast-transport-belt"}, nil)
    defaults.set(player, "pumps", {prototype="pump", quality="normal"}, nil)

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
            local main_frame = lib.globals.main_elements(player).main_frame
            local dimensions = {actual_size=main_frame.actual_size, location=main_frame.location}
            storage.dimensions["01_main_interface"] = dimensions

            lib.globals.preferences(player).factory_list_rows = 30
            main_dialog.rebuild(player, true)  -- avoid modal dialogs being squished
        end,
        name = "01_main_interface"
    },
    [2] = {
        setup = function(player)
            lib.globals.main_elements(player).main_frame.location = player.display_resolution  -- hack city
            local toggle_handler = get_handler("ui.main.title_bar", 1, "on_gui_click", "switch_to_compact_view")
            toggle_handler(player, nil, nil)
        end,
        teardown = function(player)
            local compact_frame = lib.globals.ui_state(player).compact_elements.compact_frame
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

            local modal_elements = lib.globals.modal_elements(player)
            modal_elements.search_textfield.text = "f"
            local search_handler = get_handler("ui.base.modal_dialog", 1, "on_gui_text_changed", "modal_searchfield")
            search_handler(player, nil, {text="f"})

            local group_handler = get_handler("ui.dialogs.picker_dialog", 1, "on_gui_click", "select_picker_item_group")
            group_handler(player, {group_id=3}, nil)

            local item_proto = prototyper.util.find("items", "raw-fish", "item")
            local item_handler = get_handler("ui.dialogs.picker_dialog", 1, "on_gui_click", "select_picker_item")
            item_handler(player, {item_id=item_proto.id, category_id=item_proto.category_id, enabled=true}, nil)
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
            local floor = lib.context.get(player, "Floor")
            open_modal(player, "machine", {machine_id=floor.first.next.machine.id})
        end,
        teardown = (function(player) modal_teardown(player, "05_machine") end),
        name = "05_machine"
    },
    [6] = {
        setup = function(player)
            open_modal(player, "import", nil)

            local export_string = "eNrdlMGOmzAQhl/F9SkrhSyEJQSkniqtethDW/W2QsiBgVo1NrFNdlHKO/UZ+mQdA9kmVaWeWqXlYFnfeGb+mTE+UnhulbZ5o0oDlqZHumMGaErXq2AVxHRJQcCBWSg9zbgw55aKFVbpvhVMStAnS4gWDUVfiB/Mnd53THDbnyPTsgI8Vp/lG05hOWCuxyMtBDMu6/2UDL0ka5zDI2/q19xCcytUzY3lhWcKDhIjYtjPGXmYMZkxcdhlVeIwSjOw70BazgTShlnNn/NKA+QuKuY8opid6KDVXNrcoF3WM5bKOn0UHVutyq6w/IDF5Tsl+XRixpdFfHx4N+HJzyrX8LmeX1aB5wpsfu0qT6nThaRkluW2b2FGxhXFm1bwikNJU6s7QAUlVFxCme+cK2tUJ+04mn3HNeKZpMGQLalVbV4JpbQT9NLyESwpXgAQeBB3GHDswDAsfzeaSnS8vBXswHAUuJJFEPn+t69vbsjirbKvbq54FCj3i1N72f6xon+m/+OvodmTV3HzKSMf2BNxO7K4x7W/5vafRP+Fy++v/GBz+UXBdhNuktD375IkToJ1nNyFURDFcRxt423ib9bRnxzZ/E56+CJ3ArwwI+8nQiZCwuud3M/a/7cJZsN3LbhpuA=="
            local modal_elements = lib.globals.modal_elements(player)
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
