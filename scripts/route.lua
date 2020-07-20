-- Deciding when and where to send trains


function merge_stop_signals(stopnum)
    local output = {}
    local stop = global.stopchests[stopnum].stop
    if not stop.valid then
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
    local chests = global.stopchests[stopnum].chests

    -- Add signals to value
    local stopsignals = merge_stop_signals(stopnum)
    for itemname, sig in pairs(stopsignals) do
        if value[itemname] == nil then
            value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
        end
        value[itemname].want = value[itemname].want + sig.count
    end

    for i, chest in pairs(chests) do
        if not chest.valid then
            return nil
        end

        local inv = chest.get_inventory(defines.inventory.chest).get_contents()

        -- Add inventory to value
        for itemname, amount in pairs(inv) do
            if value[itemname] == nil then
                value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
            end
            value[itemname].have = value[itemname].have + amount
        end
    end

    -- Add pending trains to value
    for trainid, x in pairs(global.stop_actions[stopnum]) do
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
function tasks.copy_stopchests(task)
    -- Make a copy of global.stopchests but in a dense array form
    for stopnum, x in pairs(global.stopchests) do
        table.insert(global.route_jobs, {handler="calculate_values", stopnum=stopnum})
    end

    table.insert(global.route_jobs, {handler="copy_reqprov_routes"})
end


function tasks.calculate_values(task)
    -- Calculate values for each stop
    global.newvalues[task.stopnum] = calculate_value_for_stop(task.stopnum)
end


function tasks.copy_reqprov_routes(task)
    -- Make a copy of global.routes but in a dense array form
    for routenum, route in pairs(global.routes) do
        table.insert(global.route_jobs, {handler="update_reqprov", routenum=routenum})

        if route.dirty then
            -- If a stop was removed from the route we need to reset requested/provided
            route.requested = {}
            route.provided = {}
            route.dirty = false
        end
    end

    table.insert(global.route_jobs, {handler="copy_service_routes"})
end


function tasks.update_reqprov(task)
    -- Update reqprov from newvalues
    local routenum = task.routenum

    for stopnum, x in pairs(get_route_stops(routenum)) do
        remove_value_from_reqprov(routenum, stopnum, global.values[stopnum])
        add_value_to_reqprov(routenum, stopnum, global.newvalues[stopnum])
    end

    --log("Requested: " .. fstr(routenum) .. " " .. fstr(global.routes[routenum].requested))
    --log("Provided: " .. fstr(routenum) .. " " .. fstr(global.routes[routenum].provided))
end


function process_routes()
    local task = global.route_jobs[global.route_index]
    global.route_index = global.route_index + 1
    if task == nil then
        -- Reset and start a new pass
        global.route_index = 1
        global.route_jobs = {}
        table.insert(global.route_jobs, {handler="copy_stopchests"})
    else
        --mod_gui.get_button_flow(game.players[1]).trainworks_top_button.caption = task.handler
        tasks[task.handler](task)
    end
end


function get_route_stops(routenum)
    -- XXX The return signature here varies.  The key is the same either way, stopnum, but the value can either be 'true' or be a table
    if global.universal_routes[routenum] then
        return global.stopchests
    else
        return global.routes[routenum].stops
    end
end


function calc_provider_weight(reqstopnum, provstopnum, itemname, wanted, have)
    -- XXX scale distance and make it negative
    -- threshold wanted/have, scale it, and make it negative
    -- scale idle time and make it positive
    local weight = 0
    local reqstop = global.stopchests[reqstopnum].stop
    local provstop = global.stopchests[provstopnum].stop
    if not reqstop.valid or not provstop.valid then
        -- Stop has been removed
        return -math.huge
    end
    local reqpos = reqstop.position
    local provpos = provstop.position

    -- Taxi cab distance between stops
    local distance = math.abs(reqpos.x - provpos.x) + math.abs(reqpos.y - provpos.y)
    weight = weight - distance / 1000

    -- Insufficient amount in provider
    if wanted > have then
        weight = weight - wanted / have - 1
    end

    -- Time since last serviced
    weight = weight + (game.tick - global.stopchests[provstopnum].last_activity) / 1000

    return weight
end


function tasks.copy_service_routes(task)
    -- Updating values and reqprov has finished
    global.values = global.newvalues
    global.newvalues = {}

    --log("Values: " .. fstr(global.values))

    -- Make a copy of global.routes but in a dense array form
    for routenum, route in pairs(global.routes) do
        table.insert(global.route_jobs, {handler="service_route_requests", routenum=routenum})
    end
end


function tasks.service_route_requests(task)
    -- Loop through requested items and see if something is in provided
    local routenum = task.routenum

    for itemname, stops in pairs(global.routes[routenum].requested) do
        for stopnum, amount in pairs(stops) do
            -- XXX cap wanted amount by train size
            local pstops = global.routes[routenum].provided[itemname]
            if pstops ~= nil then
                local bestweight = -100  -- Doubles as a threshold for having no good providers
                local beststopnum = nil
                local bestamount = nil

                for pstopnum, pamount in pairs(pstops) do
                    local newweight = calc_provider_weight(stopnum, pstopnum, itemname, amount, pamount)
                    if newweight >= bestweight then
                        bestweight = newweight
                        beststopnum = pstopnum
                        bestamount = pamount
                    end
                end

                if beststopnum ~= nil then
                    local actions = {}
                    actions[itemname] = math.min(amount, bestamount)
                    log("Min2: " .. fstr(actions))
                    dispatch_train(routenum, beststopnum, stopnum, actions)
                end
            end
        end
    end
end