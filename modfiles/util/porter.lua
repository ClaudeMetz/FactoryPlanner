local migrator = require("backend.handlers.migrator")
local Factory = require("backend.data.Factory")

local _porter = {}

---@class ExportTable
---@field export_modset ModToVersion
---@field subfactories PackedFactory[]

---@class ImportTable
---@field export_modset ModToVersion
---@field subfactories Factory[]

---@alias ExportString string

-- Converts the given subfactories into a factory exchange string
---@param subfactories Factory[]
---@return ExportString
function _porter.generate_export_string(subfactories)
    local export_table = {
        export_modset = global.installed_mods,
        subfactories = {}
    }

    for _, subfactory in pairs(subfactories) do
        table.insert(export_table.subfactories, subfactory:pack())
    end

    return game.encode_string(game.table_to_json(export_table))  --[[@as ExportString]]
end

-- Converts the given factory exchange string into a temporary Factory
---@param export_string ExportString
---@return ImportTable?
---@return string?
function _porter.process_export_string(export_string)
    local export_table = nil  ---@type AnyBasic?

    if not pcall(function()
        export_table = game.json_to_table(game.decode_string(export_string) --[[@as string]])
        assert(type(export_table) == "table")
    end) then return nil, "decoding_failure" end
    ---@cast export_table ExportTable

    if not pcall(function()
        -- Works for any old version of the mod, which is not the case for other migrations
        migrator.migrate_export_table(export_table)
    end) then return nil, "migration_failure" end

    -- Include the modset at export time to be displayed to the user if a subfactory is invalid
    local import_table = {export_modset = export_table.export_modset, subfactories = {}}  ---@type ImportTable

    if not pcall(function()  -- Unpacking and validating could be pcall-ed separately, but that's too many slow pcalls
        for _, packed_subfactory in pairs(export_table.subfactories) do
            local unpacked_subfactory = Factory.unpack(packed_subfactory)
            unpacked_subfactory:validate()
            table.insert(import_table.subfactories, unpacked_subfactory)
        end
    end) then return nil, "unpacking_failure" end

    -- This is not strictly a decoding failure, but close enough
    if #import_table.subfactories == 0 then return nil, "decoding_failure" end

    return import_table, nil
end

---@alias UpdatedMods { [string]: { old: VersionString, current: VersionString } }

-- Creates a nice tooltip laying out which mods were added, removed and updated since the subfactory became invalid
---@param old_modset ModToVersion
---@return LocalisedString
function _porter.format_modset_diff(old_modset)
    if not old_modset then return "" end

    ---@type { added: ModToVersion, removed: ModToVersion, updated: UpdatedMods }
    local changes = {added={}, removed={}, updated={}}
    local new_modset = script.active_mods

    -- Determine changes by running through both sets of mods once each
    for name, current_version in pairs(new_modset) do
        local old_version = old_modset[name]
        if not old_version then
            changes.added[name] = current_version
        elseif old_version ~= current_version then
            changes.updated[name] = {old=old_version, current=current_version}
        end
    end

    for name, old_version in pairs(old_modset) do
        if not new_modset[name] then
            changes.removed[name] = old_version
        end
    end

    -- Compose tooltip from all three types of changes
    local tooltip = {"", {"fp.subfactory_modset_changes"}}  ---@type LocalisedString
    local current_table, next_index = tooltip, 3

    if next(changes.added) then
        current_table, next_index = util.build_localised_string({
            {"fp.subfactory_mod_added"}}, current_table, next_index)
        for name, version in pairs(changes.added) do
            current_table, next_index = util.build_localised_string({
                {"fp.subfactory_mod_and_version", name, version}}, current_table, next_index)
        end
    end

    if next(changes.removed) then
        current_table, next_index = util.build_localised_string({
            {"fp.subfactory_mod_removed"}}, current_table, next_index)
        for name, version in pairs(changes.removed) do
            current_table, next_index = util.build_localised_string({
                {"fp.subfactory_mod_and_version", name, version}}, current_table, next_index)
        end
    end

    if next(changes.updated) then
        current_table, next_index = util.build_localised_string({
            {"fp.subfactory_mod_updated"}}, current_table, next_index)
        for name, versions in pairs(changes.updated) do
            current_table, next_index = util.build_localised_string({
                {"fp.subfactory_mod_and_versions", name, versions.old, versions.current}}, current_table, next_index)
        end
    end

    -- Return an empty string if no changes were found, ie. the tooltip is still only the header
    return (table_size(tooltip) == 2) and "" or tooltip
end

-- Adds given export_string-subfactories to the current factory
---@param player LuaPlayer
---@param export_string ExportString
function _porter.add_subfactories(player, export_string)
    local import_table = util.porter.process_export_string(export_string)  ---@cast import_table -nil
    -- No error handling here, as the export_string for this will always be known to work

    local district = util.context.get(player, "District")  --[[@as District]]
    local first_subfactory = nil

    for _, subfactory in pairs(import_table.subfactories) do
        district:insert(subfactory)
        if not subfactory.valid then subfactory:repair(player) end
        solver.update(player, subfactory)
        first_subfactory = first_subfactory or subfactory
    end

    util.context.set(player, first_subfactory)
end

return _porter
