-- GameState: ラウンドの状態とプレイヤーごとの状態をまとめて持つ（サーバー専用）
-- RoundManager と ItemManager の両方から参照する共有の置き場。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local GameState = {}

-- ラウンド全体の状態
GameState.Phase = "Waiting"       -- "Waiting" / "Intermission" / "Round" / "Results"
GameState.TimeLeft = 0
GameState.PlayersNeeded = 0
GameState.Message = ""
GameState.Taggers = {}           -- [参加者] = { Since, NoTagBack }
GameState.ChosenDuration = Config.DefaultDuration -- 投票で決まった今ラウンドの試合時間（秒）
GameState.ChosenMode = Config.SuddenDeath.NormalId -- 投票で決まった今ラウンドのルール
GameState.ChosenBotStrength = "Auto" -- 投票で決まった今ラウンドのボットの強さ
GameState.Participants = {}       -- [Player またはボット] = true  このラウンドの参加者
GameState.Uncaught = {}          -- 開始時の逃げ役で、まだタッチされていない人
GameState.Winners = {}            -- 結果表示用の勝者リスト（Player の配列）
GameState.TagCounts = {}          -- [Player] = この試合で鬼にタッチされた回数（順位に使う）
GameState.Eliminated = {}         -- 脱落した人（脱落した順の Player 配列）
GameState.Results = {}            -- 結果表示用の順位表（RoundManager が作る）

-- プレイヤーごとの状態
local playerData = {}

local function newData()
	return {
		BeastEffectUntil = 0,    -- BeastUsed に使用済みの Id を記録する
		BeastSlowUntil = 0,
		BeastProneUntil = 0,
		BeastGlideUntil = 0,
		HeldItems = {},           -- 持っているアイテムの Id のリスト（古い順。枠数は GetItemSlots）
		HeldExpireAt = {},        -- HeldItems と同じ並びの使用期限（時刻）。0 は期限なし（購入アイテム）
		PendingItems = {},        -- ラウンド外に買ったアイテム（次のラウンド開始時に渡す）
		TaggerSkillReadyAt = {}, -- サーバー時刻でのクールダウン終了
		TaggerDashUntil = 0,
		TaggerSmellUntil = 0,
		NextSmellUpdate = 0,
		CatchBoostUntil = 0,
		ActiveCombos = {},        -- このラウンドで発動したデッキの組み合わせ
		DashUntil = 0,            -- ダッシュ効果が切れる時刻
		GiantUntil = 0,
		ShrinkUntil = 0,
		ReflectUntil = 0,
		ShieldUntil = 0,          -- シールドが切れる時刻
		StarUntil = 0,            -- スター（タッチ無効）が切れる時刻
		StunUntil = 0,
		StunImmuneUntil = 0,
		InsulateUntil = 0,
		SpikeBootsUntil = 0,
		PhaseUntil = 0,
		DownUntil = 0,            -- バナナで転倒している時間の終わり
		InvulnerableUntil = 0,    -- シールドで防いだ直後の無敵が切れる時刻
		ZoneStamina = Config.ZoneStaminaMax, -- エリア外スタミナ（0 になると中央へ強制送還）
		ZoneReturns = 0,          -- この試合で強制送還された回数
		JumpUntil = 0,            -- ハイジャンプが切れる時刻
		SneakUntil = 0,           -- しのび足が切れる時刻
		ZoneGuardUntil = 0,       -- エリアガードが切れる時刻
		SlowUntil = 0,            -- アイテムによる減速がすべて切れる時刻
		SlowEffects = {},         -- アイテム Id ごとの減速終了時刻
		FrozenUntil = 0,          -- タイムストップで止まっているのが切れる時刻
		BlindUntil = 0,           -- （ボットの鬼）スモーク・フラッシュで見えないのが切れる時刻
		LastUseTime = 0,          -- 最後にアイテム使用を受け付けた時刻
	}
end

function GameState.Now()
	return os.clock()
end

function GameState.GetData(player)
	local data = playerData[player]
	if not data then
		data = newData()
		playerData[player] = data
	end
	return data
end

local function releaseFrozenRoot(data)
	if data.FrozenRoot then
		data.FrozenRoot.Anchored = data.FrozenRootWasAnchored
		data.FrozenRoot = nil
		data.FrozenRootWasAnchored = nil
	end
end

-- ラウンドの区切りで持ち物・効果を消す。
-- ただし購入で予約済みのアイテム（PendingItems）は消さない（買ったのに失う状態を作らない）
function GameState.ResetData(player)
	GameState.ClearStun(player)
	local data = GameState.GetData(player)
	releaseFrozenRoot(data)
	local fresh = newData()
	fresh.LastUseTime = data.LastUseTime
	fresh.PendingItems = data.PendingItems
	playerData[player] = fresh
	return fresh
end

function GameState.ClearData(player)
	local data = playerData[player]
	if data then
		releaseFrozenRoot(data)
	end
	playerData[player] = nil
	GameState.ClearPasses(player)
end

---------------------------------------------------------------------
-- Game Pass の所有状態（Monetization が確認して書き込む）
---------------------------------------------------------------------

local passOwnership = {}     -- [Player] = { DoubleItem = true, SparkleTrail = true }

function GameState.SetPassOwned(player, passKey, owned)
	local passes = passOwnership[player]
	if not passes then
		passes = {}
		passOwnership[player] = passes
	end
	passes[passKey] = owned and true or nil
end

function GameState.OwnsPass(player, passKey)
	local passes = passOwnership[player]
	return passes ~= nil and passes[passKey] == true
end

function GameState.ClearPasses(player)
	passOwnership[player] = nil
end

-- 所持枠の数（ダブルアイテム所有者は 2）
function GameState.GetItemSlots(player)
	if GameState.OwnsPass(player, "DoubleItem") then
		return Config.Monetization.DoubleItem.ItemSlots
	end
	return Config.BaseItemSlots
end

function GameState.AllData()
	return playerData
end

function GameState.IsTagger(player)
	return player ~= nil and GameState.Taggers[player] ~= nil
end

function GameState.TaggerList()
	local list = {}
	for player in pairs(GameState.Taggers) do
		table.insert(list, player)
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function GameState.NearestTagger(position)
	local nearest, best = nil, math.huge
	for tagger in pairs(GameState.Taggers) do
		local root = GameState.GetRootPart(tagger)
		if root and GameState.IsAlive(tagger) then
			local distance = (root.Position - position).Magnitude
			if distance < best then
				nearest, best = tagger, distance
			end
		end
	end
	return nearest, best
end

function GameState.IsParticipant(player)
	return GameState.Participants[player] == true
end

function GameState.GetHumanoid(player)
	local character = player and player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

function GameState.GetRootPart(player)
	local character = player and player.Character
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

function GameState.IsAlive(player)
	local humanoid = GameState.GetHumanoid(player)
	return humanoid ~= nil and humanoid.Health > 0
end

function GameState.HasShield(player)
	return GameState.GetData(player).ShieldUntil > GameState.Now()
end

function GameState.IsDashing(player)
	return GameState.GetData(player).DashUntil > GameState.Now()
end

-- スターの効果中（鬼にタッチされない）かどうか
function GameState.HasStar(player)
	return GameState.GetData(player).StarUntil > GameState.Now()
end

function GameState.IsDowned(player)
	return GameState.GetData(player).DownUntil > GameState.Now()
end

function GameState.IsProne(player)
	return GameState.GetData(player).BeastProneUntil > GameState.Now()
end

function GameState.ApplyDownPose(player, downed)
	downed = downed or GameState.IsProne(player)
	local character = player.Character
	if character then
		character:SetAttribute("BananaDowned", downed and true or nil)
	end
	local humanoid = GameState.GetHumanoid(player)
	if not humanoid then
		return
	end
	local states = Enum.HumanoidStateType
	humanoid:SetStateEnabled(states.GettingUp, not downed)
	if downed and humanoid.Health > 0 then
		humanoid:ChangeState(states.FallingDown)
	elseif humanoid.Health > 0 and humanoid:GetState() == states.FallingDown then
		humanoid:ChangeState(states.GettingUp)
	end
end

function GameState.TryDown(player, duration)
	if not GameState.GetHumanoid(player) then
		return false
	end
	local data = GameState.GetData(player)
	local now = GameState.Now()
	if data.DownUntil > now then
		if duration then
			data.DownUntil = math.max(data.DownUntil, now + duration)
		end
		return false
	end
	data.DownUntil = now + (duration or Config.Items.Banana.DownTime)
	GameState.RefreshSpeed(player)
	GameState.StopStunnedMovement(player)
	GameState.ApplyDownPose(player, true)
	return true
end

function GameState.ClearDown(player)
	local data = GameState.GetData(player)
	if data.DownUntil > 0 then
		data.DownUntil = 0
		GameState.ApplyDownPose(player, false)
		GameState.RefreshSpeed(player)
	elseif player.Character and not GameState.IsProne(player) then
		player.Character:SetAttribute("BananaDowned", nil)
	end
end

-- 役割とアイテム効果から WalkSpeed を決め直す（速度の確定は必ずここで行う）
function GameState.IsStunned(player)
	return GameState.GetData(player).StunUntil > GameState.Now()
end

function GameState.TryVoltStun(player)
	if not player or GameState.Phase ~= "Round" or workspace:GetAttribute("CurrentGimmick") ~= "Volt"
		or not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return false
	end
	local now = GameState.Now()
	local data = GameState.GetData(player)
	if data.StunImmuneUntil > now or data.InsulateUntil > now then
		return false
	end
	GameState.ApplyStun(player, Config.VoltStunTime)
	data.StunImmuneUntil = now + Config.VoltStunTime + Config.VoltRecoveryTime
	return true
end

function GameState.ApplyStun(player, duration)
	local data = GameState.GetData(player)
	local now = GameState.Now()
	data.StunUntil = math.max(data.StunUntil, now + duration)
	local character = player.Character
	if character then
		character:SetAttribute("StunUntil", workspace:GetServerTimeNow() + data.StunUntil - now)
		character:SetAttribute("StunSequence", (character:GetAttribute("StunSequence") or 0) + 1)
	end
	GameState.RefreshSpeed(player)
	GameState.StopStunnedMovement(player)
end

function GameState.StopStunnedMovement(player)
	local root = GameState.GetRootPart(player)
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, math.min(0, root.AssemblyLinearVelocity.Y), 0)
	end
end

function GameState.ClearStun(player)
	GameState.GetData(player).StunUntil = 0
	if player.Character then
		player.Character:SetAttribute("StunUntil", nil)
	end
end

function GameState.ClearFreeze(player)
	local data = GameState.GetData(player)
	data.FrozenUntil = 0
	releaseFrozenRoot(data)
end

local function slowDefinition(effectId)
	if effectId == "Roar" then
		return Config.TaggerSkills.Roar
	end
	return Config.Items[effectId]
end

function GameState.ApplySlow(player, itemId)
	local data = GameState.GetData(player)
	local untilTime = GameState.Now() + slowDefinition(itemId).SlowTime
	data.SlowEffects[itemId] = untilTime
	data.SlowUntil = math.max(data.SlowUntil, untilTime)
	GameState.RefreshSpeed(player)
end

function GameState.TaggerLateBoost(timeLeft, duration)
	local boost = Config.TaggerSkills.LateBoost
	if timeLeft <= boost.FinalSeconds then
		return boost.FinalMultiplier, 2
	elseif timeLeft <= duration * boost.FirstRatio then
		return boost.FirstMultiplier, 1
	end
	return 1, 0
end

function GameState.RefreshSpeed(player)
	local data = GameState.GetData(player)
	local humanoid = GameState.GetHumanoid(player)
	if not humanoid then
		releaseFrozenRoot(data)
		return
	end
	local now = GameState.Now()
	local speed = Config.NormalWalkSpeed
	local isRoundTagger = GameState.Phase == "Round" and GameState.IsTagger(player)
	local lateMultiplier = 1
	if isRoundTagger then
		lateMultiplier = GameState.TaggerLateBoost(GameState.TimeLeft, GameState.ChosenDuration)
		speed = Config.TaggerWalkSpeed * lateMultiplier
		if data.TaggerDashUntil > now then
			speed = math.max(speed, Config.TaggerSkills.Dash.WalkSpeed)
		end
	end
	if GameState.IsDashing(player) then
		speed = math.max(speed, Config.Items.Dash.WalkSpeed)
	end
	if type(player) == "table" and player.IsBot == true then
		-- ボットは段位に合わせた倍率を掛ける。上限は Config（最大 1.15）
		if type(player.SpeedMultiplier) == "number" then
			local multiplier = math.clamp(player.SpeedMultiplier, 0, Config.BotSpeedMultiplierCap or 1.15)
			speed = speed * multiplier
		end
		-- ひとりモードのボットは人より少し遅くして、ひとりでも勝ち目があるようにする
		if player.SoloCap then
			local cap = GameState.IsTagger(player) and Config.BotTaggerWalkSpeed or Config.BotRunnerWalkSpeed
			speed = math.min(speed, cap * lateMultiplier)
		end
	end
	local beast = data.BeastEffectUntil > now and Config.Beasts[data.BeastUsed]
	if beast and beast.SpeedMultiplier then
		local roleSpeed = GameState.IsTagger(player) and Config.TaggerWalkSpeed or Config.NormalWalkSpeed
		speed = math.max(speed, roleSpeed * beast.SpeedMultiplier)
	end
	if isRoundTagger and data.CatchBoostUntil > now then
		speed *= Config.TaggerSkills.CatchStreak.Multiplier
	end
	if isRoundTagger and type(player) == "table" and player.IsBot == true then
		local chase = player.Chase
		if chase and chase.Role == GameState.Taggers[player] then
			speed *= chase.SpeedMultiplier
		end
	end
	if data.BeastSlowUntil > now then
		speed *= Config.Beasts.Sekhmet.SpeedMultiplier
	end
	if data.SlowUntil > now then
		for itemId, untilTime in pairs(data.SlowEffects) do
			if untilTime > now then
				speed = math.min(speed, slowDefinition(itemId).SlowSpeed)
			end
		end
	end
	local frozen = data.FrozenUntil > now
	local root = frozen and GameState.GetRootPart(player) or nil
	if data.FrozenRoot ~= root then
		releaseFrozenRoot(data)
		if root then
			data.FrozenRoot = root
			data.FrozenRootWasAnchored = root.Anchored == true
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
			root.Anchored = true
		end
	end
	if frozen then
		humanoid.Jump = false
		speed = 0
	end
	local immobilized = GameState.IsStunned(player) or GameState.IsDowned(player) or data.BeastProneUntil > now
	if immobilized then
		humanoid.Jump = false
		speed = 0
	end
	humanoid.WalkSpeed = speed * Config.ComboMultiplier(data.ActiveCombos, "SpeedMultiplier")

	-- ジャンプの高さ（ハイジャンプで高く、タイムストップ中は跳べない）
	humanoid.UseJumpPower = false
	local jump = Config.NormalJumpHeight
	if data.JumpUntil > now then
		jump = Config.Items.HighJump.JumpHeight
	end
	if beast and beast.JumpMultiplier then
		jump = math.max(jump, Config.NormalJumpHeight * beast.JumpMultiplier)
	end
	if frozen or immobilized then
		jump = 0
	end
	humanoid.JumpHeight = jump
end

-- 試合中で、まだ脱落していない参加者か
function GameState.IsActive(player)
	return GameState.Participants[player] == true
end

function GameState.RefreshAllSpeeds()
	for _, player in ipairs(Players:GetPlayers()) do
		GameState.RefreshSpeed(player)
	end
	for _, participant in ipairs(GameState.ParticipantList()) do
		if type(participant) == "table" and participant.IsBot == true then
			GameState.RefreshSpeed(participant)
		end
	end
end

function GameState.CountParticipants()
	local count = 0
	for _ in pairs(GameState.Participants) do
		count = count + 1
	end
	return count
end

function GameState.ParticipantList()
	local list = {}
	for player in pairs(GameState.Participants) do
		table.insert(list, player)
	end
	return list
end

---------------------------------------------------------------------
-- キャラクターから参加者を引く（人間は Players、ボットはこの対応表）
---------------------------------------------------------------------

local characterOwners = {} -- [Model] = 参加者（Player またはボット）

function GameState.RegisterCharacter(entity, character)
	if character ~= nil then
		characterOwners[character] = entity
	end
end

function GameState.UnregisterCharacter(character)
	if character ~= nil then
		characterOwners[character] = nil
	end
end

-- 触れた Part から、そのキャラクターの参加者を返す。人間を優先し、いなければボット。
function GameState.ParticipantFromHit(hit)
	if type(hit) ~= "table" and type(hit) ~= "userdata" then
		return nil
	end
	if type(hit.FindFirstAncestorOfClass) ~= "function" then
		return nil
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		return player
	end
	return characterOwners[character]
end

return GameState
