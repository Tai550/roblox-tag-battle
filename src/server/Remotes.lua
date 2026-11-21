-- Remotes: サーバーとクライアントの通信に使う RemoteEvent を作る
-- ReplicatedStorage.Remotes フォルダに作成し、クライアントは WaitForChild で待つ。
--
--   StateUpdate  (サーバー → 全員)  ラウンドの状態（フェーズ、残り時間、鬼など）
--   ItemUpdate   (サーバー → 本人)  持っているアイテムのリスト、枠数、効果時間（スパイクブーツは Workspace のサーバー時刻での終了時刻）
--   UseItem      (クライアント → サーバー) 「何枠目を使いたい」というお願い。判定はサーバー
--   SmokeEffect  (サーバー → 鬼)    スモークの画面効果を出す
--   Notify       (サーバー → 本人)  画面に短いメッセージを出す
--   PassUpdate   (サーバー → 本人)  Game Pass の所有状態（ショップの「所有済み」表示用）
--                (クライアント → サーバー) 引数なし。「今の所有状態を送って」というお願い
--   DurationVote (クライアント → サーバー) 試合時間への投票（引数は秒数）。集計はサーバー
--   ZoneUpdate   (サーバー → 本人)  縮小エリアの半径、エリア外スタミナ、送還の回数
--   RadarEffect  (サーバー → 本人)  レーダー：光らせる相手の UserId リストと秒数
--   HostStart    (クライアント → サーバー) 友達部屋のホストが「開始」を押した
--   LeaveToLobby (クライアント → サーバー) 「ロビーへ戻る」を押した
--   MapVote      (クライアント → サーバー) 開始前のマップ投票（引数はマップ Id）
--   AdminRequest (クライアント ⇔ サーバー) 管理者画面の操作（権限はサーバーが毎回確認）
--   RankUp       (サーバー → 本人)  段位が上がった瞬間だけ。引数は新しい段位名

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENT_NAMES = {
	"StateUpdate", "ItemUpdate", "UseItem", "SmokeEffect", "Notify", "PassUpdate",
	"DurationVote", "MapVote", "ZoneUpdate", "RadarEffect", "HostStart", "LeaveToLobby", "RankUp", "AdminRequest",
}

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
-- 本物のプレイヤーか（ひとりモードのボットは表なので false）
function Remotes.IsRealPlayer(player)
	if player == nil or (type(player) == "table" and player.IsBot == true) then
		return false
	end
	return player.Parent ~= nil
end

function Remotes.NotifyPlayer(player, text)
	if Remotes.IsRealPlayer(player) then
		Remotes.Notify:FireClient(player, text)
	end
end

return Remotes
