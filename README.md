# <img align="left" src="https://a-lurker.github.io/icons/Aeratron_50_50.png"> Vera-Plugin-Aeratron

Control [Aeratron fans](https://aeratronaustralia.com.au/aeratron-ae3-50-3-blade-dc-ceiling-fan) using the BroadLink plugin.

Plugin tested on a Aeratron AE3 Blade DC Ceiling Fan with a rectangular remote using the openLuup environment. You also need to have the [BroadLink plugin](https://github.com/a-lurker/Vera-Plugin-BroadLink-Mk2) installed.

Make sure:
- the variable 'BroadLinkDeviceID' is set to the device ID of the IR child of the BroadLink RF remote control plugin.
- the variable 'DipSwitch' is set to match the dip switch setting as physically set in the remote control.

Available actions:

Service: urn:a-lurker-com:serviceId:Aeratron1
- SetDipSwitch: layout of dipswitch eg '0000'
- AirUpDown: 'up' or 'down'  case insensitive
- SetSpeed: number '1' to '6'
- SpeedUpDown: 'up' or 'down'  case insensitive
- SetLightOnOff: '0' or '1'

Service: urn:upnp-org:serviceId:SwitchPower1
- SetTarget: '0' or '1'

    -- an example call that you can try in the UI 'Lua Test' text box:
    local deviceID = the_id_of_the_plugin
    luup.call_action('urn:a-lurker-com:serviceId:Aeratron1', 'SetSpeed', {Speed = '3'}, deviceID)

    return true
