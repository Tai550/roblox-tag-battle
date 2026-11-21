-- Main: サーバーの起動スクリプト（ServerScriptService.Server.Main）
-- 各モジュールを初期化して、ラウンドのループを開始する。

local Leaderstats = require(script.Parent:WaitForChild("Leaderstats"))
local RankManager = require(script.Parent:WaitForChild("RankManager"))
local ItemManager = require(script.Parent:WaitForChild("ItemManager"))
local RoundManager = require(script.Parent:WaitForChild("RoundManager"))
local Monetization = require(script.Parent:WaitForChild("Monetization"))
local DeckManager = require(script.Parent:WaitForChild("DeckManager"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local AdminManager = require(script.Parent:WaitForChild("AdminManager"))

-- マップと Workspace.ItemSpawns を、どの Init よりも先に（試合開始より前に）用意する。
-- ItemManager / ZoneManager は試合開始時に ItemSpawns を読むので、ここで作ればそのまま連動する。
-- 起動直後は渋谷。ラウンド開始時の入れ替えは RoundManager が行う。
MapBuilder.Build()

AdminManager.Init() -- 入室時の BAN 確認と管理 Remote
Leaderstats.Init()
RankManager.Init()   -- 段位の読み込み（leaderstats を作ったあと。保存はここで繋ぐ）
ItemManager.Init()
DeckManager.Init()   -- デッキ構築（DeckSelect の受付）
RoundManager.Init()
Monetization.Init()  -- 課金（レシート処理・Game Pass の所有確認・トレイル）

-- ずっと回り続けるループなので最後に呼ぶ
RoundManager.Run()
