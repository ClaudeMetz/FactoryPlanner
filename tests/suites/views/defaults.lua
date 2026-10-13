---@diagnostic disable

-- Restore player defaults after each check, including when it fails
local function with_defaults(check)
    local player = game.players[1]
    local player_table = lib.globals.player_table(player)
    local previous = player_table.preferences.default_prototypes
    player_table.preferences.default_prototypes = {
        pumps = defaults.get_fallback("pumps"),
        wagons = defaults.get_fallback("wagons")
    }
    local ok, message = xpcall(check, debug.traceback, player, player_table)
    player_table.preferences.default_prototypes = previous
    assert(ok, message)
end

return {
    lookup = {check=function()
        with_defaults(function(player, player_table)
            local saved = player_table.preferences.default_prototypes
            local pump = defaults.get(player, "pumps")
            assert(defaults.get_optional(player, "pumps") == pump, "A usable default must be returned unchanged")
            local cargo = prototyper.util.find("wagons", nil, "cargo-wagon")
            local cargo_default = defaults.get(player, "wagons", cargo.id)
            assert(defaults.get_optional(player, "wagons", "cargo-wagon") == cargo_default)
            assert(defaults.get_optional(player, "wagons", cargo.id) == cargo_default)
            assert(defaults.get_optional(player, "wagons", "missing-category") == nil)
            assert(defaults.get_optional(player, "wagons", #storage.prototypes.wagons + 1) == nil)
            assert(defaults.get_optional(player, "wagons") == nil, "A category collection is not a prototype default")

            saved.pumps = {}
            saved.wagons[cargo.id] = {}
            assert(defaults.get_optional(player, "pumps") == nil)
            assert(defaults.get_optional(player, "wagons", cargo.id) == nil)
            assert(defaults.get(player, "pumps") == saved.pumps, "Existing callers must still be able to read empty entries")
            saved.wagons[cargo.id] = nil
            assert(defaults.get_optional(player, "wagons", "cargo-wagon") == nil)
        end)
    end}
}
