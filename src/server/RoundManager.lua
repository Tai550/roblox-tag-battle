-- RoundManager: ラウンド進行（待機 → 鬼の選出 → ラウンド → 結果）とタッチ判定
-- タッチ判定はサーバーが鬼と逃げる人の距離を測って行う（クライアントは信用しない）。
-- 人間が最低人数以上かつ目標未満のとき、BotManager が足りない分のボットを参加者に足す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local TaggerLook = require(script.Parent:WaitForChild("TaggerLook"))
local BotManager = require(script.Parent:WaitForChild("BotManager"))

local RoundManager = {}

-- ボットはプレーンなテーブル。Player の未知プロパティは読まない。
local function isBot(entity)
	return type(entity) == "table" and entity.IsBot == true
end

local function countHumanParticipants()
	local count = 0
	for _, participant in ipairs(GameState.ParticipantList()) do
		if not isBot(participant) then
			count = count + 1
		end
	end
	return count
end

local broadcastState -- 下の「状態の送信」で定義する（投票ハンドラからも使うため先に宣言）

-- このラウンドで「まだ鬼になっていない人」を最後に捕まえた鬼。
-- 結果が「逃げ切りゼロ」で確定したときだけ、追加 RP を渡す。
local sweepTagger = nil

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
	if isBot(player) then
		return
	end
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
	-- 鬼の見た目は GameState.Tagger と必ず同じ相手に付ける（交代・離脱後の再選出もここ）
	TaggerLook.Follow(newTagger)
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

-- タッチが確定したときの記録と RP。
-- 「全員捕まえた」の追加点は、ここでは保留して勝敗確定時に渡す。
local function awardForTag(tagger, runner)
	RankManager.AddCount(runner, "Tagged")
	RankManager.Award(tagger, Config.RankPoints.Tag)
	RankManager.Award(runner, Config.RankPoints.Caught)

	local caughtEveryone = true
	for _, participant in ipairs(GameState.ParticipantList()) do
		if participant ~= tagger and participant ~= runner and not GameState.BeenTagger[participant] then
			caughtEveryone = false
			break
		end
	end
	if caughtEveryone then
		sweepTagger = tagger
	end
end

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
					awardForTag(tagger, runner)
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
	sweepTagger = nil
	GameState.Participants = {}
	GameState.BeenTagger = {}
	GameState.Winners = {}
	BotManager.DespawnAll()
	local humans = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if GameState.IsAlive(player) then
			GameState.Participants[player] = true
			GameState.ResetData(player)
			table.insert(humans, player)
		end
	end
	-- 人間が MinPlayers 未満なら始めない。ボットだけでは始めない。
	if #humans < Config.MinPlayers then
		GameState.Participants = {}
		return nil -- そもそも始められない（キャラクター未読み込みなど）
	end

	-- ラウンドが始まる直前（インターミッションのあと、試合の処理より前）にマップを用意する。
	-- 1回目は渋谷、2回目はパーク、以降は交互。ここはラウンドにつき一度だけなので、
	-- Phase が Round のあいだにマップは変わらない。始められなかったときは進めない。
	MapBuilder.BuildNextRound()

	local duration = GameState.ChosenDuration

	GameState.Phase = "Round"
	GameState.Message = ""
	GameState.TimeLeft = duration
	-- 人間が目標未満のときだけ差分をボットで補う。マップ生成のあと（スポーン位置が決まったあと）
	BotManager.Fill(humans)
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

		-- 抜けた人間を参加者から外す。ボットは Players に居ないので、ここでは外さない。
		for _, player in ipairs(GameState.ParticipantList()) do
			if not isBot(player) and player.Parent ~= Players then
				GameState.Participants[player] = nil
				GameState.BeenTagger[player] = nil
			end
		end
		-- 人間が一人もいなくなったらボットだけでは続けない。合計が最低人数未満でも中止。
		if countHumanParticipants() < 1 or GameState.CountParticipants() < Config.MinPlayers then
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
		BotManager.Tick()
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
	BotManager.Halt()
	ItemManager.Stop()
	ZoneManager.Stop()

	local winners = {}
	if completed then
		for _, player in ipairs(GameState.ParticipantList()) do
			local stillHere = isBot(player) or player.Parent == Players
			if stillHere and not GameState.BeenTagger[player] then
				table.insert(winners, player)
				-- RP と記録は人間だけ。RankManager の入口でもボットは弾く
				if not isBot(player) then
					RankManager.AddCount(player, "Survived")
					RankManager.Award(player, Config.RankPoints.Survived)
				end
			end
		end
		-- 逃げ切った人がいない＝鬼側の勝ち。最後にタッチした鬼へ追加点。ボットには付けない。
		if #winners == 0 and sweepTagger and not isBot(sweepTagger) and sweepTagger.Parent == Players then
			RankManager.Award(sweepTagger, Config.RankPoints.TaggedAll)
		end
	end

	GameState.Phase = "Results"
	GameState.Tagger = nil
	TaggerLook.Follow(nil) -- ラウンド終了で、残っている鬼の色と Highlight を全員分外す
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
	BotManager.DespawnAll() -- ラウンドが終わったらボットを残さない
end

---------------------------------------------------------------------
-- 初期化とメインループ
---------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		GameState.RefreshSpeed(player)
		ItemManager.OnCharacterAdded(player)
		TaggerLook.OnCharacterAdded(player) -- 鬼のままリスポーンしたら色と Highlight を付け直す
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
		TaggerLook.Clear(player)
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
