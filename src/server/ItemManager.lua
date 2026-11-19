-- ItemManager: バトルアイテムの出現・拾う処理・使用効果（すべてサーバー側で確定）
--
-- クライアントから届くのは UseItem の「使いたい」という合図だけ。
-- 何を持っているか、使えるか、効果がどうなるかはサーバーが持つ状態だけで決める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))

local ItemManager = {}

local SHIELD_EFFECT_NAME = "TagShieldEffect"

local active = false
local spawnLoopToken = 0
local spawnedItems = {}     -- [Part] = { ItemId = ..., PointKey = ... }
local occupiedPoints = {}   -- [PointKey] = Part
local warnedNoSpawns = false
local itemContainer = nil

---------------------------------------------------------------------
-- 出現ポイント
---------------------------------------------------------------------

-- 出現ポイントの一覧を返す。各要素は { Key = 識別用, Position = Vector3 }
-- ItemSpawns フォルダがなければ、原点付近の予備ポイントを使う（エラーにはしない）
local function getSpawnPoints()
	local points = {}
	local folder = workspace:FindFirstChild(Config.ItemSpawnFolderName)
	if folder then
		for _, child in ipairs(folder:GetDescendants()) do
			if child:IsA("BasePart") then
				table.insert(points, { Key = child, Position = child.Position })
			end
		end
	end

	if #points == 0 then
		if not warnedNoSpawns then
			warnedNoSpawns = true
			warn(string.format(
				"[ItemManager] Workspace.%s に Part が見つからないため、原点付近にアイテムを出現させます。",
				Config.ItemSpawnFolderName
			))
		end
		for index, offset in ipairs(Config.FallbackSpawnOffsets) do
			table.insert(points, {
				Key = "Fallback" .. index,
				Position = Config.FallbackSpawnCenter + offset,
			})
		end
	end

	return points
end

local function getItemContainer()
	if itemContainer and itemContainer.Parent then
		return itemContainer
	end
	itemContainer = Instance.new("Folder")
	itemContainer.Name = "SpawnedItems"
	itemContainer.Parent = workspace
	return itemContainer
end

---------------------------------------------------------------------
-- クライアントへの状態送信
---------------------------------------------------------------------

local function sendItemUpdate(player)
	if not player or not player.Parent then
		return
	end
	local data = GameState.GetData(player)
	local now = GameState.Now()
	Remotes.ItemUpdate:FireClient(player, {
		HeldItem = data.HeldItem or "",
		DashTimeLeft = math.max(0, data.DashUntil - now),
		ShieldTimeLeft = math.max(0, data.ShieldUntil - now),
	})
end
ItemManager.SendItemUpdate = sendItemUpdate

---------------------------------------------------------------------
-- シールドの見た目（ForceField を見た目だけに使う）
---------------------------------------------------------------------

local function addShieldVisual(player)
	local character = player.Character
	if character and not character:FindFirstChild(SHIELD_EFFECT_NAME) then
		local field = Instance.new("ForceField")
		field.Name = SHIELD_EFFECT_NAME
		field.Visible = true
		field.Parent = character
	end
end

local function removeShieldVisual(player)
	local character = player.Character
	local field = character and character:FindFirstChild(SHIELD_EFFECT_NAME)
	if field then
		field:Destroy()
	end
end

---------------------------------------------------------------------
-- アイテムの出現と拾う処理
---------------------------------------------------------------------

local function countItems()
	local count = 0
	for _ in pairs(spawnedItems) do
		count = count + 1
	end
	return count
end

local function pickRandomItemId()
	local total = 0
	for _, itemId in ipairs(Config.ItemOrder) do
		local def = Config.Items[itemId]
		if def and def.SpawnWeight and def.SpawnWeight > 0 then
			total = total + def.SpawnWeight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, itemId in ipairs(Config.ItemOrder) do
		local def = Config.Items[itemId]
		if def and def.SpawnWeight and def.SpawnWeight > 0 then
			roll = roll - def.SpawnWeight
			if roll <= 0 then
				return itemId
			end
		end
	end
	return Config.ItemOrder[#Config.ItemOrder]
end

local function removeItem(part)
	local info = spawnedItems[part]
	if info then
		occupiedPoints[info.PointKey] = nil
		spawnedItems[part] = nil
	end
	part:Destroy()
end

local function onItemTouched(part, hit)
	local info = spawnedItems[part]
	if not info or not active then
		return
	end
	local character = hit:FindFirstAncestorOfClass("Model")
	local player = character and Players:GetPlayerFromCharacter(character)
	if not player then
		return
	end
	if not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return
	end
	local data = GameState.GetData(player)
	if data.HeldItem ~= nil then
		return -- 1つしか持てない
	end

	local itemId = info.ItemId
	removeItem(part)
	data.HeldItem = itemId
	sendItemUpdate(player)

	local def = Config.Items[itemId]
	Remotes.NotifyPlayer(player, string.format(
		"%s を拾った！ ［%s］で使う：%s",
		def.DisplayName, Config.UseItemKeyLabel, def.Description
	))
end

local function createItemPart(itemId, position)
	local def = Config.Items[itemId]

	local part = Instance.new("Part")
	part.Name = "Item_" .. itemId
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(2.5, 2.5, 2.5)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = def.Color
	part.Position = position

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 120, 0, 30)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = def.DisplayName
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	return part
end

local function spawnOne()
	if countItems() >= Config.MaxItemsOnMap then
		return
	end

	local freePoints = {}
	for _, point in ipairs(getSpawnPoints()) do
		if not occupiedPoints[point.Key] then
			table.insert(freePoints, point)
		end
	end
	if #freePoints == 0 then
		return
	end

	local itemId = pickRandomItemId()
	if not itemId then
		return
	end

	local point = freePoints[math.random(1, #freePoints)]
	local part = createItemPart(itemId, point.Position + Vector3.new(0, Config.ItemHeightOffset, 0))

	spawnedItems[part] = { ItemId = itemId, PointKey = point.Key }
	occupiedPoints[point.Key] = part

	part.Touched:Connect(function(hit)
		onItemTouched(part, hit)
	end)
	part.Parent = getItemContainer()
end

---------------------------------------------------------------------
-- アイテムの効果（すべてサーバー側で確定）
-- 戻り値: 成功したら true。失敗したら false と理由（画面に出す文）
---------------------------------------------------------------------

local handlers = {}

handlers.Dash = function(player, def, data)
	data.DashUntil = GameState.Now() + def.Duration
	GameState.RefreshSpeed(player)
	Remotes.NotifyPlayer(player, string.format("ダッシュ！ %d秒間 速くなる", def.Duration))
	return true
end

handlers.Smoke = function(player, def, data)
	local tagger = GameState.Tagger
	if not tagger or not tagger.Parent or tagger == player then
		return false, "今はスモークを使えません"
	end
	Remotes.SmokeEffect:FireClient(tagger, def.Duration, def.FadeOutTime)
	Remotes.NotifyPlayer(player, "スモーク！ 鬼の画面をまっ白にした")
	return true
end

handlers.Shield = function(player, def, data)
	if GameState.HasShield(player) then
		return false, "シールドはもう張っています"
	end
	data.ShieldUntil = GameState.Now() + def.Duration
	addShieldVisual(player)
	Remotes.NotifyPlayer(player, string.format("シールド！ %d秒間、1回だけタッチを防ぐ", def.Duration))
	return true
end

handlers.Warp = function(player, def, data)
	local character = player.Character
	if not character then
		return false, nil
	end
	local points = getSpawnPoints()
	if #points == 0 then
		return false, "ワープ先が見つかりません"
	end
	local point = points[math.random(1, #points)]
	character:PivotTo(CFrame.new(point.Position + Vector3.new(0, def.HeightOffset, 0)))
	Remotes.NotifyPlayer(player, "ワープ！")
	return true
end

local function onUseItem(player)
	-- クライアントから来た引数は一切使わない
	local data = GameState.GetData(player)
	local now = GameState.Now()
	if now - data.LastUseTime < Config.UseItemCooldown then
		return
	end
	data.LastUseTime = now

	if not active or GameState.Phase ~= "Round" then
		return
	end
	if not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return
	end

	local itemId = data.HeldItem
	if not itemId then
		return
	end
	local def = Config.Items[itemId]
	local handler = handlers[itemId]
	if not def or not handler then
		data.HeldItem = nil
		sendItemUpdate(player)
		return
	end

	if GameState.IsTagger(player) and not def.CanTaggerUse then
		Remotes.NotifyPlayer(player, def.DisplayName .. " は鬼には使えません")
		return
	end

	local ok, reason = handler(player, def, data)
	if ok then
		data.HeldItem = nil
	elseif reason then
		Remotes.NotifyPlayer(player, reason)
	end
	sendItemUpdate(player)
end

---------------------------------------------------------------------
-- 外部（RoundManager）から呼ぶ関数
---------------------------------------------------------------------

-- シールドがあれば消費して true を返す
function ItemManager.ConsumeShield(player)
	if not GameState.HasShield(player) then
		return false
	end
	local data = GameState.GetData(player)
	data.ShieldUntil = 0
	data.InvulnerableUntil = GameState.Now() + Config.Items.Shield.GraceTime
	removeShieldVisual(player)
	sendItemUpdate(player)
	return true
end

-- 効果時間切れの処理（RoundManager のループから定期的に呼ぶ）
function ItemManager.Tick()
	local now = GameState.Now()
	for player, data in pairs(GameState.AllData()) do
		if data.DashUntil > 0 and data.DashUntil <= now then
			data.DashUntil = 0
			GameState.RefreshSpeed(player)
			sendItemUpdate(player)
		end
		if data.ShieldUntil > 0 and data.ShieldUntil <= now then
			data.ShieldUntil = 0
			removeShieldVisual(player)
			sendItemUpdate(player)
			Remotes.NotifyPlayer(player, "シールドが消えた")
		end
	end
end

-- 復活したときにシールドの見た目を付け直す
function ItemManager.OnCharacterAdded(player)
	if GameState.HasShield(player) then
		addShieldVisual(player)
	end
end

-- ラウンド開始時に呼ぶ: アイテムの定期出現を始める
function ItemManager.Start()
	active = true
	spawnLoopToken = spawnLoopToken + 1
	local myToken = spawnLoopToken
	task.spawn(function()
		while active and spawnLoopToken == myToken do
			task.wait(Config.ItemSpawnInterval)
			if active and spawnLoopToken == myToken then
				spawnOne()
			end
		end
	end)
end

-- ラウンド終了時に呼ぶ: 出現中のアイテム・持ち物・効果をすべて消す
function ItemManager.Stop()
	active = false
	spawnLoopToken = spawnLoopToken + 1

	local parts = {}
	for part in pairs(spawnedItems) do
		table.insert(parts, part)
	end
	for _, part in ipairs(parts) do
		removeItem(part)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		GameState.ResetData(player)
		removeShieldVisual(player)
		sendItemUpdate(player)
	end
end

function ItemManager.Init()
	Remotes.UseItem.OnServerEvent:Connect(onUseItem)
end

return ItemManager
