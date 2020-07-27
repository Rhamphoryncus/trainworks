-- Todo:
-- Handle destruction of entities.  Probably just .valid checks and add them to a global "delete me" table to be processed later?
-- Add profiling hooks
-- Add a hardcoded route 1 as universal to share reqprov with all universal routes
-- Add GUI buttons for creating new routes and deleting empty routes
-- Figure out other entity built events
-- Figure out why blueprinting shared station names does weird things


require("scripts.util")
require("scripts.train")
require("scripts.route")
require("scripts.gui")


script.on_init(function()
    global.stopchests = {}  -- stopnum -> {stop, chests, last_activity}  -- The chests belonging to each stop
    global.train_actions = {}  -- trainid -> {source, dest, actions}  -- Trains in progress
        -- actions is itemname -> amount
    global.stop_actions = {}  -- stopnum -> trainid -> {actions, pickup}  -- Actions pending for each stop
        -- actions is itemname -> amount
    global.train_lastactivity = {}  -- trainid -> tick  -- Time the train started to become idle
    global.stop_idletrain = {}  -- stopnum -> train  -- Train idling at each stop
    global.values = {}  -- stopnum -> itemname -> {have, want, coming}  -- Previous pass's values
    global.newvalues = {}  -- stopnum -> itemname -> {have, want, coming}  -- Current pass's values
    global.routes = {}  -- routenum -> {name, trains, stops, provided, requested}
        -- name is string
        -- trains is trainid -> train
        -- stops is stopnum -> true
        -- provided is itemname -> stopnum -> amount
        -- requested is itemname -> stopnum -> amount
        -- dirty is true/nil  -- Indicates a route that had stops removed and the reqprov needs resetting
    global.universal_routes = {}  -- routenum -> true
    global.route_counter = 1  -- Index for new routes.  Perpetually increasing
    global.route_map = {}  -- routename -> routenum  -- reverse mapping of depot/route name to routenum

    global.gui_selected_route = {}  -- playernum -> routenum
    global.gui_players = {}  -- playernum -> true
    global.gui_routelist = {}  -- playernum -> guielement
    global.gui_routestatus = {}  -- playernum -> guielement
    global.gui_routemodify = {}  -- playernum -> guielement

    global.route_index = 1  -- Index number into global.route_jobs
    global.route_jobs = {}  -- {{handler, ...}, ...}  -- Array of tasks to be performed, one tick at a time

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
    log("Built " .. ent.name)
    if ent.name == "tw_depot" then
        -- XXX temporary bodge until I have a proper GUI
        local routenum = global.route_counter
        global.route_counter = global.route_counter + 1
        global.routes[routenum] = {name=ent.backer_name, trains={}, stops={}, provided={}, requested={}}
        global.route_map[ent.backer_name] = routenum
        global.universal_routes[routenum] = true
    elseif ent.name == "tw_stop" then
        local control = ent.get_or_create_control_behavior()
        control.send_to_train = false
        find_stop_chests(ent)
    elseif ent.name == "locomotive" then
    elseif ent.name == "tw_chest_horizontal" then
        register_chest(ent)
    elseif ent.name == "tw_chest_vertical" then
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
        log("Train state: " .. fstr(e.old_state) .. " -> " .. fstr(train.state))
        -- XXX FIXME this should only respond to trains that have joined a depot
        if train.state == defines.train_state.wait_station and e.old_state == defines.train_state.arrive_station and train.station ~= nil then
            log("Train in station: " .. train.station.backer_name)
            if train.station.prototype.name == "tw_depot" then
                reset_train(train)
            else
                action_train(train)
            end
        end
    end
)