-- Main: サーバーの起動スクリプト（ServerScriptService.Server.Main）
-- 各モジュールを初期化して、ラウンドのループを開始する。

local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))

-- マップと Workspace.ItemSpawns を、どの Init よりも先に（試合開始より前に）用意する。
-- ItemManager / ZoneManager は試合開始時に ItemSpawns を読むので、ここで作ればそのまま連動する。
MapBuilder.Build()

Leaderstats.Init()
ItemManager.Init()
DeckManager.Init()   -- デッキ構築（DeckSelect の受付）
RoundManager.Init()
Monetization.Init()  -- 課金（レシート処理・Game Pass の所有確認・トレイル）

-- ずっと回り続けるループなので最後に呼ぶ
RoundManager.Run()
