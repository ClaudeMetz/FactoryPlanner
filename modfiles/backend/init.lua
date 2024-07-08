local District = require("backend.data.District")

local loader = require("backend.handlers.loader")
local migrator = require("backend.handlers.migrator")
require("backend.handlers.prototyper")
require("backend.handlers.screenshotter")

require("backend.calculation.solver")


---@class PreferencesTable
---@field pause_on_interface boolean
---@field tutorial_mode boolean
---@field utility_scopes { components: "Factory" | "Floor" }
---@field recipe_filters { disabled: boolean, hidden: boolean }
---@field products_per_row integer
---@field factory_list_rows integer
---@field default_timescale Timescale
---@field show_gui_button boolean
---@field attach_factory_products boolean
---@field skip_factory_naming boolean
---@field prefer_matrix_solver boolean
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
---@field belts_or_lanes "belts" | "lanes"
---@field default_machines PrototypeWithCategoryDefault
---@field default_fuels PrototypeWithCategoryDefault
---@field default_belts PrototypeDefault
---@field default_wagons PrototypeWithCategoryDefault
---@field default_beacons PrototypeDefault

---@alias Timescale 1 | 60 | 3600

---@class MBDefaults
---@field machine FPModulePrototype?
---@field machine_secondary FPModulePrototype?
---@field beacon FPModulePrototype?
---@field beacon_count number?

---@param player_table PlayerTable
function reload_preferences(player_table)
    -- Reloads the user preferences, incorporating previous preferences if possible
    local player_preferences = player_table.preferences or {}
    local updated_prefs = {}

    local function reload(name, default)
        -- Needs to be longform-if because true is a valid default
        if player_preferences[name] == nil then
            updated_prefs[name] = default
        else
            updated_prefs[name] = player_preferences[name]
        end
    end

    reload("pause_on_interface", false)
    reload("tutorial_mode", true)
    reload("utility_scopes", {components = "Factory"})
    reload("recipe_filters", {disabled = false, hidden = false})

    reload("products_per_row", 7)
    reload("factory_list_rows", 24)
    reload("default_timescale", 60)

    reload("show_gui_button", true)
    reload("attach_factory_products", false)
    reload("skip_factory_naming", false)
    reload("prefer_matrix_solver", false)
    reload("show_floor_items", false)
    reload("fold_out_subfloors", false)
    reload("ingredient_satisfaction", false)
    reload("round_button_numbers", false)
    reload("ignore_barreling_recipes", true)
    reload("ignore_recycling_recipes", true)

    reload("done_column", true)
    reload("percentage_column", false)
    reload("pollution_column", false)
    reload("line_comment_column", false)

    reload("mb_defaults", {machine = nil, machine_secondary = nil, beacon = nil, beacon_count = nil})

    reload("belts_or_lanes", "belts")

    reload("default_machines", prototyper.defaults.get_fallback("machines"))
    reload("default_fuels", prototyper.defaults.get_fallback("fuels"))
    reload("default_belts", prototyper.defaults.get_fallback("belts"))
    reload("default_wagons", prototyper.defaults.get_fallback("wagons"))
    reload("default_beacons", prototyper.defaults.get_fallback("beacons"))

    -- Default to coal if it exists, since any other default is silly
    local coal_fuel = prototyper.util.find_prototype("fuels", "coal", "chemical")
    if coal_fuel then updated_prefs.default_fuels[coal_fuel.category_id] = coal_fuel end

    player_table.preferences = updated_prefs
end


---@class UIStateTable
---@field main_dialog_dimensions DisplayResolution?
---@field last_action string?
---@field view_states ViewStates?
---@field messages PlayerMessage[]
---@field main_elements table
---@field compact_elements table
---@field last_selected_picker_group integer?
---@field tooltips table
---@field modal_dialog_type ModalDialogType?
---@field modal_data table?
---@field selection_mode boolean
---@field compact_view boolean
---@field recalculate_on_factory_change boolean

---@param player_table PlayerTable
local function reset_ui_state(player_table)
    -- The UI table gets replaced because the whole interface is reset
    player_table.ui_state = {
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

        selection_mode = false,
        compact_view = false,
        recalculate_on_factory_change = false
    }
end


---@class PlayerTable
---@field preferences PreferencesTable
---@field ui_state UIStateTable
---@field district District
---@field context ContextTable
---@field translation_tables { [string]: TranslatedDictionary }?
---@field clipboard ClipboardEntry?

---@param player LuaPlayer
local function player_init(player)
    global.players[player.index] = {}  --[[@as table]]
    local player_table = global.players[player.index]

    player_table.district = District.init()
    util.context.init(player)

    reload_preferences(player_table)
    reset_ui_state(player_table)

    util.gui.toggle_mod_gui(player)
    util.messages.raise(player, "hint", {"fp.hint_tutorial"}, 6)

    if DEV_ACTIVE then util.porter.add_factories(player, DEV_EXPORT_STRING) end
end

---@param player LuaPlayer
local function refresh_player_table(player)
    local player_table = global.players[player.index]

    reload_preferences(player_table)
    reset_ui_state(player_table)

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
