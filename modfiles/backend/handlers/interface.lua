interface = {}

---@class PackedSimpleItem
---@field class "SimpleItem"
---@field proto FPPackedPrototype

-- Helper functions to pack up Floor or Line products, byproducts and ingredients
---@param items SimpleItem[]
---@return FPPackedPrototype[]
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
---@param player_index PlayerIndex
---@return PackedFactory?
local function export_current_factory(player_index)
    local player = game.get_player(player_index)
    if not player then return nil end

    local player_table = lib.globals.player_table(player)
    if not player_table then return nil end

    local current_factory = lib.context.get(player, "Factory")  ---@as Factory
    if not current_factory then return nil end

    return current_factory:pack(true)
end

---@param player_index PlayerIndex
---@return table?
local function export_preferences(player_index)
    local player = game.get_player(player_index)
    if not player then return nil end

    local player_table = lib.globals.player_table(player)
    if not player_table then return nil end

    return lib.unpack_export_string(lib.preferences.export(player))
end

---@param player_index PlayerIndex
---@param export_table table
---@return string | true | nil
local function import_preferences(player_index, export_table)
    local player = game.get_player(player_index)
    if not player then return nil end

    local player_table = lib.globals.player_table(player)
    if not player_table then return nil end

    local export_string = lib.pack_export_string(export_table)
    local error = lib.preferences.import(player, export_string)
    if error then
        return error
    else
        -- This rebuilds the main interface implicitly
        GLOBAL_HANDLERS["shrinkwrap_interface"]{player_index=player.index}
        return true
    end
end

remote.add_interface("fp-interface", {
    export_current_factory = export_current_factory,
    export_preferences = export_preferences,
    import_preferences = import_preferences
})
