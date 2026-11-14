"""Core of the Axiom Tower generator: the records BuildMap builds, prefab definitions, spaces and openings,
the solid structure, wall/floor/ceiling finishes, placement checks and the game contract helpers.

Conventions (studs): +x is east, +z is south (north is -z), y is up; the main floor is y = 0.
A space is a rectangle of clear floor (its four wall faces) with a floor height y0 and a structural height h.
Walls are 2 thick and sit outside the faces; two spaces share a wall when their faces are exactly 2 apart.
A room is what the game sees (one bounds box, a camera at least, one Lights folder); it may hold several
spaces. Pieces (kit models and prefabs) pivot where they mount and face -Z, like the kit:
  floor pieces at the bottom centre, wall pieces at the bottom centre of the back (on the wall's face),
  desk pieces on a desk top, ceiling pieces at the top centre.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

WALL = 2
SKIN = 0.1  # wall finish thickness, in front of the wall face

# ------------------------------------------------------------------------------------------------------
# Records

BOXES: list[dict] = []  # plain parts in world space
PIECES: list[list] = []  # [name, folder, x, y, z, yaw, opts]: kit pieces and prefabs
PREFABS: dict[str, dict] = {}  # name -> {"parts": [...]} (parts relative to the pivot)
DIMS: dict[str, tuple] = {}  # name -> (sx, sy, sz, cx, cy, cz): bounding box and its centre, piece space
GAME: dict = {"rooms": [], "platform": None, "spawn": None}
ERRORS: list[str] = []
WARNINGS: list[str] = []


def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNINGS.append(msg)


def rnd(v, n=3):
    r = round(v, n)
    return 0.0 if r == 0 else r


def hash01(*parts) -> float:
    """A stable pseudo-random number in [0, 1] from the parts (FNV-1a with a murmur3 finaliser, so keys that
    differ only in their last character still land far apart)."""
    h = 2166136261
    for ch in "|".join(str(p) for p in parts):
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & 0xFFFFFFFF
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & 0xFFFFFFFF
    h ^= h >> 16
    return h / 0xFFFFFFFF


def pick(options, *key):
    return options[int(hash01(*key) * len(options)) % len(options)]


def wpick(weights: dict, *key):
    total = sum(weights.values())
    r = hash01(*key) * total
    for k, w in weights.items():
        r -= w
        if r <= 0:
            return k
    return next(iter(weights))


# Colours (dark, desaturated, realistic). Nothing but the Chimera is red (design doc readability rule).
C = {
    "mass": (40, 40, 42),
    "slab": (30, 30, 32),
    "paint": (118, 115, 108),  # greige office paint
    "paintCool": (104, 110, 114),
    "paintWhite": (150, 150, 146),
    "paintDark": (54, 56, 60),
    "block": (112, 112, 104),
    "blockLow": (70, 74, 78),
    "tileWhite": (156, 160, 156),
    "tileGrey": (100, 104, 104),
    "carpet": (58, 62, 72),
    "carpetDark": (46, 44, 52),
    "carpetRed": (70, 52, 50),  # a warm brown, not red
    "terrazzo": (120, 116, 108),
    "terrazzoDark": (64, 64, 66),
    "concrete": (92, 92, 90),
    "concreteDark": (62, 62, 62),
    "vinyl": (128, 124, 114),
    "raised": (120, 124, 128),
    "ceiling": (150, 148, 140),
    "ceilingDark": (26, 26, 28),
    "plenum": (20, 20, 22),
    "wood": (92, 64, 44),
    "woodDark": (58, 40, 30),
    "woodLight": (140, 108, 74),
    "steel": (120, 124, 128),
    "steelDark": (52, 55, 60),
    "chrome": (170, 172, 176),
    "alu": (140, 144, 148),
    "black": (16, 16, 18),
    "rubber": (28, 28, 30),
    "glass": (150, 175, 185),
    "glassDark": (30, 40, 46),
    "paper": (196, 194, 184),
    "paperOld": (176, 168, 146),
    "fabric": (70, 76, 86),
    "fabricWarm": (92, 84, 74),
    "leather": (34, 30, 28),
    "plastic": (200, 198, 190),
    "plasticGrey": (120, 120, 118),
    "hazard": (190, 145, 30),
    "safety": (210, 170, 40),
    "green": (50, 170, 90),
    "cyan": (80, 200, 255),
    "amber": (255, 150, 50),
    "warm": (255, 214, 160),
    "cool": (210, 225, 240),
    "plant": (52, 78, 44),
    "plantDead": (92, 76, 46),
    "soil": (44, 34, 26),
}


# ------------------------------------------------------------------------------------------------------
# Rotation maths for prefab bounds (CFrame.Angles(rx, ry, rz) = Rx * Ry * Rz)


def rot_matrix(rx, ry, rz):
    a, b, c = math.radians(rx), math.radians(ry), math.radians(rz)
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    rxm = ((1, 0, 0), (0, ca, -sa), (0, sa, ca))
    rym = ((cb, 0, sb), (0, 1, 0), (-sb, 0, cb))
    rzm = ((cc, -sc, 0), (sc, cc, 0), (0, 0, 1))

    def mul(p, q):
        return tuple(tuple(sum(p[i][k] * q[k][j] for k in range(3)) for j in range(3)) for i in range(3))
    return mul(mul(rxm, rym), rzm)


def part_corners(size, cf):
    sx, sy, sz = size
    x, y, z, rx, ry, rz = cf
    m = rot_matrix(rx, ry, rz)
    out = []
    for ax in (-0.5, 0.5):
        for ay in (-0.5, 0.5):
            for az in (-0.5, 0.5):
                lx, ly, lz = ax * sx, ay * sy, az * sz
                out.append((x + m[0][0] * lx + m[0][1] * ly + m[0][2] * lz,
                            y + m[1][0] * lx + m[1][1] * ly + m[1][2] * lz,
                            z + m[2][0] * lx + m[2][1] * ly + m[2][2] * lz))
    return out


# ------------------------------------------------------------------------------------------------------
# Prefabs: small models defined once (parts relative to the pivot) and cloned for every placement.

MATERIAL_OF_VARIANT = {
    "AxiomPlaster": "Plaster", "AxiomCarpet": "Carpet", "AxiomCeiling": "Limestone", "AxiomTerrazzo": "Marble",
    "AxiomWood": "Wood", "AxiomBlock": "Brick", "AxiomTile": "CeramicTiles", "AxiomConcrete": "Concrete",
    "AxiomVinyl": "Slate", "AxiomFabric": "Fabric", "AxiomSteel": "Metal", "AxiomTread": "DiamondPlate",
    "AxiomWorn": "CorrodedMetal", "AxiomRubber": "Rubber", "AxiomCardboard": "Cardboard",
    "AxiomLeather": "Leather", "AxiomHazard": "SmoothPlastic",
}


class Prefab:
    """A prefab under construction. Parts: n name, s size, cf [x, y, z, rx, ry, rz] (degrees), m material,
    c colour, v variant; flags: col (collides), nq (no raycasts), t transparency, refl, ns (no shadow),
    sh ("cyl", "ball", "wedge"), tag, a (attributes), light, gui, tex, fx, weld (name of the part it's
    welded to, which must be anchored; the welded part moves with it)."""

    def __init__(self, name, mount="Floor"):
        self.name = name
        self.mount = mount
        self.parts = []

    def box(self, n, size, pos, color, mat="SmoothPlastic", var=None, rot=(0, 0, 0), solid=False, **kw):
        if isinstance(color, str):
            color = C[color]
        if var and mat == "SmoothPlastic" and var != "AxiomHazard":
            mat = MATERIAL_OF_VARIANT[var]
        rec = {"n": n, "s": [rnd(v) for v in size], "cf": [rnd(pos[0]), rnd(pos[1]), rnd(pos[2]), rnd(rot[0]), rnd(rot[1]), rnd(rot[2])],
               "m": mat, "c": list(color)}
        if var:
            rec["v"] = var
        if solid:
            rec["col"] = 1
        sx, sy, sz = size
        if sx * sy * sz < 0.4 and "ns" not in kw:
            rec["ns"] = 1
        for k, v in kw.items():
            if v is not None and v is not False:
                rec[k] = v
        self.parts.append(rec)
        return rec

    def cyl(self, n, length, dia, pos, color, mat="SmoothPlastic", var=None, axis="y", solid=False, rot=None, **kw):
        r = rot or {"x": (0, 0, 0), "y": (0, 0, 90), "z": (0, 90, 0)}[axis]
        return self.box(n, (length, dia, dia), pos, color, mat, var, r, solid, sh="cyl", **kw)

    def ball(self, n, dia, pos, color, mat="SmoothPlastic", var=None, **kw):
        return self.box(n, (dia, dia, dia), pos, color, mat, var, (0, 0, 0), False, sh="ball", **kw)

    def wedge(self, n, size, pos, color, mat="SmoothPlastic", var=None, rot=(0, 0, 0), solid=False, **kw):
        return self.box(n, size, pos, color, mat, var, rot, solid, sh="wedge", **kw)

    def done(self):
        PREFABS[self.name] = {"parts": self.parts, "mount": self.mount}
        lo = [1e9] * 3
        hi = [-1e9] * 3
        for p in self.parts:
            if p.get("t", 0) >= 1 and not p.get("col"):
                continue
            for c in part_corners(p["s"], p["cf"]):
                for i in range(3):
                    lo[i] = min(lo[i], c[i])
                    hi[i] = max(hi[i], c[i])
        DIMS[self.name] = (rnd(hi[0] - lo[0], 2), rnd(hi[1] - lo[1], 2), rnd(hi[2] - lo[2], 2),
                           rnd((hi[0] + lo[0]) / 2, 2), rnd((hi[1] + lo[1]) / 2, 2), rnd((hi[2] + lo[2]) / 2, 2))
        return self


def gui(text, face="Front", font="Roboto", color=(220, 220, 220), size=None, light=1.0, bright=1.0, bg=None,
        align="Center", valign="Center", ppu=40, pad=0.06, bold=False, wrap=True, rot=0, transp=0.0):
    """A SurfaceGui with one TextLabel. `size` is the text height in studs (None: scale to fit)."""
    g = {"text": text, "face": face, "font": font, "color": list(color), "light": light, "bright": bright,
         "align": align, "valign": valign, "ppu": ppu, "pad": pad}
    if size:
        g["size"] = size
    if bg:
        g["bg"] = list(bg)
    if bold:
        g["bold"] = 1
    if not wrap:
        g["nowrap"] = 1
    if rot:
        g["rot"] = rot
    if transp:
        g["tt"] = transp
    return g


def light(kind="point", color=(255, 230, 200), range_=16, brightness=1.0, shadows=False, face="Bottom", angle=None, off=False):
    l = {"kind": kind, "c": list(color), "range": range_, "brightness": brightness}
    if shadows:
        l["shadows"] = True
    if kind != "point":
        l["face"] = face
    if angle:
        l["angle"] = angle
    if off:
        l["off"] = True
    return l


# ------------------------------------------------------------------------------------------------------
# World parts and placements


def box(name, folder, x0, x1, y0, y1, z0, z1, mat="Concrete", color="mass", var="", **flags):
    c = C[color] if isinstance(color, str) else color
    if var and mat in ("Concrete", "SmoothPlastic") and var in MATERIAL_OF_VARIANT and var != "AxiomHazard":
        mat = MATERIAL_OF_VARIANT[var]
    rec = {"n": name, "f": folder, "p": [rnd((x0 + x1) / 2), rnd((y0 + y1) / 2), rnd((z0 + z1) / 2)],
           "s": [rnd(x1 - x0), rnd(y1 - y0), rnd(z1 - z0)], "m": mat, "c": list(c)}
    if var:
        rec["v"] = var
    for k, v in flags.items():
        if v is not None and v is not False:
            rec[k] = v
    BOXES.append(rec)
    return rec


def obox(name, folder, cx, cy, cz, sx, sy, sz, yaw=0.0, mat="SmoothPlastic", color="steelDark", var="", **flags):
    """A box by centre and size, turned `yaw` degrees about Y (or r=[rx, ry, rz] in flags)."""
    c = C[color] if isinstance(color, str) else color
    if var and mat == "SmoothPlastic" and var in MATERIAL_OF_VARIANT and var != "AxiomHazard":
        mat = MATERIAL_OF_VARIANT[var]
    rec = {"n": name, "f": folder, "p": [rnd(cx), rnd(cy), rnd(cz)], "s": [rnd(sx), rnd(sy), rnd(sz)], "m": mat, "c": list(c)}
    if yaw:
        rec["r"] = rnd(yaw)
    if var:
        rec["v"] = var
    for k, v in flags.items():
        if v is not None and v is not False:
            rec[k] = v
    BOXES.append(rec)
    return rec


def piece(name, folder, x, y, z, yaw=0.0, **opts):
    y_ = yaw % 360
    rec = [name, folder, rnd(x), rnd(y), rnd(z), rnd(y_ if y_ <= 180 else y_ - 360)]
    if opts:
        rec.append(opts)
    PIECES.append(rec)
    return rec


# ------------------------------------------------------------------------------------------------------
# Rooms, spaces, openings, windows


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
    open: tuple = ()
    walls: str = "plaster"  # finish style (see FINISH)
    floor: str = "concrete"  # floor finish (see FLOORS)
    ceiling: str = "exposed"  # "tile" (drop ceiling), "plaster", "exposed"
    drop: float = 0  # drop/plaster ceiling height above y0 (0: the structural top)
    holes: int = 0  # missing ceiling tiles

    @property
    def w(self):
        return self.x1 - self.x0

    @property
    def d(self):
        return self.z1 - self.z0

    @property
    def top(self):
        return self.y0 + self.h

    @property
    def ceil(self):
        """Height of the finished ceiling (what the room shows)."""
        return self.y0 + (self.drop if self.drop else self.h)

    def contains(self, x, z, margin=0.0):
        return self.x0 + margin <= x <= self.x1 - margin and self.z0 + margin <= z <= self.z1 - margin


ROOMS: dict[str, Room] = {}
SPACES: dict[str, Space] = {}


def room(id, name, wing, style):
    ROOMS[id] = Room(id, name, wing, style)


def space(id, room_id, x0, x1, z0, z1, h=16, y0=0, open=(), walls="plaster", floor="concrete", ceiling="exposed", drop=0, holes=0):
    s = Space(id, room_id, x0, x1, z0, z1, h, y0, tuple(open), walls, floor, ceiling, drop, holes)
    SPACES[id] = s
    ROOMS[room_id].spaces.append(id)
    return s


@dataclass
class Opening:
    a: str
    b: str
    at: float
    width: float
    kind: str  # door, frame, wide, gate, portal, elevator
    door: str | None = None
    name: str = ""
    base: float | None = None
    style: str = "office"  # door look: office, steel, glass
    height: float | None = None


OPENINGS: list[Opening] = []
OPEN_HEIGHT = {"door": 10, "frame": 10, "wide": 10, "gate": 14, "portal": 10, "elevator": 10}


def opening(a, b, at, width, kind, door=None, name="", base=None, style="office", height=None):
    OPENINGS.append(Opening(a, b, at, width, kind, door, name, base, style, height))


def open_height(o: Opening):
    return o.height or OPEN_HEIGHT[o.kind]


# Interior glazing (a glass wall between two spaces) and exterior windows (in the building's envelope).
GLAZING: list[dict] = []  # {"a", "b", "from", "to", "base", "top"} (base/top above the floor of `a`... absolute y)
EXTERIOR: list[dict] = []  # {"space", "side", "from", "to", "sill", "head", "kind"} sill/head above the space floor


def glazing(a, b, u0, u1, y0, y1):
    GLAZING.append({"a": a, "b": b, "from": u0, "to": u1, "base": y0, "top": y1})


def exterior(sid, side, u0, u1, sill, head, kind="window"):
    EXTERIOR.append({"space": sid, "side": side, "from": u0, "to": u1, "sill": sill, "head": head, "kind": kind})


# ------------------------------------------------------------------------------------------------------
# Geometry helpers

SIDES = {
    # side: (axis the wall runs along, inward normal, yaw for a piece facing into the room)
    "N": ("x", (0, 1), 180),
    "S": ("x", (0, -1), 0),
    "W": ("z", (1, 0), -90),
    "E": ("z", (-1, 0), 90),
}


def face_coord(s: Space, side: str) -> float:
    return {"N": s.z0, "S": s.z1, "W": s.x0, "E": s.x1}[side]


def side_range(s: Space, side: str):
    return (s.x0, s.x1) if side in "NS" else (s.z0, s.z1)


def shared_wall(a: Space, b: Space):
    """(side of a, side of b, wall centre line, lo, hi) if a and b share a wall."""
    if abs(a.z1 + WALL - b.z0) < 1e-6:
        return "S", "N", a.z1 + WALL / 2, max(a.x0, b.x0), min(a.x1, b.x1)
    if abs(b.z1 + WALL - a.z0) < 1e-6:
        return "N", "S", a.z0 - WALL / 2, max(a.x0, b.x0), min(a.x1, b.x1)
    if abs(a.x1 + WALL - b.x0) < 1e-6:
        return "E", "W", a.x1 + WALL / 2, max(a.z0, b.z0), min(a.z1, b.z1)
    if abs(b.x1 + WALL - a.x0) < 1e-6:
        return "W", "E", a.x0 - WALL / 2, max(a.z0, b.z0), min(a.z1, b.z1)
    return None


def opening_base(o: Opening) -> float:
    return o.base if o.base is not None else max(SPACES[o.a].y0, SPACES[o.b].y0)


def opening_geometry(o: Opening):
    g = shared_wall(SPACES[o.a], SPACES[o.b])
    if not g:
        err(f"opening {o.a}-{o.b}: the spaces don't share a wall")
    return g


def wall_xz(s: Space, side: str, u: float, d: float):
    """A point `d` in front of side's wall face, at `u` along it."""
    return {"N": (u, s.z0 + d), "S": (u, s.z1 - d), "W": (s.x0 + d, u), "E": (s.x1 - d, u)}[side]


def side_yaw(side: str) -> float:
    return SIDES[side][2]


def yaw_facing(dx: float, dz: float) -> float:
    """Yaw that turns a piece's front (-Z) toward the direction (dx, dz)."""
    return math.degrees(math.atan2(-dx, -dz))


def to_world(x, z, yaw, lx, lz):
    a = math.radians(yaw)
    c, s_ = math.cos(a), math.sin(a)
    return x + lx * c + lz * s_, z - lx * s_ + lz * c


def geo(sid):
    return f"Map/Geometry/{sid}"


def props(sid):
    return f"Map/Props/{sid}"


def lights_folder(sid):
    return f"Facility/Lights/{SPACES[sid].room}"


# ------------------------------------------------------------------------------------------------------
# Layout checks


def check_layout():
    ids = list(SPACES)
    for s in SPACES.values():
        for v in (s.x0, s.x1, s.z0, s.z1):
            if v % 2 != 0:
                err(f"{s.id}: face {v} is not even")
        if s.w <= 0 or s.d <= 0:
            err(f"{s.id}: empty rectangle")
    for i in range(len(ids)):
        for j in range(i + 1, len(ids)):
            a, b = SPACES[ids[i]], SPACES[ids[j]]
            if a.top + 1 <= b.y0 - 1 or b.top + 1 <= a.y0 - 1:
                continue
            gx = max(a.x0 - b.x1, b.x0 - a.x1)
            gz = max(a.z0 - b.z1, b.z0 - a.z1)
            if gx < 0 and gz < 0:
                err(f"{a.id} and {b.id} overlap")
            elif 0 <= max(gx, gz) < WALL - 1e-6 and min(gx, gz) < 0:
                err(f"{a.id} and {b.id} are {max(gx, gz)} apart (walls are {WALL} thick)")
    for o in OPENINGS:
        g = opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        if o.at < lo + 1 - 1e-6 or o.at + o.width > hi - 1 + 1e-6:
            if not any(side in SPACES[x].open for x, side in ((o.a, side_a), (o.b, side_b))):
                err(f"opening {o.a}-{o.b} at {o.at}: too close to the end of the shared wall {lo}..{hi}")
        base = opening_base(o)
        for sid in (o.a, o.b):
            s = SPACES[sid]
            if base < s.y0 - 1e-6 or base + open_height(o) > s.ceil + 1e-6:
                err(f"opening {o.a}-{o.b}: doesn't fit {sid}'s height (base {base}, ceiling {s.ceil})")
    by_wall: dict = {}
    for o in OPENINGS:
        g = opening_geometry(o)
        if g:
            by_wall.setdefault((round(g[2], 3), g[0] in "NS"), []).append(o)
    for lst in by_wall.values():
        for i in range(len(lst)):
            for j in range(i + 1, len(lst)):
                p, q = lst[i], lst[j]
                if abs(opening_base(p) - opening_base(q)) > 12:
                    continue
                if p.at < q.at + q.width + 2 and q.at < p.at + p.width + 2:
                    err(f"openings {p.a}-{p.b} and {q.a}-{q.b} overlap on their wall")


# ------------------------------------------------------------------------------------------------------
# Structure: a solid block with every space, doorway and window carved out of it.


def wall_cuts():
    """Every cut through a wall: (x0, x1, z0, z1, y0, y1)."""
    cuts = []
    for o in OPENINGS:
        g = opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        base = opening_base(o)
        top = base + open_height(o)
        if side_a in "NS":
            cuts.append((o.at, o.at + o.width, line - 1, line + 1, base, top))
        else:
            cuts.append((line - 1, line + 1, o.at, o.at + o.width, base, top))
    for gz in GLAZING:
        side_a, side_b, line, lo, hi = shared_wall(SPACES[gz["a"]], SPACES[gz["b"]])
        if side_a in "NS":
            cuts.append((gz["from"], gz["to"], line - 1, line + 1, gz["base"], gz["top"]))
        else:
            cuts.append((line - 1, line + 1, gz["from"], gz["to"], gz["base"], gz["top"]))
    for ex in EXTERIOR:
        s = SPACES[ex["space"]]
        f = face_coord(s, ex["side"])
        y0, y1 = s.y0 + ex["sill"], s.y0 + ex["head"]
        if ex["side"] == "N":
            cuts.append((ex["from"], ex["to"], f - WALL, f, y0, y1))
        elif ex["side"] == "S":
            cuts.append((ex["from"], ex["to"], f, f + WALL, y0, y1))
        elif ex["side"] == "W":
            cuts.append((f - WALL, f, ex["from"], ex["to"], y0, y1))
        else:
            cuts.append((f, f + WALL, ex["from"], ex["to"], y0, y1))
    return cuts


def build_structure(extra_voids=()):
    """Carves spaces, openings and windows out of a block 2 studs bigger than the spaces all round, then
    merges what's left into as few boxes as it can. extra_voids: (x0, x1, z0, z1, y0, y1) carved too."""
    import numpy as np

    x_lo = int(min(s.x0 for s in SPACES.values()) - WALL)
    x_hi = int(max(s.x1 for s in SPACES.values()) + WALL)
    z_lo = int(min(s.z0 for s in SPACES.values()) - WALL)
    z_hi = int(max(s.z1 for s in SPACES.values()) + WALL)
    y_lo, y_hi = -4.0, max(s.top for s in SPACES.values()) + 2
    ys = {y_lo, y_hi}
    for s in SPACES.values():
        ys.update((s.y0 - 1, s.top + 1))
    cuts = wall_cuts() + list(extra_voids)
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
                solid[int(math.floor(c[0] - x_lo)):int(math.ceil(c[1] - x_lo)), int(math.floor(c[2] - z_lo)):int(math.ceil(c[3] - z_lo))] = False
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
        box("Mass", "Map/Geometry/Structure", i0 + x_lo, i1 + x_lo, y0, y1, j0 + z_lo, j1 + z_lo, mat="Concrete", color="mass")
    return len(blocks)


# ------------------------------------------------------------------------------------------------------
# Finishes. Each wall face gets a skin (paint, panelling, block, tile) from the floor to the ceiling,
# split round doorways and windows, with a base along the floor. Two-tone styles split at `split`.

FINISH = {
    # style: lower (mat, var, colour), upper, split height, base (mat, var, colour, height, depth), rail
    "office": {"upper": ("Plaster", "AxiomPlaster", "paint"), "base": ("Rubber", "AxiomRubber", (36, 36, 38), 0.5, 0.06)},
    "cool": {"upper": ("Plaster", "AxiomPlaster", "paintCool"), "base": ("Rubber", "AxiomRubber", (36, 36, 38), 0.5, 0.06)},
    "white": {"upper": ("Plaster", "AxiomPlaster", "paintWhite"), "base": ("Rubber", "AxiomRubber", (40, 40, 42), 0.5, 0.06)},
    "exec": {"lower": ("Wood", "AxiomWood", "wood"), "upper": ("Plaster", "AxiomPlaster", (112, 104, 94)), "split": 3.6,
             "rail": ("Wood", "AxiomWood", "woodDark", 0.3, 0.12), "base": ("Wood", "AxiomWood", "woodDark", 0.6, 0.1)},
    "lobby": {"lower": ("Wood", "AxiomWood", "woodDark"), "upper": ("Plaster", "AxiomPlaster", (98, 94, 88)), "split": 10,
              "rail": ("Metal", "AxiomSteel", "steel", 0.15, 0.06), "base": ("Marble", "AxiomTerrazzo", "terrazzoDark", 0.6, 0.08)},
    "atrium": {"lower": ("Marble", "AxiomTerrazzo", (86, 84, 80)), "upper": ("Plaster", "AxiomPlaster", (92, 90, 86)), "split": 14,
               "rail": ("Metal", "AxiomSteel", "steelDark", 0.3, 0.08)},
    "corridor": {"lower": ("Plaster", "AxiomPlaster", (82, 84, 86)), "upper": ("Plaster", "AxiomPlaster", "paint"), "split": 3.2,
                 "rail": ("Metal", "AxiomSteel", "steel", 0.35, 0.18), "base": ("Rubber", "AxiomRubber", (30, 30, 32), 0.5, 0.06)},
    "block": {"lower": ("Brick", "AxiomBlock", "blockLow"), "upper": ("Brick", "AxiomBlock", "block"), "split": 4,
              "rail": ("SmoothPlastic", None, (150, 120, 40), 0.25, 0.02)},
    "blockplain": {"upper": ("Brick", "AxiomBlock", (96, 98, 96))},
    "tile": {"upper": ("CeramicTiles", "AxiomTile", "tileWhite"), "lower": ("CeramicTiles", "AxiomTile", "tileGrey"), "split": 1.0},
    "server": {"upper": ("Plaster", "AxiomPlaster", (128, 132, 134)), "base": ("Rubber", "AxiomRubber", (30, 30, 32), 0.5, 0.06)},
    "lab": {"lower": ("Plaster", "AxiomPlaster", (70, 76, 80)), "upper": ("Plaster", "AxiomPlaster", (132, 134, 132)), "split": 4,
            "rail": ("SmoothPlastic", None, (160, 130, 40), 0.25, 0.02)},
    "car": {"lower": ("Metal", "AxiomSteel", (120, 122, 124)), "upper": ("Metal", "AxiomSteel", (150, 152, 154)), "split": 3.4,
            "rail": ("Metal", "AxiomSteel", (190, 190, 190), 0.25, 0.3)},
}

FLOORS = {
    # finish: (material, variant, colour, reflectance)
    "carpet": ("Carpet", "AxiomCarpet", "carpet", 0),
    "carpetDark": ("Carpet", "AxiomCarpet", "carpetDark", 0),
    "carpetWarm": ("Carpet", "AxiomCarpet", "carpetRed", 0),
    "terrazzo": ("Marble", "AxiomTerrazzo", "terrazzo", 0.08),
    "terrazzoDark": ("Marble", "AxiomTerrazzo", "terrazzoDark", 0.06),
    "concrete": ("Concrete", "AxiomConcrete", "concrete", 0),
    "concreteDark": ("Concrete", "AxiomConcrete", "concreteDark", 0),
    "epoxy": ("Concrete", "AxiomConcrete", (78, 84, 86), 0.04),
    "vinyl": ("Slate", "AxiomVinyl", "vinyl", 0.02),
    "raised": ("Slate", "AxiomVinyl", "raised", 0.02),
    "tile": ("CeramicTiles", "AxiomTile", "tileGrey", 0.03),
    "tread": ("DiamondPlate", "AxiomTread", (52, 54, 58), 0),
}


def wall_cut_list(s: Space, side: str):
    """Doorways and windows on one side of a space: (u0, u1, y0, y1) with y relative to the space's floor."""
    out = []
    for o in OPENINGS:
        for me in (o.a, o.b):
            if me != s.id:
                continue
            g = opening_geometry(o)
            if not g:
                continue
            my_side = g[0] if me == o.a else g[1]
            if my_side == side:
                base = opening_base(o) - s.y0
                out.append((o.at, o.at + o.width, base, base + open_height(o)))
    for gz in GLAZING:
        for me in (gz["a"], gz["b"]):
            if me != s.id:
                continue
            g = shared_wall(SPACES[gz["a"]], SPACES[gz["b"]])
            my_side = g[0] if me == gz["a"] else g[1]
            if my_side == side:
                out.append((gz["from"], gz["to"], gz["base"] - s.y0, gz["top"] - s.y0))
    for ex in EXTERIOR:
        if ex["space"] == s.id and ex["side"] == side:
            out.append((ex["from"], ex["to"], ex["sill"], ex["head"]))
    return sorted(out)


def skin_part(s: Space, side: str, u0: float, u1: float, y0: float, y1: float, depth0: float, depth1: float, spec, name, folder):
    """A finish block on a wall: u along the wall, y above the space floor, depth in front of the face."""
    mat, var, col = spec[0], spec[1], spec[2]
    f = face_coord(s, side)
    sign = 1 if side in "NW" else -1  # +1: the room is on the + side of the face
    a, b = f + sign * depth0, f + sign * depth1
    lo, hi = min(a, b), max(a, b)
    if side in "NS":
        return box(name, folder, u0, u1, s.y0 + y0, s.y0 + y1, lo, hi, mat=mat, color=col, var=var or "")
    return box(name, folder, lo, hi, s.y0 + y0, s.y0 + y1, u0, u1, mat=mat, color=col, var=var or "")


def finish_walls(s: Space):
    style = FINISH[s.walls]
    folder = geo(s.id)
    ceil_h = s.ceil - s.y0
    for side in "NSWE":
        if side in s.open:
            continue
        lo, hi = side_range(s, side)
        if side in "WE":
            lo, hi = lo + SKIN, hi - SKIN
        cuts = wall_cut_list(s, side)
        edges = sorted({lo, hi, *[max(lo, min(hi, c[0])) for c in cuts], *[max(lo, min(hi, c[1])) for c in cuts]})
        runs = []  # (u0, u1, [(y0, y1) wall intervals])
        for a, b in zip(edges, edges[1:]):
            if b - a < 1e-6:
                continue
            mid = (a + b) / 2
            holes = sorted((c[2], c[3]) for c in cuts if c[0] < mid < c[1])
            spans = []
            y = 0.0
            for (h0, h1) in holes:
                if h0 > y + 1e-6:
                    spans.append((y, min(h0, ceil_h)))
                y = max(y, h1)
            if y < ceil_h - 1e-6:
                spans.append((y, ceil_h))
            spans = [(p, q) for (p, q) in spans if q - p > 1e-6]
            if runs and runs[-1][2] == spans and abs(runs[-1][1] - a) < 1e-6:
                runs[-1] = (runs[-1][0], b, spans)
            else:
                runs.append((a, b, spans))
        split = style.get("split")
        for (u0, u1, spans) in runs:
            for (y0, y1) in spans:
                if split and "lower" in style and y0 < split < y1:
                    skin_part(s, side, u0, u1, y0, split, 0, SKIN, style["lower"], "WallLower", folder)
                    skin_part(s, side, u0, u1, split, y1, 0, SKIN, style["upper"], "Wall", folder)
                elif split and "lower" in style and y1 <= split:
                    skin_part(s, side, u0, u1, y0, y1, 0, SKIN, style["lower"], "WallLower", folder)
                else:
                    skin_part(s, side, u0, u1, y0, y1, 0, SKIN, style["upper"], "Wall", folder)
                if "rail" in style and split and y0 <= split - style["rail"][3] and y1 >= split:
                    r = style["rail"]
                    skin_part(s, side, u0, u1, split - r[3] / 2, split + r[3] / 2, SKIN, SKIN + r[4], (r[0], r[1], r[2]), "Rail", folder)
                if "base" in style and y0 < 1e-6:
                    bs = style["base"]
                    skin_part(s, side, u0, u1, 0, bs[3], SKIN, SKIN + bs[4], (bs[0], bs[1], bs[2]), "Base", folder)


def floor_and_ceiling(s: Space, holes=()):
    """The floor finish, the structural ceiling, and the finished ceiling (a drop ceiling with any missing
    tiles in `holes`: (x0, x1, z0, z1) rectangles)."""
    mat, var, col, refl = FLOORS[s.floor]
    flags = {"refl": refl} if refl else {}
    box("Floor", geo(s.id), s.x0, s.x1, s.y0 - 1, s.y0, s.z0, s.z1, mat=mat, color=col, var=var, **flags)
    box("Slab", geo(s.id), s.x0, s.x1, s.top, s.top + 1, s.z0, s.z1, mat="Concrete", color="slab", var="AxiomConcrete")
    if s.ceiling == "tile":
        y = s.ceil
        for (x0, x1, z0, z1) in rect_minus(s.x0, s.x1, s.z0, s.z1, holes):
            box("CeilingTile", geo(s.id), x0, x1, y, y + 0.2, z0, z1, mat="Limestone", color="ceiling", var="AxiomCeiling", ns=True)
        for (x0, x1, z0, z1) in holes:
            # The grid stays where a tile is missing; the plenum above is dark.
            box("CeilingGrid", geo(s.id), x0 - 0.05, x0 + 0.05, y, y + 0.15, z0, z1, mat="Metal", color=(170, 170, 166), nc=True, ns=True)
            box("CeilingGrid", geo(s.id), x1 - 0.05, x1 + 0.05, y, y + 0.15, z0, z1, mat="Metal", color=(170, 170, 166), nc=True, ns=True)
    elif s.ceiling == "plaster" and s.drop:
        box("Ceiling", geo(s.id), s.x0, s.x1, s.ceil, s.ceil + 0.3, s.z0, s.z1, mat="Plaster", color=(84, 84, 82), var="AxiomPlaster", ns=True)


def rect_minus(x0, x1, z0, z1, holes):
    """Rectangles covering [x0,x1]x[z0,z1] minus `holes`, as x-strips."""
    xs = sorted({x0, x1, *[max(x0, min(x1, h[0])) for h in holes], *[max(x0, min(x1, h[1])) for h in holes]})
    out = []
    for a, b in zip(xs, xs[1:]):
        if b - a < 1e-6:
            continue
        mid = (a + b) / 2
        hz = sorted((h[2], h[3]) for h in holes if h[0] < mid < h[1])
        z = z0
        for (h0, h1) in hz:
            if h0 > z + 1e-6:
                out.append((a, b, z, h0))
            z = max(z, h1)
        if z < z1 - 1e-6:
            out.append((a, b, z, z1))
    # Merge strips with the same z range side by side.
    merged = []
    for r in sorted(out, key=lambda r: (r[2], r[3], r[0])):
        if merged and merged[-1][2] == r[2] and merged[-1][3] == r[3] and abs(merged[-1][1] - r[0]) < 1e-6:
            merged[-1] = (merged[-1][0], r[1], r[2], r[3])
        else:
            merged.append(r)
    return merged


# ------------------------------------------------------------------------------------------------------
# Placement checks: footprints of floor pieces, keep-outs in front of doorways, wall-piece overlaps.

FOOT: dict = {}  # space -> [(x0, x1, z0, z1, label)]
KEEPOUT: dict = {}  # space -> [(x0, x1, z0, z1)]
WALLUSE: dict = {}  # (space, side) -> [(u0, u1, y0, y1)]


def dims(name):
    if name not in DIMS:
        raise KeyError(f"no dims for {name}")
    return DIMS[name]


def footprint(name, x, z, yaw):
    sx, sy, sz, cx, cy, cz = dims(name)
    pts = [to_world(x, z, yaw, cx + ax * sx / 2, cz + az * sz / 2) for ax in (-1, 1) for az in (-1, 1)]
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return (min(xs), max(xs), min(zs), max(zs))


def overlaps(a, b, m=0.0):
    return a[0] < b[1] - m and b[0] < a[1] - m and a[2] < b[3] - m and b[2] < a[3] - m


def keepout(sid, x0, x1, z0, z1):
    KEEPOUT.setdefault(sid, []).append((min(x0, x1), max(x0, x1), min(z0, z1), max(z0, z1)))


def door_keepouts():
    """Nothing may stand in front of a doorway: 7 deep (9 for wide ones) and 2 wider each side."""
    for s in SPACES.values():
        for side in "NSWE":
            for o in OPENINGS:
                for me in (o.a, o.b):
                    if me != s.id:
                        continue
                    g = opening_geometry(o)
                    if not g:
                        continue
                    my_side = g[0] if me == o.a else g[1]
                    if my_side != side or opening_base(o) > s.y0 + 1e-6:
                        continue
                    depth = 9 if o.width > 8 else 7
                    a = wall_xz(s, side, o.at - 2, 0)
                    b = wall_xz(s, side, o.at + o.width + 2, depth)
                    keepout(s.id, a[0], b[0], a[1], b[1])


# Pieces with a working front (where people stand, sit or reach in): the floor in front of each must stay
# clear of walls and of other pieces, so nothing faces a wall or gets boxed in. Depth in studs.
FRONT_DEPTH = {
    "OfficeDesk": 2.6, "OfficeDeskOpen": 2.6, "Workbench": 2.6, "ControlConsole_8": 2.6, "MainframeTerminal": 3.2,
    "ShellDock": 2.0, "StorageShelf_6": 2.3, "Bookshelf": 2.0, "FilingCabinet": 1.8, "Locker_Double": 2.0,
    "PartsRack": 2.3, "PalletRack": 3.4, "Counter": 2.3, "Fridge": 2.3, "VendingMachine": 2.3, "Copier": 2.0,
    "WaterCooler": 1.4, "Switchgear": 2.3, "BatteryRack": 2.0, "ServerRack_A": 2.6, "ServerRack_B": 2.6,
    "CoolingUnit": 2.3, "Credenza": 1.4, "Vanity": 2.0, "DisplayCase": 1.4, "ToolChest": 1.8, "RollCage": 1.4,
    "Compactor": 2.3, "AirHandler": 2.3, "ResinRack": 2.0, "Sofa": 1.0, "SofaFabric": 1.0, "Bench": 1.0,
    "SecurityPodium": 1.6, "CrashCart": 1.2, "GasTank": 0.8,
}
FRONTS: dict = {}  # space -> [(x0, x1, z0, z1, label)]: the floor in front of each fronted piece


def front_rect(name, x, z, yaw):
    """The strip of floor in front of a fronted piece (its -Z side), 90% of its width."""
    depth = FRONT_DEPTH.get(name)
    if not depth:
        return None
    sx, sy, sz, cx, cy, cz = dims(name)
    zf = cz - sz / 2
    pts = [to_world(x, z, yaw, cx + ax * sx * 0.45, zf - d) for ax in (-1, 1) for d in (0.05, depth)]
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    return (min(xs), max(xs), min(zs), max(zs))


def seat(label: str) -> bool:
    """Chairs may stand in front of desks and tables (that's where they go)."""
    return "chair" in label.lower()


def fits(sid, name, x, z, yaw, label=None) -> bool:
    """Would a floor piece fit here: inside the room, clear of doorways, other pieces and their fronts, with
    its own front clear?"""
    s = SPACES[sid]
    rect = footprint(name, x, z, yaw)
    lab = label or name
    if rect[0] < s.x0 + 0.15 or rect[1] > s.x1 - 0.15 or rect[2] < s.z0 + 0.15 or rect[3] > s.z1 - 0.15:
        return False
    if any(overlaps(rect, k, 0.05) for k in KEEPOUT.get(sid, [])):
        return False
    if any(overlaps(rect, f, 0.05) for f in FOOT.get(sid, [])):
        return False
    if not seat(lab) and any(overlaps(rect, f, 0.05) for f in FRONTS.get(sid, [])):
        return False
    fr = front_rect(name, x, z, yaw)
    if fr:
        if fr[0] < s.x0 or fr[1] > s.x1 or fr[2] < s.z0 or fr[3] > s.z1:
            return False
        if any(overlaps(fr, f, 0.05) for f in FOOT.get(sid, []) if not seat(f[4])):
            return False
    return True


def claim(sid, rect, label, check=True, front=None):
    s = SPACES[sid]
    if check:
        if rect[0] < s.x0 + 0.1 or rect[1] > s.x1 - 0.1 or rect[2] < s.z0 + 0.1 or rect[3] > s.z1 - 0.1:
            err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} pokes into a wall")
        for k in KEEPOUT.get(sid, []):
            if overlaps(rect, k, 0.05):
                err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} blocks a doorway or a path")
                break
        for f in FOOT.get(sid, []):
            if overlaps(rect, f, 0.05):
                err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} overlaps {f[4]}")
                break
        if not seat(label):
            for f in FRONTS.get(sid, []):
                if overlaps(rect, f, 0.05):
                    err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} stands in front of {f[4]}")
                    break
    if front:
        fr = front_rect(*front)
        if fr:
            if check:
                if fr[0] < s.x0 or fr[1] > s.x1 or fr[2] < s.z0 or fr[3] > s.z1:
                    err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} faces a wall")
                for f in FOOT.get(sid, []):
                    if not seat(f[4]) and overlaps(fr, f, 0.05):
                        err(f"{sid}: {label} at {tuple(round(v, 1) for v in rect)} faces {f[4]} too closely")
                        break
            FRONTS.setdefault(sid, []).append((*fr, label))
    FOOT.setdefault(sid, []).append((*rect, label))


def wall_free(s: Space, side: str, u0, u1, y0, y1, what: str, report=True) -> bool:
    lo, hi = side_range(s, side)
    if u0 < lo - 1e-6 or u1 > hi + 1e-6:
        if report:
            err(f"{s.id} {side}: {what} at {u0:.1f}..{u1:.1f} runs off the wall ({lo}..{hi})")
        return False
    for (a, b, c0, c1) in wall_cut_list(s, side):
        if u0 < b + 0.6 and u1 > a - 0.6 and y0 < s.y0 + c1 + 0.3 and y1 > s.y0 + c0:
            if report:
                err(f"{s.id} {side}: {what} at {u0:.1f}..{u1:.1f} covers a doorway or window")
            return False
    for (a, b, c, d) in WALLUSE.get((s.id, side), []):
        if u0 < b and u1 > a and y0 < d and y1 > c:
            if report:
                err(f"{s.id} {side}: {what} at {u0:.1f}..{u1:.1f} overlaps another wall piece")
            return False
    return True


Z_WALL = SKIN + 0.02  # wall pieces hang on the finish


def on_wall(sid, side, u, name, y=0.0, folder=None, depth=Z_WALL, check=True, **opts):
    """A wall-mounted piece facing into the room; `y` is its pivot height above the floor."""
    s = SPACES[sid]
    sx, sy, sz, cx, cy, cz = dims(name)
    w0, w1 = u - sx / 2 + cx, u + sx / 2 + cx
    if side in "NE":
        w0, w1 = u - sx / 2 - cx, u + sx / 2 - cx
    yb0, yb1 = s.y0 + y + cy - sy / 2, s.y0 + y + cy + sy / 2
    if check:
        wall_free(s, side, w0, w1, yb0, yb1, name)
    WALLUSE.setdefault((sid, side), []).append((w0, w1, yb0, yb1))
    x, z = wall_xz(s, side, u, depth)
    return piece(name, folder or props(sid), x, s.y0 + y, z, side_yaw(side), **opts)


def against(sid, side, u, name, gap=0.3, folder=None, label=None, check=True, y=None, **opts):
    """A floor piece backed against a wall, facing into the room."""
    s = SPACES[sid]
    sx, sy, sz, cx, cy, cz = dims(name)
    back = cz + sz / 2
    x, z = wall_xz(s, side, u, SKIN + gap + back)
    yaw = side_yaw(side)
    claim(sid, footprint(name, x, z, yaw), label or name, check, front=(name, x, z, yaw))
    return piece(name, folder or props(sid), x, s.y0 if y is None else y, z, yaw, **opts)


def floor_piece(sid, name, x, z, yaw=0.0, folder=None, label=None, check=True, y=None, claim_it=True, **opts):
    s = SPACES[sid]
    if claim_it:
        claim(sid, footprint(name, x, z, yaw), label or name, check, front=(name, x, z, yaw))
    return piece(name, folder or props(sid), x, s.y0 if y is None else y, z, yaw, **opts)


def ceiling_piece(sid, name, x, z, yaw=0.0, drop=0.0, folder=None, **opts):
    s = SPACES[sid]
    return piece(name, folder or props(sid), x, s.ceil - drop, z, yaw, **opts)


# ------------------------------------------------------------------------------------------------------
# Game contract helpers

CAMERAS: list = []
DOCK_LIST: list = []


def camera(cam_id, sid, side, u, aim, name, head=None, pan=None, tilt=None):
    s = SPACES[sid]
    head_y = head if head is not None else s.ceil - s.y0 - 1.2
    attrs = {"CameraId": cam_id, "Room": s.room, "DisplayName": name, "Links": ""}
    if pan:
        attrs["PanLimit"] = pan
    if tilt:
        attrs["TiltLimit"] = tilt
    rec = on_wall(sid, side, u, "SecurityCamera", head_y - 12, "Facility/Cameras", id=cam_id, a=attrs,
                  aim=[aim[0], aim[1], aim[2]])
    CAMERAS.append({"id": cam_id, "room": s.room, "rec": rec})
    return rec


def dock(dock_id, sid, side, u, name, gap=0.3):
    s = SPACES[sid]
    rec = against(sid, side, u, "ShellDock", gap=gap, folder="Map/Docks", label=dock_id, id=dock_id,
                  a={"DockId": dock_id, "TargetId": dock_id, "Room": s.room, "DisplayName": name})
    DOCK_LIST.append(dock_id)
    return rec


def terminal(term_id, sid, side, u, name, gap=0.4):
    s = SPACES[sid]
    return against(sid, side, u, "MainframeTerminal", gap=gap, folder="Map/Terminals", label=term_id, id=term_id,
                   a={"TerminalId": term_id, "TargetId": term_id, "Room": s.room, "DisplayName": name, "Progress": 0})


def station(st_id, sid, side, u):
    return against(sid, side, u, "ChargingStation", gap=0.2, folder="Facility/Stations", label=st_id, id=st_id,
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


def room_bounds(r: Room):
    sp = [SPACES[i] for i in r.spaces]
    return (min(s.x0 for s in sp), max(s.x1 for s in sp), min(s.y0 for s in sp), max(s.top for s in sp),
            min(s.z0 for s in sp), max(s.z1 for s in sp))


def game_rooms(no_emergency=("CORE", "INSERTION", "FAB")):
    for r in ROOMS.values():
        x0, x1, y0, y1, z0, z1 = room_bounds(r)
        GAME["rooms"].append({"id": r.id, "name": r.name, "wing": r.wing,
                              "c": [rnd((x0 + x1) / 2), rnd((y0 + y1) / 2), rnd((z0 + z1) / 2)],
                              "s": [rnd(x1 - x0), rnd(y1 - y0), rnd(z1 - z0)],
                              "emergency": r.wing not in no_emergency})
    rs = list(ROOMS.values())
    for i in range(len(rs)):
        for j in range(i + 1, len(rs)):
            a, b = room_bounds(rs[i]), room_bounds(rs[j])
            if a[0] < b[1] and b[0] < a[1] and a[2] < b[3] and b[2] < a[3] and a[4] < b[5] and b[4] < a[5]:
                err(f"room boxes {rs[i].id} and {rs[j].id} overlap")
