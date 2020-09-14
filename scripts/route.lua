-- Deciding when and where to send trains


function merge_stop_signals(stopnum)
    local priority = 0
    local output = {}
    local stop = global.stops[stopnum].stop
    if not stop.valid then
        global.cleanup_stops[stopnum] = true
        return {}
    end
    local signals = stop.get_merged_signals() or {}

    for j, sig in pairs(signals) do
        if (sig.signal.type == "item" or sig.signal.type == "fluid") and sig.signal.name then
            output[sig.signal.name] = sig
        elseif sig.signal.type == "virtual" and sig.signal.name == "trainworks_priority" then
            priority = sig.count
        end
    end

    -- Cache the priority as a side effect
    global.stops[stopnum].weight = priority
        
    return output
end


function calculate_value_for_stop(stopnum)
    local value = {}

    -- Add signals to value
    local stopsignals = merge_stop_signals(stopnum)
    for itemname, sig in pairs(stopsignals) do
        if value[itemname] == nil then
            value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
        end
        value[itemname].want = value[itemname].want + sig.count
    end

    -- Add inventory to value
    for itemname, amount in pairs(merge_inventories(get_chest_inventories(stopnum))) do
        if value[itemname] == nil then
            value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
        end
        value[itemname].have = value[itemname].have + amount
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


function find_best_providers(stops, itemname, wanted)
    local first_stopnum = nil
    local first_have = 0
    local first_age = -math.huge
    local second_stopnum = nil
    local second_have = 0
    local second_age = -math.huge

    for pstopnum, provhave in pairs(stops) do
        local age = time_since_last_service(pstopnum, itemname)
        provhave = math.min(provhave, wanted)

        -- Find the first provider option, hopefully a full request
        if (provhave > first_have) or (provhave == first_have and age > first_age) then
            first_stopnum = pstopnum
            first_have = provhave
            first_age = age
        end

        -- Find the second provider option, one that hasn't been serviced in a while
        if age > second_age then
            second_stopnum = pstopnum
            second_have = provhave
            second_age = age
        end
    end

    local first_weight = global.stops[first_stopnum].weight or 0
    local second_weight = global.stops[second_stopnum].weight or 0

    return {stopnum=first_stopnum, have=first_have, age=first_age, weight=first_weight}, {stopnum=second_stopnum, have=second_have, age=second_age, weight=second_weight}
end

function time_since_last_service(stopnum, itemname)
    -- Time since last serviced in minutes
    local last = global.stops[stopnum].last_activity[itemname]
    if last == nil then
        -- There's new work to do so start tracking how long it has waited
        last = game.tick
        global.stops[stopnum].last_activity[itemname] = last
    end

    return (game.tick - last) / 3600
end

function trigger_shortcut(requester, first, itemname, maximum_amount, weight)
    -- Full wagonload, send immediately
    if requester.want == maximum_amount and first.have == maximum_amount and (weight + requester.weight + first.weight) >= 0 then
        return true
    else
        return false
    end
end

function trigger_providerage(requester, first, itemname, maximum_amount, weight)
    -- Requester is getting empty, send a train quickly.  Alternatively it's almost full and a train just goes eventually.
    -- Each potential fullness corresponds to a minimum age
    -- 0% -> 0 minutes
    -- 25% -> 0 minutes
    -- 50% -> 5 minutes
    -- 75% -> 10 minutes
    -- 100% -> 15 minutes
    local fullness = 1 - (requester.want / global.stops[requester.stopnum].oldvalues[itemname].want)
    local minimum_age = math.max(fullness * 20 - 5, 0)
    if first.age + weight + requester.weight + first.weight > minimum_age then
        return true
    else
        return false
    end
end

function trigger_requesterage(requester, first, itemname, maximum_amount, weight)
    -- Requester waited a long time, just clean it up
    if requester.age + weight + requester.weight + first.weight >= 30 then
        return true
    else
        return false
    end
end

function tasks.service_route_requests(task)
    -- Loop through requested items and see if something is in provided
    local routenum = task.routenum
    local routeweight = global.routes[routenum].weight

    for itemname, stops in pairs(global.routes[routenum].requested) do
        for stopnum, reqwanted in pairs(stops) do
            local reqweight = global.stops[stopnum].weight or 0
            local train = find_idling_train(routenum, itemname)
            local pstops = global.routes[routenum].provided[itemname]
            if train ~= nil and pstops ~= nil and next(pstops) ~= nil then
                local maximum_amount = space_for_type(get_train_inventories(train), itemname)

                -- Cap reqwanted by train size
                reqwanted = math.min(reqwanted, maximum_amount)

                local first, second = find_best_providers(pstops, itemname, reqwanted)
                local requester = {stopnum=stopnum, want=reqwanted, age=time_since_last_service(stopnum, itemname), weight=reqweight}
                local chosen = nil
                if trigger_shortcut(requester, first, itemname, maximum_amount, routeweight) then
                    --game.print("Shortcut")
                    chosen = first
                elseif trigger_providerage(requester, first, itemname, maximum_amount, routeweight) then
                    --game.print("Providerage Full")
                    chosen = first
                elseif trigger_providerage(requester, second, itemname, maximum_amount, routeweight) then
                    --game.print("Providerage Old")
                    chosen = second
                elseif trigger_requesterage(requester, first, itemname, maximum_amount, routeweight) then
                    --game.print("Requesterage")
                    chosen = first
                end

                if chosen ~= nil then
                    local actions = {}
                    actions[itemname] = math.min(reqwanted, chosen.have)
                    dispatch_train(train, chosen.stopnum, requester.stopnum, actions)
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
