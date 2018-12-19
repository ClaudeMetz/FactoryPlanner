-- Creates the titlebar including name and exit-button
function add_titlebar_to(main_dialog)
    local titlebar = main_dialog.add{type="flow", name="titlebar", direction="horizontal"}
    titlebar.style.top_padding = 4
    
    titlebar.add{type="label", name="label_titlebar_name", caption=" Factory Planner"}
    titlebar["label_titlebar_name"].style.font="fp-label-supersized"
    titlebar["label_titlebar_name"].style.top_padding = 0

    titlebar.add{type="flow", name="flow_titlebar_spacing", direction="horizontal"}
    titlebar["flow_titlebar_spacing"].style.width=550

    titlebar.add{type="button", name="button_titlebar_exit", caption="X", style="fp_button_exit"}
end