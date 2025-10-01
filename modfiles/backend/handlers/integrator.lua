local integrator = {}

local interfaces = nil  -- local variable not used across scopes

local function collect_interfaces()
    interfaces = {}

    local interface_list = remote.interfaces
    for mod, _ in pairs(script.active_mods) do
        local interface = "integration-" .. mod
        local functions = interface_list[interface]
        if functions then interfaces[interface] = functions end
    end
end


-- Maps from integration types to internal generator types
local type_to_internal = {
    entity = {"machines"},
    recipe = {"recipes"}
}

function integrator.collect_prototypes()
    if interfaces == nil then collect_interfaces() end

    local prototypes = {}
    for interface, functions in pairs(interfaces) do
        for prototype_type, _ in pairs(type_to_internal) do
            if functions[prototype_type] then
                local data = remote.call(interface, prototype_type)
                for _, internal_type in pairs(type_to_internal[prototype_type]) do
                    prototypes[internal_type] = prototypes[internal_type] or {}
                    ftable.shallow_merge{prototypes[internal_type], data}
                end
            end
        end
    end
    return prototypes
end


function integrator.collect_modifiers()
    if interfaces == nil then collect_interfaces() end

    local modifiers = {}
    for interface, functions in pairs(interfaces) do
        if functions["modifiers"] then
            local modifier_list = remote.call(interface, "modifiers")
            for prototype_type, _ in pairs(type_to_internal) do
                if modifier_list[prototype_type] then
                    for _, internal_type in pairs(type_to_internal[prototype_type]) do
                        modifiers[internal_type] = modifiers[internal_type] or {}
                        ftable.shallow_merge{modifiers[internal_type], modifier_list[prototype_type]}
                    end
                end
            end
        end
    end
    return modifiers
end


local function handle_integration_action(data)
    if data.action == "enable_recipe" then
        if data.version == 1 then

        end
    end
end

function integrator.register_events()
    if interfaces == nil then collect_interfaces() end

    for interface, functions in pairs(interfaces) do
        if functions.raises_event and remote.call(interface, "raises_event") == true then
            script.on_event(interface .. "-action", handle_integration_action)
        end
    end
end


return integrator



-- ** AUX STUFF **

-- event proto
data:extend {
    {
        type = "custom-event",
        name = "integration-factoryplanner-action"
    }
}

-- raised as
script.raise_event("integration-factoryplanner-action", {
    version = 1,
    action = "enable_recipe"
})
