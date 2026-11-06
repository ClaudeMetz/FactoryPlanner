---@diagnostic disable

local gui = require("helpers").gui
local fixtures = require("fixtures")

local function pick_up(player, action, key, object)
    local frame = lib.globals.main_elements(player).main_frame
    gui.click(player, gui.require(frame, {on_gui_click=action, [key]=object.id}))
end

local function move(player, direction)
    local input = "fp_move_" .. direction
    script.get_event_handler(input)({name=input, input_name=input, player_index=player.index, tick=game.tick})
end

return {
    testMoveFactoryWithArrows = {check=function(context)
        local player, classes = context.player, context.classes
        local selected = fixtures.factory(context, "Selected")
        local district = selected.parent
        local archived = classes.Factory.init("Archived", "sequential")
        archived.archived = true
        district:insert(archived)
        local moving = classes.Factory.init("Moving", "sequential")
        district:insert(moving)
        main_dialog.rebuild(player, true)
        local ui = lib.globals.ui_state(player)
        ui.main_elements.factory_list.search_textfield.text = "Moving"
        lib.gui.run_refresh(player, "factory_list")

        move(player, "up")
        assert(district.first == selected, "Arrows without a held object must do nothing")
        pick_up(player, "pick_up_factory", "factory_id", moving)
        move(player, "up")
        move(player, "down")
        assert(moving.previous == archived and moving.next == nil, "Searching must disable arrow movement")
        assert(ui.held_object_id == moving.id, "Searching must preserve move mode")
        ui.main_elements.factory_list.search_textfield.text = ""
        lib.gui.run_refresh(player, "factory_list")
        move(player, "up")
        assert(district.first == moving and moving.next == selected,
            "Clearing search must restore movement, skipping archived factories")
        assert(ui.held_object_id == moving.id, "Arrow movement must retain the held object")
        assert(lib.context.get(player, "Factory") == selected, "Moving must preserve factory selection")
        move(player, "up")
        assert(district.first == moving and ui.held_object_id == moving.id, "Top boundary must retain move mode")
        move(player, "down")
        assert(selected.next == moving)
        move(player, "down")
        assert(selected.next == moving, "Archived factories must not provide another move destination")

        ui.main_elements.main_frame.visible = false
        move(player, "up")
        assert(selected.next == moving, "Closed interface must not move objects")
        ui.main_elements.main_frame.visible = true
        ui.modal_dialog_type = "factory"
        move(player, "up")
        assert(selected.next == moving, "Modal dialog must block movement")
        ui.modal_dialog_type = nil
        pick_up(player, "pick_up_factory", "factory_id", moving)
        assert(ui.held_object_id == nil, "Clicking the held object must still cancel move mode")
    end},

    testMoveDistrictWithArrows = {check=function(context)
        local player = context.player
        local factory = fixtures.factory(context, "Selected")
        local realm = factory.parent.parent
        realm:remove(realm.first)
        local moving = context.classes.District.init("Moving")
        realm:insert(moving)
        main_dialog.rebuild(player, true)
        gui.click(player, gui.require(lib.globals.main_elements(player).main_frame,
            {on_gui_click="toggle_districts_view"}))
        pick_up(player, "pick_up_district", "district_id", moving)
        move(player, "up")
        assert(moving.next == factory.parent and moving.previous == nil)
        move(player, "up")
        assert(moving.previous == nil, "District must stop at the top")
        move(player, "down")
        move(player, "down")
        assert(moving.previous == factory.parent and moving.next == nil)
        assert(lib.globals.ui_state(player).held_object_id == moving.id)
    end},

    testMoveRecipeAndSubfloorWithArrows = {check=function(context)
        local player = context.player
        local factory = fixtures.factory(context, "Selected")
        local top = factory.top_floor
        local first = fixtures.line(context, top, "iron-plate")
        first:change_machine_to_default(player)
        local subfloor = context.classes.Floor.init(2, top.solver)
        top:insert(subfloor)
        local defining = fixtures.line(context, subfloor, "iron-plate")
        defining:change_machine_to_default(player)
        local second = fixtures.line(context, subfloor, "iron-gear-wheel")
        second:change_machine_to_default(player)
        local third = fixtures.line(context, subfloor, "copper-plate")
        third:change_machine_to_default(player)
        solver.update(player, factory)
        main_dialog.rebuild(player, true)

        pick_up(player, "pick_up_line", "line_id", subfloor)
        move(player, "up")
        assert(top.first == subfloor and subfloor.next == first, "Subfloor must move as one object")
        move(player, "down")
        move(player, "down")
        assert(top.first == first and first.next == subfloor and subfloor.next == nil)
        pick_up(player, "pick_up_line", "line_id", subfloor)

        lib.context.set(player, subfloor)
        lib.gui.run_refresh(player, "production")
        pick_up(player, "pick_up_line", "line_id", third)
        move(player, "up")
        move(player, "up")
        assert(subfloor.first == defining and defining.next == third and third.next == second,
            "Recipe must stop below the defining subfloor recipe")
        move(player, "down")
        move(player, "down")
        assert(defining.next == second and second.next == third and third.next == nil)
        assert(lib.globals.ui_state(player).held_object_id == third.id)
    end}
}
