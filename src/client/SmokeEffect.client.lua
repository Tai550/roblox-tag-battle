-- SmokeEffect: スモークを受けたとき（自分が鬼のとき）に画面を真っ白にする
-- サーバーから SmokeEffect が届いたときだけ表示する。誰に届けるかはサーバーが決める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SmokeEvent = Remotes:WaitForChild("SmokeEffect")

local localPlayer = Players.LocalPlayer

local MAX_DURATION = 10 -- 想定外の値が来ても長く固まらないようにする上限

local gui = Instance.new("ScreenGui")
gui.Name = "SmokeOverlay"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 100 -- HUD より手前に出して、画面全体を隠す

local overlay = Instance.new("Frame")
overlay.Name = "White"
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = Color3.new(1, 1, 1)
overlay.BackgroundTransparency = 1
overlay.BorderSizePixel = 0
overlay.Visible = false
overlay.Parent = gui

local caption = Instance.new("TextLabel")
caption.Size = UDim2.new(1, 0, 0, 40)
caption.Position = UDim2.new(0, 0, 0.5, -20)
caption.BackgroundTransparency = 1
caption.Font = Enum.Font.GothamBold
caption.TextSize = 28
caption.TextColor3 = Color3.fromRGB(190, 190, 190)
caption.TextTransparency = 1
caption.Text = "スモークで前が見えない！"
caption.Parent = overlay

gui.Parent = localPlayer:WaitForChild("PlayerGui")

local smokeToken = 0
local currentTweens = {}

local function cancelTweens()
	for _, tween in ipairs(currentTweens) do
		tween:Cancel()
	end
	currentTweens = {}
end

local function showSmoke(duration, fadeOutTime)
	duration = math.clamp(tonumber(duration) or Config.Items.Smoke.Duration, 0, MAX_DURATION)
	fadeOutTime = math.clamp(tonumber(fadeOutTime) or Config.Items.Smoke.FadeOutTime, 0, 3)

	smokeToken = smokeToken + 1
	local myToken = smokeToken

	cancelTweens()
	overlay.Visible = true
	overlay.BackgroundTransparency = 0
	caption.TextTransparency = 0

	task.delay(duration, function()
		if smokeToken ~= myToken then
			return -- 途中で次のスモークが来たら、そちらに任せる
		end
		local info = TweenInfo.new(fadeOutTime)
		local fadeFrame = TweenService:Create(overlay, info, { BackgroundTransparency = 1 })
		local fadeText = TweenService:Create(caption, info, { TextTransparency = 1 })
		currentTweens = { fadeFrame, fadeText }
		fadeFrame:Play()
		fadeText:Play()
		fadeFrame.Completed:Connect(function(playbackState)
			if smokeToken == myToken and playbackState == Enum.PlaybackState.Completed then
				overlay.Visible = false
			end
		end)
	end)
end

SmokeEvent.OnClientEvent:Connect(showSmoke)
