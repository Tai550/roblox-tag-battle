-- Lobby Main: ロビーサーバー（スタートプレース）
--
--   ・保存データ（コイン・持っているアイテム・デッキ）の読み込みと、ショップ・デッキの変更
--   ・「すぐ遊ぶ」パッド：乗った人が2人以上そろうとカウントダウンし、最大8人で試合サーバーへ
--   ・友達部屋：4桁の合言葉で、同じ予約サーバーへ集まる
--   ・ルール掲示板の文字を表示する

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local MemoryStoreService = game:GetService("MemoryStoreService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))

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
local DataUpdate = remote("DataUpdate")     -- サーバー → 本人: コイン・持ち物・デッキ
local QueueUpdate = remote("QueueUpdate")   -- サーバー → 全員: すぐ遊ぶの待ち人数と残り秒
local Notify = remote("Notify")             -- サーバー → 本人: 短いお知らせ
local BuyItem = remote("BuyItem")           -- 本人 → サーバー: アイテムを買いたい（Id）
local SetDeck = remote("SetDeck")           -- 本人 → サーバー: このデッキにしたい（Id のリスト）
local CreateRoom = remote("CreateRoom")     -- 本人 → サーバー: 友達部屋を作りたい
local JoinRoom = remote("JoinRoom")         -- 本人 → サーバー: この合言葉の部屋に入りたい
local RoomCreated = remote("RoomCreated")   -- サーバー → 本人: 作った部屋の合言葉
local SoloPlay = remote("SoloPlay")         -- 本人 → サーバー: ひとりモードで遊びたい
remoteFolder.Parent = ReplicatedStorage

local function notify(player, text)
	if player and player.Parent then
		Notify:FireClient(player, text)
	end
end

local function sendData(player)
	local data = PlayerDataStore.Get(player)
	DataUpdate:FireClient(player, { Coins = data.Coins, Owned = data.Owned, Deck = data.Deck, Wins = data.Wins })
	local stats = player:FindFirstChild("leaderstats")
	local coins = stats and stats:FindFirstChild(Config.LeaderstatNames.Coins)
	if coins then
		coins.Value = data.Coins
	end
end

---------------------------------------------------------------------
-- 参加・退出
---------------------------------------------------------------------

local function onPlayerAdded(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = Config.LeaderstatNames.Coins
	coins.Parent = stats
	stats.Parent = player
	PlayerDataStore.Load(player)
	sendData(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end
Players.PlayerRemoving:Connect(function(player)
	PlayerDataStore.Forget(player)
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
padText.TextColor3 = Color3.fromRGB(255, 255, 255)
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
	"・ピンクの壁の外にいるとスタミナが減る。0 になると中央へ強制送還",
	"・強制送還は2回まで。3回目で脱落（観戦席から見守る）",
	"",
	"■ アイテム",
	"・フィールドのボックスに触ると、自分のデッキからアイテムが出る",
	"・3つまでためておける。せまくなった終盤に使おう",
	"・デッキはロビーで組む（試合中は変えられない）",
	"・コインでショップから新しいアイテムを買える（梅・竹・松）",
	"",
	"■ ランク",
	"・試合でRPがたまると段位が上がる（ブロンズ→シルバー→…→マスター）",
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
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = table.concat(RULES, "\n")
	text.Parent = surface
end
