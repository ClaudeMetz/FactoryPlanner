local _preferences = {}

_preferences.products_per_row_options = {5, 6, 7, 8, 9, 10}
_preferences.factory_list_rows_options = {20, 22, 24, 26, 28, 30, 32}
_preferences.compact_width_percentages = {8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36}

---@alias Timescale 1 | 60
---@alias BeltsOrLanes "belts" | "lanes"

---@class PreferencesTable
---@field timescale Timescale
---@field pause_on_interface boolean
---@field utility_scopes { components: "Factory" | "Floor" }
---@field recipe_filters { disabled: boolean, hidden: boolean }
---@field compact_ingredients boolean
---@field fold_out_subfloors boolean
---@field products_per_row integer
---@field factory_list_rows integer
---@field compact_width_percentage integer
---@field show_gui_button boolean
---@field attach_factory_products boolean
---@field skip_factory_naming boolean
---@field prefer_matrix_solver boolean
---@field use_simplex_solver boolean
---@field show_floor_items boolean
---@field ingredient_satisfaction boolean
---@field calculate_emissions boolean
---@field ignore_barreling_recipes boolean
---@field ignore_recycling_recipes boolean
---@field done_column boolean
---@field percentage_column boolean
---@field line_comment_column boolean
---@field item_views ItemViewPreferences
---@field belts_or_lanes BeltsOrLanes
---@field default_prototypes DefaultPrototypesTable
---@field default_temperatures TemperatureDefaultMap

---@class DefaultPrototypesTable
---@field machines PrototypeDefaultWithCategory
---@field fuels PrototypeDefaultWithCategory
---@field beacons DefaultPrototype
---@field belts DefaultPrototype
---@field pumps DefaultPrototype
---@field silos DefaultPrototype
---@field wagons PrototypeDefaultWithCategory

---@param player_table PlayerTable
function _preferences.reload(player_table)
    -- Reloads the user preferences, incorporating previous preferences if possible
    local player_preferences = player_table.preferences or {}
    local updated_prefs = {}

    ---@param name string
    ---@param default any
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
    reload("compact_ingredients", false)
    reload("fold_out_subfloors", false)

    -- Main dimensions are maxed, to be shrinkwrapped down
    reload("products_per_row", 10)
    reload("factory_list_rows", 32)
    reload("compact_width_percentage", 26)

    reload("show_gui_button", true)
    reload("skip_factory_naming", true)
    reload("attach_factory_products", false)
    reload("prefer_matrix_solver", false)
    reload("use_simplex_solver", false)
    reload("show_floor_items", true)
    reload("ingredient_satisfaction", false)
    reload("calculate_emissions", false)
    reload("ignore_barreling_recipes", false)
    reload("ignore_recycling_recipes", false)

    reload("done_column", true)
    reload("percentage_column", false)
    reload("line_comment_column", false)

    reload("item_views", item_views.default_preferences())

    reload("belts_or_lanes", "belts")

    updated_prefs.default_prototypes = defaults.refresh_preferences(player_preferences.default_prototypes)

    reload("default_temperatures", lib.temperature.get_fallback())

    player_table.preferences = updated_prefs
end


-- Version, incremented each time the format of exported preferences changes in any way
-- The mod prevents importing non-matching preferences versions to avoid needing migrations
_preferences.current_version = 1

---@class PreferencesExportTable
---@field version integer
---@field timescale Timescale
---@field pause_on_interface boolean
---@field compact_ingredients boolean
---@field fold_out_subfloors boolean
---@field products_per_row integer
---@field factory_list_rows integer
---@field compact_width_percentage integer
---@field show_gui_button boolean
---@field attach_factory_products boolean
---@field skip_factory_naming boolean
---@field prefer_matrix_solver boolean
---@field use_simplex_solver boolean
---@field show_floor_items boolean
---@field ingredient_satisfaction boolean
---@field calculate_emissions boolean
---@field ignore_barreling_recipes boolean
---@field ignore_recycling_recipes boolean
---@field done_column boolean
---@field percentage_column boolean
---@field line_comment_column boolean
---@field belts_or_lanes BeltsOrLanes

---@param player LuaPlayer
---@return ExportString
function _preferences.export(player)
    local prefs = lib.globals.preferences(player)

    local export_table = {
        version = _preferences.current_version,

        timescale = prefs.timescale,
        pause_on_interface = prefs.pause_on_interface,
        compact_ingredients = prefs.compact_ingredients,
        fold_out_subfloors = prefs.fold_out_subfloors,
        products_per_row = prefs.products_per_row,
        factory_list_rows = prefs.factory_list_rows,
        compact_width_percentage = prefs.compact_width_percentage,
        show_gui_button = prefs.show_gui_button,
        attach_factory_products = prefs.attach_factory_products,
        skip_factory_naming = prefs.skip_factory_naming,
        prefer_matrix_solver = prefs.prefer_matrix_solver,
        use_simplex_solver = prefs.use_simplex_solver,
        show_floor_items = prefs.show_floor_items,
        ingredient_satisfaction = prefs.ingredient_satisfaction,
        calculate_emissions = prefs.calculate_emissions,
        ignore_barreling_recipes = prefs.ignore_barreling_recipes,
        ignore_recycling_recipes = prefs.ignore_recycling_recipes,
        done_column = prefs.done_column,
        percentage_column = prefs.percentage_column,
        line_comment_column = prefs.line_comment_column,
        belts_or_lanes = prefs.belts_or_lanes
    }

    return lib.pack_export_string(export_table)
end

---@param value integer
---@param options integer[]
---@return boolean
local function verify_range(value, options)
    if type(value) ~= "number" or value % 1 ~= 0 then return false end
    for _, option in pairs(options) do
        if option == value then return true end
    end
    return false
end

---@param player LuaPlayer
---@param export_string ExportString
---@return string?
function _preferences.import(player, export_string)
    local export_table = nil

    if not pcall(function()
        export_table = lib.unpack_export_string(export_string)
        assert(type(export_table) == "table")
    end) then return "decoding_failure" end
    ---@cast export_table PreferencesExportTable

    if export_table.version ~= _preferences.current_version then return "version_mismatch" end

    if not pcall(function()
        local et = export_table
        if et.timescale ~= 1 and et.timescale ~= 60 then error() end
        if type(et.pause_on_interface) ~= "boolean" then error() end
        if type(et.compact_ingredients) ~= "boolean" then error() end
        if type(et.fold_out_subfloors) ~= "boolean" then error() end
        if not verify_range(et.products_per_row, _preferences.products_per_row_options) then error() end
        if not verify_range(et.factory_list_rows, _preferences.factory_list_rows_options) then error() end
        if not verify_range(et.compact_width_percentage, _preferences.compact_width_percentages) then error() end
        if type(et.show_gui_button) ~= "boolean" then error() end
        if type(et.attach_factory_products) ~= "boolean" then error() end
        if type(et.skip_factory_naming) ~= "boolean" then error() end
        if type(et.prefer_matrix_solver) ~= "boolean" then error() end
        if type(et.use_simplex_solver) ~= "boolean" then error() end
        if type(et.show_floor_items) ~= "boolean" then error() end
        if type(et.ingredient_satisfaction) ~= "boolean" then error() end
        if type(et.calculate_emissions) ~= "boolean" then error() end
        if type(et.ignore_barreling_recipes) ~= "boolean" then error() end
        if type(et.ignore_recycling_recipes) ~= "boolean" then error() end
        if type(et.done_column) ~= "boolean" then error() end
        if type(et.percentage_column) ~= "boolean" then error() end
        if type(et.line_comment_column) ~= "boolean" then error() end
        if et.belts_or_lanes ~= "belts" and et.belts_or_lanes ~= "lanes" then error() end
    end) then return "unpacking_failure" end

    -- All good, overwrite preferences
    local prefs = lib.globals.preferences(player)
    export_table.version = nil
    for name, value in pairs(export_table) do
        prefs[name] = value
    end

    -- No return indicates success
end


---@alias PreferencesChangeType "all" | "main_dimensions" | "compact_dimensions" | "solver_config" | "mod_gui" | "edit_views" | "belts_or_lanes" | "prototype_default"

---@param player LuaPlayer
---@param change_type PreferencesChangeType
---@param shrinkwrap boolean?
function _preferences.refresh_after_change(player, change_type, shrinkwrap)
    local rebuild_views_data, rebuild_views_interface = false, false
    local run_solver, run_solver_all = false, false
    local toggle_mod_gui = false
    local refresh_scope = nil  ---@type RefreshGUITrigger?
    local rebuild_main, rebuild_compact = false, false

    if change_type == "all" then  -- import, reset, etc
        rebuild_views_data = true
        run_solver_all = true
        run_solver = true  -- update current factory right away
        rebuild_main = true
        rebuild_compact = true
    elseif change_type == "main_dimensions" then
        rebuild_main = true
    elseif change_type == "compact_dimensions" then
        rebuild_compact = true
    elseif change_type == "solver_config" then
        run_solver_all = true
        run_solver = true  -- update current factory right away
        refresh_scope = "production"
    elseif change_type == "mod_gui" then
        toggle_mod_gui = true
    elseif change_type == "edit_views" then
        rebuild_views_interface = true
        refresh_scope = "factory"
    elseif change_type == "belts_or_lanes" then
        rebuild_views_data = true
        rebuild_views_interface = true
        run_solver = true
        refresh_scope = "factory"
    elseif change_type == "prototype_default" then
        rebuild_views_data = true
        rebuild_views_interface = true
        refresh_scope = "factory"
    end

    if rebuild_views_data then item_views.rebuild_data(player) end
    if rebuild_views_interface then item_views.rebuild_interface(player) end
    if run_solver_all then
        local realm = lib.globals.player_table(player).realm
        realm:schedule_solver_updates(game.tick, player)
    end
    if run_solver then solver.update(player) end
    if toggle_mod_gui then lib.gui.toggle_mod_gui(player) end
    if refresh_scope then lib.gui.run_refresh(player, refresh_scope) end
    if shrinkwrap then  -- this rebuilds the main interface implicitly
        GLOBAL_HANDLERS["shrinkwrap_interface"]{player_index=player.index}
    elseif rebuild_main then main_dialog.rebuild(player, true) end
    if rebuild_compact then compact_dialog.rebuild(player, false) end
end

return _preferences
