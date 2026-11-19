-- Remotes: サーバーとクライアントの通信に使う RemoteEvent を作る
-- ReplicatedStorage.Remotes フォルダに作成し、クライアントは WaitForChild で待つ。
--
--   StateUpdate  (サーバー → 全員)  ラウンドの状態（フェーズ、残り時間、鬼など）
--   ItemUpdate   (サーバー → 本人)  持っているアイテムのリスト、枠数、ダッシュ/シールドの残り時間
--   UseItem      (クライアント → サーバー) 「何枠目を使いたい」というお願い。判定はサーバー
--   SmokeEffect  (サーバー → 鬼)    スモークの画面効果を出す
--   Notify       (サーバー → 本人)  画面に短いメッセージを出す
--   PassUpdate   (サーバー → 本人)  Game Pass の所有状態（ショップの「所有済み」表示用）
--                (クライアント → サーバー) 引数なし。「今の所有状態を送って」というお願い

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENT_NAMES = { "StateUpdate", "ItemUpdate", "UseItem", "SmokeEffect", "Notify", "PassUpdate" }

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
end

local Remotes = {}

for _, name in ipairs(EVENT_NAMES) do
	local event = folder:FindFirstChild(name)
	if not event then
		event = Instance.new("RemoteEvent")
		event.Name = name
		event.Parent = folder
	end
	Remotes[name] = event
end

folder.Parent = ReplicatedStorage

-- 本人の画面にメッセージを出す
function Remotes.NotifyPlayer(player, text)
	if player and player.Parent then
		Remotes.Notify:FireClient(player, text)
	end
end

return Remotes
