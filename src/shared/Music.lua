-- Music: BGM を鳴らす（クライアント専用）
-- Music.Play("Lobby" / "Match" / "Final") で曲を切り替える。同じ曲なら何もしない。

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent:WaitForChild("Config"))

local Music = {}

local current = nil      -- 今鳴っている Sound
local currentKey = nil

local function fade(sound, volume, seconds)
	local tween = TweenService:Create(sound, TweenInfo.new(seconds), { Volume = volume })
	tween:Play()
	return tween
end

function Music.Play(key)
	if key == currentKey then
		return
	end
	currentKey = key
	local old = current
	if old then
		fade(old, 0, 1).Completed:Connect(function()
			old:Destroy()
		end)
	end
	local soundId = Config.Music[key]
	if not soundId or soundId == "" then
		current = nil
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "BGM_" .. key
	sound.SoundId = soundId
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	sound:Play()
	fade(sound, Config.Music.Volume, 1.5)
	current = sound
end

function Music.Stop()
	Music.Play(nil)
end

return Music
