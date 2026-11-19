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
GameState.Tagger = nil            -- 今の鬼（Player）
GameState.TaggerSince = 0         -- 鬼になった時刻（クールダウン判定用）
GameState.Participants = {}       -- [Player] = true  このラウンドの参加者
GameState.BeenTagger = {}         -- [Player] = true  このラウンドで一度でも鬼になった人
GameState.Winners = {}            -- 結果表示用の勝者リスト（Player の配列）

-- プレイヤーごとの状態
local playerData = {}

local function newData()
	return {
		HeldItem = nil,           -- 持っているアイテムの Id（1つだけ）
		DashUntil = 0,            -- ダッシュ効果が切れる時刻
		ShieldUntil = 0,          -- シールドが切れる時刻
		InvulnerableUntil = 0,    -- シールドで防いだ直後の無敵が切れる時刻
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

function GameState.ResetData(player)
	local data = GameState.GetData(player)
	local lastUse = data.LastUseTime
	local fresh = newData()
	fresh.LastUseTime = lastUse
	playerData[player] = fresh
	return fresh
end

function GameState.ClearData(player)
	playerData[player] = nil
end

function GameState.AllData()
	return playerData
end

function GameState.IsTagger(player)
	return player ~= nil and GameState.Tagger == player
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

-- 役割とアイテム効果から WalkSpeed を決め直す（速度の確定は必ずここで行う）
function GameState.RefreshSpeed(player)
	local humanoid = GameState.GetHumanoid(player)
	if not humanoid then
		return
	end
	local speed = Config.NormalWalkSpeed
	if GameState.Phase == "Round" and GameState.IsTagger(player) then
		speed = Config.TaggerWalkSpeed
	end
	if GameState.IsDashing(player) then
		speed = math.max(speed, Config.Items.Dash.WalkSpeed)
	end
	humanoid.WalkSpeed = speed
end

function GameState.RefreshAllSpeeds()
	for _, player in ipairs(Players:GetPlayers()) do
		GameState.RefreshSpeed(player)
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

return GameState
