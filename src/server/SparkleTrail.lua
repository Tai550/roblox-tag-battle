-- SparkleTrail: キラキラトレイル（Game Pass）の見た目を付け外しする（サーバー側）
-- 見た目だけの効果。速度・当たり判定・タッチ判定には一切関わらない。
-- サーバーで作るので、ほかのプレイヤーにも軌跡が見える。
--
-- 構成: HumanoidRootPart の中に Attachment を上下に2つ付け、Trail でつなぐ。
-- キャラクターが再出現すると部品ごと消えるので、CharacterAdded のたびに付け直す。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SparkleTrail = {}

local TRAIL_NAME = "SparkleTrail"
local ATTACH_TOP_NAME = "SparkleTrailTop"
local ATTACH_BOTTOM_NAME = "SparkleTrailBottom"

local function getRootPart(character, timeout)
	if not character then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", timeout or 10)
end

-- 指定のキャラクターにトレイルを付ける（すでに付いていれば何もしない）
function SparkleTrail.Attach(character)
	local root = getRootPart(character)
	if not root or root:FindFirstChild(TRAIL_NAME) then
		return
	end
	local settings = Config.Monetization.SparkleTrail
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

-- 指定のキャラクターからトレイルを外す
function SparkleTrail.Detach(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	for _, name in ipairs({ TRAIL_NAME, ATTACH_TOP_NAME, ATTACH_BOTTOM_NAME }) do
		local child = root:FindFirstChild(name)
		if child then
			child:Destroy()
		end
	end
end

return SparkleTrail
