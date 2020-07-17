require("data.migrations.migration_0_17_13")
require("data.migrations.migration_0_17_21")
require("data.migrations.migration_0_17_27")
require("data.migrations.migration_0_17_29")
require("data.migrations.migration_0_17_38")
require("data.migrations.migration_0_17_51")
require("data.migrations.migration_0_17_55")
require("data.migrations.migration_0_17_56")
require("data.migrations.migration_0_17_57")
require("data.migrations.migration_0_17_61")
require("data.migrations.migration_0_17_65")
require("data.migrations.migration_0_18_20")
require("data.migrations.migration_0_18_27")
require("data.migrations.migration_0_18_29")
require("data.migrations.migration_0_18_38")

-- This code handles the general migration process of the mod's global table
-- It decides whether and which migrations should be applied, in appropriate order

migrator = {}

-- Returns a table containing all existing migrations in order
local migration_masterlist = {
    [1] = {version="0.17.13"},
    [2] = {version="0.17.21"},
    [3] = {version="0.17.27"},
    [4] = {version="0.17.29"},
    [5] = {version="0.17.38"},
    [6] = {version="0.17.51"},
    [7] = {version="0.17.55"},
    [8] = {version="0.17.56"},
    [9] = {version="0.17.57"},
    [10] = {version="0.17.61"},
    [11] = {version="0.17.65"},
    [12] = {version="0.18.20"},
    [13] = {version="0.18.27"},
    [14] = {version="0.18.29"},
    [15] = {version="0.18.38"},
}

-- ** LOCAL UTIL **
-- Compares two mod versions, returns true if v1 is an earlier version than v2 (v1 < v2)
-- Version numbers have to be of the same structure: same amount of numbers, separated by a '.'
local function compare_versions(v1, v2)
    local split_v1 = cutil.split(v1, ".")
    local split_v2 = cutil.split(v2, ".")

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
local function apply_migrations(migrations, name, player, object)
    for _, migration in ipairs(migrations) do
        local internal_version = migration:gsub("%.", "_")
        local f = _G["migration_" .. internal_version][name]
        if f ~= nil then f(player, object) end
    end
end

-- Determines whether a migration needs to take place, and if so, returns the appropriate range of the
-- migration_masterlist. If the version changed, but no migrations apply, it returns an empty array.
local function determine_migrations(previous_version)
    local migrations = {}

    local found = false
    for _, migration in ipairs(migration_masterlist) do
        if compare_versions(previous_version, migration.version) then found = true end
        if found then table.insert(migrations, migration.version) end
    end

    return migrations
end

-- Applies any appropriate migrations to the given subfactory
local function attempt_subfactory_migration(player, subfactory, migrations)
    -- if migrations~=nil, it forgoes re-determining them because the results would be identical
    migrations = migrations or determine_migrations(subfactory.mod_version)

    apply_migrations(migrations, "subfactory", player, subfactory)
    subfactory.mod_version = global.mod_version
end


-- ** TOP LEVEL **
-- Applies any appropriate migrations to the global table
function migrator.attempt_global_migration()
    local migrations = determine_migrations(global.mod_version)

    apply_migrations(migrations, "global", nil, nil)
    global.mod_version = game.active_mods["factoryplanner"]
end

-- Applies any appropriate migrations to the given factory
function migrator.attempt_player_table_migration(player)
    local player_table = get_table(player)
    if player_table ~= nil then  -- don't apply migrations to new players
        local migrations = determine_migrations(player_table.mod_version)

        -- General migrations
        apply_migrations(migrations, "player_table", player, player_table)

        -- Subfactory migrations
        local factories = {"factory", "archive"}
        for _, factory_name in pairs(factories) do
            for _, subfactory in pairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
                attempt_subfactory_migration(player, subfactory, migrations)
            end
        end

        player_table.mod_version = global.mod_version
    end
end