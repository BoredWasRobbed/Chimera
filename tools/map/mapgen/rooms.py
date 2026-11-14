"""The wings' rooms, laid out like a real building: each room is planned round the paths between its doors
(kept clear), furniture stands in aligned rows and runs against the walls, everything faces the floor it's
used from (the front-clearance check in core.claim enforces it), and every server, shelf and cabinet can be
walked up to. The Reception, the lobby, the deck and the stairs are in dress.py."""
from __future__ import annotations

import math

from . import core
from . import dress as D
from .core import (C, SPACES, against, box, claim, conduit_trap, floor_piece, geo, gui, hash01, keepout, light,
                   light_panel, lights_folder, obox, on_wall, piece, props as props_f, steam_trap, to_world)

fixture, light_state, troffer_grid, emergency_packs = D.fixture, D.light_state, D.troffer_grid, D.emergency_packs
try_floor, clutter_floor, desk, partition, rack_row = D.try_floor, D.clutter_floor, D.desk, D.partition, D.rack_row
column, exposed_ceiling, pick_feed = D.column, D.exposed_ceiling, D.pick_feed

COOL = (170, 200, 255)
HIGHBAY = (235, 238, 240)


def aisle(sid, x0, x1, z0, z1):
    """A walkway kept clear of furniture."""
    keepout(sid, x0, x1, z0, z1)


def wall_run(sid, side, start, names, step=None, gap=0.3, **opts):
    """Pieces backed against a wall one after another from `start` along it (increasing u)."""
    u = start
    out = []
    sgn = 1 if side in "SW" else -1  # which way the piece's own X runs along the wall
    for name in names:
        w, cx = core.dims(name)[0], core.dims(name)[3]
        rec = against(sid, side, u + w / 2 - sgn * cx, name, gap=gap, **opts)
        out.append(rec)
        u += (step or w) + 0.15
    return out


def floor_line(sid, x0, x1, z0, z1, col=(170, 140, 40)):
    s = SPACES[sid]
    box("FloorLine", geo(sid), x0, x1, s.y0, s.y0 + 0.02, z0, z1, mat="SmoothPlastic", color=col, nc=True, nq=True, ns=True)


def hazard_frame(sid, x0, x1, z0, z1, w=0.4):
    """A painted hazard border on the floor (a loading zone, round a machine)."""
    s = SPACES[sid]
    for (a0, a1, b0, b1) in ((x0, x1, z0, z0 + w), (x0, x1, z1 - w, z1), (x0, x0 + w, z0, z1), (x1 - w, x1, z0, z1)):
        box("HazardLine", geo(sid), a0, a1, s.y0, s.y0 + 0.025, b0, b1, mat="SmoothPlastic", color="hazard", var="AxiomHazard", nc=True, nq=True, ns=True)


def battens(sid, xs, zs, y=None, dead=0.3, flicker=0.15, yaw=0, light_=None):
    s = SPACES[sid]
    for x in xs:
        for z in zs:
            fixture(sid, "Batten", x, z, yaw, y=(s.y0 + y) if y is not None else None,
                    state=light_state(sid, f"{x},{z}", dead, flicker), light_=light_)


def highbays(sid, xs, zs, dead=0.3, flicker=0.2, col=HIGHBAY, brightness=1.3):
    s = SPACES[sid]
    for x in xs:
        for z in zs:
            fixture(sid, "HighBay", x, z, y=s.top - 3, state=light_state(sid, f"{x},{z}", dead, flicker),
                    light_=light("spot", col, 34, brightness, face="Left", angle=100))


# ------------------------------------------------------------------------------------------------------
# Office Wing


def desk_spine(sid, x0, n, zc, seed, rng_chairs=True):
    """A bench of desks: n desks a side of a centre screen running along x from x0, low screens between
    desks. Everyone sits on the aisle side facing the screen."""
    s = SPACES[sid]
    w = 6.0
    length = n * w
    claim(sid, (x0 - 0.2, x0 + length + 0.2, zc - 7.0, zc + 7.0), "desk spine")
    partition(sid, x0, x0 + length, zc - 0.15, zc + 0.15, h=5.0)
    for k in range(n + 1):
        x = x0 + k * w
        partition(sid, x - 0.1, x + 0.1, zc - 3.6, zc - 0.15, h=4.0)
        partition(sid, x - 0.1, x + 0.1, zc + 0.15, zc + 3.6, h=4.0)
    for k in range(n):
        for side in (-1, 1):
            i = seed * 100 + k * 2 + (side > 0)
            x = x0 + w * (k + 0.5)
            z = zc + side * 1.68
            yaw = 0 if side < 0 else 180  # the desk's back against the screen; its user on the aisle side
            r = hash01("spine", sid, i)
            chair = "normal" if r < 0.62 else ("pushed" if r < 0.8 else ("tipped" if r < 0.9 else "none"))
            lamp = None
            if hash01("lamp", sid, i) < 0.14:
                lamp = "on" if hash01("lampon", sid, i) < 0.6 else ("flicker" if hash01("lampf", i) < 0.5 else "dead")
            mons = (pick_feed(sid, i),) if hash01("dual", sid, i) < 0.55 else (pick_feed(sid, i), pick_feed(sid, i + 7))
            desk(sid, x, z, yaw, i, monitors=mons, lamp=lamp, chair=chair, open_drawer=hash01("dr", sid, i) < 0.2,
                 tower=hash01("tw", sid, i) < 0.25, check=False, claimed=True)
            if hash01("pin", sid, i) < 0.6:
                px, pz = to_world(x, z, yaw, -1.2 + 2.0 * hash01("px", i), 1.55)
                obox("Pinned", props_f(sid), px, s.y0 + 3.9, pz, 0.85, 1.1, 0.03, yaw=yaw, mat="SmoothPlastic",
                     color=C["paper"] if hash01("pc", i) < 0.7 else (200, 210, 230), nc=True, nq=True, ns=True)


def dress_open_office():
    sid = "OW_OPEN"
    s = SPACES[sid]
    # Paths: the main aisle from the Reception's glass door, the window walk, aisles down to the corridor.
    aisle(sid, -181, -58, -124.5, -115.5)
    aisle(sid, -188, -58, -148, -143.4)
    aisle(sid, -177, -165, -115.5, -84)
    aisle(sid, -119, -107, -115.5, -84)
    # Structure: a column in each gap between the desk benches.
    for x in (-151, -121, -91):
        column(sid, x, -136, 3.0, mat=("Plaster", "AxiomPlaster", (110, 108, 102)))
    # Desk benches: four along the windows, two by the corridor.
    seed = 1
    for (x0, n) in ((-178, 4), (-148, 4), (-118, 4), (-88, 3)):
        desk_spine(sid, x0, n, -136, seed)
        seed += 1
    for (x0, n) in ((-163, 6), (-104, 6)):
        desk_spine(sid, x0, n, -104, seed)
        seed += 1
    # Along the corridor wall: the print station, filing and supplies, the coffee point, the dock.
    wall_run(sid, "S", -163.6, ["Copier", "FilingCabinet", "FilingCabinet", "FilingCabinet", "StorageShelf_6"])
    on_wall(sid, "S", -134, "CorkBoard", 0, check=False)
    core.dock("DOCK_OW_OPEN", sid, "S", -100, "Open Office dock")
    wall_run(sid, "S", -95.5, ["FilingCabinet", "FilingCabinet", "FilingCabinet"])
    rec = against(sid, "S", -80, "Counter", gap=0.05)
    px, pz = to_world(rec[2], rec[4], rec[5], -2.4, 0.4)
    piece("CoffeeMaker", props_f(sid), px, s.y0 + 2.96, pz, rec[5])
    px, pz = to_world(rec[2], rec[4], rec[5], 2.2, 0.3)
    piece("Microwave", props_f(sid), px, s.y0 + 2.96, pz, rec[5])
    against(sid, "S", -69.5, "WaterCooler")
    try_floor(sid, "TrashBinRecycle", -66.2, -86.0, 0)
    core.station("STATION_OW", sid, "W", -92)
    try_floor(sid, "PlantPot", -185.5, -102, 0)
    for x in (-155, -125, -95, -66):
        try_floor(sid, "PlanterTall" if hash01("op", x) < 0.5 else "PlanterDead", x, -145.6, 0)
    # A barricade somebody started by the corridor: a desk on its side, chairs piled on it.
    piece("OfficeDesk", props_f(sid), -186.0, s.y0 + 3.0, -118.0, 90, tilt=-90)
    piece("OfficeChair", props_f(sid), -184.8, s.y0 + 1.0, -111.5, 160, tilt=-82)
    clutter_floor(sid, -140, -120, ("PaperScatter",))
    clutter_floor(sid, -96, -119, ("PaperScatter",))
    try_floor(sid, "TrashBinTipped", -128, -121.5, 200)
    on_wall(sid, "W", -110, "Whiteboard", 0)
    on_wall(sid, "W", -142, "PosterWellness", 0, check=False)
    on_wall(sid, "E", -134, "PosterSafety", 0, check=False)
    on_wall(sid, "E", -99, "CorkBoard", 0, check=False)
    on_wall(sid, "E", -106, "RoomSign", 0, check=False)
    on_wall(sid, "W", -146, "NoteLights", 0, check=False)
    on_wall(sid, "E", -141, "ClawMarks", 0, check=False)
    on_wall(sid, "W", -100, "WallClock", 0, check=False)
    piece("KidsDrawing", props_f(sid), -137.0, s.y0, -104.17, 0)
    # Lights: a row of troffers over each bench and over the aisles.
    for z in (-140, -120, -100, -89):
        for x in range(-182, -60, 12):
            fixture(sid, "Troffer", x, z, 90, state=light_state(sid, f"{x},{z}", 0.5, 0.15))
    core.camera("OW_OPEN", sid, "E", -145.5, (-140, 2, -102), "Open Office", head=10.6, pan=65)
    light_panel(sid, "E", -112)
    emergency_packs(sid, (("E", -128), ("W", -96)))

    # The corridor behind the office: posters, the cooler, a fire cabinet, the trap.
    hall = "OW_HALL"
    aisle(hall, -188, -58, -79.5, -74.5)
    for x in (-180, -164, -148, -132, -116, -100, -84, -68):
        fixture(hall, "Troffer", x, -77, 90, state=light_state(hall, x, 0.35, 0.25))
    on_wall(hall, "N", -146, "PosterCamera", 0, check=False)
    on_wall(hall, "N", -88, "PosterAllHands", 0, check=False)
    on_wall(hall, "S", -150, "FireCabinet", 0, check=False)
    on_wall(hall, "S", -82, "Graffiti", 0, check=False)
    on_wall(hall, "S", -136, "WallClock", 0, check=False)
    conduit_trap("TRAP_OW_HALL", hall, "N", -70)
    on_wall(hall, "N", -70, "Scorch", 3.0, check=False)
    piece("DroppedFlashlight", props_f(hall), -120, 0, -75.5, 80, flicker="flicker")
    clutter_floor(hall, -100, -77, ("PaperScatter",))


def dress_exec():
    sid = "OW_EXEC"
    s = SPACES[sid]
    aisle(sid, -197, -190, -138, -126)
    # The executive's desk faces the door, the credenza under the window behind it.
    piece("DaisRug", props_f(sid), -213, s.y0, -132, 90)
    desk(sid, -214, -132, 90, 7, monitors=("Status", "Upload"), lamp="on", chair="pushed")
    against(sid, "W", -132, "Credenza", gap=0.6)
    piece("PlantPot", props_f(sid), -230.0, s.y0 + 2.62, -128.5, 0)
    for z in (-135.5, -128.5):
        floor_piece(sid, "Armchair", -206.4, z, 90 + (z + 132) * 3, label="guest armchair")
    # The bookcases and the terminal on the south wall, a small meeting table by the windows.
    wall_run(sid, "S", -230.5, ["Bookshelf", "Bookshelf", "Bookshelf"])
    core.terminal("TERM_OW", sid, "S", -199, "Executive Office terminal")
    floor_piece(sid, "MeetingTable", -200, -142.5, 0, label="meeting table")
    for k, (dx, dz) in enumerate(((-3.6, 0), (3.6, 0), (0, 3.5))):
        a = math.degrees(math.atan2(-dx, -dz)) + 180
        try_floor(sid, "OfficeChair", -200 + dx, -142.5 + dz, a + 10 * k, label="meeting chair")
    piece("ClutterA", props_f(sid), -200.6, s.y0 + 2.75, -142.3, 30)
    try_floor(sid, "PlanterTall", -229.3, -145.3, 0)
    try_floor(sid, "FloorLamp", -229.5, -115.5, 0, folder=lights_folder(sid))
    clutter_floor(sid, -210, -124, ("PaperScatter",))
    on_wall(sid, "E", -144, "PosterChimera", 0, check=False)
    on_wall(sid, "E", -120, "WallClock", 0, check=False)
    for (x, z, st) in ((-222, -140, "dead"), (-206, -140, "flicker"), (-222, -122, "on"), (-206, -122, "dead")):
        fixture(sid, "Downlight", x, z, state=st)
    core.camera("OW_EXEC", sid, "E", -116, (-222, 2, -138), "Executive Office", head=10.6)
    light_panel(sid, "E", -122)
    emergency_packs(sid, (("S", -218.5),))


def dress_conference():
    sid = "OW_CONF"
    s = SPACES[sid]
    floor_piece(sid, "ConferenceTable", -211, -86, 90, label="table")
    for k, z in enumerate((-93, -88, -83, -78)):
        for sx, base in ((-1, 90), (1, -90)):
            if hash01("cc", k, sx) < 0.15:
                continue
            x = -211 + sx * 4.4 + sx * 1.2 * hash01("cp", k, sx)
            piece("OfficeChair", props_f(sid), x, s.y0, z, base + 180 + 40 * (hash01("ca", k, sx) - 0.5))
    piece("OfficeChair", props_f(sid), -211, s.y0, -96.5, 180)
    piece("OfficeChair", props_f(sid), -205, s.y0 + 1.0, -70, 30, tilt=-82)
    for (z, k) in ((-92, "Laptop"), (-84, "Mug"), (-80, "PaperTray"), (-88, "Mug")):
        piece(k, props_f(sid), -211 + (1.2 if k != "Mug" else -1.6), s.y0 + 2.8, z, 90 + 20 * hash01("ck", z))
    piece("ClutterA", props_f(sid), -211, s.y0 + 2.8, -88, 90)
    piece("ClutterC", props_f(sid), -211, s.y0 + 2.8, -81, -90)
    on_wall(sid, "N", -228, "WallMonitor_Map", 1.0, check=False)
    on_wall(sid, "E", -100, "Whiteboard", 0, check=False)
    rec = against(sid, "S", -214, "Credenza")
    for k, dx in enumerate((-2.2, -1.6, 2.0)):
        px, pz = to_world(rec[2], rec[4], rec[5], dx, 0.2)
        piece("Mug" if k < 2 else "CoffeeMaker", props_f(sid), px, s.y0 + 2.62, pz, rec[5])
    against(sid, "S", -202, "FilingCabinet")
    against(sid, "S", -200.1, "FilingCabinet")
    try_floor(sid, "PlanterDead", -193.5, -107, 0)
    try_floor(sid, "TrashBin", -229.5, -64.5, 0)
    core.dock("DOCK_OW_CONF", sid, "N", -199.5, "Conference Room dock")
    troffer_grid(sid, 12, 14, dead=0.3, flicker=0.2)
    core.camera("OW_CONF", sid, "E", -66, (-214, 2, -98), "Conference Room", head=10.6)
    light_panel(sid, "E", -88)
    emergency_packs(sid, (("S", -226),))


def dress_break():
    sid = "OW_BREAK"
    s = SPACES[sid]
    aisle(sid, -170, -160, -70, -61)
    # The kitchen along the south wall, vending on the east, tables in the middle.
    for x in (-180.2, -172):
        against(sid, "S", x, "Counter", gap=0.05)
    against(sid, "S", -164.4, "Fridge", gap=0.05)
    piece("Microwave", props_f(sid), -183, s.y0 + 2.96, -37.6, 0)
    piece("CoffeeMaker", props_f(sid), -176.5, s.y0 + 2.96, -37.6, 0)
    against(sid, "S", -158.6, "TrashBinRecycle")
    against(sid, "S", -156.9, "TrashBin")
    for z in (-63, -58.2):
        rec = against(sid, "E", z, "VendingMachine", gap=0.1)
        piece("VendingGlow", lights_folder(sid), rec[2], s.y0, rec[4], rec[5], **({"flicker": "buzz"} if z > -60 else {}))
    against(sid, "E", -49, "WaterCooler")
    for (x, z) in ((-178, -58), (-162, -58), (-178, -47), (-162, -47)):
        floor_piece(sid, "CafeTable", x, z, 0, label="table")
        for k in range(4):
            a = math.radians(k * 90 + 45)
            nm = "CafeChairTipped" if (x, z, k) == (-162, -47, 1) else "CafeChair"
            try_floor(sid, nm, x + math.sin(a) * 3.0, z + math.cos(a) * 3.0, math.degrees(a), label="cafe chair")
        piece(("ClutterB", "ClutterC", "MagazineFan", "ClutterA")[int(hash01("bt", x, z) * 4)], props_f(sid), x, s.y0 + 2.66, z, 10)
    on_wall(sid, "W", -64, "CorkBoard", 0, check=False)
    on_wall(sid, "N", -150, "PosterWellness", 0, check=False)
    on_wall(sid, "N", -144, "WallMonitor_Status", 2.0, check=False)
    on_wall(sid, "W", -40, "NoteNOC", 0, check=False)
    on_wall(sid, "N", -184, "WallClock", 0, check=False)
    troffer_grid(sid, 14, 12, dead=0.3, flicker=0.15)
    core.camera("OW_BREAK", sid, "N", -138, (-170, 2, -46), "Break Room", head=10.6)
    light_panel(sid, "N", -180)
    emergency_packs(sid, (("W", -38),))
    # Restrooms: stalls along the far wall, the vanity by the door, a leak.
    for wc in ("OW_WC_M", "OW_WC_F"):
        w = SPACES[wc]
        for k in range(3):
            x0 = w.x0 + 0.6 + 4.2 * k
            box("Stall", props_f(wc), x0 + 4.05, x0 + 4.2, w.y0 + 0.6, w.y0 + 6.4, w.z1 - 5.6, w.z1, mat="Metal", color=(96, 100, 104), var="AxiomSteel")
            if hash01("stall", wc, k) < 0.6:
                obox("StallDoor", props_f(wc), x0 + 1.0, w.y0 + 3.5, w.z1 - 7.0, 0.12, 5.8, 2.6, yaw=20, mat="Metal", color=(96, 100, 104), var="AxiomSteel", nc=True)
            else:
                box("StallDoor", props_f(wc), x0 + 0.15, x0 + 4.05, w.y0 + 0.6, w.y0 + 6.4, w.z1 - 5.62, w.z1 - 5.5, mat="Metal", color=(96, 100, 104), var="AxiomSteel")
            piece("Toilet", props_f(wc), x0 + 2.1, w.y0, w.z1 - 1.6, 0)
        box("StallFront", props_f(wc), w.x0, w.x0 + 13.2, w.y0 + 6.4, w.y0 + 6.6, w.z1 - 5.65, w.z1 - 5.5, mat="Metal", color=(96, 100, 104), var="AxiomSteel", nc=True)
        claim(wc, (w.x0 + 0.1, w.x0 + 13.2, w.z1 - 5.7, w.z1 - 0.1), "stalls")
        against(wc, "W" if wc == "OW_WC_M" else "E", -62, "Vanity", gap=0.05)
        on_wall(wc, "E" if wc == "OW_WC_M" else "W", -66, "HandDryer", 0, check=False)
        clutter_floor(wc, w.x0 + 8, w.z1 - 9, ("Puddle",))
        fixture(wc, "Troffer", (w.x0 + w.x1) / 2, w.z0 + 5, 90, state="dead" if wc == "OW_WC_M" else "flicker")
        fixture(wc, "Troffer", (w.x0 + w.x1) / 2, w.z1 - 6, 90, state="on")


def dress_archive():
    sid = "OW_ARCHIVE"
    s = SPACES[sid]
    # The main aisle down the east side from the Break Room door, a cross aisle to the Boiler Room door.
    aisle(sid, -198, -190, -60, 38)
    aisle(sid, -232, -190, 27, 38)
    # Back-to-back runs of file shelving across the room, each facing a 4-stud aisle.
    pitch = 8.4
    zc = -54.0
    rows = 0
    while zc + 2.3 < 8:
        for k in range(4):
            x = -225.0 + 6.15 * k
            floor_piece(sid, "FileShelf", x, zc - 1.06, 0, label="file shelving")
            floor_piece(sid, "FileShelf", x, zc + 1.06, 180, label="file shelving")
        fixture(sid, "Batten", -213, zc - 4.2, 0, y=s.y0 + 11.2, state=light_state(sid, f"r{rows}", 0.35, 0.25))
        zc += pitch
        rows += 1
    # The records desk, the scanner, carts and boxes waiting to be shelved.
    against(sid, "W", 18, "OfficeDesk", gap=0.4)
    desk_rec = core.PIECES[-1]
    px, pz = to_world(desk_rec[2], desk_rec[4], desk_rec[5], 0, 0.7)
    piece("Monitor_Log", props_f(sid), px, s.y0 + 2.8, pz, desk_rec[5])
    px, pz = to_world(desk_rec[2], desk_rec[4], desk_rec[5], -2.3, 0.6)
    piece("DeskLamp", lights_folder(sid), px, s.y0 + 2.8, pz, desk_rec[5] + 20)
    px, pz = to_world(desk_rec[2], desk_rec[4], desk_rec[5], 0.2, -2.8)
    piece("OfficeChair", props_f(sid), px, s.y0, pz, desk_rec[5] + 200)
    piece("ClutterB", props_f(sid), desk_rec[2], s.y0 + 2.8, desk_rec[4], desk_rec[5])
    against(sid, "W", 11, "Copier")
    for (x, z, yaw) in ((-214, 16, 0), (-206, 20, 12)):
        try_floor(sid, "RollCage", x, z, yaw)
    try_floor(sid, "BoxStack", -205.5, 23.5, 0)
    try_floor(sid, "BoxOpen", -202.2, 22.5, 15)
    try_floor(sid, "Ladder", -194.5, 14, 0)
    clutter_floor(sid, -210, -8, ("PaperScatter",))
    for z in (-50, -30, -10, 10):
        fixture(sid, "Batten", -194, z, 90, y=s.y0 + 11.2, state=light_state(sid, f"m{z}", 0.3, 0.2))
    fixture(sid, "Batten", -213, 22, 0, y=s.y0 + 11.2, state="on")
    core.camera("OW_ARCHIVE", sid, "E", -8, (-214, 2, 24), "Records Room", head=10.6, pan=70)
    light_panel(sid, "E", -42)
    emergency_packs(sid, (("E", 6),))


# ------------------------------------------------------------------------------------------------------
# Server Farms


def rack_block(sid, x0, n, zc, aisle_w=6.0, label="racks"):
    """Two rows of racks facing each other across a walkable cold aisle on zc: open sliding doors at the
    ends, a glass roof, perforated tiles and a light over the aisle."""
    s = SPACES[sid]
    half = aisle_w / 2 + 2.05
    end = rack_row(sid, x0, n, zc - half, 180, label=label)
    rack_row(sid, x0, n, zc + half, 0, label=label)
    for xe in (x0, end):
        for side in (-1, 1):
            obox("AisleDoorPost", props_f(sid), xe, s.y0 + 6, zc + side * (aisle_w / 2 - 0.1), 0.25, 12, 0.25, color=(60, 62, 66), nc=True, ns=True)
            # The sliding door, parked open against the rack end.
            obox("AisleDoor", props_f(sid), xe + (-0.25 if xe == x0 else 0.25), s.y0 + 5.6, zc + side * (aisle_w / 2 + 1.3), 0.06, 10.8, 2.4,
                 mat="Glass", color=(110, 130, 140), t=0.6, nc=True, nq=True, ns=True)
        obox("AisleHeader", props_f(sid), xe, s.y0 + 12.1, zc, 0.3, 0.4, aisle_w, color=(60, 62, 66), nc=True, ns=True)
    box("AisleRoof", props_f(sid), x0, end, s.y0 + 12.15, s.y0 + 12.25, zc - aisle_w / 2, zc + aisle_w / 2, mat="Glass", color=(110, 130, 140), t=0.7, nc=True, nq=True, ns=True)
    for xt in range(int(math.ceil(x0)) + 2, int(end) - 1, 4):
        box("Perf", geo(sid), xt - 1.9, xt + 1.9, s.y0, s.y0 + 0.02, zc - 1.8, zc + 1.8, mat="Metal", color=(70, 74, 78), var="AxiomTread", nc=True, nq=True, ns=True)
    for x in range(int(x0) + 6, int(end), 14):
        fixture(sid, "Batten", x, zc, 0, y=s.y0 + 11.9, state=light_state(sid, f"{x},{zc}", 0.3, 0.15), light_=light("point", COOL, 16, 0.9))
    return end


def dress_datahall():
    sid = "SF_DATAHALL"
    s = SPACES[sid]
    # Cross aisles at each end and down the middle; the work area along the south wall.
    aisle(sid, 58, 70, -148, -84)
    aisle(sid, 176, 188, -148, -84)
    aisle(sid, 118, 128, -148, -104)
    # Cooling units along the north wall feed the floor; two blocks of contained aisles.
    for u in (79, 95, 111, 135, 151, 167):
        against(sid, "N", u, "CoolingUnit", gap=0.1)
    for x0 in (70.4, 129.0):
        rack_block(sid, x0, 16, -131)
        rack_block(sid, x0, 16, -111)
    # The work area: suppression tanks, new servers still boxed, a bench, a crash cart.
    wall_run(sid, "S", 87, ["GasTank", "GasTank", "GasTank"], gap=0.4)
    against(sid, "S", 104, "Workbench")
    wall_run(sid, "S", 114, ["BoxStack", "CardboardBox", "BoxStack"])
    core.dock("DOCK_SF_DATA", sid, "S", 140, "Data Hall dock")
    wall_run(sid, "S", 145.5, ["ToolChest", "StorageShelf_6"])
    try_floor(sid, "CrashCart", 95, -96, 90)
    try_floor(sid, "PalletJack", 130, -96, 15)
    try_floor(sid, "CableSpool", 150, -97, 0)
    try_floor(sid, "Ladder", 122.5, -96, 0)
    exposed_ceiling(sid, ducts=(("x", -144.5, 0),))
    for x in (64, 90, 116, 142, 168, 182):
        for z in (-121, -96, -88):
            fixture(sid, "Batten", x, z, 0, y=s.y0 + 15.5, state=light_state(sid, f"o{x},{z}", 0.3, 0.12), light_=light("point", COOL, 18, 0.8))
    on_wall(sid, "W", -138, "Wayfinding", 0, text="DATA HALL A  ·  AUTHORISED STAFF")
    core.camera("SF_DATAHALL", sid, "W", -96, (150, 2, -94), "Data Hall", head=13.5, pan=65)
    light_panel(sid, "W", -110)
    conduit_trap("TRAP_SF_DATA", sid, "E", -100)
    emergency_packs(sid, (("W", -104), ("E", -92)))
    hall = "SF_HALL"
    aisle(hall, 58, 188, -79.5, -74.5)
    for x in (66, 82, 98, 114, 130, 146, 162, 178):
        fixture(hall, "Troffer", x, -77, 90, state=light_state(hall, x, 0.4, 0.2))
    on_wall(hall, "N", 92, "PosterNetwork", 0, check=False)
    on_wall(hall, "N", 140, "FireCabinet", 0, check=False)
    on_wall(hall, "S", 150, "PosterCamera", 0, check=False)


def dress_noc():
    sid = "SF_NOC"
    s = SPACES[sid]
    # The video wall over the room's south side, two rows of operator desks facing it.
    on_wall(sid, "S", 195.5, "WallMonitor_Map", 1.5, check=False)
    on_wall(sid, "S", 202.1, "WallMonitor_Camera", 1.5, check=False, feed="Camera", cameraId="SF_DATAHALL")
    on_wall(sid, "S", 219.4, "WallMonitor_Camera", 4.0, check=False, feed="Camera", cameraId="CORE_NE")
    core.terminal("TERM_SF", sid, "S", 226, "Network Ops terminal")
    for k, x in enumerate((199, 211, 223)):
        if x == 211:
            continue
        desk(sid, x, -127, 0, 40 + k, monitors=("Log", "Terminals") if k else ("Squad", "Status"), lamp="on" if k == 2 else None,
             chair="pushed" if k else "normal")
    for k, x in enumerate((199, 211, 223)):
        desk(sid, x, -137, 0, 50 + k, monitors=(("Status", "Upload"), ("Log",), ("Off",))[k], chair=("normal", "tipped", "pushed")[k])
    piece("ClutterB", props_f(sid), 211, s.y0 + 2.8, -137, 0)
    try_floor(sid, "TrashBinTipped", 229.5, -128, 90)
    try_floor(sid, "PlantPot", 229.6, -146.2, 0)
    try_floor(sid, "BoxOpen", 193.5, -146, 10)
    on_wall(sid, "S", 204.6, "NoteNOC", 0, check=False)
    fixture(sid, "Downlight", 199, -132, state="flicker")
    fixture(sid, "Downlight", 223, -132, state="dead")
    fixture(sid, "Downlight", 211, -120, state="on")
    fixture(sid, "Downlight", 211, -142, state="on")
    core.camera("SF_NOC", sid, "S", 191.5, (220, 2, -138), "Network Operations", head=10.6)
    light_panel(sid, "S", 216.5)
    emergency_packs(sid, (("S", 230),))


def dress_ups():
    sid = "SF_UPS"
    s = SPACES[sid]
    # Switchgear down both long walls, battery strings in an island between them.
    for z in (-104, -97.8, -91.6):
        against(sid, "W", z, "Switchgear", gap=0.2)
    for z in (-104, -97.8, -91.6, -85.4, -79.2, -73, -66.8):
        against(sid, "E", z, "Switchgear", gap=0.2)
    for z in (-96, -89.4, -82.8, -76.2, -69.6):
        floor_piece(sid, "BatteryRack", 209.8, z, 90, label="battery string")
        floor_piece(sid, "BatteryRack", 212.2, z, -90, label="battery string")
    try_floor(sid, "Toolbox", 200, -68, 20)
    try_floor(sid, "Cone", 202.5, -66, 0)
    on_wall(sid, "N", 196, "PosterSafety", 0, check=False)
    conduit_trap("TRAP_SF_UPS", sid, "S", 200)
    exposed_ceiling(sid, trays=(("z", 211, 0.5), ("z", 197, 0.5), ("z", 225, 0.5)))
    battens(sid, (203, 219), (-104, -90, -76, -66), y=13.5, dead=0.25, flicker=0.25, yaw=90)
    core.camera("SF_UPS", sid, "E", -63.2, (204, 2, -100), "UPS Room", head=12.6)
    light_panel(sid, "N", 199)
    emergency_packs(sid, (("N", 224),))


def dress_rackhall():
    sid = "SF_RACKHALL"
    s = SPACES[sid]
    # The central aisle from the hall's gate, the south walkway to the plant and the dock.
    aisle(sid, 101, 131, -70, -30)
    aisle(sid, 58, 131, -36.2, -30)
    # Two contained aisles west of the walkway, one east; the older kit and the bench in the south-east.
    rack_block(sid, 64, 12, -60, label="racks")
    rack_block(sid, 64, 12, -43.4, label="racks")
    rack_block(sid, 133, 16, -60, label="racks")
    against(sid, "E", -61, "CoolingUnit", gap=0.1)
    core.station("STATION_SF", sid, "S", 160)
    core.dock("DOCK_SF_RACK", sid, "S", 180, "Rack Hall dock")
    rack_row(sid, 152, 9, -46.2, 0, label="racks")
    against(sid, "S", 169.5, "Workbench")
    try_floor(sid, "CrashCart", 141, -45, 90)
    try_floor(sid, "BoxStack", 136.5, -40, 0)
    try_floor(sid, "CardboardBox", 140, -39.5, 12)
    try_floor(sid, "CableSpool", 150.5, -39.5, 0)
    exposed_ceiling(sid, ducts=(("x", -51.7, 0),))
    for x in (110, 122):
        for z in (-64, -50, -36):
            fixture(sid, "Batten", x, z, 90, y=s.y0 + 15.5, state=light_state(sid, f"c{x},{z}", 0.25, 0.15), light_=light("point", COOL, 18, 0.8))
    for x in (146, 168):
        fixture(sid, "Batten", x, -44, 0, y=s.y0 + 15.5, state=light_state(sid, f"s{x}", 0.25, 0.25), light_=light("point", COOL, 18, 0.8))
    core.camera("SF_RACKHALL", sid, "S", 100, (170, 2, -36), "Rack Hall", head=13.5, pan=70)
    light_panel(sid, "N", 132.5)
    emergency_packs(sid, (("N", 98),))


# ------------------------------------------------------------------------------------------------------
# Cooling Plant


def dress_pumps():
    sid = "CP_PUMPS"
    s = SPACES[sid]
    aisle(sid, 197, 206, -60, 38)  # the walk down the room, door to door
    for z in (-40, -24, -8, 8, 24):
        D.pump(sid, 214, z, 90)
    obox("Header", props_f(sid), 216, 17.5, -8, 72, 2.2, 2.2, r=[0, 90, 0], mat="CorrodedMetal", color=(62, 58, 54), var="AxiomWorn", shape="cyl", nc=True)
    against(sid, "N", 218, "Switchgear", gap=0.2)
    against(sid, "N", 228, "ToolChest")
    wall_run(sid, "S", 218, ["StorageShelf_6", "Barrel"], gap=0.3)
    for z in (-44, -12, 18):
        clutter_floor(sid, 226, z, ("Puddle",))
    for z in range(-56, 36, 8):
        box("Drain", geo(sid), 229.5, 230.5, s.y0, s.y0 + 0.03, z - 3.5, z + 3.5, mat="Metal", color=(30, 30, 32), var="AxiomTread", nc=True, nq=True, ns=True)
    core.dock("DOCK_CP_PUMPS", sid, "W", 28, "Pump Room dock")
    steam_trap("TRAP_PUMPS", sid, "W", -20)
    steam_trap("TRAP_PUMPS_S", sid, "W", 4)
    on_wall(sid, "W", -6, "FireCabinet", 0, check=False)
    exposed_ceiling(sid, pipes=(("z", 200, 2.0),))
    highbays(sid, (204, 222), (-52, -32, -12, 8, 28), dead=0.3, flicker=0.2, col=(190, 225, 240), brightness=1.2)
    core.camera("CP_PUMPS", sid, "W", -56, (216, 2, 0), "Pump Room", head=16, pan=60)
    light_panel(sid, "W", -36)
    emergency_packs(sid, (("W", 14), ("W", -28)))


def dress_chillers():
    sid = "CP_CHILLERS"
    s = SPACES[sid]
    aisle(sid, 54, 124, 28, 40)  # from the corridor door between the chillers
    aisle(sid, 112, 150, 50, 66)  # round to Plant Control's door
    D.chiller(sid, 96, 22, length=30)
    D.chiller(sid, 96, 46, length=30)
    D.tank(sid, 131, 25)
    D.tank(sid, 131, 42, 8, 14)
    D.pump(sid, 74, 60, 0)
    D.pump(sid, 92, 60, 0)
    for (x, z) in ((104, 64), (106.6, 64.4), (104.5, 61.6)):
        try_floor(sid, "Barrel", x, z, 0)
    box("SpillPallet", props_f(sid), 102.3, 108.6, s.y0, s.y0 + 0.4, 60.3, 66.6, mat="SmoothPlastic", color=(200, 160, 40), nc=True, nq=True)
    for (x, z) in ((70, 36), (116, 34), (124, 62), (84, 66)):
        obox("Mist", props_f(sid), x, 0.5, z, 4, 1, 4, t=1, nc=True, nq=True, ns=True, fx="mist")
    exposed_ceiling(sid, pipes=(("x", 18, 2.0), ("x", 66, 2.0)))
    highbays(sid, (66, 90, 114, 140), (20, 34, 52, 66), dead=0.35, flicker=0.2, col=(190, 225, 240), brightness=1.1)
    core.dock("DOCK_CP_CHILLERS", sid, "S", 62, "Chiller Hall dock")
    steam_trap("TRAP_CHILLERS", sid, "N", 100)
    core.camera("CP_CHILLERS", sid, "N", 62, (110, 2, 50), "Chiller Hall", head=16, pan=65)
    light_panel(sid, "N", 76)
    emergency_packs(sid, (("S", 120),))
    back = "CP_BACKHALL"
    for z in (-20, -4, 8):
        fixture(back, "Batten", 144, z, 90, y=SPACES[back].y0 + 12.5, state=light_state(back, z, 0.3, 0.3))
    on_wall(back, "W", -10, "Graffiti", 0, check=False, text="IT SEES YOU")
    on_wall(back, "E", 2, "FireCabinet", 0, check=False)


def dress_control():
    sid = "CP_CONTROL"
    s = SPACES[sid]
    # Everyone faces the plant: the mimic board and the screens on the north wall.
    core.terminal("TERM_CP", sid, "N", 170, "Plant Control terminal")
    on_wall(sid, "N", 190, "MimicPanel", 0)
    on_wall(sid, "N", 226, "WallMonitor_Map", 1.0, check=False)
    for x in (184, 197):
        floor_piece(sid, "ControlConsole_8", x, 56, 180, label="console")
        piece("OfficeChair", props_f(sid), x, s.y0, 60.5, 10 * (x - 190) / 7)
    for k, x in enumerate((180, 192, 204, 216)):
        desk(sid, x, 70, 180, 61 + k, monitors=(("Status", "Log"), ("Off",), ("Terminals",), ("Log", "Upload"))[k],
             lamp=("flicker", None, "on", None)[k], chair=("normal", "tipped", "pushed", "normal")[k])
    for k, x in enumerate((186, 198)):
        desk(sid, x, 82, 180, 70 + k, monitors=("Status",), chair="pushed" if k else "normal")
    for z in (88, 91.4, 94.8):
        against(sid, "W", z, "Locker_Double")
    rec = against(sid, "S", 176, "Counter", gap=0.05)
    px, pz = to_world(rec[2], rec[4], rec[5], -2.0, 0.4)
    piece("CoffeeMaker", props_f(sid), px, s.y0 + 2.96, pz, rec[5])
    px, pz = to_world(rec[2], rec[4], rec[5], 2.4, 0.2)
    piece("Mug", props_f(sid), px, s.y0 + 2.96, pz, rec[5] + 40)
    wall_run(sid, "S", 212, ["FilingCabinet", "FilingCabinet", "FilingCabinet"])
    floor_piece(sid, "MeetingTable", 220, 88, 0, label="lunch table")
    for k in range(3):
        a = math.radians(k * 120 + 30)
        try_floor(sid, "CafeChair" if k != 1 else "CafeChairTipped", 220 + math.sin(a) * 3.4, 88 + math.cos(a) * 3.4, math.degrees(a), label="lunch chair")
    piece("ClutterC", props_f(sid), 220, s.y0 + 2.75, 88, 0)
    try_floor(sid, "TrashBin", 230, 60, 0)
    try_floor(sid, "PlanterDead", 229.5, 47, 0)
    clutter_floor(sid, 206, 76, ("PaperScatter",))
    on_wall(sid, "S", 196, "PosterSafety", 0, check=False)
    on_wall(sid, "S", 204, "NotePA", 0, check=False)
    piece("ClawMarks", props_f(sid), 228.0, s.y0, 99.88, 0)
    troffer_grid(sid, 16, 14, dead=0.35, flicker=0.2)
    core.camera("CP_CONTROL", sid, "S", 156.5, (206, 2, 60), "Plant Control", head=10.6, pan=65)
    light_panel(sid, "W", 70)
    emergency_packs(sid, (("S", 166),))


# ------------------------------------------------------------------------------------------------------
# Maintenance


def dress_service(room_id, n_sid, s_sid, east):
    s = SPACES[n_sid]
    t = SPACES[s_sid]
    x_mid = (s.x0 + s.x1) / 2
    wall_out = "W" if not east else "E"
    wall_in = "E" if not east else "W"
    # The walk down the inner side stays clear; carts and stock wait along the outer wall.
    walk = (s.x1 - 5.5, s.x1) if not east else (s.x0, s.x0 + 5.5)
    aisle(n_sid, walk[0], walk[1], s.z0, s.z1)
    aisle(s_sid, walk[0], walk[1], t.z0, t.z1)
    for sid in (n_sid, s_sid):
        sp = SPACES[sid]
        exposed_ceiling(sid, ducts=(("z", x_mid + (2 if east else -2), 0),), trays=(("z", x_mid + (-3 if east else 3), 2.5),))
        for z in range(int(sp.z0) + 8, int(sp.z1) - 2, 12):
            fixture(sid, "Batten", x_mid, z, 90, y=sp.y0 + 10.5, state=light_state(sid, z, 0.35, 0.3))
    steam_trap(f"TRAP_{room_id}_N", n_sid, wall_out, -34, -2.0)
    steam_trap(f"TRAP_{room_id}_S", s_sid, wall_out, 52, -2.0)
    against(n_sid, wall_out, -40, "JanitorCart", gap=0.2)
    against(n_sid, wall_out, -6, "MopBucket", gap=0.2)
    try_floor(n_sid, "WetFloorSign", x_mid + (1 if east else -1), -10, 40)
    clutter_floor(n_sid, x_mid, -3, ("Puddle",))
    against(n_sid, wall_out, -28, "BoxStack", gap=0.2)
    if east:
        core.dock("DOCK_MT_EAST", s_sid, "E", 20, "East service dock")
        against(s_sid, wall_out, 46, "Pallet", gap=0.2)
        against(s_sid, wall_out, 56, "BoxStack", gap=0.2)
    else:
        against(s_sid, wall_out, 16, "Pallet", gap=0.2)
        against(s_sid, wall_out, 22, "BoxStack", gap=0.2)
        try_floor(s_sid, "Stretcher", x_mid - 1.5, 56, 0)
    on_wall(n_sid, wall_out, -20, "Wayfinding", 0, check=False, text="SERVICE  ·  STAIRS  ·  FABRICATION")
    on_wall(s_sid, wall_out, 18 if east else 26, "PosterCamera" if east else "NoteLearns", 0, check=False)
    on_wall(n_sid, wall_in, -4, "FireCabinet", 0, check=False)
    on_wall(n_sid, wall_in, -40, "ClawMarks" if east else "Scorch", 0, check=False)
    core.camera(room_id, n_sid, wall_in, -6, (x_mid, 2, 40 if east else -46), "East service corridor" if east else "West service corridor", head=12.2, pan=40)
    light_panel(n_sid, wall_out, -12)
    emergency_packs(n_sid, ((wall_in, -36),))
    emergency_packs(s_sid, ((wall_in, 30),))


def dress_loading():
    sid = "MT_LOADING"
    s = SPACES[sid]
    # The loading zone in front of the freight lift, forklift lanes, racking along the south wall.
    aisle(sid, -124, -96, 14, 28)
    hazard_frame(sid, -123, -97, 14.2, 27.6)
    aisle(sid, -150, -54, 34, 40)
    aisle(sid, -150, -136, 14, 22)
    on_wall(sid, "N", -110, "ElevatorDoors", 0, check=False)
    on_wall(sid, "N", -100.5, "StencilText", 0, check=False, text="FREIGHT  ·  OUT OF SERVICE")
    core.station("STATION_MT", sid, "S", -140)
    wall_run(sid, "S", -134.4, ["PalletRack", "PalletRack", "PalletRack"])
    core.dock("DOCK_MT_LOADING", sid, "S", -100, "Freight Hall dock")
    wall_run(sid, "S", -94.4, ["PalletRack", "PalletRack", "PalletRack"])
    wall_run(sid, "N", -94, ["RollCage", "RollCage", "RollCage", "RollCage"])
    against(sid, "N", -74.5, "Compactor")
    wall_run(sid, "W", 24, ["Pallet", "Pallet"], gap=0.3)
    for (x, z) in ((-120, 46), (-116, 46), (-112, 46)):
        try_floor(sid, "Pallet", x, z, 0)
    try_floor(sid, "PalletJack", -106, 46.5, -90)
    try_floor(sid, "BoxStack", -88, 46, 0)
    try_floor(sid, "CrateStack", -78, 46.5, 0)
    floor_line(sid, -150, -54, 33.6, 34.0)
    floor_line(sid, -150, -54, 40.0, 40.4)
    clutter_floor(sid, -100, 30, ("Puddle",))
    exposed_ceiling(sid, ducts=(("x", 30, 0),), pipes=(("x", 56, 1.5),))
    for x in (-140, -118, -96, -74):
        for z in (24, 48, 61):
            fixture(sid, "JarLightHung", x, z, y=s.top, state=light_state(sid, f"{x},{z}", 0.35, 0.25))
    core.camera("MT_LOADING", sid, "N", -60, (-100, 2, 60), "Freight Hall", head=14, pan=65)
    light_panel(sid, "N", -64)
    conduit_trap("TRAP_LOADING", sid, "N", -132)
    emergency_packs(sid, (("N", -128),))
    back = "MT_BACKHALL"
    b = SPACES[back]
    for z in (-26, -10, 4):
        fixture(back, "Batten", -144, z, 90, y=b.y0 + 12.5, state=light_state(back, z, 0.3, 0.3))
    against(back, "E", -2, "TrashBin")
    on_wall(back, "E", -16, "PosterNetwork", 0, check=False)
    on_wall(back, "S", -144, "CautionTape", 0, check=False)
    on_wall(back, "W", -20, "ClawMarks", 0, check=False)


def dress_mech():
    sid = "MT_MECH"
    s = SPACES[sid]
    aisle(sid, -232, -216, 40, 52)
    aisle(sid, -166, -152, 50, 66)
    aisle(sid, -184, -172, 50, 132)  # the walk past the boilers to the terminal
    D.boiler(sid, -200, 72)
    D.boiler(sid, -200, 96)
    for (x, z) in ((-226, 64), (-226, 76), (-226, 88)):
        try_floor(sid, "WaterHeater", x, z, 0)
    for x in (-212, -200, -188):
        against(sid, "N", x, "Switchgear", gap=0.2)
    D.pump(sid, -160, 112, 0)
    D.pump(sid, -160, 124, 0)
    floor_piece(sid, "AirHandler", -204, 124, 0, label="air handler")
    against(sid, "E", 84, "Workbench")
    wall_run(sid, "E", 92, ["StorageShelf_6"])
    against(sid, "E", 72, "ToolChest")
    core.terminal("TERM_MT", sid, "W", 118, "Boiler Room terminal")
    for (x, z) in ((-178, 84), (-208, 112), (-170, 70)):
        obox("Mist", props_f(sid), x, 0.5, z, 4, 1, 4, t=1, nc=True, nq=True, ns=True, fx="steam")
    for (x, z) in ((-214, 128), (-190, 128), (-228, 104)):
        clutter_floor(sid, x, z, ("Puddle",))
    exposed_ceiling(sid, pipes=(("x", 60, 2.0), ("x", 108, 2.0), ("z", -178, 3.0)))
    for u in (-168, -164):
        on_wall(sid, "N", u, "PipeVertical_16", 0, check=False)
    for x in (-220, -196, -172):
        for z in (54, 84, 114):
            fixture(sid, "JarLightHung", x, z, y=s.top, state=light_state(sid, f"{x},{z}", 0.4, 0.25))
    on_wall(sid, "E", 100, "StencilText", 0, check=False, text="DANGER  ·  STEAM")
    on_wall(sid, "N", -176, "NoteLearns", 0, check=False)
    steam_trap("TRAP_MECH", sid, "E", 112)
    steam_trap("TRAP_MECH_E", sid, "E", 124)
    conduit_trap("TRAP_MECH_POWER", sid, "N", -178)
    core.camera("MT_MECH", sid, "E", 44, (-200, 2, 108), "Boiler Room", head=16, pan=60)
    light_panel(sid, "E", 70)
    emergency_packs(sid, (("N", -194), ("E", 104)))


# ------------------------------------------------------------------------------------------------------
# Fabrication Bays


def dress_fab():
    sid = "FAB_ASSEMBLY"
    s = SPACES[sid]
    aisle(sid, -38, 38, 39, 53)  # between the corridor doorways
    aisle(sid, -14, 14, 53, 70)  # down to the Print Floor
    # Workbenches in a row facing the walkway, parts and tools along the north wall behind them.
    for x in (-24, -8, 8, 24):
        floor_piece(sid, "Workbench", x, 31, 180, label="bench")
    core.dock("DOCK_FAB_B", sid, "N", -30, "Assembly Bay dock")
    against(sid, "N", -19, "PartsRack")
    against(sid, "N", -6, "ToolChest")
    against(sid, "N", 6, "ToolChest")
    against(sid, "N", 19, "PartsRack")
    against(sid, "N", 30.5, "ToolChest")
    # Two assembly cells: a shell chassis on a stand between two robot arms.
    for cx in (-26, 26):
        obox("ChassisStand", props_f(sid), cx, 0.4, 62, 3.2, 0.8, 3.2, mat="DiamondPlate", color=(52, 54, 58), var="AxiomTread")
        claim(sid, (cx - 1.8, cx + 1.8, 60.2, 63.8), "chassis stand")
        D.chassis(sid, cx, 62, 180, y=0.8, height=0.7 + 0.3 * hash01(cx))
        hazard_frame(sid, cx - 9, cx + 9, 55.5, 68.5)
        # The arms reach over the stand, so their footprints overlap it.
        floor_piece(sid, "RobotArm", cx - 7.0, 62, -90, label="robot arm", check=False)
        floor_piece(sid, "RobotArm", cx + 7.0, 62, 90, label="robot arm", check=False)
    floor_line(sid, -38, 38, 38.6, 39.0)
    floor_line(sid, -38, 38, 53.0, 53.4)
    try_floor(sid, "Cone", 13, 50, 0)
    exposed_ceiling(sid, ducts=(("x", 22, 0),), trays=(("x", 46, 2.0),))
    highbays(sid, (-24, 0, 24), (26, 46, 62), dead=0.3, flicker=0.2)
    on_wall(sid, "S", -34, "PosterChimera", 0, check=False)
    on_wall(sid, "S", -24, "StencilText", 0, check=False, text="ASSEMBLY  ·  SHELL CHASSIS")
    core.camera("FAB_ASSEMBLY", sid, "N", 12, (0, 2, 50), "Assembly Bay", head=16, pan=65)
    light_panel(sid, "N", -12.6)

    sid = "FAB_PRINT"
    s = SPACES[sid]
    aisle(sid, -14, 14, 72, 123)
    for (x, z) in ((-38, 92), (-38, 114), (38, 92), (38, 114)):
        D.print_gantry(sid, x, z)
    # Finished chassis hang on hoists in rows either side of the aisle, waiting.
    for x in (-22, 22):
        for z in (86, 96, 106, 116):
            D.chassis(sid, x, z, 90 if x < 0 else -90, height=1.0)
            obox("Hoist", props_f(sid), x, 12.5, z, 0.12, 15, 0.12, color=(40, 40, 40), nc=True, ns=True)
            claim(sid, (x - 1.6, x + 1.6, z - 2.0, z + 2.0), "hanging chassis")
    core.dock("DOCK_FAB_A", sid, "S", 0, "Print Floor dock")
    for z in (80, 100, 120):
        against(sid, "W", z, "ResinRack")
        against(sid, "E", z, "ResinRack")
    rec = against(sid, "S", -24, "OfficeDesk")
    for (lx, lz, feed) in ((-1.3, 0.7, "Status"), (1.3, 0.7, "Log")):
        px, pz = to_world(rec[2], rec[4], rec[5], lx, lz)
        piece(f"Monitor_{feed}", props_f(sid), px, s.y0 + 2.8, pz, rec[5])
    px, pz = to_world(rec[2], rec[4], rec[5], 0, -2.8)
    piece("OfficeChair", props_f(sid), px, s.y0, pz, rec[5] + 190)
    for x in (-8, 8, 10.5):
        try_floor(sid, "Barrel", x, 129, 0)
    on_wall(sid, "S", -40, "StencilText", 0, check=False, text="PRINT BAY 1")
    on_wall(sid, "S", 40, "StencilText", 0, check=False, text="PRINT BAY 2")
    on_wall(sid, "E", 110, "NotePrinted", 0, check=False)
    exposed_ceiling(sid, pipes=(("x", 80, 2.0),), beams_every=12)
    highbays(sid, (-38, -22, 22, 38), (88, 112), dead=0.3, flicker=0.25)
    core.camera("FAB_PRINT", sid, "N", 30, (-10, 2, 110), "Print Floor", head=16, pan=65)
    light_panel(sid, "N", 18)


def dress_rooms():
    dress_open_office()
    dress_exec()
    dress_conference()
    dress_break()
    dress_archive()
    dress_datahall()
    dress_noc()
    dress_ups()
    dress_rackhall()
    dress_pumps()
    dress_chillers()
    dress_control()
    dress_service("MT_WEST", "MTW_N", "MTW_S", False)
    dress_service("MT_EAST", "MTE_N", "MTE_S", True)
    dress_loading()
    dress_mech()
    dress_fab()
