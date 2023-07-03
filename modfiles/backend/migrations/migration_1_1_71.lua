---@diagnostic disable

-- This directly uses class methods, which is inherently fragile, but there's no
-- good way around it. The minimum migration version will need to be moved past
-- this is there ever is a large change related to this again.
local District = require("backend.data.District")
local Factory = require("backend.data.Factory")

local migration = {}

function migration.global()
    global.mod_version = nil
    global.current_ID = 0
end

function migration.player_table(player_table)
    player_table.district = District.init()
    player_table.context = {
        object_id = 2,  -- set to first floor preemptively
        cache = {main = nil, archive = nil, factory = {}}
    }

    for _, factory_name in pairs({"factory", "archive"}) do
        for _, subfactory in pairs(player_table[factory_name].Subfactory.datasets) do
            local factory = Factory.init(subfactory.name, subfactory.timescale)
            factory.archived = (factory_name == "archive")
            factory.mining_productivity = subfactory.mining_productivity
            factory.matrix_free_items = subfactory.matrix_free_items
            factory.blueprints = subfactory.blueprints
            factory.notes = subfactory.notes

            factory.tick_of_deletion = subfactory.tick_of_deletion
            factory.item_request_proxy = subfactory.item_request_proxy
            factory.last_valid_modset = subfactory.last_valid_modset

            for _, product in pairs(subfactory.Product.datasets) do
                -- TODO product stuff
            end
            -- TODO floor stuff

            player_table.district:insert(factory)
        end
    end

    player_table.index = nil
    player_table.mod_version = nil
    player_table.factory = nil
    player_table.archive = nil
end

function migration.packed_subfactory(packed_subfactory)
    -- Most things just carry over as-is here, only the structure changes

    packed_subfactory.products = packed_subfactory.Product.objects
    -- TODO Floor stuff
end

return migration
