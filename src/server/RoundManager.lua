-- RoundManager: 試合の進行（待機 → インターミッション → 鬼ごっこ → 結果）とタッチ判定
-- タッチ判定はサーバーが鬼と逃げる人の距離を測って行う（クライアントは信用しない）。
--
-- 勝ち負け:
--   ・時間いっぱい逃げ切った人の中で、鬼にタッチされた回数が少ない人ほど上位
--   ・一度もタッチされずに逃げ切った人が「優勝」
--   ・終了の瞬間に鬼だった人は負け
--   ・エリア外で脱落した人は最下位（あとまで残った人ほど上）
--   ・タッチ返しなし：鬼になった人は、自分にタッチした人を（別の人が鬼になるまで）タッチできない
-- 人数が足りないときは BotManager がボットで補う（ひとりモードはボットだけが相手）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))
local MatchSession = require(script.Parent:WaitForChild("MatchSession"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))
local BotManager = require(script.Parent:WaitForChild("BotManager"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local TaggerLook = require(script.Parent:WaitForChild("TaggerLook"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

local RoundManager = {}

local broadcastState -- 下の「状態の送信」で定義する
local soloRound = false -- このラウンドをボットと遊ぶか
local moveHumansToSpawn -- 下で定義する

---------------------------------------------------------------------
-- 試合時間の投票
---------------------------------------------------------------------

local votes = {}          -- [Player] = 投票した秒数
local voteCounts = {}     -- [秒数] = 票数（表示用）
local displayDuration = Config.DefaultDuration

for _, duration in ipairs(Config.MatchDurations) do
	voteCounts[duration] = 0
end

-- 投票を集計する（計算だけの関数。テストからも呼べる）。
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
	if GameState.Phase ~= "Intermission" then
		return
	end
	local duration = tonumber(durationArg)
	if not duration then
		return
	end
	for _, candidate in ipairs(Config.MatchDurations) do
		if candidate == duration then
			votes[player] = duration
			refreshVoteDisplay()
			broadcastState()
			return
		end
	end
end

---------------------------------------------------------------------
-- 順位とコイン（計算だけの関数。テストからも呼べる）
---------------------------------------------------------------------

-- entries: { { Key = 何でも, Tags = タッチされた回数, FinalTagger = true/false, EliminatedOrder = nil か 1,2,... } }
-- 戻り値: 順位の高い順に並べた配列。各要素に Rank / Coins / Status / Champion を足したもの
function RoundManager.ComputeResults(entries)
	local survivors, finalTaggers, eliminated = {}, {}, {}
	for _, entry in ipairs(entries) do
		if entry.EliminatedOrder then
			table.insert(eliminated, entry)
		elseif entry.FinalTagger then
			table.insert(finalTaggers, entry)
		else
			table.insert(survivors, entry)
		end
	end
	table.sort(survivors, function(a, b)
		return a.Tags < b.Tags
	end)
	table.sort(eliminated, function(a, b)
		return a.EliminatedOrder > b.EliminatedOrder -- あとで脱落した人ほど上
	end)

	local rewards = Config.CoinRewards
	local results = {}
	local rank = 0
	local lastTags = nil
	for index, entry in ipairs(survivors) do
		if entry.Tags ~= lastTags then
			rank = index
			lastTags = entry.Tags
		end
		local champion = entry.Tags == 0
		entry.Rank = rank
		entry.Champion = champion
		entry.Status = champion and "優勝" or "逃げ切り"
		entry.Coins = champion and rewards.Champion
			or math.max(rewards.SurvivorMin, rewards.Survivor - rewards.PerTagPenalty * entry.Tags)
		table.insert(results, entry)
	end
	for _, entry in ipairs(finalTaggers) do
		entry.Rank = #results + 1
		entry.Champion = false
		entry.Status = "最後の鬼"
		entry.Coins = rewards.FinalTagger
		table.insert(results, entry)
	end
	for _, entry in ipairs(eliminated) do
		entry.Rank = #results + 1
		entry.Champion = false
		entry.Status = "脱落"
		entry.Coins = rewards.Eliminated
		table.insert(results, entry)
	end
	return results
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
		Eliminated = userIdList(GameState.Eliminated),
		Results = GameState.Results,
		Message = GameState.Message,
		ChosenDuration = displayDuration,
		VoteCounts = countsForClient,
		Mode = MatchSession.Mode,
		RoomCode = MatchSession.Code,
		HostUserId = MatchSession.GetHostUserId(),
	})
end

---------------------------------------------------------------------
-- 鬼の設定
---------------------------------------------------------------------

-- tagBackFrom: タッチで交代したときの前の鬼。新しい鬼はこの人にタッチ返しできない。
-- 脱落・離脱などタッチ以外の交代では nil（誰にでもタッチできる）
local function setTagger(newTagger, tagBackFrom)
	local oldTagger = GameState.Tagger
	GameState.Tagger = newTagger
	GameState.NoTagBack = tagBackFrom
	GameState.TaggerSince = GameState.Now()
	if newTagger then
		GameState.BeenTagger[newTagger] = true
		GameState.RefreshSpeed(newTagger)
	end
	if oldTagger and oldTagger ~= newTagger then
		GameState.RefreshSpeed(oldTagger)
	end
	-- 鬼の見た目（少し赤く＋Highlight）は GameState.Tagger と必ず同じ相手に付ける
	TaggerLook.Follow(newTagger)
	broadcastState()
end

-- タッチ返しの禁止に当たるか（計算だけの関数。テストからも呼べる）
function RoundManager.IsTagBackBlocked(runner, noTagBack)
	return noTagBack ~= nil and runner == noTagBack
end

local function pickRandomParticipant(except)
	local list = {}
	for _, player in ipairs(GameState.ParticipantList()) do
		if player ~= except then
			table.insert(list, player)
		end
	end
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

---------------------------------------------------------------------
-- 観戦席と脱落
---------------------------------------------------------------------

local function sendToSpectator(player)
	local character = player.Character
	if character then
		local offset = Vector3.new(math.random(-6, 6), 3, math.random(-6, 6))
		local target = Config.SpectatorPosition + offset
		character:PivotTo(CFrame.new(target.X, target.Y, target.Z))
	end
end

local function isEliminated(player)
	for _, other in ipairs(GameState.Eliminated) do
		if other == player then
			return true
		end
	end
	return false
end

-- reason: 「エリア外」「落下」など、全員に知らせる理由
local function eliminate(player, reason)
	if not GameState.IsParticipant(player) then
		return
	end
	GameState.Participants[player] = nil
	table.insert(GameState.Eliminated, player)
	sendToSpectator(player)
	Remotes.NotifyPlayer(player, "脱落… 観戦席から見守ろう")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			Remotes.NotifyPlayer(other, player.DisplayName .. " が" .. (reason or "エリア外") .. "で脱落！")
		end
	end
	if GameState.Tagger == player then
		local replacement = pickRandomParticipant(player)
		setTagger(replacement)
		if replacement then
			Remotes.NotifyPlayer(replacement, "鬼が脱落したので、あなたが新しい鬼です！")
		end
	end
	broadcastState()
end

-- 落下ダンジョン：足場から落ちたら脱落（命綱を持っていれば最後の足場に戻る）
function RoundManager.CheckSkyFalls()
	if GameState.Phase ~= "Round" or MapBuilder.CurrentMap ~= "Sky" then
		return
	end
	local platforms = MapBuilder.GetSkyPlatforms()
	if not platforms then
		return
	end
	local query = RaycastParams.new()
	query.FilterType = Enum.RaycastFilterType.Include
	query.FilterDescendantsInstances = { platforms }
	for _, player in ipairs(GameState.ParticipantList()) do
		local root = GameState.GetRootPart(player)
		local humanoid = GameState.GetHumanoid(player)
		if root and humanoid and humanoid.Health > 0 then
			local data = GameState.GetData(player)
			if root.Position.Y < Config.FallEliminateY then
				if not ItemManager.TrySafetyLine(player) then
					eliminate(player, "落下")
				end
			elseif humanoid.FloorMaterial ~= Enum.Material.Air then
				local reach = math.max(6, humanoid.HipHeight + root.Size.Y / 2 + 1)
				if workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), query) then
					data.LastSkyStand = player.Character:GetPivot()
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- タッチ判定
---------------------------------------------------------------------

-- 試合中の自分の記録（右上の表示用）。Player の属性に書くので、ボットには書かない
local function addRoundStat(player, attribute, amount)
	if player and not BotManager.IsBot(player) then
		player:SetAttribute(attribute, (player:GetAttribute(attribute) or 0) + amount)
	end
end

local function awardRoundRP(player, amount)
	local credited = RankManager.Award(player, amount)
	if credited then
		addRoundStat(player, "RoundRP", credited)
	end
end

-- 「手が届いたらタッチ」：鬼の胸の少し前から、相手の体のいちばん近い表面までの距離で判定する
-- 体が重なっている・頭の上に乗っているときもタッチ（正面の判定だけだと、真上や真後ろで取りこぼす）
function RoundManager.IsBodyContact(taggerPos, runner)
	local root = GameState.GetRootPart(runner)
	if not root then
		return false
	end
	local offset = root.Position - taggerPos
	if offset.Magnitude <= Config.TagBodyDistance then
		return true
	end
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return flat <= Config.TagStackRadius and math.abs(offset.Y) <= 6
end

local function isWithinTagReach(origin, character)
	if not character then
		return false
	end
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			local localOrigin = part.CFrame:PointToObjectSpace(origin)
			local halfSize = part.Size * 0.5
			local closest = Vector3.new(
				math.clamp(localOrigin.X, -halfSize.X, halfSize.X),
				math.clamp(localOrigin.Y, -halfSize.Y, halfSize.Y),
				math.clamp(localOrigin.Z, -halfSize.Z, halfSize.Z)
			)
			if (localOrigin - closest).Magnitude <= Config.TagTouchDistance then
				return true
			end
		end
	end
	return false
end

function RoundManager.TryTag()
	local tagger = GameState.Tagger
	if not tagger then
		return
	end
	local now = GameState.Now()
	if now - GameState.TaggerSince < Config.TagCooldown then
		return
	end
	if not GameState.IsAlive(tagger) then
		return
	end
	local taggerRoot = GameState.GetRootPart(tagger)
	if not taggerRoot then
		return
	end

	local origin = taggerRoot.Position + taggerRoot.CFrame.LookVector * Config.TagReachForward
	for _, runner in ipairs(GameState.ParticipantList()) do
		if runner ~= tagger and GameState.IsAlive(runner)
			and not RoundManager.IsTagBackBlocked(runner, GameState.NoTagBack) then
			if isWithinTagReach(origin, runner.Character) or RoundManager.IsBodyContact(taggerRoot.Position, runner) then
				local data = GameState.GetData(runner)
				if data.InvulnerableUntil > now then
					-- シールドで防いだ直後なのでタッチ無効
				elseif GameState.HasStar(runner) then
					-- スターの効果中なのでタッチ無効
				elseif ItemManager.ConsumeShield(runner) then
					Remotes.NotifyPlayer(runner, "シールドがタッチを防いだ！ 今のうちに逃げよう")
					Remotes.NotifyPlayer(tagger, runner.DisplayName .. " のシールドに防がれた！")
				else
					GameState.TagCounts[runner] = (GameState.TagCounts[runner] or 0) + 1
					Leaderstats.Set(runner, "Tagged", GameState.TagCounts[runner])
					RankManager.AddCount(runner, "Tagged")
					addRoundStat(tagger, "RoundTags", 1)
					addRoundStat(runner, "RoundCaught", 1)
					awardRoundRP(tagger, Config.RankPoints.Tag)
					awardRoundRP(runner, Config.RankPoints.Caught)
					Remotes.NotifyPlayer(runner, "タッチされた！ 今度はあなたが鬼！（" .. tagger.DisplayName .. " にはタッチ返しできない）")
					Remotes.NotifyPlayer(tagger, runner.DisplayName .. " にタッチ！ 鬼を交代した")
					setTagger(runner, tagger)
					return -- 1回の判定で交代は1人まで
				end
			end
		end
	end
end

---------------------------------------------------------------------
-- 各フェーズ
---------------------------------------------------------------------

local function setPhase(phase, message, timeLeft)
	GameState.Phase = phase
	GameState.Message = message or ""
	GameState.TimeLeft = timeLeft or 0
	broadcastState()
end

-- Studio: 人数がそろうまで待つ。1人のまましばらくたったらボットと遊ぶ
local function waitForMinPlayers()
	local aloneSince = nil
	while true do
		local count = #Players:GetPlayers()
		if count >= Config.MinPlayers then
			soloRound = false
			return true
		end
		if count == 1 then
			aloneSince = aloneSince or GameState.Now()
			if GameState.Now() - aloneSince >= Config.StudioSoloAfter then
				soloRound = true
				return true
			end
		else
			aloneSince = nil
		end
		GameState.PlayersNeeded = Config.MinPlayers - count
		setPhase("Waiting", string.format("あと%d人で開始できます", GameState.PlayersNeeded))
		task.wait(1)
	end
end

-- Quick: ロビーから一緒に来た人がそろうのを待つ。そろわなければロビーへ戻す
local function waitForArrivals()
	local deadline = GameState.Now() + Config.MatchArrivalTimeout
	while true do
		local count = #Players:GetPlayers()
		local expected = math.max(Config.MinPlayers, MatchSession.Expected)
		if count >= expected then
			return true
		end
		local left = deadline - GameState.Now()
		if left <= 0 then
			if count >= Config.MinPlayers then
				return true
			end
			setPhase("Waiting", "人数が集まらなかったので、ロビーへ戻ります")
			task.wait(3)
			MatchSession.SendToLobby(Players:GetPlayers())
			task.wait(10)
			return false
		end
		GameState.PlayersNeeded = math.max(0, expected - count)
		setPhase("Waiting", string.format("みんなの到着を待っています（%d/%d）", count, expected), left)
		task.wait(1)
	end
end

-- Friends: ホストが「開始」を押すのを待つ
local function waitForHost()
	MatchSession.StartRequested = false
	while true do
		local count = #Players:GetPlayers()
		if MatchSession.StartRequested then
			MatchSession.StartRequested = false
			if count >= Config.MinPlayers then
				return true
			end
		end
		local host = MatchSession.GetHost()
		local hostName = host and host.DisplayName or "ホスト"
		GameState.PlayersNeeded = math.max(0, Config.MinPlayers - count)
		if count < Config.MinPlayers then
			setPhase("RoomWaiting", string.format("友達を待っています。合言葉: %s", MatchSession.Code))
		else
			setPhase("RoomWaiting", string.format("%s が「開始」を押すと始まります（%d人）", hostName, count))
		end
		task.wait(0.5)
	end
end

-- Solo: 本人が来たらすぐ始める
local function waitForSoloPlayer()
	while #Players:GetPlayers() == 0 do
		setPhase("Waiting", "準備中…")
		task.wait(0.5)
	end
	soloRound = true
	return true
end

-- 人数が足りなくなったら false
local function runIntermission()
	setPhase("Intermission", "まもなく鬼ごっこが始まります。試合時間に投票しよう")
	votes = {}
	refreshVoteDisplay()
	local endTime = GameState.Now() + Config.IntermissionTime
	while true do
		local left = endTime - GameState.Now()
		if left <= 0 then
			break
		end
		local needed = soloRound and 1 or Config.MinPlayers
		if #Players:GetPlayers() < needed then
			return false
		end
		GameState.TimeLeft = left
		broadcastState()
		task.wait(math.min(1, left))
	end
	GameState.ChosenDuration = RoundManager.TallyVotes(votes)
	displayDuration = GameState.ChosenDuration
	return true
end

-- マップを入れ替えたあと、人間を新しいマップの出現場所へ移す
moveHumansToSpawn = function()
	local spawnPart = nil
	local map = workspace:FindFirstChild("Map")
	if map then
		spawnPart = map:FindFirstChildWhichIsA("SpawnLocation", true)
	end
	local sky = MapBuilder.CurrentMap == "Sky"
	if sky then
		local platforms = MapBuilder.GetSkyPlatforms()
		spawnPart = platforms and platforms:FindFirstChild("ArenaStart") or spawnPart
	end
	local base = spawnPart and (spawnPart.Position + Vector3.new(0, spawnPart.Size.Y / 2, 0)) or Config.FallbackSpawnCenter
	for index, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			local angle = index / math.max(1, #Players:GetPlayers()) * math.pi * 2
			local destination = CFrame.new(base + Vector3.new(math.cos(angle) * 6, 4, math.sin(angle) * 6))
			character:PivotTo(destination)
			if sky then
				GameState.GetData(player).LastSkyStand = destination
			end
		end
	end
end

-- 試合本体。戻り値: 試合をしたら true、始められなかったら false
local function runRound()
	GameState.Participants = {}
	GameState.BeenTagger = {}
	GameState.Winners = {}
	GameState.TagCounts = {}
	GameState.Eliminated = {}
	GameState.Results = {}
	GameState.NoTagBack = nil
	Leaderstats.ResetAll()
	BotManager.Clear()
	-- 2試合目からはマップを入れ替える（1試合目は起動時に作ったマップ）
	local mapChanged = MapBuilder.PrepareRound()
	if mapChanged or MapBuilder.CurrentMap == "Sky" then
		moveHumansToSpawn()
	end
	local entrants = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if GameState.IsAlive(player) then
			table.insert(entrants, player)
		end
	end
	local bots
	if soloRound then
		bots = BotManager.Spawn(Config.SoloBotCount, { SoloCap = true })
	else
		-- 人間が目標人数（8人）未満なら、差分をボットで補う
		bots = BotManager.Fill(entrants)
	end
	if #bots > 0 then
		for _, bot in ipairs(bots) do
			table.insert(entrants, bot)
		end
		task.wait(0.5) -- ボットの体が落ち着くのを待つ
	end
	for _, player in ipairs(entrants) do
		if GameState.IsAlive(player) then
			GameState.Participants[player] = true
			GameState.TagCounts[player] = 0
			GameState.ResetData(player)
			GameState.RefreshSpeed(player)
		end
	end
	if GameState.CountParticipants() < Config.MinPlayers then
		BotManager.Clear()
		GameState.Participants = {}
		return false
	end
	local roster = GameState.ParticipantList() -- 結果に載せる人（途中で抜けた人は除く）

	local duration = GameState.ChosenDuration
	GameState.Phase = "Round"
	GameState.Message = ""
	GameState.TimeLeft = duration
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("RoundTags", 0)
		player:SetAttribute("RoundCaught", 0)
		player:SetAttribute("RoundRP", 0)
	end
	local info = MapBuilder.GetCurrentMapInfo()
	if info then
		Remotes.Notify:FireAllClients("このマップ：" .. info.Name)
	end
	ItemManager.Start()
	ZoneManager.Start(duration)

	local firstTagger = pickRandomParticipant()
	setTagger(firstTagger)
	Remotes.NotifyPlayer(firstTagger, "あなたが最初の鬼です！ 3秒後からタッチできます")
	ItemManager.DeliverPendingItems()

	local endTime = GameState.Now() + duration
	local nextBroadcast = 0

	while true do
		local now = GameState.Now()
		local left = endTime - now
		if left <= 0 then
			break
		end

		-- 抜けたプレイヤーを参加者から外す
		local humansLeft = 0
		for _, player in ipairs(GameState.ParticipantList()) do
			if BotManager.IsBot(player) then
				-- ボットは Players にいないので外さない
			elseif player.Parent ~= Players then
				GameState.Participants[player] = nil
			else
				humansLeft = humansLeft + 1
			end
		end
		-- 残りが1人以下、または人間が残っていない（全員脱落・離脱）なら終わり
		if GameState.CountParticipants() < 2 or humansLeft == 0 then
			break
		end

		local tagger = GameState.Tagger
		if not tagger or not GameState.IsParticipant(tagger) then
			local replacement = pickRandomParticipant()
			setTagger(replacement)
			if replacement then
				Remotes.NotifyPlayer(replacement, "鬼がいなくなったので、あなたが新しい鬼です！")
			end
		end

		RoundManager.TryTag()
		ItemManager.Tick()
		ZoneManager.Tick()
		RoundManager.CheckSkyFalls()
		BotManager.Tick()

		if now >= nextBroadcast then
			GameState.TimeLeft = left
			broadcastState()
			nextBroadcast = now + 1
		end

		task.wait(Config.TagCheckInterval)
	end

	-- 結果を作る
	local entries = {}
	for _, player in ipairs(roster) do
		if BotManager.IsBot(player) or player.Parent == Players then
			local eliminatedOrder = nil
			for index, other in ipairs(GameState.Eliminated) do
				if other == player then
					eliminatedOrder = index
				end
			end
			table.insert(entries, {
				Key = player,
				Tags = GameState.TagCounts[player] or 0,
				FinalTagger = GameState.Tagger == player,
				EliminatedOrder = eliminatedOrder,
			})
		end
	end
	local results = RoundManager.ComputeResults(entries)
	local forClient = {}
	local winners = {}
	for _, entry in ipairs(results) do
		local player = entry.Key
		if BotManager.IsBot(player) then
			entry.Coins = 0 -- ボットはコインをもらわない
		elseif soloRound then
			entry.Coins = math.floor(entry.Coins * Config.SoloCoinRate)
		end
		table.insert(forClient, {
			UserId = player.UserId,
			Name = player.DisplayName,
			Rank = entry.Rank,
			Tags = entry.Tags,
			Coins = entry.Coins,
			Status = entry.Status,
		})
		if entry.Champion then
			table.insert(winners, player)
		end
		if not BotManager.IsBot(player) then
			task.spawn(PlayerDataStore.AddCoins, player, entry.Coins, entry.Champion)
			-- 段位の RP：一度もタッチされずに逃げ切った人（優勝）に加点
			if entry.Champion then
				RankManager.AddCount(player, "Survived")
				awardRoundRP(player, Config.RankPoints.Survived)
			end
		end
		Remotes.NotifyPlayer(player, string.format("%d位！ %d コインもらった", entry.Rank, entry.Coins))
	end
	GameState.Results = forClient
	GameState.Winners = winners
	return true
end

local function runResults()
	BotManager.Halt()
	ItemManager.Stop()
	ZoneManager.Stop()
	GameState.Tagger = nil
	GameState.NoTagBack = nil
	TaggerLook.Follow(nil) -- 鬼の色と Highlight を外す
	GameState.Participants = {}
	GameState.RefreshAllSpeeds()

	local message
	if #GameState.Winners > 0 then
		local names = {}
		for _, player in ipairs(GameState.Winners) do
			table.insert(names, player.DisplayName)
		end
		message = "優勝: " .. table.concat(names, "、")
	else
		message = "一度もタッチされずに逃げ切った人はいませんでした"
	end

	-- 観戦席の人を地上に戻す
	for _, player in ipairs(GameState.Eliminated) do
		if not BotManager.IsBot(player) and player.Parent == Players then
			player:LoadCharacter()
		end
	end

	local endTime = GameState.Now() + Config.ResultsTime
	while true do
		local left = endTime - GameState.Now()
		if left <= 0 then
			break
		end
		setPhase("Results", message, left)
		task.wait(math.min(1, left))
	end
	GameState.Eliminated = {}
	BotManager.Clear()
end

---------------------------------------------------------------------
-- 初期化とメインループ
---------------------------------------------------------------------

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	GameState.RefreshSpeed(player)
	ItemManager.OnCharacterAdded(player)
	TaggerLook.OnCharacterAdded(player) -- 鬼のままリスポーンしたら色を付け直す
	-- 落下ダンジョンで試合中にリスポーンした参加者は、中央の足場へ戻す
	if GameState.Phase == "Round" and MapBuilder.CurrentMap == "Sky" and GameState.IsParticipant(player) then
		local platforms = MapBuilder.GetSkyPlatforms()
		local start = platforms and platforms:FindFirstChild("ArenaStart")
		if start then
			local destination = CFrame.new(start.Position + Vector3.new(0, start.Size.Y / 2 + 4, 0))
			character:PivotTo(destination)
			GameState.GetData(player).LastSkyStand = destination
		end
	end
	-- 試合中に参加していない人（脱落した人・途中から来た人）は観戦席へ
	if GameState.Phase == "Round" and not GameState.IsParticipant(player) then
		task.wait(0.2)
		sendToSpectator(player)
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
	ZoneManager.OnEliminate = eliminate
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		GameState.Participants[player] = nil
		GameState.BeenTagger[player] = nil
		if GameState.NoTagBack == player then
			GameState.NoTagBack = nil
		end
		TaggerLook.Clear(player)
		ItemManager.EndPhase(player)
		GameState.ClearStun(player)
		GameState.ClearData(player)
		votes[player] = nil
		refreshVoteDisplay()
	end)
end

RoundManager.IsEliminated = isEliminated

function RoundManager.Run()
	while true do
		local mode = MatchSession.Mode
		local ready
		if mode == "Pending" then
			setPhase("Waiting", "部屋の準備中…")
			task.wait(0.5)
			ready = false
		elseif mode == "Stray" then
			setPhase("Waiting", "ロビーへ移動します…")
			task.wait(5)
			ready = false
		elseif mode == "Quick" then
			soloRound = false
			ready = waitForArrivals()
		elseif mode == "Friends" then
			soloRound = false
			ready = waitForHost()
		elseif mode == "Solo" then
			ready = waitForSoloPlayer()
		else
			ready = waitForMinPlayers()
		end

		if ready and runIntermission() then
			if runRound() then
				runResults()
				if MatchSession.Mode == "Quick" then
					-- 1試合ごとに全員ロビーへ戻る
					setPhase("Results", "ロビーへ戻ります…")
					MatchSession.SendToLobby(Players:GetPlayers())
					task.wait(15)
				end
			else
				task.wait(1)
			end
		end
	end
end

return RoundManager
