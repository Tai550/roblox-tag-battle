-- 試合中の保存データとパス所持状態からトレイルを反映する。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CharacterTrail = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CharacterTrail"))
local PlayerDataStore = require(script.Parent:WaitForChild("PlayerDataStore"))
local GameState = require(script.Parent:WaitForChild("GameState"))

local SparkleTrail = {}

function SparkleTrail.Refresh(player, character)
	if character then
		CharacterTrail.Apply(character, function()
			if player.Parent == Players and player.Character == character then
				return CharacterTrail.Resolve(PlayerDataStore.Get(player), GameState.OwnsPass(player, "SparkleTrail"))
			end
		end)
	end
end

return SparkleTrail
