#!/usr/bin/env python3
"""Designs Axiom Data Vault, the full Chimera map, from the map kit.

The layout below (spaces, rooms, openings) is the source of truth. This script checks it against the
kit's rules and the design doc's layout rules, works out every structural block and every kit piece's
placement, and writes:
  tools/map/MapLayout.luau   the placements as a JSON string; ServerStorage.DevTools.BuildMap builds them
  tools/map/plan.png         a top-down plan for review (pass --plan PATH to write it elsewhere)

Run:  python tools/map/design_map.py            (checks, then writes both files)
      python tools/map/design_map.py --check    (checks only)
      add --walk to print walking distances between the terminals and from the spawn
Needs Pillow and numpy. Then build it in Studio: require(game.ServerStorage.DevTools.BuildMap:Clone()).build()

Conventions (studs): +x is east, +z is south (north is -z), y is up; the ground floor is y = 0.
A space is a rectangle of clear floor (its four wall faces) with a floor height y0 and a ceiling height h.
Walls are 2 thick and sit outside the faces; two spaces share a wall when their faces are exactly 2 apart.
A room is what the game sees (one bounds box, one camera at least, one Lights folder); it may hold
several spaces. Every face coordinate is even, and wall-panel spans start and end on multiples of 4, so
openings (multiples of 4 wide, at multiples of 4) line up on both sides of a wall: a corner post is
2 or 4 wide to reach the grid.
"""
from __future__ import annotations

import json
import math
import os
import sys
from collections import deque
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
WALL = 2
GRID = 4

# ------------------------------------------------------------------------------------------------------
# Rooms and spaces

WINGS = {
    "CORE": (70, 110, 190),
    "INSERTION": (220, 220, 230),
    "OD": (120, 200, 210),
    "OW": (150, 150, 120),
    "FAB": (200, 120, 70),
    "SF": (70, 130, 230),
    "CP": (100, 210, 230),
    "MT": (200, 150, 80),
}


@dataclass
class Room:
    id: str
    name: str
    wing: str
    style: str
    spaces: list = field(default_factory=list)


@dataclass
class Space:
    id: str
    room: str
    x0: float
    x1: float
    z0: float
    z1: float
    h: float = 16
    y0: float = 0
    open: tuple = ()  # sides with no wall of their own: a corridor end that runs into another space's wall
    floor: str = "concrete"
    ceiling: str = "exposed"

    @property
    def w(self):
        return self.x1 - self.x0

    @property
    def d(self):
        return self.z1 - self.z0

    @property
    def top(self):
        return self.y0 + self.h

    def contains(self, x, z, margin=0.0):
        return self.x0 + margin <= x <= self.x1 - margin and self.z0 + margin <= z <= self.z1 - margin


ROOMS: dict[str, Room] = {}
SPACES: dict[str, Space] = {}


def room(id, name, wing, style):
    ROOMS[id] = Room(id, name, wing, style)


def space(id, room_id, x0, x1, z0, z1, h=16, y0=0, open=(), floor="concrete", ceiling="exposed"):
    s = Space(id, room_id, x0, x1, z0, z1, h, y0, tuple(open), floor, ceiling)
    SPACES[id] = s
    ROOMS[room_id].spaces.append(id)
    return s


# The Core: the cavernous central hub, three storeys high, with the Uplink and the finale platform.
room("CORE", "The Core", "CORE", "core")
space("CORE", "CORE", -62, 62, -62, 62, h=40, floor="polished", ceiling="exposed")

# Insertion: the lift lobby (the only well-lit room) and the freight lift the squad rides down in.
room("INSERTION", "Insertion", "INSERTION", "lobby")
space("INS", "INSERTION", -38, 38, 64, 106, h=16, floor="plate", ceiling="panels")
space("INS_LIFT", "INSERTION", -12, 12, 108, 126, h=16, open=("N",), floor="plate", ceiling="panels")

# Observation Decks: a glass gallery over the Core on the upper level, and a stair hall at each end.
room("OD_DECK", "Observation Deck", "OD", "deck")
space("OD_DECK", "OD_DECK", -38, 38, 64, 86, h=16, y0=24, floor="plate", ceiling="panels")
room("OD_STAIR_W", "West Stair Hall", "OD", "stair")
space("OD_STAIR_W", "OD_STAIR_W", -106, -40, 64, 96, h=40, floor="polished", ceiling="exposed")
room("OD_STAIR_E", "East Stair Hall", "OD", "stair")
space("OD_STAIR_E", "OD_STAIR_E", 40, 106, 64, 96, h=40, floor="polished", ceiling="exposed")

# Office Wing (west): abandoned cubicles and many doors.
room("OW_RECEPTION", "Reception", "OW", "office")
space("OW_RECEPTION", "OW_RECEPTION", -108, -64, -30, 62, h=16, floor="polished", ceiling="panels")
room("OW_CUBICLES", "Cubicle Floor", "OW", "office")
space("OW_CUBICLES", "OW_CUBICLES", -200, -110, -62, 58, h=16, floor="carpet", ceiling="panels")
room("OW_EXEC", "Executive Office", "OW", "office")
space("OW_EXEC", "OW_EXEC", -252, -202, -58, -12, h=16, floor="carpet", ceiling="panels")
room("OW_OFFICES", "Conference Room", "OW", "office")
space("OW_OFFICES", "OW_OFFICES", -252, -202, -10, 58, h=16, floor="carpet", ceiling="panels")

# Fabrication Bays (north-west): where shells are printed. Not a wing: its docks stay up until Lockdown.
room("FAB_PRINT", "Print Floor", "FAB", "fab")
space("FAB_PRINT", "FAB_PRINT", -150, -90, -148, -64, h=24, floor="tread", ceiling="exposed")
room("FAB_ASSEMBLY", "Assembly Bay", "FAB", "fab")
space("FAB_ASSEMBLY", "FAB_ASSEMBLY", -88, -32, -148, -64, h=24, floor="tread", ceiling="exposed")

# Server Farms (north): tall racks in a maze, blue glow, fans.
room("SF_RACKHALL", "Rack Hall", "SF", "server")
space("SF_RACKHALL", "SF_RACKHALL", -30, 62, -148, -64, h=24, floor="raised", ceiling="exposed")
room("SF_DATAHALL", "Data Hall", "SF", "server")
space("SF_DATAHALL", "SF_DATAHALL", -30, 62, -230, -150, h=24, floor="raised", ceiling="exposed")
room("SF_NOC", "Network Operations", "SF", "noc")
space("SF_NOC", "SF_NOC", -30, 30, -276, -232, h=16, floor="raised", ceiling="panels")

# Cooling Plant (north-east): coolant tanks, mist, cold light.
room("CP_PUMPS", "Pump Room", "CP", "plant")
space("CP_PUMPS", "CP_PUMPS", 64, 132, -108, -12, h=24, floor="concrete", ceiling="exposed")
room("CP_CHILLERS", "Chiller Hall", "CP", "plant")
space("CP_CHILLERS", "CP_CHILLERS", 64, 174, -200, -110, h=24, floor="concrete", ceiling="exposed")
room("CP_CONTROL", "Plant Control", "CP", "control")
space("CP_CONTROL", "CP_CONTROL", 100, 160, -246, -202, h=16, floor="plate", ceiling="panels")

# Maintenance Tunnels (east): narrow, full of steam pipes, the darkest wing.
room("MT_TUNNEL", "Service Tunnel", "MT", "tunnel")
space("MT_TUNNEL", "MT_TUNNEL", 64, 152, -10, 10, h=12, floor="concrete", ceiling="exposed")
room("MT_GALLERY", "Pipe Gallery", "MT", "tunnel")
space("MT_GALLERY", "MT_GALLERY", 154, 174, -30, 90, h=16, floor="concrete", ceiling="exposed")
room("MT_BOILER", "Boiler Room", "MT", "boiler")
space("MT_BOILER", "MT_BOILER", 176, 236, -30, 30, h=24, floor="concrete", ceiling="exposed")
room("MT_SOUTH", "South Tunnel", "MT", "tunnel")
space("MT_SOUTH", "MT_SOUTH", 108, 152, 72, 84, h=12, open=("W", "E"), floor="concrete", ceiling="exposed")

# ------------------------------------------------------------------------------------------------------
# Openings between spaces: (a, b, start along the wall, width, kind, door id or None, display name)
#   door   an 8 x 10 doorway with a lockable sliding door (Map/Doors)
#   frame  an 8 x 10 doorway with no door
#   wide   a 12 x 10 doorway; portal: the same, filling a corridor's open end
#   gate   a 24 x 14 doorway (the Core's gates and the big halls)


@dataclass
class Opening:
    a: str
    b: str
    at: float
    width: float
    kind: str
    door: str | None = None
    name: str = ""
    base: float | None = None  # floor height of the doorway (default: the higher of the two floors)


OPENINGS: list[Opening] = []


def opening(a, b, at, width, kind, door=None, name="", base=None):
    OPENINGS.append(Opening(a, b, at, width, kind, door, name, base))


FRAME_OF = {"door": "DoorFrame_8x10", "frame": "DoorFrame_8x10", "wide": "DoorFrame_12x10", "portal": "DoorFrame_12x10", "gate": "DoorFrame_24x14"}
OPEN_HEIGHT = {"door": 10, "frame": 10, "wide": 10, "portal": 10, "gate": 14}

# The Core's gates and doors.
opening("CORE", "INS", -12, 24, "gate")
opening("CORE", "OW_RECEPTION", -12, 24, "gate")
opening("CORE", "SF_RACKHALL", -12, 24, "gate")
opening("CORE", "FAB_ASSEMBLY", -52, 8, "door", "D_CORE_FAB", "Fabrication door")
opening("CORE", "CP_PUMPS", -48, 8, "door", "D_CORE_CP", "Pump Room door")
opening("CORE", "MT_TUNNEL", -4, 8, "door", "D_CORE_MT", "Service Tunnel door")
# Insertion and the stair halls.
opening("INS", "INS_LIFT", -12, 24, "gate")
opening("INS", "OD_STAIR_W", 80, 8, "frame")
opening("INS", "OD_STAIR_E", 80, 8, "frame")
opening("OD_STAIR_W", "OD_DECK", 72, 8, "door", "D_OD_W", "Deck west door", base=24)
opening("OD_STAIR_E", "OD_DECK", 72, 8, "door", "D_OD_E", "Deck east door", base=24)
opening("OD_STAIR_W", "OW_RECEPTION", -96, 8, "frame")
opening("OD_STAIR_E", "MT_SOUTH", 72, 12, "portal")
# Office Wing.
opening("OW_RECEPTION", "OW_CUBICLES", -4, 8, "door", "D_OW_CUBICLES", "Cubicle Floor door")
opening("OW_CUBICLES", "OW_EXEC", -40, 8, "door", "D_OW_EXEC_E", "Executive Office east door")
opening("OW_OFFICES", "OW_EXEC", -232, 8, "door", "D_OW_EXEC_S", "Executive Office south door")
opening("OW_CUBICLES", "OW_OFFICES", 20, 8, "door", "D_OW_OFFICES", "Office Row door")
# Fabrication Bays.
opening("FAB_PRINT", "FAB_ASSEMBLY", -120, 24, "gate")
opening("FAB_ASSEMBLY", "SF_RACKHALL", -112, 8, "door", "D_FAB_SF", "Rack Hall west door")
opening("FAB_PRINT", "OW_CUBICLES", -136, 8, "door", "D_FAB_OW", "Print Floor south door")
# Server Farms.
opening("SF_RACKHALL", "SF_DATAHALL", 4, 24, "gate")
opening("SF_DATAHALL", "SF_NOC", -20, 8, "door", "D_SF_NOC_W", "Network Ops west door")
opening("SF_DATAHALL", "SF_NOC", 12, 8, "door", "D_SF_NOC_E", "Network Ops east door")
opening("SF_RACKHALL", "CP_PUMPS", -96, 8, "door", "D_CP_SF", "Coolant feed door")
# Cooling Plant.
opening("CP_PUMPS", "CP_CHILLERS", 84, 24, "gate")
opening("CP_PUMPS", "MT_TUNNEL", 100, 8, "door", "D_CP_MT", "Tunnel access door")
opening("CP_CHILLERS", "CP_CONTROL", 112, 8, "door", "D_CP_CONTROL_W", "Plant Control west door")
opening("CP_CHILLERS", "CP_CONTROL", 140, 8, "door", "D_CP_CONTROL_E", "Plant Control east door")
# Maintenance Tunnels.
opening("MT_TUNNEL", "MT_GALLERY", -4, 8, "door", "D_MT_GALLERY", "Pipe Gallery door")
opening("MT_GALLERY", "MT_BOILER", -20, 8, "door", "D_MT_BOILER_N", "Boiler Room north door")
opening("MT_GALLERY", "MT_BOILER", 12, 8, "door", "D_MT_BOILER_S", "Boiler Room south door")
opening("MT_SOUTH", "MT_GALLERY", 72, 12, "portal")

# Windows: the Observation Deck looks into the Core through glass in their shared wall, one bay per
# 8 studs of wall, between deck-floor height +0.6 and +7.4.
WINDOWS = [{"a": "CORE", "b": "OD_DECK", "from": -36, "to": 36, "base": 24}]

# ------------------------------------------------------------------------------------------------------
# Geometry helpers

SIDES = {
    # side: (axis the wall runs along, inward normal, yaw in degrees for a kit piece facing into the room)
    "N": ("x", (0, 1), 180),
    "S": ("x", (0, -1), 0),
    "W": ("z", (1, 0), -90),
    "E": ("z", (-1, 0), 90),
}


def face_coord(s: Space, side: str) -> float:
    return {"N": s.z0, "S": s.z1, "W": s.x0, "E": s.x1}[side]


def side_range(s: Space, side: str) -> tuple[float, float]:
    return (s.x0, s.x1) if side in "NS" else (s.z0, s.z1)


def post_size(coord: float) -> int:
    """How far a corner post reaches from a face at `coord` to the next multiple of 4."""
    r = coord % GRID
    if r == 2:
        return 2
    if r == 0:
        return 4
    raise ValueError(f"face coordinate {coord} is not even")


def has_post(s: Space, corner: str) -> bool:
    return not any(side in s.open for side in corner)


def span(s: Space, side: str) -> tuple[float, float]:
    """The run of wall panels along a side: between the corner posts (or the open ends)."""
    lo, hi = side_range(s, side)
    a, b = ("N", "S") if side in "WE" else ("W", "E")
    # Posts at the two ends of this side: corner names are like "NW".
    lo_corner = (side + a) if side in "NS" else (a + side)
    hi_corner = (side + b) if side in "NS" else (b + side)
    lo_corner = "".join(sorted(lo_corner, key="NSWE".index))
    hi_corner = "".join(sorted(hi_corner, key="NSWE".index))
    if has_post(s, lo_corner):
        lo += post_size(lo)
    if has_post(s, hi_corner):
        hi -= post_size(hi)
    return lo, hi


def shared_wall(a: Space, b: Space):
    """Returns (side of a, side of b, wall line (centre), lo, hi) if a and b share a wall."""
    if abs(a.z1 + WALL - b.z0) < 1e-6:
        return "S", "N", a.z1 + WALL / 2, max(a.x0, b.x0), min(a.x1, b.x1)
    if abs(b.z1 + WALL - a.z0) < 1e-6:
        return "N", "S", a.z0 - WALL / 2, max(a.x0, b.x0), min(a.x1, b.x1)
    if abs(a.x1 + WALL - b.x0) < 1e-6:
        return "E", "W", a.x1 + WALL / 2, max(a.z0, b.z0), min(a.z1, b.z1)
    if abs(b.x1 + WALL - a.x0) < 1e-6:
        return "W", "E", a.x0 - WALL / 2, max(a.z0, b.z0), min(a.z1, b.z1)
    return None


ERRORS: list[str] = []
WARNINGS: list[str] = []


def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNINGS.append(msg)


def opening_base(o: Opening) -> float:
    a, b = SPACES[o.a], SPACES[o.b]
    return o.base if o.base is not None else max(a.y0, b.y0)


def opening_geometry(o: Opening):
    a, b = SPACES[o.a], SPACES[o.b]
    sw = shared_wall(a, b)
    if not sw:
        err(f"opening {o.a}-{o.b}: the spaces don't share a wall")
        return None
    side_a, side_b, line, lo, hi = sw
    return side_a, side_b, line, lo, hi


# ------------------------------------------------------------------------------------------------------
# Validation of the layout


def check_layout():
    ids = list(SPACES)
    for s in SPACES.values():
        for v in (s.x0, s.x1, s.z0, s.z1):
            if v % 2 != 0:
                err(f"{s.id}: face {v} is not even")
        if s.w <= 0 or s.d <= 0:
            err(f"{s.id}: empty rectangle")
    # No two spaces closer than a wall unless they share one exactly (spaces on different levels may stack).
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = SPACES[ids[i]], SPACES[ids[j]]
            if a.top + 1 <= b.y0 - 1 or b.top + 1 <= a.y0 - 1:
                continue  # different storeys with a slab between
            gx = max(a.x0 - b.x1, b.x0 - a.x1)
            gz = max(a.z0 - b.z1, b.z0 - a.z1)
            gap = max(gx, gz)
            if gap < WALL - 1e-6 and not (gap >= 0 and min(gx, gz) < 0 and False):
                if gx < 0 and gz < 0:
                    err(f"{a.id} and {b.id} overlap")
                elif 0 <= gap < WALL:
                    err(f"{a.id} and {b.id} are {gap} apart (walls are {WALL} thick)")
    # Openings: inside both spans, on the grid, with panels (or nothing) beside them.
    for o in OPENINGS:
        g = opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        lo_o, hi_o = o.at, o.at + o.width
        if o.width % GRID:
            err(f"opening {o.a}-{o.b} at {o.at}: width {o.width} not a multiple of {GRID}")
        if lo_o < lo or hi_o > hi:
            err(f"opening {o.a}-{o.b} at {o.at}: outside the shared wall {lo}..{hi}")
        for sid, side in ((o.a, side_a), (o.b, side_b)):
            s = SPACES[sid]
            if side in s.open:
                lo_f, hi_f = side_range(s, side)
                if (lo_o, hi_o) != (lo_f, hi_f):
                    err(f"opening {o.a}-{o.b}: {sid}'s open side {side} is {lo_f}..{hi_f}, not {lo_o}..{hi_o}")
                continue
            p0, p1 = span(s, side)
            if lo_o < p0 or hi_o > p1:
                err(f"opening {o.a}-{o.b} at {o.at}: outside {sid}'s {side} panel span {p0}..{p1}")
            for seg in (lo_o - p0, p1 - hi_o):
                if seg % GRID or 0 < seg < GRID:
                    err(f"opening {o.a}-{o.b} at {o.at}: leaves a {seg}-stud gap in {sid}'s {side} wall")
                if seg == 0:
                    err(f"opening {o.a}-{o.b} at {o.at}: right against a corner post in {sid}'s {side} wall")
        base = opening_base(o)
        for sid in (o.a, o.b):
            s = SPACES[sid]
            if base < s.y0 - 1e-6 or base + OPEN_HEIGHT[o.kind] + 2 > s.top + 1e-6:
                err(f"opening {o.a}-{o.b}: its frame doesn't fit {sid}'s height")
        if o.kind == "portal":
            if not any(side in SPACES[x].open for x, side in ((o.a, side_a), (o.b, side_b))):
                err(f"portal {o.a}-{o.b}: neither side is open")
    # Openings on the same wall must not overlap, and a door needs 8 studs of solid wall to slide into.
    by_wall: dict = {}
    for o in OPENINGS:
        g = opening_geometry(o)
        if g:
            key = (round(g[2], 3), "x" if g[0] in "NS" else "z")
            by_wall.setdefault(key, []).append(o)
    for key, lst in by_wall.items():
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                p, q = lst[i], lst[j]
                ybp, ybq = opening_base(p), opening_base(q)
                # Stacked doorways (a landing door over a ground door) may sit side by side, never in the
                # same panel columns; doorways at one height need room for both frames between them.
                margin = 2.4 if abs(ybp - ybq) <= 14 else 0
                if p.at < q.at + q.width + margin and q.at < p.at + p.width + margin:
                    err(f"openings {p.a}-{p.b} and {q.a}-{q.b} overlap on their wall")
    # Spans and open runs must be whole multiples of 4.
    for s in SPACES.values():
        for side in "NSWE":
            if side in s.open:
                continue
            p0, p1 = span(s, side)
            if (p1 - p0) % GRID:
                err(f"{s.id} {side}: panel span {p0}..{p1} is not a multiple of {GRID}")


# ------------------------------------------------------------------------------------------------------
# Output: everything the loader builds. Boxes are plain parts; pieces are kit models placed by pivot.

BOXES: list[dict] = []
PIECES: list[list] = []
POSTS: list[list] = []
GAME: dict = {"rooms": [], "cameras": [], "docks": [], "terminals": [], "stations": [], "traps": [], "lightPanels": [], "floodlights": [], "spawn": None, "platform": None}

MAT_CONCRETE = "Concrete"
COLORS = {
    "structure": (34, 36, 40),
    "polished": (44, 46, 50),
    "concrete": (52, 53, 55),
    "tread": (40, 42, 46),
    "plate": (34, 36, 40),
    "carpet": (38, 42, 50),
    "ceiling": (22, 23, 26),
    "ceilingPanel": (30, 32, 36),
    "dark": (25, 27, 31),
    "edge": (72, 77, 86),
    "plateSteel": (42, 45, 51),
    "hazard": (190, 145, 30),
}


def rnd(v, n=3):
    r = round(v, n)
    return 0.0 if r == 0 else r


def box(name, folder, x0, x1, y0, y1, z0, z1, material=MAT_CONCRETE, color="structure", variant="", **flags):
    c = COLORS[color] if isinstance(color, str) else color
    rec = {"n": name, "f": folder, "p": [rnd((x0 + x1) / 2), rnd((y0 + y1) / 2), rnd((z0 + z1) / 2)],
           "s": [rnd(x1 - x0), rnd(y1 - y0), rnd(z1 - z0)], "m": material, "c": list(c)}
    if variant:
        rec["v"] = variant
    rec.update(flags)
    BOXES.append(rec)
    return rec


def obox(name, folder, cx, cy, cz, sx, sy, sz, yaw=0.0, material="Metal", color="dark", variant="AxiomSteel", **flags):
    """A box by centre and size, turned `yaw` degrees about Y."""
    c = COLORS[color] if isinstance(color, str) else color
    rec = {"n": name, "f": folder, "p": [rnd(cx), rnd(cy), rnd(cz)], "s": [rnd(sx), rnd(sy), rnd(sz)], "m": material, "c": list(c)}
    if yaw:
        rec["r"] = rnd(yaw)
    if variant:
        rec["v"] = variant
    rec.update(flags)
    BOXES.append(rec)
    return rec


def piece(kit, folder, x, y, z, yaw=0.0, **opts):
    rec = [kit, folder, rnd(x), rnd(y), rnd(z), rnd(yaw % 360 if yaw % 360 <= 180 else yaw % 360 - 360)]
    if opts:
        rec.append(opts)
    PIECES.append(rec)
    return rec


def geo(sid):
    return f"Map/Geometry/{sid}"


def props(sid):
    return f"Map/Props/{sid}"


# ------------------------------------------------------------------------------------------------------
# Structure: the facility is a solid block with every space, doorway and window carved out of it.


def build_structure():
    import numpy as np

    x_lo = int(min(s.x0 for s in SPACES.values()) - 6)
    x_hi = int(max(s.x1 for s in SPACES.values()) + 6)
    z_lo = int(min(s.z0 for s in SPACES.values()) - 6)
    z_hi = int(max(s.z1 for s in SPACES.values()) + 6)
    y_lo, y_hi = -5.0, max(s.top for s in SPACES.values()) + 5
    ys = {y_lo, y_hi}
    for s in SPACES.values():
        ys.update((s.y0 - 1, s.top + 1))
    cuts = []  # (x0, x1, z0, z1, y0, y1)
    for o in OPENINGS:
        side_a, side_b, line, lo, hi = opening_geometry(o)
        base = opening_base(o)
        top = base + OPEN_HEIGHT[o.kind]
        if side_a in "NS":
            cuts.append((o.at, o.at + o.width, line - 1, line + 1, base, top))
        else:
            cuts.append((line - 1, line + 1, o.at, o.at + o.width, base, top))
    for wnd in WINDOWS:
        side_a, side_b, line, lo, hi = shared_wall(SPACES[wnd["a"]], SPACES[wnd["b"]])
        b0, b1 = wnd["base"] + 0.6, wnd["base"] + 7.4
        if side_a in "NS":
            cuts.append((wnd["from"], wnd["to"], line - 1, line + 1, b0, b1))
        else:
            cuts.append((line - 1, line + 1, wnd["from"], wnd["to"], b0, b1))
    for c in cuts:
        ys.update((c[4], c[5]))
    ys = sorted(ys)
    nx, nz = x_hi - x_lo, z_hi - z_lo
    slabs = []
    for ya, yb in zip(ys, ys[1:]):
        solid = np.ones((nx, nz), dtype=bool)
        for s in SPACES.values():
            if s.y0 - 1 <= ya and s.top + 1 >= yb:
                solid[int(s.x0 - x_lo):int(s.x1 - x_lo), int(s.z0 - z_lo):int(s.z1 - z_lo)] = False
        for c in cuts:
            if c[4] <= ya and c[5] >= yb:
                solid[int(c[0] - x_lo):int(c[1] - x_lo), int(c[2] - z_lo):int(c[3] - z_lo)] = False
        # Run-length rectangles: runs along z, merged across consecutive x rows.
        rects = []
        active = {}
        for i in range(nx + 1):
            runs = set()
            if i < nx:
                col = solid[i]
                j = 0
                while j < nz:
                    if col[j]:
                        k = j
                        while k < nz and col[k]:
                            k += 1
                        runs.add((j, k))
                        j = k
                    else:
                        j += 1
            for key in list(active):
                if key not in runs:
                    rects.append((active.pop(key), i, key[0], key[1]))
            for key in runs:
                if key not in active:
                    active[key] = i
        slabs.append((ya, yb, rects))
    # Merge identical rectangles in consecutive slabs into taller blocks.
    blocks = []
    open_blocks = {}
    for ya, yb, rects in slabs:
        current = {}
        for r in rects:
            if r in open_blocks and abs(open_blocks[r][1] - ya) < 1e-9:
                current[r] = (open_blocks[r][0], yb)
            else:
                current[r] = (ya, yb)
        for r, (y0, y1) in open_blocks.items():
            if r not in current or current[r][0] != y0:
                blocks.append((r, y0, y1))
        open_blocks = current
    for r, (y0, y1) in open_blocks.items():
        blocks.append((r, y0, y1))
    for (i0, i1, j0, j1), y0, y1 in blocks:
        box("Mass", "Map/Geometry/Structure", i0 + x_lo, i1 + x_lo, y0, y1, j0 + z_lo, j1 + z_lo)
    # Mullions between window bays (the cut above runs the whole window).
    for wnd in WINDOWS:
        side_a, side_b, line, lo, hi = shared_wall(SPACES[wnd["a"]], SPACES[wnd["b"]])
        b0, b1 = wnd["base"] + 0.6, wnd["base"] + 7.4
        u = wnd["from"]
        while u <= wnd["to"] + 1e-6:
            u0, u1 = max(u - 0.5, wnd["from"]), min(u + 0.5, wnd["to"])
            if side_a in "NS":
                box("Mullion", "Map/Geometry/Structure", u0, u1, b0, b1, line - 1, line + 1)
            else:
                box("Mullion", "Map/Geometry/Structure", line - 1, line + 1, b0, b1, u0, u1)
            u += 8
    return len(blocks)


# ------------------------------------------------------------------------------------------------------
# Wall lining: every wall face gets kit panels in columns 8 (or 4) wide, stacked to the ceiling.

WALL_VARIANTS = {
    # style: (16-high variants with weights, 12-high variants, upper variants)
    "core": ({"Ribbed": 4, "Plate": 3, "Vent": 2, "Screen": 1}, {"Ribbed": 2, "Plate": 2, "Vent": 1}, ["WallUpper_8x8_Ribbed", "WallUpper_8x8"]),
    "lobby": ({"Plate": 5, "Ribbed": 2, "Screen": 2, "Vent": 1}, {"Plate": 3, "Ribbed": 1}, ["WallUpper_8x8"]),
    "deck": ({"Plate": 4, "Screen": 1, "Ribbed": 1}, {"Plate": 1}, ["WallUpper_8x8"]),
    "stair": ({"Plate": 3, "Ribbed": 2, "Hazard": 1, "Vent": 1}, {"Plate": 1}, ["WallUpper_8x8", "WallUpper_8x8_Ribbed"]),
    "office": ({"Plate": 6, "Vent": 1, "Screen": 1, "Access": 1}, {"Plate": 3, "Vent": 1}, ["WallUpper_8x8"]),
    "fab": ({"Plate": 3, "Ribbed": 2, "Hazard": 2, "Vent": 2, "Access": 1}, {"Plate": 2, "Ribbed": 1}, ["WallUpper_8x8_Ribbed", "WallUpper_8x8"]),
    "server": ({"Ribbed": 4, "Vent": 4, "Plate": 1, "Screen": 1}, {"Ribbed": 2, "Vent": 2}, ["WallUpper_8x8_Ribbed", "WallUpper_8x8"]),
    "noc": ({"Plate": 3, "Screen": 2, "Ribbed": 1}, {"Plate": 2, "Screen": 1}, ["WallUpper_8x8"]),
    "plant": ({"Pipes": 4, "Plate": 2, "Vent": 2, "Hazard": 1, "Access": 1}, {"Plate": 2, "Vent": 1}, ["WallUpper_8x8", "WallUpper_8x8_Ribbed"]),
    "control": ({"Plate": 3, "Screen": 2, "Vent": 1}, {"Plate": 1}, ["WallUpper_8x8"]),
    "tunnel": ({"Pipes": 4, "Plate": 2, "Vent": 2, "Hazard": 1}, {"Plate": 3, "Vent": 2, "Ribbed": 1}, ["WallUpper_8x8"]),
    "boiler": ({"Pipes": 3, "Plate": 2, "Hazard": 2, "Vent": 1}, {"Plate": 1}, ["WallUpper_8x8", "WallUpper_8x8_Ribbed"]),
}
VARIANTS_12 = {"Plate", "Ribbed", "Vent", "Screen"}

# Per-column overrides set by dressing (a prop on the wall wants a plain panel): (space, side, u) -> variant
COLUMN_OVERRIDE: dict = {}


def hash01(*parts) -> float:
    h = 2166136261
    for ch in "|".join(str(p) for p in parts):
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h / 0xFFFFFFFF


def pick(weights: dict, *key) -> str:
    total = sum(weights.values())
    r = hash01(*key) * total
    for k, w in weights.items():
        r -= w
        if r <= 0:
            return k
    return next(iter(weights))


def wall_openings(s: Space, side: str):
    """Openings and windows on one side of a space: (u0, u1, base relative to the space, header top, kind)."""
    out = []
    for o in OPENINGS:
        for me, other in ((o.a, o.b), (o.b, o.a)):
            if me != s.id:
                continue
            g = opening_geometry(o)
            if not g:
                continue
            my_side = g[0] if me == o.a else g[1]
            if my_side != side:
                continue
            base = opening_base(o) - s.y0
            out.append((o.at, o.at + o.width, base, base + OPEN_HEIGHT[o.kind] + 2, o.kind))
    return sorted(out)


def window_bays(s: Space, side: str):
    bays = []
    for wnd in WINDOWS:
        for me in (wnd["a"], wnd["b"]):
            if me != s.id:
                continue
            g = shared_wall(SPACES[wnd["a"]], SPACES[wnd["b"]])
            my_side = g[0] if me == wnd["a"] else g[1]
            if my_side == side:
                u = wnd["from"]
                while u < wnd["to"] - 1e-6:
                    bays.append((u, u + 8, wnd["base"] - s.y0))
                    u += 8
    return bays


def columns(lo, hi, cuts):
    """Splits [lo, hi] into columns 8 wide (and 4 wide where needed) around the cut intervals."""
    cols = []
    edges = [lo]
    for c in cuts:
        edges += [c[0], c[1]]
    edges.append(hi)
    for i in range(0, len(edges), 2):
        a, b = edges[i], edges[i + 1]
        u = a
        while b - u >= 8 - 1e-6:
            cols.append((u, 8, None))
            u += 8
        if b - u >= 4 - 1e-6:
            cols.append((u, 4, None))
            u += 4
        if b - u > 1e-6:
            err(f"columns: {b - u} studs left over in {a}..{b}")
        if i // 2 < len(cuts):
            c = cuts[i // 2]
            u = c[0]
            while c[1] - u >= 8 - 1e-6:
                cols.append((u, 8, c))
                u += 8
            if c[1] - u >= 4 - 1e-6:
                cols.append((u, 4, c))
    return cols


def stack(h, start=0.0):
    """Pieces (height, is_base) filling [start, h] of a wall column."""
    out = []
    y = start
    if start == 0:
        base = 12 if h < 16 else 16
        out.append((0.0, base, True))
        y = base
    while h - y >= 8 - 1e-6:
        out.append((y, 8, False))
        y += 8
    while h - y >= 4 - 1e-6:
        out.append((y, 4, False))
        y += 4
    if h - y > 1e-6:
        err(f"stack: {h - y} studs left at the top of a wall of {h}")
    return out


def line_space(s: Space):
    room_style = ROOMS[s.room].style
    weights16, weights12, uppers = WALL_VARIANTS[room_style]
    for side in "NSWE":
        if side in s.open:
            continue
        axis, inward, yaw = SIDES[side]
        face = face_coord(s, side)
        p0, p1 = span(s, side)
        cuts = sorted(wall_openings(s, side))
        bays = window_bays(s, side)
        for u, width, cut in columns(p0, p1, cuts):
            uc = u + width / 2
            x, z = (uc, face) if axis == "x" else (face, uc)
            bay = next((b for b in bays if b[0] <= u + 1e-6 and u + width <= b[1] + 1e-6), None)
            if cut is not None:
                # A doorway column: panels below a raised doorway (a door onto a landing), fill above it.
                pieces = stack(cut[2]) if cut[2] > 1e-6 else []
                pieces += stack(s.h, start=cut[3]) if cut[3] < s.h - 1e-6 else []
            else:
                pieces = stack(s.h)
            for (y, hh, is_base) in pieces:
                window = None
                if bay and width == 8:
                    if is_base and hh == 16 and abs(y - bay[2]) < 1e-6:
                        window = "WallGlass_8x16"  # the deck side: glass from the floor
                    elif not is_base and hh == 8 and abs(y - bay[2]) < 1e-6:
                        window = "WallWindow_8x8"  # the far side: a glazed band in the wall
                if window:
                    name = window
                elif is_base:
                    override = COLUMN_OVERRIDE.get((s.id, side, u))
                    weights = weights16 if hh == 16 else weights12
                    variant = pick(weights, s.id, side, u) if width == 8 else "Plate"
                    if override == "CLEAN":
                        if variant not in CLEAN_BEHIND:
                            variant = "Plate"
                    elif override and width == 8:
                        variant = override
                    if hh != 16 and variant not in VARIANTS_12:
                        variant = "Plate"
                    name = f"WallPanel_{width}x{int(hh)}_{variant}"
                else:
                    if hh == 8 and y >= 24 - 1e-6:
                        name = f"WallUpper_{width}x8_Lite"
                    elif width == 8 and hh == 8:
                        name = uppers[0] if hash01(s.id, side, u, y) < 0.7 else uppers[-1]
                    else:
                        name = f"WallUpper_{width}x{int(hh)}"
                piece(name, geo(s.id), x, s.y0 + y, z, yaw)
        # Frames and doors: once per opening, from the lower-id space of the pair (they straddle the wall).
    # corner posts
    for corner in ("NW", "NE", "SW", "SE"):
        if not has_post(s, corner):
            continue
        cx = s.x0 if "W" in corner else s.x1
        cz = s.z0 if "N" in corner else s.z1
        px, pz = post_size(cx), post_size(cz)
        ax0, ax1 = (cx, cx + px) if "W" in corner else (cx - px, cx)
        az0, az1 = (cz, cz + pz) if "N" in corner else (cz - pz, cz)
        POSTS.append([rnd(ax0), rnd(ax1), rnd(az0), rnd(az1), rnd(s.y0), rnd(s.h), corner, s.id])


def door_slide(o: Opening, side_a, line, base) -> int:
    """Which way along the wall (+1 / -1) the door's 8-stud pocket fits inside solid wall."""
    best = None
    for direction in (1, -1):
        edge = o.at + o.width if direction > 0 else o.at
        p_lo, p_hi = (edge, edge + 8.6) if direction > 0 else (edge - 8.6, edge)
        clear = True
        for other in OPENINGS:
            if other is o:
                continue
            g = opening_geometry(other)
            if not g or abs(g[2] - line) > 1e-6 or (g[0] in "NS") != (side_a in "NS"):
                continue
            ob = opening_base(other)
            if abs(ob - base) > 12:
                continue
            if other.at - 1.2 < p_hi and other.at + other.width + 1.2 > p_lo:
                clear = False
        for s in SPACES.values():
            if s.y0 > base + 10 or s.top < base:
                continue
            if side_a in "NS":
                inside = s.x0 < p_hi and s.x1 > p_lo and s.z0 < line + 0.3 and s.z1 > line - 0.3
            else:
                inside = s.z0 < p_hi and s.z1 > p_lo and s.x0 < line + 0.3 and s.x1 > line - 0.3
            if inside:
                clear = False
        if clear:
            best = direction
            break
    if best is None:
        err(f"door {o.door}: no solid wall to slide into")
        best = 1
    return best


def place_openings():
    for o in OPENINGS:
        g = opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        base = opening_base(o)
        centre = o.at + o.width / 2
        if side_a in "NS":
            x, z, yaw = centre, line, 0
        else:
            x, z, yaw = line, centre, 90
        folder = geo(o.a if o.a < o.b else o.b)
        piece(FRAME_OF[o.kind], folder, x, base, z, yaw)
        if o.kind == "door":
            direction = door_slide(o, side_a, line, base)
            # The door's local X is world +x at yaw 0 and world -z at yaw 90.
            slide = 8 * direction if yaw == 0 else -8 * direction
            ra, rb = SPACES[o.a].room, SPACES[o.b].room
            piece("Door_8x10", "Map/Doors", x, base, z, yaw, id=o.door,
                  a={"DoorId": o.door, "TargetId": o.door, "RoomA": ra, "RoomB": rb, "DisplayName": o.name, "Slide": slide})


# ------------------------------------------------------------------------------------------------------
# Dressing helpers. Every room is dressed by the same rules: wall pieces hang on the panel sheets (0.52 in
# front of the wall), floor pieces stand 0.95 off the wall (clear of the panels' ribs), nothing stands in
# a doorway's swing, ceiling runs go wall to wall, and anything on a wall gets a plain panel behind it.

Z_SHEET = 0.52
GAP = 0.95

# Bounding size and its centre relative to the pivot, in the piece's own space (from the built kit).
KIT_DIMS = {
    "Desk_8x4": (8, 2.84, 4, 0, 1.42, 0),
    "Workstation_8x4": (8, 5.23, 6.53, 0, 2.62, -1.26),
    "PCTower": (0.91, 2.08, 2.06, 0, 1.04, -0.03),
    "OfficeChair": (2.2, 3.71, 2.23, 0, 1.85, 0.09),
    "ControlConsole_8": (8.2, 5.22, 2.64, 0, 2.61, 0.18),
    "FilingCabinet": (1.8, 4.5, 2.74, 0, 2.25, -0.07),
    "Locker_Double": (3.2, 7.4, 2.02, 0, 3.7, -0.11),
    "StorageShelf_6": (6.01, 7.0, 2.13, 0, 3.5, 0.06),
    "ServerRack_A": (2.88, 12, 4.1, 0, 6, -0.05),
    "ServerRack_B": (2.88, 12, 4.1, 0, 6, -0.05),
    "CoolingUnit": (6.1, 16, 3.28, 0, 8, -0.09),
    "CableBundle_8": (8, 0.36, 1.5, 0, 0.18, 0.1),
    "Crate_4": (4, 4, 4.05, 0, 2, -0.03),
    "CrateStack": (8.6, 8, 4.87, 0.25, 4, 0.09),
    "Barrel": (2.3, 3.55, 2.3, 0, 1.77, 0),
    "Railing_8": (8.2, 3.61, 0.6, 0, 1.8, 0),
    "MainframeTerminal": (7.59, 7.14, 3.4, 0.19, 3.57, 0.2),
    "ShellDock": (6.9, 9.55, 5.95, 0, 4.63, 0.27),
    "ChargingStation": (5.5, 6.0, 6.95, 0, 3.0, 0.73),
    "Pillar_16": (2.3, 16, 2.3, 0, 8, 0),
    "Pillar_12": (2.3, 12, 2.3, 0, 6, 0),
}
# Wall pieces: width along the wall and the height band they cover above their pivot.
WALL_DIMS = {
    "Sign_Sector": (4.3, 6.0, 8.0), "Sign_Direction": (5.3, 6.3, 7.7), "Sign_Warning": (3.3, 5.8, 8.2),
    "Sign_Restricted": (4.3, 6.0, 8.0), "Sign_Lockdown": (5.2, 8.2, 10.4),
    "WallMonitor_Map": (6.6, 6.0, 10.0), "WallMonitor_Camera": (6.6, 6.0, 10.0), "WallMonitor_Status": (6.6, 6.0, 10.0),
    "JunctionBox": (2.4, 0.0, 16.0), "PipeRun_8": (8.0, 9.2, 12.8), "PipeVertical_16": (2.3, 0.0, 16.0),
    "Light_WallCage": (1.3, 9.3, 10.7), "LightPanel": (1.9, 3.7, 16.0), "SecurityCamera": (1.0, 11.2, 13.2),
}
CLEAN_BEHIND = {"Plate", "Ribbed", "Hazard"}

FOOT: dict = {}  # space -> [(x0, x1, z0, z1, label)]
KEEPOUT: dict = {}  # space -> [(x0, x1, z0, z1)]
WALLUSE: dict = {}  # (space, side) -> [(u0, u1, y0, y1)]


def wall_xz(s: Space, side: str, u: float, d: float):
    return {"N": (u, s.z0 + d), "S": (u, s.z1 - d), "W": (s.x0 + d, u), "E": (s.x1 - d, u)}[side]


def side_yaw(side: str) -> float:
    return SIDES[side][2]


def yaw_facing(dx: float, dz: float) -> float:
    return math.degrees(math.atan2(-dx, -dz))


def to_world(x, z, yaw, lx, lz):
    a = math.radians(yaw)
    c, s_ = math.cos(a), math.sin(a)
    return x + lx * c + lz * s_, z - lx * s_ + lz * c


def footprint(kit, x, z, yaw):
    sx, sy, sz, rx, ry, rz = KIT_DIMS[kit]
    pts = [to_world(x, z, yaw, rx + ax * sx / 2, rz + az * sz / 2) for ax in (-1, 1) for az in (-1, 1)]
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return (min(xs), max(xs), min(zs), max(zs))


def overlaps(a, b, m=0.0):
    return a[0] < b[1] - m and b[0] < a[1] - m and a[2] < b[3] - m and b[2] < a[3] - m


def keepout(sid, x0, x1, z0, z1):
    KEEPOUT.setdefault(sid, []).append((min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)))


def door_keepouts():
    """Nothing may stand in front of a doorway: 8 deep and 2 wider each side."""
    for s in SPACES.values():
        for side in "NSWE":
            for (u0, u1, base, top, kind) in wall_openings(s, side):
                if base > 1e-6:
                    continue
                depth = 9 if kind in ("gate", "portal", "wide") else 7
                a = wall_xz(s, side, u0 - 2, 0)
                b = wall_xz(s, side, u1 + 2, depth)
                keepout(s.id, a[0], b[0], a[1], b[1])


def claim(sid, rect, label, check=True):
    s = SPACES[sid]
    if check:
        if rect[0] < s.x0 + 0.5 or rect[1] > s.x1 - 0.5 or rect[2] < s.z0 + 0.5 or rect[3] > s.z1 - 0.5:
            err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} pokes into a wall")
        for k in KEEPOUT.get(sid, []):
            if overlaps(rect, k, 0.05):
                err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} blocks a doorway or a path")
                break
        for f in FOOT.get(sid, []):
            if overlaps(rect, f, 0.05):
                err(f"{sid}: {label} overlaps {f[4]}")
                break
    FOOT.setdefault(sid, []).append((*rect, label))


def mark_columns_clean(s: Space, side: str, u0: float, u1: float):
    """Panels behind a prop get a plain face (no screen, vent or pipes to collide with)."""
    p0, p1 = span(s, side)
    cuts = sorted(wall_openings(s, side))
    for u, width, cut in columns(p0, p1, cuts):
        if cut is None and u < u1 and u + width > u0:
            COLUMN_OVERRIDE[(s.id, side, u)] = "CLEAN"


def wall_free(s: Space, side: str, u0: float, u1: float, y0: float, y1: float, what: str) -> bool:
    p0, p1 = span(s, side) if side not in s.open else side_range(s, side)
    if u0 < p0 - 1e-6 or u1 > p1 + 1e-6:
        err(f"{s.id} {side}: {what} at {u0:.1f}..{u1:.1f} runs off the wall ({p0}..{p1})")
        return False
    for (a, b, base, top, kind) in wall_openings(s, side):
        if u0 < b + 1.3 and u1 > a - 1.3 and y0 < top + 0.3 and y1 > base:
            err(f"{s.id} {side}: {what} at {u0:.1f}..{u1:.1f} covers a doorway frame")
            return False
    for (a, b, c, d) in WALLUSE.get((s.id, side), []):
        if u0 < b and u1 > a and y0 < d and y1 > c:
            err(f"{s.id} {side}: {what} at {u0:.1f}..{u1:.1f} overlaps another wall piece")
            return False
    return True


def on_wall(sid, side, u, kit, y=0.0, folder=None, depth=Z_SHEET, check=True, **opts):
    """A wall-mounted kit piece, hung on the panel sheets and facing into the room. `y` is its pivot height."""
    s = SPACES[sid]
    w, b0, b1 = WALL_DIMS[kit]
    if check:
        wall_free(s, side, u - w / 2, u + w / 2, s.y0 + y + b0, s.y0 + y + b1, kit)
    WALLUSE.setdefault((sid, side), []).append((u - w / 2, u + w / 2, s.y0 + y + b0, s.y0 + y + b1))
    mark_columns_clean(s, side, u - w / 2, u + w / 2)
    x, z = wall_xz(s, side, u, depth)
    return piece(kit, folder or props(sid), x, s.y0 + y, z, side_yaw(side), **opts)


def against(sid, side, u, kit, gap=GAP, folder=None, label=None, check=True, **opts):
    """A floor piece backed against a wall, facing into the room."""
    s = SPACES[sid]
    sx, sy, sz, rx, ry, rz = KIT_DIMS[kit]
    back = rz + sz / 2
    x, z = wall_xz(s, side, u, gap + back)
    yaw = side_yaw(side)
    claim(sid, footprint(kit, x, z, yaw), label or kit, check)
    mark_columns_clean(s, side, u - sx / 2, u + sx / 2)
    return piece(kit, folder or props(sid), x, s.y0, z, yaw, **opts)


def floor(sid, kit, x, z, yaw=0.0, folder=None, label=None, check=True, y=None, **opts):
    s = SPACES[sid]
    if kit in KIT_DIMS:
        claim(sid, footprint(kit, x, z, yaw), label or kit, check)
    return piece(kit, folder or props(sid), x, s.y0 if y is None else y, z, yaw, **opts)


def ceiling(sid, kit, x, z, yaw=0.0, drop=0.0, folder=None, **opts):
    s = SPACES[sid]
    return piece(kit, folder or geo(sid), x, s.top - drop, z, yaw, **opts)


def ceiling_run(sid, kit, axis, at, a=None, b=None, drop=0.0, folder=None, wall_to_wall=True):
    """8-stud ceiling pieces end to end along `axis` ("x" or "z") at cross position `at`, from a to b.
    Wall to wall, the run is lengthened (up to 2 into each wall) to a whole number of pieces."""
    s = SPACES[sid]
    lo, hi = (s.x0, s.x1) if axis == "x" else (s.z0, s.z1)
    a = lo if a is None else a
    b = hi if b is None else b
    length = b - a
    n = math.ceil(length / 8 - 1e-6)
    start = (a + b) / 2 - n * 4
    if not wall_to_wall:
        n = int(length // 8)
        start = (a + b) / 2 - n * 4
    yaw = 90 if axis == "z" else 0
    out = []
    for i in range(n):
        c = start + 8 * i + 4
        x, z = (c, at) if axis == "x" else (at, c)
        out.append(ceiling(sid, kit, x, z, yaw, drop, folder))
    return out


def rod(sid, x, z, y0, y1, folder=None):
    """A hanger rod from y0 up to y1 (a ceiling)."""
    obox("HangerRod", folder or geo(sid), x, (y0 + y1) / 2, z, 0.1, y1 - y0, 0.1, color="edge", nc=True, ns=True)


ROOM_LIGHT = {
    # room style: (colour, brightness scale, range scale)
    "lobby": ((240, 245, 255), 1.35, 1.0),
    "core": ((170, 205, 255), 1.0, 1.1),
    "deck": ((205, 225, 255), 1.15, 1.0),
    "stair": ((220, 226, 236), 1.15, 1.1),
    "office": ((236, 230, 214), 1.05, 1.1),
    "fab": ((255, 220, 180), 0.95, 1.0),
    "server": ((140, 185, 255), 0.85, 1.0),
    "noc": ((170, 200, 255), 1.0, 1.0),
    "plant": ((165, 228, 255), 1.0, 1.0),
    "control": ((180, 225, 255), 0.9, 1.0),
    "tunnel": ((255, 178, 110), 0.65, 0.85),
    "boiler": ((255, 170, 100), 0.8, 1.0),
}
BASE_LIGHT = {"Light_CeilingStrip": (24, 2.0), "Light_WallCage": (18, 1.5), "Light_Pendant": (30, 2.5)}


def light_opts(sid, kit, boost=1.0):
    r = ROOMS[SPACES[sid].room]
    colour, bscale, rscale = ROOM_LIGHT[r.style]
    rng, bright = BASE_LIGHT[kit]
    return {"c": list(colour), "brightness": rnd(bright * bscale * boost, 2), "range": rnd(rng * rscale, 1)}


def lights_folder(sid):
    return f"Facility/Lights/{SPACES[sid].room}"


def ceiling_light(sid, kit, x, z, yaw=0.0, drop=0.0, boost=1.0):
    return ceiling(sid, kit, x, z, yaw, drop, lights_folder(sid), light=light_opts(sid, kit, boost))


def wall_light(sid, side, u, y=0.0, boost=1.0):
    return on_wall(sid, side, u, "Light_WallCage", y, lights_folder(sid), light=light_opts(sid, "Light_WallCage", boost))


def strip_grid(sid, step=16, along="x", boost=1.0, skip=()):
    """Ceiling strip lights on the panel ceiling's tile centres, every `step` studs."""
    s = SPACES[sid]
    xs, _ = tile_grid(s.x0, s.x1)
    zs, _ = tile_grid(s.z0, s.z1)
    every = max(1, step // 8)
    xs = xs[(len(xs) % every) // 2::every] if len(xs) > every else xs[len(xs) // 2:len(xs) // 2 + 1]
    zs = zs[(len(zs) % every) // 2::every] if len(zs) > every else zs[len(zs) // 2:len(zs) // 2 + 1]
    for x in xs:
        for z in zs:
            if (x + 4, z + 4) in skip:
                continue
            ceiling_light(sid, "Light_CeilingStrip", x + 4, z + 4, 0 if along == "x" else 90, boost=boost)


def dead_strip(sid, x, z, yaw=0.0):
    """A dead fixture: no power, no light, just the housing (the facility is half abandoned)."""
    ceiling(sid, "Light_CeilingStrip", x, z, yaw, folder=props(sid), dead=True)


def emergency(sid, points):
    for (x, z) in points:
        ceiling(sid, "Light_Emergency", x, z, 0, 0.0, f"Facility/EmergencyLights/{SPACES[sid].room}")


# Gameplay pieces ----------------------------------------------------------------------------------------

CAMERAS: list = []
DOCK_LIST: list = []


def camera(cam_id, sid, side, u, aim, name, head=None, pan=None, tilt=None):
    s = SPACES[sid]
    head_y = head if head is not None else min(s.h - 2.2, 21)
    attrs = {"CameraId": cam_id, "Room": s.room, "DisplayName": name, "Links": ""}
    if pan:
        attrs["PanLimit"] = pan
    if tilt:
        attrs["TiltLimit"] = tilt
    rec = on_wall(sid, side, u, "SecurityCamera", head_y - 12, "Facility/Cameras", id=cam_id, a=attrs,
                  aim=[aim[0], aim[1], aim[2]])
    # Nothing bulky (a pipe run) under the camera, so its view down the room is clear.
    WALLUSE.setdefault((sid, side), []).append((u - 4.5, u + 4.5, s.y0 + head_y - 6, s.y0 + head_y - 1))
    CAMERAS.append({"id": cam_id, "room": s.room, "rec": rec})
    return rec


def dock(dock_id, sid, side, u, name):
    s = SPACES[sid]
    rec = against(sid, side, u, "ShellDock", folder="Map/Docks", label=dock_id, id=dock_id,
                  a={"DockId": dock_id, "TargetId": dock_id, "Room": s.room, "DisplayName": name})
    DOCK_LIST.append(dock_id)
    return rec


def terminal(term_id, sid, side, u, name):
    s = SPACES[sid]
    return against(sid, side, u, "MainframeTerminal", folder="Map/Terminals", label=term_id, id=term_id,
                   a={"TerminalId": term_id, "TargetId": term_id, "Room": s.room, "DisplayName": name, "Progress": 0})


def station(st_id, sid, side, u):
    return against(sid, side, u, "ChargingStation", gap=0.6, folder="Facility/Stations", label=st_id, id=st_id,
                   unpack="station", props=props(sid))


def steam_trap(trap_id, sid, side, u, y=0.0):
    s = SPACES[sid]
    fx, fz = wall_xz(s, side, u, 3.2)
    return on_wall(sid, side, u, "PipeRun_8", y, "Facility/Traps", id=trap_id, unpack="trap", target="Bonnet",
                   floor=[rnd(fx), s.y0 + 0.1, rnd(fz)],
                   a={"TrapKind": "Steam", "Room": s.room, "TargetKind": "Overload", "TargetId": trap_id})


def conduit_trap(trap_id, sid, side, u):
    s = SPACES[sid]
    fx, fz = wall_xz(s, side, u, 3.0)
    return on_wall(sid, side, u, "JunctionBox", 0, "Facility/Traps", id=trap_id, unpack="trap", target="Box",
                   floor=[rnd(fx), s.y0 + 0.1, rnd(fz)],
                   a={"TrapKind": "Conduit", "Room": s.room, "TargetKind": "Overload", "TargetId": trap_id})


def light_panel(sid, side, u):
    return on_wall(sid, side, u, "LightPanel", 0, lights_folder(sid), id="Panel", unpack="part")


def sector_sign(sid, side, u, y=0.0):
    return on_wall(sid, side, u, "Sign_Sector", y)


def direction_sign(sid, side, u, text, y=0.0):
    return on_wall(sid, side, u, "Sign_Direction", y, text=text)


# Composite props ----------------------------------------------------------------------------------------

DESK_H = 2.8


def desk_set(sid, x, z, yaw, monitors=("Status",), chair=True, tower=True, keyboard=True, extras=(), chair_turn=10.0,
             chair_back=3.2, check=True):
    """A desk with its computer: monitors on the top, a keyboard and mouse, a PC tower and a chair."""
    s = SPACES[sid]
    floor(sid, "Desk_8x4", x, z, yaw, check=check, label="desk")
    top = s.y0 + DESK_H
    spots = [(0.0, 0.85, 0.0)] if len(monitors) == 1 else [(-1.75, 0.85, -12.0), (1.25, 0.85, 12.0)]
    for (lx, lz, turn), feed in zip(spots, monitors):
        px, pz = to_world(x, z, yaw, lx, lz)
        piece(f"Monitor_{feed}", props(sid), px, top, pz, yaw + turn)
    if keyboard:
        px, pz = to_world(x, z, yaw, -0.3, -0.75)
        piece("Keyboard", props(sid), px, top, pz, yaw)
        px, pz = to_world(x, z, yaw, 1.25, -0.75)
        piece("Mouse", props(sid), px, top, pz, yaw)
    for kind in extras:
        lx, lz, turn = {"Mug": (3.2, -1.1, 20), "PaperTray": (-3.0, -0.5, 4), "Laptop": (2.3, -0.3, -14)}[kind]
        px, pz = to_world(x, z, yaw, lx, lz)
        piece(kind, props(sid), px, top, pz, yaw + turn)
    if tower:
        px, pz = to_world(x, z, yaw, -2.5, 0.55)
        piece("PCTower", props(sid), px, s.y0, pz, yaw)
    if chair:
        px, pz = to_world(x, z, yaw, -0.3, -chair_back)
        floor(sid, "OfficeChair", px, pz, yaw + 180 + chair_turn, check=check, label="chair")


def partition(sid, x0, x1, z0, z1, h=5.4):
    """A cubicle partition: a fabric panel on a steel frame with a capping rail."""
    s = SPACES[sid]
    box("Partition", props(sid), x0, x1, s.y0, s.y0 + h - 0.12, z0, z1, material="Fabric", color=(56, 60, 68))
    box("PartitionCap", props(sid), x0 - 0.04, x1 + 0.04, s.y0 + h - 0.12, s.y0 + h, z0 - 0.04, z1 + 0.04, material="Metal", color="edge", variant="AxiomSteel")


def cubicle_cluster(sid, cx, cz, seed):
    """Four desks back to back in a block of partitions, opening onto aisles north and south."""
    claim(sid, (cx - 8.6, cx + 8.6, cz - 7.2, cz + 7.2), "cubicles")
    partition(sid, cx - 8.3, cx + 8.3, cz - 0.2, cz + 0.2)
    for sz in (-1, 1):
        partition(sid, cx - 0.2, cx + 0.2, cz + sz * 0.2 if sz > 0 else cz - 6.6, cz + 6.6 if sz > 0 else cz - 0.2)
    for sx in (-1, 1):
        partition(sid, cx + sx * 8.3 - 0.2, cx + sx * 8.3 + 0.2, cz - 6.6, cz + 6.6)
    feeds = ["Status", "Log", "Off", "Squad", "Off", "Terminals", "Status", "Log"]
    for i, (sx, sz) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)]):
        yaw = 0 if sz < 0 else 180
        x, z = cx + sx * 4.1, cz + sz * 2.25
        r = hash01(sid, cx, cz, i, seed)
        mons = (feeds[int(r * 8) % 8],) if r < 0.55 else (feeds[int(r * 13) % 8], feeds[int(r * 7) % 8])
        extras = [k for k, t in (("Mug", 0.3), ("PaperTray", 0.6), ("Laptop", 0.85)) if hash01(sid, cx, cz, i, k) < t]
        desk_set(sid, x, z, yaw, monitors=mons, chair=r > 0.2, tower=r > 0.35, extras=extras,
                 chair_turn=-25 + 50 * hash01(sid, i, cz), chair_back=3.0 + 1.2 * hash01(sid, i, cx), check=False)


def row_length(n, cooler_every=0):
    return n * 2.88 + (6.1 * ((n - 1) // cooler_every) if cooler_every else 0)


def fit_racks(length, cooler_every=0):
    n = int(length // 2.88)
    while n > 0 and row_length(n, cooler_every) > length + 1e-6:
        n -= 1
    return n


def rack_row(sid, x0, n, z, yaw, tray=True, cooler_every=0, label="racks"):
    """n server racks side by side along x from x0, facing yaw (0 north, 180 south), with a cable tray above."""
    s = SPACES[sid]
    x = x0
    placed = []
    for i in range(n):
        if cooler_every and i and i % cooler_every == 0:
            floor(sid, "CoolingUnit", x + 3.05, z, yaw, label="in-row cooler")
            x += 6.1
        kit = "ServerRack_A" if (i + int(x0)) % 3 else "ServerRack_B"
        floor(sid, kit, x + 1.44, z, yaw, label=label)
        placed.append(x + 1.44)
        x += 2.88
    if tray:
        # The cable tray rides over the rack tops on rods from the ceiling.
        length = x - x0
        pieces_n = max(1, int(round(length / 8)))
        start = (x0 + x) / 2 - pieces_n * 4
        tray_top = s.y0 + 12 + 1.66
        for k in range(pieces_n):
            piece("CableTray_8", geo(sid), start + 8 * k + 4, tray_top, z + (0.9 if yaw == 0 else -0.9), 0)
        for k in range(pieces_n + 1):
            rod(sid, start + 8 * k, z + (0.9 if yaw == 0 else -0.9), tray_top, s.top)
    return x


def tank(sid, x, z, d=10.0, h=16.0):
    """A coolant tank: a steel drum on a plinth, a domed cap, a ladder, a level gauge and pipes to the roof."""
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - d / 2 - 0.8, x + d / 2 + 0.8, z - d / 2 - 0.8, z + d / 2 + 1.6), "tank")
    obox("TankPlinth", props(sid), x, y + 0.3, z, d + 1.4, 0.6, d + 1.4, material="DiamondPlate", color="plate", variant="AxiomTread")
    obox("Tank", props(sid), x, y + 0.6 + h / 2, z, h, d, d, r=[0, 0, 90], material="Metal", color=(64, 74, 82), shape="cyl")
    obox("TankBand", props(sid), x, y + 0.6 + h * 0.3, z, 0.8, d + 0.08, d + 0.08, r=[0, 0, 90], material="SmoothPlastic",
         color="hazard", variant="AxiomHazard", shape="cyl")
    obox("TankRing", props(sid), x, y + 0.6 + h * 0.7, z, 0.3, d + 0.14, d + 0.14, r=[0, 0, 90], color="dark", shape="cyl")
    obox("TankCap", props(sid), x, y + 0.6 + h + 0.5, z, 1.0, d - 1.0, d - 1.0, r=[0, 0, 90], color=(56, 64, 72), shape="cyl")
    for k, (dx, dz) in enumerate(((d * 0.25, 0), (-d * 0.25, 0))):
        obox("TankPipe", props(sid), x + dx, (y + 0.6 + h + 1 + s.top) / 2, z + dz, s.top - (y + h + 1.6), 1.2, 1.2,
             r=[0, 0, 90], material="CorrodedMetal", color=(62, 58, 54), variant="AxiomWorn", shape="cyl", nc=True)
    # Ladder on the south face.
    lz = z + d / 2 + 0.35
    for sx in (-0.55, 0.55):
        obox("LadderRail", props(sid), x + sx, y + 0.6 + h / 2, lz, 0.14, h, 0.14, color="edge", nc=True)
    for k in range(int(h // 1.2)):
        obox("LadderRung", props(sid), x, y + 1.2 + k * 1.2, lz, 1.1, 0.1, 0.1, color="edge", nc=True, ns=True)
    obox("LevelGauge", props(sid), x - 2.2, y + 0.6 + h * 0.5, z + d / 2 + 0.06, 0.5, h * 0.6, 0.12, material="Neon",
         color=(80, 200, 255), nc=True, ns=True)


def pump(sid, x, z, yaw=0.0):
    """A coolant pump skid: a base, a motor, a volute and a riser pipe."""
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - 3.4, x + 3.4, z - 2.4, z + 2.4), "pump")
    obox("PumpSkid", props(sid), x, y + 0.3, z, 6.6, 0.6, 4.4, yaw=yaw, material="DiamondPlate", color="plate", variant="AxiomTread")
    mx, mz = to_world(x, z, yaw, -1.4, 0)
    obox("PumpMotor", props(sid), mx, y + 2.1, mz, 3.2, 2.6, 2.6, r=[0, yaw, 0], color=(40, 70, 92), shape="cyl")
    vx, vz = to_world(x, z, yaw, 1.6, 0)
    obox("PumpVolute", props(sid), vx, y + 2.0, vz, 2.0, 3.0, 3.0, r=[0, yaw + 90, 0], material="CorrodedMetal",
         color=(62, 58, 54), variant="AxiomWorn", shape="cyl")
    obox("PumpRiser", props(sid), vx, (y + 3.4 + s.top) / 2, vz, s.top - y - 3.4, 1.4, 1.4, r=[0, 0, 90],
         material="CorrodedMetal", color=(62, 58, 54), variant="AxiomWorn", shape="cyl")
    obox("PumpGuard", props(sid), mx, y + 3.55, mz, 2.6, 0.3, 2.0, yaw=yaw, color="hazard", material="SmoothPlastic", variant="AxiomHazard")


def boiler(sid, x, z, length=18.0, d=9.0):
    """A horizontal boiler drum on saddles with a firebox, a burner and a flue to the roof."""
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - length / 2 - 3.5, x + length / 2 + 0.5, z - d / 2 - 0.6, z + d / 2 + 0.6), "boiler")
    for k in (-0.3, 0.3):
        obox("Saddle", props(sid), x + k * length, y + 1.5, z, 1.2, 3.0, d * 0.8, color="dark")
    obox("BoilerDrum", props(sid), x, y + 2.4 + d / 2, z, length, d, d, material="CorrodedMetal", color=(70, 62, 56),
         variant="AxiomWorn", shape="cyl")
    for k in (-0.45, 0, 0.45):
        obox("DrumBand", props(sid), x + k * length, y + 2.4 + d / 2, z, 0.4, d + 0.12, d + 0.12, color="dark", shape="cyl")
    obox("Firebox", props(sid), x - length / 2 - 1.6, y + 2.2 + d / 2, z, 3.2, d + 1.0, d + 0.4, color=(36, 34, 33), variant="AxiomSteel")
    obox("Burner", props(sid), x - length / 2 - 3.4, y + 3.4, z, 1.2, 2.2, 2.2, color="edge", shape="cyl")
    obox("BurnerGlow", props(sid), x - length / 2 - 3.25, y + 3.4, z, 0.06, 1.4, 1.4, material="Neon", color=(255, 120, 40),
         shape="cyl", nc=True, ns=True)
    obox("Flue", props(sid), x + length * 0.3, (y + 2.4 + d + s.top) / 2, z, s.top - (y + 2.4 + d), 2.0, 2.0, r=[0, 0, 90],
         material="CorrodedMetal", color=(62, 58, 54), variant="AxiomWorn", shape="cyl", nc=True)


def chassis(sid, x, z, yaw, y=None, height=1.0, folder=None):
    """A half-printed shell chassis: the R6 frame printed from the feet up to `height` (0-1)."""
    s = SPACES[sid]
    y = s.y0 if y is None else y
    f = folder or props(sid)
    dark, plate = (24, 26, 30), (46, 50, 58)

    def part(name, lx, ly, lz, sx, sy, sz, col=dark, mat="Metal"):
        if ly - sy / 2 > 5.4 * height:
            return
        wx, wz = to_world(x, z, yaw, lx, lz)
        obox(name, f, wx, y + ly, wz, sx, sy, sz, yaw=yaw, material=mat, color=col, nc=True)
    for sx in (-0.5, 0.5):
        part("LegFrame", sx, 1.0, 0, 0.5, 2.0, 0.5)
        part("ShinPlate", sx, 0.8, -0.3, 0.7, 1.0, 0.12, plate)
    part("Pelvis", 0, 2.1, 0, 2.0, 0.3, 0.6)
    part("Spine", 0, 3.0, 0.15, 0.4, 1.8, 0.4)
    part("RibFrame", 0, 3.2, 0, 1.9, 1.2, 0.2)
    part("ChestPlate", 0.45, 3.4, -0.25, 0.8, 1.0, 0.12, plate)
    part("ShoulderBar", 0, 3.95, 0, 3.6, 0.3, 0.5)
    for sx in (-1.55, 1.55):
        part("ArmFrame", sx, 3.0, 0, 0.45, 1.9, 0.45)
    part("Neck", 0, 4.3, 0, 0.3, 0.5, 0.3)
    part("HeadFrame", 0, 4.85, 0, 1.1, 0.9, 1.0)
    # The print line: a glowing seam where the head is laying down material.
    top = 5.4 * height
    wx, wz = to_world(x, z, yaw, 0, 0)
    obox("PrintSeam", f, wx, y + top, wz, 2.0, 0.06, 0.8, yaw=yaw, material="Neon", color=(255, 150, 50), nc=True, ns=True)


def print_gantry(sid, x, z, yaw=0.0):
    """A print bay: a bed, a four-post gantry with a moving bridge and a head over a half-printed chassis."""
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - 6.2, x + 6.2, z - 8.2, z + 8.2), "print bay")
    obox("PrintBed", props(sid), x, y + 0.35, z, 10.0, 0.7, 14.0, yaw=yaw, material="DiamondPlate", color="plate", variant="AxiomTread")
    obox("BedEdge", props(sid), x, y + 0.3, z, 10.6, 0.6, 14.6, yaw=yaw, material="SmoothPlastic", color="hazard", variant="AxiomHazard")
    for sx in (-1, 1):
        for sz in (-1, 1):
            px, pz = to_world(x, z, yaw, sx * 5.6, sz * 7.6)
            obox("GantryPost", props(sid), px, y + 7.5, pz, 0.8, 15.0, 0.8, yaw=yaw, color="dark")
        rx, rz = to_world(x, z, yaw, sx * 5.6, 0)
        obox("GantryRail", props(sid), rx, y + 15.3, rz, 0.9, 0.8, 16.0, yaw=yaw, color="edge")
    bx, bz = to_world(x, z, yaw, 0, -1.5)
    obox("GantryBridge", props(sid), bx, y + 14.6, bz, 12.0, 0.9, 1.2, yaw=yaw, color=(52, 56, 62))
    obox("PrintHead", props(sid), bx, y + 13.2, bz, 1.6, 1.8, 1.4, yaw=yaw, color="dark")
    obox("PrintNozzle", props(sid), bx, y + 11.9, bz, 0.4, 0.8, 0.4, yaw=yaw, material="Neon", color=(255, 150, 50), nc=True, ns=True)
    chassis(sid, x, z, yaw + 180, y=y + 0.7, height=0.55 + 0.4 * hash01(sid, x, z))


def railing_line(sid, x0, z0, x1, z1, y=None, folder=None):
    """Railing_8 pieces along a straight line (8 long each; the run is centred)."""
    s = SPACES[sid]
    length = math.hypot(x1 - x0, z1 - z0)
    n = max(1, int(length // 8))
    ux, uz = (x1 - x0) / length, (z1 - z0) / length
    yaw = math.degrees(math.atan2(-uz, ux))  # the railing's length runs along its local X
    start = length / 2 - n * 4
    for k in range(n):
        c = start + 8 * k + 4
        piece("Railing_8", folder or props(sid), x0 + ux * c, s.y0 if y is None else y, z0 + uz * c, yaw)


def wall_fill(sid, side, kit, y=0.0, step=None, skip=(), folder=None, start=None, end=None):
    """Repeats a wall piece along a side wherever the wall is free (pipe runs down a tunnel)."""
    s = SPACES[sid]
    w = WALL_DIMS[kit][0]
    step = step or w
    p0, p1 = span(s, side) if side not in s.open else side_range(s, side)
    if start is not None:
        p0 = max(p0, start)
    if end is not None:
        p1 = min(p1, end)
    u = p0 + w / 2
    placed = 0
    while u + w / 2 <= p1 + 1e-6:
        if all(abs(u - k) > w for k in skip) and quiet_free(s, side, u - w / 2, u + w / 2, s.y0 + y + WALL_DIMS[kit][1], s.y0 + y + WALL_DIMS[kit][2]):
            on_wall(sid, side, u, kit, y, folder, check=False)
            placed += 1
        u += step
    return placed


def quiet_free(s, side, u0, u1, y0, y1):
    for (a, b, base, top, kind) in wall_openings(s, side):
        if u0 < b + 1.3 and u1 > a - 1.3 and y0 < s.y0 + top + 0.3 and y1 > s.y0 + base:
            return False
    for (a, b, c, d) in WALLUSE.get((s.id, side), []):
        if u0 < b and u1 > a and y0 < d and y1 > c:
            return False
    return True


def steps(sid, x_bottom, x_top, z0, z1, rise=24, folder=None):
    """A solid stair along x from x_bottom (floor) up to x_top (rise studs up), z0..z1 wide."""
    s = SPACES[sid]
    f = folder or geo(sid)
    d = 1 if x_top > x_bottom else -1
    run = abs(x_top - x_bottom) / rise
    for i in range(1, rise + 1):
        a = x_bottom + d * (i - 1) * run
        b = x_bottom + d * i * run
        # The steps are for the eye; an invisible ramp through their nosings carries mercs and shells (a
        # shell's controller steps up 1.1 at most and can miss a riser of exactly 1). The top step is solid.
        flags = {} if i == rise else {"nc": True}
        box("Step", f, min(a, b), max(a, b), s.y0, s.y0 + i, z0, z1, material="DiamondPlate", color=(40, 42, 46), variant="AxiomTread", **flags)
        nose = a + d * 0.2
        box("Nosing", f, min(nose - 0.2, nose + 0.2), max(nose - 0.2, nose + 0.2), s.y0 + i, s.y0 + i + 0.03, z0 + 0.3, z1 - 0.3,
            material="SmoothPlastic", color="hazard", variant="AxiomHazard", nc=True)
    lo_x, hi_x = x_bottom - d * run, x_top - d * run
    obox("StairRamp", f, (lo_x + hi_x) / 2, s.y0 + rise / 2, (z0 + z1) / 2, z1 - z0, rise, abs(hi_x - lo_x),
         yaw=90 if d > 0 else -90, material="SmoothPlastic", color="dark", variant="", wedge=True, t=1, ns=True)
    # The stringer and handrail on the open side.
    zo = z0 - 0.15
    angle = math.degrees(math.atan2(rise, abs(x_top - x_bottom)))
    length = math.hypot(rise, x_top - x_bottom)
    cx = (x_bottom + x_top) / 2
    obox("Stringer", f, cx, s.y0 + rise / 2 + 0.2, zo, length + 1.0, 1.4, 0.3, r=[0, 0, angle * d], color="dark")
    obox("Handrail", f, cx, s.y0 + rise / 2 + 3.6, zo, length, 0.22, 0.22, r=[0, 0, angle * d], color=(150, 115, 30), shape="cyl")
    obox("MidRail", f, cx, s.y0 + rise / 2 + 1.9, zo, length, 0.14, 0.14, r=[0, 0, angle * d], color="dark", shape="cyl", nc=True)
    for k in range(0, rise + 1, 4):
        px = x_bottom + d * k * run
        obox("Baluster", f, px, s.y0 + k + 1.8, zo, 0.2, 3.6, 0.2, color="dark")


# ------------------------------------------------------------------------------------------------------
# Room by room.


def dress_core():
    sid = "CORE"
    s = SPACES[sid]
    keepout(sid, -21, 21, -21, 21)
    # The finale platform: a striped plinth under floor plates, and its hold zone.
    box("PlatformPlinth", geo(sid), -20, 20, 0, 0.6, -20, 20, material="SmoothPlastic", color="hazard", variant="AxiomHazard")
    for i in range(5):
        for j in range(5):
            piece("FloorPlate_8x8", geo(sid), -16 + 8 * i, 0.6, -16 + 8 * j, 0)
    GAME["platform"] = {"c": [0, 6, 0], "s": [40, 12, 40]}
    # The Uplink: a steel core to the roof, racks round its base, glowing data lines up its corners.
    U = 6
    box("UplinkCore", geo(sid), -U, U, 0.8, 40, -U, U, material="Metal", color=(20, 22, 26), variant="AxiomSteel")
    for face, (nx, nz) in {"N": (0, -1), "S": (0, 1), "W": (-1, 0), "E": (1, 0)}.items():
        yaw = yaw_facing(nx, nz)
        for k, off in enumerate((-4.32, -1.44, 1.44, 4.32)):
            px = nx * (U + 2.05) + (off if nz else 0)
            pz = nz * (U + 2.05) + (off if nx else 0)
            piece("ServerRack_A" if k % 2 else "ServerRack_B", props(sid), px, 0.8, pz, yaw)
        for (off, w) in ((-2.0, 8), (4.0, 4)):
            for row, hh in ((12.8, 8), (20.8, 8), (28.8, 8)):
                px = nx * U + (off if nz else 0)
                pz = nz * U + (off if nx else 0)
                piece("WallUpper_8x8_Ribbed" if (w == 8 and row == 20.8) else f"WallUpper_{w}x{hh}", geo(sid), px, row, pz, yaw)
    for sx in (-1, 1):
        for sz in (-1, 1):
            obox("DataLine", geo(sid), sx * (U + 0.47), 24.6, sz * (U + 0.47), 0.9, 24, 0.9, material="Neon", color=(60, 140, 255), nc=True, ns=True)
    box("UplinkCollar", geo(sid), -U - 1.2, U + 1.2, 36.8, 40, -U - 1.2, U + 1.2, material="Metal", color="dark", variant="AxiomSteel")
    box("UplinkHalo", geo(sid), -U - 1.0, U + 1.0, 12.4, 12.8, -U - 1.0, U + 1.0, material="Neon", color=(60, 140, 255), nc=True, ns=True)
    # The Purge console faces the Uplink from the south edge of the platform.
    piece("ControlConsole_8", props(sid), 0, 0.8, 14.6, 180)
    # Cable trenches from each gate to the platform.
    for c in (24, 32, 40, 48, 56):
        for (x, z) in ((0, c), (0, -c), (-c, 0)):
            piece("FloorGrate_8x8", geo(sid), x, 0, z, 0)
        piece("FloorGrate_8x8", geo(sid), c, 0, 0, 0)
    # Four rack islands, one per quadrant, each a contained cold aisle with a cooler at its outer end.
    for (cx, cz) in ((40, -40), (-40, -40), (40, 40), (-40, 40)):
        rack_row(sid, cx - 5.76, 4, cz - 6.1, 180, label="island")
        rack_row(sid, cx - 5.76, 4, cz + 6.1, 0, label="island")
        outer = 1 if cx > 0 else -1
        floor(sid, "CoolingUnit", cx + outer * (5.76 + 1.75), cz, yaw_facing(-outer, 0), label="island cooler")
        for gx in (-4, 4):
            piece("FloorGrate_8x8", geo(sid), cx + gx, 0, cz, 0)
    # The light rig: a square truss on rods at y 28, pendants under it, floodlights at its corners.
    R = 32
    for side_c in (-R, R):
        for k in range(8):
            c = -28 + 8 * k
            piece("CeilingBeam_8", geo(sid), c, 28, side_c, 0)
            piece("CeilingBeam_8", geo(sid), side_c, 28, c, 90)
    for a in (-R, -16, 0, 16, R):
        for b in (-R, R):
            rod(sid, a, b, 28, 40)
            if abs(a) != R:
                rod(sid, b, a, 28, 40)
    for c in (-24, -8, 8, 24):
        for side_c in (-R, R):
            ceiling(sid, "Light_Pendant", c, side_c, 0, 40 - 26, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
            ceiling(sid, "Light_Pendant", side_c, c, 0, 40 - 26, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    for sx in (-1, 1):
        for sz in (-1, 1):
            piece("Floodlight", "Facility/Floodlights", sx * R, 24.5, sz * R, 0, id="Floodlight", unpack="part", look=[0, 1, 0])
    # Wall lamps light the walkways along the walls.
    for side in "NSWE":
        for u in (-36, 36):
            wall_light(sid, side, u, 0)
    # Docks, cameras, the station and the trap.
    dock("DOCK_CORE_NE", sid, "N", 26, "Core dock north-east")
    dock("DOCK_CORE_SW", sid, "S", -26, "Core dock south-west")
    camera("CORE_NE", sid, "E", -55, (-6, 2, 8), "Core north-east", head=33)
    camera("CORE_SW", sid, "W", 55, (6, 2, -8), "Core south-west", head=33)
    camera("CORE_SE", sid, "S", 55, (-10, 2, -6), "Core south-east", head=33)
    station("STATION_CORE", sid, "E", 24)
    conduit_trap("TRAP_CORE", sid, "W", -28)
    light_panel(sid, "S", -17)
    sector_sign(sid, "S", 20)
    for side, u in (("S", 0), ("N", 0), ("W", 0)):
        on_wall(sid, side, u, "Sign_Lockdown", 8.5)
    direction_sign(sid, "N", -22, "SERVER FARMS  >")
    direction_sign(sid, "W", 22, "OFFICE WING  >")
    direction_sign(sid, "S", 26, "INSERTION  >")
    direction_sign(sid, "E", 12, "<  MAINTENANCE")
    direction_sign(sid, "E", -32, "<  COOLING PLANT")
    direction_sign(sid, "N", -38, "<  FABRICATION")


def dress_insertion():
    sid = "INS"
    s = SPACES[sid]
    strip_grid(sid, step=8, along="x")
    # The lift car: bumper rails, a floor display, its own lights; the squad spawns inside it.
    lift = "INS_LIFT"
    for side in "WE":
        against(lift, side, 118, "Railing_8", check=False)
    on_wall(lift, "S", 0, "WallMonitor_Status", 1.0)
    on_wall(lift, "W", 112, "Sign_Warning", 0, text="FREIGHT LIFT\nB4 · AXIOM")
    ceiling_light(lift, "Light_CeilingStrip", 0, 113, 0, boost=1.1)
    ceiling_light(lift, "Light_CeilingStrip", 0, 121, 0, boost=1.1)
    GAME["spawn"] = {"c": [0, 0.3, 117.5], "s": [16, 12], "yaw": 180}
    for x in (-8, 0, 8):
        piece("FloorHazard_8x1", geo(sid), x, 0.2, 103.5, 0)
    # Lockers for the squad along both side walls, a security desk by the Core gate, supplies.
    for side in "WE":
        for u in (92.8, 96.0, 99.2, 102.4):
            against(sid, side, u, "Locker_Double")
        against(sid, side, 70, "Locker_Double")
    desk_set(sid, -24, 72, 0, monitors=("Camera", "Status"), extras=("Mug",))
    against(sid, "N", 30, "StorageShelf_6")
    floor(sid, "CrateStack", 26, 0 + 77, 180)
    floor(sid, "Crate_4", 19, 98, 15)
    on_wall(sid, "N", -27, "WallMonitor_Map")
    on_wall(sid, "N", 21, "WallMonitor_Status")
    station("STATION_INSERTION", sid, "S", -26)
    light_panel(sid, "S", 26)
    sector_sign(sid, "N", -18)
    direction_sign(sid, "W", 95, "OFFICE WING · DECK  >", y=2.0)
    direction_sign(sid, "E", 95, "<  MAINTENANCE · DECK", y=2.0)
    camera("INSERTION", sid, "N", 33, (0, 2, 112), "Insertion")


def dress_deck():
    sid = "OD_DECK"
    strip_grid(sid, step=16, along="x")
    terminal("TERM_OD", sid, "S", 0, "Observation Deck terminal")
    for u in (-26, -10, 10, 26):
        against(sid, "N", u, "ControlConsole_8", gap=2.0)
        x, z = u - 0.3, SPACES[sid].z0 + 2.0 + 2.64 + 2.8
        floor(sid, "OfficeChair", x, z, 0 + 8 * (1 if u > 0 else -1), label="console chair")
    on_wall(sid, "S", -18, "WallMonitor_Camera", feed="Camera", cameraId="CORE_NE")
    on_wall(sid, "S", 18, "WallMonitor_Camera", feed="Camera", cameraId="CORE_SW")
    for u in (-33, 33):
        against(sid, "S", u, "FilingCabinet")
    light_panel(sid, "S", -28)
    sector_sign(sid, "S", 28)
    camera("OD_DECK", sid, "S", -35, (14, 26, 70), "Observation Deck")
    emergency(sid, ((-20, 76), (20, 76)))


def dress_stair(sid, d):
    """A stair hall: d = +1 when the stair climbs east (west hall), -1 when it climbs west (east hall)."""
    s = SPACES[sid]
    x_in = s.x1 if d > 0 else s.x0
    x_top = x_in - d * 18
    x_bot = x_top - d * 36
    keepout(sid, min(x_bot - d, x_top), max(x_bot - d, x_top), 86, 96)  # the stair and a stud at its foot
    steps(sid, x_bot, x_top, 87, 95, rise=24)
    # The landing in front of the deck door, on a beam and two columns.
    lo, hi = sorted((x_top, x_in))
    box("Landing", geo(sid), lo, hi, 23, 24, s.z0, s.z1, material="DiamondPlate", color=(40, 42, 46), variant="AxiomTread")
    piece("CeilingBeam_8", geo(sid), x_top + d * 0.6, 23, 70, 90)
    piece("CeilingBeam_8", geo(sid), x_top + d * 0.6, 23, 78, 90)
    for zc in (66.5, 89.0):
        obox("LandingColumn", geo(sid), x_top + d * 1.0, 11.5, zc, 1.2, 23, 1.2, color="dark")
        claim(sid, (x_top + d * 1.0 - 0.6, x_top + d * 1.0 + 0.6, zc - 0.6, zc + 0.6), "landing column")
    railing_line(sid, x_top + d * 0.3, s.z0 + 1.2, x_top + d * 0.3, 86.6, y=24)
    # A dock at the foot of the hall, storage under the landing.
    xd = (x_bot + (s.x0 if d > 0 else s.x1)) / 2
    dock("DOCK_OD_W" if d > 0 else "DOCK_OD_E", sid, "N", -76 if d > 0 else 76, "West stair dock" if d > 0 else "East stair dock")
    against(sid, "N", x_top + d * 9.5, "StorageShelf_6")
    # Lamps at ground level and on the landing.
    for u in ((-62, -86) if d > 0 else (62, 86)):
        wall_light(sid, "N", u, 0)
    wall_light(sid, "W" if d < 0 else "E", 69, 24)
    wall_light(sid, "N", x_in - d * 10, 24)
    wall_light(sid, "W" if d > 0 else "E", 84 if d > 0 else 87, 0)
    wall_light(sid, "S", x_in - d * 12, 24)
    light_panel(sid, "N", -100 if d > 0 else 100)
    direction_sign(sid, "N", (-66 if d > 0 else 66), "OBSERVATION DECK  >" if d > 0 else "<  OBSERVATION DECK", y=1.5)
    sector_sign(sid, "N", x_in - d * 8, y=24)
    cam_side = "W" if d > 0 else "E"
    camera(sid, sid, cam_side, 70, (x_top, 10, 80), "West stair hall" if d > 0 else "East stair hall", head=30)
    emergency(sid, ((x_in - d * 9, 78), (xd, 72)))


def dress_reception():
    sid = "OW_RECEPTION"
    strip_grid(sid, step=16, along="z")
    dead_strip(sid, -86, 44, 90)
    # The reception counter faces the Core gate; the waiting area sits by the stairs.
    desk_set(sid, -96, -20, 0, monitors=("Status",), extras=("PaperTray",))
    desk_set(sid, -88, -20, 0, monitors=("Log", "Status"), extras=("Mug",))
    desk_set(sid, -80, -20, 0, monitors=("Off",), chair=False)
    for x in (-101, -97, -93, -89):
        for z in (30, 36):
            floor(sid, "OfficeChair", x, z, 0 + 6 * hash01(x, z) - 3, label="waiting chair")
    floor(sid, "Desk_8x4", -95, 42.5, 0, label="waiting table", strip=["Grommet"])
    for u in (-102, -99.6, -97.2):
        against(sid, "N", u, "FilingCabinet")
    on_wall(sid, "W", -20, "WallMonitor_Map")
    station("STATION_RECEPTION", sid, "N", -72)
    conduit_trap("TRAP_RECEPTION", sid, "W", 40)
    light_panel(sid, "E", 18)
    sector_sign(sid, "E", -18)
    direction_sign(sid, "S", -78, "INSERTION · DECK  >")
    camera("OW_RECEPTION", sid, "E", 56, (-90, 2, 4), "Reception")
    emergency(sid, ((-86, -10), (-86, 40)))


def dress_cubicles():
    sid = "OW_CUBICLES"
    s = SPACES[sid]
    keepout(sid, s.x0, s.x1, -7, 7)  # the main aisle from Reception to the back offices
    keepout(sid, -138, -126, s.z0, s.z1)  # the aisle from the Print Floor door
    for i, cx in enumerate((-184, -160)):
        for j, cz in enumerate((-46, -24, 22, 44)):
            cubicle_cluster(sid, cx, cz, i * 4 + j)
    # Along the east wall: the dock, filing, a printer table.
    dock("DOCK_OW_CUBE", sid, "E", -40, "Cubicle Floor dock")
    for u in (-24.0, -21.6, 16.0, 18.4, 20.8):
        against(sid, "E", u, "FilingCabinet")
    desk_set(sid, -116.5, 38, -90, monitors=("Off",), chair=False, keyboard=False, extras=("PaperTray",))
    against(sid, "E", 52, "StorageShelf_6")
    against(sid, "N", -150, "StorageShelf_6")
    against(sid, "N", -120, "FilingCabinet")
    conduit_trap("TRAP_CUBICLES", sid, "S", -132)
    light_panel(sid, "E", 12)
    sector_sign(sid, "E", -12)
    on_wall(sid, "W", -26.4, "Sign_Restricted")
    camera("OW_CUBICLES", sid, "N", -114, (-165, 2, 8), "Cubicle Floor")
    # Rows of strips over the aisles, a few of them dead.
    for x in (-188, -172, -156, -140, -124):
        for z in (-48, -32, -16, 0, 16, 32, 48):
            if hash01(sid, x, z) < 0.18:
                dead_strip(sid, x, z, 90)
            else:
                ceiling_light(sid, "Light_CeilingStrip", x, z, 90)
    emergency(sid, ((-150, -40), (-150, 0), (-150, 40)))


def dress_exec():
    sid = "OW_EXEC"
    strip_grid(sid, step=16, along="x")
    terminal("TERM_OW", sid, "W", -35, "Executive Office terminal")
    desk_set(sid, -224, -47, 0, monitors=("Status", "Upload"), extras=("Mug", "PaperTray"))
    for x in (-226, -221):
        floor(sid, "OfficeChair", x, -40, 180 + 15 * (x + 223), label="visitor chair")
    against(sid, "N", -236, "StorageShelf_6")
    for u in (-52, -49.6):
        against(sid, "E", u, "FilingCabinet")
    on_wall(sid, "N", -212, "WallMonitor_Status")
    COLUMN_OVERRIDE[(sid, "S", -248)] = "Access"
    light_panel(sid, "E", -28)
    sector_sign(sid, "E", -22.5)
    camera("OW_EXEC", sid, "S", -206, (-238, 2, -38), "Executive Office")
    emergency(sid, ((-226, -34),))


def dress_conference():
    sid = "OW_OFFICES"
    strip_grid(sid, step=16, along="x")
    dead_strip(sid, -214, 6, 0)
    # A long table of desks with chairs round it, a presentation screen on the west wall.
    for x in (-236, -228, -220):
        floor(sid, "Desk_8x4", x, 22, 0, label="table", strip=["Grommet"])
        floor(sid, "Desk_8x4", x, 26, 180, label="table", strip=["Grommet"])
        for z, yaw in ((17.6, 0), (30.4, 180)):
            floor(sid, "OfficeChair", x + 0.5 * hash01(x, z), z, yaw + 180 + 20 * (hash01(z, x) - 0.5), label="table chair")
        piece("Laptop", props(sid), x + 1.5, DESK_H, 21.4, 180 + 10 * hash01(x))
    on_wall(sid, "W", 24, "WallMonitor_Map")
    for u in (-226, -232.4):
        against(sid, "S", u, "StorageShelf_6" if u == -226 else "FilingCabinet")
    dock("DOCK_OW_CONF", sid, "S", -212, "Conference Room dock")
    light_panel(sid, "E", 32)
    sector_sign(sid, "E", 14)
    camera("OW_OFFICES", sid, "N", -206, (-234, 2, 30), "Conference Room")
    emergency(sid, ((-226, 6), (-226, 44)))


def dress_fab():
    for sid in ("FAB_PRINT", "FAB_ASSEMBLY"):
        s = SPACES[sid]
        for x in [s.x0 + 12 + 16 * k for k in range(int((s.w - 8) // 16))]:
            for z in (-136, -120, -104, -88, -72):
                ceiling(sid, "Light_Pendant", x, z, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    # Print Floor: two print bays under gantries, chassis racks along the west wall, a crane overhead.
    sid = "FAB_PRINT"
    keepout(sid, -120, -90, -122, -94)  # the walkway from the Assembly Bay gate
    print_gantry(sid, -129, -128)
    print_gantry(sid, -129, -97)
    for u in (-136, -128, -104, -96):
        against(sid, "W", u, "StorageShelf_6")
    floor(sid, "CrateStack", -100, -138, 0)
    floor(sid, "Barrel", -94.5, -131, 0)
    floor(sid, "Barrel", -96.8, -128.6, 0)
    for x in (-112, -104, -96):
        piece("FloorHazard_8x1", geo(sid), x, 0, -88.5, 0)
    for side_x in (-142, -116):
        ceiling_run(sid, "CeilingBeam_8", "z", side_x)
    dock("DOCK_FAB_A", sid, "N", -108, "Print Floor dock")
    conduit_trap("TRAP_FAB", sid, "N", -140)
    light_panel(sid, "S", -122)
    sector_sign(sid, "S", -142)
    camera("FAB_PRINT", sid, "S", -94.5, (-124, 2, -112), "Print Floor")
    # Assembly Bay: workbenches with chassis on stands, parts shelving, crates by the Core door.
    sid = "FAB_ASSEMBLY"
    keepout(sid, -88, -40, -122, -94)
    for x in (-76, -60):
        desk_set(sid, x, -138, 180, monitors=("Status",), chair=True, tower=False, keyboard=False, extras=("Laptop", "PaperTray"))
    for (x, z) in ((-72, -82), (-60, -82), (-48, -82)):
        obox("ChassisStand", props(sid), x, 0.4, z, 3.2, 0.8, 3.2, material="DiamondPlate", color="plate", variant="AxiomTread")
        claim(sid, (x - 1.8, x + 1.8, z - 1.8, z + 1.8), "chassis stand")
        chassis(sid, x, z, 180, y=0.8, height=0.75 + 0.25 * hash01(x))
    for u in (-140, -132, -84, -76):
        against(sid, "E", u, "StorageShelf_6")
    floor(sid, "CrateStack", -80, -70.5, 0)
    floor(sid, "Crate_4", -66, -70, 12)
    dock("DOCK_FAB_B", sid, "N", -46, "Assembly Bay dock")
    light_panel(sid, "S", -40)
    sector_sign(sid, "S", -60)
    camera("FAB_ASSEMBLY", sid, "E", -142, (-62, 2, -100), "Assembly Bay")


def dress_rackhall():
    sid = "SF_RACKHALL"
    s = SPACES[sid]
    keepout(sid, -4.6, 25.1, s.z0, s.z1)  # the main walkway, gate to gate
    for (cz_cold, rows) in ((-134, True), (-86, True), (-110, False)):
        north, south = cz_cold - 6.1, cz_cold + 6.1
        if rows:
            rack_row(sid, -22, 6, north, 180)
            rack_row(sid, -22, 6, south, 0)
            rack_row(sid, 30.4, 6, north, 180, cooler_every=4)
            rack_row(sid, 30.4, 6, south, 0, cooler_every=4)
            for x in (-24, -16, -8):
                FLOOR_TILE[(sid, x - 4, cz_cold - 4)] = "FloorGrate_8x8"
            for x in (28, 36, 44, 52):
                FLOOR_TILE[(sid, x - 4, cz_cold - 4)] = "FloorGrate_8x8"
    # The middle row is half built: racks to the west, a pair of CRAC units in the walkway's lee.
    rack_row(sid, -22, 6, -116.1, 180)
    for u in (-14, 44):
        against(sid, "N", u, "CoolingUnit")
    against(sid, "S", 40, "CoolingUnit")
    floor(sid, "CoolingUnit", 40, -110, 0)
    floor(sid, "CoolingUnit", 46.1 + 0.1, -110, 0)
    for z in (-144, -128, -112, -96, -80):
        for x in (2, 18):
            ceiling(sid, "Light_Pendant", x, z, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    for x in (-13, 38):
        ceiling(sid, "Light_Pendant", x, -122, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
        ceiling(sid, "Light_Pendant", x, -98, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    ceiling_run(sid, "CeilingDuct_8", "z", 10)
    dock("DOCK_SF_RACK", sid, "W", -98, "Rack Hall dock")
    station("STATION_RACKHALL", sid, "S", 30)
    conduit_trap("TRAP_RACK", sid, "E", -76)
    light_panel(sid, "S", 16)
    sector_sign(sid, "S", 22)
    direction_sign(sid, "N", -4, "<  DATA HALL · NOC", y=2.0)
    camera("SF_RACKHALL", sid, "S", -26.5, (16, 2, -112), "Rack Hall")
    emergency(sid, ((10, -136), (10, -104), (10, -76)))


def dress_datahall():
    sid = "SF_DATAHALL"
    s = SPACES[sid]
    # Two contained aisles broken into a maze: each row has gaps in different places.
    gaps = {-210: [(4, 12), (36, 44)], -186: [(-28, -18), (20, 28)]}
    for cz_cold, gap in ((-210, gaps[-210]), (-186, gaps[-186])):
        segs = []
        x = -26
        for (g0, g1) in gap + [(52, 52)]:
            if g0 > x:
                segs.append((x, g0))
            x = max(x, g1)
        for (a, b) in segs:
            n = fit_racks(b - a, 6)
            if n <= 0:
                continue
            rack_row(sid, a, n, cz_cold - 6.1, 180, cooler_every=6)
            rack_row(sid, a, n, cz_cold + 6.1, 0, cooler_every=6)
        for xt in range(-28, 60, 8):
            if not any(g0 <= xt + 4 < g1 for (g0, g1) in gap):
                FLOOR_TILE[(sid, xt, cz_cold - 4)] = "FloorGrate_8x8"
    # Coolers along the south walkway and the north wall break the long lines.
    for u in (-16, 44):
        against(sid, "S", u, "CoolingUnit")
    for u in (28, 40, 52):
        against(sid, "N", u, "CoolingUnit")
    floor(sid, "CrateStack", -20, -160, 90)
    for z in (-222, -198, -174, -160):
        for x in (-14, 10, 34, 54):
            ceiling(sid, "Light_Pendant", x, z, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    dock("DOCK_SF_DATA", sid, "W", -170, "Data Hall dock")
    conduit_trap("TRAP_DATA", sid, "E", -168)
    light_panel(sid, "S", 34)
    sector_sign(sid, "S", -2)
    direction_sign(sid, "N", 4, "<  NETWORK OPERATIONS  >", y=1.0)
    camera("SF_DATAHALL", sid, "S", 58.5, (10, 2, -196), "Data Hall")
    emergency(sid, ((16, -218), (16, -170)))


def dress_noc():
    sid = "SF_NOC"
    strip_grid(sid, step=16, along="x")
    terminal("TERM_SF", sid, "N", 0, "Network Operations terminal")
    on_wall(sid, "N", -16, "WallMonitor_Map")
    on_wall(sid, "N", 16, "WallMonitor_Camera", feed="Camera", cameraId="SF_DATAHALL")
    for x in (-17, 17):
        floor(sid, "ControlConsole_8", x, -258, 180, label="console")
        floor(sid, "OfficeChair", x - 0.4, -253.6, 4 * (1 if x > 0 else -1), label="console chair")
    desk_set(sid, -24, -268, 90, monitors=("Terminals", "Log"), extras=("Mug",))
    desk_set(sid, 24, -268, -90, monitors=("Squad", "Status"))
    COLUMN_OVERRIDE[(sid, "W", -264)] = "Access"
    light_panel(sid, "S", -6)
    sector_sign(sid, "S", 4)
    camera("SF_NOC", sid, "S", -26.5, (6, 2, -262), "Network Operations")
    emergency(sid, ((0, -246),))


def dress_pumps():
    sid = "CP_PUMPS"
    s = SPACES[sid]
    keepout(sid, 84, 108, s.z0, s.z0 + 10)
    for x in (84, 100, 116):
        pump(sid, x, -64, 0)
    # A header pipe over the pumps, and coolant runs on the east wall.
    obox("Header", props(sid), 98, 15.5, -64, 44, 2.0, 2.0, material="CorrodedMetal", color=(62, 58, 54), variant="AxiomWorn", shape="cyl", nc=True)
    railing_line(sid, 78, -59.4, 122, -59.4)
    wall_fill(sid, "E", "PipeRun_8", 0, skip=(-40, -90))
    against(sid, "W", -28, "StorageShelf_6")
    floor(sid, "Barrel", 70, -20, 0)
    floor(sid, "Barrel", 72.5, -22.2, 0)
    for x in (80, 96, 112):
        for z in (-96, -80, -48, -28):
            ceiling(sid, "Light_Pendant", x, z, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    ceiling_run(sid, "CeilingPipes_8", "z", 124)
    dock("DOCK_CP_PUMPS", sid, "E", -90, "Pump Room dock")
    steam_trap("TRAP_PUMPS", sid, "E", -40)
    light_panel(sid, "W", -36)
    sector_sign(sid, "W", -55)
    camera("CP_PUMPS", sid, "E", -103.5, (92, 2, -58), "Pump Room")
    emergency(sid, ((98, -90), (98, -36)))


def dress_chillers():
    sid = "CP_CHILLERS"
    s = SPACES[sid]
    keepout(sid, 82, 110, -124, -110)
    for x in (92, 116, 140):
        tank(sid, x, -178)
    for x in (92, 116, 140):
        railing_line(sid, x - 6, -170.6, x + 6, -170.6)
    for u in (124, 132, 148, 156):
        against(sid, "S", u, "CoolingUnit")
    for x in (80, 100, 120, 140, 160):
        for z in (-190, -160, -130):
            ceiling(sid, "Light_Pendant", x, z, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    ceiling_run(sid, "CeilingPipes_8", "x", -150)
    wall_fill(sid, "E", "PipeRun_8", 0, skip=(-150,))
    for (x, z) in ((104, -150), (128, -150), (152, -134), (80, -186)):
        obox("Mist", props(sid), x, 0.5, z, 4, 1, 4, t=1, nc=True, nq=True, ns=True, fx="mist")
    dock("DOCK_CP_CHILLERS", sid, "W", -150, "Chiller Hall dock")
    steam_trap("TRAP_CHILLERS", sid, "E", -150)
    light_panel(sid, "S", 80)
    sector_sign(sid, "S", 112)
    camera("CP_CHILLERS", sid, "S", 170.5, (112, 2, -160), "Chiller Hall")
    emergency(sid, ((120, -190), (120, -130)))


def dress_control():
    sid = "CP_CONTROL"
    strip_grid(sid, step=16, along="x")
    terminal("TERM_CP", sid, "N", 130, "Plant Control terminal")
    on_wall(sid, "N", 116, "WallMonitor_Map")
    on_wall(sid, "N", 144, "WallMonitor_Status")
    floor(sid, "ControlConsole_8", 130, -218, 180, label="console")
    floor(sid, "OfficeChair", 129.6, -213.6, 6, label="console chair")
    desk_set(sid, 106, -232, 90, monitors=("Status", "Terminals"), extras=("Mug",))
    desk_set(sid, 154, -232, -90, monitors=("Log",))
    COLUMN_OVERRIDE[(sid, "E", -244)] = "Access"
    light_panel(sid, "S", 108)
    sector_sign(sid, "S", 130)
    camera("CP_CONTROL", sid, "S", 155, (124, 2, -228), "Plant Control")
    emergency(sid, ((130, -224),))


def dress_tunnel():
    sid = "MT_TUNNEL"
    s = SPACES[sid]
    camera("MT_TUNNEL", sid, "S", 70, (150, 2, 0), "Service Tunnel")
    light_panel(sid, "N", 72)
    sector_sign(sid, "N", 112.5, y=-2.0)
    steam_trap("TRAP_TUNNEL_W", sid, "S", 92, -2.5)
    steam_trap("TRAP_TUNNEL_E", sid, "N", 132, -2.5)
    wall_fill(sid, "N", "PipeRun_8", -2.5)
    wall_fill(sid, "S", "PipeRun_8", -2.5)
    for x in range(72, 152, 8):
        piece("FloorGrate_8x8", geo(sid), x, 0, 0, 90)
    for x in (76, 92, 108, 124, 140):
        ceiling_light(sid, "Light_CeilingStrip", x, 0, 0)
    floor(sid, "Crate_4", 120, -6.9, 8)
    floor(sid, "Barrel", 84, 7.2, 0)
    emergency(sid, ((88, 0), (128, 0)))


def dress_gallery():
    sid = "MT_GALLERY"
    s = SPACES[sid]
    # Obstacles break the long gallery into short sightlines.
    floor(sid, "CrateStack", 158.8, 30, 90)
    floor(sid, "CrateStack", 169.2, 54, -90)
    pump(sid, 167, 6, 90)
    floor(sid, "Barrel", 157.4, 52, 0)
    camera("MT_GALLERY", sid, "W", -26, (164, 2, 30), "Pipe Gallery north")
    camera("MT_GALLERY_S", sid, "E", 86, (164, 2, 20), "Pipe Gallery south")
    light_panel(sid, "W", 8)
    sector_sign(sid, "W", 13.5)
    dock("DOCK_MT_GALLERY", sid, "N", 164, "Pipe Gallery dock")
    station("STATION_GALLERY", sid, "W", 44)
    steam_trap("TRAP_GALLERY_N", sid, "W", -14)
    steam_trap("TRAP_GALLERY_MID", sid, "W", 28)
    steam_trap("TRAP_GALLERY_S", sid, "E", 62)
    wall_fill(sid, "E", "PipeRun_8", 0)
    wall_fill(sid, "W", "PipeRun_8", 0)
    for z in (-20, -4, 12, 28, 44, 60, 76):
        ceiling_light(sid, "Light_CeilingStrip", 164, z, 90)
    emergency(sid, ((164, -10), (164, 30), (164, 70)))


def dress_boiler():
    sid = "MT_BOILER"
    s = SPACES[sid]
    boiler(sid, 211, -14)
    boiler(sid, 211, 14)
    terminal("TERM_MT", sid, "E", 0, "Boiler Room terminal")
    dock("DOCK_MT_BOILER", sid, "N", 186, "Boiler Room dock")
    steam_trap("TRAP_BOILER", sid, "S", 200)
    conduit_trap("TRAP_BOILER_POWER", sid, "N", 226)
    on_wall(sid, "S", 218, "Sign_Warning", text="DANGER\nSTEAM")
    wall_fill(sid, "E", "PipeRun_8", 0, skip=(0,))
    for x in (188, 204, 220):
        for z in (-22, 0, 22):
            ceiling(sid, "Light_Pendant", x, z, 0, 0.0, lights_folder(sid), light=light_opts(sid, "Light_Pendant"))
    light_panel(sid, "W", 0)
    sector_sign(sid, "W", -6)
    camera("MT_BOILER", sid, "W", 26, (222, 2, 0), "Boiler Room")
    emergency(sid, ((206, -22), (206, 22)))


def dress_south():
    sid = "MT_SOUTH"
    camera("MT_SOUTH", sid, "N", 112, (150, 2, 78), "South Tunnel")
    steam_trap("TRAP_SOUTH", sid, "N", 132, -2.5)
    light_panel(sid, "S", 148)
    wall_fill(sid, "N", "PipeRun_8", -2.5)
    wall_fill(sid, "S", "PipeRun_8", -2.5, end=144)
    for x in (116, 130, 144):
        ceiling_light(sid, "Light_CeilingStrip", x, 78, 0)
    emergency(sid, ((130, 78),))


def camera_links():
    """Every camera links to the other cameras in its room and to the cameras of neighbouring rooms."""
    adj: dict = {}
    for o in OPENINGS:
        ra, rb = SPACES[o.a].room, SPACES[o.b].room
        if ra != rb:
            adj.setdefault(ra, set()).add(rb)
            adj.setdefault(rb, set()).add(ra)
    by_room: dict = {}
    for c in CAMERAS:
        by_room.setdefault(c["room"], []).append(c["id"])
    for c in CAMERAS:
        links = [x for x in by_room[c["room"]] if x != c["id"]]
        for other in sorted(adj.get(c["room"], ())):
            links += by_room.get(other, [])
        c["rec"][6]["a"]["Links"] = ",".join(links)
    for r in ROOMS:
        if r not in by_room:
            err(f"room {r} has no camera")


def dress_all():
    door_keepouts()
    dress_core()
    dress_insertion()
    dress_deck()
    dress_stair("OD_STAIR_W", 1)
    dress_stair("OD_STAIR_E", -1)
    dress_reception()
    dress_cubicles()
    dress_exec()
    dress_conference()
    dress_fab()
    dress_rackhall()
    dress_datahall()
    dress_noc()
    dress_pumps()
    dress_chillers()
    dress_control()
    dress_tunnel()
    dress_gallery()
    dress_boiler()
    dress_south()
    camera_links()


# ------------------------------------------------------------------------------------------------------
# Floors and ceilings

FLOOR_FINISH = {
    # finish: (material, colour, variant, reflectance)
    "polished": ("SmoothPlastic", (44, 46, 50), "", 0.06),
    "concrete": ("Concrete", (58, 58, 60), "", 0),
    "tread": ("DiamondPlate", (40, 42, 46), "AxiomTread", 0),
    "plate": ("DiamondPlate", (34, 36, 40), "AxiomTread", 0),
    "raised": ("DiamondPlate", (34, 36, 40), "AxiomTread", 0),
    "carpet": ("Rubber", (36, 40, 48), "AxiomRubber", 0),
}


def tile_grid(lo, hi, size=8):
    """Tiles `size` wide centred in [lo, hi]; returns (tile starts, leftover edge strips)."""
    n = int((hi - lo) // size)
    start = lo + ((hi - lo) - n * size) / 2
    tiles = [start + i * size for i in range(n)]
    strips = []
    if start - lo > 1e-6:
        strips.append((lo, start))
    end = start + n * size
    if hi - end > 1e-6:
        strips.append((end, hi))
    return tiles, strips


def floors_and_ceilings(s: Space):
    mat, col, var, refl = FLOOR_FINISH[s.floor]
    flags = {"refl": refl} if refl else {}
    box("Floor", geo(s.id), s.x0, s.x1, s.y0 - 1, s.y0, s.z0, s.z1, material=mat, color=col, variant=var, **flags)
    box("Ceiling", geo(s.id), s.x0, s.x1, s.top, s.top + 1, s.z0, s.z1, material="Metal", color="ceiling", variant="AxiomSteel")
    if s.floor in ("plate", "raised"):
        # Floor plates over the whole room (raised access floor in the server halls).
        xs, xstrips = tile_grid(s.x0, s.x1)
        zs, zstrips = tile_grid(s.z0, s.z1)
        skip = FLOOR_SKIP.get(s.id, set())
        for x in xs:
            for z in zs:
                if (x, z) in skip:
                    continue
                kind = FLOOR_TILE.get((s.id, x, z), "FloorPlate_8x8")
                piece(kind, geo(s.id), x + 4, s.y0, z + 4, 0)
        for (a, b) in xstrips:
            box("FloorEdge", geo(s.id), a, b, s.y0, s.y0 + 0.2, s.z0, s.z1, material="DiamondPlate", color=(30, 32, 36), variant="AxiomTread")
        for (a, b) in zstrips:
            for x in xs:
                box("FloorEdge", geo(s.id), x, x + 8, s.y0, s.y0 + 0.2, a, b, material="DiamondPlate", color=(30, 32, 36), variant="AxiomTread")
    if s.ceiling == "panels":
        xs, xstrips = tile_grid(s.x0, s.x1)
        zs, zstrips = tile_grid(s.z0, s.z1)
        for x in xs:
            for z in zs:
                piece("CeilingPanel_8x8", geo(s.id), x + 4, s.top, z + 4, 0)
        for (a, b) in xstrips:
            box("CeilingEdge", geo(s.id), a, b, s.top - 0.3, s.top, s.z0, s.z1, material="Metal", color="dark", variant="AxiomSteel")
        for (a, b) in zstrips:
            for x in xs:
                box("CeilingEdge", geo(s.id), x, x + 8, s.top - 0.3, s.top, a, b, material="Metal", color="dark", variant="AxiomSteel")


FLOOR_SKIP: dict = {}  # space -> {(tile x, tile z)} left bare (a hatch or a grate goes there instead)
FLOOR_TILE: dict = {}  # (space, tile x, tile z) -> kit floor piece


# ------------------------------------------------------------------------------------------------------
# Plan render

def render_plan(path, extra=None):
    from PIL import Image, ImageDraw, ImageFont

    xs = [v for s in SPACES.values() for v in (s.x0, s.x1)]
    zs = [v for s in SPACES.values() for v in (s.z0, s.z1)]
    pad = 24
    x_min, x_max, z_min, z_max = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
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

    # walls (everything near a space)
    for s in sorted(SPACES.values(), key=lambda s: s.y0):
        col = WINGS[ROOMS[s.room].wing]
        upper = s.y0 > 10
        x0, y0 = P(s.x0 - WALL, s.z0 - WALL)
        x1, y1 = P(s.x1 + WALL, s.z1 + WALL)
        if not upper:
            dr.rectangle([x0, y0, x1, y1], fill=(60, 62, 68))
    for s in sorted(SPACES.values(), key=lambda s: s.y0):
        col = WINGS[ROOMS[s.room].wing]
        upper = s.y0 > 10
        x0, y0 = P(s.x0, s.z0)
        x1, y1 = P(s.x1, s.z1)
        if upper:
            dr.rectangle([x0, y0, x1, y1], outline=col + (255,), width=3, fill=col + (60,))
        else:
            dr.rectangle([x0, y0, x1, y1], fill=tuple(int(c * 0.35) for c in col))
        # posts
        for corner in ("NW", "NE", "SW", "SE"):
            if not has_post(s, corner):
                continue
            cx = s.x0 if "W" in corner else s.x1
            cz = s.z0 if "N" in corner else s.z1
            px, pz = post_size(cx), post_size(cz)
            ax0, ax1 = (cx, cx + px) if "W" in corner else (cx - px, cx)
            az0, az1 = (cz, cz + pz) if "N" in corner else (cz - pz, cz)
            dr.rectangle([*P(ax0, az0), *P(ax1, az1)], fill=(90, 92, 98))
    # openings
    for o in OPENINGS:
        g = opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        col = {"door": (255, 170, 60), "frame": (200, 200, 200), "wide": (200, 200, 200), "portal": (160, 160, 160), "gate": (120, 220, 255)}[o.kind]
        if side_a in "NS":
            box = [*P(o.at, line - 1.6), *P(o.at + o.width, line + 1.6)]
        else:
            box = [*P(line - 1.6, o.at), *P(line + 1.6, o.at + o.width)]
        dr.rectangle(box, fill=col + (255,))
    for wnd in WINDOWS:
        a, b = SPACES[wnd["a"]], SPACES[wnd["b"]]
        side_a, side_b, line, lo, hi = shared_wall(a, b)
        dr.rectangle([*P(wnd["from"], line - 1), *P(wnd["to"], line + 1)], fill=(140, 230, 255, 255))
    # labels
    for r in ROOMS.values():
        sp = [SPACES[i] for i in r.spaces]
        x = (min(s.x0 for s in sp) + max(s.x1 for s in sp)) / 2
        z = (min(s.z0 for s in sp) + max(s.z1 for s in sp)) / 2
        upper = sp[0].y0 > 10
        txt = r.name + (" (upper)" if upper else "")
        px, pz = P(x, z + (8 if upper else 0))
        tw = dr.textlength(txt, font=font)
        dr.text((px - tw / 2, pz - 7), txt, fill=(235, 235, 235), font=font)
    if extra:
        extra(dr, P, small)
    # scale bar and legend
    dr.line([*P(x_min + 10, z_max - 10), *P(x_min + 110, z_max - 10)], fill=(255, 255, 255), width=2)
    dr.text(P(x_min + 10, z_max - 20), "100 studs", fill=(255, 255, 255), font=small)
    legend = [((255, 170, 60), "lockable door"), ((200, 200, 200), "doorway"), ((120, 220, 255), "gate / deck glass"),
              ((255, 40, 40), "camera (line: aim)"), ((255, 140, 40), "shell dock"), ((90, 255, 140), "terminal"),
              ((255, 235, 150), "charging station"), ((230, 80, 255), "Overload trap"), ((150, 150, 155), "props")]
    lx, lz = x_min + 10, z_max - 28 - 12 * 5
    for i, (col, label) in enumerate(legend):
        px, pz = P(lx + 75 * (i // 5), lz + 12 * (i % 5))
        dr.rectangle([px, pz, px + 12, pz + 12], fill=col)
        dr.text((px + 18, pz), label, fill=(225, 225, 225), font=small)
    dr.text(P(x_min + 10, z_min + 6), "Axiom Data Vault. North is up; the Observation Deck is the outlined upper level over Insertion.",
            fill=(225, 225, 225), font=small)
    img.save(path)
    return path


def room_bounds(r: Room):
    sp = [SPACES[i] for i in r.spaces]
    x0, x1 = min(s.x0 for s in sp), max(s.x1 for s in sp)
    z0, z1 = min(s.z0 for s in sp), max(s.z1 for s in sp)
    y0, y1 = min(s.y0 for s in sp), max(s.top for s in sp)
    return x0, x1, y0, y1, z0, z1


def game_rooms():
    for r in ROOMS.values():
        x0, x1, y0, y1, z0, z1 = room_bounds(r)
        GAME["rooms"].append({"id": r.id, "name": r.name, "wing": r.wing,
                              "c": [rnd((x0 + x1) / 2), rnd((y0 + y1) / 2), rnd((z0 + z1) / 2)],
                              "s": [rnd(x1 - x0), rnd(y1 - y0), rnd(z1 - z0)],
                              "emergency": r.wing not in ("CORE", "INSERTION", "FAB")})
    # Room boxes may not overlap: the game finds a room by the first box containing a point.
    rs = list(ROOMS.values())
    for i in range(len(rs)):
        for j in range(i + 1, len(rs)):
            a, b = room_bounds(rs[i]), room_bounds(rs[j])
            if a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3] and a[4] < b[5] and b[4] < a[5]:
                err(f"room boxes {rs[i].id} and {rs[j].id} overlap")


LIGHTING = {"ambient": [34, 36, 44], "diffuse": 0.15, "specular": 0.3, "exposure": 0}


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
    walk = np.zeros((2, nx, nz), dtype=bool)  # layer 0: the ground floor, layer 1: the upper level

    def mark(layer, x0, x1, z0, z1, value=True):
        walk[layer, max(0, int(math.floor(x0 - x_lo))):int(math.ceil(x1 - x_lo)), max(0, int(math.floor(z0 - z_lo))):int(math.ceil(z1 - z_lo))] = value

    for s in SPACES.values():
        layer = 1 if s.y0 > 10 else 0
        mark(layer, s.x0 + 1, s.x1 - 1, s.z0 + 1, s.z1 - 1)
    for o in OPENINGS:
        side_a, side_b, line, lo, hi = opening_geometry(o)
        layer = 1 if opening_base(o) > 10 else 0
        if side_a in "NS":
            mark(layer, o.at + 1, o.at + o.width - 1, line - 2, line + 2)
        else:
            mark(layer, line - 2, line + 2, o.at + 1, o.at + o.width - 1)
    for sid, rects in FOOT.items():
        layer = 1 if SPACES[sid].y0 > 10 else 0
        for (x0, x1, z0, z1, label) in rects:
            mark(layer, x0 - 1, x1 + 1, z0 - 1, z1 + 1, False)
    # Stair halls: the landing is upper level, the flight joins the stair's foot to the landing.
    links = []
    for sid, d in (("OD_STAIR_W", 1), ("OD_STAIR_E", -1)):
        s = SPACES[sid]
        x_in = s.x1 if d > 0 else s.x0
        x_top = x_in - d * 18
        x_bot = x_top - d * 36
        lo, hi = sorted((x_top, x_in))
        mark(1, lo + 0.5, hi - 1, s.z0 + 1, s.z1 - 1)
        mark(0, min(x_bot, x_top), max(x_bot, x_top), 86, 96, False)
        foot = (int(x_bot - d * 2 - x_lo), int(91 - z_lo))
        top = (int(x_top + d * 2 - x_lo), int(91 - z_lo))
        links.append(((0, *foot), (1, *top), math.hypot(36, 24) + 4))

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
                    continue  # no cutting corners
                nd = dcur + cost
                if nd < dist.get((nl, ni, nj), 1e18):
                    dist[(nl, ni, nj)] = nd
                    heapq.heappush(heap, (nd, (nl, ni, nj)))
        return dist

    def node_near(x, z, layer):
        i0, j0 = int(x - x_lo), int(z - z_lo)
        for r in range(0, 8):
            for i in range(i0 - r, i0 + r + 1):
                for j in range(j0 - r, j0 + r + 1):
                    if 0 <= i < nx and 0 <= j < nz and walk[layer, i, j]:
                        return (layer, i, j)
        return None

    points = {}
    for rec in PIECES:
        if rec[0] == "MainframeTerminal":
            opts = rec[6]
            sid = next(s for s in SPACES.values() if s.contains(rec[2], rec[4]) and abs(s.y0 - rec[3]) < 1).id
            s = SPACES[sid]
            # The operator stands in front of the terminal.
            fx, fz = to_world(rec[2], rec[4], rec[5], 0, -3.5)
            points[opts["id"]] = node_near(fx, fz, 1 if s.y0 > 10 else 0)
    points["SPAWN"] = node_near(0, 117.5, 0)
    names = sorted(points)
    table = {}
    for a in names:
        dist = dijkstra(points[a])
        for b in names:
            table[(a, b)] = dist.get(points[b], float("inf"))
    return names, table


# Parts per kit piece (from the built kit), for the estimate printed at the end.
PART_COUNT = {
    "WallPanel_8x16_Plate": 43, "WallPanel_8x16_Ribbed": 47, "WallPanel_8x16_Vent": 58, "WallPanel_8x16_Pipes": 58,
    "WallPanel_8x16_Screen": 50, "WallPanel_8x16_Hazard": 38, "WallPanel_8x16_Access": 54, "WallPanel_4x16_Plate": 43,
    "WallPanel_8x12_Plate": 40, "WallPanel_8x12_Ribbed": 47, "WallPanel_8x12_Vent": 55, "WallPanel_8x12_Screen": 47,
    "WallPanel_4x12_Plate": 40, "WallUpper_8x8": 23, "WallUpper_8x8_Ribbed": 31, "WallUpper_8x4": 20,
    "WallUpper_4x8": 23, "WallUpper_4x4": 20, "WallUpper_8x8_Lite": 7, "WallUpper_4x8_Lite": 7, "WallGlass_8x16": 43, "WallWindow_8x8": 28, "FloorPlate_8x8": 6,
    "FloorGrate_8x8": 30, "FloorHazard_8x1": 3, "CeilingPanel_8x8": 8, "CeilingBeam_8": 15, "CeilingDuct_8": 21,
    "CableTray_8": 20, "CeilingPipes_8": 21, "DoorFrame_8x10": 50, "DoorFrame_12x10": 50, "DoorFrame_24x14": 50,
    "Light_CeilingStrip": 11, "Light_WallCage": 9, "Light_Pendant": 6, "LightPanel": 10, "Desk_8x4": 27,
    "Workstation_8x4": 128, "Keyboard": 2, "Mouse": 4, "Laptop": 6, "Mug": 5, "PaperTray": 8, "PCTower": 25,
    "OfficeChair": 33, "ControlConsole_8": 50, "WallMonitor_Map": 16, "WallMonitor_Camera": 16,
    "WallMonitor_Status": 16, "FilingCabinet": 21, "Locker_Double": 32, "StorageShelf_6": 42, "ServerRack_A": 55,
    "ServerRack_B": 54, "CoolingUnit": 42, "CableBundle_8": 6, "PipeRun_8": 41, "PipeVertical_16": 16,
    "JunctionBox": 14, "Crate_4": 21, "CrateStack": 63, "Barrel": 9, "Railing_8": 15, "Sign_Sector": 10,
    "Sign_Direction": 9, "Sign_Warning": 9, "Sign_Restricted": 9, "Sign_Lockdown": 7, "MainframeTerminal": 41,
    "SecurityCamera": 12, "Door_8x10": 29, "Light_Emergency": 8, "ShellDock": 39, "ChargingStation": 18,
    "Floodlight": 15,
}


def build_all():
    check_layout()
    if ERRORS:
        return
    n = build_structure()
    dress_all()
    for s in SPACES.values():
        line_space(s)
        floors_and_ceilings(s)
    place_openings()
    game_rooms()
    return n


def write_layout(path):
    data = {"version": 1, "boxes": BOXES, "pieces": PIECES, "posts": POSTS, "game": GAME, "lighting": LIGHTING}
    text = json.dumps(data, separators=(",", ":"))
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("-- Generated by tools/map/design_map.py: the Axiom Data Vault map as JSON for BuildMap. Don't edit.\n")
        f.write("return [==[" + text + "]==]\n")
    return len(text)


if __name__ == "__main__":
    blocks = build_all()
    for w in WARNINGS:
        print("warning:", w)
    for e in ERRORS:
        print("ERROR:", e)
    plan = sys.argv[sys.argv.index("--plan") + 1] if "--plan" in sys.argv else os.path.join(HERE, "plan.png")

    def overlay(dr, P, small):
        for sid, rects in FOOT.items():
            upper = SPACES[sid].y0 > 10
            for (x0, x1, z0, z1, label) in rects:
                col = (150, 150, 155, 110 if upper else 200)
                if label.startswith("DOCK"):
                    col = (255, 140, 40, 255)
                elif label.startswith("TERM"):
                    col = (90, 255, 140, 255)
                elif label.startswith("STATION"):
                    col = (255, 235, 150, 255)
                dr.rectangle([*P(x0, z0), *P(x1, z1)], fill=col)
        for rec in PIECES:
            kit, folder = rec[0], rec[1]
            x, z = rec[2], rec[4]
            if kit == "SecurityCamera":
                aim = rec[6]["aim"]
                dr.line([*P(x, z), *P(x + (aim[0] - x) * 0.25, z + (aim[2] - z) * 0.25)], fill=(255, 60, 60), width=2)
                dr.ellipse([*P(x - 2, z - 2), *P(x + 2, z + 2)], fill=(255, 40, 40))
            elif folder == "Facility/Traps":
                dr.ellipse([*P(x - 1.6, z - 1.6), *P(x + 1.6, z + 1.6)], fill=(230, 80, 255))
            elif folder.startswith("Facility/Lights") and kit != "LightPanel":
                dr.point(P(x, z), fill=(255, 255, 200))

    render_plan(plan, overlay)
    counts = {}
    for p in PIECES:
        counts[p[0]] = counts.get(p[0], 0) + 1
    print(f"{len(SPACES)} spaces, {len(ROOMS)} rooms, {len(OPENINGS)} openings; {blocks} structural blocks, "
          f"{len(BOXES)} boxes, {len(PIECES)} pieces, {len(POSTS)} posts")
    print(", ".join(f"{k} {v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])))
    est = len(BOXES) + 3 * len(POSTS) + sum(PART_COUNT.get(k, 20) * v for k, v in counts.items())
    print(f"about {est} parts")
    if "--walk" in sys.argv and not ERRORS:
        names, table = walk_distances()
        print("walking distances (studs):")
        print("".join(f"{n:>10}" for n in [""] + names))
        for a in names:
            print(f"{a:>10}" + "".join(f"{table[(a, b)]:10.0f}" for b in names))
        close = [(a, b) for a in names for b in names if a < b and a != "SPAWN" and b != "SPAWN" and table[(a, b)] < 280]
        print("terminal pairs closer than 280 studs:", close or "none")
    if "--check" not in sys.argv and not ERRORS:
        size = write_layout(os.path.join(HERE, "MapLayout.luau"))
        print(f"wrote MapLayout.luau ({size // 1024} KB); plan: {plan}")
