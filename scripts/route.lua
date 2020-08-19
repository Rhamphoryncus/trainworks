-- Deciding when and where to send trains


function merge_stop_signals(stopnum)
    local output = {}
    local stop = global.stops[stopnum].stop
    if not stop.valid then
        global.cleanup_stops[stopnum] = true
        return {}
    end
    local signals = stop.get_merged_signals() or {}

    for j, sig in pairs(signals) do
        if sig.signal.type == "item" and sig.signal.name then
            output[sig.signal.name] = sig
        end
    end
        
    return output
end


function calculate_value_for_stop(stopnum)
    local value = {}
    local chests = global.stops[stopnum].chests

    -- Add signals to value
    local stopsignals = merge_stop_signals(stopnum)
    for itemname, sig in pairs(stopsignals) do
        if value[itemname] == nil then
            value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
        end
        value[itemname].want = value[itemname].want + sig.count
    end

    for i, chest in pairs(chests) do
        if chest.valid then
            local inv = chest.get_inventory(defines.inventory.chest).get_contents()

            -- Add inventory to value
            for itemname, amount in pairs(inv) do
                if value[itemname] == nil then
                    value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
                end
                value[itemname].have = value[itemname].have + amount
            end
        end
    end

    -- Add pending trains to value
    for trainid, x in pairs(global.stops[stopnum].actions) do
        for itemname, amount in pairs(x.actions) do
            if value[itemname] == nil then
                value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
            end
            if x.pickup then
                value[itemname].pickup = value[itemname].pickup + amount
            else
                value[itemname].dropoff = value[itemname].dropoff + amount
            end
        end
    end

    return value
end


function add_value_to_reqprov(routenum, stopnum, value)
    local requested = global.routes[routenum].requested
    local provided = global.routes[routenum].provided

    if value == nil then
        return
    end

    for itemname, z in pairs(value) do
        local excess = z.have - z.want - z.pickup
        local shortage = z.want - z.have - z.dropoff

        if excess > 0 then
            if provided[itemname] == nil then
                provided[itemname] = {}
            end
            provided[itemname][stopnum] = excess
        end

        if shortage > 0 then
            if requested[itemname] == nil then
                requested[itemname] = {}
            end
            requested[itemname][stopnum] = shortage
        end
    end
end


function remove_value_from_reqprov(routenum, stopnum, value)
    local requested = global.routes[routenum].requested
    local provided = global.routes[routenum].provided

    if value == nil then
        return
    end

    for itemname, z in pairs(value) do
        if provided[itemname] ~= nil then
            provided[itemname][stopnum] = nil
        end

        if requested[itemname] ~= nil then
            requested[itemname][stopnum] = nil
        end
    end
end


tasks = {}
function tasks.cleanup(task)
    local refresh_modify_gui = false
    for stopnum, x in pairs(global.cleanup_stops) do
        for routenum, route in pairs(global.routes) do
            if route.stops[stopnum] ~= nil then
                route_remove_stop(routenum, stopnum)
            end
        end
        global.stops[stopnum] = nil
        refresh_modify_gui = true
    end
    global.cleanup_stops = {}

    for trainid, train in pairs(global.cleanup_trains) do
        reset_train(trainid, train)
    end
    global.cleanup_trains = {}

    for routenum, x in pairs(global.cleanup_routes) do
        for playernum, player in pairs(game.players) do
            -- Unselect the route
            if routenum == global.gui_selected_route[playernum] then
                select_route(playernum, nil)
            end

            -- Remove the radiobutton
            local listpane = global.gui_routelist[playernum]
            if listpane ~= nil then
                listpane[("trainworks_route_"..routenum)].destroy()
            end
        end
    
        -- Unassign the trains
        for trainid, train in pairs(global.routes[routenum].trains) do
            unassign_train(trainid)
        end

        global.route_map[global.routes[routenum].name] = nil
        global.routes[routenum] = nil
    end
    global.cleanup_routes = {}

    if refresh_modify_gui then
        -- Update the modify pane of the GUI
        for playernum, player in pairs(game.players) do
            if global.gui_selected_route[playernum] ~= nil then
                populate_stops_in_modify(playernum, global.gui_selected_route[playernum])
            end
        end
    end

    table.insert(global.routing_jobs, {handler="copy_stops"})
end


function tasks.copy_stops(task)
    -- Make a copy of global.stops keys but in a dense array form
    for stopnum, x in pairs(global.stops) do
        table.insert(global.routing_jobs, {handler="calculate_values", stopnum=stopnum})
    end

    table.insert(global.routing_jobs, {handler="copy_reqprov_routes"})
end


function tasks.calculate_values(task)
    -- Calculate values for each stop
    global.stops[task.stopnum].newvalues = calculate_value_for_stop(task.stopnum)
end


function tasks.copy_reqprov_routes(task)
    -- Make a copy of global.routes but in a dense array form
    for routenum, route in pairs(global.routes) do
        table.insert(global.routing_jobs, {handler="update_reqprov", routenum=routenum})

        if route.dirty then
            -- If a stop was removed from the route we need to reset requested/provided
            route.requested = {}
            route.provided = {}
            route.dirty = false
        end
    end

    table.insert(global.routing_jobs, {handler="copy_service_routes"})
end


function tasks.update_reqprov(task)
    -- Update reqprov from newvalues
    local routenum = task.routenum

    for stopnum, x in pairs(global.routes[routenum].stops) do
        remove_value_from_reqprov(routenum, stopnum, global.stops[stopnum].oldvalues)
        add_value_to_reqprov(routenum, stopnum, global.stops[stopnum].newvalues)
    end
end


function process_routes()
    local task = global.routing_jobs[global.routing_index]
    global.routing_index = global.routing_index + 1
    if task == nil then
        -- Reset and start a new pass
        global.routing_index = 1
        global.routing_jobs = {}
        table.insert(global.routing_jobs, {handler="cleanup"})
    else
        --mod_gui.get_button_flow(game.players[1]).trainworks_top_button.caption = task.handler  -- XXX bodge to show current task
        tasks[task.handler](task)
    end
end


function calc_provider_weight(routenum, reqstopnum, provstopnum, itemname, reqwanted, provhave, wagon_slots)
    local weights = {}
    local reqstop = global.stops[reqstopnum].stop
    local provstop = global.stops[provstopnum].stop
    if not reqstop.valid or not provstop.valid then
        -- Stop has been removed
        return -math.huge
    end
    local reqpos = reqstop.position
    local provpos = provstop.position

    -- Taxi cab distance between stops
    local distance = math.abs(reqpos.x - provpos.x) + math.abs(reqpos.y - provpos.y)
    weights.distance = -distance / 1000

    -- Insufficient amount in provider
    if reqwanted > provhave then
        weights.shortage = -reqwanted / provhave
        weights.shortage_threshold = -1
    end

    -- Requester is getting close to empty
    weights.empty = reqwanted / global.stops[reqstopnum].oldvalues[itemname].want
    if weights.empty >= 0.5 then
        weights.empty_threshold = 1
    end

    -- Insufficient to fill the train's wagons
    local stacksize = game.item_prototypes[itemname].stack_size
    local maximum = stacksize * wagon_slots
    local actual = math.min(reqwanted, provhave)
    if actual < maximum then
        weights.capacity = -(maximum - actual) / maximum
        weights.capacity_threshold = -1
    end

    -- Time since last serviced
    weights.waiting = (game.tick - global.stops[provstopnum].last_activity) / 10000

    weights.route = global.routes[routenum].weight / 100  -- XXX FIXME bodge for scaling factors

    log(fstr(weights) .. " -> " .. sum(weights))  -- XXX FIXME temporary bodge
    return sum(weights) * 100
end


function tasks.copy_service_routes(task)
    -- Updating values and reqprov has finished
    for stopnum, stop in pairs(global.stops) do
        stop.oldvalues = stop.newvalues
        stop.newvalues = {}
    end

    -- Make a copy of global.routes but in a dense array form
    for routenum, route in pairs(global.routes) do
        table.insert(global.routing_jobs, {handler="service_route_requests", routenum=routenum})
    end
end


function tasks.service_route_requests(task)
    -- Loop through requested items and see if something is in provided
    local routenum = task.routenum

    for itemname, stops in pairs(global.routes[routenum].requested) do
        for stopnum, reqwanted in pairs(stops) do
            local train = find_idling_train(routenum)
            local pstops = global.routes[routenum].provided[itemname]
            if train ~= nil and pstops ~= nil then
                local bestweight = -100  -- Doubles as a threshold for having no good providers
                local beststopnum = nil
                local besthave = nil
                local wagon_slots = count_inventory_slots(get_train_inventories(train))

                -- Cap wanted reqwanted by train size
                reqwanted = math.min(reqwanted, wagon_slots * game.item_prototypes[itemname].stack_size)

                for pstopnum, provhave in pairs(pstops) do
                    local newweight = calc_provider_weight(routenum, stopnum, pstopnum, itemname, reqwanted, provhave, wagon_slots)
                    if newweight >= bestweight then
                        bestweight = newweight
                        beststopnum = pstopnum
                        besthave = provhave
                    end
                end

                if beststopnum ~= nil then
                    local actions = {}
                    actions[itemname] = math.min(reqwanted, besthave)
                    dispatch_train(train, beststopnum, stopnum, actions)
                end
            end
        end
    end

    table.insert(global.routing_jobs, {handler="update_gui"})
end


function tasks.update_gui(task)
    if global.trains_dirty then
        update_gui()
        global.trains_dirty = false
    end

    for playernum, player in pairs(game.players) do
        update_train_status(playernum)
    end

    for trainid, x in pairs(global.trains) do
        table.insert(global.routing_jobs, {handler="update_gui_train", trainid=trainid})
    end
end


function tasks.update_gui_train(task)
    local trainid = task.trainid

    for playernum, player in pairs(game.players) do
        update_train_list_train(playernum, trainid)
    end
end
