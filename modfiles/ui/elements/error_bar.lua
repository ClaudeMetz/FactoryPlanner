-- Creates the error bar
function add_error_bar_to(main_dialog)
    local error_bar = main_dialog.add{type="flow", name="flow_error_bar", direction="vertical"}
    error_bar.style.top_margin = 6

    refresh_error_bar(game.get_player(main_dialog.player_index))
end

-- Refreshes the error_bar
function refresh_error_bar(player)
    local flow_error_bar = player.gui.screen["fp_frame_main_dialog"]["flow_error_bar"]
    -- Cuts function short if the error bar hasn't been initialized yet
    if not flow_error_bar then return end

    flow_error_bar.clear()

    local subfactory = get_context(player).subfactory
    if subfactory ~= nil and not subfactory.valid then
        create_error_bar(flow_error_bar, subfactory.id)
        flow_error_bar.visible = true
    else
        flow_error_bar.visible = false
    end
end

-- Constructs the error bar
function create_error_bar(flow, subfactory_id)
    local label_1 = flow.add{type="label", name="label_error_bar_1", caption={"", "   ", {"fp.error_bar_1"}}}
    label_1.style.font = "fp-font-16p"
    local table = flow.add{type="table", name="table_error_bar", column_count=2}
    local label_2 = table.add{type="label", name="label_error_bar_2", caption={"", "   ", {"fp.error_bar_2"}, " "}}
    label_2.style.font = "fp-font-16p"
    local button = table.add{type="button", name="fp_button_error_bar_repair", caption={"fp.error_bar_repair"},
      tooltip={"fp.error_bar_repair_tt"}, mouse_button_filter={"left"}}
    button.style.font = "fp-font-16p"
    button.style.padding = {0, 4}
    button.style.height = 28
    button.style.minimal_width = 0
end

-- Repairs the current subfactory
function handle_subfactory_repair(player)
    local subfactory = get_context(player).subfactory
    Subfactory.attempt_repair(subfactory, player)
    calculation.update(player, subfactory, true)
end