local Maid = {}
Maid.__index = Maid

function Maid.new()
	local self = setmetatable({}, Maid)
	self._tasks = {}
	self._isDestroyed = false
	return self
end

function Maid:GiveTask(task)
	if self._isDestroyed then
		warn("[Maid] Попытка добавить задачу в уничтоженный Maid")
		return nil
	end

	if task == nil then
		return nil
	end

	self._tasks[task] = task
	return task
end

function Maid:RemoveTask(task)
	if not task or not self._tasks[task] then
		return
	end

	local t = self._tasks[task]
	self._tasks[task] = nil

	if typeof(t) == "RBXScriptConnection" then
		pcall(function() t:Disconnect() end)
	elseif typeof(t) == "Instance" then
		pcall(function() t:Destroy() end)
	elseif typeof(t) == "function" then
		pcall(t)
	elseif typeof(t) == "table" and t.Destroy then
		pcall(function() t:Destroy() end)
	end
end

function Maid:Cleanup()
	if self._isDestroyed then return end

	for task, _ in pairs(self._tasks) do
		self:RemoveTask(task)
	end

	table.clear(self._tasks)
end

function Maid:Destroy()
	if self._isDestroyed then return end

	self._isDestroyed = true
	self:Cleanup()
	setmetatable(self, nil)
end

local HighlightPool = {}
HighlightPool.__index = HighlightPool

local MAX_HIGHLIGHTS = 250 

function HighlightPool.new(storageLocation)
	local self = setmetatable({}, HighlightPool)
	self._storage = storageLocation
	self._pool = {} 
	self._active = setmetatable({}, {__mode = "k"}) 
	self._brightness = 0.5
	self._isDestroyed = false

	for i = 1, MAX_HIGHLIGHTS do
		local highlight = Instance.new("Highlight")
		highlight.Parent = self._storage
		highlight.OutlineTransparency = 1
		highlight.Enabled = false
		table.insert(self._pool, highlight)
	end

	return self
end

function HighlightPool:Get(target, color)
	if self._isDestroyed then
		return nil
	end

	if not target or not target.Parent then
		return nil
	end

	if self._active[target] then
		self._active[target].FillColor = color
		return self._active[target]
	end

	local highlight = table.remove(self._pool)

	if not highlight then
		highlight = self:_evictLowestPriority()
	end

	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Parent = self._storage
		highlight.OutlineTransparency = 1
	end

	highlight.Adornee = target
	highlight.FillColor = color
	highlight.FillTransparency = 1 - self._brightness
	highlight.Enabled = true

	self._active[target] = highlight

	return highlight
end

function HighlightPool:Return(target)
	if not target or self._isDestroyed then
		return
	end

	local highlight = self._active[target]

	if highlight then
		highlight.Enabled = false
		highlight.Adornee = nil
		self._active[target] = nil

		if #self._pool < MAX_HIGHLIGHTS then
			table.insert(self._pool, highlight)
		else
			pcall(function() highlight:Destroy() end)
		end
	end
end

function HighlightPool:UpdateBrightness(newBrightness)
	if self._isDestroyed then return end

	newBrightness = math.clamp(tonumber(newBrightness) or 0.5, 0.01, 1)
	self._brightness = newBrightness

	for target, highlight in pairs(self._active) do
		if highlight and highlight.Parent then
			highlight.FillTransparency = 1 - newBrightness
		else
			self._active[target] = nil
		end
	end
end

function HighlightPool:SetColor(target, color)
	if not target or self._isDestroyed then return end

	local highlight = self._active[target]

	if highlight and highlight.Parent then
		highlight.FillColor = color
	end
end

function HighlightPool:_evictLowestPriority()
	local target, highlight = next(self._active)

	if target and highlight then
		highlight.Enabled = false
		highlight.Adornee = nil
		self._active[target] = nil
		return highlight
	end

	return nil
end

function HighlightPool:Cleanup()
	if self._isDestroyed then return end

	self._isDestroyed = true

	for target, _ in pairs(self._active) do
		self:Return(target)
	end

	for _, highlight in ipairs(self._pool) do
		pcall(function() highlight:Destroy() end)
	end

	table.clear(self._pool)
	table.clear(self._active)
end

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local mainMaid = Maid.new()

local CONFIG = {
	AllyColor = Color3.fromRGB(0, 255, 0),
	EnemyColor = Color3.fromRGB(255, 0, 0),
	C4Color = Color3.fromRGB(128, 0, 128),
	DefaultBrightness = 0.5,
	MaxSpawnWait = 1,
}

-- Создаём контейнер для хайлайтов
local highlightStorage = Instance.new("Folder")
highlightStorage.Name = "ClientHighlightStorage_" .. LocalPlayer.Name
highlightStorage.Parent = workspace

mainMaid:GiveTask(function()
	if highlightStorage and highlightStorage.Parent then
		highlightStorage:Destroy()
	end
end)

-- Инициализируем пул
local highlightPool = HighlightPool.new(highlightStorage)
mainMaid:GiveTask(function()
	if highlightPool and not highlightPool._isDestroyed then
		highlightPool:Cleanup()
	end
end)

-- Хранилище для Maid'ов каждого игрока
local playerMaids = setmetatable({}, {__mode = "k"}) -- Слабые ссылки на игроков

-- Генерация случайного имени GUI
local function randomGuiName()
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	local name = "GUI_"
	for i = 1, 16 do
		local idx = math.random(1, #chars)
		name = name .. chars:sub(idx, idx)
	end
	return name
end

-- Создание GUI
local screenGui = Instance.new("ScreenGui", PlayerGui)
screenGui.Name = randomGuiName()
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 999999999
screenGui.ResetOnSpawn = false
mainMaid:GiveTask(screenGui)

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
textBox.Text = tostring(CONFIG.DefaultBrightness)
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

-- Проверка готовности персонажа
local function isReady(character)
	return character and character.Parent and
		character:FindFirstChildOfClass("Humanoid") and
		character:FindFirstChild("Head") and
		character:FindFirstChild("HumanoidRootPart")
end

-- Получение игрока по персонажу
local function getPlayer(character)
	return Players:GetPlayerFromCharacter(character)
end

-- Получение цвета в зависимости от команды
local function getTeamColor(player)
	if not player or not player.Parent then
		return CONFIG.EnemyColor
	end

	if not LocalPlayer.Team or not player.Team then
		return CONFIG.EnemyColor
	end

	return (player.Team == LocalPlayer.Team) and CONFIG.AllyColor or CONFIG.EnemyColor
end

-- Подключение хайлайта к персонажу
local function highlightCharacter(character)
	if not isReady(character) or character == LocalPlayer.Character then
		return
	end

	local player = getPlayer(character)
	if not player or not player.Parent then
		return
	end

	-- Создаём Maid для этого игрока, если его ещё нет
	if not playerMaids[player] then
		playerMaids[player] = Maid.new()
	end

	local playerMaid = playerMaids[player]
	if playerMaid._isDestroyed then
		playerMaid = Maid.new()
		playerMaids[player] = playerMaid
	end

	-- Добавляем highlight
	local color = getTeamColor(player)
	highlightPool:Get(character, color)

	-- Слушаем изменение команды
	local teamConnection
	teamConnection = player:GetPropertyChangedSignal("Team"):Connect(function()
		if character and character.Parent then
			highlightPool:SetColor(character, getTeamColor(player))
		end
	end)
	playerMaid:GiveTask(teamConnection)

	-- Слушаем удаление персонажа
	local ancestryConnection
	ancestryConnection = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			highlightPool:Return(character)
			if playerMaids[player] then
				playerMaid:RemoveTask(ancestryConnection)
			end
		end
	end)
	playerMaid:GiveTask(ancestryConnection)

	-- Слушаем смерть персонажа
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local diedConnection
		diedConnection = humanoid.Died:Connect(function()
			task.wait(2)
			if character and character.Parent then
				highlightPool:Return(character)
			end
			if playerMaid then
				playerMaid:RemoveTask(diedConnection)
			end
		end)
		playerMaid:GiveTask(diedConnection)
	end
end

-- Подключение хайлайта к C4
local function highlightC4(c4)
	if not c4 or not c4.Parent then
		return
	end

	local c4Maid = Maid.new()
	mainMaid:GiveTask(c4Maid)

	local function setupHighlight(part)
		if not part or part.ClassName == "Folder" or part.ClassName == "Model" then
			return
		end

		if part:IsA("BasePart") then
			highlightPool:Get(part, CONFIG.C4Color)

			local ancestryConn
			ancestryConn = part.AncestryChanged:Connect(function(_, parent)
				if not parent then
					highlightPool:Return(part)
					c4Maid:RemoveTask(ancestryConn)
				end
			end)
			c4Maid:GiveTask(ancestryConn)
		end
	end

	-- Подсвечиваем все части C4
	if c4:IsA("BasePart") then
		setupHighlight(c4)
	elseif c4:IsA("Model") then
		for _, descendant in ipairs(c4:GetDescendants()) do
			setupHighlight(descendant)
		end
	end

	-- Слушаем добавление новых частей к C4
	local childAddedConn
	childAddedConn = c4.ChildAdded:Connect(function(part)
		setupHighlight(part)
	end)
	c4Maid:GiveTask(childAddedConn)

	-- Очищаем всё при удалении C4
	local c4AncestryConn
	c4AncestryConn = c4.AncestryChanged:Connect(function(_, parent)
		if not parent then
			c4Maid:Cleanup()
			mainMaid:RemoveTask(c4Maid)
		end
	end)
	c4Maid:GiveTask(c4AncestryConn)
end

-- Обработка появления персонажа
local function onCharacterAdded(character)
	if not character or not character.Parent then
		return
	end

	-- Ждём загрузки персонажа с timeout
	local startTime = tick()
	while not isReady(character) and (tick() - startTime) < CONFIG.MaxSpawnWait do
		task.wait(0.05)
	end

	if isReady(character) then
		highlightCharacter(character)
	end
end

-- Обработка нового игрока
local function onPlayerAdded(player)
	if player == LocalPlayer or not player.Parent then
		return
	end

	if not playerMaids[player] then
		playerMaids[player] = Maid.new()
	end

	local playerMaid = playerMaids[player]

	-- Если персонаж уже загружен, обрабатываем его
	if player.Character then
		onCharacterAdded(player.Character)
	end

	-- Слушаем спауны персонажа
	local charAddedConn
	charAddedConn = player.CharacterAdded:Connect(onCharacterAdded)
	playerMaid:GiveTask(charAddedConn)
end

-- Обработка ухода игрока
local function onPlayerRemoving(player)
	if playerMaids[player] then
		local playerMaid = playerMaids[player]

		-- Удаляем highlights для его персонажа
		if player.Character then
			highlightPool:Return(player.Character)
		end

		-- Очищаем все его соединения
		playerMaid:Cleanup()
		playerMaids[player] = nil
	end
end

-- Инициализация для уже существующих игроков
for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then
		task.spawn(function()
			onPlayerAdded(player)
		end)
	end
end

-- Инициализация существующих C4
for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "C4" then
		task.spawn(function()
			highlightC4(child)
		end)
	end
end

-- Подключения к событиям
mainMaid:GiveTask(Players.PlayerAdded:Connect(onPlayerAdded))
mainMaid:GiveTask(Players.PlayerRemoving:Connect(onPlayerRemoving))

mainMaid:GiveTask(workspace.ChildAdded:Connect(function(child)
	if child.Name == "C4" then
		task.spawn(function()
			highlightC4(child)
		end)
	end
end))

-- Обработка изменения яркости
mainMaid:GiveTask(textBox.FocusLost:Connect(function()
	local input = tonumber(textBox.Text)

	if input then
		local brightness = math.clamp(input, 0.01, 1)
		CONFIG.DefaultBrightness = brightness
		highlightPool:UpdateBrightness(brightness)
		textBox.Text = tostring(brightness)
	else
		textBox.Text = tostring(CONFIG.DefaultBrightness)
	end
end))

-- Система скрытия/показа
local hideState = false

local function toggleVisibility()
	hideState = not hideState
	screenGui.Enabled = not hideState

	if hideState then
		highlightStorage.Parent = nil
	else
		highlightStorage.Parent = workspace
	end
end

mainMaid:GiveTask(hideButton.MouseButton1Click:Connect(toggleVisibility))

mainMaid:GiveTask(UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.RightControl then
		toggleVisibility()
	end
end))

-- Обработка уничтожения скрипта
local destroyTimeout = 0
local DESTROY_WAIT_TIME = 5

mainMaid:GiveTask(destroyButton.MouseButton1Click:Connect(function()
	if tick() - destroyTimeout > DESTROY_WAIT_TIME then
		destroyButton.Text = "You sure?"
		destroyTimeout = tick()
	else
		-- Полная очистка
		mainMaid:Destroy()

		for player, maid in pairs(playerMaids) do
			if maid and not maid._isDestroyed then
				maid:Cleanup()
			end
		end

		table.clear(playerMaids)
		screenGui:Destroy()
	end
end))

-- Защита от ошибок при выходе из игры
game:BindToClose(function()
	pcall(function()
		mainMaid:Destroy()
	end)
end)
