local District = require("backend.data.District")

local loader = require("backend.handlers.loader")
local migrator = require("backend.handlers.migrator")
require("backend.handlers.prototyper")
require("backend.handlers.screenshotter")

require("backend.calculation.solver")

---@class PlayerTable
---@field preferences PreferencesTable
---@field settings SettingsTable
---@field ui_state UIStateTable
---@field district District
---@field context ContextTable
---@field translation_tables { [string]: TranslatedDictionary }?
---@field clipboard ClipboardEntry?

---@class PreferencesTable
---@field pause_on_interface boolean
---@field tutorial_mode boolean
---@field utility_scopes { components: "Factory" | "Floor" }
---@field recipe_filters { disabled: boolean, hidden: boolean }
---@field attach_factory_products boolean
---@field show_floor_items boolean
---@field fold_out_subfloors boolean
---@field ingredient_satisfaction boolean
---@field round_button_numbers boolean
---@field ignore_barreling_recipes boolean
---@field ignore_recycling_recipes boolean
---@field done_column boolean
---@field percentage_column boolean
---@field pollution_column boolean
---@field line_comment_column boolean
---@field mb_defaults MBDefaults
---@field default_prototypes DefaultPrototypes

---@class MBDefaults
---@field machine FPModulePrototype?
---@field machine_secondary FPModulePrototype?
---@field beacon FPModulePrototype?
---@field beacon_count number?

---@class DefaultPrototypes
---@field machines PrototypeWithCategoryDefault
---@field fuels PrototypeWithCategoryDefault
---@field belts PrototypeDefault
---@field wagons PrototypeWithCategoryDefault
---@field beacons PrototypeDefault


-- ** LOCAL UTIL **
---@param player LuaPlayer
local function reload_preferences(player)
    -- Reloads the user preferences, incorporating previous preferences if possible
    local preferences = global.players[player.index].preferences

    preferences.pause_on_interface = preferences.pause_on_interface or false
    if preferences.tutorial_mode == nil then preferences.tutorial_mode = true end
    preferences.utility_scopes = preferences.utility_scopes or {components = "Factory"}
    preferences.recipe_filters = preferences.recipe_filters or {disabled = false, hidden = false}

    preferences.attach_factory_products = preferences.attach_factory_products or false
    preferences.show_floor_items = preferences.show_floor_items or false
    preferences.fold_out_subfloors = preferences.fold_out_subfloors or false
    preferences.ingredient_satisfaction = preferences.ingredient_satisfaction or false
    preferences.round_button_numbers = preferences.round_button_numbers or false
    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.ignore_recycling_recipes = preferences.ignore_recycling_recipes or false

    if preferences.done_column == nil then preferences.done_column = true end
    if preferences.percentage_column == nil then preferences.percentage_column = true end
    preferences.pollution_column = preferences.pollution_column or false
    preferences.line_comment_column = preferences.line_comment_column or false

    preferences.mb_defaults = preferences.mb_defaults
        or {machine = nil, machine_secondary = nil, beacon = nil, beacon_count = nil}

    preferences.default_prototypes = preferences.default_prototypes or {}
    preferences.default_prototypes = {
        machines = preferences.default_prototypes.machines or prototyper.defaults.get_fallback("machines"),
        fuels = preferences.default_prototypes.fuels or prototyper.defaults.get_fallback("fuels"),
        belts = preferences.default_prototypes.belts or prototyper.defaults.get_fallback("belts"),
        wagons = preferences.default_prototypes.wagons or prototyper.defaults.get_fallback("wagons"),
        beacons = preferences.default_prototypes.beacons or prototyper.defaults.get_fallback("beacons")
    }
end

---@class SettingsTable
---@field show_gui_button boolean
---@field products_per_row integer
---@field factory_list_rows integer
---@field default_timescale integer
---@field belts_or_lanes string
---@field prefer_product_picker boolean
---@field prefer_matrix_solver boolean

---@param player LuaPlayer
local function reload_settings(player)
    -- Writes the current user mod settings to their player_table, for read-performance
    local settings = settings.get_player_settings(player)
    local timescale_to_number = {one_second = 1, one_minute = 60, one_hour = 3600}

    local settings_table = {  ---@type SettingsTable
        show_gui_button = settings["fp_display_gui_button"].value,
        products_per_row = tonumber(settings["fp_products_per_row"].value),
        factory_list_rows = tonumber(settings["fp_factory_list_rows"].value),
        default_timescale = timescale_to_number[settings["fp_default_timescale"].value],
        belts_or_lanes = settings["fp_view_belts_or_lanes"].value,
        prefer_product_picker = settings["fp_prefer_product_picker"].value,
        prefer_matrix_solver = settings["fp_prefer_matrix_solver"].value
    }

    global.players[player.index].settings = settings_table
end

---@class UIStateTable
---@field main_dialog_dimensions DisplayResolution
---@field last_action string
---@field view_states ViewStates
---@field messages PlayerMessage[]
---@field main_elements table
---@field compact_elements table
---@field last_selected_picker_group integer?
---@field tooltips table
---@field modal_dialog_type ModalDialogType?
---@field modal_data table?
---@field queued_dialog_metadata table?
---@field selection_mode boolean
---@field compact_view boolean
---@field recalculate_on_factory_change boolean

---@param player LuaPlayer
local function reset_ui_state(player)
    local ui_state_table = {  ---@type UIStateTable
        main_dialog_dimensions = nil,
        last_action = nil,
        view_states = nil,
        messages = {},
        main_elements = {},
        compact_elements = {},
        last_selected_picker_group = nil,
        tooltips = {},

        modal_dialog_type = nil,
        modal_data = nil,
        queued_dialog_metadata = nil,

        selection_mode = false,
        compact_view = false,
        recalculate_on_factory_change = false
    }

    -- The UI table gets replaced because the whole interface is reset
    global.players[player.index].ui_state = ui_state_table
end


---@param player LuaPlayer
local function player_init(player)
    global.players[player.index] = {}
    local player_table = global.players[player.index]

    player_table.district = District.init()
    util.context.init(player)

    player_table.preferences = {}
    reload_preferences(player)

    reload_settings(player)
    reset_ui_state(player)

    util.gui.toggle_mod_gui(player)
    util.messages.raise(player, "hint", {"fp.hint_tutorial"}, 6)

    if DEV_ACTIVE then util.porter.add_factories(player, DEV_EXPORT_STRING) end
end

---@param player LuaPlayer
local function refresh_player_table(player)
    local player_table = global.players[player.index]

    reload_preferences(player)
    reload_settings(player)
    reset_ui_state(player)

    util.context.validate(player)

    player_table.translation_tables = nil
    player_table.clipboard = nil

    -- Migrate the prototypes used in the player's preferences
    prototyper.defaults.migrate(player_table)
    prototyper.util.migrate_mb_defaults(player_table)

    player_table.district:validate()
end


---@return Factory?
local function import_tutorial_factory()
    local import_table, error = util.porter.process_export_string(TUTORIAL_EXPORT_STRING)
    if error then return nil end

    ---@cast import_table -nil
    local factory = import_table.factories[1]
    if not factory.valid then return nil end

    return factory  -- can still not be admissible if any lines don't produce anything
end

local function global_init()
    -- Set up a new save for development if necessary
    local freeplay = remote.interfaces["freeplay"]
    if DEV_ACTIVE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    global.players = {}  ---@type { [PlayerIndex]: PlayerTable }
    global.next_object_ID = 1  -- Counter used for assigning incrementing IDs to all objects

    -- Save metadata about currently registered on_nth_tick events
    global.nth_tick_events = {}  ---@type { [Tick]: NthTickEvent }

    prototyper.build()  -- Generate all relevant prototypes and save them in global
    loader.run(true)  -- Run loader which creates useful indexes of prototype data

    -- Retain current modset to detect mod changes for factories that became invalid
    global.installed_mods = script.active_mods  ---@type ModToVersion
    -- Import the tutorial factory to validate and cache it
    global.tutorial_factory = import_tutorial_factory()

    -- Initialize flib's translation module
    translator.on_init()
    prototyper.util.build_translation_dictionaries()

    for _, player in pairs(game.players) do player_init(player) end
end

-- Prompts migrations, a GUI and prototype reload, and a validity check on all factories
local function handle_configuration_change()
    local migrations = migrator.determine_migrations()

    if not migrations then  -- implies this save can't be migrated anymore
        for _, player in pairs(game.players) do util.gui.reset_player(player) end
        global = {}; global_init()
        game.print{"fp.mod_reset"};
        return
    end

    prototyper.build()
    loader.run(true)

    migrator.migrate_global(migrations)
    for _, player in pairs(game.players) do
        migrator.migrate_player_table(player, migrations)
        refresh_player_table(player)
    end

    global.installed_mods = script.active_mods
    global.tutorial_factory = import_tutorial_factory()

    translator.on_configuration_changed()
    prototyper.util.build_translation_dictionaries()

    for index, player in pairs(game.players) do
        util.gui.reset_player(player)  -- Destroys all existing GUI's
        util.gui.toggle_mod_gui(player)  -- Recreates the mod-GUI if necessary

        -- Update calculations in case prototypes changed in a relevant way
        local district = global.players[index].district  ---@type District
        for factory in district:iterator() do solver.update(player, factory) end
    end
end


-- ** TOP LEVEL **
script.on_init(global_init)

script.on_configuration_changed(handle_configuration_change)

script.on_load(loader.run)


-- ** PLAYER DATA **
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)  ---@cast player -nil
    player_init(player)
end)

script.on_event(defines.events.on_player_removed, function(event)
    global.players[event.player_index] = nil
end)


script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting_type == "runtime-per-user" then  -- this mod only has per-user settings
        local player = game.get_player(event.player_index)  ---@cast player -nil
        reload_settings(player)

        if event.setting == "fp_display_gui_button" then
            util.gui.toggle_mod_gui(player)

        elseif event.setting == "fp_products_per_row"
                or event.setting == "fp_factory_list_rows"
                or event.setting == "fp_prefer_product_picker" then
            main_dialog.rebuild(player, false)

        elseif event.setting == "fp_view_belts_or_lanes" then
            local player_table = util.globals.player_table(player)

            -- Goes through every factory's top level products and updates their defined_by
            local defined_by = player_table.settings.belts_or_lanes
            for _, factory in player_table.district:iterator() do
                factory:update_product_definitions(defined_by)
            end

            local factory = util.context.get(player, "Factory")
            solver.update(player, factory)
            main_dialog.rebuild(player, false)
        end
    end
end)


-- ** TRANSLATION **
-- Required by flib's translation module
script.on_event(defines.events.on_tick, translator.on_tick)
script.on_event(defines.events.on_player_joined_game, translator.on_player_joined_game)
script.on_event(defines.events.on_string_translated, translator.on_string_translated)

---@param event GuiEvent
local function dictionaries_ready(event)
    local player = game.get_player(event.player_index)  ---@cast player -nil
    local player_table = util.globals.player_table(player)

    player_table.translation_tables = translator.get_all(event.player_index)
    modal_dialog.set_searchfield_state(player)  -- enables searchfields if possible
end

-- Save translations once they are complete
script.on_event(translator.on_player_dictionaries_ready, dictionaries_ready)


-- ** COMMANDS **
commands.add_command("fp-reset-prototypes", {"command-help.fp_reset_prototypes"}, handle_configuration_change)
commands.add_command("fp-restart-translation", {"command-help.fp_restart_translation"}, function()
    translator.on_init()
    prototyper.util.build_translation_dictionaries()
end)
commands.add_command("fp-shrinkwrap-interface", {"command-help.fp_shrinkwrap_interface"}, function(command)
    if command.player_index then main_dialog.shrinkwrap_interface(game.get_player(command.player_index)) end
end)
