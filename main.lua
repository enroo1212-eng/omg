-- ==========================================
-- CELESTIAL TIMER + SERVER HOP + WEBHOOK JOIN LINK
-- ==========================================

-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua"
local MAX_SERVER_SEARCHES = 5 -- how many times to retry if no server found

-- Replace with your game ID
local PLACE_ID = 131623223084840

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
    if queue_on_teleport then
        queue_on_teleport(game:HttpGet(SCRIPT_RAW_URL))
        debugPrint("Queued self with queue_on_teleport")
    elseif syn and syn.queue_on_teleport then
        syn.queue_on_teleport(game:HttpGet(SCRIPT_RAW_URL))
        debugPrint("Queued self with syn.queue_on_teleport")
    else
        debugPrint("queue_on_teleport not supported")
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
    return ("roblox://placeId=%d&gameInstanceId=%s"):format(PLACE_ID, jobId)
end

local function sendWebhook(eventTime)
    debugPrint("Sending webhook with timer: "..eventTime.."s left")
    local payload = {
        embeds = {{
            title = "⏰ Celestial Timer Found",
            description = "Time remaining: "..string.format("%02d:%02d", eventTime/60, eventTime%60),
            color = 0x8b5cf6,
            fields = {
                { name = "🎮 Join Server", value = "[Click to Join]("..getJoinLink(game.JobId)..")", inline = false }
            },
            footer = { text = "Celestial Timer Grabber" }
        }}
    }

    local req = syn and syn.request or http_request or request
    if req then
        req({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = HttpService:JSONEncode(payload)
        })
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
-- SERVER HOPPER USING PROVIDED API
-- ==========================================
local function hopServer()
    debugPrint("Searching for servers to hop to...")
    local retries = 0

    while retries < MAX_SERVER_SEARCHES do
        local cursor = nil
        local found = false

        repeat
            local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&excludeFullGames=true&limit=100%s"):format(
                PLACE_ID,
                cursor and "&cursor="..cursor or ""
            )

            local success, data = pcall(function()
                return HttpService:JSONDecode(game:HttpGet(url))
            end)

            if not success or not data then
                debugPrint("Failed to fetch server list.")
                break
            end

            for _, server in ipairs(data.data) do
                if not getgenv().VisitedServers[server.id] then
                    debugPrint("Hopping to server: "..server.id.." ("..server.playing.." players)")
                    getgenv().VisitedServers[server.id] = true
                    queueSelf()
                    TeleportService:TeleportToPlaceInstance(PLACE_ID, server.id, Players.LocalPlayer)
                    found = true
                    break
                end
            end

            if found then return end
            cursor = data.nextPageCursor
            task.wait(0.5)
        until not cursor

        retries = retries + 1
        debugPrint("Retrying server search ("..retries.."/"..MAX_SERVER_SEARCHES..")")
        task.wait(1)
    end

    debugPrint("Could not find a suitable server after retries.")
end

-- ==========================================
-- MAIN FLOW
-- ==========================================
local timer = getCelestialTimer()
if timer then
    getgenv().CelestialTimer = timer
    sendWebhook(timer)
    debugPrint("Timer saved globally, now hopping to next server...")
    hopServer()
else
    debugPrint("No timer found, hopping to next server...")
    hopServer()
end
