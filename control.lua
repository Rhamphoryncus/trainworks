-- Todo:
-- Unravel service_requests() into persistent state
-- Restructure to have a unified state that incorporates the items, the request amounts, and outstanding actions, then derive provides and requests from that
-- Because each chest will only have a few of the many item types comparing the old state with new state will indicate what provides/requests to remove before adding the new ones
-- register_chest(), deregister_chest(), update_chest()
-- maybe also a refresh_state() that deletes the globals and rescans everything


function fstr(o)
    -- Attempts to pretty-print while sanely handling factorio API types
    if type(o) == "number" then
        return tostring(o)
    elseif type(o) == "string" then
        return o
    elseif type(o) == "table" then
        if o.valid ~= nil then
            if not o.valid then
                return "<invalid>"
            elseif not pcall(function() return o.unit_number ~= nil and o.type ~= nil end) then
                return "<non-entity>"
            else
                return "<" .. o.type .. "/" .. fstr(o.unit_number) .. ">"
            end
        else
            local a = {}
            for k,v in pairs(o) do
                table.insert(a, fstr(k) .. " = " .. fstr(v))
            end
            return "{" .. table.concat(a, ", ") .. "}"
        end
    elseif type(o) == "nil" then
        return "<nil>"
    else
        return tostring(o)
    end
end


script.on_init(function()
    global.train = nil
    global.depot = nil
    global.stopchests = {}  -- The chests belonging to each stop
    global.combinators = {}  -- Combinators containing request amounts for each chest
    global.train_actions = {}  -- Trains in progress
    global.chest_actions = {}  -- Actions pending for each chest
end)


function dispatch_train(source, dest, actions)
    local train = global.train
    if train == nil or not train.valid or train.state ~= defines.train_state.wait_station or train.station == nil or train.station.backer_name ~= "Depot" then
        -- No trains available
        return
    end
    log("Found depoted train: " .. fstr(train.state) .. " at " .. train.station.backer_name)

    local x = {
        current=1,
        records={
            {station=source.backer_name, wait_conditions={{type="time", compare_type="and", ticks=120}}},
            {station=dest.backer_name, wait_conditions={{type="time", compare_type="and", ticks=120}}},
            {station="Depot", wait_conditions={}}
        }
    }
    train.schedule = x

    global.train_actions[train.id] = {src=source, dest=dest, actions=actions}
    log("Dispatched train " .. fstr(train.id) .. " from " .. source.backer_name .. " to " .. dest.backer_name)
end

function reset_train(train)
    local x = {
        current=1,
        records={
            {station="Depot", wait_conditions={}}
        }
    }
    train.schedule = x
end

function transfer_inventories(src, dest, actions)
    for itemname, amount in pairs(actions) do
        local removed = src.remove({name=itemname, count=amount})
        local inserted = dest.insert({name=itemname, count=removed})
        local bounce = removed - inserted
        if bounce > 0 then
            log("Bounce: " .. fstr(bounce))
            local bounced = src.insert({name=itemname, count=bounce})
            if bounce ~= bounced then
                -- XXX print an error to console.  This might happen if a user applies filters or a bar to a chest/wagon
                log("Unable to bounce, items deleted!")
            end
        end
    end
end

function action_train(train)
    -- Load/unload the train as it arrives at a station
    local action = global.train_actions[train.id]
    log("Carriages: " .. fstr(train.carriages))
    log("Schedule index: " .. fstr(train.schedule.current))

    if train.schedule.current == 1 then
        -- Load
        local chest = global.stopchests[action.src][1]
        log("Chest: " .. fstr(chest))
        log("Blah: " .. fstr(global.stopchests) .. " ... " .. fstr(action))
        local c_inv = chest.get_inventory(defines.inventory.chest)
        local w_inv = train.carriages[2].get_inventory(defines.inventory.cargo_wagon)
        transfer_inventories(c_inv, w_inv, action.actions[1])
    elseif train.schedule.current == 2 then
        -- Unload
        local chest = global.stopchests[action.dest][1]
        log("Chest: " .. fstr(chest))
        log("Blah: " .. fstr(global.stopchests) .. " ... " .. fstr(action))
        local c_inv = chest.get_inventory(defines.inventory.chest)
        local w_inv = train.carriages[2].get_inventory(defines.inventory.cargo_wagon)
        transfer_inventories(w_inv, c_inv, action.actions[1])
    end
end


function update_stop(stop)
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

    global.stopchests[stop] = chestlist
--    log("b2 " .. serpent.block(global.stopchests) .. " % " .. serpent.line(#global.stopchests))
--    log("ARGH " .. serpent.line(global.stopchests[stop]))

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

    -- XXX create a combinator
    local combi = chest.surface.create_entity{name="constant-combinator", position=chest.position, force=chest.force}
    global.combinators[chest.unit_number] = combi
    log("Test2: " .. fstr(global.combinators) .. "[" .. fstr(chest) .. "] -> " .. fstr(global.combinators[chest.unit_number]))

    local stop1 = search_for_stop(chest.surface, chest.position, defines.direction.east)
    local stop2 = search_for_stop(chest.surface, chest.position, defines.direction.west)
    log("searched: " .. fstr(stop1) .. ", " .. fstr(stop2))
    if stop1 ~= nil and stop2 ~= nil then
        -- XXX return an error.  Stops aren't allowed to overlap and use the same set of chests.
        log("Error, would merge chest strings")
        return
    end

    if stop1 ~= nil then
        update_stop(stop1)
    elseif stop2 ~= nil then
        update_stop(stop2)
    end
end


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


function service_requests()
    -- iterate over all stops, then chests and combinators within them
    -- compare chest contents with combinator, figure out who wants items and who has items
    -- for each item type take the requests and create an action from the provider

    local requested = {}  -- itemname -> list of requested items
    local provided = {}  -- itemname -> list of provided items
    for stop, chests in pairs(global.stopchests) do
        for i, chest in pairs(chests) do
            local combi = global.combinators[chest.unit_number]
            local signals = merge_combinator_signals(combi)
            local inv = chest.get_inventory(defines.inventory.chest).get_contents()
--            log("inv: " .. fstr(inv))

            -- XXX FIXME does not account for actions (pending trains)
            for name, amount in pairs(inv) do
                if signals[name] then
                    local diff = amount - signals[name].count
                    if diff > 0 then
                        if not provided[name] then
                            provided[name] = {}
                        end
                        table.insert(provided[name], {stop=stop, chest=chest, amount=diff})
                    end
                else
                    if not provided[name] then
                        provided[name] = {}
                    end
                    table.insert(provided[name], {stop=stop, chest=chest, amount=amount})
                end
            end

            for name, sig in pairs(signals) do
                local diff = sig.count - (inv[name] or 0)
                if diff > 0 then
                    if not requested[name] then
                        requested[name] = {}
                    end
                    table.insert(requested[name], {stop=stop, chest=chest, amount=diff})
                end
            end
        end
    end

    log("Requests: " .. fstr(requested))
    log("Provided: " .. fstr(provided))

    -- loop through requests and see if something is in provided
    for name, req in pairs(requested) do
        local prov = provided[name]
        req = req[1]  -- XXX FIXME giant bodge
        if prov ~= nil then
            prov = prov[1]  -- XXX FIXME giant bodge
            log("Min: " .. fstr(req) .. ", " .. fstr(prov))
            local actions = {{}}
            actions[1][name] = math.min(req.amount, prov.amount)
            dispatch_train(prov.stop, req.stop, actions)
        end
    end
end


script.on_event({defines.events.on_tick},
    function (e)
        if e.tick % 30 == 0 then
            service_requests()
        end
    end
)


script.on_event({defines.events.on_built_entity},
    function (e)
        log("Built " .. e.created_entity.name)
        if e.created_entity.name == "tw_depot" then
            global.depot = e.created_entity
            global.depot.backer_name = "Depot"
        elseif e.created_entity.name == "tw_stop" then
            update_stop(e.created_entity)
        elseif e.created_entity.name == "locomotive" then
--            -- XXX modifying a train invalidates the old entity
--            global.train = e.created_entity.train
--            log(serpent.block(global))
--            log("train_state list: " .. serpent.block(defines.train_state))
        elseif e.created_entity.name == "tw_chest" then
            register_chest(e.created_entity)
        end
    end
)


script.on_event({defines.events.on_train_changed_state},
    function (e)
        local train = e.train
        log("Train state: " .. fstr(e.old_state) .. " -> " .. fstr(train.state))
        if train.state == defines.train_state.wait_station and e.old_state == defines.train_state.arrive_station and train.station ~= nil then
            log("Train in station: " .. train.station.backer_name)
            global.train = train
            if train.station.backer_name == "Depot" then
                reset_train(train)
            else
                action_train(train)
            end
        end
    end
)