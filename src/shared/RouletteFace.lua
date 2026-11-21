local Config = require(script.Parent.Config)
local RouletteVisual = require(script.Parent.RouletteVisual)

local RouletteFace = {}
local colors = Config.BrandColors

local function circle(parent, name, diameter, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(diameter, diameter)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = color
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	return frame
end

local function facePosition(angle, radius)
	return UDim2.fromScale(0.5 + math.sin(angle) * radius, 0.5 - math.cos(angle) * radius)
end

function RouletteFace.Create(parent)
	local rim = circle(parent, "Rim", 0.96, colors.Accent)
	local wheel = circle(rim, "Wheel", 0.965, colors.Surface)
	local hub = circle(wheel, "Hub", 0.14, colors.Accent)
	hub.ZIndex = 3
	circle(hub, "Cap", 0.65, colors.Primary).ZIndex = 4

	local sectors = {}
	local count = #Config.Roulette.Prizes
	local sweep = 360 / count
	local stripsPerSector = 24
	for index, prize in ipairs(Config.Roulette.Prizes) do
		local color = index % 2 == 1 and colors.Primary or colors.Secondary
		if prize.Coins == 500 then
			color = colors.Danger
		end
		local center = RouletteVisual.SectorAngle(index, count)
		local sector = { Color = color, Strips = {} }
		sectors[index] = sector
		-- 細い放射状の帯を並べ、外周を円弧に沿わせる。
		for stripIndex = 1, stripsPerSector do
			local angle = center + sweep * ((stripIndex - 0.5) / stripsPerSector - 0.5) * 0.975
			local strip = Instance.new("Frame")
			strip.AnchorPoint = Vector2.new(0.5, 0.5)
			strip.Position = facePosition(math.rad(angle), 0.25)
			strip.Size = UDim2.fromScale(math.rad(sweep / stripsPerSector) * 0.54, 0.498)
			strip.Rotation = angle
			strip.BorderSizePixel = 0
			strip.BackgroundColor3 = color
			strip.Parent = wheel
			sector.Strips[stripIndex] = strip
		end

		local amount = Instance.new("TextLabel")
		amount.AnchorPoint = Vector2.new(0.5, 0.5)
		amount.Position = facePosition(math.rad(center), 0.32)
		amount.Size = UDim2.fromScale(0.26, 0.135)
		amount.BackgroundTransparency = 1
		amount.TextColor3 = colors.White
		amount.TextStrokeColor3 = colors.Surface
		amount.TextStrokeTransparency = 0.35
		amount.TextScaled = true
		amount.Font = Enum.Font.GothamBlack
		amount.Text = tostring(prize.Coins)
		amount.ZIndex = 4
		amount.Parent = wheel
		sector.Amount = amount
	end

	local face = {}
	function face.SetAngle(angle)
		wheel.Rotation = angle % 360
		for _, sector in ipairs(sectors) do
			sector.Amount.Rotation = -wheel.Rotation
		end
	end

	function face.Highlight(winner)
		for index, sector in ipairs(sectors) do
			local color = sector.Color
			if index == winner then
				color = color:Lerp(colors.Accent, 0.55)
			end
			for _, strip in ipairs(sector.Strips) do
				strip.BackgroundColor3 = color
			end
			sector.Amount.TextColor3 = index == winner and colors.Accent or colors.White
		end
	end
	return face
end

return RouletteFace
