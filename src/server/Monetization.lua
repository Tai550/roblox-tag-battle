-- Monetization: 課金まわりのサーバー処理（付与の確定はすべてここ＝サーバー側）
--
--   1. アイテムボックス（Developer Product）
--      MarketplaceService.ProcessReceipt でレシートを受け取り、ProductId が
--      Config.Monetization.ItemBox.ProductId と一致するときだけアイテムを付与する。
--      同じレシートを二重に付与しないよう、処理済みの PurchaseId をセッション内で記録する。
--   2. Game Pass（ダブルアイテム / キラキラトレイル）
--      参加時と購入完了時（PromptGamePassPurchaseFinished）に UserOwnsGamePassAsync で
--      所有を確認し、結果を GameState に持つ。購入直後から再参加なしで反映する。
--
-- クライアントは購入画面を出すだけで、ここで決めた結果だけが反映される。

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local GameState = require(script.Parent:WaitForChild("GameState"))
local Remotes = require(script.Parent:WaitForChild("Remotes"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local SparkleTrail = require(script.Parent:WaitForChild("SparkleTrail"))

local Monetization = {}

local OWNERSHIP_RETRIES = 3       -- 所有確認が通信エラーで失敗したときの再試行回数
local RETRY_WAIT = 2              -- 再試行の間隔（秒）
local PASS_REQUEST_COOLDOWN = 1   -- クライアントからの「所有状態を送って」の受付間隔（秒）

local processedPurchaseIds = {}   -- [PurchaseId] = true  このサーバーで付与済みのレシート
local lastPassRequest = {}        -- [Player] = 時刻

local function isInGame(player)
	if player == nil or (type(player) == "table" and player.IsBot == true) then
		return false
	end
	return player.Parent == Players
end

---------------------------------------------------------------------
-- Game Pass の所有確認
---------------------------------------------------------------------

local function getPassId(passKey)
	local settings = Config.Monetization[passKey]
	return settings and tonumber(settings.PassId) or 0
end

-- PassId から "DoubleItem" などのキーを探す（ID が 0 の商品は対象外）
local function findPassKey(passId)
	for _, passKey in ipairs(Config.GamePassKeys) do
		local id = getPassId(passKey)
		if id ~= 0 and id == passId then
			return passKey
		end
	end
	return nil
end

-- UserOwnsGamePassAsync で確認する。戻り値: 確認できたか, 所有しているか
local function checkOwnership(player, passId)
	for attempt = 1, OWNERSHIP_RETRIES do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return true, result == true
		end
		warn(string.format("[Monetization] Game Pass %d の所有確認に失敗（%d回目）: %s", passId, attempt, tostring(result)))
		if attempt < OWNERSHIP_RETRIES then
			task.wait(RETRY_WAIT)
			if not isInGame(player) then
				return false, false
			end
		end
	end
	return false, false
end

local function sendPassUpdate(player)
	if not isInGame(player) then
		return
	end
	local state = {}
	for _, passKey in ipairs(Config.GamePassKeys) do
		state[passKey] = GameState.OwnsPass(player, passKey)
	end
	Remotes.PassUpdate:FireClient(player, state)
end

-- 所有状態に合わせて、効果（枠数・トレイル）を今すぐ反映する
local function applyPassEffects(player)
	if not isInGame(player) then
		return
	end
	ItemManager.OnSlotsChanged(player) -- 枠数が変わったことをアイテム表示に送る
	if player.Character then
		if GameState.OwnsPass(player, "SparkleTrail") then
			task.spawn(SparkleTrail.Attach, player.Character)
		else
			SparkleTrail.Detach(player.Character)
		end
	end
	sendPassUpdate(player)
end

-- 参加時: すべての Game Pass の所有を確認する
local function checkAllPasses(player)
	for _, passKey in ipairs(Config.GamePassKeys) do
		local passId = getPassId(passKey)
		if passId ~= 0 then
			local checked, owns = checkOwnership(player, passId)
			if not isInGame(player) then
				return
			end
			if checked then
				GameState.SetPassOwned(player, passKey, owns)
			end
		end
	end
	applyPassEffects(player)
end

-- 購入完了時（サーバー側のイベント）
local function onGamePassPurchaseFinished(player, passId, wasPurchased)
	if not wasPurchased or not isInGame(player) then
		return
	end
	local passKey = findPassKey(passId)
	if not passKey then
		return
	end
	local checked, owns = checkOwnership(player, passId)
	if not isInGame(player) then
		return
	end
	if not owns then
		-- 購入直後は所有確認の結果がまだ古いことがある（Studio のテスト購入でも false が返る）。
		-- Roblox から届いた購入完了（wasPurchased）を信じて反映する。
		if checked then
			warn(string.format("[Monetization] Game Pass %d: 購入完了を受け取ったが所有確認はまだ false。購入完了を優先して反映します", passId))
		end
		owns = true
	end
	GameState.SetPassOwned(player, passKey, owns)
	applyPassEffects(player)

	local settings = Config.Monetization[passKey]
	Remotes.NotifyPlayer(player, string.format("%s を購入しました！ ありがとうございます", settings.DisplayName))
end

---------------------------------------------------------------------
-- Developer Product（アイテムボックス）のレシート処理
---------------------------------------------------------------------

local function processReceipt(receipt)
	local purchaseId = receipt.PurchaseId

	-- 同じレシートがもう一度届いたら、付与せずに「処理済み」と返す
	if purchaseId ~= nil and processedPurchaseIds[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local itemBoxId = tonumber(Config.Monetization.ItemBox.ProductId) or 0
	if itemBoxId == 0 or receipt.ProductId ~= itemBoxId then
		-- 設定にない商品。付与しない（Roblox が後で再送する）
		warn(string.format("[Monetization] 未設定の ProductId %s のレシートを受け取りました", tostring(receipt.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- このサーバーにいない（退出済みなど）。次に参加したときに Roblox が再送する
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(ItemManager.GrantItemBox, player)
	if not ok or not granted then
		warn("[Monetization] アイテムボックスの付与に失敗: " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if purchaseId ~= nil then
		processedPurchaseIds[purchaseId] = true
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

---------------------------------------------------------------------
-- 初期化
---------------------------------------------------------------------

local function onPlayerAdded(player)
	-- 再出現のたびにトレイルを付け直す（部品はキャラクターと一緒に消えるため）
	player.CharacterAdded:Connect(function(character)
		if GameState.OwnsPass(player, "SparkleTrail") then
			SparkleTrail.Attach(character)
		end
	end)
	task.spawn(checkAllPasses, player)
end

local function onPassStateRequest(player)
	-- クライアントからの引数は使わない。連打だけ防いで、今の状態を返す
	local now = GameState.Now()
	if lastPassRequest[player] and now - lastPassRequest[player] < PASS_REQUEST_COOLDOWN then
		return
	end
	lastPassRequest[player] = now
	sendPassUpdate(player)
end

function Monetization.Init()
	-- ProcessReceipt は1つのゲームで1か所だけ設定できる
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onGamePassPurchaseFinished)
	Remotes.PassUpdate.OnServerEvent:Connect(onPassStateRequest)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastPassRequest[player] = nil
	end)
end

return Monetization
