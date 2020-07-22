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


    local frame_subfactories = content_frame.add{type="frame", name="frame_subfactories",
      style="deep_frame_in_shallow_frame"}
    frame_subfactories.style.padding = {-2, 0, 4, 0}
    frame_subfactories.style.bottom_margin = 12

    local table_subfactories = frame_subfactories.add{type="table", name="table_subfactories",
      column_count=4, style="mods_table"}
    table_subfactories.style.column_alignments[1] = "center"
    table_subfactories.style.column_alignments[3] = "center"
    table_subfactories.style.column_alignments[4] = "center"

    local checkbox_master = table_subfactories.add{type="checkbox", name="fp_checkbox_porter_master", state=false}

    local label_subfactories_title = table_subfactories.add{type="label", caption={"fp.csubfactories"}}
    label_subfactories_title.style.font = "heading-3"
    label_subfactories_title.style.margin = {6, 150, 6, 4}

    local label_subfactories_validity = table_subfactories.add{type="label", caption="Validity"}
    label_subfactories_validity.style.font = "heading-3"
    label_subfactories_validity.style.margin = {0, 4}

    local label_subfactories_location = table_subfactories.add{type="label", caption="Location"}
    label_subfactories_location.style.font = "heading-3"
    label_subfactories_location.style.margin = {0, 4}

    local valid_subfactory_found = false
    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            table_subfactories.add{type="checkbox", name=("fp_checkbox_porter_subfactory_" .. factory_name
              .. "_" .. subfactory.id), state=false, enabled=subfactory.valid}

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

            table_subfactories.add{type="label", caption={"fp." .. factory_name}}

            valid_subfactory_found = valid_subfactory_found or subfactory.valid
        end
    end
    checkbox_master.enabled = valid_subfactory_found


    local flow_export = content_frame.add{type="flow", name="flow_export_subfactories", direction="horizontal"}

    flow_export.add{type="button", name="fp_button_export_subfactories", caption="Export subfactories",
      enabled=false, style="confirm_button", mouse_button_filter={"left"}}

    local textfield_export_string = flow_export.add{type="textfield", name="textfield_export_string"}
    textfield_export_string.style.width = 0  -- needs to be set to 0 so stretching works
    textfield_export_string.style.horizontally_stretchable = true
    textfield_export_string.style.left_margin = 12
end


function export_dialog.export_subfactories(player)
    local player_table = get_table(player)
    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]
    local table_subfactories = content_frame["frame_subfactories"]["table_subfactories"]

    local subfactories_to_export = {}
    for _, factory_name in ipairs{"factory", "archive"} do
        for _, subfactory in ipairs(Factory.get_in_order(player_table[factory_name], "Subfactory")) do
            local subfactory_checkbox = table_subfactories["fp_checkbox_porter_subfactory_" .. factory_name
              .. "_" .. subfactory.id]

            if subfactory_checkbox.state == true then
                table.insert(subfactories_to_export, subfactory)
            end
        end
    end

    local export_string = porter.get_export_string(player, subfactories_to_export)

    local textfield_export_string = content_frame["flow_export_subfactories"]["textfield_export_string"]
    textfield_export_string.text = export_string
    ui_util.select_all(textfield_export_string)
end



-- ** SHARED **
-- Sets all slave checkboxes to the given state
function porter_dialog.set_all_checkboxes(player, checkbox_state)
    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]

    for _, element in pairs(content_frame["frame_subfactories"]["table_subfactories"].children) do
        if string.find(element.name, "^fp_checkbox_porter_subfactory_[a-z]+_%d+$") and element.enabled then
            element.state = checkbox_state
        end
    end

    if get_ui_state(player).modal_dialog_type == "export" then
        local button_export = content_frame["flow_export_subfactories"]["fp_button_export_subfactories"]
        button_export.enabled = checkbox_state
    end
end

-- Sets the master checkbox to the appropriate state after a slave one is changed
function porter_dialog.adjust_after_checkbox_click(player)
    local content_frame = player.gui.screen["fp_frame_modal_dialog"]["flow_modal_dialog"]["frame_content"]
    local table_subfactories = content_frame["frame_subfactories"]["table_subfactories"]

    local checked_element_count, unchecked_element_count = 0, 0
    for _, element in pairs(table_subfactories.children) do
        if string.find(element.name, "^fp_checkbox_porter_subfactory_[a-z]+_%d+$") then
            if element.state == true then checked_element_count = checked_element_count + 1
            else unchecked_element_count = unchecked_element_count + 1 end
        end
    end

    table_subfactories["fp_checkbox_porter_master"].state = (unchecked_element_count == 0)

    if get_ui_state(player).modal_dialog_type == "export" then
        local button_export = content_frame["flow_export_subfactories"]["fp_button_export_subfactories"]
        button_export.enabled = (checked_element_count > 0)
    end
end