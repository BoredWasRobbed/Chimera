"""The city around Axiom Tower: night-time blocks of towers 900 studs down, seen through the windows.

Each building is a Neon core (its window glow colour) with a facade Texture on the faces that look toward
the tower: lit windows are transparent in the texture, so the glow shows through them. A dark cap hides the
glowing top. Streets are dark planes with sodium-lit strips. Nothing here collides, casts shadows or takes
raycasts, and none of it is in the map contract (Workspace.City)."""
from __future__ import annotations

import math
import random

STREET_Y = -900  # the street, 61 floors down
FACADES = {
    "office": ("rbxassetid://125512699450578", 224, 224),
    "flats": ("rbxassetid://85949362747642", 224, 224),
    "glass": ("rbxassetid://116716908961355", 224, 224),
    "stone": ("rbxassetid://94465287245181", 224, 224),
}
GLOWS = [(255, 214, 160), (255, 226, 186), (236, 232, 214), (214, 226, 240), (255, 200, 140), (200, 214, 230)]
CROWNS = [(80, 200, 255), (230, 236, 240), (255, 190, 110)]

TOWER = (-250, 250, -166, 150)  # our own block (x0, x1, z0, z1), kept clear


def build(seed=61):
    rng = random.Random(seed)
    parts = []

    def part(n, cx, cy, cz, sx, sy, sz, mat, col, **kw):
        rec = {"n": n, "f": "City", "p": [round(cx, 1), round(cy, 1), round(cz, 1)], "s": [round(sx, 1), round(sy, 1), round(sz, 1)],
               "m": mat, "c": list(col), "nc": 1, "nq": 1, "ns": 1}
        rec.update(kw)
        parts.append(rec)
        return rec

    # The street grid: blocks 340 x 260 with 70-wide streets, our tower's block at the origin.
    bw, bd, street = 340, 260, 70
    pitch_x, pitch_z = bw + street, bd + street
    part("Ground", 0, STREET_Y - 2, -900, 12000, 4, 12000, "Asphalt", (14, 14, 16))
    for i in range(-11, 12):
        x = i * pitch_x - pitch_x / 2
        part("StreetLights", x - street / 2 + 6, STREET_Y + 0.6, -900, 1.5, 1.2, 11000, "Neon", (255, 170, 90), t=0.25)
        part("StreetLights", x + street / 2 - 6, STREET_Y + 0.6, -900, 1.5, 1.2, 11000, "Neon", (255, 170, 90), t=0.25)
        part("Traffic", x - 8, STREET_Y + 0.8, -900, 0.8, 0.8, 11000, "Neon", (255, 236, 210), t=0.6)
        part("Traffic", x + 8, STREET_Y + 0.8, -900, 0.8, 0.8, 11000, "Neon", (255, 150, 60), t=0.6)
    for j in range(-17, 9):
        z = j * pitch_z - pitch_z / 2
        part("StreetLights", 0, STREET_Y + 0.6, z - street / 2 + 6, 11000, 1.2, 1.5, "Neon", (255, 170, 90), t=0.25)
        part("StreetLights", 0, STREET_Y + 0.6, z + street / 2 - 6, 11000, 1.2, 1.5, "Neon", (255, 170, 90), t=0.25)

    downtown = (300, -2600)
    for i in range(-11, 11):
        for j in range(-17, 8):
            bx, bz = i * pitch_x, j * pitch_z
            if abs(bx) < pitch_x / 2 and abs(bz) < pitch_z / 2:
                continue  # our own block
            dist = math.hypot(bx, bz)
            if dist > 5200:
                continue
            if bz > 1600 and rng.random() < 0.5:
                continue
            ddown = math.hypot(bx - downtown[0], bz - downtown[1])
            tall = max(0.0, 1 - ddown / 3800)
            # One to four buildings per block, each taking a share of it.
            splits = rng.choice([1, 1, 2, 2, 3, 4])
            cells = []
            if splits == 1:
                cells = [(0, 0, bw, bd)]
            elif splits == 2:
                cells = [(-bw / 4, 0, bw / 2, bd), (bw / 4, 0, bw / 2, bd)] if rng.random() < 0.5 else [(0, -bd / 4, bw, bd / 2), (0, bd / 4, bw, bd / 2)]
            elif splits == 3:
                cells = [(-bw / 4, 0, bw / 2, bd), (bw / 4, -bd / 4, bw / 2, bd / 2), (bw / 4, bd / 4, bw / 2, bd / 2)]
            else:
                cells = [(sx * bw / 4, sz * bd / 4, bw / 2, bd / 2) for sx in (-1, 1) for sz in (-1, 1)]
            for (ox, oz, cw, cd) in cells:
                if rng.random() < 0.12:
                    continue  # a plaza or a low roof
                inset = rng.uniform(10, 34)
                w, d = cw - 2 * inset, cd - 2 * inset
                if w < 40 or d < 40:
                    continue
                cx, cz = bx + ox + rng.uniform(-4, 4), bz + oz + rng.uniform(-4, 4)
                base_h = rng.uniform(140, 520)
                h = base_h + tall * rng.uniform(300, 1500) + (rng.random() < 0.06) * rng.uniform(300, 700)
                top = STREET_Y + h
                kind = rng.choice(["office", "office", "glass", "flats", "flats", "stone"] if tall < 0.4 else ["office", "glass", "glass", "office", "stone"])
                tex, su, sv = FACADES[kind]
                glow = rng.choice(GLOWS)
                dim = rng.uniform(0.55, 1.0)
                col = tuple(int(c * dim) for c in glow)
                faces = []
                if cz > 0:
                    faces.append(("Front", su, sv))  # -Z face looks north, toward us when the building is south
                if cz < 0:
                    faces.append(("Back", su, sv))
                if cx > 0:
                    faces.append(("Left", su, sv))  # -X face
                if cx < 0:
                    faces.append(("Right", su, sv))
                texs = [{"id": tex, "face": f, "u": su, "v": sv, "ou": round(rng.uniform(0, su), 1), "ov": round(rng.uniform(0, sv), 1)} for f, su, sv in faces]
                part("Building", cx, (STREET_Y + top) / 2, cz, w, h, d, "Neon", col, tex=texs)
                part("Roof", cx, top + 1.5, cz, w + 2, 3, d + 2, "SmoothPlastic", (12, 12, 14))
                if rng.random() < 0.55:
                    pw, pd = w * rng.uniform(0.3, 0.6), d * rng.uniform(0.3, 0.6)
                    ph = rng.uniform(14, 40)
                    part("Penthouse", cx + rng.uniform(-w / 5, w / 5), top + 3 + ph / 2, cz + rng.uniform(-d / 5, d / 5), pw, ph, pd, "SmoothPlastic", (16, 16, 18))
                if h > 900 and rng.random() < 0.6:
                    crown = rng.choice(CROWNS)
                    part("Crown", cx, top - 12, cz, w + 0.6, 4, d + 0.6, "Neon", crown, t=0.15)
                if h > 1100 and rng.random() < 0.5:
                    mh = rng.uniform(60, 160)
                    part("Mast", cx, top + 3 + mh / 2, cz, 3, mh, 3, "SmoothPlastic", (20, 20, 22))
                    part("Beacon", cx, top + 3 + mh + 2, cz, 4, 4, 4, "Neon", (240, 244, 255), shape="ball", tag="CityBeacon")
                elif rng.random() < 0.3:
                    part("WaterTank", cx + w / 4, top + 12, cz - d / 4, 18, 20, 18, "Wood", (34, 28, 24), shape="cyl", r=[0, 0, 90])
    return parts
