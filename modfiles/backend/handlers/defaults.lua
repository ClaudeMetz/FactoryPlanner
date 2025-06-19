defaults = {}

---@class DefaultPrototype
---@field proto AnyFPPrototype
---@field quality FPQualityPrototype?
---@field modules DefaultModule[]?
---@field beacon_amount integer?

---@class DefaultModule
---@field proto FPModulePrototype
---@field quality FPQualityPrototype
---@field amount integer

---@class DefaultData
---@field prototype string?
---@field quality string?
---@field modules DefaultModuleData[]?
---@field beacon_amount integer?

---@class DefaultModuleData
---@field prototype string
---@field quality string
---@field amount integer

---@alias PrototypeDefaultWithCategory { [integer]: DefaultPrototype }
---@alias AnyPrototypeDefault DefaultPrototype | PrototypeDefaultWithCategory

-- Returns the default prototype for the given type, incorporating the category, if given
---@param player LuaPlayer
---@param data_type DataType
---@param category (integer | string)?
---@return DefaultPrototype
function defaults.get(player, data_type, category)
    local default = util.globals.preferences(player)["default_" .. data_type]
    local category_table = prototyper.util.find(data_type, nil, category)
    return (category_table == nil) and default or default[category_table.id]
end

-- Sets the default for the given type, incorporating the category if given
---@param player LuaPlayer
---@param data_type DataType
---@param data DefaultData
---@param category (integer | string)?
function defaults.set(player, data_type, data, category)
    local default = defaults.get(player, data_type, category)

    if data.prototype then
        default.proto = prototyper.util.find(data_type, data.prototype, category)  --[[@as AnyFPPrototype]]
    end
    if data.quality then
        default.quality = prototyper.util.find("qualities", data.quality, nil)  --[[@as FPQualityPrototype]]
    end
    if data.modules then
        default.modules = {}
        for _, default_module in pairs(data.modules) do
            table.insert(default.modules, {
                proto = MODULE_NAME_MAP[default_module.prototype],
                quality = prototyper.util.find("qualities", default_module.quality, nil),
                amount = default_module.amount
            })
        end
        if #default.modules == 0 then default.modules = nil end
    end
    if data.beacon_amount then
        default.beacon_amount = data.beacon_amount
    end
end

-- Sets the default prototype data for all categories of the given type
---@param player LuaPlayer
---@param data_type DataType
---@param data DefaultData
function defaults.set_all(player, data_type, data)
    -- Doesn't make sense for prototypes without categories, just use .set() instead
    if prototyper.data_types[data_type] == false then return end

    for _, category_data in pairs(storage.prototypes[data_type]) do
        local matched_prototype = prototyper.util.find(data_type, data.prototype, category_data.id)
        if matched_prototype then
            data.prototype = matched_prototype.name
            defaults.set(player, data_type, data, category_data.id)
        end
    end
end


---@param player LuaPlayer
---@param data_type DataType
---@param object Machine | Fuel | Beacon
---@param category (integer | string)?
---@return boolean equals
function defaults.equals_default(player, data_type, object, category)
    local default = defaults.get(player, data_type, category)
    local same_proto = (default.proto.name == object.proto.name)
    local same_quality, same_modules = true, true
    if object.quality_proto then same_quality = (default.quality.id == object.quality_proto.id) end
    if object.module_set then same_modules = object.module_set:equals_default(default.modules) end
    return same_proto and same_quality and same_modules
end

---@param player LuaPlayer
---@param data_type DataType
---@param object Machine | Fuel
---@return boolean equals_all
function defaults.equals_all_defaults(player, data_type, object)
    for _, category_data in pairs(storage.prototypes[data_type]) do
        local in_category = (prototyper.util.find(data_type, object.proto.name, category_data.id) ~= nil)
        local equals_default = defaults.equals_default(player, data_type, object, category_data.id)
        if in_category and not equals_default then
            return false
        end
    end
    return true
end


local prototypes_with_quality = {machines=true, beacons=true, modules=true, pumps=true, wagons=true}

-- Returns the fallback default for the given type of prototype
---@param data_type DataType
---@return AnyPrototypeDefault
function defaults.get_fallback(data_type)
    local prototypes = storage.prototypes[data_type]  ---@type AnyIndexedPrototypes
    local default_quality = prototypes_with_quality[data_type] and storage.prototypes.qualities[1] or nil

    local fallback = nil
    if prototyper.data_types[data_type] == false then
        ---@cast prototypes IndexedPrototypes<FPPrototype>
        fallback = {proto=prototypes[1], quality=default_quality, modules=nil, beacon_amount=nil}
    else
        ---@cast prototypes IndexedPrototypesWithCategory<FPPrototypeWithCategory>
        fallback = {}
        for _, category in pairs(prototypes) do
            fallback[category.id] = {proto=category.members[1], quality=default_quality, modules=nil, beacon_amount=nil}
        end
    end

    return fallback
end


---@param data_type DataType
---@param fallback DefaultPrototype
---@param default DefaultPrototype
---@param category string?
---@return DefaultPrototype migrated_default
local function migrate_prototype_default(data_type, fallback, default, category)
    local equivalent_proto = prototyper.util.find(data_type, default.proto.name, category)
    if not equivalent_proto then
        return fallback  -- full reset if prototype went missing
    else
        local migrated_default = {
            proto = equivalent_proto,
            quality = nil,  -- only migrated if relevant for this data_type
            modules = nil,  -- only migrated to anything if previously present
            beacon_amount = default.beacon_amount or fallback.beacon_amount  -- could be nil
        }

        if prototypes_with_quality[data_type] then
            local equivalent_quality = prototyper.util.find("qualities", default.quality.name, nil)
            migrated_default.quality = equivalent_quality or fallback.quality
        end

        if default.modules then
            migrated_default.modules = {}
            for _, module in pairs(default.modules) do
                local equivalent_module = prototyper.util.find("modules", module.proto.name, module.proto.category)
                if equivalent_module then
                    local equivalent_quality = prototyper.util.find("qualities", module.quality.name, nil)
                    table.insert(migrated_default.modules, {
                        proto = equivalent_module,
                        quality = equivalent_quality or fallback.quality,  -- same quality as the base proto
                        amount = module.amount
                    })
                end
            end
            if #migrated_default.modules == 0 then migrated_default.modules = nil end
        end

        return migrated_default
    end
end

-- Kinda unclean that I have to do this, but it's better than storing it elsewhere
local category_designations = {machines="category", items="type",
    fuels="combined_category", wagons="category", modules="category"}

-- Migrates the default prototype preferences, trying to preserve the users choices
-- When this is called, the loader cache will already exist
---@param player_table PlayerTable
function defaults.migrate(player_table)
    local preferences = player_table.preferences

    for data_type, has_categories in pairs(prototyper.data_types) do
        local fallback = defaults.get_fallback(data_type)
        local default = preferences["default_" .. data_type]
        if default == nil then goto skip end

        if not has_categories then
            preferences["default_" .. data_type] = migrate_prototype_default(data_type, fallback, default, nil)
        else
            local default_map = {}
            for _, default_data in pairs(default) do
                local category_name = default_data.proto[category_designations[data_type]]  ---@type string
                default_map[category_name] = default_data
            end

            local new_defaults = {}
            for _, category in pairs(storage.prototypes[data_type]) do
                local previous_default = default_map[category.name]
                new_defaults[category.id] = (not previous_default) and fallback[category.id]
                    or migrate_prototype_default(data_type, fallback[category.id], previous_default, category.name)
            end
            preferences["default_" .. data_type] = new_defaults
        end
        ::skip::
    end
end


---@param player LuaPlayer
---@param data_type DataType
---@param category (integer | string)?
---@return LocalisedString
function defaults.generate_tooltip(player, data_type, category)
    local default = defaults.get(player, data_type, category)
    local tooltip = {"", {"fp.current_default"}, "\n"}
    local quality = default.quality

    local name_line = {"", "[img=" .. default.proto.sprite .. "] ", default.proto.localised_name}
    local proto_line = (not quality or not quality.always_show) and {"fp.tt_title", name_line}
        or {"fp.tt_title_with_note", name_line, quality.rich_text}
    table.insert(tooltip, proto_line)
    if default.beacon_amount then table.insert(tooltip, " x" .. default.beacon_amount) end

    if default.modules then
        local modules = ""
        for _, module in pairs(default.modules) do
            for i = 1, module.amount, 1 do
                modules = modules .. "[img=" .. module.proto.sprite .. "]"
            end
        end
        table.insert(tooltip, {"", "\n", modules})
    end

    return tooltip
end
