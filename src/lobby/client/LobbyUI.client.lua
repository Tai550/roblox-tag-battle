-- LobbyUI: ロビーの画面（コイン・デッキ・ショップ・友達部屋・すぐ遊ぶの待ち状況）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Music = require(Shared:WaitForChild("Music"))
local Remotes = ReplicatedStorage:WaitForChild("LobbyRemotes")

local DataUpdate = Remotes:WaitForChild("DataUpdate")
local QueueUpdate = Remotes:WaitForChild("QueueUpdate")
local Notify = Remotes:WaitForChild("Notify")
local BuyItem = Remotes:WaitForChild("BuyItem")
local SetDeck = Remotes:WaitForChild("SetDeck")
local CreateRoom = Remotes:WaitForChild("CreateRoom")
local JoinRoom = Remotes:WaitForChild("JoinRoom")
local RoomCreated = Remotes:WaitForChild("RoomCreated")
local SoloPlay = Remotes:WaitForChild("SoloPlay")

local localPlayer = Players.LocalPlayer

local DARK = Color3.fromRGB(20, 22, 30)
local PANEL = Color3.fromRGB(32, 35, 48)
local WHITE = Color3.fromRGB(255, 255, 255)
local MUTED = Color3.fromRGB(170, 175, 190)
local GOLD = Color3.fromRGB(255, 205, 60)
local BLUE = Color3.fromRGB(70, 110, 230)
local GREEN = Color3.fromRGB(40, 170, 90)

Music.Play("Lobby")

---------------------------------------------------------------------
-- 部品
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.ResetOnSpawn = false
gui.Parent = localPlayer:WaitForChild("PlayerGui")

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function label(parent, text, size, position, textSize, color, bold)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = size
	l.Position = position
	l.Text = text
	l.TextSize = textSize or 14
	l.TextColor3 = color or WHITE
	l.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.Parent = parent
	return l
end

local function button(parent, text, size, position, color)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.Text = text
	b.TextSize = 15
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = WHITE
	b.BackgroundColor3 = color or BLUE
	b.BorderSizePixel = 0
	b.Parent = parent
	corner(b, 8)
	return b
end

---------------------------------------------------------------------
-- 左上：コイン　左：メニュー
---------------------------------------------------------------------

local coinPill = Instance.new("Frame")
coinPill.Size = UDim2.new(0, 150, 0, 36)
coinPill.Position = UDim2.new(0, 8, 0.5, -125) -- 左のメニューの上（チャットの案内文と重ならない位置）
coinPill.BackgroundColor3 = DARK
coinPill.BackgroundTransparency = 0.3
coinPill.Parent = gui
corner(coinPill)
local coinLabel = label(coinPill, "コイン 0", UDim2.new(1, -16, 1, 0), UDim2.new(0, 12, 0, 0), 18, GOLD, true)

local menu = Instance.new("Frame")
menu.BackgroundTransparency = 1
menu.Size = UDim2.new(0, 120, 0, 4 * 50)
menu.Position = UDim2.new(0, 8, 0.5, -75)
menu.Parent = gui
local deckButton = button(menu, "デッキ", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 0))
local shopButton = button(menu, "ショップ", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 50), Color3.fromRGB(200, 130, 40))
local roomButton = button(menu, "友達部屋", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 100), GREEN)
local soloButton = button(menu, "ひとりで遊ぶ", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 150), Color3.fromRGB(150, 80, 220))
soloButton.MouseButton1Click:Connect(function()
	SoloPlay:FireServer()
end)

-- 下の中央：すぐ遊ぶの状況
local queueLabel = label(gui, "緑のパッドに乗ると「すぐ遊ぶ」に参加", UDim2.new(0, 420, 0, 28), UDim2.new(0.5, 0, 1, -40), 16, WHITE, true)
queueLabel.AnchorPoint = Vector2.new(0.5, 0)
queueLabel.TextXAlignment = Enum.TextXAlignment.Center
queueLabel.TextStrokeTransparency = 0.3

-- お知らせ
local toast = label(gui, "", UDim2.new(0, 460, 0, 26), UDim2.new(0.5, 0, 0, 8), 16, WHITE, true)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextStrokeTransparency = 0.3
toast.TextTransparency = 1
local toastToken = 0
local function showToast(text)
	toastToken = toastToken + 1
	local myToken = toastToken
	toast.Text = text
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.3
	task.delay(3, function()
		if myToken == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------------
-- 中央のパネル（1つずつ開く）
---------------------------------------------------------------------

local function makePanel(titleText)
	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(0, 560, 0, 400)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = PANEL
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(560, 400)
	constraint.Parent = panel
	label(panel, titleText, UDim2.new(1, -80, 0, 30), UDim2.new(0, 16, 0, 10), 20, WHITE, true)
	local close = button(panel, "×", UDim2.new(0, 36, 0, 30), UDim2.new(1, -46, 0, 10), Color3.fromRGB(90, 90, 110))
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)
	return panel
end

local deckPanel = makePanel("デッキ（試合で出るアイテム）")
local shopPanel = makePanel("ショップ")
local roomPanel = makePanel("友達部屋")
local panels = { deckPanel, shopPanel, roomPanel }

local function open(panel)
	for _, other in ipairs(panels) do
		other.Visible = other == panel and not panel.Visible
	end
end
deckButton.MouseButton1Click:Connect(function()
	open(deckPanel)
end)
shopButton.MouseButton1Click:Connect(function()
	open(shopPanel)
end)
roomButton.MouseButton1Click:Connect(function()
	open(roomPanel)
end)

local function scrollList(panel, top, bottomSpace)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -(top + bottomSpace))
	scroll.Position = UDim2.new(0, 12, 0, top)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	return scroll
end

---------------------------------------------------------------------
-- データ
---------------------------------------------------------------------

local myData = { Coins = 0, Owned = {}, Deck = {} }
local draftDeck = {}  -- デッキ画面で選んでいる途中のもの

local function tierTag(def)
	return "［" .. Config.GetTierName(def.Tier) .. "］"
end

---------------------------------------------------------------------
-- デッキ画面
---------------------------------------------------------------------

local deckInfo = label(deckPanel, "", UDim2.new(1, -32, 0, 20), UDim2.new(0, 16, 0, 42), 14, MUTED)
local deckList = scrollList(deckPanel, 66, 58)
local saveDeck = button(deckPanel, "このデッキで保存", UDim2.new(0, 200, 0, 40), UDim2.new(0.5, -100, 1, -50), GREEN)
saveDeck.MouseButton1Click:Connect(function()
	SetDeck:FireServer(draftDeck)
end)

local function renderDeck()
	for _, child in ipairs(deckList:GetChildren()) do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	deckInfo.Text = string.format("持っているアイテムから %d 個えらぶ（いま %d 個）", Config.DeckSize, #draftDeck)
	for index, itemId in ipairs(Config.ItemOrder) do
		local def = Config.Items[itemId]
		if def and myData.Owned[itemId] then
			local selected = table.find(draftDeck, itemId) ~= nil
			local row = button(deckList, "", UDim2.new(1, -8, 0, 46), UDim2.new(), selected and BLUE or DARK)
			row.LayoutOrder = index
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = string.format("  %s %s %s\n  %s", selected and "✓" or "　", tierTag(def), def.DisplayName, def.Description)
			row.TextSize = 13
			row.TextWrapped = true
			row.MouseButton1Click:Connect(function()
				local at = table.find(draftDeck, itemId)
				if at then
					table.remove(draftDeck, at)
				elseif #draftDeck < Config.DeckSize then
					table.insert(draftDeck, itemId)
				else
					showToast(string.format("デッキは%d個まで。先にどれかを外してね", Config.DeckSize))
				end
				renderDeck()
			end)
		end
	end
end

---------------------------------------------------------------------
-- ショップ画面
---------------------------------------------------------------------

label(shopPanel, "試合でもらえるコインで、新しいアイテムを買える（梅 → 竹 → 松 の順に強い）",
	UDim2.new(1, -32, 0, 20), UDim2.new(0, 16, 0, 42), 13, MUTED)
local shopList = scrollList(shopPanel, 66, 12)

local function renderShop()
	for _, child in ipairs(shopList:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, itemId in ipairs(Config.ItemOrder) do
		local def = Config.Items[itemId]
		if def then
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, -8, 0, 54)
			row.BackgroundColor3 = DARK
			row.LayoutOrder = index
			row.Parent = shopList
			corner(row, 8)
			local tier = Config.Tiers[def.Tier]
			local tag = label(row, Config.GetTierName(def.Tier), UDim2.new(0, 28, 0, 28), UDim2.new(0, 8, 0.5, -14), 16, DARK, true)
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = tier and tier.Color or MUTED
			tag.TextXAlignment = Enum.TextXAlignment.Center
			corner(tag, 6)
			label(row, def.DisplayName, UDim2.new(1, -170, 0, 20), UDim2.new(0, 44, 0, 5), 15, WHITE, true)
			label(row, def.Description, UDim2.new(1, -170, 0, 26), UDim2.new(0, 44, 0, 25), 12, MUTED)
			local owned = myData.Owned[itemId]
			local price = def.Price or 0
			local text, color = string.format("%d コイン", price), Color3.fromRGB(200, 130, 40)
			if owned then
				text, color = "持っている", Color3.fromRGB(70, 75, 95)
			elseif myData.Coins < price then
				color = Color3.fromRGB(110, 90, 70)
			end
			local buy = button(row, text, UDim2.new(0, 110, 0, 36), UDim2.new(1, -118, 0.5, -18), color)
			buy.TextSize = 14
			if not owned then
				buy.MouseButton1Click:Connect(function()
					if myData.Coins < price then
						showToast(string.format("コインが足りません（あと %d）", price - myData.Coins))
						return
					end
					BuyItem:FireServer(itemId)
				end)
			end
		end
	end
end

---------------------------------------------------------------------
-- 友達部屋
---------------------------------------------------------------------

label(roomPanel, "部屋を作ると合言葉が出ます。友達はその合言葉を入れると同じ部屋に入れます。\n部屋ではホストが「開始」を押すたびに何回でも遊べます。",
	UDim2.new(1, -32, 0, 60), UDim2.new(0, 16, 0, 46), 14, MUTED)
local createButton = button(roomPanel, "部屋を作る", UDim2.new(0, 220, 0, 46), UDim2.new(0.5, -110, 0, 120), GREEN)
createButton.MouseButton1Click:Connect(function()
	CreateRoom:FireServer()
end)
label(roomPanel, "合言葉で入る", UDim2.new(1, -32, 0, 22), UDim2.new(0, 16, 0, 196), 16, WHITE, true)
local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(0, 200, 0, 44)
codeBox.Position = UDim2.new(0.5, -170, 0, 226)
codeBox.PlaceholderText = string.rep("0", Config.FriendRoomCodeLength)
codeBox.Text = ""
codeBox.TextSize = 22
codeBox.Font = Enum.Font.GothamBold
codeBox.TextColor3 = WHITE
codeBox.BackgroundColor3 = DARK
codeBox.ClearTextOnFocus = false
codeBox.Parent = roomPanel
corner(codeBox, 8)
local joinButton = button(roomPanel, "参加", UDim2.new(0, 120, 0, 44), UDim2.new(0.5, 50, 0, 226))
joinButton.MouseButton1Click:Connect(function()
	JoinRoom:FireServer((codeBox.Text:gsub("%s", "")))
end)

-- 部屋を作ったあとに出す合言葉
local createdBox = Instance.new("Frame")
createdBox.Size = UDim2.new(1, -32, 0, 110)
createdBox.Position = UDim2.new(0, 16, 1, -122)
createdBox.BackgroundColor3 = DARK
createdBox.Visible = false
createdBox.Parent = roomPanel
corner(createdBox, 10)
local createdCode = label(createdBox, "", UDim2.new(0.6, 0, 0, 56), UDim2.new(0, 16, 0, 8), 40, GOLD, true)
label(createdBox, "この合言葉を友達に伝えてね", UDim2.new(0.6, 0, 0, 22), UDim2.new(0, 16, 0, 70), 14, MUTED)
local enterButton = button(createdBox, "部屋に入る", UDim2.new(0.35, 0, 0, 52), UDim2.new(0.62, 0, 0, 28), GREEN)
local myRoomCode = nil
enterButton.MouseButton1Click:Connect(function()
	if myRoomCode then
		JoinRoom:FireServer(myRoomCode)
	end
end)
RoomCreated.OnClientEvent:Connect(function(code)
	myRoomCode = code
	createdCode.Text = "合言葉 " .. tostring(code)
	createdBox.Visible = true
	roomPanel.Visible = true
	deckPanel.Visible = false
	shopPanel.Visible = false
end)

---------------------------------------------------------------------
-- サーバーからの知らせ
---------------------------------------------------------------------

DataUpdate.OnClientEvent:Connect(function(data)
	myData = data
	coinLabel.Text = string.format("コイン %d", data.Coins or 0)
	draftDeck = {}
	for index, itemId in ipairs(data.Deck or {}) do
		draftDeck[index] = itemId
	end
	renderDeck()
	renderShop()
end)

QueueUpdate.OnClientEvent:Connect(function(info)
	if (info.Count or 0) == 0 then
		queueLabel.Text = "緑のパッドに乗ると「すぐ遊ぶ」に参加"
	elseif info.Ready then
		queueLabel.Text = string.format("すぐ遊ぶ %d/%d人　出発まで %d秒", info.Count, info.Max, info.Left)
	else
		queueLabel.Text = string.format("すぐ遊ぶ %d/%d人　あと%d人で出発", info.Count, info.Max, Config.MinPlayers - info.Count)
	end
end)

Notify.OnClientEvent:Connect(showToast)
