-- Patch the vanilla train-stop to be in a fast replacement group
local fastreplace = data.raw["train-stop"]["train-stop"].fast_replaceable_group
if fastreplace == nil then
    fastreplace = "train-stop"
    data.raw["train-stop"]["train-stop"].fast_replaceable_group = fastreplace
end


local depot = table.deepcopy(data.raw["train-stop"]["train-stop"])
depot.name = "trainworks_depot"
depot.color = {a=0.5, r=0, g=0, b=0.95}
depot.fast_replaceable_group = fastreplace

local depot_item = table.deepcopy(data.raw.item["train-stop"])
depot_item.name = "trainworks_depot"
depot_item.place_result = "trainworks_depot"
depot_item.icon = "__Trainworks__/graphics/depot.png"

local depot_recipe = table.deepcopy(data.raw.recipe["train-stop"])
depot_recipe.name = "trainworks_depot"
depot_recipe.result = "trainworks_depot"

data:extend{depot, depot_item, depot_recipe}


local stop = table.deepcopy(data.raw["train-stop"]["train-stop"])
stop.name = "trainworks_stop"
stop.color = {a=0.5, r=0.75, g=0.5, b=0}
stop.fast_replaceable_group = fastreplace

local stop_item = table.deepcopy(data.raw.item["train-stop"])
stop_item.name = "trainworks_stop"
stop_item.place_result = "trainworks_stop"
stop_item.icon = "__Trainworks__/graphics/stop.png"

local stop_recipe = table.deepcopy(data.raw.recipe["train-stop"])
stop_recipe.name = "trainworks_stop"
stop_recipe.result = "trainworks_stop"

data:extend{stop, stop_item, stop_recipe}


local chest = table.deepcopy(data.raw.container["iron-chest"])
chest.name = "trainworks_chest_horizontal"
chest.inventory_size = 400
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
chest_item.name = "trainworks_chest_horizontal"
chest_item.place_result = "trainworks_chest_horizontal"

local chest_recipe = table.deepcopy(data.raw.recipe["iron-chest"])
chest_recipe.name = "trainworks_chest_horizontal"
chest_recipe.result = "trainworks_chest_horizontal"

data:extend{chest, chest_item, chest_recipe}


local chest = table.deepcopy(data.raw.container["iron-chest"])
chest.name = "trainworks_chest_vertical"
chest.inventory_size = 400
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
chest_item.name = "trainworks_chest_vertical"
chest_item.place_result = "trainworks_chest_vertical"

local chest_recipe = table.deepcopy(data.raw.recipe["iron-chest"])
chest_recipe.name = "trainworks_chest_vertical"
chest_recipe.result = "trainworks_chest_vertical"

data:extend{chest, chest_item, chest_recipe}


local tank = table.deepcopy(data.raw["storage-tank"]["storage-tank"])
tank.name = "trainworks_tank"
tank.collision_box = {{-2.9, -0.9}, {2.9, 0.9}}
tank.selection_box = {{-2.9, -0.9}, {2.9, 0.9}}
tank.fluid_box = {
    base_area = 500,
    pipe_connections = {
        {position = {2.5, 1.5}},
        {position = {2.5, -1.5}},
        {position = {-2.5, 1.5}},
        {position = {-2.5, -1.5}},
        {position = {3.5, 0.5}},
        {position = {3.5, -0.5}},
        {position = {-3.5, 0.5}},
        {position = {-3.5, -0.5}},
    }
}
tank.minable.result = "trainworks_tank"

local tank_item = table.deepcopy(data.raw.item["storage-tank"])
tank_item.name = "trainworks_tank"
tank_item.place_result = "trainworks_tank"

local tank_recipe = table.deepcopy(data.raw.recipe["storage-tank"])
tank_recipe.name = "trainworks_tank"
tank_recipe.result = "trainworks_tank"

data:extend{tank, tank_item, tank_recipe}
