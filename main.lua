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
local RETRY_DELAY = 15 -- seconds to wait before retrying
local SERVER_LIMIT = 100 -- reduced from 100 to avoid rate limits
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
getgenv().CachedServerList = getgenv().CachedServerList or {} -- Cache server list to avoid refetching
getgenv().LastCacheTime = getgenv().LastCacheTime or 0
getgenv().VisitedServers[game.JobId] = true

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
    local m, s = text:match("(%d%d):(%d%d)")
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

    for _, obj in ipairs(EventTimers:GetChildren()) do
        local gui = obj:FindFirstChild("SurfaceGui")
        local frame = gui and gui:FindFirstChild("Frame")
        if frame then
            for _, label in ipairs(frame:GetChildren()) do
                if label:IsA("TextLabel") and label.Text:match("CELESTIAL") then
                    local cleanText = label.Text:gsub("<[^>]+>", "")
                    local timeStr = cleanText:match("APPEARS IN (%d%d:%d%d)")
                    if timeStr then
                        local seconds = parseTime(timeStr)
                        if seconds then
                            debugPrint("Found celestial timer: "..seconds.."s")
                            return seconds
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
-- SMART SERVER HOPPER WITH CACHING & RATE LIMITING
-- ==========================================
local function hopServer()
    debugPrint("Searching for lowest population servers (unlimited attempts)...")
    local attempts = 0
    local lastRequestTime = 0
    local REQUEST_DELAY = 3 -- increased delay between requests
    local CACHE_DURATION = 120 -- cache servers for 2 minutes

    while true do -- infinite loop for unlimited searches
        attempts = attempts + 1
        debugPrint(string.format("Search attempt #%d", attempts))
        
        local serverList = {}
        local needsRefetch = false
        
        -- Check if we need to refetch or can use cache
        local timeSinceCache = tick() - getgenv().LastCacheTime
        if #getgenv().CachedServerList > 0 and timeSinceCache < CACHE_DURATION then
            debugPrint(string.format("Using cached server list (%d servers, %.0fs old)", #getgenv().CachedServerList, timeSinceCache))
            serverList = getgenv().CachedServerList
        else
            debugPrint("Cache expired or empty, fetching fresh server list...")
            needsRefetch = true
        end
        
        -- Fetch new server list if needed
        if needsRefetch then
            local cursor = nil
            local pageNumber = 0
            local totalFetched = 0
            local maxPages = 10 -- limit pages to avoid too many requests
            
            getgenv().CachedServerList = {} -- clear old cache
            
            repeat
                pageNumber = pageNumber + 1
                
                if pageNumber > maxPages then
                    debugPrint(string.format("Reached max pages (%d), stopping fetch", maxPages))
                    break
                end
                
                debugPrint(string.format("Fetching page %d (limit: %d servers per page)", pageNumber, SERVER_LIMIT))
                
                -- Rate limiting protection
                local timeSinceLastRequest = tick() - lastRequestTime
                if timeSinceLastRequest < REQUEST_DELAY then
                    local waitTime = REQUEST_DELAY - timeSinceLastRequest
                    debugPrint(string.format("Rate limit protection: waiting %.1fs", waitTime))
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
                        debugPrint("Waiting 15s before retry...")
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
                    debugPrint("Waiting 15s before retry...")
                    task.wait(RETRY_DELAY)
                    break
                end

                if not data.data then
                    debugPrint("❌ Invalid response structure (no 'data' field)")
                    debugPrint("Waiting 15s before retry...")
                    task.wait(RETRY_DELAY)
                    break
                end

                debugPrint(string.format("Page %d loaded: %d servers found", pageNumber, #data.data))
                
                -- Add servers to cache
                for _, server in ipairs(data.data) do
                    table.insert(getgenv().CachedServerList, server)
                    totalFetched = totalFetched + 1
                end

                cursor = data.nextPageCursor
                
                if cursor then
                    debugPrint(string.format("nextPageCursor found, will fetch page %d...", pageNumber + 1))
                    task.wait(1) -- Wait between pagination requests
                else
                    debugPrint("No nextPageCursor - reached end of server list")
                end
                
            until not cursor
            
            if totalFetched > 0 then
                debugPrint(string.format("✅ Cached %d servers total", totalFetched))
                getgenv().LastCacheTime = tick()
                serverList = getgenv().CachedServerList
            else
                debugPrint("❌ No servers fetched, waiting before retry...")
                task.wait(RETRY_DELAY)
                -- Continue to next attempt
                continue
            end
        end
        
        -- Now search through the server list (cached or fresh)
        local bestServer = nil
        local lowestPlayers = math.huge
        local serversChecked = 0
        
        debugPrint(string.format("Scanning %d servers for low population (1-%d players)...", #serverList, MAX_PLAYERS))
        
        for _, server in ipairs(serverList) do
            local playerCount = server.playing or 0
            serversChecked = serversChecked + 1
            
            if not getgenv().VisitedServers[server.id] 
                and playerCount >= MIN_PLAYERS 
                and playerCount <= MAX_PLAYERS
                and playerCount < lowestPlayers then
                
                bestServer = server
                lowestPlayers = playerCount
                debugPrint(string.format("Found candidate: %s (%d players)", server.id:sub(1,8).."...", playerCount))
            end
        end

        debugPrint(string.format("Checked %d servers from list", serversChecked))

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
            debugPrint(string.format("❌ No suitable server found in cached list (1-%d players)", MAX_PLAYERS))
            debugPrint("Clearing cache to fetch fresh servers...")
            getgenv().CachedServerList = {} -- Clear cache to force refetch
            getgenv().LastCacheTime = 0
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
local timer = getCelestialTimer()

if timer then
    getgenv().CelestialTimer = timer
    sendWebhook(timer, game.JobId)
    debugPrint("Timer found and webhook sent! Continuing to search other servers...")
    task.wait(2) -- Brief delay before hopping
    hopServer()
else
    debugPrint("No timer in this server, hopping to next...")
    hopServer()
end

debugPrint("Script execution complete")
