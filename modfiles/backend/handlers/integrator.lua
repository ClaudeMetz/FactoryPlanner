integrator = {}

---@class IntegrationsTable
---@field runtime RuntimeIntegrations

-- ** LOCAL UTIL **
local function get_table_value(table, name)
    if table ~= nil and type(table) == "table" then return table[name] end
end


-- Listening-based system, where mods can change integration data for FP at any time

---@class RuntimeIntegrations
---@field overwrite_recipe_picker { [string]: boolean }

local function get_integration_table(name)
    storage.integrations[name] = storage.integrations[name] or {}
    return storage.integrations[name]
end

local function overwrite_recipe_picker(dataset)
    local version = get_table_value(dataset, "version")
    local values = get_table_value(dataset, "values")

    if version == 1 and type(values) == "table" then
        local overwrite_recipe_picker = get_integration_table("overwrite_recipe_picker")

        for recipe_name, value in pairs(values) do
            overwrite_recipe_picker[recipe_name] = value  -- nil equals removal
        end
    end
end

remote.add_interface("fp-integration", {
    overwrite_recipe_picker = overwrite_recipe_picker
})



-- Collection-based system, where FP pulls in the integration data it needs at a specific time
--[[ unused for now, code as an example

---@class PrototypeIntegrations
---@field force_enable { [string]: { string } }

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

function handlers.prototypes(dataset)
    local storage_table = storage.integrations.prototypes

    local force_enable = get_table_value(dataset, "force_enable")
    if force_enable then
        local version = get_table_value(force_enable, "version")
        local values = get_table_value(force_enable, "values")

        if version == 1 and type(values) == "table" then
            local integrations = {}
            for type, name in pairs(values) do
                integrations[type] = integrations[type] or {}
                integrations[type][name] = true
            end
            storage_table.force_enable = integrations
        end
    end
end


function integrator.collect(name)
    if interfaces == nil then seek_provided_interfaces() end

    storage.integrations[name] = {}

    for interface, functions in pairs(interfaces) do
        if functions[name] then
            local dataset = remote.call(interface, name)
            handlers[name](dataset)  -- process provided integration
        end
    end
end


-- Example interface for integrating mods to use
remote.add_interface("fp-integration-factoryplanner", {
    prototypes = (function()
        return {
            force_enable = {
                version = 1,
                values = {
                    recipe = "iron-gear"
                }
            }
        }
    end)
})
]]
