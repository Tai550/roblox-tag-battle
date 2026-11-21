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
--   DeckSelect   (クライアント → サーバー) 選んだデッキ（アイテム Id のリスト）。検証はサーバー
--   DeckUpdate   (サーバー → 本人)  今の自分のデッキ
--   ZoneUpdate   (サーバー → 本人)  縮小エリアの半径と、自分のエリア外スタミナ・内外判定
--   RankUp       (サーバー → 本人)  段位が上がった瞬間だけ。引数は新しい段位名

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EVENT_NAMES = {
	"StateUpdate", "ItemUpdate", "UseItem", "SmokeEffect", "Notify", "PassUpdate",
	"DurationVote", "DeckSelect", "DeckUpdate", "ZoneUpdate", "RankUp", "AdminRequest",
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

-- 本人の画面にメッセージを出す。ボットに FireClient は飛ばさない。
function Remotes.NotifyPlayer(player, text)
	if player == nil or (type(player) == "table" and player.IsBot == true) then
		return
	end
	if player.Parent then
		Remotes.Notify:FireClient(player, text)
	end
end

return Remotes
