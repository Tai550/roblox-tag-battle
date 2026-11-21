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
local VoltGimmicks = require(script.Parent:WaitForChild("VoltGimmicks"))

local RoundManager = {}

local broadcastState -- 下の「状態の送信」で定義する
local soloRound = false -- このラウンドをボットと遊ぶか
local moveHumansToSpawn -- 下で定義する

---------------------------------------------------------------------
-- 試合時間の投票
---------------------------------------------------------------------

local votes = {}          -- [Player] = 投票した秒数
local mapVotes = {}       -- [Player] = 投票したマップ Id

-- 管理者の操作（AdminManager から呼ぶ）
local startRequested = false   -- 待ちを飛ばしてすぐ始める
local endRequested = false     -- 試合をすぐ終わらせる
local nextMapRequested = false -- 次の試合は投票に関係なくローテーションの次のマップ
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

-- マップの投票を集計する（計算だけの関数）。
-- 戻り値: いちばん票の多いマップ Id（同数・無投票は nil ＝ローテーションの次）, 表示用の票数表
function RoundManager.TallyMapVotes(voteMap)
	local counts = {}
	for _, info in ipairs(Config.MatchMaps) do
		counts[info.Id] = 0
	end
	for _, id in pairs(voteMap) do
		if counts[id] then
			counts[id] = counts[id] + 1
		end
	end
	local best, bestCount, tie = nil, 0, false
	for _, info in ipairs(Config.MatchMaps) do
		local count = counts[info.Id]
		if count > bestCount then
			best, bestCount, tie = info.Id, count, false
		elseif count == bestCount and count > 0 then
			tie = true
		end
	end
	if tie then
		return nil, counts
	end
	return best, counts
end

local function onMapVote(player, id)
	if GameState.Phase ~= "Intermission" or BotManager.IsBot(player) or type(id) ~= "string" then
		return
	end
	local _, counts = RoundManager.TallyMapVotes({})
	if counts[id] == nil then
		return
	end
	mapVotes[player] = id
	broadcastState()
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

-- entries: Key / Tags / FinalTagger / ChampionEligible / EliminatedOrder（脱落順）
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
		local champion = entry.ChampionEligible == true and entry.Tags == 0
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
	local taggers = GameState.TaggerList()
	local taggerNames = {}
	for _, tagger in ipairs(taggers) do
		table.insert(taggerNames, tagger.DisplayName)
	end
	local countsForClient = {}
	for _, duration in ipairs(Config.MatchDurations) do
		countsForClient[tostring(duration)] = voteCounts[duration] or 0
	end
	Remotes.StateUpdate:FireAllClients({
		Phase = GameState.Phase,
		TimeLeft = math.max(0, math.ceil(GameState.TimeLeft)),
		PlayersNeeded = GameState.PlayersNeeded,
		MinPlayers = Config.MinPlayers,
		TaggerUserIds = userIdList(taggers),
		TaggerNames = taggerNames,
		Participants = userIdList(GameState.ParticipantList()),
		Eliminated = userIdList(GameState.Eliminated),
		Results = GameState.Results,
		Message = GameState.Message,
		ChosenDuration = displayDuration,
		VoteCounts = countsForClient,
		MapVoteCounts = select(2, RoundManager.TallyMapVotes(mapVotes)),
		CurrentMap = MapBuilder.CurrentMap,
		NextMap = MapBuilder.GetNextMapId(),
		Mode = MatchSession.Mode,
		RoomCode = MatchSession.Code,
		HostUserId = MatchSession.GetHostUserId(),
	})
end

---------------------------------------------------------------------
-- 鬼の設定
---------------------------------------------------------------------

local initialRunners = {}
local everTaggers = {}

local function hasInitialRunner()
	for player in pairs(initialRunners) do
		if GameState.IsParticipant(player) then
			return true
		end
	end
	return false
end

local function removeParticipant(player)
	ItemManager.ClearBeastEffects(player)
	GameState.ClearFreeze(player)
	GameState.Participants[player] = nil
	GameState.Uncaught[player] = nil
end

local function setTagger(oldTagger, newTagger, tagBackFrom)
	if oldTagger then
		GameState.Taggers[oldTagger] = nil
		GameState.RefreshSpeed(oldTagger)
		TaggerLook.Clear(oldTagger)
	end
	if newTagger then
		everTaggers[newTagger] = true
		GameState.Taggers[newTagger] = { Since = GameState.Now(), NoTagBack = tagBackFrom }
		GameState.RefreshSpeed(newTagger)
		TaggerLook.Apply(newTagger)
	end
end

-- タッチ返しの禁止に当たるか（計算だけの関数。テストからも呼べる）
function RoundManager.IsTagBackBlocked(runner, noTagBack)
	return noTagBack ~= nil and runner == noTagBack
end

local function targetTaggerCount(count)
	if count <= 2 then
		return math.min(count, 1)
	end
	return math.clamp(Config.TaggerCount, 1, count - 1)
end

local function pickRunner()
	local runners = {}
	for _, player in ipairs(GameState.ParticipantList()) do
		if not GameState.IsTagger(player) and GameState.IsAlive(player) then
			table.insert(runners, player)
		end
	end
	if #runners > 0 then
		return runners[math.random(1, #runners)]
	end
end

function RoundManager.SelectInitialTaggers()
	initialRunners = {}
	everTaggers = {}
	GameState.Uncaught = {}
	for _ = 1, targetTaggerCount(GameState.CountParticipants()) do
		local tagger = pickRunner()
		if tagger then
			setTagger(nil, tagger)
			Remotes.NotifyPlayer(tagger, "あなたが最初の鬼です！ 3秒後からタッチできます")
		end
	end
	for _, player in ipairs(GameState.ParticipantList()) do
		if not GameState.IsTagger(player) then
			initialRunners[player] = true
			GameState.Uncaught[player] = true
		end
	end
	broadcastState()
end

local function reconcileTaggers()
	for _, tagger in ipairs(GameState.TaggerList()) do
		if not GameState.IsParticipant(tagger) then
			setTagger(tagger, nil)
		end
	end
	local count = GameState.CountParticipants()
	-- 残り1人、または開始時の逃げ役が全員抜けたら、そのまま試合を終える。
	if count <= 1 or not hasInitialRunner() then
		return
	end
	local taggers = GameState.TaggerList()
	local wanted = targetTaggerCount(count)
	for index = wanted + 1, #taggers do
		setTagger(taggers[index], nil)
	end
	for _ = #taggers + 1, wanted do
		local replacement = pickRunner()
		if replacement then
			setTagger(nil, replacement)
			Remotes.NotifyPlayer(replacement, "鬼がいなくなったので、あなたが新しい鬼です！")
		end
	end
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
	removeParticipant(player)
	table.insert(GameState.Eliminated, player)
	sendToSpectator(player)
	Remotes.NotifyPlayer(player, "脱落… 観戦席から見守ろう")
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			Remotes.NotifyPlayer(other, player.DisplayName .. " が" .. (reason or "エリア外") .. "で脱落！")
		end
	end
	reconcileTaggers()
	broadcastState()
	return not hasInitialRunner()
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
				if not ItemManager.TrySafetyLine(player) and eliminate(player, "落下") then
					return
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

local function tryTagFor(tagger, role, now)
	if now - role.Since < Config.TagCooldown or not GameState.IsAlive(tagger)
		or GameState.IsDowned(tagger) or GameState.IsProne(tagger) or GameState.IsStunned(tagger)
		or GameState.GetData(tagger).FrozenUntil > now then
		return
	end
	local taggerRoot = GameState.GetRootPart(tagger)
	if not taggerRoot then
		return
	end

	local origin = taggerRoot.Position + taggerRoot.CFrame.LookVector * Config.TagReachForward
	for _, runner in ipairs(GameState.ParticipantList()) do
		if not GameState.IsTagger(runner) and GameState.IsAlive(runner)
			and not RoundManager.IsTagBackBlocked(runner, role.NoTagBack) then
			if isWithinTagReach(origin, runner.Character) or RoundManager.IsBodyContact(taggerRoot.Position, runner) then
				local data = GameState.GetData(runner)
				if data.InvulnerableUntil > now or data.BeastProneUntil > now
					or ItemManager.TryBeastChargeHit(runner, tagger, now) then
					-- シールドの猶予時間または召喚獣の加護でタッチ無効
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
					if GameState.Uncaught[runner] then
						GameState.Uncaught[runner] = nil
						if next(GameState.Uncaught) == nil then
							awardRoundRP(tagger, Config.RankPoints.TaggedAll)
						end
					end
					Remotes.NotifyPlayer(runner, "タッチされた！ 今度はあなたが鬼！（" .. tagger.DisplayName .. " にはタッチ返しできない）")
					Remotes.NotifyPlayer(tagger, runner.DisplayName .. " にタッチ！ 鬼を交代した")
					setTagger(tagger, runner, tagger)
					broadcastState()
					return
				end
			end
		end
	end
end

function RoundManager.TryTag()
	local now = GameState.Now()
	for _, tagger in ipairs(GameState.TaggerList()) do
		tryTagFor(tagger, GameState.Taggers[tagger], now)
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
		if startRequested and count >= 1 then
			soloRound = true -- 管理者の「開始」：1人ならボット相手で始める
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
		if count >= expected or (startRequested and count >= 1) then
			soloRound = count < Config.MinPlayers
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
		if startRequested and count >= 1 then
			soloRound = count < Config.MinPlayers
			return true
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
	setPhase("Intermission", "まもなく鬼ごっこが始まります。試合時間とマップに投票しよう")
	votes = {}
	mapVotes = {}
	refreshVoteDisplay()
	local endTime = GameState.Now() + Config.IntermissionTime
	while true do
		local left = endTime - GameState.Now()
		if left <= 0 or startRequested or nextMapRequested then
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
	GameState.Winners = {}
	GameState.TagCounts = {}
	GameState.Eliminated = {}
	GameState.Results = {}
	Leaderstats.ResetAll()
	BotManager.Clear()
	-- 2試合目からはマップを入れ替える（1試合目は起動時に作ったマップ）
	-- マップ：管理者の「次のマップ」＞投票で一番多いマップ＞ローテーションの次
	local chosenMap = nil
	if nextMapRequested then
		chosenMap = MapBuilder.GetNextMapId()
	else
		chosenMap = RoundManager.TallyMapVotes(mapVotes)
	end
	nextMapRequested = false
	startRequested = false
	endRequested = false
	mapVotes = {}
	local mapChanged = MapBuilder.PrepareRound(chosenMap)
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

	RoundManager.SelectInitialTaggers()
	ItemManager.DeliverPendingItems()

	local startedAt = GameState.Now()
	VoltGimmicks.Start(startedAt)
	local endTime = startedAt + duration
	local nextBroadcast = 0

	while true do
		local now = GameState.Now()
		local left = endTime - now
		if left <= 0 or endRequested or nextMapRequested then
			endRequested = false
			break
		end

		-- 抜けたプレイヤーを参加者から外す
		local humansLeft = 0
		for _, player in ipairs(GameState.ParticipantList()) do
			if BotManager.IsBot(player) then
				-- ボットは Players にいないので外さない
			elseif player.Parent ~= Players then
				removeParticipant(player)
			else
				humansLeft = humansLeft + 1
			end
		end
		-- 残りが1人以下、人間がいない、または開始時の逃げ役が全員抜けたら終わり
		if GameState.CountParticipants() < 2 or humansLeft == 0 or not hasInitialRunner() then
			break
		end

		reconcileTaggers()

		VoltGimmicks.Tick(now)
		RoundManager.TryTag()
		ItemManager.Tick()
		ZoneManager.Tick()
		if not hasInitialRunner() then
			break
		end
		RoundManager.CheckSkyFalls()
		if not hasInitialRunner() then
			break
		end
		BotManager.Tick()

		if now >= nextBroadcast then
			GameState.TimeLeft = left
			broadcastState()
			nextBroadcast = now + 1
		end

		task.wait(Config.TagCheckInterval)
	end

	VoltGimmicks.Stop()

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
				FinalTagger = GameState.IsTagger(player),
				ChampionEligible = initialRunners[player] == true and not everTaggers[player],
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
	local initialRunnersGone = not hasInitialRunner()
	initialRunners = {}
	everTaggers = {}
	GameState.Uncaught = {}
	BotManager.Halt()
	ItemManager.Stop()
	ZoneManager.Stop()
	GameState.Taggers = {}
	TaggerLook.ClearAll() -- 鬼の色と Highlight を外す
	GameState.Participants = {}
	GameState.RefreshAllSpeeds()

	local message
	if #GameState.Winners > 0 then
		local names = {}
		for _, player in ipairs(GameState.Winners) do
			table.insert(names, player.DisplayName)
		end
		message = "優勝: " .. table.concat(names, "、")
	elseif initialRunnersGone then
		message = "鬼の勝ち！"
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
	player.CharacterRemoving:Connect(function()
		ItemManager.ClearBeastEffects(player)
		GameState.ClearFreeze(player)
	end)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

function RoundManager.Init()
	Remotes.DurationVote.OnServerEvent:Connect(onDurationVote)
	Remotes.MapVote.OnServerEvent:Connect(onMapVote)
	ZoneManager.OnEliminate = eliminate
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		watchPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		removeParticipant(player)
		for _, role in pairs(GameState.Taggers) do
			if role.NoTagBack == player then
				role.NoTagBack = nil
			end
		end
		TaggerLook.Clear(player)
		ItemManager.EndPhase(player)
		GameState.ClearStun(player)
		GameState.ClearDown(player)
		GameState.ClearData(player)
		votes[player] = nil
		mapVotes[player] = nil
		refreshVoteDisplay()
	end)
end

RoundManager.IsEliminated = isEliminated

---------------------------------------------------------------------
-- 管理者の操作（AdminManager から。権限の確認は AdminManager が毎回行う）
---------------------------------------------------------------------

function RoundManager.SetAdminTagger(player)
	if GameState.Phase ~= "Round" or not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return false
	end
	if GameState.IsTagger(player) then
		return true
	end
	setTagger(GameState.TaggerList()[1], player)
	broadcastState()
	return true
end

function RoundManager.RequestStart()
	if GameState.Phase == "Round" or startRequested or #Players:GetPlayers() == 0 then
		return false
	end
	startRequested = true
	return true
end

function RoundManager.RequestEnd()
	if GameState.Phase ~= "Round" or endRequested then
		return false
	end
	endRequested = true
	return true
end

function RoundManager.RequestNextMap()
	if nextMapRequested then
		return false
	end
	nextMapRequested = true
	return true
end

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
