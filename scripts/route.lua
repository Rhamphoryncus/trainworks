-- Deciding when and where to send trains


function merge_combinator_signals(combi)
    local output = {}
    local signals = combi.get_merged_signals() or combi.get_control_behavior().parameters.parameters or {}
--    log("Signals: " .. fstr(signals))

    for j, sig in pairs(signals) do
--        log("V: " .. fstr(j) .. ", " .. fstr(sig))
        if sig.signal.type == "item" and sig.signal.name then
            output[sig.signal.name] = sig
        end
    end

--    log("Output: " .. fstr(output))
    return output
end


function calculate_value_for_stop(stopnum)
    local value = {}
    local chests = global.stopchests[stopnum].chests

    for i, chest in pairs(chests) do
        if not chest.valid then
            return nil
        end

        local combi = global.combinators[chest.unit_number]
        local signals = merge_combinator_signals(combi)
        local inv = chest.get_inventory(defines.inventory.chest).get_contents()

        -- XXX FIXME does not account for actions (pending trains)
        -- Add inventory to value
        for itemname, amount in pairs(inv) do
            if value[itemname] == nil then
                value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
            end
            value[itemname].have = value[itemname].have + amount
        end

        -- Add signals to value
        for itemname, sig in pairs(signals) do
            if value[itemname] == nil then
                value[itemname] = {have=0, want=0, pickup=0, dropoff=0}
            end
            value[itemname].want = value[itemname].want + sig.count
        end
    end

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


function add_value_to_reqprov(routename, stopnum, value)
    local requested = global.routes[routename].requested
    local provided = global.routes[routename].provided

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


function remove_value_from_reqprov(routename, stopnum, value)
    local requested = global.routes[routename].requested
    local provided = global.routes[routename].provided

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


function update_reqprov()
    -- XXX break up into "buckets"
    -- A, single: copy all stopchests into B
    -- B, multi: call calculate_value_for_stop() one at a time
    -- C, single: copy all routes into D
    -- D, multi: process reqprov for each route one at a time
    -- XXX FIXME rework idea: merge this all into a single "jobs" array where each entry is a table with "group" or "handler" attributes and other attributes
    -- It's fine to keep appending to the array as I iterate, that's O(1).  The array will get reset once I run out of tasks.

    local task = global.route_jobs[global.route_index]
    global.route_index = global.route_index + 1
    if task == nil then
        -- Reset and start a new pass
        global.route_index = 1
        global.route_jobs = {}
        table.insert(global.route_jobs, {handler="A"})
        global.values = global.newvalues
        global.newvalues = {}

        log("Values: " .. fstr(global.values))

        service_requests()
    elseif task.handler == "A" then
        -- Make a copy of global.stopchests but in a dense array form
        for stopnum, x in pairs(global.stopchests) do
            table.insert(global.route_jobs, {handler="B", stopnum=stopnum})
        end
        table.insert(global.route_jobs, {handler="C"})
    elseif task.handler == "B" then
        -- Calculate values for each stop
        global.newvalues[task.stopnum] = calculate_value_for_stop(task.stopnum)
    elseif task.handler == "C" then
        -- Make a copy of global.routes but in a dense array form
        for routename, route in pairs(global.routes) do
            table.insert(global.route_jobs, {handler="D", routename=routename})

            if route.dirty then
                -- If a stop was removed from the route we need to reset requested/provided
                route.requested = {}
                route.provided = {}
                route.dirty = false
            end
        end
    elseif task.handler == "D" then
        -- Update reqprov from newvalues
        local routename = task.routename

        for stopnum, x in pairs(get_route_stops(routename)) do
            remove_value_from_reqprov(routename, stopnum, global.values[stopnum])
            add_value_to_reqprov(routename, stopnum, global.newvalues[stopnum])
        end

        log("Requested: " .. fstr(routename) .. " " .. fstr(global.routes[routename].requested))
        log("Provided: " .. fstr(routename) .. " " .. fstr(global.routes[routename].provided))
    else
        error("Unexpected task handler")
    end
end


function get_route_stops(routename)
    -- XXX The return signature here varies.  The key is the same either way, stopnum, but the value can either be 'true' or be a table
    if global.universal_routes[routename] then
        return global.stopchests
    else
        return global.routes[routename].stops
    end
end


function calc_provider_weight(reqstopnum, provstopnum, itemname, wanted, have)
    -- XXX scale distance and make it negative
    -- threshold wanted/have, scale it, and make it negative
    -- scale idle time and make it positive
    local weight = 0
    local reqpos = global.stopchests[reqstopnum].stop.position
    local provpos = global.stopchests[provstopnum].stop.position

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


function service_requests()
    -- Loop through requests and see if something is in provided
    for routename, route in pairs(global.routes) do
        for itemname, stops in pairs(global.routes[routename].requested) do
            for stopnum, amount in pairs(stops) do
                -- XXX cap wanted amount by train size
                local pstops = global.routes[routename].provided[itemname]
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
                        dispatch_train(routename, beststopnum, stopnum, actions)
                    end
                end
            end
        end
    end
end
