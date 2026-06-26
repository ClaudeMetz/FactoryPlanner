integrator = {}

---@class IntegrationsTable
---@field overwrite_recipe_picker { [string]: boolean }
---@field recycling_recipes { patterns: string[], names: string[] }

-- ** LOCAL UTIL **
local function get_integration_table(name)
    storage.integrations[name] = storage.integrations[name] or {}
    return storage.integrations[name]
end

local function get_table_value(table, name)
    if table ~= nil and type(table) == "table" then return table[name] end
end


-- ** RUNTIME INTEGRATIONS **

local function overwrite_recipe_picker(dataset)
    local version = get_table_value(dataset, "version")
    local recipes = get_table_value(dataset, "recipes")

    if version == 1 and type(recipes) == "table" then
        local overwrite_recipe_picker = get_integration_table("overwrite_recipe_picker")

        for recipe_name, value in pairs(recipes) do
            overwrite_recipe_picker[recipe_name] = value  -- nil equals removal
        end
    end
end

-- Push-based system, where mods can push integration data to FP at any time
remote.add_interface("fp-integration", {
    overwrite_recipe_picker = overwrite_recipe_picker
})


-- ** STATIC INTEGRATIONS **

-- Pull-based system, where FP pulls in the integration data it needs at specific times
local interfaces = nil  -- local variable not used across scopes

local function seek_provided_interfaces()
    interfaces = {}

    local interface_list = remote.interfaces
    for mod, _ in pairs(script.active_mods) do
        local interface = "fp-integration-" .. mod
        local functions = interface_list[interface]
        if functions then interfaces[interface] = functions end
    end
end


local handlers = {}  -- handlers for every kind of integration

function handlers.recycling_recipes(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local recipes = get_table_value(dataset, "recipes")

    if version == 1 and type(recipes) == "table" then
        for _, recipe_name in pairs(recipes) do
            storage_table[recipe_name] = true
        end
    end
end

function handlers.compacting_recipes(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local recipes = get_table_value(dataset, "recipes")

    if version == 1 and type(recipes) == "table" then
        for _, recipe_name in pairs(recipes) do
            storage_table[recipe_name] = true
        end
    end
end


function integrator.collect(name)
    if interfaces == nil then seek_provided_interfaces() end

    local storage_table = get_integration_table(name)
    for interface, functions in pairs(interfaces) do
        if functions[name] then
            local dataset = remote.call(interface, name)
            handlers[name](dataset, storage_table)
        end
    end
end


-- Adds vanilla recycling and compacting recipes through the open API
remote.add_interface("fp-integration-factoryplanner", {
    recycling_recipes = (function()
        local recycling_recipes = {}
        for _, proto in pairs(prototypes.recipe) do
            if string.match(proto.name, ".*%-recycling$") and proto.hidden then
                table.insert(recycling_recipes, proto.name)
            end
        end
        return {version = 1, recipes = recycling_recipes}
    end),

    compacting_recipes = (function()
        local compacting_recipes = {}
        for _, proto in pairs(prototypes.recipe) do
            for _, pattern in pairs({"^fill%-.*", "^empty%-.*"}) do
                if string.match(proto.name, pattern) then
                    for _, product in pairs(proto.products) do
                        if product.name == "barrel" then
                            table.insert(compacting_recipes, proto.name)
                            goto matched
                        end
                    end
                    for _, ingredient in pairs(proto.ingredients) do
                        if ingredient.name == "barrel" then
                            table.insert(compacting_recipes, proto.name)
                            goto matched
                        end
                    end
                end
            end
            ::matched::
        end
        return {version = 1, recipes = compacting_recipes}
    end)
})
