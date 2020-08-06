-- Loading of trains and managing stops


function train_is_idling(trainid, train)
    if not train.valid then
        global.cleanup_trains[trainid] = train
        return false
    end

    if train.state ~= defines.train_state.wait_station
            or train.station == nil
            or train.station.prototype.name ~= "tw_depot"
            then
        return false
    end

    if global.train_lastactivity[trainid] > game.tick - 120 then
        return false
    end

    for x, loco in pairs(train.locomotives.front_movers) do
        local inv = loco.get_inventory(defines.inventory.fuel)
        local empty = inv.count_empty_stacks{include_filtered=true}
        if empty > 0 then
            return false
        end
    end

    for x, loco in pairs(train.locomotives.back_movers) do
        local inv = loco.get_inventory(defines.inventory.fuel)
        local empty = inv.count_empty_stacks{include_filtered=true}
        if empty > 0 then
            return false
        end
    end

    for x, wagon in pairs(train.cargo_wagons) do
        local inv = wagon.get_inventory(defines.inventory.cargo_wagon)
        if not inv.is_empty() then
            return false
        end
    end

    return true
end


function dispatch_train(routenum, sourcenum, destnum, actions)
    local train = nil
    for maybetrainid, maybetrain in pairs(global.routes[routenum].trains) do
        if train_is_idling(maybetrainid, maybetrain) then
            train = maybetrain
            break
        end
    end
    if train == nil then
        -- No train available
        return
    end
    log("Found depoted train: " .. fstr(train.state) .. " at " .. train.station.backer_name)

    global.stop_idletrain[train.station.unit_number] = nil

    local source = global.stopchests[sourcenum].stop
    local dest = global.stopchests[destnum].stop
    if not source.valid or not dest.valid or not source.connected_rail or not dest.connected_rail then
        return
    end

    local x = {
        current=1,
        records={
            {rail=source.connected_rail, wait_conditions={{type="time", compare_type="and", ticks=120}}},
            {rail=dest.connected_rail, wait_conditions={{type="time", compare_type="and", ticks=120}}},
            {station=train.station.backer_name, wait_conditions={}}
        }
    }
    train.schedule = x

    global.train_lastactivity[train.id] = nil
    global.trains[train.id].src = source
    global.trains[train.id].dest = dest
    global.trains[train.id].actions = actions
    global.stop_actions[source.unit_number][train.id] = {actions=actions, pickup=true}
    global.stop_actions[dest.unit_number][train.id] = {actions=actions, pickup=false}
    log("Dispatched train " .. fstr(train.id) .. " from " .. source.backer_name .. " to " .. dest.backer_name)
end

function reset_train(trainid, train)
    if global.trains[trainid] == nil then
        global.trains[trainid] = {train=train}
    else
        if global.trains[trainid].src ~= nil then
            global.stop_actions[global.trains[trainid].src.unit_number][trainid] = nil  -- Delete the pickup action
        end
        if global.trains[trainid].dest ~= nil then
            global.stop_actions[global.trains[trainid].dest.unit_number][trainid] = nil  -- Delete the dropoff action
        end
        global.trains[trainid].src = nil
        global.trains[trainid].dest = nil
        global.trains[trainid].actions = nil
    end
    if not train.valid then
        global.train_lastactivity[trainid] = nil
        -- XXX Looping here is a bit of a bodge
        for routenum, x in pairs(global.routes) do
            x.trains[trainid] = nil
        end
        return
    end

    global.stop_idletrain[train.station.unit_number] = train

    local routenum = global.route_map[train.station.backer_name]
    if routenum == nil then
        -- Train is orphaned.  Route was renamed or deleted.
        train.schedule = nil
        return
    end

    global.routes[routenum].trains[trainid] = train

    local x = {
        current=1,
        records={
            {station=train.station.backer_name, wait_conditions={}}
        }
    }
    train.schedule = x

    global.train_lastactivity[trainid] = game.tick
end


function transfer_inventories_balanced(invs, itemname, amount, extract)
    -- First pass, find out how much is already stored
    local found = {}
    local found_total = 0
    for i, inv in pairs(invs) do
        local x = inv.get_item_count(itemname)
        found[i] = x
        found_total = found_total + x
    end
    local target = nil
    if extract then
        target = math.ceil((found_total - amount) / #invs)
    else
        target = math.floor((found_total + amount) / #invs)
    end

    -- Second pass, bring every inventory up to the average (target) amount
    local transferred = 0
    for i, inv in pairs(invs) do
        local count = nil
        if extract then
            count = found[i] - target
        else
            count = target - found[i]
        end

        if count + transferred > amount then
            count = amount - transferred
        end
        if count > 0 then
            if extract then
                transferred = transferred + inv.remove({name=itemname, count=count})
            else
                transferred = transferred + inv.insert({name=itemname, count=count})
            end
        end
    end

    -- Third pass, squeeze in any remainder anywhere there's space
    if transferred < amount then
        for i, inv in pairs(invs) do
            if amount - transferred <= 0 then
                break
            end
            if extract then
                transferred = transferred + inv.remove({name=itemname, count=(amount-transferred)})
            else
                transferred = transferred + inv.insert({name=itemname, count=(amount-transferred)})
            end
        end
    end

    return transferred
end

function transfer_inventories(src, dest, actions)
    for itemname, amount in pairs(actions) do
        local removed = transfer_inventories_balanced(src, itemname, amount, true)
        if removed > 0 then
            local inserted = transfer_inventories_balanced(dest, itemname, removed, false)
            local bounce = removed - inserted
            if bounce > 0 then
                log("Bounce: " .. fstr(bounce))
                local bounced = transfer_inventories_balanced(src, itemname, bounce, false)
                if bounce ~= bounced then
                    -- XXX print an error to console.  This might happen if a user applies filters or a bar to a chest/wagon
                    log("Unable to bounce, items deleted!")
                end
            end
        end
    end
end

function get_chest_inventories(stopnum)
    local invs = {}
    local chests = global.stopchests[stopnum].chests
    for i, chest in pairs(chests) do
        if chest.valid then
            table.insert(invs, chest.get_inventory(defines.inventory.chest))
        end
    end
    return invs
end

function get_train_inventories(train)
    local invs = {}
    for i, wagon in pairs(train.cargo_wagons) do
        table.insert(invs, wagon.get_inventory(defines.inventory.cargo_wagon))
    end
    return invs
end

function action_train(train)
    -- Load/unload the train as it arrives at a station
    local action = global.trains[train.id]
    log("Carriages: " .. fstr(train.carriages))
    log("Schedule index: " .. fstr(train.schedule.current))

    if train.schedule.current == 1 then
        -- Load
        transfer_inventories(get_chest_inventories(action.src.unit_number), get_train_inventories(train), action.actions)
        global.stopchests[action.src.unit_number].last_activity = game.tick

        global.stop_actions[action.src.unit_number][train.id] = nil  -- Delete the pickup action
    elseif train.schedule.current == 2 then
        -- Unload
        transfer_inventories(get_train_inventories(train), get_chest_inventories(action.dest.unit_number), action.actions)
        global.stopchests[action.dest.unit_number].last_activity = game.tick

        global.stop_actions[action.dest.unit_number][train.id] = nil  -- Delete the dropoff action
    end
end


valid_container_types = {
    tw_chest_horizontal = true,
    tw_chest_vertical = true
}


function find_chests(surface, x, y, direction)
    -- Note: skips the first location
    local chestlist = {}
    local last_x, last_y = x, y

    while true do
        if direction == defines.direction.north then
            y = y - 7
        elseif direction == defines.direction.south then
            y = y + 7
        elseif direction == defines.direction.east then
            x = x + 7
        elseif direction == defines.direction.west then
            x = x - 7
        end

        --game.print("Searching for chest at " .. fstr(x) .. "," .. fstr(y))
        local chests = surface.find_entities_filtered{type="container", position={x, y}}
        local chest = chests[1] -- XXX ugly
        -- XXX FIXME check against valid_container_types

        if chest == nil or not valid_container_types[chest.name] then
            break
        end

        table.insert(chestlist, chest)
        last_x, last_y = x, y
    end

    return chestlist, last_x, last_y
end


flip_direction = {}
flip_direction[defines.direction.north] = defines.direction.south
flip_direction[defines.direction.northeast] = defines.direction.southwest
flip_direction[defines.direction.east] = defines.direction.west
flip_direction[defines.direction.southeast] = defines.direction.northwest
flip_direction[defines.direction.south] = defines.direction.north
flip_direction[defines.direction.southwest] = defines.direction.northeast
flip_direction[defines.direction.west] = defines.direction.east
flip_direction[defines.direction.northwest] = defines.direction.southeast


function find_stop_chests(stop)
    -- Chests on the same side as the stop
    local x, y = stop.position.x, stop.position.y
    if stop.direction == defines.direction.north then
        -- North facing trainstop means the first wagon is a bit south of it
        y = y + 3
    elseif stop.direction == defines.direction.south then
        y = y - 3
    elseif stop.direction == defines.direction.east then
        x = x - 3
    elseif stop.direction == defines.direction.west then
        x = x + 3
    end

    local chestlist = find_chests(stop.surface, x, y, flip_direction[stop.direction])
    --game.print("find_stop_chests same: " .. fstr(stop) .. " -> " .. fstr(chestlist) .. " [" .. fstr(x) .. "," .. fstr(y) .. "]")

    -- Chests on the opposite side from the stop
    local x, y = stop.position.x, stop.position.y
    if stop.direction == defines.direction.north then
        -- North facing trainstop means the first wagon is a bit south of it
        x = x - 4
        y = y + 3
    elseif stop.direction == defines.direction.south then
        x = x + 4
        y = y - 3
    elseif stop.direction == defines.direction.east then
        x = x - 3
        y = y - 4
    elseif stop.direction == defines.direction.west then
        x = x + 3
        y = y + 4
    end

    local chestlist2 = find_chests(stop.surface, x, y, flip_direction[stop.direction])
    --game.print("find_stop_chests opposite: " .. fstr(stop) .. " -> " .. fstr(chestlist2) .. " [" .. fstr(x) .. "," .. fstr(y) .. "]")

    -- Merge the two lists
    for x, chest in pairs(chestlist2) do
        table.insert(chestlist, chest)
    end
    --if #chestlist > 0 then
    --    game.print("Chestlist " .. fstr(stop) .. " -> " .. fstr(chestlist))
    --end

    -- XXX FIXME last_activity should be per-typename and provided vs requested
    global.stopchests[stop.unit_number] = {stop=stop, chests=chestlist, last_activity=game.tick}
    global.stop_actions[stop.unit_number] = {}
end


function search_for_stop_same(surface, pos, direction)
    local chestlist, x, y = find_chests(surface, pos.x, pos.y, direction)
    --game.print("search_for_stop_same (" .. fstr(direction) .. "): x:" .. fstr(x) .. " y:" .. fstr(y) .. "  " .. fstr(chestlist))

    if direction == defines.direction.north then
        y = y - 10
    elseif direction == defines.direction.south then
        y = y + 10
    elseif direction == defines.direction.east then
        x = x + 10
    elseif direction == defines.direction.west then
        x = x - 10
    end

    local stops = surface.find_entities_filtered{type="train-stop", position={x, y}}
    local stop = stops[1]  -- XXX ugly hack
    --game.print("Found: " .. fstr(stop))

    return stop
end


function search_for_stop_opposite(surface, pos, direction)
    local chestlist, x, y = find_chests(surface, pos.x, pos.y, direction)
    --game.print("search_for_stop_opposite (" .. fstr(direction) .. "): x:" .. fstr(x) .. " y:" .. fstr(y) .. "  " .. fstr(chestlist))

    if direction == defines.direction.north then
        x = x + 4
        y = y - 10
    elseif direction == defines.direction.south then
        x = x - 4
        y = y + 10
    elseif direction == defines.direction.east then
        x = x + 10
        y = y + 4
    elseif direction == defines.direction.west then
        x = x - 10
        y = y - 4
    end

    local stops = surface.find_entities_filtered{type="train-stop", position={x, y}}
    local stop = stops[1]  -- XXX ugly hack
    --game.print("Found: " .. fstr(stop))

    return stop
end


function register_chest(chest)
    local stops = nil

    -- XXX FIXME generalize this for future expansion, such as bot logistic chests
    if chest.name == "tw_chest_horizontal" then
        stops = {
            search_for_stop_same(chest.surface, chest.position, defines.direction.east),
            search_for_stop_same(chest.surface, chest.position, defines.direction.west),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.east),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.west)
        }
    elseif chest.name == "tw_chest_vertical" then
        stops = {
            search_for_stop_same(chest.surface, chest.position, defines.direction.north),
            search_for_stop_same(chest.surface, chest.position, defines.direction.south),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.north),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.south)
        }
    end

    -- XXX I allow multiple stops to use the same chest.  Trains might get a bit confused but it's not catastrophic
    for i, stop in pairs(stops) do
        find_stop_chests(stop)
    end
end


script.on_event({defines.events.on_entity_renamed},
    function (e)
        if e.entity.prototype.name == "tw_depot" then
            local train = global.stop_idletrain[e.entity.unit_number]

            if train ~= nil and train.state == defines.train_state.wait_station and train.station == e.entity then
                local routenum = global.route_map[e.entity.backer_name]
                if routenum ~= nil then
                    global.routes[routenum].trains[train.id] = train
                end
            else
                global.stop_idletrain[e.entity.unit_number] = nil
            end
        end
    end
)
