-- RoundManager: ラウンド進行（待機 → 鬼の選出 → ラウンド → 結果）とタッチ判定
-- タッチ判定はサーバーが鬼と逃げる人の距離を測って行う（クライアントは信用しない）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))

local RoundManager = {}

local broadcastState -- 下の「状態の送信」で定義する（投票ハンドラからも使うため先に宣言）

---------------------------------------------------------------------
-- 試合時間の投票
---------------------------------------------------------------------

local votes = {}          -- [Player] = 投票した秒数
local voteCounts = {}     -- [秒数] = 票数（表示用）
local displayDuration = Config.DefaultDuration -- 表示用の「今の決定時間」

for _, duration in ipairs(Config.MatchDurations) do
	voteCounts[duration] = 0
end

-- 投票を集計する（計算だけの関数。テストからも呼べる）。
-- 戻り値: 決まった秒数, { [秒数] = 票数 }
-- 最多票を採用する。同数が複数あるときと、投票がゼロのときは DefaultDuration。
function RoundManager.TallyVotes(voteMap)
	local counts = {}
	for _, duration in ipairs(Config.MatchDurations) do
		counts[duration] = 0
	end
	for _, duration in pairs(voteMap) do
		if counts[duration] ~= nil then
			counts[duration] = counts[duration] + 1
		end
	end

	local maxCount = 0
	for _, duration in ipairs(Config.MatchDurations) do
		if counts[duration] > maxCount then
			maxCount = counts[duration]
		end
	end

	local chosen = Config.DefaultDuration
	if maxCount > 0 then
		local leaders = {}
		for _, duration in ipairs(Config.MatchDurations) do
			if counts[duration] == maxCount then
				table.insert(leaders, duration)
			end
		end
		if #leaders == 1 then
			chosen = leaders[1]
		end
	end
	return chosen, counts
end

local function refreshVoteDisplay()
	displayDuration, voteCounts = RoundManager.TallyVotes(votes)
end

local function onDurationVote(player, durationArg)
	-- 投票できるのはインターミッション中だけ。値も Config の候補にあるものだけ
	if GameState.Phase ~= "Intermission" then
		return
	end
	local duration = tonumber(durationArg)
	if not duration then
		return
	end
	local valid = false
	for _, candidate in ipairs(Config.MatchDurations) do
		if candidate == duration then
			valid = true
			break
		end
	end
	if not valid then
		return
	end
	votes[player] = duration -- 投票し直したら上書き
	refreshVoteDisplay()
	broadcastState()
end

---------------------------------------------------------------------
-- 状態の送信
---------------------------------------------------------------------

local function userIdList(players)
	local ids = {}
	for _, player in ipairs(players) do
		table.insert(ids, player.UserId)
	end
	return ids
end

broadcastState = function()
	local tagger = GameState.Tagger
	-- VoteCounts のキーは文字列にする（RemoteEvent で数値キーの辞書が化けるのを避ける）
	local countsForClient = {}
	for _, duration in ipairs(Config.MatchDurations) do
		countsForClient[tostring(duration)] = voteCounts[duration] or 0
	end
	Remotes.StateUpdate:FireAllClients({
		Phase = GameState.Phase,
		TimeLeft = math.max(0, math.ceil(GameState.TimeLeft)),
		PlayersNeeded = GameState.PlayersNeeded,
		MinPlayers = Config.MinPlayers,
		TaggerUserId = tagger and tagger.UserId or 0,
		TaggerName = tagger and tagger.DisplayName or "",
		Participants = userIdList(GameState.ParticipantList()),
		Winners = userIdList(GameState.Winners),
		Message = GameState.Message,
		ChosenDuration = displayDuration,
		VoteCounts = countsForClient,
	})
end

---------------------------------------------------------------------
-- 鬼の設定
---------------------------------------------------------------------

local function setTagger(newTagger)
	local oldTagger = GameState.Tagger
	GameState.Tagger = newTagger
	GameState.TaggerSince = GameState.Now()

	if newTagger then
		GameState.BeenTagger[newTagger] = true
		GameState.RefreshSpeed(newTagger)
	end
	if oldTagger and oldTagger ~= newTagger then
		GameState.RefreshSpeed(oldTagger)
	end
	broadcastState()
end

local function pickRandomParticipant()
	local list = GameState.ParticipantList()
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

---------------------------------------------------------------------
-- タッチ判定
---------------------------------------------------------------------

local function tryTag()
	local tagger = GameState.Tagger
	if not tagger then
		return
	end
	local now = GameState.Now()
	if now - GameState.TaggerSince < Config.TagCooldown then
		return -- 鬼になった直後のクールダウン中
	end
	if not GameState.IsAlive(tagger) then
		return
	end
	local taggerRoot = GameState.GetRootPart(tagger)
	if not taggerRoot then
		return
	end

	for _, runner in ipairs(GameState.ParticipantList()) do
		if runner ~= tagger and GameState.IsAlive(runner) then
			local runnerRoot = GameState.GetRootPart(runner)
			if runnerRoot and (runnerRoot.Position - taggerRoot.Position).Magnitude <= Config.TagDistance then
				local data = GameState.GetData(runner)
				if data.InvulnerableUntil > now then
					-- シールドで防いだ直後なのでタッチ無効
				elseif GameState.HasStar(runner) then
					-- スターの効果中なのでタッチ無効（シールドは消費しない）
				elseif ItemManager.ConsumeShield(runner) then
					Remotes.NotifyPlayer(runner, "シールドがタッチを防いだ！ 今のうちに逃げよう")
					Remotes.NotifyPlayer(tagger, runner.DisplayName .. " のシールドに防がれた！")
				else
					Leaderstats.Increment(runner, "Tagged")
					Remotes.NotifyPlayer(runner, "タッチされた！ 今度はあなたが鬼！")
					Remotes.NotifyPlayer(tagger, runner.DisplayName .. " にタッチ！ 鬼を交代した")
					setTagger(runner)
					return -- 1回の判定で交代は1人まで
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- 各フェーズ
---------------------------------------------------------------------

local function runWaiting()
	while true do
		local count = #Players:GetPlayers()
		if count >= Config.MinPlayers then
			return
		end
		GameState.Phase = "Waiting"
		GameState.TimeLeft = 0
		GameState.PlayersNeeded = Config.MinPlayers - count
		GameState.Message = string.format("あと%d人で開始できます", GameState.PlayersNeeded)
		broadcastState()
		task.wait(1)
	end
end

-- 人数が足りなくなったら false を返す
local function runIntermission()
	GameState.Phase = "Intermission"
	GameState.PlayersNeeded = 0
	GameState.Message = "まもなく鬼ごっこが始まります"
	votes = {} -- 投票はインターミッションごとにリセット
	refreshVoteDisplay()
	local endTime = GameState.Now() + Config.IntermissionTime
	while true do
		local left = endTime - GameState.Now()
		if left <= 0 then
			break
		end
		if #Players:GetPlayers() < Config.MinPlayers then
			return false
		end
		GameState.TimeLeft = left
		broadcastState()
		task.wait(math.min(1, left))
	end
	-- 投票を確定する
	GameState.ChosenDuration = RoundManager.TallyVotes(votes)
	displayDuration = GameState.ChosenDuration
	return true
end

-- ラウンド本体。戻り値: 最後まで終わったら true、人数不足で中止したら false
local function runRound()
	GameState.Participants = {}
	GameState.BeenTagger = {}
	GameState.Winners = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if GameState.IsAlive(player) then
			GameState.Participants[player] = true
			GameState.ResetData(player)
		end
	end
	if GameState.CountParticipants() < Config.MinPlayers then
		GameState.Participants = {}
		return nil -- そもそも始められない（キャラクター未読み込みなど）
	end

	local duration = GameState.ChosenDuration

	GameState.Phase = "Round"
	GameState.Message = ""
	GameState.TimeLeft = duration
	ItemManager.Start()
	ZoneManager.Start(duration) -- 縮小エリアを開始（中心・開始半径は出現ポイントから決まる）

	local firstTagger = pickRandomParticipant()
	setTagger(firstTagger)
	Remotes.NotifyPlayer(firstTagger, "あなたが最初の鬼です！ 3秒後からタッチできます")
	ItemManager.DeliverPendingItems() -- ラウンド外に買ったアイテムボックスをここで渡す

	local endTime = GameState.Now() + duration
	local nextBroadcast = 0
	local completed = true

	while true do
		local now = GameState.Now()
		local left = endTime - now
		if left <= 0 then
			break
		end

		-- 抜けたプレイヤーを参加者から外す
		for _, player in ipairs(GameState.ParticipantList()) do
			if player.Parent ~= Players then
				GameState.Participants[player] = nil
				GameState.BeenTagger[player] = nil
			end
		end
		if GameState.CountParticipants() < Config.MinPlayers then
			completed = false
			break
		end

		-- 鬼が抜けたら、残った参加者からランダムに次の鬼を選ぶ
		local tagger = GameState.Tagger
		if not tagger or not GameState.IsParticipant(tagger) then
			local replacement = pickRandomParticipant()
			setTagger(replacement)
			Remotes.NotifyPlayer(replacement, "鬼が抜けたので、あなたが新しい鬼です！")
		end

		tryTag()
		ItemManager.Tick()
		ZoneManager.Tick()

		if now >= nextBroadcast then
			GameState.TimeLeft = left
			broadcastState()
			nextBroadcast = now + 1
		end

		task.wait(Config.TagCheckInterval)
	end

	return completed
end

local function runResults(completed)
	ItemManager.Stop()
	ZoneManager.Stop()

	local winners = {}
	if completed then
		for _, player in ipairs(GameState.ParticipantList()) do
			if player.Parent == Players and not GameState.BeenTagger[player] then
				table.insert(winners, player)
				Leaderstats.Increment(player, "Survived")
			end
		end
	end

	GameState.Phase = "Results"
	GameState.Tagger = nil
	GameState.Winners = winners
	GameState.RefreshAllSpeeds()

	if not completed then
		GameState.Message = "人数が足りなくなったため、ラウンドを中止しました"
	elseif #winners == 0 then
		GameState.Message = "逃げ切った人はいませんでした… 鬼の勝ち！"
	else
		local names = {}
		for _, player in ipairs(winners) do
			table.insert(names, player.DisplayName)
		end
		GameState.Message = "逃げ切り成功: " .. table.concat(names, "、")
	end

	local endTime = GameState.Now() + Config.ResultsTime
	while true do
		local left = endTime - GameState.Now()
		if left <= 0 then
			break
		end
		GameState.TimeLeft = left
		broadcastState()
		task.wait(math.min(1, left))
	end

	GameState.Participants = {}
	GameState.BeenTagger = {}
	GameState.Winners = {}
end

---------------------------------------------------------------------
-- 初期化とメインループ
---------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		GameState.RefreshSpeed(player)
		ItemManager.OnCharacterAdded(player)
	end
end

local function watchPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function RoundManager.Init()
	Remotes.DurationVote.OnServerEvent:Connect(onDurationVote)
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		GameState.Participants[player] = nil
		GameState.BeenTagger[player] = nil
		GameState.ClearData(player)
		votes[player] = nil
		refreshVoteDisplay()
		-- 鬼が抜けた場合の交代はラウンドのループ側で行う
	end)
end

function RoundManager.Run()
	while true do
		runWaiting()
		if runIntermission() then
			local completed = runRound()
			if completed == nil then
				task.wait(1) -- キャラクターの読み込み待ち。待機からやり直す
			else
				runResults(completed)
			end
		end
	end
end

return RoundManager
