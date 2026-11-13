"""PS1-style textures for the Chimera map kit.

Each texture is drawn as 256x256 pixel art (ordered dithering, a limited set of tones, hand-placed grime,
scratches, pits and rust), then scaled up 4x with nearest-neighbour to 1024x1024 so the pixels stay crisp
under Roblox's texture filtering. Every texture tiles seamlessly, and none has a single big feature (a large
stain, a long streak) the eye could catch repeating: detail is spread evenly at several small scales, and the
largest variation repeats several times within a tile. The isotropic ones (steel, rust, rubber, leather) are
also shown with Roblox's Organic tiling, which shuffles tiles so repeats don't line up.

The textures are mostly grey: Roblox multiplies a MaterialVariant's colour map by the part's Color, so the
kit's part colours still set the tone, and a piece falls back to its plain colour if a texture fails to load.
The rusted metal keeps a little rust colour on purpose.

Run:  python tools/mapkit/textures/make_textures.py [preview.png]
Writes axiom_*.png next to this script; with an argument, also a preview sheet: each texture tiled 3x2 the
way a regular tiling repeats it, plain and under the kit colours it's used with.
"""
import os
import sys

import numpy as np
from PIL import Image

N = 256  # pixels per tile
SCALE = 4  # 256 -> 1024
OUT = os.path.dirname(os.path.abspath(__file__))
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
BAYER_TILE = np.tile(BAYER, (N // 4, N // 4))
YY, XX = np.mgrid[0:N, 0:N]


def tile_noise(rng, cells):
    """Value noise that wraps at the tile's edges: a cells x cells grid, smoothly interpolated."""
    grid = rng.random((cells, cells))
    pos = np.arange(N) * cells / N
    i0 = np.floor(pos).astype(int)
    f = pos - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    fy, fx = f[:, None], f[None, :]
    top = grid[np.ix_(i0, i0)] * (1 - fx) + grid[np.ix_(i0, i1)] * fx
    bottom = grid[np.ix_(i1, i0)] * (1 - fx) + grid[np.ix_(i1, i1)] * fx
    return top * (1 - fy) + bottom * fy


def fractal(rng, cells, weights):
    """Octaves of tileable noise. `cells` are how many times each octave varies across the tile."""
    v = sum(w * tile_noise(rng, c) for c, w in zip(cells, weights))
    return (v - v.min()) / max(v.max() - v.min(), 1e-9)


def dither(v, levels):
    """Ordered (Bayer 4x4) dither of v in 0..1 down to `levels` steps."""
    return np.clip(np.floor(v * (levels - 1) + BAYER_TILE), 0, levels - 1) / (levels - 1)


def posterize(img, levels=28):
    return np.round(np.clip(img, 0, 1) * (levels - 1)) / (levels - 1)


def mask_of(rng, cells, weights, threshold, softness, levels=3):
    """A dithered patch mask: noise above `threshold`, faded over `softness`."""
    return dither(np.clip((fractal(rng, cells, weights) - threshold) / softness, 0, 1), levels)


def scratches(img, rng, count, light, dark, lengths, directions=None):
    """Short scratches: a lit line with a shadow pixel under each point, so they read as cut in."""
    dirs = directions or [(1, 0), (1, 1), (1, -1), (2, 1), (2, -1), (0, 1), (1, 2)]
    for _ in range(count):
        x, y = rng.integers(N, size=2)
        dx, dy = dirs[rng.integers(len(dirs))]
        strength = rng.uniform(0.5, 1.0)
        for i in range(rng.integers(*lengths)):
            img[(y + i * dy) % N, (x + i * dx) % N] += light * strength
            img[(y + i * dy + 1) % N, (x + i * dx) % N] -= dark * strength


def blotches(img, rng, count, radius, amount):
    """Dithered round scuffs or stains of varied strength."""
    for _ in range(count):
        cx, cy = rng.integers(N, size=2)
        r = rng.uniform(*radius)
        a = amount * rng.uniform(0.5, 1.0)
        span = int(r) + 1
        for dy in range(-span, span + 1):
            for dx in range(-span, span + 1):
                d = (dx * dx + dy * dy) ** 0.5 / r
                if d < 1 and BAYER[(cy + dy) % 4, (cx + dx) % 4] < 1.05 - d:
                    img[(cy + dy) % N, (cx + dx) % N] += a


def specks(img, rng, count, amount, size=1):
    """Single pixels (or small squares) of pits, dust or bare metal."""
    for _ in range(count):
        x, y = rng.integers(N, size=2)
        for dy in range(size):
            for dx in range(size):
                img[(y + dy) % N, (x + dx) % N] += amount


def steel(seed=11):
    """Painted dark steel: paint mottled at a few small scales, grime pooled in small patches, wipes,
    scratches, scuffs, pits and chips of bare metal. No feature is big enough to stand out as it repeats."""
    rng = np.random.default_rng(seed)
    img = 0.7 + 0.24 * dither(fractal(rng, (8, 16, 32, 64), (0.12, 0.33, 0.33, 0.22)), 7)
    img += 0.07 * (dither(rng.random((N, N)), 3) - 0.5)
    img -= 0.1 * mask_of(rng, (16, 32, 64), (0.4, 0.35, 0.25), 0.58, 0.28, 4)
    scratches(img, rng, 70, 0.0, 0.05, (6, 22), [(0, 1)])  # faint wipes
    scratches(img, rng, 170, 0.15, 0.1, (3, 14))
    blotches(img, rng, 60, (1.5, 4.5), -0.09)
    specks(img, rng, 520, -0.18)
    specks(img, rng, 90, 0.15)
    specks(img, rng, 30, 0.12, 2)
    return posterize(img)


def tread(seed=23):
    """Diamond tread plate: a herringbone of raised bars lit from the top left, on a plate with fine grime."""
    rng = np.random.default_rng(seed)
    img = 0.64 + 0.15 * dither(fractal(rng, (8, 16, 32, 64), (0.35, 0.3, 0.2, 0.15)), 5)
    img -= 0.08 * mask_of(rng, (16, 32), (0.6, 0.4), 0.55, 0.3, 3)
    cell = 16
    py, px = (YY % cell) - cell / 2 + 0.5, (XX % cell) - cell / 2 + 0.5
    flip = ((XX // cell + YY // cell) % 2) == 1
    u = np.where(flip, (px + py), (px - py)) / 1.4142
    v = np.where(flip, (py - px), (px + py)) / 1.4142
    bar = np.abs(u) / 6.6 + np.abs(v) / 2.3 <= 1
    up_left = np.roll(np.roll(bar, 1, axis=0), 1, axis=1)
    down_right = np.roll(np.roll(bar, -1, axis=0), -1, axis=1)
    up_left2 = np.roll(np.roll(bar, 2, axis=0), 2, axis=1)
    lit = bar & ~up_left
    shade = bar & ~down_right
    body = bar & ~lit & ~shade
    img = np.where(body, 0.86, img)
    img = np.where(lit, 1.0, img)
    img = np.where(shade, 0.6, img)
    shadow = ~bar & up_left
    img = np.where(shadow, np.minimum(img, 0.56), img)
    img = np.where(~bar & ~up_left & up_left2, np.minimum(img, 0.62), img)
    # Wear: boots polish some bars, grime fills others, a few scuffs cross the plate.
    wear = fractal(rng, (8, 16), (0.6, 0.4))
    img = np.where(bar & (wear > 0.62), np.minimum(1.0, img + 0.05), img)
    img = np.where(bar & (wear < 0.3), img - 0.06, img)
    scratches(img, rng, 60, 0.08, 0.04, (4, 12))
    specks(img, rng, 300, -0.12)
    return posterize(img)


def worn(seed=37):
    """Corroded metal for pipes and drums: mottled, with speckled rust, pitting and bright chips."""
    rng = np.random.default_rng(seed)
    base = 0.56 + 0.3 * dither(fractal(rng, (8, 16, 32, 64), (0.12, 0.33, 0.33, 0.22)), 7)
    base += 0.07 * (dither(rng.random((N, N)), 3) - 0.5)
    rgb = np.stack([base, base, base], axis=-1)
    rust = mask_of(rng, (24, 48, 64), (0.4, 0.35, 0.25), 0.6, 0.2, 4) > 0.5
    heavy = rust & (mask_of(rng, (48, 64), (0.6, 0.4), 0.6, 0.2, 3) > 0.5)
    rgb[rust] *= np.array([1.0, 0.82, 0.68]) * 0.86
    rgb[heavy] *= np.array([0.95, 0.85, 0.78])
    pits = rng.integers(N, size=(800, 2))
    rgb[pits[:, 1], pits[:, 0]] *= 0.55
    chips = rng.integers(N, size=(200, 2))
    rgb[chips[:, 1], chips[:, 0]] = np.minimum(1.0, rgb[chips[:, 1], chips[:, 0]] + 0.17)
    return posterize(rgb)


def rubber(seed=41):
    """Dark rubber: fine speckle, faint mottling, short scuffs and dust."""
    rng = np.random.default_rng(seed)
    img = 0.8 + 0.08 * dither(0.55 * rng.random((N, N)) + 0.45 * fractal(rng, (16, 32), (0.5, 0.5)), 4)
    scratches(img, rng, 90, 0.06, 0.0, (4, 14))
    specks(img, rng, 500, 0.1)
    return posterize(img)


def cardboard(seed=53):
    """Cardboard: flutes faintly showing through the liner, fibres, and small faint stains."""
    rng = np.random.default_rng(seed)
    img = 0.88 + 0.05 * dither(fractal(rng, (12, 24, 48), (0.4, 0.35, 0.25)), 4)
    flute = (XX % 6)
    img += np.select([flute == 0, flute == 1, flute == 3], [-0.035, -0.012, 0.025], 0.0)
    img += 0.05 * (dither(rng.random((N, N)), 3) - 0.5)
    blotches(img, rng, 26, (3, 7), -0.035)
    specks(img, rng, 300, -0.06)
    return posterize(img)


def leather(seed=67):
    """Seat leather: pebbled grain from small cells, with short creases."""
    rng = np.random.default_rng(seed)
    points = rng.random((1100, 2)) * N
    d1 = np.full((N, N), 1e9)
    d2 = np.full((N, N), 1e9)
    for px, py in points:
        dx = np.abs(XX + 0.5 - px)
        dx = np.minimum(dx, N - dx)
        dy = np.abs(YY + 0.5 - py)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        d2 = np.where(d < d1, d1, np.minimum(d2, d))
        d1 = np.minimum(d1, d)
    edge = np.clip((d2 - d1) / 2.2, 0, 1)
    img = 0.8 + 0.09 * dither(edge, 4) + 0.04 * dither(fractal(rng, (8, 16), (0.5, 0.5)), 3)
    for _ in range(24):
        y0 = rng.uniform(0, N)
        amp, freq, phase = rng.uniform(1, 3), rng.uniform(0.08, 0.2), rng.uniform(0, 6.28)
        x0, length = rng.integers(N), rng.integers(10, 30)
        for i in range(length):
            x = x0 + i
            y = int(y0 + amp * np.sin(freq * x + phase))
            img[y % N, x % N] -= 0.11
            img[(y - 1) % N, x % N] += 0.05
    return posterize(img)


def hazard(seed=79):
    """Hazard stripes in worn paint: 45-degree bands, chipped to bare metal in small flecks, scuffed, dirty."""
    rng = np.random.default_rng(seed)
    light = ((XX + YY) % 64) < 32
    img = np.where(light, 0.96, 0.13).astype(float)
    img *= 0.86 + 0.14 * dither(fractal(rng, (16, 32, 64), (0.35, 0.35, 0.3)), 4)
    chips = mask_of(rng, (32, 64), (0.5, 0.5), 0.66, 0.16, 3) > 0.5
    img[light & chips] = 0.4
    scuffs = np.zeros((N, N))
    scratches(scuffs, rng, 120, 0.18, 0.1, (5, 16))
    img += np.where(light, -np.abs(scuffs), np.abs(scuffs) * 0.8)
    return posterize(img)


TEXTURES = {
    "axiom_steel": steel,
    "axiom_tread": tread,
    "axiom_worn": worn,
    "axiom_rubber": rubber,
    "axiom_cardboard": cardboard,
    "axiom_leather": leather,
    "axiom_hazard": hazard,
}

# The kit colours each texture is mostly seen under, for the preview sheet.
PREVIEW_TINTS = {
    "axiom_steel": [(47, 50, 57), (25, 27, 31)],
    "axiom_tread": [(34, 36, 40)],
    "axiom_worn": [(62, 58, 54)],
    "axiom_rubber": [(18, 18, 20)],
    "axiom_cardboard": [(112, 90, 62)],
    "axiom_leather": [(26, 27, 31)],
    "axiom_hazard": [(190, 145, 30)],
}


def to_rgb(img):
    if img.ndim == 2:
        img = np.stack([img, img, img], axis=-1)
    return np.clip(img, 0, 1)


def save(name, img):
    rgb = (to_rgb(img) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(rgb, "RGB").resize((N * SCALE, N * SCALE), Image.NEAREST).save(os.path.join(OUT, name + ".png"), optimize=True)
    return rgb


def main():
    made = {name: save(name, make()) for name, make in TEXTURES.items()}
    if len(sys.argv) > 1:
        # Preview: each texture tiled 3 x 2 at its native size (repeats show as they would with a regular
        # tiling), plain, then under its kit colours (brightened, as light in the game would).
        rows = []
        for name, rgb in made.items():
            big = np.tile(rgb, (2, 3, 1))
            cells = [big]
            for tint in PREVIEW_TINTS[name]:
                tinted = np.clip(big.astype(float) * np.array(tint) / 255 * 2.4, 0, 255).astype(np.uint8)
                cells.append(tinted)
            gap = np.full((big.shape[0], 6, 3), 40, np.uint8)
            row = np.concatenate([c for cell in cells for c in (cell, gap)][:-1], axis=1)
            width = 3 * (3 * N) + 2 * 6
            if row.shape[1] < width:
                row = np.concatenate([row, np.full((row.shape[0], width - row.shape[1], 3), 40, np.uint8)], axis=1)
            rows.append(row)
            rows.append(np.full((6, width, 3), 40, np.uint8))
        Image.fromarray(np.concatenate(rows[:-1], axis=0)).save(sys.argv[1])
    print("wrote", ", ".join(f"{n}.png" for n in made))


if __name__ == "__main__":
    main()
