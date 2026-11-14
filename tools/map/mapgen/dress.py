"""Dressing: finishes, doors and windows, stairs, lights, weather, and every room's furniture and clutter.

The rules every room follows: nothing stands in front of a doorway; floor pieces are checked against the
walls and each other; small clutter neither collides nor blocks raycasts; every room has lights the Chimera
can kill (in its Lights folder) and a light panel by a door; a share of the lights are dead or flickering,
and the rooms are mostly lit by what's in them (desk lamps, screens, vending machines) and the city outside.
"""
from __future__ import annotations

import math
import random

from . import core, props
from .core import (C, DIMS, GAME, OPENINGS, PIECES, SPACES, against, box, ceiling_piece, claim, conduit_trap, dims,
                   floor_piece, footprint, geo, gui, hash01, keepout, light, light_panel, lights_folder, obox, on_wall,
                   overlaps, piece, props as props_f, rnd, side_yaw, steam_trap, to_world, wall_xz, yaw_facing)

DESK_H = props.DESK_H
STAIRS: list[dict] = []
WEATHER: dict = {"rain": [], "glow": []}
RAIN_TEX = "rbxassetid://85336612099817"

# Parts per kit piece (from the built kit), for the estimate printed at the end.
KIT_PARTS = {
    "Monitor_Status": 12, "Monitor_Camera": 12, "Monitor_Terminals": 12, "Monitor_Log": 12, "Monitor_Squad": 12,
    "Monitor_Upload": 12, "Monitor_Alert": 12, "Monitor_Off": 12, "Keyboard": 2, "Mouse": 4, "Laptop": 6, "Mug": 5,
    "PaperTray": 8, "PCTower": 25, "OfficeChair": 33, "ControlConsole_8": 50, "WallMonitor_Map": 16,
    "WallMonitor_Camera": 16, "WallMonitor_Status": 16, "FilingCabinet": 21, "Locker_Double": 32, "StorageShelf_6": 42,
    "ServerRack_A": 55, "ServerRack_B": 54, "CoolingUnit": 42, "CableBundle_8": 6, "PipeRun_8": 41, "PipeVertical_16": 16,
    "JunctionBox": 14, "Crate_4": 21, "CrateStack": 63, "Barrel": 9, "Railing_8": 15, "Sign_Lockdown": 7,
    "MainframeTerminal": 41, "SecurityCamera": 12, "ShellDock": 39, "ChargingStation": 18, "Floodlight": 15,
    "LightPanel": 10, "CeilingDuct_8": 21, "CableTray_8": 20, "CeilingPipes_8": 21, "CeilingBeam_8": 15,
}

# Bounds of the kit pieces used (size and centre in piece space, from the built kit).
KIT_DIMS = {
    "PCTower": (0.91, 2.08, 2.06, 0, 1.04, -0.03), "OfficeChair": (2.2, 3.71, 2.23, 0, 1.85, 0.09),
    "ControlConsole_8": (8.2, 5.22, 2.64, 0, 2.61, 0.18), "FilingCabinet": (1.8, 4.5, 2.74, 0, 2.25, -0.07),
    "Locker_Double": (3.2, 7.4, 2.02, 0, 3.7, -0.11), "StorageShelf_6": (6.01, 7.0, 2.13, 0, 3.5, 0.06),
    "ServerRack_A": (2.88, 12, 4.1, 0, 6, -0.05), "ServerRack_B": (2.88, 12, 4.1, 0, 6, -0.05),
    "CoolingUnit": (6.1, 16, 3.28, 0, 8, -0.09), "CableBundle_8": (8, 0.36, 1.5, 0, 0.18, 0.1),
    "Crate_4": (4, 4, 4.05, 0, 2, -0.03), "CrateStack": (8.6, 8, 4.87, 0.25, 4, 0.09), "Barrel": (2.3, 3.55, 2.3, 0, 1.77, 0),
    "Railing_8": (8.2, 3.61, 0.6, 0, 1.8, 0), "MainframeTerminal": (7.59, 7.14, 3.4, 0.19, 3.57, 0.2),
    "ShellDock": (6.9, 9.55, 5.95, 0, 4.63, 0.27), "ChargingStation": (5.5, 6.0, 6.95, 0, 3.0, 0.73),
    # Wall pieces (depth is how far they stand off the wall).
    "Sign_Lockdown": (5.2, 2.2, 0.4, 0, 9.3, -0.2), "WallMonitor_Map": (6.6, 4.0, 0.5, 0, 8.0, -0.25),
    "WallMonitor_Camera": (6.6, 4.0, 0.5, 0, 8.0, -0.25), "WallMonitor_Status": (6.6, 4.0, 0.5, 0, 8.0, -0.25),
    "JunctionBox": (2.4, 16.0, 0.8, 0, 8.0, -0.4), "PipeRun_8": (8.0, 3.6, 1.6, 0, 11.0, -0.8),
    "PipeVertical_16": (2.3, 16.0, 1.2, 0, 8.0, -0.6), "LightPanel": (1.9, 3.0, 0.5, 0, 5.2, -0.25),
    "SecurityCamera": (1.0, 2.0, 2.0, 0, 12.2, -1.0),
}
DIMS.update(KIT_DIMS)


def rng_for(*key):
    return random.Random(int(hash01(*key) * 2 ** 31))


# ------------------------------------------------------------------------------------------------------
# Lights


def fixture(sid, name, x, z, yaw=0.0, drop=0.0, state="on", y=None, light_=None):
    """A light fixture: 'on' (in the room's Lights folder), 'flicker' (lit, but stutters), or 'dead'."""
    s = SPACES[sid]
    yy = (s.ceil - drop) if y is None else y
    opts = {}
    if light_:
        opts["light"] = light_
    if state == "dead":
        return piece(name, props_f(sid), x, yy, z, yaw, dead=True, **opts)
    if state in ("flicker", "dying", "buzz"):
        opts["flicker"] = state
    return piece(name, lights_folder(sid), x, yy, z, yaw, **opts)


def light_state(sid, i, dead=0.25, flicker=0.12):
    r = hash01("ls", sid, i)
    if r < dead:
        return "dead"
    if r < dead + flicker:
        return "flicker" if hash01("lf", sid, i) < 0.6 else "dying"
    return "on"


def troffer_grid(sid, step_x=12, step_z=12, dead=0.3, flicker=0.12, rect=None, kind="Troffer", yaw=0):
    """Troffers on the drop ceiling every step studs (a 2 x 4 fixture; yaw 0 runs its length along z)."""
    s = SPACES[sid]
    x0, x1, z0, z1 = rect or (s.x0, s.x1, s.z0, s.z1)
    nx = max(1, int((x1 - x0) // step_x))
    nz = max(1, int((z1 - z0) // step_z))
    ox = x0 + ((x1 - x0) - (nx - 1) * step_x) / 2
    oz = z0 + ((z1 - z0) - (nz - 1) * step_z) / 2
    out = []
    i = 0
    for a in range(nx):
        for b in range(nz):
            x, z = ox + a * step_x, oz + b * step_z
            st = light_state(sid, i, dead, flicker)
            out.append((x, z))
            fixture(sid, kind, x, z, yaw, state=st)
            i += 1
    return out


def emergency_packs(sid, spots):
    """Twin-head emergency lights on the walls, off until the wing's terminal is rebooted."""
    s = SPACES[sid]
    if not core.ROOMS[s.room].wing or s.room in ("CORE", "INSERTION") or core.ROOMS[s.room].wing == "FAB":
        return
    for (side, u) in spots:
        y = min(0.0, (s.ceil - s.y0) - 11.6)
        on_wall(sid, side, u, "EmergencyPack", y, f"Facility/EmergencyLights/{s.room}")


def exit_sign(sid, side, u, y=None):
    s = SPACES[sid]
    yy = min(0.0, (s.ceil - s.y0) - 12.0) if y is None else y
    return on_wall(sid, side, u, "ExitSign", yy, check=False)


# ------------------------------------------------------------------------------------------------------
# Openings: frames, doors, lift doors


def place_openings():
    for o in OPENINGS:
        g = core.opening_geometry(o)
        if not g:
            continue
        side_a, side_b, line, lo, hi = g
        base = core.opening_base(o)
        centre = o.at + o.width / 2
        h = core.open_height(o)
        if side_a in "NS":
            x, z, yaw = centre, line, 0
        else:
            x, z, yaw = line, centre, 90
        a, b = SPACES[o.a], SPACES[o.b]
        rooms_styles = {a.walls, b.walls}
        style = "metal"
        if o.kind in ("gate",) or rooms_styles & {"atrium", "lobby"}:
            style = "stone"
        if o.kind == "elevator":
            style = "steel"
        elif rooms_styles & {"exec"} and o.kind == "door":
            style = "wood"
        elif rooms_styles <= {"block", "blockplain"}:
            style = "block" if o.kind == "frame" else "metal"
        name = props.frame(o.width, h, style)
        folder = geo(o.a if o.a < o.b else o.b)
        piece(name, folder, x, base, z, yaw)
        if o.kind == "door":
            slide = door_slide(o, side_a, line, base)
            slide_local = 8 * slide if yaw == 0 else -8 * slide
            ra, rb = a.room, b.room
            door_prefab = {"office": "Door_Office", "steel": "Door_Steel", "glass": "Door_Glass"}[o.style]
            piece(door_prefab, "Map/Doors", x, base, z, yaw, id=o.door,
                  a={"DoorId": o.door, "TargetId": o.door, "TargetKind": "LockDoor", "RoomA": ra, "RoomB": rb,
                     "DisplayName": o.name, "Slide": slide_local})
            # A badge reader beside the door on each side, on the latch side (away from the pocket).
            for sid, side in ((o.a, side_a), (o.b, side_b)):
                s = SPACES[sid]
                u = o.at - 1.0 if slide > 0 else o.at + o.width + 1.0
                if core.wall_free(s, side, u - 0.3, u + 0.3, s.y0 + base + 3.9, s.y0 + base + 4.9, "reader", report=False):
                    on_wall(sid, side, u, "CardReader", base - s.y0, check=False)
        # Exit signs over the main doorways out of the big rooms.
        if o.kind in ("door", "gate") and base < 1:
            for sid, side in ((o.a, side_a), (o.b, side_b)):
                s = SPACES[sid]
                if s.ceil - (base + h) >= 1.6 and hash01("exit", o.a, o.b, sid) < 0.7:
                    yy = base + h + 0.4 - 10.7
                    if core.wall_free(s, side, centre - 1.3, centre + 1.3, s.y0 + yy + 10.6, s.y0 + yy + 11.8, "exit", report=False):
                        on_wall(sid, side, centre, "ExitSign", yy, check=False)


def door_slide(o, side_a, line, base) -> int:
    """Which way along the wall (+1 / -1) the door's pocket fits inside solid wall."""
    for direction in (1, -1):
        edge = o.at + o.width if direction > 0 else o.at
        p_lo, p_hi = (edge, edge + 8.6) if direction > 0 else (edge - 8.6, edge)
        clear = True
        for other in OPENINGS:
            if other is o:
                continue
            g = core.opening_geometry(other)
            if not g or abs(g[2] - line) > 1e-6 or (g[0] in "NS") != (side_a in "NS"):
                continue
            if abs(core.opening_base(other) - base) > 12:
                continue
            if other.at - 1.2 < p_hi and other.at + other.width + 1.2 > p_lo:
                clear = False
        for gz in core.GLAZING:
            g = core.shared_wall(SPACES[gz["a"]], SPACES[gz["b"]])
            if abs(g[2] - line) < 1e-6 and (g[0] in "NS") == (side_a in "NS") and gz["from"] - 0.5 < p_hi and gz["to"] + 0.5 > p_lo:
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
            return direction
    core.err(f"door {o.door}: no solid wall to slide into")
    return 1


# ------------------------------------------------------------------------------------------------------
# Windows: exterior glazing and the glass between rooms


def exterior_windows():
    for ex in core.EXTERIOR:
        s = SPACES[ex["space"]]
        side = ex["side"]
        f = core.face_coord(s, side)
        out = -1 if side in "NW" else 1  # direction from the room to the outside
        y0, y1 = s.y0 + ex["sill"], s.y0 + ex["head"]
        u0, u1 = ex["from"], ex["to"]
        folder = geo(s.id)
        kind = ex["kind"]

        def wbox(name, a0, a1, b0, b1, ya, yb, **kw):
            """a: along the wall, b: depth from the face (positive outward)."""
            d0, d1 = f + out * b0, f + out * b1
            if side in "NS":
                return box(name, folder, a0, a1, ya, yb, min(d0, d1), max(d0, d1), **kw)
            return box(name, folder, min(d0, d1), max(d0, d1), ya, yb, a0, a1, **kw)

        if kind == "louver":
            u = u0
            while u + 8 <= u1 + 1e-6:
                x, z = wall_xz(s, side, u + 4, 0)
                yaw = side_yaw(side)
                piece("Louver", folder, x, y0, z, yaw)
                u += 8
            add_rain(s, side, u0, u1, y0, y1, out, heavy=True)
            continue
        mullion = {"curtain": 8, "window": 6, "clerestory": 8}[kind]
        alu = (44, 46, 50)
        glass_d = 1.2  # the glass sits 1.2 into the 2-thick wall from the inside face
        n = int(round((u1 - u0) / mullion))
        step = (u1 - u0) / n
        for i in range(n + 1):
            u = u0 + i * step
            wbox("Mullion", u - 0.3, u + 0.3, -0.25, 1.9, y0, y1, mat="Metal", color=alu, var="AxiomSteel")
        transoms = [y0, y1]
        if kind == "curtain":
            transoms += [y0 + 13.3, y0 + 26.6]
        for ty in transoms:
            wbox("Transom", u0, u1, -0.2, 1.9, ty - 0.3 if ty > y0 else ty, ty + 0.3 if ty < y1 else ty, mat="Metal", color=alu, var="AxiomSteel") if ty not in (y0, y1) else None
        # Glass, with rain on the outside of the pane.
        for i in range(n):
            a0, a1 = u0 + i * step + 0.3, u0 + (i + 1) * step - 0.3
            outer = {"N": "Front", "S": "Back", "W": "Left", "E": "Right"}[side]
            g = wbox("Glass", a0, a1, glass_d - 0.05, glass_d + 0.05, y0, y1, mat="Glass", color=(120, 140, 150), t=0.82, refl=0.08, ns=True,
                     tex=[{"id": RAIN_TEX, "face": outer, "u": 8, "v": 8, "t": 0.25, "tag": "RainGlass"}])
        # Sill and head trim on the room side.
        if kind != "curtain":
            wbox("Sill", u0, u1, -0.35, 0.6, y0 - 0.3, y0, mat="Marble", color=(100, 98, 92), var="AxiomTerrazzo")
            wbox("SillApron", u0, u1, -0.25, 0.0, y0 - 0.9, y0 - 0.3, mat="Plaster", color=C["paint"], var="AxiomPlaster")
        else:
            wbox("Threshold", u0, u1, -0.3, 2.0, y0, y0 + 0.4, mat="Metal", color=alu, var="AxiomSteel")
        # Blinds in offices: some down, some up, a few hanging crooked.
        if kind == "window" and s.walls in ("office", "exec", "cool", "corridor"):
            for i in range(n):
                a0, a1 = u0 + i * step + 0.35, u0 + (i + 1) * step - 0.35
                r = hash01("blind", s.id, side, i)
                head = y1 - 0.2
                if r < 0.35:
                    low = head - 0.8  # rolled up
                elif r < 0.75:
                    low = y0 + (y1 - y0) * (0.3 + 0.4 * hash01("bl", s.id, i))
                else:
                    low = y0 + 0.3
                for k in range(int((head - low) / 0.5)):
                    yy = head - 0.25 - 0.5 * k
                    tilt = 0.18 if r < 0.9 else 0.3
                    wbox("Slat", a0, a1, -0.45, -0.25, yy - 0.04, yy + 0.04, mat="SmoothPlastic", color=(176, 174, 166), nc=True, nq=True, ns=False)
                wbox("Headrail", a0 - 0.1, a1 + 0.1, -0.5, -0.2, head, head + 0.25, mat="SmoothPlastic", color=(176, 174, 166), nc=True, nq=True)
        add_rain(s, side, u0, u1, y0, y1, out, heavy=kind == "curtain")
        add_glow(s, side, u0, u1, y0, y1, out, strong=kind == "curtain")


def add_rain(s, side, u0, u1, y0, y1, out, heavy=False):
    """A rain emitter outside a window: an invisible slab above the head, raining down past the glass."""
    f = core.face_coord(s, side)
    d = f + out * 6
    if side in "NS":
        c = [rnd((u0 + u1) / 2), rnd(y1 + 14), rnd(d)]
        size = [rnd(u1 - u0 + 8), 1, 6]
    else:
        c = [rnd(d), rnd(y1 + 14), rnd((u0 + u1) / 2)]
        size = [6, 1, rnd(u1 - u0 + 8)]
    WEATHER["rain"].append({"c": c, "s": size, "rate": rnd(min(400, (u1 - u0) * (6 if heavy else 3))), "fall": rnd(y1 - y0 + 30)})


def add_glow(s, side, u0, u1, y0, y1, out, strong=False):
    """City glow through a window: cool spotlights outside aimed in and down (lightning flashes them)."""
    f = core.face_coord(s, side)
    step = 24 if strong else 30
    n = max(1, int((u1 - u0) // step))
    for i in range(n):
        u = u0 + (u1 - u0) * (i + 0.5) / n
        d = f + out * 10
        y = min(y1 + 6, s.y0 + 30)
        if side in "NS":
            pos, look = [rnd(u), rnd(y), rnd(d)], [rnd(u), s.y0, rnd(f - out * 30)]
        else:
            pos, look = [rnd(d), rnd(y), rnd(u)], [rnd(f - out * 30), s.y0, rnd(u)]
        WEATHER["glow"].append({"p": pos, "look": look, "c": [118, 136, 168], "b": 2.0 if strong else 1.3, "range": 60,
                                "angle": 110, "shadows": strong or i % 2 == 0})


def glass_walls():
    """Glass in the walls between rooms (the deck over the atrium, the NOC over the data hall)."""
    for gz in core.GLAZING:
        a, b = SPACES[gz["a"]], SPACES[gz["b"]]
        side_a, side_b, line, lo, hi = core.shared_wall(a, b)
        u0, u1, y0, y1 = gz["from"], gz["to"], gz["base"], gz["top"]
        folder = geo(a.id)
        n = max(1, int(round((u1 - u0) / 6)))
        step = (u1 - u0) / n
        for i in range(n + 1):
            u = u0 + i * step
            if side_a in "NS":
                box("Mullion", folder, u - 0.25, u + 0.25, y0, y1, line - 1, line + 1, mat="Metal", color=(44, 46, 50), var="AxiomSteel")
            else:
                box("Mullion", folder, line - 1, line + 1, y0, y1, u - 0.25, u + 0.25, mat="Metal", color=(44, 46, 50), var="AxiomSteel")
        for i in range(n):
            a0, a1 = u0 + i * step + 0.25, u0 + (i + 1) * step - 0.25
            if side_a in "NS":
                box("Glass", folder, a0, a1, y0, y1, line - 0.05, line + 0.05, mat="Glass", color=(120, 140, 150), t=0.75, refl=0.06, ns=True)
            else:
                box("Glass", folder, line - 0.05, line + 0.05, y0, y1, a0, a1, mat="Glass", color=(120, 140, 150), t=0.75, refl=0.06, ns=True)
        for yy, h in ((y0, 0.35), (y1 - 0.35, 0.35)):
            if side_a in "NS":
                box("Frame", folder, u0, u1, yy, yy + h, line - 1.12, line + 1.12, mat="Metal", color=(44, 46, 50), var="AxiomSteel")
            else:
                box("Frame", folder, line - 1.12, line + 1.12, yy, yy + h, u0, u1, mat="Metal", color=(44, 46, 50), var="AxiomSteel")


# ------------------------------------------------------------------------------------------------------
# Stairs (switchback fire stairs; an invisible ramp under each flight carries mercs and shells)


def flight(sid, x0, x1, z_low, z_high, y_low, rise, folder):
    """A flight between z_low (at y_low) and z_high (at y_low + rise), across x0..x1."""
    d = 1 if z_high > z_low else -1
    run = abs(z_high - z_low) / rise
    col = (78, 78, 76)
    for i in range(1, rise + 1):
        za = z_low + d * (i - 1) * run
        zb = z_low + d * i * run
        y = y_low + i
        box("Tread", folder, x0, x1, y - 0.25, y, min(za, zb), max(za, zb), mat="Concrete", color=col, var="AxiomConcrete", nc=True, nq=True)
        box("Riser", folder, x0, x1, y - 1, y - 0.25, min(za, za + d * 0.2), max(za, za + d * 0.2), mat="Concrete", color=col, var="AxiomConcrete", nc=True, nq=True, ns=True)
        box("Nosing", folder, x0 + 0.2, x1 - 0.2, y - 0.02, y + 0.02, min(za, za + d * 0.3), max(za, za + d * 0.3), mat="SmoothPlastic", color=(170, 140, 40), nc=True, nq=True, ns=True)
    length = math.hypot(abs(z_high - z_low), rise)
    angle = math.degrees(math.atan2(rise, abs(z_high - z_low)))
    cz = (z_low + z_high) / 2
    # The soffit under the flight, so it reads as solid from below.
    obox("Soffit", folder, (x0 + x1) / 2, y_low + rise / 2 - 0.9, cz, x1 - x0, 0.6, length, mat="Concrete", color=(64, 64, 62), var="AxiomConcrete",
         r=[d * angle, 0, 0], nc=True, nq=True)
    # The ramp: a wedge rising toward z_high.
    obox("StairRamp", folder, (x0 + x1) / 2, y_low + rise / 2, cz, x1 - x0, rise, abs(z_high - z_low), yaw=0 if d > 0 else 180,
         mat="SmoothPlastic", color=(40, 40, 40), var="", wedge=True, t=1, ns=True, nq=True)
    return length


def rail(folder, x, z0, z1, y0, y1, col=(170, 140, 40)):
    """A handrail on posts from (z0, y0) to (z1, y1) at x."""
    length = math.hypot(z1 - z0, y1 - y0)
    angle = math.degrees(math.atan2(y1 - y0, abs(z1 - z0))) * (1 if z1 < z0 else -1)
    obox("Handrail", folder, x, (y0 + y1) / 2 + 3.4, (z0 + z1) / 2, 0.2, 0.2, length, mat="Metal", color=col, r=[angle, 0, 0], nc=True)
    obox("MidRail", folder, x, (y0 + y1) / 2 + 1.8, (z0 + z1) / 2, 0.12, 0.12, length, mat="Metal", color=(40, 40, 42), r=[angle, 0, 0], nc=True, ns=True)
    n = max(2, int(abs(z1 - z0) // 4) + 1)
    for k in range(n):
        t = k / (n - 1)
        obox("Post", folder, x, y0 + (y1 - y0) * t + 1.7, z0 + (z1 - z0) * t, 0.18, 3.4, 0.18, mat="Metal", color=(40, 40, 42), nc=True)
    # A solid but invisible guard so nobody walks off the open side.
    obox("Guard", folder, x, (y0 + y1) / 2 + 2.5, (z0 + z1) / 2, 0.3, 5, length, mat="SmoothPlastic", color=(0, 0, 0), r=[angle, 0, 0], t=1, nq=True, ns=True)


def fire_stair(sid, east: bool):
    """Switchback stair: bottom landing at the south end, flight 1 up the lobby-side half to the mid landing
    at the north end (y 12), flight 2 back down the far half to the top landing (y 24) at the south end,
    where the deck door is."""
    s = SPACES[sid]
    folder = geo(sid)
    inner = (s.x0, s.x0 + 7) if east else (s.x1 - 7, s.x1)  # the half next to the lobby (and the deck door)
    outer = (s.x1 - 7, s.x1) if east else (s.x0, s.x0 + 7)
    zb, zm = s.z1 - 8, s.z0 + 10  # flights run between these
    l1 = flight(sid, *inner, zb, zm, 0, 12, folder)
    l2 = flight(sid, *outer, zm, zb, 12, 12, folder)
    box("MidLanding", folder, s.x0, s.x1, 11, 12, s.z0, zm, mat="Concrete", color=(78, 78, 76), var="AxiomConcrete")
    box("TopLanding", folder, s.x0, s.x1, 23, 24, zb, s.z1, mat="Concrete", color=(78, 78, 76), var="AxiomConcrete")
    gap = (inner[0] - 2, inner[0]) if east is False else (inner[1], inner[1] + 2)
    # Rails: on the open edges of the flights, the mid landing and the top landing.
    rx_in = inner[0] - 0.1 if not east else inner[1] + 0.1
    rx_out = outer[1] + 0.1 if not east else outer[0] - 0.1
    rail(folder, rx_in, zb, zm, 0, 12)
    rail(folder, rx_out, zm, zb, 12, 24)
    ra, rb = (outer[1], s.x1) if not east else (s.x0, outer[0])
    obox("LandingRail", folder, (ra + rb) / 2, 24 + 3.4, zb - 0.1, rb - ra, 0.2, 0.2, mat="Metal", color=(170, 140, 40), nc=True)
    obox("LandingGuard", folder, (ra + rb) / 2, 24 + 2.5, zb - 0.1, rb - ra, 5, 0.3, mat="SmoothPlastic", color=(0, 0, 0), t=1, nq=True, ns=True)
    ga, gb = (outer[1], inner[0]) if not east else (inner[1], outer[0])
    obox("GapRail", folder, (ga + gb) / 2, 12 + 3.4, zm + 0.1, gb - ga, 0.2, 0.2, mat="Metal", color=(170, 140, 40), nc=True)
    obox("GapGuard", folder, (ga + gb) / 2, 12 + 2.5, zm + 0.1, gb - ga, 5, 0.3, mat="SmoothPlastic", color=(0, 0, 0), t=1, nq=True, ns=True)
    # Painted floor numbers on the landings.
    on_wall(sid, "S", (s.x0 + s.x1) / 2, "FloorNumber", 19.0, check=False, text="62")
    on_wall(sid, "S", (s.x0 + s.x1) / 2, "FloorNumber", -5.0, check=False, text="61")
    # The stairs on down are chained off: a barrier and a sign in the nook under the mid landing.
    on_wall(sid, "N", (s.x0 + s.x1) / 2, "Barrier", 0, check=False)
    foot = ((inner[0] + inner[1]) / 2, zb + 2)
    top = ((s.x0 + s.x1) / 2, (zb + s.z1) / 2)
    STAIRS.append({"foot": foot, "top": top, "length": l1 + l2 + (zb - zm) * 0 + 12,
                   "blocked": (inner[0], inner[1], zm, zb), "landing": (s.x0 + 0.5, s.x1 - 0.5, zb + 0.5, s.z1 - 0.5)})
    keepout(sid, min(inner), max(inner), zm, zb)
    keepout(sid, min(outer), max(outer), zm, zb)
    return inner, outer, zb, zm


# ------------------------------------------------------------------------------------------------------
# Furniture helpers


def try_floor(sid, name, x, z, yaw=0.0, folder=None, label=None, **opts):
    """Places a floor piece only if it fits (inside the room, clear of doorways, other pieces and their
    fronts, with its own front clear)."""
    if not core.fits(sid, name, x, z, yaw, label):
        return None
    return floor_piece(sid, name, x, z, yaw, folder=folder, check=False, label=label, **opts)


def clutter_floor(sid, x, z, kinds=("PaperScatter",), r=0.0):
    """Flat clutter (papers, a puddle) placed without a footprint claim."""
    s = SPACES[sid]
    for i, k in enumerate(kinds):
        piece(k, props_f(sid), x + r * i, s.y0, z, hash01("cf", sid, x, z, i) * 360)


def desk(sid, x, z, yaw, seed, monitors=None, lamp=None, chair="normal", open_drawer=False, clutter=True, tower=True, check=True,
         claimed=False):
    """An office desk with its computer, clutter and chair (chair: normal, pushed, tipped, none). The user sits
    on the desk's -Z side. `claimed`: the desk stands in an area already claimed (a bench of desks), so the
    chair is placed without a footprint of its own."""
    s = SPACES[sid]
    name = "OfficeDeskOpen" if open_drawer else "OfficeDesk"
    floor_piece(sid, name, x, z, yaw, check=check, label="desk")
    top = s.y0 + DESK_H
    feeds = monitors if monitors is not None else (pick_feed(sid, seed),)
    spots = [(0.0, 0.7, 0.0)] if len(feeds) == 1 else [(-1.3, 0.7, -10.0), (1.3, 0.7, 10.0)]
    for (lx, lz, turn), feed in zip(spots, feeds):
        px, pz = to_world(x, z, yaw, lx, lz)
        piece(f"Monitor_{feed}", props_f(sid), px, top, pz, yaw + turn)
    px, pz = to_world(x, z, yaw, -0.2, -0.65)
    piece("Keyboard", props_f(sid), px, top, pz, yaw + 4 * (hash01("kb", sid, seed) - 0.5))
    px, pz = to_world(x, z, yaw, 1.2, -0.6)
    piece("Mouse", props_f(sid), px, top, pz, yaw + 20 * hash01("ms", sid, seed))
    if clutter:
        kind = ("ClutterA", "ClutterB", "ClutterC")[int(hash01("cl", sid, seed) * 3) % 3]
        piece(kind, props_f(sid), x, top, z, yaw)
        if hash01("mug", sid, seed) < 0.5:
            px, pz = to_world(x, z, yaw, 2.4, -0.9)
            piece("Mug", props_f(sid), px, top, pz, yaw + 60 * hash01("mg", seed))
    if tower:
        px, pz = to_world(x, z, yaw, -2.2, 0.4)
        piece("PCTower", props_f(sid), px, s.y0, pz, yaw)
    if lamp:
        px, pz = to_world(x, z, yaw, -2.3, 0.6)
        if lamp == "dead":
            piece("DeskLamp", props_f(sid), px, top, pz, yaw + 20, dead=True)
        else:
            piece("DeskLamp", lights_folder(sid), px, top, pz, yaw + 20, **({"flicker": lamp} if lamp in ("flicker", "dying") else {}))
    if chair != "none":
        back = 2.6 + (1.6 if chair == "pushed" else 0.6 * hash01("cb", sid, seed))
        px, pz = to_world(x, z, yaw, -0.2 + 0.6 * (hash01("cx", seed) - 0.5), -back)
        turn = yaw + 180 + (60 if chair == "pushed" else 30) * (hash01("ct", sid, seed) - 0.5)
        if chair == "tipped":
            px, pz = to_world(x, z, yaw, 0.3, -4.2)
            piece("OfficeChair", props_f(sid), px, s.y0 + 1.0, pz, turn + 40, tilt=-82)
        elif claimed:
            piece("OfficeChair", props_f(sid), px, s.y0, pz, turn)
        else:
            try_floor(sid, "OfficeChair", px, pz, turn, label="office chair")
    if hash01("bag", sid, seed) < 0.18:
        px, pz = to_world(x, z, yaw, 1.0, 0.3)
        piece("Backpack" if hash01("bk", seed) < 0.6 else "Handbag", props_f(sid), px, s.y0, pz, yaw + 30)


FEEDS = ("Status", "Log", "Off", "Off", "Off", "Squad", "Terminals", "Off", "Upload", "Off", "Log")


def pick_feed(sid, seed):
    return FEEDS[int(hash01("feed", sid, seed) * len(FEEDS)) % len(FEEDS)]


def partition(sid, x0, x1, z0, z1, h=5.0, color=(64, 68, 76)):
    s = SPACES[sid]
    box("Partition", props_f(sid), x0, x1, s.y0, s.y0 + h - 0.12, z0, z1, mat="Fabric", color=color, var="AxiomFabric")
    box("PartitionCap", props_f(sid), x0 - 0.03, x1 + 0.03, s.y0 + h - 0.12, s.y0 + h, z0 - 0.03, z1 + 0.03, mat="Metal", color=(140, 142, 144), var="AxiomSteel", ns=True)


def rack_row(sid, x0, n, z, yaw, tray=True, cooler_every=0, label="racks", open_every=0):
    """n server racks side by side along x from x0, facing yaw (0 north, 180 south), cable tray above."""
    s = SPACES[sid]
    x = x0
    for i in range(n):
        if cooler_every and i and i % cooler_every == 0:
            floor_piece(sid, "CoolingUnit", x + 3.05, z, yaw, label="in-row cooler")
            x += 6.1
        kit = "ServerRack_A" if (i + int(x0)) % 3 else "ServerRack_B"
        floor_piece(sid, kit, x + 1.44, z, yaw, label=label)
        x += 2.88
    if tray:
        length = x - x0
        pieces_n = max(1, int(round(length / 8)))
        start = (x0 + x) / 2 - pieces_n * 4
        tray_y = s.y0 + 13.6
        off = 0.9 if yaw == 0 else -0.9
        for k in range(pieces_n):
            piece("CableTray_8", geo(sid), start + 8 * k + 4, tray_y, z + off, 0)
        for k in range(pieces_n + 1):
            obox("HangerRod", geo(sid), start + 8 * k, (tray_y + s.top) / 2, z + off, 0.1, s.top - tray_y, 0.1, color=(60, 60, 62), nc=True, ns=True)
    return x


def column(sid, x, z, d=4.0, folder=None, mat=("Plaster", "AxiomPlaster", (96, 94, 90))):
    s = SPACES[sid]
    f = folder or geo(sid)
    obox("Column", f, x, (s.y0 + s.ceil) / 2, z, s.ceil - s.y0, d, d, mat=mat[0], color=mat[2], var=mat[1], shape="cyl", r=[0, 0, 90])
    obox("ColumnBase", f, x, s.y0 + 0.4, z, 0.8, d + 0.4, d + 0.4, mat="Marble", color=(60, 60, 60), var="AxiomTerrazzo", shape="cyl", r=[0, 0, 90])
    claim(s.id, (x - d / 2 - 0.2, x + d / 2 + 0.2, z - d / 2 - 0.2, z + d / 2 + 0.2), "column")


def exposed_ceiling(sid, ducts=(), pipes=(), trays=(), beams_every=0):
    """Service runs under an exposed slab: ducts, pipe bundles and cable trays wall to wall."""
    s = SPACES[sid]
    for (axis, at, drop) in ducts:
        run(sid, "CeilingDuct_8", axis, at, drop)
    for (axis, at, drop) in pipes:
        run(sid, "CeilingPipes_8", axis, at, drop)
    for (axis, at, drop) in trays:
        run(sid, "CableTray_8", axis, at, drop)
    if beams_every:
        z = s.z0 + beams_every
        while z < s.z1 - 2:
            box("Beam", geo(sid), s.x0, s.x1, s.top - 1.2, s.top, z - 0.5, z + 0.5, mat="Metal", color=(40, 42, 44), var="AxiomSteel")
            z += beams_every


def run(sid, kit, axis, at, drop=0.0):
    s = SPACES[sid]
    lo, hi = (s.x0, s.x1) if axis == "x" else (s.z0, s.z1)
    n = int((hi - lo) // 8)
    start = (lo + hi) / 2 - n * 4
    for i in range(n):
        c = start + 8 * i + 4
        x, z = (c, at) if axis == "x" else (at, c)
        piece(kit, geo(sid), x, s.top - drop, z, 0 if axis == "x" else 90)


def ceiling_holes(sid, count):
    """Missing ceiling tiles (2 x 4 grid cells) with wires and a fallen tile under some."""
    s = SPACES[sid]
    r = rng_for("holes", sid)
    holes = []
    for i in range(count * 6):
        if len(holes) >= count:
            break
        x = s.x0 + 4 + 2 * r.randrange(int((s.w - 8) // 2))
        z = s.z0 + 4 + 4 * r.randrange(max(1, int((s.d - 8) // 4)))
        h = (x, x + 2, z, z + 4)
        if any(overlaps(h, o, -1) for o in holes):
            continue
        holes.append(h)
    for i, (x0, x1, z0, z1) in enumerate(holes):
        cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
        if i % 2 == 0:
            piece("HangingWires", props_f(sid), cx, s.ceil, cz, hash01("hw", sid, i) * 360)
        if i % 3 == 1:
            piece("HangingTile", props_f(sid), cx, s.ceil, cz - 2, 0)
        else:
            try_floor(sid, "FallenTile", cx + 1, cz + 1, hash01("ft", sid, i) * 360)
    return holes


def finishes():
    for s in SPACES.values():
        core.finish_walls(s)
        holes = ceiling_holes(s.id, s.holes) if s.ceiling == "tile" and s.holes else []
        core.floor_and_ceiling(s, holes)
        if s.ceiling == "plaster" and not s.drop:
            box("Ceiling", geo(s.id), s.x0, s.x1, s.top - 0.3, s.top, s.z0, s.z1, mat="Plaster", color=(70, 70, 68), var="AxiomPlaster", ns=True)


# ------------------------------------------------------------------------------------------------------
# The Reception (the Core)


def dress_core():
    sid = "CORE"
    s = SPACES[sid]
    cx, cz = 0.0, -102.0
    core.dock("DOCK_CORE_SW", sid, "S", -28, "Reception dock south-west")
    core.dock("DOCK_CORE_NE", sid, "E", -100, "Reception dock east")
    core.station("STATION_CORE", sid, "W", -96)
    # The dais the reception desk stands on is the finale platform.
    keepout(sid, -12, 12, -66, -52)  # the walk in from the lobby
    box("Dais", geo(sid), -18, 18, 0, 0.5, cz - 17, cz + 17, mat="Marble", color=(92, 90, 86), var="AxiomTerrazzo", refl=0.06)
    for (x0, x1, z0, z1) in ((-18.15, 18.15, cz - 17.15, cz - 16.95), (-18.15, 18.15, cz + 16.95, cz + 17.15), (-18.15, -17.95, cz - 17, cz + 17), (17.95, 18.15, cz - 17, cz + 17)):
        box("DaisEdge", geo(sid), x0, x1, 0, 0.52, z0, z1, mat="Metal", color=(150, 152, 154), var="AxiomSteel", ns=True)
    GAME["platform"] = {"c": [cx, 6.5, cz], "s": [36, 12, 34]}
    # The Uplink: a black glass monolith to the ceiling with data lines up its corners, ringed by the desk.
    U = 2.4
    box("Uplink", geo(sid), cx - U, cx + U, 0.5, 40, cz - U, cz + U, mat="Glass", color=(12, 14, 18), refl=0.18)
    for sx in (-1, 1):
        for sz in (-1, 1):
            obox("DataLine", geo(sid), cx + sx * (U + 0.08), 20.25, cz + sz * (U + 0.08), 0.14, 39.5, 0.14, mat="Neon", color=(36, 104, 150), nc=True, ns=True, nq=True)
    for y in (13.0, 30.0):
        for (dx, dz, sx_, sz_) in ((0, -U - 0.25, 2 * U + 0.6, 0.12), (0, U + 0.25, 2 * U + 0.6, 0.12), (-U - 0.25, 0, 0.12, 2 * U + 0.6), (U + 0.25, 0, 0.12, 2 * U + 0.6)):
            obox("Halo", geo(sid), cx + dx, y, cz + dz, sx_, 0.12, sz_, mat="Neon", color=(36, 104, 150), nc=True, ns=True, nq=True)
    # A few status lights blink in the glass.
    for k in range(10):
        a = hash01("up", k)
        face = k % 4
        dx, dz = ((0, -U - 0.03), (0, U + 0.03), (-U - 0.03, 0), (U + 0.03, 0))[face]
        along = (hash01("ua", k) - 0.5) * (2 * U - 0.8)
        px, pz = (cx + along, cz + dz) if face < 2 else (cx + dx, cz + along)
        obox("UplinkLed", geo(sid), px, 2 + a * 34, pz, 0.2, 0.08, 0.2, mat="Neon", color=(60, 160, 220), nc=True, ns=True, nq=True, tag="KitLeds")
    reception_desk(sid, cx, cz)
    floor_piece(sid, "ControlConsole_8", cx + 13.8, cz, -90, y=0.5, label="Purge console")
    # Columns break up the long lines across the atrium.
    for x in (-30, 30):
        for z in (-130, -102, -74):
            column(sid, x, z, 4.4)
    for x in (-30, 30):
        for z in (-130, -102, -74):
            for (dx, dz) in ((0, 2.9), (0, -2.9)):
                up = obox("Fixture", lights_folder(sid), x + dx, 0.15, z + dz, 0.9, 0.3, 0.6, mat="Neon", color=(255, 214, 160), nc=True, nq=True, ns=True)
                up["light"] = light("spot", (255, 205, 150), 34, 1.6, face="Top", angle=40)
            obox("UplightHousing", props_f(sid), x, 0.12, z + 2.9, 1.1, 0.24, 0.8, mat="Metal", color=(30, 30, 32), nc=True, nq=True, ns=True)
            obox("UplightHousing", props_f(sid), x, 0.12, z - 2.9, 1.1, 0.24, 0.8, mat="Metal", color=(30, 30, 32), nc=True, nq=True, ns=True)
    # Speed gates across the way in, with glass wings.
    for x in (-10, -6, -2, 2, 6, 10):
        piece("Turnstile", props_f(sid), x, 0, -59, 0)
    for sx in (-1, 1):
        box("GateGlass", props_f(sid), sx * 10.5 if sx > 0 else -18, sx * 18 if sx > 0 else -10.5, 0, 3.6, -59.1, -58.9, mat="Glass", color=(130, 160, 170), t=0.6, ns=True)
    # Lounges either side, by the windows.
    lounge(sid, -41.5, -137, 90, "Sofa", "Armchair", 1)
    lounge(sid, 41.5, -137, -90, "SofaFabric", "ArmchairFabric", 2)
    lounge(sid, -41.5, -104, 90, "SofaFabric", "Armchair", 3)
    for x in (-20, -6, 8, 22):
        try_floor(sid, "Bench", x, -140.5, 180)
    for x in (-50, -36, 36, 50):
        try_floor(sid, "PlanterTall" if hash01("pl", x) < 0.5 else "PlanterDead", x, -143, 0)
    for (x, z) in ((-50, -58), (50, -58), (-24, -70), (24, -70), (0, -144)):
        try_floor(sid, "PlanterDead" if hash01("pd", x, z) < 0.6 else "PlanterTall", x, z, 0)
    for x, z in ((-18, -67), (18, -67)):
        try_floor(sid, "DisplayCase", x, z, 180)
    try_floor(sid, "WaterCooler", 34, -55.5, 0)
    try_floor(sid, "CoatRack", -38, -56.5, 0)
    clutter_floor(sid, -36, -60, ("Puddle",))
    try_floor(sid, "WetFloorSign", -32, -62, 30)
    clutter_floor(sid, 14, -96, ("PaperScatter",))
    clutter_floor(sid, -26, -114, ("PaperScatter",))
    try_floor(sid, "CardboardBox", 44, -64, 20)
    try_floor(sid, "BoxOpen", 45, -68.5, -10)
    try_floor(sid, "TrashBinTipped", 20, -88, 140)
    try_floor(sid, "SecurityPodium", -24, -62, 180)
    try_floor(sid, "Stretcher", 30, -90, 30)
    piece("DroppedFlashlight", props_f(sid), 26, 0, -84, 205, flicker="dying")
    on_wall(sid, "W", -108, "ClawMarks", 0, check=False)
    on_wall(sid, "E", -70, "Scorch", 0, check=False)
    # The wall of glass faces the city; the Axiom name on the walls; screens and signs.
    for side, u in (("W", -102), ("E", -102)):
        on_wall(sid, side, u, "AxiomLogo", 22, check=False)
    on_wall(sid, "S", 34, "Wayfinding", 0, text="<  OFFICES        SERVER FARMS  >")
    on_wall(sid, "S", -34, "Wayfinding", 0, text="<  STAIRS · SERVICE")
    on_wall(sid, "W", -62, "RoomSign", 0, text="RECEPTION")
    for side, u in (("W", -140), ("E", -66)):
        on_wall(sid, side, u, "Sign_Lockdown", 8.0)
    on_wall(sid, "E", -134, "WallMonitor_Status", 2.0)
    on_wall(sid, "W", -88, "PosterRemember", 0)
    on_wall(sid, "E", -110, "PosterVault", 0)
    on_wall(sid, "W", -91, "NoteCameras", 0)
    on_wall(sid, "S", 26, "PosterAllHands", 0)
    # Lights: long pendants over the floor (most dead), downlights round the edge, lamps in the lounges.
    i = 0
    for x in (-20, 0, 20):
        for z in (-140, -124, -80, -64):
            fixture(sid, "PendantLong", x, z, 0, state=light_state(sid, i, 0.45, 0.2),
                    light_=light("surface", (255, 210, 160), 36, 1.0, face="Bottom", angle=100))
            i += 1
    for side in ("W", "E"):
        for z in (-140, -116, -80):
            on_wall(sid, side, z, "Sconce", 0, folder=lights_folder(sid), check=False, **({"flicker": "flicker"} if hash01("sc", side, z) < 0.3 else {}))
    for (x, z, st) in ((-50, -110, "on"), (38, -110, "flicker"), (-38, -72, "on")):
        try_floor(sid, "FloorLamp", x, z, 0, folder=lights_folder(sid), **({"flicker": st} if st != "on" else {}))
    for sx in (-1, 1):
        for z in (-130, -74):
            piece("Floodlight", "Facility/Floodlights", sx * 27.6, 22.0, z + (6 if z < -100 else -6), 0, id="Floodlight", unpack="part",
                  look=[0, 2, cz])
    # Gameplay: docks, cameras, a charging station, a trap and the light panel.
    core.camera("CORE_NE", sid, "E", -146, (-22, 2, -66), "Reception north-east", head=24, pan=70, tilt=40)
    core.camera("CORE_SW", sid, "W", -60, (12, 2, -110), "Reception south-west", head=24, pan=70, tilt=40)
    conduit_trap("TRAP_CORE", sid, "E", -88)
    light_panel(sid, "S", 20)


def reception_desk(sid, cx, cz):
    """A round reception desk about the Uplink: wood front, stone top, a lit strip under the lip, a gap on
    the window side for the staff. Monitors, phones and papers on the inner work surface."""
    folder = props_f(sid)
    R, depth, n = 9.0, 2.0, 22
    gap = math.radians(70)
    a0 = math.pi + gap / 2  # angles measured from +z (south) toward +x
    span = 2 * math.pi - gap
    claim(sid, (cx - R - 0.6, cx + R + 0.6, cz - R - 0.6, cz + R + 0.6), "reception desk")
    for i in range(n):
        a = a0 + span * (i + 0.5) / n
        chord = 2 * R * math.sin(span / n / 2) + 0.12
        x, z = cx + math.sin(a) * R, cz + math.cos(a) * R
        yaw = math.degrees(a)  # the segment's -Z faces outward... front faces away from the centre
        obox("DeskFront", folder, x, 0.5 + 1.8, z, chord, 3.6, depth, yaw=yaw, mat="Wood", color=C["woodDark"], var="AxiomWood", col=True)
        tx, tz = cx + math.sin(a) * (R + 0.15), cz + math.cos(a) * (R + 0.15)
        obox("DeskTop", folder, tx, 0.5 + 3.7, tz, chord + 0.25, 0.2, depth + 0.6, yaw=yaw, mat="Marble", color=(150, 146, 136), var="AxiomTerrazzo", refl=0.05)
        lx, lz = cx + math.sin(a) * (R + 1.2), cz + math.cos(a) * (R + 1.2)
        led = obox("Fixture", lights_folder(sid), lx, 0.5 + 3.5, lz, chord, 0.08, 0.12, yaw=yaw, mat="Neon", color=(150, 210, 240), nc=True, nq=True, ns=True)
        if i % 5 == 2:
            led["light"] = light("point", (170, 210, 235), 13, 0.7)
        ix, iz = cx + math.sin(a) * (R - 1.6), cz + math.cos(a) * (R - 1.6)
        obox("WorkTop", folder, ix, 0.5 + 2.75, iz, chord * 0.82, 0.12, 1.4, yaw=yaw, mat="Wood", color=(110, 84, 60), var="AxiomWood")
    sx, sz = cx, cz + R + 1.06
    plate = obox("Lettering", folder, sx, 0.5 + 2.2, sz, 7.0, 1.2, 0.05, yaw=0, mat="SmoothPlastic", color=(30, 30, 30), t=1, nc=True, nq=True)
    plate["gui"] = gui("AXIOM DATA VAULT", "Back", "Zekton", (190, 196, 200), ppu=50, light=1)
    # Inside: three workstations facing out, chairs, phones, the visitor book on the counter.
    for k, (ang, feed) in enumerate(((0.0, "Camera"), (-0.9, "Log"), (0.9, "Status"))):
        a = ang
        px, pz = cx + math.sin(a) * (R - 1.7), cz + math.cos(a) * (R - 1.7)
        yaw = math.degrees(a)  # the screen faces in, toward the receptionist
        piece(f"Monitor_{feed}", folder, px, 0.5 + 2.81, pz, yaw, **({"feed": "Camera", "cameraId": "INSERTION"} if feed == "Camera" else {}))
        kx, kz = cx + math.sin(a) * (R - 2.3), cz + math.cos(a) * (R - 2.3)
        piece("Keyboard", folder, kx, 0.5 + 2.81, kz, yaw)
        chx, chz = cx + math.sin(a) * (R - 4.2), cz + math.cos(a) * (R - 4.2)
        piece("OfficeChair", folder, chx, 0.5, chz, yaw + 180 + 25 * (k - 1))
    bx, bz = cx + math.sin(0.35) * (R + 0.2), cz + math.cos(0.35) * (R + 0.2)
    book = obox("VisitorBook", folder, bx, 0.5 + 3.84, bz, 1.4, 0.08, 1.0, yaw=20, mat="SmoothPlastic", color=(200, 196, 184), nc=True, nq=True)
    obox("Pen", folder, bx + 0.6, 0.5 + 3.86, bz - 0.2, 0.05, 0.05, 0.7, yaw=-30, mat="SmoothPlastic", color=(20, 20, 20), nc=True, nq=True, ns=True)
    piece("Mug", folder, cx + math.sin(-0.5) * (R - 1.4), 0.5 + 2.81, cz + math.cos(-0.5) * (R - 1.4), 30)
    piece("PaperTray", folder, cx + math.sin(1.4) * (R - 1.5), 0.5 + 2.81, cz + math.cos(1.4) * (R - 1.5), 80)


def lounge(sid, x, z, yaw, sofa, chair, seed):
    """A seating group on a rug: a sofa, two armchairs facing it across a coffee table, a side table."""
    s = SPACES[sid]
    piece("Rug", props_f(sid), x, s.y0, z, yaw)
    sx, sz = to_world(x, z, yaw, 0, 4.2)
    floor_piece(sid, sofa, sx, sz, yaw, label="sofa")
    floor_piece(sid, "CoffeeTable", x, z, yaw, label="coffee table")
    for k, lx in enumerate((-2.4, 2.4)):
        px, pz = to_world(x, z, yaw, lx, -4.4)
        floor_piece(sid, chair, px, pz, yaw + 180 + (12 if k else -12), label="armchair")
    tx, tz = to_world(x, z, yaw, 5.6, 4.0)
    try_floor(sid, "SideTable", tx, tz, 0)
    mx, mz = to_world(x, z, yaw, 0.8, 0.2)
    piece("MagazineFan" if "MagazineFan" in core.PREFABS else "ClutterB", props_f(sid), mx, s.y0 + 1.5, mz, yaw + 15)


# ------------------------------------------------------------------------------------------------------
# The lift lobby, the car, the deck and the stairs


def dress_insertion():
    sid = "INS"
    s = SPACES[sid]
    keepout(sid, -8, 8, -24, -14)  # out of the car
    on_wall(sid, "S", -14, "ElevatorDoors", 0, check=False)
    on_wall(sid, "S", 14, "ElevatorDoorsAjar", 0, check=False)
    for u in (-8.6, 8.6):
        on_wall(sid, "S", u, "CallButtons", 0, check=False)
    for z in (-44, -24):
        on_wall(sid, "W", z, "Sconce", 0, folder=lights_folder(sid))
        on_wall(sid, "E", z, "Sconce", 0, check=False, folder=lights_folder(sid))
    against(sid, "W", -34, "Bench", gap=0.6)
    try_floor(sid, "PlanterTall", 16.8, -46.5, 0)
    try_floor(sid, "TrashBin", 17.6, -20.5, 0)
    try_floor(sid, "WetFloorSign", -4, -36, -20)
    clutter_floor(sid, -2, -40, ("Puddle",))
    box("Mat", props_f(sid), -6, 6, 0, 0.04, -22, -15, mat="Rubber", color=(26, 26, 28), var="AxiomRubber", nc=True, nq=True, ns=True)
    on_wall(sid, "E", -36, "Wayfinding", 0, text="LEVEL 61  ·  AXIOM DATA VAULT", check=False)
    on_wall(sid, "W", -30, "NoteElevator", 0, check=False)
    i = 0
    for x in (-10, 10):
        for z in (-44, -32, -20):
            fixture(sid, "Downlight", x, z, state=("flicker" if i == 2 else light_state(sid, i, 0.2, 0.0)))
            i += 1
    core.camera("INSERTION", sid, "W", -47, (8, 2, -18), "Elevator lobby", head=12.0)
    core.station("STATION_INSERTION", sid, "E", -29)
    light_panel(sid, "W", -40)
    # The service car: the squad's ride up. Rails, a control panel, a stuttering light.
    car = "INS_CAR"
    c = SPACES[car]
    for side in ("W", "E", "S"):
        lo, hi = core.side_range(c, side)
        if side in "WE":
            a, b = wall_xz(c, side, -6, 0.45)
            box("Handrail", props_f(car), *( (a - 0.1, a + 0.1) if side in "WE" else (lo + 1, hi - 1)), 3.3, 3.5, -11, -1, mat="Metal", color=(190, 190, 190), nc=True, ns=True)
    box("Handrail", props_f(car), -5, 5, 3.3, 3.5, -0.55, -0.35, mat="Metal", color=(190, 190, 190), nc=True, ns=True)
    panel = box("CarPanel", props_f(car), 5.75, 5.9, 3.0, 7.0, -10.6, -9.2, mat="Metal", color=(170, 172, 176), var="AxiomSteel")
    for k in range(6):
        box("CarButton", props_f(car), 5.62, 5.75, 3.6 + 0.5 * k, 3.9 + 0.5 * k, -10.1, -9.8, mat="Neon", color=(255, 220, 170) if k == 5 else (60, 60, 60), nc=True, nq=True, ns=True)
    fixture(car, "Downlight", -2.5, -6, state="flicker")
    fixture(car, "Downlight", 2.5, -6, state="dead")
    GAME["spawn"] = {"c": [0, 0.3, -6.5], "s": [8, 8], "yaw": 0}


def dress_deck():
    sid = "OD_DECK"
    s = SPACES[sid]
    core.terminal("TERM_OD", sid, "S", 0, "Observation Deck terminal")
    core.dock("DOCK_OD_W", sid, "W", -40, "Observation Deck dock west")
    core.dock("DOCK_OD_E", sid, "E", -40, "Observation Deck dock east")
    # Lounge chairs facing the glass, a long desk under it with the atrium cameras.
    for k, x in enumerate((-9, -3, 3, 9)):
        floor_piece(sid, "Armchair" if k % 2 else "ArmchairFabric", x, -42.5, 10 * (k - 1.5), label="deck chair")
    for x in (-6, 6):
        try_floor(sid, "SideTable", x, -38.5, 0)
    floor_piece(sid, "CoffeeTable", 0, -30, 0, label="table")
    piece("ClutterB", props_f(sid), 0, s.y0 + 1.5, -30, 20)
    try_floor(sid, "PlanterTall", -17, -17, 0)
    try_floor(sid, "PlanterDead", 17, -48, 0)
    try_floor(sid, "TrashBin", 12, -16, 0)
    on_wall(sid, "S", -12, "WallMonitor_Camera", 1.0, feed="Camera", cameraId="CORE_NE", check=False)
    on_wall(sid, "S", 12, "WallMonitor_Camera", 1.0, feed="Camera", cameraId="CORE_SW", check=False)
    on_wall(sid, "W", -28, "PosterChimera", 0, check=False)
    on_wall(sid, "E", -28, "NotePrinted", 0, check=False)
    troffer_grid(sid, 12, 10, dead=0.35, flicker=0.2, rect=(s.x0, s.x1, -44, -14))
    for x in (-12, 0, 12):
        fixture(sid, "Downlight", x, -48, state="on" if x else "flicker")
    core.camera("OD_DECK", sid, "S", -17.5, (8, 26, -46), "Observation Deck", head=10.8)
    light_panel(sid, "S", -6)
    emergency_packs(sid, (("S", 7), ("W", -30)))


def dress_stair(sid, east):
    s = SPACES[sid]
    inner, outer, zb, zm = fire_stair(sid, east)
    folder = props_f(sid)
    # Under the mid landing: the sealed stair down, a mop bucket and junk.
    try_floor(sid, "MopBucket", (outer[0] + outer[1]) / 2, s.z0 + 3, 0)
    try_floor(sid, "BoxStack", (outer[0] + outer[1]) / 2 + (1 if east else -1), s.z0 + 7.5, 10)
    on_wall(sid, "E" if not east else "W", -32, "NoteStairs", 0, check=False)
    fixture(sid, "JarLight", (s.x0 + s.x1) / 2, (s.z0 + zm) / 2, y=11, state="flicker" if east else "on")
    fixture(sid, "JarLight", (s.x0 + s.x1) / 2, zb + 4, y=s.y0 + 37.5, state="on")
    fixture(sid, "JarLight", (s.x0 + s.x1) / 2, -18, y=s.y0 + 22.9, state="dying" if east else "on")
    cam_side = "W" if not east else "E"
    core.camera(sid, sid, cam_side, -46, ((s.x0 + s.x1) / 2, 6, zb), "East stairwell" if east else "West stairwell", head=10.2, pan=70)
    light_panel(sid, "S", (inner[0] + inner[1]) / 2)
    emergency_packs(sid, (("N", (s.x0 + s.x1) / 2),))


# ------------------------------------------------------------------------------------------------------
# Cooling Plant


def tank(sid, x, z, d=9.0, h=15.0):
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - d / 2 - 0.8, x + d / 2 + 0.8, z - d / 2 - 0.8, z + d / 2 + 1.6), "tank")
    obox("TankPlinth", props_f(sid), x, y + 0.3, z, d + 1.4, 0.6, d + 1.4, mat="Concrete", color=(70, 70, 68), var="AxiomConcrete")
    obox("Tank", props_f(sid), x, y + 0.6 + h / 2, z, h, d, d, r=[0, 0, 90], mat="Metal", color=(64, 74, 82), var="AxiomSteel", shape="cyl")
    obox("TankBand", props_f(sid), x, y + 0.6 + h * 0.3, z, 0.8, d + 0.08, d + 0.08, r=[0, 0, 90], mat="SmoothPlastic", color="hazard", var="AxiomHazard", shape="cyl")
    obox("TankCap", props_f(sid), x, y + 0.6 + h + 0.5, z, 1.0, d - 1.0, d - 1.0, r=[0, 0, 90], color=(56, 64, 72), shape="cyl")
    for dx in (d * 0.25, -d * 0.25):
        obox("TankPipe", props_f(sid), x + dx, (y + 0.6 + h + 1 + s.top) / 2, z, s.top - (y + h + 1.6), 1.2, 1.2, r=[0, 0, 90],
             mat="CorrodedMetal", color=(62, 58, 54), var="AxiomWorn", shape="cyl", nc=True)
    lz = z + d / 2 + 0.35
    for sx in (-0.55, 0.55):
        obox("LadderRail", props_f(sid), x + sx, y + 0.6 + h / 2, lz, 0.14, h, 0.14, color=(150, 150, 146), nc=True)
    for k in range(int(h // 1.2)):
        obox("LadderRung", props_f(sid), x, y + 1.2 + k * 1.2, lz, 1.1, 0.1, 0.1, color=(150, 150, 146), nc=True, ns=True)
    obox("LevelGauge", props_f(sid), x - 2.2, y + 0.6 + h * 0.5, z + d / 2 + 0.06, 0.5, h * 0.6, 0.12, mat="Neon", color=(80, 190, 230), nc=True, ns=True, nq=True)


def pump(sid, x, z, yaw=0.0):
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - 3.4, x + 3.4, z - 2.4, z + 2.4) if yaw % 180 == 0 else (x - 2.4, x + 2.4, z - 3.4, z + 3.4), "pump")
    obox("PumpSkid", props_f(sid), x, y + 0.3, z, 6.6, 0.6, 4.4, yaw=yaw, mat="DiamondPlate", color=(52, 54, 58), var="AxiomTread")
    mx, mz = to_world(x, z, yaw, -1.4, 0)
    obox("PumpMotor", props_f(sid), mx, y + 2.1, mz, 3.2, 2.6, 2.6, r=[0, yaw, 0], color=(40, 70, 92), shape="cyl")
    vx, vz = to_world(x, z, yaw, 1.6, 0)
    obox("PumpVolute", props_f(sid), vx, y + 2.0, vz, 2.0, 3.0, 3.0, r=[0, yaw + 90, 0], mat="CorrodedMetal", color=(62, 58, 54), var="AxiomWorn", shape="cyl")
    obox("PumpRiser", props_f(sid), vx, (y + 3.4 + s.top) / 2, vz, s.top - y - 3.4, 1.4, 1.4, r=[0, 0, 90], mat="CorrodedMetal", color=(62, 58, 54), var="AxiomWorn", shape="cyl")
    obox("PumpGuard", props_f(sid), mx, y + 3.55, mz, 2.6, 0.3, 2.0, yaw=yaw, color="hazard", var="AxiomHazard")


def chiller(sid, x, z, length=26):
    """A water-cooled chiller: a long shell on legs, a compressor, a control box and pipes to the roof."""
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - length / 2 - 1, x + length / 2 + 1, z - 4.5, z + 4.5), "chiller")
    for k in (-0.35, 0.35):
        obox("Leg", props_f(sid), x + k * length, y + 1.0, z, 1.2, 2.0, 7.0, color=(50, 54, 58))
    obox("Shell", props_f(sid), x, y + 4.2, z - 1.4, length, 3.6, 3.6, mat="Metal", color=(70, 90, 96), var="AxiomSteel", shape="cyl")
    obox("Shell", props_f(sid), x, y + 4.2, z + 1.8, length, 3.2, 3.2, mat="Metal", color=(64, 84, 90), var="AxiomSteel", shape="cyl")
    obox("Compressor", props_f(sid), x - length * 0.2, y + 7.6, z, 6.0, 3.0, 4.0, mat="Metal", color=(60, 64, 66), var="AxiomSteel")
    obox("Control", props_f(sid), x + length / 2 + 0.2, y + 4.0, z - 2.6, 0.6, 4.0, 2.4, mat="Metal", color=(40, 42, 44))
    obox("ControlScreen", props_f(sid), x + length / 2 + 0.52, y + 4.6, z - 2.6, 0.04, 1.0, 1.4, mat="Neon", color=(80, 170, 120), nc=True, nq=True, ns=True)
    for dz in (-1.4, 1.8):
        obox("Riser", props_f(sid), x + length * 0.42, (y + 6 + s.top) / 2, z + dz, s.top - y - 6, 1.6, 1.6, r=[0, 0, 90], mat="Metal", color=(60, 80, 110), shape="cyl", nc=True)


# ------------------------------------------------------------------------------------------------------
# Maintenance


def boiler(sid, x, z, length=18.0, d=8.0):
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - length / 2 - 3.5, x + length / 2 + 0.5, z - d / 2 - 0.6, z + d / 2 + 0.6), "boiler")
    for k in (-0.3, 0.3):
        obox("Saddle", props_f(sid), x + k * length, y + 1.5, z, 1.2, 3.0, d * 0.8, color=(40, 40, 42))
    obox("BoilerDrum", props_f(sid), x, y + 2.4 + d / 2, z, length, d, d, mat="CorrodedMetal", color=(70, 62, 56), var="AxiomWorn", shape="cyl")
    for k in (-0.45, 0, 0.45):
        obox("DrumBand", props_f(sid), x + k * length, y + 2.4 + d / 2, z, 0.4, d + 0.12, d + 0.12, color=(40, 40, 42), shape="cyl")
    obox("Firebox", props_f(sid), x - length / 2 - 1.6, y + 2.2 + d / 2, z, 3.2, d + 1.0, d + 0.4, color=(36, 34, 33), var="AxiomSteel")
    obox("Burner", props_f(sid), x - length / 2 - 3.4, y + 3.4, z, 1.2, 2.2, 2.2, color=(70, 74, 78), shape="cyl")
    obox("BurnerGlow", props_f(sid), x - length / 2 - 3.25, y + 3.4, z, 0.06, 1.4, 1.4, mat="Neon", color=(255, 130, 50), shape="cyl", nc=True, ns=True, nq=True)
    obox("Flue", props_f(sid), x + length * 0.3, (y + 2.4 + d + s.top) / 2, z, s.top - (y + 2.4 + d), 2.0, 2.0, r=[0, 0, 90], mat="CorrodedMetal", color=(62, 58, 54), var="AxiomWorn", shape="cyl", nc=True)


# ------------------------------------------------------------------------------------------------------
# Fabrication Bays


def chassis(sid, x, z, yaw, y=None, height=1.0, folder=None):
    """A half-printed shell chassis: the R6 frame printed from the feet up to `height` (0-1)."""
    s = SPACES[sid]
    y = s.y0 if y is None else y
    f = folder or props_f(sid)
    dark, plate = (24, 26, 30), (46, 50, 58)

    def part(name, lx, ly, lz, sx, sy, sz, col=dark, mat="Metal"):
        if ly - sy / 2 > 5.4 * height:
            return
        wx, wz = to_world(x, z, yaw, lx, lz)
        obox(name, f, wx, y + ly, wz, sx, sy, sz, yaw=yaw, mat=mat, color=col, var="AxiomSteel", nc=True)
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
    top = 5.4 * height
    wx, wz = to_world(x, z, yaw, 0, 0)
    obox("PrintSeam", f, wx, y + top, wz, 2.0, 0.06, 0.8, yaw=yaw, mat="Neon", color=(255, 150, 50), nc=True, ns=True, nq=True)


def print_gantry(sid, x, z, yaw=0.0):
    s = SPACES[sid]
    y = s.y0
    claim(sid, (x - 6.2, x + 6.2, z - 8.2, z + 8.2), "print bay")
    obox("PrintBed", props_f(sid), x, y + 0.35, z, 10.0, 0.7, 14.0, yaw=yaw, mat="DiamondPlate", color=(52, 54, 58), var="AxiomTread")
    obox("BedEdge", props_f(sid), x, y + 0.3, z, 10.6, 0.6, 14.6, yaw=yaw, color="hazard", var="AxiomHazard")
    for sx in (-1, 1):
        for sz in (-1, 1):
            px, pz = to_world(x, z, yaw, sx * 5.6, sz * 7.6)
            obox("GantryPost", props_f(sid), px, y + 7.5, pz, 0.8, 15.0, 0.8, yaw=yaw, color=(40, 42, 46), var="AxiomSteel")
        rx, rz = to_world(x, z, yaw, sx * 5.6, 0)
        obox("GantryRail", props_f(sid), rx, y + 15.3, rz, 0.9, 0.8, 16.0, yaw=yaw, color=(70, 74, 80), var="AxiomSteel")
    bx, bz = to_world(x, z, yaw, 0, -1.5)
    obox("GantryBridge", props_f(sid), bx, y + 14.6, bz, 12.0, 0.9, 1.2, yaw=yaw, color=(52, 56, 62), var="AxiomSteel")
    obox("PrintHead", props_f(sid), bx, y + 13.2, bz, 1.6, 1.8, 1.4, yaw=yaw, color=(30, 32, 36), var="AxiomSteel")
    obox("PrintNozzle", props_f(sid), bx, y + 11.9, bz, 0.4, 0.8, 0.4, yaw=yaw, mat="Neon", color=(255, 150, 50), nc=True, ns=True, nq=True)
    chassis(sid, x, z, yaw + 180, y=y + 0.7, height=0.55 + 0.4 * hash01(sid, x, z))


# ------------------------------------------------------------------------------------------------------


def dress_all():
    from . import rooms

    core.door_keepouts()
    place_openings()
    exterior_windows()
    glass_walls()
    dress_core()
    dress_insertion()
    dress_deck()
    dress_stair("OD_STAIR_W", False)
    dress_stair("OD_STAIR_E", True)
    rooms.dress_rooms()
    finishes()
