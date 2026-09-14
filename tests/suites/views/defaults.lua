---@diagnostic disable

-- Replace only the pump/wagon catalogs to model configuration changes, restoring
-- both the catalogs and player defaults even if a check fails.
local function with_defaults(check)
    local player = game.players[1]
    local player_table = lib.globals.player_table(player)
    local previous = player_table.preferences.default_prototypes
    local pumps, wagons = storage.prototypes.pumps, storage.prototypes.wagons
    local pump_map, wagon_map = PROTOTYPE_MAPS.pumps, PROTOTYPE_MAPS.wagons
    player_table.preferences.default_prototypes = {
        pumps = defaults.get_fallback("pumps"),
        wagons = defaults.get_fallback("wagons")
    }
    local ok, message = xpcall(check, debug.traceback, player, player_table)
    player_table.preferences.default_prototypes = previous
    storage.prototypes.pumps, storage.prototypes.wagons = pumps, wagons
    PROTOTYPE_MAPS.pumps, PROTOTYPE_MAPS.wagons = pump_map, wagon_map
    assert(ok, message)
end

local function set_wagons(entries)
    local indexed, mapped = {}, {}
    for id, entry in ipairs(entries) do
        indexed[id] = {id=id, name=entry.name, members=entry.proto and {entry.proto} or {}}
        mapped[entry.name] = {id=id, name=entry.name,
            members=entry.proto and {[entry.proto.name]=entry.proto} or {}}
    end
    storage.prototypes.wagons, PROTOTYPE_MAPS.wagons = indexed, mapped
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
    end},

    migration = {check=function()
        with_defaults(function(player, player_table)
            local pumps, pump_map = storage.prototypes.pumps, PROTOTYPE_MAPS.pumps
            local pump = defaults.get_optional(player, "pumps")
            local cargo = defaults.get_optional(player, "wagons", "cargo-wagon")
            local fluid = defaults.get_optional(player, "wagons", "fluid-wagon")
            -- Metadata makes it possible to distinguish preservation from resetting to fallback.
            cargo.modules, cargo.beacon_amount = {}, 7
            fluid.modules, fluid.beacon_amount = {}, 9

            storage.prototypes.pumps, PROTOTYPE_MAPS.pumps = {}, {}
            set_wagons{{name="fluid-wagon", proto=fluid.proto}, {name="cargo-wagon"}}
            defaults.migrate(player_table)
            assert(defaults.get_optional(player, "pumps") == nil)
            assert(defaults.get_optional(player, "wagons", "cargo-wagon") == nil)
            local kept_fluid = defaults.get_optional(player, "wagons", "fluid-wagon")
            assert(kept_fluid.proto == fluid.proto and kept_fluid.beacon_amount == 9,
                "Changing category IDs must preserve the remaining default by category name")

            -- Neither empty uncategorized entries nor empty category entries may crash on reload.
            defaults.migrate(player_table)
            storage.prototypes.pumps, PROTOTYPE_MAPS.pumps = pumps, pump_map
            set_wagons{{name="cargo-wagon", proto=cargo.proto}, {name="fluid-wagon", proto=fluid.proto}}
            defaults.migrate(player_table)
            local restored_pump = defaults.get_optional(player, "pumps")
            local restored_cargo = defaults.get_optional(player, "wagons", "cargo-wagon")
            assert(restored_pump.proto == pump.proto and restored_pump.quality == pump.quality)
            assert(restored_cargo.proto == cargo.proto and restored_cargo.quality == cargo.quality)
            assert(restored_cargo.beacon_amount == nil, "A returning category must use its fallback, not another category's saved settings")
            assert(defaults.get_optional(player, "wagons", "fluid-wagon").beacon_amount == 9)

            -- Also exercise removing a category entirely, as happens when hidden wagons are filtered out.
            set_wagons{{name="cargo-wagon", proto=cargo.proto}}
            defaults.migrate(player_table)
            assert(defaults.get_optional(player, "wagons", "fluid-wagon") == nil)
            set_wagons{{name="fluid-wagon", proto=fluid.proto}, {name="cargo-wagon", proto=cargo.proto}}
            defaults.migrate(player_table)
            assert(defaults.get_optional(player, "wagons", "fluid-wagon").proto == fluid.proto)
            assert(defaults.get_optional(player, "wagons", "cargo-wagon").proto == cargo.proto)
        end)
    end}
}
