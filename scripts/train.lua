-- Loading of trains and managing stops


function train_status_refueling(trainid, train)
    local status_bad = {"gui.train_status_refueling"}

    -- XXX Minor bug: last_fuel doesn't get updated when there isn't a job being dispatched.  However, this is harmless so long as fuel is always being maintained as full, which is the normal case.
    if train.state ~= defines.train_state.wait_station
            or train.station == nil
            or train.station.prototype.name ~= "trainworks_depot"
            then
        return false, ""
    end

    local fuel = merge_inventories(get_train_fuels(train))
    if global.trains[trainid].last_fuel == nil or not compare_dictionaries(fuel, global.trains[trainid].last_fuel) then
        global.trains[trainid].last_fuel = fuel
        global.trains[trainid].last_activity = game.tick
        return true, status_bad
    end

    if global.trains[trainid].last_activity > game.tick - 120 then
        return true, status_bad
    end

    for x, loco in pairs(train.locomotives.front_movers) do
        local inv = loco.get_inventory(defines.inventory.fuel)
        local empty = inv.count_empty_stacks{include_filtered=true}
        if empty > 0 then
            return true, status_bad
        end
    end

    for x, loco in pairs(train.locomotives.back_movers) do
        local inv = loco.get_inventory(defines.inventory.fuel)
        local empty = inv.count_empty_stacks{include_filtered=true}
        if empty > 0 then
            return true, status_bad
        end
    end

    return false, ""
end

function train_status_garbage(trainid, train)
    if train.state ~= defines.train_state.wait_station
            or train.station == nil
            or train.station.prototype.name ~= "trainworks_depot"
            then
        return false, ""
    end

    for x, wagon in pairs(train.cargo_wagons) do
        local inv = wagon.get_inventory(defines.inventory.cargo_wagon)
        if not inv.is_empty() then
            return true, {"gui.train_status_garbage"}
        end
    end

    for x, wagon in pairs(train.fluid_wagons) do
        if wagon.fluidbox[1] ~= nil then
            return true, {"gui.train_status_garbage"}
        end
    end

    return false, ""
end

function train_status_error(trainid, train)
    if train.state == defines.train_state.no_path then
        return true, {"gui.train_status_no_path"}
    elseif train.state == defines.train_state.no_schedule then
        return true, {"gui.train_status_no_schedule"}
    elseif train.state == defines.train_state.manual_control or train.state == defines.train_state_manual_control_stop then
        return true, {"gui.train_status_manual"}
    else
        return false, ""
    end
end

function train_is_idling(trainid, train, itemname)
    if not train.valid then
        global.cleanup_trains[trainid] = train
        return false
    end

    if train.state ~= defines.train_state.wait_station
            or train.station == nil
            or train.station.prototype.name ~= "trainworks_depot"
            then
        return false
    end

    -- Make sure the train has the right wagons for this cargo
    if game.fluid_prototypes[itemname] ~= nil and next(train.fluid_wagons) == nil then
        return false
    elseif game.item_prototypes[itemname] ~= nil and next(train.cargo_wagons) == nil then
        return false
    end

    if train_status_refueling(trainid, train) then
        return false
    end

    if train_status_garbage(trainid, train) then
        return false
    end

    if train_status_error(trainid, train) then
        return false
    end

    return true
end


function find_idling_train(routenum, itemname)
    for trainid, train in pairs(global.routes[routenum].trains) do
        if train_is_idling(trainid, train, itemname) then
            return train
        end
    end

    return nil  -- No train available
end


function dispatch_train(train, sourcenum, destnum, actions)
    global.depot_idletrain[train.station.unit_number] = nil

    local source = global.stops[sourcenum].stop
    local dest = global.stops[destnum].stop
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

    global.trains[train.id].src = source
    global.trains[train.id].dest = dest
    global.trains[train.id].actions = actions
    global.stops[source.unit_number].actions[train.id] = {actions=actions, pickup=true}
    global.stops[dest.unit_number].actions[train.id] = {actions=actions, pickup=false}
end

function reset_train(trainid, train)
    if global.trains[trainid] == nil then
        global.trains[trainid] = {train=train, status="", issue=false}
        global.trains_dirty = true
    else
        if global.trains[trainid].src ~= nil then
            global.stops[global.trains[trainid].src.unit_number].actions[trainid] = nil  -- Delete the pickup action
        end
        if global.trains[trainid].dest ~= nil then
            global.stops[global.trains[trainid].dest.unit_number].actions[trainid] = nil  -- Delete the dropoff action
        end
        global.trains[trainid].src = nil
        global.trains[trainid].dest = nil
        global.trains[trainid].actions = nil
    end
    if not train.valid then
        -- XXX Looping here is a bit of a bodge
        for routenum, x in pairs(global.routes) do
            x.trains[trainid] = nil
        end
        global.trains[trainid] = nil
        return
    end

    global.depot_idletrain[train.station.unit_number] = train

    local routenum = global.route_map[train.station.backer_name]
    if routenum == nil then
        -- Train is orphaned.  Route was renamed or deleted.
        train.schedule = nil
        return
    end

    assign_train(routenum, trainid)

    local x = {
        current=1,
        records={
            {station=train.station.backer_name, wait_conditions={}}
        }
    }
    train.schedule = x

    global.trains[trainid].last_activity = game.tick
end


function inv_count(inv, itemname)
    if pcall(function() return inv.owner.type == "storage-tank" end) then
        if inv[1] ~= nil and inv[1].name == itemname then
            return math.floor(inv[1].amount)
        else
            return 0
        end
    elseif pcall(function() return inv.entity_owner.type == "container" end) then
        if game.item_prototypes[itemname] ~= nil then
            return inv.get_item_count(itemname)
        else
            return 0
        end
    else
        error("Unexpected type of inventory")
    end
end

function inv_space(inv, itemname)
    if pcall(function() return inv.owner.type == "storage-tank" end) then
        local proto = game.fluid_prototypes[itemname]
        if proto then
            return inv.get_capacity(1)
        else
            return 0
        end
    elseif pcall(function() return inv.entity_owner.type == "container" end) then
        local proto = game.item_prototypes[itemname]
        if proto then
            return #inv * proto.stack_size
        else
            return 0
        end
    else
        error("Unexpected type of inventory")
    end
end

function inv_contents(inv)
    if pcall(function() return inv.owner.type == "storage-tank" end) then
        local contents = {}
        if inv[1] ~= nil then
            contents[inv[1].name] = math.floor(inv[1].amount)
        end
        return contents
    elseif pcall(function() return inv.entity_owner.type == "container" end) then
        return inv.get_contents()
    else
        error("Unexpected type of inventory")
    end
end

function inv_add(inv, itemname, count)
    if pcall(function() return inv.owner.type == "storage-tank" end) then
        local subbox = inv[1]
        if subbox == nil then
            subbox = {name=itemname, amount=0}
        elseif subbox.name ~= itemname then
            return 0
        end

        local count = math.min(inv.get_capacity(1) - subbox.amount, count)
        subbox.amount = subbox.amount + count
        inv[1] = subbox
        return count
    elseif pcall(function() return inv.entity_owner.type == "container" end) then
        if game.item_prototypes[itemname] ~= nil then
            return inv.insert({name=itemname, count=count})
        else
            return 0
        end
    else
        error("Unexpected type of inventory")
    end
end

function inv_subtract(inv, itemname, count)
    if pcall(function() return inv.owner.type == "storage-tank" end) then
        local subbox = inv[1]
        if subbox.name ~= itemname then
            return 0
        end

        local count = math.min(subbox.amount, count)
        subbox.amount = subbox.amount - count
        if subbox.amount > 0 then
            inv[1] = subbox
        else
            inv[1] = nil
        end
        return count
    elseif pcall(function() return inv.entity_owner.type == "container" end) then
        return inv.remove({name=itemname, count=count})
    else
        error("Unexpected type of inventory")
    end
end

function transfer_inventories_balanced(invs, itemname, amount, extract)
    -- First pass, find out how much is already stored
    local found = {}
    local found_total = 0
    for i, inv in pairs(invs) do
        local x = inv_count(inv, itemname)
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
                transferred = transferred + inv_subtract(inv, itemname, count)
            else
                transferred = transferred + inv_add(inv, itemname, count)
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
                transferred = transferred + inv_subtract(inv, itemname, amount-transferred)
            else
                transferred = transferred + inv_add(inv, itemname, amount-transferred)
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
                local bounced = transfer_inventories_balanced(src, itemname, bounce, false)
                if bounce ~= bounced then
                    -- XXX print an error to console.  This might happen if a user applies filters or a bar to a chest/wagon
                    game.print("Unable to bounce, items deleted!  " .. itemname .. "=" ..tostring(bounce-bounced))
                end
            end
        end
    end
end

function get_chest_inventories(stopnum)
    local invs = {}
    local chests = global.stops[stopnum].chests
    for i, chest in pairs(chests) do
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest)
            if inv == nil then
                inv = chest.fluidbox
            end
            table.insert(invs, inv)
        end
    end
    return invs
end

function get_train_inventories(train)
    local invs = {}
    for i, wagon in pairs(train.cargo_wagons) do
        table.insert(invs, wagon.get_inventory(defines.inventory.cargo_wagon))
    end
    for i, wagon in pairs(train.fluid_wagons) do
        table.insert(invs, wagon.fluidbox)
    end
    return invs
end

function get_train_fuels(train)
    local invs = {}
    for i, wagon in pairs(train.locomotives.front_movers) do
        table.insert(invs, wagon.get_inventory(defines.inventory.fuel))
    end
    for i, wagon in pairs(train.locomotives.back_movers) do
        table.insert(invs, wagon.get_inventory(defines.inventory.fuel))
    end
    return invs
end

function merge_inventories(invs)
    local contents = {}

    for i, inv in pairs(invs) do
        for itemname, count in pairs(inv_contents(inv)) do
            contents[itemname] = (contents[itemname] or 0) + count
        end
    end

    return contents
end

function count_inventory_slots(invs)
    local count = 0

    for i, inv in pairs(invs) do
        count = count + #inv
    end

    return count
end

function space_for_type(invs, itemname)
    local space = 0

    for i, inv in pairs(invs) do
        space = space + inv_space(inv, itemname)
    end

    return space
end


function action_train(train)
    -- Load/unload the train as it arrives at a station
    local action = global.trains[train.id]

    if train.schedule.current == 1 then
        -- Load
        local stopnum = action.src.unit_number
        transfer_inventories(get_chest_inventories(stopnum), get_train_inventories(train), action.actions)

        local last_activity = global.stops[stopnum].last_activity
        local prov = global.routes[global.trains[train.id].routenum].provided
        for itemname, amount in pairs(action.actions) do
            -- Update last_activity or reset to nil if there's no more work to do
            if prov[itemname][stopnum] == nil then
                last_activity[itemname] = nil
            else
                last_activity[itemname] = game.tick
            end
        end

        global.stops[action.src.unit_number].actions[train.id] = nil  -- Delete the pickup action
    elseif train.schedule.current == 2 then
        -- Unload
        local stopnum = action.dest.unit_number
        transfer_inventories(get_train_inventories(train), get_chest_inventories(stopnum), action.actions)

        local last_activity = global.stops[stopnum].last_activity
        local req = global.routes[global.trains[train.id].routenum].requested
        for itemname, amount in pairs(action.actions) do
            -- Update last_activity or reset to nil if there's no more work to do
            if req[itemname][stopnum] == nil then
                last_activity[itemname] = nil
            else
                last_activity[itemname] = game.tick
            end
        end

        global.stops[action.dest.unit_number].actions[train.id] = nil  -- Delete the dropoff action
    end
end


MAX_STATION_LENGTH = 24
function find_entity_chain(surface, pos, offset, direction, length, type, prototypes)
    local entlist = {}
    local x, y = pos.x, pos.y
    local intro = true

    for i=1,length do
        local obj_pos = {x=x+offset.x, y=y+offset.y}
        local objs = surface.find_entities_filtered{type=type, position=obj_pos}
        local hit = false
        for _, o in pairs(objs) do
            if o.position.x == obj_pos.x and o.position.y == obj_pos.y and prototypes[o.name] then
                table.insert(entlist, o)
                hit = true
                intro = false
            end
        end

        if not intro and not hit then
            -- A gap marks the end of the chain
            --game.print("Hit gap (" .. type .. "):" .. fstr(entlist))
            break
        end

        if direction == defines.direction.north then
            y = y - 7
        elseif direction == defines.direction.south then
            y = y + 7
        elseif direction == defines.direction.east then
            x = x + 7
        elseif direction == defines.direction.west then
            x = x - 7
        end
    end

    --game.print("find_entity_chain (" .. type .. "): " .. fstr(entlist))
    return entlist
end


valid_container_types = {
    trainworks_chest_horizontal = true,
    trainworks_chest_vertical = true,
    trainworks_tank = true,
}

valid_stop_types = {
    trainworks_stop = true
}

flip_direction = {}
flip_direction[defines.direction.north] = defines.direction.south
flip_direction[defines.direction.northeast] = defines.direction.southwest
flip_direction[defines.direction.east] = defines.direction.west
flip_direction[defines.direction.southeast] = defines.direction.northwest
flip_direction[defines.direction.south] = defines.direction.north
flip_direction[defines.direction.southwest] = defines.direction.northeast
flip_direction[defines.direction.west] = defines.direction.east
flip_direction[defines.direction.northwest] = defines.direction.southeast

stop_offset_same = {}
stop_offset_same[defines.direction.north] = {x=0, y=-3}
stop_offset_same[defines.direction.east] = {x=3, y=0}
stop_offset_same[defines.direction.south] = {x=0, y=3}
stop_offset_same[defines.direction.west] = {x=-3, y=0}

stop_offset_opposite = {}
stop_offset_opposite[defines.direction.north] = {x=4, y=-3}
stop_offset_opposite[defines.direction.east] = {x=3, y=4}
stop_offset_opposite[defines.direction.south] = {x=-4, y=3}
stop_offset_opposite[defines.direction.west] = {x=-3, y=-4}


function update_stop_chests(stop)
    -- Chests on the same side as the stop
    local chestlist = find_entity_chain(stop.surface, stop.position, stop_offset_same[flip_direction[stop.direction]], flip_direction[stop.direction], MAX_STATION_LENGTH, nil, valid_container_types)

    -- Chests on the opposite side from the stop
    local chestlist2 = find_entity_chain(stop.surface, stop.position, stop_offset_opposite[flip_direction[stop.direction]], flip_direction[stop.direction], MAX_STATION_LENGTH, nil, valid_container_types)

    --game.print("update_stop_chests " .. fstr(stop) .. " -> " .. fstr(chestlist) .. "/" .. fstr(chestlist2))

    -- Merge the two lists
    for x, chest in pairs(chestlist2) do
        table.insert(chestlist, chest)
    end

    global.stops[stop.unit_number].chests = chestlist
end


function register_stop(stop)
    -- Clear the send_to_train flag if it wasn't user provided
    if stop.get_control_behavior() == nil then
        local control = stop.get_or_create_control_behavior()
        control.send_to_train = false
    end

    global.stops[stop.unit_number] = {stop=stop, chests={}, last_activity={}, weight=0, actions={}}
    update_stop_chests(stop)

    -- The universal route gets all stops
    route_add_stop(1, stop.unit_number)

    -- Update the modify pane of the GUI
    for playernum, player in pairs(game.players) do
        if global.gui_selected_route[playernum] ~= nil then
            populate_stops_in_modify(playernum, global.gui_selected_route[playernum])
        end
    end
end


function search_for_stop_same(surface, pos, direction)
    local stops = find_entity_chain(surface, pos, stop_offset_same[direction], direction, MAX_STATION_LENGTH, "train-stop", valid_stop_types)
    --game.print("search_for_stop_same (" .. fstr(direction) .. "): " .. fstr(pos) .. "  " .. fstr(stops))

    -- Filter for the correct orientation
    for i, stop in pairs(stops) do
        if stop.direction == direction then
            return stop
        end
    end

    return nil
end


function search_for_stop_opposite(surface, pos, direction)
    local stops = find_entity_chain(surface, pos, stop_offset_opposite[direction], direction, MAX_STATION_LENGTH, "train-stop", valid_stop_types)
    --game.print("search_for_stop_opposite (" .. fstr(direction) .. "): " .. fstr(pos) .. "  " .. fstr(stops))

    -- Filter for the correct orientation
    for i, stop in pairs(stops) do
        if stop.direction == direction then
            return stop
        end
    end

    return nil
end


function register_chest(chest)
    local stops = nil

    -- XXX FIXME generalize this for future expansion, such as bot logistic chests
    if chest.name == "trainworks_chest_horizontal" or (chest.name == "trainworks_tank" and chest.direction == defines.direction.north) then
        stops = {
            search_for_stop_same(chest.surface, chest.position, defines.direction.east),
            search_for_stop_same(chest.surface, chest.position, defines.direction.west),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.east),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.west)
        }
    elseif chest.name == "trainworks_chest_vertical" or (chest.name == "trainworks_tank" and chest.direction == defines.direction.east) then
        stops = {
            search_for_stop_same(chest.surface, chest.position, defines.direction.north),
            search_for_stop_same(chest.surface, chest.position, defines.direction.south),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.north),
            search_for_stop_opposite(chest.surface, chest.position, defines.direction.south)
        }
    end

    -- XXX I allow multiple stops to use the same chest.  Trains might get a bit confused but it's not catastrophic
    for i, stop in pairs(stops) do
        update_stop_chests(stop)
    end
end


function assign_train(routenum, trainid)
    if global.trains[trainid].routenum ~= nil then
        unassign_train(trainid)
    end

    if routenum ~= nil then
        global.trains[trainid].routenum = routenum
        global.routes[routenum].trains[trainid] = global.trains[trainid].train

        global.trains_dirty = true
    end
end

function unassign_train(trainid)
    local routenum = global.trains[trainid].routenum
    if routenum ~= nil then
        global.routes[routenum].trains[trainid] = nil
        global.trains[trainid].routenum = nil

        global.trains_dirty = true
    end
end


script.on_event({defines.events.on_entity_renamed},
    function (e)
        if e.entity.prototype.name == "trainworks_depot" then
            local train = global.depot_idletrain[e.entity.unit_number]

            if train ~= nil and train.state == defines.train_state.wait_station and train.station == e.entity then
                local routenum = global.route_map[e.entity.backer_name]
                assign_train(routenum, train.id)
            else
                global.depot_idletrain[e.entity.unit_number] = nil
            end
        elseif e.entity.prototype.name == "trainworks_stop" then
            --game.print("Stop renamed")
        end
    end
)
