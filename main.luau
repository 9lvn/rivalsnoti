--[[
    ============================================================
    STYLED AVATAR PREVIEWS + AUTO LAYOUT + ACCOUNT AGE + PING
    + TELEPORT MENU + MOBILE CONFIRM POPUP + BACON DETECTOR
    + FADE TOGGLE ANIMATION + EXECUTOR PING COLOR SETUP SAVE
    + CLICK PING TO REFRESH VALUES
    ============================================================

    Press K to toggle the whole overlay:
    - avatar cards
    - ping display
    - teleport menu button
    - teleport menu panel
    - mobile confirmation popup

    FIRST RUN:
    - If no saved ping config exists, a setup popup appears.
    - Choose the max ping for GREEN and ORANGE.
    - RED is anything above ORANGE.
    - Config is saved with executor file APIs and loaded next time.

    CLICK PING BOX:
    - Clears cached avatar values
    - Clears stat update cooldowns
    - Refreshes all visible preview values
    - Updates ping instantly
]]

--========================================================================================================================================================================================================================================================
-- 1) SERVICES + SINGLETON CLEANUP
--========================================================================================================================================================================================================================================================

local HttpService          = game:GetService("HttpService")
local Players              = game:GetService("Players")
local RunService           = game:GetService("RunService")
local MarketplaceService   = game:GetService("MarketplaceService")
local UserInputService     = game:GetService("UserInputService")
local CoreGui              = game:GetService("CoreGui")
local TweenService         = game:GetService("TweenService")
local Workspace            = game:GetService("Workspace")
local TeleportService      = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer

if _G.AvatarPreviewSystem and _G.AvatarPreviewSystem.Shutdown then
    pcall(function()
        _G.AvatarPreviewSystem.Shutdown()
    end)
end

local System = {}
_G.AvatarPreviewSystem = System

--========================================================================================================================================================================================================================================================
-- 2) CONFIG VALUES
--========================================================================================================================================================================================================================================================

local BASE_PREVIEW_WIDTH   = 470
local BASE_PREVIEW_HEIGHT  = 730

local NAME_HEIGHT          = 42
local VIEWPORT_HEIGHT      = 520
local LABEL_HEIGHT         = 132

local CARD_SPACING         = 20
local SCREEN_PADDING       = 18
local TOP_OFFSET           = 74
local BOTTOM_PADDING       = 18
local MIN_CARD_SCALE       = 0.42

local ROTATION_SPEED_DEG   = 40
local MAX_ASSETS_TO_CHECK  = 35

local TOGGLE_FADE_TIME     = 0.22

local HUB_ID               = 17625359962
local TEAM_DEATHMATCH_ID   = 71874690745115
local FFA_ID               = 129604661913557
local GUN_GAME_ID          = 133215910299950
local MOBILE_SERVER_ID     = 18126510175

local CONFIG_FOLDER        = "AvatarPreviewSystem"
local CONFIG_FILE          = CONFIG_FOLDER .. "/PingConfig.json"

--========================================================================================================================================================================================================================================================
-- 3) STATE + UTILITY HELPERS
--========================================================================================================================================================================================================================================================

local avatarValueCache = {}
local activePreviews = {}
local updateCooldown = {}
local warned = {}
local previewsVisible = true
local connections = {}
local shuttingDown = false
local toggleBusy = false

local topBarGui = nil
local pingHolder = nil
local pingLabel = nil
local pingFadeCover = nil
local teleportMenuButton = nil
local teleportButtonFadeCover = nil

local teleportMenu = nil
local teleportMenuFadeCover = nil
local teleportWarningLabel = nil

local mobileConfirmFrame = nil
local mobileConfirmFadeCover = nil

local firstRunConfigFrame = nil
local firstRunFadeCover = nil
local greenInputBox = nil
local orangeInputBox = nil
local configStatusLabel = nil

local activeNotifications = {}
local NOTIFICATION_SPACING = 12

local pingUpdateAccumulator = 0

local layoutDirty = true
local lastViewportSize = Vector2.new(0, 0)

local pingColorConfig = {
    greenMax = 30,
    orangeMax = 60
}

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

local function createFadeCover(parent, color, zIndex, radius)
    local cover = Instance.new("Frame")
    cover.Name = "FadeCover"
    cover.Size = UDim2.new(1, 0, 1, 0)
    cover.Position = UDim2.new(0, 0, 0, 0)
    cover.BackgroundColor3 = color
    cover.BackgroundTransparency = 1
    cover.BorderSizePixel = 0
    cover.ZIndex = zIndex or 100
    cover.Parent = parent
    addCorner(cover, radius or 20)
    return cover
end

local function tweenObject(instance, info, props)
    local tween = TweenService:Create(instance, info, props)
    tween:Play()
    return tween
end

local function getIsFile()
    return isfile or (typeof(readfile) == "function" and function(path)
        local ok = pcall(function()
            return readfile(path)
        end)
        return ok
    end)
end

local function getMakeFolder()
    return makefolder or createfolder
end

local function executorFileAvailable()
    return typeof(readfile) == "function"
        and typeof(writefile) == "function"
end

local function ensureConfigFolder()
    local makeFolderFn = getMakeFolder()
    if typeof(makeFolderFn) ~= "function" then
        return
    end

    if typeof(isfolder) == "function" then
        local ok, exists = pcall(function()
            return isfolder(CONFIG_FOLDER)
        end)
        if ok and exists then
            return
        end
    end

    pcall(function()
        makeFolderFn(CONFIG_FOLDER)
    end)
end

local function clampNumber(n, minValue, maxValue, fallback)
    n = tonumber(n)
    if not n then
        return fallback
    end

    n = math.floor(n + 0.5)

    if n < minValue then
        n = minValue
    end

    if n > maxValue then
        n = maxValue
    end

    return n
end

local function savePingConfig()
    if not executorFileAvailable() then
        warn("Executor file functions not available; ping config cannot be saved.")
        return false
    end

    ensureConfigFolder()

    local payload = {
        greenMax = pingColorConfig.greenMax,
        orangeMax = pingColorConfig.orangeMax
    }

    local ok, err = pcall(function()
        writefile(CONFIG_FILE, HttpService:JSONEncode(payload))
    end)

    if not ok then
        warn("Failed to save ping config:", err)
        return false
    end

    return true
end

local function loadPingConfig()
    local isFileFn = getIsFile()
    if not executorFileAvailable() or typeof(isFileFn) ~= "function" then
        return false
    end

    local ok, exists = pcall(function()
        return isFileFn(CONFIG_FILE)
    end)

    if not ok or not exists then
        return false
    end

    local readOk, raw = pcall(function()
        return readfile(CONFIG_FILE)
    end)

    if not readOk or not raw or raw == "" then
        return false
    end

    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(raw)
    end)

    if not decodeOk or typeof(data) ~= "table" then
        return false
    end

    local greenMax = clampNumber(data.greenMax, 1, 9999, 80)
    local orangeMax = clampNumber(data.orangeMax, greenMax + 1, 9999, 140)

    pingColorConfig.greenMax = greenMax
    pingColorConfig.orangeMax = orangeMax

    return true
end

local function getPingNumber()
    local ok, result = pcall(function()
        local networkPing = LocalPlayer:GetNetworkPing()
        return math.floor((networkPing * 1000) + 0.5)
    end)

    if ok and result then
        return result
    end

    return nil
end

local function getPingColor(pingMs)
    if typeof(pingMs) ~= "number" then
        return Color3.fromRGB(230, 240, 255)
    end

    if pingMs <= pingColorConfig.greenMax then
        return Color3.fromRGB(120, 255, 140)
    elseif pingMs <= pingColorConfig.orangeMax then
        return Color3.fromRGB(255, 190, 90)
    else
        return Color3.fromRGB(255, 105, 105)
    end
end

--========================================================================================================================================================================================================================================================
-- 4) TOP BAR: PING + TELEPORT MENU BUTTON + FIRST RUN CONFIG
--========================================================================================================================================================================================================================================================

local function getPingText()
    local ping = getPingNumber()
    if typeof(ping) == "number" then
        return ping .. " ms", ping
    end
    return "? ms", nil
end

local function updatePingDisplay()
    if pingLabel then
        local text, pingMs = getPingText()
        pingLabel.Text = "Ping: " .. text
        pingLabel.TextColor3 = getPingColor(pingMs)
    end
end

local function refreshAllDisplayedValues()
    table.clear(avatarValueCache)
    table.clear(updateCooldown)

    updatePingDisplay()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local preview = activePreviews[player.UserId]
            if preview then
                updateStatsLabel(player.UserId, player)
            end
        end
    end
end

local function showTeleportWarning(text)
    if teleportWarningLabel then
        teleportWarningLabel.Text = text
        teleportWarningLabel.Visible = true

        task.spawn(function()
            task.wait(3)
            if teleportWarningLabel and teleportWarningLabel.Text == text then
                teleportWarningLabel.Visible = false
            end
        end)
    end
end

local function teleportToPlace(placeId)
    local ok, err = pcall(function()
        TeleportService:Teleport(placeId, LocalPlayer)
    end)

    if not ok then
        warn("Teleport failed:", err)
        showTeleportWarning("Teleport failed.")
    end
end

local function showMobileConfirmPopup()
    if not mobileConfirmFrame then
        return
    end

    mobileConfirmFrame.Visible = true
    if mobileConfirmFadeCover then
        mobileConfirmFadeCover.BackgroundTransparency = 0
        tweenObject(
            mobileConfirmFadeCover,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
    end
end

local function hideMobileConfirmPopup()
    if mobileConfirmFrame then
        mobileConfirmFrame.Visible = false
    end
end

local function showFirstRunConfigPopup()
    if not firstRunConfigFrame then
        return
    end

    firstRunConfigFrame.Visible = true
    if greenInputBox then
        greenInputBox.Text = tostring(pingColorConfig.greenMax)
    end
    if orangeInputBox then
        orangeInputBox.Text = tostring(pingColorConfig.orangeMax)
    end
    if configStatusLabel then
        configStatusLabel.Text = "Choose your ping color limits."
        configStatusLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
    end

    if firstRunFadeCover then
        firstRunFadeCover.BackgroundTransparency = 0
        tweenObject(
            firstRunFadeCover,
            TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {BackgroundTransparency = 1}
        )
    end
end

local function hideFirstRunConfigPopup()
    if firstRunConfigFrame then
        firstRunConfigFrame.Visible = false
    end
end

local function toggleFirstRunConfigPopup()
    if not firstRunConfigFrame then
        return
    end

    local shouldOpen = not firstRunConfigFrame.Visible

    if shouldOpen then
        if teleportMenu then
            teleportMenu.Visible = false
        end

        if mobileConfirmFrame then
            mobileConfirmFrame.Visible = false
        end

        showFirstRunConfigPopup()
    else
        hideFirstRunConfigPopup()
    end
end

local function createLabeledInput(parent, titleText, placeholderText, yPos)
    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Position = UDim2.new(0, 18, 0, yPos)
    title.Size = UDim2.new(1, -36, 0, 24)
    title.Text = titleText
    title.TextColor3 = Color3.fromRGB(230, 240, 255)
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = parent

    local box = Instance.new("TextBox")
    box.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    box.BackgroundTransparency = 0.12
    box.BorderSizePixel = 0
    box.Position = UDim2.new(0, 18, 0, yPos + 28)
    box.Size = UDim2.new(1, -36, 0, 42)
    box.PlaceholderText = placeholderText
    box.Text = ""
    box.ClearTextOnFocus = false
    box.TextColor3 = Color3.fromRGB(245, 250, 255)
    box.PlaceholderColor3 = Color3.fromRGB(140, 150, 175)
    box.Font = Enum.Font.GothamSemibold
    box.TextSize = 20
    box.Parent = parent
    addCorner(box, 12)
    addStroke(box, Color3.fromRGB(130, 165, 230), 1.2, 0.35)

    return box
end

local function createTopBarAndMenu()
    if topBarGui then
        safeDestroy(topBarGui)
        topBarGui = nil
        pingHolder = nil
        pingLabel = nil
        pingFadeCover = nil
        teleportMenuButton = nil
        teleportButtonFadeCover = nil
        teleportMenu = nil
        teleportMenuFadeCover = nil
        teleportWarningLabel = nil
        mobileConfirmFrame = nil
        mobileConfirmFadeCover = nil
        firstRunConfigFrame = nil
        firstRunFadeCover = nil
        greenInputBox = nil
        orangeInputBox = nil
        configStatusLabel = nil
    end

    topBarGui = Instance.new("ScreenGui")
    topBarGui.Name = "AvatarPreviewTopBar"
    topBarGui.ResetOnSpawn = false
    topBarGui.IgnoreGuiInset = true
    topBarGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    topBarGui.DisplayOrder = 100
    topBarGui.Parent = CoreGui

    local container = Instance.new("Frame")
    container.Name = "TopBarContainer"
    container.AnchorPoint = Vector2.new(0.5, 0)
    container.Position = UDim2.new(0.5, 0, 0, 14)
    container.Size = UDim2.new(0, 510, 0, 54)
    container.BackgroundTransparency = 1
    container.Parent = topBarGui

    local pingHolderVisual = Instance.new("Frame")
    pingHolderVisual.Name = "PingHolderVisual"
    pingHolderVisual.Position = UDim2.new(0, 0, 0, 0)
    pingHolderVisual.Size = UDim2.new(0, 200, 0, 54)
    pingHolderVisual.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    pingHolderVisual.BackgroundTransparency = 0.08
    pingHolderVisual.BorderSizePixel = 0
    pingHolderVisual.Parent = container
    addCorner(pingHolderVisual, 14)
    addStroke(pingHolderVisual, Color3.fromRGB(120, 160, 255), 1.4, 0.35)
    addGradient(pingHolderVisual, Color3.fromRGB(22, 24, 35), Color3.fromRGB(16, 18, 26), 90)

    pingHolder = Instance.new("TextButton")
    pingHolder.Name = "PingHolder"
    pingHolder.Position = UDim2.new(0, 0, 0, 0)
    pingHolder.Size = UDim2.new(0, 200, 0, 54)
    pingHolder.BackgroundTransparency = 1
    pingHolder.BorderSizePixel = 0
    pingHolder.Text = ""
    pingHolder.AutoButtonColor = false
    pingHolder.Parent = container

    pingLabel = Instance.new("TextLabel")
    pingLabel.Name = "PingLabel"
    pingLabel.BackgroundTransparency = 1
    pingLabel.Size = UDim2.new(1, -16, 1, 0)
    pingLabel.Position = UDim2.new(0, 8, 0, 0)
    pingLabel.TextColor3 = Color3.fromRGB(230, 240, 255)
    pingLabel.TextStrokeTransparency = 0.85
    pingLabel.Font = Enum.Font.GothamBold
    pingLabel.TextSize = 24
    pingLabel.Text = "Ping: ..."
    pingLabel.Parent = pingHolderVisual

    pingFadeCover = createFadeCover(pingHolderVisual, Color3.fromRGB(18, 20, 28), 20, 14)

    trackConnection(pingHolder.MouseButton1Click:Connect(function()
        if not previewsVisible then
            return
        end

        if pingFadeCover then
            pingFadeCover.BackgroundTransparency = 0.55
            tweenObject(
                pingFadeCover,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {BackgroundTransparency = 1}
            )
        end

        toggleFirstRunConfigPopup()

        task.spawn(function()
            refreshAllDisplayedValues()
        end)
    end))

    local teleportButtonHolder = Instance.new("Frame")
    teleportButtonHolder.Name = "TeleportButtonHolder"
    teleportButtonHolder.Position = UDim2.new(0, 214, 0, 0)
    teleportButtonHolder.Size = UDim2.new(0, 296, 0, 54)
    teleportButtonHolder.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
    teleportButtonHolder.BackgroundTransparency = 0.08
    teleportButtonHolder.BorderSizePixel = 0
    teleportButtonHolder.Parent = container
    addCorner(teleportButtonHolder, 14)
    addStroke(teleportButtonHolder, Color3.fromRGB(120, 160, 255), 1.4, 0.35)
    addGradient(teleportButtonHolder, Color3.fromRGB(22, 24, 35), Color3.fromRGB(16, 18, 26), 90)

    teleportMenuButton = Instance.new("TextButton")
    teleportMenuButton.Name = "TeleportMenuButton"
    teleportMenuButton.Size = UDim2.new(1, 0, 1, 0)
    teleportMenuButton.Position = UDim2.new(0, 0, 0, 0)
    teleportMenuButton.BackgroundTransparency = 1
    teleportMenuButton.BorderSizePixel = 0
    teleportMenuButton.Text = ""
    teleportMenuButton.AutoButtonColor = false
    teleportMenuButton.Parent = teleportButtonHolder

    local teleportMenuButtonLabel = Instance.new("TextLabel")
    teleportMenuButtonLabel.Name = "TeleportMenuButtonLabel"
    teleportMenuButtonLabel.BackgroundTransparency = 1
    teleportMenuButtonLabel.Size = UDim2.new(1, -16, 1, 0)
    teleportMenuButtonLabel.Position = UDim2.new(0, 8, 0, 0)
    teleportMenuButtonLabel.Text = "Open Teleport Menu"
    teleportMenuButtonLabel.TextColor3 = Color3.fromRGB(230, 240, 255)
    teleportMenuButtonLabel.TextStrokeTransparency = 0.85
    teleportMenuButtonLabel.Font = Enum.Font.GothamBold
    teleportMenuButtonLabel.TextSize = 24
    teleportMenuButtonLabel.Parent = teleportMenuButton

    teleportButtonFadeCover = nil

    teleportMenu = Instance.new("Frame")
    teleportMenu.Name = "TeleportMenu"
    teleportMenu.AnchorPoint = Vector2.new(0.5, 0)
    teleportMenu.Position = UDim2.new(0.5, 0, 0, 78)
    teleportMenu.Size = UDim2.new(0, 510, 0, 334)
    teleportMenu.BackgroundColor3 = Color3.fromRGB(17, 19, 27)
    teleportMenu.BackgroundTransparency = 0.08
    teleportMenu.BorderSizePixel = 0
    teleportMenu.Visible = false
    teleportMenu.Parent = topBarGui
    addCorner(teleportMenu, 16)
    addStroke(teleportMenu, Color3.fromRGB(120, 150, 255), 1.4, 0.35)
    addGradient(teleportMenu, Color3.fromRGB(24, 28, 40), Color3.fromRGB(14, 16, 24), 90)

    local menuTitle = Instance.new("TextLabel")
    menuTitle.Name = "MenuTitle"
    menuTitle.BackgroundTransparency = 1
    menuTitle.Position = UDim2.new(0, 14, 0, 10)
    menuTitle.Size = UDim2.new(1, -28, 0, 28)
    menuTitle.Text = "Teleport Menu"
    menuTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
    menuTitle.Font = Enum.Font.GothamBold
    menuTitle.TextSize = 24
    menuTitle.TextXAlignment = Enum.TextXAlignment.Left
    menuTitle.Parent = teleportMenu

    local divider = Instance.new("Frame")
    divider.BackgroundColor3 = Color3.fromRGB(95, 115, 170)
    divider.BackgroundTransparency = 0.45
    divider.BorderSizePixel = 0
    divider.Position = UDim2.new(0, 14, 0, 44)
    divider.Size = UDim2.new(1, -28, 0, 1)
    divider.Parent = teleportMenu

    local function createMenuButton(text, yPos)
        local button = Instance.new("TextButton")
        button.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
        button.BackgroundTransparency = 0.12
        button.BorderSizePixel = 0
        button.Size = UDim2.new(1, -28, 0, 42)
        button.Position = UDim2.new(0, 14, 0, yPos)
        button.Text = text
        button.TextColor3 = Color3.fromRGB(240, 245, 255)
        button.Font = Enum.Font.GothamSemibold
        button.TextSize = 20
        button.AutoButtonColor = false
        button.Parent = teleportMenu
        addCorner(button, 12)
        addStroke(button, Color3.fromRGB(130, 165, 230), 1.3, 0.22)
        return button
    end

    local hubButton = createMenuButton("Hub", 58)
    local mobileButton = createMenuButton("Mobile Hub", 106)
    local ffaButton = createMenuButton("FFA", 154)
    local gunGameButton = createMenuButton("Gun Game", 202)
    local tdmButton = createMenuButton("Team Deathmatch", 250)

    teleportWarningLabel = Instance.new("TextLabel")
    teleportWarningLabel.Name = "TeleportWarning"
    teleportWarningLabel.BackgroundTransparency = 1
    teleportWarningLabel.Position = UDim2.new(0, 14, 1, -26)
    teleportWarningLabel.Size = UDim2.new(1, -28, 0, 22)
    teleportWarningLabel.Text = ""
    teleportWarningLabel.TextColor3 = Color3.fromRGB(255, 210, 140)
    teleportWarningLabel.Font = Enum.Font.Gotham
    teleportWarningLabel.TextSize = 16
    teleportWarningLabel.TextXAlignment = Enum.TextXAlignment.Left
    teleportWarningLabel.Visible = false
    teleportWarningLabel.Parent = teleportMenu

    teleportMenuFadeCover = createFadeCover(teleportMenu, Color3.fromRGB(17, 19, 27), 20, 16)

    mobileConfirmFrame = Instance.new("Frame")
    mobileConfirmFrame.Name = "MobileConfirmFrame"
    mobileConfirmFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mobileConfirmFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mobileConfirmFrame.Size = UDim2.new(0, 390, 0, 180)
    mobileConfirmFrame.BackgroundColor3 = Color3.fromRGB(17, 19, 27)
    mobileConfirmFrame.BackgroundTransparency = 0.04
    mobileConfirmFrame.BorderSizePixel = 0
    mobileConfirmFrame.Visible = false
    mobileConfirmFrame.Parent = topBarGui
    addCorner(mobileConfirmFrame, 16)
    addStroke(mobileConfirmFrame, Color3.fromRGB(120, 150, 255), 1.4, 0.35)
    addGradient(mobileConfirmFrame, Color3.fromRGB(24, 28, 40), Color3.fromRGB(14, 16, 24), 90)

    local mobileConfirmTitle = Instance.new("TextLabel")
    mobileConfirmTitle.Name = "MobileConfirmTitle"
    mobileConfirmTitle.BackgroundTransparency = 1
    mobileConfirmTitle.Position = UDim2.new(0, 14, 0, 12)
    mobileConfirmTitle.Size = UDim2.new(1, -28, 0, 28)
    mobileConfirmTitle.Text = "Mobile Hub Confirmation"
    mobileConfirmTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
    mobileConfirmTitle.Font = Enum.Font.GothamBold
    mobileConfirmTitle.TextSize = 22
    mobileConfirmTitle.TextXAlignment = Enum.TextXAlignment.Left
    mobileConfirmTitle.Parent = mobileConfirmFrame

    local mobileConfirmDivider = Instance.new("Frame")
    mobileConfirmDivider.BackgroundColor3 = Color3.fromRGB(95, 115, 170)
    mobileConfirmDivider.BackgroundTransparency = 0.45
    mobileConfirmDivider.BorderSizePixel = 0
    mobileConfirmDivider.Position = UDim2.new(0, 14, 0, 46)
    mobileConfirmDivider.Size = UDim2.new(1, -28, 0, 1)
    mobileConfirmDivider.Parent = mobileConfirmFrame

    local mobileConfirmText = Instance.new("TextLabel")
    mobileConfirmText.Name = "MobileConfirmText"
    mobileConfirmText.BackgroundTransparency = 1
    mobileConfirmText.Position = UDim2.new(0, 14, 0, 58)
    mobileConfirmText.Size = UDim2.new(1, -28, 0, 48)
    mobileConfirmText.Text = "You need to use device spoofer."
    mobileConfirmText.TextColor3 = Color3.fromRGB(230, 240, 255)
    mobileConfirmText.Font = Enum.Font.GothamSemibold
    mobileConfirmText.TextSize = 22
    mobileConfirmText.TextWrapped = true
    mobileConfirmText.TextXAlignment = Enum.TextXAlignment.Left
    mobileConfirmText.TextYAlignment = Enum.TextYAlignment.Top
    mobileConfirmText.Parent = mobileConfirmFrame

    local yesButton = Instance.new("TextButton")
    yesButton.Name = "YesButton"
    yesButton.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    yesButton.BackgroundTransparency = 0.12
    yesButton.BorderSizePixel = 0
    yesButton.Position = UDim2.new(0, 14, 1, -56)
    yesButton.Size = UDim2.new(0.5, -21, 0, 42)
    yesButton.Text = "omg i know bruh"
    yesButton.TextColor3 = Color3.fromRGB(240, 245, 255)
    yesButton.Font = Enum.Font.GothamSemibold
    yesButton.TextSize = 20
    yesButton.AutoButtonColor = false
    yesButton.Parent = mobileConfirmFrame
    addCorner(yesButton, 12)
    addStroke(yesButton, Color3.fromRGB(90, 110, 160), 1, 0.55)

    local noButton = Instance.new("TextButton")
    noButton.Name = "NoButton"
    noButton.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    noButton.BackgroundTransparency = 0.12
    noButton.BorderSizePixel = 0
    noButton.Position = UDim2.new(0.5, 7, 1, -56)
    noButton.Size = UDim2.new(0.5, -21, 0, 42)
    noButton.Text = "wait fr? nevermind ig"
    noButton.TextColor3 = Color3.fromRGB(240, 245, 255)
    noButton.Font = Enum.Font.GothamSemibold
    noButton.TextSize = 20
    noButton.AutoButtonColor = false
    noButton.Parent = mobileConfirmFrame
    addCorner(noButton, 12)
    addStroke(noButton, Color3.fromRGB(90, 110, 160), 1, 0.55)

    mobileConfirmFadeCover = createFadeCover(mobileConfirmFrame, Color3.fromRGB(17, 19, 27), 20, 16)

    firstRunConfigFrame = Instance.new("Frame")
    firstRunConfigFrame.Name = "FirstRunConfigFrame"
    firstRunConfigFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    firstRunConfigFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    firstRunConfigFrame.Size = UDim2.new(0, 470, 0, 340)
    firstRunConfigFrame.BackgroundColor3 = Color3.fromRGB(17, 19, 27)
    firstRunConfigFrame.BackgroundTransparency = 0.04
    firstRunConfigFrame.BorderSizePixel = 0
    firstRunConfigFrame.Visible = false
    firstRunConfigFrame.Parent = topBarGui
    addCorner(firstRunConfigFrame, 16)
    addStroke(firstRunConfigFrame, Color3.fromRGB(120, 150, 255), 1.4, 0.35)
    addGradient(firstRunConfigFrame, Color3.fromRGB(24, 28, 40), Color3.fromRGB(14, 16, 24), 90)

    local cfgTitle = Instance.new("TextLabel")
    cfgTitle.Name = "ConfigTitle"
    cfgTitle.BackgroundTransparency = 1
    cfgTitle.Position = UDim2.new(0, 18, 0, 12)
    cfgTitle.Size = UDim2.new(1, -36, 0, 30)
    cfgTitle.Text = "First Time Ping Setup"
    cfgTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
    cfgTitle.Font = Enum.Font.GothamBold
    cfgTitle.TextSize = 24
    cfgTitle.TextXAlignment = Enum.TextXAlignment.Left
    cfgTitle.Parent = firstRunConfigFrame

    local cfgDivider = Instance.new("Frame")
    cfgDivider.BackgroundColor3 = Color3.fromRGB(95, 115, 170)
    cfgDivider.BackgroundTransparency = 0.45
    cfgDivider.BorderSizePixel = 0
    cfgDivider.Position = UDim2.new(0, 18, 0, 48)
    cfgDivider.Size = UDim2.new(1, -36, 0, 1)
    cfgDivider.Parent = firstRunConfigFrame

    local cfgDesc = Instance.new("TextLabel")
    cfgDesc.BackgroundTransparency = 1
    cfgDesc.Position = UDim2.new(0, 18, 0, 60)
    cfgDesc.Size = UDim2.new(1, -36, 0, 42)
    cfgDesc.Text = "Choose the highest ping that should count as green and orange. Anything above orange becomes red."
    cfgDesc.TextColor3 = Color3.fromRGB(210, 225, 245)
    cfgDesc.Font = Enum.Font.Gotham
    cfgDesc.TextSize = 16
    cfgDesc.TextWrapped = true
    cfgDesc.TextXAlignment = Enum.TextXAlignment.Left
    cfgDesc.TextYAlignment = Enum.TextYAlignment.Top
    cfgDesc.Parent = firstRunConfigFrame

    greenInputBox = createLabeledInput(firstRunConfigFrame, "Green up to (ms)", "Example: 80", 112)
    orangeInputBox = createLabeledInput(firstRunConfigFrame, "Orange up to (ms)", "Example: 140", 192)

    configStatusLabel = Instance.new("TextLabel")
    configStatusLabel.BackgroundTransparency = 1
    configStatusLabel.Position = UDim2.new(0, 18, 1, -76)
    configStatusLabel.Size = UDim2.new(1, -36, 0, 22)
    configStatusLabel.Text = ""
    configStatusLabel.TextColor3 = Color3.fromRGB(200, 220, 255)
    configStatusLabel.Font = Enum.Font.Gotham
    configStatusLabel.TextSize = 15
    configStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    configStatusLabel.Parent = firstRunConfigFrame

    local saveConfigButton = Instance.new("TextButton")
    saveConfigButton.Name = "SaveConfigButton"
    saveConfigButton.BackgroundColor3 = Color3.fromRGB(10, 12, 18)
    saveConfigButton.BackgroundTransparency = 0.12
    saveConfigButton.BorderSizePixel = 0
    saveConfigButton.Position = UDim2.new(0, 18, 1, -48)
    saveConfigButton.Size = UDim2.new(1, -36, 0, 36)
    saveConfigButton.Text = "Save Ping Colors"
    saveConfigButton.TextColor3 = Color3.fromRGB(240, 245, 255)
    saveConfigButton.Font = Enum.Font.GothamSemibold
    saveConfigButton.TextSize = 18
    saveConfigButton.AutoButtonColor = false
    saveConfigButton.Parent = firstRunConfigFrame
    addCorner(saveConfigButton, 12)
    addStroke(saveConfigButton, Color3.fromRGB(130, 165, 230), 1.2, 0.25)

    firstRunFadeCover = createFadeCover(firstRunConfigFrame, Color3.fromRGB(17, 19, 27), 20, 16)

    trackConnection(teleportMenuButton.MouseButton1Click:Connect(function()
        if not previewsVisible then
            return
        end

        if firstRunConfigFrame and firstRunConfigFrame.Visible then
            return
        end

        if mobileConfirmFrame then
            mobileConfirmFrame.Visible = false
        end

        teleportMenu.Visible = not teleportMenu.Visible
        if teleportMenu.Visible then
            teleportMenuFadeCover.BackgroundTransparency = 0
            tweenObject(
                teleportMenuFadeCover,
                TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                {BackgroundTransparency = 1}
            )
        end
    end))

    trackConnection(hubButton.MouseButton1Click:Connect(function()
        teleportToPlace(HUB_ID)
    end))

    trackConnection(mobileButton.MouseButton1Click:Connect(function()
        showMobileConfirmPopup()
    end))

    trackConnection(ffaButton.MouseButton1Click:Connect(function()
        teleportToPlace(FFA_ID)
    end))

    trackConnection(gunGameButton.MouseButton1Click:Connect(function()
        teleportToPlace(GUN_GAME_ID)
    end))

    trackConnection(tdmButton.MouseButton1Click:Connect(function()
        teleportToPlace(TEAM_DEATHMATCH_ID)
    end))

    trackConnection(yesButton.MouseButton1Click:Connect(function()
        hideMobileConfirmPopup()
        teleportToPlace(MOBILE_SERVER_ID)
    end))

    trackConnection(noButton.MouseButton1Click:Connect(function()
        hideMobileConfirmPopup()
        showTeleportWarning("Mobile teleport cancelled.")
    end))

    trackConnection(saveConfigButton.MouseButton1Click:Connect(function()
        local greenValue = clampNumber(greenInputBox and greenInputBox.Text, 1, 9999, nil)
        local orangeValue = clampNumber(orangeInputBox and orangeInputBox.Text, 1, 9999, nil)

        if not greenValue or not orangeValue then
            if configStatusLabel then
                configStatusLabel.Text = "Enter valid numbers for both values."
                configStatusLabel.TextColor3 = Color3.fromRGB(255, 140, 140)
            end
            return
        end

        if orangeValue <= greenValue then
            if configStatusLabel then
                configStatusLabel.Text = "Orange must be greater than green."
                configStatusLabel.TextColor3 = Color3.fromRGB(255, 140, 140)
            end
            return
        end

        pingColorConfig.greenMax = greenValue
        pingColorConfig.orangeMax = orangeValue

        local saved = savePingConfig()
        updatePingDisplay()

        if configStatusLabel then
            if saved then
                configStatusLabel.Text = "Saved successfully."
                configStatusLabel.TextColor3 = Color3.fromRGB(120, 255, 140)
            else
                configStatusLabel.Text = "Saved for this session only. Executor file API missing."
                configStatusLabel.TextColor3 = Color3.fromRGB(255, 190, 90)
            end
        end

        task.delay(0.6, function()
            hideFirstRunConfigPopup()
        end)
    end))

    updatePingDisplay()
end

local function setTopBarVisibleAnimated(visible)
    if not topBarGui then
        return
    end

    local info = TweenInfo.new(TOGGLE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    if visible then
        topBarGui.Enabled = true

        if pingFadeCover then
            pingFadeCover.BackgroundTransparency = 0
            tweenObject(pingFadeCover, info, {BackgroundTransparency = 1})
        end

        if teleportMenu.Visible and teleportMenuFadeCover then
            teleportMenuFadeCover.BackgroundTransparency = 0
            tweenObject(teleportMenuFadeCover, info, {BackgroundTransparency = 1})
        end

        if mobileConfirmFrame and mobileConfirmFrame.Visible and mobileConfirmFadeCover then
            mobileConfirmFadeCover.BackgroundTransparency = 0
            tweenObject(mobileConfirmFadeCover, info, {BackgroundTransparency = 1})
        end

        if firstRunConfigFrame and firstRunConfigFrame.Visible and firstRunFadeCover then
            firstRunFadeCover.BackgroundTransparency = 0
            tweenObject(firstRunFadeCover, info, {BackgroundTransparency = 1})
        end

        updatePingDisplay()
    else
        local pending = 0

        if pingFadeCover then
            pending = pending + 1
            pingFadeCover.BackgroundTransparency = 1
            local tween = tweenObject(pingFadeCover, info, {BackgroundTransparency = 0})
            task.spawn(function()
                tween.Completed:Wait()
                pending = pending - 1
                if pending <= 0 and not previewsVisible and topBarGui then
                    topBarGui.Enabled = false
                end
            end)
        end

        if teleportMenu then
            teleportMenu.Visible = false
        end

        if mobileConfirmFrame then
            mobileConfirmFrame.Visible = false
        end

        if firstRunConfigFrame then
            firstRunConfigFrame.Visible = false
        end

        if pending == 0 and topBarGui then
            topBarGui.Enabled = false
        end
    end
end

--========================================================================================================================================================================================================================================================
-- 5) RANK / AVATAR VALUE HELPERS
--========================================================================================================================================================================================================================================================

local function getRankFromElo(elo)
    if elo <= 0 then
        return "Unranked"
    end

    local ranks = {
        {200,  "Bronze I"},    {400,  "Bronze II"},   {600,  "Bronze III"},
        {800,  "Silver I"},    {1000, "Silver II"},   {1200, "Silver III"},
        {1400, "Gold I"},      {1600, "Gold II"},     {1800, "Gold III"},
        {2000, "Platinum I"},  {2200, "Platinum II"}, {2400, "Platinum III"},
        {2600, "Diamond I"},   {2800, "Diamond II"},  {3000, "Diamond III"},
        {3200, "Onyx I"},      {3400, "Onyx II"},     {3600, "Onyx III"},
        {12500, "Nemesis"},     {math.huge, "Archnemesis"}
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

--======================================================================================================================================================================================================================================================================================================================
-- 6) CAMERA FITTING
--======================================================================================================================================================================================================================================================================================================================

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

--================================================================================================================================
-- 7) PREVIEW CARDS
--================================================================================================================================

--================================================================================================================================
-- 7) PREVIEW CARDS
--================================================================================================================================

local function findStat(player, names)
    for _, name in ipairs(names) do
        local obj = player:FindFirstChild(name, true)
        if obj then
            return obj
        end
    end
end


local function updateStatsLabel(userId, player)

    local data = activePreviews[userId]
    if not data or not data.StatsLabel then
        return
    end

    local level = "?"
    local streak = "?"
    local rank = "?"
    local value = getAvatarValue(userId)
    local accountAge = "?"

    local levelValue = findStat(player, {"Level","LEVEL","level"})
    local streakValue = findStat(player, {"Win Streak","WinStreak","Streak","winstreak"})

    if levelValue then
        level = tostring(levelValue.Value)
    end

    if streakValue then
        streak = tostring(streakValue.Value)
    end

    local eloValue = findStat(player, {"Current ELO","ELO","Elo"})
    if eloValue then
        rank = getRankFromElo(eloValue.Value)
    end

    local okAge, resultAge = pcall(function()
        return player.AccountAge
    end)

    if okAge then
        accountAge = tostring(resultAge)
    end

    data.StatsLabel.Text = string.format(
        "Level %s   •   Streak %s   •   Rank %s\nValue %dR$   •   Account Age %s days",
        level,
        streak,
        rank,
        value,
        accountAge
    )
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
    uiScale.Parent = root


    local card = Instance.new("Frame")
    card.Size = UDim2.new(1,0,1,0)
    card.BackgroundColor3 = Color3.fromRGB(17,19,27)
    card.BorderSizePixel = 0
    card.Parent = root
    addCorner(card,20)


    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1,-24,0,NAME_HEIGHT)
    nameLabel.Position = UDim2.new(0,12,0,10)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.fromRGB(240,245,255)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 28
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.Text = "@"..player.Name
    nameLabel.Parent = card


    local viewport = Instance.new("ViewportFrame")
    viewport.Size = UDim2.new(1,-24,0,VIEWPORT_HEIGHT)
    viewport.Position = UDim2.new(0,12,0,NAME_HEIGHT+24)
    viewport.BackgroundColor3 = Color3.fromRGB(10,12,18)
    viewport.BorderSizePixel = 0
    viewport.Parent = card
    addCorner(viewport,16)


    local worldModel = Instance.new("WorldModel")
    worldModel.Parent = viewport


    local camera = Instance.new("Camera")
    camera.Parent = viewport
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = 48
    viewport.CurrentCamera = camera


    local label = Instance.new("TextLabel")
    label.Name = "StatsLabel"
    label.Size = UDim2.new(1,-24,0,LABEL_HEIGHT)
    label.Position = UDim2.new(0,12,1,-LABEL_HEIGHT-12)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(205,255,220)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 27
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
        ScaleObject = uiScale
    }


    task.spawn(function()

        local success, desc = pcall(function()
            return Players:GetHumanoidDescriptionFromUserIdAsync(userId)
        end)

        if not success or not desc then
            label.Text = "Failed to load avatar"
            return
        end


        local modelSuccess, model = pcall(function()
            return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
        end)

        if not modelSuccess or not model then
            label.Text = "Failed to build avatar"
            return
        end


        sanitizePreviewModel(model)

        local rootPart = model:FindFirstChild("HumanoidRootPart")
        if rootPart then
           rootPart.Anchored = true
        end


        local preview = activePreviews[userId]

        if not preview then
            model:Destroy()
            return
        end


        model.Parent = preview.World
        preview.Model = model


        model:PivotTo(CFrame.new(0,0,0) * CFrame.Angles(0,math.pi,0))


        task.wait()


        local cam = preview.Camera
        local cf, size = model:GetBoundingBox()

        local distance = math.max(size.X,size.Y,size.Z) * 2

        cam.CFrame =
            CFrame.new(
                cf.Position + Vector3.new(0,size.Y*0.3,distance),
                cf.Position + Vector3.new(0,size.Y*0.3,0)
            )


        updateStatsLabel(userId,player)

    end)


    task.spawn(function()

        while activePreviews[userId] and not shuttingDown do

            if previewsVisible then
                updateStatsLabel(userId,player)
            end

            task.wait(2)

        end

    end)

end
--========================================================================================================================================================================================================================================================
-- 8) AUTO LAYOUT
--========================================================================================================================================================================================================================================================

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

--========================================================================================================================================================================================================================================================
-- 9) TOGGLE ANIMATION
--========================================================================================================================================================================================================================================================

local function setPreviewsVisibleAnimated(visible)
    local info = TweenInfo.new(TOGGLE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

    if visible then
        for _, data in pairs(activePreviews) do
            if data.Gui then
                data.Gui.Enabled = true
            end
            if data.FadeCover then
                data.FadeCover.BackgroundTransparency = 0
                tweenObject(data.FadeCover, info, {BackgroundTransparency = 1})
            end
        end

        setTopBarVisibleAnimated(true)
        layoutDirty = true
    else
        for _, data in pairs(activePreviews) do
            if data.FadeCover then
                data.FadeCover.BackgroundTransparency = 1
                local tween = tweenObject(data.FadeCover, info, {BackgroundTransparency = 0})

                task.spawn(function()
                    tween.Completed:Wait()
                    if not previewsVisible and data.Gui then
                        data.Gui.Enabled = false
                    end
                end)
            elseif data.Gui then
                data.Gui.Enabled = false
            end
        end

        setTopBarVisibleAnimated(false)
    end
end

--========================================================================================================================================================================================================================================================
-- 10) BACON DETECTOR + NOTIFICATION
--========================================================================================================================================================================================================================================================

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

local function updateNotificationStack(animated)
    for i, notif in ipairs(activeNotifications) do
        if notif and notif.Parent then
            local targetPos = UDim2.new(1, -20, 0, 20 + ((i - 1) * (92 + NOTIFICATION_SPACING)))
            if animated then
                TweenService:Create(
                    notif,
                    TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                    {Position = targetPos}
                ):Play()
            else
                notif.Position = targetPos
            end
        end
    end
end

local function showBaconWarning(name, baconType)
    pcall(function()
        local old = CoreGui:FindFirstChild("CustomNotificationContainer")
        if not old then
            local container = Instance.new("ScreenGui")
            container.Name = "CustomNotificationContainer"
            container.ResetOnSpawn = false
            container.IgnoreGuiInset = true
            container.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            container.DisplayOrder = 200
            container.Parent = CoreGui
        end
    end)

    local gui = CoreGui:FindFirstChild("CustomNotificationContainer")
    if not gui then
        gui = Instance.new("ScreenGui")
        gui.Name = "CustomNotificationContainer"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 200
        gui.Parent = CoreGui
    end

    local frame = Instance.new("Frame")
    frame.Name = "NotificationFrame"
    frame.Size = UDim2.new(0, 350, 0, 92)
    frame.AnchorPoint = Vector2.new(1, 0)
    frame.Position = UDim2.new(1, 370, 0, 20)
    frame.BackgroundColor3 = Color3.fromRGB(17, 19, 27)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    addCorner(frame, 14)
    addStroke(frame, Color3.fromRGB(120, 150, 255), 1.4, 0.35)
    addGradient(frame, Color3.fromRGB(24, 28, 40), Color3.fromRGB(14, 16, 24), 90)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, -22, 0, 30)
    title.Position = UDim2.new(0, 12, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = "Bacon Detector"
    title.TextColor3 = Color3.fromRGB(240, 245, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 20
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local message = Instance.new("TextLabel")
    message.Name = "Message"
    message.Size = UDim2.new(1, -22, 0, 42)
    message.Position = UDim2.new(0, 12, 0, 37)
    message.BackgroundTransparency = 1
    message.Text = tostring(name) .. " detected as " .. tostring(baconType)
    message.TextColor3 = Color3.fromRGB(205, 255, 220)
    message.Font = Enum.Font.Gotham
    message.TextSize = 17
    message.TextWrapped = true
    message.TextXAlignment = Enum.TextXAlignment.Left
    message.TextYAlignment = Enum.TextYAlignment.Top
    message.Parent = frame

    table.insert(activeNotifications, frame)
    updateNotificationStack(false)

    local tweenIn = TweenService:Create(
        frame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {Position = UDim2.new(1, -20, 0, 20 + ((#activeNotifications - 1) * (92 + NOTIFICATION_SPACING)))}
    )

    local tweenOut = TweenService:Create(
        frame,
        TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
        {Position = UDim2.new(1, 370, 0, frame.Position.Y.Offset)}
    )

    tweenIn:Play()

    task.spawn(function()
        task.wait(4)

        if not frame or not frame.Parent then
            return
        end

        tweenOut:Play()
        tweenOut.Completed:Wait()

        for i, notif in ipairs(activeNotifications) do
            if notif == frame then
                table.remove(activeNotifications, i)
                break
            end
        end

        safeDestroy(frame)
        updateNotificationStack(true)

        if #activeNotifications == 0 and gui then
            safeDestroy(gui)
        end
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

--========================================================================================================================================================================================================================================================
-- 11) CONNECTIONS / HEARTBEAT / CLEANUP
--========================================================================================================================================================================================================================================================

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

    if input.KeyCode == Enum.KeyCode.K and not toggleBusy then
        toggleBusy = true
        previewsVisible = not previewsVisible

        setPreviewsVisibleAnimated(previewsVisible)

        task.delay(TOGGLE_FADE_TIME + 0.03, function()
            toggleBusy = false
        end)

        if previewsVisible then
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

    if topBarGui then
        safeDestroy(topBarGui)
        topBarGui = nil
        pingHolder = nil
        pingLabel = nil
        pingFadeCover = nil
        teleportMenuButton = nil
        teleportButtonFadeCover = nil
        teleportMenu = nil
        teleportMenuFadeCover = nil
        teleportWarningLabel = nil
        mobileConfirmFrame = nil
        mobileConfirmFadeCover = nil
        firstRunConfigFrame = nil
        firstRunFadeCover = nil
        greenInputBox = nil
        orangeInputBox = nil
        configStatusLabel = nil
    end

    for _, obj in ipairs(CoreGui:GetChildren()) do
        if obj:IsA("ScreenGui") then
            if string.find(obj.Name, "^AvatarPreview_")
                or obj.Name == "CustomNotification"
                or obj.Name == "CustomNotificationContainer"
                or obj.Name == "AvatarPreviewTopBar" then
                safeDestroy(obj)
            end
        end
    end
end

--========================================================================================================================================================================================================================================================
-- STARTUP
--========================================================================================================================================================================================================================================================

local hadSavedConfig = loadPingConfig()

createTopBarAndMenu()
layoutDirty = true
updateAllPreviews()
initialBaconScan()

if not hadSavedConfig then
    task.delay(0.2, function()
        if not shuttingDown then
            showFirstRunConfigPopup()
        end
    end)
end

print("✨ Styled Avatar Previews + Auto Layout + Better Camera Fit + Teleport Menu + Mobile Confirm Popup + Bigger Stats Text + Account Age + Ping + Bacon Detector + Saved Ping Colors + Click Ping Refresh LOADED!")
print("💡 Press K to toggle everything (cards + ping + teleport button + teleport menu + popup)")
