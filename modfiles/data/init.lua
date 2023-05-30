require("data.classes.Collection")
require("data.classes.Factory")
require("data.classes.Subfactory")
require("data.classes.Floor")
require("data.classes.Line")
require("data.classes.Recipe")
require("data.classes.Machine")
require("data.classes.Beacon")
require("data.classes.ModuleSet")
require("data.classes.Module")
require("data.classes.Item")
require("data.classes.Fuel")

local loader = require("data.handlers.loader")
local migrator = require("data.handlers.migrator")
require("data.handlers.prototyper")
require("data.handlers.screenshotter")

require("data.calculation.solver")

---@class PlayerTable
---@field preferences PreferencesTable
---@field settings SettingsTable
---@field ui_state UIStateTable
---@field mod_version VersionString
---@field index PlayerIndex
---@field factory FPFactory
---@field archive FPFactory
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
---@field machine FPModulePrototype
---@field machine_secondary FPModulePrototype
---@field beacon FPBeaconPrototype
---@field beacon_count number

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
---@field messages PlayerMessages
---@field main_elements { [string]: LuaGuiElement }
---@field compact_elements { [string]: LuaGuiElement }
---@field context Context
---@field last_selected_picker_group integer?
---@field modal_dialog_type ModalDialogType?
---@field modal_data ModalData?
---@field queued_dialog_metadata ModalData?
---@field flags UIStateFlags

---@class UIStateFlags
---@field archive_open boolean
---@field selection_mode boolean
---@field compact_view boolean
---@field recalculate_on_subfactory_change boolean

---@param player LuaPlayer
local function reset_ui_state(player)
    local ui_state_table = {}

    ui_state_table.main_dialog_dimensions = nil  ---@type DisplayResolution Can only be calculated after on_init
    ui_state_table.last_action = nil  ---@type string The last user action (used for rate limiting)
    ui_state_table.view_states = nil  ---@type ViewStates The state of the production views
    ui_state_table.messages = {}  ---@type PlayerMessages  The general message/warning list
    ui_state_table.main_elements = {}  -- References to UI elements in the main interface
    ui_state_table.compact_elements = {}  -- References to UI elements in the compact interface
    ui_state_table.context = util.context.create(player)  -- The currently displayed set of data
    ui_state_table.last_selected_picker_group = nil  ---@type integer The item picker category that was last selected

    ui_state_table.modal_dialog_type = nil  ---@type ModalDialogType The internal modal dialog type
    ui_state_table.modal_data = nil  ---@type ModalData Data that can be set for a modal dialog to use
    ui_state_table.queued_dialog_metadata = nil  ---@type ModalData Info on dialog to open after the current one closes

    ui_state_table.flags = {
        archive_open = false,  -- Wether the players subfactory archive is currently open
        selection_mode = false,  -- Whether the player is currently using a selector
        compact_view = false,  -- Whether the user has switched to the compact main view
        recalculate_on_subfactory_change = false  -- Whether calculations should re-run
    }

    -- The UI table gets replaced because the whole interface is reset
    global.players[player.index].ui_state = ui_state_table
end


---@param player LuaPlayer
local function create_player_table(player)
    global.players[player.index] = {}
    local player_table = global.players[player.index]

    player_table.mod_version = global.mod_version
    player_table.index = player.index

    player_table.factory = Factory.init()
    player_table.archive = Factory.init()

    player_table.preferences = {}
    reload_preferences(player)

    reload_settings(player)
    reset_ui_state(player)

    ui_util.messages.raise(player, "hint", {"fp.hint_tutorial"}, 12)
end

---@param player LuaPlayer
local function refresh_player_table(player)
    local player_table = global.players[player.index]

    reload_preferences(player)
    reload_settings(player)
    reset_ui_state(player)

    -- This whole reset thing will be moved ...
    local archive_subfactories = Factory.get_in_order(player_table.archive, "Subfactory")
    player_table.archive.selected_subfactory = archive_subfactories[1]  -- can be nil

    local factory = player_table.factory
    local subfactories = Factory.get_in_order(factory, "Subfactory")
    local subfactory_to_select = subfactories[1]  -- can be nil
    if factory.selected_subfactory ~= nil then
        -- Get the selected subfactory from the factory to make sure it still exists
        local selected_subfactory = Factory.get(factory, "Subfactory", factory.selected_subfactory.id)
        if selected_subfactory ~= nil then subfactory_to_select = selected_subfactory end
    end
    util.context.set_subfactory(player, subfactory_to_select)

    player_table.translation_tables = nil
    player_table.clipboard = nil
end


local function global_init()
    -- Set up a new save for development if necessary
    local freeplay = remote.interfaces["freeplay"]
    if DEV_ACTIVE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    -- Initiates all factorio-global variables
    global.mod_version = script.active_mods["factoryplanner"]  ---@type VersionString
    global.players = {}  ---@type { [PlayerIndex]: PlayerTable }

    -- Save metadata about currently registered on_nth_tick events
    global.nth_tick_events = {}  ---@type { [Tick]: NthTickEvent }

    prototyper.build()  -- Generate all relevant prototypes and save them in global
    loader.run(true)  -- Run loader which creates useful caches of prototype data

    -- Retain current modset to detect mod changes for subfactories that became invalid
    global.installed_mods = script.active_mods  ---@type ModToVersion
    -- Import the tutorial subfactory so it's 'cached'
    global.tutorial_subfactory = data_util.import_tutorial_subfactory()

    -- Initialize flib's translation module
    translator.on_init()
    prototyper.util.build_translation_dictionaries()

    -- Create player tables for all existing players
    for _, player in pairs(game.players) do create_player_table(player) end
end

-- Prompts migrations, a GUI and prototype reload, and a validity check on all subfactories
local function handle_configuration_change()
    prototyper.build()  -- Run prototyper
    loader.run(true)  -- Re-run the loader to update with the new prototypes

    migrator.migrate_global()  -- Migrate global

    -- Runs through all players, even new ones without player_table
    for _, player in pairs(game.players) do
        -- Migrate player_table data if it exists
        migrator.migrate_player_table(player)

        -- Create or update player_table
        refresh_player_table(player)
        local player_table = global.players[player.index]

        -- Migrate the player's default prototype choices
        prototyper.defaults.migrate(player_table)

        -- Update the validity of the entire factory and archive
        Factory.validate(player_table.factory)
        Factory.validate(player_table.archive)
    end

    global.installed_mods = script.active_mods
    global.tutorial_subfactory = data_util.import_tutorial_subfactory()

    translator.on_configuration_changed()
    prototyper.util.build_translation_dictionaries()

    for index, player in pairs(game.players) do
        ui_util.reset_player_gui(player)  -- Destroys all existing GUI's
        ui_util.toggle_mod_gui(player)  -- Recreates the mod-GUI if necessary

        -- Update factory and archive calculations in case prototypes changed in a relevant way
        local player_table = global.players[index]  ---@type PlayerTable
        Factory.update_calculations(player_table.factory, player)
        Factory.update_calculations(player_table.archive, player)
    end
end


-- ** TOP LEVEL **
script.on_init(global_init)

script.on_configuration_changed(handle_configuration_change)

script.on_load(loader.run)


-- ** PLAYER DATA **
script.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)  ---@cast player -nil

    -- Sets up the player_table for the new player
    create_player_table(player)

    -- Sets up the mod-GUI for the new player if necessary
    ui_util.toggle_mod_gui(player)

    -- Add the subfactories that are handy for development
    if DEV_ACTIVE then data_util.add_subfactories_by_string(player, DEV_EXPORT_STRING) end
end)

script.on_event(defines.events.on_player_removed, function(event)
    global.players[event.player_index] = nil
end)


script.on_event(defines.events.on_player_joined_game, translator.on_player_joined_game)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
    if event.setting_type == "runtime-per-user" then  -- this mod only has per-user settings
        local player = game.get_player(event.player_index)  ---@cast player -nil
        reload_settings(player)

        if event.setting == "fp_display_gui_button" then
            ui_util.toggle_mod_gui(player)

        elseif event.setting == "fp_products_per_row"
                or event.setting == "fp_subfactory_list_rows"
                or event.setting == "fp_prefer_product_picker" then
            main_dialog.rebuild(player, false)

        elseif event.setting == "fp_view_belts_or_lanes" then
            local player_table = data_util.player_table(player)

            -- Goes through every subfactory's top level products and updates their defined_by
            local defined_by = player_table.settings.belts_or_lanes
            Factory.update_product_definitions(player_table.factory, defined_by)
            Factory.update_product_definitions(player_table.archive, defined_by)
            local subfactory = player_table.ui_state.context.subfactory

            solver.update(player, subfactory)
            main_dialog.rebuild(player, false)
        end
    end
end)


-- ** TRANSLATION **
-- Required by flib's translation module
script.on_event(defines.events.on_tick, translator.on_tick)

-- Keep translation going
script.on_event(defines.events.on_string_translated, translator.on_string_translated)

---@param event GuiEvent
local function dictionaries_ready(event)
    local player = game.get_player(event.player_index)  ---@cast player -nil
    local player_table = data_util.player_table(player)

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
