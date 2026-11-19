-- Main: サーバーの起動スクリプト（ServerScriptService.Server.Main）
-- 各モジュールを初期化して、ラウンドのループを開始する。

local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))

Leaderstats.Init()
ItemManager.Init()
RoundManager.Init()
Monetization.Init()  -- 課金（レシート処理・Game Pass の所有確認・トレイル）

-- ずっと回り続けるループなので最後に呼ぶ
RoundManager.Run()
