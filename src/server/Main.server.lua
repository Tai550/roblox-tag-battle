-- Main: 試合サーバーの起動スクリプト（ServerScriptService.Server.Main）
-- 各モジュールを初期化して、試合のループを開始する。

local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local MatchSession = require(script.Parent:WaitForChild("MatchSession"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))

Leaderstats.Init()
MatchSession.Init()  -- すぐ遊ぶ／友達部屋／Studio の判定とロビーへの移動
DeckManager.Init()   -- 保存データ（デッキ）の読み込み
ItemManager.Init()
RoundManager.Init()
Monetization.Init()  -- 課金（Game Pass の所有確認・トレイル）

-- ずっと回り続けるループなので最後に呼ぶ
RoundManager.Run()
