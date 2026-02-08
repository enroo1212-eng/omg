-- ==========================================
-- CELESTIAL TIMER + SMART SERVER HOP + WEBHOOK
-- ==========================================

-- 🔧 CONFIG
-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua"
local MAX_SERVER_SEARCHES = math.huge -- unlimited searches
local PLACE_ID = 131623223084840
local MIN_PLAYERS = 1 -- minimum players to consider a server
local MAX_PLAYERS = 6 -- maximum players for "lowest possible server"
local RETRY_DELAY = 18 -- seconds to wait before retrying
local SERVER_LIMIT = 100 -- back to 100 since rate limits apply regardless
local RATE_LIMIT_WAIT = 60 -- wait 60 seconds if we get 429 error

-- ==========================================
-- SERVICES
-- ==========================================
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer

-- ==========================================
-- GLOBAL STATE
-- ==========================================
getgenv().VisitedServers = getgenv().VisitedServers or {}
getgenv().CelestialTimer = getgenv().CelestialTimer or nil
getgenv().FailedAttempts = getgenv().FailedAttempts or 0
getgenv().BestTimerFound = getgenv().BestTimerFound or nil
getgenv().BestTimerJobId = getgenv().BestTimerJobId or nil
getgenv().VisitedServers[game.JobId] = true

-- ==========================================
-- SERVER CACHE SYSTEM (STORED IN WORKSPACE)
-- ==========================================
local CACHE_DURATION = 180 -- 3 minutes in seconds
local ServerCacheFolder = workspace:FindFirstChild("ServerCache") or Instance.new("Folder")
ServerCacheFolder.Name = "ServerCache"
ServerCacheFolder.Parent = workspace

-- Function to save servers to workspace
local function saveServersToCache(servers)
    debugPrint(string.format("💾 Saving %d servers to workspace cache...", #servers))
    
    -- Clear old cache
    ServerCacheFolder:ClearAllChildren()
    
    -- Create timestamp file
    local timestampValue = Instance.new("NumberValue")
    timestampValue.Name = "CacheTimestamp"
    timestampValue.Value = tick()
    timestampValue.Parent = ServerCacheFolder
    
    -- Create delete time indicator
    local deleteTime = Instance.new("StringValue")
    deleteTime.Name = "DeleteAt"
    deleteTime.Value = os.date("%H:%M:%S", tick() + CACHE_DURATION)
    deleteTime.Parent = ServerCacheFolder
    
    -- Save each server as a StringValue
    for i, server in ipairs(servers) do
        local serverValue = Instance.new("StringValue")
        serverValue.Name = "Server_"..i
        serverValue.Value = HttpService:JSONEncode(server)
        serverValue.Parent = ServerCacheFolder
    end
    
    debugPrint(string.format("✅ Cache saved at %s (will delete at %s)", 
        os.date("%H:%M:%S", timestampValue.Value),
        deleteTime.Value
    ))
end

-- Function to load servers from workspace cache
local function loadServersFromCache()
    local timestampValue = ServerCacheFolder:FindFirstChild("CacheTimestamp")
    
    if not timestampValue then
        debugPrint("❌ No cache timestamp found")
        return nil
    end
    
    local cacheAge = tick() - timestampValue.Value
    local deleteIn = CACHE_DURATION - cacheAge
    
    debugPrint(string.format("📂 Cache found from %s (%.0fs ago)", 
        os.date("%H:%M:%S", timestampValue.Value), 
        cacheAge
    ))
    
    if cacheAge > CACHE_DURATION then
        debugPrint(string.format("🗑️ Cache expired (%.0fs old, max %ds). Deleting...", cacheAge, CACHE_DURATION))
        ServerCacheFolder:ClearAllChildren()
        return nil
    end
    
    debugPrint(string.format("⏱️ Cache valid. Auto-delete in %.0fs (at %s)", 
        deleteIn,
        os.date("%H:%M:%S", timestampValue.Value + CACHE_DURATION)
    ))
    
    -- Load servers from cache
    local servers = {}
    for _, child in ipairs(ServerCacheFolder:GetChildren()) do
        if child:IsA("StringValue") and child.Name:match("^Server_") then
            local success, server = pcall(function()
                return HttpService:JSONDecode(child.Value)
            end)
            if success and server then
                table.insert(servers, server)
            end
        end
    end
    
    debugPrint(string.format("✅ Loaded %d servers from cache", #servers))
    return servers
end

-- Function to clear cache
local function clearCache()
    debugPrint("🗑️ Clearing server cache...")
    ServerCacheFolder:ClearAllChildren()
end

-- ==========================================
-- DEBUG
-- ==========================================
local function debugPrint(msg)
    print("[CelestialFinder] "..msg)
end

debugPrint("Script started on JobId: "..game.JobId)

-- ==========================================
-- SELF QUEUE
-- ==========================================
local function queueSelf()
    local success = false
    
    if queue_on_teleport then
        pcall(function()
            queue_on_teleport(game:HttpGet(SCRIPT_RAW_URL))
            success = true
        end)
        if success then debugPrint("Queued self with queue_on_teleport") end
    end
    
    if not success and syn and syn.queue_on_teleport then
        pcall(function()
            syn.queue_on_teleport(game:HttpGet(SCRIPT_RAW_URL))
            success = true
        end)
        if success then debugPrint("Queued self with syn.queue_on_teleport") end
    end
    
    if not success then
        debugPrint("Warning: queue_on_teleport not supported - script may not persist")
    end
end

queueSelf()

-- ==========================================
-- UTILITIES
-- ==========================================
local function parseTime(text)
    -- Handle both MM:SS and M:SS formats
    local m, s = text:match("(%d+):(%d+)")
    if not m or not s then return nil end
    return tonumber(m) * 60 + tonumber(s)
end

local function getJoinLink(jobId)
    -- Create a proper game join link
    return string.format("https://www.roblox.com/games/%d?privateServerLinkCode=%s", PLACE_ID, jobId)
end

-- Test function to verify webhook works
local function testWebhook()
    debugPrint("🧪 Testing webhook connection...")
    
    local testPayload = {
        content = "✅ **Webhook Test Successful!**",
        embeds = {{
            title = "🔧 Connection Test",
            description = "If you see this message, your webhook is working correctly!",
            color = 65280, -- Green
            fields = {
                {
                    name = "Status",
                    value = "Connected ✅",
                    inline = true
                }
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
        }}
    }
    
    local requestFunc = request or http_request or (syn and syn.request)
    
    if requestFunc then
        local success, result = pcall(function()
            return requestFunc({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(testPayload)
            })
        end)
        
        if success then
            debugPrint("✅ Test webhook sent! Check your Discord channel.")
            if result and result.StatusCode then
                debugPrint("Status Code: "..result.StatusCode)
            end
        else
            debugPrint("❌ Test webhook failed: "..(result or "unknown"))
        end
    else
        debugPrint("❌ No request function available")
    end
end

-- Uncomment the line below to test webhook before running main script
-- testWebhook()

local function sendWebhook(eventTime, jobId)
    debugPrint("Attempting to send webhook with timer: "..eventTime.."s left")
    
    local timeStr = string.format("%02d:%02d", math.floor(eventTime/60), eventTime%60)
    local deepLink = string.format("roblox://placeId=%d&gameInstanceId=%s", PLACE_ID, jobId)
    local webLink = string.format("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s", PLACE_ID, jobId)
    
    -- Payload with clickable web link
    local payload = {
        content = "🔔 **Celestial Timer Found!**",
        embeds = {{
            title = "⏰ Celestial Event Timer",
            description = string.format(
                "**Time Remaining:** `%s`\n\n**🎮 [CLICK HERE TO JOIN SERVER](%s)**\n\n**Or copy this:**\n```%s```\n\n**Server ID:** `%s`", 
                timeStr,
                webLink,
                deepLink,
                jobId:sub(1, 16).."..."
            ),
            color = 9055471,
            fields = {
                {
                    name = "📊 Server Stats",
                    value = string.format("• Players: %d\n• Ping: Active\n• Server: %s", 
                        #Players:GetPlayers(), 
                        game.JobId:sub(1, 8).."..."
                    ),
                    inline = true
                },
                {
                    name = "⏱️ Timer Info",
                    value = string.format("• Minutes: %d\n• Seconds: %d", 
                        math.floor(eventTime/60), 
                        eventTime%60
                    ),
                    inline = true
                }
            },
            footer = { 
                text = "Celestial Timer Finder • Click the blue link to join instantly"
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
        }}
    }

    local jsonPayload = HttpService:JSONEncode(payload)
    debugPrint("JSON Payload: "..jsonPayload:sub(1, 200).."...")

    -- Try multiple request methods
    local requestFunc = nil
    local requestName = "unknown"
    
    if request then
        requestFunc = request
        requestName = "request"
    elseif http_request then
        requestFunc = http_request
        requestName = "http_request"
    elseif syn and syn.request then
        requestFunc = syn.request
        requestName = "syn.request"
    end
    
    debugPrint("Using request function: "..requestName)
    
    if requestFunc then
        local success, result = pcall(function()
            return requestFunc({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = { 
                    ["Content-Type"] = "application/json"
                },
                Body = jsonPayload
            })
        end)
        
        if success then
            debugPrint("✅ Webhook sent successfully!")
            if result then
                debugPrint("Response: "..tostring(result.StatusCode or "No status code"))
                if result.Body then
                    debugPrint("Body: "..result.Body:sub(1, 100))
                end
            end
        else
            debugPrint("❌ Webhook request failed: "..(result or "unknown error"))
        end
    else
        debugPrint("❌ No HTTP request function available!")
        debugPrint("Make sure your executor supports: request, http_request, or syn.request")
    end
end

-- ==========================================
-- GET CELESTIAL TIMER
-- ==========================================
local function getCelestialTimer()
    local EventTimers = workspace:FindFirstChild("EventTimers")
    if not EventTimers then
        debugPrint("No EventTimers folder found.")
        return nil
    end

    debugPrint("EventTimers folder found, checking children...")
    
    for _, obj in ipairs(EventTimers:GetChildren()) do
        debugPrint("Checking object: "..obj.Name)
        local gui = obj:FindFirstChild("SurfaceGui")
        local frame = gui and gui:FindFirstChild("Frame")
        if frame then
            debugPrint("Found Frame, checking TextLabels...")
            for _, label in ipairs(frame:GetChildren()) do
                if label:IsA("TextLabel") then
                    local text = label.Text
                    debugPrint("TextLabel found with text: '"..text.."'")
                    
                    if text:match("CELESTIAL") then
                        debugPrint("⭐ Found CELESTIAL label!")
                        
                        -- Remove any HTML/rich text tags
                        local cleanText = text:gsub("<[^>]+>", "")
                        debugPrint("Cleaned text: '"..cleanText.."'")
                        
                        -- Try to find time pattern MM:SS
                        local timeStr = cleanText:match("(%d+):(%d+)")
                        if timeStr then
                            debugPrint("Time string extracted: '"..timeStr.."'")
                            
                            local seconds = parseTime(timeStr)
                            if seconds then
                                debugPrint(string.format("✅ Parsed time successfully: %s = %d seconds = %d:%02d", 
                                    timeStr, 
                                    seconds,
                                    math.floor(seconds/60),
                                    seconds%60
                                ))
                                return seconds
                            else
                                debugPrint("❌ parseTime returned nil for: '"..timeStr.."'")
                            end
                        else
                            debugPrint("⚠️ Found CELESTIAL label but no time pattern in: '"..cleanText.."'")
                        end
                    end
                end
            end
        end
    end

    debugPrint("No celestial timer found in this server.")
    return nil
end

-- ==========================================
-- SMART SERVER HOPPER WITH WORKSPACE CACHING
-- ==========================================
local function hopServer()
    debugPrint("Searching for lowest population servers (unlimited attempts)...")
    local attempts = 0
    local lastRequestTime = 0
    local REQUEST_DELAY = 3 -- increased delay between requests

    while true do -- infinite loop for unlimited searches
        attempts = attempts + 1
        debugPrint(string.format("========== Search attempt #%d ==========", attempts))
        
        local serverList = {}
        local needsRefetch = false
        
        -- Try to load from workspace cache first
        local cachedServers = loadServersFromCache()
        
        if cachedServers and #cachedServers > 0 then
            debugPrint(string.format("Using cached server list (%d servers)", #cachedServers))
            serverList = cachedServers
        else
            debugPrint("No valid cache found. Fetching fresh server list from API...")
            needsRefetch = true
        end
        
        -- Fetch new server list if needed
        if needsRefetch then
            local cursor = nil
            local pageNumber = 0
            local totalFetched = 0
            local maxPages = 10 -- limit pages to avoid too many requests
            local freshServers = {}
            
            repeat
                pageNumber = pageNumber + 1
                
                if pageNumber > maxPages then
                    debugPrint(string.format("Reached max pages (%d), stopping fetch", maxPages))
                    break
                end
                
                debugPrint(string.format("📡 Fetching page %d (limit: %d servers per page)", pageNumber, SERVER_LIMIT))
                
                -- Rate limiting protection
                local timeSinceLastRequest = tick() - lastRequestTime
                if timeSinceLastRequest < REQUEST_DELAY then
                    local waitTime = REQUEST_DELAY - timeSinceLastRequest
                    debugPrint(string.format("⏳ Rate limit protection: waiting %.1fs", waitTime))
                    task.wait(waitTime)
                end
                
                lastRequestTime = tick()

                local url = string.format(
                    "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=%d%s",
                    PLACE_ID,
                    SERVER_LIMIT,
                    cursor and "&cursor="..cursor or ""
                )

                local success, response = pcall(function()
                    return game:HttpGet(url)
                end)

                if not success then
                    local errorMsg = tostring(response)
                    debugPrint("❌ API request failed: "..errorMsg)
                    
                    -- Check for 429 rate limit error
                    if errorMsg:match("429") or errorMsg:match("Too Many Requests") then
                        debugPrint(string.format("⚠️ RATE LIMITED (429)! Waiting %d seconds...", RATE_LIMIT_WAIT))
                        task.wait(RATE_LIMIT_WAIT)
                        break -- Break out to retry from beginning
                    else
                        debugPrint(string.format("Waiting %ds before retry...", RETRY_DELAY))
                        task.wait(RETRY_DELAY)
                        break
                    end
                end

                local data = nil
                local parseSuccess = pcall(function()
                    data = HttpService:JSONDecode(response)
                end)

                if not parseSuccess or not data then
                    debugPrint("❌ Failed to parse JSON response")
                    debugPrint(string.format("Waiting %ds before retry...", RETRY_DELAY))
                    task.wait(RETRY_DELAY)
                    break
                end

                if not data.data then
                    debugPrint("❌ Invalid response structure (no 'data' field)")
                    debugPrint(string.format("Waiting %ds before retry...", RETRY_DELAY))
                    task.wait(RETRY_DELAY)
                    break
                end

                debugPrint(string.format("✅ Page %d loaded: %d servers found", pageNumber, #data.data))
                
                -- Add servers to fresh list
                for _, server in ipairs(data.data) do
                    table.insert(freshServers, server)
                    totalFetched = totalFetched + 1
                end

                cursor = data.nextPageCursor
                
                if cursor then
                    debugPrint(string.format("➡️ nextPageCursor found, will fetch page %d...", pageNumber + 1))
                    task.wait(1) -- Wait between pagination requests
                else
                    debugPrint("🏁 No nextPageCursor - reached end of server list")
                end
                
            until not cursor
            
            if totalFetched > 0 then
                debugPrint(string.format("✅ Fetched %d servers total from API", totalFetched))
                saveServersToCache(freshServers)
                serverList = freshServers
            else
                debugPrint(string.format("❌ No servers fetched, waiting %ds before retry...", RETRY_DELAY))
                task.wait(RETRY_DELAY)
                continue
            end
        end
        
        -- Now search through the server list (cached or fresh)
        local bestServer = nil
        local lowestPlayers = math.huge
        local serversChecked = 0
        
        debugPrint(string.format("🔍 Scanning %d servers for low population (%d-%d players)...", #serverList, MIN_PLAYERS, MAX_PLAYERS))
        
        for _, server in ipairs(serverList) do
            local playerCount = server.playing or 0
            serversChecked = serversChecked + 1
            
            if not getgenv().VisitedServers[server.id] 
                and playerCount >= MIN_PLAYERS 
                and playerCount <= MAX_PLAYERS
                and playerCount < lowestPlayers then
                
                bestServer = server
                lowestPlayers = playerCount
                debugPrint(string.format("⭐ Found candidate: %s (%d players)", server.id:sub(1,8).."...", playerCount))
            end
        end

        debugPrint(string.format("📊 Checked %d servers from list", serversChecked))

        -- If we found a suitable server, teleport to it
        if bestServer then
            debugPrint(string.format("✅ Found optimal server: %s (%d players)", 
                bestServer.id:sub(1, 8).."...", lowestPlayers))
            
            getgenv().VisitedServers[bestServer.id] = true
            queueSelf()
            
            -- Attempt teleport with error handling
            local teleportSuccess, teleportErr = pcall(function()
                TeleportService:TeleportToPlaceInstance(PLACE_ID, bestServer.id, LocalPlayer)
            end)
            
            if not teleportSuccess then
                debugPrint("❌ Teleport failed: "..(teleportErr or "unknown"))
                getgenv().FailedAttempts = getgenv().FailedAttempts + 1
                
                debugPrint(string.format("Waiting %ds before next attempt...", RETRY_DELAY))
                task.wait(RETRY_DELAY)
            else
                debugPrint("✅ Teleport initiated successfully!")
                return -- Successfully initiated teleport
            end
        else
            debugPrint(string.format("❌ No suitable server found in list (%d-%d players)", MIN_PLAYERS, MAX_PLAYERS))
            debugPrint("Clearing cache to fetch fresh servers...")
            clearCache()
            debugPrint(string.format("Waiting %ds before retry...", RETRY_DELAY))
            task.wait(RETRY_DELAY)
        end
    end
end

-- ==========================================
-- RECONNECT ON FAILURE
-- ==========================================
local function setupReconnect()
    game:GetService("CoreGui").RobloxPromptGui.promptOverlay.ChildAdded:Connect(function(prompt)
        if prompt.Name == "ErrorPrompt" then
            debugPrint("Disconnect detected, attempting reconnect...")
            task.wait(1)
            queueSelf()
            TeleportService:Teleport(PLACE_ID, LocalPlayer)
        end
    end)
end

pcall(setupReconnect) -- Setup disconnect handler

-- ==========================================
-- MAIN FLOW
-- ==========================================
task.wait(2) -- Initial delay to ensure workspace is loaded

debugPrint("Checking for celestial timer...")
debugPrint("Current server JobId: "..game.JobId)

local timer = getCelestialTimer()

if timer then
    debugPrint(string.format("✅ Timer found in this server: %d seconds (%d minutes %d seconds)", 
        timer, 
        math.floor(timer/60), 
        timer%60
    ))
    
    -- Send webhook for EVERY timer found
    debugPrint("Sending webhook notification for this timer...")
    sendWebhook(timer, game.JobId)
    
    -- Update global state
    getgenv().CelestialTimer = timer
    
    -- Track best timer for logging purposes
    if not getgenv().BestTimerFound or timer < getgenv().BestTimerFound then
        getgenv().BestTimerFound = timer
        getgenv().BestTimerJobId = game.JobId
        debugPrint(string.format("This is now the best timer found: %d seconds", timer))
    end
    
    debugPrint("Continuing to search other servers...")
    task.wait(2)
    hopServer()
else
    debugPrint("No timer in this server, hopping to next...")
    hopServer()
end

debugPrint("Script execution complete")
