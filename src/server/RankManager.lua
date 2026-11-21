-- RankManager: 段位（ランク）の累計 RP と、逃げ切り・鬼タッチの累計を保存する
-- 保存先は DataStore「RankV1」。失敗しても試合は止めない（warn だけ出す）。
-- 読み込みに失敗した参加は 0 から始め、その状態では保存しない（クラウドの上書きを防ぐ）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))

local RankManager = {}

local DATASTORE_NAME = Config.RankDataStoreName or "RankV1"

-- [Player] = { RP, Survived, Tagged, Loaded, LoadOk, Loading, Left }
local cache = {}
local dataStore = nil
local started = false

-- ボットはプレーンなテーブル。Player（userdata）の未知プロパティを読まないよう type で分ける。
local function isBot(player)
	return type(player) == "table" and player.IsBot == true
end

local function tierNameOf(rp)
	local tier = Config.TierForRP(rp)
	if tier then
		return tier.Name
	end
	return ""
end

local function ensure(player)
	local data = cache[player]
	if not data then
		data = {
			RP = 0,
			Survived = 0,
			Tagged = 0,
			Loaded = false,
			LoadOk = false,
			Loading = false,
			Left = false,
		}
		cache[player] = data
	end
	return data
end

local function sync(player)
	local data = cache[player]
	if not data then
		return
	end
	Leaderstats.Set(player, "RP", data.RP)
	Leaderstats.Set(player, "Survived", data.Survived)
	Leaderstats.Set(player, "Tagged", data.Tagged)
	Leaderstats.Set(player, "Rank", tierNameOf(data.RP))
end

local function fireRankUp(player, rankName)
	if isBot(player) or not player or not player.Parent or rankName == nil or rankName == "" then
		return
	end
	local ok, err = pcall(function()
		Remotes.RankUp:FireClient(player, rankName)
	end)
	if not ok then
		warn("RankManager: 昇格の通知に失敗しました", player.Name, err)
	end
end

local function getStore()
	if dataStore then
		return dataStore
	end
	local ok, result = pcall(function()
		return game:GetService("DataStoreService"):GetDataStore(DATASTORE_NAME)
	end)
	if not ok or result == nil then
		warn("RankManager: DataStore を取得できませんでした", result)
		return nil
	end
	dataStore = result
	return dataStore
end

local function nonNegativeInt(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

-- 読み込みに成功したセッションだけ書く。RP・回数は減らないよう、クラウド側の方が大きければそちらを残す。
local function savePlayer(player)
	if isBot(player) then
		return
	end
	local data = player and cache[player]
	if not data then
		return
	end
	if not data.LoadOk then
		warn("RankManager: 読み込めていないため保存をスキップしました", player.Name)
		return
	end
	if player.UserId == nil then
		warn("RankManager: UserId がないため保存をスキップしました", player.Name)
		return
	end
	local store = getStore()
	if not store then
		warn("RankManager: 保存先がないため保存をスキップしました", player.Name)
		return
	end
	local key = tostring(player.UserId)
	local snapshot = {
		RP = data.RP,
		Survived = data.Survived,
		Tagged = data.Tagged,
	}
	local ok, err = pcall(function()
		store:UpdateAsync(key, function(old)
			local previous = type(old) == "table" and old or {}
			return {
				RP = math.max(snapshot.RP, nonNegativeInt(previous.RP)),
				Survived = math.max(snapshot.Survived, nonNegativeInt(previous.Survived)),
				Tagged = math.max(snapshot.Tagged, nonNegativeInt(previous.Tagged)),
			}
		end)
	end)
	if not ok then
		warn("RankManager: 保存に失敗しました", player.Name, err)
	end
end

local function finishIfLeft(player)
	local data = cache[player]
	if not data or not data.Left then
		return
	end
	savePlayer(player)
	if cache[player] == data then
		cache[player] = nil
	end
end

local function onPlayerRemoving(player)
	local data = cache[player]
	if not data then
		return
	end
	data.Left = true
	-- 読み込みの途中で抜けると、終わってから保存する（0 で上書きしないため）
	if data.Loading then
		return
	end
	savePlayer(player)
	if cache[player] == data then
		cache[player] = nil
	end
end

-- いまの累計。未ロードなら 0。
function RankManager.Get(player)
	local data = player and cache[player]
	if not data then
		return { RP = 0, Survived = 0, Tagged = 0, Loaded = false, LoadOk = false }
	end
	return {
		RP = data.RP,
		Survived = data.Survived,
		Tagged = data.Tagged,
		Loaded = data.Loaded,
		LoadOk = data.LoadOk,
	}
end

-- 参加時の読み込み。失敗したら 0 から（すでにこのセッションで加算された分は残す）。
function RankManager.Load(player)
	if not player or isBot(player) then
		return
	end
	local data = ensure(player)
	if data.Loaded or data.Loading then
		return
	end
	data.Loading = true

	local stored = nil
	local ok, err = true, nil
	local store = getStore()
	if not store then
		ok, err = false, "DataStore がありません"
	elseif player.UserId == nil then
		ok, err = false, "UserId がありません"
	else
		ok, err = pcall(function()
			stored = store:GetAsync(tostring(player.UserId))
		end)
	end

	-- GetAsync で待っているあいだに入った加算は、この時点の data に含まれている
	local earnedRP = data.RP
	local earnedSurvived = data.Survived
	local earnedTagged = data.Tagged

	if not ok then
		warn("RankManager: 読み込みに失敗したので 0 から始めます", player.Name, err)
		data.LoadOk = false
	else
		local baseRP, baseSurvived, baseTagged = 0, 0, 0
		if type(stored) == "table" then
			baseRP = nonNegativeInt(stored.RP)
			baseSurvived = nonNegativeInt(stored.Survived)
			baseTagged = nonNegativeInt(stored.Tagged)
		end
		data.RP = baseRP + earnedRP
		data.Survived = baseSurvived + earnedSurvived
		data.Tagged = baseTagged + earnedTagged
		data.LoadOk = true
		-- 待っているあいだの加算で段が上がったときだけ通知する（読み込みそのものでは出さない）
		if earnedRP > 0 then
			local seenName = tierNameOf(earnedRP)
			local afterName = tierNameOf(data.RP)
			if seenName ~= afterName then
				fireRankUp(player, afterName)
			end
		end
	end

	data.Loading = false
	data.Loaded = true
	sync(player)
	if player.Parent == nil then
		data.Left = true
	end
	finishIfLeft(player)
end

-- 累計 RP を増やす。境界を越えたときだけ、そのプレイヤーに RankUp を1回送る。
function RankManager.Award(player, amount)
	if isBot(player) or not player or type(amount) ~= "number" then
		return
	end
	amount = math.floor(amount)
	if amount <= 0 then
		return
	end
	local data = ensure(player)
	local oldName = tierNameOf(data.RP)
	data.RP = data.RP + amount
	local newName = tierNameOf(data.RP)
	sync(player)
	if newName ~= oldName then
		fireRankUp(player, newName)
	end
end

-- 逃げ切り / 鬼タッチの累計を 1 増やす（保存用の数と leaderstats の両方）
function RankManager.AddCount(player, key)
	if isBot(player) or not player or (key ~= "Survived" and key ~= "Tagged") then
		return
	end
	local data = ensure(player)
	data[key] = data[key] + 1
	Leaderstats.Set(player, key, data[key])
end

function RankManager.Save(player)
	if isBot(player) then
		return
	end
	savePlayer(player)
end

local function loadPlayerSafe(player)
	local ok, err = pcall(RankManager.Load, player)
	if not ok then
		warn("RankManager: 読み込み処理でエラー", player and player.Name, err)
	end
end

function RankManager.Init()
	if started then
		return
	end
	started = true

	local function spawnLoad(player)
		task.spawn(function()
			loadPlayerSafe(player)
		end)
	end

	Players.PlayerAdded:Connect(spawnLoad)
	for _, player in ipairs(Players:GetPlayers()) do
		spawnLoad(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		local ok, err = pcall(onPlayerRemoving, player)
		if not ok then
			warn("RankManager: 退出時の保存でエラー", player and player.Name, err)
		end
	end)

	local bindOk, bindErr = pcall(function()
		game:BindToClose(function()
			local listOk, playersOrErr = pcall(function()
				return Players:GetPlayers()
			end)
			if not listOk then
				warn("RankManager: 終了時のプレイヤー取得に失敗しました", playersOrErr)
				return
			end
			for _, player in ipairs(playersOrErr) do
				savePlayer(player)
			end
		end)
	end)
	if not bindOk then
		warn("RankManager: BindToClose の登録に失敗しました", bindErr)
	end

	task.spawn(function()
		local interval = Config.RankSaveInterval
		if type(interval) ~= "number" or interval < 1 then
			interval = 180
		end
		while true do
			task.wait(interval)
			local ok, err = pcall(function()
				for _, player in ipairs(Players:GetPlayers()) do
					savePlayer(player)
				end
			end)
			if not ok then
				warn("RankManager: 定期保存でエラー", err)
			end
		end
	end)
end

return RankManager
