prototyper = {
    util = {},
    defaults = {}
}

-- The purpose of the prototyper is to recreate the global tables containing all relevant data types.
-- It also handles some other things related to prototypes, such as updating preferred ones, etc.
-- Its purpose is to not lose any data, so if a dataset of a factory-dataset doesn't exist anymore
-- in the newly loaded global tables, it saves the name in string-form instead and makes the
-- concerned factory-dataset invalid. This accomplishes that invalid data is only permanently
-- removed when the user tells the subfactory to repair itself, giving him a chance to re-add the
-- missing mods. It is also a better separation of responsibilities and avoids some redundant code.

-- (Load order is important here: machines->recipes->items->fuels)
local data_types = {"machines", "recipes", "items", "fuels", "belts", "modules", "beacons"}


-- ** TOP LEVEL **
-- Generates the new data and mapping_tables and saves them to lua-globals
function prototyper.setup()
    new = {}
    for _, data_type in ipairs(data_types) do
        new["all_" .. data_type] = generator["all_" .. data_type]()
    end
end

-- Updates the relevant data of the given player to fit the new data
function prototyper.run(player_table)
    -- Then, update the default/preferred datasets
    for _, data_type in ipairs(data_types) do
        if player_table.preferences.default_prototypes[data_type] ~= nil then
            prototyper.defaults.migrate(player_table, data_type)
        end
    end

    -- Update the validity of all elements of the factory and archive
    Collection.validate_datasets(player_table.factory.Subfactory)
    Collection.validate_datasets(player_table.archive.Subfactory)
end

-- Overwrites the factorio global data with the new data in lua-global
function prototyper.finish()
    for _, data_type in ipairs(data_types) do
        global["all_" .. data_type] = new["all_" .. data_type]
    end
    new = nil

    loader.run()
end


-- ** UTIL **
-- Validates given object with prototype, which includes trying to find the correct
-- new reference for its prototype, if able. Returns valid-status at the end.
function prototyper.util.validate_prototype_object(object, proto_name, data_type, category_name)
    local proto = object[proto_name]
    local new_proto = prototyper.util.get_new_prototype_by_name(data_type, proto.name, proto[category_name])

    if new_proto ~= nil then  -- meaning a new, fitting prototype has been found
        object[proto_name] = new_proto
        return true

    else  -- simplify prototype if no match can be found among the new ones
        if not proto.simplified then object[proto_name] = prototyper.util.simplify_prototype(proto) end
        return false
    end
end

-- Returns the prototype defined by the given names, if it exists
function prototyper.util.get_new_prototype_by_name(data_type, proto_name, category_name)
    local current_prototype_table = new or global  -- need to check which one is currently in use
    local new_prototypes = current_prototype_table["all_" .. data_type]

    if new_prototypes.structure_type == "simple" then
        local prototype_id = new_prototypes.map[proto_name]
        if prototype_id == nil then return nil
        else return new_prototypes[data_type][prototype_id] end

    else  -- structure_type == "complex"
        local category_id = new_prototypes.map[category_name]
        if category_id == nil then return nil
        else
            local prototypes = new_prototypes[new_prototypes.main_structure_name][category_id]
            local prototype_id = prototypes.map[proto_name]
            if prototype_id == nil then return nil
            else return prototypes[data_type][prototype_id] end
        end
    end
end

-- Returns a new table that only contains the given prototypes' identifiers
function prototyper.util.simplify_prototype(proto)
    if proto == nil then return nil end
    local simple_proto = { name = proto.name, simplified = true }

    -- Doing the detection this way is a bit ugly, but makes much easier
    -- It is actually important to check for category first, type second, as
    -- fuels specifically have both, with category being the relevant one here
    if proto.category then simple_proto.category = proto.category
    elseif proto.type then simple_proto.type = proto.type end

    return simple_proto
end


-- ** DEFAULTS **
-- Defines fallbacks by name which overwrites choosing the first in the proto list
local specific_fallbacks = { ["fuels"] = { ["chemical"] = "coal" } }

-- Returns the fallback default for the given type of prototype
function prototyper.defaults.get_fallback(type)
    -- Use the lua-global new-table if it exists, use global otherwise
    local data_table = new or global
    local all_prototypes = data_table["all_" .. type]
    local specific_fallback = specific_fallbacks[type]

    -- Simple prototype structures return a single prototype as a fallback
    local fallback = {structure_type = all_prototypes.structure_type}
    if all_prototypes.structure_type == "simple" then
        local prototype_id = (specific_fallback) and all_prototypes.map[specific_fallback] or 1
        fallback.prototype = all_prototypes[type][prototype_id]

    -- Complex prototype structures return a table containing a fallback for every category
    else  -- structure_type == "complex"
        fallback.prototypes = {}
        for category_id, category in pairs(all_prototypes.categories) do
            local category_fallback = (specific_fallback) and specific_fallback[category.name]
            local prototype_id = (category_fallback) and category.map[category_fallback] or 1
            fallback.prototypes[category_id] = category[type][prototype_id]
        end
    end

    return fallback
end


-- Returns the default prototype for the given type, incorporating the category, if given
function prototyper.defaults.get(player, type, category_id)
    local default = data_util.get("preferences", player).default_prototypes[type]
    if default.structure_type == "simple" then
        return default.prototype
    else  -- structure_type == "complex"
        return default.prototypes[category_id]
    end
end

-- Sets the default prototype for the given type, incorporating the category, if given
function prototyper.defaults.set(player, type, prototype_id, category_id)
    local default = data_util.get("preferences", player).default_prototypes[type]
    if default.structure_type == "simple" then
        local new_prototype = global["all_" .. type][type][prototype_id]
        default.prototype = new_prototype
    else  -- structure_type == "complex"
        local new_category = global["all_" .. type].categories[category_id]
        local new_prototype = new_category[type][prototype_id]
        default.prototypes[category_id] = new_prototype
    end
end


-- Migrates the default_prototypes preferences, trying to preserve the users choices
function prototyper.defaults.migrate(player_table, type)
    local new_prototypes = new["all_" .. type]
    local default_prototypes = player_table.preferences.default_prototypes
    local default = default_prototypes[type]

    if default.structure_type == "simple" then
        -- Use the same prototype if an equivalent can be found, use fallback otherwise
        local new_prototype_id = new_prototypes.map[default.prototype.name]
        default.prototype = (new_prototype_id ~= nil) and new_prototypes[type][new_prototype_id]
          or prototyper.defaults.get_fallback(type).prototype

    else  -- structure_type == "complex"
        local category_map = {}  -- Needs a map of category_name -> old_prototype
        for _, prototype in pairs(default.prototypes) do category_map[prototype.category] = prototype end

        -- Invalid categories need to be removed to avoid prototypes hanging around, thus new array
        local new_default = {prototypes = {}, structure_type = "complex"}
        local fallback = prototyper.defaults.get_fallback(type)

        -- Go through the new categories and see if an old, valid default to carry over exists
        for category_id, category in pairs(new_prototypes.categories) do
            local old_default_matched = false
            local old_default_prototype = category_map[category.name]

            if old_default_prototype ~= nil then  -- old category still exists
                local new_prototype_id = category.map[old_default_prototype.name]

                if new_prototype_id ~= nil then  -- machine in that category exists too
                    new_default.prototypes[category_id] = category[type][new_prototype_id]
                    old_default_matched = true
                end
            end

            -- If no old default could be matched up, use the fallback default
            if not old_default_matched then
                new_default.prototypes[category_id] = fallback.prototypes[category_id]
            end
        end

        default_prototypes[type] = new_default
    end
end