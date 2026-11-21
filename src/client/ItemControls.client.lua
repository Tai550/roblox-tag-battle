-- ItemControls: アイテム使用ボタン（枠ごとの画面ボタンとキー入力）と、持ち物・効果時間の表示
-- クライアントは「何枠目を使いたい」とサーバーに伝えるだけ。使えるかどうかはサーバーが決める。
--   1枠目: E / 1 キー / ゲームパッド X
--   2枠目: Q / 2 キー / ゲームパッド Y（ダブルアイテム所有者だけ表示）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrandColors = Config.BrandColors
local UILayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UILayout"))
local EdgeMargin = UILayout.EdgeMargin
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
UILayout.ApplySafeArea(gui)
gui.DisplayOrder = 11

local BUTTON_HEIGHT = math.max(70, UILayout.MinTouchSize)
local BUTTON_GAP = 10
local slotButtons = {}

local row = Instance.new("Frame")
row.Name = "ItemSlots"
row.AnchorPoint = Vector2.new(0.5, 1)
row.Position = UDim2.new(0.5, 0, 1, -UILayout.BottomClearance)
row.BackgroundTransparency = 1
row.Parent = gui

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, BUTTON_GAP)
layout.Parent = row

-- 1枠目を右、2枠目をその左に並べる。非表示の枠は列の幅を取らない。
for slot = 1, #Config.ItemSlotKeys do
	local button = Instance.new("TextButton")
	button.Name = "UseItemButton" .. slot
	button.LayoutOrder = -slot
	button.BackgroundColor3 = BrandColors.Secondary
	button.BackgroundTransparency = 0.2
	button.Font = Enum.Font.GothamBold
	button.TextSize = 20
	button.TextColor3 = BrandColors.White
	button.TextWrapped = true
	button.AutoButtonColor = true
	button.Visible = slot <= maxSlots
	button.Parent = row

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 12)
	buttonCorner.Parent = button

	slotButtons[slot] = button
end

local statusLabel = Instance.new("TextLabel")
statusLabel.Name = "EffectStatus"
statusLabel.Size = UDim2.new(1, -2 * EdgeMargin, 0, 66)
statusLabel.Position = UDim2.new(0.5, 0, 1, -UILayout.BottomClearance - BUTTON_HEIGHT - 5)
statusLabel.AnchorPoint = Vector2.new(0.5, 1)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.GothamBold
statusLabel.TextSize = 18
statusLabel.TextColor3 = BrandColors.White
statusLabel.TextStrokeTransparency = 0.4
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextYAlignment = Enum.TextYAlignment.Bottom
statusLabel.Text = ""
statusLabel.Parent = gui

local function resizeRow()
	local width = gui.AbsoluteSize.X
	local available = width - 2 * EdgeMargin
	if UserInputService.TouchEnabled then
		-- 中央に収め、画面の左右を標準操作に空ける。
		available = math.min(available, width * 0.56)
	end
	local slotCount = #slotButtons
	local gaps = (slotCount - 1) * BUTTON_GAP
	local buttonWidth = math.clamp(math.floor((available - gaps) / slotCount), UILayout.MinTouchSize, 190)
	row.Size = UDim2.fromOffset(buttonWidth * slotCount + gaps, BUTTON_HEIGHT)
	for _, button in ipairs(slotButtons) do
		button.Size = UDim2.fromOffset(buttonWidth, BUTTON_HEIGHT)
		button.TextSize = buttonWidth < 150 and 14 or 20
	end
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(resizeRow)
gui.Parent = localPlayer:WaitForChild("PlayerGui")
resizeRow()

---------------------------------------------------------------------
-- 表示の更新
---------------------------------------------------------------------

local function useHint(slot)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "タップで使う"
	end
	return string.format("[%s / %d] で使う", Config.GetSlotKeyLabel(slot), slot)
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
			button.Text = nameLine .. "\n" .. (def.Passive and "落下時に自動で発動" or useHint(slot))
			button.BackgroundColor3 = BrandColors.Primary
			button.TextColor3 = def.Color
		else
			if maxSlots >= 2 then
				button.Text = string.format("%d枠目: なし", slot)
			else
				button.Text = "アイテムなし"
			end
			button.BackgroundColor3 = BrandColors.Secondary
			button.TextColor3 = BrandColors.White
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
	local def = Config.GetItem(heldItems[slot])
	if slot > maxSlots or not def or def.Passive then
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
