-- All the fun GUI stuff to interact with the user


require("mod-gui")


function create_gui(player)
    mod_gui.get_button_flow(player).add
    {
        type="button",
        name="trainworks_top_button",
        caption="Trainworks",
        style=mod_gui.button_style
    }

    mod_gui.get_frame_flow(player).add
    {
        type="frame",
        name="trainworks_frame",
        caption="Routes",
        style=mod_gui.frame_style
    }
    mod_gui.get_frame_flow(player).trainworks_frame.visible = false

    mod_gui.get_frame_flow(player).add
    {
        type="frame",
        name="trainworks_status",
        caption="Status",
        style=mod_gui.frame_style
    }
    mod_gui.get_frame_flow(player).trainworks_status.visible = false

    mod_gui.get_frame_flow(player).add
    {
        type="frame",
        name="trainworks_modify",
        caption="Add/Remove",
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


function get_backer_name(stopnum)
    local stop = global.stopchests[stopnum].stop
    if stop.valid then
        return stop.backer_name
    else
        return "<Station Removed>"
    end
end


function populate_route_list(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_frame
    local pane = frame.add{type="scroll-pane", name="trainworks_routepane", vertical_scroll_policy="auto-and-reserve-space"}
    local flow = pane.add{type="flow", name="trainworks_routeflow", direction="vertical"}
    for routename, route in pairs(global.routes) do
        flow.add{type="button", name=("trainworks_route_"..routename), caption=route.name}
    end
    frame.visible = true
end

function clear_route_list(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_frame
    frame.visible = false
    frame.clear()
end


function populate_routestatus(playernum, routename)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status
    local flow = frame.add{type="flow", name="trainworks_stationflow", direction="vertical"}
    -- Top buttons
    flow.add{type="button", name="trainworks_showmodify", caption="Modify"}
    -- List of stops
    local pane = flow.add{type="scroll-pane", name="trainworks_stationpane", vertical_scroll_policy="auto-and-reserve-space"}
    for stopnum, x in pairs(get_route_stops(routename)) do
        local name = "label_"..tostring(stopnum)
        pane.add{type="label", name=name, caption=get_backer_name(stopnum)}
    end
    frame.visible = true
    global.gui_routestatus[playernum] = pane
end

function clear_routestatus(playernum)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_status
    frame.visible = false
    frame.clear()
    global.gui_routestatus[playernum] = nil
end


function populate_modify(playernum, routename)
    local frame = mod_gui.get_frame_flow(game.players[playernum]).trainworks_modify
    local flow = frame.add{type="flow", name="trainworks_modifyflow", direction="vertical"}
    local universalcaption = "Make universal"
    if global.universal_routes[routename] then
        universalcaption = "Undo universal"
    end
    flow.add{type="button", name="trainworks_toggleuniversal", caption=universalcaption}
    flow.add{type="textfield", name="trainworks_modifyfilter"}

    -- List of stations that could be added to this route
    local toppane = flow.add{type="scroll-pane", name="trainworks_modifytoppane", vertical_scroll_policy="auto-and-reserve-space"}
    for stopnum, x in pairs(global.stopchests) do
        if not global.routes[routename].stops[stopnum] then
            local enabled = not global.universal_routes[routename]
            toppane.add{type="button", name=("trainworks_add_"..tostring(stopnum)), caption=get_backer_name(stopnum), enabled=enabled}
        end
    end

    -- XXX FIXME consider a horizontal rule here

    -- List of stations already in this route
    local bottompane = flow.add{type="scroll-pane", name="trainworks_modifybottompane", vertical_scroll_policy="auto-and-reserve-space"}
    local table = bottompane.add{type="table", name="trainworks_modifytable", column_count=2}
    for stopnum, x in pairs(global.routes[routename].stops) do
        local enabled = not global.universal_routes[routename]
        table.add{type="label", name=("trainworks_removelabel_"..tostring(stopnum)), caption=get_backer_name(stopnum)}
        table.add{type="button", name=("trainworks_remove_"..tostring(stopnum)), caption="X", enabled=enabled}
        -- XXX FIXME should use a more appropriate LuaStyle that's not overly wide
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


function route_add_stop(routename, stopnum)
    global.routes[routename].stops[stopnum] = true

    for playernum, player in pairs(game.players) do
        -- Add to status window
        local statuspane = global.gui_routestatus[playernum]
        if statuspane ~= nil then
            local name = "label_"..tostring(stopnum)
            if statuspane[name] == nil then
                statuspane.add{type="label", name=name, caption=get_backer_name(stopnum)}
            end
        end

        -- Remove from top of modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            local x = modifypane.trainworks_modifytoppane
            local name = "trainworks_add_"..tostring(stopnum)
            if x[name] ~= nil then
                x[name].destroy()
            end
        end

        -- Add to bottom of modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            local table = modifypane.trainworks_modifybottompane.trainworks_modifytable
            local name = "trainworks_removelabel_"..tostring(stopnum)
            if table[name] == nil then
                local enabled = not global.universal_routes[routename]
                table.add{type="label", name=name, caption=get_backer_name(stopnum)}
                table.add{type="button", name=("trainworks_remove_"..tostring(stopnum)), caption="X", enabled=enabled}
            end
        end
    end
end

function route_remove_stop(routename, stopnum)
    global.routes[routename].stops[stopnum] = nil
    global.routes[routename].dirty = true

    for playernum, player in pairs(game.players) do
        -- Remove from status window
        local statuspane = global.gui_routestatus[playernum]
        if statuspane ~= nil then
            local name = "label_"..tostring(stopnum)
            if statuspane[name] ~= nil then
                statuspane[name].destroy()
            end
        end

        -- Add to top of modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            local x = modifypane.trainworks_modifytoppane
            local name = "trainworks_add_"..tostring(stopnum)
            if x[name] == nil then
                local enabled = not global.universal_routes[routename]
                x.add{type="button", name=name, caption=get_backer_name(stopnum), enabled=enabled}
            end
        end

        -- Remove from bottom of modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            local table = modifypane.trainworks_modifybottompane.trainworks_modifytable
            local name = "trainworks_removelabel_"..tostring(stopnum)
            if table[name] ~= nil then
                table[name].destroy()
                table["trainworks_remove_"..tostring(stopnum)].destroy()
            end
        end
    end
end


function activate_universal(routename)
    global.universal_routes[routename] = true
    global.routes[routename].dirty = true

    for playernum, player in pairs(game.players) do
        -- Update the route status window
        clear_routestatus(playernum)
        populate_routestatus(playernum, routename)

        -- Update the route modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            modifypane.trainworks_toggleuniversal.caption = "Undo universal"

            for childname, child in pairs(modifypane.trainworks_modifytoppane.children) do
                child.enabled = false
            end

            for childname, child in pairs(modifypane.trainworks_modifybottompane.trainworks_modifytable.children) do
                child.enabled = false
            end
        end
    end
end


function deactivate_universal(routename)
    global.universal_routes[routename] = nil
    global.routes[routename].dirty = true

    for playernum, player in pairs(game.players) do
        -- Update the route status window
        clear_routestatus(playernum)
        populate_routestatus(playernum, routename)

        -- Update the route modify window
        local modifypane = global.gui_routemodify[playernum]
        if modifypane ~= nil then
            modifypane.trainworks_toggleuniversal.caption = "Make universal"

            for childname, child in pairs(modifypane.trainworks_modifytoppane.children) do
                child.enabled = true
            end

            for childname, child in pairs(modifypane.trainworks_modifybottompane.trainworks_modifytable.children) do
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
            if frame.trainworks_frame.visible then
                clear_route_list(e.player_index)
                clear_routestatus(e.player_index)
                clear_modify(e.player_index)
            else
                populate_route_list(e.player_index)
            end
        elseif e.element.name:match("^trainworks_route_") then
            --local routename = e.element.caption
            local routename = tonumber(e.element.name:match("^trainworks_route_(.*)$"))
            global.gui_selected_route[e.player_index] = routename  -- Cache it for later
            log("Bah "..routename)
            local frame = mod_gui.get_frame_flow(player).trainworks_status
            if frame.visible then
                clear_routestatus(e.player_index)
                clear_modify(e.player_index)
            else
                populate_routestatus(e.player_index, routename)
            end
        elseif e.element.name == "trainworks_showmodify" then
            local routename = global.gui_selected_route[e.player_index]
            local frame = mod_gui.get_frame_flow(player).trainworks_modify
            if frame.visible then
                clear_modify(e.player_index)
            else
                populate_modify(e.player_index, routename)
            end
        elseif e.element.name:match("^trainworks_add_") then
            local routename = global.gui_selected_route[e.player_index]
            local stopnum = tonumber(e.element.name:match("^trainworks_add_(.*)$"))
            route_add_stop(routename, stopnum)
            log("Add "..fstr(stopnum))
        elseif e.element.name:match("^trainworks_remove_") then
            local routename = global.gui_selected_route[e.player_index]
            local stopnum = tonumber(e.element.name:match("^trainworks_remove_(.*)$"))
            route_remove_stop(routename, stopnum)
            log("Remove "..fstr(stopnum))
        elseif e.element.name == "trainworks_toggleuniversal" then
            local routename = global.gui_selected_route[e.player_index]
            if global.universal_routes[routename] then
                deactivate_universal(routename)
            else
                activate_universal(routename)
            end
        end
    end
)
