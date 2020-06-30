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
    global.train_actions = {}  -- trainid -> {source, dest, actions}  -- Trains in progress
    global.stop_actions = {}  -- stopnum -> {actions, load}  -- Actions pending for each stop
    global.values = {}  -- stopnum -> itemname -> {have, want, coming}
    global.requested = {}  -- itemname -> stopnum -> amount
    global.provided = {}  -- itemname -> stopnum -> amount

end)


function dispatch_train(sourcenum, destnum, actions)
    local train = global.train
    if train == nil or not train.valid or train.state ~= defines.train_state.wait_station or train.station == nil or train.station.backer_name ~= "Depot" then
        -- No trains available
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
            {station="Depot", wait_conditions={}}
        }
    }
    train.schedule = x

    global.train_actions[train.id] = {src=source, dest=dest, actions=actions}
    global.stop_actions[source.unit_number] = {actions=actions, load=true}
    global.stop_actions[dest.unit_number] = {actions=actions, load=false}
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

        global.stop_actions[action.src.unit_number] = nil  -- Delete the load request
    elseif train.schedule.current == 2 then
        -- Unload
        transfer_inventories(get_train_inventories(train), get_chest_inventories(action.dest.unit_number), action.actions)

        global.stop_actions[action.dest.unit_number] = nil  -- Delete the unload request
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

    -- XXX FIXME can't use stop as key, has to be stop.unit_number
    global.stopchests[stop.unit_number] = {stop=stop, chests=chestlist}
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
        find_stop_chests(stop1)
    elseif stop2 ~= nil then
        find_stop_chests(stop2)
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
                value[itemname] = {have=0, want=0, reqcoming=0, provcoming=0}
            end
            value[itemname].have = value[itemname].have + amount
        end

        -- Add signals to value
        for itemname, sig in pairs(signals) do
            if value[itemname] == nil then
                value[itemname] = {have=0, want=0, reqcoming=0, provcoming=0}
            end
            value[itemname].want = value[itemname].want + sig.count
        end
    end

    return value
end


function add_value_to_reqprov(stopnum, value)
    local requested = global.requested
    local provided = global.provided

    if value == nil then
        return
    end

    for itemname, z in pairs(value) do
        local excess = z.have - z.want - z.reqcoming
        local shortage = z.want - z.have - z.provcoming

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


function remove_value_from_reqprov(stopnum, value)
    local requested = global.requested
    local provided = global.provided

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
    -- Calculate values, update reqprov
    for stopnum, x in pairs(global.stopchests) do
        log("Stop: " .. fstr(x.stop))

        remove_value_from_reqprov(stopnum, global.values[stopnum])
        global.values[stopnum] = nil

        local value = calculate_value_for_stop(stopnum)
        global.values[stopnum] = value
        add_value_to_reqprov(stopnum, value)
    end

    log("Values: " .. fstr(global.values))
    log("Requested: " .. fstr(global.requested))
    log("Provided: " .. fstr(global.provided))
end


function service_requests()
    -- Loop through requests and see if something is in provided
    for itemname, stops in pairs(global.requested) do
        for stopnum, amount in pairs(stops) do
            local pstops = global.provided[itemname]
            if pstops ~= nil then
                for pstopnum, pamount in pairs(pstops) do
                    local actions = {}
                    actions[itemname] = math.min(amount, pamount)
                    log("Min2: " .. fstr(actions))
                    dispatch_train(pstopnum, stopnum, actions)
                end
            end
        end
    end
end


script.on_event({defines.events.on_tick},
    function (e)
        if e.tick % 30 == 0 then
            update_reqprov()
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
            find_stop_chests(e.created_entity)
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