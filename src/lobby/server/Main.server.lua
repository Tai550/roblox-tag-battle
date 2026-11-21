-- Lobby Main: ロビーサーバー（スタートプレース）
--
--   ・保存データ（コイン・持っているアイテム・デッキ）の読み込みと、ショップ・デッキの変更
--   ・「すぐ遊ぶ」パッド：乗った人が2人以上そろうとカウントダウンし、最大8人で試合サーバーへ
--   ・友達部屋：4桁の合言葉で、同じ予約サーバーへ集まる
--   ・ルール掲示板の文字を表示する
--   ・段位（累計 RP）の表示と、一度でも試合に出た人の RP ランキングボード
--   ・デイリールーレット（30分ごとに1回分の権利がたまる）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local DataStoreService = game:GetService("DataStoreService")
local UserService = game:GetService("UserService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))
local RouletteBoard = require(script.Parent:WaitForChild("RouletteBoard"))

---------------------------------------------------------------------
-- 通信（RemoteEvent）
---------------------------------------------------------------------

local remoteFolder = Instance.new("Folder")
remoteFolder.Name = "LobbyRemotes"
local function remote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = remoteFolder
	return event
end
local OpenBeasts = remote("OpenBeasts")
local DrawBeast = remote("DrawBeast")
local BeastResult = remote("BeastResult")
local EquipBeast = remote("EquipBeast")
local DataUpdate = remote("DataUpdate")     -- サーバー → 本人: コイン・持ち物・デッキ
local QueueUpdate = remote("QueueUpdate")   -- サーバー → 全員: すぐ遊ぶの待ち人数と残り秒
local Notify = remote("Notify")             -- サーバー → 本人: 短いお知らせ
local BuyItem = remote("BuyItem")           -- 本人 → サーバー: アイテムを買いたい（Id）
local SetDeck = remote("SetDeck")           -- 本人 → サーバー: このデッキにしたい（Id のリスト）
local CreateRoom = remote("CreateRoom")     -- 本人 → サーバー: 友達部屋を作りたい
local JoinRoom = remote("JoinRoom")         -- 本人 → サーバー: この合言葉の部屋に入りたい
local RoomCreated = remote("RoomCreated")   -- サーバー → 本人: 作った部屋の合言葉
local SoloPlay = remote("SoloPlay")         -- 本人 → サーバー: ひとりモードで遊びたい
local SpinRoulette = remote("SpinRoulette") -- 本人 → サーバー: ルーレットを回したい
local RouletteResult = remote("RouletteResult") -- サーバー → 本人: 当たった景品の番号（失敗時は nil）
local RouletteSpinVisual = remote("RouletteSpinVisual") -- サーバー → 全員: 回転演出と停止時刻
remoteFolder.Parent = ReplicatedStorage

local function notify(player, text)
	if player and player.Parent then
		Notify:FireClient(player, text)
	end
end

local rankRP = {}        -- [Player] = 累計 RP（試合サーバーが保存したもの）
local sentStock = {}     -- [Player] = 最後に送ったルーレットの回数

local function sendData(player)
	local data = PlayerDataStore.Get(player)
	local stock, nextIn = PlayerDataStore.RouletteView(data, os.time())
	sentStock[player] = stock
	DataUpdate:FireClient(player, {
		Coins = data.Coins, Owned = data.Owned, Deck = data.Deck, Wins = data.Wins,
		Beasts = data.Beasts, EquippedBeast = data.EquippedBeast,
		RP = rankRP[player] or 0,
		RouletteStock = stock, RouletteNextIn = nextIn,
	})
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(Config.LeaderstatNames.Coins)
	if coins then
		coins.Value = data.Coins
	end
end

---------------------------------------------------------------------
-- 段位（読むだけ。RP を増やして保存するのは試合サーバーの RankManager）
---------------------------------------------------------------------

local rankStore = nil
local leaderboardStore = nil
pcall(function()
	rankStore = DataStoreService:GetDataStore(Config.RankDataStoreName)
	leaderboardStore = DataStoreService:GetOrderedDataStore(Config.RankLeaderboardStoreName)
end)

local function nonNegativeInt(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function showRank(player)
	local rp = rankRP[player] or 0
	local tier = Config.TierForRP(rp)
	local stats = player:FindFirstChild("leaderstats")
	if stats then
		local rankValue = stats:FindFirstChild(Config.LeaderstatNames.Rank)
		local rpValue = stats:FindFirstChild(Config.LeaderstatNames.RP)
		if rankValue then
			rankValue.Value = tier and tier.Name or ""
		end
		if rpValue then
			rpValue.Value = rp
		end
	end
end

local function loadRank(player)
	if not rankStore then
		return
	end
	local ok, stored = pcall(function()
		return rankStore:GetAsync(tostring(player.UserId))
	end)
	if not ok then
		warn("[Lobby] 段位の読み込みに失敗: " .. tostring(stored))
		return
	end
	if player.Parent ~= Players then
		return
	end
	rankRP[player] = type(stored) == "table" and nonNegativeInt(stored.RP) or 0
	showRank(player)
	-- 試合に出たことがある人（段位の記録がある人）は、ランキングにも載せる（以前の記録の取りこみ）
	if type(stored) == "table" and leaderboardStore then
		local rp = rankRP[player]
		pcall(function()
			leaderboardStore:UpdateAsync(tostring(player.UserId), function(old)
				return math.max(nonNegativeInt(old), rp)
			end)
		end)
	end
end

---------------------------------------------------------------------
-- 参加・退出
---------------------------------------------------------------------

local loaded = {}
local beastRequest = {}

local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local rank = Instance.new("StringValue")
	rank.Name = Config.LeaderstatNames.Rank
	rank.Parent = stats
	local rp = Instance.new("IntValue")
	rp.Name = Config.LeaderstatNames.RP
	rp.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = Config.LeaderstatNames.Coins
	coins.Parent = stats
	stats.Parent = player
	showRank(player)
	PlayerDataStore.Load(player)
	if player.Parent ~= Players then
		PlayerDataStore.Forget(player)
		return
	end
	loaded[player] = true
	loadRank(player)
	if loaded[player] then
		sendData(player)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	loaded[player] = nil
	beastRequest[player] = nil
	PlayerDataStore.Forget(player)
	rankRP[player] = nil
	sentStock[player] = nil
end)

---------------------------------------------------------------------
-- ショップとデッキ（検証はすべてサーバー）
---------------------------------------------------------------------

local lastRequest = {} -- [Player] = 時刻（連打防止）
local function tooFast(player, seconds)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < seconds then
		return true
	end
	lastRequest[player] = now
	return false
end

BuyItem.OnServerEvent:Connect(function(player, itemId)
	if tooFast(player, 0.5) or type(itemId) ~= "string" then
		return
	end
	local ok, reason = PlayerDataStore.BuyItem(player, itemId)
	if ok then
		notify(player, Config.Items[itemId].DisplayName .. " を買った！ デッキに入れてみよう")
	else
		notify(player, reason or "買えませんでした")
	end
	sendData(player)
end)

SetDeck.OnServerEvent:Connect(function(player, list)
	if tooFast(player, 0.5) then
		return
	end
	local ok = PlayerDataStore.SetDeck(player, list)
	notify(player, ok and "デッキを保存した！" or string.format("デッキは持っているアイテムから%d個えらんでね", Config.DeckSize))
	sendData(player)
end)

---------------------------------------------------------------------
-- 召喚獣ガチャ
---------------------------------------------------------------------

local spawn = workspace:WaitForChild("LobbyMap"):WaitForChild("SpawnLocation")
local machineOrigin = spawn.Position + Vector3.new(11, -0.5, 0)
local machine = Instance.new("Model")
machine.Name = "BeastGacha"

local function machinePart(name, offset, size, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = machineOrigin + offset
	part.Color = color
	part.Anchored = true
	part.Parent = machine
	return part
end

local brand = Config.BrandColors
local stand = machinePart("Stand", Vector3.new(0, 1.5, 0), Vector3.new(4, 3, 3), brand.Primary)
local capsuleCase = machinePart("CapsuleCase", Vector3.new(0, 4.5, 0), Vector3.new(4, 3, 3), brand.White)
capsuleCase.Material = Enum.Material.Glass
capsuleCase.Transparency = 0.65
for index, tier in ipairs({ "B", "A", "S", "SS" }) do
	local offset = Vector3.new(index % 2 == 0 and 0.85 or -0.85, 3.75, index <= 2 and 0.65 or -0.65)
	local capsule = machinePart("Capsule", offset, Vector3.new(1.1, 1.1, 1.1), Config.Tiers[tier].Color)
	capsule.Shape = Enum.PartType.Ball
	capsule.CanCollide = false
end
local sign = machinePart("Sign", Vector3.new(0, 6.5, 0), Vector3.new(4, 1, 3), brand.Secondary)
local signGui = Instance.new("SurfaceGui")
signGui.Face = Enum.NormalId.Left
signGui.Parent = sign
local signText = Instance.new("TextLabel")
signText.Size = UDim2.fromScale(1, 1)
signText.BackgroundTransparency = 1
signText.Text = "ガチャ"
signText.TextColor3 = brand.White
signText.Font = Enum.Font.GothamBold
signText.TextScaled = true
signText.Parent = signGui

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "ガチャを開く"
prompt.ObjectText = "召喚獣"
prompt.RequiresLineOfSight = false
prompt.MaxActivationDistance = 10
prompt.Parent = stand
machine.Parent = workspace

local function nearMachine(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - stand.Position).Magnitude <= prompt.MaxActivationDistance
end

prompt.Triggered:Connect(function(player)
	if loaded[player] and nearMachine(player) then
		sendData(player)
		OpenBeasts:FireClient(player)
	end
end)

DrawBeast.OnServerEvent:Connect(function(player)
	if not loaded[player] or beastRequest[player] or tooFast(player, 0.5) then
		return
	end
	if not nearMachine(player) then
		BeastResult:FireClient(player, nil, "ガチャの台に近づいてください")
		return
	end
	beastRequest[player] = true
	local result, reason = PlayerDataStore.DrawBeast(player)
	beastRequest[player] = nil
	if loaded[player] then
		sendData(player)
		BeastResult:FireClient(player, result, reason)
	else
		PlayerDataStore.Forget(player)
	end
end)

EquipBeast.OnServerEvent:Connect(function(player, id)
	if not loaded[player] or beastRequest[player] or type(id) ~= "string" or tooFast(player, 0.5) then
		return
	end
	beastRequest[player] = true
	local ok, _, reason = PlayerDataStore.SetEquippedBeast(player, id)
	beastRequest[player] = nil
	if loaded[player] then
		sendData(player)
		if not ok then
			notify(player, reason or "持っている召喚獣を選んでください")
		end
	else
		PlayerDataStore.Forget(player)
	end
end)

---------------------------------------------------------------------
-- デイリールーレット（景品の抽選も保存もサーバー）
---------------------------------------------------------------------

local rouletteBoard = RouletteBoard.Create(spawn)
local rouletteBusy = false
SpinRoulette.OnServerEvent:Connect(function(player)
	if rouletteBusy or tooFast(player, 1) then
		RouletteResult:FireClient(player, nil)
		if rouletteBusy then
			notify(player, "ルーレットが回転中です。止まってからまわしてね")
		end
		return
	end
	-- 保存処理が待機している間も、1台の盤で同時に回転を始めない。
	rouletteBusy = true
	local prizeIndex = PlayerDataStore.PickRoulettePrize()
	local ok, _, reason = PlayerDataStore.SpinRoulette(player, prizeIndex, os.time())
	if ok then
		local duration = Config.Roulette.RevealDelay or 3
		local revealAt = workspace:GetServerTimeNow() + duration
		local coins = Config.Roulette.Prizes[prizeIndex].Coins
		local playerName = player.DisplayName
		rouletteBoard.Start(playerName, prizeIndex, revealAt, duration)
		RouletteResult:FireClient(player, prizeIndex)
		RouletteSpinVisual:FireAllClients(player.UserId, playerName, prizeIndex, coins, revealAt)
		-- 盤の停止と同じタイミングで、本人のコインと回数を新しくする。
		task.delay(math.max(0, revealAt - workspace:GetServerTimeNow()), function()
			rouletteBoard.Reveal(prizeIndex, coins, playerName)
			rouletteBusy = false
			if player.Parent == Players then
				notify(player, string.format("ルーレットで %d コインもらった！", Config.Roulette.Prizes[prizeIndex].Coins))
				sendData(player)
			end
		end)
	else
		rouletteBusy = false
		RouletteResult:FireClient(player, nil)
		notify(player, reason or "まだルーレットを回せません。30分ごとに1回たまります")
		sendData(player)
	end
end)

-- 権利がたまったら画面に知らせる
task.spawn(function()
	while true do
		task.wait(10)
		local now = os.time()
		for _, player in ipairs(Players:GetPlayers()) do
			local stock = PlayerDataStore.RouletteView(PlayerDataStore.Get(player), now)
			if sentStock[player] ~= nil and stock > sentStock[player] then
				notify(player, "ルーレットを回せるようになった！")
				sendData(player)
			end
		end
	end
end)

---------------------------------------------------------------------
-- 試合サーバーへの移動
---------------------------------------------------------------------

local function canTeleport(players)
	if RunService:IsStudio() then
		for _, player in ipairs(players) do
			notify(player, "Studio では試合サーバーへ移動できません（公開版で試してね）")
		end
		return false
	end
	if Config.MatchPlaceId == 0 then
		for _, player in ipairs(players) do
			notify(player, "試合の場所を準備中です")
		end
		return false
	end
	return true
end

-- 試合サーバーが「自分はどんな部屋か」を調べられるよう、予約サーバーの ID ごとに情報を残す
local serverInfoOk, serverInfo = pcall(function()
	return MemoryStoreService:GetHashMap("RoomByServer_v1")
end)
if not serverInfoOk then
	serverInfo = nil
end
local function registerServer(privateServerId, info)
	if serverInfo and privateServerId and privateServerId ~= "" then
		local ok, err = pcall(function()
			serverInfo:SetAsync(privateServerId, info, Config.FriendRoomLifetime)
		end)
		if not ok then
			warn("[Lobby] 部屋情報の保存に失敗: " .. tostring(err))
		end
	end
end

-- 予約サーバーへ送る。accessCode を省略すると新しく予約する
local function teleportToMatch(players, teleportData, accessCode)
	if not canTeleport(players) then
		return false
	end
	local ok, err = pcall(function()
		local code = accessCode
		if not code then
			local privateServerId
			code, privateServerId = TeleportService:ReserveServer(Config.MatchPlaceId)
			registerServer(privateServerId, teleportData)
		end
		local options = Instance.new("TeleportOptions")
		options.ReservedServerAccessCode = code
		options:SetTeleportData(teleportData)
		TeleportService:TeleportAsync(Config.MatchPlaceId, players, options)
	end)
	if not ok then
		warn("[Lobby] 移動に失敗: " .. tostring(err))
		for _, player in ipairs(players) do
			notify(player, "移動に失敗しました: " .. string.sub(tostring(err), 1, 80))
		end
	end
	return ok
end

SoloPlay.OnServerEvent:Connect(function(player)
	if tooFast(player, 3) then
		return
	end
	notify(player, "ひとりモードへ移動します！")
	teleportToMatch({ player }, { Mode = "Solo", HostUserId = player.UserId })
end)

TeleportService.TeleportInitFailed:Connect(function(player, _, message)
	notify(player, "移動に失敗しました: " .. tostring(message))
end)

---------------------------------------------------------------------
-- すぐ遊ぶ（パッドに乗った人で自動マッチ）
---------------------------------------------------------------------

local lobbyMap = workspace:WaitForChild("LobbyMap")
local quickPad = lobbyMap:WaitForChild("QuickPad")

-- パッドの上の表示
local billboard = Instance.new("BillboardGui")
billboard.Size = UDim2.new(0, 260, 0, 80)
billboard.StudsOffset = Vector3.new(0, 9, 0)
billboard.AlwaysOnTop = true
billboard.Parent = quickPad
local padText = Instance.new("TextLabel")
padText.Size = UDim2.new(1, 0, 1, 0)
padText.BackgroundTransparency = 1
padText.TextScaled = true
padText.Font = Enum.Font.GothamBold
padText.TextColor3 = Config.BrandColors.White
padText.TextStrokeTransparency = 0.2
padText.Parent = billboard

local queue = {}          -- パッドに乗った順の Player
local departAt = nil      -- 出発する時刻（2人そろったら決まる）
local departing = false

local function onPad(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local offset = root.Position - quickPad.Position
	local flat = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return flat <= Config.QuickPadRadius and math.abs(offset.Y) <= 8
end

local function refreshQueue()
	-- パッドから降りた人・抜けた人を外す
	local kept = {}
	for _, player in ipairs(queue) do
		if player.Parent == Players and onPad(player) then
			table.insert(kept, player)
		end
	end
	queue = kept
	-- 新しく乗った人を後ろに足す
	for _, player in ipairs(Players:GetPlayers()) do
		if onPad(player) and not table.find(queue, player) then
			table.insert(queue, player)
		end
	end
end

local function queueTick()
	if departing then
		return
	end
	refreshQueue()
	local count = math.min(#queue, Config.QuickMaxPlayers)
	local now = os.clock()
	if count < Config.MinPlayers then
		departAt = nil
	elseif count >= Config.QuickMaxPlayers then
		departAt = math.min(departAt or math.huge, now + Config.QuickFullCountdown)
	elseif not departAt then
		departAt = now + Config.QuickCountdown
	end

	local left = departAt and math.max(0, math.ceil(departAt - now)) or 0
	if count == 0 then
		padText.Text = "すぐ遊ぶ\nここに乗ると参加"
	elseif count < Config.MinPlayers then
		padText.Text = string.format("すぐ遊ぶ %d/%d\nあと%d人で出発", count, Config.QuickMaxPlayers, Config.MinPlayers - count)
	else
		padText.Text = string.format("すぐ遊ぶ %d/%d\n出発まで %d秒", count, Config.QuickMaxPlayers, left)
	end
	QueueUpdate:FireAllClients({ Count = count, Max = Config.QuickMaxPlayers, Left = left, Ready = departAt ~= nil })

	if departAt and now >= departAt then
		local group = {}
		for index = 1, count do
			table.insert(group, queue[index])
		end
		departAt = nil
		departing = true
		padText.Text = "出発！"
		for _, player in ipairs(group) do
			notify(player, "試合へ移動します！")
		end
		teleportToMatch(group, { Mode = "Quick", Expected = #group })
		task.wait(3)
		departing = false
	end
end

task.spawn(function()
	while true do
		queueTick()
		task.wait(0.5)
	end
end)

---------------------------------------------------------------------
-- 友達部屋（合言葉）
---------------------------------------------------------------------

local roomsOk, rooms = pcall(function()
	return MemoryStoreService:GetHashMap("FriendRooms_v1")
end)
if not roomsOk then
	rooms = nil
end

local function newCode()
	local digits = {}
	for index = 1, Config.FriendRoomCodeLength do
		digits[index] = tostring(math.random(0, 9))
	end
	return table.concat(digits)
end

CreateRoom.OnServerEvent:Connect(function(player)
	if tooFast(player, 3) then
		return
	end
	if not canTeleport({ player }) then
		return
	end
	if not rooms then
		notify(player, "今は友達部屋を作れません")
		return
	end
	local ok, err = pcall(function()
		local code
		for _ = 1, 10 do
			code = newCode()
			if rooms:GetAsync(code) == nil then
				break
			end
		end
		local accessCode, privateServerId = TeleportService:ReserveServer(Config.MatchPlaceId)
		rooms:SetAsync(code, { AccessCode = accessCode, HostUserId = player.UserId }, Config.FriendRoomLifetime)
		registerServer(privateServerId, { Mode = "Friends", Code = code, HostUserId = player.UserId })
		-- まず合言葉を画面に出す。「部屋に入る」を押すと移動する（その間に友達へ伝えられる）
		RoomCreated:FireClient(player, code)
	end)
	if not ok then
		warn("[Lobby] 部屋を作れませんでした: " .. tostring(err))
		notify(player, "部屋を作れませんでした: " .. string.sub(tostring(err), 1, 80))
	end
end)

JoinRoom.OnServerEvent:Connect(function(player, code)
	if tooFast(player, 2) then
		return
	end
	if type(code) ~= "string" or #code ~= Config.FriendRoomCodeLength or not code:match("^%d+$") then
		notify(player, string.format("合言葉は%d桁の数字です", Config.FriendRoomCodeLength))
		return
	end
	if not canTeleport({ player }) then
		return
	end
	if not rooms then
		notify(player, "今は友達部屋に入れません")
		return
	end
	local ok, room = pcall(function()
		return rooms:GetAsync(code)
	end)
	if not ok or type(room) ~= "table" or not room.AccessCode then
		notify(player, "その合言葉の部屋は見つかりませんでした")
		return
	end
	notify(player, "友達部屋へ移動します！")
	teleportToMatch({ player }, { Mode = "Friends", Code = code, HostUserId = room.HostUserId }, room.AccessCode)
end)

---------------------------------------------------------------------
-- ルール掲示板
---------------------------------------------------------------------

local RULES = {
	"ハイパー鬼ごっこ　ルール",
	"",
	"■ 勝ち方",
	"・時間いっぱい鬼から逃げ切ろう。終了の瞬間に鬼だった人は負け",
	"・タッチ返しなし：自分にタッチした人には、すぐタッチし返せない",
	"・順位は「鬼にタッチされた回数」が少ない順",
	"・一度もタッチされずに逃げ切ったら優勝！コインがいちばん多くもらえる",
	"",
	"■ 縮むエリア",
	"・赤い壁の外にいるとスタミナが減る。0 になると中央へ強制送還",
	"・強制送還は2回まで。3回目で脱落（観戦席から見守る）",
	"",
	"■ アイテム",
	"・フィールドのボックスに触ると、自分のデッキからアイテムが出る",
	"・3つまでためておける。せまくなった終盤に使おう",
	"・デッキはロビーで組む（試合中は変えられない）",
	"・コインでショップから新しいアイテムを買える（B・A・S）",
	"",
	"■ ランク",
	"・試合でRPがたまると段位が上がる（ブロンズ→シルバー→…→マスター）",
	"・右のランキングボードに、累計RPの上位が出る",
	"",
	"■ デイリールーレット",
	"・30分ごとに1回まわせる（3回分までためられる）。コインが当たる",
	"",
	"■ 遊び方",
	"・すぐ遊ぶ：緑のパッドに乗る。2人そろうと出発（最大8人。足りない分はボットが入る）",
	"・友達部屋：左の「友達部屋」から作って、合言葉を友達に教えよう",
	"・ひとりで遊ぶ：ボットと練習できる（コインは半分）",
}

local board = lobbyMap:FindFirstChild("RulesBoard")
if board then
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Right
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = board
	local text = Instance.new("TextLabel")
	text.Size = UDim2.new(1, -60, 1, -60)
	text.Position = UDim2.new(0, 30, 0, 30)
	text.BackgroundTransparency = 1
	text.TextColor3 = Config.BrandColors.White
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = table.concat(RULES, "\n")
	text.Parent = surface
end

---------------------------------------------------------------------
-- ランキングボード（一度でも試合に出た人の累計 RP 上位）
---------------------------------------------------------------------

local rankBoard = lobbyMap:FindFirstChild("RankBoard")
if rankBoard then
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Left
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.Parent = rankBoard

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -60, 0, 70)
	title.Position = UDim2.new(0, 30, 0, 20)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Config.BrandColors.Accent
	title.Text = "ランキング（累計RP）"
	title.Parent = surface

	local rows = {}
	local perColumn = math.ceil(Config.RankLeaderboardSize / 2)
	for index = 1, Config.RankLeaderboardSize do
		local column = index <= perColumn and 0 or 1
		local line = (index - 1) % perColumn
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(0.5, -45, 0, 46)
		row.Position = UDim2.new(column * 0.5, 30, 0, 105 + line * 51)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = Config.BrandColors.White
		row.RichText = true
		row.Text = ""
		row.Parent = surface
		rows[index] = row
	end
	rows[1].Text = "読み込み中…"

	local nameCache = {} -- [UserId] = 表示名
	local function fillNames(userIds)
		local missing = {}
		for _, id in ipairs(userIds) do
			if not nameCache[id] then
				table.insert(missing, id)
			end
		end
		if #missing == 0 then
			return
		end
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(missing)
		end)
		if ok and type(infos) == "table" then
			for _, info in ipairs(infos) do
				nameCache[info.Id] = info.DisplayName or info.Username
			end
		end
		for _, id in ipairs(missing) do
			if not nameCache[id] then
				local nameOk, name = pcall(function()
					return Players:GetNameFromUserIdAsync(id)
				end)
				nameCache[id] = nameOk and name or ("ID " .. tostring(id))
			end
		end
	end

	local function escape(text)
		return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
	end

	local function colorHex(color)
		return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
	end

	local function refreshBoard()
		if not leaderboardStore then
			rows[1].Text = "ランキングは公開版で表示されます"
			return
		end
		local ok, entries = pcall(function()
			local pages = leaderboardStore:GetSortedAsync(false, Config.RankLeaderboardSize)
			return pages:GetCurrentPage()
		end)
		if not ok then
			warn("[Lobby] ランキングの読み込みに失敗: " .. tostring(entries))
			if rows[1].Text == "読み込み中…" then
				rows[1].Text = "ランキングを読み込めませんでした"
			end
			return
		end
		local ids = {}
		for _, entry in ipairs(entries) do
			local id = tonumber(entry.key)
			if id then
				table.insert(ids, id)
			end
		end
		fillNames(ids)
		for index, row in ipairs(rows) do
			local entry = entries[index]
			local id = entry and tonumber(entry.key)
			if id then
				local rp = nonNegativeInt(entry.value)
				local tier = Config.TierForRP(rp)
				row.Text = string.format('%d. %s  <font color="%s">%s</font> %d', index, escape(nameCache[id] or "?"),
					tier and colorHex(tier.Color) or "#FFFFFF", tier and tier.Name or "", rp)
			else
				row.Text = (index == 1) and "まだ記録がありません" or ""
			end
		end
	end

	task.spawn(function()
		while true do
			refreshBoard()
			task.wait(Config.RankLeaderboardRefresh)
		end
	end)
end
