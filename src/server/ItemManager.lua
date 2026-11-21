-- ItemManager: バトルアイテムの出現・拾う処理・使用効果（すべてサーバー側で確定）
--
-- クライアントから届くのは UseItem の「何枠目を使いたい」という合図だけ。
-- 何を持っているか、使えるか、効果がどうなるかはサーバーが持つ状態だけで決める。
-- 所持はリスト形式（data.HeldItems、古い順）。枠数は GameState.GetItemSlots で決まる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))

local ItemManager = {}

local SHIELD_EFFECT_NAME = "TagShieldEffect"
local STAR_EFFECT_NAME = "TagStarEffect"

local active = false
local spawnLoopToken = 0
local spawnedItems = {}     -- [Part] = { IsBox = true, PointKey = ... } フィールドのボックス
local boxMotions = {}       -- [Part] = Heartbeat の接続（箱を消したら必ず切る）
local occupiedPoints = {}   -- [PointKey] = Part
local placedBananas = {}    -- [Part] = { PlacedBy = Player, ExpireAt = 時刻 }
local warnedNoSpawns = false
local itemContainer = nil

---------------------------------------------------------------------
-- 出現ポイント
---------------------------------------------------------------------

-- 出現ポイントの一覧を返す。各要素は { Key = 識別用, Position = Vector3 }
-- ItemSpawns フォルダがなければ、原点付近の予備ポイントを使う（エラーにはしない）
-- 戻り値: ポイントの配列, 予備ポイントかどうか
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
		return points, true
	end

	return points, false
end

-- ZoneManager からも使うため公開する
function ItemManager.GetSpawnPoints()
	return getSpawnPoints()
end

-- ポイントのうち、エリア（中心 cx, cz・半径 radius）の内側にあるものだけを返す
-- （計算だけの関数。テストからも呼べる）
function ItemManager.FilterPointsInZone(points, cx, cz, radius)
	local inside = {}
	for _, point in ipairs(points) do
		if ZoneManager.IsInsideXZ(cx, cz, radius, point.Position) then
			table.insert(inside, point)
		end
	end
	return inside
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
	if not player or (type(player) == "table" and player.IsBot == true) or not player.Parent then
		return
	end
	local data = GameState.GetData(player)
	local now = GameState.Now()
	local held = {}
	local expireLeft = {}
	for index, itemId in ipairs(data.HeldItems) do
		held[index] = itemId
		local expireAt = data.HeldExpireAt[index] or 0
		expireLeft[index] = expireAt > 0 and math.max(0, expireAt - now) or 0
	end
	Remotes.ItemUpdate:FireClient(player, {
		HeldItems = held,
		HeldExpireLeft = expireLeft, -- 枠ごとの使用期限の残り秒（0 は期限なし）
		MaxSlots = GameState.GetItemSlots(player),
		DashTimeLeft = math.max(0, data.DashUntil - now),
		ShieldTimeLeft = math.max(0, data.ShieldUntil - now),
		StarTimeLeft = math.max(0, data.StarUntil - now),
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
-- スターの見た目（キラキラの粒子）
---------------------------------------------------------------------

local function addStarVisual(player)
	local character = player.Character
	if character and not character:FindFirstChild(STAR_EFFECT_NAME) then
		local sparkles = Instance.new("Sparkles")
		sparkles.Name = STAR_EFFECT_NAME
		sparkles.SparkleColor = Color3.fromRGB(255, 220, 60)
		local root = character:FindFirstChild("HumanoidRootPart")
		sparkles.Parent = root or character
	end
end

local function removeStarVisual(player)
	local character = player.Character
	if not character then
		return
	end
	local effect = character:FindFirstChild(STAR_EFFECT_NAME, true)
	if effect then
		effect:Destroy()
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

-- 今出ている宝箱の位置。ボットが取りに行く判断に使う。
function ItemManager.GetActiveBoxPositions()
	local list = {}
	for part in pairs(spawnedItems) do
		local position = part and part.Position
		if part and part.Parent and position then
			table.insert(list, position)
		end
	end
	return list
end

-- SpawnWeight の重みで抽選する。filter を渡すと、filter(def) が true のアイテムだけから選ぶ
local function pickRandomItemId(filter)
	local candidates = {}
	local total = 0
	for _, itemId in ipairs(Config.ItemOrder) do
		local def = Config.Items[itemId]
		if def and def.SpawnWeight and def.SpawnWeight > 0 and (filter == nil or filter(def)) then
			table.insert(candidates, itemId)
			total = total + def.SpawnWeight
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	for _, itemId in ipairs(candidates) do
		roll = roll - Config.Items[itemId].SpawnWeight
		if roll <= 0 then
			return itemId
		end
	end
	return candidates[#candidates]
end

local function stopBoxMotion(part)
	local conn = boxMotions[part]
	if not conn then
		return
	end
	boxMotions[part] = nil
	conn:Disconnect()
end

local function removeItem(part)
	stopBoxMotion(part)
	local info = spawnedItems[part]
	if info then
		occupiedPoints[info.PointKey] = nil
		spawnedItems[part] = nil
	end
	part:Destroy()
end

-- テストから、浮遊の接続が残っていないことを数える
function ItemManager.ActiveBoxMotions()
	local count = 0
	for _ in pairs(boxMotions) do
		count = count + 1
	end
	return count
end

-- 置いてからの秒数に対する上下（スタッド）と、Y 軸の回転（ラジアン）
-- 上下は振幅 0.4、回転は 1 秒に 30 度。計算だけなのでテストからも呼べる。
function ItemManager.BoxMotionAt(elapsed)
	local bob = math.sin(elapsed * math.pi) * 0.4
	local yaw = math.rad(30) * elapsed
	return bob, yaw
end

-- 浮遊の経過時間。テストからはこの関数を差し替えて時刻を固定する（os は書き換えられない）。
function ItemManager.MotionNow()
	return os.clock()
end

-- フィールドのボックスに触れたとき：自分のデッキからランダムで1つ手に入る。
-- 手に入れたアイテムには使用期限（Config.BoxExpireTime）が付く。
local function onBoxTouched(part, hit)
	local info = spawnedItems[part]
	if not info or not active then
		return
	end
	-- 人間は Players、ボットは GameState の対応表。触れた相手を参加者に引き直す
	local player = GameState.ParticipantFromHit(hit)
	if not player then
		return
	end
	if not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return
	end
	local data = GameState.GetData(player)
	if #data.HeldItems >= GameState.GetItemSlots(player) then
		return -- 枠がいっぱいなら拾えない
	end

	local itemId = DeckManager.PickFromDeck(player)
	if not itemId then
		return
	end

	removeItem(part)
	table.insert(data.HeldItems, itemId)
	table.insert(data.HeldExpireAt, GameState.Now() + Config.BoxExpireTime)
	sendItemUpdate(player)

	local def = Config.Items[itemId]
	Remotes.NotifyPlayer(player, string.format(
		"ボックスから %s が出た！ ［%s］で使う（%d秒以内に使おう）",
		def.DisplayName, Config.GetSlotKeyLabel(#data.HeldItems), Config.BoxExpireTime
	))
end

-- 宝箱の部品を本体へ溶接する。本体が動くと一緒に動く。
-- 触れた判定は spawn 側で各 Part の Touched を本体の処理へつなぐ。
local function attachPiece(root, name, size, pos, color, material, transparency)
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)
	piece.Position = pos
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanTouch = true
	piece.Massless = true
	piece.Material = material
	piece.Color = color
	piece.Transparency = transparency or 0
	piece.TopSurface = Enum.SurfaceType.Smooth
	piece.BottomSurface = Enum.SurfaceType.Smooth
	piece.Parent = root

	local weld = Instance.new("WeldConstraint")
	weld.Name = name .. "Weld"
	weld.Part0 = root
	weld.Part1 = piece
	weld.Parent = piece
	piece.Anchored = false
	return piece
end

-- フィールドに置く宝箱。戻り値は Touched を受ける本体 Part（名前は ItemBox）。
-- 購入の GrantItemBox はここを通らない。
local function createBoxPart(position)
	local wood = Color3.fromRGB(118, 76, 42)
	local woodLid = Color3.fromRGB(150, 104, 58)
	local gold = Color3.fromRGB(214, 170, 62)
	local goldBright = Color3.fromRGB(255, 205, 90)
	local glow = Color3.fromRGB(255, 190, 110)

	-- 少し縦長の木の箱
	local bodySize = Vector3.new(2.4, 2.6, 2.0)
	local lidSize = Vector3.new(2.7, 0.42, 2.25)

	local root = Instance.new("Part")
	root.Name = "ItemBox"
	root.Size = bodySize
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = true
	root.Material = Enum.Material.Wood
	root.Color = wood
	root.CFrame = CFrame.new(position.X, position.Y, position.Z)
	root.Position = position
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth

	local lidCenter = Vector3.new(
		position.X,
		position.Y + bodySize.Y / 2 + lidSize.Y / 2,
		position.Z
	)
	attachPiece(root, "Lid", lidSize, lidCenter, woodLid, Enum.Material.Wood, 0)

	-- 蓋の前後だけ、細い金色の縁
	local trimZ = lidSize.Z / 2 + 0.04
	local trimSize = Vector3.new(lidSize.X, lidSize.Y, 0.12)
	attachPiece(
		root, "LidTrimFront", trimSize,
		Vector3.new(lidCenter.X, lidCenter.Y, lidCenter.Z + trimZ),
		gold, Enum.Material.Metal, 0
	)
	attachPiece(
		root, "LidTrimBack", trimSize,
		Vector3.new(lidCenter.X, lidCenter.Y, lidCenter.Z - trimZ),
		gold, Enum.Material.Metal, 0
	)

	-- 本体の中央を縦に巻く金色の帯（前面・後面・蓋の上）
	local faceZ = bodySize.Z / 2 + 0.06
	attachPiece(
		root, "BandFront", Vector3.new(0.36, bodySize.Y, 0.12),
		Vector3.new(position.X, position.Y, position.Z + faceZ),
		gold, Enum.Material.Metal, 0
	)
	attachPiece(
		root, "BandBack", Vector3.new(0.36, bodySize.Y, 0.12),
		Vector3.new(position.X, position.Y, position.Z - faceZ),
		gold, Enum.Material.Metal, 0
	)
	attachPiece(
		root, "BandTop", Vector3.new(0.36, 0.12, lidSize.Z),
		Vector3.new(position.X, lidCenter.Y + lidSize.Y / 2 + 0.06, position.Z),
		gold, Enum.Material.Metal, 0
	)

	-- 正面の小さな鍵穴
	attachPiece(
		root, "Keyhole", Vector3.new(0.28, 0.4, 0.14),
		Vector3.new(position.X, position.Y - 0.15, position.Z + faceZ + 0.1),
		goldBright, Enum.Material.Metal, 0
	)

	-- 蓋の境目に細い光
	local seam = attachPiece(
		root, "SeamGlow", Vector3.new(bodySize.X + 0.2, 0.08, bodySize.Z + 0.2),
		Vector3.new(position.X, position.Y + bodySize.Y / 2, position.Z),
		glow, Enum.Material.Neon, 0.15
	)
	local light = Instance.new("PointLight")
	light.Name = "ChestGlow"
	light.Color = glow
	light.Brightness = 0.55
	light.Range = 10
	light.Shadows = false
	light.Parent = seam

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LabelGui"
	billboard.Size = UDim2.new(0, 140, 0, 36)
	billboard.StudsOffset = Vector3.new(0, bodySize.Y / 2 + lidSize.Y + 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "宝箱"
	label.TextColor3 = Color3.fromRGB(255, 220, 140)
	label.TextStrokeColor3 = Color3.fromRGB(90, 58, 28)
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Parent = billboard

	return root
end
ItemManager.CreateBoxPart = createBoxPart

-- 本体と、溶接した部品のどれに触れても同じ拾う処理になるようにする
local function connectBoxTouch(part)
	local function onHit(hit)
		onBoxTouched(part, hit)
	end
	part.Touched:Connect(onHit)
	for _, desc in ipairs(part:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Touched:Connect(onHit)
		end
	end
end

-- 置かれているあいだだけ、ゆっくり上下して回転する。消したら接続を切る。
local function startBoxMotion(part)
	local runService = game:GetService("RunService")
	local heartbeat = runService and runService.Heartbeat
	if not heartbeat or type(heartbeat.Connect) ~= "function" then
		return
	end
	local originX = part.Position.X
	local originY = part.Position.Y
	local originZ = part.Position.Z
	local started = ItemManager.MotionNow()
	local conn
	conn = heartbeat:Connect(function()
		if boxMotions[part] ~= conn or part.Parent == nil then
			stopBoxMotion(part)
			return
		end
		local bob, yaw = ItemManager.BoxMotionAt(ItemManager.MotionNow() - started)
		part.CFrame = CFrame.new(originX, originY + bob, originZ) * CFrame.Angles(0, yaw, 0)
	end)
	boxMotions[part] = conn
end

local zoneBoxCounter = 0

local function spawnOne()
	if countItems() >= Config.BoxMaxOnMap then
		return
	end

	local points = getSpawnPoints()
	-- ボックスは縮小エリアの内側にだけ出す
	if ZoneManager.IsActive() then
		local centerPos = ZoneManager.GetCenter()
		points = ItemManager.FilterPointsInZone(points, centerPos.X, centerPos.Z, ZoneManager.GetRadius())
	end

	local freePoints = {}
	for _, point in ipairs(points) do
		if not occupiedPoints[point.Key] then
			table.insert(freePoints, point)
		end
	end
	if #freePoints == 0 then
		-- エリア内に空きポイントがない（終盤にエリアが小さくなった）ときは、
		-- エリア内のランダムな位置に直接出す
		if not ZoneManager.IsActive() then
			return
		end
		local centerPos = ZoneManager.GetCenter()
		local radius = ZoneManager.GetRadius() * 0.85
		local angle = math.random() * math.pi * 2
		local dist = math.random() * radius
		zoneBoxCounter = zoneBoxCounter + 1
		freePoints = { {
			Key = "ZoneBox" .. zoneBoxCounter,
			Position = Vector3.new(
				centerPos.X + math.cos(angle) * dist,
				centerPos.Y,
				centerPos.Z + math.sin(angle) * dist
			),
		} }
	end

	local point = freePoints[math.random(1, #freePoints)]
	local part = createBoxPart(point.Position + Vector3.new(0, Config.ItemHeightOffset, 0))

	spawnedItems[part] = { IsBox = true, PointKey = point.Key }
	occupiedPoints[point.Key] = part

	connectBoxTouch(part)
	part.Parent = getItemContainer()
	startBoxMotion(part)
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
	if not tagger or tagger == player then
		return false, "今はスモークを使えません"
	end
	-- ボットに画面はない。FireClient はせず、追う処理をしばらく止める
	if type(tagger) == "table" and tagger.IsBot == true then
		tagger.BlindUntil = GameState.Now() + def.Duration
		Remotes.NotifyPlayer(player, "スモーク！ 鬼の画面をまっ白にした")
		return true
	end
	if not tagger.Parent then
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

handlers.Star = function(player, def, data)
	data.StarUntil = GameState.Now() + def.Duration
	addStarVisual(player)
	Remotes.NotifyPlayer(player, string.format("スター！ %d秒間、鬼にタッチされない", def.Duration))
	return true
end

---------------------------------------------------------------------
-- バナナ（置くアイテム。踏んだ人がすべる）
---------------------------------------------------------------------

local function removeBanana(part)
	placedBananas[part] = nil
	part:Destroy()
end

local function onBananaTouched(part, hit)
	local info = placedBananas[part]
	if not info or not active then
		return
	end
	local player = GameState.ParticipantFromHit(hit)
	if not player or player == info.PlacedBy then
		return -- 置いた本人はすべらない
	end
	if not GameState.IsParticipant(player) or not GameState.IsAlive(player) then
		return
	end
	local data = GameState.GetData(player)
	if GameState.IsSlipping(player) then
		return
	end
	local root = GameState.GetRootPart(player)
	if not root then
		return
	end

	-- 進んでいる向き（止まっているときは体の向き）にすべる
	local direction = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	if direction.Magnitude < 1 then
		direction = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if direction.Magnitude < 0.01 then
		return
	end
	data.SlipDirection = direction.Unit
	data.SlipUntil = GameState.Now() + Config.Items.Banana.SlipTime

	removeBanana(part)
	Remotes.NotifyPlayer(player, "バナナですべった！")
	sendItemUpdate(player)
end

handlers.Banana = function(player, def, data)
	local root = GameState.GetRootPart(player)
	if not root then
		return false, nil
	end

	local part = Instance.new("Part")
	part.Name = "BananaTrap"
	part.Size = Vector3.new(2.2, 0.6, 2.2)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = def.Color
	part.Position = Vector3.new(root.Position.X, root.Position.Y - 2.5, root.Position.Z)

	placedBananas[part] = { PlacedBy = player, ExpireAt = GameState.Now() + def.Duration }
	part.Touched:Connect(function(hit)
		onBananaTouched(part, hit)
	end)
	part.Parent = getItemContainer()

	Remotes.NotifyPlayer(player, "バナナを置いた！")
	return true
end

local function onUseItem(player, slotArg)
	-- クライアントから来るのは枠番号だけ。整数で、実際に持っている枠のときだけ受け付ける
	local slot = 1
	if slotArg ~= nil then
		slot = tonumber(slotArg)
		if slot == nil or slot ~= math.floor(slot) or slot < 1 or slot > GameState.GetItemSlots(player) then
			return
		end
	end
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

	local itemId = data.HeldItems[slot]
	if not itemId then
		return
	end
	local def = Config.Items[itemId]
	local handler = handlers[itemId]
	if not def or not handler then
		table.remove(data.HeldItems, slot)
		table.remove(data.HeldExpireAt, slot)
		sendItemUpdate(player)
		return
	end

	if GameState.IsTagger(player) and not def.CanTaggerUse then
		Remotes.NotifyPlayer(player, def.DisplayName .. " は鬼には使えません")
		return
	end

	local ok, reason = handler(player, def, data)
	if ok then
		table.remove(data.HeldItems, slot) -- 後ろの枠のアイテムは前に詰める
		table.remove(data.HeldExpireAt, slot)
	elseif reason then
		Remotes.NotifyPlayer(player, reason)
	end
	sendItemUpdate(player)
end

-- サーバー内部（ボット）からも、クライアントと同じ使用処理を通す
ItemManager.TryUse = onUseItem

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
		if data.StarUntil > 0 and data.StarUntil <= now then
			data.StarUntil = 0
			removeStarVisual(player)
			sendItemUpdate(player)
			Remotes.NotifyPlayer(player, "スターが消えた")
		end

		-- バナナですべっている最中は、決まった向きへ進み続ける
		if data.SlipUntil > 0 then
			local root = GameState.GetRootPart(player)
			if data.SlipUntil <= now then
				data.SlipUntil = 0
				data.SlipDirection = nil
				if root then
					local velocity = root.AssemblyLinearVelocity
					root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
				end
			elseif root and data.SlipDirection then
				local velocity = root.AssemblyLinearVelocity
				root.AssemblyLinearVelocity = Vector3.new(
					data.SlipDirection.X * Config.Items.Banana.SlipSpeed,
					velocity.Y,
					data.SlipDirection.Z * Config.Items.Banana.SlipSpeed
				)
			end
		end

		-- ボックスで手に入れたアイテムの使用期限切れ（後ろの枠から消す）
		for index = #data.HeldItems, 1, -1 do
			local expireAt = data.HeldExpireAt[index] or 0
			if expireAt > 0 and expireAt <= now then
				local expiredId = data.HeldItems[index]
				table.remove(data.HeldItems, index)
				table.remove(data.HeldExpireAt, index)
				local def = Config.Items[expiredId]
				if def then
					Remotes.NotifyPlayer(player, def.DisplayName .. " の使用期限が切れた")
				end
				sendItemUpdate(player)
			end
		end
	end

	-- 置いたまま時間が過ぎたバナナを消す
	local expiredBananas = {}
	for part, info in pairs(placedBananas) do
		if info.ExpireAt <= now then
			table.insert(expiredBananas, part)
		end
	end
	for _, part in ipairs(expiredBananas) do
		removeBanana(part)
	end
end

-- 復活したときにシールド・スターの見た目を付け直す
function ItemManager.OnCharacterAdded(player)
	if GameState.HasShield(player) then
		addShieldVisual(player)
	end
	if GameState.HasStar(player) then
		addStarVisual(player)
	end
end

---------------------------------------------------------------------
-- 購入（アイテムボックス）での付与。Monetization から呼ぶ
---------------------------------------------------------------------

-- 持ち物に1つ加える。枠がいっぱいなら、いちばん古いもの（1枠目）を捨てて入れ替える。
-- 購入アイテムに使用期限はないので、期限は常に 0（期限なし）で入れる。
-- 戻り値: 入れ替えで捨てたアイテムの Id（入れ替えなしなら nil）
local function addToInventory(player, itemId)
	local data = GameState.GetData(player)
	local replaced = nil
	while #data.HeldItems >= GameState.GetItemSlots(player) do
		replaced = table.remove(data.HeldItems, 1)
		table.remove(data.HeldExpireAt, 1)
	end
	table.insert(data.HeldItems, itemId)
	table.insert(data.HeldExpireAt, 0)
	return replaced
end

local function notifyBoxResult(player, itemId, replacedId)
	local def = Config.Items[itemId]
	local slot = #GameState.GetData(player).HeldItems
	local text = string.format(
		"アイテムボックス: %s を手に入れた！ ［%s］で使う",
		def.DisplayName, Config.GetSlotKeyLabel(slot)
	)
	local replacedDef = Config.GetItem(replacedId)
	if replacedDef then
		text = text .. string.format("（枠がいっぱいだったので %s と入れ替えた）", replacedDef.DisplayName)
	end
	Remotes.NotifyPlayer(player, text)
end

-- 今使えるアイテムの中からランダムに1つ選ぶ（鬼には鬼が使えるアイテムだけ）
local function pickBoxItemFor(player)
	local isTagger = GameState.IsTagger(player)
	local itemId = pickRandomItemId(function(def)
		return def.CanTaggerUse or not isTagger
	end)
	return itemId or pickRandomItemId(nil)
end

-- アイテムボックスの中身を必ず渡す。戻り値: 渡した（または予約した）アイテムの Id。失敗時 nil
--   ラウンド中の参加者 → その場で持ち物に入れる（いっぱいなら入れ替え）
--   それ以外（待機中・観戦中など）→ 予約して、次のラウンド開始時に渡す
function ItemManager.GrantItemBox(player)
	if not player or (type(player) == "table" and player.IsBot == true) or not player.Parent then
		return nil
	end
	local data = GameState.GetData(player)

	if active and GameState.Phase == "Round" and GameState.IsParticipant(player) then
		local itemId = pickBoxItemFor(player)
		if not itemId then
			return nil
		end
		local replacedId = addToInventory(player, itemId)
		sendItemUpdate(player)
		notifyBoxResult(player, itemId, replacedId)
		return itemId
	end

	-- 中身はラウンド開始時に（その時の役割に合わせて）決める
	table.insert(data.PendingItems, "ItemBox")
	Remotes.NotifyPlayer(player, "アイテムボックスを受け取った！ 次のラウンド開始時にアイテムが届きます")
	return "ItemBox"
end

-- 予約中のアイテムボックスを渡す（ラウンド開始時）
local function deliverPending(player)
	local data = GameState.GetData(player)
	if #data.PendingItems == 0 then
		return
	end
	local pending = data.PendingItems
	data.PendingItems = {}
	for _ in ipairs(pending) do
		local itemId = pickBoxItemFor(player)
		if itemId then
			local replacedId = addToInventory(player, itemId)
			notifyBoxResult(player, itemId, replacedId)
		end
	end
	sendItemUpdate(player)
end

-- ラウンド開始直後（最初の鬼が決まった後）に呼ぶ: 予約中のアイテムを参加者に渡す
function ItemManager.DeliverPendingItems()
	for _, player in ipairs(GameState.ParticipantList()) do
		deliverPending(player)
	end
end

-- 所持枠の数が変わったとき（ダブルアイテム購入直後など）に呼ぶ
function ItemManager.OnSlotsChanged(player)
	local data = GameState.GetData(player)
	while #data.HeldItems > GameState.GetItemSlots(player) do
		table.remove(data.HeldItems, 1)
		table.remove(data.HeldExpireAt, 1)
	end
	sendItemUpdate(player)
end

-- フィールドの箱を1つ出す（ラウンド中・Start 済みであること）。テストからも使う。
function ItemManager.SpawnOne()
	spawnOne()
end

-- ラウンド開始時に呼ぶ: アイテムの定期出現を始める
function ItemManager.Start()
	active = true
	spawnLoopToken = spawnLoopToken + 1
	local myToken = spawnLoopToken
	task.spawn(function()
		while active and spawnLoopToken == myToken do
			task.wait(Config.BoxSpawnInterval)
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

	local bananas = {}
	for part in pairs(placedBananas) do
		table.insert(bananas, part)
	end
	for _, part in ipairs(bananas) do
		removeBanana(part)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		GameState.ResetData(player)
		removeShieldVisual(player)
		removeStarVisual(player)
		sendItemUpdate(player)
	end
end

function ItemManager.Init()
	Remotes.UseItem.OnServerEvent:Connect(function(player, slotArg)
		if type(player) == "table" and player.IsBot == true then
			return
		end
		onUseItem(player, slotArg)
	end)
end

return ItemManager
