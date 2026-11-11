---@diagnostic disable

-- Copy, Cut, and Paste coverage for lib.clipboard, including immutable snapshots,
-- GUI dispatch, and removal that changes the original parent.
local helpers = require("helpers")
local fixtures = require("fixtures")
local gui = require("helpers").gui
local SimpleItem = script and require("__factoryplanner__.backend.data.SimpleItem")

local function fixture(context)
    local classes, player = context.classes, game.players[1]
    local factory = fixtures.factory(context, "clipboard-test")
    local product = classes.FactoryItem.init("product", prototyper.util.find("items", "iron-gear-wheel", "item"))
    product.definition.amount = 12
    factory:insert(product)
    return classes, player, factory, product
end

local function add_line(classes, player, floor, recipe_name)
    local line = classes.Line.init(prototyper.util.find("recipes", recipe_name or "iron-gear-wheel"))
    floor:insert(line)
    line:change_machine_to_proto(player, helpers.find_machine("assembling-machine-2"))
    return line
end

local function add_module(classes, object, amount)
    local module = classes.Module.init(prototyper.util.find("modules", "speed-module", "speed"),
        amount, defaults.get_fallback("qualities").proto)
    object.module_set:insert(module)
    object.module_set:normalize({effects=true})
    return module
end

local function add_beacon(classes, line)
    local beacon = classes.Beacon.init(line, prototyper.util.find("beacons", "beacon"))
    beacon.amount = 3
    add_module(classes, beacon, 2)
    line:set_beacon(beacon)
    return beacon
end

local function click(player, handler, tags, flags, action)
    action = action or "cut"
    tags.mod, tags.on_gui_click, tags.flags = "fp", handler, flags or {}
    local button = player.gui.screen.add{type="sprite-button", tags=tags}
    gui.click(player, button, {
        button=(action == "paste") and defines.mouse_button_type.left or defines.mouse_button_type.right,
        control=(action == "cut"), shift=(action ~= "cut")
    })
    button.destroy()
end

return {
    copy_product = {check=function(context)
        for _, belts in ipairs{false, true} do
            local classes, player, factory, product = fixture(context)
            product.definition = {type="amount", amount=17}
            if belts then
                product.definition = {type="belts", belt_count=1.5}
                product.definition.belt_proto = prototyper.util.find("belts", "fast-transport-belt")
                product.definition.belt_stack = 2
            end
            -- No production: the configured requirement must survive even when output is zero.
            solver.update(player, factory)
            assert(product.amount == 0)
            click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
                {top_level=true, product=true}, "copy")
            local clip = lib.globals.player_table(player).clipboard
            assert(clip.class == "FactoryItem" and product.parent == factory)
            product.definition = {type="amount", amount=99}

            local _, _, destination, target = fixture(context)
            for i = 1, 2 do
                click(player, "act_on_item_box", {item_id=target.id, item_category="product"},
                    {top_level=true, product=true}, "paste")
                local pasted = destination.first
                assert(pasted ~= target and pasted ~= product and destination:count() == 1)
                assert(pasted.definition.type == (belts and "belts" or "amount"))
                assert(pasted.definition[belts and "belt_count" or "amount"] == (belts and 1.5 or 17))
                if belts then
                    assert(pasted.definition.belt_proto.name == "fast-transport-belt" and pasted.definition.belt_stack == 2)
                else
                    assert(pasted.definition.belt_proto == nil and pasted.definition.belt_stack == nil)
                end
                pasted.definition[belts and "belt_count" or "amount"] = 42
                pasted.definition.belt_stack = belts and 1 or nil
                target = pasted
            end
            assert(lib.globals.player_table(player).clipboard == clip)
        end
    end},

    paste_onto_recipe = {check=function(context)
        local classes, player, factory = fixture(context)
        local source = add_line(classes, player, factory.top_floor, "copper-cable")
        source.comment = "Pasted unrelated recipe"
        local target = add_line(classes, player, factory.top_floor, "transport-belt")
        solver.update(player, factory)
        click(player, "act_on_line_recipe", {line_id=source.id}, nil, "copy")
        click(player, "act_on_line_recipe", {line_id=target.id}, nil, "paste")
        local floor = target.parent
        assert(floor.class == "Floor" and floor.parent == factory.top_floor and floor.first == target)
        assert(floor:count() == 2 and floor.first.next.comment == "Pasted unrelated recipe")
        assert(source.parent == factory.top_floor, "Paste must not move the copied source")
        lib.clipboard.dummy_paste(player, classes.Line.init(), floor)
        assert(floor:count() == 3 and floor:find_last().recipe.proto.name == "copper-cable",
            "dummy paste must accept unrelated recipes inside a subfloor")
    end},
    cut_line_collapses_subfloor = {check=function(context)
        local classes, player, factory = fixture(context)
        local floor = classes.Floor.init(2, factory.top_floor.solver)
        factory.top_floor:insert(floor)
        local defining = add_line(classes, player, floor)
        local source = add_line(classes, player, floor)
        source.comment = "Keep this line"
        solver.update(player, factory)
        click(player, "act_on_line_recipe", {line_id=source.id})
        assert(source.parent == nil and factory.top_floor.first == defining,
            "cut must remove the line and collapse its old subfloor")
        assert(lib.clipboard.paste(player, factory.top_floor))
        local pasted = factory.top_floor:find_last()
        assert(pasted ~= source and pasted.comment == "Keep this line")
    end},
    cut_subfloor = {check=function(context)
        local classes, player, factory = fixture(context)
        local floor = classes.Floor.init(2, factory.top_floor.solver)
        factory.top_floor:insert(floor)
        add_line(classes, player, floor)
        local nested = classes.Floor.init(3, floor.solver)
        floor:insert(nested)
        add_line(classes, player, nested).comment = "Nested configuration"
        solver.update(player, factory)
        click(player, "act_on_line_recipe", {line_id=floor.id})
        assert(factory.top_floor:count() == 0)
        assert(lib.clipboard.paste(player, factory.top_floor))
        local pasted = factory.top_floor.first
        assert(pasted.class == "Floor" and pasted:count() == 2)
        assert(pasted.first.next.first.comment == "Nested configuration")
    end},
    cut_beacon = {check=function(context)
        local classes, player, factory = fixture(context)
        local line = add_line(classes, player, factory.top_floor)
        local source = add_beacon(classes, line)
        solver.update(player, factory)
        click(player, "act_on_line_beacon", {beacon_id=source.id})
        assert(line.beacon == nil)
        assert(lib.clipboard.paste(player, classes.Beacon.init(line)))
        assert(line.beacon ~= source and line.beacon.amount == 3)
        assert(line.beacon.module_set.first.amount == 2)
        assert(line.beacon.module_set.first.proto.name == "speed-module")
    end},
    cut_modules = {check=function(context)
        for _, from_beacon in ipairs{false, true} do
            local classes, player, factory = fixture(context)
            local line = add_line(classes, player, factory.top_floor)
            local object = from_beacon and add_beacon(classes, line) or line.machine
            local source = from_beacon and object.module_set.first or add_module(classes, object, 2)
            local target = add_line(classes, player, factory.top_floor)
            solver.update(player, factory)
            click(player, "act_on_line_module", {module_id=source.id})
            assert(source.parent == nil and object.module_set.module_count == 0)
            if from_beacon then assert(line.beacon == nil, "last module must remove its beacon") end
            assert(lib.clipboard.paste(player, target.machine))
            assert(target.machine.module_set.first.amount == 2)
            assert(target.machine.module_set.first.proto.name == "speed-module")
        end
    end},
    cut_product = {check=function(context)
        for _, belts in ipairs{false, true} do
            local classes, player, factory, product = fixture(context)
            product.definition = {type="amount", amount=17}
            if belts then
                product.definition = {type="belts", belt_count=1.5}
                product.definition.belt_proto = prototyper.util.find("belts", "transport-belt")
                product.definition.belt_stack = 2
                add_line(classes, player, factory.top_floor)
            end
            solver.update(player, factory)
            local expected_amount = product.definition[belts and "belt_count" or "amount"]
            click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
                {top_level=true, product=true}, "copy")
            local copied = lib.globals.player_table(player).clipboard
            click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
                {top_level=true, product=true})
            assert(factory:count() == 0 and product.parent == nil)
            local clip = lib.globals.player_table(player).clipboard
            assert(clip.class == "FactoryItem" and clip.class == copied.class)
            assert(clip.packed_object.proto.name == copied.packed_object.proto.name
                and clip.packed_object.proto.type == copied.packed_object.proto.type
                and clip.packed_object.definition[belts and "belt_count" or "amount"] == copied.packed_object.definition[belts and "belt_count" or "amount"]
                and clip.packed_object.definition.type == copied.packed_object.definition.type
                and clip.packed_object.definition.belt_stack == copied.packed_object.definition.belt_stack,
                "Cut must store the same product configuration as Copy")
            lib.clipboard.dummy_paste(player, classes.FactoryItem.init("product"), factory)
            local pasted = factory.first
            assert(pasted and pasted ~= product and pasted.definition[belts and "belt_count" or "amount"] == expected_amount)
            assert(pasted.definition.type == (belts and "belts" or "amount"))
            if belts then
                assert(pasted.definition.belt_proto.name == "transport-belt" and pasted.definition.belt_stack == 2)
            end
            lib.clipboard.dummy_paste(player, classes.FactoryItem.init("product"), factory)
            assert(factory:count() == 1, "repeated paste must not create a duplicate product")
            assert(lib.globals.player_table(player).clipboard == clip, "failed paste must retain clipboard")
        end
    end},
    cut_restrictions = {check=function(context)
        local classes, player, factory, product = fixture(context)
        local line = add_line(classes, player, factory.top_floor)
        local beacon = add_beacon(classes, line)
        local module = beacon.module_set.first
        click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
            {top_level=true, product=true}, "copy")
        local clip = lib.globals.player_table(player).clipboard
        for _, target in ipairs{
            {"act_on_line_recipe", {line_id=line.id}},
            {"act_on_line_beacon", {beacon_id=beacon.id}},
            {"act_on_line_module", {module_id=module.id}},
            {"act_on_item_box", {item_id=product.id, item_category="product"}}
        } do
            click(player, target[1], target[2], {archived=true, top_level=true, product=true})
            assert(lib.globals.player_table(player).clipboard == clip, "blocked cut must not replace clipboard")
        end
        click(player, "act_on_line_recipe", {line_id=line.id}, {defining_recipe=true})
        click(player, "act_on_item_box", {item_id=product.id, item_category="product"}, {top_level=false})
        assert(line.parent == factory.top_floor and line.beacon == beacon and module.parent == beacon.module_set)
        assert(product.parent == factory and lib.globals.player_table(player).clipboard == clip)
    end},
}
