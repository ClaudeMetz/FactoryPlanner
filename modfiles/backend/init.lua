local Realm = require("backend.data.Realm")

local loader = require("backend.handlers.loader")
local migrator = require("backend.handlers.migrator")
require("backend.handlers.prototyper")
require("backend.handlers.defaults")
require("backend.handlers.screenshotter")

require("backend.calculation.solver")


---@class PreferencesTable
---@field timescale Timescale
---@field pause_on_interface boolean
---@field utility_scopes { components: "Factory" | "Floor" }
---@field recipe_filters { disabled: boolean, hidden: boolean }
---@field products_per_row integer
---@field factory_list_rows integer
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
---@field line_comment_column boolean
---@field item_views ItemViewPreference[]
---@field belts_or_lanes "belts" | "lanes"
---@field default_machines PrototypeDefaultWithCategory
---@field default_fuels PrototypeDefaultWithCategory
---@field default_beacons DefaultPrototype
---@field default_belts DefaultPrototype
---@field default_wagons PrototypeDefaultWithCategory

---@alias Timescale 1 | 60

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

    reload("timescale", 60)
    reload("pause_on_interface", false)
    reload("utility_scopes", {components = "Factory"})
    reload("recipe_filters", {disabled = false, hidden = false})

    reload("products_per_row", 6)
    reload("factory_list_rows", 28)

    reload("show_gui_button", false)
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
    reload("line_comment_column", false)

    reload("item_views", item_views.default_preferences())

    reload("belts_or_lanes", "belts")

    reload("default_machines", defaults.get_fallback("machines"))
    reload("default_fuels", defaults.get_fallback("fuels"))
    reload("default_beacons", defaults.get_fallback("beacons"))
    reload("default_belts", defaults.get_fallback("belts"))
    reload("default_wagons", defaults.get_fallback("wagons"))

    player_table.preferences = updated_prefs
end


---@class UIStateTable
---@field main_dialog_dimensions DisplayResolution?
---@field last_action LastAction?
---@field views_data ItemViewsData?
---@field messages PlayerMessage[]
---@field main_elements table
---@field compact_elements table
---@field calculator_elements table
---@field last_selected_picker_group integer?
---@field tooltips table
---@field modal_dialog_type ModalDialogType?
---@field modal_data table?
---@field selection_mode boolean
---@field compact_view boolean
---@field districts_view boolean
---@field recalculate_on_factory_change boolean

---@class LastAction
---@field action_name string
---@field tick Tick

---@param player_table PlayerTable
local function reset_ui_state(player_table)
    -- The UI table gets replaced because the whole interface is reset
    player_table.ui_state = {
        main_dialog_dimensions = nil,
        last_action = nil,
        views_data = nil,
        messages = {},
        main_elements = {},
        compact_elements = {},
        calculator_elements = {},
        last_selected_picker_group = nil,
        tooltips = {},

        modal_dialog_type = nil,
        modal_data = nil,

        selection_mode = false,
        compact_view = false,
        districts_view = false,
        recalculate_on_factory_change = false
    }
end


---@class PlayerTable
---@field preferences PreferencesTable
---@field ui_state UIStateTable
---@field realm Realm
---@field context ContextTable
---@field translation_tables { [string]: TranslatedDictionary }?
---@field clipboard ClipboardEntry?

---@param player LuaPlayer
local function player_init(player)
    storage.players[player.index] = {}  --[[@as table]]
    local player_table = storage.players[player.index]

    player_table.realm = Realm.init()
    util.context.init(player_table)
    util.context.set(player, player_table.realm.first)

    reload_preferences(player_table)
    reset_ui_state(player_table)

    -- Set default fuel to coal because anything else is awkward
    defaults.set_all(player, "fuels", {prototype="coal"})

    util.gui.toggle_mod_gui(player)

    if DEV_ACTIVE then
        util.porter.add_factories(player, DEV_EXPORT_STRING)

        player.force.research_all_technologies()
        player.clear_recipe_notifications()
        player.cheat_mode = true
    end
end

---@param player LuaPlayer
local function refresh_player_table(player)
    local player_table = storage.players[player.index]

    defaults.migrate(player_table)

    reload_preferences(player_table)
    reset_ui_state(player_table)

    util.context.validate(player)

    player_table.translation_tables = nil
    player_table.clipboard = nil

    player_table.realm:validate()
end

---@class GlobalTable
---@field players { [PlayerIndex]: PlayerTable }
---@field prototypes PrototypeLists
---@field next_object_ID integer
---@field nth_tick_events { [Tick]: NthTickEvent }
---@field productivity_recipes ProductivityRecipes
---@field installed_mods ModToVersion
storage = {}  -- just for the type checker, doesn't do anything

local function global_init()
    -- Set up a new save for development if necessary
    local freeplay = remote.interfaces["freeplay"]
    if DEV_ACTIVE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    storage.players = {}  -- Table containing all player-specific data
    storage.next_object_ID = 1  -- Counter used for assigning incrementing IDs to all objects
    storage.nth_tick_events = {}  -- Save metadata about currently registered on_nth_tick events

    storage.prototypes = {}  -- Table containing all relevant prototypes indexed by ID
    prototyper.build()  -- Generate all relevant prototypes and save them in storage
    loader.run(true)  -- Run loader which creates useful indexes of prototype data

    storage.installed_mods = script.active_mods  -- Retain current modset to detect mod changes for invalid factories

    translator.on_init()  -- Initialize flib's translation module
    prototyper.util.build_translation_dictionaries()

    for _, player in pairs(game.players) do player_init(player) end
end

-- Prompts migrations, a GUI and prototype reload, and a validity check on all factories
local function handle_configuration_change()
    local migrations = migrator.determine_migrations()

    if not migrations then  -- implies this save can't be migrated anymore
        for _, player in pairs(game.players) do util.gui.reset_player(player) end
        storage = {}; global_init()
        game.print{"fp.mod_reset"};
        return
    end

    migrator.migrate_global(migrations)
    migrator.migrate_player_tables(migrations)

    -- Re-build prototypes
    storage.prototypes = {}
    prototyper.build()
    loader.run(true)

    for index, player in pairs(game.players) do
        refresh_player_table(player)  -- part of migration cleanup

        util.gui.reset_player(player)  -- Destroys all existing GUI's
        util.gui.toggle_mod_gui(player)  -- Recreates the mod-GUI if necessary

        -- Update calculations in case prototypes changed in a relevant way
        for district in storage.players[index].realm:iterator() do
            for factory in district:iterator() do solver.update(player, factory) end
        end
    end

    storage.installed_mods = script.active_mods

    translator.on_configuration_changed()
    prototyper.util.build_translation_dictionaries()
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
    storage.players[event.player_index] = nil
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
commands.add_command("fp-restart-translation", {"command-help.fp_restart_translation"}, function()
    translator.on_init()
    prototyper.util.build_translation_dictionaries()
end)
commands.add_command("fp-shrinkwrap-interface", {"command-help.fp_shrinkwrap_interface"}, function(command)
    if command.player_index then main_dialog.shrinkwrap_interface(game.get_player(command.player_index)) end
end)
