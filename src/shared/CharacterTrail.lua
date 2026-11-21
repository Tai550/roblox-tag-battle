-- サーバーで軌跡を付け替え、ほかのプレイヤーにも表示する。
local Config = require(script.Parent:WaitForChild("Config"))
local CharacterTrail = {}

local TRAIL_NAME = "SparkleTrail"
local ATTACH_TOP_NAME = "SparkleTrailTop"
local ATTACH_BOTTOM_NAME = "SparkleTrailBottom"

function CharacterTrail.Resolve(data, ownsSparkle)
	local id = data.EquippedTrail
	if id and data.Trails[id] then
		return Config.Trails[id]
	end
	if ownsSparkle and (id == nil or id == "Sparkle") then
		return Config.Monetization.SparkleTrail
	end
	return nil
end

function CharacterTrail.Apply(character, resolveStyle)
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10)
	if not root or not character.Parent then
		return
	end
	-- RootPart の待機中に装備が変わることがあるので、ここで最新の状態を読む。
	local settings = resolveStyle()
	for _, name in ipairs({ TRAIL_NAME, ATTACH_TOP_NAME, ATTACH_BOTTOM_NAME }) do
		local child = root:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
	if not settings then
		return
	end

	local height = settings.AttachmentHeight

	local top = Instance.new("Attachment")
	top.Name = ATTACH_TOP_NAME
	top.Position = Vector3.new(0, height, 0)
	top.Parent = root

	local bottom = Instance.new("Attachment")
	bottom.Name = ATTACH_BOTTOM_NAME
	bottom.Position = Vector3.new(0, -height, 0)
	bottom.Parent = root

	local trail = Instance.new("Trail")
	trail.Name = TRAIL_NAME
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Lifetime = settings.Lifetime
	trail.MinLength = 0.1            -- 止まっているときは軌跡が伸びない
	trail.FaceCamera = true
	trail.LightEmission = settings.LightEmission
	trail.Color = ColorSequence.new(settings.ColorStart, settings.ColorEnd)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, settings.TransparencyStart),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	trail.Enabled = true
	trail.Parent = root
end

return CharacterTrail
