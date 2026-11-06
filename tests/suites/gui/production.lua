---@diagnostic disable

local tests = {}

-- Input target results
do
    local helpers = require("helpers")
    local arrange = require("fixtures").input

    local cases = {}
    for _, solver_name in ipairs{"sequential", "simplex", "gaussian"} do
        cases["testSatisfiedInputPresentation_" .. solver_name] = {check=function(context)
            local build = arrange(context)
            local c, player, classes = helpers.collector(), context.player, context.classes
            local f = build.factory(solver_name)
            local plate = build.line(f.top_floor, "plate")
            local ore = build.target(f, "iron-ore", "ingredient", 20)
            solver.update(player, f)
            c.close(ore.amount, 20, solver_name .. " ingredient achieved amount")
            c.close(plate.machine.amount, 10, solver_name .. " input-paced machines")
            c.close(build.find(f.top_floor.ingredients, "iron-ore").required_amount, 20, solver_name .. " top allocation")
            c.close(build.find(plate.ingredients, "iron-ore").target_amount, 20, solver_name .. " line allocation")
            main_dialog.rebuild(player, false)
            local count = 0
            for _, button in pairs(lib.globals.main_elements(player).item_boxes.ingredient_item_table.children) do
                if button.sprite == "item/iron-ore" then
                    count = count + 1
                    c.check(button.tags.item_id == ore.id and button.style.name == "fflib_slot_button_green",
                        solver_name .. " satisfied consumption must be represented by its target")
                end
            end
            c.check(count == 1, solver_name .. " must not duplicate a satisfied ingredient")

            c.done()
        end}
    end
    for _, solver_name in ipairs{"sequential", "simplex"} do
        cases["testExcessInputPresentation_" .. solver_name] = {check=function(context)
            local build = arrange(context)
            local c, player, classes = helpers.collector(), context.player, context.classes
            local f = build.factory(solver_name)
            local plate = build.line(f.top_floor, "plate")
            local ore = build.target(f, "iron-ore", "ingredient", 10)
            local output = build.target(f, "iron-plate", "product", 0)
            output.definition = {type="machines", machine_count=8}
            solver.update(player, f)
            c.close(ore.amount, 16, solver_name .. " excess consumption")
            local calculated = build.find(f.top_floor.ingredients, "iron-ore")
            c.close(calculated.required_amount, 10, solver_name .. " capped target share")
            c.close(calculated:get_remaining_amount(), 6, solver_name .. " excess consumption remainder")
            main_dialog.rebuild(player, false)
            compact_dialog.rebuild(player, false)
            local count = 0
            for _, button in pairs(lib.globals.main_elements(player).item_boxes.ingredient_item_table.children) do
                if button.sprite == "item/iron-ore" then
                    count = count + 1
                    if button.tags.item_index then
                        c.close(button.number, item_views.process_item(player, ore.proto, 6, nil),
                            solver_name .. " GUI shows only excess consumption")
                    end
                end
            end
            c.check(count == 2, solver_name .. " excess consumption must have a separate remainder")
            c.done()
        end}
    end
    tests.inputs = cases
end

-- Machine targets
do
    local machine_fixture = require("fixtures").machine
    local gui = require("helpers").gui

    tests.machines = {
        testMachineRequirementPresentation = {check=function(context)
            local f = machine_fixture(context)
            local classes = context.classes
            solver.update(f.player, f.factory)
            -- A producing line appears in compact view; its tooltip must still show only the configured count
            f.first.production_ratio, f.first.machine.amount = 7, 7
            main_dialog.rebuild(f.player, false)
            compact_dialog.rebuild(f.player, false)
            local ui = lib.globals.ui_state(f.player)
            local button = gui.require(ui.main_elements.main_frame, {on_gui_click="act_on_line_machine", machine_id=f.first.machine.id})
            assert(button and button.style.name == "fflib_slot_button_blue")
            local tooltip = ui.tooltips.production_table[button.index]
            assert(tooltip[3][3][1] == "fp.machine_requirement" and tooltip[3][3][2] == "3.5")
            assert(tooltip[3][3][4] == nil, "Tooltip must only show the fixed limit")
            local compact_button = gui.require(ui.compact_elements.compact_frame, {on_gui_click="act_on_compact_machine", line_id=f.first.id})
            assert(compact_button and compact_button.style.name == "fflib_slot_button_blue")
            local compact_tooltip = ui.tooltips.compact_dialog[compact_button.index]
            assert(compact_tooltip[3][3][1] == "fp.machine_requirement" and compact_tooltip[3][3][2] == "3.5")
            f.iron.definition = {type="amount", amount=1}
            f.factory:remove(f.copper)
            solver.update(f.player, f.factory)
            assert(f.first.machine_requirement == nil, "Changing definitions must clear old assignments")
            lib.gui.run_refresh(f.player, "production")
            local button = gui.require(lib.globals.main_elements(f.player).main_frame, {on_gui_click="act_on_line_machine", machine_id=f.first.machine.id})
            assert(button.style.name == "fflib_slot_button_default")
        end},
        testMachineRequirementDialog = {check=function(context)
            local f = machine_fixture(context)
            local classes = context.classes
            solver.update(f.player, f.factory)
            main_dialog.rebuild(f.player, false)
            lib.gui.open_dialog(f.player, {dialog="machine", modal_data={machine_id=f.first.machine.id}})
            local elements = lib.globals.modal_elements(f.player)
            assert(elements.limit_textfield == nil and elements.force_limit_switch == nil)
            lib.gui.close_dialog(f.player, "submit")
            lib.gui.open_dialog(f.player, {dialog="machine", modal_data={machine_id=f.first.machine.id}})
            lib.gui.close_dialog(f.player, "cancel")

        end},
        testTargetOrderRefreshesMachineRequirement = {check=function(context)
            local f = machine_fixture(context)
            local classes = context.classes
            solver.update(f.player, f.factory)
            main_dialog.rebuild(f.player, false)
            local function move(action)
                local button = gui.require(lib.globals.main_elements(f.player).main_frame, {on_gui_click="act_on_item_box", item_id=f.copper.id})
                gui.click(f.player, button, {button=defines.mouse_button_type.right})
                local menu = lib.globals.ui_state(f.player).context_menu
                gui.click(f.player, gui.require(menu, {action=action}))
            end
            move("move_left")
            assert(f.first.machine_requirement.count == 8, "Moving a target must refresh the chosen count")
            move("move_right")
            assert(f.first.machine_requirement.count == 3.5)
        end},
    }
end

-- Surplus subfloors
do
    local gui = require("helpers").gui
    local helpers = require("helpers")
    local chain = require("fixtures").chain
    local build_factory, add_product, item_amount = chain.build, chain.product, chain.amount

    tests.surplus = {
        testSurplusRecipeCreatesSubfloor = {check=function(context)
            local c, player = helpers.collector(), context.player
            local factory = build_factory(context, {"test-solver-gear", "test-solver-plate"})
            local product = add_product(context.classes, factory, "test-solver-gear", 5)

            solver.update(player, factory)
            local top = factory.top_floor
            local gear_line, plate_line = top.first, top.first.next
            -- Request a coproduct so a consuming gear line can use the 10 plates/s surplus
            local coproduct_line = context.classes.Line.init(
                prototyper.util.find("recipes", "test-solver-plate-with-slag"))
            top:replace(plate_line, coproduct_line)
            coproduct_line:change_machine_to_proto(player,
                prototyper.util.find("machines", "test-solver-machine", "test-solver"))
            add_product(context.classes, factory, "test-solver-slag", 20)
            local consumer = context.classes.Line.init(
                prototyper.util.find("recipes", "test-solver-gear"))
            top:insert(consumer)
            consumer:change_machine_to_proto(player,
                prototyper.util.find("machines", "test-solver-machine", "test-solver"))
            solver.update(player, factory)
            -- Surplus-driven recipes can define subfloors, including nested ones
            main_dialog.rebuild(player, false)
            local button = gui.require(lib.globals.main_elements(player).main_frame,
                {on_gui_click="act_on_line_recipe", line_id=consumer.id})
            assert(button.style.name == "fflib_slot_button_default", "Surplus recipes must use the ordinary recipe button")
            gui.click(player, button)
            local consumer_floor = consumer.parent
            c.check(consumer_floor ~= top and consumer_floor.first == consumer,
                "clicking a surplus-driven recipe must create its subfloor")
            c.check(helpers.approx(consumer.machine.amount, 5) and helpers.approx(product.amount, 10),
                "consumer subfloor: expected parent surplus to pace 5 gear machines")
            c.done()
        end},
    }
end

return tests
