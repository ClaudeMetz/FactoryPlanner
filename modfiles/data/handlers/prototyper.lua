local generator = require("data.handlers.generator")

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

-- Load order is important here: machines->recipes->items->fuels
-- The boolean indicates whether this prototype has categories or not
prototyper.data_types = {machines = true, recipes = false, items = true, fuels = true,
                         belts = false, wagons = true, modules = true, beacons = false}


-- Converts given prototype list to use ids as keys, and sorts it if desired
local function convert_and_sort(data_type, prototype_sorting_function)
    local final_list = {}

    local function apply(list, sorting_function, category_id)
        local new_list = {}

        for _, member in pairs(list) do table.insert(new_list, member) end
        if sorting_function then table.sort(new_list, sorting_function) end

        for id, member in pairs(new_list) do
            member.id = id
            member.category_id = category_id
            member.data_type = data_type
        end

        return new_list
    end

    local function category_sorting_function(a, b)
        if a.name < b.name then return true
        elseif a.name > b.name then return false end
    end

    if prototyper.data_types[data_type] == false then
        final_list = apply(global.prototypes[data_type], prototype_sorting_function, nil)
    else
        final_list = apply(global.prototypes[data_type], category_sorting_function, nil)
        for id, category in pairs(final_list) do
            category.members = apply(category.members, prototype_sorting_function, id)
        end
    end

    return final_list
end


function prototyper.build()
    global.prototypes = {}
    local prototypes = global.prototypes

    for data_type, _ in pairs(prototyper.data_types) do
        prototypes[data_type] = generator[data_type].generate()
    end

    -- Second pass to do some things that can't be done in the first pass due to the strict sequencing
    for data_type, _ in pairs(prototyper.data_types) do
        local second_pass = generator[data_type].second_pass
        if second_pass ~= nil then second_pass(prototypes[data_type]) end
    end

    -- Finish up generation by converting lists to use ids as keys, and sort if desired
    for data_type, _ in pairs(prototyper.data_types) do
        local sorting_function = generator[data_type].sorting_function
        prototypes[data_type] = convert_and_sort(data_type, sorting_function)
    end
end


-- ** UTIL **
-- Returns the attribute string for the given prototype
function prototyper.util.get_attributes(prototype)
    if prototype.category_id == nil then
        return PROTOTYPE_ATTRIBUTES[prototype.data_type][prototype.id]
    else
        return PROTOTYPE_ATTRIBUTES[prototype.data_type][prototype.category_id][prototype.id]
    end
end

-- Finds the given prototype by name. Can use the loader cache since it'll exist at this point
function prototyper.util.find_prototype(data_type, prototype_name, category_name)
    local prototype_map = PROTOTYPE_MAPS[data_type]

    if category_name == nil then
        return prototype_map[prototype_name]  -- can be nil
    else
        local category = prototype_map[category_name]
        if category == nil then return nil end
        return category.members[prototype_name]  -- can be nil
    end
end

-- Validates given object with prototype, which includes trying to find the correct
-- new reference for its prototype, if able. Returns valid-status at the end.
function prototyper.util.validate_prototype_object(prototype, category_designation)
    local updated_proto = prototype

    if prototype.simplified then  -- try to unsimplify, otherwise it stays that way
        local new_proto = prototyper.util.find_prototype(prototype.data_type, prototype.name, prototype.category)
        if new_proto then updated_proto = new_proto end
    else
        local category = prototype[category_designation]
        local new_proto = prototyper.util.find_prototype(prototype.data_type, prototype.name, category)
        updated_proto = new_proto or prototyper.util.simplify_prototype(prototype, category)
    end

    return updated_proto
end

-- Returns a new table that only contains the given prototypes' identifiers
function prototyper.util.simplify_prototype(proto, category)
    return { name = proto.name, category = category, data_type = proto.data_type, simplified = true }
end

-- Build the necessary RawDictionaries for translation
function prototyper.util.build_translation_dictionaries()
    for _, item_category in ipairs(global.prototypes.items) do
        translator.new(item_category.name)
        for _, proto in pairs(item_category.members) do
            translator.add(item_category.name, proto.name, proto.localised_name)
        end
    end

    translator.new("recipe")
    for _, proto in pairs(global.prototypes.recipes) do
        translator.add("recipe", proto.name, proto.localised_name)
    end
end


-- ** DEFAULTS **
-- Returns the default prototype for the given type, incorporating the category, if given
function prototyper.defaults.get(player, data_type, category_id)
    local default = data_util.preferences(player).default_prototypes[data_type]
    return (category_id == nil) and default or default[category_id]
end

-- Sets the default prototype for the given type, incorporating the category, if given
function prototyper.defaults.set(player, data_type, prototype_id, category_id)
    local default_prototypes = data_util.preferences(player).default_prototypes
    local prototypes = global.prototypes[data_type]

    if category_id == nil then
        default_prototypes[data_type] = prototypes[prototype_id]
    else
        default_prototypes[data_type][category_id] = prototypes[category_id].members[prototype_id]
    end
end

-- Returns the fallback default for the given type of prototype
function prototyper.defaults.get_fallback(data_type)
    local prototypes = global.prototypes[data_type]

    local fallback = nil
    if prototyper.data_types[data_type] == false then
        fallback = prototypes[1]
    else
        fallback = {}
        for _, category in pairs(prototypes) do
            fallback[category.id] = category.members[1]
        end
    end

    return fallback
end

-- Migrates the default_prototypes preferences, trying to preserve the users choices
-- When this is called, the loader cache will already exist
function prototyper.defaults.migrate(player_table)
    local default_prototypes = player_table.preferences.default_prototypes

    for data_type, has_categories in pairs(prototyper.data_types) do
        if default_prototypes[data_type] ~= nil then
            if not has_categories then
                -- Use the same prototype if an equivalent can be found, use fallback otherwise
                local default_proto = default_prototypes[data_type]
                local equivalent_proto = prototyper.util.find_prototype(data_type, default_proto.name, nil)
                default_prototypes[data_type] = equivalent_proto or prototyper.defaults.get_fallback(data_type)

            else
                local new_defaults = {}  -- Create new table to get rid of any dead categories implicitly
                local fallback = prototyper.defaults.get_fallback(data_type)

                local default_map = {}  -- Needs a map of category name -> prototype
                for _, default_category in pairs(default_prototypes[data_type]) do
                    default_map[default_category.name] = default_category.prototype
                end

                for _, category in pairs(global.prototypes[data_type]) do
                    local previous_category = default_map[category.name]
                    if previous_category then  -- category existed previously
                        local proto_name = previous_category.prototype.name
                        new_defaults[category.id] = prototyper.util.find_prototype(data_type, proto_name, category.name)
                    end
                    new_defaults[category.id] = new_defaults[category.id] or fallback[category.id]
                end

                default_prototypes[data_type] = new_defaults
            end
        end
    end
end
