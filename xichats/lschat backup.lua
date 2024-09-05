addon.name      = 'lschat2';
addon.author    = 'K0D3R';
addon.version   = '1.0';
addon.desc      = 'Outputs Linkshell, Party, and Tell Chat to a Window';
addon.link      = '';

require('common');
local imgui = require('imgui');

-- Chat Variables
local chat = {
    messages = T{ },
    is_open = { true, },
    filter = 'All', -- Default filter
};

-- Color Window Variable
local colorWindowOpen = { false, }

-- Add new variables for the input buffers
local usernameBuffer = {''}
local colorBuffer = {''}

-- Table to store the usernames and colors
local userColors = {}

--------------------------------
-- Load User Colors From File --
--------------------------------
local function loadUserColors()
    local file = io.open(addon.path:append('\\usercolors.txt'), 'r');
    if file then
        for line in file:lines() do
            local username, color = line:match('(%w+): ({[^}]+})')
            local r, g, b, a = color:match('{(%d+%.?%d*), (%d+%.?%d*), (%d+%.?%d*), (%d+%.?%d*)}')
            userColors[username] = {tonumber(r), tonumber(g), tonumber(b), tonumber(a)}
        end
        file:close()
    end
end

-- Call the function to load User Colors
loadUserColors()

----------------------
-- Clean Up Strings --
----------------------
local function clean_str(str)
    -- Parse the strings auto-translate tags..
    str = AshitaCore:GetChatManager():ParseAutoTranslate(str, true);

    -- Strip FFXI-specific color and translate tags..
    str = str:strip_colors();
    str = str:strip_translate(true);

    -- Strip line breaks..
    while (true) do
        local hasN = str:endswith('\n');
        local hasR = str:endswith('\r');

        if (not hasN and not hasR) then
            break;
        end

        if (hasN) then str = str:trimend('\n'); end
        if (hasR) then str = str:trimend('\r'); end
    end

    -- Replace mid-linebreaks..
    return (str:gsub(string.char(0x07), '\n'));
end

------------------------------
-- Get Current Time as String --
------------------------------
local function get_current_time()
    local t = os.date('*t')
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

------------------------------
-- Check for slash commands --
------------------------------
ashita.events.register('command', 'command_cb', function (e)
    -- Parse the command arguments..
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/lschat')) then
        return;
    end

    -- Block all related commands..
    e.blocked = true;

    -- Toggle the chat window..
    chat.is_open[1] = not chat.is_open[1];
end);

---------------------------
-- Read Incoming Packets --
---------------------------
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    -- Packet: Incoming Chat Message
    if (e.id == 0x017) then
        local msgType = struct.unpack('B', e.data, 0x04 + 1);
        if msgType == 26 then
            return; -- Skip processing this message
        end

        local character = struct.unpack('c15', e.data_modified, 0x08 + 1):trimend('\x00');
        local msg = struct.unpack('s', e.data_modified, 0x17 + 0x01);

        -- Debug output
        print("Packet ID: 0x017, MsgType: " .. msgType .. ", Character: " .. character .. ", Message: " .. msg);

        -- Replace percent signs with double percent signs
        msg = string.gsub(msg, "%%", "%%%%");
        msg = clean_str(msg);

        -- Determine message type for display
        local chatType = "Unknown";
        local color = {1.0, 1.0, 1.0, 1.0}; -- Default color is White
        
        if msgType == 1 then
            chatType = "Party";
            color = {1.0, 1.0, 1.0, 1.0}; -- White
        elseif msgType == 3 then
            chatType = "Tell";
            color = {0.8, 0.6, 0.9, 1.0}; -- Light Purple
        elseif msgType == 4 then
            chatType = "Party";
            color = {0.678, 0.847, 0.902, 1.0}; -- Light Blue
        elseif msgType == 5 then
            chatType = "Linkshell1";
            color = {0.6, 1.0, 0.6, 1.0}; -- Bright Light Green
        elseif msgType == 27 then
            chatType = "Linkshell2";
            color = {0.5, 0.9, 0.5, 1.0}; -- Bright Dark Green
        end

        local timestamp = get_current_time()
        local fullMsg = timestamp .. " " .. character .. ": " .. msg;
        if (not chat.messages:hasval(fullMsg)) then
            chat.messages:append({message = fullMsg, color = color, type = chatType});
            -- Play a sound file when a new message is added
            --ashita.misc.play_sound(addon.path:append('\\sounds\\message.wav'));
        end
    end
end);

---------------------------
-- Read Outgoing Packets --
---------------------------
ashita.events.register('packet_out', 'outgoing_packet', function (e)
    if (e.id == 0x0B5) then
        local msgType = struct.unpack('B', e.data, 0x04 + 1);
        if msgType == 26 then
            return; -- Skip processing this message
        end

        local msg = struct.unpack('s', e.data_modified, 0x06 + 0x01);

        -- Replace percent signs with double percent signs
        msg = string.gsub(msg, "%%", "%%%%");
        msg = clean_str(msg);

        local character = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or 'Unknown';
        local chatType = "Unknown";
        local color = {1.0, 1.0, 1.0, 1.0}; -- Default color is White

        if msgType == 1 then
            chatType = "Party";
            color = {1.0, 1.0, 1.0, 1.0}; -- White
        elseif msgType == 3 then
            chatType = "Tell";
            color = {0.8, 0.6, 0.9, 1.0}; -- Light Purple
        elseif msgType == 4 then
            chatType = "Party";
            color = {0.678, 0.847, 0.902, 1.0}; -- Light Blue
        elseif msgType == 5 then
            chatType = "Linkshell1";
            color = {0.6, 1.0, 0.6, 1.0}; -- Bright Light Green
        elseif msgType == 27 then
            chatType = "Linkshell2";
            color = {0.5, 0.9, 0.5, 1.0}; -- Bright Dark Green
        end

        local timestamp = get_current_time()
        local fullMsg = timestamp .. " " .. character .. ": " .. msg;
        if (not chat.messages:hasval(fullMsg)) then
            chat.messages:append({message = fullMsg, color = color, type = chatType});
        end
    end    
end);

-----------------
-- Form Design --
-----------------
ashita.events.register('d3d_present', 'present_cb', function ()
    if (chat.is_open[1]) then
        imgui.SetNextWindowSize({ 400, 400, }, ImGuiCond_FirstUseEver);
        if (imgui.Begin('Chat Window', chat.is_open)) then
            -- Filter Buttons
            if imgui.Button('All') then
                chat.filter = 'All';
            end
            imgui.SameLine();
            if imgui.Button('Party') then
                chat.filter = 'Party';
            end
            imgui.SameLine();
            if imgui.Button('Tells') then
                chat.filter = 'Tell';
            end
            imgui.SameLine();
            if imgui.Button('LS1') then
                chat.filter = 'Linkshell1';
            end
            imgui.SameLine();
            if imgui.Button('LS2') then
                chat.filter = 'Linkshell2';
            end

            imgui.Separator();
            
            if (imgui.BeginChild('MessagesWindow', {0, -imgui.GetFrameHeightWithSpacing() + 20})) then
                for _, v in ipairs(chat.messages) do
                    if chat.filter == 'All' or v.type == chat.filter then
                        local msg = v.message
                        local color = v.color or {1.0, 1.0, 1.0, 1.0}  -- Default color is White
                    
                        imgui.TextColored(color, msg)
                    end
                end
                imgui.SetScrollHereY(1.0);  -- Scrolls to the bottom
            end
            imgui.EndChild();
        end
        imgui.End();
    end
end);
