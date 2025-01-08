addon.name      = 'xichats';
addon.author    = 'K0D3R, Nils';
addon.version   = '2.0';
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
        History = true
    },
    message_ids = {},
    debug_enabled = false,
    filterStates = { All = 0, Party = 0, Tell = 0, LS1 = 0, LS2 = 0, Say = 0, Yell = 0, Shout = 0, Emote = 0, History = 0 },
    lastMessageTime = os.time(),
    shouldScrollToBottom = true, -- Track if we should scroll to the bottom
};

-- User Interaction Variables
local lastScrollInteractionTime = os.time()
local isUserScrolling = false  -- Track if the user is actively scrolling

-- Add new variables for the input buffers
local usernameBuffer = {''}
local colorBuffer = {''}

-- Table to store the usernames and colors
local userColors = {}

-- Add new variable for search query
local searchQuery = {''}

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

------------------------------
-- Get Current Date and Time as String (MM/DD/YY | HH:MM:SS) --
------------------------------
local function get_current_time()
    local t = os.date('*t')
    -- Updated format to include | between date and time
    return string.format("%02d/%02d/%02d | %02d:%02d:%02d", t.month, t.day, t.year % 100, t.hour, t.min, t.sec)
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
    local file = io.open(addon.path:append('\\chat_history.txt'), 'r')
    if file then
        for line in file:lines() do
            -- Check if line is valid and contains at least three pipe symbols ('|')
            if line and line:find('|') then
                local parts = {}
                for part in line:gmatch("[^|]+") do
                    table.insert(parts, part:trim())  -- Split and trim each part
                end

                -- Check if we have exactly 4 parts (Date, Time, msgType, Message)
                if #parts == 4 then
                    local timestamp_date = parts[1]  -- Date
                    local timestamp_time = parts[2]  -- Time
                    local msgType = tonumber(parts[3])  -- Message type
                    local character_msg = parts[4]  -- Character and message

                    -- Use pattern matching to extract character and message
                    local character, msg = character_msg:match('([^:]+): (.+)')

                    -- Default color for historical messages
                    local color = {1.0, 1.0, 1.0, 1.0}

                    -- Assign color based on msgType
                    if msgType == 4 then color = {0.678, 0.847, 0.902, 1.0} -- Light Blue (Party)
                    elseif msgType == 3 then color = {0.8, 0.6, 0.9, 1.0} -- Light Purple (Tell)
                    elseif msgType == 5 then color = {0.6, 1.0, 0.6, 1.0} -- Light Green (LS1)
                    elseif msgType == 27 then color = {0.3, 0.7, 0.3, 1.0} -- Dark Green (LS2)
                    elseif msgType == 26 then color = {1.0, 0.3, 0.3, 1.0} -- Lighter Red (Yell)
                    elseif msgType == 0 then color = {1.0, 0.6, 0.6, 1.0} -- Lighter Red (Say)
                    elseif msgType == 1 then color = {1.0, 0.5, 0.5, 1.0} -- Lighter Red (Shout)
                    elseif msgType == 8 then color = {1.0, 1.0, 1.0, 1.0} -- White (Emote)
                    elseif msgType == 14 then color = {0.0, 0.0, 0.5, 1.0} -- Dark Blue (System)
                    end

                    -- Determine the chat type based on msgType
                    local chatType = "Unknown"
                    if msgType == 4 then chatType = "Party"
                    elseif msgType == 3 then chatType = "Tell"
                    elseif msgType == 5 then chatType = "LS1"
                    elseif msgType == 27 then chatType = "LS2"
                    elseif msgType == 26 then chatType = "Yell"
                    elseif msgType == 0 then chatType = "Say"
                    elseif msgType == 1 then chatType = "Shout"
                    elseif msgType == 8 then chatType = "Emote"
                    elseif msgType == 14 then chatType = "System"
                    end

                    -- Check if the message type is active in the current filter states
                    if chat.filterStates[chatType] == 0 then
                        -- Format the full message with timestamp, msgType, character, and message
                        local fullMsg = string.format("%s | %s | %d | %s: %s", timestamp_date, timestamp_time, msgType, character, msg)
                        chat.messages:append({message = fullMsg, color = color, type = chatType, isHistorical = true})
                        chat.message_ids[fullMsg .. msgType] = true -- Mark this message as seen
                    end
                else
                    print("Warning: Line skipped due to unexpected format (should have 4 parts): " .. line)
                end
            else
                print("Warning: Line skipped due to missing or invalid separator ('|'): " .. line)
            end
        end
        file:close()
    end
end

--------------------
-- Addon Loaded Message --
--------------------
local function addAddonLoadedMessage()
    local timestamp = get_current_time()  -- Get the current timestamp
    local date, time = timestamp:match("(%d+/%d+/%d+) | (%d+:%d+:%d+)")  -- Split timestamp into date and time
    local msgType = 100  -- Custom message type for "Addon Loaded"
    local message = "Addon Loaded"  -- The message text

    -- Create the full message in the desired format
    local fullMessage = string.format("%s | %s | %d | %s", date, time, msgType, message)

    -- Append to chat messages
    chat.messages:append({message = fullMessage, color = {1.0, 1.0, 1.0, 1.0}, type = "System", isHistorical = true})
    chat.message_ids[fullMessage .. msgType] = true  -- Mark as seen (msgType 100 for System)

    -- Save this message to the chat history file
    saveChatHistory()  -- Save the chat history with the new addon loaded message
end

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

    -- Debug toggle
    if args[2] == "debug" then
        chat.debug_enabled = not chat.debug_enabled
        local status = chat.debug_enabled and "enabled" or "disabled"
        AshitaCore:GetChatManager():QueueCommand(1, '/echo Debug output has been ' .. status);

    -- Toggle main chat window
    elseif args[2] == "toggle" then
        chat.is_open[1] = not chat.is_open[1];

    -- Show/hide main chat window
    elseif args[2] == "show" then
        chat.is_open[1] = true;
    elseif args[2] == "hide" then
        chat.is_open[1] = false;

    -- Archive chat history
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

    -- Handle isolated window commands
    elseif args[2] == "p" then
        -- Toggle isolated window for Party chat
        chat.isolated_windows["Party"] = chat.isolated_windows["Party"] or { is_open = true, messages = T{} }
        chat.isolated_windows["Party"].is_open = not chat.isolated_windows["Party"].is_open

    elseif args[2] == "l" then
        -- Toggle isolated window for Linkshell 1 chat
        chat.isolated_windows["LS1"] = chat.isolated_windows["LS1"] or { is_open = true, messages = T{} }
        chat.isolated_windows["LS1"].is_open = not chat.isolated_windows["LS1"].is_open

    elseif args[2] == "ls2" then
        -- Toggle isolated window for Linkshell 2 chat
        chat.isolated_windows["LS2"] = chat.isolated_windows["LS2"] or { is_open = true, messages = T{} }
        chat.isolated_windows["LS2"].is_open = not chat.isolated_windows["LS2"].is_open

    -- Toggle visibility of the date in chat messages
    elseif args[2] == "details" then  -- Changed from 'dates' to 'details'
        showDate = not showDate
        local status = showDate and "enabled" or "disabled"
        AshitaCore:GetChatManager():QueueCommand(1, '/echo Date visibility has been ' .. status);
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
            AshitaCore:GetChatManager():QueueCommand(1, '/echo [DEBUG] msgType: ' .. msgType .. ', Character: ' .. character .. ', Message: ' .. msg);
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
            if not isUserScrolling then
                chat.shouldScrollToBottom = true -- Set to scroll to bottom on new messages if not scrolling
            end
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
        end

        local timestamp = get_current_time()
        local fullMsg = string.format("%s | %d | %s: %s", timestamp, msgType, character, msg);
        local message_id = fullMsg .. msgType;  -- Create a unique ID based on message and type

        if chat.debug_enabled then
            AshitaCore:GetChatManager():QueueCommand(1, '/echo [DEBUG] Outgoing msgType: ' .. msgType .. ', Character: ' .. character .. ', Message: ' .. msg);
        end

        if (not chat.message_ids[message_id]) then
            chat.message_ids[message_id] = true
            chat.messages:append({message = fullMsg, color = color, type = chatType, isHistorical = false}); -- Mark new messages as not historical
            chat.lastMessageTime = os.time();  -- Update last message time
            
            -- Save chat history whenever a new message is added
            saveChatHistory()
            if not isUserScrolling then
                chat.shouldScrollToBottom = true -- Set to scroll to bottom on new messages if not scrolling
            end
        end
    end    
end);

---------------------------
-- Form Design --
---------------------------
ashita.events.register('d3d_present', 'present_cb', function ()
    if (chat.is_open[1]) then
        imgui.SetNextWindowSize({ 400, 400, }, ImGuiCond_FirstUseEver);
        if (imgui.Begin('Chat Window', chat.is_open)) then
            -- Create Search Bar for entering search query
            imgui.Text('Search:');
            imgui.SameLine();
            imgui.InputText('##search', searchQuery, 100);

            -- Create the "Enable/Disable Auto-Scroll" button to the right of the search field
            imgui.SameLine()
            if imgui.Button(chat.shouldScrollToBottom and "Scroll: On" or "Scroll: Off", {120, 23}) then
                chat.shouldScrollToBottom = not chat.shouldScrollToBottom
            end

            -- First and second row filter definitions
            local firstRowFilters = {"All", "Tell", "Party", "LS1", "LS2"}
            local secondRowFilters = {"Say", "Yell", "Shout", "Emote", "History"}
            local buttonSize = {100, 23}

            -- Function to toggle filter states
            local function toggleAllFilters()
                local allFilters = { "Tell", "Party", "LS1", "LS2", "Say", "Yell", "Shout", "Emote" }
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

            -- Display chat messages in the main window
            if (imgui.BeginChild('MessagesWindow', {0, -imgui.GetFrameHeightWithSpacing() + 20})) then
                for _, v in ipairs(chat.messages) do
                    local filterState = chat.filterStates[v.type] or 0
                    local historyFilterState = chat.filterStates["History"] or 0

                    -- Escape special characters in the search query (like "-")
                    local sanitizedSearchQuery = searchQuery[1]:gsub("([%-\\^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
                    -- If search query is provided, filter messages by the search query (case insensitive)
                    local matchesSearch = sanitizedSearchQuery == '' or v.message:lower():find(sanitizedSearchQuery:lower()) ~= nil

                    -- Display the message if it matches the search filter and is not historical, or History filter is off
                    if filterState == 0 and (historyFilterState == 0 or not v.isHistorical) and matchesSearch then
                        local color = v.color or {1.0, 1.0, 1.0, 1.0}
                        local messageText = v.message

                        -- If the date is hidden, format without the date part
                        if not showDate then
                            -- Extract time, msgType, and message without the date
                            local time, msgType, msg = messageText:match("([^|]+) | (%d+) | (.+)")
                            -- Format without the date
                            messageText = string.format("%s | %s", time, msg)
                        end

                        imgui.PushStyleColor(0, color)
                        imgui.TextWrapped(messageText)  -- Ensure text wraps
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

    -- Display isolated windows with proper colors and auto-scrolling
    for filterName, window in pairs(chat.isolated_windows) do
        if window.is_open then
            imgui.SetNextWindowSize({300, 300}, ImGuiCond_FirstUseEver)
            local is_open, _ = imgui.Begin(filterName .. ' Chat Window', window.is_open)

            -- Don't set is_open to false immediately; this prevents it from closing too quickly
            -- Add the logic here to manage the window's open/close state
            if not is_open then
                window.is_open = false  -- Close the window if "X" is clicked
            end

            -- Add Close Button inside the isolated window
            if imgui.Button("Close") then
                window.is_open = false  -- Close the isolated window
            end
            imgui.SameLine()

            -- Display messages specific to the isolated window filter type
            for _, v in ipairs(chat.messages) do
                if v.type == filterName then
                    local matchesSearch = searchQuery[1] == '' or v.message:lower():find(sanitizedSearchQuery:lower()) ~= nil
                    if matchesSearch then
                        local color = v.color or {1.0, 1.0, 1.0, 1.0}
                        imgui.PushStyleColor(0, color)
                        imgui.TextWrapped(v.message)  -- Ensure text wraps
                        imgui.PopStyleColor()
                    end
                end
            end

            -- Auto-scroll to the bottom unless the user is manually scrolling
            if chat.shouldScrollToBottom then
                imgui.SetScrollHereY(1.0)  -- Scroll to the bottom of the window
            end

            imgui.End()
        end
    end
end)

-- Load chat history when addon initializes and add the loaded message
loadChatHistory()
addAddonLoadedMessage()

-- Call the function to load User Colors
loadUserColors()