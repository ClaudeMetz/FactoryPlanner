local generator = require("backend.handlers.generator")

prototyper = {
    util = {}
}

-- The purpose of the prototyper is to recreate the storage tables containing all relevant data types.
-- It also handles some other things related to prototypes, such as updating preferred ones, etc.
-- Its purpose is to not lose any data, so if a dataset of a factory doesn't exist anymore
-- in the newly loaded storage tables, it saves the name in string-form instead and makes the
-- concerned factory-dataset invalid. This accomplishes that invalid data is only permanently
-- removed when the user tells the factory to repair itself, giving him a chance to re-add the
-- missing mods. It is also a better separation of responsibilities and avoids some redundant code.

-- Load order is important here: recipes->items->machines->fuels->modules->beacons->...
-- The boolean indicates whether this prototype has categories or not
---@type table<DataType, boolean>
prototyper.data_types = {recipes = false, items = true, machines = true, fuels = true,
                         belts = false, pumps = false, silos = false, wagons = true, modules = true,
                         beacons = false, locations = false, qualities = false}

---@alias DataType "recipes" | "items" | "machines" | "fuels" | "belts" | "pumps" | "silos" | "wagons" | "modules" | "beacons" | "locations" | "qualities"

---@alias NamedPrototypes<T> table<string, T>
---@alias NamedPrototypesWithCategory<T> table<string, NamedCategory<T>>
---@alias NamedCategory<T> { name: string, members: NamedPrototypes<T> }
---@alias AnyNamedPrototypes NamedPrototypes<FPPrototype> | NamedPrototypesWithCategory<FPPrototype>

---@alias IndexedPrototypes<T> table<integer, T>
---@alias IndexedPrototypesWithCategory<T> table<integer, IndexedCategory<T>>
---@alias IndexedCategory<T> { id: integer, name: string, data_type: DataType, category_id: integer?, members: IndexedPrototypes<T> }
---@alias AnyIndexedPrototypes IndexedPrototypes<FPPrototype> | IndexedPrototypesWithCategory<FPPrototype>

---@class PrototypeLists
---@field recipes IndexedPrototypes<FPRecipePrototype>
---@field items IndexedPrototypesWithCategory<FPItemPrototype>
---@field machines IndexedPrototypesWithCategory<FPMachinePrototype>
---@field fuels IndexedPrototypesWithCategory<FPFuelPrototype>
---@field belts IndexedPrototypes<FPBeltPrototype>
---@field pumps IndexedPrototypes<FPPumpPrototype>
---@field silos IndexedPrototypes<FPSiloPrototype>
---@field wagons IndexedPrototypesWithCategory<FPWagonPrototype>
---@field modules IndexedPrototypesWithCategory<FPModulePrototype>
---@field beacons IndexedPrototypes<FPBeaconPrototype>
---@field locations IndexedPrototypes<FPLocationPrototype>
---@field qualities IndexedPrototypes<FPQualityPrototype>

---@alias SortingFunction fun(a: table, b: table): boolean


-- Converts given prototype list to use ids as keys, and sorts it if desired
---@param data_type DataType
---@param prototype_sorting_function SortingFunction?
---@return AnyIndexedPrototypes
local function convert_and_sort(data_type, prototype_sorting_function)
    local final_list = {}

    ---@param list AnyNamedPrototypes
    ---@param sorting_function SortingFunction?
    ---@param category_id integer?
    ---@return AnyIndexedPrototypes
    local function apply(list, sorting_function, category_id)
        local new_list = {}  ---@type (FPPrototype | IndexedCategory<FPPrototype>)[]

        for _, member in pairs(list) do table.insert(new_list, member) end
        if sorting_function then table.sort(new_list, sorting_function) end

        for id, member in pairs(new_list) do
            member.id = id
            member.category_id = category_id  -- can be nil
            member.data_type = data_type
        end

        return new_list  ---@as AnyIndexedPrototypes
    end

    ---@param a NamedCategory<FPPrototype>
    ---@param b NamedCategory<FPPrototype>
    ---@return boolean
    local function category_sorting_function(a, b)
        if a.name < b.name then return true
        elseif a.name > b.name then return false end
        return false
    end

    if prototyper.data_types[data_type] == false then
        final_list = apply(storage.prototypes[data_type]--[[@as NamedPrototypes<FPPrototype>]], prototype_sorting_function, nil)
        ---@cast final_list IndexedPrototypes<FPPrototype>
    else
        final_list = apply(storage.prototypes[data_type]--[[@as NamedPrototypesWithCategory<FPPrototype>]], category_sorting_function, nil)
        ---@cast final_list IndexedPrototypesWithCategory<FPPrototypeWithCategory>
        for id, category in pairs(final_list) do
            local members = category.members  ---@cast members NamedPrototypes<FPPrototype>
            category.members = apply(members, prototype_sorting_function, id)
        end
    end

    return final_list
end


function prototyper.build()
    integrator.collect("recycling_recipes")
    integrator.collect("compacting_recipes")

    for data_type, _ in pairs(prototyper.data_types) do
        storage.prototypes[data_type] = generator[data_type].generate()  ---@as AnyIndexedPrototypes
    end

    -- Second pass to do some things that can't be done in the first pass due to the strict sequencing
    for data_type, _ in pairs(prototyper.data_types) do
        local second_pass = generator[data_type].second_pass  ---@as fun(prototypes: NamedPrototypes<FPPrototype>)?
        if second_pass ~= nil then second_pass(storage.prototypes[data_type]) end
    end

    -- Finish up generation by converting lists to use ids as keys, and sort if desired
    for data_type, _ in pairs(prototyper.data_types) do
        local sorting_function = generator[data_type].sorting_function  ---@type SortingFunction?
        storage.prototypes[data_type] = convert_and_sort(data_type, sorting_function)  ---@type AnyIndexedPrototypes
    end
end


-- ** UTIL **
---@param data_type DataType
---@param prototype (integer | string)?
---@param category (integer | string)?
---@return (AnyFPPrototype | NamedCategory<FPPrototype>)?
function prototyper.util.find(data_type, prototype, category)
    local prototypes, prototype_map = storage.prototypes[data_type], PROTOTYPE_MAPS[data_type]

    if (category == nil) ~= (prototype == nil) then  -- either category or prototype provided
        local identifier = category or prototype
        local relevant_map = (type(identifier) == "string") and prototype_map or prototypes
        return relevant_map[identifier]  -- can be nil

    else  -- category and prototype provided
        local category_map = (type(category) == "string") and prototype_map or prototypes
        local category_table = category_map[category]  ---@type MappedCategory<FPPrototype>
        if category_table == nil then return nil end

        if type(prototype) == type(category) then
            return category_table.members[prototype]  -- can be nil
        else  -- If types don't match, we need to use the opposite map for the category
            if type(prototype) == "string" then
                return prototype_map[category_table.name].members--[[@cast -nil]][prototype]  -- can be nil
            else
                return prototypes[category_table.id].members--[[@cast -nil]][prototype]  -- can be nil
            end
        end
    end
end


---@class FPPackedPrototype
---@field name string
---@field category string?
---@field data_type DataType
---@field simplified boolean

---@alias CategoryDesignation ("category" | "type" | "combined_category")

-- Returns a new table that only contains the given prototypes' identifiers
---@param prototype AnyPrototype
---@param category_designation CategoryDesignation?
---@return FPPackedPrototype
function prototyper.util.simplify_prototype(prototype, category_designation)
    return {name = prototype.name, category = prototype[category_designation],
        data_type = prototype.data_type, simplified = true}
end

---@param prototypes AnyPrototype[]
---@param category_designation CategoryDesignation?
---@return FPPackedPrototype[]
function prototyper.util.simplify_prototypes(prototypes, category_designation)
    local simplified_prototypes = {}
    for index, proto in pairs(prototypes) do
        simplified_prototypes[index] = prototyper.util.simplify_prototype(proto, category_designation)
    end
    return simplified_prototypes
end


---@alias AnyPrototype (AnyFPPrototype | FPPackedPrototype)

-- Validates given object with prototype, which includes trying to find the correct
-- new reference for its prototype, if able. Returns valid-status at the end.
---@param prototype AnyPrototype
---@param category_designation CategoryDesignation?
---@return AnyPrototype
function prototyper.util.validate_prototype_object(prototype, category_designation)
    local updated_proto = prototype

    if prototype.simplified then  -- try to unsimplify, otherwise it stays that way
        ---@cast prototype FPPackedPrototype
        if not category_designation or prototype.category then  -- failsafe
            local new_proto = prototyper.util.find(prototype.data_type, prototype.name, prototype.category)  ---@as AnyFPPrototype?
            if new_proto then updated_proto = new_proto end
        end
    else
        ---@cast prototype AnyFPPrototype
        local category = prototype[category_designation]  ---@type string
        local new_proto = prototyper.util.find(prototype.data_type, prototype.name, category)  ---@as AnyFPPrototype?
        updated_proto = new_proto or prototyper.util.simplify_prototype(prototype, category_designation)  ---@as AnyPrototype
    end

    return updated_proto
end

---@param prototypes AnyPrototype[]?
---@param category_designation CategoryDesignation
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
    for _, item_category in ipairs(storage.prototypes.items) do
        lib.translator.new(item_category.name)
        for _, proto in pairs(item_category.members) do
            lib.translator.add(item_category.name, proto.name, proto.localised_name)
        end
    end

    lib.translator.new("recipe")
    for _, proto in pairs(storage.prototypes.recipes) do
        lib.translator.add("recipe", proto.name, proto.localised_name)
    end
end
