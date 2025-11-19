local Players = game:GetService("Players")

local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")



local ally = Color3.fromRGB(0, 255, 0)

local enemy = Color3.fromRGB(255, 0, 0)

local c4Color = Color3.fromRGB(128, 0, 128)

local highlightsEnabled = true

local brightness = 0.5



local function randomGuiName()

	local template = "{xxxx-xxxx-xxxx-xxxx}"

	return template:gsub("x", function()

		return string.char(math.random(48, 57))

	end)

end



local guiName = randomGuiName()



local screenGui = Instance.new("ScreenGui", PlayerGui)

screenGui.Name = guiName

screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

screenGui.DisplayOrder = 999999999

screenGui.ResetOnSpawn = false



local mainFrame = Instance.new("Frame", screenGui)

mainFrame.Name = "Main"

mainFrame.Size = UDim2.new(0, 150, 0, 77)

mainFrame.Position = UDim2.new(0.01, 0, 0.017, 0)

mainFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

mainFrame.ZIndex = 999999999

local gradient = Instance.new("UIGradient", mainFrame)

gradient.Color = ColorSequence.new({

	ColorSequenceKeypoint.new(0, Color3.fromRGB(98, 28, 126)),

	ColorSequenceKeypoint.new(0.314, Color3.fromRGB(66, 19, 81)),

	ColorSequenceKeypoint.new(1, Color3.fromRGB(37, 11, 46)),

})

Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 20)



local textBox = Instance.new("TextBox", mainFrame)

textBox.Size = UDim2.new(0, 127, 0, 24)

textBox.Position = UDim2.new(0.07, 0, 0.1, 0)

textBox.PlaceholderText = "0.01 - 1"

textBox.Text = tostring(brightness)

textBox.BackgroundColor3 = Color3.fromRGB(192, 194, 227)

textBox.Font = Enum.Font.Jura

textBox.TextScaled = true

textBox.ZIndex = 999999999

Instance.new("UICorner", textBox).CornerRadius = UDim.new(0, 15)



local hideButton = Instance.new("TextButton", mainFrame)

hideButton.Name = "Hide"

hideButton.Size = UDim2.new(0, 137, 0, 15)

hideButton.Text = "Hide - RCtrl"

hideButton.Position = UDim2.new(0.036, 0, 0.5, 0)

hideButton.BackgroundColor3 = Color3.fromRGB(192, 194, 227)

hideButton.Font = Enum.Font.Jura

hideButton.TextScaled = true

hideButton.ZIndex = 999999999

Instance.new("UICorner", hideButton).CornerRadius = UDim.new(0, 15)

Instance.new("UIStroke", hideButton).Color = Color3.fromRGB(205, 205, 205)



local destroyButton = Instance.new("TextButton", mainFrame)

destroyButton.Name = "Destroy"

destroyButton.Size = UDim2.new(0, 137, 0, 15)

destroyButton.Text = "Destroy"

destroyButton.Position = UDim2.new(0.036, 0, 0.745, 0)

destroyButton.BackgroundColor3 = Color3.fromRGB(192, 194, 227)

destroyButton.Font = Enum.Font.Jura

destroyButton.TextScaled = true

destroyButton.ZIndex = 999999999

Instance.new("UICorner", destroyButton).CornerRadius = UDim.new(0, 15)

Instance.new("UIStroke", destroyButton).Color = Color3.fromRGB(205, 205, 205)



local function isReady(model)

	return model:FindFirstChildOfClass("Humanoid") and model:FindFirstChild("Head")

end



local function getPlayer(model)

	for _, plr in ipairs(Players:GetPlayers()) do

		if plr.Character == model then

			return plr

		end

	end

end



local function applyBrightness(highlight)

	highlight.FillTransparency = 1 - brightness

end



local function highlight(model)

	if not isReady(model) then return end

	if model == LocalPlayer.Character then return end



	local plr = getPlayer(model)

	if not plr then return end



	local h = model:FindFirstChild("Highlight") or Instance.new("Highlight")

	h.Parent = model

	h.OutlineTransparency = 1

	h.FillColor = (plr.Team == LocalPlayer.Team) and ally or enemy

	applyBrightness(h)



	plr:GetPropertyChangedSignal("Team"):Connect(function()

		h.FillColor = (plr.Team == LocalPlayer.Team) and ally or enemy

	end)

end



local function highlightC4(c4)

	if c4:IsA("BasePart") then

		local h = c4:FindFirstChild("Highlight") or Instance.new("Highlight")

		h.Parent = c4

		h.FillColor = c4Color

		applyBrightness(h)

	elseif c4:IsA("Model") then

		for _, part in ipairs(c4:GetDescendants()) do

			if part:IsA("BasePart") then

				local h = part:FindFirstChild("Highlight") or Instance.new("Highlight")

				h.Parent = part

				h.FillColor = c4Color

				applyBrightness(h)

			end

		end

	end

end



local function updateHighlights(state)

	for _, model in ipairs(workspace:GetDescendants()) do

		if model:FindFirstChild("Highlight") then

			model.Highlight.Enabled = state

		end

	end

end



local function connectModel(model)

	if isReady(model) then

		highlight(model)

	else

		model.ChildAdded:Connect(function()

			if isReady(model) then

				highlight(model)

			end

		end)

	end

end



for _, obj in ipairs(workspace:GetDescendants()) do

	if obj:IsA("Model") then connectModel(obj) end

end



workspace.DescendantAdded:Connect(function(obj)

	if obj:IsA("Model") and obj.Name ~= "C4" then

		connectModel(obj)

	end

end)



workspace.ChildAdded:Connect(function(obj)

    if obj.Name == "C4" then

        highlightC4(obj)

    end

end)



for _, plr in ipairs(Players:GetPlayers()) do

	if plr.Character then connectModel(plr.Character) end

	plr.CharacterAdded:Connect(connectModel)

end



textBox.FocusLost:Connect(function()

	local input = tonumber(textBox.Text)

	if input then

		brightness = math.clamp(input, 0.01, 1)

		for _, h in ipairs(workspace:GetDescendants()) do

			if h:IsA("Highlight") then

				applyBrightness(h)

			end

		end

	else

		textBox.Text = tostring(brightness)

	end

end)



local hideState = false

local function toggleVisibility()

	hideState = not hideState

	screenGui.Enabled = not hideState

	updateHighlights(not hideState and highlightsEnabled)

end



hideButton.MouseButton1Click:Connect(toggleVisibility)



local destroyTimeout = nil

destroyButton.MouseButton1Click:Connect(function()

	if not destroyTimeout then

		destroyButton.Text = "You sure?"

		destroyTimeout = true

		task.delay(5, function()

			if destroyTimeout then

				destroyButton.Text = "Destroy"

				destroyTimeout = nil

			end

		end)

	else

		screenGui:Destroy()

		updateHighlights(false)

	end

end)



UserInputService.InputBegan:Connect(function(input, gameProcessed)

	if input.KeyCode == Enum.KeyCode.RightControl and not gameProcessed then

		toggleVisibility()

	end

end) 
