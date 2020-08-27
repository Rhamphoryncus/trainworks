local tech = {
    type = "technology",
    name = "trainworks_tech",
    icon_size = 128,
    icon = "__base__/graphics/technology/automated-rail-transportation.png",
    effects = {
        {
            type = "unlock-recipe",
            recipe = "trainworks_depot"
        },
        {
            type = "unlock-recipe",
            recipe = "trainworks_stop"
        },
        {
            type = "unlock-recipe",
            recipe = "trainworks_chest_horizontal"
        },
        {
            type = "unlock-recipe",
            recipe = "trainworks_chest_vertical"
        },
        {
            type = "unlock-recipe",
            recipe = "trainworks_tank"
        }
    },
    prerequisites = {"automated-rail-transportation"},
    unit = {
        count = 100,
        ingredients = {
            {"automation-science-pack", 1},
            {"logistic-science-pack", 1}
        },
        time = 30
    },
    order = "c-g-b"
}

data:extend{tech}
