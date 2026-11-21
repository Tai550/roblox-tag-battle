-- MatchUI: 試合時間の投票、デッキ構築、縮小エリアの表示をまとめた画面
-- クライアントは「投票したい秒数」「選んだデッキ」をサーバーに伝えるだけ。
-- 集計・検証・判定はすべてサーバーが行う。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateUpdate = Remotes:WaitForChild("StateUpdate")
local DurationVote = Remotes:WaitForChild("DurationVote")
local DeckSelect = Remotes:WaitForChild("DeckSelect")
local DeckUpdate = Remotes:WaitForChild("DeckUpdate")
local ZoneUpdate = Remotes:WaitForChild("ZoneUpdate")

local localPlayer = Players.LocalPlayer

local currentPhase = ""
local myVote = 0            -- 自分が投票した秒数（0 は未投票）
local chosenDuration = Config.DefaultDuration
local selectedDeck = {}     -- デッキ編集用：選んでいるアイテム Id のリスト
local deckPanelOpen = false

---------------------------------------------------------------------
-- 画面の部品
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MatchUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local function makeFrame(name, size, position)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	frame.BackgroundTransparency = 0.3
	frame.Visible = false
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	return frame
end

local function makeLabel(parent, name, size, position, textSize, text)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = Color3.fromRGB(240, 240, 240)
	label.TextStrokeTransparency = 0.4
	label.Text = text or ""
	label.Parent = parent
	return label
end

local function makeButton(parent, name, size, position, text, textSize)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
	button.BackgroundTransparency = 0.15
	button.Font = Enum.Font.GothamBold
	button.TextSize = textSize or 20
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextWrapped = true
	button.AutoButtonColor = true
	button.Text = text
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	return button
end

---------------------------------------------------------------------
-- 投票パネル（インターミッション中だけ表示）
---------------------------------------------------------------------

-- 上部 HUD が段位の1行ぶん高くなったので、その下にずらす
local voteFrame = makeFrame("VotePanel", UDim2.new(0, 460, 0, 120), UDim2.new(0.5, 0, 0, 164))
makeLabel(voteFrame, "Title", UDim2.new(1, -16, 0, 24), UDim2.new(0.5, 0, 0, 6), 18, "試合時間に投票しよう！")
local voteButtons = {}
for index, duration in ipairs(Config.MatchDurations) do
	local button = makeButton(
		voteFrame,
		"Vote" .. duration,
		UDim2.new(0, 130, 0, 56),
		UDim2.new(0.5, (index - 2) * 145, 0, 44),
		"",
		20
	)
	button.Activated:Connect(function()
		myVote = duration
		DurationVote:FireServer(duration)
	end)
	voteButtons[duration] = button
end
local voteStatusLabel = makeLabel(voteFrame, "Status", UDim2.new(1, -16, 0, 20), UDim2.new(0.5, 0, 0, 104), 15, "")

local function refreshVotePanel(state)
	voteFrame.Visible = currentPhase == "Intermission"
	if not voteFrame.Visible then
		return
	end
	local counts = state.VoteCounts or {}
	for _, duration in ipairs(Config.MatchDurations) do
		local button = voteButtons[duration]
		local count = tonumber(counts[tostring(duration)]) or 0
		button.Text = string.format("%d分\n%d票", math.floor(duration / 60), count)
		if duration == myVote then
			button.BackgroundColor3 = Color3.fromRGB(40, 130, 220)
		elseif duration == chosenDuration then
			button.BackgroundColor3 = Color3.fromRGB(120, 100, 40)
		else
			button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
		end
	end
	voteStatusLabel.Text = string.format("今の決定: %d分（同数なら%d分）", math.floor(chosenDuration / 60), math.floor(Config.DefaultDuration / 60))
end

---------------------------------------------------------------------
-- デッキパネル
---------------------------------------------------------------------

local refreshDeckPanel -- デッキパネルの再描画（下で定義。ボタンの処理から使うため先に宣言）

local deckButton = makeButton(gui, "DeckButton", UDim2.new(0, 130, 0, 52), UDim2.new(0, 85, 1, -70), "デッキ", 20)
deckButton.AnchorPoint = Vector2.new(0.5, 1)
deckButton.Visible = true

local deckFrame = makeFrame("DeckPanel", UDim2.new(0, 420, 0, 300), UDim2.new(0.5, 0, 0.5, -150))
makeLabel(deckFrame, "Title", UDim2.new(1, -16, 0, 26), UDim2.new(0.5, 0, 0, 8), 20, "デッキをえらぼう")
local deckInfoLabel = makeLabel(
	deckFrame, "Info", UDim2.new(1, -16, 0, 20), UDim2.new(0.5, 0, 0, 36), 15,
	string.format("ボックスから出るアイテムを%dつ選ぶ", Config.DeckSize)
)

local deckButtons = {}
for index, itemId in ipairs(Config.ItemOrder) do
	local def = Config.Items[itemId]
	local column = (index - 1) % 3
	local row = math.floor((index - 1) / 3)
	local button = makeButton(
		deckFrame,
		"DeckItem" .. itemId,
		UDim2.new(0, 124, 0, 74),
		UDim2.new(0.5, (column - 1) * 136, 0, 66 + row * 84),
		def.DisplayName,
		18
	)
	button.Activated:Connect(function()
		-- 選んでいるものを押したら外す。新しいものは上限まで追加できる
		for i, selectedId in ipairs(selectedDeck) do
			if selectedId == itemId then
				table.remove(selectedDeck, i)
				refreshDeckPanel()
				return
			end
		end
		if #selectedDeck < Config.DeckSize then
			table.insert(selectedDeck, itemId)
		end
		refreshDeckPanel()
	end)
	deckButtons[itemId] = button
end

local deckConfirmButton = makeButton(deckFrame, "Confirm", UDim2.new(0, 180, 0, 48), UDim2.new(0.5, 0, 0, 244), "これにする", 20)
deckConfirmButton.Activated:Connect(function()
	if #selectedDeck == Config.DeckSize then
		DeckSelect:FireServer(selectedDeck)
		deckPanelOpen = false
		deckFrame.Visible = false
	end
end)

refreshDeckPanel = function()
	for itemId, button in pairs(deckButtons) do
		local def = Config.Items[itemId]
		local selected = false
		for _, selectedId in ipairs(selectedDeck) do
			if selectedId == itemId then
				selected = true
				break
			end
		end
		if selected then
			button.BackgroundColor3 = def.Color
			button.TextColor3 = Color3.fromRGB(20, 20, 20)
			button.Text = def.DisplayName .. "\n（選択中）"
		else
			button.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
			button.TextColor3 = Color3.new(1, 1, 1)
			button.Text = def.DisplayName
		end
	end
	deckInfoLabel.Text = string.format(
		"ボックスから出るアイテムを%dつ選ぶ（今 %d/%d）",
		Config.DeckSize, #selectedDeck, Config.DeckSize
	)
	deckConfirmButton.BackgroundColor3 = #selectedDeck == Config.DeckSize
		and Color3.fromRGB(40, 160, 80)
		or Color3.fromRGB(60, 60, 70)
end

deckButton.Activated:Connect(function()
	deckPanelOpen = not deckPanelOpen
	deckFrame.Visible = deckPanelOpen
	if deckPanelOpen then
		DeckSelect:FireServer() -- 引数なし = 今のデッキを送ってもらう
		refreshDeckPanel()
	end
end)

DeckUpdate.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or type(info.Deck) ~= "table" then
		return
	end
	selectedDeck = {}
	for index, itemId in ipairs(info.Deck) do
		if type(itemId) == "string" then
			selectedDeck[index] = itemId
		end
	end
	refreshDeckPanel()
end)

---------------------------------------------------------------------
-- 縮小エリアの表示（ラウンド中）
---------------------------------------------------------------------

local zoneFrame = makeFrame("ZonePanel", UDim2.new(0, 240, 0, 84), UDim2.new(1, -130, 0, 8))
zoneFrame.AnchorPoint = Vector2.new(0.5, 0)
local zoneRadiusLabel = makeLabel(zoneFrame, "Radius", UDim2.new(1, -12, 0, 22), UDim2.new(0.5, 0, 0, 4), 17, "")
local zoneWarnLabel = makeLabel(zoneFrame, "Warn", UDim2.new(1, -12, 0, 22), UDim2.new(0.5, 0, 0, 26), 17, "")
zoneWarnLabel.TextColor3 = Color3.fromRGB(255, 90, 90)

local staminaBack = Instance.new("Frame")
staminaBack.Name = "StaminaBack"
staminaBack.Size = UDim2.new(1, -20, 0, 16)
staminaBack.Position = UDim2.new(0.5, 0, 0, 56)
staminaBack.AnchorPoint = Vector2.new(0.5, 0)
staminaBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
staminaBack.Parent = zoneFrame

local staminaFill = Instance.new("Frame")
staminaFill.Name = "StaminaFill"
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = Color3.fromRGB(90, 220, 120)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaBack

ZoneUpdate.OnClientEvent:Connect(function(info)
	if type(info) ~= "table" or currentPhase ~= "Round" then
		zoneFrame.Visible = false
		return
	end
	zoneFrame.Visible = true
	local radius = tonumber(info.Radius) or 0
	local stamina = tonumber(info.Stamina) or 0
	local maxStamina = tonumber(info.MaxStamina) or Config.ZoneStaminaMax
	zoneRadiusLabel.Text = string.format("エリアの大きさ: %d", math.floor(radius))
	if info.IsOutside then
		zoneWarnLabel.Text = "エリアの外！ もどって！"
	else
		zoneWarnLabel.Text = "エリアの中"
	end
	local ratio = maxStamina > 0 and math.clamp(stamina / maxStamina, 0, 1) or 0
	staminaFill.Size = UDim2.new(ratio, 0, 1, 0)
	staminaFill.BackgroundColor3 = ratio > 0.35 and Color3.fromRGB(90, 220, 120) or Color3.fromRGB(255, 90, 90)
end)

---------------------------------------------------------------------
-- 状態の受信
---------------------------------------------------------------------

StateUpdate.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		return
	end
	currentPhase = state.Phase or ""
	chosenDuration = tonumber(state.ChosenDuration) or Config.DefaultDuration
	if currentPhase ~= "Intermission" then
		myVote = 0
	end
	if currentPhase ~= "Round" then
		zoneFrame.Visible = false
	end
	refreshVotePanel(state)
end)

refreshDeckPanel()
