addon.name      = 'xichats';
addon.author    = 'K0D3R, Nils';
addon.version   = '1.9';
addon.desc      = 'Outputs Linkshell, Party, Tell, Say, Yell, Shout, and Emote Chat to a Window';
addon.link      = '';

require('common');
local imgui = require('imgui');

-- Chat Variables
local chat = {
    messages = T{},
    is_open = { true, },
    isolated_windows = {},
    filters = {
        All = true,
        Party = true,
        Tell = true,
        LS1 = true,
        LS2 = true,
        Say = true,
        Yell = true,
        Shout = true,
        Emote = true,
        History = true -- Add History filter
    },
    message_ids = {},
    debug_enabled = false,
    filterStates = { All = 0, Party = 0, Tell = 0, LS1 = 0, LS2 = 0, Say = 0, Yell = 0, Shout = 0, Emote = 0, History = 0 }, -- Initialize filter state for History
    lastMessageTime = os.time(),  -- Track the last message time
    shouldScrollToBottom = true, -- Track if we should scroll to the bottom
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

------------------------------
-- Get Current Time as String --
------------------------------
local function get_current_time()
    local t = os.date('*t')
    return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

--------------------------------
-- Save Chat History to File --
--------------------------------
local function saveChatHistory()
    local file = io.open(addon.path:append('\\chat_history.txt'), 'w');
    if file then
        for _, msg in ipairs(chat.messages) do
            file:write(string.format("%s\n", msg.message));
        end
        file:close();
    end
end

--------------------------------
-- Load Chat History from File --
--------------------------------
local function loadChatHistory()
    local file = io.open(addon.path:append('\\chat_history.txt'), 'r');
    if file then
        for line in file:lines() do
            if line:find('|') then
                local parts = line:split('|');
                local timestamp = parts[1]:trim();
                local msgType = tonumber(parts[2]:trim());
                local character_msg = parts[3]:trim();
                local character, msg = character_msg:match('([^:]+): (.+)');
                local color = {1.0, 1.0, 1.0, 1.0}; -- Default color for historical messages

                -- Assign color based on msgType, similar to the logic in packet_in and outgoing_packet
                if msgType == 4 then color = {0.678, 0.847, 0.902, 1.0}; -- Light Blue (Party)
                elseif msgType == 3 then color = {0.8, 0.6, 0.9, 1.0}; -- Light Purple (Tell)
                elseif msgType == 5 then color = {0.6, 1.0, 0.6, 1.0}; -- Light Green (LS1)
                elseif msgType == 27 then color = {0.3, 0.7, 0.3, 1.0}; -- Dark Green (LS2)
                elseif msgType == 26 then color = {1.0, 0.3, 0.3, 1.0}; -- Lighter Red (Yell)
                elseif msgType == 0 then color = {1.0, 0.6, 0.6, 1.0}; -- Lighter Red (Say)
                elseif msgType == 1 then color = {1.0, 0.5, 0.5, 1.0}; -- Lighter Red (Shout)
                elseif msgType == 8 then color = {1.0, 1.0, 1.0, 1.0}; -- White (Emote)
                elseif msgType == 14 then color = {0.0, 0.0, 0.5, 1.0}; -- Dark Blue (System)
                end

                local chatType = "Unknown";
                -- Determine the chat type based on msgType
                if msgType == 4 then chatType = "Party"; 
                elseif msgType == 3 then chatType = "Tell"; 
                elseif msgType == 5 then chatType = "LS1"; 
                elseif msgType == 27 then chatType = "LS2"; 
                elseif msgType == 26 then chatType = "Yell"; 
                elseif msgType == 0 then chatType = "Say"; 
                elseif msgType == 1 then chatType = "Shout"; 
                elseif msgType == 8 then chatType = "Emote"; 
                elseif msgType == 14 then chatType = "System"; 
                end

                -- Check if the message type is active in the current filter states
                if chat.filterStates[chatType] == 0 then
                    local fullMsg = string.format("%s | %d | %s: %s", timestamp, msgType, character, msg);
                    chat.messages:append({message = fullMsg, color = color, type = chatType, isHistorical = true});
                    chat.message_ids[fullMsg .. msgType] = true; -- Mark this message as seen
                end
            else
                print("Warning: Line skipped due to unexpected format: " .. line)
            end
        end
        file:close();
    end
end

-- Function to add the addon loaded message
local function addAddonLoadedMessage()
    local timestamp = get_current_time()
    local message = string.format("-- Addon Loaded on %s --", timestamp)

    -- Append to chat messages
    chat.messages:append({message = message, color = {1.0, 1.0, 1.0, 1.0}, type = "System"});
    chat.message_ids[message .. 0] = true; -- Mark as seen (msgType 0 for System)
    
    -- Save this message to the chat history file
    saveChatHistory()
end

-- Load chat history when addon initializes and add the loaded message
loadChatHistory()
addAddonLoadedMessage()

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

---------------------------
-- Check for slash commands --
---------------------------
ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/xichats')) then
        return;
    end
    e.blocked = true;

    if args[2] == "debug" then
        chat.debug_enabled = not chat.debug_enabled
        local status = chat.debug_enabled and "enabled" or "disabled"
        AshitaCore:GetChatManager():QueueCommand(1, '/echo Debug output has been ' .. status);
    elseif args[2] == "toggle" then
        chat.is_open[1] = not chat.is_open[1];
    elseif args[2] == "show" then
        chat.is_open[1] = true;
    elseif args[2] == "hide" then
        chat.is_open[1] = false;
    elseif args[2] == "archive" then
        local timestamp = os.date('%Y-%m-%d_%H-%M-%S')
        local current_log_path = addon.path:append('\\chat_history.txt')
        local archived_log_path = addon.path:append('\\chatlog-' .. timestamp .. '.txt')

        -- Rename current log file with timestamp
        os.rename(current_log_path, archived_log_path)

        -- Create a new chat history file
        local new_log_file = io.open(current_log_path, 'w')
        if new_log_file then
            new_log_file:close()
            chat.messages:clear() -- Clear chat messages after archiving
            addAddonLoadedMessage() -- Add message that addon loaded to new log file
            AshitaCore:GetChatManager():QueueCommand(1, '/echo Chat log archived successfully.')
        else
            AshitaCore:GetChatManager():QueueCommand(1, '/echo Error archiving chat log.')
        end
    end
end);

---------------------------
-- Read Incoming Packets --
---------------------------
ashita.events.register('packet_in', 'packet_in_cb', function (e)
    if (e.id == 0x017) then
        local msgType = struct.unpack('B', e.data, 0x04 + 1);

        local character = struct.unpack('c15', e.data_modified, 0x08 + 1):trimend('\x00');
        local msg = struct.unpack('s', e.data_modified, 0x17 + 0x01);

        msg = string.gsub(msg, "%%", "%%%%");
        msg = clean_str(msg);

        if chat.debug_enabled then
            AshitaCore:GetChatManager():QueueCommand(1, '/echo [DEBUG] MsgType: ' .. msgType .. ', Character: ' .. character .. ', Message: ' .. msg);
        end

        local chatType = "Unknown";
        local color = {1.0, 1.0, 1.0, 1.0}; -- Default color is White

        -- Assign chat types and colors based on msgType
        if msgType == 4 then
            chatType = "Party";
            color = {0.678, 0.847, 0.902, 1.0}; -- Light Blue
        elseif msgType == 3 then
            chatType = "Tell";
            color = {0.8, 0.6, 0.9, 1.0}; -- Light Purple
        elseif msgType == 5 then
            chatType = "LS1"; 
            color = {0.6, 1.0, 0.6, 1.0}; -- Light Green
        elseif msgType == 27 then
            chatType = "LS2"; 
            color = {0.3, 0.7, 0.3, 1.0}; -- Dark Green
        elseif msgType == 26 then
            chatType = "Yell";
            color = {1.0, 0.3, 0.3, 1.0}; -- Lighter Red for Yell
        elseif msgType == 0 or msgType == 6 or msgType == 7 or msgType == 9 or msgType == 10 or msgType == 11 or msgType == 12 then
            chatType = "Say";
            color = {1.0, 0.6, 0.6, 1.0}; -- Lighter Red for Say
        elseif msgType == 1 then
            chatType = "Shout";
            color = {1.0, 0.5, 0.5, 1.0}; -- Lighter Red for Shout
        elseif msgType == 8 then
            chatType = "Emote";
            color = {1.0, 1.0, 1.0, 1.0}; -- White
        elseif msgType == 14 then
            chatType = "System";
            color = {0.0, 0.0, 0.5, 1.0}; -- Dark Blue
        else
            chatType = "Other"; -- For any other message types
        end

        local timestamp = get_current_time()
        local fullMsg = string.format("%s | %d | %s: %s", timestamp, msgType, character, msg);
        local message_id = fullMsg .. msgType;  -- Create a unique ID based on message and type

        if (not chat.message_ids[message_id]) then
            chat.message_ids[message_id] = true
            chat.messages:append({message = fullMsg, color = color, type = chatType, isHistorical = false}); -- Mark new messages as not historical
            chat.lastMessageTime = os.time();  -- Update last message time
            
            -- Save chat history whenever a new message is added
            saveChatHistory()
            chat.shouldScrollToBottom = true -- Set to scroll to bottom on new messages
        end
    end
end);

---------------------------
-- Read Outgoing Packets --
---------------------------
ashita.events.register('packet_out', 'outgoing_packet', function (e)
    if (e.id == 0x0B5) then
        local msgType = struct.unpack('B', e.data, 0x04 + 1);

        local msg = struct.unpack('s', e.data_modified, 0x06 + 0x01);

        msg = string.gsub(msg, "%%", "%%%%");
        msg = clean_str(msg);

        local character = AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) or 'Unknown';
        local chatType = "Unknown";
        local color = {1.0, 1.0, 1.0, 1.0}; -- Default color is White

        if msgType == 4 then
            chatType = "Party";
            color = {0.678, 0.847, 0.902, 1.0}; -- Light Blue
        elseif msgType == 3 then
            chatType = "Tell";
            color = {0.8, 0.6, 0.9, 1.0}; -- Light Purple
        elseif msgType == 5 then
            chatType = "LS1"; 
            color = {0.6, 1.0, 0.6, 1.0}; -- Light Green
        elseif msgType == 27 then
            chatType = "LS2"; 
            color = {0.3, 0.7, 0.3, 1.0}; -- Dark Green
        elseif msgType == 26 then
            chatType = "Yell";
            color = {1.0, 0.3, 0.3, 1.0}; -- Lighter Red for Yell
        elseif msgType == 0 then
            chatType = "Say";
            color = {1.0, 1.0, 1.0, 1.0}; -- Lighter Red for Say
        elseif msgType == 1 then
            chatType = "Shout";
            color = {1.0, 0.5, 0.5, 1.0}; -- Lighter Red for Shout
        elseif msgType == 8 then
            chatType = "Emote";
            color = {1.0, 0.6, 0.6, 1.0}; -- White
        elseif msgType == 14 or msgType == 29 then
            chatType = "System";
            color = {0.0, 0.0, 0.8, 1.0}; -- Dark Blue
        else
            chatType = "Other"; -- For any other message types
        end

        local timestamp = get_current_time()
        local fullMsg = string.format("%s | %d | %s: %s", timestamp, msgType, character, msg);
        local message_id = fullMsg .. msgType;  -- Create a unique ID based on message and type

        if chat.debug_enabled then
            AshitaCore:GetChatManager():QueueCommand(1, '/echo [DEBUG] Outgoing MsgType: ' .. msgType .. ', Character: ' .. character .. ', Message: ' .. msg);
        end

        if (not chat.message_ids[message_id]) then
            chat.message_ids[message_id] = true
            chat.messages:append({message = fullMsg, color = color, type = chatType, isHistorical = false}); -- Mark new messages as not historical
            chat.lastMessageTime = os.time();  -- Update last message time
            
            -- Save chat history whenever a new message is added
            saveChatHistory()
            chat.shouldScrollToBottom = true -- Set to scroll to bottom on new messages
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
            -- First and second row filter definitions
            local firstRowFilters = {"All", "Tell", "Party", "LS1", "LS2"}
            local secondRowFilters = {"Say", "Yell", "Shout", "Emote", "History"} -- Move History to the end of the second row
            local buttonSize = {100, 23}

            -- Function to toggle filter states
            local function toggleAllFilters()
                local allFilters = { "Tell", "Party", "LS1", "LS2", "Say", "Yell", "Shout", "Emote" }
                -- Toggle all filter states
                for _, name in ipairs(allFilters) do
                    chat.filterStates[name] = (chat.filterStates[name] + 1) % 2  -- Toggle between 0 and 1
                end
            end

            -- Create the first row of buttons
            for _, filterName in ipairs(firstRowFilters) do
                local state = chat.filterStates[filterName] or 0
                local buttonText = state == 0 and filterName or '< ' .. filterName .. '>'

                if imgui.Button(buttonText, buttonSize) then
                    if imgui.IsKeyPressed(0x10) then
                        -- Open/close isolated windows
                        chat.isolated_windows[filterName] = chat.isolated_windows[filterName] or { is_open = true, messages = T{} }
                        chat.isolated_windows[filterName].is_open = not chat.isolated_windows[filterName].is_open
                    else
                        if filterName == "All" then
                            toggleAllFilters()  -- Toggle all filters for both rows
                        else
                            chat.filterStates[filterName] = (state + 1) % 2  -- Toggle the specific filter
                        end
                        chat.shouldScrollToBottom = true -- Set to scroll to bottom when any button is pressed
                    end
                end
                imgui.SameLine()
            end

            imgui.NewLine()  -- Move to the next row

            -- Create the second row of buttons
            for _, filterName in ipairs(secondRowFilters) do
                local state = chat.filterStates[filterName] or 0
                local buttonText = state == 0 and filterName or '< ' .. filterName .. '>'

                if imgui.Button(buttonText, buttonSize) then
                    if imgui.IsKeyPressed(0x10) then
                        chat.isolated_windows[filterName] = chat.isolated_windows[filterName] or { is_open = true, messages = T{} }
                        chat.isolated_windows[filterName].is_open = not chat.isolated_windows[filterName].is_open
                    else
                        chat.filterStates[filterName] = (state + 1) % 2  -- Toggle the specific filter
                        chat.shouldScrollToBottom = true -- Set to scroll to bottom when any button is pressed
                    end
                end
                imgui.SameLine()
            end

            imgui.Separator()

            -- Display chat messages
            if (imgui.BeginChild('MessagesWindow', {0, -imgui.GetFrameHeightWithSpacing() + 20})) then
                for _, v in ipairs(chat.messages) do
                    local filterState = chat.filterStates[v.type] or 0
                    local historyFilterState = chat.filterStates["History"] or 0

                    -- Display the message if it is not historical or if the History filter is off
                    if filterState == 0 and (historyFilterState == 0 or not v.isHistorical) then
                        local color = v.color or {1.0, 1.0, 1.0, 1.0}
                        imgui.PushStyleColor(0, color)
                        imgui.TextWrapped(v.message)
                        imgui.PopStyleColor()
                    end
                end
                if chat.shouldScrollToBottom then
                    imgui.SetScrollHereY(1.0)  -- Scroll to the bottom if shouldScrollToBottom is true
                end
            end
            imgui.EndChild()
        end
        imgui.End()
    end

    -- Display isolated windows
    for filterName, window in pairs(chat.isolated_windows) do
        if window.is_open then
            imgui.SetNextWindowSize({300, 300}, ImGuiCond_FirstUseEver)
            if imgui.Begin(filterName .. ' Chat Window', window.is_open) then
                for _, v in ipairs(chat.messages) do
                    if v.type == filterName then
                        imgui.Text(v.message)
                    end
                end
                imgui.End()
            end
        end
    end
end)

-- Scroll behavior based on scrollbar interaction
ashita.events.register('d3d_scroll', 'scroll_cb', function ()
    chat.shouldScrollToBottom = false -- Disable scrolling to bottom while user is interacting with the scrollbar
end)
