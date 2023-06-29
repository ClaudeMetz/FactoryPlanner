local migrator = require("backend.handlers.migrator")

local _porter = {}

---@class ExportTable
---@field mod_version VersionString
---@field export_modset ModToVersion
---@field subfactories FPPackedSubfactory[]

---@alias ExportString string

-- Converts the given subfactories into a factory exchange string
---@param subfactories FPSubfactory[]
---@return ExportString
function _porter.generate_export_string(subfactories)
    local export_table = {
        -- This can use the global mod_version since it's only called for migrated, valid subfactories
        mod_version = global.mod_version,
        export_modset = global.installed_mods,
        subfactories = {}
    }

    for _, subfactory in pairs(subfactories) do
        table.insert(export_table.subfactories, Subfactory.pack(subfactory))
    end

    local export_string = game.encode_string(game.table_to_json(export_table))  ---@cast export_string -nil
    return export_string
end

-- Converts the given factory exchange string into a temporary Factory
---@param export_string ExportString
---@return District?
---@return string?
function _porter.process_export_string(export_string)
    local export_table = nil  ---@type AnyBasic?

    if not pcall(function()
        export_table = game.json_to_table(game.decode_string(export_string) --[[@as string]])
        assert(type(export_table) == "table")
    end) then return nil, "decoding_failure" end
    ---@cast export_table ExportTable

    if not pcall(function()
        migrator.migrate_export_table(export_table)
    end) then return nil, "migration_failure" end

    local import_factory = Factory.init()
    if not pcall(function()  -- Unpacking and validating could be pcall-ed separately, but that's too many slow pcalls
        for _, packed_subfactory in pairs(export_table.subfactories) do
            local unpacked_subfactory = Subfactory.unpack(packed_subfactory)

            -- The imported subfactories will be temporarily contained in a factory, so they
            -- can be validated and moved to the appropriate 'real' factory easily
            Factory.add(import_factory, unpacked_subfactory)

            -- Validate the subfactory to both add the valid-attributes to all the objects
            -- and potentially un-simplify the prototypes that came in packed
            Subfactory.validate(unpacked_subfactory)
        end

        -- Include the modset at export time to be displayed to the user if a subfactory is invalid
        import_factory.export_modset = export_table.export_modset

    end) then return nil, "unpacking_failure" end

    -- This is not strictly a decoding failure, but close enough
    if Factory.count(import_factory, "Subfactory") == 0 then return nil, "decoding_failure" end

    return import_factory, nil
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
function _porter.add_by_string(player, export_string)
    local context = util.globals.context(player)
    local first_subfactory = Factory.import_by_string(context.factory, export_string)
    util.context.set_subfactory(player, first_subfactory)

    for _, subfactory in pairs(Factory.get_in_order(context.factory, "Subfactory")) do
        if not subfactory.valid then Subfactory.repair(subfactory, player) end
        solver.update(player, subfactory)
    end
end

return _porter
