addon.name      = 'xichats';
addon.author    = 'K0D3R, Nils';
addon.version   = '1.0';
addon.desc      = 'Outputs Linkshell, Party, and Tell Chat to a Window';
addon.link      = '';

require('common');
local imgui = require('imgui');

-- Chat Variables
local chat = {
    messages = T{ },
    is_open = { true, },
    filters = {
        All = true,
        Party = true,
        Tell = true,
        Linkshell1 = true,
        Linkshell2 = true
    },
    message_ids = {}  -- Table to store unique message IDs
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
    str = AshitaCore:GetChatManager():ParseAutoTranslate(str, true);
    str = str:strip_colors();
    str = str:strip_translate(true);
    while (true) do
        local hasN = str:endswith('\n');
        local hasR = str:endswith('\r');
        if (not hasN and not hasR) then
            break;
        end
        if (hasN) then str = str:trimend('\n'); end
        if (hasR) then str = str:trimend('\r'); end
    end
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
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/lschat')) then
        return;
    end
    e.blocked = true;
    chat.is_open[1] = not chat.is_open[1];
end);

---------------------------
-- Read Incoming Packets --
---------------------------
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if (e.id == 0x017) then
        local msgType = struct.unpack('B', e.data, 0x04 + 1);
        if msgType == 0 or msgType == 12 then
            return;
        end
        if msgType == 26 then
            return;
        end

        local character = struct.unpack('c15', e.data_modified, 0x08 + 1):trimend('\x00');
        local msg = struct.unpack('s', e.data_modified, 0x17 + 0x01);

        msg = string.gsub(msg, "%%", "%%%%");
        msg = clean_str(msg);

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
            color = {0.3, 0.7, 0.3, 1.0}; -- Darker Green
        end

        local timestamp = get_current_time()
        local fullMsg = timestamp .. " " .. character .. ": " .. msg;
        local message_id = fullMsg .. msgType  -- Create a unique ID based on message and type

        if (not chat.message_ids[message_id]) then
            chat.message_ids[message_id] = true
            chat.messages:append({message = fullMsg, color = color, type = chatType});
        end
    end
end);

---------------------------
-- Read Outgoing Packets --
---------------------------
ashita.events.register('packet_out', 'outgoing_packet', function (e)
    if (e.id == 0x0B5) then
        local msgType = struct.unpack('B', e.data, 0x04 + 1);
        if msgType == 0 or msgType == 12 then
            return;
        end
        if msgType == 26 then
            return;
        end

        local msg = struct.unpack('s', e.data_modified, 0x06 + 0x01);

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
            color = {0.3, 0.7, 0.3, 1.0}; -- Darker Green
        end

        local timestamp = get_current_time()
        local fullMsg = timestamp .. " " .. character .. ": " .. msg;
        local message_id = fullMsg .. msgType  -- Create a unique ID based on message and type

        if (not chat.message_ids[message_id]) then
            chat.message_ids[message_id] = true
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
            local filterNames = {"All", "Party", "Tell", "Linkshell1", "Linkshell2"}
            for _, filterName in ipairs(filterNames) do
                local active = chat.filters[filterName]
                local buttonText = (active and filterName) or ('< ' .. filterName .. ' >')
                if imgui.Button(buttonText) then
                    if filterName == "All" then
                        -- When 'All' is clicked, activate all filters
                        for _, name in ipairs(filterNames) do
                            chat.filters[name] = true
                        end
                    else
                        chat.filters[filterName] = not active
                        -- Turn off 'All' if any filter is manually changed
                        chat.filters["All"] = false
                    end
                end
                imgui.SameLine();
            end

            imgui.Separator();
            
            if (imgui.BeginChild('MessagesWindow', {0, -imgui.GetFrameHeightWithSpacing() + 20})) then
                for _, v in ipairs(chat.messages) do
                    if chat.filters[v.type] then
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
