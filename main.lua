local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Cache = {}
local Connections = {}
local Settings = {
    Enabled = true,
    Brightness = 0.5,
    AllyColor = Color3.fromRGB(0, 255, 0),
    EnemyColor = Color3.fromRGB(255, 0, 0)
}

local function RandomString()
    return string.char(math.random(97, 122))..string.char(math.random(97, 122))..math.random(1000, 9999)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = RandomString()
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.ResetOnSpawn = false
if pcall(function() ScreenGui.Parent = CoreGui end) then else ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Name = "Main"
MainFrame.Size = UDim2.new(0, 150, 0, 85)
MainFrame.Position = UDim2.new(0.02, 0, 0.25, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
MainFrame.Active = true
MainFrame.Draggable = true
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 12)

local Gradient = Instance.new("UIGradient", MainFrame)
Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(98, 28, 126)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(37, 11, 46))
})

local BrightnessBox = Instance.new("TextBox", MainFrame)
BrightnessBox.Size = UDim2.new(0, 130, 0, 20)
BrightnessBox.Position = UDim2.new(0.065, 0, 0.12, 0)
BrightnessBox.Text = tostring(Settings.Brightness)
BrightnessBox.PlaceholderText = "0.1 - 1"
BrightnessBox.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
Instance.new("UICorner", BrightnessBox).CornerRadius = UDim.new(0, 6)

local HideButton = Instance.new("TextButton", MainFrame)
HideButton.Size = UDim2.new(0, 130, 0, 20)
HideButton.Position = UDim2.new(0.065, 0, 0.42, 0)
HideButton.Text = "Hide GUI (RCtrl)"
HideButton.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
Instance.new("UICorner", HideButton).CornerRadius = UDim.new(0, 6)

local DestroyButton = Instance.new("TextButton", MainFrame)
DestroyButton.Size = UDim2.new(0, 130, 0, 20)
DestroyButton.Position = UDim2.new(0.065, 0, 0.72, 0)
DestroyButton.Text = "Destroy"
DestroyButton.BackgroundColor3 = Color3.fromRGB(200, 200, 200)
Instance.new("UICorner", DestroyButton).CornerRadius = UDim.new(0, 6)

local function GetColor(model)
    local localTeam = LocalPlayer.Team and LocalPlayer.Team.Name
    
    if model.Parent then
        local folderName = model.Parent.Name
        if localTeam then
            if folderName == localTeam then return Settings.AllyColor end
        else
            local ctFolder = Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild("Counter-Terrorists")
            local tFolder = Workspace:FindFirstChild("Characters") and Workspace.Characters:FindFirstChild("Terrorists")
            
            if ctFolder and ctFolder:FindFirstChild(LocalPlayer.Name) then
                if folderName == "Counter-Terrorists" then return Settings.AllyColor end
            elseif tFolder and tFolder:FindFirstChild(LocalPlayer.Name) then
                if folderName == "Terrorists" then return Settings.AllyColor end
            end
        end
    end
    return Settings.EnemyColor
end

local function AddHighlight(model)
    if not model:IsA("Model") or model.Name == LocalPlayer.Name then return end
    if model:FindFirstChild("OptimizedESP") then return end
    
    model:WaitForChild("HumanoidRootPart", 5)
    
    local hl = Instance.new("Highlight")
    hl.Name = "OptimizedESP"
    hl.FillTransparency = 1 - Settings.Brightness
    hl.OutlineTransparency = 1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = model
    
    for _, v in ipairs(Cache) do
        if v.Model == model then return end
    end
    
    table.insert(Cache, {
        Model = model,
        Highlight = hl
    })
end

local function RemoveFromCache(model)
    for i, v in ipairs(Cache) do
        if v.Model == model then
            table.remove(Cache, i)
            break
        end
    end
end

local charactersFolder = Workspace:WaitForChild("Characters", 10)
if charactersFolder then
    for _, folder in ipairs(charactersFolder:GetChildren()) do
        if folder:IsA("Folder") then
            for _, char in ipairs(folder:GetChildren()) do
                task.spawn(AddHighlight, char)
            end
            
            table.insert(Connections, folder.ChildAdded:Connect(function(char)
                task.spawn(AddHighlight, char)
            end))
            -- Здесь исправлено на ChildRemoved
            table.insert(Connections, folder.ChildRemoved:Connect(RemoveFromCache))
        end
    end
end

table.insert(Connections, RunService.RenderStepped:Connect(function()
    if not Settings.Enabled then return end
    
    local camPos = Camera.CFrame.Position
    local validTargets = {}
    
    for i = #Cache, 1, -1 do
        local entry = Cache[i]
        if entry.Model and entry.Model.Parent and entry.Model.Parent.Parent == charactersFolder then
            local pos = entry.Model.PrimaryPart and entry.Model.PrimaryPart.Position

            if pos then
                entry.Dist = (camPos - pos).Magnitude
                entry.Highlight.FillColor = GetColor(entry.Model)
                entry.Highlight.FillTransparency = 1 - Settings.Brightness
                table.insert(validTargets, entry)
            else
                entry.Highlight.Enabled = false
            end
        else
            if entry.Highlight then entry.Highlight:Destroy() end
            table.remove(Cache, i)
        end
    end
    
    table.sort(validTargets, function(a, b)
        return a.Dist < b.Dist
    end)
    
    for i, entry in ipairs(validTargets) do
        entry.Highlight.Enabled = (i <= 31)
    end
end))

BrightnessBox.FocusLost:Connect(function()
    local num = tonumber(BrightnessBox.Text)
    if num then Settings.Brightness = math.clamp(num, 0, 1) end
end)

local visible = true
local function ToggleUI()
    visible = not visible
    MainFrame.Visible = visible
end

HideButton.MouseButton1Click:Connect(ToggleUI)
table.insert(Connections, UserInputService.InputBegan:Connect(function(io, gp)
    if not gp and io.KeyCode == Enum.KeyCode.RightControl then ToggleUI() end
end))

local confirm = false
DestroyButton.MouseButton1Click:Connect(function()
    if not confirm then
        confirm = true
        DestroyButton.Text = "Confirm?"
        task.delay(2, function() confirm = false DestroyButton.Text = "Destroy" end)
    else
        Settings.Enabled = false
        for _, c in ipairs(Connections) do c:Disconnect() end
        for _, v in ipairs(Cache) do if v.Highlight then v.Highlight:Destroy() end end
        ScreenGui:Destroy()
    end
end)
