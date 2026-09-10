---@diagnostic disable

-- Copy, Cut, and Paste coverage for lib.clipboard, including immutable snapshots,
-- GUI dispatch, and removal that changes the original parent.
local helpers = require("helpers")

local function fixture(context)
    local classes, player = context.classes, game.players[1]
    local district = classes.District.init()
    lib.globals.player_table(player).realm:insert(district)
    local factory = classes.Factory.init("clipboard-test", "sequential")
    district:insert(factory)
    lib.context.set(player, factory)
    local product = classes.TLProduct.init(prototyper.util.find("items", "iron-gear-wheel", "item"))
    product.required_amount = 12
    factory:insert(product)
    return classes, player, factory, product
end

local function add_line(classes, player, floor, recipe_name)
    local line = classes.Line.init(prototyper.util.find("recipes", recipe_name or "iron-gear-wheel"), "produce")
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
    tags.mod = "fp"
    tags.on_gui_click = handler
    tags.flags = flags or {}
    local button = player.gui.screen.add{type="sprite-button", tags=tags}
    lib.globals.ui_state(player).last_action = nil
    local ok, message = pcall(script.get_event_handler(defines.events.on_gui_click), {
        name=defines.events.on_gui_click, tick=game.tick, player_index=player.index,
        element=button, button=(action == "paste") and defines.mouse_button_type.left or defines.mouse_button_type.right,
        control=(action == "cut"), alt=false, shift=(action ~= "cut")
    })
    button.destroy()
    assert(ok, message)
end

return {
    copy_snapshots = {check=function(context)
        for _, subfloor in ipairs{false, true} do
            local classes, player, factory = fixture(context)
            local source = subfloor and classes.Floor.init(2) or nil
            if source then factory.top_floor:insert(source) end
            local line = add_line(classes, player, source or factory.top_floor)
            source = source or line
            line.comment = "Copied configuration"
            line.percentage = 75
            local beacon = add_beacon(classes, line)
            solver.update(player, factory)
            click(player, "act_on_line_recipe", {line_id=source.id}, nil, "copy")
            local clip = lib.globals.player_table(player).clipboard
            assert(source.parent == factory.top_floor and factory.top_floor:count() == 1,
                "Copy must leave its source in place")

            line.comment = "Changed after copy"
            beacon.amount = 1
            beacon.module_set.first:set_amount(1)
            for i = 1, 2 do
                assert(lib.clipboard.paste(player, factory.top_floor))
                local pasted = factory.top_floor:find_last()
                local pasted_line = subfloor and pasted.first or pasted
                assert(pasted ~= source and pasted_line ~= line)
                assert(pasted_line.comment == "Copied configuration" and pasted_line.percentage == 75)
                assert(pasted_line.beacon.amount == 3 and pasted_line.beacon.module_set.first.amount == 2,
                    "Paste must restore the snapshot, independent of source and earlier pastes")
                pasted_line.comment = "Changed after paste"
                pasted_line.beacon.module_set.first:set_amount(1)
                assert(factory.top_floor:count() == i + 1)
            end
            assert(lib.globals.player_table(player).clipboard == clip, "Paste must retain the clipboard")
        end
    end},

    copy_product = {check=function(context)
        local classes, player, factory, product = fixture(context)
        product.defined_by = "belts"
        product.required_amount = 1.5
        product.belt_proto = prototyper.util.find("belts", "transport-belt")
        product.belt_stack = 2
        add_line(classes, player, factory.top_floor)
        solver.update(player, factory)
        local copied_amount = product.amount
        assert(copied_amount > 0 and copied_amount ~= product.required_amount)
        click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
            {top_level=true, product=true}, "copy")
        assert(product.parent == factory and product.defined_by == "belts" and product.required_amount == 1.5)
        assert(lib.globals.player_table(player).clipboard.class == "SimpleItem")
        product.amount = 0

        local _, _, destination, target = fixture(context)
        click(player, "act_on_item_box", {item_id=target.id, item_category="product"},
            {top_level=true, product=true}, "paste")
        assert(destination.first ~= target and destination.first.defined_by == "amount")
        assert(destination.first.required_amount == copied_amount,
            "ordinary Copy/Paste must use the calculated item amount, not the full product configuration")
    end},

    paste_onto_recipe = {check=function(context)
        local classes, player, factory = fixture(context)
        local source = add_line(classes, player, factory.top_floor)
        source.comment = "Pasted gear recipe"
        local target = add_line(classes, player, factory.top_floor, "transport-belt")
        solver.update(player, factory)
        click(player, "act_on_line_recipe", {line_id=source.id}, nil, "copy")
        click(player, "act_on_line_recipe", {line_id=target.id}, nil, "paste")
        local floor = target.parent
        assert(floor.class == "Floor" and floor.parent == factory.top_floor and floor.first == target)
        assert(floor:count() == 2 and floor.first.next.comment == "Pasted gear recipe")
        assert(source.parent == factory.top_floor, "Paste must not move the copied source")
    end},

    paste_failures = {check=function(context)
        local classes, player, factory, product = fixture(context)
        local line = add_line(classes, player, factory.top_floor)
        local player_table = lib.globals.player_table(player)
        player_table.clipboard = nil
        assert(not lib.clipboard.paste(player, product))
        assert(factory.first == product and factory:count() == 1 and player_table.clipboard == nil)

        click(player, "act_on_line_recipe", {line_id=line.id}, nil, "copy")
        local clip = player_table.clipboard
        assert(not lib.clipboard.paste(player, product), "a recipe cannot be pasted onto a product")
        assert(factory.first == product and product.required_amount == 12 and player_table.clipboard == clip)
        lib.clipboard.dummy_paste(player, classes.TLProduct.init(), factory)
        assert(factory:count() == 1 and factory.first == product, "failed dummy paste must remove its placeholder")
        assert(player_table.clipboard == clip)
    end},

    cut_line_collapses_subfloor = {check=function(context)
        local classes, player, factory = fixture(context)
        local floor = classes.Floor.init(2)
        factory.top_floor:insert(floor)
        local defining = add_line(classes, player, floor)
        local source = add_line(classes, player, floor)
        source.comment = "Keep this line"
        source.percentage = 75
        solver.update(player, factory)
        click(player, "act_on_line_recipe", {line_id=source.id})
        assert(source.parent == nil and factory.top_floor.first == defining,
            "cut must remove the line and collapse its old subfloor")
        assert(lib.clipboard.paste(player, factory.top_floor))
        local pasted = factory.top_floor:find_last()
        assert(pasted ~= source and pasted.comment == "Keep this line" and pasted.percentage == 75)
    end},

    cut_subfloor = {check=function(context)
        local classes, player, factory = fixture(context)
        local floor = classes.Floor.init(2)
        factory.top_floor:insert(floor)
        add_line(classes, player, floor)
        local nested = classes.Floor.init(3)
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
            product.required_amount = belts and 1.5 or 17
            if belts then
                product.defined_by = "belts"
                product.belt_proto = prototyper.util.find("belts", "transport-belt")
                product.belt_stack = 2
                add_line(classes, player, factory.top_floor)
            end
            solver.update(player, factory)
            local expected_amount = product.amount
            click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
                {top_level=true, product=true}, "copy")
            local copied = lib.globals.player_table(player).clipboard
            click(player, "act_on_item_box", {item_id=product.id, item_category="product"},
                {top_level=true, product=true})
            assert(factory:count() == 0 and product.parent == nil)
            local clip = lib.globals.player_table(player).clipboard
            assert(clip.class == "SimpleItem" and clip.class == copied.class)
            assert(clip.packed_object.proto.name == copied.packed_object.proto.name
                and clip.packed_object.proto.type == copied.packed_object.proto.type
                and clip.packed_object.amount == copied.packed_object.amount,
                "Cut must store the same item and calculated amount as Copy")
            lib.clipboard.dummy_paste(player, classes.TLProduct.init(), factory)
            local pasted = factory.first
            assert(pasted and pasted ~= product and pasted.required_amount == expected_amount)
            assert(pasted.defined_by == "amount")
            lib.clipboard.dummy_paste(player, classes.TLProduct.init(), factory)
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
    end}
}
