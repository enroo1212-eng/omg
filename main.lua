-- ==========================================
-- CELESTIAL TIMER GRAB + SERVER HOP + SELF QUEUE
-- ==========================================

-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua"

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
getgenv().CelestialTimer = getgenv().CelestialTimer or nil -- stores latest timer in seconds

-- mark current server as visited
getgenv().VisitedServers[game.JobId] = true

-- ==========================================
-- DEBUG FUNCTION
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

local function sendWebhook(eventTime)
    debugPrint("Sending webhook with timer: "..eventTime.."s left")
    local payload = {
        embeds = {{
            title = "⏰ Celestial Timer Found",
            description = "Time remaining: "..string.format("%02d:%02d", eventTime/60, eventTime%60),
            color = 0x8b5cf6,
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
                    -- Remove RichText tags
                    local cleanText = label.Text:gsub("<[^>]+>", "")
                    -- Extract "APPEARS IN XX:XX"
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
-- SERVER HOPPER
-- ==========================================
local function hopServer()
    debugPrint("Searching for servers to hop to...")
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100"):format(game.PlaceId)
    local success, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not success or not data then
        debugPrint("Failed to fetch server list.")
        return
    end

    for _, server in ipairs(data.data) do
        if server.playing >= 8 then
            debugPrint("Skipping full server: "..server.id.." ("..server.playing.."/8)")
        elseif getgenv().VisitedServers[server.id] then
            debugPrint("Skipping visited server: "..server.id)
        else
            debugPrint("Hopping to server: "..server.id.." ("..server.playing.."/8)")
            getgenv().VisitedServers[server.id] = true
            queueSelf()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
            return
        end
    end

    debugPrint("No suitable servers found to hop.")
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
