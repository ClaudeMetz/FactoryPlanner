-- Creates the production pane that displays 
function add_production_pane_to(main_dialog, player)
    local title = main_dialog.add{type="label", name="label_production_pane_title", caption={"", "  ", {"label.production"}}}
    title.style.top_padding = 8
    title.style.bottom_padding = 30
    title.style.font = "fp-button-standard"
end