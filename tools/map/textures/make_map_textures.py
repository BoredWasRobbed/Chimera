"""PS1-style textures for Axiom Tower, the realistic set the map is finished with.

Same style and rules as the kit's textures (tools/mapkit/textures/make_textures.py, whose helpers this
imports): 256x256 pixel art with ordered dithering and a few tones, scaled up 4x with hard edges so the
pixels stay crisp, tiling seamlessly, with detail spread evenly so repeats don't catch the eye. They're grey,
so a part's colour sets its tone.

  surfaces (MaterialVariants)  plaster, carpet tile, acoustic ceiling tile, terrazzo, wood veneer, painted
                               block, ceramic tile, concrete, vinyl tile, fabric
  city (Textures, with alpha)  four night facades: lit windows are transparent, so the neon part behind
                               them glows through; dark windows and walls are opaque
  glass (Texture, with alpha)  rain on a window: drops and runs, mostly transparent

Run:  python tools/map/textures/make_map_textures.py [preview.png]
Writes map_*.png next to this script; with an argument, also a preview sheet.
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "mapkit", "textures"))
import make_textures as kit  # noqa: E402  (the kit's helpers)

N, SCALE = kit.N, kit.SCALE
YY, XX = kit.YY, kit.XX
fractal, dither, posterize, mask_of = kit.fractal, kit.dither, kit.posterize, kit.mask_of
scratches, blotches, specks = kit.scratches, kit.blotches, kit.specks


def plaster(seed=101):
    """Painted drywall: a faint roller stipple, scuffs at random, small grime patches and dents."""
    rng = np.random.default_rng(seed)
    img = 0.84 + 0.07 * dither(fractal(rng, (16, 32, 64), (0.3, 0.4, 0.3)), 4)
    img += 0.035 * (dither(rng.random((N, N)), 3) - 0.5)
    img -= 0.03 * mask_of(rng, (16, 32, 64), (0.4, 0.35, 0.25), 0.6, 0.25, 3)
    scratches(img, rng, 45, 0.0, 0.06, (4, 13), [(1, 0), (2, 1), (2, -1), (3, 1)])
    blotches(img, rng, 26, (1.5, 3.5), -0.05)
    specks(img, rng, 260, -0.07)
    return posterize(img)


def carpet(seed=103):
    """Commercial carpet tile: loop-pile speckle, a fine rib laid quarter-turned tile to tile, seams,
    trodden patches and small stains. A tile is 64 px (2 studs at 8 studs a texture)."""
    rng = np.random.default_rng(seed)
    pile = 0.6 * rng.random((N, N)) + 0.4 * fractal(rng, (32, 64), (0.5, 0.5))
    img = 0.66 + 0.2 * dither(pile, 5)
    tile = 64
    turned = ((XX // tile + YY // tile) % 2) == 0
    rib = np.where(turned, YY % 3 == 0, XX % 3 == 0)
    img -= 0.09 * rib
    img -= 0.09 * ((XX % tile == 0) | (YY % tile == 0))
    img -= 0.05 * mask_of(rng, (16, 32, 64), (0.4, 0.35, 0.25), 0.55, 0.3, 3)
    blotches(img, rng, 12, (2, 4), -0.1)
    specks(img, rng, 500, 0.08)
    return posterize(img)


def ceiling(seed=107):
    """Acoustic lay-in ceiling tiles (2 x 4 studs at 8 studs a texture) in a light T-bar grid: fissured
    mineral fibre, each tile a slightly different age, a few sagging corners and dust."""
    rng = np.random.default_rng(seed)
    img = 0.84 + 0.04 * dither(fractal(rng, (16, 32, 64), (0.4, 0.35, 0.25)), 3)
    tw, th = 64, 128
    tiles = rng.uniform(-0.05, 0.03, size=(N // th, N // tw))
    img += tiles[YY // th, XX // tw]
    for _ in range(1500):
        x, y = rng.integers(N, size=2)
        dx, dy = [(1, 0), (0, 1), (1, 1), (1, -1)][rng.integers(4)]
        for i in range(rng.integers(1, 4)):
            img[(y + i * dy) % N, (x + i * dx) % N] -= 0.13
    specks(img, rng, 600, -0.06)
    blotches(img, rng, 14, (3, 6), -0.05)
    grid_x = (XX % tw) < 3
    grid_y = (YY % th) < 3
    img = np.where(grid_x | grid_y, 0.97, img)
    img = np.where(((XX % tw) == 3) | ((YY % th) == 3), img - 0.12, img)
    return posterize(img)


def terrazzo(seed=109):
    """Polished terrazzo in 4-stud tiles (128 px): marble chips of a few tones in a smooth matrix, with a
    thin grout line."""
    rng = np.random.default_rng(seed)
    img = 0.7 + 0.06 * dither(fractal(rng, (8, 16, 32), (0.4, 0.35, 0.25)), 3)
    for count, (lo, hi), size in ((2600, (-0.2, -0.1), 1), (1700, (0.08, 0.18), 1), (500, (-0.16, 0.16), 2), (120, (0.1, 0.2), 3)):
        for _ in range(count):
            x, y = rng.integers(N, size=2)
            v = rng.uniform(lo, hi)
            for dy in range(size):
                for dx in range(size):
                    if size < 3 or (dx, dy) != (2, 2):
                        img[(y + dy) % N, (x + dx) % N] += v
    tile = 128
    img = np.where(((XX % tile) == 0) | ((YY % tile) == 0), img * 0.72, img)
    img = np.where(((XX % tile) == 1) | ((YY % tile) == 1), img * 0.9, img)
    scratches(img, rng, 30, 0.06, 0.0, (5, 16))
    return posterize(img)


def wood(seed=113):
    """Wood veneer: vertical grain, planks of slightly different tone 64 px wide, a few small knots."""
    rng = np.random.default_rng(seed)
    warp = fractal(rng, (4, 8, 16), (0.5, 0.3, 0.2))
    plank = 64
    tone = rng.uniform(-0.06, 0.06, size=N // plank)[XX // plank]
    phase = rng.uniform(0, 6.28, size=N // plank)[XX // plank]
    grain = 0.5 + 0.5 * np.sin((XX % plank) * 0.9 + warp * 9 + phase)
    img = 0.66 + tone + 0.12 * dither(grain * 0.7 + 0.3 * fractal(rng, (32, 64), (0.5, 0.5)), 4)
    img = np.where((XX % plank) == 0, img - 0.12, img)
    for _ in range(5):
        cx, cy = rng.integers(N, size=2)
        for dy in range(-4, 5):
            for dx in range(-2, 3):
                d = (dx * dx / 4 + dy * dy / 16) ** 0.5
                if d < 1:
                    img[(cy + dy) % N, (cx + dx) % N] -= 0.15 * (1 - d)
    specks(img, rng, 200, -0.05)
    return posterize(img)


def block(seed=127):
    """Painted concrete block in running bond: 2 x 1 stud blocks (64 x 32 px), recessed mortar, pitted
    faces, paint runs and grime low on the wall."""
    rng = np.random.default_rng(seed)
    img = 0.8 + 0.07 * dither(fractal(rng, (16, 32, 64), (0.35, 0.35, 0.3)), 4)
    bw, bh = 64, 32
    row = YY // bh
    xs = (XX + (row % 2) * (bw // 2)) % bw
    tone = rng.uniform(-0.04, 0.04, size=(N // bh, N // bw + 1))
    img += tone[row, ((XX + (row % 2) * (bw // 2)) // bw) % (N // bw)]
    mortar = (xs < 2) | ((YY % bh) < 2)
    img = np.where(mortar, img - 0.16, img)
    img = np.where(((xs == 2) | ((YY % bh) == 2)) & ~mortar, img - 0.06, img)
    specks(img, rng, 1400, -0.1)
    specks(img, rng, 200, 0.06)
    scratches(img, rng, 30, 0.0, 0.06, (4, 10), [(0, 1)])
    return posterize(img)


def tile(seed=131):
    """Ceramic tile, 1 stud squares (64 px at 4 studs a texture): glaze varying tile to tile, grout lines,
    hairline crazing and dirt in the grout."""
    rng = np.random.default_rng(seed)
    t = 64
    tone = rng.uniform(-0.04, 0.04, size=(N // t, N // t))
    img = 0.88 + tone[YY // t, XX // t] + 0.03 * dither(fractal(rng, (16, 32), (0.5, 0.5)), 3)
    grout = ((XX % t) < 3) | ((YY % t) < 3)
    img = np.where(grout, 0.56 + 0.06 * dither(rng.random((N, N)), 3), img)
    img = np.where((((XX % t) == 3) | ((YY % t) == 3)) & ~grout, img - 0.06, img)
    scratches(img, rng, 40, 0.0, 0.06, (3, 9))
    specks(img, rng, 160, -0.08)
    return posterize(img)


def concrete(seed=137):
    """Sealed concrete floor: cloudy trowel marks, hairline cracks, stains and pits."""
    rng = np.random.default_rng(seed)
    img = 0.7 + 0.14 * dither(fractal(rng, (4, 8, 16, 32), (0.3, 0.3, 0.25, 0.15)), 5)
    img += 0.04 * (dither(rng.random((N, N)), 3) - 0.5)
    for _ in range(5):
        x, y = rng.uniform(0, N, size=2)
        ang = rng.uniform(0, 6.28)
        for _ in range(rng.integers(20, 45)):
            ang += rng.normal(0, 0.18)
            x += np.cos(ang)
            y += np.sin(ang)
            img[int(y) % N, int(x) % N] -= 0.16
    blotches(img, rng, 18, (2, 6), -0.07)
    specks(img, rng, 700, -0.1)
    return posterize(img)


def vinyl(seed=139):
    """Vinyl composition tile, 2-stud squares in two tones laid as a checker, with chip speckle, seams and
    black heel scuffs."""
    rng = np.random.default_rng(seed)
    t = 64
    checker = ((XX // t + YY // t) % 2) == 0
    img = np.where(checker, 0.8, 0.74) + 0.04 * dither(fractal(rng, (16, 32), (0.5, 0.5)), 3)
    for count, v in ((1500, -0.14), (900, 0.08)):
        specks(img, rng, count, v)
    img = np.where(((XX % t) == 0) | ((YY % t) == 0), img - 0.1, img)
    scratches(img, rng, 70, 0.0, 0.0, (2, 6))
    for _ in range(60):
        x, y = rng.integers(N, size=2)
        dx, dy = [(1, 0), (2, 1), (1, 1), (2, -1)][rng.integers(4)]
        for i in range(rng.integers(3, 8)):
            img[(y + i * dy // 2) % N, (x + i * dx // 2) % N] -= 0.3
    blotches(img, rng, 16, (2, 4), -0.06)
    return posterize(img)


def fabric(seed=149):
    """Cubicle and upholstery fabric: a fine basket weave, heathered, with lint and a few pulls."""
    rng = np.random.default_rng(seed)
    weave = (((XX // 2) + (YY // 2)) % 2 == 0)
    img = 0.76 + 0.08 * weave + 0.1 * dither(rng.random((N, N)) * 0.5 + 0.5 * fractal(rng, (32, 64), (0.5, 0.5)), 4)
    img -= 0.025 * mask_of(rng, (32, 64), (0.6, 0.4), 0.6, 0.25, 3)
    specks(img, rng, 300, 0.08)
    scratches(img, rng, 20, 0.06, 0.0, (3, 8))
    return posterize(img)


# ------------------------------------------------------------------------------------------------------
# City facades (RGBA). A facade texture covers 32 window bays across and 16 floors up (16 px a floor); lit
# windows are transparent so the building's neon core glows through them.

DARK_GLASS = np.array([0.07, 0.09, 0.12])


def facade_base(rng, wall_tone, grain):
    wall = wall_tone + grain * dither(fractal(rng, (16, 32, 64), (0.4, 0.35, 0.25)), 3)
    return np.stack([wall * 1.0, wall * 0.98, wall * 0.96], axis=-1)


def lit_pattern(rng, floors, bays, busy):
    """Which windows are lit: whole floors left on, runs of offices, and scattered single windows."""
    lit = rng.random((floors, bays)) < busy * 0.5
    for f in range(floors):
        r = rng.random()
        if r < busy * 0.12:
            lit[f, :] = rng.random(bays) < 0.7  # a floor still working late
        elif r < busy * 0.6:
            a = rng.integers(bays)
            lit[f, a:a + rng.integers(2, 9)] = True
    return lit


def facade(seed, floor_px, win_h, bay_px, win_w, wall_tone, busy, blinds=0.3, spandrel_lines=False):
    rng = np.random.default_rng(seed)
    rgb = facade_base(rng, wall_tone, 0.05)
    alpha = np.ones((N, N))
    floors, bays = N // floor_px, N // bay_px
    lit = lit_pattern(rng, floors, bays, busy)
    dim = rng.random((floors, bays)) < blinds
    for f in range(floors):
        for b in range(bays):
            y0 = f * floor_px + (floor_px - win_h) // 2
            x0 = b * bay_px + (bay_px - win_w) // 2
            ys, xs = slice(y0, y0 + win_h), slice(x0, x0 + win_w)
            if lit[f, b]:
                # Transparent: the glow behind shows. Blinds or a far wall dim some.
                a = 0.45 if dim[f, b] else 0.0
                alpha[ys, xs] = a
                rgb[ys, xs] = [0.12, 0.1, 0.08]
                if dim[f, b]:
                    for yy in range(y0, y0 + win_h, 2):
                        alpha[yy, xs] = 0.75
            else:
                shade = DARK_GLASS * rng.uniform(0.7, 1.3)
                rgb[ys, xs] = shade
                rgb[y0, xs] = shade * 1.5  # sky caught on the top edge of the pane
    if spandrel_lines:
        for f in range(floors):
            rgb[f * floor_px, :] *= 0.7
    return rgb, alpha


def city_office(seed=211):
    """An office tower with ribbon windows: long glazed bands between concrete spandrels, mullions every bay."""
    rgb, alpha = facade(seed, 16, 10, 8, 7, 0.2, busy=0.32, spandrel_lines=True)
    return rgb, alpha


def city_flats(seed=223):
    """Apartments: punched windows in a brick-dark wall, warm and more of them lit."""
    rgb, alpha = facade(seed, 16, 8, 12, 6, 0.17, busy=0.45, blinds=0.45)
    return rgb, alpha


def city_glass(seed=227):
    """A glass curtain-wall tower: dark glass in a mullion grid, only a few lights on."""
    rng = np.random.default_rng(seed)
    rgb = np.zeros((N, N, 3)) + DARK_GLASS * 1.1
    rgb += 0.03 * dither(fractal(rng, (2, 4, 8), (0.5, 0.3, 0.2)), 3)[..., None]
    alpha = np.ones((N, N))
    lit = lit_pattern(rng, 16, 32, 0.16)
    for f in range(16):
        for b in range(32):
            if lit[f, b]:
                alpha[f * 16 + 1:f * 16 + 15, b * 8 + 1:b * 8 + 8] = 0.0
    rgb[(YY % 16) == 0] = 0.16
    rgb[(XX % 8) == 0] = 0.13
    return rgb, alpha


def city_stone(seed=229):
    """An older stone building: paired tall windows, a cornice band every four floors."""
    rgb, alpha = facade(seed, 16, 11, 16, 6, 0.24, busy=0.28, blinds=0.5)
    for f in range(0, 16, 4):
        rgb[f * 16:f * 16 + 3, :] *= 1.25
    return rgb, alpha


def rain(seed=233):
    """Rain on glass: beads of every size and a few runs, light on transparent."""
    rng = np.random.default_rng(seed)
    rgb = np.ones((N, N, 3)) * 0.85
    alpha = np.zeros((N, N))
    for _ in range(420):
        x, y = rng.integers(N, size=2)
        r = rng.choice([0, 0, 0, 1, 1, 2])
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if dx * dx + dy * dy <= r * r + 0.5:
                    alpha[(y + dy) % N, (x + dx) % N] = 0.35 if (dx, dy) != (-r if r else 0, -r if r else 0) else 0.6
        alpha[(y + r + 1) % N, x % N] = max(alpha[(y + r + 1) % N, x % N], 0.2)
    for _ in range(26):
        x, y = rng.integers(N, size=2)
        length = rng.integers(20, 90)
        for i in range(length):
            xx = (x + int(2 * np.sin(i * 0.15))) % N
            alpha[(y + i) % N, xx] = max(alpha[(y + i) % N, xx], 0.22)
        alpha[(y + length) % N, x % N] = 0.55
    return rgb, alpha


SURFACES = {
    "map_plaster": plaster,
    "map_carpet": carpet,
    "map_ceiling": ceiling,
    "map_terrazzo": terrazzo,
    "map_wood": wood,
    "map_block": block,
    "map_tile": tile,
    "map_concrete": concrete,
    "map_vinyl": vinyl,
    "map_fabric": fabric,
}
OVERLAYS = {
    "map_city_office": city_office,
    "map_city_flats": city_flats,
    "map_city_glass": city_glass,
    "map_city_stone": city_stone,
    "map_rain": rain,
}

# The colours each surface is mostly seen under, for the preview sheet.
PREVIEW_TINTS = {
    "map_plaster": (128, 124, 116), "map_carpet": (62, 66, 76), "map_ceiling": (150, 148, 140),
    "map_terrazzo": (120, 116, 108), "map_wood": (96, 66, 44), "map_block": (112, 112, 106),
    "map_tile": (150, 154, 150), "map_concrete": (96, 96, 94), "map_vinyl": (130, 126, 116),
    "map_fabric": (70, 76, 86),
}


def save_rgb(name, img):
    rgb = (np.clip(kit.to_rgb(img), 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(rgb, "RGB").resize((N * SCALE, N * SCALE), Image.NEAREST).save(os.path.join(HERE, name + ".png"), optimize=True)
    return rgb


def save_rgba(name, rgb, alpha):
    out = np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], axis=-1)
    data = (out * 255 + 0.5).astype(np.uint8)
    Image.fromarray(data, "RGBA").resize((N * SCALE, N * SCALE), Image.NEAREST).save(os.path.join(HERE, name + ".png"), optimize=True)
    return data


def main():
    made = {name: save_rgb(name, make()) for name, make in SURFACES.items()}
    over = {name: save_rgba(name, *make()) for name, make in OVERLAYS.items()}
    if len(sys.argv) > 1:
        rows = []
        width = 2 * (2 * N) + 6
        for name, rgb in made.items():
            big = np.tile(rgb, (2, 2, 1))
            tint = np.clip(big.astype(float) * np.array(PREVIEW_TINTS[name]) / 255 * 1.6, 0, 255).astype(np.uint8)
            rows.append(np.concatenate([big, np.full((2 * N, 6, 3), 40, np.uint8), tint], axis=1))
            rows.append(np.full((6, width, 3), 40, np.uint8))
        for name, data in over.items():
            # Over a warm glow on the left, over black on the right.
            big = np.tile(data, (2, 2, 1)).astype(float) / 255
            a = big[..., 3:4]
            glow = np.array([1.0, 0.85, 0.55])
            left = big[..., :3] * a + glow * (1 - a)
            right = big[..., :3] * a
            cell = np.concatenate([left, np.full((2 * N, 6, 3), 40 / 255), right], axis=1)
            rows.append((np.clip(cell, 0, 1) * 255).astype(np.uint8))
            rows.append(np.full((6, width, 3), 40, np.uint8))
        Image.fromarray(np.concatenate(rows[:-1], axis=0)).save(sys.argv[1])
    print("wrote", ", ".join(f"{n}.png" for n in list(made) + list(over)))


if __name__ == "__main__":
    main()
