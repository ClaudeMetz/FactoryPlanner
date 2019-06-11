require("migration_0_17_0")

-- This code handles the general migration process of the mod's global table
-- It decides whether and which migrations should be applied, in appropriate order
-- (The migration process is split into sub-functions so it can later be applied to lone subfactories)

-- Returns a table containing all existing migrations in order
-- The appropriate migration file needs to be required at the top
local function migration_masterlist()
    return {
        --[0] = {version="0.17.0"},
    }
end

-- Applies any appropriate migrations to the given factory
function attempt_factory_migration(factory)
    local migrations = determine_migrations(factory.mod_version)

    apply_migrations(migrations, factory)
    factory.mod_version = global.mod_version

    for _, subfactory in pairs(Factory.get_in_order(factory, "Subfactory")) do
        attempt_subfactory_migration(subfactory, migrations)
    end
end

-- Applies any appropriate migrations to the given subfactory
function attempt_subfactory_migration(subfactory, migrations)
    -- if migrations~=nil, it forgoes re-checking itself to avoid repeated checks
    local migrations = migrations or determine_migrations(subfactory.mod_version)

    apply_migrations(migrations, subfactory)
    subfactory.mod_version = global.mod_version
end

-- Determines whether a migration needs to take place, and if so, returns the appropriate range of the 
-- migration_masterlist. If the version changed, but no migrations apply, it returns an empty array.
function determine_migrations(previous_version)
    local migrations = {}
    
    local found = false
    for _, migration in ipairs(migration_masterlist()) do
        if compare_versions(previous_version, migration.version) then found = true end
        if found then table.insert(migrations, migration.version) end
    end

    return migrations
end

-- Applies given migrations to the object (doesn't change it's mod_version attribute)
function apply_migrations(migrations, object)
    for _, migration in ipairs(migrations) do
        local internal_name = migration:gsub("%.", "_")
        local migration_functions = _G["migration_" .. internal_name]
        migration_functions[object.class](object)
    end
end

-- Compares two mod versions, returns true if v1 is an earlier version than v2 (v1 < v2)
-- Version numbers have to be of the same structure: equal amount of numbers, separated by a '.'
local function compare_versions(v1, v2)
    local split_v1 = ui_util.split(v1, ".")
    local split_v2 = ui_util.split(v2, ".")

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