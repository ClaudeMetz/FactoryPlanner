import_dialog = {}
export_dialog = {}

-- ** TOP LEVEL **
function import_dialog.open(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"", {"fp.import"}, " ", {"fp.subfactories"}}

end



function export_dialog.open(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"", {"fp.export"}, " ", {"fp.subfactories"}}

    local player = game.get_player(flow_modal_dialog.player_index)
    local player_table = get_table(player)

    local content_frame = flow_modal_dialog.add{type="frame", direction="vertical",
      style="inside_shallow_frame_with_padding"}

    local table_subfactories = content_frame.add{type="table", column_count=2, style="mods_table"}
    table_subfactories.style.column_alignments[1] = "center"

    table_subfactories.add{type="checkbox", name="fp_checkbox_export_select_all",
      state=false}

    local label_subfactories_title = table_subfactories.add{type="label", caption={"fp.csubfactories"}}
    label_subfactories_title.style.font = "heading-3"
    label_subfactories_title.style.margin = {6, 100, 6, 4}

    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in pairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            table_subfactories.add{type="checkbox", name=("fp_checkbox_export_subfactory_" .. subfactory.id),
              state=false, enabled=subfactory.valid}

            local subfactory_icon = (subfactory.icon) and "[" .. subfactory.icon.type .. "="
              .. subfactory.icon.name .. "]   " or ""
            table_subfactories.add{type="label", caption=subfactory_icon .. subfactory.name}
        end
    end
end