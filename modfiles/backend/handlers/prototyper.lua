local generator = require("backend.handlers.generator")

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
---@type { [DataType]: boolean }
prototyper.data_types = {machines = true, recipes = false, items = true, fuels = true,
                         belts = false, wagons = true, modules = true, beacons = false}

---@alias DataType "machines" | "recipes" | "items" | "fuels" | "belts" | "wagons" | "modules" | "beacons"

---@alias NamedPrototypes<T> { [string]: T }
---@alias NamedPrototypesWithCategory<T> { [string]: { name: string, members: { [string]: T } } } }
---@alias NamedCategory { name: string, members: { [string]: table } }
---@alias AnyNamedPrototypes NamedPrototypes | NamedPrototypesWithCategory

---@alias IndexedPrototypes<T> { [integer]: T }
---@alias IndexedPrototypesWithCategory<T> { [integer]: { id: integer, name: string, members: { [integer]: T } } }
---@alias IndexedCategory { id: integer, name: string, members: { [integer]: table } }
---@alias AnyIndexedPrototypes IndexedPrototypes | IndexedPrototypesWithCategory

---@class PrototypeLists: { [DataType]: table }
---@field machines IndexedPrototypesWithCategory<FPMachinePrototype>
---@field recipes IndexedPrototypes<FPRecipePrototype>
---@field items IndexedPrototypesWithCategory<FPItemPrototype>
---@field fuels IndexedPrototypesWithCategory<FPFuelPrototype>
---@field belts IndexedPrototypes<FPBeltPrototype>
---@field wagons IndexedPrototypesWithCategory<FPWagonPrototype>
---@field modules IndexedPrototypesWithCategory<FPModulePrototype>
---@field beacons IndexedPrototypes<FPBeaconPrototype>

---@alias SortingFunction fun(a: table, b: table): boolean


-- Converts given prototype list to use ids as keys, and sorts it if desired
---@param data_type DataType
---@param prototype_sorting_function SortingFunction
---@return AnyIndexedPrototypes
local function convert_and_sort(data_type, prototype_sorting_function)
    local final_list = {}

    ---@param list AnyNamedPrototypes[]
    ---@param sorting_function SortingFunction
    ---@param category_id integer?
    ---@return AnyIndexedPrototypes
    local function apply(list, sorting_function, category_id)
        local new_list = {}  ---@type (IndexedPrototypes | IndexedCategory)[]

        for _, member in pairs(list) do table.insert(new_list, member) end
        if sorting_function then table.sort(new_list, sorting_function) end

        for id, member in pairs(new_list) do
            member.id = id
            member.category_id = category_id  -- can be nil
            member.data_type = data_type
        end

        return new_list
    end

    ---@param a NamedCategory
    ---@param b NamedCategory
    ---@return boolean
    local function category_sorting_function(a, b)
        if a.name < b.name then return true
        elseif a.name > b.name then return false end
        return false
    end

    if prototyper.data_types[data_type] == false then
        final_list = apply(global.prototypes[data_type], prototype_sorting_function, nil)
        ---@cast final_list IndexedPrototypes<FPPrototype>
    else
        final_list = apply(global.prototypes[data_type], category_sorting_function, nil)
        ---@cast final_list IndexedPrototypesWithCategory<FPPrototypeWithCategory>
        for id, category in pairs(final_list) do
            category.members = apply(category.members, prototype_sorting_function, id)
        end
    end

    return final_list
end


function prototyper.build()
    global.prototypes = {}  ---@type PrototypeLists
    local prototypes = global.prototypes

    for data_type, _ in pairs(prototyper.data_types) do
        ---@type AnyNamedPrototypes
        prototypes[data_type] = generator[data_type].generate()
    end

    -- Second pass to do some things that can't be done in the first pass due to the strict sequencing
    for data_type, _ in pairs(prototyper.data_types) do
        local second_pass = generator[data_type].second_pass  ---@type fun(prototypes: NamedPrototypes)
        if second_pass ~= nil then second_pass(prototypes[data_type]) end
    end

    -- Finish up generation by converting lists to use ids as keys, and sort if desired
    for data_type, _ in pairs(prototyper.data_types) do
        local sorting_function = generator[data_type].sorting_function  ---@type SortingFunction
        prototypes[data_type] = convert_and_sort(data_type, sorting_function)  ---@type AnyIndexedPrototypes
    end
end


-- ** UTIL **
-- Returns the attribute string for the given prototype
---@param prototype AnyFPPrototype
---@return LocalisedString
function prototyper.util.get_attributes(prototype)
    if prototype.category_id == nil then
        ---@cast prototype FPPrototype
        return PROTOTYPE_ATTRIBUTES[prototype.data_type][prototype.id]
    else
        ---@cast prototype FPPrototypeWithCategory
        return PROTOTYPE_ATTRIBUTES[prototype.data_type][prototype.category_id][prototype.id]
    end
end

-- Finds the given prototype by name. Can use the loader cache since it'll exist at this point.
---@param data_type DataType
---@param prototype_name string
---@param category_name string?
---@return AnyFPPrototype?
function prototyper.util.find_prototype(data_type, prototype_name, category_name)
    local prototype_map = PROTOTYPE_MAPS[data_type]

    if category_name == nil then
        return prototype_map[prototype_name]  -- can be nil
    else
        local category = prototype_map[category_name]  ---@type MappedCategory
        if category == nil then return nil end
        return category.members[prototype_name]  -- can be nil
    end
end


---@class FPPackedPrototype
---@field name string
---@field category string
---@field data_type DataType
---@field simplified boolean

-- Returns a new table that only contains the given prototypes' identifiers
---@param prototype AnyFPPrototype
---@param category string?
---@return FPPackedPrototype
function prototyper.util.simplify_prototype(prototype, category)
    return { name = prototype.name, category = category, data_type = prototype.data_type, simplified = true }
end

---@param prototypes FPPrototype[]
---@return FPPackedPrototype[]?
function prototyper.util.simplify_prototypes(prototypes, category_designation)
    if not prototypes then return nil end

    local simplified_prototypes = {}
    for index, proto in pairs(prototypes) do
        simplified_prototypes[index] = prototyper.util.simplify_prototype(proto, proto[category_designation])
    end
    return simplified_prototypes
end


---@alias AnyPrototype (AnyFPPrototype | FPPackedPrototype)

-- Validates given object with prototype, which includes trying to find the correct
-- new reference for its prototype, if able. Returns valid-status at the end.
---@param prototype AnyPrototype
---@param category_designation ("category" | "type")?
---@return AnyPrototype
function prototyper.util.validate_prototype_object(prototype, category_designation)
    local updated_proto = prototype

    if prototype.simplified then  -- try to unsimplify, otherwise it stays that way
        ---@cast prototype FPPackedPrototype
        local new_proto = prototyper.util.find_prototype(prototype.data_type, prototype.name, prototype.category)
        if new_proto then updated_proto = new_proto end
    else
        ---@cast prototype AnyFPPrototype
        local category = prototype[category_designation]  ---@type string
        local new_proto = prototyper.util.find_prototype(prototype.data_type, prototype.name, category)
        updated_proto = new_proto or prototyper.util.simplify_prototype(prototype, category)
    end

    return updated_proto
end

---@param prototypes AnyPrototype[]?
---@return AnyPrototype[]?
---@return boolean valid
function prototyper.util.validate_prototype_objects(prototypes, category_designation)
    if not prototypes then return nil, true end

    local validated_prototypes, valid = {}, true
    for index, proto in pairs(prototypes) do
        validated_prototypes[index] = prototyper.util.validate_prototype_object(proto, category_designation)
        valid = (not validated_prototypes[index].simplified) and valid
    end
    return validated_prototypes, valid
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

-- Migrates the prototypes for default beacons and modules
---@param player_table PlayerTable
function prototyper.util.migrate_mb_defaults(player_table)
    local mb_defaults = player_table.preferences.mb_defaults
    local find = prototyper.util.find_prototype

    local machine = mb_defaults.machine
    if machine then
        mb_defaults.machine = find("modules", machine.name, machine.category)  --[[@as FPModulePrototype ]]
    end

    local second = mb_defaults.machine_secondary
    if second then
        mb_defaults.machine_secondary = find("modules", second.name, second.category)  --[[@as FPModulePrototype ]]
    end

    local beacon = mb_defaults.beacon
    if beacon then
        mb_defaults.beacon = find("beacons", beacon.name, nil)  --[[@as FPBeaconPrototype ]]
    end
end


-- ** DEFAULTS **
---@alias PrototypeDefault FPPrototype
---@alias PrototypeWithCategoryDefault { [integer]: FPPrototypeWithCategory }
---@alias AnyPrototypeDefault PrototypeDefault | PrototypeWithCategoryDefault

-- Returns the default prototype for the given type, incorporating the category, if given
---@param player LuaPlayer
---@param data_type DataType
---@param category_id integer?
---@return AnyPrototypeDefault
function prototyper.defaults.get(player, data_type, category_id)
    ---@type AnyPrototypeDefault
    local default = util.globals.preferences(player).default_prototypes[data_type]
    return (category_id == nil) and default or default[category_id]
end

-- Sets the default prototype for the given type, incorporating the category, if given
---@param player LuaPlayer
---@param data_type DataType
---@param prototype_id integer
---@param category_id integer?
function prototyper.defaults.set(player, data_type, prototype_id, category_id)
    local default_prototypes = util.globals.preferences(player).default_prototypes
    local prototypes = global.prototypes[data_type]  ---@type AnyIndexedPrototypes

    if category_id == nil then
        ---@type PrototypeDefault
        default_prototypes[data_type] = prototypes[prototype_id]
    else
        ---@type PrototypeWithCategoryDefault
        default_prototypes[data_type][category_id] = prototypes[category_id].members[prototype_id]
    end
end

-- Returns the fallback default for the given type of prototype
---@param data_type DataType
---@return AnyPrototypeDefault
function prototyper.defaults.get_fallback(data_type)
    local prototypes = global.prototypes[data_type]  ---@type AnyIndexedPrototypes

    local fallback = {}
    if prototyper.data_types[data_type] == false then
        ---@cast prototypes IndexedPrototypes<FPPrototype>
        fallback = prototypes[1]
    else
        ---@cast prototypes IndexedPrototypesWithCategory<FPPrototypeWithCategory>
        fallback = {}  ---@type PrototypeWithCategoryDefault
        for _, category in pairs(prototypes) do
            fallback[category.id] = category.members[1]
        end
    end

    return fallback
end

-- Kinda unclean that I have to do this, but it's better than storing it elsewhere
local category_designations = {machines="category", items="type",
    fuels="category", wagons="category", modules="category"}

-- Migrates the default_prototypes preferences, trying to preserve the users choices
-- When this is called, the loader cache will already exist
---@param player_table PlayerTable
function prototyper.defaults.migrate(player_table)
    local default_prototypes = player_table.preferences.default_prototypes

    for data_type, has_categories in pairs(prototyper.data_types) do
        if default_prototypes[data_type] ~= nil then
            if not has_categories then
                -- Use the same prototype if an equivalent can be found, use fallback otherwise
                local default_proto = default_prototypes[data_type]  ---@type PrototypeDefault
                local equivalent_proto = prototyper.util.find_prototype(data_type, default_proto.name, nil)
                ---@cast equivalent_proto PrototypeDefault
                default_prototypes[data_type] = equivalent_proto  ---@type PrototypeDefault
                    or prototyper.defaults.get_fallback(data_type)
            else
                local new_defaults = {}  ---@type PrototypeWithCategoryDefault
                local fallback = prototyper.defaults.get_fallback(data_type)

                local default_map = {}  ---@type { [string]: FPPrototype }
                for _, default_proto in pairs(default_prototypes[data_type]--[[@as PrototypeWithCategoryDefault]]) do
                    local category_name = default_proto[category_designations[data_type]]  ---@type string
                    default_map[category_name] = default_proto
                end

                ---@type IndexedPrototypesWithCategory<FPPrototypeWithCategory>
                local categories = global.prototypes[data_type]

                for _, category in pairs(categories) do
                    local previous_category = default_map[category.name]
                    if previous_category then  -- category existed previously
                        local proto_name = previous_category.name
                        ---@type PrototypeWithCategoryDefault
                        new_defaults[category.id] = prototyper.util.find_prototype(data_type, proto_name, category.name)
                    end
                    new_defaults[category.id] = new_defaults[category.id] or fallback[category.id]
                end

                default_prototypes[data_type] = new_defaults  ---@type PrototypeWithCategoryDefault
            end
        end
    end
end
