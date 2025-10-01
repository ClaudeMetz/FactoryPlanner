---@return [LuaEntityPrototype]
local function entities()

    return {{
    }}
end

---@return [LuaRecipePrototype]
local function recipes()

    return {{
    }}
end


local function modifiers()

    return {
        entity = {},
        recipe = {}
    }
end


remote.add_interface("integration-factoryplanner", {
    entity = entities,
    recipe = recipes,
    modifiers = modifiers,
    raises_event = function() return true end
})
