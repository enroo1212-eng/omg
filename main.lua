-- ==========================================
-- CELESTIAL TIMER + SMART SERVER HOP + WEBHOOK
-- ==========================================

-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua"
local MAX_SERVER_SEARCHES = math.huge -- unlimited searches
local PLACE_ID = 131623223084840
local MIN_PLAYERS = 1 -- minimum players to consider a server
local MAX_PLAYERS = 4 -- maximum players for "lowest possible server"
local RETRY_DELAY = 15 -- seconds to wait before retrying

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

local function sendWebhook(eventTime, jobId)
    debugPrint("Attempting to send webhook with timer: "..eventTime.."s left")
    
    local timeStr = string.format("%02d:%02d", math.floor(eventTime/60), eventTime%60)
    local joinLink = string.format("roblox://placeId=%d&gameInstanceId=%s", PLACE_ID, jobId)
    
    local payload = {
        embeds = {{
            title = "⏰ Celestial Timer Found!",
            description = string.format("**Time Remaining:** `%s`\n**Server ID:** `%s`", timeStr, jobId),
            color = 0x8b5cf6,
            fields = {
                {
                    name = "📍 Server Info",
                    value = string.format("Players: %d\nServer: %s", #Players:GetPlayers(), game.JobId:sub(1, 8).."..."),
                    inline = true
                }
            },
            footer = { 
                text = "Celestial Timer Finder • Click button below to join",
                icon_url = "https://cdn.discordapp.com/emojis/1234567890.png"
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%S")
        }},
        components = {{
            type = 1,
            components = {{
                type = 2,
                style = 5, -- Link button (external)
                label = "🎮 Join Server",
                url = joinLink
            }}
        }}
    }

    -- Try multiple request methods
    local requestFunc = nil
    
    if request then
        requestFunc = request
        debugPrint("Using request() function")
    elseif http_request then
        requestFunc = http_request
        debugPrint("Using http_request() function")
    elseif syn and syn.request then
        requestFunc = syn.request
        debugPrint("Using syn.request() function")
    end
    
    if requestFunc then
        local success, err = pcall(function()
            local response = requestFunc({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = { 
                    ["Content-Type"] = "application/json"
                },
                Body = HttpService:JSONEncode(payload)
            })
            debugPrint("Webhook response: "..(response and "Success" or "No response"))
        end)
        
        if success then
            debugPrint("✅ Webhook sent successfully!")
        else
            debugPrint("❌ Webhook failed: "..(err or "unknown error"))
        end
    else
        debugPrint("❌ No HTTP request function available! Tried: request, http_request, syn.request")
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

        repeat
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

            local success, data = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            if not success then
                debugPrint("API request failed, waiting 15s before retry...")
                task.wait(RETRY_DELAY)
                break
            end

            if not data or not data.data then
                debugPrint("Invalid response from API, waiting 15s...")
                task.wait(RETRY_DELAY)
                break
            end

            -- Find server with lowest player count that we haven't visited
            for _, server in ipairs(data.data) do
                local playerCount = server.playing or 0
                
                if not getgenv().VisitedServers[server.id] 
                    and playerCount >= MIN_PLAYERS 
                    and playerCount <= MAX_PLAYERS
                    and playerCount < lowestPlayers then
                    
                    bestServer = server
                    lowestPlayers = playerCount
                end
            end

            cursor = data.nextPageCursor
            
            -- Small delay between pagination requests
            if cursor then
                task.wait(0.5)
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
                debugPrint("Teleport failed: "..(teleportErr or "unknown"))
                getgenv().FailedAttempts = getgenv().FailedAttempts + 1
                
                debugPrint(string.format("Waiting %ds before next attempt...", RETRY_DELAY))
                task.wait(RETRY_DELAY)
            else
                debugPrint("Teleport initiated successfully!")
                return -- Successfully initiated teleport
            end
        else
            debugPrint(string.format("No suitable server found (1-%d players). Waiting %ds before retry...", MAX_PLAYERS, RETRY_DELAY))
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
