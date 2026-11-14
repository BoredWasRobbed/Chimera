#!/usr/bin/env python3
"""Designs Axiom Tower, Level 61: the Chimera map, a corporate data vault high in a skyscraper at night.

The squad rides the service lift up to Level 61 and steps out into the elevator lobby. Ahead is the core of
the floor: the Reception, a two-storey atrium round the reception desk and the Uplink, with a wall of glass
on its far side looking out over the city. The wings wrap round it: the Office Wing (west), the Server Farms
(east), the Fabrication Bays behind the lifts, the Cooling Plant (south-east) and the back-of-house
Maintenance areas (south-west, with the Boiler Room); the Observation Deck looks down on the atrium from over the lobby.

The layout below (rooms, spaces, openings, windows) is the source of truth. This script checks it, works out
every structural block, finish, prop and gameplay piece, and writes:
  tools/map/MapLayout.luau   the placements as a JSON string; ServerStorage.DevTools.BuildMap builds them
  tools/map/plan.png         a top-down plan for review (pass --plan PATH to write it elsewhere)

Run:  python tools/map/design_map.py            (checks, then writes both files)
      python tools/map/design_map.py --check    (checks only)
      add --walk to print walking distances between the terminals and from the spawn
Needs Pillow and numpy. Then build it in Studio: require(game.ServerStorage.DevTools.BuildMap:Clone()).build()

Conventions (studs): +x is east, +z is south (north is -z, toward the city's downtown), y is up; the floor of
Level 61 is y = 0 and the street is 900 below. See mapgen/core.py for spaces, rooms and pivots.
"""
from __future__ import annotations

import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from mapgen import city, core, dress, props  # noqa: E402
from mapgen.core import (EXTERIOR, GAME, OPENINGS, ROOMS, SPACES, WARNINGS, ERRORS, exterior, glazing,  # noqa: E402
                         opening, room, space)

# ------------------------------------------------------------------------------------------------------
# Rooms and spaces. Wings: CORE, INSERTION, OD (Observation Deck), OW (Office Wing), SF (Server Farms),
# CP (Cooling Plant), MT (Maintenance), FAB (Fabrication Bays: not a wing with a terminal; its docks stay up).

WINGS = {
    "CORE": (70, 110, 190), "INSERTION": (220, 220, 230), "OD": (120, 200, 210), "OW": (170, 150, 110),
    "FAB": (200, 120, 70), "SF": (70, 130, 230), "CP": (100, 210, 230), "MT": (200, 150, 80),
}

# The core: the Reception atrium, the lift lobby, the deck over it and the two fire stairs.
room("CORE", "Reception", "CORE", "atrium")
space("CORE", "CORE", -56, 56, -148, -52, h=40, walls="atrium", floor="terrazzo", ceiling="plaster")
room("INSERTION", "Elevator Lobby", "INSERTION", "lobby")
space("INS", "INSERTION", -20, 20, -50, -14, h=16, walls="lobby", floor="terrazzo", ceiling="plaster", drop=13)
space("INS_CAR", "INSERTION", -6, 6, -12, 0, h=12, open=("N",), walls="car", floor="tread", ceiling="plaster", drop=10.5)
room("OD_DECK", "Observation Deck", "OD", "deck")
space("OD_DECK", "OD_DECK", -20, 20, -50, -14, h=14, y0=24, walls="exec", floor="carpetDark", ceiling="tile", drop=11.5)
room("OD_STAIR_W", "West Stairwell", "OD", "stair")
space("OD_STAIR_W", "OD_STAIR_W", -38, -22, -50, -14, h=40, walls="block", floor="concrete", ceiling="plaster", drop=38)
room("OD_STAIR_E", "East Stairwell", "OD", "stair")
space("OD_STAIR_E", "OD_STAIR_E", 22, 38, -50, -14, h=40, walls="block", floor="concrete", ceiling="plaster", drop=38)

# Office Wing (west): open-plan desks along the windows, the corner office, meeting rooms, the break room.
room("OW_OPEN", "Open Office", "OW", "office")
space("OW_OPEN", "OW_OPEN", -188, -58, -148, -84, h=16, walls="office", floor="carpet", ceiling="tile", drop=12, holes=7)
space("OW_HALL", "OW_OPEN", -188, -58, -82, -72, h=16, walls="corridor", floor="carpetDark", ceiling="tile", drop=12, holes=2)
room("OW_EXEC", "Executive Office", "OW", "exec")
space("OW_EXEC", "OW_EXEC", -232, -190, -148, -112, h=16, walls="exec", floor="carpetWarm", ceiling="tile", drop=12)
room("OW_CONF", "Conference Room", "OW", "office")
space("OW_CONF", "OW_CONF", -232, -190, -110, -62, h=16, walls="office", floor="carpet", ceiling="tile", drop=12, holes=1)
room("OW_BREAK", "Break Room", "OW", "break")
space("OW_BREAK", "OW_BREAK", -188, -134, -70, -36, h=16, walls="cool", floor="vinyl", ceiling="tile", drop=12, holes=2)
space("OW_WC_M", "OW_BREAK", -132, -114, -70, -52, h=16, walls="tile", floor="tile", ceiling="tile", drop=11)
space("OW_WC_F", "OW_BREAK", -112, -94, -70, -52, h=16, walls="tile", floor="tile", ceiling="tile", drop=11, holes=1)
room("OW_ARCHIVE", "Records Room", "OW", "archive")
space("OW_ARCHIVE", "OW_ARCHIVE", -232, -190, -60, 38, h=16, walls="white", floor="vinyl", ceiling="tile", drop=12, holes=3)

# Server Farms (east): the data hall, the network operations centre in the corner, the rack hall, the UPS room.
room("SF_DATAHALL", "Data Hall", "SF", "server")
space("SF_DATAHALL", "SF_DATAHALL", 58, 188, -148, -84, h=18, walls="server", floor="raised", ceiling="exposed")
space("SF_HALL", "SF_DATAHALL", 58, 188, -82, -72, h=16, walls="corridor", floor="vinyl", ceiling="tile", drop=12)
room("SF_NOC", "Network Operations", "SF", "noc")
space("SF_NOC", "SF_NOC", 190, 232, -148, -112, h=16, walls="cool", floor="carpetDark", ceiling="tile", drop=12)
room("SF_UPS", "UPS Room", "SF", "ups")
space("SF_UPS", "SF_UPS", 190, 232, -110, -62, h=16, walls="block", floor="concrete", ceiling="exposed")
room("SF_RACKHALL", "Rack Hall", "SF", "server")
space("SF_RACKHALL", "SF_RACKHALL", 58, 188, -70, -30, h=18, walls="server", floor="raised", ceiling="exposed")

# Cooling Plant (south-east).
room("CP_PUMPS", "Pump Room", "CP", "plant")
space("CP_PUMPS", "CP_PUMPS", 190, 232, -60, 38, h=24, walls="block", floor="concreteDark", ceiling="exposed")
room("CP_CHILLERS", "Chiller Hall", "CP", "plant")
space("CP_CHILLERS", "CP_CHILLERS", 54, 150, 14, 70, h=24, walls="block", floor="concreteDark", ceiling="exposed")
space("CP_BACKHALL", "CP_CHILLERS", 138, 150, -28, 12, h=14, walls="block", floor="concrete", ceiling="exposed")
room("CP_CONTROL", "Plant Control", "CP", "control")
space("CP_CONTROL", "CP_CONTROL", 152, 232, 40, 100, h=16, walls="cool", floor="vinyl", ceiling="tile", drop=12, holes=2)

# Maintenance (back of house): the service corridors either side of the lifts, the freight hall, the
# mechanical room in the south-west corner.
room("MT_WEST", "West Service Corridor", "MT", "service")
space("MTW_N", "MT_WEST", -52, -40, -50, 4, h=14, walls="block", floor="concrete", ceiling="exposed")
space("MTW_S", "MT_WEST", -52, -40, 6, 62, h=14, walls="block", floor="concrete", ceiling="exposed")
room("MT_EAST", "East Service Corridor", "MT", "service")
space("MTE_N", "MT_EAST", 40, 52, -50, 4, h=14, walls="block", floor="concrete", ceiling="exposed")
space("MTE_S", "MT_EAST", 40, 52, 6, 62, h=14, walls="block", floor="concrete", ceiling="exposed")
room("MT_LOADING", "Freight Hall", "MT", "freight")
space("MT_LOADING", "MT_LOADING", -150, -54, 14, 70, h=20, walls="block", floor="concreteDark", ceiling="exposed")
space("MT_BACKHALL", "MT_LOADING", -150, -138, -34, 12, h=14, walls="block", floor="concrete", ceiling="exposed")
room("MT_MECH", "Boiler Room", "MT", "mech")
space("MT_MECH", "MT_MECH", -232, -152, 40, 132, h=24, walls="block", floor="concreteDark", ceiling="exposed")

# Fabrication Bays (behind the lifts): where the shells are printed.
room("FAB_ASSEMBLY", "Assembly Bay", "FAB", "fab")
space("FAB_ASSEMBLY", "FAB_ASSEMBLY", -38, 38, 14, 70, h=24, walls="lab", floor="epoxy", ceiling="exposed")
room("FAB_PRINT", "Print Floor", "FAB", "fab")
space("FAB_PRINT", "FAB_PRINT", -56, 56, 72, 132, h=24, walls="lab", floor="epoxy", ceiling="exposed")

# ------------------------------------------------------------------------------------------------------
# Openings: (a, b, start along the wall, width, kind, door id, name, base=None, style=door look)
#   door      an 8 x 10 doorway with a lockable sliding door (Map/Doors); style office, steel or glass
#   frame     a doorway with no door (any width)
#   gate      a 24 x 14 opening
#   elevator  the lift car's 12 x 10 opening

# The Reception.
opening("CORE", "INS", -12, 24, "gate", height=12)
opening("CORE", "OW_OPEN", -124, 8, "door", "D_CORE_OW", "Office entrance", style="glass")
opening("CORE", "OW_HALL", -81, 8, "frame")
opening("CORE", "SF_DATAHALL", -124, 8, "door", "D_CORE_SF", "Data Hall door", style="steel")
opening("CORE", "SF_HALL", -81, 8, "frame")
opening("CORE", "MTW_N", -50, 8, "door", "D_CORE_MTW", "West service door", style="steel")
opening("CORE", "MTE_N", 42, 8, "door", "D_CORE_MTE", "East service door", style="steel")
# The lobby, the lift car and the stairs to the deck.
opening("INS", "INS_CAR", -6, 12, "elevator")
opening("MTW_N", "OD_STAIR_W", -24, 8, "door", "D_STAIR_W", "West stair door", style="steel")
opening("MTE_N", "OD_STAIR_E", -24, 8, "door", "D_STAIR_E", "East stair door", style="steel")
opening("OD_STAIR_W", "OD_DECK", -23, 8, "door", "D_OD_W", "Deck west door", base=24, style="office")
opening("OD_STAIR_E", "OD_DECK", -23, 8, "door", "D_OD_E", "Deck east door", base=24, style="office")
# Office Wing.
opening("OW_OPEN", "OW_EXEC", -136, 8, "door", "D_OW_EXEC", "Executive Office door", style="office")
opening("OW_EXEC", "OW_CONF", -216, 8, "door", "D_OW_EXEC_S", "Executive Office side door", style="office")
opening("OW_CONF", "OW_HALL", -81, 8, "door", "D_OW_CONF", "Conference Room door", style="office")
opening("OW_OPEN", "OW_HALL", -176, 10, "frame")
opening("OW_OPEN", "OW_HALL", -118, 10, "frame")
opening("OW_HALL", "OW_BREAK", -170, 10, "frame")
opening("OW_HALL", "OW_WC_M", -127, 6, "frame")
opening("OW_HALL", "OW_WC_F", -107, 6, "frame")
opening("OW_BREAK", "OW_ARCHIVE", -54, 8, "door", "D_OW_ARCHIVE", "Records Room door", style="office")
opening("OW_BREAK", "MT_BACKHALL", -148, 8, "door", "D_OW_SERVICE", "Break Room service door", style="steel")
opening("OW_ARCHIVE", "MT_MECH", -228, 8, "door", "D_MT_MECH_N", "Boiler Room north door", style="steel")
# Server Farms.
opening("SF_DATAHALL", "SF_HALL", 74, 10, "frame")
opening("SF_DATAHALL", "SF_HALL", 160, 10, "frame")
opening("SF_DATAHALL", "SF_NOC", -122, 8, "door", "D_SF_NOC_W", "Network Ops door", style="steel")
opening("SF_NOC", "SF_UPS", 206, 8, "door", "D_SF_NOC_S", "Network Ops back door", style="steel")
opening("SF_HALL", "SF_UPS", -81, 8, "door", "D_SF_UPS", "UPS Room door", style="steel")
opening("SF_HALL", "SF_RACKHALL", 104, 24, "frame")
opening("SF_RACKHALL", "CP_PUMPS", -48, 8, "door", "D_CP_PUMPS_W", "Pump Room west door", style="steel")
opening("SF_RACKHALL", "CP_BACKHALL", 140, 8, "frame")
# Cooling Plant.
opening("CP_BACKHALL", "CP_CHILLERS", 140, 8, "frame")
opening("CP_PUMPS", "CP_CONTROL", 206, 8, "door", "D_CP_CONTROL_N", "Plant Control north door", style="steel")
opening("CP_CHILLERS", "CP_CONTROL", 54, 8, "door", "D_CP_CONTROL_W", "Plant Control west door", style="steel")
# Maintenance.
opening("MTW_N", "MTW_S", -50, 8, "frame")
opening("MTE_N", "MTE_S", 42, 8, "frame")
opening("MTW_S", "MT_LOADING", 30, 8, "door", "D_MT_LOADING", "Freight Hall door", style="steel")
opening("MTE_S", "CP_CHILLERS", 30, 8, "door", "D_CP_CHILLERS", "Chiller Hall door", style="steel")
opening("MT_BACKHALL", "MT_LOADING", -148, 8, "frame")
opening("MT_LOADING", "MT_MECH", 54, 8, "door", "D_MT_MECH_E", "Boiler Room east door", style="steel")
# Fabrication Bays.
opening("MTW_S", "FAB_ASSEMBLY", 42, 8, "frame")
opening("MTE_S", "FAB_ASSEMBLY", 42, 8, "frame")
opening("FAB_ASSEMBLY", "FAB_PRINT", -12, 24, "gate")

# Glass between rooms: the Observation Deck looks down into the Reception; the NOC looks into the Data Hall.
glazing("CORE", "OD_DECK", -18, 18, 24.6, 35.4)
glazing("SF_DATAHALL", "SF_NOC", -146, -130, 3, 10)

# The building's skin: the Reception's wall of glass over the city, office windows, plant louvres.
exterior("CORE", "N", -56, 56, 0, 40, "curtain")
exterior("OW_OPEN", "N", -186, -60, 2, 11)
exterior("OW_EXEC", "N", -230, -192, 2, 11)
exterior("OW_EXEC", "W", -146, -114, 2, 11)
exterior("OW_CONF", "W", -108, -64, 2, 11)
exterior("SF_NOC", "N", 192, 230, 2, 11)
exterior("SF_NOC", "E", -146, -114, 2, 11)
exterior("CP_PUMPS", "E", -52, 28, 2, 12, "louver")
exterior("CP_CONTROL", "E", 44, 96, 2, 11)
exterior("MT_MECH", "S", -224, -160, 4, 14, "louver")
exterior("MT_MECH", "W", 48, 96, 4, 14, "louver")
exterior("FAB_PRINT", "S", -48, 48, 14, 22, "clerestory")


# ------------------------------------------------------------------------------------------------------
# Plan render


def render_plan(path):
    from PIL import Image, ImageDraw, ImageFont

    xs = [v for s in SPACES.values() for v in (s.x0, s.x1)]
    zs = [v for s in SPACES.values() for v in (s.z0, s.z1)]
    pad = 24
    x_min, x_max, z_min, z_max = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad + 30
    S = 2.0
    W, H = int((x_max - x_min) * S), int((z_max - z_min) * S)
    img = Image.new("RGB", (W, H), (18, 19, 22))
    dr = ImageDraw.Draw(img, "RGBA")
    try:
        font = ImageFont.truetype("arial.ttf", 13)
        small = ImageFont.truetype("arial.ttf", 10)
    except OSError:
        font = small = ImageFont.load_default()

    def P(x, z):
        return ((x - x_min) * S, (z - z_min) * S)

    for s in SPACES.values():
        if s.y0 < 10:
            dr.rectangle([*P(s.x0 - 2, s.z0 - 2), *P(s.x1 + 2, s.z1 + 2)], fill=(60, 62, 68))
    for s in sorted(SPACES.values(), key=lambda s: s.y0):
        col = WINGS[ROOMS[s.room].wing]
        if s.y0 > 10:
            dr.rectangle([*P(s.x0, s.z0), *P(s.x1, s.z1)], outline=col + (255,), width=3, fill=col + (50,))
        else:
            dr.rectangle([*P(s.x0, s.z0), *P(s.x1, s.z1)], fill=tuple(int(c * 0.35) for c in col))
    for o in OPENINGS:
        g = core.opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        col = {"door": (255, 170, 60), "frame": (200, 200, 200), "gate": (120, 220, 255), "elevator": (230, 230, 120)}.get(o.kind, (200, 200, 200))
        if side_a in "NS":
            dr.rectangle([*P(o.at, line - 1.6), *P(o.at + o.width, line + 1.6)], fill=col + (255,))
        else:
            dr.rectangle([*P(line - 1.6, o.at), *P(line + 1.6, o.at + o.width)], fill=col + (255,))
    for gz in core.GLAZING:
        side_a, side_b, line, lo, hi = core.shared_wall(SPACES[gz["a"]], SPACES[gz["b"]])
        if side_a in "NS":
            dr.rectangle([*P(gz["from"], line - 1), *P(gz["to"], line + 1)], fill=(140, 230, 255, 255))
        else:
            dr.rectangle([*P(line - 1, gz["from"]), *P(line + 1, gz["to"])], fill=(140, 230, 255, 255))
    for ex in EXTERIOR:
        s = SPACES[ex["space"]]
        f = core.face_coord(s, ex["side"])
        col = {"curtain": (160, 240, 255), "window": (120, 190, 230), "louver": (150, 150, 120), "clerestory": (120, 190, 230)}[ex["kind"]]
        d = -2 if ex["side"] in "NW" else 2
        if ex["side"] in "NS":
            dr.rectangle([*P(ex["from"], min(f, f + d)), *P(ex["to"], max(f, f + d))], fill=col)
        else:
            dr.rectangle([*P(min(f, f + d), ex["from"]), *P(max(f, f + d), ex["to"])], fill=col)
    for sid, rects in core.FOOT.items():
        upper = SPACES[sid].y0 > 10
        for (x0, x1, z0, z1, label) in rects:
            col = (150, 150, 155, 90 if upper else 170)
            if label.startswith("DOCK"):
                col = (255, 140, 40, 255)
            elif label.startswith("TERM"):
                col = (90, 255, 140, 255)
            elif label.startswith("STATION"):
                col = (255, 235, 150, 255)
            dr.rectangle([*P(x0, z0), *P(x1, z1)], fill=col)
    for rec in core.PIECES:
        name, folder, x, z = rec[0], rec[1], rec[2], rec[4]
        if name == "SecurityCamera":
            aim = rec[6]["aim"]
            dr.line([*P(x, z), *P(x + (aim[0] - x) * 0.25, z + (aim[2] - z) * 0.25)], fill=(255, 60, 60), width=2)
            dr.ellipse([*P(x - 2, z - 2), *P(x + 2, z + 2)], fill=(255, 40, 40))
        elif folder == "Facility/Traps":
            dr.ellipse([*P(x - 1.6, z - 1.6), *P(x + 1.6, z + 1.6)], fill=(230, 80, 255))
        elif folder.startswith("Facility/Lights") and name != "LightPanel":
            dr.point(P(x, z), fill=(255, 255, 200))
    for r in ROOMS.values():
        sp = [SPACES[i] for i in r.spaces]
        main = max(sp, key=lambda s: s.w * s.d)
        x, z = (main.x0 + main.x1) / 2, (main.z0 + main.z1) / 2
        upper = main.y0 > 10
        txt = r.name + (" (upper)" if upper else "")
        px, pz = P(x, z + (10 if upper else 0))
        tw = dr.textlength(txt, font=font)
        dr.text((px - tw / 2, pz - 7), txt, fill=(235, 235, 235), font=font)
    dr.line([*P(x_min + 10, z_max - 10), *P(x_min + 110, z_max - 10)], fill=(255, 255, 255), width=2)
    dr.text(P(x_min + 10, z_max - 20), "100 studs", fill=(255, 255, 255), font=small)
    legend = [((255, 170, 60), "lockable door"), ((200, 200, 200), "doorway"), ((120, 220, 255), "gate / glass"),
              ((255, 40, 40), "camera (line: aim)"), ((255, 140, 40), "shell dock"), ((90, 255, 140), "terminal"),
              ((255, 235, 150), "charging station"), ((230, 80, 255), "Overload trap"), ((160, 240, 255), "exterior glass"),
              ((150, 150, 120), "louvres")]
    for i, (col, label) in enumerate(legend):
        px, pz = P(x_min + 120 + 76 * (i // 2), z_max - 26 + 12 * (i % 2))
        dr.rectangle([px, pz, px + 12, pz + 12], fill=col)
        dr.text((px + 18, pz), label, fill=(225, 225, 225), font=small)
    dr.text(P(x_min + 10, z_min + 6), "Axiom Tower, Level 61. North (top) faces downtown through the Reception's glass; "
            "the Observation Deck is the outlined upper level over the lobby.", fill=(225, 225, 225), font=small)
    img.save(path)
    return path


# ------------------------------------------------------------------------------------------------------
# Walking distances


def walk_distances():
    """Walking distances (studs) between the terminals and from the spawn, on a 1-stud grid round the props.
    The design doc wants no two terminals within 20 s' walk (280 studs at 14 studs/s)."""
    import heapq

    import numpy as np

    x_lo = int(min(s.x0 for s in SPACES.values())) - 2
    x_hi = int(max(s.x1 for s in SPACES.values())) + 2
    z_lo = int(min(s.z0 for s in SPACES.values())) - 2
    z_hi = int(max(s.z1 for s in SPACES.values())) + 2
    nx, nz = x_hi - x_lo, z_hi - z_lo
    walk = np.zeros((2, nx, nz), dtype=bool)

    def mark(layer, x0, x1, z0, z1, value=True):
        walk[layer, max(0, int(math.floor(x0 - x_lo))):int(math.ceil(x1 - x_lo)), max(0, int(math.floor(z0 - z_lo))):int(math.ceil(z1 - z_lo))] = value

    for s in SPACES.values():
        mark(1 if s.y0 > 10 else 0, s.x0 + 1, s.x1 - 1, s.z0 + 1, s.z1 - 1)
    for o in OPENINGS:
        side_a, side_b, line, lo, hi = core.opening_geometry(o)
        layer = 1 if core.opening_base(o) > 10 else 0
        if side_a in "NS":
            mark(layer, o.at + 1, o.at + o.width - 1, line - 2, line + 2)
        else:
            mark(layer, line - 2, line + 2, o.at + 1, o.at + o.width - 1)
    for sid, rects in core.FOOT.items():
        layer = 1 if SPACES[sid].y0 > 10 else 0
        for (x0, x1, z0, z1, label) in rects:
            mark(layer, x0 - 1, x1 + 1, z0 - 1, z1 + 1, False)
    links = []
    for st in dress.STAIRS:
        # The flights and landings: walking from the foot to the top landing costs the flights' length.
        layer0 = (0, int(st["foot"][0] - x_lo), int(st["foot"][1] - z_lo))
        layer1 = (1, int(st["top"][0] - x_lo), int(st["top"][1] - z_lo))
        mark(0, *st["blocked"], False)
        mark(1, *st["landing"])
        links.append((layer0, layer1, st["length"]))

    def dijkstra(start):
        dist = {start: 0.0}
        heap = [(0.0, start)]
        extra = {}
        for a, b, c in links:
            extra.setdefault(a, []).append((b, c))
            extra.setdefault(b, []).append((a, c))
        while heap:
            dcur, node = heapq.heappop(heap)
            if dcur > dist.get(node, 1e18):
                continue
            layer, i, j = node
            steps = [((layer, i + di, j + dj), math.hypot(di, dj)) for di in (-1, 0, 1) for dj in (-1, 0, 1) if di or dj]
            steps += extra.get(node, [])
            for (nl, ni, nj), cost in steps:
                if not (0 <= ni < nx and 0 <= nj < nz) or not walk[nl, ni, nj]:
                    continue
                if nl == layer and abs(ni - i) == 1 and abs(nj - j) == 1 and not (walk[nl, i, nj] and walk[nl, ni, j]):
                    continue
                nd = dcur + cost
                if nd < dist.get((nl, ni, nj), 1e18):
                    dist[(nl, ni, nj)] = nd
                    heapq.heappush(heap, (nd, (nl, ni, nj)))
        return dist

    def node_near(x, z, layer):
        i0, j0 = int(x - x_lo), int(z - z_lo)
        for r in range(0, 10):
            for i in range(i0 - r, i0 + r + 1):
                for j in range(j0 - r, j0 + r + 1):
                    if 0 <= i < nx and 0 <= j < nz and walk[layer, i, j]:
                        return (layer, i, j)
        return None

    points = {}
    for rec in core.PIECES:
        if rec[0] == "MainframeTerminal":
            opts = rec[6]
            sid = next(s for s in SPACES.values() if s.contains(rec[2], rec[4]) and abs(s.y0 - rec[3]) < 1).id
            s = SPACES[sid]
            fx, fz = core.to_world(rec[2], rec[4], rec[5], 0, -4.0)
            points[opts["id"]] = node_near(fx, fz, 1 if s.y0 > 10 else 0)
    sp = GAME["spawn"]["c"]
    points["SPAWN"] = node_near(sp[0], sp[2], 0)
    names = sorted(points)
    table = {}
    for a in names:
        dist = dijkstra(points[a])
        for b in names:
            table[(a, b)] = dist.get(points[b], float("inf"))
    return names, table


# ------------------------------------------------------------------------------------------------------
# Main

LIGHTING = {
    "ambient": [20, 21, 26], "outdoor": [40, 40, 50], "diffuse": 0.2, "specular": 0.45, "exposure": 0.1,
    "clock": 0.4, "brightness": 0.0,
    "atmosphere": {"density": 0.3, "offset": 0.0, "color": [150, 120, 100], "decay": [70, 60, 72], "glare": 0.0, "haze": 3.0},
    "bloom": {"intensity": 0.75, "size": 26, "threshold": 1.05},
    "grade": {"brightness": -0.02, "contrast": 0.12, "saturation": -0.22, "tint": [236, 242, 250]},
    "sky": {"stars": 0},
}

MATERIALS = [
    # MaterialVariants the map's surfaces use (the kit's own Axiom* variants come from BuildMapKit).
    {"name": "AxiomPlaster", "base": "Plaster", "id": "rbxassetid://121476907277218", "studs": 8, "pattern": "Organic"},
    {"name": "AxiomCarpet", "base": "Carpet", "id": "rbxassetid://117336682994558", "studs": 8, "pattern": "Regular"},
    {"name": "AxiomCeiling", "base": "Limestone", "id": "rbxassetid://82639719760094", "studs": 8, "pattern": "Regular"},
    {"name": "AxiomTerrazzo", "base": "Marble", "id": "rbxassetid://136805927953732", "studs": 8, "pattern": "Regular"},
    {"name": "AxiomWood", "base": "Wood", "id": "rbxassetid://134046651116553", "studs": 6, "pattern": "Regular"},
    {"name": "AxiomBlock", "base": "Brick", "id": "rbxassetid://99523333273284", "studs": 8, "pattern": "Regular"},
    {"name": "AxiomTile", "base": "CeramicTiles", "id": "rbxassetid://96050867668506", "studs": 4, "pattern": "Regular"},
    {"name": "AxiomConcrete", "base": "Concrete", "id": "rbxassetid://83948564499604", "studs": 16, "pattern": "Organic"},
    {"name": "AxiomVinyl", "base": "Slate", "id": "rbxassetid://76373198525242", "studs": 8, "pattern": "Regular"},
    {"name": "AxiomFabric", "base": "Fabric", "id": "rbxassetid://121476579890821", "studs": 3, "pattern": "Organic"},
]


def build_all():
    core.check_layout()
    if ERRORS:
        return 0
    props.build_all()
    n = core.build_structure()
    dress.dress_all()
    core.camera_links()
    core.game_rooms()
    return n


def write_layout(path, city_parts):
    data = {"version": 2, "boxes": core.BOXES, "pieces": core.PIECES, "prefabs": core.PREFABS, "game": GAME,
            "lighting": LIGHTING, "materials": MATERIALS, "city": city_parts, "weather": dress.WEATHER}
    text = json.dumps(data, separators=(",", ":"))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/map/design_map.py: the Axiom Tower map as JSON for BuildMap. Don't edit.\n")
        f.write("return [==[" + text + "]==]\n")
    return len(text)


if __name__ == "__main__":
    blocks = build_all()
    for w in WARNINGS:
        print("warning:", w)
    for e in ERRORS:
        print("ERROR:", e)
    plan = sys.argv[sys.argv.index("--plan") + 1] if "--plan" in sys.argv else os.path.join(HERE, "plan.png")
    city_parts = city.build()
    render_plan(plan)
    counts = {}
    for p in core.PIECES:
        counts[p[0]] = counts.get(p[0], 0) + 1
    prefab_parts = sum(len(core.PREFABS[k]["parts"]) * v for k, v in counts.items() if k in core.PREFABS)
    kit = {k: v for k, v in counts.items() if k not in core.PREFABS}
    print(f"{len(SPACES)} spaces, {len(ROOMS)} rooms, {len(OPENINGS)} openings; {blocks} structural blocks, "
          f"{len(core.BOXES)} boxes, {len(core.PIECES)} pieces ({len(core.PREFABS)} prefabs), {len(city_parts)} city parts")
    print("kit pieces:", ", ".join(f"{k} {v}" for k, v in sorted(kit.items(), key=lambda kv: -kv[1])))
    est = len(core.BOXES) + prefab_parts + sum(dress.KIT_PARTS.get(k, 20) * v for k, v in kit.items()) + len(city_parts)
    print(f"about {est} parts ({prefab_parts} in prefabs)")
    cams = [c["id"] for c in core.CAMERAS]
    terms = [p for p in core.PIECES if p[0] == "MainframeTerminal"]
    doors = [p for p in core.PIECES if p[1] == "Map/Doors"]
    print(f"game: {len(cams)} cameras, {len(core.DOCK_LIST)} docks, {len(doors)} doors, {len(terms)} terminals")
    if "--walk" in sys.argv and not ERRORS:
        names, table = walk_distances()
        print("walking distances (studs):")
        print("".join(f"{n:>15}" for n in [""] + names))
        for a in names:
            print(f"{a:>15}" + "".join(f"{table[(a, b)]:15.0f}" for b in names))
        close = [(a, b) for a in names for b in names if a < b and "SPAWN" not in (a, b) and table[(a, b)] < 280]
        print("terminal pairs closer than 280 studs:", close or "none")
    if "--check" not in sys.argv and not ERRORS:
        size = write_layout(os.path.join(HERE, "MapLayout.luau"), city_parts)
        print(f"wrote MapLayout.luau ({size // 1024} KB); plan: {plan}")
