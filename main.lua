
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

--==============================================================================
-- КЛАСС HIGHLIGHTPOOL (исправлен с устранением race conditions)
--==============================================================================
local HighlightPool = {}
HighlightPool.__index = HighlightPool

local MAX_HIGHLIGHTS = 250

function HighlightPool.new(storageLocation)
	local self = setmetatable({}, HighlightPool)
	self._storage = storageLocation
	self._pool = {}
	self._active = {} -- ИСПРАВЛЕНИЕ: Используем strong references вместо weak
	self._activeLookup = {} -- Обратный индекс для быстрого поиска
	self._brightness = 0.5
	self._isDestroyed = false
	self._lock = false -- ИСПРАВЛЕНИЕ: Флаг для предотвращения race conditions

	-- Предварительно создаём пул хайлайтов
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

	-- ИСПРАВЛЕНИЕ: Защита от race conditions
	while self._lock do
		task.wait(0.001)
	end
	self._lock = true

	local function unlock()
		self._lock = false
	end

	-- Если уже есть активный highlight для этого target, обновляем цвет
	if self._active[target] then
		self._active[target].FillColor = color
		unlock()
		return self._active[target]
	end

	-- Берём из пула
	local highlight = table.remove(self._pool)

	-- ИСПРАВЛЕНИЕ: Если пула нет, ищем несколько highlights для эвикции
	if not highlight then
		highlight = self:_evictMultiple()
	end

	if not highlight then
		-- На случай крайности - создаём новый
		highlight = Instance.new("Highlight")
		highlight.Parent = self._storage
		highlight.OutlineTransparency = 1
	end

	-- Настраиваем highlight
	highlight.Adornee = target
	highlight.FillColor = color
	highlight.FillTransparency = 1 - self._brightness
	highlight.Enabled = true

	self._active[target] = highlight
	self._activeLookup[highlight] = target

	unlock()
	return highlight
end

function HighlightPool:Return(target)
	if not target or self._isDestroyed then
		return
	end

	while self._lock do
		task.wait(0.001)
	end
	self._lock = true

	local highlight = self._active[target]

	if highlight then
		highlight.Enabled = false
		highlight.Adornee = nil

		self._active[target] = nil
		self._activeLookup[highlight] = nil

		-- Возвращаем в пул
		if #self._pool < MAX_HIGHLIGHTS then
			table.insert(self._pool, highlight)
		else
			pcall(function() highlight:Destroy() end)
		end
	end

	self._lock = false
end

function HighlightPool:UpdateBrightness(newBrightness)
	if self._isDestroyed then return end

	newBrightness = math.clamp(tonumber(newBrightness) or 0.5, 0.01, 1)
	self._brightness = newBrightness

	while self._lock do
		task.wait(0.001)
	end
	self._lock = true

	for target, highlight in pairs(self._active) do
		-- ИСПРАВЛЕНИЕ: Проверяем наличие объекта правильно
		if highlight and highlight.Parent and target and target.Parent then
			highlight.FillTransparency = 1 - newBrightness
		else
			self._active[target] = nil
			if highlight then
				self._activeLookup[highlight] = nil
			end
		end
	end

	self._lock = false
end

function HighlightPool:SetColor(target, color)
	if not target or self._isDestroyed then return end

	while self._lock do
		task.wait(0.001)
	end
	self._lock = true

	local highlight = self._active[target]

	if highlight and highlight.Parent then
		highlight.FillColor = color
	end

	self._lock = false
end

-- ИСПРАВЛЕНИЕ: Эвикция нескольких highlights если нужно
function HighlightPool:_evictMultiple()
	local count = 0
	local maxEvict = 5 -- Пытаемся освободить до 5 highlights

	for target, highlight in pairs(self._active) do
		if count >= maxEvict then break end

		if highlight and target then
			highlight.Enabled = false
			highlight.Adornee = nil
			self._active[target] = nil
			self._activeLookup[highlight] = nil
			table.insert(self._pool, highlight)
			count = count + 1
		end
	end

	return table.remove(self._pool)
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
	table.clear(self._activeLookup)
end

--==============================================================================
-- ОСНОВНОЙ КОД СКРИПТА
--==============================================================================
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Основной Maid для всего скрипта
local mainMaid = Maid.new()

-- Конфигурация
local CONFIG = {
	AllyColor = Color3.fromRGB(0, 255, 0),
	EnemyColor = Color3.fromRGB(255, 0, 0),
	C4Color = Color3.fromRGB(128, 0, 128),
	DefaultBrightness = 0.5,
	MaxSpawnWait = 1,
	MaxRetries = 3,
}

-- Создаём контейнер для хайлайтов с уникальным названием
local highlightStorage = Instance.new("Folder")
highlightStorage.Name = "ClientHighlightStorage_" .. LocalPlayer.UserId .. "_" .. tick()
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

-- Хранилище для Maid'ов каждого игрока (используем strong references)
local playerMaids = {}

-- Генерация случайного имени GUI
local function randomGuiName()
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
	local name = "GUI_"
	for i = 1, 24 do
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

-- ИСПРАВЛЕНИЕ: Добавляем retry механизм для загрузки персонажей
local function highlightCharacter(character)
	if not isReady(character) or character == LocalPlayer.Character then
		return
	end

	local player = getPlayer(character)
	if not player or not player.Parent then
		return
	end

	-- Убеждаемся, что у игрока есть Maid
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
	if not player:FindFirstChild("_ESPTeamConnection") then
		local teamConnection
		teamConnection = player:GetPropertyChangedSignal("Team"):Connect(function()
			if character and character.Parent and player and player.Parent then
				highlightPool:SetColor(character, getTeamColor(player))
			end
		end)
		playerMaid:GiveTask(teamConnection)
	end

	-- Слушаем удаление персонажа
	local ancestryConnection
	ancestryConnection = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			highlightPool:Return(character)
			if playerMaid then
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
			-- ИСПРАВЛЕНИЕ: Проверяем перед возвратом
			task.wait(0.5)
			if character and character.Parent then
				highlightPool:Return(character)
			end
			if playerMaid and not playerMaid._isDestroyed then
				playerMaid:RemoveTask(diedConnection)
			end
		end)
		playerMaid:GiveTask(diedConnection)
	end
end

-- ИСПРАВЛЕНИЕ: Улучшенная загрузка персонажа с retry
local function onCharacterAdded(character)
	if not character or not character.Parent then
		return
	end

	-- Ждём загрузки персонажа с timeout и retries
	local startTime = tick()
	local retries = 0

	while not isReady(character) and retries < CONFIG.MaxRetries do
		if (tick() - startTime) >= CONFIG.MaxSpawnWait then
			retries = retries + 1
			startTime = tick()
		end
		task.wait(0.05)
	end

	if isReady(character) then
		highlightCharacter(character)
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
		if not part or not part.Parent then
			return
		end

		-- ИСПРАВЛЕНИЕ: Правильная проверка типов
		if part:IsA("BasePart") then
			highlightPool:Get(part, CONFIG.C4Color)

			local ancestryConn
			ancestryConn = part.AncestryChanged:Connect(function(_, parent)
				if not parent then
					highlightPool:Return(part)
					if c4Maid and not c4Maid._isDestroyed then
						c4Maid:RemoveTask(ancestryConn)
					end
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
		if c4Maid and not c4Maid._isDestroyed then
			setupHighlight(part)
		end
	end)
	c4Maid:GiveTask(childAddedConn)

	-- Очищаем всё при удалении C4
	local c4AncestryConn
	c4AncestryConn = c4.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if c4Maid and not c4Maid._isDestroyed then
				c4Maid:Cleanup()
			end
			mainMaid:RemoveTask(c4Maid)
		end
	end)
	c4Maid:GiveTask(c4AncestryConn)
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
		if not playerMaid._isDestroyed then
			playerMaid:Cleanup()
		end
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

-- ИСПРАВЛЕНИЕ: Throttling для ChildAdded события
local lastC4Time = 0
local C4_THROTTLE = 0.1

mainMaid:GiveTask(workspace.ChildAdded:Connect(function(child)
	if child.Name == "C4" then
		local now = tick()
		if now - lastC4Time >= C4_THROTTLE then
			lastC4Time = now
			task.spawn(function()
				highlightC4(child)
			end)
		end
	end
end))

-- Обработка изменения яркости с throttling
local lastBrightnessUpdate = 0
local BRIGHTNESS_THROTTLE = 0.2

mainMaid:GiveTask(textBox.FocusLost:Connect(function()
	local now = tick()
	if now - lastBrightnessUpdate < BRIGHTNESS_THROTTLE then
		return
	end
	lastBrightnessUpdate = now

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

-- ИСПРАВЛЕНИЕ: Валидация текстбокса при вводе
mainMaid:GiveTask(textBox:GetPropertyChangedSignal("Text"):Connect(function()
	local text = textBox.Text
	if text:find("[^0-9%.]") then
		textBox.Text = text:gsub("[^0-9%.]", "")
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
		for player, maid in pairs(playerMaids) do
			if maid and not maid._isDestroyed then
				maid:Cleanup()
			end
		end

		table.clear(playerMaids)

		if mainMaid and not mainMaid._isDestroyed then
			mainMaid:Destroy()
		end

		if screenGui and screenGui.Parent then
			screenGui:Destroy()
		end
	end
end))

-- Защита от ошибок при выходе из игры
game:BindToClose(function()
	pcall(function()
		if mainMaid and not mainMaid._isDestroyed then
			mainMaid:Destroy()
		end
	end)
end)
