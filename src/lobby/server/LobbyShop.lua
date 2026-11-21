-- ロビーの屋台、トレイル購入と装備、Robux 商品の受付。
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CharacterTrail = require(Shared:WaitForChild("CharacterTrail"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))

local LobbyShop = {}

local function checkOwnership(player, passId)
	for attempt = 1, 3 do
		local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, passId)
		if ok then
			return true, owns == true
		end
		warn("[LobbyShop] パスの所持確認に失敗", passId, attempt, owns)
		if attempt < 3 then
			task.wait(2)
			if player.Parent ~= Players then
				break
			end
		end
	end
	return false, false
end

local function createStall(spawn)
	local model = Instance.new("Model")
	model.Name = "ShopStall"
	local brand = Config.BrandColors
	local origin = spawn.Position + Vector3.new(-13, -spawn.Position.Y, 0)
	local facing = CFrame.lookAt(origin, Vector3.new(spawn.Position.X, origin.Y, spawn.Position.Z))

	local function part(name, offset, size, color)
		local piece = Instance.new("Part")
		piece.Name = name
		piece.Size = size
		piece.CFrame = facing * CFrame.new(offset)
		piece.Anchored = true
		piece.Color = color
		piece.Parent = model
		return piece
	end

	local counter = part("Counter", Vector3.new(0, 1.5, 0), Vector3.new(7, 3, 3), brand.Primary)
	part("Countertop", Vector3.new(0, 3, 0), Vector3.new(7.5, 0.3, 3.5), brand.Accent)
	for _, side in ipairs({ -1, 1 }) do
		part("Post", Vector3.new(side * 3.25, 4.25, 0.8), Vector3.new(0.4, 2.5, 0.4), brand.Secondary)
	end
	part("Roof", Vector3.new(0, 5.7, 0), Vector3.new(8, 0.4, 4), brand.Secondary)
	local sign = part("Sign", Vector3.new(0, 6.5, -1), Vector3.new(6, 1.2, 0.3), brand.Surface)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Text = "ショップ"
	title.TextColor3 = brand.Accent
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = surface

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "ショップを開く"
	prompt.ObjectText = "ショップ"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 10
	prompt.Parent = counter
	model.Parent = workspace
	return prompt
end

function LobbyShop.Init(options)
	local state = {}
	local processing = {}
	local shop = {}
	local prompt = createStall(options.Spawn)
	local configured = {}
	for _, key in ipairs(Config.ShopProductOrder) do
		configured[key] = Config.ShopProductId(key) ~= 0
	end

	local function sendUpdate(player)
		local current = state[player]
		if current and options.IsLoaded(player) then
			options.ShopUpdate:FireClient(player, { Owned = current.Owned, Configured = configured })
		end
	end

	local function refreshTrail(player, character)
		if character then
			CharacterTrail.Apply(character, function()
				local current = state[player]
				if current and player.Character == character then
					return CharacterTrail.Resolve(PlayerDataStore.Get(player), current.Owned.SparkleTrail)
				end
			end)
		end
	end

	function shop.PlayerLoaded(player)
		local current = { Owned = {} }
		state[player] = current
		current.CharacterConnection = player.CharacterAdded:Connect(function(character)
			refreshTrail(player, character)
		end)
		sendUpdate(player)
		task.spawn(refreshTrail, player, player.Character)
		task.spawn(function()
			for _, key in ipairs(Config.GamePassKeys) do
				local id = Config.ShopProductId(key)
				if id ~= 0 then
					local checked, owns = checkOwnership(player, id)
					if state[player] ~= current then
						return
					end
					-- 購入完了イベントが先に反映済みなら、古い照会結果で戻さない。
					if checked and not current.Owned[key] then
						current.Owned[key] = owns
					end
				end
			end
			sendUpdate(player)
			task.spawn(refreshTrail, player, player.Character)
		end)
	end

	function shop.Remove(player)
		local current = state[player]
		if current then
			current.CharacterConnection:Disconnect()
			state[player] = nil
		end
	end

	local function accept(player, id)
		local current = state[player]
		if not current or not options.IsLoaded(player) or type(id) ~= "string" or current.Busy then
			return nil
		end
		local now = os.clock()
		if current.LastRequest and now - current.LastRequest < 0.5 then
			return nil
		end
		current.LastRequest = now
		return current
	end

	prompt.Triggered:Connect(function(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if options.IsLoaded(player) and root
			and (root.Position - prompt.Parent.Position).Magnitude <= prompt.MaxActivationDistance then
			options.SendData(player)
			sendUpdate(player)
			options.OpenShop:FireClient(player)
		end
	end)

	options.BuyTrail.OnServerEvent:Connect(function(player, id)
		local current = accept(player, id)
		if not current then
			return
		end
		current.Busy = true
		local ok, reason = PlayerDataStore.BuyTrail(player, id)
		current.Busy = false
		if state[player] == current then
			options.Notify(player, ok and (Config.Trails[id].DisplayName .. " を買った！") or (reason or "買えませんでした"))
			options.SendData(player)
		end
	end)

	options.EquipTrail.OnServerEvent:Connect(function(player, id)
		local current = accept(player, id)
		if not current then
			return
		end
		if id == "Sparkle" and not current.Owned.SparkleTrail then
			options.Notify(player, "キラキラトレイルを所持していません")
			return
		end
		current.Busy = true
		local ok, _, reason = PlayerDataStore.SetEquippedTrail(player, id)
		current.Busy = false
		if state[player] == current then
			if ok then
				task.spawn(refreshTrail, player, player.Character)
			else
				options.Notify(player, reason or "持っているトレイルを選んでください")
			end
			options.SendData(player)
		end
	end)

	options.PromptPurchase.OnServerEvent:Connect(function(player, key)
		local current = accept(player, key)
		if not current then
			return
		end
		local id = Config.ShopProductId(key)
		if id == 0 or current.Owned[key] then
			return
		end
		local openPurchase = key == "ItemBox" and MarketplaceService.PromptProductPurchase
			or MarketplaceService.PromptGamePassPurchase
		local ok, err = pcall(openPurchase, MarketplaceService, player, id)
		if not ok then
			warn("[LobbyShop] 購入画面を開けませんでした", key, err)
			options.Notify(player, "購入画面を開けませんでした")
		end
	end)

	-- 参加時の通知より UI の起動が遅い場合にも、最新の状態を返す。
	options.ShopUpdate.OnServerEvent:Connect(function(player)
		if accept(player, "ShopUpdate") then
			options.SendData(player)
			sendUpdate(player)
		end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, wasPurchased)
		local current = state[player]
		if not wasPurchased or not current then
			return
		end
		for _, key in ipairs(Config.GamePassKeys) do
			if Config.ShopProductId(key) == passId and passId ~= 0 then
				checkOwnership(player, passId)
				if state[player] == current then
					-- 購入直後の照会は古い結果を返すことがある。サーバーの購入完了イベントを優先する。
					current.Owned[key] = true
					sendUpdate(player)
					task.spawn(refreshTrail, player, player.Character)
					options.Notify(player, Config.Monetization[key].DisplayName .. " を購入しました！")
				end
				return
			end
		end
	end)

	local granted = Enum.ProductPurchaseDecision.PurchaseGranted
	local pending = Enum.ProductPurchaseDecision.NotProcessedYet
	MarketplaceService.ProcessReceipt = function(receipt)
		local productId = Config.ShopProductId("ItemBox")
		local purchaseId = receipt.PurchaseId
		if productId == 0 or receipt.ProductId ~= productId or type(purchaseId) ~= "string" or purchaseId == "" then
			return pending
		end
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if not player or processing[purchaseId] then
			return pending
		end

		processing[purchaseId] = true
		-- 再送は入室時のデータ読み込みを待たずに届くことがある。
		local deadline = os.clock() + 30
		while player.Parent == Players and not options.IsLoaded(player) and os.clock() < deadline do
			task.wait(0.1)
		end
		if not options.IsLoaded(player) then
			processing[purchaseId] = nil
			return pending
		end
		local ok, saved, added = pcall(PlayerDataStore.AddItemBox, player, purchaseId)
		processing[purchaseId] = nil
		if not ok or not saved then
			warn("[LobbyShop] アイテムボックスの保存に失敗", receipt.PlayerId)
			return pending
		end
		if added and options.IsLoaded(player) then
			sendUpdate(player)
			options.Notify(player, "アイテムボックスを購入しました！ 次の試合で受け取れます")
		end
		return granted
	end
	return shop
end

return LobbyShop
