---@diagnostic disable
local helpers = require("helpers")
local Realm = script and require("__factoryplanner__.backend.data.Realm")

-- Each case owns its player state, objects and GUI; prototypes remain configuration-wide
local fixtures = {}

function fixtures.run(context, check)
    local cleanups = {}
    local function defer(cleanup) cleanups[#cleanups + 1] = cleanup end
    local ok, message = xpcall(function()
        local player = game.players[1]
        local previous = lib.globals.player_table(player)
        local first_id = storage.next_object_ID
        context.player, context.defer = player, defer
        context.set = function(object, key, value)
            local old = object[key]
            defer(function() object[key] = old end)
            object[key] = value
        end

        local roots, existing = {player.gui.screen, player.gui.left, player.gui.center, player.gui.top}, {}
        for _, root in ipairs(roots) do
            for _, child in pairs(root.children) do existing[child.index] = true end
        end
        local old_ticks = {}
        for tick in pairs(storage.nth_tick_events) do old_ticks[tick] = true end
        defer(function()
            for tick in pairs(storage.nth_tick_events) do
                if not old_ticks[tick] then lib.nth_tick.cancel(tick) end
            end
        end)
        context.set(game, "tick_paused", game.tick_paused)
        local old_opened = player.opened
        defer(function() player.opened = old_opened end)
        local cursor = game.create_inventory(1)
        defer(function() cursor.destroy() end)
        cursor[1].swap_stack(player.cursor_stack)
        defer(function()
            player.cursor_stack.clear()
            cursor[1].swap_stack(player.cursor_stack)
        end)
        defer(function()
            for _, root in ipairs(roots) do
                for _, child in pairs(root.children) do
                    if not existing[child.index] then child.destroy() end
                end
            end
        end)
        defer(function()
            -- Includes detached objects and clones, not just objects still in the realm
            for id = first_id, storage.next_object_ID - 1 do
                local object = OBJECT_INDEX[id]
                if object and object.class == "Factory" then
                    for _, tick in pairs{object.tick_of_deletion, object.tick_of_solver_update} do
                        lib.nth_tick.cancel(tick)
                    end
                    if object.blueprints_inventory.valid then object.blueprints_inventory.destroy() end
                end
                OBJECT_INDEX[id] = nil
            end
        end)
        defer(function() storage.players[player.index] = previous end)

        local state = lib.flib.shallow_copy(previous)
        state.preferences = lib.flib.deep_copy(previous.preferences)
        state.clipboard = nil
        state.ui_state = {main_elements={}, compact_elements={}, calculator_elements={}, tooltips={},
            compact_view=false, districts_view=false}
        state.realm = Realm.init()
        lib.context.init(state)
        storage.players[player.index] = state
        lib.context.set(player, state.realm.first)
        check(context)
    end, debug.traceback)

    local errors = {}
    for index = #cleanups, 1, -1 do
        local cleaned, error = xpcall(cleanups[index], debug.traceback)
        if not cleaned then errors[#errors + 1] = error end
    end
    context.player, context.defer, context.set = nil, nil, nil
    if #errors > 0 then
        message = (ok and "" or message .. "\n") .. "Fixture cleanup failed:\n" .. table.concat(errors, "\n")
        return false, message, false
    end
    return ok, message, true
end

function fixtures.factory(context, name, solver_name)
    local player = context.player
    local district = context.classes.District.init()
    lib.globals.player_table(player).realm:insert(district)
    local factory = context.classes.Factory.init(name, solver_name or "sequential")
    district:insert(factory)
    lib.context.set(player, factory)
    return factory
end

function fixtures.line(context, floor, recipe_name, machine)
    local line = context.classes.Line.init(prototyper.util.find("recipes", recipe_name))
    floor:insert(line)
    if machine then line:change_machine_to_proto(context.player, machine) end
    return line
end

function fixtures.target(context, factory, name, category, definition, item_type)
    local target = context.classes.FactoryItem.init(prototyper.util.find("items", name, item_type or "item"), category)
    target.definition = definition or {type="amount", amount=0}
    factory:insert(target)
    return target
end

-- Target objects
function fixtures.target_item(context)
    local factory = fixtures.factory(context, "factory-item-test")
    local item = fixtures.target(context, factory, "iron-plate", "product")
    return context.player, factory, item
end

-- Target definitions
function fixtures.definition(kind)
    if kind == "amount" then return {type="amount", amount=10} end
    if kind == "belts" then return {type="belts", belt_count=1, belt_stack=1,
        belt_proto=prototyper.util.find("belts", "transport-belt")} end
    assert(kind == "machines", "Unknown target definition: " .. tostring(kind))
    return {type="machines", machine_count=5}
end

-- Item views
function fixtures.view(context)
    local player = context.player
    local state = lib.globals.player_table(player)
    state.preferences.item_views = item_views.default_preferences()
    item_views.rebuild_data(player)
    return player, state
end

-- Input targets
function fixtures.input(context)
    local function factory(solver_name)
        return fixtures.factory(context, "input-targets", solver_name)
    end
    local function line(floor, name)
        return fixtures.line(context, floor, "test-input-target-" .. name,
            helpers.find_machine("test-input-target-machine"))
    end
    local function target(factory, name, category, amount, item_type)
        return fixtures.target(context, factory, name, category, {type="amount", amount=amount}, item_type)
    end
    local function find(items, name)
        for _, item in pairs(items) do if item.proto.name == name then return item end end
    end
    return {factory=factory, line=line, target=target, find=find}
end

-- Machine targets
function fixtures.machine(context)
    local classes, player = context.classes, context.player
    local factory = fixtures.factory(context, "machine-requirements")
    local top = factory.top_floor

    local function add_line(floor, recipe_name)
        local line = classes.Line.init(prototyper.util.find("recipes", recipe_name or "test-machine-requirements"))
        floor:insert(line)
        line:change_machine_to_proto(player, prototyper.util.find("machines", "assembling-machine-2", "crafting"))
        return line
    end
    local function add_product(proto, count)
        local product = classes.FactoryItem.init(proto, "product")
        product.definition = {type="machines", machine_count=count}
        factory:insert(product)
        return product
    end
    local first, second = add_line(top), add_line(top)
    local iron = add_product(prototyper.util.find("items", "iron-plate", "item"), 3.5)
    local copper = add_product(prototyper.util.find("items", "copper-plate", "item"), 8)
    return {player=player, factory=factory, top=top, add_line=add_line, add_product=add_product,
        first=first, second=second, iron=iron, copper=copper}
end

-- Sequential chains
do
    -- Runs a hand-computable setup through the full solver stack: factory objects built
    -- the way the GUI would build them, solved for real, results checked against
    -- pen-and-paper numbers.
    --
    -- Setup keeps its prototypes deliberately plain, with every number chosen so the
    -- expected results can be worked out by hand:
    --
    --   2 test-solver-ore -> 1 test-solver-plate (0.5s) -> half of 2 per test-solver-gear (1s)
    --
    -- The machine crafts at speed 1 and draws a flat 100kW with no drain, so a line of N
    -- machines consumes exactly N * 100kW. Keep these prototypes boring: the generator's
    -- own edge cases are covered by the other cases, and anything clever here couples
    -- solver expectations to generator behavior. A change in the checked numbers means
    -- solver behavior changed.

    -- Builds a factory in a fresh district with one line per recipe name, in order.
    -- The factory is put in context, as solver.update() only clears the cache of the
    -- floor in context and its parents.
    local function build_factory(context, recipe_names)
        local classes, player = context.classes, context.player
        local factory = fixtures.factory(context, "test-factory", "sequential")

        for _, recipe_name in ipairs(recipe_names) do
            local line = classes.Line.init(prototyper.util.find("recipes", recipe_name))
            factory.top_floor:insert(line)
            line.machine = classes.Machine.init(line,
                prototyper.util.find("machines", "test-solver-machine", "test-solver"))
            line.machine:summarize_effects()
            line.machine:normalize_fuel(player)
        end

        return factory
    end

    local function add_product(classes, factory, item_name, amount)
        local product = classes.FactoryItem.init(prototyper.util.find("items", item_name, "item"), "product")
        product.definition.amount = amount  -- per second
        factory:insert(product)
        return product
    end

    -- Returns the amount of the named item in an object's item list, or nil
    local function item_amount(item_list, name)
        for _, item in pairs(item_list) do
            if item.proto.name == name then return item.amount end
        end
        return nil
    end

    fixtures.chain = {build=build_factory, product=add_product, amount=item_amount}
end

return fixtures
