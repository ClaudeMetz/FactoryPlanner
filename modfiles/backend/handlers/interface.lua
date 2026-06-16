interface = {}

-- Helper functions to pack up Floor or Line products, byproducts and ingredients
function interface.pack_items(items)
    local packed_items = {}

    for _, item in pairs(items) do
        table.insert(packed_items, {
            proto = prototyper.util.simplify_prototype(item.proto, "type"),
            amount = item.amount
        })
    end

    return packed_items
end


-- ** MAIN **
local function export_current_factory(player_index)
    local player = game.get_player(player_index)
    if not player then return nil end

    local player_table = util.globals.player_table(player)
    if not player_table then return nil end

    local current_factory = util.context.get(player, "Factory")
    if not current_factory then return nil end

    return current_factory:pack(true)
end

remote.add_interface("fp-interface", {
    export_current_factory = export_current_factory
})
