-- LobbyUI: ロビーの画面（段位・コイン・デッキ・ショップ・友達部屋・ルーレット・召喚獣ガチャ・すぐ遊ぶの待ち状況）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrandColors = Config.BrandColors
local BeastModels = require(Shared:WaitForChild("BeastModels"))
local UILayout = require(Shared:WaitForChild("UILayout"))
local Music = require(Shared:WaitForChild("Music"))
local RouletteFace = require(Shared:WaitForChild("RouletteFace"))
local RouletteVisual = require(Shared:WaitForChild("RouletteVisual"))
local Remotes = ReplicatedStorage:WaitForChild("LobbyRemotes")

local OpenBeasts = Remotes:WaitForChild("OpenBeasts")
local DrawBeast = Remotes:WaitForChild("DrawBeast")
local BeastResult = Remotes:WaitForChild("BeastResult")
local EquipBeast = Remotes:WaitForChild("EquipBeast")
local DataUpdate = Remotes:WaitForChild("DataUpdate")
local QueueUpdate = Remotes:WaitForChild("QueueUpdate")
local Notify = Remotes:WaitForChild("Notify")
local BuyItem = Remotes:WaitForChild("BuyItem")
local SetDeck = Remotes:WaitForChild("SetDeck")
local CreateRoom = Remotes:WaitForChild("CreateRoom")
local JoinRoom = Remotes:WaitForChild("JoinRoom")
local RoomCreated = Remotes:WaitForChild("RoomCreated")
local SoloPlay = Remotes:WaitForChild("SoloPlay")
local SpinRoulette = Remotes:WaitForChild("SpinRoulette")
local RouletteResult = Remotes:WaitForChild("RouletteResult")
local RouletteSpinVisual = Remotes:WaitForChild("RouletteSpinVisual")

local localPlayer = Players.LocalPlayer

local DARK = BrandColors.Surface
local WHITE = BrandColors.White
local GOLD = BrandColors.Accent

Music.Play("Lobby")

---------------------------------------------------------------------
-- 部品
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LobbyUI"
gui.ResetOnSpawn = false
local playerGui = localPlayer:WaitForChild("PlayerGui")
gui.Parent = playerGui
UILayout.ApplySafeArea(gui)

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
	b.TextColor3 = color == GOLD and DARK or WHITE
	b.BackgroundColor3 = color or BrandColors.Primary
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

-- コインの上：段位と累計 RP（試合中の左上と同じ表示）
local rankPill = Instance.new("Frame")
rankPill.Size = UDim2.new(0, 190, 0, 36)
rankPill.Position = UDim2.new(0, 8, 0.5, -167)
rankPill.BackgroundColor3 = DARK
rankPill.BackgroundTransparency = 0.3
rankPill.Parent = gui
corner(rankPill)
local rankLabel = label(rankPill, "", UDim2.new(1, -16, 1, 0), UDim2.new(0, 12, 0, 0), 17, WHITE, true)
local function showRank(rp)
	local tier = Config.TierForRP(rp)
	rankLabel.Text = string.format("%s  %d RP", tier and tier.Name or "", rp)
	rankLabel.TextColor3 = tier and tier.Color or WHITE
end
showRank(0)

local menu = Instance.new("Frame")
menu.BackgroundTransparency = 1
menu.Size = UDim2.new(0, 120, 0, 5 * 50)
menu.Position = UDim2.new(0, 8, 0.5, -75)
menu.Parent = gui
local deckButton = button(menu, "デッキ", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 0))
local shopButton = button(menu, "ショップ", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 50))
local roomButton = button(menu, "友達部屋", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 100))
local rouletteButton = button(menu, "ルーレット", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 150))
local tradeButton = button(menu, "召喚獣交換", UDim2.fromOffset(108, UILayout.MinTouchSize),
	UDim2.fromOffset(126, 0), BrandColors.Secondary)
local soloButton = button(menu, "ひとりで遊ぶ", UDim2.new(1, 0, 0, 44), UDim2.new(0, 0, 0, 200), BrandColors.Accent)
soloButton.MouseButton1Click:Connect(function()
	SoloPlay:FireServer()
end)

-- 下の中央：すぐ遊ぶの状況
local queueLabel = label(gui, "緑のパッドに乗ると「すぐ遊ぶ」に参加", UDim2.new(0, 420, 0, 28), UDim2.new(0.5, 0, 1, -40), 16, WHITE, true)
queueLabel.AnchorPoint = Vector2.new(0.5, 0)
queueLabel.TextXAlignment = Enum.TextXAlignment.Center
queueLabel.TextStrokeTransparency = 0.3

-- お知らせ
local toast = label(gui, "", UDim2.new(1, -2 * UILayout.EdgeMargin, 0, 26), UDim2.new(0.5, 0, 0, 8), 16, WHITE, true)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextStrokeTransparency = 0.3
toast.TextTransparency = 1
toast.TextWrapped = true
toast.AutomaticSize = Enum.AutomaticSize.Y
local toastSize = Instance.new("UISizeConstraint")
toastSize.MaxSize = Vector2.new(460, math.huge)
toastSize.Parent = toast
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
	-- 画面より大きい固定サイズだと、スマホでは上下が画面外に出てしまう。
	-- 画面から余白を引いた大きさを上限（560×400）で止める。
	panel.Size = UDim2.new(1, -2 * UILayout.EdgeMargin, 1, -2 * UILayout.EdgeMargin)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.BackgroundColor3 = DARK
	panel.Visible = false
	panel.Parent = gui
	corner(panel, 12)
	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(560, 400)
	constraint.Parent = panel
	label(panel, titleText, UDim2.new(1, -80, 0, 30), UDim2.new(0, 16, 0, 10), 20, WHITE, true)
	local close = button(panel, "×", UDim2.new(0, 36, 0, 30), UDim2.new(1, -46, 0, 10), BrandColors.Secondary)
	close.MouseButton1Click:Connect(function()
		panel.Visible = false
	end)
	return panel
end

local deckPanel = makePanel("デッキ（試合で出るアイテム）")
local shopPanel = makePanel("ショップ")
local roomPanel = makePanel("友達部屋")
local roulettePanel = makePanel("デイリールーレット")
local beastPanel = makePanel("召喚獣ガチャ")
local tradePanel = makePanel("召喚獣交換")
local panels = { deckPanel, shopPanel, roomPanel, roulettePanel, beastPanel, tradePanel }

local function syncPanelVisibility()
	for _, panel in ipairs(panels) do
		if panel.Visible then
			playerGui:SetAttribute("LobbyPanelOpen", true)
			return
		end
	end
	playerGui:SetAttribute("LobbyPanelOpen", nil)
end
for _, panel in ipairs(panels) do
	panel:GetPropertyChangedSignal("Visible"):Connect(syncPanelVisibility)
end

local function open(panel)
	if playerGui:GetAttribute("LobbyAdminOpen") then
		return
	end
	local show = not panel.Visible
	for _, other in ipairs(panels) do
		other.Visible = other == panel and show
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
rouletteButton.MouseButton1Click:Connect(function()
	open(roulettePanel)
end)

local function scrollList(panel, top, bottomSpace)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -(top + bottomSpace))
	scroll.Position = UDim2.new(0, 12, 0, top)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = BrandColors.Secondary
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

local shownCoins = 0
local myData = { Coins = 0, Owned = {}, Deck = {}, Beasts = {} }
local draftDeck = {}  -- デッキ画面で選んでいる途中のもの

local function tierTag(def)
	return "［" .. Config.GetTierName(def.Tier) .. "］"
end

---------------------------------------------------------------------
-- 召喚獣交換
---------------------------------------------------------------------

local renderTrade
do
	local action = Remotes:WaitForChild("TradeAction")
	local list = scrollList(tradePanel, 48, 12)
	local state = { Phase = "idle" }
	local targetId, beastId, message
	local rowIndex

	local function beastName(id)
		return Config.Beasts[id].DisplayName
	end

	local function textRow(text, height)
		rowIndex += 1
		local row = label(list, text, UDim2.new(1, -12, 0, height or 26), UDim2.new(), 16, WHITE, true)
		row.LayoutOrder = rowIndex
	end

	local function actionRow(text, color, callback)
		rowIndex += 1
		local row = button(list, text, UDim2.new(1, -12, 0, UILayout.MinTouchSize), UDim2.new(), color)
		row.LayoutOrder = rowIndex
		row.TextWrapped = true
		row.Activated:Connect(callback)
	end

	local function chooseBeast(excludedId)
		textRow("出す召喚獣を選ぶ")
		local hasOffer = false
		for _, id in ipairs(Config.BeastOrder) do
			if myData.Beasts[id] and id ~= excludedId then
				hasOffer = true
				actionRow(beastName(id), beastId == id and GOLD or BrandColors.Secondary, function()
					beastId = id
					renderTrade()
				end)
			end
		end
		if not hasOffer then
			textRow("出せる召喚獣がいません")
		end
	end

	renderTrade = function()
		if not tradePanel.Visible then
			return
		end
		for _, child in ipairs(list:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		rowIndex = 0
		if message then
			textRow(message, 44)
		end
		if state.Phase == "idle" then
			textRow("同じロビーにいる相手を選ぶ")
			local hasPartner = false
			for _, player in ipairs(Players:GetPlayers()) do
				if player ~= localPlayer then
					hasPartner = true
					actionRow(player.DisplayName .. " (@" .. player.Name .. ")",
						targetId == player.UserId and GOLD or BrandColors.Secondary, function()
							targetId = player.UserId
							renderTrade()
						end)
				end
			end
			if not hasPartner then
				textRow("交換できる相手がいません")
				return
			end
			chooseBeast()
			if targetId and Players:GetPlayerByUserId(targetId) and beastId and myData.Beasts[beastId] then
				actionRow("申し込む", GOLD, function()
					action:FireServer("request", targetId, beastId)
				end)
			end
		elseif state.Phase == "offered" then
			textRow(state.From .. " → " .. state.To .. "　" .. beastName(state.OfferA), 48)
			if state.IsSender then
				textRow("相手の応答を待っています")
			else
				actionRow("断る", BrandColors.Secondary, function()
					action:FireServer("cancel", state.Id)
				end)
				chooseBeast(state.OfferA)
				if state.BlockedReason then
					textRow(state.BlockedReason, 48)
				elseif beastId and beastId ~= state.OfferA and myData.Beasts[beastId] then
					actionRow("この獣で返す", GOLD, function()
						action:FireServer("offer", state.Id, beastId)
					end)
				end
			end
		else
			textRow(state.From .. "の " .. beastName(state.OfferA) .. "\n⇄ " ..
				state.To .. "の " .. beastName(state.OfferB), 60)
			if state.Phase == "saving" then
				textRow("交換を保存しています")
			elseif state.BlockedReason then
				textRow(state.BlockedReason, 48)
			elseif state.Confirmed then
				textRow("相手の決定を待っています")
			else
				actionRow("決定", GOLD, function()
					action:FireServer("confirm", state.Id)
				end)
			end
		end
		if state.Phase ~= "idle" and (state.Phase ~= "offered" or state.IsSender) then
			actionRow("やめる", BrandColors.Secondary, function()
				action:FireServer("cancel", state.Id)
			end)
		end
	end

	tradeButton.Activated:Connect(function()
		open(tradePanel)
	end)
	tradePanel:GetPropertyChangedSignal("Visible"):Connect(renderTrade)
	Players.PlayerAdded:Connect(renderTrade)
	Players.PlayerRemoving:Connect(function(player)
		if targetId == player.UserId then
			targetId = nil
		end
		task.defer(renderTrade)
	end)
	Remotes:WaitForChild("TradeUpdate").OnClientEvent:Connect(function(nextState, notice)
		if nextState then
			local incoming = nextState.Phase == "offered" and not nextState.IsSender
			local changedPhase = state.Phase ~= nextState.Phase
			if nextState.Id ~= state.Id then
				beastId = nil
			end
			state = nextState
			if changedPhase then
				list.CanvasPosition = Vector2.zero
			end
			if incoming and not tradePanel.Visible then
				open(tradePanel)
				if not tradePanel.Visible then
					showToast("召喚獣の交換申し込みが届きました")
				end
			end
			tradeButton.Text = state.Phase == "idle" and "召喚獣交換" or "交換を確認"
		end
		message = notice
		if notice and not tradePanel.Visible then
			showToast(notice)
		end
		renderTrade()
	end)
end

---------------------------------------------------------------------
-- 召喚獣ガチャ
---------------------------------------------------------------------

local beastCoins = label(beastPanel, "", UDim2.new(1, -32, 0, 20), UDim2.fromOffset(16, 42), 14, WHITE)
local beastList = scrollList(beastPanel, 64, UILayout.MinTouchSize + 70)
local resultLabel = label(beastPanel, "", UDim2.new(1, -32, 0, 58),
	UDim2.new(0, 16, 1, -UILayout.MinTouchSize - 68), 14, WHITE, true)
local drawButton = button(beastPanel, string.format("引く（%dコイン）", Config.BeastDrawCost),
	UDim2.fromOffset(200, UILayout.MinTouchSize), UDim2.new(0.5, 0, 1, -10), GOLD)
drawButton.AnchorPoint = Vector2.new(0.5, 1)

local equipButtons = {}
for index, id in ipairs(Config.BeastOrder) do
	local def = Config.Beasts[id]
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 76)
	row.LayoutOrder = index
	row.BackgroundColor3 = BrandColors.Primary
	row.BorderSizePixel = 0
	row.Parent = beastList
	corner(row, 8)

	local preview = Instance.new("ViewportFrame")
	preview.Size = UDim2.fromOffset(56, 64)
	preview.Position = UDim2.fromOffset(4, 6)
	preview.BackgroundTransparency = 1
	preview.Parent = row
	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(3, 2.5, -5), Vector3.new(0, 1.5, 0))
	camera.FieldOfView = 36
	camera.Parent = preview
	preview.CurrentCamera = camera
	BeastModels.Build(id, CFrame.new(), 0.33).Parent = preview

	label(row, tierTag(def) .. def.DisplayName, UDim2.new(1, -146, 0, 24),
		UDim2.fromOffset(60, 4), 15, Config.Tiers[def.Tier].Color, true)
	label(row, def.Description, UDim2.new(1, -146, 0, 46),
		UDim2.fromOffset(60, 26), 13, WHITE)
	local equip = button(row, "", UDim2.fromOffset(76, UILayout.MinTouchSize),
		UDim2.new(1, -82, 0.5, -UILayout.MinTouchSize / 2), BrandColors.Secondary)
	equip.Activated:Connect(function()
		if myData.Beasts[id] then
			EquipBeast:FireServer(myData.EquippedBeast == id and "" or id)
		end
	end)
	equipButtons[id] = equip
end

local function renderBeasts()
	for id, equip in pairs(equipButtons) do
		local owned = myData.Beasts[id] == true
		local equipped = myData.EquippedBeast == id
		equip.Text = equipped and "装備解除" or (owned and "装備する" or "未所持")
		equip.Interactable = owned
		equip.BackgroundColor3 = equipped and GOLD or (owned and BrandColors.Secondary or DARK)
		equip.TextColor3 = equipped and DARK or WHITE
	end
end

OpenBeasts.OnClientEvent:Connect(function()
	if not beastPanel.Visible then
		open(beastPanel)
	end
end)

drawButton.Activated:Connect(function()
	DrawBeast:FireServer()
end)

BeastResult.OnClientEvent:Connect(function(result, reason)
	if not result then
		resultLabel.Text = reason or "ガチャを引けませんでした"
		resultLabel.TextColor3 = WHITE
		return
	end
	local def = Config.Beasts[result.Id]
	local description = def.Description
	if result.Duplicate then
		description ..= string.format("（所持済み・%dコイン返却）", Config.BeastDuplicateRefund)
	end
	resultLabel.Text = tierTag(def) .. def.DisplayName .. "\n" .. description
	resultLabel.TextColor3 = Config.Tiers[def.Tier].Color
end)

renderBeasts()

---------------------------------------------------------------------
-- デッキ画面
---------------------------------------------------------------------

local deckInfo = label(deckPanel, "", UDim2.new(1, -32, 0, 20), UDim2.new(0, 16, 0, 42), 14, WHITE)
local deckList = scrollList(deckPanel, 66, UILayout.MinTouchSize + UILayout.EdgeMargin + 8)
local saveDeck = button(deckPanel, "このデッキで保存", UDim2.new(0, 200, 0, UILayout.MinTouchSize), UDim2.new(0.5, 0, 1, -UILayout.EdgeMargin), GOLD)
saveDeck.AnchorPoint = Vector2.new(0.5, 1)
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
			local row = button(deckList, "", UDim2.new(1, -8, 0, 46), UDim2.new(), selected and GOLD or BrandColors.Primary)
			row.LayoutOrder = index
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.Text = string.format("  %s %s %s\n  %s", selected and "✓" or "　", tierTag(def), def.DisplayName, def.Description)
			local itemMark = Instance.new("UIStroke")
			itemMark.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			itemMark.Color = def.Color
			itemMark.Thickness = 2
			itemMark.Parent = row
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

label(shopPanel, "試合でもらえるコインで、新しいアイテムを買える（B → A → S の順に強い）",
	UDim2.new(1, -32, 0, 20), UDim2.new(0, 16, 0, 42), 13, WHITE)
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
			row.BackgroundColor3 = BrandColors.Primary
			row.LayoutOrder = index
			row.Parent = shopList
			corner(row, 8)
			local tier = Config.Tiers[def.Tier]
			local tag = label(row, Config.GetTierName(def.Tier), UDim2.new(0, 28, 0, 28), UDim2.new(0, 8, 0.5, -14), 16, DARK, true)
			tag.TextColor3 = def.Tier == "S" and WHITE or DARK
			tag.BackgroundTransparency = 0
			tag.BackgroundColor3 = tier and tier.Color or WHITE
			tag.TextXAlignment = Enum.TextXAlignment.Center
			corner(tag, 6)
			label(row, def.DisplayName, UDim2.new(1, -170, 0, 20), UDim2.new(0, 44, 0, 5), 15, def.Color, true)
			label(row, def.Description, UDim2.new(1, -170, 0, 26), UDim2.new(0, 44, 0, 25), 12, WHITE)
			local owned = myData.Owned[itemId]
			local price = def.Price or 0
			local text, color = string.format("%d コイン", price), BrandColors.Accent
			if owned then
				text, color = "持っている", BrandColors.Primary
			elseif shownCoins < price then
				color = BrandColors.Secondary
			end
			local buy = button(row, text, UDim2.new(0, 110, 0, 36), UDim2.new(1, -118, 0.5, -18), color)
			buy.TextSize = 14
			if not owned then
				buy.MouseButton1Click:Connect(function()
					if shownCoins < price then
						showToast(string.format("コインが足りません（あと %d）", price - shownCoins))
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
	UDim2.new(1, -32, 0, 60), UDim2.new(0, 16, 0, 46), 14, WHITE)
local createButton = button(roomPanel, "部屋を作る", UDim2.new(0, 220, 0, 46), UDim2.new(0.5, -110, 0, 120), GOLD)
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
codeBox.PlaceholderColor3 = WHITE
codeBox.BackgroundColor3 = DARK
codeBox.ClearTextOnFocus = false
codeBox.Parent = roomPanel
corner(codeBox, 8)
local joinButton = button(roomPanel, "参加", UDim2.new(0, 120, 0, 44), UDim2.new(0.5, 50, 0, 226), GOLD)
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
label(createdBox, "この合言葉を友達に伝えてね", UDim2.new(0.6, 0, 0, 22), UDim2.new(0, 16, 0, 70), 14, WHITE)
local enterButton = button(createdBox, "部屋に入る", UDim2.new(0.35, 0, 0, 52), UDim2.new(0.62, 0, 0, 28), GOLD)
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
	open(roomPanel)
end)

---------------------------------------------------------------------
-- デイリールーレット
---------------------------------------------------------------------

local rouletteRules = Config.Roulette
roulettePanel:FindFirstChildOfClass("UISizeConstraint").MaxSize = Vector2.new(440, 620)

local wheelArea = Instance.new("Frame")
wheelArea.Name = "WheelArea"
wheelArea.BackgroundTransparency = 1
wheelArea.Position = UDim2.fromOffset(12, 43)
local controlsHeight = UILayout.MinTouchSize + 62
wheelArea.Size = UDim2.new(1, -24, 1, -43 - controlsHeight)
wheelArea.Parent = roulettePanel

local wheelHolder = Instance.new("Frame")
wheelHolder.BackgroundTransparency = 1
wheelHolder.AnchorPoint = Vector2.new(0.5, 0.5)
wheelHolder.Position = UDim2.fromScale(0.5, 0.5)
wheelHolder.Size = UDim2.fromScale(1, 1)
wheelHolder.Parent = wheelArea
local square = Instance.new("UIAspectRatioConstraint")
square.AspectRatio = 1
square.Parent = wheelHolder
local face = RouletteFace.Create(wheelHolder)

local pointer = label(wheelHolder, "▼", UDim2.fromScale(0.14, 0.135), UDim2.fromScale(0.5, 0), 20, GOLD, true)
pointer.AnchorPoint = Vector2.new(0.5, 0.22)
pointer.TextXAlignment = Enum.TextXAlignment.Center
pointer.TextScaled = true
pointer.TextStrokeColor3 = DARK
pointer.TextStrokeTransparency = 0
pointer.ZIndex = 5

local reward = label(gui, "", UDim2.new(0.88, 0, 0, 60), UDim2.fromScale(0.5, 0.24), 30, GOLD, true)
reward.AnchorPoint = Vector2.new(0.5, 0.5)
reward.TextXAlignment = Enum.TextXAlignment.Center
reward.TextScaled = true
reward.BackgroundColor3 = DARK
reward.BackgroundTransparency = 0.08
reward.Visible = false
reward.ZIndex = 8
corner(reward, 12)
local rewardSize = Instance.new("UISizeConstraint")
rewardSize.MaxSize = Vector2.new(300, 60)
rewardSize.Parent = reward

local stockLabel = label(roulettePanel, "", UDim2.new(1, -24, 0, 24),
	UDim2.new(0, 12, 1, -controlsHeight + 1), 18, GOLD, true)
stockLabel.TextXAlignment = Enum.TextXAlignment.Center
local nextLabel = label(roulettePanel, "", UDim2.new(1, -24, 0, 22),
	UDim2.new(0, 12, 1, -controlsHeight + 26), 14, WHITE)
nextLabel.TextXAlignment = Enum.TextXAlignment.Center
local spinButton = button(roulettePanel, "まわす！", UDim2.new(0.8, 0, 0, UILayout.MinTouchSize + 6),
	UDim2.new(0.5, 0, 1, -8), GOLD)
spinButton.AnchorPoint = Vector2.new(0.5, 1)
spinButton.TextSize = 20

local function layoutRoulette()
	local size = roulettePanel.AbsoluteSize
	local sideBySide = size.X >= 365 and size.Y < 390
	if sideBySide then
		wheelArea.Size = UDim2.new(0.56, -12, 1, -51)
		stockLabel.Size = UDim2.new(0.44, -12, 0, 26)
		stockLabel.Position = UDim2.new(0.56, 0, 0.5, -54)
		nextLabel.Size = UDim2.new(0.44, -12, 0, 40)
		nextLabel.Position = UDim2.new(0.56, 0, 0.5, -28)
		spinButton.Size = UDim2.new(0.44, -20, 0, UILayout.MinTouchSize + 6)
		spinButton.Position = UDim2.new(0.78, -6, 0.5, UILayout.MinTouchSize + 31)
	else
		wheelArea.Size = UDim2.new(1, -24, 1, -43 - controlsHeight)
		stockLabel.Size = UDim2.new(1, -24, 0, 24)
		stockLabel.Position = UDim2.new(0, 12, 1, -controlsHeight + 1)
		nextLabel.Size = UDim2.new(1, -24, 0, 22)
		nextLabel.Position = UDim2.new(0, 12, 1, -controlsHeight + 26)
		spinButton.Size = UDim2.new(0.8, 0, 0, UILayout.MinTouchSize + 6)
		spinButton.Position = UDim2.new(0.5, 0, 1, -8)
	end
end
roulettePanel:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutRoulette)
layoutRoulette()

local function positionReward()
	if roulettePanel.Visible then
		reward.Parent = wheelArea
		reward.Position = UDim2.fromScale(0.5, 0.73)
		reward.Size = UDim2.new(0.84, 0, 0.25, 0)
	else
		reward.Parent = gui
		reward.Position = UDim2.fromScale(0.5, 0.24)
		reward.Size = UDim2.new(0.88, 0, 0, 60)
	end
end
roulettePanel:GetPropertyChangedSignal("Visible"):Connect(positionReward)

local rouletteStock = 0
local latestGrantAt = nil
local nextGrantAt = nil   -- 次の権利がたまる時刻（os.clock 基準）。満タンなら nil
local spinning = false
local pendingSpin = false
local angle = 0
local rewardToken = 0

local function renderRoulette()
	rouletteButton.Text = rouletteStock > 0 and string.format("ルーレット (%d)", rouletteStock) or "ルーレット"
	rouletteButton.BackgroundColor3 = rouletteStock > 0 and BrandColors.Danger or BrandColors.Primary
	stockLabel.Text = string.format("まわせる回数：%d / %d", rouletteStock, rouletteRules.MaxStock)
	if nextGrantAt then
		local left = math.max(0, math.ceil(nextGrantAt - os.clock()))
		nextLabel.Text = string.format("次の1回まで %d:%02d", math.floor(left / 60), left % 60)
	else
		nextLabel.Text = "満タン！ まわすと次の時間がたまり始めます"
	end
	local busy = pendingSpin or spinning
	local available = rouletteStock > 0 and not busy
	spinButton.Text = busy and "…" or "まわす！"
	spinButton.BackgroundColor3 = available and GOLD or BrandColors.Secondary
	spinButton.TextColor3 = available and DARK or WHITE
	spinButton.AutoButtonColor = available
	spinButton.Active = available
end

local function applyRouletteBalances()
	shownCoins = myData.Coins or 0
	local coinText = string.format("コイン %d", shownCoins)
	coinLabel.Text = coinText
	beastCoins.Text = coinText
	rouletteStock = myData.RouletteStock or 0
	nextGrantAt = latestGrantAt
	renderRoulette()
end

local function requestSpin()
	if pendingSpin or spinning then
		return
	end
	if rouletteStock < 1 then
		showToast("まだまわせません。次の1回までまってね")
		return
	end
	pendingSpin = true
	renderRoulette()
	SpinRoulette:FireServer()
end

spinButton.Activated:Connect(requestSpin)
ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player == localPlayer and prompt.Name == "RoulettePrompt" then
		if not roulettePanel.Visible then
			open(roulettePanel)
		end
		requestSpin()
	end
end)

RouletteResult.OnClientEvent:Connect(function(prizeIndex)
	if not prizeIndex then
		pendingSpin = false
		if not spinning then
			applyRouletteBalances()
			renderShop()
		end
	end
end)

RouletteSpinVisual.OnClientEvent:Connect(function(userId, playerName, prizeIndex, coins, revealAt)
	if userId ~= localPlayer.UserId then
		while workspace:GetServerTimeNow() < revealAt do
			RunService.RenderStepped:Wait()
		end
		showToast(string.format("%s がルーレットで %d コイン獲得！", playerName, coins))
		return
	end
	pendingSpin = false
	spinning = true
	rewardToken += 1
	local token = rewardToken
	reward.Visible = false
	face.Highlight(nil)
	renderRoulette()

	local duration = rouletteRules.RevealDelay or 3
	local startAngle = angle
	local target = RouletteVisual.TargetRotation(startAngle, prizeIndex, #rouletteRules.Prizes)
	local remaining = revealAt - workspace:GetServerTimeNow()
	while remaining > 0 do
		face.SetAngle(RouletteVisual.SpinAngle(startAngle, target, 1 - remaining / duration))
		RunService.RenderStepped:Wait()
		remaining = revealAt - workspace:GetServerTimeNow()
	end
	angle = target % 360
	face.SetAngle(angle)
	face.Highlight(prizeIndex)
	reward.Text = string.format("+%d コイン", coins)
	reward.Visible = true
	spinning = false
	applyRouletteBalances()
	renderShop()
	task.delay(4, function()
		if rewardToken == token then
			reward.Visible = false
			face.Highlight(nil)
		end
	end)
end)

task.spawn(function()
	while true do
		task.wait(1)
		if not spinning then
			renderRoulette()
		end
	end
end)

---------------------------------------------------------------------
-- サーバーからの知らせ
---------------------------------------------------------------------

DataUpdate.OnClientEvent:Connect(function(data)
	myData = data
	showRank(data.RP or 0)
	latestGrantAt = data.RouletteNextIn and (os.clock() + data.RouletteNextIn) or nil
	if not pendingSpin and not spinning then
		applyRouletteBalances()
	end
	draftDeck = {}
	for index, itemId in ipairs(data.Deck or {}) do
		draftDeck[index] = itemId
	end
	renderDeck()
	renderShop()
	renderBeasts()
	renderTrade()
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
