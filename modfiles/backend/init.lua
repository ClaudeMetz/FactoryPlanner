local District = require("backend.data.District")

local loader = require("backend.handlers.loader")
local migrator = require("backend.handlers.migrator")
require("backend.handlers.prototyper")
--require("backend.handlers.screenshotter")

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
---@field utility_scopes { components: "Subfactory" | "Floor" }
---@field recipe_filters { disabled: boolean, hidden: boolean }
---@field attach_subfactory_products boolean
---@field show_floor_items boolean
---@field fold_out_subfloors boolean
---@field ingredient_satisfaction boolean
---@field round_button_numbers boolean
---@field ignore_barreling_recipes boolean
---@field ignore_recycling_recipes boolean
---@field done_column boolean
---@field pollution_column boolean
---@field line_comment_column boolean
---@field mb_defaults MBDefaults
---@field default_prototypes DefaultPrototypes

---@class MBDefaults
---@field machine FPModulePrototype?
---@field machine_secondary FPModulePrototype?
---@field beacon FPBeaconPrototype?
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
    preferences.utility_scopes = preferences.utility_scopes or {components = "Subfactory"}
    preferences.recipe_filters = preferences.recipe_filters or {disabled = false, hidden = false}

    preferences.attach_subfactory_products = preferences.attach_subfactory_products or false
    preferences.show_floor_items = preferences.show_floor_items or false
    preferences.fold_out_subfloors = preferences.fold_out_subfloors or false
    preferences.ingredient_satisfaction = preferences.ingredient_satisfaction or false
    preferences.round_button_numbers = preferences.round_button_numbers or false
    preferences.ignore_barreling_recipes = preferences.ignore_barreling_recipes or false
    preferences.ignore_recycling_recipes = preferences.ignore_recycling_recipes or false

    preferences.done_column = preferences.done_column or false
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
---@field subfactory_list_rows integer
---@field default_timescale integer
---@field belts_or_lanes string
---@field prefer_product_picker boolean
---@field prefer_matrix_solver boolean

---@param player LuaPlayer
local function reload_settings(player)
    -- Writes the current user mod settings to their player_table, for read-performance
    local settings = settings.get_player_settings(player)
    local settings_table = {}

    local timescale_to_number = {one_second = 1, one_minute = 60, one_hour = 3600}

    settings_table.show_gui_button = settings["fp_display_gui_button"].value
    settings_table.products_per_row = tonumber(settings["fp_products_per_row"].value)
    settings_table.subfactory_list_rows = tonumber(settings["fp_subfactory_list_rows"].value)
    settings_table.default_timescale = timescale_to_number[settings["fp_default_timescale"].value]  ---@type integer
    settings_table.belts_or_lanes = settings["fp_view_belts_or_lanes"].value
    settings_table.prefer_product_picker = settings["fp_prefer_product_picker"].value
    settings_table.prefer_matrix_solver = settings["fp_prefer_matrix_solver"].value

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
---@field modal_dialog_type ModalDialogType?
---@field modal_data table?
---@field queued_dialog_metadata table?
---@field flags UIStateFlags

---@class UIStateFlags
---@field selection_mode boolean
---@field compact_view boolean
---@field recalculate_on_subfactory_change boolean

---@param player LuaPlayer
local function reset_ui_state(player)
    local ui_state_table = {}

    ui_state_table.main_dialog_dimensions = nil  ---@type DisplayResolution Can only be calculated after on_init
    ui_state_table.last_action = nil  ---@type string The last user action (used for rate limiting)
    ui_state_table.view_states = nil  ---@type ViewStates The state of the production views
    ui_state_table.messages = {}  ---@type PlayerMessage[]  The general message/warning list
    ui_state_table.main_elements = {}  -- References to UI elements in the main interface
    ui_state_table.compact_elements = {}  -- References to UI elements in the compact interface
    ui_state_table.last_selected_picker_group = nil  ---@type integer The item picker category that was last selected

    ui_state_table.modal_dialog_type = nil  ---@type ModalDialogType The internal modal dialog type
    ui_state_table.modal_data = nil  ---@type table? Data that can be set for a modal dialog to use
    ui_state_table.queued_dialog_metadata = nil  ---@type table? Info on dialog to open after the current one closes

    ui_state_table.flags = {  -- TODO do away with, make them just ui_state variables
        selection_mode = false,  -- Whether the player is currently using a selector
        compact_view = false,  -- Whether the user has switched to the compact main view
        recalculate_on_subfactory_change = false  -- Whether calculations should re-run
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
    util.messages.raise(player, "hint", {"fp.hint_tutorial"}, 12)

    if DEV_ACTIVE then util.porter.add_subfactories(player, DEV_EXPORT_STRING) end
end

---@param player LuaPlayer
local function refresh_player_table(player)
    local player_table = global.players[player.index]

    reload_preferences(player)
    reload_settings(player)
    reset_ui_state(player)

    util.context.validate(player)  -- TODO verify

    player_table.translation_tables = nil
    player_table.clipboard = nil

    -- Migrate the prototypes used in the player's preferences
    prototyper.defaults.migrate(player_table)
    prototyper.util.migrate_mb_defaults(player_table)

    player_table.district:validate()
end


---@return Factory?
local function import_tutorial_subfactory()
    local import_table, error = util.porter.process_export_string(TUTORIAL_EXPORT_STRING)
    if error then
        return nil
    else
        ---@cast import_table -nil
        return import_table.subfactories[1]
    end
end

local function global_init()
    -- Set up a new save for development if necessary
    local freeplay = remote.interfaces["freeplay"]
    if DEV_ACTIVE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    global.players = {}  ---@type { [PlayerIndex]: PlayerTable }
    global.current_ID = 0  -- Counter used for assigning incrementing IDs to all objects

    -- Save metadata about currently registered on_nth_tick events
    global.nth_tick_events = {}  ---@type { [Tick]: NthTickEvent }

    prototyper.build()  -- Generate all relevant prototypes and save them in global
    loader.run(true)  -- Run loader which creates useful indexes of prototype data

    -- Retain current modset to detect mod changes for subfactories that became invalid
    global.installed_mods = script.active_mods  ---@type ModToVersion
    -- Import the tutorial subfactory to validate and cache it
    global.tutorial_subfactory = import_tutorial_subfactory()

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
    global.tutorial_subfactory = import_tutorial_subfactory()

    translator.on_configuration_changed()
    prototyper.util.build_translation_dictionaries()

    for index, player in pairs(game.players) do
        util.gui.reset_player(player)  -- Destroys all existing GUI's
        util.gui.toggle_mod_gui(player)  -- Recreates the mod-GUI if necessary

        -- Update calculations in case prototypes changed in a relevant way
        local district = global.players[index].district  ---@type District
        for _, factory in district:iterator() do solver.update(player, factory) end
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
    -- TODO clear any on_ticks, maybe other stuff?
end)


script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting_type == "runtime-per-user" then  -- this mod only has per-user settings
        local player = game.get_player(event.player_index)  ---@cast player -nil
        reload_settings(player)

        if event.setting == "fp_display_gui_button" then
            util.gui.toggle_mod_gui(player)

        elseif event.setting == "fp_products_per_row"
                or event.setting == "fp_subfactory_list_rows"
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
