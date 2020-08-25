local priority = {
    type = "virtual-signal",
    name = "trainworks_priority",
    icon = "__base__/graphics/icons/list-dot.png",
    icon_size = 64, icon_mipmaps = 4,
    subgroup = "virtual-signal",
    order = "e[signal]-[priority]"
}

data:extend{priority}
