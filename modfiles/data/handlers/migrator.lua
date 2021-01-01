-- This code handles the general migration process of the mod's global table
-- It decides whether and which migrations should be applied, in appropriate order

migrator = {}

-- Factory exchange strings from versions before this can no longer be imported
local last_migratable_version = "0.18.0"

-- Returns a table containing all existing migrations in order
local migration_masterlist = {
    [1] = {version="0.18.20", migration=require("data.migrations.migration_0_18_20")},
    [2] = {version="0.18.27", migration=require("data.migrations.migration_0_18_27")},
    [3] = {version="0.18.29", migration=require("data.migrations.migration_0_18_29")},
    [4] = {version="0.18.38", migration=require("data.migrations.migration_0_18_38")},
    [5] = {version="0.18.42", migration=require("data.migrations.migration_0_18_42")},
    [6] = {version="0.18.45", migration=require("data.migrations.migration_0_18_45")},
    [7] = {version="0.18.48", migration=require("data.migrations.migration_0_18_48")},
    [8] = {version="0.18.49", migration=require("data.migrations.migration_0_18_49")},
    [9] = {version="0.18.51", migration=require("data.migrations.migration_0_18_51")},
    [10] = {version="1.0.6", migration=require("data.migrations.migration_1_0_6")},
    [11] = {version="1.1.5", migration=require("data.migrations.migration_1_1_5")},
    [12] = {version="1.1.6", migration=require("data.migrations.migration_1_1_6")},
    [13] = {version="1.1.8", migration=require("data.migrations.migration_1_1_8")},
}

-- ** LOCAL UTIL **
-- Compares two mod versions, returns true if v1 is an earlier version than v2 (v1 < v2)
-- Version numbers have to be of the same structure: same amount of numbers, separated by a '.'
local function compare_versions(v1, v2)
    local split_v1 = split_string(v1, ".")
    local split_v2 = split_string(v2, ".")

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
local function apply_migrations(migrations, function_name, object, player)
    for _, migration in ipairs(migrations) do
        local migration_function = migration[function_name]

        if migration_function ~= nil then
            local migration_message = migration_function(object, player)

            -- If no message is returned, everything went fine
            if migration_message == "removed" then break end
        end
    end
end

-- Determines whether a migration needs to take place, and if so, returns the appropriate range of the
-- migration_masterlist. If the version changed, but no migrations apply, it returns an empty array.
local function determine_migrations(previous_version)
    local migrations = {}

    local found = false
    for _, migration in ipairs(migration_masterlist) do
        if compare_versions(previous_version, migration.version) then found = true end
        if found then table.insert(migrations, migration.migration) end
    end

    return migrations
end


-- ** TOP LEVEL **
-- Applies any appropriate migrations to the global table
function migrator.migrate_global()
    local migrations = determine_migrations(global.mod_version)

    apply_migrations(migrations, "global", nil, nil)
    global.mod_version = game.active_mods["factoryplanner"]
end

-- Applies any appropriate migrations to the given factory
function migrator.migrate_player_table(player)
    local player_table = data_util.get("table", player)
    if player_table ~= nil then  -- don't apply migrations to new players
        local migrations = determine_migrations(player_table.mod_version)

        -- General migrations
        apply_migrations(migrations, "player_table", player_table, player)
        player_table.mod_version = global.mod_version

        -- Subfactory migrations
        local factories = {"factory", "archive"}
        for _, factory_name in pairs(factories) do
            for _, subfactory in pairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
                apply_migrations(migrations, "subfactory", subfactory, player)
                subfactory.mod_version = global.mod_version
            end
        end
    end
end

-- Applies any appropriate migrations to the given export_table's subfactories
function migrator.migrate_export_table(export_table)
    if not compare_versions(last_migratable_version, export_table.mod_version) then error() end

    local migrations = determine_migrations(export_table.mod_version)
    for _, packed_subfactory in pairs(export_table.subfactories) do
        -- This migration type won't need the player argument, and removing it allows
        -- us to run imports without having a player attached
        apply_migrations(migrations, "packed_subfactory", packed_subfactory, nil)
    end
    export_table.mod_version = global.mod_version
end
