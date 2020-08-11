-- All the fun GUI stuff to interact with the user


require("mod-gui")


function create_gui(player)
    mod_gui.get_button_flow(player).add
    {
        type="button",
        name="trainworks_top_button",
        caption={"gui.trainworks"},
        style=mod_gui.button_style
    }

    mod_gui.get_frame_flow(player).add
    {
        type="frame",
        name="trainworks_status",
        caption={"gui.status"},
        style=mod_gui.frame_style
    }
    mod_gui.get_frame_flow(player).trainworks_status.visible = false

    mod_gui.get_frame_flow(player).add
    {
        type="frame",
        name="trainworks_modify",
        caption={"gui.modify"},
        style=mod_gui.frame_style
    }
    mod_gui.get_frame_flow(player).trainworks_modify.visible = false
end


function gui_player_joined(playernum)
    if global.gui_players[playernum] == nil then
        create_gui(game.players[playernum])
        global.gui_players[playernum] = true
    end
end


script.on_event({defines.events.on_player_joined_game},
    function (e)
        gui_player_joined(e.player_index)
    end
)


function gui_initialize_players()
    for playernum, player in pairs(game.players) do
        gui_player_joined(playernum)
    end
end


-- XXX FIXME this is added blindly.  It's not clear this even is the only event, or even the right even, such as for kicks/bans
script.on_event({defines.events.on_player_left_game},
    function (e)
        clear_status(e.player_index)
        clear_modify(e.player_index)
    end
)


function get_backer_name(stopnum)
    local stop = global.stops[stopnum].stop
    if stop.valid then
        return stop.backer_name
    else
        return "<Station Removed>"
    end
end


function populate_status(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status

    -- Tabs to select between routes or trains
    local tabs = frame.add{type="tabbed-pane", name="trainworks_tabs"}
    local routetab = tabs.add{type="tab", name="trainworks_routetab", caption={"gui.routetab"}}
    local traintab = tabs.add{type="tab", name="trainworks_traintab", caption={"gui.traintab"}}

    -- List of routes to select from
    local routepane = tabs.add{type="scroll-pane", name="trainworks_routepane", vertical_scroll_policy="auto-and-reserve-space"}
    tabs.add_tab(routetab, routepane)
    local first = nil
    for routenum, route in pairs(global.routes) do
        local caption = route.name
        if routenum == 1 then
            caption = {"gui.universalroute", caption}
        end
        routepane.add{type="radiobutton", name=("trainworks_route_"..routenum), state=(not first), caption=caption}
        if first == nil then
            first = routenum
        end
    end
    global.gui_routelist[playernum] = routepane

    -- Stops within the selected route
    -- XXX FIXME this should swap out for train status
    local stationflow = frame.add{type="flow", name="trainworks_stationflow", direction="vertical"}
    stationflow.add{type="button", name="trainworks_newroute", caption={"gui.newroute"}}
    stationflow.add{type="button", name="trainworks_showmodify", caption={"gui.showmodify"}}
    local statuspane = stationflow.add{type="scroll-pane", name="trainworks_stationpane", vertical_scroll_policy="auto-and-reserve-space"}
    global.gui_routestatus[playernum] = statuspane

    -- Detailed status of selected train
    local trainflow = frame.add{type="flow", name="trainworks_trainflow", direction="vertical"}
    trainflow.add{type="label", name="trainworks_train_cargo", caption="Test cargo"}
    trainflow.add{type="label", name="trainworks_train_fullness", caption="Test fullness"}
    trainflow.add{type="label", name="trainworks_train_position", caption="Test position"}
    local minimap = trainflow.add{type="minimap", name="trainworks_train_minimap"}

    -- Various trains servicing routes
    local trainlistflow = tabs.add{type="flow", name="trainworks_trainlistflow", direction="vertical"}
    tabs.add_tab(traintab, trainlistflow)
    -- XXX FIXME radiobuttons at top: "All trains" and "Trains with issues"
    -- Search box underneath to filter by route or train name.  Does train name have any value?
    -- Scroll pane and radiobox underneath of the trains, updated by route.lua
    local trainmodeflow = trainlistflow.add{type="flow", name="trainworks_trainmodeflow", direction="horizontal"}
    local modeall = trainmodeflow.add{type="radiobutton", name="trainworks_trainmode_all", state=false, caption={"gui.trainmode_all"}}
    local modeissues = trainmodeflow.add{type="radiobutton", name="trainworks_trainmode_issues", state=true, caption={"gui.trainmode_issues"}}
    trainlistflow.add{type="textfield", name="trainworks_trainfilter", tooltip={"gui.trainfilter"}}
    local trainpane = trainlistflow.add{type="scroll-pane", name="trainworks_trainpane", vertical_scroll_policy="auto-and-reserve-space"}
    local traintable = trainpane.add{type="table", name="trainworks_traintable", column_count=2}
    global.gui_traintable[playernum] = traintable
    populate_train_list(playernum)

    if first ~= nil then
        select_route(playernum, first)
    end

    frame.visible = true
end

function clear_status(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status
    frame.visible = false
    frame.clear()
    global.gui_routelist[playernum] = nil
end

function select_route(playernum, routenum)
    local status = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status

    -- Unset all the radiobuttons
    local pane = status.trainworks_tabs.trainworks_routepane
    for childname, child in pairs(pane.children) do
        child.state = false
    end

    -- Hide and reshow the route status pane
    global.gui_selected_route[playernum] = routenum  -- Cache it for later
    clear_modify(playernum)
    populate_stops_in_route(playernum, routenum)

    -- Reset the active radiobutton
    if routenum ~= nil then
        status.trainworks_stationflow.visible = true
        status.trainworks_trainflow.visible = false
        pane[("trainworks_route_"..routenum)].state = true
        select_train(playernum, nil)
    end
end

function populate_stops_in_route(playernum, routenum)
    local pane = global.gui_routestatus[playernum]

    pane.clear()

    if routenum ~= nil then
        for stopnum, x in pairs(global.routes[routenum].stops) do
            local name = "trainworks_routelabel_"..tostring(stopnum)
            pane.add{type="label", name=name, caption=get_backer_name(stopnum)}
        end
    end
end

function select_train(playernum, trainid)
    local status = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status

    local traintable = global.gui_traintable[playernum]
    global.gui_selected_train[playernum] = trainid

    if trainid ~= nil then
        status.trainworks_stationflow.visible = false
        status.trainworks_trainflow.visible = true

        select_route(playernum, nil)
    end
end

function populate_train_list(playernum)
    local trainlistflow = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status.trainworks_tabs.trainworks_trainlistflow
    local filter = trainlistflow.trainworks_trainfilter.text
    local issuesmode = trainlistflow.trainworks_trainmodeflow.trainworks_trainmode_issues.state
    local traintable = global.gui_traintable[playernum]
    local selectedid = global.gui_selected_train[playernum]

    -- Clear first
    -- XXX Minor bug: if the player holds down the radiobutton that will get reset
    traintable.clear()

    -- Then readd the list of trains
    for routenum, x in pairs(global.routes) do
        local routename = global.routes[routenum].name
        for trainid, train in pairs(x.trains) do
            local status = ""
            local issue = false
            if train_status_garbage(trainid, train) then
                status = {"gui.train_status_garbage"}
                issue = true
            elseif train_status_error(trainid, train) then
                issue, status = train_status_error(trainid, train)
            elseif train_status_refueling(trainid, train) then  -- XXX Minor bug: updates idle time as a side effect
                status = {"gui.train_status_refueling"}
            end

            if not train.valid then
                global.cleanup_trains[trainid] = train
            elseif string.find(routename, filter, 1, true) == nil and string.find(tostring(trainid), filter, 1, true) == nil then
                -- Skip this train
            elseif issuesmode and not issue then
                -- Skip this train
            else
                local caption={"gui.trainbutton", routename, trainid}
                local state = false
                if trainid == selectedid then
                    state = true
                end
                traintable.add{type="radiobutton", name=("trainworks_trainbutton_"..trainid), state=state, caption=caption}
                traintable.add{type="label", name=("trainworks_trainlabel_"..trainid), caption=status}
            end
        end
    end

    populate_train_status(playernum)
end

function populate_train_status(playernum)
    local flow = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status.trainworks_trainflow

    local trainid = global.gui_selected_train[playernum]
    if trainid ~= nil then
        local train = global.trains[trainid].train

        local cargostring = ""
        if train.schedule.current == 1 then
            local actions = global.trains[trainid].actions
            if actions ~= nil then
                cargostring = "Intended: " .. generate_cargo_string(actions)
            else
                cargostring = ""
            end
        elseif train.schedule.current == 2 then
            cargostring = generate_cargo_string(merge_inventories(get_train_inventories(train)))
        else
            cargostring = ""
        end
        flow.trainworks_train_cargo.caption = cargostring
        flow.trainworks_train_fullness.caption = "Not 0"

        local pos = train.locomotives.front_movers[1].position
        flow.trainworks_train_position.caption = string.format("%i, %i", pos.x, pos.y)  -- This truncates rather than rounding to nearest.  Oh well.
    
        flow.trainworks_train_minimap.position = pos
        flow.trainworks_train_minimap.surface_index = train.locomotives.front_movers[1].surface.index
    end
end

function generate_cargo_string(contents)
    local stuff = {}
    for itemname, count in pairs(contents) do
        table.insert(stuff, string.format("[item=%s]=%i", itemname, count))
    end

    return table.concat(stuff, ", ")
end


function populate_modify(playernum, routenum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_modify
    local flow = frame.add{type="flow", name="trainworks_modifyflow", direction="vertical"}
    flow.add{type="textfield", name="trainworks_modifyname", text=global.routes[routenum].name}
    local button = flow.add{type="button", name="trainworks_deleteroute", caption={"gui.deleteroute"}, tooltip={"gui.deleteroute_tooltip"}}
    if #global.routes[routenum] > 0 or routenum == 1 then
        button.enabled = false
    end
    flow.add{type="textfield", name="trainworks_modifyfilter", tooltip={"gui.modifyfilter"}}
    global.gui_routemodify[playernum] = flow
    global.gui_deleteroute[playernum] = button

    -- List of stations that could be added to this route
    local toppane = flow.add{type="scroll-pane", name="trainworks_modifypane", vertical_scroll_policy="auto-and-reserve-space"}
    populate_stops_in_modify(playernum, routenum)

    frame.visible = true
end

function populate_stops_in_modify(playernum, routenum)
    if global.gui_routemodify[playernum] ~= nil then
        local toppane = global.gui_routemodify[playernum].trainworks_modifypane
        toppane.clear()

        for stopnum, x in pairs(global.stops) do
            local state = not not global.routes[routenum].stops[stopnum]
            local enabled = (routenum ~= 1)
            toppane.add{type="checkbox", name=("trainworks_routecheckbox_"..tostring(stopnum)), state=state, caption=get_backer_name(stopnum), enabled=enabled}
        end
    end
end

function clear_modify(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_modify
    frame.visible = false
    frame.clear()
    global.gui_routemodify[playernum] = nil
    global.gui_deleteroute[playernum] = nil
end


function route_add_stop(routenum, stopnum)
    global.routes[routenum].stops[stopnum] = true

    for playernum, player in pairs(game.players) do
        if global.gui_selected_route[playernum] == routenum then
            -- Prevent deletion of a non-empty route
            local button = global.gui_deleteroute[playernum]
            if button ~= nil then
                button.enabled = false
            end

            -- Add to status window
            local statuspane = global.gui_routestatus[playernum]
            if statuspane ~= nil then
                local name = "trainworks_routelabel_"..tostring(stopnum)
                if statuspane[name] == nil then
                    statuspane.add{type="label", name=name, caption=get_backer_name(stopnum)}
                end
            end
        end
    end
end

function route_remove_stop(routenum, stopnum)
    global.routes[routenum].stops[stopnum] = nil
    global.routes[routenum].dirty = true

    for playernum, player in pairs(game.players) do
        -- Allow deletion of the route if it's empty
        local button = global.gui_deleteroute[playernum]
        if button ~= nil and #global.routes[routenum].stops == 0 then
            button.enabled = true
        end


        -- Remove from status window
        local statuspane = global.gui_routestatus[playernum]
        if statuspane ~= nil then
            local name = "trainworks_routelabel_"..tostring(stopnum)
            if statuspane[name] ~= nil then
                statuspane[name].destroy()
            end
        end
    end
end


function new_route()
    -- Create a new stop, extract the backer name, and delete the stop
    -- Add stop to global.routes
    -- Add to global.route_map
    -- Add to each of global.gui_routelist
    local tempstop = game.surfaces[1].create_entity{name="trainworks_stop", position={0,0}}
    local routename = tempstop.backer_name
    tempstop.destroy()
    if global.route_map[routename] ~= nil then
        game.print("New route matches existing route name " .. routename)
        return
    end

    local routenum = global.route_counter
    global.route_counter = global.route_counter + 1
    global.routes[routenum] = {name=routename, trains={}, stops={}, provided={}, requested={}}
    global.route_map[routename] = routenum

    for playernum, player in pairs(game.players) do
        local listpane = global.gui_routelist[playernum]
        if listpane ~= nil then
            listpane.add{type="radiobutton", name=("trainworks_route_"..routenum), state=false, caption=routename}
        end
    end
end


function update_gui()
    for playernum, player in pairs(game.players) do
        if mod_gui.get_frame_flow(player).trainworks_status.visible then
            populate_train_list(playernum)
        end
    end
end


script.on_event({defines.events.on_gui_click},
    function (e)
        local player = game.players[e.player_index]
        if e.element.name == "trainworks_top_button" then
            local frame = mod_gui.get_frame_flow(player)
            if frame.trainworks_status.visible then
                clear_status(e.player_index)
                clear_modify(e.player_index)
            else
                populate_status(e.player_index)
            end
        elseif e.element.name:match("^trainworks_route_") then
            local routenum = tonumber(e.element.name:match("^trainworks_route_(.*)$"))
            select_route(e.player_index, routenum)
        elseif e.element.name:match("^trainworks_trainbutton_") then
            local trainid = tonumber(e.element.name:match("^trainworks_trainbutton_(.*)$"))
            select_train(e.player_index, trainid)
        elseif e.element.name == "trainworks_trainmode_all" then
            e.element.parent.trainworks_trainmode_issues.state = false
        elseif e.element.name == "trainworks_trainmode_issues" then
            e.element.parent.trainworks_trainmode_all.state = false
        elseif e.element.name == "trainworks_showmodify" then
            local routenum = global.gui_selected_route[e.player_index]
            local frame = mod_gui.get_frame_flow(player).trainworks_modify
            if frame.visible then
                clear_modify(e.player_index)
            else
                if routenum ~= nil then
                    populate_modify(e.player_index, routenum)
                end
            end
        elseif e.element.name:match("^trainworks_routecheckbox_") then
            local routenum = global.gui_selected_route[e.player_index]
            local stopnum = tonumber(e.element.name:match("^trainworks_routecheckbox_(.*)$"))
            if e.element.state then
                route_add_stop(routenum, stopnum)
            else
                route_remove_stop(routenum, stopnum)
            end
        elseif e.element.name == "trainworks_newroute" then
            game.print("new route")
            new_route()
        elseif e.element.name == "trainworks_deleteroute" then
            local routenum = global.gui_selected_route[e.player_index]
            if routenum == 1 then
                game.print("Can't delete universal route (should be impossible)")
            else
                game.print("delete route")
                global.cleanup_routes[routenum] = true
            end
        end
    end
)


script.on_event({defines.events.on_gui_text_changed},
    function (e)
        --game.print("Text changed by " .. fstr(e.player_index) .. ": " .. fstr(e.element.text))
    end
)


function rename_route(routenum, text)
    local oldname = global.routes[routenum].name
    if global.route_map[text] ~= nil then
        game.print("Can't rename route " .. oldname .. " to " .. text .. ", already exists!")
        return
    end
    global.route_map[oldname] = nil
    global.routes[routenum].name = text
    global.route_map[text] = routenum

    -- Forget all the trains that were associated with the old name
    -- XXX This modifies the table as we iterate over it but simply removing elements should be safe
    for trainid, train in pairs(global.routes[routenum].trains) do
        unassign_train(trainid)
    end

    for playernum, player in pairs(game.players) do
        local listpane = global.gui_routelist[playernum]
        if listpane ~= nil then
            local routelabel = listpane[("trainworks_route_"..routenum)]
            routelabel.caption = text
        end
    end
end


script.on_event({defines.events.on_gui_confirmed},
    function (e)
        if e.element.name == "trainworks_modifyname" then
            rename_route(global.gui_selected_route[e.player_index], e.element.text)
        end
    end
)
