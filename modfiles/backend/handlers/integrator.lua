integrator = {}

---@class IntegrationsTable
---@field recycling_recipes table<string, true>
---@field compacting_recipes table<string, true>
---@field machine_effects table<ForceIndex, table<string, IntegerModuleEffects>>
---@field overwrite_recipe_picker table<ForceIndex, table<string, boolean>>
---@field recipe_substitutions table<ForceIndex, table<string, string>>

-- ** LOCAL UTIL **
---@param table Any?
---@param name string
---@return AnyBasic?
local function get_table_value(table, name)
    if table ~= nil and type(table) == "table" then return table[name] end
end


-- ** RUNTIME INTEGRATIONS **

-- Signals that a mod's data changed, prompting FP to collect it again
---@param dataset Any?
local function invalidate(dataset)
    local version = get_table_value(dataset, "version")
    local integration = get_table_value(dataset, "integration")

    if version ~= 1 then return end
    if integration ~= nil and type(integration) == "string" then
        integrator.invalidate(integration)
    end
end

-- Push-based system, where mods can push integration data to FP at any time
remote.add_interface("fp-integration", {
    invalidate = invalidate
})


-- ** STATIC INTEGRATIONS **

---@alias Interfaces table<string, table<string, true>>

-- Pull-based system, where FP pulls in the integration data it needs at specific times
local interfaces = nil  ---@type Interfaces? local variable not used across scopes

local function seek_provided_interfaces()
    interfaces = {}

    local interface_list = remote.interfaces
    for mod, _ in pairs(script.active_mods) do
        local interface = "fp-integration-" .. mod
        local functions = interface_list[interface]
        if functions then interfaces[interface] = functions--[[@as table<string, true>]] end
    end
end


local handlers = {}  -- handlers for every kind of integration

---@param dataset Any
---@param storage_table table
function handlers.recycling_recipes(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local recipes = get_table_value(dataset, "recipes")

    if version == 1 and type(recipes) == "table" then
        for _, recipe_name in pairs(recipes) do
            storage_table[recipe_name] = true
        end
    end
end

---@param dataset Any
---@param storage_table table
function handlers.compacting_recipes(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local recipes = get_table_value(dataset, "recipes")

    if version == 1 and type(recipes) == "table" then
        for _, recipe_name in pairs(recipes) do
            storage_table[recipe_name] = true
        end
    end
end

---@param dataset Any
---@param storage_table table
function handlers.machine_effects(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local effects = get_table_value(dataset, "effects")

    if version == 1 and type(effects) == "table" then
        for machine_name, machine_effects in pairs(effects) do
            if type(machine_effects) == "table" then
                local formatted = {}
                -- Only actual effects are kept, so the table stays sparse like a machine's own
                for effect_name, value in pairs(machine_effects) do
                    if lib.effects.blank[effect_name] ~= nil and type(value) == "number" and value ~= 0 then
                        formatted[effect_name] = math.floor(value * MAGIC_NUMBERS.effect_precision + 1e-4)
                    end
                end
                storage_table[machine_name] = formatted
            end
        end
    end
end

---@param dataset Any
---@param storage_table table
function handlers.recipe_substitutions(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local substitutions = get_table_value(dataset, "substitutions")

    if version == 1 and type(substitutions) == "table" then
        for recipe_name, replacement_name in pairs(substitutions) do
            -- A recipe standing in for itself would just make it permanently unobtainable
            if type(replacement_name) == "string" and replacement_name ~= recipe_name then
                storage_table[recipe_name] = replacement_name
            end
        end
    end
end

---@param dataset Any
---@param storage_table table
function handlers.overwrite_recipe_picker(dataset, storage_table)
    local version = get_table_value(dataset, "version")
    local recipes = get_table_value(dataset, "recipes")

    if version == 1 and type(recipes) == "table" then
        for recipe_name, value in pairs(recipes) do
            if type(value) == "boolean" then storage_table[recipe_name] = value end
        end
    end
end


---@param name string
---@param force_index ForceIndex?
---@return table
local function call_providers(name, force_index)
    local collected = {}
    for interface, functions in pairs(interfaces--[[@cast -nil]]) do
        if functions[name] then
            ---@diagnostic disable-next-line: param-type-mismatch
            local dataset = remote.call(interface, name, force_index)  ---@as Any
            handlers[name]--[[@cast -nil]](dataset, collected)
        end
    end
    return collected
end

-- Integrations that are collected once per force, instead of a single time
local force_scoped = {
    machine_effects = true,
    recipe_substitutions = true,
    overwrite_recipe_picker = true
}

---@param name string
function integrator.collect(name)
    if interfaces == nil then seek_provided_interfaces() end

    local collected = {}  ---@type table
    if force_scoped[name] then
        for _, force in pairs(game.forces) do
            collected[force.index] = call_providers(name, force.index)
        end
    else
        collected = call_providers(name, nil)
    end

    storage.integrations[name] = collected
end

function integrator.initialize()
    integrator.collect("machine_effects")
    integrator.collect("recipe_substitutions")
    integrator.collect("overwrite_recipe_picker")
end


-- Collects the named integration again, and runs appropriate updates if necessary
---@param integration string
function integrator.invalidate(integration)
    integrator.collect(integration)

    if integration == "machine_effects" then
        local offset = 1
        for _, player in pairs(game.players) do
            local realm = lib.globals.player_table(player).realm
            realm:schedule_solver_updates((game.tick + offset), player)
            offset = offset + 2
        end

    elseif integration == "recipe_substitutions" then
        local running_tick = game.tick + 1  ---@type MapTick?
        for _, player in pairs(game.players) do
            local realm = lib.globals.player_table(player).realm
            running_tick = realm:apply_recipe_substitution(player, running_tick)
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
