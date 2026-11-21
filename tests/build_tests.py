#!/usr/bin/env python3
"""テスト用に src の各モジュールを tests/.build/ へ複写し、
先頭へ mockenv から Roblox API を取り込む前置きを付ける。

使い方:
    python3 tests/build_tests.py
    luau tests/run_tests.lua   （luau CLI が必要）
"""

import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "tests", ".build")

MODULES = [
    ("src/shared/Config.lua", "Config"),
    ("src/shared/UILayout.lua", "UILayout"),
    ("src/shared/LobbyMenu.lua", "LobbyMenu"),
    ("src/shared/CharacterTrail.lua", "CharacterTrail"),
    ("src/shared/BeastModels.lua", "BeastModels"),
    ("src/lobby/server/BeastFollower.lua", "BeastFollower"),
    ("src/shared/RouletteVisual.lua", "RouletteVisual"),
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
    ("src/server/VoltGimmicks.lua", "VoltGimmicks"),
    ("src/server/TaggerSkills.lua", "TaggerSkills"),
    ("src/server/TaggerLook.lua", "TaggerLook"),
    ("src/server/BotManager.lua", "BotManager"),
    ("src/server/RoundManager.lua", "RoundManager"),
    ("src/serverlib/AdminService.lua", "AdminService"),
    ("src/server/AdminManager.lua", "AdminManager"),
    ("src/lobby/server/LobbyAdmin.lua", "LobbyAdmin"),
    ("src/lobby/server/LobbyTrade.lua", "LobbyTrade"),
]

CLIENTS = ("Slide",)

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
local RaycastParams = __RT.RaycastParams
local UDim = __RT.UDim
local UDim2 = __RT.UDim2
local PhysicalProperties = __RT.PhysicalProperties
local OverlapParams = __RT.OverlapParams
local RaycastParams = __RT.RaycastParams
local task = __RT.task
local warn = __RT.warn
-- [original file below]
"""


def check_arena_assets():
    # The Arena is loaded from Rojo JSON, so check the actual committed geometry.
    def read_children(filename):
        with open(os.path.join(ROOT, "src", "workspace", filename), encoding="utf-8") as f:
            return json.load(f)["children"]

    def inside(part):
        props = part["properties"]
        x, _, z = props["Position"]["Vector3"]
        width, _, depth = props["Size"]["Vector3"]
        return abs(x) + width / 2 <= 90 and abs(z) + depth / 2 <= 90

    parts = read_children("Map.model.json")
    floor = next(part for part in parts if part["name"] == "Floor")
    assert floor["properties"]["Size"]["Vector3"] == [180, 2, 180], "Arena floor dimensions"
    spawns = [part for part in parts if part["className"] == "SpawnLocation"]
    assert len(spawns) == 1 and inside(spawns[0]), "Arena player spawn"
    items = read_children("ItemSpawns.model.json")
    assert len(items) == 14 and all(map(inside, items)), "Arena item spawn bounds"
    print("checked Arena floor, player spawn and item spawns")
    return [floor, *spawns], items


def write_arena_fixture(parts, items):
    with open(os.path.join(BUILD, "ArenaFixture.lua"), "w", encoding="utf-8") as f:
        f.write("return {\n")
        for group, children in (("Map", parts), ("ItemSpawns", items)):
            f.write(f"\t{group} = {{\n")
            for part in children:
                props = part["properties"]
                name, cls = json.dumps(part["name"]), json.dumps(part["className"])
                position = ", ".join(map(str, props["Position"]["Vector3"]))
                size = ", ".join(map(str, props["Size"]["Vector3"]))
                f.write(f"\t\t{{ {name}, {cls}, {{ {position} }}, {{ {size} }} }},\n")
            f.write("\t},\n")
        f.write("}\n")


def main():
    arena_parts, arena_items = check_arena_assets()
    if os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    os.makedirs(BUILD)
    write_arena_fixture(arena_parts, arena_items)
    shutil.copy(os.path.join(ROOT, "tests", "mockenv.lua"), os.path.join(BUILD, "mockenv.lua"))
    # Run the lobby queue tick with a mock clock, without booting the lobby or its polling loop.
    with open(os.path.join(ROOT, "src/lobby/server/Main.server.lua"), encoding="utf-8") as f:
        lobby = f.read()
    queue_start = lobby.index("local queue = {}")
    queue_end = lobby.index("task.spawn(function()\n\twhile true do\n\t\tqueueTick()", queue_start)
    with open(os.path.join(BUILD, "LobbyQueue.lua"), "w", encoding="utf-8") as f:
        f.write('local Vector3 = require("./mockenv").Vector3\n')
        f.write("return function(Config, Players, loaded, quickPad, padText, QueueUpdate, os)\n")
        f.write(lobby[queue_start:queue_end])
        f.write("return queueTick, function() return departAt end\nend\n")
    for rel_path, name in MODULES:
        with open(os.path.join(ROOT, rel_path), encoding="utf-8") as f:
            source = f.read()
        with open(os.path.join(BUILD, name + ".lua"), "w", encoding="utf-8") as f:
            f.write(PRELUDE.format(name=name))
            f.write(source)
        print("built", name)
    for name in CLIENTS:
        with open(os.path.join(ROOT, "src", "client", name + ".client.lua"), encoding="utf-8") as f:
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
