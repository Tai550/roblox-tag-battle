-- Shop: ショップ画面（開くボタンと、3商品の一覧）
-- ここでは購入画面（Roblox の確認ダイアログ）を出すだけ。付与の確定はすべてサーバー側
-- （Developer Product は ProcessReceipt、Game Pass は所有確認）で行う。
--
--   ID が 0 の商品        → 「準備中」と表示し、購入ボタンは押せない
--   所有済みの Game Pass  → 「所有済み」と表示し、購入ボタンは押せない
--   アイテムボックス      → ラウンドに参加している間だけ買える（買った瞬間に使えるようにするため）

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local BrandColors = Config.BrandColors
local UILayout = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("UILayout"))
local EdgeMargin = UILayout.EdgeMargin
local TouchSize = UILayout.MinTouchSize
local CloseInset = 12
local ListTop = CloseInset + TouchSize + 8
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StateUpdate = Remotes:WaitForChild("StateUpdate")
local PassUpdate = Remotes:WaitForChild("PassUpdate")

local localPlayer = Players.LocalPlayer

local COLOR_PANEL = BrandColors.Surface
local COLOR_ROW = BrandColors.Primary
local COLOR_BUY = BrandColors.Accent
local COLOR_DISABLED = BrandColors.Secondary
local COLOR_OWNED = BrandColors.Primary
local COLOR_TEXT = BrandColors.White

-- 表示する商品（並び順）
local PRODUCTS = {
	{ Key = "ItemBox", Kind = "Product" },
	{ Key = "DoubleItem", Kind = "GamePass" },
	{ Key = "SparkleTrail", Kind = "GamePass" },
}

local ownedPasses = {}      -- [passKey] = true（サーバーから届いた所有状態）
local inRound = false       -- 自分がラウンドに参加中か
local prices = {}           -- [商品Key] = Robux 価格（取れたときだけ）
local rows = {}             -- [商品Key] = { Button = ..., Status = ... }

local function getId(product)
	local settings = Config.Monetization[product.Key]
	if product.Kind == "Product" then
		return tonumber(settings.ProductId) or 0
	end
	return tonumber(settings.PassId) or 0
end

---------------------------------------------------------------------
-- 画面の部品
---------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ShopGui"
gui.ResetOnSpawn = false
UILayout.ApplySafeArea(gui)
gui.DisplayOrder = 20

local function addCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function makeText(className, parent, text, textSize, color)
	local label = Instance.new(className)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = color or COLOR_TEXT
	label.Text = text
	label.Parent = parent
	return label
end

-- 開くボタン（画面左の中ほど）
local openButton = makeText("TextButton", gui, "ショップ", 20)
openButton.Name = "OpenShop"
openButton.Size = UDim2.new(0, 110, 0, TouchSize)
openButton.Position = UDim2.new(0, EdgeMargin, 0.5, -TouchSize / 2)
openButton.BackgroundTransparency = 0.15
openButton.BackgroundColor3 = BrandColors.Primary
openButton.TextColor3 = BrandColors.White
addCorner(openButton, 10)

-- 一覧のパネル
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(1, -2 * EdgeMargin, 1, -2 * EdgeMargin)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = COLOR_PANEL
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
addCorner(panel, 14)

local sizeLimit = Instance.new("UISizeConstraint")
sizeLimit.MaxSize = Vector2.new(480, 360)
sizeLimit.Parent = panel

local title = makeText("TextLabel", panel, "ショップ", 24)
title.Size = UDim2.new(1, -TouchSize - CloseInset - 24, 0, TouchSize)
title.Position = UDim2.new(0, 16, 0, CloseInset)
title.TextXAlignment = Enum.TextXAlignment.Left

local closeButton = makeText("TextButton", panel, "×", 26)
closeButton.Name = "Close"
closeButton.Size = UDim2.fromOffset(TouchSize, TouchSize)
closeButton.Position = UDim2.new(1, -CloseInset, 0, CloseInset)
closeButton.AnchorPoint = Vector2.new(1, 0)
closeButton.BackgroundTransparency = 0.6
closeButton.BackgroundColor3 = BrandColors.Secondary
addCorner(closeButton, 8)

local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Size = UDim2.new(1, -24, 1, -ListTop - 12)
list.Position = UDim2.fromOffset(12, ListTop)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.fromOffset(0, 0)
list.ScrollingDirection = Enum.ScrollingDirection.Y
list.ScrollBarThickness = 4
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

local function makeRow(product, order)
	local settings = Config.Monetization[product.Key]

	local row = Instance.new("Frame")
	row.Name = product.Key
	row.LayoutOrder = order
	row.Size = UDim2.new(1, -4, 0, TouchSize + 44)
	row.BackgroundColor3 = COLOR_ROW
	row.Parent = list
	addCorner(row, 10)

	local kindText = product.Kind == "Product" and "消費アイテム" or "ゲームパス（買い切り）"
	local name = makeText("TextLabel", row, settings.DisplayName .. "  ", 20)
	name.Size = UDim2.new(1, -150, 0, 26)
	name.Position = UDim2.new(0, 12, 0, 6)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.RichText = true
	name.Text = settings.DisplayName .. string.format('  <font size="13" color="#BEBEC8">%s</font>', kindText)

	local desc = makeText("TextLabel", row, settings.Description, 14, COLOR_TEXT)
	desc.Font = Enum.Font.Gotham
	desc.Size = UDim2.new(1, -150, 0, 54)
	desc.Position = UDim2.new(0, 12, 0, 32)
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.TextWrapped = true

	local button = makeText("TextButton", row, "", 18)
	button.Name = "Buy"
	button.Size = UDim2.new(0, 124, 0, TouchSize)
	button.Position = UDim2.new(1, -10, 0, 10)
	button.AnchorPoint = Vector2.new(1, 0)
	addCorner(button, 8)

	local status = makeText("TextLabel", row, "", 12, COLOR_TEXT)
	status.Font = Enum.Font.Gotham
	status.Size = UDim2.new(0, 124, 0, 30)
	status.Position = UDim2.new(1, -10, 0, 12 + TouchSize)
	status.AnchorPoint = Vector2.new(1, 0)
	status.TextWrapped = true

	rows[product.Key] = { Button = button, Status = status }
	return button
end

---------------------------------------------------------------------
-- 表示の更新
---------------------------------------------------------------------

-- 商品の今の状態を返す: "Preparing" / "Owned" / "Unavailable" / "Buyable"
local function getProductState(product)
	if getId(product) == 0 then
		return "Preparing"
	end
	if product.Kind == "GamePass" and ownedPasses[product.Key] then
		return "Owned"
	end
	if product.Key == "ItemBox" and not inRound then
		return "Unavailable"
	end
	return "Buyable"
end

local function setButton(button, text, color, enabled)
	button.Text = text
	button.BackgroundColor3 = color
	button.AutoButtonColor = enabled
	button.Active = enabled
	button.TextColor3 = color == COLOR_BUY and COLOR_PANEL or COLOR_TEXT
end

local function refresh()
	for _, product in ipairs(PRODUCTS) do
		local row = rows[product.Key]
		local state = getProductState(product)
		if state == "Preparing" then
			setButton(row.Button, "準備中", COLOR_DISABLED, false)
			row.Status.Text = "まだ販売していません"
		elseif state == "Owned" then
			setButton(row.Button, "所有済み", COLOR_OWNED, false)
			row.Status.Text = "効果は自動で反映されます"
		elseif state == "Unavailable" then
			setButton(row.Button, "ラウンド中のみ", COLOR_DISABLED, false)
			row.Status.Text = "ラウンドに参加中に買えます"
		else
			local price = prices[product.Key]
			setButton(row.Button, price and string.format("購入  R$ %d", price) or "購入", COLOR_BUY, true)
			row.Status.Text = ""
		end
	end
end

-- 本物の ID が入っている商品だけ、Roblox から価格を取ってきて表示する
local function loadPrices()
	for _, product in ipairs(PRODUCTS) do
		local id = getId(product)
		if id ~= 0 then
			task.spawn(function()
				local infoType = product.Kind == "Product" and Enum.InfoType.Product or Enum.InfoType.GamePass
				local ok, info = pcall(function()
					return MarketplaceService:GetProductInfo(id, infoType)
				end)
				if ok and type(info) == "table" and tonumber(info.PriceInRobux) then
					prices[product.Key] = tonumber(info.PriceInRobux)
					refresh()
				end
			end)
		end
	end
end

---------------------------------------------------------------------
-- 購入（確認ダイアログを出すだけ）
---------------------------------------------------------------------

local function onBuy(product)
	if getProductState(product) ~= "Buyable" then
		return
	end
	local id = getId(product)
	if product.Kind == "Product" then
		MarketplaceService:PromptProductPurchase(localPlayer, id)
	else
		MarketplaceService:PromptGamePassPurchase(localPlayer, id)
	end
end

for index, product in ipairs(PRODUCTS) do
	local button = makeRow(product, index)
	button.Activated:Connect(function()
		onBuy(product)
	end)
end

openButton.Activated:Connect(function()
	panel.Visible = not panel.Visible
	if panel.Visible then
		PassUpdate:FireServer() -- 開いたときに最新の所有状態をもらう
	end
end)

closeButton.Activated:Connect(function()
	panel.Visible = false
end)

---------------------------------------------------------------------
-- サーバーからの状態
---------------------------------------------------------------------

PassUpdate.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		return
	end
	ownedPasses = {}
	for _, passKey in ipairs(Config.GamePassKeys) do
		ownedPasses[passKey] = state[passKey] == true
	end
	refresh()
end)

StateUpdate.OnClientEvent:Connect(function(state)
	if type(state) ~= "table" then
		return
	end
	local participant = false
	if type(state.Participants) == "table" then
		for _, userId in ipairs(state.Participants) do
			if userId == localPlayer.UserId then
				participant = true
				break
			end
		end
	end
	local nowInRound = state.Phase == "Round" and participant
	if nowInRound ~= inRound then
		inRound = nowInRound
		refresh()
	end
end)

refresh()
gui.Parent = localPlayer:WaitForChild("PlayerGui")
PassUpdate:FireServer() -- 起動時にも所有状態をもらう（参加時の確認がまだなら、確認後にサーバーから届く）
loadPrices()
