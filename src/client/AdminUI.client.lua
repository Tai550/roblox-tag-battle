local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(shared:WaitForChild("Config"))
local BrandColors = Config.BrandColors
local UILayout = require(shared:WaitForChild("UILayout"))
local remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AdminRequest")

local edge = UILayout.EdgeMargin
local touchSize = UILayout.MinTouchSize
local background = BrandColors.Surface
local buttonColor = BrandColors.Primary
local selectedColor = BrandColors.Accent
local textColor = BrandColors.White

local function make(className, parent, properties)
	local object = Instance.new(className)
	for property, value in pairs(properties) do
		object[property] = value
	end
	object.Parent = parent
	return object
end

local function textControl(className, parent, text, height)
	local object = make(className, parent, {
		Size = UDim2.new(1, -8, 0, height),
		BackgroundColor3 = buttonColor,
		BackgroundTransparency = className == "TextLabel" and 1 or 0,
		BorderSizePixel = 0,
		Text = text,
		TextColor3 = textColor,
		TextSize = 15,
		Font = Enum.Font.GothamMedium,
		TextWrapped = true,
	})
	if className ~= "TextLabel" then
		make("UICorner", object, { CornerRadius = UDim.new(0, 8) })
	end
	return object
end

local function stack(parent)
	make("UIListLayout", parent, {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local gui = make("ScreenGui", nil, {
	Name = "AdminGui",
	Enabled = false,
	ResetOnSpawn = false,
	DisplayOrder = 20,
})
UILayout.ApplySafeArea(gui)
gui.Parent = player:WaitForChild("PlayerGui")

local open = textControl("TextButton", gui, "管理", touchSize)
open.Name = "AdminButton"
open.AnchorPoint = Vector2.new(1, 0)
open.Position = UDim2.new(1, -edge, 0.5, -math.max(touchSize, UILayout.BottomClearance / 2))
open.Size = UDim2.fromOffset(72, touchSize)

local panel = make("Frame", gui, {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -2 * edge, 1, -2 * edge),
	BackgroundColor3 = background,
	BorderSizePixel = 0,
	Visible = false,
	Active = true,
})
make("UISizeConstraint", panel, { MaxSize = Vector2.new(540, 680) })
make("UICorner", panel, { CornerRadius = UDim.new(0, 12) })
local title = textControl("TextLabel", panel, "サーバー管理", touchSize)
title.Position = UDim2.fromOffset(12, 4)
title.Size = UDim2.new(1, -88, 0, touchSize)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextSize = 18
local close = textControl("TextButton", panel, "閉じる", touchSize)
close.BackgroundColor3 = BrandColors.Secondary
close.AnchorPoint = Vector2.new(1, 0)
close.Position = UDim2.new(1, -8, 0, 4)
close.Size = UDim2.fromOffset(64, touchSize)

local tabs = make("Frame", panel, {
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(8, touchSize + 8),
	Size = UDim2.new(1, -16, 0, touchSize),
})
local feedback = textControl("TextLabel", panel, "", 40)
feedback.Position = UDim2.new(0, 8, 1, -42)
feedback.Size = UDim2.new(1, -16, 0, 40)
feedback.TextSize = 13

local pages, tabButtons = {}, {}
local function setSelected(button, selected)
	button.BackgroundColor3 = selected and selectedColor or buttonColor
	button.TextColor3 = selected and background or textColor
end

local function selectPage(index)
	for i, page in ipairs(pages) do
		page.Visible = i == index
		setSelected(tabButtons[i], i == index)
	end
end

for index, name in ipairs({ "プレイヤー", "お知らせ", "進行", "付与と情報" }) do
	local tab = textControl("TextButton", tabs, name, touchSize)
	tab.Position = UDim2.new((index - 1) / 4, 0, 0, 0)
	tab.Size = UDim2.new(0.25, -3, 1, 0)
	tab.TextSize = 13
	tab.Activated:Connect(function() selectPage(index) end)
	tabButtons[index] = tab

	local page = make("ScrollingFrame", panel, {
		Position = UDim2.fromOffset(8, 2 * touchSize + 14),
		Size = UDim2.new(1, -16, 1, -(2 * touchSize + 58)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ScrollBarThickness = 5,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.fromOffset(0, 0),
	})
	stack(page)
	pages[index] = page
end
selectPage(1)

local function row(className, page, order, text, height)
	local control = textControl(className, page, text, height or touchSize)
	control.LayoutOrder = order
	return control
end

local function actionButton(page, order, text, callback, color)
	local button = row("TextButton", page, order, text)
	button.BackgroundColor3 = color or buttonColor
	button.TextColor3 = color == selectedColor and background or textColor
	button.Activated:Connect(callback)
	return button
end

local function input(page, order, placeholder)
	local box = row("TextBox", page, order, "")
	box.PlaceholderText = placeholder
	box.PlaceholderColor3 = BrandColors.White
	box.ClearTextOnFocus = false
	return box
end

local requestPending = false
local function request(action, first, second)
	if requestPending or player:GetAttribute("IsAdmin") ~= true then
		return
	end
	requestPending = true
	if action ~= "Status" then
		feedback.Text = "処理中…"
	end
	remote:FireServer(action, first, second)
end

local targetId, targetName, bannedId, itemId
local playerTarget = row("TextLabel", pages[1], 1, "対象を選択してください", 28)
local grantTarget = row("TextLabel", pages[4], 1, "プレイヤー欄で付与先を選択してください", 32)
local function selectTarget(id, name)
	targetId, targetName = id, name
	playerTarget.Text = name and ("対象  " .. name) or "対象を選択してください"
	grantTarget.Text = name and ("付与先  " .. name) or "プレイヤー欄で付与先を選択してください"
end

local function targetAction(action, argument)
	if not targetId then
		feedback.Text = "入室中のプレイヤーを選択してください"
		return
	end
	request(action, targetId, argument)
end

local function list(page, order)
	local frame = make("Frame", page, {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = order,
	})
	stack(frame)
	return frame
end

local botCount = row("TextLabel", pages[1], 2, "", 24)
local playersList = list(pages[1], 3)
local reason = input(pages[1], 4, "キック・BANの理由（任意）")
actionButton(pages[1], 5, "キック", function() targetAction("Kick", reason.Text) end, BrandColors.Danger)
actionButton(pages[1], 6, "BAN", function() targetAction("Ban", reason.Text) end, BrandColors.Danger)
actionButton(pages[1], 7, "鬼にする（試合中）", function() targetAction("Tagger") end, BrandColors.Danger)
actionButton(pages[1], 8, "自分のところへ呼ぶ", function() targetAction("Bring") end)
actionButton(pages[1], 9, "選んだ人のところへ行く", function() targetAction("GoTo") end)
actionButton(pages[1], 10, "BAN一覧を取得", function() request("ListBans") end)
local bansList = list(pages[1], 11)
local moreBans = actionButton(pages[1], 12, "次のBAN一覧", function() request("NextBans") end)
moreBans.Visible = false
local unban = actionButton(pages[1], 13, "選択したBANを解除", function()
	if bannedId then
		request("Unban", bannedId)
	end
end)
unban.Visible = false

local announcement = input(pages[2], 1, "全員に表示するお知らせ")
announcement.MultiLine = true
announcement.Size = UDim2.new(1, -8, 0, 100)
actionButton(pages[2], 2, "全員に表示", function() request("Announce", announcement.Text) end, BrandColors.Accent)

actionButton(pages[3], 1, "ラウンドを今すぐ始める", function() request("StartRound") end, BrandColors.Accent)
actionButton(pages[3], 2, "ラウンドを今すぐ終わらせる", function() request("EndRound") end, BrandColors.Danger)
actionButton(pages[3], 3, "次のマップへ進める", function() request("NextMap") end)
local botsEnabled
local bots = actionButton(pages[3], 4, "ボット補充", function()
	if botsEnabled ~= nil then
		request("SetBots", not botsEnabled)
	end
end)

local itemIds = {}
for id in pairs(Config.Items) do
	table.insert(itemIds, id)
end
table.sort(itemIds)
local itemIndex = 0
local itemPicker
itemPicker = actionButton(pages[4], 2, "渡すアイテムを選ぶ", function()
	itemIndex = itemIndex % #itemIds + 1
	itemId = itemIds[itemIndex]
	itemPicker.Text = Config.Items[itemId].DisplayName .. "（タップで変更）"
end)
actionButton(pages[4], 3, "アイテムを1つ渡す", function()
	if itemId then
		targetAction("GrantItem", itemId)
	else
		feedback.Text = "アイテムを選択してください"
	end
end)
local rp = input(pages[4], 4, "追加するRP（整数）")
actionButton(pages[4], 5, "RPを加算", function() targetAction("AwardRP", tonumber(rp.Text)) end)
local info = row("TextLabel", pages[4], 6, "", 85)
local history = row("TextLabel", pages[4], 7, "", 0)
history.AutomaticSize = Enum.AutomaticSize.Y
history.TextXAlignment = Enum.TextXAlignment.Left

local function populateList(parent, entries, selected, click)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end
	for index, entry in ipairs(entries) do
		local button = actionButton(parent, index, entry.Text, function()
			click(entry)
			for _, sibling in ipairs(parent:GetChildren()) do
				if sibling:IsA("GuiButton") then
					setSelected(sibling, sibling.Name == tostring(entry.UserId))
				end
			end
		end)
		button.Name = tostring(entry.UserId)
		setSelected(button, entry.UserId == selected)
	end
end

local bans = {}
local function renderBans(hasNext)
	populateList(bansList, bans, bannedId, function(entry)
		bannedId = entry.UserId
		unban.Text = "BAN解除  #" .. tostring(bannedId)
		unban.Visible = true
	end)
	moreBans.Visible = hasNext
	unban.Visible = bannedId ~= nil
end

local phaseNames = { Waiting = "待機", Intermission = "開始前", Round = "試合中", Results = "結果" }
local lastPlayerList
remote.OnClientEvent:Connect(function(reply)
	requestPending = false
	if not gui.Enabled or not panel.Visible then
		return
	end
	if reply.Message then
		feedback.Text = reply.Message
	end
	if reply.Bans then
		table.clear(bans)
		bannedId = nil
		for _, userId in ipairs(reply.Bans.UserIds) do
			table.insert(bans, { UserId = userId, Text = "UserId  " .. tostring(userId) })
		end
		renderBans(reply.Bans.HasNext)
	elseif reply.Unbanned then
		for i, entry in ipairs(bans) do
			if entry.UserId == reply.Unbanned then
				table.remove(bans, i)
				break
			end
		end
		bannedId = nil
		renderBans(moreBans.Visible)
	end

	local status = reply.Status
	if not status then
		return
	end
	botCount.Text = string.format("参加中のボット %d体", status.Bots)
	botsEnabled = status.BotsEnabled
	bots.Text = botsEnabled and "ボット補充をオフにする" or "ボット補充をオンにする"
	info.Text = string.format("%s  /  %s\n参加 %d人（人間 %d・ボット %d）\n稼働 %d分%02d秒",
		status.Map, phaseNames[status.Phase] or status.Phase, status.Humans + status.Bots,
		status.Humans, status.Bots, math.floor(status.Uptime / 60), status.Uptime % 60)
	history.Text = #status.History > 0 and "操作履歴\n" .. table.concat(status.History, "\n")
		or "操作履歴はまだありません"

	local entries, signature = {}, {}
	local selectedPresent = false
	for _, entry in ipairs(status.Players) do
		selectedPresent = selectedPresent or entry.UserId == targetId
		entry.Text = string.format("%s  ·  %s  ·  %d RP  ·  %s", entry.Name, entry.Rank, entry.RP,
			entry.Participating and "参加中" or "待機・観戦")
		table.insert(entries, entry)
		table.insert(signature, tostring(entry.UserId) .. entry.Text)
	end
	if targetName and not selectedPresent then
		selectTarget(nil, nil)
	end
	local playerList = table.concat(signature, "\n")
	if playerList ~= lastPlayerList then
		lastPlayerList = playerList
		populateList(playersList, entries, targetId, function(entry)
			selectTarget(entry.UserId, entry.Name)
		end)
	end
end)

local function syncAdmin()
	gui.Enabled = player:GetAttribute("IsAdmin") == true
	open.Visible = gui.Enabled and not panel.Visible
	if not gui.Enabled then
		panel.Visible = false
		requestPending = false
	end
end

open.Activated:Connect(function()
	panel.Visible = true
	open.Visible = false
	feedback.Text = ""
	request("Status")
end)
close.Activated:Connect(function()
	panel.Visible = false
	open.Visible = gui.Enabled
end)
player:GetAttributeChangedSignal("IsAdmin"):Connect(syncAdmin)
syncAdmin()

task.spawn(function()
	while true do
		task.wait(4)
		if gui.Enabled and panel.Visible then
			request("Status")
		end
	end
end)
