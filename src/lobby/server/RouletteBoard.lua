local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local RouletteFace = require(Shared.RouletteFace)
local RouletteVisual = require(Shared.RouletteVisual)

local RouletteBoard = {}
local colors = Config.BrandColors

local function part(parent, name, size, cframe, color)
	local piece = Instance.new("Part")
	piece.Name = name
	piece.Size = size
	piece.CFrame = cframe
	piece.Color = color
	piece.Anchored = true
	piece.CanCollide = false
	piece.CanTouch = false
	piece.Parent = parent
	return piece
end

local function surface(adornee)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Parent = adornee
	return gui
end

function RouletteBoard.Create(spawn)
	local model = Instance.new("Model")
	model.Name = "RouletteBoard"
	local position = Vector3.new(spawn.Position.X - 14, 8, spawn.Position.Z - 27)
	local center = CFrame.lookAt(position, Vector3.new(spawn.Position.X, position.Y, spawn.Position.Z))

	local base = part(model, "Base", Vector3.new(9, 1, 4.5), center * CFrame.new(0, -7.5, 0), colors.Surface)
	base.CanCollide = true
	part(model, "Pedestal", Vector3.new(6, 6, 2.6), center * CFrame.new(0, -4.5, 0.25), colors.Surface)

	local rotor = Instance.new("Model")
	rotor.Name = "Rotor"
	rotor.Parent = model
	local drum = part(rotor, "Drum", Vector3.new(1.25, 13, 13),
		center * CFrame.Angles(0, math.pi / 2, 0), colors.Primary)
	drum.Shape = Enum.PartType.Cylinder
	rotor.WorldPivot = center
	for index = 0, 11 do
		local angle = index * math.pi / 6
		local bolt = part(rotor, "RimBolt", Vector3.new(0.3, 0.3, 0.3),
			center * CFrame.new(math.sin(angle) * 6.15, math.cos(angle) * 6.15, -0.64),
			index % 3 == 0 and colors.Accent or colors.Secondary)
		bolt.Shape = Enum.PartType.Ball
	end

	local facePart = part(model, "Face", Vector3.new(12.4, 12.4, 0.05),
		center * CFrame.new(0, 0, -0.66), colors.Primary)
	facePart.Transparency = 1
	facePart.CanQuery = false
	local faceGui = surface(facePart)
	faceGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	faceGui.CanvasSize = Vector2.new(768, 768)
	local face = RouletteFace.Create(faceGui)

	local pointerPart = part(model, "Pointer", Vector3.new(1.8, 1.65, 0.06),
		center * CFrame.new(0, 6.1, -0.88), colors.Surface)
	pointerPart.Transparency = 1
	pointerPart.CanQuery = false
	local pointer = Instance.new("TextLabel")
	pointer.Size = UDim2.fromScale(1, 1)
	pointer.BackgroundTransparency = 1
	pointer.Text = "▼"
	pointer.TextScaled = true
	pointer.Font = Enum.Font.GothamBlack
	pointer.TextColor3 = colors.Accent
	pointer.TextStrokeColor3 = colors.Surface
	pointer.TextStrokeTransparency = 0
	pointer.Parent = surface(pointerPart)

	local lights = {}
	for index = 1, 28 do
		local angle = index * 2 * math.pi / 28
		local light = part(model, "MarqueeLight", Vector3.new(0.39, 0.39, 0.39),
			center * CFrame.new(math.sin(angle) * 6.8, math.cos(angle) * 6.8, -0.45), colors.Secondary)
		light.Shape = Enum.PartType.Ball
		lights[index] = light
	end

	local sign = part(model, "ResultSign", Vector3.new(8.4, 1.5, 0.35),
		center * CFrame.new(0, -6.95, -1.65), colors.Surface)
	local signGui = surface(sign)
	local result = Instance.new("TextLabel")
	result.Size = UDim2.fromScale(1, 1)
	result.BackgroundColor3 = colors.Surface
	result.BorderSizePixel = 0
	result.TextScaled = true
	result.Font = Enum.Font.GothamBlack
	result.TextColor3 = colors.Accent
	result.Text = "デイリールーレット"
	result.Parent = signGui

	local playerLabel = Instance.new("TextLabel")
	playerLabel.Size = UDim2.fromScale(1, 0.3)
	playerLabel.BackgroundTransparency = 1
	playerLabel.TextColor3 = colors.White
	playerLabel.TextScaled = true
	playerLabel.Font = Enum.Font.GothamBold
	playerLabel.Visible = false
	playerLabel.Parent = signGui

	local function showResult(text, playerName)
		playerLabel.Text = playerName or ""
		playerLabel.Visible = playerName ~= nil
		local headerHeight = playerName and 0.3 or 0
		result.Position = UDim2.fromScale(0, headerHeight)
		result.Size = UDim2.fromScale(1, 1 - headerHeight)
		result.Text = text
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RoulettePrompt"
	prompt.ActionText = "ルーレットをまわす"
	prompt.ObjectText = "デイリールーレット"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = sign
	model.Parent = workspace

	local angle = 0
	local spin
	local resultUntil = 0
	local lastLightPhase
	local board = {}
	local function setAngle(value)
		angle = value % 360
		face.SetAngle(angle)
		rotor:PivotTo(center * CFrame.Angles(0, 0, math.rad(angle)))
	end

	function board.Start(playerName, prizeIndex, revealAt, duration)
		face.Highlight(nil)
		showResult("回転中…", playerName)
		spin = {
			Start = angle,
			Target = RouletteVisual.TargetRotation(angle, prizeIndex, #Config.Roulette.Prizes),
			RevealAt = revealAt,
			Duration = duration,
		}
	end

	function board.Reveal(prizeIndex, coins, playerName)
		setAngle(spin.Target)
		spin = nil
		face.Highlight(prizeIndex)
		showResult(string.format("+%d コイン", coins), playerName)
		resultUntil = workspace:GetServerTimeNow() + 4
	end

	RunService.Heartbeat:Connect(function()
		local now = workspace:GetServerTimeNow()
		if spin then
			local progress = 1 - (spin.RevealAt - now) / spin.Duration
			setAngle(RouletteVisual.SpinAngle(spin.Start, spin.Target, progress))
		elseif resultUntil > 0 and now >= resultUntil then
			resultUntil = 0
			showResult("デイリールーレット")
			face.Highlight(nil)
		end

		local phase = spin and math.floor(now * 13) % 2
			or (now < resultUntil and 2 or math.floor(now * 2) % 2)
		if phase ~= lastLightPhase then
			lastLightPhase = phase
			for index, light in ipairs(lights) do
				local lit = phase == 2 or index % 2 == phase
				light.Color = lit and colors.Accent or colors.Primary
				light.Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic
			end
		end
	end)
	return board
end

return RouletteBoard
