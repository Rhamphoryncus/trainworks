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

    if global.train_idle[train.id] > game.tick - 120 then
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

    global.train_idle[train.id] = nil
    global.train_actions[train.id] = {src=source, dest=dest, actions=actions}
    global.stop_actions[source.unit_number][train.id] = {actions=actions, pickup=true}
    global.stop_actions[dest.unit_number][train.id] = {actions=actions, pickup=false}
    log("Dispatched train " .. fstr(train.id) .. " from " .. source.backer_name .. " to " .. dest.backer_name)
end

function reset_train(train)
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

    global.train_idle[train.id] = game.tick
end

function extract_inventories(invs, itemname, amount)
    -- XXX FIXME should first attempt a balanced extraction
    local extracted = 0
    for i, inv in pairs(invs) do
        if amount - extracted <= 0 then
            break
        end
        extracted = extracted + inv.remove({name=itemname, count=(amount-extracted)})
    end
    return extracted
end

function insert_inventories(invs, itemname, amount)
    -- XXX FIXME should first attempt a balanced insertion
    -- Or maybe that should be a separate function used only on chests, not cargo wagons?
    -- Or maintain balance in the chests, not just the transfer amounts?
    local inserted = 0
    for i, inv in pairs(invs) do
        if amount - inserted <= 0 then
            break
        end
        inserted = inserted + inv.insert({name=itemname, count=(amount-inserted)})
    end
    return inserted
end

function transfer_inventories(src, dest, actions)
    for itemname, amount in pairs(actions) do
        local removed = extract_inventories(src, itemname, amount)
        if removed > 0 then
            local inserted = insert_inventories(dest, itemname, removed)
            local bounce = removed - inserted
            if bounce > 0 then
                log("Bounce: " .. fstr(bounce))
                local bounced = insert_inventories(src, itemname, bounce)
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


function find_stop_chests(stop)
    -- loop through the chest and each chest's neighbour, making sure they're aligned on the tracks (later) and have no stop registered yet
    -- if they have a stop abort the register, make the item drop or something instead.
    -- XXX better to check the stop orientation and detect chests exactly where they should be?
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

    local chestlist = {}

    -- XXX FIXME use search_for_stop() to make sure there isn't already a stop

    while true do
        if stop.direction == defines.direction.north then
            -- North facing stop means we go south each step to find the chests/wagons
            pos.y = pos.y - 7
        elseif stop.direction == defines.direction.south then
            pos.y = pos.y + 7
        elseif stop.direction == defines.direction.east then
            pos.x = pos.x - 7
        elseif stop.direction == defines.direction.west then
            pos.x = pos.x + 7
        end

        local chests = stop.surface.find_entities_filtered{type="container", position=pos}
        local chest = chests[1] -- XXX ugly

        log("Warg " .. fstr(stop) .. " (" .. fstr(stop.position) .. ") -> " .. fstr(chests) .. " (" .. fstr(pos) .. ")")
        if chest == nil then
            break
        end

        table.insert(chestlist, chest)
        log("Inserted 1 " .. serpent.line(chest) .. " into " .. serpent.line(chestlist) .. " of size " .. serpent.line(#chestlist))
    end

    -- XXX FIXME last_activity should be per-typename and provided vs requested
    global.stopchests[stop.unit_number] = {stop=stop, chests=chestlist, last_activity=game.tick}
    global.stop_actions[stop.unit_number] = {}
--    log("b2 " .. serpent.block(global.stopchests) .. " % " .. serpent.line(#global.stopchests))
--    log("ARGH " .. serpent.line(global.stopchests[stop.unit_number]))

--    local foo = {}
--    foo[stop] = "baz"
--    log("PBBT " .. serpent.dump(foo))
end


function search_for_stop(surface, pos, direction)
    pos = {x=pos.x, y=pos.y}  -- Clone pos so we don't modify the passed-in table

    while true do
        -- XXX check for stop first
        local stoppos = {x=pos.x, y=pos.y}
        if direction == defines.direction.north then
            stoppos.y = pos.y + 3
        elseif direction == defines.direction.south then
            stoppos.y = pos.y - 3
        elseif direction == defines.direction.east then
            stoppos.x = pos.x + 3
        elseif direction == defines.direction.west then
            stoppos.x = pos.x - 3
        end
        local stops = surface.find_entities_filtered{type="train-stop", position=stoppos}
        local stop = stops[1]  -- XXX ugly hack
--        log("Searched at " .. fstr(stoppos) .. " and " .. fstr(pos) .. " -> " .. fstr(stops) .. ", " .. fstr(stop))
        if stop ~= nil then
            return stop
        end

        local chests = surface.find_entities_filtered{type="container", position=pos}
        local chest = chests[1]  -- XXX ugly hack
        if chest == nil then
            return nil  -- No stop found
        end

        if direction == defines.direction.north then
            -- Following the orientation of the stop.  North-facing stop means we go north each step to reach it
            pos.y = pos.y + 7
        elseif direction == defines.direction.south then
            pos.y = pos.y - 7
        elseif direction == defines.direction.east then
            pos.x = pos.x + 7
        elseif direction == defines.direction.west then
            pos.x = pos.x - 7
        end
    end
end


function register_chest(chest)
    -- XXX FIXME check chest orientation, which may depend on having all the overlap stuff.  Assuming east-west for now.
    log("Feh " .. fstr(chest) .. " & " .. fstr(chest.position))
    local leftpos = {chest.position.x - 7, chest.position.y}
    local rightpos = {chest.position.x + 7, chest.position.y}
    local left = chest.surface.find_entities_filtered{type="container", position=leftpos}
    local right = chest.surface.find_entities_filtered{type="container", position=rightpos}

    local stop1 = search_for_stop(chest.surface, chest.position, defines.direction.east)
    local stop2 = search_for_stop(chest.surface, chest.position, defines.direction.west)
    log("searched: " .. fstr(stop1) .. ", " .. fstr(stop2))
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
        log("Entity renamed")
        -- XXX FIXME This should pull in trains idling here with an empty or 1 station schedule, if the new station name matches a route
    end
)
