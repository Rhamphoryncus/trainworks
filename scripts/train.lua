-- Loading of trains and managing stops


function train_is_idling(train)
    if not train.valid then
        return false
    end

    if train.state ~= defines.train_state.wait_station
            or train.station == nil
            or train.station.prototype.name ~= "tw_depot"
            then
        return false
    end

    if global.train_lastactivity[train.id] > game.tick - 120 then
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
        if train_is_idling(maybetrain) then
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
    if not source.valid or not dest.valid then
        return
    end

    local x = {
        current=1,
        records={
            {station=source.backer_name, wait_conditions={{type="time", compare_type="and", ticks=120}}},
            {station=dest.backer_name, wait_conditions={{type="time", compare_type="and", ticks=120}}},
            {station=train.station.backer_name, wait_conditions={}}
        }
    }
    train.schedule = x

    global.train_lastactivity[train.id] = nil
    global.train_actions[train.id] = {src=source, dest=dest, actions=actions}
    global.stop_actions[source.unit_number][train.id] = {actions=actions, pickup=true}
    global.stop_actions[dest.unit_number][train.id] = {actions=actions, pickup=false}
    log("Dispatched train " .. fstr(train.id) .. " from " .. source.backer_name .. " to " .. dest.backer_name)
end

function reset_train(train)
    global.stop_idletrain[train.station.unit_number] = train

    local routenum = global.route_map[train.station.backer_name]
    if routenum == nil then
        -- Train is orphaned.  Route was renamed or deleted.
        train.schedule = nil
        return
    end

    global.routes[routenum].trains[train.id] = train

    local x = {
        current=1,
        records={
            {station=train.station.backer_name, wait_conditions={}}
        }
    }
    train.schedule = x

    global.train_lastactivity[train.id] = game.tick
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
        table.insert(invs, chest.get_inventory(defines.inventory.chest))
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
    local action = global.train_actions[train.id]
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
        global.train_actions[train.id] = nil
    end
end


function find_chests(surface, x, y, direction)
    -- Note: skips the first location
    local chestlist = {}
    local last_x, last_y = x, y

    while true do
        if direction == defines.direction.north then
            y = y + 7
        elseif direction == defines.direction.south then
            y = y - 7
        elseif direction == defines.direction.east then
            x = x + 7
        elseif direction == defines.direction.west then
            x = x - 7
        end

        local chests = surface.find_entities_filtered{type="container", position={x, y}}
        local chest = chests[1] -- XXX ugly

        if chest == nil then
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
    local offset = {0.0, 0.0}
    local pos = stop.position
    if stop.direction == defines.direction.north then
        -- North facing trainstop means the first wagon is a bit south of it
        pos.y = pos.y - 3
    elseif stop.direction == defines.direction.south then
        pos.y = pos.y + 3
    elseif stop.direction == defines.direction.east then
        pos.x = pos.x - 3
    elseif stop.direction == defines.direction.west then
        pos.x = pos.x + 3
    end

    local chestlist = find_chests(stop.surface, pos.x, pos.y, flip_direction[stop.direction])
    --game.print("find_stop_chests: " .. fstr(chestlist))

    -- XXX FIXME last_activity should be per-typename and provided vs requested
    global.stopchests[stop.unit_number] = {stop=stop, chests=chestlist, last_activity=game.tick}
    global.stop_actions[stop.unit_number] = {}
end


function search_for_stop(surface, pos, direction)
    local chestlist, x, y = find_chests(surface, pos.x, pos.y, direction)
    --game.print("search_for_stop (" .. fstr(direction) .. "): x:" .. fstr(x) .. " y:" .. fstr(y) .. "  " .. fstr(chestlist))

    if direction == defines.direction.north then
        y = y + 10
    elseif direction == defines.direction.south then
        y = y - 10
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


function register_chest(chest)
    -- XXX FIXME check chest orientation, which may depend on having all the overlap stuff.  Assuming east-west for now.
    --log("Feh " .. fstr(chest) .. " & " .. fstr(chest.position))
    local leftpos = {chest.position.x - 7, chest.position.y}
    local rightpos = {chest.position.x + 7, chest.position.y}
    local left = chest.surface.find_entities_filtered{type="container", position=leftpos}
    local right = chest.surface.find_entities_filtered{type="container", position=rightpos}

    local stop1 = search_for_stop(chest.surface, chest.position, defines.direction.east)
    local stop2 = search_for_stop(chest.surface, chest.position, defines.direction.west)
    --log("searched: " .. fstr(stop1) .. ", " .. fstr(stop2))
    if stop1 ~= nil and stop2 ~= nil then
        -- XXX return an error.  Stops aren't allowed to overlap and use the same set of chests.
        log("Error, would merge chest strings")
        return
    end

    if stop1 ~= nil then
        find_stop_chests(stop1)
    elseif stop2 ~= nil then
        find_stop_chests(stop2)
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
