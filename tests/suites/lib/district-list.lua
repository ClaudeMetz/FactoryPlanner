---@diagnostic disable

local function find_button(element, action, id_key, id)
    if element.tags.on_gui_click == action and element.tags[id_key] == id then return element end
    for _, child in pairs(element.children) do
        local found = find_button(child, action, id_key, id)
        if found then return found end
    end
end

return {check=function(context)
    local player = game.players[1]
    local realm = lib.globals.player_table(player).realm
    local source = context.classes.District.init("Source")
    local destination = context.classes.District.init("Destination")
    realm:insert(source)
    realm:insert(destination)
    local selected = context.classes.Factory.init("Selected", "sequential")
    local moving = context.classes.Factory.init("Moving", "sequential")
    source:insert(selected)
    source:insert(moving)
    lib.context.set(player, selected)
    main_dialog.rebuild(player, false)
    local ui_state = lib.globals.ui_state(player)

    local function button(action, id_key, id)
        return find_button(ui_state.main_elements.main_frame, action, id_key, id)
    end
    local function click(action, id_key, id)
        local element = assert(button(action, id_key, id), "Missing button: " .. action)
        ui_state.last_action = nil
        script.get_event_handler(defines.events.on_gui_click){name=defines.events.on_gui_click,
            tick=game.tick, player_index=player.index, element=element,
            button=defines.mouse_button_type.left, control=false, alt=false, shift=false}
    end

    -- Picking up and cancelling restores ordinary district navigation
    click("pick_up_factory", "factory_id", moving.id)
    local move_button = button("place_factory_in_district", "district_id", destination.id)
    local select_button = button("select_district", "district_id", destination.id)
    assert(move_button.type == "sprite-button" and move_button.enabled)
    assert(move_button.parent == select_button.parent)
    assert(move_button.parent.children[1] == move_button)
    assert(not button("place_factory_in_district", "district_id", source.id).enabled)
    assert(button("select_district", "district_id", source.id))
    click("pick_up_factory", "factory_id", moving.id)
    assert(ui_state.held_object_id == nil)
    assert(button("select_district", "district_id", destination.id))
    assert(not button("place_factory_in_district", "district_id", destination.id))

    -- The district name still navigates instead of placing the held factory
    click("pick_up_factory", "factory_id", moving.id)
    click("select_district", "district_id", destination.id)
    assert(moving.parent == source and ui_state.held_object_id == nil)
    click("select_district", "district_id", source.id)

    -- The held factory can differ from the selected factory
    click("pick_up_factory", "factory_id", moving.id)
    click("place_factory_in_district", "district_id", destination.id)
    assert(moving.parent == destination and source:count() == 1 and destination:count() == 1)
    assert(lib.context.get(player, "Factory") == moving)
    assert(ui_state.held_object_id == nil and not ui_state.districts_view)
    assert(button("select_district", "district_id", source.id))
    click("select_district", "district_id", source.id)
    assert(lib.context.get(player, "Factory") == selected)

    -- Moving the selected factory out leaves an empty source navigable
    click("pick_up_factory", "factory_id", selected.id)
    click("place_factory_in_district", "district_id", destination.id)
    click("select_district", "district_id", source.id)
    assert(lib.context.get(player, "District") == source)
    assert(lib.context.get(player, "Factory") == nil)

    -- Archived factories retain their existing move restrictions
    selected.archived = true
    lib.context.set(player, selected)
    lib.gui.run_refresh(player, "all")
    click("pick_up_factory", "factory_id", selected.id)
    assert(button("select_district", "district_id", source.id))
    assert(not button("place_factory_in_district", "district_id", source.id))
    click("select_district", "district_id", source.id)
    assert(selected.parent == destination and ui_state.held_object_id == nil)
end}
