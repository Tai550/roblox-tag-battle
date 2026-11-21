-- Main: 試合サーバーの起動スクリプト（ServerScriptService.Server.Main）
-- 各モジュールを初期化して、試合のループを開始する。

local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local MatchSession = require(script.Parent:WaitForChild("MatchSession"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))
local AdminManager = require(script.Parent:WaitForChild("AdminManager"))

-- マップと Workspace.ItemSpawns を、どの Init よりも先に用意する（アリーナ・渋谷・パークのどれか）
MapBuilder.Init()

AdminManager.Init() -- 入室時の BAN 確認と管理者画面の受付
Leaderstats.Init()
RankManager.Init()   -- 段位の読み込み（leaderstats を作ったあと）
MatchSession.Init()  -- すぐ遊ぶ／友達部屋／ひとり／Studio の判定とロビーへの移動
DeckManager.Init()   -- 保存データ（デッキ）の読み込み
ItemManager.Init()
RoundManager.Init()
Monetization.Init()  -- 課金（Game Pass の所有確認・トレイル）

-- ずっと回り続けるループなので最後に呼ぶ
RoundManager.Run()
