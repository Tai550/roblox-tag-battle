#!/usr/bin/env python3
"""マップ（Map.model.json）とアイテム出現地点（ItemSpawns.model.json）を生成する。

実行: python3 tools/gen_map.py
数字を変えて再実行すれば、Rojo 経由で Studio にすぐ反映される。

レイアウト（上から見た図。+X が右、+Z が下）
    北西: 森（木・岩・丘）        | 北東: コンテナヤード（積み上げ・ルーフ）
    ------------- 中央: 広場とタワー（スロープ2本） -------------
    南西: 生け垣の迷路             | 南東: アスレチック（トンネル・段差・すべり台）
各エリアの中央（±60, ±60）は空き地にしてあり、アイテムが出現する。
"""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "src" / "workspace"

# Enum.Material の値
MAT = {
    "Plastic": 256, "SmoothPlastic": 272, "Neon": 288, "Wood": 512, "WoodPlanks": 528,
    "Slate": 800, "Concrete": 816, "Brick": 848, "Cobblestone": 880,
    "CorrodedMetal": 1040, "DiamondPlate": 1056, "Metal": 1088,
    "Grass": 1280, "Sand": 1296, "Glass": 1568,
}
BALL, BLOCK, CYLINDER = 0, 1, 2

parts = []


def _rot_matrix(x_axis):
    """ローカル X 軸を x_axis に向け、Y 軸をできるだけ上に向ける回転行列（行優先）。"""
    n = math.sqrt(sum(c * c for c in x_axis))
    x = [c / n for c in x_axis]
    up = [0.0, 1.0, 0.0]
    dot = sum(a * b for a, b in zip(up, x))
    y = [u - dot * c for u, c in zip(up, x)]
    n = math.sqrt(sum(c * c for c in y))
    y = [c / n for c in y]
    z = [x[1] * y[2] - x[2] * y[1], x[2] * y[0] - x[0] * y[2], x[0] * y[1] - x[1] * y[0]]
    return [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]


def part(name, size, pos, color, material="SmoothPlastic", shape=BLOCK, rot=None,
         transparency=0.0, collide=True, children=None):
    props = {
        "Anchored": True,
        "Size": {"Vector3": [float(v) for v in size]},
        "Color": {"Color3uint8": list(color)},
        "Material": {"Enum": MAT[material]},
        "TopSurface": {"Enum": 0},
        "BottomSurface": {"Enum": 0},
    }
    if rot is None:
        props["Position"] = {"Vector3": [float(v) for v in pos]}
    else:
        props["CFrame"] = {"CFrame": {"position": [float(v) for v in pos], "orientation": rot}}
    if shape != BLOCK:
        props["Shape"] = {"Enum": shape}
    if transparency:
        props["Transparency"] = {"Float32": transparency}
    if not collide:
        props["CanCollide"] = {"Bool": False}
    node = {"name": name, "className": "Part", "properties": props}
    if children:
        node["children"] = children
    parts.append(node)
    return node


VERTICAL = [[0, -1, 0], [1, 0, 0], [0, 0, 1]]  # Z 軸まわりに90度：円柱（軸はローカル X）を縦に立てる


def ramp(name, low, high, width, color, material="WoodPlanks", thick=1.0):
    """low から high へ登るスロープ（厚み thick の板）。上面が両端の点を通るよう少し下げる。"""
    d = [h - l for h, l in zip(high, low)]
    length = math.sqrt(sum(c * c for c in d))
    rot = _rot_matrix(d)
    # 板の中心を、上面の法線（ローカル Y）方向に thick/2 だけ下げる
    ny = [rot[0][1], rot[1][1], rot[2][1]]
    mid = [(l + h) / 2 - n * thick / 2 for l, h, n in zip(low, high, ny)]
    part(name, (length + 1, thick, width), mid, color, material, rot=rot)


def wall_x(name, x1, x2, z, h, t, color, material, y0=0.0):
    part(name, (abs(x2 - x1), h, t), ((x1 + x2) / 2, y0 + h / 2, z), color, material)


def wall_z(name, z1, z2, x, h, t, color, material, y0=0.0):
    part(name, (t, h, abs(z2 - z1)), (x, y0 + h / 2, (z1 + z2) / 2), color, material)


def light(range_=28, brightness=1.5, color=(1.0, 0.85, 0.6)):
    return [{
        "name": "Light",
        "className": "PointLight",
        "properties": {
            "Range": {"Float32": range_},
            "Brightness": {"Float32": brightness},
            "Color": {"Color3": list(color)},
        },
    }]


# ---------------------------------------------------------------- 地面と外周
HALF = 120
part("Floor", (2 * HALF, 2, 2 * HALF), (0, -1, 0), (96, 176, 60), "Grass")
# 中央から4方向にのびる石畳の道
part("PathX", (2 * HALF - 8, 0.2, 12), (0, 0.1, 0), (170, 160, 140), "Cobblestone")
part("PathZ", (12, 0.2, 2 * HALF - 8), (0, 0.1, 0), (170, 160, 140), "Cobblestone")

WALL_H, WALL_T = 22, 4
BRICK = (150, 85, 70)
wall_x("WallN", -HALF, HALF, HALF, WALL_H, WALL_T, BRICK, "Brick")
wall_x("WallS", -HALF, HALF, -HALF, WALL_H, WALL_T, BRICK, "Brick")
wall_z("WallE", -HALF, HALF, HALF, WALL_H, WALL_T, BRICK, "Brick")
wall_z("WallW", -HALF, HALF, -HALF, WALL_H, WALL_T, BRICK, "Brick")
STRIPE = (255, 200, 60)
wall_x("StripeN", -HALF, HALF, HALF - 2.2, 1, 0.4, STRIPE, "Neon", y0=WALL_H - 4)
wall_x("StripeS", -HALF, HALF, -HALF + 2.2, 1, 0.4, STRIPE, "Neon", y0=WALL_H - 4)
wall_z("StripeE", -HALF, HALF, HALF - 2.2, 1, 0.4, STRIPE, "Neon", y0=WALL_H - 4)
wall_z("StripeW", -HALF, HALF, -HALF + 2.2, 1, 0.4, STRIPE, "Neon", y0=WALL_H - 4)
for i, (sx, sz) in enumerate([(1, 1), (-1, 1), (-1, -1), (1, -1)], 1):
    part(f"CornerTower{i}", (12, 30, 12), (sx * (HALF - 2), 15, sz * (HALF - 2)), (120, 70, 60), "Brick")
    part(f"CornerBeacon{i}", (6, 6, 6), (sx * (HALF - 2), 33, sz * (HALF - 2)), STRIPE, "Neon",
         shape=BALL, children=light(60, 2))

# ---------------------------------------------------------------- 中央: 広場とタワー
part("Plaza", (0.4, 56, 56), (0, 0.2, 0), (200, 195, 185), "Slate", shape=CYLINDER, rot=VERTICAL)
TOWER_Y = 15
for i, (sx, sz) in enumerate([(1, 1), (-1, 1), (-1, -1), (1, -1)], 1):
    part(f"TowerPillar{i}", (2.5, TOWER_Y, 2.5), (sx * 8, TOWER_Y / 2, sz * 8), (90, 90, 100), "Concrete")
part("TowerDeck", (20, 1, 20), (0, TOWER_Y - 0.5, 0), (230, 120, 50), "DiamondPlate")
# 手すり（スロープがつながる ±X 側の中央はあけておく）
RAIL = (60, 60, 70)
wall_x("RailN", -10, 10, 9.7, 3, 0.6, RAIL, "Metal", y0=TOWER_Y)
wall_x("RailS", -10, 10, -9.7, 3, 0.6, RAIL, "Metal", y0=TOWER_Y)
for sx in (1, -1):
    wall_z(f"RailX{sx}a", 4, 10, sx * 9.7, 3, 0.6, RAIL, "Metal", y0=TOWER_Y)
    wall_z(f"RailX{sx}b", -10, -4, sx * 9.7, 3, 0.6, RAIL, "Metal", y0=TOWER_Y)
part("TowerFlag", (1, 10, 1), (0, TOWER_Y + 5, 0), (240, 240, 240), "Metal")
part("TowerFlagCloth", (5, 3, 0.3), (2.8, TOWER_Y + 8.5, 0), (230, 50, 60), "Plastic")
ramp("TowerRampE", (42, 0, 0), (10, TOWER_Y, 0), 7, (190, 140, 90))
ramp("TowerRampW", (-42, 0, 0), (-10, TOWER_Y, 0), 7, (190, 140, 90))
for i, (sx, sz) in enumerate([(1, 1), (-1, 1), (-1, -1), (1, -1)], 1):
    part(f"LampPole{i}", (0.8, 10, 0.8), (sx * 22, 5, sz * 22), (50, 50, 55), "Metal")
    part(f"LampHead{i}", (2.4, 2.4, 2.4), (sx * 22, 10.6, sz * 22), (255, 230, 170), "Neon",
         shape=BALL, children=light())

# ---------------------------------------------------------------- 北東: コンテナヤード
CONT = [(200, 60, 50), (50, 110, 200), (240, 190, 40), (60, 160, 90), (240, 120, 40)]
containers = [
    # (x, y, z, 長い向き, 色)
    (32, 5, 34, "x", 0), (36, 5, 86, "x", 1), (86, 5, 30, "z", 2), (90, 5, 82, "z", 3),
    (90, 15, 76, "short", 4), (62, 5, 100, "x", 2), (102, 5, 54, "z", 0), (44, 5, 62, "z", 1),
    (38, 15, 34, "short", 3),
]
for i, (x, y, z, d, c) in enumerate(containers, 1):
    size = {"x": (20, 10, 8), "z": (8, 10, 20), "short": (8, 10, 10)}[d]
    part(f"Container{i}", size, (x, y, z), CONT[c], "CorrodedMetal")
# コンテナの上に登るルート
ramp("ContainerRamp1", (90, 0, 110), (90, 10, 92), 6, (120, 120, 125), "DiamondPlate")
part("ContainerStep1", (4, 5, 4), (90, 12.5, 86), (160, 110, 60), "WoodPlanks")
ramp("ContainerRamp2", (27, 0, 12.5), (27, 10, 30), 6, (120, 120, 125), "DiamondPlate")
part("ContainerStep2", (4, 5, 4), (30, 12.5, 34), (160, 110, 60), "WoodPlanks")
for i, (x, z) in enumerate([(70, 40), (74, 44), (55, 82), (106, 96), (20, 104), (75, 20)], 1):
    part(f"Crate{i}", (4, 4, 4), (x, 2, z), (160, 110, 60), "WoodPlanks")

# ---------------------------------------------------------------- 北西: 森
trees = [(-32, 32), (-25, 56), (-36, 86), (-50, 40), (-86, 34), (-95, 70), (-76, 96),
         (-52, 108), (-100, 102), (-72, 24), (-86, 54), (-42, 66), (-108, 22)]
for i, (x, z) in enumerate(trees, 1):
    h = 10 + (i * 7) % 5
    part(f"Trunk{i}", (h, 2.4, 2.4), (x, h / 2, z), (110, 75, 45), "Wood", shape=CYLINDER, rot=VERTICAL)
    s = 11 + (i * 3) % 4
    part(f"Leaves{i}", (s, s, s), (x, h + s * 0.3, z), (50, 130 + (i * 11) % 40, 55), "Grass", shape=BALL)
part("Hill", (40, 40, 40), (-30, -13, 100), (100, 170, 70), "Grass", shape=BALL)
part("HillTrunk", (9, 2.4, 2.4), (-30, 7 + 4.5, 100), (110, 75, 45), "Wood", shape=CYLINDER, rot=VERTICAL)
part("HillLeaves", (12, 12, 12), (-30, 7 + 9 + 3.6, 100), (70, 160, 60), "Grass", shape=BALL)
for i, (x, z, s) in enumerate([(-58, 86, 7), (-92, 16, 6), (-20, 22, 5), (-110, 44, 8), (-66, 40, 5)], 1):
    part(f"Rock{i}", (s, s, s), (x, s * 0.25, z), (130, 130, 135), "Slate", shape=BALL)

# ---------------------------------------------------------------- 南西: 生け垣の迷路
HEDGE, HH, HT = (40, 105, 45), 8, 3
hedges_x = [  # (x1, x2, z)
    (-76, -65, -45), (-55, -44, -45), (-76, -44, -75),
    (-96, -71, -25), (-59, -25, -25), (-96, -41, -96), (-29, -25, -96),
]
hedges_z = [  # (z1, z2, x)
    (-76, -65, -45), (-55, -44, -45), (-76, -44, -75),
    (-96, -51, -25), (-39, -25, -25), (-96, -86, -96), (-74, -25, -96),
    (-96, -82, -60), (-38, -25, -60),
]
for i, (a, b, z) in enumerate(hedges_x, 1):
    wall_x(f"HedgeX{i}", a, b, z, HH, HT, HEDGE, "Grass")
for i, (a, b, x) in enumerate(hedges_z, 1):
    wall_z(f"HedgeZ{i}", a, b, x, HH, HT, HEDGE, "Grass")
for i, (x, z) in enumerate([(-25, -25), (-96, -25), (-25, -96), (-96, -96)], 1):
    part(f"MazePost{i}", (4, 11, 4), (x, 5.5, z), (200, 195, 185), "Slate")
    part(f"MazeGem{i}", (2.5, 2.5, 2.5), (x, 12.5, z), (120, 220, 255), "Neon", shape=BALL)

# ---------------------------------------------------------------- 南東: アスレチック
PARK = (80, 170, 230)
# ファンボックス（台の両側にスロープ）
part("FunBox", (16, 4, 14), (60, 2, -34), (230, 230, 235), "Concrete")
ramp("FunRampE", (80, 0, -34), (68, 4, -34), 14, PARK, "SmoothPlastic")
ramp("FunRampW", (40, 0, -34), (52, 4, -34), 14, PARK, "SmoothPlastic")
# トンネル（中を走り抜けられる）
wall_z("TunnelWallA", -78, -44, 85, 7, 1.5, (240, 120, 40), "SmoothPlastic")
wall_z("TunnelWallB", -78, -44, 95, 7, 1.5, (240, 120, 40), "SmoothPlastic")
part("TunnelRoof", (11.5, 1.2, 34), (90, 7.6, -61), (250, 200, 60), "SmoothPlastic")
# 段差を登って、高台からすべり台で下りる
STEP = (240, 80, 120)
for i, (x, h) in enumerate([(26, 3), (34, 6), (42, 9), (50, 12)], 1):
    part(f"JumpStep{i}", (6, h, 6), (x, h / 2, -92), STEP, "SmoothPlastic")
part("HighDeck", (14, 1, 14), (62, 13.5, -92), (230, 230, 235), "DiamondPlate")
for sx in (-1, 1):
    part(f"HighDeckLeg{sx}", (2, 13, 2), (62 + sx * 6, 6.5, -86), (90, 90, 100), "Metal")
    part(f"HighDeckLegB{sx}", (2, 13, 2), (62 + sx * 6, 6.5, -98), (90, 90, 100), "Metal")
ramp("Slide", (106, 0, -92), (69, 14, -92), 6, (250, 200, 60), "SmoothPlastic")
for i, (x, z) in enumerate([(32, -60), (40, -66), (100, -26), (24, -40), (104, -104)], 1):
    part(f"Bumper{i}", (5, 3, 5), (x, 1.5, z), PARK, "SmoothPlastic", shape=CYLINDER, rot=VERTICAL)

# ---------------------------------------------------------------- スポーン地点
part("SpawnPad", (0.6, 14, 14), (0, 0.5, 0), (255, 255, 255), "Neon", shape=CYLINDER, rot=VERTICAL,
     transparency=0.3, collide=False)
spawn = {
    "name": "SpawnLocation",
    "className": "SpawnLocation",
    "properties": {
        "Anchored": True,
        "Size": {"Vector3": [12.0, 1.0, 12.0]},
        "Position": {"Vector3": [0.0, 0.5, 0.0]},
        "Transparency": {"Float32": 1.0},
        "Duration": {"Int32": 0},
    },
}

map_model = {"className": "Model", "children": parts + [spawn]}

# ---------------------------------------------------------------- アイテム出現地点（すべて地面の上・障害物の外）
spawn_points = [
    (55, 0), (92, 0), (-55, 0), (-92, 0), (0, 55), (0, 92), (0, -55), (0, -92),
    (60, 60), (-60, 60), (-60, -60), (60, -60), (0, 24), (0, -24),
]
item_spawns = {
    "className": "Folder",
    "children": [
        {
            "name": f"Spawn{i}",
            "className": "Part",
            "properties": {
                "Anchored": True,
                "CanCollide": {"Bool": False},
                "Transparency": {"Float32": 1.0},
                "Size": {"Vector3": [2.0, 1.0, 2.0]},
                "Position": {"Vector3": [float(x), 0.5, float(z)]},
            },
        }
        for i, (x, z) in enumerate(spawn_points, 1)
    ],
}

(OUT_DIR / "Map.model.json").write_text(json.dumps(map_model, ensure_ascii=False, indent=1) + "\n")
(OUT_DIR / "ItemSpawns.model.json").write_text(json.dumps(item_spawns, ensure_ascii=False, indent=1) + "\n")
print(f"Map: {len(parts) + 1} parts / ItemSpawns: {len(spawn_points)} points")
