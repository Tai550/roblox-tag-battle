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
    ("src/server/GameState.lua", "GameState"),
    ("src/server/Remotes.lua", "Remotes"),
    ("src/server/Leaderstats.lua", "Leaderstats"),
    ("src/serverlib/PlayerDataStore.lua", "PlayerDataStore"),
    ("src/server/MatchSession.lua", "MatchSession"),
    ("src/server/RankManager.lua", "RankManager"),
    ("src/server/DeckManager.lua", "DeckManager"),
    ("src/server/ZoneManager.lua", "ZoneManager"),
    ("src/server/ItemManager.lua", "ItemManager"),
    ("src/server/MapBuilder.lua", "MapBuilder"),
    ("src/server/TaggerLook.lua", "TaggerLook"),
    ("src/server/BotManager.lua", "BotManager"),
    ("src/server/RoundManager.lua", "RoundManager"),
]

PRELUDE = """-- [test] Roblox API mock prelude
local __RT = require("./mockenv")
local game = __RT.game
local workspace = __RT.workspace
local script = __RT.scriptFor("{name}")
local require = __RT.fakeRequire
local Instance = __RT.Instance
local Enum = __RT.Enum
local Color3 = __RT.Color3
local Vector3 = __RT.Vector3
local CFrame = __RT.CFrame
local RaycastParams = __RT.RaycastParams
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
    print("done ->", BUILD)


if __name__ == "__main__":
    main()
