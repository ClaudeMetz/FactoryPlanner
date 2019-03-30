data_util = {
    context = {},
    machines = {}
}

-- **** CONTEXT ****
-- Creates a blank context referencing which part of the Factory is currently displayed
function data_util.context.create()
    return {
        subfactory = nil,
        floor = nil        
    }
end

-- Updates the context to match the newly selected subfactory
function data_util.context.set_subfactory(player, subfactory)
    local context = global.players[player.index].context
    context.subfactory = subfactory
    context.floor = (subfactory ~= nil) and subfactory.selected_floor or nil
end


-- **** MACHINES ****
-- Updates default machines for the given player, restoring previous settings
function data_util.machines.update_default(player)
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

-- Changes the preferred machine for the given category
function data_util.machines.set_default(player, category, name)
    global.players[player.index].default_machines[category] = name
end

-- Returns the default machine for the given category
function data_util.machines.get_default(player, category)
    local defaults = global.players[player.index].default_machines
    return global.all_machines[category].machines[defaults[category]]
end