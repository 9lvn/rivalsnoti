-- STYLED Avatar Previews + Fixed Rotation + Bacon Detector + Account Age + Ping Display
-- Auto-scaling layout, better camera fit, bigger text, custom bacon notification, K toggle hide/show

local HttpService          = game:GetService("HttpService")
local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local MarketplaceService   = game:GetService("MarketplaceService")
local UserInputService     = game:GetService("UserInputService")
local CoreGui              = game:GetService("CoreGui")
local TweenService         = game:GetService("TweenService")
local Workspace            = game:GetService("Workspace")

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

local BASE_PREVIEW_WIDTH   = 470
local BASE_PREVIEW_HEIGHT  = 730
local NAME_HEIGHT          = 42
local VIEWPORT_HEIGHT      = 520
local LABEL_HEIGHT         = 118

local CARD_SPACING         = 20
local SCREEN_PADDING       = 18
local TOP_OFFSET           = 74
local BOTTOM_PADDING       = 18
local MIN_CARD_SCALE       = 0.42
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

local layoutDirty = true
local lastViewportSize = Vector2.new(0, 0)

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

local function addCorner(instance, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = instance
    return corner
end

local function addStroke(instance, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color
    stroke.Thickness = thickness
    stroke.Transparency = transparency or 0
    stroke.Parent = instance
    return stroke
end

local function addGradient(instance, c1, c2, rotation)
    local gradient = Instance.new("UIGradient")
    gradient.Color = ColorSequence.new(c1, c2)
    gradient.Rotation = rotation or 90
    gradient.Parent = instance
    return gradient
end

local function getScreenSize()
    local cam = Workspace.CurrentCamera
    if cam and cam.ViewportSize.X > 0 and cam.ViewportSize.Y > 0 then
        return cam.ViewportSize
    end
    return Vector2.new(1920, 1080)
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

    local holder = Instance.new("Frame")
    holder.Name = "PingHolder"
    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Position = UDim2.new(0.5, 0, 0, 14)
    holder.Size = UDim2.new(0, 270, 0, 54)
    holder.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    holder.BackgroundTransparency = 0.08
    holder.BorderSizePixel = 0
    holder.Parent = pingGui
    addCorner(holder, 14)
    addStroke(holder, Color3.fromRGB(120, 160, 255), 1.4, 0.35)
    addGradient(holder, Color3.fromRGB(22, 24, 35), Color3.fromRGB(16, 18, 26), 90)

    pingLabel = Instance.new("TextLabel")
    pingLabel.Name = "PingLabel"
    pingLabel.BackgroundTransparency = 1
    pingLabel.Size = UDim2.new(1, -16, 1, 0)
    pingLabel.Position = UDim2.new(0, 8, 0, 0)
    pingLabel.TextColor3 = Color3.fromRGB(230, 240, 255)
    pingLabel.TextStrokeTransparency = 0.85
    pingLabel.Font = Enum.Font.GothamBold
    pingLabel.TextSize = 25
    pingLabel.Text = "Ping: " .. getPingText()
    pingLabel.Parent = holder
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

local function fitModelInViewport(preview)
    if not preview or not preview.Model or not preview.Camera or not preview.Viewport then
        return
    end

    local model = preview.Model
    local camera = preview.Camera
    local viewport = preview.Viewport

    local ok, bboxCFrame, bboxSize = pcall(function()
        local cf, size = model:GetBoundingBox()
        return cf, size
    end)

    if not ok or not bboxCFrame or not bboxSize then
        return
    end

    local viewportSize = viewport.AbsoluteSize
    local aspect = 1
    if viewportSize.Y > 0 then
        aspect = viewportSize.X / viewportSize.Y
    end

    camera.FieldOfView = 48

    local verticalFov = math.rad(camera.FieldOfView)
    local horizontalFov = 2 * math.atan(math.tan(verticalFov / 2) * aspect)

    local halfHeight = bboxSize.Y * 0.56
    local halfWidth = math.max(bboxSize.X, bboxSize.Z) * 0.62

    local distanceForHeight = halfHeight / math.tan(verticalFov / 2)
    local distanceForWidth = halfWidth / math.tan(horizontalFov / 2)
    local distance = math.max(distanceForHeight, distanceForWidth) + 0.75

    local focus = bboxCFrame.Position + Vector3.new(0, bboxSize.Y * 0.05, 0)
    local cameraPos = focus + Vector3.new(0, bboxSize.Y * 0.02, distance)

    camera.CFrame = CFrame.new(cameraPos, focus)
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
        "Level %s   •   Streak %s   •   %s\nValue %dR$   •   Account Age %s days",
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
    root.Size = UDim2.new(0, BASE_PREVIEW_WIDTH, 0, BASE_PREVIEW_HEIGHT)
    root.BackgroundTransparency = 1
    root.Parent = gui

    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = root

    local shadow = Instance.new("Frame")
    shadow.Name = "Shadow"
    shadow.Size = UDim2.new(1, 12, 1, 12)
    shadow.Position = UDim2.new(0, -6, 0, -2)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.78
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = root
    addCorner(shadow, 22)

    local card = Instance.new("Frame")
    card.Name = "Card"
    card.Size = UDim2.new(1, 0, 1, 0)
    card.BackgroundColor3 = Color3.fromRGB(17, 19, 27)
    card.BackgroundTransparency = 0.1
    card.BorderSizePixel = 0
    card.Parent = root
    addCorner(card, 20)
    addStroke(card, Color3.fromRGB(120, 150, 255), 1.4, 0.45)
    addGradient(card, Color3.fromRGB(24, 28, 40), Color3.fromRGB(14, 16, 24), 90)

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -24, 0, NAME_HEIGHT)
    nameLabel.Position = UDim2.new(0, 12, 0, 10)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(240, 245, 255)
    nameLabel.TextStrokeTransparency = 0.9
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 28
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Text = "@" .. tostring(player.Name)
    nameLabel.Parent = card

    local divider = Instance.new("Frame")
    divider.Name = "Divider"
    divider.Size = UDim2.new(1, -24, 0, 1)
    divider.Position = UDim2.new(0, 12, 0, NAME_HEIGHT + 14)
    divider.BackgroundColor3 = Color3.fromRGB(95, 115, 170)
    divider.BackgroundTransparency = 0.45
    divider.BorderSizePixel = 0
    divider.Parent = card

    local viewport = Instance.new("ViewportFrame")
    viewport.Name = "Viewport"
    viewport.Size = UDim2.new(1, -24, 0, VIEWPORT_HEIGHT)
    viewport.Position = UDim2.new(0, 12, 0, NAME_HEIGHT + 24)
    viewport.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    viewport.BackgroundTransparency = 0.12
    viewport.BorderSizePixel = 0
    viewport.Ambient = Color3.fromRGB(210, 220, 240)
    viewport.LightColor = Color3.fromRGB(255, 245, 230)
    viewport.Parent = card
    addCorner(viewport, 16)
    addStroke(viewport, Color3.fromRGB(90, 110, 160), 1, 0.55)

    local worldModel = Instance.new("WorldModel")
    worldModel.Name = "WorldModel"
    worldModel.Parent = viewport

    local camera = Instance.new("Camera")
    camera.Name = "PreviewCamera"
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = 48
    camera.Parent = viewport
    viewport.CurrentCamera = camera

    local label = Instance.new("TextLabel")
    label.Name = "StatsLabel"
    label.Size = UDim2.new(1, -24, 0, LABEL_HEIGHT)
    label.Position = UDim2.new(0, 12, 1, -LABEL_HEIGHT - 12)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(205, 255, 220)
    label.TextStrokeTransparency = 0.88
    label.TextStrokeColor3 = Color3.new(0, 0, 0)
    label.TextSize = 23
    label.Font = Enum.Font.GothamSemibold
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.Text = "Loading..."
    label.Parent = card

    activePreviews[userId] = {
        Gui = gui,
        Root = root,
        Card = card,
        Viewport = viewport,
        World = worldModel,
        Camera = camera,
        StatsLabel = label,
        NameLabel = nameLabel,
        Model = nil,
        StatsConnections = {},
        ScaleObject = uiScale,
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

        model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.pi, 0))
        model.Parent = preview.World

        preview.Model = model

        task.wait()
        fitModelInViewport(preview)

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
                "Value %dR$   •   Account Age %s days\nLoading stats...",
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

local function calculateBestGrid(count, screenSize)
    if count <= 0 then
        return 1, 1, 1
    end

    local availableWidth = math.max(100, screenSize.X - (SCREEN_PADDING * 2))
    local availableHeight = math.max(100, screenSize.Y - TOP_OFFSET - BOTTOM_PADDING)

    local bestCols = count
    local bestRows = 1
    local bestScale = MIN_CARD_SCALE

    for cols = 1, count do
        local rows = math.ceil(count / cols)

        local scaleW = (availableWidth - ((cols - 1) * CARD_SPACING)) / (cols * BASE_PREVIEW_WIDTH)
        local scaleH = (availableHeight - ((rows - 1) * CARD_SPACING)) / (rows * BASE_PREVIEW_HEIGHT)
        local scale = math.min(scaleW, scaleH, 1)

        if scale > bestScale then
            bestScale = scale
            bestCols = cols
            bestRows = rows
        end
    end

    bestScale = math.max(bestScale, MIN_CARD_SCALE)

    return bestCols, bestRows, bestScale
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

    local count = #others
    if count <= 0 then
        return
    end

    local screenSize = getScreenSize()
    local cols, rows, scale = calculateBestGrid(count, screenSize)

    local scaledWidth = BASE_PREVIEW_WIDTH * scale
    local scaledHeight = BASE_PREVIEW_HEIGHT * scale

    local totalWidth = (cols * scaledWidth) + ((cols - 1) * CARD_SPACING)
    local totalHeight = (rows * scaledHeight) + ((rows - 1) * CARD_SPACING)

    local startX = math.floor((screenSize.X - totalWidth) / 2)
    local availableHeight = screenSize.Y - TOP_OFFSET - BOTTOM_PADDING
    local startY = math.floor(TOP_OFFSET + math.max(0, (availableHeight - totalHeight) / 2))

    for index, player in ipairs(others) do
        local data = activePreviews[player.UserId]
        if data and data.Root and data.ScaleObject then
            local col = (index - 1) % cols
            local row = math.floor((index - 1) / cols)

            local x = startX + col * (scaledWidth + CARD_SPACING)
            local y = startY + row * (scaledHeight + CARD_SPACING)

            data.ScaleObject.Scale = scale
            data.Root.Position = UDim2.new(0, x, 0, y)

            if data.Model then
                task.defer(function()
                    if activePreviews[player.UserId] == data then
                        fitModelInViewport(data)
                    end
                end)
            end
        end
    end
end

trackConnection(RunService.Heartbeat:Connect(function(deltaTime)
    if shuttingDown then
        return
    end

    local viewportSize = getScreenSize()
    if viewportSize ~= lastViewportSize then
        lastViewportSize = viewportSize
        layoutDirty = true
    end

    pingUpdateAccumulator = pingUpdateAccumulator + deltaTime
    if pingUpdateAccumulator >= 0.35 then
        pingUpdateAccumulator = 0
        updatePingDisplay()
    end

    if layoutDirty then
        layoutDirty = false
        updateAllPreviews()
    end

    if not previewsVisible then
        return
    end

    local rotationAngle = math.rad(ROTATION_SPEED_DEG * deltaTime)

    for userId, data in pairs(activePreviews) do
        local model = data.Model

        if model and model.Parent then
            model:PivotTo(model:GetPivot() * CFrame.Angles(0, rotationAngle, 0))
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
            layoutDirty = true
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
        layoutDirty = true
    end)
end))

trackConnection(Players.PlayerRemoving:Connect(function(player)
    task.delay(0.2, function()
        cleanupPreview(player.UserId)
        if not shuttingDown then
            layoutDirty = true
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
    pcall(function()
        local old = CoreGui:FindFirstChild("CustomNotification")
        if old then
            old:Destroy()
        end
    end)

    local gui = Instance.new("ScreenGui")
    gui.Name = "CustomNotification"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 200
    gui.Parent = CoreGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 320, 0, 84)
    frame.Position = UDim2.new(0, -340, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -20, 0, 30)
    title.Position = UDim2.new(0, 10, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = "Bacon Detector"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local message = Instance.new("TextLabel")
    message.Size = UDim2.new(1, -20, 0, 42)
    message.Position = UDim2.new(0, 10, 0, 32)
    message.BackgroundTransparency = 1
    message.Text = tostring(name) .. " detected as " .. tostring(baconType)
    message.TextColor3 = Color3.fromRGB(210, 210, 210)
    message.Font = Enum.Font.Gotham
    message.TextSize = 17
    message.TextWrapped = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.TextYAlignment = Enum.TextYAlignment.Top
    message.Parent = frame

    local tweenIn = TweenService:Create(
        frame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.new(0, 20, 0, 20)}
    )

    local tweenOut = TweenService:Create(
        frame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Position = UDim2.new(0, -340, 0, 20)}
    )

    tweenIn:Play()

    task.spawn(function()
        task.wait(4)
        if not frame or not frame.Parent then
            safeDestroy(gui)
            return
        end

        tweenOut:Play()
        tweenOut.Completed:Wait()
        safeDestroy(gui)
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
            if string.find(obj.Name, "^AvatarPreview_") or string.find(obj.Name, "^BaconWarning_") or obj.Name == "CustomNotification" then
                safeDestroy(obj)
            end
        end
    end
end

createPingDisplay()
layoutDirty = true
updateAllPreviews()
initialBaconScan()

print("✨ Styled Avatar Previews + Auto Layout + Better Camera Fit + Bigger Text + Custom Bacon Notification + Account Age + Ping Display LOADED!")
print("💡 Press K to toggle previews (hide / show)")
