-- ==========================================
-- FULL SELF-QUEUING EVENT TRACKER + SERVER HOP
-- ==========================================

-- 🔧 CONFIG
local WEBHOOK_URL = "https://discord.com/api/webhooks/1470016492392419391/Hi4VRzHwtnggE-AmygcE5jJEl7goOcaMSUM-2uFPWvbCwifEiaZAm2Dc0uMjCqh6OC8j"
local ALERT_TIME = 120 -- seconds (2 minutes)
local HOP_DELAY = 2 -- seconds between hops
local SCRIPT_RAW_URL = "https://raw.githubusercontent.com/enroo1212-eng/omg/refs/heads/main/main.lua" -- this script raw URL

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
getgenv().AlertSent = getgenv().AlertSent or false

-- mark current server as visited
getgenv().VisitedServers[game.JobId] = true

-- ==========================================
-- SELF QUEUE ON TELEPORT
-- ==========================================
local function queueSelf()
    if queue_on_teleport then
        queue_on_teleport(game:HttpGet(SCRIPT_RAW_URL))
    elseif syn and syn.queue_on_teleport then
        syn.queue_on_teleport(game:HttpGet(SCRIPT_RAW_URL))
    end
end
queueSelf() -- queue immediately

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

local function sendWebhook(eventName, secondsLeft)
    if getgenv().AlertSent then return end
    getgenv().AlertSent = true

    local payload = {
        embeds = {{
            title = "⏰ Event Starting Soon",
            description = "**"..eventName.."**",
            color = 0x8b5cf6,
            fields = {
                { name = "⏱ Time Left", value = string.format("%02d:%02d", secondsLeft/60, secondsLeft%60), inline = true },
                { name = "🎮 Join Server", value = "[Click to Join](" .. getJoinLink() .. ")", inline = false }
            },
            footer = { text = "Automated Event Tracker" }
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
-- WATCH EVENT TIMERS
-- ==========================================
local function watchEventTimers()
    local EventTimers = workspace:WaitForChild("EventTimers", 10)
    if not EventTimers then return false end

    for _, obj in ipairs(EventTimers:GetChildren()) do
        local gui = obj:FindFirstChild("SurfaceGui")
        local frame = gui and gui:FindFirstChild("Frame")
        local label = frame and frame:FindFirstChild("TextLabel2")
        if label then
            local function check()
                if getgenv().AlertSent then return end
                local clean = label.Text:gsub("<[^>]+>", "")
                local seconds = parseTime(clean)
                if seconds and seconds <= ALERT_TIME then
                    local eventName = clean:match("(.+)%sEVENT") or "EVENT"
                    sendWebhook(eventName, seconds)
                end
            end

            check()
            label:GetPropertyChangedSignal("Text"):Connect(check)
            return true
        end
    end
    return false
end

-- ==========================================
-- SERVER HOPPER
-- ==========================================
local function hopServer()
    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?limit=100"):format(game.PlaceId)
    local success, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(url))
    end)
    if not success or not data then return end

    for _, server in ipairs(data.data) do
        if server.playing < 8 and not getgenv().VisitedServers[server.id] then
            getgenv().VisitedServers[server.id] = true

            -- queue self again for next server
            queueSelf()

            task.wait(HOP_DELAY)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
            return
        end
    end
end

-- MAIN FLOW
if not getgenv().AlertSent then
    local foundTimer = watchEventTimers()
    if not foundTimer then
        -- Only hop if no event timer exists
        hopServer()
    end
end

