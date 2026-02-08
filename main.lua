-- ==========================================
-- CELESTIAL TIMER + SMART SERVER HOP + WEBHOOK
-- ==========================================

-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua"
local MAX_SERVER_SEARCHES = math.huge -- unlimited searches
local PLACE_ID = 131623223084840
local MIN_PLAYERS = 1 -- minimum players to consider a server
local MAX_PLAYERS = 6 -- maximum players for "lowest possible server"
local RETRY_DELAY = 20 -- seconds to wait before retrying

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
    local joinLink = string.format("roblox://placeId=%d&gameInstanceId=%s", PLACE_ID, jobId)
    
    -- Simplified payload without components (more compatible)
    local payload = {
        content = "🔔 **Celestial Timer Found!**",
        embeds = {{
            title = "⏰ Celestial Event Timer",
            description = string.format("**Time Remaining:** `%s`\n\n**🎮 Join Server:**\n```%s```\n\n**Server ID:** `%s`", 
                timeStr, 
                joinLink,
                jobId:sub(1, 16).."..."
            ),
            color = 9055471, -- Purple color (0x8a5cf6 converted to decimal)
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
                text = "Celestial Timer Finder • Copy the roblox:// link above"
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
-- SMART SERVER HOPPER WITH RATE LIMITING
-- ==========================================
local function hopServer()
    debugPrint("Searching for lowest population servers (unlimited attempts)...")
    local attempts = 0
    local lastRequestTime = 0
    local REQUEST_DELAY = 2 -- seconds between API requests to avoid rate limiting

    while true do -- infinite loop for unlimited searches
        attempts = attempts + 1
        debugPrint(string.format("Search attempt #%d", attempts))
        
        local cursor = nil
        local bestServer = nil
        local lowestPlayers = math.huge
        local pageNumber = 0

        repeat
            pageNumber = pageNumber + 1
            debugPrint(string.format("Fetching page %d%s", pageNumber, cursor and " (cursor: "..cursor:sub(1,20).."...)" or " (first page)"))
            
            -- Rate limiting protection
            local timeSinceLastRequest = tick() - lastRequestTime
            if timeSinceLastRequest < REQUEST_DELAY then
                local waitTime = REQUEST_DELAY - timeSinceLastRequest
                debugPrint(string.format("Rate limit protection: waiting %.1fs", waitTime))
                task.wait(waitTime)
            end
            
            lastRequestTime = tick()

            local url = string.format(
                "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100%s",
                PLACE_ID,
                cursor and "&cursor="..cursor or ""
            )

            local success, response = pcall(function()
                return game:HttpGet(url)
            end)

            if not success then
                debugPrint("❌ API request failed: "..(response or "unknown error"))
                debugPrint("Restarting from first page, waiting 15s...")
                task.wait(RETRY_DELAY)
                break -- Break out of repeat loop to restart from beginning
            end

            local data = nil
            local parseSuccess = pcall(function()
                data = HttpService:JSONDecode(response)
            end)

            if not parseSuccess or not data then
                debugPrint("❌ Failed to parse JSON response")
                debugPrint("Restarting from first page, waiting 15s...")
                task.wait(RETRY_DELAY)
                break -- Break out to restart from beginning
            end

            if not data.data then
                debugPrint("❌ Invalid response structure (no 'data' field)")
                debugPrint("Restarting from first page, waiting 15s...")
                task.wait(RETRY_DELAY)
                break -- Break out to restart from beginning
            end

            debugPrint(string.format("Page %d loaded: %d servers found", pageNumber, #data.data))

            -- Find server with lowest player count that we haven't visited
            local serversChecked = 0
            for _, server in ipairs(data.data) do
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

            debugPrint(string.format("Checked %d servers on page %d", serversChecked, pageNumber))

            -- Get next cursor if available
            local previousCursor = cursor
            cursor = data.nextPageCursor
            
            if cursor then
                debugPrint(string.format("nextPageCursor found, continuing to page %d...", pageNumber + 1))
                task.wait(0.5) -- Small delay between pagination requests
            else
                debugPrint("No nextPageCursor - reached end of server list")
            end
            
        until not cursor or bestServer

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
            debugPrint(string.format("❌ No suitable server found (1-%d players). Waiting %ds before retry...", MAX_PLAYERS, RETRY_DELAY))
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
