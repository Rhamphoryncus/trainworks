-- XXX FIXME
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
        name="trainworks_stations",
        caption="Stations",
        style=mod_gui.frame_style
    }
    mod_gui.get_frame_flow(player).trainworks_stations.visible = false
end


function update_gui()
    if not global.loaded_gui then
        global.loaded_gui = true
        -- XXX FIXME bodge
        create_gui(game.players[1])
    end
end


function populate_route_list(player)
    local frame = mod_gui.get_frame_flow(player).trainworks_frame
    local pane = frame.add{type="scroll-pane", name="trainworks_routepane", vertical_scroll_policy="auto-and-reserve-space"}
    local flow = pane.add{type="flow", name="trainworks_routeflow", direction="vertical"}
    for routename, route in pairs(global.routes) do
        flow.add{type="button", name=("trainworks_route_"..routename), caption=routename}
    end
    frame.visible = true
end

function clear_route_list(player)
    local frame = mod_gui.get_frame_flow(player).trainworks_frame
    frame.visible = false
    frame.clear()
end


function populate_station_list(player, routename)
    local frame = mod_gui.get_frame_flow(player).trainworks_stations
    local flow = frame.add{type="flow", name="trainworks_stationflow", direction="vertical"}
    -- XXX button to add stops and button to make (or clear) universal
    flow.add{type="button", name="trainworks_stationaddstations", caption="Add stations"}
    flow.add{type="button", name="trainworks_stationuniversal", caption="Make universal"}
    local pane = flow.add{type="scroll-pane", name="trainworks_stationpane", vertical_scroll_policy="auto-and-reserve-space"}
    local table = pane.add{type="table", name="trainworks_stationtable", column_count=2}
    for stopnum, x in pairs(global.routes[routename].stops) do
        table.add{type="label", caption=global.stopchests[stopnum].stop.backer_name}
        table.add{type="button", name=("trainworks_station_"..fstr(stopnum)), caption="X"}
        -- XXX FIXME should use a more appropriate LuaStyle that's not overly wide
    end
    frame.visible = true
end

function clear_station_list(player)
    local frame = mod_gui.get_frame_flow(player).trainworks_stations
    frame.visible = false
    frame.clear()
end


script.on_event({defines.events.on_gui_click},
    function (e)
        local player = game.players[e.player_index]
        if e.element.name == "trainworks_top_button" then
            local frame = mod_gui.get_frame_flow(player)
            if frame.trainworks_frame.visible then
                clear_route_list(player)
                clear_station_list(player)
            else
                populate_route_list(player)
            end
        elseif e.element.name:match("^trainworks_route_") then
            local routename = e.element.caption
            log("Bah "..routename)
            local frame = mod_gui.get_frame_flow(player).trainworks_stations
            if frame.visible then
                clear_station_list(player)
            else
                populate_station_list(player, routename)
            end
        end
    end
)
