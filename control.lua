-- Todo:


require("scripts.util")
require("scripts.train")
require("scripts.route")
require("scripts.gui")


script.on_init(function()
    global.stopchests = {}  -- stopnum -> {stop, chests, last_activity}  -- The chests belonging to each stop
    global.combinators = {}  -- chestnum -> combi  -- Combinators containing request amounts for each chest
    global.train_actions = {}  -- trainid -> {source, dest, actions}  -- Trains in progress
        -- actions is itemname -> amount
    global.stop_actions = {}  -- stopnum -> trainid -> {actions, pickup}  -- Actions pending for each stop
        -- actions is itemname -> amount
    global.values = {}  -- stopnum -> itemname -> {have, want, coming}
    global.routes = {}  -- routename -> {depots, trains, stops, provided, requested}
        -- depots is stopnum -> true
        -- trains is trainid -> true
        -- stops is stopnum -> true
        -- provided is itemname -> stopnum -> amount
        -- requested is itemname -> stopnum -> amount
    global.universal_routes = {}  -- routename -> true
    global.gui_selected_route = {}  -- playernum -> routename
    global.gui_players = {}  -- playernum -> true
    global.gui_routestatus = {}  -- playernum -> guielement
    global.gui_routemodify = {}  -- playernum -> guielement

    gui_initialize_players()
end)


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
            -- XXX temporary bodge until I have a proper GUI
            global.routes[e.created_entity.backer_name] = {depots={}, trains={}, stops={}, provided={}, requested={}}
            global.universal_routes[e.created_entity.backer_name] = true
        elseif e.created_entity.name == "tw_stop" then
            find_stop_chests(e.created_entity)
        elseif e.created_entity.name == "locomotive" then
        elseif e.created_entity.name == "tw_chest" then
            register_chest(e.created_entity)
        end
    end
)


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