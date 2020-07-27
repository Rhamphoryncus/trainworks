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
    local stop = global.stopchests[stopnum].stop
    if stop.valid then
        return stop.backer_name
    else
        return "<Station Removed>"
    end
end


function populate_status(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status

    -- List of routes to select from
    local routepane = frame.add{type="scroll-pane", name="trainworks_routepane", vertical_scroll_policy="auto-and-reserve-space"}
    local first = nil
    for routenum, route in pairs(global.routes) do
        routepane.add{type="radiobutton", name=("trainworks_route_"..routenum), state=(not first), caption=route.name}
        if first == nil then
            first = routenum
        end
    end
    global.gui_routelist[playernum] = routepane

    -- Stops within the selected route
    local flow = frame.add{type="flow", name="trainworks_stationflow", direction="vertical"}
    flow.add{type="button", name="trainworks_showmodify", caption={"gui.showmodify"}}
    local statuspane = flow.add{type="scroll-pane", name="trainworks_stationpane", vertical_scroll_policy="auto-and-reserve-space"}
    global.gui_routestatus[playernum] = statuspane
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
    -- Unset all the radiobuttons
    local pane = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status.trainworks_routepane
    for childname, child in pairs(pane.children) do
        child.state = false
    end

    -- Hide and reshow the route status pane
    global.gui_selected_route[playernum] = routenum  -- Cache it for later
    clear_modify(playernum)
    populate_stops_in_route(playernum, routenum)

    -- Reset the active radiobutton
    pane[("trainworks_route_"..routenum)].state = true
end

function populate_stops_in_route(playernum, routenum)
    local pane = global.gui_routestatus[playernum]

    pane.clear()

    if routenum ~= nil then
        for stopnum, x in pairs(get_route_stops(routenum)) do
            local name = "label_"..tostring(stopnum)
            pane.add{type="label", name=name, caption=get_backer_name(stopnum)}
        end
    end
end


function populate_modify(playernum, routenum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_modify
    local flow = frame.add{type="flow", name="trainworks_modifyflow", direction="vertical"}
    flow.add{type="textfield", name="trainworks_modifyname", text=global.routes[routenum].name}
    local universalcaption = {"gui.toggleuniversal"}
    if global.universal_routes[routenum] then
        universalcaption = "Undo universal"
    end
    flow.add{type="button", name="trainworks_toggleuniversal", caption=universalcaption}
    flow.add{type="textfield", name="trainworks_modifyfilter"}

    -- List of stations that could be added to this route
    local toppane = flow.add{type="scroll-pane", name="trainworks_modifypane", vertical_scroll_policy="auto-and-reserve-space"}
    for stopnum, x in pairs(global.stopchests) do
        local state = not not global.routes[routenum].stops[stopnum]
        local enabled = not global.universal_routes[routenum]
        toppane.add{type="checkbox", name=("trainworks_checkbox_"..tostring(stopnum)), state=state, caption=get_backer_name(stopnum), enabled=enabled}
    end

    frame.visible = true
    global.gui_routemodify[playernum] = flow
end

function clear_modify(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_modify
    frame.visible = false
    frame.clear()
    global.gui_routemodify[playernum] = nil
end


function route_add_stop(routenum, stopnum)
    global.routes[routenum].stops[stopnum] = true

    for playernum, player in pairs(game.players) do
        -- Add to status window
        local statuspane = global.gui_routestatus[playernum]
        if statuspane ~= nil then
            local name = "label_"..tostring(stopnum)
            if statuspane[name] == nil then
                statuspane.add{type="label", name=name, caption=get_backer_name(stopnum)}
            end
        end
    end
end

function route_remove_stop(routenum, stopnum)
    global.routes[routenum].stops[stopnum] = nil
    global.routes[routenum].dirty = true

    for playernum, player in pairs(game.players) do
        -- Remove from status window
        local statuspane = global.gui_routestatus[playernum]
        if statuspane ~= nil then
            local name = "label_"..tostring(stopnum)
            if statuspane[name] ~= nil then
                statuspane[name].destroy()
            end
        end
    end
end


function activate_universal(routenum)
    global.universal_routes[routenum] = true
    global.routes[routenum].dirty = true

    for playernum, player in pairs(game.players) do
        -- Update the route status window
        populate_stops_in_route(playernum, routenum)

        -- Update the route modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            modifypane.trainworks_toggleuniversal.caption = "Undo universal"

            for childname, child in pairs(modifypane.trainworks_modifypane.children) do
                child.enabled = false
            end
        end
    end
end


function deactivate_universal(routenum)
    global.universal_routes[routenum] = nil
    global.routes[routenum].dirty = true

    for playernum, player in pairs(game.players) do
        -- Update the route status window
        populate_stops_in_route(playernum, routenum)

        -- Update the route modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            modifypane.trainworks_toggleuniversal.caption = {"gui.toggleuniversal"}

            for childname, child in pairs(modifypane.trainworks_modifypane.children) do
                child.enabled = true
            end
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
        elseif e.element.name:match("^trainworks_checkbox_") then
            local routenum = global.gui_selected_route[e.player_index]
            local stopnum = tonumber(e.element.name:match("^trainworks_checkbox_(.*)$"))
            if e.element.state then
                route_add_stop(routenum, stopnum)
                log("Add "..fstr(stopnum))
            else
                route_remove_stop(routenum, stopnum)
                log("Remove "..fstr(stopnum))
            end
        elseif e.element.name == "trainworks_toggleuniversal" then
            local routenum = global.gui_selected_route[e.player_index]
            if global.universal_routes[routenum] then
                deactivate_universal(routenum)
            else
                activate_universal(routenum)
            end
        end
    end
)


script.on_event({defines.events.on_gui_text_changed},
    function (e)
        log("Text changed by " .. fstr(e.player_index) .. ": " .. fstr(e.element.text))
    end
)


function rename_route(routenum, text)
    local oldname = global.routes[routenum].name
    if global.route_map[text] ~= nil then
        game.print("Can't rename route " .. oldname .. " to " .. text .. ", already exists!")
        return
    end
    log("Renaming route " .. fstr(routenum) .. " to " .. fstr(text))
    global.route_map[oldname] = nil
    global.routes[routenum].name = text
    global.route_map[text] = routenum

    -- Forget all the trains that were associated with the old name
    global.routes[routenum].trains = {}

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
