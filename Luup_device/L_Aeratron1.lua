-- a-lurker, copyright 2018
-- First investigation 20 February 2018
-- First release 18 August 2020

-- Tested on openLuup

--[[
    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    version 3 (GPLv3) as published by the Free Software Foundation;

    In addition to the GPLv3 License, this software is only for private
    or home usage. Commercial utilisation is not authorized.

    The above copyright notice and this permission notice shall be included
    in all copies or substantial portions of the Software.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    Pairing: as described in the Aeratron manual:

    The remote can be set to any one of sixteen fans within a 7m radius.
    The remote remembers all settings, so all settings must be ready
    before transmitting the codde.

    Code match for Transmitter (hand held) and Receiver
    1. Set the code to be encoded by the Dip Switch of transmitter
    2. Switch on the main power to activate the receiver
    3. Within 3 minutes after the power is turned on, press the transmitter’s “ON/OFF” key and do
       not release for 5 seconds
    4. Receiver issues four (beep) short sounds which indicates successful code match
    5. After successful code match, the fan automatically returns to the original speed as indicated
       on LCD screen
    6. Press any transmitter button to check for proper functioning
    7. For code changes, repeat steps 1 to 6

    The transmitter and receiver will memorise the code for future use (also if switched off).

    When is a code transmitted?
    1) the light button is pressed on or off
    2) the power button is pressed on or off
       the power on/off button toggles between sending zero speed and the previous fan speed setting (ie 1 to 6)
    3) the speed up/down buttons are pressed:
       if the fan speed was zero (ie power was 'off'), last speed setting (ie 1 to 6) is sent
       if the last speed setting was 1 to 6 (ie power was 'on'), the speed changes up or down but never goes to zero
    4) the forward/reverse button is pressed and the fans speed is currently 1 to 6 (ie power is 'on')

    When is a code not transmitted?
    1) the dip switch is changed
    2) the forward/reverse button is pressed and the fan speed is currently zero (ie power is 'off')


    Operatingspeed(rpm)/PowerUsage(Watt)

    Model: e503 (3 blades)
    Speed1:  51rpm,  3.8W
    Speed2:  70rpm,  4.5W
    Speed3: 103rpm,  7.5W
    Speed4: 119rpm,  9.5W
    Speed5: 139rpm, 13.6W
    Speed6: 158rpm, 18.0W

    Model: e502 (2 blades)
    Speed1:  52rpm,  3.9W
    Speed2:  73rpm,  4.5W
    Speed3: 113rpm,  7.7W
    Speed4: 131rpm,  9.6W
    Speed5: 153rpm, 13.6W
    Speed6: 177rpm, 18.2W
]]

local PLUGIN_NAME     = 'Aeratron'
local PLUGIN_SID      = 'urn:a-lurker-com:serviceId:'..PLUGIN_NAME..'1'
local PLUGIN_VERSION  = '0.51'
local THIS_LUL_DEVICE = nil
local SWP_SID         = 'urn:upnp-org:serviceId:SwitchPower1'

-- this the id of the BraodLink device that will tramsmit the RF code
local m_broadLinkDeviceID = nil
local m_lastSpeed = 0

-- these are the indices of misc data bits
local SW_4    = 1   -- start of the 4 it dip switch setting
local FWD_REV = 11  -- forward/reverse bit
local SPD_B2  = 14  -- speed bit 2
local SPD_B1  = 15  -- speed bit 1
local SPD_B0  = 16  -- speed bit 0
local LIGHT_S = 17  -- light on/off: first bit
local LIGHT_0 = 19  -- light on/off: bit is always zero and the rest are one
local LIGHT_E = 24  -- light on/off: last bit

-- set up the baseline RF code for the fan
local m_codeTab = {
    '0',   --  1  sw4
    '0',   --  2  sw3
    '0',   --  3  sw2
    '0',   --  4  sw1

    '0',   --  5  unused?
    '0',   --  6  unused?
    '0',   --  7  unused?
    '0',   --  8  unused?
    '0',   --  9  unused?
    '0',   -- 10  unused?

    '0',   -- 11 forward/reverse

    '0',   -- 12  unused? Possibly beeps when set to high????
    '0',   -- 13  unused?

    '0',   -- 14  spd2  Also acts as power on/off
    '0',   -- 15  spd1  where off = '000'
    '0',   -- 16  spd0

    -- on = '11011111', off '00000000'
    '0',   -- 17
    '0',   -- 18
    '0',   -- 19  <-- stays at '0'
    '0',   -- 20
    '0',   -- 21
    '0',   -- 22
    '0',   -- 23
    '0'    -- 24
}

-- don't change this, it won't do anything. Use the debugEnabled flag instead
local DEBUG_MODE = true

local function debug(textParm, logLevel)
    if DEBUG_MODE then
        local text = ''
        local theType = type(textParm)
        if (theType == 'string') then
            text = textParm
        else
            text = 'type = '..theType..', value = '..tostring(textParm)
        end
        luup.log(PLUGIN_NAME..' debug: '..text,50)

    elseif (logLevel) then
        local text = ''
        if (type(textParm) == 'string') then text = textParm end
        luup.log(PLUGIN_NAME..' debug: '..text, logLevel)
    end
end

-- If non existent, create the variable. Update
-- the variable, only if it needs to be updated
local function updateVariable(varK, varV, sid, id)
    if (sid == nil) then sid = PLUGIN_SID      end
    if (id  == nil) then  id = THIS_LUL_DEVICE end

    if (varV == nil) then
        if (varK == nil) then
            luup.log(PLUGIN_NAME..' debug: '..'Error: updateVariable was supplied with nil values', 1)
        else
            luup.log(PLUGIN_NAME..' debug: '..'Error: updateVariable '..tostring(varK)..' was supplied with a nil value', 1)
        end
        return
    end

    local newValue = tostring(varV)
    debug(newValue..' --> '..varK)

    local currentValue = luup.variable_get(sid, varK, id)
    if ((currentValue ~= newValue) or (currentValue == nil)) then
        luup.variable_set(sid, varK, newValue, id)
    end
end

-- Encoding: each '1' becomes an '01' sequence and each '0' becomes a '10' sequence
-- Decoding: each '01' sequence becomes a '1' and each '10' sequence becomes an '0'
local function manchesterEncode(codeTab)
    local codeStr = table.concat(codeTab, ' ')
    debug(codeStr)

    -- When DEcoding these ranges where used to test for a short or long pulse:
    -- Short: (hex >= 0x0e) and (hex <= 0x17)   middle about 12h
    -- Long:  (hex >= 0x1c) and (hex <= 0x27)   middle about 21h
    -- However these values appeared to be the most common; may need tweaking:
    local SHORT = '10'   -- '0'
    local LONG  = '23'   -- '1'

    --  'b2'   a 433MHz RF code
    --  '08'   8 repeats
    --  '32'   lsb 32h bits to send: = 30h code bits + leadin HIGH + terminator = 32h
    --  '00'   msb 32h bits to send
    --  '1c'   leadin HIGH
    local LEAD_IN  = 'b2 08 32 00 1c '
    local LEAD_OUT = ' ce 00 00 00 00 00 00'

    local encodedTab = {
    }

    -- do the Manchester encoding for the 24 bits of data
    for i=1, 24  do
        if (codeTab[i] == '1') then
            table.insert(encodedTab, SHORT)   -- '0'
            table.insert(encodedTab, LONG)    -- '1'
        elseif (codeTab[i] == '0') then
            table.insert(encodedTab, LONG)    -- '1'
            table.insert(encodedTab, SHORT)   -- '0'
        else
            debug('Error: input code is not 1 or 0')
        end
    end

    local encodedStr = LEAD_IN..table.concat(encodedTab, ' ')..LEAD_OUT
    debug(encodedStr)
    return encodedStr
end

-- Send the code to the BroadLink device
local function sendCode()
    local fanCode = manchesterEncode(m_codeTab)
    luup.call_action('urn:a-lurker-com:serviceId:IrTransmitter1', 'SendCode', {Code = fanCode}, m_broadLinkDeviceID)
end

-- Service: change the dip switch setting.
-- Set up the code bits to reflect the remote's dipswitch setting (ie the remote to fan pairing).
-- Dipswitch is numbered from left to right ie sw1 to sw4.
-- Low is considered as the switch being towards the battery case.
-- The remote can be set to any one of sixteen fans within a 7m radius.
-- The power setting is unchanged
-- Example input, a four digit binary string: '0000'
local function setDipSwitch(dipSwitch)
    if ((dipSwitch == nil) or (#dipSwitch ~= 4)) then dipSwitch = '0000' end
    local dipSwCode = tonumber(dipSwitch,2)
    if ((dipSwCode == nil) or (dipSwCode < 0) or (dipSwCode > 15)) then dipSwitch = '0000' end

    local count = SW_4
    for bitStr in dipSwitch:gmatch('.') do
        m_codeTab[count] = bitStr
        count = count+1
    end
    updateVariable('DipSwitch', dipSwitch)
end

-- Service: direction down/up ie forward/reverse
-- Arrow down:  move the ambient air down in summer:      rotation direction when looking upwards is anticlockwise
-- Arrow down:  move a heater's warm air down in winter:  rotation direction when looking upwards is anticlockwise
-- Arrow up:    move an A/C's cold air up in summer:      rotation direction when looking upwards is clockwise
-- The power setting is unchanged
local function airUpDown(upDown)
    if (type(upDown) ~= 'string') then upDown = 'down' end
    upDown = upDown:lower()

    -- forward/reverse 0 = anticlockwise, 1 = clockwise (looking upwards)
    -- preferred default is moving air downwards ie reverse
    if (upDown == 'up') then
         m_codeTab[FWD_REV] = '1'  -- shows up arrow on remote
    else
         m_codeTab[FWD_REV] = '0'  -- shows down arrow on remote
         -- anything else is forced to 'down'
         upDown = 'down'
    end

    updateVariable('Direction', upDown)
end

-- Alter the speed settings in the code table ready to be transmitted as needed
local function setSpeedInCodeTab(speedType)
    -- speed can be:
    --    'off': set RF code speed to zero
    --    'last': use last speed
    --    'up' or 'down': get last used speed then inc/dec and limit from 1 to 6
    --    number: the number is limited from 1 to 6

    debug(speedType)
    local speed = 1

    -- default the RF code to a speed of 0 ie off
    m_codeTab[SPD_B2], m_codeTab[SPD_B1], m_codeTab[SPD_B0] = '0', '0', '0'

    -- everything results in the fan being on except the 'off' command
    -- the last used speed is retained
    if (speedType == 'off') then
        updateVariable('Status', '0', SWP_SID)
        -- update the fan
        sendCode()
        return
    end

    -- get the last used speed, we may need it. It's in the range 1 to 6
    local lastSpeed = luup.variable_get(PLUGIN_SID, 'Speed', THIS_LUL_DEVICE)
    lastSpeed = tonumber(lastSpeed)
    if (lastSpeed == nil) then speedType = 'last' lastSpeed = 1 end

    debug('last speed = '..tostring(lastSpeed))

    if (speedType == 'last') then
        -- use the last used speed
        -- this case occurs when the fan is turned on. see setFanOnOff()
        speed = lastSpeed
    elseif (speedType == 'up') then
        speed = lastSpeed + 1
    elseif (speedType == 'down') then
        speed = lastSpeed - 1
    else -- a number was passed in
        speed = tonumber(speedType)
        if (speed == nil) then speed = 1 end
    end

    -- maintain the speed in the valid range of 1 to 6
    if     (speed < 1) then speed = 1
    elseif (speed > 6) then speed = 6 end
    updateVariable('Speed', tostring(speed))

    -- binary encode the speed
    if (speed >= 4) then m_codeTab[SPD_B2] = '1' speed = speed-4 end  -- 4 5 6: 100 101 110
    if (speed >= 2) then m_codeTab[SPD_B1] = '1' speed = speed-2 end  --   2 3:  10  11
    if (speed == 1) then m_codeTab[SPD_B0] = '1' end                  --     1:   1

    updateVariable('Status', '1', SWP_SID)

    -- update the fan
    sendCode()
end

-- Service: change the speed setting. The speed can be adjusted from 1 to 6.
-- Note that if the fan is off (RF code speed = 0) then changing the speed
-- in the range 1 to 6 effectively turns the fan on.
local function setSpeed(speed)
    -- the speed is validated in setSpeedInCodeTab()
    speed = tonumber(speed)
    if (speed == nil) then speed = 1 end
    setSpeedInCodeTab(speed)
end

-- Service: change the speed up or down. The speed can be adjusted from 1 to 6.
-- Note that when using the remote, if the fan is off, setting the speed up or down turns the
-- fan on but does not actually change the speed. The last used speed is used. This code
-- works a little differently: The speed changes from the last used speed, if the fan was off.
local function speedUpDown(upDown)
    if (type(upDown) ~= 'string') then upDown = 'down' end
    upDown = upDown:lower()
    if not((upDown == 'up') or (upDown == 'down')) then upDown = 'down' end
    setSpeedInCodeTab(upDown)
end

-- Service: power on/off
-- Note that if the fan is set to on, then the last used speed is used.
local function setFanOnOff(onOff)
    if not((onOff == '0') or (onOff == '1')) then onOff = '0' end

    if (onOff == '1') then
        setSpeedInCodeTab('last')
    else
        setSpeedInCodeTab('off')
    end
end

-- Service: optional light on/off setting
local function setLightOnOff(onOff)
    if (onOff == '1') then
        -- on = '11011111'
        for i=LIGHT_S, LIGHT_E  do m_codeTab[i] = '1' end
        m_codeTab[LIGHT_0] = '0'
    else
        -- off '00000000'
        for i=LIGHT_S, LIGHT_E  do m_codeTab[i] = '0' end
    end
    -- update the light
    sendCode()
end

-- OK lets do it
function luaStartUp(lul_device)
    THIS_LUL_DEVICE = lul_device
    debug('Initialising plugin: '..PLUGIN_NAME)

    -- Lua ver 5.1 does not have bit functions, whereas ver 5.2 and above do. Not
    -- that this matters in this code but it's nice to know if anything changes.
    debug('Using: '.._VERSION)

    -- set up some defaults:
    updateVariable('PluginVersion', PLUGIN_VERSION)

    -- set up some defaults:
    local debugEnabled = luup.variable_get(PLUGIN_SID, 'DebugEnabled', THIS_LUL_DEVICE)
    if not((debugEnabled == '0') or (debugEnabled == '1')) then
        debugEnabled = '0'
        updateVariable('DebugEnabled', debugEnabled)
    end
    DEBUG_MODE = (debugEnabled == '1')

    local pluginEnabled = luup.variable_get(PLUGIN_SID, 'PluginEnabled', THIS_LUL_DEVICE)
    if not((pluginEnabled == '0') or (pluginEnabled == '1')) then
        pluginEnabled = '1'
        updateVariable('PluginEnabled', pluginEnabled)
    end
    if (pluginEnabled ~= '1') then return true, 'All OK', PLUGIN_NAME end

    -- value dipSwitch is validated in setDipSwitch()
    local dipSwitch = luup.variable_get(PLUGIN_SID, 'DipSwitch', THIS_LUL_DEVICE)
    setDipSwitch(dipSwitch)

    -- value direction is validated in airUpDown()
    local direction = luup.variable_get(PLUGIN_SID, 'Direction', THIS_LUL_DEVICE)
    airUpDown(direction)

    m_broadLinkDeviceID = luup.variable_get(PLUGIN_SID, 'BroadLinkDeviceID', THIS_LUL_DEVICE)
    m_broadLinkDeviceID = tonumber(m_broadLinkDeviceID,10)
    if (m_broadLinkDeviceID == nil) then
        updateVariable('BroadLinkDeviceID', '???')
        debug('Enter the device ID of the IR child of the BroadLink RF remote control plugin',50)
        return false, 'Enter the RF remote control device ID', PLUGIN_NAME
    end

    -- required for UI7. UI5 uses true or false for the passed parameter.
    -- UI7 uses 0 or 1 or 2 for the parameter. This works for both UI5 and UI7
    luup.set_failure(false)

    return true, 'All OK', PLUGIN_NAME
end
