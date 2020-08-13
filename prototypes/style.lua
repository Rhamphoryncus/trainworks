-- Limit size of the scroll pane so it doesn't trigger another scrollbar in the mod-gui container
data.raw["gui-style"].default["trainworks_scroll_pane"] = {
    type = "scroll_pane_style",
    parent = "scroll_pane",
    maximal_height = 525
}
