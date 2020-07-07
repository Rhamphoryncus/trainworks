-- XXX FIXME
require("mod-gui")


function create_gui(player)
    mod_gui.get_button_flow(player).add
    {
        type="button",
        name="tw_button",
        caption="Trainworks",
        style=mod_gui.button_style
    }

    mod_gui.get_frame_flow(player).add
    {
        type="frame",
        name="tw_frame",
        caption="Trainworks frame",
        style=mod_gui.frame_style
    }
end


function update_gui()
    if not global.loaded_gui then
        global.loaded_gui = true
        -- XXX FIXME bodge
        create_gui(game.players[1])
    end
end


script.on_event({defines.events.on_gui_click},
    function (e)
        local player = game.players[e.player_index]
        if e.element.name == "tw_button" then
            local frame = mod_gui.get_frame_flow(player)
            frame.tw_frame.visible = not frame.tw_frame.visible
        end
    end
)
