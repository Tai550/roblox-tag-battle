-- ItemControls: アイテム使用ボタン（画面のボタンとキー入力）と、持ち物・効果時間の表示
-- クライアントは「使いたい」とサーバーに伝えるだけ。使えるかどうかはサーバーが決める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ItemUpdate = Remotes:WaitForChild("ItemUpdate")
local UseItem = Remotes:WaitForChild("UseItem")

local localPlayer = Players.LocalPlayer

local heldItemId = nil
local dashEndsAt = 0
local shieldEndsAt = 0
local lastRequest = 0

---------------------------------------------------------------------
-- 画面の部品
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ItemHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11

local button = Instance.new("TextButton")
button.Name = "UseItemButton"
button.Size = UDim2.new(0, 190, 0, 70)
button.Position = UDim2.new(1, -20, 1, -110)
button.AnchorPoint = Vector2.new(1, 1)
button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
button.BackgroundTransparency = 0.2
button.Font = Enum.Font.GothamBold
button.TextSize = 20
button.TextColor3 = Color3.new(1, 1, 1)
button.TextWrapped = true
button.AutoButtonColor = true
button.Parent = gui

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 12)
buttonCorner.Parent = button

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "EffectStatus"
statusLabel.Size = UDim2.new(0, 260, 0, 50)
statusLabel.Position = UDim2.new(1, -20, 1, -185)
statusLabel.AnchorPoint = Vector2.new(1, 1)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 18
statusLabel.TextColor3 = Color3.new(1, 1, 1)
statusLabel.TextStrokeTransparency = 0.4
statusLabel.TextXAlignment = Enum.TextXAlignment.Right
statusLabel.TextYAlignment = Enum.TextYAlignment.Bottom
statusLabel.Text = ""
statusLabel.Parent = gui

gui.Parent = localPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- 表示の更新
---------------------------------------------------------------------

local function useHint()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "タップで使う"
	end
	return "[" .. Config.UseItemKeyLabel .. "] で使う"
end

local function refreshButton()
	local def = Config.GetItem(heldItemId)
	if def then
		button.Text = def.DisplayName .. "\n" .. useHint()
		button.BackgroundColor3 = def.Color
		button.TextColor3 = Color3.fromRGB(20, 20, 20)
	else
		button.Text = "アイテムなし"
		button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		button.TextColor3 = Color3.fromRGB(200, 200, 200)
	end
end

local function refreshStatus()
	local now = os.clock()
	local lines = {}
	if dashEndsAt > now then
		table.insert(lines, string.format("ダッシュ中 %.1f秒", dashEndsAt - now))
	end
	if shieldEndsAt > now then
		table.insert(lines, string.format("シールド %.1f秒", shieldEndsAt - now))
	end
	statusLabel.Text = table.concat(lines, "\n")
end

ItemUpdate.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then
		return
	end
	if type(info.HeldItem) == "string" and info.HeldItem ~= "" then
		heldItemId = info.HeldItem
	else
		heldItemId = nil
	end
	local now = os.clock()
	dashEndsAt = now + (tonumber(info.DashTimeLeft) or 0)
	shieldEndsAt = now + (tonumber(info.ShieldTimeLeft) or 0)
	refreshButton()
	refreshStatus()
end)

---------------------------------------------------------------------
-- 使用の入力（ボタンとキー）
---------------------------------------------------------------------

local function requestUse()
	local now = os.clock()
	if now - lastRequest < 0.2 then
		return
	end
	lastRequest = now
	if heldItemId then
		UseItem:FireServer()
	end
end

button.Activated:Connect(requestUse)

local function isUseKey(keyCode)
	for _, key in ipairs(Config.UseItemKeys) do
		if key == keyCode then
			return true
		end
	end
	return false
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return -- チャット入力中などは無視
	end
	if isUseKey(input.KeyCode) then
		requestUse()
	end
end)

refreshButton()

-- 効果の残り時間表示を定期的に更新
while true do
	refreshStatus()
	task.wait(0.1)
end
