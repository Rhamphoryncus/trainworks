local depot = table.deepcopy(data.raw["train-stop"]["train-stop"])
depot.name = "tw_depot"

local depot_item = table.deepcopy(data.raw.item["train-stop"])
depot_item.name = "tw_depot"
depot_item.place_result = "tw_depot"

local depot_recipe = table.deepcopy(data.raw.recipe["train-stop"])
depot_recipe.enabled = true
depot_recipe.name = "tw_depot"
depot_recipe.result = "tw_depot"

data:extend{depot, depot_item, depot_recipe}


local stop = table.deepcopy(data.raw["train-stop"]["train-stop"])
stop.name = "tw_stop"

local stop_item = table.deepcopy(data.raw.item["train-stop"])
stop_item.name = "tw_stop"
stop_item.place_result = "tw_stop"

local stop_recipe = table.deepcopy(data.raw.recipe["train-stop"])
stop_recipe.enabled = true
stop_recipe.name = "tw_stop"
stop_recipe.result = "tw_stop"

data:extend{stop, stop_item, stop_recipe}


local chest = table.deepcopy(data.raw.container["iron-chest"])
chest.name = "tw_chest"
chest.inventory_size = 50
chest.collision_box = {{-2.9, -0.9}, {2.9, 0.9}}
chest.selection_box = {{-2.9, -0.9}, {2.9, 0.9}}

local chest_item = table.deepcopy(data.raw.item["iron-chest"])
chest_item.name = "tw_chest"
chest_item.place_result = "tw_chest"

local chest_recipe = table.deepcopy(data.raw.recipe["iron-chest"])
chest_recipe.enabled = true
chest_recipe.name = "tw_chest"
chest_recipe.result = "tw_chest"

data:extend{chest, chest_item, chest_recipe}
