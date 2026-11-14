"""The prop library: everything that makes Axiom Tower look lived in, as prefabs (see core.Prefab).

Pivots follow the kit: floor props at the bottom centre, wall props at the bottom centre of the back, desk
props on a desk top (2.8 high), ceiling props at the top centre; the front faces -Z.

Light fixtures name their glowing part Fixture (Blackout and gunfire turn it off), so a placed fixture goes
in its room's Lights folder. Emergency packs name their heads Lamp (a rebooted terminal lights them).
Nothing glows red: red belongs to the Chimera.
"""
from __future__ import annotations

import math

from .core import C, DIMS, PREFABS, Prefab, gui, hash01, light

DESK_H = 2.8

WOOD = ("Wood", "AxiomWood")
PLASTER = ("Plaster", "AxiomPlaster")
FABRIC = ("Fabric", "AxiomFabric")
LEATHER = ("Leather", "AxiomLeather")
STEEL = ("Metal", "AxiomSteel")
RUBBER = ("Rubber", "AxiomRubber")
CARD = ("Cardboard", "AxiomCardboard")
TILE = ("CeramicTiles", "AxiomTile")

LENS_COOL = (205, 214, 220)
LENS_WARM = (240, 214, 170)
LIGHT_COOL = (214, 228, 240)
LIGHT_WARM = (255, 210, 160)
LIGHT_SODIUM = (255, 176, 96)


def m(spec):
    return {"mat": spec[0], "var": spec[1]}


# ------------------------------------------------------------------------------------------------------
# Light fixtures


def fixtures():
    # 2 x 4 lay-in troffer in a drop ceiling: a steel housing and a prismatic lens.
    p = Prefab("Troffer", "Ceiling")
    p.box("Housing", (2.2, 0.1, 4.2), (0, -0.05, 0), (176, 176, 172), "Metal", ns=1)
    lens = p.box("Fixture", (1.9, 0.06, 3.9), (0, -0.09, 0), LENS_COOL, "Neon", ns=1)
    lens["light"] = light("surface", LIGHT_COOL, 18, 0.9, face="Bottom", angle=120)
    p.done()

    # Recessed downlight (a can).
    p = Prefab("Downlight", "Ceiling")
    p.cyl("Trim", 0.08, 1.4, (0, -0.04, 0), (150, 150, 148), "Metal", ns=1)
    lens = p.cyl("Fixture", 0.05, 0.9, (0, -0.09, 0), (214, 190, 150), "Neon", ns=1)
    lens["light"] = light("spot", LIGHT_WARM, 26, 1.6, face="Left", angle=75)  # the cylinder's -X end faces down
    p.done()

    # A linear pendant on two cables (`drop` studs below the ceiling).
    for name, drop in (("Pendant", 3.0), ("PendantLong", 12.0)):
        p = Prefab(name, "Ceiling")
        for x in (-3.2, 3.2):
            p.cyl("Cable", drop, 0.04, (x, -drop / 2, 0), (20, 20, 22), "Metal", ns=1)
        p.box("Body", (7.6, 0.35, 0.55), (0, -drop - 0.175, 0), (24, 24, 26), "Metal")
        lens = p.box("Fixture", (7.3, 0.05, 0.36), (0, -drop - 0.37, 0), LENS_WARM, "Neon", ns=1)
        lens["light"] = light("surface", LIGHT_WARM, 22, 1.1, face="Bottom", angle=110)
        p.done()

    # A bare fluorescent batten (back of house).
    p = Prefab("Batten", "Ceiling")
    p.box("Channel", (4.2, 0.25, 0.4), (0, -0.125, 0), (150, 150, 146), "Metal")
    tube = p.cyl("Fixture", 4.0, 0.2, (0, -0.33, 0), (215, 225, 222), "Neon", axis="x", ns=1)
    tube["light"] = light("point", (220, 235, 232), 16, 0.8)
    p.done()

    # A caged vapour-tight jar light (tunnels, plant rooms).
    p = Prefab("JarLight", "Ceiling")
    p.cyl("Base", 0.3, 0.9, (0, -0.15, 0), (40, 42, 40), "Metal")
    globe = p.ball("Fixture", 0.75, (0, -0.65, 0), (255, 196, 130), "Neon", ns=1)
    globe["light"] = light("point", LIGHT_SODIUM, 18, 0.9)
    for a in range(4):
        r = math.radians(a * 90 + 45)
        p.box("Cage", (0.05, 0.85, 0.05), (math.cos(r) * 0.42, -0.65, math.sin(r) * 0.42), (40, 42, 40), "Metal", ns=1)
    p.done()

    # Industrial high-bay dome.
    p = Prefab("HighBay", "Ceiling")
    p.cyl("Hook", 1.2, 0.08, (0, -0.6, 0), (30, 30, 32), "Metal", ns=1)
    p.cyl("Driver", 0.8, 1.0, (0, -1.6, 0), (44, 46, 48), "Metal")
    p.cyl("Dome", 0.9, 2.6, (0, -2.4, 0), (70, 74, 76), "Metal")
    lens = p.cyl("Fixture", 0.06, 2.3, (0, -2.88, 0), (225, 232, 236), "Neon", ns=1)
    lens["light"] = light("spot", (220, 232, 240), 40, 1.6, face="Left", angle=100)  # the cylinder's -X end faces down
    p.done()

    # Wall sconce (lobby, corridors).
    p = Prefab("Sconce", "Wall")
    p.box("Plate", (0.5, 1.4, 0.1), (0, 7.0, -0.05), (60, 58, 54), "Metal")
    shade = p.box("Fixture", (0.9, 1.4, 0.45), (0, 7.0, -0.32), (196, 160, 118), "Neon", ns=1)
    shade["t"] = 0.15
    shade["light"] = light("point", LIGHT_WARM, 14, 0.7)
    p.done()

    # Desk lamp (on a desk top).
    p = Prefab("DeskLamp", "Desk")
    p.cyl("Base", 0.12, 0.7, (0, 0.06, 0.1), (30, 30, 32), "Metal")
    p.cyl("Arm", 1.5, 0.08, (0, 0.8, 0.25), (30, 30, 32), "Metal", rot=(0, 0, 80))
    p.cyl("Arm2", 1.0, 0.08, (0, 1.5, -0.15), (30, 30, 32), "Metal", rot=(0, 90, 30))
    p.box("Head", (0.5, 0.25, 0.7), (0, 1.55, -0.6), (30, 30, 32), "Metal", rot=(-20, 0, 0))
    bulb = p.box("Fixture", (0.38, 0.04, 0.5), (0, 1.43, -0.63), (255, 226, 180), "Neon", rot=(-20, 0, 0), ns=1)
    bulb["light"] = light("spot", (255, 214, 160), 12, 1.2, face="Bottom", angle=80)
    p.done()

    # Floor lamp with a fabric shade.
    p = Prefab("FloorLamp")
    p.cyl("Base", 0.15, 1.2, (0, 0.075, 0), (30, 30, 30), "Metal")
    p.cyl("Pole", 5.2, 0.12, (0, 2.7, 0), (30, 30, 30), "Metal")
    p.cyl("Shade", 1.3, 1.5, (0, 5.6, 0), (190, 176, 150), "Fabric", var="AxiomFabric", t=0.1)
    bulb = p.ball("Fixture", 0.4, (0, 5.4, 0), (255, 220, 170), "Neon", ns=1)
    bulb["light"] = light("point", LIGHT_WARM, 14, 0.8)
    p.done()

    # A tripod work light someone left on.
    p = Prefab("WorkLight")
    for a in range(3):
        r = math.radians(a * 120)
        p.cyl("Leg", 3.4, 0.1, (math.cos(r) * 0.8, 1.55, math.sin(r) * 0.8), (180, 150, 40), "Metal", rot=(0, -a * 120, 70))
    p.cyl("Pole", 3.2, 0.12, (0, 4.4, 0), (40, 40, 40), "Metal")
    p.box("Head", (1.2, 0.9, 0.5), (0, 6.2, -0.1), (190, 150, 30), "SmoothPlastic", rot=(25, 0, 0))
    lens = p.box("Fixture", (1.0, 0.7, 0.05), (0, 6.12, -0.38), (255, 236, 200), "Neon", rot=(25, 0, 0), ns=1)
    lens["light"] = light("spot", (255, 236, 205), 36, 2.2, shadows=True, face="Front", angle=70)
    p.done()

    # The glowing face of a vending machine (the cabinet itself is VendingMachine, placed in Props).
    p = Prefab("VendingGlow")
    face = p.box("Fixture", (2.2, 4.6, 0.05), (-0.3, 3.4, -1.36), (200, 220, 226), "Neon", ns=1, nq=1)
    face["light"] = light("surface", (205, 228, 235), 12, 0.7, face="Front", angle=120)
    p.done()


def emergency():
    # Twin-head emergency light: both heads are Lamps, off until the wing's terminal is rebooted.
    p = Prefab("EmergencyPack", "Wall")
    p.box("Box", (1.6, 0.8, 0.5), (0, 10.0, -0.25), (196, 192, 180), "SmoothPlastic")
    p.box("Lens", (1.1, 0.2, 0.05), (0, 10.05, -0.51), (60, 60, 58), "SmoothPlastic", ns=1)
    for x in (-0.55, 0.55):
        lamp = p.cyl("Lamp", 0.4, 0.42, (x, 9.62, -0.55), (35, 35, 38), "SmoothPlastic", rot=(0, 90, -35), ns=1)
        lamp["light"] = light("spot", (255, 168, 80), 32, 1.4, face="Right", angle=80, off=True)
    p.box("Charge", (0.08, 0.08, 0.04), (0.6, 10.25, -0.51), (90, 255, 140), "Neon", ns=1)
    p.done()

    for name, hanging in (("ExitSign", False), ("ExitSignHanging", True)):
        p = Prefab(name, "Ceiling" if hanging else "Wall")
        y = -1.6 if hanging else 11.2
        z = 0 if hanging else -0.2
        body = p.box("Housing", (2.4, 1.0, 0.3), (0, y, z), (220, 220, 214), "SmoothPlastic")
        for fz, face in ((-0.16, "Front"), (0.16, "Back")) if hanging else ((-0.16, "Front"),):
            plate = p.box("Face", (2.2, 0.8, 0.02), (0, y, z + fz), (20, 60, 30), "SmoothPlastic", ns=1, nq=1)
            plate["gui"] = gui("EXIT", face, "Oswald", (110, 255, 150), light=0, bright=1.6, ppu=60, bold=True)
        if hanging:
            for x in (-0.8, 0.8):
                p.cyl("Rod", 1.1, 0.06, (x, -0.55, 0), (120, 120, 120), "Metal", ns=1)
        body["light"] = light("point", (90, 255, 140), 7, 0.5)
        p.done()


# ------------------------------------------------------------------------------------------------------
# Doors, frames, card readers, elevator doors

FRAME_STYLES = {
    "metal": ((58, 60, 64), "Metal", "AxiomSteel"),
    "wood": (C["woodDark"], "Wood", "AxiomWood"),
    "stone": ((92, 90, 86), "Marble", "AxiomTerrazzo"),
    "steel": ((150, 152, 154), "Metal", "AxiomSteel"),
    "block": ((96, 98, 96), "Brick", "AxiomBlock"),
}


def frame(w, h, style="metal"):
    """A doorway lining for a w x h opening in a 2-thick wall (doorway mount: the bottom centre of the
    opening on the wall's centre line): jambs and a head lining the cut, casings on both faces."""
    name = f"Frame_{int(w)}x{int(h)}_{style}"
    if name in PREFABS:
        return name
    col, mat, var = FRAME_STYLES[style]
    p = Prefab(name, "Doorway")
    depth = 2 + 2 * 0.1
    for s in (-1, 1):
        p.box("Jamb", (0.3, h, depth), (s * (w / 2 - 0.15), h / 2, 0), col, mat, var, solid=True)
    p.box("Head", (w, 0.3, depth), (0, h - 0.15, 0), col, mat, var, solid=True)
    if style != "stone":
        for fz in (-1, 1):
            z = fz * (1 + 0.1 + 0.05)
            for s in (-1, 1):
                p.box("Casing", (0.4, h + 0.4, 0.1), (s * (w / 2 + 0.2), (h + 0.4) / 2, z), col, mat, var)
            p.box("Casing", (w + 1.2, 0.4, 0.1), (0, h + 0.2, z), col, mat, var)
    p.done()
    return name


def doors():
    # Sliding doors for 8 x 10 openings: only Panel moves; everything on it is welded to it. LockLight1
    # and LockLight2 hang over the doorway on each face and show the lock (amber).
    def lock_lights(p):
        for i, fz in enumerate((-1, 1)):
            p.box(f"LockLight{i + 1}", (1.8, 0.22, 0.08), (0, 10.62, fz * 1.24), (45, 45, 48), "SmoothPlastic", ns=1)
            p.box("LockLightMount", (2.1, 0.4, 0.06), (0, 10.62, fz * 1.18), (40, 40, 42), "Metal", ns=1)

    def door_attrs(p):
        p.attrs = {"TargetKind": "LockDoor", "Slide": 8}

    # Office: walnut veneer with a narrow vision lite and steel pulls.
    p = Prefab("Door_Office", "Doorway")
    p.box("Panel", (8, 10, 0.45), (0, 5, 0), C["wood"], "Wood", "AxiomWood", solid=True)
    for fz in (-1, 1):
        z = fz * 0.235
        p.box("Lite", (0.9, 4.2, 0.03), (2.6, 6.0, z), (40, 52, 58), "Glass", t=0.35, weld="Panel")
        p.box("LiteFrame", (1.1, 4.4, 0.02), (2.6, 6.0, z * 0.98), (40, 40, 42), "Metal", weld="Panel", ns=1)
        p.cyl("Pull", 2.2, 0.12, (-3.0, 4.6, fz * 0.38), (170, 172, 176), "Metal", weld="Panel")
        for y in (3.6, 5.6):
            p.box("PullMount", (0.12, 0.12, 0.15), (-3.0, y, fz * 0.3), (170, 172, 176), "Metal", weld="Panel", ns=1)
        p.box("Kick", (7.6, 0.8, 0.02), (0, 0.45, z * 1.02), (130, 132, 134), "Metal", "AxiomSteel", weld="Panel", ns=1)
    lock_lights(p)
    p.done()

    # Steel security door with a wired-glass window and a push bar.
    p = Prefab("Door_Steel", "Doorway")
    p.box("Panel", (8, 10, 0.5), (0, 5, 0), (82, 86, 90), "Metal", "AxiomSteel", solid=True)
    for fz in (-1, 1):
        z = fz * 0.26
        p.box("Window", (1.6, 1.6, 0.03), (2.4, 6.4, z), (36, 46, 50), "Glass", t=0.3, weld="Panel")
        p.box("WindowFrame", (1.9, 1.9, 0.02), (2.4, 6.4, z * 0.98), (50, 52, 54), "Metal", weld="Panel", ns=1)
        p.box("Bar", (5.4, 0.3, 0.25), (0.2, 3.9, fz * 0.42), (150, 152, 150), "Metal", weld="Panel")
        p.box("Kick", (7.6, 1.2, 0.02), (0, 0.65, z * 1.02), (120, 122, 124), "DiamondPlate", "AxiomTread", weld="Panel", ns=1)
        stencil = p.box("Stencil", (3.6, 0.6, 0.02), (-1.0, 8.6, z * 1.03), (82, 86, 90), "SmoothPlastic", weld="Panel", t=1, ns=1, nq=1)
        stencil["gui"] = gui("AUTHORIZED PERSONNEL ONLY", "Front" if fz < 0 else "Back", "Oswald", (190, 190, 180), transp=0.2)
    lock_lights(p)
    p.done()

    # Glass sliding door in steel rails (the reception's office entrance).
    p = Prefab("Door_Glass", "Doorway")
    pane = p.box("Panel", (8, 10, 0.3), (0, 5, 0), (120, 150, 160), "Glass", solid=True)
    pane["t"] = 0.65
    p.box("Rail", (8, 0.6, 0.4), (0, 9.7, 0), (150, 152, 154), "Metal", "AxiomSteel", weld="Panel")
    p.box("Rail", (8, 0.5, 0.4), (0, 0.25, 0), (150, 152, 154), "Metal", "AxiomSteel", weld="Panel")
    for fz in (-1, 1):
        band = p.box("Frost", (7.6, 0.8, 0.02), (0, 5.0, fz * 0.16), (210, 214, 214), "SmoothPlastic", weld="Panel", t=0.45, ns=1, nq=1)
        band["gui"] = gui("A X I O M", "Front" if fz < 0 else "Back", "Zekton", (60, 64, 66), transp=0.3)
        p.cyl("Pull", 3.0, 0.14, (-3.2, 4.8, fz * 0.3), (170, 172, 176), "Metal", weld="Panel")
    lock_lights(p)
    p.done()

    # A badge reader beside a door; its LED shows the nearest door's state (KitDoorLight).
    p = Prefab("CardReader", "Wall")
    p.box("Body", (0.55, 0.95, 0.14), (0, 4.4, -0.07), (24, 24, 26), "SmoothPlastic")
    p.box("Pad", (0.4, 0.4, 0.02), (0, 4.25, -0.15), (40, 40, 44), "SmoothPlastic", ns=1)
    led = p.box("Led", (0.36, 0.07, 0.02), (0, 4.72, -0.15), (90, 255, 140), "Neon", ns=1, nq=1)
    led["tag"] = "KitDoorLight"
    p.done()

    # Elevator doors on a lobby wall: a stainless surround, two leaves, a floor display and call buttons.
    for name, gap in (("ElevatorDoors", 0.0), ("ElevatorDoorsAjar", 1.6)):
        p = Prefab(name, "Wall")
        w, h = 7.2, 10
        for s in (-1, 1):
            p.box("Surround", (0.7, h + 0.7, 0.25), (s * (w / 2 + 0.35), (h + 0.7) / 2, -0.125), (150, 152, 154), "Metal", "AxiomSteel")
        p.box("Surround", (w + 1.4, 0.7, 0.25), (0, h + 0.35, -0.125), (150, 152, 154), "Metal", "AxiomSteel")
        leaf = (w - gap) / 2
        for s in (-1, 1):
            x = s * (gap / 2 + leaf / 2)
            p.box("Leaf", (leaf, h, 0.2), (x, h / 2, -0.1), (128, 130, 132), "Metal", "AxiomSteel", solid=True)
            p.box("LeafLine", (0.03, h, 0.01), (s * (gap / 2 + 0.015), h / 2, -0.205), (60, 60, 62), "Metal", ns=1)
        if gap:
            # The shaft behind the gap: darkness and a hoist cable.
            p.box("Shaft", (gap + 0.4, h, 0.2), (0, h / 2, 0.15), (6, 6, 7), "SmoothPlastic", solid=True)
            p.cyl("Cable", h, 0.08, (0.2, h / 2, -0.02), (40, 40, 40), "Metal", ns=1)
        disp = p.box("Display", (1.6, 0.6, 0.06), (0, h + 1.3, -0.08), (14, 12, 10), "SmoothPlastic")
        disp["gui"] = gui("61" if not gap else "--", "Front", "Code", (255, 160, 60), light=0, bright=1.5, ppu=50)
        p.done()

    p = Prefab("CallButtons", "Wall")
    p.box("Plate", (0.6, 1.4, 0.06), (0, 4.4, -0.03), (150, 152, 154), "Metal", "AxiomSteel")
    for y in (4.75, 4.05):
        b = p.cyl("Button", 0.05, 0.34, (0, y, -0.08), (255, 230, 190), "Neon", axis="z", ns=1, nq=1)
    p.done()


# ------------------------------------------------------------------------------------------------------
# Lobby and lounge furniture


def lobby():
    for name, spec, col in (("Sofa", LEATHER, C["leather"]), ("SofaFabric", FABRIC, C["fabric"])):
        p = Prefab(name)
        p.box("Base", (7.6, 1.0, 3.0), (0, 0.7, 0.1), col, spec[0], spec[1], solid=True)
        p.box("Back", (7.6, 1.9, 0.5), (0, 2.15, 1.35), col, spec[0], spec[1], solid=True)
        for s in (-1, 1):
            p.box("Arm", (0.6, 1.05, 3.0), (s * 3.5, 1.72, 0.1), col, spec[0], spec[1], solid=True)
        for i, x in enumerate((-2.15, 0, 2.15)):
            p.box("Seat", (2.1, 0.45, 2.3), (x, 1.42, -0.2), col, spec[0], spec[1], rot=(0, 0, (i - 1) * 0.6))
            p.box("Cushion", (2.1, 1.4, 0.55), (x, 2.3, 0.95), col, spec[0], spec[1], rot=(-9, 0, 0))
        for sx in (-1, 1):
            for sz in (-1, 1):
                p.box("Foot", (0.25, 0.2, 0.25), (sx * 3.5, 0.1, sz * 1.3), (20, 20, 20), "Metal", ns=1)
        p.done()

    for name, spec, col in (("Armchair", LEATHER, C["leather"]), ("ArmchairFabric", FABRIC, C["fabric"])):
        p = Prefab(name)
        p.box("Base", (3.4, 1.0, 3.0), (0, 0.7, 0.1), col, spec[0], spec[1], solid=True)
        p.box("Back", (3.4, 1.9, 0.5), (0, 2.15, 1.35), col, spec[0], spec[1], solid=True)
        for s in (-1, 1):
            p.box("Arm", (0.55, 1.05, 3.0), (s * 1.42, 1.72, 0.1), col, spec[0], spec[1])
        p.box("Seat", (2.3, 0.45, 2.3), (0, 1.42, -0.2), col, spec[0], spec[1])
        p.box("Cushion", (2.3, 1.4, 0.55), (0, 2.3, 0.95), col, spec[0], spec[1], rot=(-9, 0, 0))
        for sx in (-1, 1):
            for sz in (-1, 1):
                p.box("Foot", (0.22, 0.2, 0.22), (sx * 1.4, 0.1, sz * 1.3), (20, 20, 20), "Metal", ns=1)
        p.done()

    p = Prefab("CoffeeTable")
    p.box("Top", (5.2, 0.22, 2.6), (0, 1.39, 0), C["woodDark"], "Wood", "AxiomWood", solid=True)
    p.box("Shelf", (4.8, 0.1, 2.2), (0, 0.45, 0), (40, 52, 56), "Glass", t=0.4)
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box("Leg", (0.18, 1.28, 0.18), (sx * 2.4, 0.64, sz * 1.1), (24, 24, 26), "Metal")
    p.done()

    p = Prefab("SideTable")
    p.cyl("Top", 0.15, 1.8, (0, 1.9, 0), C["woodDark"], "Wood", "AxiomWood", solid=True)
    p.cyl("Stem", 1.8, 0.2, (0, 0.95, 0), (24, 24, 26), "Metal")
    p.cyl("Foot", 0.1, 1.3, (0, 0.05, 0), (24, 24, 26), "Metal")
    p.done()

    p = Prefab("Rug")
    p.box("Rug", (14, 0.05, 9), (0, 0.025, 0), (54, 50, 48), "Carpet", "AxiomCarpet", ns=1, nq=1)
    p.box("Field", (12.6, 0.03, 7.6), (0, 0.06, 0), (70, 64, 58), "Carpet", "AxiomCarpet", ns=1, nq=1)
    p.done()

    for name, dead in (("PlanterTall", False), ("PlanterDead", True)):
        p = Prefab(name)
        p.cyl("Pot", 2.6, 2.3, (0, 1.3, 0), (38, 38, 40), "Concrete", "AxiomConcrete", solid=True)
        p.cyl("Soil", 0.1, 2.0, (0, 2.58, 0), C["soil"], "Ground", ns=1)
        p.cyl("Trunk", 3.2 if not dead else 2.6, 0.22, (0.1, 4.1 if not dead else 3.8, 0), (70, 52, 36), "Wood")
        leaf = C["plantDead"] if dead else C["plant"]
        mat = "Grass" if dead else "LeafyGrass"
        clumps = ((0, 6.2, 0, 2.6), (0.9, 5.4, 0.5, 1.9), (-0.8, 5.6, -0.4, 2.0), (0.3, 7.0, -0.3, 1.6), (-0.4, 4.9, 0.7, 1.5))
        for i, (x, y, z, d) in enumerate(clumps):
            if dead and i in (0, 3):
                continue
            yy = y - (1.4 if dead else 0)
            p.ball("Leaves", d * (0.75 if dead else 1), (x, yy, z), leaf, mat)
        if dead:
            for i in range(5):
                a = i * 1.3
                p.box("FallenLeaf", (0.4, 0.04, 0.25), (math.cos(a) * 1.6, 0.02, math.sin(a) * 1.6), C["plantDead"], "SmoothPlastic", rot=(0, i * 47, 0), nq=1)
        p.done()

    p = Prefab("PlanterBox")
    p.box("Box", (8, 2.4, 2.4), (0, 1.2, 0), (52, 50, 48), "Concrete", "AxiomConcrete", solid=True)
    p.box("Soil", (7.6, 0.1, 2.0), (0, 2.38, 0), C["soil"], "Ground", ns=1)
    for i, x in enumerate((-2.8, -1.2, 0.6, 2.4)):
        dead = hash01("pb", i) < 0.5
        p.ball("Shrub", 1.9 if not dead else 1.3, (x, 3.0 if not dead else 2.7, 0.1 * i - 0.1), C["plantDead"] if dead else C["plant"],
               "Grass" if dead else "LeafyGrass")
    p.done()

    p = Prefab("WaterCooler")
    p.box("Cabinet", (1.3, 3.3, 1.3), (0, 1.65, 0), (200, 200, 196), "SmoothPlastic", solid=True)
    p.box("Tray", (0.8, 0.1, 0.4), (0, 2.1, -0.75), (60, 60, 60), "SmoothPlastic", ns=1)
    for x in (-0.25, 0.25):
        p.box("Tap", (0.14, 0.25, 0.2), (x, 2.75, -0.72), (60, 70, 160) if x < 0 else (190, 190, 190), "SmoothPlastic", ns=1)
    bottle = p.cyl("Bottle", 1.6, 1.05, (0, 4.15, 0), (110, 160, 200), "Glass")
    bottle["t"] = 0.35
    p.cyl("Water", 0.7, 0.98, (0, 3.75, 0), (70, 120, 170), "SmoothPlastic", t=0.4, ns=1)
    p.done()

    p = Prefab("CoatRack")
    p.cyl("Base", 0.12, 1.4, (0, 0.06, 0), (24, 24, 24), "Metal")
    p.cyl("Pole", 6.0, 0.16, (0, 3.0, 0), (24, 24, 24), "Metal")
    for a in range(4):
        r = math.radians(a * 90)
        p.box("Hook", (0.5, 0.06, 0.06), (math.cos(r) * 0.25, 5.9, math.sin(r) * 0.25), (24, 24, 24), "Metal", rot=(0, -a * 90, 20), ns=1)
    p.box("Coat", (1.1, 3.4, 0.6), (0.45, 4.2, 0), (46, 50, 58), "Fabric", "AxiomFabric", rot=(0, 0, 4))
    p.box("Coat", (1.0, 2.8, 0.55), (-0.3, 4.4, 0.45), (78, 70, 58), "Fabric", "AxiomFabric", rot=(0, 90, -3))
    p.cyl("Umbrella", 3.0, 0.3, (-0.5, 1.6, -0.4), (24, 24, 30), "Fabric", rot=(0, 0, 80))
    p.done()

    p = Prefab("Bench")
    p.box("Seat", (7, 0.35, 1.8), (0, 1.55, 0), C["woodDark"], "Wood", "AxiomWood", solid=True)
    for s in (-1, 1):
        p.box("Leg", (0.4, 1.4, 1.6), (s * 3.0, 0.7, 0), (36, 36, 38), "Metal")
    p.done()

    # A speed-gate lane cabinet: mercs walk through the lanes between cabinets (the flaps are open).
    p = Prefab("Turnstile")
    p.box("Cabinet", (0.9, 3.4, 5.0), (0, 1.7, 0), (60, 62, 66), "Metal", "AxiomSteel", solid=True)
    p.box("Top", (1.0, 0.1, 5.1), (0, 3.45, 0), (20, 22, 24), "Glass", t=0.2)
    for s in (-1, 1):
        p.box("Flap", (0.06, 1.8, 1.0), (s * 0.55, 2.4, 0.2), (130, 160, 170), "Glass", t=0.55, rot=(0, s * 70, 0), ns=1, nq=1)
    p.box("Reader", (0.6, 0.06, 0.6), (0, 3.52, -1.8), (20, 20, 22), "SmoothPlastic", ns=1)
    led = p.box("Led", (0.5, 0.06, 0.08), (0, 3.53, -2.2), (90, 255, 140), "Neon", ns=1, nq=1)
    p.done()

    p = Prefab("DisplayCase")
    p.box("Plinth", (3, 3.4, 3), (0, 1.7, 0), (30, 30, 32), "Marble", "AxiomTerrazzo", solid=True)
    case = p.box("Case", (2.8, 2.4, 2.8), (0, 4.6, 0), (130, 160, 170), "Glass", solid=True)
    case["t"] = 0.7
    p.box("Blade", (1.6, 0.3, 1.1), (0, 3.65, 0), (40, 42, 46), "Metal", "AxiomSteel", rot=(0, 20, 0))
    p.box("Led", (0.08, 0.06, 0.04), (0.6, 3.82, -0.4), (80, 200, 255), "Neon", ns=1, nq=1)
    plaque = p.box("Plaque", (2.0, 0.6, 0.04), (0, 2.6, -1.52), (150, 130, 80), "Metal", ns=1)
    plaque["gui"] = gui("AXIOM NODE 001\nTHE FIRST VAULT, 2009", "Front", "Merriweather", (30, 26, 20), ppu=60)
    p.done()


# ------------------------------------------------------------------------------------------------------
# Offices


def office():
    p = Prefab("OfficeDesk")
    p.box("Top", (6, 0.12, 3), (0, DESK_H - 0.06, 0), (124, 104, 82), "Wood", "AxiomWood", solid=True)
    for s in (-1, 1):
        p.box("Leg", (0.12, DESK_H - 0.12, 2.8), (s * 2.9, (DESK_H - 0.12) / 2, 0), (60, 62, 66), "Metal", solid=True)
    p.box("Modesty", (5.7, 1.6, 0.08), (0, 1.75, 1.35), (60, 62, 66), "Metal")
    p.box("Pedestal", (1.5, 2.4, 2.5), (2.0, 1.3, 0.15), (70, 72, 76), "Metal", "AxiomSteel", solid=True)
    for y in (0.6, 1.4, 2.15):
        p.box("Drawer", (1.42, 0.02, 0.04), (2.0, y + 0.35, -1.12), (40, 40, 42), "Metal", ns=1)
        p.box("Handle", (0.6, 0.08, 0.08), (2.0, y, -1.14), (150, 150, 150), "Metal", ns=1)
    p.done()

    # An open drawer variant (someone left in a hurry).
    p = Prefab("OfficeDeskOpen")
    for part in PREFABS["OfficeDesk"]["parts"]:
        p.parts.append(dict(part))
    p.box("DrawerOut", (1.3, 0.55, 2.0), (2.0, 2.1, -1.6), (66, 68, 72), "Metal", "AxiomSteel")
    p.box("Files", (1.1, 0.4, 1.6), (2.0, 2.3, -1.6), C["paperOld"], "SmoothPlastic", ns=1, nq=1)
    p.done()

    p = Prefab("ConferenceTable")
    p.box("Top", (16, 0.3, 5.2), (0, 2.65, 0), C["woodDark"], "Wood", "AxiomWood", solid=True)
    for x in (-5, 5):
        p.box("Pedestal", (1.6, 2.5, 2.4), (x, 1.25, 0), (30, 30, 32), "Metal", solid=True)
    p.box("Port", (1.2, 0.04, 0.6), (0, 2.81, 0), (20, 20, 22), "Metal", ns=1)
    p.done()

    p = Prefab("CafeTable")
    p.cyl("Top", 0.12, 3.6, (0, 2.6, 0), (180, 176, 168), "SmoothPlastic", solid=True)
    p.cyl("Stem", 2.5, 0.25, (0, 1.3, 0), (30, 30, 32), "Metal")
    p.cyl("Foot", 0.1, 1.8, (0, 0.05, 0), (30, 30, 32), "Metal")
    p.done()

    for name, tipped in (("CafeChair", False), ("CafeChairTipped", True)):
        p = Prefab(name)
        if not tipped:
            p.box("Seat", (1.6, 0.15, 1.6), (0, 1.55, 0), (64, 70, 80), "SmoothPlastic", solid=True)
            p.box("Back", (1.6, 1.4, 0.12), (0, 2.4, 0.78), (64, 70, 80), "SmoothPlastic", rot=(-6, 0, 0))
            for sx in (-1, 1):
                for sz in (-1, 1):
                    p.box("Leg", (0.1, 1.5, 0.1), (sx * 0.7, 0.75, sz * 0.7), (30, 30, 32), "Metal", ns=1)
        else:
            p.box("Seat", (1.6, 0.15, 1.6), (0, 0.8, 0.3), (64, 70, 80), "SmoothPlastic", rot=(80, 0, 0), solid=True)
            p.box("Back", (1.6, 1.4, 0.12), (0, 0.06, 1.2), (64, 70, 80), "SmoothPlastic", rot=(90, 0, 0))
            for sx in (-1, 1):
                for sz in (-1, 1):
                    p.box("Leg", (0.1, 1.5, 0.1), (sx * 0.7, 1.55 + sz * 0.1, -0.45 + sz * 0.7), (30, 30, 32), "Metal", rot=(80, 0, 0), ns=1)
        p.done()

    # Desk clutter: three arrangements, each a few small things (no collisions, no raycasts).
    def paper(p, x, z, r, n=1, col=C["paper"]):
        for i in range(n):
            p.box("Paper", (0.85, 0.01 + 0.012 * i, 1.1), (x, 0.006 + 0.012 * i, z), col, "SmoothPlastic", rot=(0, r + i * 7, 0), nq=1, ns=1)

    p = Prefab("ClutterA", "Desk")
    paper(p, -1.2, 0.0, 12, 3)
    p.box("Binder", (0.35, 1.0, 1.2), (-2.6, 0.5, 0.9), (40, 60, 90), "SmoothPlastic", nq=1)
    p.box("Binder", (0.35, 1.0, 1.2), (-2.2, 0.5, 0.9), (40, 40, 44), "SmoothPlastic", nq=1)
    p.cyl("PenCup", 0.45, 0.3, (2.4, 0.22, 0.9), (30, 30, 32), "SmoothPlastic", nq=1)
    for i in range(3):
        p.cyl("Pen", 0.6, 0.04, (2.38 + 0.05 * i, 0.5, 0.9 + 0.03 * i), ((20, 30, 120), (20, 20, 20), (200, 200, 190))[i], "SmoothPlastic", rot=(0, 0, 80 + i * 4), nq=1)
    frame_ = p.box("Photo", (0.7, 0.55, 0.06), (1.8, 0.28, 1.1), (30, 26, 22), "Wood", rot=(-12, -18, 0), nq=1)
    frame_["gui"] = gui("", "Front", "Roboto", (0, 0, 0), bg=(120, 110, 96), light=1)
    p.box("Sticky", (0.3, 0.01, 0.3), (0.4, 0.01, -0.9), (220, 210, 90), "SmoothPlastic", rot=(0, 25, 0), nq=1, ns=1)
    p.done()

    p = Prefab("ClutterB", "Desk")
    paper(p, -1.6, -0.3, -20, 2, C["paperOld"])
    p.box("Phone", (0.9, 0.3, 0.8), (-2.4, 0.15, 0.6), (30, 30, 32), "SmoothPlastic", rot=(0, 15, 0), nq=1)
    p.box("Handset", (0.9, 0.15, 0.25), (-2.4, 0.38, 0.45), (26, 26, 28), "SmoothPlastic", rot=(0, 15, 0), nq=1)
    for i in range(4):
        p.box("Book", (1.0, 0.2, 0.75), (2.3, 0.1 + 0.2 * i, 0.8), ((60, 50, 40), (40, 50, 60), (90, 80, 60), (50, 50, 50))[i], "SmoothPlastic", rot=(0, i * 9, 0), nq=1)
    p.cyl("Takeout", 0.5, 0.6, (1.2, 0.25, -0.6), (200, 196, 186), "SmoothPlastic", nq=1)
    p.cyl("Can", 0.42, 0.22, (-0.5, 0.21, -0.9), (40, 80, 140), "Metal", nq=1)
    p.done()

    p = Prefab("ClutterC", "Desk")
    paper(p, 1.6, 0.2, 40, 4)
    p.cyl("Pot", 0.5, 0.5, (-2.3, 0.25, 0.9), (150, 120, 90), "SmoothPlastic", nq=1)
    p.ball("Succulent", 0.55, (-2.3, 0.62, 0.9), C["plantDead"], "Grass", nq=1)
    p.box("Stapler", (0.25, 0.25, 0.8), (-1.2, 0.12, 0.5), (30, 30, 32), "SmoothPlastic", rot=(0, -30, 0), nq=1)
    p.box("Notebook", (0.9, 0.08, 1.2), (0.3, 0.04, -0.4), (30, 34, 50), "SmoothPlastic", rot=(0, -8, 0), nq=1)
    for i in range(3):
        p.box("Sticky", (0.3, 0.01, 0.3), (2.6 - 0.35 * i, 0.012, -0.9), ((220, 210, 90), (230, 170, 80), (130, 200, 200))[i], "SmoothPlastic", rot=(0, 10 * i, 0), nq=1, ns=1)
    p.done()

    p = Prefab("Backpack")
    p.box("Body", (1.2, 1.5, 0.7), (0, 0.75, 0), (36, 40, 46), "Fabric", "AxiomFabric", rot=(-10, 0, 0))
    p.box("Pocket", (0.9, 0.6, 0.2), (0, 0.5, -0.4), (30, 32, 36), "Fabric", "AxiomFabric", ns=1)
    p.done()

    p = Prefab("Handbag")
    p.box("Body", (1.2, 0.8, 0.45), (0, 0.4, 0), (60, 40, 30), "Leather", "AxiomLeather")
    p.cyl("Strap", 1.0, 0.06, (0, 0.95, 0), (50, 34, 26), "Leather", axis="x", ns=1)
    p.done()

    for name, tipped in (("TrashBin", False), ("TrashBinTipped", True)):
        p = Prefab(name)
        if not tipped:
            p.cyl("Bin", 1.6, 1.1, (0, 0.8, 0), (40, 40, 42), "SmoothPlastic", solid=True)
            p.cyl("Liner", 0.1, 1.15, (0, 1.6, 0), (20, 20, 22), "SmoothPlastic", ns=1)
            p.ball("Trash", 0.6, (0.2, 1.55, 0.1), C["paper"], "SmoothPlastic", nq=1)
        else:
            p.cyl("Bin", 1.6, 1.1, (0, 0.55, 0), (40, 40, 42), "SmoothPlastic", axis="z")
            for i in range(4):
                p.ball("Trash", 0.45, (0.3 * i - 0.4, 0.2, -1.2 - 0.3 * i), C["paper"], "SmoothPlastic", nq=1)
        p.done()

    p = Prefab("CardboardBox")
    p.box("Box", (2.2, 1.6, 1.6), (0, 0.8, 0), (112, 90, 62), "Cardboard", "AxiomCardboard", solid=True)
    p.box("Tape", (0.4, 0.02, 1.62), (0, 1.61, 0), (150, 130, 90), "SmoothPlastic", ns=1)
    p.done()

    p = Prefab("BoxOpen")
    p.box("Box", (2.2, 1.4, 1.6), (0, 0.7, 0), (112, 90, 62), "Cardboard", "AxiomCardboard", solid=True)
    p.box("Flap", (2.2, 0.8, 0.04), (0, 1.6, -1.0), (112, 90, 62), "Cardboard", "AxiomCardboard", rot=(-40, 0, 0), ns=1)
    p.box("Flap", (2.2, 0.8, 0.04), (0, 1.6, 1.0), (112, 90, 62), "Cardboard", "AxiomCardboard", rot=(45, 0, 0), ns=1)
    p.box("Files", (1.8, 0.5, 1.2), (0, 1.3, 0), C["paperOld"], "SmoothPlastic", ns=1)
    p.box("Frame", (0.7, 0.9, 0.08), (0.4, 1.7, 0.2), (30, 26, 22), "Wood", rot=(-15, 0, 10), ns=1)
    p.done()

    p = Prefab("BoxStack")
    p.box("Box", (2.2, 1.6, 1.6), (0, 0.8, 0), (112, 90, 62), "Cardboard", "AxiomCardboard", solid=True)
    p.box("Box", (2.0, 1.4, 1.5), (0.1, 2.3, 0.05), (104, 84, 58), "Cardboard", "AxiomCardboard", rot=(0, 8, 0), solid=True)
    p.box("Box", (1.6, 1.0, 1.2), (-0.2, 3.5, 0), (118, 96, 66), "Cardboard", "AxiomCardboard", rot=(0, -12, 0))
    p.done()

    p = Prefab("Copier")
    p.box("Body", (3.2, 3.0, 2.6), (0, 1.5, 0), (190, 190, 184), "SmoothPlastic", solid=True)
    p.box("Lid", (3.2, 0.3, 2.6), (0, 3.15, 0), (150, 150, 146), "SmoothPlastic")
    p.box("Panel", (1.2, 0.08, 0.6), (0.8, 3.3, -1.0), (40, 40, 42), "SmoothPlastic", ns=1)
    p.box("Screen", (0.5, 0.02, 0.35), (0.7, 3.35, -1.0), (60, 110, 130), "Neon", ns=1, nq=1)
    for y in (0.6, 1.3):
        p.box("Tray", (2.8, 0.04, 0.04), (0, y, -1.32), (60, 60, 60), "SmoothPlastic", ns=1)
    p.box("Output", (1.6, 0.06, 1.4), (-2.2, 2.4, 0), (170, 170, 166), "SmoothPlastic")
    p.box("Jam", (0.9, 0.02, 1.0), (-1.8, 2.5, -0.3), C["paper"], "SmoothPlastic", rot=(0, 0, 18), nq=1)
    p.done()

    p = Prefab("Bookshelf")
    p.box("Carcass", (3.4, 7, 1.3), (0, 3.5, 0.0), C["woodDark"], "Wood", "AxiomWood", solid=True)
    for i, y in enumerate((1.0, 2.6, 4.2, 5.8)):
        x = -1.45
        k = 0
        while x < 1.3:
            w = 0.18 + 0.1 * hash01("bk", i, k)
            h = 1.0 + 0.35 * hash01("bh", i, k)
            if hash01("gap", i, k) > 0.15:
                col = pick_book(i, k)
                p.box("Book", (w, h, 0.9), (x + w / 2, y + h / 2, -0.25), col, "SmoothPlastic", nq=1, ns=1)
            x += w + 0.02
            k += 1
    p.box("Front", (3.0, 6.6, 0.02), (0, 3.5, -0.66), (14, 12, 10), "SmoothPlastic", t=1, nq=1)
    p.done()

    for name, n in (("FilingStack", 2),):
        p = Prefab(name)
        for i in range(n):
            p.box("Drawer", (1.8, 2.0, 2.6), (0, 1.0 + 2.05 * i, 0), (90, 92, 94), "Metal", "AxiomSteel", solid=True)
        p.done()

    # Wall things -------------------------------------------------------------------------------------
    p = Prefab("Whiteboard", "Wall")
    board = p.box("Board", (8, 4, 0.12), (0, 5.4, -0.06), (210, 212, 208), "SmoothPlastic")
    board["gui"] = gui("Q4: VAULT 61 MIGRATION\n- uplink go-live 11/13 ✓\n- night shift on print floor??\n\nCHIMERA = ???", "Front", "PatrickHand", (30, 50, 110), ppu=40, align="Left", valign="Top", pad=0.3)
    p.box("Frame", (8.2, 0.12, 0.16), (0, 7.45, -0.08), (160, 162, 164), "Metal", ns=1)
    p.box("Tray", (6, 0.12, 0.3), (0, 3.36, -0.2), (160, 162, 164), "Metal", ns=1)
    p.box("Marker", (0.4, 0.08, 0.08), (1.2, 3.46, -0.24), (30, 50, 110), "SmoothPlastic", ns=1, nq=1)
    p.done()

    p = Prefab("CorkBoard", "Wall")
    p.box("Cork", (4, 3, 0.12), (0, 5.6, -0.06), (150, 120, 80), "SmoothPlastic")
    p.box("Frame", (4.2, 3.2, 0.06), (0, 5.6, -0.03), (90, 70, 50), "Wood", ns=1)
    for i in range(6):
        x = -1.4 + 0.55 * i + 0.2 * hash01("cork", i)
        y = 5.2 + 0.9 * hash01("cy", i)
        sheet = p.box("Flyer", (0.85, 1.1, 0.02), (x, y, -0.13), (C["paper"] if i % 2 else (200, 210, 190)), "SmoothPlastic", rot=(0, 0, -6 + 12 * hash01("cr", i)), nq=1, ns=1)
    flyer = p.box("Notice", (1.3, 0.9, 0.02), (0.9, 6.5, -0.14), (230, 220, 170), "SmoothPlastic", rot=(0, 0, 4), nq=1, ns=1)
    flyer["gui"] = gui("NIGHT SHIFT\nSIGN-UP\nLVL 61", "Front", "PatrickHand", (40, 40, 40), ppu=60)
    p.done()

    p = Prefab("WallClock", "Wall")
    face = p.cyl("Face", 0.15, 1.6, (0, 8.6, -0.08), (220, 218, 210), "SmoothPlastic", axis="z")
    p.cyl("Rim", 0.18, 1.75, (0, 8.6, -0.06), (30, 30, 32), "SmoothPlastic", axis="z", ns=1)
    p.box("Hour", (0.08, 0.45, 0.02), (0.14, 8.7, -0.17), (20, 20, 20), "SmoothPlastic", rot=(0, 0, -95), ns=1, nq=1)
    p.box("Minute", (0.06, 0.65, 0.02), (0.06, 8.32, -0.18), (20, 20, 20), "SmoothPlastic", rot=(0, 0, 186), ns=1, nq=1)
    p.done()

    posters = (
        ("PosterVault", "AXIOM\n\nYOUR DATA.\nOUR VAULT.\nFOREVER.", (24, 30, 40), (170, 200, 220)),
        ("PosterRemember", "WE REMEMBER\nEVERYTHING\n\nAXIOM DATA VAULT", (30, 30, 34), (210, 210, 200)),
        ("PosterSafety", "SAFETY IS\nEVERYONE'S JOB\n\n412 DAYS WITHOUT\nAN INCIDENT", (190, 150, 40), (30, 26, 20)),
        ("PosterCamera", "SMILE!\nYOU ARE ON\nCAMERA\n\nSECURITY ON LEVEL 61", (40, 44, 50), (220, 220, 210)),
        ("PosterChimera", "PROJECT CHIMERA\n\nNEED-TO-KNOW\nDO NOT DISCUSS\nOUTSIDE THE VAULT", (20, 22, 26), (150, 180, 190)),
        ("PosterNetwork", "SEE SOMETHING ODD\nON THE NETWORK?\n\nCALL IT: EXT 6100", (30, 40, 70), (200, 210, 230)),
        ("PosterWellness", "WELLNESS\nWEDNESDAY\n\nbreathe in.\nbreathe out.", (110, 130, 120), (240, 240, 230)),
        ("PosterAllHands", "ALL HANDS\nTHURSDAY 9 AM\nLEVEL 61 ATRIUM\n\nATTENDANCE MANDATORY", (60, 50, 44), (230, 220, 200)),
    )
    for name, text, bg, fg in posters:
        p = Prefab(name, "Wall")
        p.box("Frame", (2.6, 3.6, 0.1), (0, 6.2, -0.05), (24, 24, 26), "Metal")
        sheet = p.box("Print", (2.3, 3.3, 0.02), (0, 6.2, -0.11), bg, "SmoothPlastic", ns=1)
        sheet["gui"] = gui(text, "Front", "Oswald", fg, ppu=60, pad=0.2)
        p.done()

    notes = (
        ("NoteCameras", "DON'T TRUST\nTHE CAMERAS"),
        ("NotePA", "it talks through\nthe PA now"),
        ("NoteStairs", "STAIRS CHAINED\nBELOW 61.\nDON'T BOTHER."),
        ("NoteElevator", "elevator 2 stuck\nsince tuesday\n- facilities"),
        ("NotePrinted", "they printed\nanother one\nlast night"),
        ("NoteLights", "KEEP THE\nLIGHTS ON"),
        ("NoteLearns", "IT LEARNS"),
        ("NoteNOC", "WE'RE IN THE NOC\nCOME FIND US"),
    )
    for name, text in notes:
        p = Prefab(name, "Wall")
        sheet = p.box("Note", (1.1, 1.3, 0.02), (0, 5.2, -0.01), (214, 210, 196), "SmoothPlastic", rot=(0, 0, -4), nq=1, ns=1)
        g = gui(text, "Front", "PermanentMarker", (20, 20, 24), ppu=70, pad=0.08)
        sheet["gui"] = g
        p.box("Tape", (0.5, 0.15, 0.022), (0, 5.82, -0.012), (200, 200, 180), "SmoothPlastic", t=0.3, nq=1, ns=1)
        p.done()

    p = Prefab("FireCabinet", "Wall")
    p.box("Cabinet", (1.6, 3.2, 0.5), (0, 4.4, -0.25), (190, 190, 186), "Metal")
    glass = p.box("Glass", (1.3, 2.7, 0.04), (0, 4.4, -0.52), (150, 170, 175), "Glass", ns=1)
    glass["t"] = 0.6
    p.cyl("Extinguisher", 2.0, 0.6, (0, 4.2, -0.25), (170, 172, 176), "Metal", "AxiomSteel")
    sign = p.box("Label", (1.3, 0.35, 0.02), (0, 6.2, -0.01), (30, 30, 32), "SmoothPlastic", ns=1)
    sign["gui"] = gui("FIRE EXTINGUISHER", "Front", "Oswald", (230, 230, 220), ppu=60)
    p.done()

    p = Prefab("AlarmStrobe", "Wall")
    p.box("Box", (0.9, 1.1, 0.35), (0, 8.4, -0.17), (210, 210, 206), "SmoothPlastic")
    p.box("Lens", (0.6, 0.3, 0.06), (0, 8.15, -0.37), (220, 220, 220), "SmoothPlastic", ns=1)
    p.done()

    p = Prefab("Thermostat", "Wall")
    p.box("Body", (0.7, 0.9, 0.15), (0, 4.8, -0.08), (200, 200, 196), "SmoothPlastic")
    p.box("Display", (0.4, 0.25, 0.02), (0, 4.95, -0.16), (60, 90, 60), "Neon", ns=1, nq=1)
    p.done()

    p = Prefab("CeilingVent", "Ceiling")
    p.box("Diffuser", (2.0, 0.12, 2.0), (0, -0.06, 0), (190, 190, 186), "Metal", ns=1)
    p.box("Ring", (1.4, 0.04, 1.4), (0, -0.13, 0), (130, 130, 128), "Metal", ns=1)
    p.box("Core", (0.7, 0.04, 0.7), (0, -0.15, 0), (40, 40, 42), "Metal", ns=1)
    p.done()

    p = Prefab("Speaker", "Ceiling")
    p.cyl("Grille", 0.08, 1.1, (0, -0.04, 0), (196, 196, 192), "Metal", ns=1)
    p.cyl("Core", 0.03, 0.6, (0, -0.09, 0), (60, 60, 60), "Metal", ns=1)
    p.done()

    p = Prefab("SmokeDetector", "Ceiling")
    p.cyl("Body", 0.3, 0.7, (0, -0.15, 0), (210, 210, 206), "SmoothPlastic", ns=1)
    p.box("Led", (0.06, 0.04, 0.06), (0.22, -0.31, 0), (90, 255, 140), "Neon", ns=1, nq=1)
    p.done()

    # Ceiling damage: a tile hanging by one edge, and wires out of a hole.
    p = Prefab("HangingTile", "Ceiling")
    p.box("Tile", (2.0, 0.15, 3.9), (0, -1.2, 1.6), C["ceiling"], "Limestone", "AxiomCeiling", rot=(-38, 0, 0), ns=1)
    p.done()

    p = Prefab("HangingWires", "Ceiling")
    for i, (x, z, ln, rx, rz) in enumerate(((0, 0, 3.2, 8, 0), (0.3, 0.2, 2.4, -6, 10), (-0.2, 0.4, 4.0, 4, -8))):
        p.cyl("Wire", ln, 0.07, (x, -ln / 2, z), ((30, 30, 30), (60, 60, 140), (150, 140, 60))[i], "Rubber", rot=(rx, 0, 90 + rz), ns=1)
    p.box("Junction", (0.5, 0.35, 0.5), (0.1, -4.1, 0.4), (120, 120, 116), "Metal", rot=(10, 20, 0), ns=1)
    p.done()

    p = Prefab("FallenTile")
    p.box("Tile", (2.0, 0.15, 3.9), (0, 0.3, 0), C["ceiling"], "Limestone", "AxiomCeiling", rot=(0, 18, 8), nq=1)
    p.box("Chunk", (1.0, 0.15, 1.2), (1.6, 0.08, -1.3), C["ceiling"], "Limestone", "AxiomCeiling", rot=(0, -30, 0), nq=1, ns=1)
    p.box("Chunk", (0.6, 0.15, 0.5), (-1.4, 0.08, 1.8), C["ceiling"], "Limestone", "AxiomCeiling", rot=(0, 40, 0), nq=1, ns=1)
    p.done()

    p = Prefab("PaperScatter")
    for i in range(7):
        a = hash01("ps", i) * 6.28
        r = 0.6 + 2.2 * hash01("pr", i)
        p.box("Paper", (0.85, 0.01, 1.1), (math.cos(a) * r, 0.01 + 0.002 * i, math.sin(a) * r), C["paper"] if i % 3 else C["paperOld"],
              "SmoothPlastic", rot=(0, hash01("pa", i) * 360, 0), nq=1, ns=1)
    p.done()

    p = Prefab("Puddle")
    p.box("Water", (5, 0.02, 3.2), (0, 0.01, 0), (20, 26, 30), "Glass", refl=0.3, nq=1, ns=1)
    p.box("Water", (2.4, 0.02, 2.2), (2.6, 0.012, 0.9), (20, 26, 30), "Glass", refl=0.3, nq=1, ns=1)
    p.done()


def pick_book(i, k):
    cols = ((70, 46, 40), (40, 52, 70), (60, 70, 50), (90, 80, 60), (40, 40, 44), (120, 110, 90), (70, 60, 80))
    return cols[int(hash01("bc", i, k) * len(cols)) % len(cols)]


# ------------------------------------------------------------------------------------------------------
# Break room, restrooms


def kitchen():
    p = Prefab("Counter")  # 8 long base cabinets with a sink; the wall cabinets are part of it
    p.box("Base", (8, 2.8, 2.2), (0, 1.4, 0.1), (160, 156, 146), "SmoothPlastic", solid=True)
    p.box("Toe", (8, 0.35, 0.1), (0, 0.18, -0.92), (30, 30, 32), "SmoothPlastic", ns=1)
    p.box("Top", (8.1, 0.15, 2.4), (0, 2.88, 0), (60, 60, 62), "Marble", "AxiomTerrazzo")
    for x in (-3, -1, 1, 3):
        p.box("DoorLine", (0.02, 2.1, 0.02), (x, 1.5, -1.01), (110, 108, 100), "SmoothPlastic", ns=1)
        p.box("Pull", (0.08, 0.5, 0.08), (x - 0.25, 2.2, -1.05), (150, 150, 150), "Metal", ns=1)
    p.box("Sink", (2.0, 0.3, 1.4), (1.6, 2.82, -0.1), (150, 152, 154), "Metal", "AxiomSteel")
    p.cyl("Faucet", 1.0, 0.12, (1.6, 3.4, 0.7), (170, 172, 176), "Metal", ns=1)
    p.box("Spout", (0.1, 0.1, 0.8), (1.6, 3.85, 0.35), (170, 172, 176), "Metal", ns=1)
    p.box("Upper", (8, 2.6, 1.3), (0, 7.4, 0.55), (160, 156, 146), "SmoothPlastic")
    p.box("Splash", (8, 2.0, 0.06), (0, 3.95, 1.17), (150, 154, 150), "CeramicTiles", "AxiomTile", ns=1)
    p.cyl("Mug", 0.4, 0.32, (-2.6, 3.15, -0.4), (200, 196, 186), "SmoothPlastic", nq=1)
    p.cyl("Mug", 0.4, 0.32, (-2.1, 3.15, -0.2), (40, 60, 90), "SmoothPlastic", nq=1)
    p.box("DishRack", (1.4, 0.5, 1.0), (3.2, 3.2, -0.1), (190, 190, 190), "SmoothPlastic", nq=1)
    p.done()

    p = Prefab("Fridge")
    p.box("Body", (3.0, 6.6, 2.6), (0, 3.3, 0.2), (176, 178, 176), "Metal", "AxiomSteel", solid=True)
    p.box("Seam", (3.0, 0.04, 0.02), (0, 4.6, -1.11), (60, 60, 60), "SmoothPlastic", ns=1)
    for y in (5.6, 3.2):
        p.box("Handle", (0.1, 1.4, 0.15), (1.2, y, -1.2), (150, 150, 150), "Metal", ns=1)
    note = p.box("Note", (0.7, 0.9, 0.02), (-0.5, 5.4, -1.12), (230, 226, 200), "SmoothPlastic", rot=(0, 0, 5), ns=1, nq=1)
    note["gui"] = gui("LABEL YOUR\nFOOD!!\n- mgmt", "Front", "PatrickHand", (40, 40, 60), ppu=70)
    p.done()

    p = Prefab("Microwave", "Desk")
    p.box("Body", (1.8, 1.0, 1.2), (0, 0.5, 0), (40, 40, 42), "SmoothPlastic")
    p.box("Window", (1.1, 0.7, 0.02), (-0.2, 0.5, -0.61), (20, 22, 24), "Glass", ns=1)
    p.box("Clock", (0.3, 0.12, 0.02), (0.6, 0.75, -0.61), (90, 255, 140), "Neon", ns=1, nq=1)
    p.done()

    p = Prefab("CoffeeMaker", "Desk")
    p.box("Body", (0.9, 1.4, 1.0), (0, 0.7, 0.1), (24, 24, 26), "SmoothPlastic")
    p.cyl("Pot", 0.7, 0.6, (0, 0.38, -0.3), (40, 30, 24), "Glass", t=0.2)
    p.box("Lamp", (0.08, 0.08, 0.02), (0.3, 1.2, -0.41), (255, 160, 60), "Neon", ns=1, nq=1)
    p.done()

    p = Prefab("VendingMachine")
    p.box("Cabinet", (3.4, 7.0, 2.8), (0, 3.5, 0), (28, 30, 34), "Metal", solid=True)
    glass = p.box("Glass", (2.3, 4.8, 0.06), (-0.3, 3.4, -1.42), (110, 130, 140), "Glass", ns=1)
    glass["t"] = 0.75
    for row in range(5):
        for col in range(4):
            colr = ((160, 60, 40), (40, 90, 160), (200, 160, 40), (60, 140, 70), (150, 100, 50))[(row + col) % 5]
            if hash01("vm", row, col) < 0.25:
                continue
            p.box("Snack", (0.45, 0.6, 0.15), (-1.1 + 0.55 * col, 1.6 + 0.9 * row, -1.25), colr, "SmoothPlastic", ns=1, nq=1)
    p.box("Keypad", (0.6, 1.4, 0.06), (1.3, 4.2, -1.42), (20, 20, 22), "SmoothPlastic", ns=1)
    p.box("Slot", (2.0, 0.5, 0.08), (-0.3, 0.8, -1.42), (10, 10, 10), "SmoothPlastic", ns=1)
    logo = p.box("Logo", (2.3, 0.6, 0.04), (-0.3, 6.3, -1.42), (20, 22, 26), "SmoothPlastic", ns=1)
    logo["gui"] = gui("SNAX", "Front", "Oswald", (200, 220, 230), light=0, bright=1.2, ppu=40)
    p.done()

    p = Prefab("Toilet")
    p.box("Base", (1.2, 1.4, 1.8), (0, 0.7, -0.2), (200, 200, 196), "SmoothPlastic", solid=True)
    p.box("Seat", (1.4, 0.15, 1.9), (0, 1.48, -0.25), (210, 210, 206), "SmoothPlastic")
    p.box("Tank", (1.6, 1.6, 0.6), (0, 2.1, 0.75), (200, 200, 196), "SmoothPlastic")
    p.done()

    p = Prefab("Vanity")
    p.box("Counter", (8, 0.4, 2.2), (0, 3.0, 0.1), (60, 60, 62), "Marble", "AxiomTerrazzo", solid=True)
    p.box("Apron", (8, 0.8, 0.1), (0, 2.6, -0.95), (60, 60, 62), "Marble", "AxiomTerrazzo")
    for x in (-2.2, 2.2):
        p.box("Basin", (1.8, 0.2, 1.2), (x, 3.12, -0.1), (210, 210, 206), "SmoothPlastic", ns=1)
        p.cyl("Tap", 0.6, 0.1, (x, 3.5, 0.6), (170, 172, 176), "Metal", ns=1)
    p.box("Mirror", (7.6, 4.0, 0.08), (0, 6.2, 1.15), (40, 46, 50), "Glass", refl=0.25)
    p.done()

    p = Prefab("HandDryer", "Wall")
    p.box("Body", (1.0, 1.4, 0.7), (0, 4.6, -0.35), (190, 190, 186), "Metal", "AxiomSteel")
    p.box("Nozzle", (0.5, 0.2, 0.3), (0, 3.85, -0.5), (60, 60, 60), "Metal", ns=1)
    p.done()

    p = Prefab("MopBucket")
    p.box("Bucket", (1.6, 1.3, 1.2), (0, 0.75, 0), (200, 170, 40), "SmoothPlastic", solid=True)
    p.box("Wringer", (0.8, 0.5, 1.0), (0.4, 1.6, 0), (40, 40, 40), "SmoothPlastic", ns=1)
    p.cyl("Handle", 4.8, 0.12, (-0.3, 2.6, 0.2), (150, 150, 150), "Metal", rot=(0, 0, 70))
    p.box("Water", (1.4, 0.05, 1.0), (0, 1.2, 0), (60, 64, 50), "SmoothPlastic", ns=1, nq=1)
    p.done()

    p = Prefab("WetFloorSign")
    for s in (-1, 1):
        sign = p.box("Board", (1.2, 2.4, 0.06), (0, 1.15, s * 0.32), (220, 180, 30), "SmoothPlastic", rot=(s * 15, 0, 0))
        sign["gui"] = gui("CAUTION\nWET\nFLOOR", "Front" if s < 0 else "Back", "Oswald", (20, 20, 20), ppu=50, pad=0.15)
    p.done()


# ------------------------------------------------------------------------------------------------------
# Maintenance, plant, server and fabrication props


def industrial():
    p = Prefab("Ladder")
    for s in (-1, 1):
        for fz in (-1, 1):
            p.box("Rail", (0.15, 6.2, 0.25), (s * 0.85, 3.0, fz * 0.75), (190, 150, 40), "SmoothPlastic", rot=(fz * -12, 0, 0))
    for i in range(5):
        y = 1.0 + 1.1 * i
        p.box("Step", (1.6, 0.12, 0.5), (0, y, -0.75 + 0.12 * i), (150, 150, 150), "Metal", ns=1)
    p.box("Top", (1.9, 0.25, 0.9), (0, 6.1, 0), (190, 150, 40), "SmoothPlastic")
    p.done()

    p = Prefab("Toolbox")
    p.box("Box", (2.0, 0.9, 0.9), (0, 0.45, 0), (40, 60, 110), "Metal", solid=True)
    p.box("Lid", (2.0, 0.2, 0.9), (0, 1.0, 0), (36, 54, 100), "Metal")
    p.box("Handle", (1.0, 0.1, 0.1), (0, 1.25, 0), (30, 30, 30), "Metal", ns=1)
    p.done()

    p = Prefab("Cone")
    p.box("Base", (1.2, 0.12, 1.2), (0, 0.06, 0), (210, 120, 30), "SmoothPlastic")
    p.cyl("Cone", 2.0, 0.7, (0, 1.1, 0), (220, 130, 30), "SmoothPlastic")
    p.cyl("Band", 0.3, 0.62, (0, 1.4, 0), (230, 230, 220), "SmoothPlastic", ns=1)
    p.done()

    p = Prefab("CableSpool")
    p.cyl("Drum", 1.2, 1.6, (0, 1.0, 0), (60, 40, 30), "Wood", axis="x", solid=True)
    for s in (-1, 1):
        p.cyl("Flange", 0.15, 2.4, (s * 0.6, 1.2, 0), (110, 84, 60), "Wood", axis="x")
    p.done()

    p = Prefab("CrashCart")
    p.box("Tray", (2.4, 0.1, 1.6), (0, 3.0, 0), (120, 122, 124), "Metal", solid=True)
    p.box("Tray", (2.4, 0.1, 1.6), (0, 1.2, 0), (120, 122, 124), "Metal")
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box("Post", (0.1, 3.0, 0.1), (sx * 1.15, 1.6, sz * 0.75), (120, 122, 124), "Metal", ns=1)
            p.ball("Caster", 0.25, (sx * 1.1, 0.12, sz * 0.7), (20, 20, 20), "Rubber", ns=1)
    p.box("Monitor", (1.6, 1.1, 0.12), (0, 3.7, 0.3), (20, 20, 22), "SmoothPlastic")
    scr = p.box("Screen", (1.4, 0.9, 0.02), (0, 3.7, 0.23), (8, 14, 18), "SmoothPlastic", ns=1)
    scr["gui"] = gui("> fsck /dev/vault0\nERROR: unexpected\n  write by uid 0\n> _", "Front", "Code", (110, 220, 140), light=0, bright=1.2, ppu=60, align="Left", valign="Top")
    p.box("Keyboard", (1.4, 0.08, 0.5), (0, 3.09, -0.4), (30, 30, 32), "SmoothPlastic", ns=1)
    p.done()

    p = Prefab("GasTank")
    p.cyl("Tank", 5.2, 1.4, (0, 2.8, 0), (150, 152, 150), "Metal", "AxiomSteel", solid=True)
    p.ball("Cap", 1.4, (0, 5.4, 0), (150, 152, 150), "Metal", "AxiomSteel")
    p.cyl("Valve", 0.6, 0.3, (0, 6.2, 0), (60, 60, 60), "Metal")
    p.cyl("Gauge", 0.1, 0.5, (0, 6.0, -0.3), (220, 220, 210), "SmoothPlastic", axis="z", ns=1)
    lab = p.box("Label", (0.9, 0.9, 0.02), (0, 3.4, -0.71), (210, 210, 200), "SmoothPlastic", ns=1)
    lab["gui"] = gui("FM-200\nSUPPRESSION", "Front", "Oswald", (30, 30, 30), ppu=60)
    p.done()

    p = Prefab("Switchgear")
    p.box("Cabinet", (4.0, 7.2, 2.2), (0, 3.6, 0), (110, 116, 114), "Metal", "AxiomSteel", solid=True)
    for x in (-1.0, 1.0):
        p.box("Door", (1.9, 6.6, 0.04), (x, 3.7, -1.12), (100, 106, 104), "Metal", ns=1)
        p.box("Latch", (0.12, 0.6, 0.1), (x + (0.75 if x < 0 else -0.75), 3.8, -1.18), (40, 40, 40), "Metal", ns=1)
    for i, x in enumerate((-1.4, -0.6, 0.6, 1.4)):
        p.cyl("Meter", 0.08, 0.45, (x, 6.1, -1.18), (220, 220, 210), "SmoothPlastic", axis="z", ns=1)
        p.box("Pilot", (0.14, 0.14, 0.04), (x, 5.5, -1.17), (90, 255, 140) if i != 2 else (255, 160, 50), "Neon", ns=1, nq=1)
    warn = p.box("Warning", (1.6, 0.8, 0.02), (-1.0, 4.6, -1.15), (220, 180, 30), "SmoothPlastic", ns=1)
    warn["gui"] = gui("DANGER\n480 V", "Front", "Oswald", (20, 20, 20), ppu=60)
    p.done()

    p = Prefab("WaterHeater")
    p.cyl("Tank", 7.0, 3.0, (0, 3.5, 0), (190, 190, 184), "Metal", "AxiomSteel", solid=True)
    p.cyl("Flue", 3.0, 0.7, (0, 8.5, 0), (130, 130, 130), "Metal")
    for x in (-0.8, 0.8):
        p.cyl("Pipe", 3.0, 0.35, (x, 8.3, 0.4), (150, 100, 60), "Metal")
    p.box("Control", (0.8, 0.9, 0.3), (0, 1.2, -1.55), (40, 40, 42), "SmoothPlastic", ns=1)
    p.box("Pilot", (0.1, 0.1, 0.02), (0.2, 1.3, -1.71), (255, 150, 50), "Neon", ns=1, nq=1)
    p.done()

    p = Prefab("Workbench")
    p.box("Top", (8, 0.3, 3), (0, 3.0, 0), (90, 70, 50), "Wood", "AxiomWood", solid=True)
    for sx in (-1, 1):
        for sz in (-1, 1):
            p.box("Leg", (0.25, 2.85, 0.25), (sx * 3.7, 1.42, sz * 1.3), (40, 60, 90), "Metal")
    p.box("Shelf", (7.6, 0.15, 2.6), (0, 0.8, 0), (40, 60, 90), "Metal")
    p.box("Pegboard", (8, 4, 0.12), (0, 5.3, 1.45), (120, 110, 90), "SmoothPlastic")
    for i in range(7):
        x = -3.3 + 1.1 * i
        p.box("Tool", (0.15, 0.9 + 0.4 * hash01("t", i), 0.1), (x, 5.6, 1.35), (40, 40, 44), "Metal", rot=(0, 0, -10 + 20 * hash01("tr", i)), ns=1, nq=1)
    p.box("Vise", (0.8, 0.6, 0.9), (3.2, 3.45, -1.0), (40, 60, 90), "Metal", ns=1)
    p.box("Servo", (0.8, 0.8, 0.8), (-1.2, 3.55, -0.2), (24, 24, 26), "Metal", "AxiomSteel", ns=1)
    p.box("Plate", (1.6, 0.06, 1.0), (0.6, 3.18, 0.1), (46, 50, 58), "Metal", "AxiomSteel", rot=(0, 20, 0), ns=1)
    p.done()

    p = Prefab("RobotArm")
    p.cyl("Base", 1.0, 3.0, (0, 0.5, 0), (190, 150, 40), "SmoothPlastic", solid=True)
    p.cyl("Turret", 1.2, 2.0, (0, 1.6, 0), (190, 150, 40), "SmoothPlastic")
    p.box("Lower", (1.0, 5.0, 1.0), (0, 4.2, -0.6), (190, 150, 40), "SmoothPlastic", rot=(-20, 0, 0))
    p.cyl("Elbow", 1.4, 1.3, (0, 6.6, -1.4), (40, 40, 42), "Metal", axis="x")
    p.box("Upper", (0.8, 4.0, 0.8), (0, 6.3, -3.2), (190, 150, 40), "SmoothPlastic", rot=(-110, 0, 0))
    p.box("Tool", (0.6, 1.4, 0.6), (0, 5.2, -5.1), (40, 40, 42), "Metal", rot=(-160, 0, 0))
    p.box("Tip", (0.2, 0.3, 0.2), (0, 4.45, -5.3), (255, 150, 50), "Neon", ns=1, nq=1)
    p.done()

    p = Prefab("PartsRack")
    p.box("Frame", (6, 7, 1.6), (0, 3.5, 0), (40, 60, 90), "Metal", solid=True)
    for row in range(4):
        for col in range(5):
            colr = (60, 120, 170) if (row + col) % 3 else (200, 170, 40)
            p.box("Bin", (1.0, 0.8, 1.4), (-2.4 + 1.2 * col, 0.9 + 1.6 * row, -0.2), colr, "SmoothPlastic", ns=1, nq=1)
    p.done()

    p = Prefab("Louver", "Wall")  # an exterior louvre bay, 8 wide x 10 high, for plant rooms
    for i in range(14):
        p.box("Blade", (8, 0.08, 1.2), (0, 0.6 + 0.66 * i, 0.5), (60, 64, 66), "Metal", rot=(-35, 0, 0), ns=1)
    for s in (-1, 1):
        p.box("Mullion", (0.3, 10, 1.6), (s * 4.1, 5, 0.5), (60, 64, 66), "Metal")
    p.box("Screen", (8, 10, 0.05), (0, 5, 1.2), (20, 20, 22), "SmoothPlastic", t=0.6, solid=True, ns=1)
    p.done()


# ------------------------------------------------------------------------------------------------------
# Signs


def signs():
    # A room plaque by a doorway: shows the room on the other side of its wall (FacilityScreens).
    p = Prefab("RoomPlaque", "Wall")
    plate = p.box("Plate", (2.4, 0.8, 0.08), (0, 6.6, -0.04), (34, 38, 46), "SmoothPlastic")
    plate["tag"] = "KitSign"
    plate["a"] = {"SignMode": "Through"}
    plate["gui"] = dict(gui("ROOM", "Front", "Oswald", (225, 228, 230), ppu=60, pad=0.1), name="SignText")
    p.done()

    p = Prefab("RoomSign", "Wall")  # names the room it hangs in
    plate = p.box("Plate", (5.0, 1.3, 0.1), (0, 8.4, -0.05), (30, 34, 40), "SmoothPlastic")
    plate["tag"] = "KitSign"
    plate["a"] = {"SignMode": "Room"}
    plate["gui"] = dict(gui("ROOM", "Front", "Oswald", (225, 228, 230), ppu=50, pad=0.15), name="SignText")
    p.box("Stripe", (5.0, 0.12, 0.11), (0, 7.68, -0.05), (80, 200, 255), "SmoothPlastic", ns=1)
    p.done()

    p = Prefab("Wayfinding", "Wall")  # directions; opts.text replaces the text
    plate = p.box("Plate", (5.4, 1.4, 0.08), (0, 8.2, -0.04), (34, 38, 46), "SmoothPlastic")
    plate["gui"] = dict(gui("<  RECEPTION", "Front", "Oswald", (225, 228, 230), ppu=50, pad=0.12, align="Left"), name="SignText")
    p.done()

    p = Prefab("FloorNumber", "Wall")
    plate = p.box("Paint", (5, 5, 0.02), (0, 7.5, -0.01), (100, 100, 96), "SmoothPlastic", t=1, nq=1, ns=1)
    plate["gui"] = dict(gui("61", "Front", "Oswald", (210, 170, 40), ppu=30, pad=0.0), name="SignText")
    p.done()

    p = Prefab("StencilText", "Wall")
    plate = p.box("Paint", (8, 1.2, 0.02), (0, 6.0, -0.01), (100, 100, 96), "SmoothPlastic", t=1, nq=1, ns=1)
    plate["gui"] = dict(gui("TEXT", "Front", "Oswald", (210, 210, 200), ppu=40, pad=0.0, transp=0.15), name="SignText")
    p.done()

    p = Prefab("Graffiti", "Wall")  # scrawled on a wall in marker
    plate = p.box("Paint", (7, 2.6, 0.02), (0, 5.0, -0.01), (100, 100, 96), "SmoothPlastic", t=1, nq=1, ns=1)
    plate["gui"] = dict(gui("IT SEES YOU", "Front", "PermanentMarker", (16, 16, 18), ppu=40, pad=0.0, transp=0.1, rot=-3), name="SignText")
    p.done()

    p = Prefab("Barrier", "Wall")  # a chained gate across a stair going down (doorway-free wall mount)
    for x in (-3.0, 0, 3.0):
        p.cyl("Post", 4.0, 0.15, (x, 2.0, -0.5), (150, 150, 150), "Metal")
    p.box("Mesh", (6.4, 3.6, 0.05), (0, 2.1, -0.5), (90, 90, 90), "Metal", t=0.55, solid=True, ns=1)
    sign = p.box("Sign", (2.4, 1.2, 0.04), (0, 2.6, -0.56), (210, 210, 200), "SmoothPlastic", ns=1)
    sign["gui"] = gui("NO ACCESS\nLEVELS 1-60\nSEALED", "Front", "Oswald", (30, 30, 30), ppu=60)
    p.done()


def extras():
    p = Prefab("AxiomLogo", "Wall")  # the company name, backlit
    plate = p.box("Letters", (18, 4.6, 0.1), (0, 2.6, -0.06), (20, 22, 26), "SmoothPlastic", t=1, nq=1, ns=1)
    plate["gui"] = gui("AXIOM", "Front", "Zekton", (190, 220, 235), light=0, bright=1.3, ppu=24, pad=0.0)
    p.box("Line", (16, 0.12, 0.08), (0, 0.1, -0.05), (70, 170, 255), "Neon", ns=1, nq=1)
    sub = p.box("Sub", (12, 1.0, 0.1), (0, -0.9, -0.06), (20, 22, 26), "SmoothPlastic", t=1, nq=1, ns=1)
    sub["gui"] = gui("D A T A   V A U L T", "Front", "Zekton", (150, 160, 168), light=1, ppu=40, pad=0.0)
    p.done()

    # A jar light on a drop rod, for tall plant rooms (hangs `drop` below the slab).
    for name, drop in (("JarLightHung", 7.0),):
        p = Prefab(name, "Ceiling")
        p.cyl("Rod", drop, 0.18, (0, -drop / 2, 0), (40, 42, 40), "Metal")
        p.cyl("Base", 0.3, 0.9, (0, -drop - 0.15, 0), (40, 42, 40), "Metal")
        globe = p.ball("Fixture", 0.8, (0, -drop - 0.7, 0), (255, 190, 120), "Neon", ns=1)
        globe["light"] = light("point", LIGHT_SODIUM, 28, 1.3)
        for a in range(4):
            r = math.radians(a * 90 + 45)
            p.box("Cage", (0.05, 0.9, 0.05), (math.cos(r) * 0.45, -drop - 0.7, math.sin(r) * 0.45), (40, 42, 40), "Metal", ns=1)
        p.done()

    # Three gashes torn through a wall's finish (the Chimera's claws), with the board showing.
    p = Prefab("ClawMarks", "Wall")
    for i, dx in enumerate((-0.6, 0.0, 0.6)):
        ln = 3.2 - 0.4 * abs(i - 1)
        p.box("Gash", (0.22, ln, 0.03), (dx + 0.4, 5.0 - 0.15 * i, -0.015), (16, 14, 14), "SmoothPlastic", rot=(0, 0, -28), nq=1, ns=1)
        p.box("GashEdge", (0.08, ln * 0.9, 0.035), (dx + 0.52, 5.05 - 0.15 * i, -0.02), (150, 146, 136), "SmoothPlastic", rot=(0, 0, -28), nq=1, ns=1)
    p.done()

    p = Prefab("Scorch", "Wall")  # soot round something that shorted
    for i, (dx, dy, w, h) in enumerate(((0, 2.6, 2.4, 3.2), (0.3, 3.6, 1.6, 2.0), (-0.4, 1.8, 1.4, 1.2))):
        p.box("Soot", (w, h, 0.02), (dx, dy, -0.012 - 0.002 * i), (12, 11, 10), "SmoothPlastic", t=0.35 + 0.15 * i, nq=1, ns=1)
    p.done()

    p = Prefab("DroppedFlashlight")  # still on, pointing along the floor
    p.cyl("Body", 1.1, 0.32, (0, 0.17, 0.2), (24, 24, 26), "Metal", axis="z")
    lens = p.cyl("Fixture", 0.06, 0.4, (0, 0.17, -0.38), (255, 236, 200), "Neon", axis="z", ns=1)
    lens["light"] = light("spot", (255, 236, 205), 26, 1.6, shadows=True, face="Right", angle=50)
    p.done()

    p = Prefab("CautionTape", "Wall")  # across a doorway, half torn down; it doesn't stop anyone
    for i, (y, rz, ln) in enumerate(((4.2, 6, 9.0), (6.1, -4, 9.0), (3.0, 58, 3.6))):
        t = p.box("Tape", (ln, 0.35, 0.02), (0 if i < 2 else 3.6, y, -0.6), (220, 180, 30), "SmoothPlastic", rot=(0, 0, rz), nq=1, ns=1)
        t["gui"] = gui("CAUTION  -  DO NOT ENTER  -  CAUTION", "Front", "Oswald", (20, 20, 20), ppu=40, pad=0.0)
    p.done()

    p = Prefab("Stretcher")  # an emergency stretcher, tipped on its side
    p.box("Frame", (2.2, 0.2, 6.4), (0, 1.1, 0), (170, 172, 176), "Metal", rot=(0, 0, 70))
    p.box("Mat", (1.9, 0.25, 5.8), (0.15, 1.15, 0), (40, 60, 90), "Rubber", "AxiomRubber", rot=(0, 0, 70))
    for z in (-2.6, 2.6):
        p.box("Leg", (0.12, 2.0, 0.12), (0.9, 1.0, z), (170, 172, 176), "Metal", rot=(0, 0, -20), ns=1)
    p.done()

    p = Prefab("SecurityPodium")
    p.box("Body", (3.2, 3.6, 2.0), (0, 1.8, 0), (40, 38, 36), "Wood", "AxiomWood", solid=True)
    p.box("Top", (3.4, 0.15, 2.2), (0, 3.68, 0.05), (60, 60, 62), "Marble", "AxiomTerrazzo")
    p.box("Radio", (0.4, 0.9, 0.25), (1.0, 4.2, 0.2), (24, 24, 26), "SmoothPlastic", rot=(0, 20, 0), nq=1)
    p.box("Led", (0.06, 0.06, 0.02), (1.05, 4.6, 0.07), (90, 255, 140), "Neon", nq=1, ns=1)
    log = p.box("Logbook", (1.3, 0.06, 1.0), (-0.5, 3.8, 0.1), (190, 186, 172), "SmoothPlastic", rot=(0, -8, 0), nq=1)
    sign = p.box("Sign", (2.6, 0.7, 0.04), (0, 3.0, -1.02), (30, 32, 36), "SmoothPlastic", ns=1)
    sign["gui"] = gui("SECURITY  ·  SIGN IN", "Front", "Oswald", (200, 204, 206), ppu=50)
    p.done()

    p = Prefab("KidsDrawing", "Wall")  # taped to a partition: a crayon house and a family, and a robot
    sheet = p.box("Sheet", (1.4, 1.0, 0.02), (0, 4.4, -0.01), (226, 222, 210), "SmoothPlastic", rot=(0, 0, 3), nq=1, ns=1)
    sheet["gui"] = gui("my mom works\nat AXIOM", "Front", "PatrickHand", (60, 70, 160), ppu=60, pad=0.08)
    p.done()

    p = Prefab("MagazineFan", "Desk")
    for i in range(4):
        col = ((60, 80, 110), (200, 196, 180), (80, 70, 60), (120, 130, 120))[i]
        p.box("Magazine", (1.0, 0.03, 1.35), (0.25 * i - 0.4, 0.015 + 0.03 * i, 0.08 * i), col, "SmoothPlastic", rot=(0, -20 + 14 * i, 0), nq=1, ns=1)
    p.done()


def build_all():
    extras()
    fixtures()
    emergency()
    doors()
    lobby()
    office()
    kitchen()
    industrial()
    signs()
