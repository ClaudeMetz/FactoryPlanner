-- Handles populating the modal dialog to view or edit notes
function open_notes_dialog(flow_modal_dialog)
    create_notes_dialog_structure(flow_modal_dialog, {"label.notes"})
end

-- Handles closing of the notes dialog
function close_notes_dialog(flow_modal_dialog, action, data)
    if action == "submit" then
        local player = game.get_player(flow_modal_dialog.player_index)
        get_context(player).subfactory.notes = data.notes
    end
end

-- Returns all necessary instructions to create and run conditions on the modal dialog
function get_notes_condition_instructions()
    return {
        data = {
            notes = (function(flow_modal_dialog) return flow_modal_dialog["text-box_notes"].text end)
        },
        conditions = {
            [1] = {
                label = {"label.notes_instruction_1"},
                check = (function(data) return (#data.notes > 50000) end),
                refocus = (function(flow) flow["text-box_notes"].focus() end),
                show_on_edit = true
            }
        }
    }
end

-- Fills out the modal dialog to view or edit notes
function create_notes_dialog_structure(flow_modal_dialog, title)
    flow_modal_dialog.parent.caption = title

    -- Notes
    local player = game.get_player(flow_modal_dialog.player_index)
    local text_box_notes = flow_modal_dialog.add{type="text-box", name="text-box_notes", 
      text=get_context(player).subfactory.notes}
    text_box_notes.style.width = 600
    text_box_notes.style.height = 400
    text_box_notes.word_wrap = true
    text_box_notes.focus()
end