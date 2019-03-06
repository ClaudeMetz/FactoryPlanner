data_util = {}

-- Returns given datasets' id's in order by position (-> [gui_position] = id)
function data_util.order_by_position(datasets)
    local ordered_table = {}
    for id, dataset in pairs(datasets) do
        ordered_table[dataset.gui_position] = id
    end
    return ordered_table
end

-- Shifts every position after the deleted one down by 1
function data_util.update_positions(datasets, deleted_position)
    for _, dataset in pairs(datasets) do
        if dataset.gui_position > deleted_position then
            dataset.gui_position = dataset.gui_position - 1
        end
    end
end

-- Returns the id of the dataset that has the given position in the given table
function data_util.get_id_by_position(datasets, gui_position)
    if gui_position == 0 then return 0 end
    for id, dataset in pairs(datasets) do
        if dataset.gui_position == gui_position then
            return id
        end
    end
end

-- Shifts position of given dataset (indicated by main_id) in the given direction
function data_util.shift_position(datasets, main_id, direction, dataset_count)
    local main_dataset = datasets[main_id]
    local main_gui_position = main_dataset.gui_position

    -- Doesn't shift if outer elements are being shifted further outward
    if (main_gui_position == 1 and direction == "negative") or
      (main_gui_position == dataset_count and direction == "positive") then 
        return 
    end

    local second_gui_position
    if direction == "positive" then
        second_gui_position = main_gui_position + 1
    else  -- direction == "negative"
        second_gui_position = main_gui_position - 1
    end
    local second_id = data_util.get_id_by_position(datasets, second_gui_position)
    local second_dataset = datasets[second_id]

    main_dataset.gui_position = second_gui_position
    second_dataset.gui_position = main_gui_position
end



-- Returns the names of the recipes that shouldn't be included
function data_util.generate_undesirable_recipes()
    local undesirables = 
    {
        ["small-plane"] = false,
        ["electric-energy-interface"] = false,
        ["railgun"] = false,
        ["railgun-dart"] = false,
        ["player-port"] = false
    }

    -- Leaves loaders in if LoaderRedux is loaded
    if game.active_mods["LoaderRedux"] == nil then
        undesirables["loader"] = false
        undesirables["fast-loader"] = false
        undesirables["express-loader"] = false
    end

    return undesirables
end

-- Returns all standard recipes + custom mining recipes and space science recipe
function data_util.generate_all_recipes()
    local recipes = {}

    -- Adding all standard recipes
    for name, recipe in pairs(game.forces.player.recipes) do recipes[name] = recipe end

    -- Adding all (solid) mining recipes
    -- (Inspired by https://github.com/npo6ka/FNEI/commit/58fef0cd4bd6d71a60b9431cb6fa4d96d2248c76)
    local function base_recipe()
        return {
            enabled = true,
            hidden = false,
            energy = nil,
            group = {name="intermediate_products", order="c"},
            subgroup = {name="mining", order="z"},
        }
    end

    for _, proto in pairs(game.entity_prototypes) do
        -- Adds all mining recipes. Only supports solids for now.
        if proto.mineable_properties and proto.resource_category and 
          proto.mineable_properties.products[1].type ~= "fluid" then
            local recipe = base_recipe()
            recipe.name = "impostor-" .. proto.name
            recipe.localised_name = proto.localised_name
            recipe.category = proto.resource_category
            recipe.ingredients = {{type="entity", name=proto.name, amount=1}}
            local products = proto.mineable_properties.products
            recipe.products = products
            if #products == 1 then recipe.item_type = products[1].type end
            recipe.order = proto.order

            if proto.mineable_properties.required_fluid then
                table.insert(recipe.ingredients, {
                    type = "fluid",
                    name = proto.mineable_properties.required_fluid,
                    amount = proto.mineable_properties.fluid_amount
                })
            end

            recipes[recipe.name] = recipe
        end

        -- Adds unconditional extraction, like water pumps. Not sure if necessary/useful yet.
        --[[ if proto.fluid then
            local recipe = base_recipe()
            recipe.name = "impostor-" .. proto.fluid.name
            recipe.localised_name = proto.fluid.localised_name
            recipe.category = proto.resource_category
            recipe.ingredients = nil
            recipe.products = {{ type = 'fluid', name = proto.fluid.name, amount = 1 }}
            recipe.item_type = "fluid"
            recipe.order = proto.order

            recipes[recipe.name] = recipe
        end ]]
    end
    
    -- Adding convenient space science recipe
    recipes["fp-space-science-pack"] = {
        name = "fp-space-science-pack",
        localised_name = {"item-name.space-science-pack"},  -- official locale
        category = "rocket-building",
        enabled = false,
        hidden = false,
        energy = nil,
        group = {name="intermediate_products", order="c"},
        subgroup = {name="science-pack", order="g"},
        order = "k[fp-space-science-pack]",
        ingredients = {
            {type="item", name="rocket-part", amount=100},
            {type="item", name="satellite", amount=1}
        },
        products = {{type="item", name="space-science-pack", amount=1000}}
    }
 
    return recipes
end


-- Generates a table containing all machines for all categories
function data_util.generate_all_machines()
    local categories = {}
    
    local function generate_category_entry(category, proto)
        log(category)
        if categories[category] == nil then
            categories[category] = {machines = {}, order = {}}
        end
        local data = categories[category]
        
        table.insert(data["order"], proto.name)
        local machine = {
            name = proto.name,
            localised_name = proto.localised_name,
            position = #data["order"]
        }
        data["machines"][proto.name] = machine
    end

    for _, proto in pairs(game.entity_prototypes) do
        if proto.crafting_categories and proto.name ~= "player" then
            for category, enabled in pairs(proto.crafting_categories) do
                if enabled then
                    generate_category_entry(category, proto)
                end
            end

        -- Adds mining machines
        elseif proto.resource_categories then
            for category, enabled in pairs(proto.resource_categories) do
                -- Only supports solid mining recipes for now
                 if enabled and category ~= "basic-fluid" then
                    generate_category_entry(category, proto)
                    -- The following makes the complex-solid machines show up after the basic ones
                    if category == "basic-solid" then categories["complex-solid"] = {} end
                end
            end
        end
    end

    -- Add separate category for mining with fluids that avoids the burner-miner
    -- Does not handle the case of multiple different kinds of burner-miners
    categories["complex-solid"] = ui_util.copy_table(categories["basic-solid"])
    categories["complex-solid"].machines["burner-mining-drill"] = nil
    table.remove(categories["complex-solid"].order, 1)

    return categories
end

-- Updates default machines for the given player, restoring previous settings
function data_util.update_default_machines(player)
    local old_defaults = global.players[player.index].default_machines
    local new_defaults = {}

    for category, data in pairs(global.all_machines) do
        if old_defaults[category] ~= nil and data.machines[old_defaults[category]] ~= nil then
            new_defaults[category] = old_defaults[category]
        else
            new_defaults[category] = data.machines[data.order[1]].name
        end
    end
    
    global.players[player.index].default_machines = new_defaults
end

-- Returns the default machine for the given category
function data_util.get_default_machine(player, category)
    local defaults = global.players[player.index].default_machines
    return global.all_machines[category].machines[defaults[category]]
end

-- Changes the preferred machine for the given category
function data_util.set_default_machine(player, category, name)
    global.players[player.index].default_machines[category] = name
end