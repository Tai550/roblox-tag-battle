-- ItemManager: バトルアイテムの出現・拾う処理・使用効果（すべてサーバー側で確定）
--
-- クライアントから届くのは UseItem の「何枠目を使いたい」という合図だけ。
-- 何を持っているか、使えるか、効果がどうなるかはサーバーが持つ状態だけで決める。
-- 所持はリスト形式（data.HeldItems、古い順）。枠数は GameState.GetItemSlots で決まる。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local ZoneManager = require(script.Parent:WaitForChild("ZoneManager"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))

local ItemManager = {}

local SHIELD_EFFECT_NAME = "TagShieldEffect"
local STAR_EFFECT_NAME = "TagStarEffect"

local active = false
local spawnLoopToken = 0
local spawnedItems = {}     -- [Part] = { IsBox = true, PointKey = ... } フィールドのボックス
local boxMotions = {}       -- [Part] = Heartbeat の接続（箱を消したら必ず切る）
local occupiedPoints = {}   -- [PointKey] = Part
local placedBananas = {}    -- [Part] = { PlacedBy = Player, ExpireAt = 時刻 }
local placedGlue = {}       -- [Part] = { PlacedBy = Player, ExpireAt = 時刻 }  ねばねば罠
local decoys = {}           -- [Model] = 消える時刻  ダミー人形
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
	if not Remotes.IsRealPlayer(player) then
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
		-- 画面の端に小さく出す「効果中」の一覧
		Effects = {
			{ Name = "ダッシュ", Left = math.max(0, data.DashUntil - now) },
			{ Name = "シールド", Left = math.max(0, data.ShieldUntil - now) },
			{ Name = "スター", Left = math.max(0, data.StarUntil - now) },
			{ Name = "ハイジャンプ", Left = math.max(0, data.JumpUntil - now) },
			{ Name = "しのび足", Left = math.max(0, data.SneakUntil - now) },
			{ Name = "エリアガード", Left = math.max(0, data.ZoneGuardUntil - now) },
			{ Name = "ねばねば", Left = math.max(0, data.SlowUntil - now) },
			{ Name = "タイムストップ", Left = math.max(0, data.FrozenUntil - now) },
			{ Name = "壁抜け", Left = math.max(0, (data.PhaseUntil or 0) - now) },
			{ Name = "スパイクブーツ", Left = math.max(0, (data.SpikeBootsUntil or 0) - now) },
			{ Name = "絶縁", Left = math.max(0, (data.InsulateUntil or 0) - now) },
		},
		SpikeBootsUntil = data.SpikeBootsServerTime or 0,
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
local function pickRandomItemId(pool, filter)
	local candidates = {}
	local total = 0
	for _, itemId in ipairs(pool) do
		local def = Config.Items[itemId]
		if def and def.SpawnWeight > 0 and (filter == nil or filter(def)) then
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
-- 通常枠は従来どおりデッキから。固有アイテムだけマップの候補を足す。
function ItemManager.GetFieldPool(deck, mapId)
	local pool = table.clone(deck)
	for id, def in pairs(Config.Items) do
		if def.ExclusiveMap and def.ExclusiveMap == mapId and def.SpawnWeight > 0 then
			table.insert(pool, id)
		end
	end
	return pool
end

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

	local pool = ItemManager.GetFieldPool(DeckManager.GetDeck(player), MapBuilder.CurrentMap)
	local itemId = pickRandomItemId(pool)
	if not itemId then
		return
	end

	removeItem(part)
	table.insert(data.HeldItems, itemId)
	local def = Config.Items[itemId]
	local expireAt = (not def.Passive and Config.BoxExpireTime > 0) and GameState.Now() + Config.BoxExpireTime or 0
	table.insert(data.HeldExpireAt, expireAt)
	sendItemUpdate(player)

	if def.Passive then
		Remotes.NotifyPlayer(player, "ボックスから " .. def.DisplayName .. " が出た！ " .. def.Description)
		return
	end
	Remotes.NotifyPlayer(player, string.format(
		"%s をゲット！［%s］で使う", def.DisplayName, Config.GetSlotKeyLabel(#data.HeldItems)
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

-- エリアの中のランダムな「空いた地面」を探す。
-- 真上から光線を落として、最初に当たったのが低い地面なら OK（＝上に建物も木もない）。
local function findOpenGround()
	local centerPos, radius
	if ZoneManager.IsActive() then
		centerPos = ZoneManager.GetCenter()
		radius = ZoneManager.GetRadius() * 0.9
	else
		centerPos = Config.FallbackSpawnCenter
		radius = Config.ZoneFallbackRadius
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { getItemContainer() }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	local wall = workspace:FindFirstChild("ZoneWall")
	if wall then
		table.insert(ignore, wall)
	end
	params.FilterDescendantsInstances = ignore
	-- 置ける高さの上限（空中の足場マップは Map の属性で上げる）
	local map = workspace:FindFirstChild("Map")
	local maxHeight = (map and map:GetAttribute("BoxGroundMaxHeight")) or Config.BoxGroundMaxHeight
	for _ = 1, Config.BoxSpawnTries do
		local angle = math.random() * math.pi * 2
		local dist = math.sqrt(math.random()) * radius -- 円の中で均等に散らばるように
		local x = centerPos.X + math.cos(angle) * dist
		local z = centerPos.Z + math.sin(angle) * dist
		local hit = workspace:Raycast(Vector3.new(x, 200, z), Vector3.new(0, -400, 0), params)
		if hit and hit.Position.Y <= maxHeight then
			return hit.Position
		end
	end
	return nil
end

local function spawnOne()
	if countItems() >= Config.BoxMaxOnMap then
		return
	end
	local ground = findOpenGround()
	if not ground then
		return -- 空いた地面が見つからなければ、今回は出さない（次の回でまた探す）
	end
	zoneBoxCounter = zoneBoxCounter + 1
	local key = "Box" .. zoneBoxCounter
	local part = createBoxPart(ground + Vector3.new(0, Config.ItemHeightOffset, 0))

	spawnedItems[part] = { IsBox = true, PointKey = key }
	occupiedPoints[key] = part

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
	if Remotes.IsRealPlayer(tagger) then
		Remotes.SmokeEffect:FireClient(tagger, def.Duration, def.FadeOutTime)
	else
		GameState.GetData(tagger).BlindUntil = GameState.Now() + def.Duration -- ボットの鬼は立ち止まる
	end
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
	player.Character:SetAttribute("BananaSlipping", true)

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

---------------------------------------------------------------------
-- 追加アイテム
---------------------------------------------------------------------

-- 鬼以外の、まだ残っている参加者
local function activeRunners()
	local list = {}
	for _, other in ipairs(GameState.ParticipantList()) do
		if other ~= GameState.Tagger and GameState.IsAlive(other) then
			table.insert(list, other)
		end
	end
	return list
end

handlers.HighJump = function(player, def, data)
	data.JumpUntil = GameState.Now() + def.Duration
	GameState.RefreshSpeed(player)
	Remotes.NotifyPlayer(player, string.format("ハイジャンプ！ %d秒間 高く跳べる", def.Duration))
	return true
end

handlers.Decoy = function(player, def, data)
	local character = player.Character
	local root = GameState.GetRootPart(player)
	if not character or not root then
		return false, nil
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local copy = character:Clone()
	character.Archivable = wasArchivable
	if not copy then
		return false, nil
	end
	copy.Name = "Decoy"
	for _, child in ipairs(copy:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ForceField") or child:IsA("Sparkles") then
			child:Destroy()
		elseif child:IsA("BasePart") then
			child.Anchored = true
			child.CanCollide = false
			child.CanTouch = false
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayName = player.DisplayName
	end
	copy.Parent = getItemContainer()
	decoys[copy] = GameState.Now() + def.Duration
	Remotes.NotifyPlayer(player, "ダミー人形を置いた！")
	return true
end

handlers.Flash = function(player, def, data)
	local tagger = GameState.Tagger
	local root = GameState.GetRootPart(player)
	local taggerRoot = GameState.GetRootPart(tagger)
	if not tagger or tagger == player or not root or not taggerRoot then
		return false, "今はフラッシュを使えません"
	end
	if (taggerRoot.Position - root.Position).Magnitude > def.Range then
		return false, "鬼が遠すぎます（近づいてから使おう）"
	end
	if Remotes.IsRealPlayer(tagger) then
		Remotes.SmokeEffect:FireClient(tagger, def.Duration, def.FadeOutTime)
	else
		GameState.GetData(tagger).BlindUntil = GameState.Now() + def.Duration
	end
	Remotes.NotifyPlayer(player, "フラッシュ！ 鬼の目をくらませた")
	return true
end

local function setSneakVisual(player, on, def)
	local character = player.Character
	if not character then
		return
	end
	for _, child in ipairs(character:GetDescendants()) do
		if (child:IsA("BasePart") and child.Name ~= "HumanoidRootPart") or child:IsA("Decal") then
			if on then
				if child:GetAttribute("SneakOriginal") == nil then
					child:SetAttribute("SneakOriginal", child.Transparency)
				end
				child.Transparency = math.max(child.Transparency, def.Transparency)
			else
				local original = child:GetAttribute("SneakOriginal")
				if original ~= nil then
					child.Transparency = original
					child:SetAttribute("SneakOriginal", nil)
				end
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = on and Enum.HumanoidDisplayDistanceType.None
			or Enum.HumanoidDisplayDistanceType.Viewer
	end
end

handlers.Sneak = function(player, def, data)
	data.SneakUntil = GameState.Now() + def.Duration
	setSneakVisual(player, true, def)
	Remotes.NotifyPlayer(player, string.format("しのび足！ %d秒間 見えにくくなる", def.Duration))
	return true
end

local function removeGlue(part)
	placedGlue[part] = nil
	part:Destroy()
end

local function onGlueTouched(part, hit)
	local info = placedGlue[part]
	if not info or not active then
		return
	end
	local player = GameState.ParticipantFromHit(hit)
	if not player or not GameState.IsTagger(player) then
		return -- 鬼だけが引っかかる（ボットの鬼も）
	end
	local def = Config.Items.Glue
	GameState.GetData(player).SlowUntil = GameState.Now() + def.SlowTime
	GameState.RefreshSpeed(player)
	removeGlue(part)
	Remotes.NotifyPlayer(player, "ねばねば罠にかかった！")
	if info.PlacedBy and info.PlacedBy.Parent then
		Remotes.NotifyPlayer(info.PlacedBy, "鬼がねばねば罠にかかった！")
	end
	sendItemUpdate(player)
end

handlers.Glue = function(player, def, data)
	local root = GameState.GetRootPart(player)
	if not root then
		return false, nil
	end
	local part = Instance.new("Part")
	part.Name = "GlueTrap"
	part.Size = Vector3.new(5, 0.3, 5)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Transparency = 0.3
	part.Color = def.Color
	part.Position = Vector3.new(root.Position.X, root.Position.Y - 2.8, root.Position.Z)
	placedGlue[part] = { PlacedBy = player, ExpireAt = GameState.Now() + def.Duration }
	part.Touched:Connect(function(hit)
		onGlueTouched(part, hit)
	end)
	part.Parent = getItemContainer()
	Remotes.NotifyPlayer(player, "ねばねば罠を置いた！")
	return true
end

handlers.AirBurst = function(player, def, data)
	local root = GameState.GetRootPart(player)
	if not root then
		return false, nil
	end
	local count = 0
	for _, other in ipairs(GameState.ParticipantList()) do
		local otherRoot = GameState.GetRootPart(other)
		if other ~= player and otherRoot and GameState.IsAlive(other) then
			local offset = otherRoot.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			if offset.Magnitude <= def.Range then
				local direction = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
				otherRoot.AssemblyLinearVelocity = direction * def.PushSpeed + Vector3.new(0, def.LiftSpeed, 0)
				Remotes.NotifyPlayer(other, player.DisplayName .. " のエアバーストで吹き飛ばされた！")
				count = count + 1
			end
		end
	end
	Remotes.NotifyPlayer(player, count > 0 and string.format("エアバースト！ %d人を吹き飛ばした", count)
		or "エアバースト！（まわりに誰もいなかった）")
	return true
end

handlers.ZoneGuard = function(player, def, data)
	data.ZoneGuardUntil = GameState.Now() + def.Duration
	Remotes.NotifyPlayer(player, string.format("エリアガード！ %d秒間 エリア外でもスタミナが減らない", def.Duration))
	return true
end

handlers.Radar = function(player, def, data)
	-- 光らせる相手のキャラクター（ボットも含む）を送る
	local targets = {}
	if GameState.IsTagger(player) then
		for _, runner in ipairs(activeRunners()) do
			if runner.Character then
				table.insert(targets, runner.Character)
			end
		end
	elseif GameState.Tagger and GameState.Tagger.Character then
		table.insert(targets, GameState.Tagger.Character)
	end
	if #targets == 0 then
		return false, "今はレーダーで探す相手がいません"
	end
	Remotes.RadarEffect:FireClient(player, targets, def.Duration)
	Remotes.NotifyPlayer(player, string.format("レーダー！ %d秒間 相手が光って見える", def.Duration))
	return true
end

handlers.TimeStop = function(player, def, data)
	local tagger = GameState.Tagger
	if not tagger or tagger == player or not GameState.IsAlive(tagger) then
		return false, "今はタイムストップを使えません"
	end
	GameState.GetData(tagger).FrozenUntil = GameState.Now() + def.Duration
	GameState.RefreshSpeed(tagger)
	Remotes.NotifyPlayer(tagger, player.DisplayName .. " のタイムストップで動けない！")
	Remotes.NotifyPlayer(player, "タイムストップ！ 鬼を止めた")
	sendItemUpdate(tagger)
	return true
end

handlers.SecondChance = function(player, def, data)
	if data.ZoneReturns <= 0 then
		return false, "まだ強制送還されていません（送還されたあとに使おう）"
	end
	data.ZoneReturns = data.ZoneReturns - 1
	Leaderstats.Set(player, "Returns", data.ZoneReturns)
	ZoneManager.SendZoneUpdate(player)
	Remotes.NotifyPlayer(player, "セカンドチャンス！ 強制送還の回数が1回もどった")
	return true
end

local function applyPhaseGroup(effect, part)
	if part:IsA("BasePart") and effect.Groups[part] == nil then
		effect.Groups[part] = part.CollisionGroup
		part.CollisionGroup = MapBuilder.PhaseGroup
	end
end

function ItemManager.EndPhase(player)
	local data = GameState.GetData(player)
	local effect = data.PhaseEffect
	if not effect then
		return
	end
	effect.Connection:Disconnect()
	local map = workspace:FindFirstChild(MapBuilder.MapFolderName)
	local walls = map and map:FindFirstChild("CaveInnerWalls")
	if walls and effect.Character == player.Character then
		local query = OverlapParams.new()
		query.FilterType = Enum.RaycastFilterType.Include
		query.FilterDescendantsInstances = { walls }
		query.MaxParts = 1
		local root = GameState.GetRootPart(player)
		for part in pairs(effect.Groups) do
			if part.Parent and (part == root or part.CanCollide)
				and #workspace:GetPartsInPart(part, query) > 0 then
				effect.Character:PivotTo(effect.Start)
				if root then
					root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
				end
				break
			end
		end
	end
	for part, group in pairs(effect.Groups) do
		if part.Parent then
			part.CollisionGroup = group
		end
	end
	data.PhaseEffect = nil
	data.PhaseUntil = 0
end

handlers.Phase = function(player, def, data)
	local character = player.Character
	if not character or not GameState.GetRootPart(player) then
		return false
	end
	local effect = data.PhaseEffect
	if not effect then
		effect = { Character = character, Start = character:GetPivot(), Groups = {} }
		effect.Connection = character.DescendantAdded:Connect(function(part)
			applyPhaseGroup(effect, part)
		end)
		for _, part in ipairs(character:GetDescendants()) do
			applyPhaseGroup(effect, part)
		end
		data.PhaseEffect = effect
	end
	data.PhaseUntil = GameState.Now() + def.Duration
	Remotes.NotifyPlayer(player, "壁抜け！ 2.5秒間、洞窟の内壁を通り抜けられる")
	return true
end

handlers.SpikeBoots = function(player, def, data)
	data.SpikeBootsUntil = GameState.Now() + def.Duration
	data.SpikeBootsServerTime = workspace:GetServerTimeNow() + def.Duration
	Remotes.NotifyPlayer(player, "スパイクブーツ！ 5秒間、氷の床で滑らない")
	return true
end

handlers.Insulate = function(player, def, data)
	data.InsulateUntil = GameState.Now() + def.Duration
	Remotes.NotifyPlayer(player, "絶縁！ 6秒間、帯電部品で痺れない")
	return true
end

function ItemManager.TrySafetyLine(player)
	if type(player) == "table" and player.IsBot then
		return false
	end
	local data = GameState.GetData(player)
	local slot = table.find(data.HeldItems, "SafetyLine")
	local root = GameState.GetRootPart(player)
	if not slot or not data.LastSkyStand or not root then
		return false
	end
	local expires = data.HeldExpireAt[slot] or 0
	if expires > 0 and expires <= GameState.Now() then
		return false
	end
	player.Character:PivotTo(data.LastSkyStand)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	table.remove(data.HeldItems, slot)
	table.remove(data.HeldExpireAt, slot)
	sendItemUpdate(player)
	Remotes.NotifyPlayer(player, "命綱が発動！ 最後の足場に戻った")
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
	if def and def.ExclusiveMap then
		if (type(player) == "table" and player.IsBot) or def.ExclusiveMap ~= MapBuilder.CurrentMap then
			return
		end
		if def.Passive then
			Remotes.NotifyPlayer(player, def.Description)
			return
		end
	end
	local expires = data.HeldExpireAt[slot] or 0
	if expires > 0 and expires <= now then
		return
	end
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
		if data.PhaseEffect and (data.PhaseUntil <= now or data.PhaseEffect.Character ~= player.Character
			or not GameState.IsAlive(player)) then
			ItemManager.EndPhase(player)
		end
		local stunned = data.StunUntil > now
		if stunned then
			GameState.StopStunnedMovement(player)
		elseif data.StunUntil > 0 then
			GameState.ClearStun(player)
			GameState.RefreshSpeed(player)
		end
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

		-- 追加アイテムの効果切れ
		if data.JumpUntil > 0 and data.JumpUntil <= now then
			data.JumpUntil = 0
			GameState.RefreshSpeed(player)
			sendItemUpdate(player)
		end
		if data.SlowUntil > 0 and data.SlowUntil <= now then
			data.SlowUntil = 0
			GameState.RefreshSpeed(player)
			sendItemUpdate(player)
		end
		if data.FrozenUntil > 0 and data.FrozenUntil <= now then
			data.FrozenUntil = 0
			GameState.RefreshSpeed(player)
			sendItemUpdate(player)
		end
		if data.SneakUntil > 0 and data.SneakUntil <= now then
			data.SneakUntil = 0
			setSneakVisual(player, false)
			sendItemUpdate(player)
		end
		if data.ZoneGuardUntil > 0 and data.ZoneGuardUntil <= now then
			data.ZoneGuardUntil = 0
			Remotes.NotifyPlayer(player, "エリアガードが切れた")
			sendItemUpdate(player)
		end

		-- バナナですべっている最中は、決まった向きへ進み続ける
		if data.SlipUntil > 0 then
			local root = GameState.GetRootPart(player)
			if data.SlipUntil <= now then
				data.SlipUntil = 0
				data.SlipDirection = nil
				if player.Character then
					player.Character:SetAttribute("BananaSlipping", nil)
				end
				if root then
					local velocity = root.AssemblyLinearVelocity
					root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
				end
			elseif root and data.SlipDirection and not stunned then
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

	-- 時間が過ぎた罠とダミー人形を消す
	local expiredGlue = {}
	for part, info in pairs(placedGlue) do
		if info.ExpireAt <= now then
			table.insert(expiredGlue, part)
		end
	end
	for _, part in ipairs(expiredGlue) do
		removeGlue(part)
	end
	local expiredDecoys = {}
	for model, expireAt in pairs(decoys) do
		if expireAt <= now then
			table.insert(expiredDecoys, model)
		end
	end
	for _, model in ipairs(expiredDecoys) do
		decoys[model] = nil
		model:Destroy()
	end
end

-- 復活したときにシールド・スターの見た目を付け直す
function ItemManager.OnCharacterAdded(player)
	ItemManager.EndPhase(player)
	if GameState.IsSlipping(player) then
		player.Character:SetAttribute("BananaSlipping", true)
	end
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
	local itemId = pickRandomItemId(Config.ItemOrder, function(def)
		return not def.ExclusiveMap and (def.CanTaggerUse or not isTagger)
	end)
	return itemId or pickRandomItemId(Config.ItemOrder, function(def)
		return not def.ExclusiveMap
	end)
end

-- アイテムボックスの中身を必ず渡す。戻り値: 渡した（または予約した）アイテムの Id。失敗時 nil
--   ラウンド中の参加者 → その場で持ち物に入れる（いっぱいなら入れ替え）
--   それ以外（待機中・観戦中など）→ 予約して、次のラウンド開始時に渡す
-- 指定のアイテムを渡す（管理者画面から）。試合外なら次に参加する試合で届く
function ItemManager.GrantItem(player, itemId)
	if not Remotes.IsRealPlayer(player) or not Config.Items[itemId] then
		return false
	end
	if active and GameState.Phase == "Round" and GameState.IsParticipant(player) then
		addToInventory(player, itemId)
		sendItemUpdate(player)
		Remotes.NotifyPlayer(player, Config.Items[itemId].DisplayName .. " を受け取りました")
	else
		table.insert(GameState.GetData(player).PendingItems, itemId)
		Remotes.NotifyPlayer(player, Config.Items[itemId].DisplayName .. " は次の試合で届きます")
	end
	return true
end

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
	for _, entry in ipairs(pending) do
		-- "ItemBox" はデッキから抽選、それ以外は管理者が指定したアイテムそのもの
		local itemId = entry == "ItemBox" and pickBoxItemFor(player) or (Config.Items[entry] and entry)
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
	local glue = {}
	for part in pairs(placedGlue) do
		table.insert(glue, part)
	end
	for _, part in ipairs(glue) do
		removeGlue(part)
	end
	local models = {}
	for model in pairs(decoys) do
		table.insert(models, model)
	end
	for _, model in ipairs(models) do
		decoys[model] = nil
		model:Destroy()
	end

	for player in pairs(GameState.AllData()) do
		ItemManager.EndPhase(player)
		GameState.ClearStun(player)
		if player.Character then
			player.Character:SetAttribute("BananaSlipping", nil)
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		GameState.ResetData(player)
		removeShieldVisual(player)
		removeStarVisual(player)
		setSneakVisual(player, false)
		GameState.RefreshSpeed(player)
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
