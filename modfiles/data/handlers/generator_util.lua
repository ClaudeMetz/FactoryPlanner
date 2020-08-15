generator_util = {
    data_structure = {}
}

-- ** DATA STRUCTURE **
-- Local variables only touched during the single event where the generator runs, which is desync-safe
local data, metadata = nil, nil

-- Initializes the data and metadata for the given data structure
function generator_util.data_structure.init(structure_type, main_structure_name,
  sub_structure_name, sub_structure_varname)
    data = {
        [main_structure_name] = {},
        structure_type = structure_type,
        main_structure_name = main_structure_name
    }
    metadata = {
        main_structure_name = main_structure_name,
        sub_structure_name = sub_structure_name,
        sub_structure_varname = sub_structure_varname,
        existing_sub_structure_names = {},
        structure_type = structure_type
    }
end

-- Inserts the given prototype into the correct part of the structure.
function generator_util.data_structure.insert(prototype)
    local function insert_prototype(prototype_table)
        local next_id = #prototype_table + 1
        prototype.id = next_id
        prototype_table[next_id] = prototype
    end

    if metadata.structure_type == "simple" then
        local prototype_table = data[metadata.main_structure_name]
        insert_prototype(prototype_table)

    else  -- structure_type == "complex"
        local category_table = data[metadata.main_structure_name]
        local category_name = prototype[metadata.sub_structure_varname]

        -- Create sub_category, if it doesn't exist
        local category_id = metadata.existing_sub_structure_names[category_name]
        if not category_id then
            category_id = #category_table + 1
            metadata.existing_sub_structure_names[category_name] = category_id
            local category_entry = {[metadata.sub_structure_name]={}, name=category_name, id=category_id}
            category_table[category_id] = category_entry
        end

        local prototype_table = category_table[category_id][metadata.sub_structure_name]
        insert_prototype(prototype_table)
    end
end

-- Applies the given sorting function to the data. Run before map generation.
function generator_util.data_structure.sort(sorting_function)
    local function reassign_ids(prototype_table)
        for index, prototype in ipairs(prototype_table) do prototype.id = index end
    end

    if metadata.structure_type == "simple" then
        local prototype_table = data[metadata.main_structure_name]
        table.sort(prototype_table, sorting_function)
        reassign_ids(prototype_table)

    else  -- structure_type == "complex"
        for _, category_table in pairs(data[metadata.main_structure_name]) do
            local prototype_table = category_table[metadata.sub_structure_name]
            table.sort(prototype_table, sorting_function)
            reassign_ids(prototype_table)
        end
    end
end

-- Generates a '[prototype.name] -> prototype.id'-map for each part of the structure. Run after sorting.
function generator_util.data_structure.generate_map(add_identifiers)
    if metadata.structure_type == "simple" then
        data.map = {}
        for _, prototype in pairs(data[metadata.main_structure_name]) do
            data.map[prototype.name] = prototype.id
            -- Identifiers only make sense for complex structures
        end

    else  -- structure_type == "complex"
        data.map = {}
        for _, category_table in pairs(data[metadata.main_structure_name]) do
            data.map[category_table.name] = category_table.id

            category_table.map = {}
            for _, prototype in pairs(category_table[metadata.sub_structure_name]) do
                category_table.map[prototype.name] = prototype.id

                if add_identifiers then prototype.identifier = category_table.id .. "_" .. prototype.id end
            end
        end
    end
end

-- Cleans up and returns the completed data structure
function generator_util.data_structure.get()
    local structure = data
    data, metadata = nil, nil
    return structure
end


-- ** LOCAL UTIL **
-- Determines the actual amount of items that a recipe product or ingredient equates to
local function generate_formatted_item(base_item, type)
    local base_amount = 0
    if base_item.amount_max ~= nil and base_item.amount_min ~= nil then
        base_amount = (base_item.amount_max + base_item.amount_min) / 2
    else
        base_amount = base_item.amount
    end

    local probability, proddable_amount = (base_item.probability or 1), nil
    if type == "product" then
        proddable_amount = (base_amount - (base_item.catalyst_amount or 0)) * probability
    end

    -- This will probably screw up the main_product detection down the line
    if base_item.temperature ~= nil then
        base_item.name = base_item.name .. "-" .. base_item.temperature
    end

    return {
        name = base_item.name,
        type = base_item.type,
        amount = (base_amount * probability),
        proddable_amount = proddable_amount,
        temperature = base_item.temperature
    }
end

-- Combines items that occur more than once into one entry
local function combine_identical_products(item_list)
    local touched_items = {item = {}, fluid = {}, entity = {}}

    for index=#item_list, 1, -1 do
        local item = item_list[index]
        if item.temperature == nil then  -- don't care to deal with temperature crap
            local touched_item = touched_items[item.type][item.name]
            if touched_item ~= nil then
                touched_item.amount = touched_item.amount + item.amount
                touched_item.proddable_amount = touched_item.proddable_amount + item.proddable_amount

                -- Using the table.remove function to preserve array-format
                table.remove(item_list, index)
            else
                touched_items[item.type][item.name] = item
            end
        end
    end
end

-- Converts the given list to a list[type][name]-format
local function create_type_indexed_list(item_list)
    local indexed_list = {item = {}, fluid = {}, entity = {}}

    for index, item in pairs(item_list) do
        indexed_list[item.type][item.name] = {index = index, item = table.shallow_copy(item)}
    end

    return indexed_list
end

-- Determines the type_count for the given recipe prototype
local function determine_item_type_counts(indexed_items)
    return {
        items = table_size(indexed_items.item),
        fluids = table_size(indexed_items.fluid)
    }
end


-- ** TOP LEVEL **
-- Formats the products/ingredients of a recipe for more convenient use
function generator_util.format_recipe_products_and_ingredients(recipe_proto)
    local ingredients = {}
    for _, base_ingredient in pairs(recipe_proto.ingredients) do
        local formatted_ingredient = generate_formatted_item(base_ingredient, "ingredient")

        -- Productivity applies to all ingredients by default, some exceptions apply (ex. satellite)
        -- Also add proddable_amount so productivity bonus can be un-applied later in the model
        if base_ingredient.ignore_productivity then
            formatted_ingredient.ignore_productivity = true
            formatted_ingredient.proddable_amount = formatted_ingredient.amount
        end

        table.insert(ingredients, formatted_ingredient)
    end

    local indexed_ingredients = create_type_indexed_list(ingredients)
    recipe_proto.type_counts.ingredients = determine_item_type_counts(indexed_ingredients)


    local products = {}
    for _, base_product in pairs(recipe_proto.products) do
        local formatted_product = generate_formatted_item(base_product, "product")
        table.insert(products, formatted_product)

        -- Update the main product as well, if present
        if recipe_proto.main_product ~= nil and
          formatted_product.type == recipe_proto.main_product.type and
          formatted_product.name == recipe_proto.main_product.name then
            recipe_proto.main_product = formatted_product
        end
    end

    combine_identical_products(products)  -- only needed products, ingredients can't have duplicates
    local indexed_products = create_type_indexed_list(products)
    recipe_proto.type_counts.products = determine_item_type_counts(indexed_products)


    -- Reduce item amounts for items that are both an ingredient and a product
    for _, items_of_type in pairs(indexed_ingredients) do
        for _, ingredient in pairs(items_of_type) do
            local peer_product = indexed_products[ingredient.item.type][ingredient.item.name]

            if peer_product then
                local difference = ingredient.item.amount - peer_product.item.amount

                if difference < 0 then
                    ingredients[ingredient.index].amount = nil
                    products[peer_product.index].amount = -difference
                elseif difference > 0 then
                    ingredients[ingredient.index].amount = difference
                    products[peer_product.index].amount = nil
                else
                    ingredients[ingredient.index].amount = nil
                    products[peer_product.index].amount = nil
                end
            end
        end
    end

    -- Remove items after the fact so the iteration above doesn't break
    for _, item_table in pairs{ingredients, products} do
        for i = #item_table, 1, -1 do
            if item_table[i].amount == nil then table.remove(item_table, i) end
        end
    end


    recipe_proto.ingredients = ingredients
    recipe_proto.products = products
end


-- Determines whether this recipe is a recycling one or not
-- Compatible with: 'Industrial Revolution', 'Reverse Factory', 'Recycling Machines'
function generator_util.is_recycling_recipe(proto)
    local active_mods = {
        DIR = game.active_mods["IndustrialRevolution"],
        RF = game.active_mods["reverse-factory"],
        ZR = game.active_mods["ZRecycling"]
    }

    if active_mods.DIR and string.match(proto.name, "^scrap%-.*") then
        return true
    elseif active_mods.RF and string.match(proto.name, "^rf%-.*") then
        return true
    elseif active_mods.ZR and string.match(proto.name, "^dry411srev%-.*") then
        return true
    else
        return false
    end
end

-- Determines whether the given recipe is a barreling or stacking one
-- Compatible with: 'Deadlock's Stacking Beltboxes & Compact Loaders' and extensions of it
function generator_util.is_barreling_recipe(proto)
    if proto.subgroup.name == "empty-barrel" or proto.subgroup.name == "fill-barrel" then
        return true
    elseif string.match(proto.name, "^deadlock%-stacks%-.*") or string.match(proto.name, "^deadlock%-packrecipe%-.*")
      or string.match(proto.name, "^deadlock%-unpackrecipe%-.*") then
        return true
    else
        return false
    end
end

-- Determines whether this recipe is annoying or not
-- Compatible with: Klonan's Transport/Mining Drones
function generator_util.is_annoying_recipe(proto)
    if string.match(proto.name, "^request%-.*") or string.match(proto.name, "^mine%-.*") then
        return true
    else
        return false
    end
end


-- Finds a sprite for the given entity prototype
function generator_util.determine_entity_sprite(proto)
    local entity_sprite = "entity/" .. proto.name
    if game.is_valid_sprite_path(entity_sprite) then
        return entity_sprite
    end

    local items_to_place_this = proto.items_to_place_this
    if items_to_place_this and #items_to_place_this > 0 then
        local item_sprite = "item/" .. items_to_place_this[1].name
        if game.is_valid_sprite_path(item_sprite) then
            return item_sprite
        end
    end

    return nil
end


-- Returns nil if no effect is true, returns the effects otherwise
function generator_util.format_allowed_effects(allowed_effects)
    if allowed_effects == nil then return nil end
    for _, allowed in pairs(allowed_effects) do
        if allowed == true then return allowed_effects end
    end
    return nil  -- all effects are false
end


-- Returns the appropriate prototype name for the given item, incorporating temperature
function generator_util.format_temperature_name(item, name)
    -- Optionally two dashes to account for negative temperatures
    return (item.temperature) and string.gsub(name, "%-+[0-9]+$", "") or name
end

-- Returns the appropriate localised string for the given item, incorporating temperature
function generator_util.format_temperature_localised_name(item, proto)
    local temperature_tt = {"fp.two_word_title", item.temperature, {"fp.unit_celsius"}}
    return (item.temperature ~= nil) and {"fp.annotated_title", proto.localised_name,
      temperature_tt} or proto.localised_name
end


-- Adds the tooltip for the given recipe
function generator_util.add_recipe_tooltip(recipe)
    local tooltip = {"", recipe.localised_name}
    local current_table = tooltip
    local current_depth = 1

    -- Inserts strings in a way to minimize depth ('nestedness') of the localised string
    local function multi_insert(t)
        for _, e in pairs(t) do
            -- Nest localised string deeper if the limit of 20 elements per 'level' is reached
            if table_size(current_table) == 20 then
                -- If the depth is more than 8, the serpent deserializer will crash when loading the save
                -- because the resulting global table will be 'too complex'
                if current_depth == 8 then return tooltip end

                table.insert(current_table, {""})
                current_table = current_table[table_size(current_table)]
                current_depth = current_depth + 1
            end
            table.insert(current_table, e)
        end
    end

    if recipe.energy ~= nil then multi_insert{"\n  ", {"fp.name_value", {"fp.crafting_time"}, recipe.energy}} end
    for _, item_type in ipairs({"ingredients", "products"}) do
        local locale_key = (item_type == "ingredients") and "fp.pu_ingredient" or "fp.pu_product"
        multi_insert{"\n  ", {"fp.name_value", {locale_key, 2}, ""}}
        if #recipe[item_type] == 0 then
            multi_insert{"\n    ", {"fp.none"}}
        else
            for _, item in ipairs(recipe[item_type]) do
                local name = generator_util.format_temperature_name(item, item.name)
                local proto = game[item.type .. "_prototypes"][name]
                local localised_name = generator_util.format_temperature_localised_name(item, proto)
                multi_insert{("\n    " .. "[" .. item.type .. "=" .. name .. "] " .. item.amount .. "x "),
                  localised_name}
            end
        end
    end

    recipe.tooltip = tooltip
end

-- Adds the tooltip for the given item
function generator_util.add_item_tooltip(item)
    item.tooltip = item.localised_name
end


-- Generates a table imitating LuaGroup to avoid lua-cpp bridging
function generator_util.generate_group_table(group)
    return {name=group.name, localised_name=group.localised_name, order=group.order, valid=true}
end