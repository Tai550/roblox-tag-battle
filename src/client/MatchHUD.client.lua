-- MatchHUD: 試合サーバーの画面表示（すべてここにまとめる）
--
-- 試合中はプレー画面をじゃましないよう、情報は画面のふちに小さく出す。
--   上の中央 : 残り時間と鬼の名前
--   左上     : エリアの内外・エリア外スタミナ・強制送還の回数・効果中のアイテム
--   下の中央 : アイテムの枠（タップ / キーで使う）
-- 試合の前後（待機・投票・結果・友達部屋）だけ、画面の中央にパネルを出す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BrandColors = Config.BrandColors
local Music = require(Shared:WaitForChild("Music"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local StateUpdate = Remotes:WaitForChild("StateUpdate")
local ItemUpdate = Remotes:WaitForChild("ItemUpdate")
local ZoneUpdate = Remotes:WaitForChild("ZoneUpdate")
local Notify = Remotes:WaitForChild("Notify")
local RadarEffect = Remotes:WaitForChild("RadarEffect")
local UseItem = Remotes:WaitForChild("UseItem")
local UseBeast = Remotes:WaitForChild("UseBeast")
local IsisJump = Remotes:WaitForChild("IsisJump")
local DurationVote = Remotes:WaitForChild("DurationVote")
local MapVote = Remotes:WaitForChild("MapVote")
local HostStart = Remotes:WaitForChild("HostStart")
local LeaveToLobby = Remotes:WaitForChild("LeaveToLobby")
local RankUp = Remotes:WaitForChild("RankUp")

local localPlayer = Players.LocalPlayer

local DARK = BrandColors.Surface
local WHITE = BrandColors.White
local RED = BrandColors.Danger
local SECONDARY = BrandColors.Secondary
local GOLD = BrandColors.Accent

---------------------------------------------------------------------
-- 部品を作る小さな関数
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "MatchHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false -- 上の Roblox のバーより下から使う
gui.Parent = localPlayer:WaitForChild("PlayerGui")
require(Shared:WaitForChild("UILayout")).ApplySafeArea(gui) -- スマホの切り欠き・標準バーを避ける

local function corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
end

local function frame(name, size, position, parent, transparency)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = transparency or 0.35
	f.BorderSizePixel = 0
	f.Parent = parent or gui
	corner(f)
	return f
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
	l.Parent = parent
	return l
end

local function button(parent, text, size, position, color)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.Text = text
	b.TextSize = 16
	b.Font = Enum.Font.GothamBold
	b.TextColor3 = color == GOLD and DARK or WHITE
	b.BackgroundColor3 = color or BrandColors.Primary
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 8)
	return b
end

---------------------------------------------------------------------
-- 上の中央：残り時間と鬼
---------------------------------------------------------------------

local topPill = frame("TopPill", UDim2.new(0, 250, 0, 36), UDim2.new(0.5, 0, 0, 4))
topPill.AnchorPoint = Vector2.new(0.5, 0)
local timeLabel = label(topPill, "", UDim2.new(0, 70, 1, 0), UDim2.new(0, 12, 0, 0), 20, WHITE, true)
local taggerLabel = label(topPill, "", UDim2.new(1, -92, 1, 0), UDim2.new(0, 84, 0, 0), 14, RED, true)
taggerLabel.TextTruncate = Enum.TextTruncate.AtEnd
local topStroke = Instance.new("UIStroke")
topStroke.Thickness = 2
topStroke.Color = RED
topStroke.Enabled = false
topStroke.Parent = topPill

---------------------------------------------------------------------
-- 左上：エリアの状態と効果
---------------------------------------------------------------------

local zonePanel = frame("ZonePanel", UDim2.new(0, 156, 0, 62), UDim2.new(0, 8, 0, 4))
local zoneLabel = label(zonePanel, "エリアの中", UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 4), 13, SECONDARY, true)
local staminaBack = Instance.new("Frame")
staminaBack.Size = UDim2.new(1, -16, 0, 8)
staminaBack.Position = UDim2.new(0, 8, 0, 25)
staminaBack.BackgroundColor3 = BrandColors.Surface
staminaBack.BorderSizePixel = 0
staminaBack.Parent = zonePanel
corner(staminaBack, 4)
local staminaFill = Instance.new("Frame")
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = SECONDARY
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaBack
corner(staminaFill, 4)
local returnsLabel = label(zonePanel, "送還 0/2", UDim2.new(1, -16, 0, 16), UDim2.new(0, 8, 0, 39), 12, WHITE)

local effectsLabel = label(gui, "", UDim2.new(0, 200, 0, 120), UDim2.new(0, 10, 0, 72), 12, GOLD, true)
effectsLabel.TextYAlignment = Enum.TextYAlignment.Top
effectsLabel.TextStrokeTransparency = 0.5

---------------------------------------------------------------------
-- 下の中央：アイテムの枠
---------------------------------------------------------------------

local itemBar = Instance.new("Frame")
itemBar.Name = "ItemBar"
itemBar.BackgroundTransparency = 1
itemBar.AnchorPoint = Vector2.new(0.5, 1)
itemBar.Position = UDim2.new(0.5, 0, 1, -10)
itemBar.Size = UDim2.new(1, -20, 0, 62)
itemBar.Parent = gui
local barLimit = Instance.new("UISizeConstraint")
barLimit.MaxSize = Vector2.new(4 * 78, 62)
barLimit.Parent = itemBar
local barLayout = Instance.new("UIListLayout")
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
barLayout.Padding = UDim.new(0, 6)
barLayout.Parent = itemBar

local slotButtons = {}
for slot = 1, 4 do
	local b = button(itemBar, "", UDim2.new(0.25, -6, 0, 62), UDim2.new(), DARK)
	b.Name = "Slot" .. slot
	b.BackgroundTransparency = 0.35
	b.TextSize = 12
	b.TextWrapped = true
	b.LayoutOrder = slot
	local key = label(b, Config.GetSlotKeyLabel(slot), UDim2.new(0, 20, 0, 14), UDim2.new(0, 5, 0, 3), 11, GOLD, true)
	key.Name = "Key"
	b.MouseButton1Click:Connect(function()
		UseItem:FireServer(slot)
	end)
	slotButtons[slot] = b
end

local beastButton = button(itemBar, "", UDim2.new(0.2, -6, 0, 62), UDim2.new(), BrandColors.Primary)
beastButton.Name = "SummonBeast"
beastButton.LayoutOrder = #slotButtons + 1
beastButton.TextWrapped = true
beastButton.TextSize = 12
beastButton.Visible = false
beastButton.Activated:Connect(function()
	UseBeast:FireServer()
end)

---------------------------------------------------------------------
-- お知らせ（上の中央、少しだけ出て消える）
---------------------------------------------------------------------

local toast = label(gui, "", UDim2.new(0, 420, 0, 26), UDim2.new(0.5, 0, 0, 46), 15, WHITE, true)
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.TextXAlignment = Enum.TextXAlignment.Center
toast.TextStrokeTransparency = 0.3
toast.TextTransparency = 1
local toastToken = 0

local function showToast(text, color)
	toastToken = toastToken + 1
	local myToken = toastToken
	toast.Text = text
	toast.TextColor3 = color or WHITE
	toast.TextTransparency = 0
	toast.TextStrokeTransparency = 0.3
	task.delay(2.6, function()
		if myToken == toastToken then
			TweenService:Create(toast, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

---------------------------------------------------------------------
-- 中央パネル（試合の前後だけ）
---------------------------------------------------------------------

local center = frame("CenterPanel", UDim2.new(0, 440, 0, 120), UDim2.new(0.5, 0, 0, 50), gui, 0.2)
center.AnchorPoint = Vector2.new(0.5, 0)
center.AutomaticSize = Enum.AutomaticSize.Y
local centerPad = Instance.new("UIPadding")
centerPad.PaddingTop = UDim.new(0, 12)
centerPad.PaddingBottom = UDim.new(0, 12)
centerPad.PaddingLeft = UDim.new(0, 14)
centerPad.PaddingRight = UDim.new(0, 14)
centerPad.Parent = center
local centerLayout = Instance.new("UIListLayout")
centerLayout.Padding = UDim.new(0, 8)
centerLayout.SortOrder = Enum.SortOrder.LayoutOrder
centerLayout.Parent = center

local titleLabel = label(center, "", UDim2.new(1, 0, 0, 26), UDim2.new(), 22, WHITE, true)
titleLabel.LayoutOrder = 1
local messageLabel = label(center, "", UDim2.new(1, 0, 0, 20), UDim2.new(), 15, WHITE)
messageLabel.LayoutOrder = 2
messageLabel.TextWrapped = true
messageLabel.AutomaticSize = Enum.AutomaticSize.Y

local voteRow = Instance.new("Frame")
voteRow.BackgroundTransparency = 1
voteRow.Size = UDim2.new(1, 0, 0, 40)
voteRow.LayoutOrder = 3
voteRow.Parent = center
local voteLayout = Instance.new("UIListLayout")
voteLayout.FillDirection = Enum.FillDirection.Horizontal
voteLayout.Padding = UDim.new(0, 8)
voteLayout.Parent = voteRow
local voteButtons = {}
for index, duration in ipairs(Config.MatchDurations) do
	local b = button(voteRow, "", UDim2.new(1 / #Config.MatchDurations, -6, 1, 0), UDim2.new())
	b.LayoutOrder = index
	b.MouseButton1Click:Connect(function()
		DurationVote:FireServer(duration)
	end)
	voteButtons[duration] = b
end

-- マップ投票（7マップを4列×2段のボタンで）
local mapGrid = Instance.new("Frame")
mapGrid.BackgroundTransparency = 1
mapGrid.Size = UDim2.new(1, 0, 0, 0)
mapGrid.AutomaticSize = Enum.AutomaticSize.Y
mapGrid.LayoutOrder = 3
mapGrid.Parent = center
local mapGridLayout = Instance.new("UIGridLayout")
mapGridLayout.CellSize = UDim2.new(0.25, -6, 0, 40)
mapGridLayout.CellPadding = UDim2.new(0, 6, 0, 6)
mapGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
mapGridLayout.Parent = mapGrid
local mapButtons = {}
local myMapVote = nil
for index, map in ipairs(Config.MatchMaps) do
	local b = button(mapGrid, "", UDim2.new(), UDim2.new())
	b.LayoutOrder = index
	b.TextSize = 13
	b.TextWrapped = true
	b.MouseButton1Click:Connect(function()
		myMapVote = map.Id
		MapVote:FireServer(map.Id)
	end)
	mapButtons[map.Id] = { Button = b, Map = map }
end
voteRow.LayoutOrder = 4

local resultsList = Instance.new("Frame")
resultsList.BackgroundTransparency = 1
resultsList.Size = UDim2.new(1, 0, 0, 0)
resultsList.AutomaticSize = Enum.AutomaticSize.Y
resultsList.LayoutOrder = 5
resultsList.Parent = center
local resultsLayout = Instance.new("UIListLayout")
resultsLayout.Padding = UDim.new(0, 2)
resultsLayout.SortOrder = Enum.SortOrder.LayoutOrder
resultsLayout.Parent = resultsList

local actionRow = Instance.new("Frame")
actionRow.BackgroundTransparency = 1
actionRow.Size = UDim2.new(1, 0, 0, 40)
actionRow.LayoutOrder = 5
actionRow.Parent = center
local startButton = button(actionRow, "開始！", UDim2.new(0.5, -4, 1, 0), UDim2.new(0, 0, 0, 0), BrandColors.Accent)
local lobbyButton = button(actionRow, "ロビーへ戻る", UDim2.new(0.5, -4, 1, 0), UDim2.new(0.5, 4, 0, 0), BrandColors.Secondary)
startButton.MouseButton1Click:Connect(function()
	HostStart:FireServer()
end)
lobbyButton.MouseButton1Click:Connect(function()
	LeaveToLobby:FireServer()
	showToast("ロビーへ移動します…")
end)

---------------------------------------------------------------------
-- 観戦（脱落したとき）
---------------------------------------------------------------------

-- 友達部屋の合言葉（いつでも見えるよう左下に小さく）
local codeLabel = label(gui, "", UDim2.new(0, 200, 0, 22), UDim2.new(0, 10, 1, -78), 14, GOLD, true)
codeLabel.TextStrokeTransparency = 0.4

local spectatePanel = frame("Spectate", UDim2.new(0, 260, 0, 40), UDim2.new(0, 8, 1, -50))
local spectateLabel = label(spectatePanel, "観戦中", UDim2.new(1, -96, 1, 0), UDim2.new(0, 10, 0, 0), 13, WHITE, true)
spectateLabel.TextTruncate = Enum.TextTruncate.AtEnd
local nextButton = button(spectatePanel, "次の人", UDim2.new(0, 80, 0, 30), UDim2.new(1, -86, 0, 5))
spectatePanel.Visible = false
local spectateIndex = 1

---------------------------------------------------------------------
-- 状態
---------------------------------------------------------------------

local state = {}
local myItems = { HeldItems = {}, MaxSlots = Config.BaseItemSlots, Effects = {} }

UserInputService.JumpRequest:Connect(function()
	if not myItems.IsisJumpActive then
		return
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.FloorMaterial == Enum.Material.Air then
		IsisJump:FireServer()
	end
end)

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function contains(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

local function activePlayers()
	local list = {}
	for _, userId in ipairs(state.Participants or {}) do
		local player = Players:GetPlayerByUserId(userId)
		if player and player ~= localPlayer then
			table.insert(list, player)
		end
	end
	return list
end

local function updateSpectate()
	local camera = workspace.CurrentCamera
	local eliminated = state.Phase == "Round" and not contains(state.Participants, localPlayer.UserId)
	spectatePanel.Visible = eliminated
	if not eliminated then
		local humanoid = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		if humanoid and camera.CameraSubject ~= humanoid then
			camera.CameraSubject = humanoid
		end
		return
	end
	local targets = activePlayers()
	if #targets == 0 then
		spectateLabel.Text = "観戦中"
		return
	end
	if spectateIndex > #targets then
		spectateIndex = 1
	end
	local target = targets[spectateIndex]
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraSubject = humanoid
	end
	spectateLabel.Text = "観戦中: " .. target.DisplayName
end

nextButton.MouseButton1Click:Connect(function()
	spectateIndex = spectateIndex + 1
	updateSpectate()
end)

local function clearResults()
	for _, child in ipairs(resultsList:GetChildren()) do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function renderResults(results)
	clearResults()
	for index, row in ipairs(results or {}) do
		local color = WHITE
		if row.Status == "優勝" then
			color = GOLD
		elseif row.Status == "最後の鬼" then
			color = RED
		elseif row.Status == "脱落" then
			color = BrandColors.White
		end
		local text = string.format("%d位  %s  ［%s・鬼%d回］  +%dコイン",
			row.Rank, row.Name, row.Status, row.Tags, row.Coins)
		local l = label(resultsList, text, UDim2.new(1, 0, 0, 20), UDim2.new(), 14, color, row.UserId == localPlayer.UserId)
		l.LayoutOrder = index
	end
end

local beastHighlights = {}

local function clearBeastHighlights()
	for highlight in pairs(beastHighlights) do
		highlight:Destroy()
	end
	table.clear(beastHighlights)
end

local function renderState()
	local phase = state.Phase
	local inRound = phase == "Round"

	-- ふちの表示は試合中だけ
	topPill.Visible = inRound
	zonePanel.Visible = inRound and contains(state.Participants, localPlayer.UserId)
	effectsLabel.Visible = inRound
	itemBar.Visible = inRound and contains(state.Participants, localPlayer.UserId)
	if not itemBar.Visible then
		clearBeastHighlights()
	end

	if inRound then
		timeLabel.Text = formatTime(state.TimeLeft)
		timeLabel.TextColor3 = (state.TimeLeft or math.huge) <= Config.Music.FinalTime and RED or WHITE
		local amTagger = table.find(state.TaggerUserIds or {}, localPlayer.UserId) ~= nil
		taggerLabel.Text = amTagger and "あなたが鬼！" or ("鬼: " .. table.concat(state.TaggerNames or {}, "、"))
		topStroke.Enabled = amTagger
	end

	codeLabel.Text = (state.Mode == "Friends" and state.RoomCode and state.RoomCode ~= "")
		and ("友達部屋 合言葉 " .. state.RoomCode) or ""

	-- 中央パネル
	center.Visible = not inRound
	voteRow.Visible = phase == "Intermission"
	mapGrid.Visible = phase == "Intermission"
	if phase ~= "Intermission" then
		myMapVote = nil
	end
	resultsList.Visible = phase == "Results"
	local isFriends = state.Mode == "Friends"
	local isHost = state.HostUserId == localPlayer.UserId
	startButton.Visible = isFriends and phase == "RoomWaiting" and isHost
	lobbyButton.Visible = state.Mode == "Friends" or state.Mode == "Quick" or state.Mode == "Solo"
	actionRow.Visible = startButton.Visible or lobbyButton.Visible

	if phase == "Waiting" then
		titleLabel.Text = "準備中"
	elseif state.Mode == "Solo" and phase ~= "Results" and phase ~= "Intermission" then
		titleLabel.Text = "ひとりモード"
	elseif phase == "RoomWaiting" then
		titleLabel.Text = "友達部屋　合言葉 " .. (state.RoomCode or "")
	elseif phase == "Intermission" then
		titleLabel.Text = string.format("まもなく開始　%d", state.TimeLeft or 0)
	elseif phase == "Results" then
		titleLabel.Text = "結果"
	else
		titleLabel.Text = ""
	end
	messageLabel.Text = state.Message or ""

	if phase == "Intermission" then
		local counts = state.MapVoteCounts or {}
		for id, entry in pairs(mapButtons) do
			local name = entry.Map.VoteLabel or entry.Map.Name
			local mark = id == state.NextMap and "（次）" or ""
			entry.Button.Text = string.format("%s%s\n%d票", name, mark, counts[id] or 0)
			entry.Button.BackgroundColor3 = id == myMapVote and Color3.fromRGB(70, 110, 230)
				or Color3.fromRGB(70, 75, 95)
		end
		for duration, b in pairs(voteButtons) do
			local votes = state.VoteCounts and state.VoteCounts[tostring(duration)] or 0
			b.Text = string.format("%d分（%d票）", duration / 60, votes)
			local selected = duration == state.ChosenDuration
			b.BackgroundColor3 = selected and GOLD or BrandColors.Primary
			b.TextColor3 = selected and DARK or WHITE
		end
	end
	if phase == "Results" then
		renderResults(state.Results)
	end

	-- BGM
	if inRound then
		Music.Play((state.TimeLeft or 999) <= Config.Music.FinalTime and "Final" or "Match")
	else
		Music.Play("Lobby")
	end

	updateSpectate()
end

local function renderItems()
	local maxSlots = myItems.MaxSlots or Config.BaseItemSlots
	local beast = Config.Beasts[myItems.EquippedBeast]
	beastButton.Visible = beast ~= nil and myItems.BeastUsed ~= true
	if beast then
		beastButton.Text = "召喚\n" .. beast.DisplayName
		beastButton.TextColor3 = Config.Tiers[beast.Tier].Color
	end
	local columns = beastButton.Visible and maxSlots + 1 or #slotButtons
	barLimit.MaxSize = Vector2.new(columns * 78, 62)
	beastButton.Size = UDim2.new(1 / columns, -6, 0, 62)
	for slot, b in ipairs(slotButtons) do
		b.Visible = slot <= maxSlots
		b.Size = UDim2.new(1 / columns, -6, 0, 62)
		local itemId = myItems.HeldItems and myItems.HeldItems[slot]
		local def = itemId and Config.Items[itemId]
		if def then
			b.Text = def.Passive and (def.DisplayName .. "\n（自動）") or def.DisplayName
			b.BackgroundColor3 = BrandColors.Primary
			b.TextColor3 = def.Color
			b.BackgroundTransparency = 0.1
		else
			b.Text = ""
			b.BackgroundColor3 = DARK
			b.BackgroundTransparency = 0.6
		end
	end
	local lines = {}
	for _, effect in ipairs(myItems.Effects or {}) do
		if effect.Left and effect.Left > 0 then
			table.insert(lines, string.format("%s %d秒", effect.Name, math.ceil(effect.Left)))
		end
	end
	effectsLabel.Text = table.concat(lines, "\n")
end

---------------------------------------------------------------------
-- サーバーからの知らせ
---------------------------------------------------------------------

StateUpdate.OnClientEvent:Connect(function(info)
	state = info
	renderState()
end)

ItemUpdate.OnClientEvent:Connect(function(info)
	myItems = info
	renderItems()
end)

ZoneUpdate.OnClientEvent:Connect(function(info)
	local ratio = math.clamp((info.Stamina or 0) / math.max(1, info.MaxStamina or 100), 0, 1)
	staminaFill.Size = UDim2.new(ratio, 0, 1, 0)
	staminaFill.BackgroundColor3 = ratio > 0.35 and SECONDARY or RED
	if (info.GuardLeft or 0) > 0 then
		zoneLabel.Text = string.format("エリアガード %d秒", math.ceil(info.GuardLeft))
		zoneLabel.TextColor3 = RED
	elseif info.IsOutside then
		zoneLabel.Text = "エリアの外！ 戻ろう"
		zoneLabel.TextColor3 = RED
	else
		zoneLabel.Text = "エリアの中"
		zoneLabel.TextColor3 = WHITE
	end
	returnsLabel.Text = string.format("強制送還 %d/%d（次で脱落: %s）",
		info.Returns or 0, info.MaxReturns or 2, (info.Returns or 0) >= (info.MaxReturns or 2) and "はい" or "いいえ")
end)

Notify.OnClientEvent:Connect(function(text)
	showToast(text)
end)

---------------------------------------------------------------------
-- 左上：段位と、この試合の記録（タッチ・捕まった回数・獲得 RP）
---------------------------------------------------------------------

-- 左上のエリア表示のすぐ下（右上はプレイヤーリストと重なるため）
local statsPanel = frame("RoundStats", UDim2.new(0, 190, 0, 46), UDim2.new(0, 8, 0, 72), gui, 0.35)
local rankText = label(statsPanel, "", UDim2.new(1, -16, 0, 20), UDim2.new(0, 8, 0, 3), 14, GOLD, true)
rankText.Name = "Rank"
local roundText = label(statsPanel, "", UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, 24), 12, WHITE, false)
roundText.Name = "RoundCounts"

local function refreshStats()
	local folder = localPlayer:FindFirstChild("leaderstats")
	local rpStat = folder and folder:FindFirstChild(Config.LeaderstatNames.RP)
	local rp = rpStat and tonumber(rpStat.Value) or 0
	local tier = Config.TierForRP(rp)
	rankText.Text = string.format("%s  %d RP", tier and tier.Name or "", rp)
	rankText.TextColor3 = tier and tier.Color or GOLD
	roundText.Text = string.format("タッチ %d　捕まった %d　+%d RP",
		localPlayer:GetAttribute("RoundTags") or 0,
		localPlayer:GetAttribute("RoundCaught") or 0,
		localPlayer:GetAttribute("RoundRP") or 0)
end
for _, name in ipairs({ "RoundTags", "RoundCaught", "RoundRP" }) do
	localPlayer:GetAttributeChangedSignal(name):Connect(refreshStats)
end
task.spawn(function()
	local folder = localPlayer:WaitForChild("leaderstats")
	local rpStat = folder:WaitForChild(Config.LeaderstatNames.RP)
	rpStat.Changed:Connect(refreshStats)
	refreshStats()
end)
refreshStats()
RankUp.OnClientEvent:Connect(function(rankName)
	if type(rankName) == "string" and rankName ~= "" then
		showToast("ランクアップ！ " .. rankName .. " に昇格", GOLD)
	end
end)

-- レーダー：相手を壁ごしに光らせる（自分の画面だけ）
RadarEffect.OnClientEvent:Connect(function(characters, duration, isBeast)
	duration = math.clamp(tonumber(duration) or 0, 0, 15)
	for _, character in ipairs(characters or {}) do
		if typeof(character) == "Instance" and character:IsA("Model") then
			local highlight = Instance.new("Highlight")
			highlight.Name = "RadarHighlight"
			highlight.FillColor = Config.RadarHighlightColor
			highlight.OutlineColor = WHITE
			highlight.FillTransparency = 0.4
			highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			highlight.Adornee = character
			highlight.Parent = gui
			if isBeast then
				beastHighlights[highlight] = true
			end
			task.delay(duration, function()
				if not isBeast or beastHighlights[highlight] then
					beastHighlights[highlight] = nil
					highlight:Destroy()
				end
			end)
		end
	end
end)

-- キーボード / ゲームパッドでアイテムを使う
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	for slot, keys in ipairs(Config.ItemSlotKeys) do
		for _, keyCode in ipairs(keys) do
			if input.KeyCode == keyCode then
				UseItem:FireServer(slot)
				return
			end
		end
	end
end)

-- 効果の残り秒数を毎秒すこしずつ減らして表示する（サーバーの更新の間をつなぐ）
task.spawn(function()
	while true do
		task.wait(1)
		for _, effect in ipairs(myItems.Effects or {}) do
			if effect.Left and effect.Left > 0 then
				effect.Left = math.max(0, effect.Left - 1)
			end
		end
		renderItems()
		if state.Phase == "Round" then
			updateSpectate()
		end
	end
end)

renderState()
renderItems()
