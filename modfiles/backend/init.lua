local Realm = require("backend.data.Realm")

local loader = require("backend.handlers.loader")
local migrator = require("backend.migrations.migrator")
require("backend.handlers.prototyper")
require("backend.handlers.defaults")
require("backend.handlers.integrator")
require("backend.handlers.interface")

local dev_export_string = "eNrdVkuPnDAM/i85DyMew/PYQ0+tVKnHaoRCMLNRE8KGsO1oxH+vA8wUmJ3VrratdssJG3+2P9sxORH42ShtcqnKFgzJTqSgLZCM+Ft368VkQ0oougMtaWNAT/oA1SDggRooHU25aOeASvACZZSirYvyfUcFN8eFCWVG6WMjaF1fvHrWuG0oA4ceZin0Z3sOGOfbiTBBWxvx4+gFUTWVFvCBtpyhWIgOGs1rg1YnhNfKWCjBT41WZccMf8CM8kLVfLSY1Ev/X0bliDLKFmcKhOSZ0YhmDuOaddwaMSzHweaTEW5A2tJRQ3NzbGBStZYgl43gFYeSZEZ30NsKV7yGMi8slErV1dadhvuOa1RPmszbRssnTkI3dXdhmEau60VRGke70EviII5TP42SOOw3z2HDkYlzAKqdH3cA4h9QcbdJsHxSP9yFvh+nieu6SbBLEt8P0yBKkjTaJbsAuew3xKgmr4RS2mZ/GYNBsSE4kJh85uEb5rBs5SfUDIkw3kD+rHbOGY+4G5zPI6Xqs/mosQFLhXGziooWNoTauYMRhzDQDGozjLrnuhsiKbuzac6ofZ5U1z3D7yALJHpwJpwTLBv3m1S7YjMBbtCZjutVkWqlJRUrV6Mxv+WrUsgxF1xiRSfauGg6Afm0bC5EB+1XsIUfLZb9G78/dhKrijMONTs6I87xV2W4GKyrMIX560U4D73f73sUmZISrEzI/Hg+PaHDEcV1aeDNT2Zr0LNTdbqmQ6BZL1oJwuDIvqV5rDq7NGbbpBs24DoaU3S1GNkdSM6uMrD+Ho3ev2j2T/0Ts7LaeP7LN971yn93685btUPT6q3N1p/q93+zG8Z/Ev5m3816eFUL98PGf+rCihfg76+8sFrpZfcim+i+/wV3PxDb"

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
---@field context_menu LuaGuiElement?
---@field active_selector string?
---@field compact_view boolean
---@field districts_view boolean

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
        context_menu = nil,
        active_selector = nil,

        compact_view = false,
        districts_view = false
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
    lib.context.init(player_table)
    lib.context.set(player, player_table.realm.first)

    lib.preferences.reload(player_table)
    reset_ui_state(player_table)

    -- Set default fuel to coal because anything else is awkward
    defaults.set_all(player, "fuels", {prototype="coal"})

    lib.gui.toggle_mod_gui(player)
    lib.nth_tick.register((game.tick + 1), "shrinkwrap_interface", {player_index=player.index})

    if DEVELOPER_MODE then
        lib.porter.add_factories(player, dev_export_string)

        player.force.research_all_technologies()
        player.clear_recipe_notifications()
        player.cheat_mode = true
    end
end

---@param player LuaPlayer
local function refresh_player_table(player)
    local player_table = storage.players[player.index]

    lib.preferences.reload(player_table)
    reset_ui_state(player_table)

    defaults.migrate(player_table)
    lib.temperature.migrate(player_table)

    lib.context.validate(player)

    player_table.translation_tables = nil
    player_table.clipboard = nil

    player_table.realm:validate()
end


local function generate_object_index()
    OBJECT_INDEX = {}  ---@type table<ObjectID, Object>
    for _, player_table in pairs(storage.players) do
        if not player_table.realm then return end  -- migration issue mitigation
        player_table.realm:index()  -- recursively indexes all objects
    end
end

local function run_on_load(fake_load)
    if not fake_load then
        if script.active_mods["factoryplanner"] ~= storage.installed_mods["factoryplanner"] then
            return  -- if the mod version changed, this needs to just run during migration
        end

        generate_object_index()
    end

    lib.nth_tick.register_all()

    loader.run()
end


---@class GlobalTable
---@field players { [PlayerIndex]: PlayerTable }
---@field prototypes PrototypeLists
---@field integrations IntegrationsTable
---@field next_object_ID integer
---@field nth_tick_events { [Tick]: NthTickEvent }
---@field installed_mods ModToVersion
storage = {}  -- just for the type checker, doesn't do anything

local function global_init()
    -- Set up a new save for development if necessary
    local freeplay = remote.interfaces["freeplay"]
    if DEVELOPER_MODE and freeplay then  -- Disable freeplay popup-message
        if freeplay["set_skip_intro"] then remote.call("freeplay", "set_skip_intro", true) end
        if freeplay["set_disable_crashsite"] then remote.call("freeplay", "set_disable_crashsite", true) end
    end

    storage.players = {}  -- Table containing all player-specific data
    storage.next_object_ID = 1  -- Counter used for assigning incrementing IDs to all objects
    storage.nth_tick_events = {}  -- Save metadata about currently registered on_nth_tick events

    storage.prototypes = {}  -- Table containing all relevant prototypes indexed by ID
    storage.integrations = {}  -- Table containing all integration data collected from other mods
    prototyper.build()  -- Generate all relevant prototypes and save them in storage
    run_on_load(true)  -- Run loader which creates useful indexes of prototype data
    generate_object_index()  -- This just initializes the OBJECT_INDEX variable

    storage.installed_mods = script.active_mods  -- Retain current modset to detect mod changes for invalid factories

    lib.translator.on_init()  -- Initialize flib's translation module
    prototyper.util.build_translation_dictionaries()

    for _, player in pairs(game.players) do player_init(player) end

    if test_runner then test_runner() end  -- Run if a test mod is active
end

-- Prompts migrations, a GUI and prototype reload, and a validity check on all factories
local function handle_configuration_change()
    local migrations = migrator.determine_migrations()

    if not migrations then  -- implies this save can't be migrated anymore
        for _, player in pairs(game.players) do lib.gui.reset_player(player) end
        storage = {}; global_init()
        game.print{"fp.mod_reset"};
        return
    end

    storage.prototypes = {}
    storage.integrations = {}
    prototyper.build()
    run_on_load(true)

    migrator.migrate_global(migrations)
    migrator.migrate_player_tables(migrations)
    generate_object_index()  -- rebuild this after objects have been migrated

    for index, player in pairs(game.players) do
        refresh_player_table(player)  -- part of migration cleanup

        lib.gui.reset_player(player)  -- Destroys all existing GUI's
        lib.gui.toggle_mod_gui(player)  -- Recreates the mod-GUI if necessary

        -- Update calculations in case prototypes changed in a relevant way
        for district in storage.players[index].realm:iterator() do
            district.needs_refresh = true
            for factory in district:iterator() do
                solver.update(player, factory)
            end
        end
    end

    storage.installed_mods = script.active_mods

    lib.translator.on_configuration_changed()
    prototyper.util.build_translation_dictionaries()
end


script.on_load(run_on_load)

script.on_init(global_init)

script.on_configuration_changed(handle_configuration_change)


-- ** COMMANDS **
commands.add_command("fp-restart-translation", {"command-help.fp_restart_translation"}, function()
    lib.translator.on_init()
    prototyper.util.build_translation_dictionaries()
end)
commands.add_command("fp-shrinkwrap-interface", {"command-help.fp_shrinkwrap_interface"}, function(command)
    if command.player_index then
        lib.nth_tick.register((game.tick + 1), "shrinkwrap_interface", {player_index=command.player_index})
    end
end)


-- ** EVENTS **
local listeners = {}

listeners.player = {
    on_player_dictionaries_ready = (function(player, _)
        local player_table = lib.globals.player_table(player)
        player_table.translation_tables = lib.translator.get_all(player.index)

        modal_dialog.set_searchfield_state(player)  -- enables searchfields if possible
    end),

    on_player_joined_game = (function(_, event)
        lib.translator.on_player_joined_game(event)
    end),
    on_player_locale_changed = (function(_, event)
        lib.translator.on_player_locale_changed(event)
    end),
    on_string_translated = (function(_, event)
        lib.translator.on_string_translated(event)
    end)
}

listeners.game = {
    on_player_created = (function(event)
        local player = game.get_player(event.player_index)
        player_init(player)
    end),
    on_player_removed = (function(event)
        storage.players[event.player_index] = nil
    end),

    on_tick = lib.translator.on_tick
}

return { listeners }
