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


local tempstop = table.deepcopy(data.raw["train-stop"]["train-stop"])
tempstop.name = "tw_temporary_stop"
tempstop.collision_mask = nil
tempstop.collision_box = nil
tempstop.selection_box = nil
--tempstop.minable = false

local tempstop_item = table.deepcopy(data.raw.item["train-stop"])
tempstop_item.name = "tw_temporary_stop"
tempstop_item.place_result = "tw_temporary_stop"

data:extend{tempstop, tempstop_item}


local chest = table.deepcopy(data.raw.container["iron-chest"])
chest.name = "tw_chest_horizontal"
chest.inventory_size = 50
chest.collision_box = {{-2.9, -0.9}, {2.9, 0.9}}
chest.selection_box = {{-2.9, -0.9}, {2.9, 0.9}}
chest.picture.layers[1].scale = 2
chest.picture.layers[1].hr_version.scale = 1
chest.picture.layers[3] = table.deepcopy(chest.picture.layers[1])
chest.picture.layers[4] = table.deepcopy(chest.picture.layers[1])
chest.picture.layers[1].shift = util.by_pixel(-64, 0)
chest.picture.layers[3].shift = util.by_pixel(0, 0)
chest.picture.layers[4].shift = util.by_pixel(64, 0)
chest.picture.layers[1].hr_version.shift = util.by_pixel(-64, 0)
chest.picture.layers[3].hr_version.shift = util.by_pixel(0, 0)
chest.picture.layers[4].hr_version.shift = util.by_pixel(64, 0)

local chest_item = table.deepcopy(data.raw.item["iron-chest"])
chest_item.name = "tw_chest_horizontal"
chest_item.place_result = "tw_chest_horizontal"

local chest_recipe = table.deepcopy(data.raw.recipe["iron-chest"])
chest_recipe.enabled = true
chest_recipe.name = "tw_chest_horizontal"
chest_recipe.result = "tw_chest_horizontal"

data:extend{chest, chest_item, chest_recipe}


local chest = table.deepcopy(data.raw.container["iron-chest"])
chest.name = "tw_chest_vertical"
chest.inventory_size = 50
chest.collision_box = {{-0.9, -2.9}, {0.9, 2.9}}
chest.selection_box = {{-0.9, -2.9}, {0.9, 2.9}}
chest.picture.layers[1].scale = 2
chest.picture.layers[1].hr_version.scale = 1
chest.picture.layers[3] = table.deepcopy(chest.picture.layers[1])
chest.picture.layers[4] = table.deepcopy(chest.picture.layers[1])
chest.picture.layers[1].shift = util.by_pixel(0, -64)
chest.picture.layers[3].shift = util.by_pixel(0, 0)
chest.picture.layers[4].shift = util.by_pixel(0, 64)
chest.picture.layers[1].hr_version.shift = util.by_pixel(0, -64)
chest.picture.layers[3].hr_version.shift = util.by_pixel(0, 0)
chest.picture.layers[4].hr_version.shift = util.by_pixel(0, 64)

local chest_item = table.deepcopy(data.raw.item["iron-chest"])
chest_item.name = "tw_chest_vertical"
chest_item.place_result = "tw_chest_vertical"

local chest_recipe = table.deepcopy(data.raw.recipe["iron-chest"])
chest_recipe.enabled = true
chest_recipe.name = "tw_chest_vertical"
chest_recipe.result = "tw_chest_vertical"

data:extend{chest, chest_item, chest_recipe}
