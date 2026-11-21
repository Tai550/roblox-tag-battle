#!/usr/bin/env python3
"""テスト用に src の各モジュールを tests/.build/ へ複写し、
先頭へ mockenv から Roblox API を取り込む前置きを付ける。

使い方:
    python3 tests/build_tests.py
    luau tests/run_tests.lua   （luau CLI が必要）
"""

import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "tests", ".build")

MODULES = [
    ("src/shared/Config.lua", "Config"),
    ("src/shared/Music.lua", "Music"),
    ("src/shared/UILayout.lua", "UILayout"),
    ("src/server/GameState.lua", "GameState"),
    ("src/server/Remotes.lua", "Remotes"),
    ("src/server/Leaderstats.lua", "Leaderstats"),
    ("src/server/RankManager.lua", "RankManager"),
    ("src/serverlib/PlayerDataStore.lua", "PlayerDataStore"),
    ("src/server/DeckManager.lua", "DeckManager"),
    ("src/server/ZoneManager.lua", "ZoneManager"),
    ("src/server/ItemManager.lua", "ItemManager"),
    ("src/server/MapBuilder.lua", "MapBuilder"),
    ("src/server/TaggerLook.lua", "TaggerLook"),
    ("src/server/BotManager.lua", "BotManager"),
    ("src/server/RoundManager.lua", "RoundManager"),
    ("src/server/AdminManager.lua", "AdminManager"),
]

CLIENTS = {
    **{name: f"src/client/{name}.client.lua"
       for name in ("HUD", "ItemControls", "MatchUI", "Shop", "AdminUI")},
    "LobbyUI": "src/lobby/client/LobbyUI.client.lua",
}
BRAND_UI = (*CLIENTS.values(), "src/client/MatchHUD.client.lua")

PRELUDE = """-- [test] Roblox API mock prelude
local __RT = require("./mockenv")
local game = __RT.game
local workspace = __RT.workspace
local script = __RT.scriptFor("{name}")
local require = __RT.fakeRequire
local Instance = __RT.Instance
local Enum = __RT.Enum
local Color3 = __RT.Color3
local Vector2 = __RT.Vector2
local Vector3 = __RT.Vector3
local CFrame = __RT.CFrame
local UDim = __RT.UDim
local UDim2 = __RT.UDim2
local PhysicalProperties = __RT.PhysicalProperties
local OverlapParams = __RT.OverlapParams
local RaycastParams = __RT.RaycastParams
local task = __RT.task
local warn = __RT.warn
-- [original file below]
"""


def main():
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    os.makedirs(BUILD)
    shutil.copy(os.path.join(ROOT, "tests", "mockenv.lua"), os.path.join(BUILD, "mockenv.lua"))
    for rel_path, name in MODULES:
        with open(os.path.join(ROOT, rel_path), encoding="utf-8") as f:
            source = f.read()
        with open(os.path.join(BUILD, name + ".lua"), "w", encoding="utf-8") as f:
            f.write(PRELUDE.format(name=name))
            f.write(source)
        print("built", name)
    for rel_path in BRAND_UI:
        with open(os.path.join(ROOT, rel_path), encoding="utf-8") as f:
            source = f.read()
        if "Config.BrandColors" not in source or "Color3.fromRGB" in source or "Color3.new" in source:
            raise AssertionError(f"{rel_path} must use the shared brand palette for UI colors")
    for name, rel_path in CLIENTS.items():
        with open(os.path.join(ROOT, rel_path), encoding="utf-8") as f:
            source = f.read()
        with open(os.path.join(BUILD, name + ".lua"), "w", encoding="utf-8") as f:
            f.write(PRELUDE.format(name=name))
            f.write("return function()\n")
            f.write(source)
            f.write("\nend\n")
        print("built", name)
    print("done ->", BUILD)


if __name__ == "__main__":
    main()
