-- HUD: 自分の役割、残り時間、人数待ち、結果、お知らせメッセージを表示する
-- 表示するだけで、ゲームの判定は何もしない（判定はすべてサーバー）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateUpdate = Remotes:WaitForChild("StateUpdate")
local Notify = Remotes:WaitForChild("Notify")
local RankUp = Remotes:WaitForChild("RankUp")

local localPlayer = Players.LocalPlayer

local COLOR_TAGGER = Color3.fromRGB(255, 80, 80)
local COLOR_RUNNER = Color3.fromRGB(110, 200, 255)
local COLOR_NEUTRAL = Color3.fromRGB(230, 230, 230)
local COLOR_WIN = Color3.fromRGB(255, 215, 80)

---------------------------------------------------------------------
-- 画面の部品を作る
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "TagHUD"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10

local function makeLabel(name, parent, size, position, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = COLOR_NEUTRAL
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = parent
	return label
end

local topFrame = Instance.new("Frame")
topFrame.Name = "Top"
topFrame.Size = UDim2.new(0, 460, 0, 148)
topFrame.Position = UDim2.new(0.5, 0, 0, 8)
topFrame.AnchorPoint = Vector2.new(0.5, 0)
topFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
topFrame.BackgroundTransparency = 0.35
topFrame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = topFrame

local phaseLabel = makeLabel("Phase", topFrame, UDim2.new(1, -16, 0, 24), UDim2.new(0.5, 0, 0, 4), 20)
local timerLabel = makeLabel("Timer", topFrame, UDim2.new(1, -16, 0, 32), UDim2.new(0.5, 0, 0, 28), 28)
local roleLabel = makeLabel("Role", topFrame, UDim2.new(1, -16, 0, 22), UDim2.new(0.5, 0, 0, 60), 18)
local messageLabel = makeLabel("Message", topFrame, UDim2.new(1, -16, 0, 20), UDim2.new(0.5, 0, 0, 82), 15)
messageLabel.TextWrapped = true
local rankLabel = makeLabel("Rank", topFrame, UDim2.new(1, -16, 0, 26), UDim2.new(0.5, 0, 0, 108), 16)
rankLabel.Text = "ランクを読み込み中"

local notifyLabel = makeLabel("Notify", gui, UDim2.new(0, 600, 0, 36), UDim2.new(0.5, 0, 0.62, 0), 24)
notifyLabel.TextWrapped = true
notifyLabel.AutomaticSize = Enum.AutomaticSize.Y -- 長いお知らせ（アイテムボックスの入れ替えなど）は複数行で表示
notifyLabel.Visible = false

gui.Parent = localPlayer:WaitForChild("PlayerGui")

---------------------------------------------------------------------
-- 状態の表示
---------------------------------------------------------------------

local function formatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function containsUserId(list, userId)
	if type(list) ~= "table" then
		return false
	end
	for _, id in ipairs(list) do
		if id == userId then
			return true
		end
	end
	return false
end

local function onStateUpdate(state)
	if type(state) ~= "table" then
		return
	end
	local phase = state.Phase
	local timeLeft = tonumber(state.TimeLeft) or 0
	local myId = localPlayer.UserId
	local isParticipant = containsUserId(state.Participants, myId)
	local isTagger = state.TaggerUserId == myId

	roleLabel.TextColor3 = COLOR_NEUTRAL
	messageLabel.Text = state.Message or ""

	if phase == "Waiting" then
		phaseLabel.Text = "プレイヤー待ち"
		timerLabel.Text = string.format("あと %d 人", tonumber(state.PlayersNeeded) or 0)
		roleLabel.Text = string.format("%d人そろうと始まります", tonumber(state.MinPlayers) or Config.MinPlayers)
		messageLabel.Text = ""
	elseif phase == "Intermission" then
		phaseLabel.Text = "まもなく開始"
		timerLabel.Text = string.format("%d 秒", timeLeft)
		roleLabel.Text = "鬼はランダムに1人選ばれます"
	elseif phase == "Round" then
		phaseLabel.Text = "鬼ごっこ中"
		timerLabel.Text = "残り " .. formatTime(timeLeft)
		if isTagger then
			roleLabel.Text = "あなたは 鬼！ 逃げる人にタッチしよう"
			roleLabel.TextColor3 = COLOR_TAGGER
		elseif isParticipant then
			local taggerName = state.TaggerName or ""
			roleLabel.Text = "逃げろ！ 鬼: " .. taggerName
			roleLabel.TextColor3 = COLOR_RUNNER
		else
			roleLabel.Text = "観戦中（次のラウンドから参加）"
		end
	elseif phase == "Results" then
		phaseLabel.Text = "結果発表"
		timerLabel.Text = ""
		if containsUserId(state.Eliminated, myId) then
			roleLabel.Text = "落下で脱落"
		elseif containsUserId(state.Winners, myId) then
			roleLabel.Text = "あなたの勝ち！ 逃げ切り成功！"
			roleLabel.TextColor3 = COLOR_WIN
		elseif isParticipant then
			roleLabel.Text = "残念… 次は逃げ切ろう"
		else
			roleLabel.Text = ""
		end
	end
end

StateUpdate.OnClientEvent:Connect(onStateUpdate)

---------------------------------------------------------------------
-- お知らせメッセージ（数秒で消える）
---------------------------------------------------------------------

local notifyToken = 0

Notify.OnClientEvent:Connect(function(text)
	if type(text) ~= "string" then
		return
	end
	notifyToken = notifyToken + 1
	local myToken = notifyToken
	notifyLabel.Text = text
	notifyLabel.Visible = true
	task.delay(3, function()
		if notifyToken == myToken then
			notifyLabel.Visible = false
		end
	end)
end)

---------------------------------------------------------------------
-- 自分の段位と RP（leaderstats を読むだけ。新しい Remote は使わない）
---------------------------------------------------------------------

local function refreshRank()
	local folder = localPlayer:FindFirstChild("leaderstats")
	if not folder then
		rankLabel.Text = "ランクを読み込み中"
		rankLabel.TextColor3 = COLOR_NEUTRAL
		return
	end
	local rpStat = folder:FindFirstChild(Config.LeaderstatNames.RP)
	local rankStat = folder:FindFirstChild(Config.LeaderstatNames.Rank)
	local rp = rpStat and tonumber(rpStat.Value) or 0
	local rankName = rankStat and rankStat.Value or ""
	local tier = Config.TierForRP(rp)
	if rankName == "" and tier then
		rankName = tier.Name
	end
	local nextTier = Config.NextTierForRP(rp)
	if nextTier then
		local remain = math.max(0, nextTier.MinRP - rp)
		rankLabel.Text = string.format("%s  RP %d  次の段位まであと%dRP", rankName, rp, remain)
	else
		rankLabel.Text = string.format("%s  RP %d  最高段位", rankName, rp)
	end
	rankLabel.TextColor3 = (tier and tier.Color) or COLOR_NEUTRAL
end

task.spawn(function()
	local folder = localPlayer:WaitForChild("leaderstats")
	local rpStat = folder:WaitForChild(Config.LeaderstatNames.RP)
	local rankStat = folder:WaitForChild(Config.LeaderstatNames.Rank)
	rpStat.Changed:Connect(refreshRank)
	rankStat.Changed:Connect(refreshRank)
	refreshRank()
end)

---------------------------------------------------------------------
-- 昇格（段位が上がった瞬間だけ。数秒で消える）
---------------------------------------------------------------------

local rankUpLabel = makeLabel("RankUp", gui, UDim2.new(0, 640, 0, 44), UDim2.new(0.5, 0, 0.42, 0), 28)
rankUpLabel.TextColor3 = COLOR_WIN
rankUpLabel.Visible = false

local rankUpToken = 0

local function colorForRankName(rankName)
	for _, tier in ipairs(Config.RankTiers) do
		if tier.Name == rankName then
			return tier.Color
		end
	end
	return COLOR_WIN
end

RankUp.OnClientEvent:Connect(function(rankName)
	if type(rankName) ~= "string" or rankName == "" then
		return
	end
	rankUpToken = rankUpToken + 1
	local myToken = rankUpToken
	rankUpLabel.Text = "ランクアップ！ " .. rankName .. "に昇格"
	rankUpLabel.TextColor3 = colorForRankName(rankName)
	rankUpLabel.Visible = true
	task.delay(4, function()
		if rankUpToken == myToken then
			rankUpLabel.Visible = false
		end
	end)
end)
