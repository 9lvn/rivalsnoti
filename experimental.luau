-- OPSEC Cheat Premium - Rivals Optimized (2026)
-- Top bar only draggable • Fixed skeleton & scaling for Rivals • Added part picker dropdown

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Config
local Settings = {
    ESP_Box = false,
    Skeleton = false,
    Health = false,
    Aimbot = false,
    TeamCheck = true,
    VisibleCheck = false,
    ShowFOV = false,
    FOV_Radius = 150,
    Aim_Smooth = 0.35,
    TargetPart = "Head",  -- default
    Kill_Delay = 1.000,
    Smooth = 0.5,
}

-- Target parts list (Rivals-compatible)
local TargetParts = {
    "Head",
    "HumanoidRootPart",
    "UpperTorso",
    "LowerTorso",
    "LeftUpperArm",
    "RightUpperArm",
    "LeftHand",
    "RightHand",
    "LeftUpperLeg",
    "RightUpperLeg"
}

-- ────────────────────────────────────────
-- GUI (your original menu + part picker)
-- ────────────────────────────────────────

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "OPSECCheatPremium"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game:GetService("CoreGui")

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 380, 0, 440) -- taller for dropdown
MainFrame.Position = UDim2.new(0.5, -190, 0.5, -220)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

-- Title Bar (draggable only here)
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 40)
TitleBar.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 1, 0)
Title.Position = UDim2.new(0, 10, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "OPSEC Cheat Premium"
Title.TextColor3 = Color3.new(1, 1, 1)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TitleBar

local Star = Instance.new("TextLabel")
Star.Size = UDim2.new(0, 30, 1, 0)
Star.Position = UDim2.new(1, -35, 0, 0)
Star.BackgroundTransparency = 1
Star.Text = "★"
Star.TextColor3 = Color3.fromRGB(255, 215, 0)
Star.Font = Enum.Font.GothamBold
Star.TextSize = 24
Star.Parent = TitleBar

-- Sidebar & ContentFrame (unchanged)
local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 120, 1, -40)
Sidebar.Position = UDim2.new(0, 0, 0, 40)
Sidebar.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainFrame

local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, -120, 1, -40)
ContentFrame.Position = UDim2.new(0, 120, 0, 40)
ContentFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
ContentFrame.BorderSizePixel = 0
ContentFrame.Parent = MainFrame

-- Categories (unchanged)
local Categories = {
    {Name = "Combat", Icon = "⚔️", Key = "combat"},
    {Name = "Visuals", Icon = "👁️", Key = "visuals"},
    {Name = "Items", Icon = "🗡️", Key = "items"},
    {Name = "Hud", Icon = "📊", Key = "hud"},
}

local CurrentCategory = "combat"
local CategoryFrames = {}

local yOffset = 10
for _, cat in ipairs(Categories) do
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, -10, 0, 38)
    Btn.Position = UDim2.new(0, 5, 0, yOffset)
    Btn.BackgroundColor3 = (cat.Key == CurrentCategory) and Color3.fromRGB(35, 35, 60) or Color3.fromRGB(28, 28, 28)
    Btn.BorderSizePixel = 0
    Btn.Text = cat.Icon .. " " .. cat.Name
    Btn.TextColor3 = Color3.new(1,1,1)
    Btn.Font = Enum.Font.GothamSemibold
    Btn.TextSize = 16
    Btn.TextXAlignment = Enum.TextXAlignment.Left
    Btn.Parent = Sidebar
   
    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 12)
    Padding.Parent = Btn
   
    Btn.MouseButton1Click:Connect(function()
        CurrentCategory = cat.Key
        for _, b in Sidebar:GetChildren() do
            if b:IsA("TextButton") then
                b.BackgroundColor3 = (b.Text:find(cat.Name)) and Color3.fromRGB(35, 35, 60) or Color3.fromRGB(28, 28, 28)
            end
        end
        for name, frame in pairs(CategoryFrames) do
            frame.Visible = (name == cat.Key)
        end
    end)
   
    yOffset = yOffset + 45
end

-- Create category frames
local function CreateCategoryFrame(key)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Visible = (key == CurrentCategory)
    frame.Parent = ContentFrame
    CategoryFrames[key] = frame
    return frame
end

-- Combat page
local CombatFrame = CreateCategoryFrame("combat")
local yCombat = 15

local function AddToggle(parent, label, key, default)
    local tog = Instance.new("TextButton")
    tog.Size = UDim2.new(1, -20, 0, 36)
    tog.Position = UDim2.new(0, 10, 0, yCombat)
    tog.BackgroundColor3 = default and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(60, 60, 60)
    tog.Text = label .. ": " .. (default and "Enabled" or "Disabled")
    tog.TextColor3 = Color3.new(1,1,1)
    tog.Font = Enum.Font.GothamSemibold
    tog.TextSize = 15
    tog.Parent = parent
   
    tog.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        tog.Text = label .. ": " .. (Settings[key] and "Enabled" or "Disabled")
        tog.BackgroundColor3 = Settings[key] and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(60, 60, 60)
    end)
   
    yCombat = yCombat + 45
    return tog
end

AddToggle(CombatFrame, "Aimbot", "Aimbot", Settings.Aimbot)
AddToggle(CombatFrame, "Team Check", "TeamCheck", Settings.TeamCheck)
AddToggle(CombatFrame, "Visible Check (Aimbot)", "VisibleCheck", Settings.VisibleCheck)
AddToggle(CombatFrame, "Show FOV Circle", "ShowFOV", Settings.ShowFOV)

-- Target Part Picker (dropdown)
local TargetPartBtn = Instance.new("TextButton")
TargetPartBtn.Size = UDim2.new(1, -20, 0, 36)
TargetPartBtn.Position = UDim2.new(0, 10, 0, yCombat)
TargetPartBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
TargetPartBtn.Text = "Target Part: " .. Settings.TargetPart
TargetPartBtn.TextColor3 = Color3.new(1,1,1)
TargetPartBtn.Font = Enum.Font.GothamSemibold
TargetPartBtn.TextSize = 15
TargetPartBtn.Parent = CombatFrame
yCombat = yCombat + 45

local DropdownFrame = Instance.new("Frame")
DropdownFrame.Size = UDim2.new(1, -20, 0, 0)
DropdownFrame.Position = UDim2.new(0, 10, 0, yCombat - 5)
DropdownFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
DropdownFrame.BorderSizePixel = 0
DropdownFrame.ClipsDescendants = true
DropdownFrame.Visible = false
DropdownFrame.Parent = CombatFrame

Instance.new("UICorner", DropdownFrame).CornerRadius = UDim.new(0, 6)

local dropdownY = 5
for _, part in ipairs(TargetParts) do
    local Item = Instance.new("TextButton")
    Item.Size = UDim2.new(1, -10, 0, 32)
    Item.Position = UDim2.new(0, 5, 0, dropdownY)
    Item.BackgroundTransparency = 1
    Item.Text = part
    Item.TextColor3 = (part == Settings.TargetPart) and Color3.fromRGB(0, 255, 150) or Color3.new(1,1,1)
    Item.Font = Enum.Font.Gotham
    Item.TextSize = 14
    Item.TextXAlignment = Enum.TextXAlignment.Left
    Item.Parent = DropdownFrame
    
    local Padding = Instance.new("UIPadding")
    Padding.PaddingLeft = UDim.new(0, 12)
    Padding.Parent = Item
    
    Item.MouseButton1Click:Connect(function()
        Settings.TargetPart = part
        TargetPartBtn.Text = "Target Part: " .. part
        for _, child in DropdownFrame:GetChildren() do
            if child:IsA("TextButton") then
                child.TextColor3 = (child.Text == part) and Color3.fromRGB(0, 255, 150) or Color3.new(1,1,1)
            end
        end
        DropdownFrame.Visible = false
        DropdownFrame.Size = UDim2.new(1, -20, 0, 0)
    end)
    
    dropdownY = dropdownY + 32
end

TargetPartBtn.MouseButton1Click:Connect(function()
    if DropdownFrame.Visible then
        DropdownFrame.Visible = false
        DropdownFrame.Size = UDim2.new(1, -20, 0, 0)
    else
        DropdownFrame.Visible = true
        DropdownFrame.Size = UDim2.new(1, -20, 0, dropdownY + 10)
    end
end)

-- Sliders (FOV & Smoothness)
local function AddSlider(parent, label, min, max, default, callback, yPos)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -20, 0, 50)
    frame.Position = UDim2.new(0, 10, 0, yPos)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = label .. ": " .. string.format("%.2f", default)
    lbl.TextColor3 = Color3.new(1,1,1)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 14
    lbl.Parent = frame

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 0, 8)
    bar.Position = UDim2.new(0, 0, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    bar.Parent = frame

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((default - min)/(max - min), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 170, 100)
    fill.Parent = bar

    local dragging = false

    bar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local rel = math.clamp((inp.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
            local val = min + (max - min) * rel
            fill.Size = UDim2.new(rel, 0, 1, 0)
            lbl.Text = label .. ": " .. string.format("%.2f", val)
            callback(val)
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end)
end

AddSlider(CombatFrame, "FOV Radius", 50, 400, Settings.FOV_Radius, function(v) Settings.FOV_Radius = v end, yCombat)
yCombat = yCombat + 55
AddSlider(CombatFrame, "Aim Smoothness", 0.05, 1, Settings.Aim_Smooth, function(v) Settings.Aim_Smooth = v end, yCombat)

-- Visuals page (unchanged)
local VisualsFrame = CreateCategoryFrame("visuals")
local y = 15

local function AddVisualToggle(label, key, default)
    local tog = Instance.new("TextButton")
    tog.Size = UDim2.new(1, -20, 0, 36)
    tog.Position = UDim2.new(0, 10, 0, y)
    tog.BackgroundColor3 = default and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(60, 60, 60)
    tog.Text = label .. ": " .. (default and "Enabled" or "Disabled")
    tog.TextColor3 = Color3.new(1,1,1)
    tog.Font = Enum.Font.Gotham
    tog.TextSize = 14
    tog.Parent = VisualsFrame
   
    tog.MouseButton1Click:Connect(function()
        Settings[key] = not Settings[key]
        tog.Text = label .. ": " .. (Settings[key] and "Enabled" or "Disabled")
        tog.BackgroundColor3 = Settings[key] and Color3.fromRGB(0, 140, 80) or Color3.fromRGB(60, 60, 60)
    end)
   
    y = y + 45
end

AddVisualToggle("ESP Corner Box", "ESP_Box", Settings.ESP_Box)
AddVisualToggle("Skeleton", "Skeleton", Settings.Skeleton)
AddVisualToggle("Health Bar", "Health", Settings.Health)

-- Items & Hud placeholders (unchanged)
local ItemsFrame = CreateCategoryFrame("items")
local KillDelayLabel = Instance.new("TextLabel")
KillDelayLabel.Size = UDim2.new(1, -20, 0, 25)
KillDelayLabel.Position = UDim2.new(0, 10, 0, 15)
KillDelayLabel.BackgroundTransparency = 1
KillDelayLabel.Text = "Kill Delay: " .. Settings.Kill_Delay .. "s"
KillDelayLabel.TextColor3 = Color3.new(1,1,1)
KillDelayLabel.Font = Enum.Font.Gotham
KillDelayLabel.TextSize = 14
KillDelayLabel.Parent = ItemsFrame

local HudFrame = CreateCategoryFrame("hud")
local HudLabel = Instance.new("TextLabel")
HudLabel.Size = UDim2.new(1, -20, 0, 30)
HudLabel.Position = UDim2.new(0, 10, 0, 20)
HudLabel.BackgroundTransparency = 1
HudLabel.Text = "HUD options coming soon..."
HudLabel.TextColor3 = Color3.new(0.7,0.7,0.7)
HudLabel.Font = Enum.Font.Gotham
HudLabel.TextSize = 15
HudLabel.Parent = HudFrame

-- Draggable ONLY on TitleBar
local dragging, dragInput, dragStart, startPos
TitleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPos = MainFrame.Position
        
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

TitleBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then
        local delta = input.Position - dragStart
        MainFrame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end
end)

-- RightShift toggle
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ────────────────────────────────────────
-- ESP + Aimbot (Rivals optimized)
-- ────────────────────────────────────────

local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.Color = Color3.fromRGB(220, 220, 255)
fovCircle.Filled = false
fovCircle.Transparency = 0.65
fovCircle.Visible = false

local Connections = {}

local function IsVisible(part)
    if not Settings.VisibleCheck then return true end
    local dir = (part.Position - Camera.CFrame.Position).Unit * 6000
    local ray = Ray.new(Camera.CFrame.Position, dir)
    local ignore = {LocalPlayer.Character or {}, workspace.CurrentCamera}
    local hit = workspace:FindPartOnRayWithIgnoreList(ray, ignore)
    return hit and hit:IsDescendantOf(part.Parent)
end

local function SetupPlayer(plr)
    if plr == LocalPlayer then return end
    
    local corners = {}
    for i = 1, 8 do
        local line = Drawing.new("Line")
        line.Thickness = 2
        line.Color = Color3.fromRGB(255, 80, 80)
        corners[i] = line
    end
    
    local healthBG = Drawing.new("Line")
    healthBG.Thickness = 4
    healthBG.Color = Color3.fromRGB(0,0,0)
    
    local healthBar = Drawing.new("Line")
    healthBar.Thickness = 2
    healthBar.Color = Color3.fromRGB(0, 255, 0)
    
    Connections[plr] = {Corners = corners, HealthBG = healthBG, Health = healthBar}
end

for _, p in Players:GetPlayers() do SetupPlayer(p) end
Players.PlayerAdded:Connect(SetupPlayer)

Players.PlayerRemoving:Connect(function(plr)
    if Connections[plr] then
        for k, obj in pairs(Connections[plr]) do
            if typeof(obj) == "table" then
                for _, d in pairs(obj) do d:Remove() end
            else
                obj:Remove()
            end
        end
        Connections[plr] = nil
    end
end)

RunService.RenderStepped:Connect(function()
    fovCircle.Visible = Settings.ShowFOV
    fovCircle.Position = Vector2.new(Camera.ViewportSize.X/2, Camera.ViewportSize.Y/2)
    fovCircle.Radius = Settings.FOV_Radius
    
    for plr, data in pairs(Connections) do
        for _, line in pairs(data.Corners) do line.Visible = false end
        data.HealthBG.Visible = false
        data.Health.Visible = false
        
        local char = plr.Character
        if char and char:FindFirstChild("Head") and char:FindFirstChild("Humanoid") and char.Humanoid.Health > 0 then
            if Settings.TeamCheck and plr.Team == LocalPlayer.Team then continue end
            
            local head = char:FindFirstChild("Head")
            local root = char:FindFirstChild("HumanoidRootPart") or head
            local targetPart = char:FindFirstChild(Settings.TargetPart) or head
            local targetPos, onScreen = Camera:WorldToViewportPoint(targetPart.Position)
            
            if onScreen then
                local top = Camera:WorldToViewportPoint((root.CFrame * CFrame.new(0, 3.2, 0)).Position)   -- Rivals offset
                local bottom = Camera:WorldToViewportPoint((root.CFrame * CFrame.new(0, -3.8, 0)).Position) -- Rivals offset
                local height = math.abs(top.Y - bottom.Y)
                local width = height * 0.55  -- better ratio for Rivals
                
                local tl = Vector2.new(targetPos.X - width/2, top.Y)
                local tr = Vector2.new(targetPos.X + width/2, top.Y)
                local bl = Vector2.new(targetPos.X - width/2, bottom.Y)
                local br = Vector2.new(targetPos.X + width/2, bottom.Y)
                
                if Settings.ESP_Box then
                    local len = width * 0.3
                    
                    data.Corners[1].From = tl
                    data.Corners[1].To = Vector2.new(tl.X + len, tl.Y)
                    data.Corners[1].Visible = true
                    
                    data.Corners[2].From = tl
                    data.Corners[2].To = Vector2.new(tl.X, tl.Y + len)
                    data.Corners[2].Visible = true
                    
                    data.Corners[3].From = tr
                    data.Corners[3].To = Vector2.new(tr.X - len, tr.Y)
                    data.Corners[3].Visible = true
                    
                    data.Corners[4].From = tr
                    data.Corners[4].To = Vector2.new(tr.X, tr.Y + len)
                    data.Corners[4].Visible = true
                    
                    data.Corners[5].From = bl
                    data.Corners[5].To = Vector2.new(bl.X + len, bl.Y)
                    data.Corners[5].Visible = true
                    
                    data.Corners[6].From = bl
                    data.Corners[6].To = Vector2.new(bl.X, bl.Y - len)
                    data.Corners[6].Visible = true
                    
                    data.Corners[7].From = br
                    data.Corners[7].To = Vector2.new(br.X - len, br.Y)
                    data.Corners[7].Visible = true
                    
                    data.Corners[8].From = br
                    data.Corners[8].To = Vector2.new(br.X, br.Y - len)
                    data.Corners[8].Visible = true
                end
                
                if Settings.Health then
                    local barHeight = height * 0.9
                    local pct = char.Humanoid.Health / char.Humanoid.MaxHealth
                    local barX = targetPos.X + width/2 + 8
                    
                    data.HealthBG.From = Vector2.new(barX, top.Y)
                    data.HealthBG.To = Vector2.new(barX, top.Y + barHeight)
                    data.HealthBG.Visible = true
                    
                    data.Health.From = Vector2.new(barX, top.Y + barHeight)
                    data.Health.To = Vector2.new(barX, top.Y + barHeight * (1 - pct))
                    data.Health.Visible = true
                end
            end
        end
    end
    
    -- Aimbot (Rivals optimized)
    if Settings.Aimbot and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
        local closest = nil
        local minDist = math.huge
        local mousePos = UserInputService:GetMouseLocation()
        
        for _, plr in Players:GetPlayers() do
            if plr ~= LocalPlayer and plr.Character then
                if Settings.TeamCheck and plr.Team == LocalPlayer.Team then continue end
                
                local part = plr.Character:FindFirstChild(Settings.TargetPart)
                if not part then continue end
                
                local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
                if onScreen then
                    if Settings.VisibleCheck and not IsVisible(part) then continue end
                    
                    local dist = (Vector2.new(pos.X, pos.Y) - mousePos).Magnitude
                    if dist < Settings.FOV_Radius and dist < minDist then
                        minDist = dist
                        closest = part
                    end
                end
            end
        end
        
        if closest then
            local target = Camera:WorldToViewportPoint(closest.Position)
            local current = UserInputService:GetMouseLocation()
            local dx = (target.X - current.X) * Settings.Aim_Smooth
            local dy = (target.Y - current.Y) * Settings.Aim_Smooth
            mousemoverel(dx, dy)
        end
    end
end)

print("OPSEC Cheat Premium - Rivals Optimized")
print("• Top bar only draggable")
print("• Part picker added in Combat tab")
print("• Hold RMB = aimbot | RightShift = toggle menu")
