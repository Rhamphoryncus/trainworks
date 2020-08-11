-- Todo:
-- Handle destruction of entities.  Probably just .valid checks and add them to a global "delete me" table to be processed later?  Trains are done but stops and depots are still needed.
-- Add profiling hooks
-- Rebalance weights
-- Add provider/requester priorities to routes
-- Add provider/requester priorities to stops
-- Handle migration/reset parts of the mod on version changes
-- Make stopchest's last_activity be per-typename
-- Remove unused parts of train status
-- Consider changing colour or otherwise hilighting trains with error status.  Maybe bold?
-- Make sure deleting a route orphans any trains it owns
-- Better balancing for wildly unbalanced chests
-- Generate backer_name for new routes in a way that doesn't create a temporary object (and smoke) at 0,0


require("scripts.util")
require("scripts.train")
require("scripts.route")
require("scripts.gui")


script.on_init(function()
    global.stops = {}  -- stopnum -> {stop, chests, last_activity, actions, oldvalues, newvalues}
        -- stop is stop  -- Underlying stop handle
        -- chests is {chest, ...}  -- Chest handles
        -- last_activity is tick  -- Game tick that something was last picked up/dropped off
        -- actions is trainid -> {actions, pickup}
            -- actions is itemname -> amount  -- Transfers intended at this stop
            -- pickup is boolean  -- If the transfers are a pickup or drop off
        -- oldvalues is itemname -> {have, want, coming}  -- Previous pass's values
            -- have is integer
            -- want is integer
            -- coming is integer
        -- newvalues is itemname -> {have, want, coming}  -- Current pass's values
            -- have is integer
            -- want is integer
            -- coming is integer

    global.trains = {}  -- trainid -> {train, routenum, src, dest, actions, last_fuel, last_activity}
        -- train is train  -- Underlying train handle
        -- routenum is routenum  -- Route this train is assigned to
        -- src is stop  -- Pickup station
        -- dest is stop  -- Dropoff station
        -- actions is itemname -> amount
        -- last_fuel is itemname -> amount  -- Amount of fuel on locomotives last time we looked
        -- last_activity is tick  -- Game tick when we last loaded fuel
    global.depot_idletrain = {}  -- stopnum -> train  -- Train idling at each stop

    global.routes = {}  -- routenum -> {name, trains, stops, provided, requested}
        -- name is string
        -- trains is trainid -> train
        -- stops is stopnum -> true
        -- provided is itemname -> stopnum -> amount
        -- requested is itemname -> stopnum -> amount
        -- dirty is true/nil  -- Indicates a route that had stops removed and the reqprov needs resetting
    global.route_counter = 2  -- Index for new routes.  Perpetually increasing
    global.route_map = {}  -- routename -> routenum  -- reverse mapping of depot/route name to routenum
    global.routes[1] = {name="Universal", trains={}, stops={}, provided={}, requested={}}
    global.route_map["Universal"] = 1

    global.gui_selected_route = {}  -- playernum -> routenum
    global.gui_players = {}  -- playernum -> true
    global.gui_routelist = {}  -- playernum -> guielement
    global.gui_routestatus = {}  -- playernum -> guielement
    global.gui_routemodify = {}  -- playernum -> guielement
    global.gui_selected_train = {}  -- playernum -> trainid
    global.gui_traintable = {}  -- playernum -> guielement
    global.gui_deleteroute = {}  -- playernum -> guielement

    global.routing_index = 1  -- Index number into global.routing_jobs
    global.routing_jobs = {}  -- {{handler, ...}, ...}  -- Array of tasks to be performed, one tick at a time

    global.cleanup_stops = {}  -- stopid -> true  -- Stops that were destroyed and need to be untracked
    global.cleanup_trains = {}  -- trainid -> train  -- Trains that were destroyed and need to be untracked
    global.cleanup_routes = {}  -- routenum -> true  -- Routes that the user asked to delete

    gui_initialize_players()
end)


script.on_event({defines.events.on_tick},
    function (e)
        if e.tick % 1 == 0 then
            process_routes()
        end
    end
)


function handle_built_event(ent)
    if ent.name == "trainworks_depot" then
    elseif ent.name == "trainworks_stop" then
        register_stop(ent)
    elseif ent.name == "locomotive" then
    elseif ent.name == "trainworks_chest_horizontal" then
        register_chest(ent)
    elseif ent.name == "trainworks_chest_vertical" then
        register_chest(ent)
    end
end
script.on_event({defines.events.on_built_entity}, function (e) handle_built_event(e.created_entity) end)  -- Entity built event
script.on_event({defines.events.on_robot_built_entity}, function (e) handle_built_event(e.created_entity) end)  -- Other built event
script.on_event({defines.events.script_raised_built}, function (e) handle_built_event(e.entity) end)  -- Other other built event
script.on_event({defines.events.script_raised_revive}, function (e) handle_built_event(e.entity) end)  -- Other other other built event
script.on_event({defines.events.on_entity_cloned}, function (e) handle_built_event(e.destination) end)  -- Other other other other built event


script.on_event({defines.events.on_train_changed_state},
    function (e)
        local train = e.train
        -- XXX FIXME this should only respond to trains that have joined a depot
        if train.state == defines.train_state.wait_station and e.old_state == defines.train_state.arrive_station then
            if train.station ~= nil and train.station.prototype.name == "trainworks_depot" then
                reset_train(train.id, train)
            else
                action_train(train)
            end
        end
    end
)