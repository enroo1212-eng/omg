-- ==========================================
-- CELESTIAL TIMER GRAB + FULL SERVER HOP + SELF QUEUE + JOIN BUTTON
-- ==========================================

-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua"
local MAX_PLAYERS_PER_SERVER = 8 -- adjust if needed

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

local function getJoinLink()
    return ("roblox://placeId=%d&gameInstanceId=%s"):format(game.PlaceId, game.JobId)
end

local function sendWebhook(eventTime)
    debugPrint("Sending webhook with timer: "..eventTime.."s left")
    local payload = {
        embeds = {{
            title = "⏰ Celestial Timer Found",
            description = "Time remaining: "..string.format("%02d:%02d", eventTime/60, eventTime%60),
            color = 0x8b5cf6,
            fields = {
                { name = "🎮 Join Server", value = "[Click to Join](" .. getJoinLink() .. ")", inline = false }
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
-- SERVER HOPPER WITH PAGING + SORTING
-- ==========================================
local function hopServer()
    debugPrint("Searching for servers to hop to...")
    local cursor = nil

    while true do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100%s"):format(
            game.PlaceId,
            cursor and "&cursor="..cursor or ""
        )

        local success, data = pcall(function()
            return HttpService:JSONDecode(game:HttpGet(url))
        end)

        if not success or not data then
            debugPrint("Failed to fetch server list.")
            return
        end

        -- sort servers by least players first
        table.sort(data.data, function(a, b) return a.playing < b.playing end)

        local found = false
        for _, server in ipairs(data.data) do
            if server.playing < MAX_PLAYERS_PER_SERVER and not getgenv().VisitedServers[server.id] then
                debugPrint("Hopping to server: "..server.id.." ("..server.playing.."/"..MAX_PLAYERS_PER_SERVER..")")
                getgenv().VisitedServers[server.id] = true
                queueSelf()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
                found = true
                break
            end
        end

        if found then return end

        -- no server found yet, check if there is a next page
        if not data.nextPageCursor then
            debugPrint("No suitable servers found after checking all pages.")
            return
        end
        cursor = data.nextPageCursor
        debugPrint("No server found yet, fetching next page...")
        task.wait(0.5)
    end
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
