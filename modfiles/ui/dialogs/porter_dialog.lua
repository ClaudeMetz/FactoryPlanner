import_dialog = {}
export_dialog = {}
porter_dialog = {}  -- table containing functionality shared between both dialogs

-- ** TOP LEVEL **
function import_dialog.open(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"", {"fp.import"}, " ", {"fp.subfactories"}}

end



function export_dialog.open(flow_modal_dialog)
    flow_modal_dialog.parent.caption = {"", {"fp.export"}, " ", {"fp.subfactories"}}

    local player = game.get_player(flow_modal_dialog.player_index)
    local player_table = get_table(player)

    local content_frame = flow_modal_dialog.add{type="frame", name="frame_content", direction="vertical",
      style="inside_shallow_frame_with_padding"}

    local label_text = content_frame.add{type="label", caption="Select the subfactories that you'd like to export:"}
    label_text.style.bottom_margin = 6

    local table_subfactories = content_frame.add{type="table", name="table_subfactories",
      column_count=3, style="mods_table"}
    table_subfactories.style.column_alignments[1] = "center"
    table_subfactories.style.column_alignments[3] = "center"

    local checkbox_master = table_subfactories.add{type="checkbox", name="fp_checkbox_porter_master", state=false}

    local label_subfactories_title = table_subfactories.add{type="label", caption={"fp.csubfactories"}}
    label_subfactories_title.style.font = "heading-3"
    label_subfactories_title.style.margin = {6, 150, 6, 4}

    local label_subfactories_validity = table_subfactories.add{type="label", caption="Validity"}
    label_subfactories_validity.style.font = "heading-3"
    label_subfactories_validity.style.padding = {0, 4}

    local valid_subfactory_found = false
    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in pairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            table_subfactories.add{type="checkbox", name=("fp_checkbox_porter_subfactory_" .. subfactory.id),
              state=false, enabled=subfactory.valid}

            local subfactory_icon = ""
            if subfactory.icon ~= nil then
                local subfactory_sprite = subfactory.icon.type .. "/" .. subfactory.icon.name
                if not game.is_valid_sprite_path(subfactory_sprite) then
                    subfactory_sprite = "utility/danger_icon"
                end
                subfactory_icon = "[img=" .. subfactory_sprite .. "]  "
            end
            table_subfactories.add{type="label", caption=subfactory_icon .. subfactory.name}

            local validity_caption = (subfactory.valid) and "valid" or "[color=1, 0.2, 0.2]invalid[/color]"
            table_subfactories.add{type="label", caption=validity_caption}

            valid_subfactory_found = valid_subfactory_found or subfactory.valid
        end
    end

    checkbox_master.enabled = valid_subfactory_found
end



-- ** SHARED **
-- Sets all slave checkboxes to the given state
function porter_dialog.set_all_checkboxes(player, checkbox_state)
    local table_subfactories = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
      ["frame_content"]["table_subfactories"]

    for _, element in pairs(table_subfactories.children) do
        if string.find(element.name, "^fp_checkbox_porter_subfactory_%d+$") and element.enabled then
            element.state = checkbox_state
        end
    end
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
function porter_dialog.adjust_master_checkbox(player)
    local table_subfactories = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]
      ["frame_content"]["table_subfactories"]

    local unchecked_element_found = false
    for _, element in pairs(table_subfactories.children) do
        if string.find(element.name, "^fp_checkbox_porter_subfactory_%d+$") and element.state == false then
            unchecked_element_found = true
            break
        end
    end

    table_subfactories["fp_checkbox_porter_master"].state = not unchecked_element_found
end