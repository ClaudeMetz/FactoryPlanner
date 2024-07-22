-- This code handles the general migration process of the mod's global table
-- It decides whether and which migrations should be applied, in appropriate order

local migrator = {}

---@alias MigrationMasterList { [integer]: { version: VersionString, migration: Migration } }
---@alias Migration { global: function, player_table: function, packed_factory: function? }
---@alias MigrationObject PlayerTable | Factory | PackedFactory

-- Returns a table containing all existing migrations in order
local migration_masterlist = {  ---@type MigrationMasterList
    [1] = {version="1.0.6", migration=require("backend.migrations.migration_1_0_6")},
    [2] = {version="1.1.5", migration=require("backend.migrations.migration_1_1_5")},
    [3] = {version="1.1.14", migration=require("backend.migrations.migration_1_1_14")},
    [4] = {version="1.1.27", migration=require("backend.migrations.migration_1_1_27")},
    [5] = {version="1.1.42", migration=require("backend.migrations.migration_1_1_42")},
    [6] = {version="1.1.59", migration=require("backend.migrations.migration_1_1_59")},
    [7] = {version="1.1.61", migration=require("backend.migrations.migration_1_1_61")},
    [8] = {version="1.1.65", migration=require("backend.migrations.migration_1_1_65")},
    [9] = {version="1.1.66", migration=require("backend.migrations.migration_1_1_66")},
    [10] = {version="1.1.67", migration=require("backend.migrations.migration_1_1_67")},
    [11] = {version="1.1.73", migration=require("backend.migrations.migration_1_1_73")},
    [12] = {version="1.2.1", migration=require("backend.migrations.migration_1_2_1")},
    [13] = {version="1.2.2", migration=require("backend.migrations.migration_1_2_2")},
}


-- Compares two mod versions, returns true if v1 is an earlier version than v2 (v1 < v2)
-- Version numbers have to be of the same structure: same amount of numbers, separated by a '.'
---@param v1 VersionString
---@param v2 VersionString
---@return boolean
local function compare_versions(v1, v2)
    local split_v1 = util.split_string(v1, ".")
    local split_v2 = util.split_string(v2, ".")

    for i = 1, #split_v1 do
        if split_v1[i] == split_v2[i] then
            -- continue
        elseif split_v1[i] < split_v2[i] then
            return true
        else
            return false
        end
    end
    return false  -- return false if both versions are the same
end

-- Applies given migrations to the object
---@param migrations Migration[]
---@param function_name string
---@param object MigrationObject?
---@param player LuaPlayer?
local function apply_migrations(migrations, function_name, object, player)
    for _, migration in ipairs(migrations) do
        local migration_function = migration[function_name]

        if migration_function ~= nil then
            migration_function(object, player)  ---@type string
        end
    end
end


-- Determines whether a migration needs to take place, and if so, returns the appropriate range of the
-- migration_masterlist. If the version changed, but no migrations apply, it returns an empty array.
---@param comparison_version VersionString?
---@return Migration[]?
function migrator.determine_migrations(comparison_version)
    local previous_version = global.installed_mods["factoryplanner"]

    -- 1.1.60 is the first version that can be properly migrated (doesn't apply to export strings)
    if not comparison_version and not compare_versions("1.1.59", previous_version) then return nil end
    comparison_version = comparison_version or previous_version

    local migrations = {}
    local found = false

    for _, migration in ipairs(migration_masterlist) do
        if compare_versions(comparison_version, migration.version) then found = true end
        if found then table.insert(migrations, migration.migration) end
    end

    return migrations
end


---@param migrations Migration[]
function migrator.migrate_global(migrations)
    apply_migrations(migrations, "global", nil, nil)
end

---@param player LuaPlayer
---@param migrations Migration[]
function migrator.migrate_player_table(player, migrations)
    local player_table = util.globals.player_table(player)
    apply_migrations(migrations, "player_table", player_table, player)
end


-- Applies any appropriate migrations to the given export_table's factories
---@param export_table ExportTable
function migrator.migrate_export_table(export_table)
    local export_version = export_table.export_modset["factoryplanner"]
    export_table.factories = export_table.factories or export_table.subfactories  -- migration
    local migrations = migrator.determine_migrations(export_version)  ---@cast migrations -nil

    for _, packed_factory in pairs(export_table.factories) do
        apply_migrations(migrations, "packed_factory", packed_factory, nil)
    end
end

return migrator
