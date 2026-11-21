-- ItemControls: アイテム使用ボタン（枠ごとの画面ボタンとキー入力）と、持ち物・効果時間の表示
-- クライアントは「何枠目を使いたい」とサーバーに伝えるだけ。使えるかどうかはサーバーが決める。
--   1枠目: ボタン（右）/ E キー / ゲームパッド X
--   2枠目: ボタン（左）/ Q キー / ゲームパッド Y（ダブルアイテム所有者だけ表示）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ItemUpdate = Remotes:WaitForChild("ItemUpdate")
local UseItem = Remotes:WaitForChild("UseItem")

local localPlayer = Players.LocalPlayer

local heldItems = {}        -- 持っているアイテムの Id のリスト（サーバーから届いたもの）
local heldExpireLeft = {}   -- 枠ごとの使用期限の残り秒（サーバーから届いたもの。0 は期限なし）
local expireReceivedAt = 0  -- 使用期限情報を受け取った時刻（残り秒の表示を進めるため）
local maxSlots = Config.BaseItemSlots
local dashEndsAt = 0
local shieldEndsAt = 0
local starEndsAt = 0
local lastRequest = 0

---------------------------------------------------------------------
-- 画面の部品
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ItemHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 11

local BUTTON_WIDTH = 190
local BUTTON_GAP = 10
local slotButtons = {}

-- 1枠目を右下、2枠目をその左に並べる
for slot = 1, #Config.ItemSlotKeys do
	local button = Instance.new("TextButton")
	button.Name = "UseItemButton" .. slot
	button.Size = UDim2.new(0, BUTTON_WIDTH, 0, 70)
	button.Position = UDim2.new(1, -20 - (slot - 1) * (BUTTON_WIDTH + BUTTON_GAP), 1, -110)
	button.AnchorPoint = Vector2.new(1, 1)
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	button.BackgroundTransparency = 0.2
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextWrapped = true
	button.AutoButtonColor = true
	button.Visible = slot <= maxSlots
	button.Parent = gui

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 12)
	buttonCorner.Parent = button

	slotButtons[slot] = button
end

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

local function useHint(slot)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "タップで使う"
	end
	return "[" .. Config.GetSlotKeyLabel(slot) .. "] で使う"
end

-- 枠の使用期限の残り秒（受け取った値から経過分を引いて表示用に進める）
local function expireLeftFor(slot)
	local left = heldExpireLeft[slot] or 0
	if left <= 0 then
		return 0
	end
	return math.max(0, left - (os.clock() - expireReceivedAt))
end

local function refreshButton()
	for slot, button in ipairs(slotButtons) do
		button.Visible = slot <= maxSlots
		local def = Config.GetItem(heldItems[slot])
		if def then
			local nameLine = def.DisplayName
			local expireLeft = expireLeftFor(slot)
			if expireLeft > 0 then
				nameLine = nameLine .. string.format("（あと%d秒）", math.ceil(expireLeft))
			end
			button.Text = nameLine .. "\n" .. useHint(slot)
			button.BackgroundColor3 = def.Color
			button.TextColor3 = Color3.fromRGB(20, 20, 20)
		else
			if maxSlots >= 2 then
				button.Text = string.format("%d枠目: なし", slot)
			else
				button.Text = "アイテムなし"
			end
			button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
			button.TextColor3 = Color3.fromRGB(200, 200, 200)
		end
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
	if starEndsAt > now then
		table.insert(lines, string.format("スター %.1f秒", starEndsAt - now))
	end
	statusLabel.Text = table.concat(lines, "\n")
end

ItemUpdate.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" then
		return
	end
	heldItems = {}
	if type(info.HeldItems) == "table" then
		for index, itemId in ipairs(info.HeldItems) do
			if type(itemId) == "string" then
				heldItems[index] = itemId
			end
		end
	end
	heldExpireLeft = {}
	if type(info.HeldExpireLeft) == "table" then
		for index, left in ipairs(info.HeldExpireLeft) do
			heldExpireLeft[index] = tonumber(left) or 0
		end
	end
	expireReceivedAt = os.clock()
	local slots = tonumber(info.MaxSlots)
	if slots then
		maxSlots = math.clamp(math.floor(slots), 1, #slotButtons)
	end
	local now = os.clock()
	dashEndsAt = now + (tonumber(info.DashTimeLeft) or 0)
	shieldEndsAt = now + (tonumber(info.ShieldTimeLeft) or 0)
	starEndsAt = now + (tonumber(info.StarTimeLeft) or 0)
	refreshButton()
	refreshStatus()
end)

---------------------------------------------------------------------
-- 使用の入力（ボタンとキー）
---------------------------------------------------------------------

local function requestUse(slot)
	local now = os.clock()
	if now - lastRequest < 0.2 then
		return
	end
	if slot > maxSlots or not heldItems[slot] then
		return
	end
	lastRequest = now
	UseItem:FireServer(slot)
end

for slot, button in ipairs(slotButtons) do
	button.Activated:Connect(function()
		requestUse(slot)
	end)
end

-- 押されたキーが何枠目のキーかを返す（どれでもなければ nil）
local function slotForKey(keyCode)
	for slot, keys in ipairs(Config.ItemSlotKeys) do
		for _, key in ipairs(keys) do
			if key == keyCode then
				return slot
			end
		end
	end
	return nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return -- チャット入力中などは無視
	end
	local slot = slotForKey(input.KeyCode)
	if slot then
		requestUse(slot)
	end
end)

refreshButton()

-- 効果の残り時間表示と、使用期限のカウントダウンを定期的に更新
while true do
	refreshStatus()
	refreshButton()
	task.wait(0.1)
end
