"""PS1-style textures for the Chimera map kit.

Each texture is drawn as 64x64 pixel art (ordered dithering, a limited set of tones, hand-placed grime,
scratches, rivets and rust), then scaled up 8x with nearest-neighbour to 512x512 so the pixels stay crisp
under Roblox's texture filtering. Every texture tiles seamlessly.

The textures are mostly grey: Roblox multiplies a MaterialVariant's colour map by the part's Color, so the
kit's part colours still set the tone, and a piece falls back to its plain colour if a texture fails to load.
The worn metal keeps a little rust colour on purpose.

Run:  python tools/mapkit/textures/make_textures.py [preview.png]
Writes axiom_*.png next to this script; with an argument, also a contact sheet tinted by the kit's colours.
"""
import os
import sys

import numpy as np
from PIL import Image

N = 64  # pixels per tile
SCALE = 8  # 64 -> 512
OUT = os.path.dirname(os.path.abspath(__file__))
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
BAYER_TILE = np.tile(BAYER, (N // 4, N // 4))


def tile_noise(rng, period):
    """Value noise that wraps at the tile's edges: a period x period grid, smoothly interpolated."""
    grid = rng.random((period, period))
    pos = np.arange(N) * period / N
    i0 = np.floor(pos).astype(int)
    f = pos - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % period
    fy, fx = f[:, None], f[None, :]
    top = grid[np.ix_(i0, i0)] * (1 - fx) + grid[np.ix_(i0, i1)] * fx
    bottom = grid[np.ix_(i1, i0)] * (1 - fx) + grid[np.ix_(i1, i1)] * fx
    return top * (1 - fy) + bottom * fy


def fractal(rng, periods, weights):
    v = sum(w * tile_noise(rng, p) for p, w in zip(periods, weights))
    return (v - v.min()) / max(v.max() - v.min(), 1e-9)


def dither(v, levels):
    """Ordered (Bayer 4x4) dither of v in 0..1 down to `levels` steps."""
    return np.clip(np.floor(v * (levels - 1) + BAYER_TILE), 0, levels - 1) / (levels - 1)


def posterize(img, levels=24):
    return np.round(np.clip(img, 0, 1) * (levels - 1)) / (levels - 1)


def put(img, x, y, value, mode="set"):
    x, y = x % N, y % N
    if mode == "add":
        img[y, x] = img[y, x] + value
    elif mode == "mul":
        img[y, x] = img[y, x] * value
    else:
        img[y, x] = value


def scratches(img, rng, count, light, dark, lengths=(3, 9)):
    """Short scratches: a lit line with a shadow pixel under each point, so they read as cut in."""
    for _ in range(count):
        x, y = rng.integers(N, size=2)
        length = rng.integers(*lengths)
        dx, dy = [(1, 0), (1, 1), (1, -1), (2, 1), (1, 0)][rng.integers(5)]
        for i in range(length):
            put(img, x + i * dx, y + i * dy, light, "add")
            put(img, x + i * dx, y + i * dy + 1, -dark, "add")


def blotches(img, rng, count, radius, amount):
    """Dithered round scuffs or stains."""
    for _ in range(count):
        cx, cy = rng.integers(N, size=2)
        r = rng.uniform(*radius)
        for dy in range(-int(r) - 1, int(r) + 2):
            for dx in range(-int(r) - 1, int(r) + 2):
                d = (dx * dx + dy * dy) ** 0.5 / r
                if d < 1 and BAYER[(cy + dy) % 4, (cx + dx) % 4] < 1.05 - d:
                    put(img, cx + dx, cy + dy, amount, "add")


def streaks(img, rng, count, lengths, amount):
    """Vertical grime runs that fade as they drip down."""
    for _ in range(count):
        x, y = rng.integers(N, size=2)
        length = rng.integers(*lengths)
        for i in range(length):
            if rng.random() < 0.85:
                put(img, x, y + i, -amount * (1 - i / length), "add")


def steel(seed=11):
    """Painted dark steel: mottled paint, grime pooled in patches and running down, scratches, scuffs, pits
    and chips of bare metal."""
    rng = np.random.default_rng(seed)
    img = 0.70 + 0.26 * dither(fractal(rng, (4, 8, 16), (0.5, 0.3, 0.2)), 6)
    img += 0.06 * (dither(rng.random((N, N)), 3) - 0.5)
    grime = dither(np.clip((fractal(rng, (4, 8), (0.6, 0.4)) - 0.55) / 0.35, 0, 1), 4)
    img -= 0.16 * grime
    for _ in range(5):
        y = rng.integers(N)
        img[y, :] += 0.025
    streaks(img, rng, 16, (8, 28), 0.16)
    scratches(img, rng, 24, 0.16, 0.1, (3, 12))
    blotches(img, rng, 8, (1.2, 3.2), -0.1)
    for _ in range(50):
        put(img, *rng.integers(N, size=2), -0.2, "add")
    for _ in range(14):
        put(img, *rng.integers(N, size=2), 0.16, "add")
    return posterize(img)


def tread(seed=23):
    """Diamond tread plate: raised bars in alternating diagonals, lit from the top left, on a dirty plate."""
    rng = np.random.default_rng(seed)
    img = 0.64 + 0.16 * dither(fractal(rng, (4, 8), (0.6, 0.4)), 4)
    blotches(img, rng, 10, (1.5, 3.5), -0.08)
    mask = np.zeros((N, N), bool)
    cell = 8
    for cy in range(N // cell):
        for cx in range(N // cell):
            flip = (cx + cy) % 2 == 1
            for y in range(cell):
                for x in range(cell):
                    px, py = x - cell / 2 + 0.5, y - cell / 2 + 0.5
                    u = (px + py) / 1.4142 if flip else (px - py) / 1.4142
                    v = (py - px) / 1.4142 if flip else (px + py) / 1.4142
                    if abs(u) / 3.3 + abs(v) / 1.15 <= 1:
                        mask[cy * cell + y, cx * cell + x] = True
    for y in range(N):
        for x in range(N):
            if mask[y, x]:
                lit = not mask[(y - 1) % N, (x - 1) % N]
                shade = not mask[(y + 1) % N, (x + 1) % N]
                img[y, x] = 1.0 if lit else (0.6 if shade else 0.88)
            elif mask[(y - 1) % N, (x - 1) % N]:
                img[y, x] = min(img[y, x], 0.58)  # drop shadow
    # Boots polish the bars in a few worn bands.
    for _ in range(4):
        x0, y0 = rng.integers(N, size=2)
        for i in range(40):
            for w in range(3):
                x, y = (x0 + i) % N, (y0 + i // 3 + w) % N
                if mask[y, x] and rng.random() < 0.6:
                    img[y, x] = min(1.0, img[y, x] + 0.05)
    return posterize(img)


def worn(seed=37):
    """Corroded metal for pipes, drums and old crates: rust patches with drips, pitting and bright chips."""
    rng = np.random.default_rng(seed)
    base = 0.58 + 0.3 * dither(fractal(rng, (4, 8, 16), (0.5, 0.3, 0.2)), 6)
    base += 0.06 * (dither(rng.random((N, N)), 3) - 0.5)
    rgb = np.stack([base, base, base], axis=-1)
    rust = fractal(rng, (8, 16, 32), (0.45, 0.35, 0.2))
    patch = dither(np.clip((rust - 0.58) / 0.22, 0, 1), 4) > 0.5
    tint = np.array([1.0, 0.82, 0.68])
    rgb[patch] *= tint * 0.86
    # Drips run down from the rust patches.
    ys, xs = np.nonzero(patch)
    for k in rng.choice(len(ys), size=min(18, len(ys)), replace=False):
        x, y = xs[k], ys[k]
        for i in range(rng.integers(3, 12)):
            if rng.random() < 0.8:
                yy = (y + i) % N
                rgb[yy, x] = rgb[yy, x] * (tint * (0.94 + 0.04 * i / 12))
    for _ in range(60):
        x, y = rng.integers(N, size=2)
        rgb[y, x] *= 0.55
    for _ in range(24):
        x, y = rng.integers(N, size=2)
        rgb[y, x] = np.minimum(1.0, rgb[y, x] + 0.18)
    return posterize(rgb)


def rubber(seed=41):
    """Dark rubber: fine speckle, a few scuffs and dust."""
    rng = np.random.default_rng(seed)
    img = 0.80 + 0.08 * dither(rng.random((N, N)) * 0.6 + 0.4 * fractal(rng, (8, 16), (0.5, 0.5)), 4)
    for _ in range(7):
        x, y = rng.integers(N, size=2)
        for i in range(rng.integers(4, 12)):
            put(img, x + i, y, 0.06, "add")
    for _ in range(40):
        put(img, *rng.integers(N, size=2), 0.12, "add")
    return posterize(img)


def cardboard(seed=53):
    """Cardboard: flutes showing through the liner, fibres, a crease and water stains."""
    rng = np.random.default_rng(seed)
    img = 0.88 + 0.05 * dither(fractal(rng, (8, 16), (0.5, 0.5)), 4)
    for x in range(N):
        img[:, x] += {0: -0.035, 1: -0.01, 2: 0.025, 3: 0.0}[x % 4]
    img += 0.04 * (dither(rng.random((N, N)), 3) - 0.5)
    blotches(img, rng, 3, (4, 7), -0.05)
    y = rng.integers(N)
    for x in range(N):
        put(img, x, y, -0.07, "add")
        put(img, x, y - 1, 0.05, "add")
    return posterize(img)


def leather(seed=67):
    """Seat leather: pebbled grain from cells, with a couple of creases."""
    rng = np.random.default_rng(seed)
    points = rng.random((90, 2)) * N
    yy, xx = np.mgrid[0:N, 0:N]
    d1 = np.full((N, N), 1e9)
    d2 = np.full((N, N), 1e9)
    for px, py in points:
        dx = np.abs(xx + 0.5 - px)
        dx = np.minimum(dx, N - dx)
        dy = np.abs(yy + 0.5 - py)
        dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        d2 = np.where(d < d1, d1, np.minimum(d2, d))
        d1 = np.minimum(d1, d)
    edge = np.clip((d2 - d1) / 1.6, 0, 1)
    img = 0.8 + 0.09 * dither(edge, 4)
    for _ in range(3):
        y0 = rng.uniform(0, N)
        amp, freq, phase = rng.uniform(1, 3), rng.uniform(0.05, 0.12), rng.uniform(0, 6.28)
        x0, length = rng.integers(N), rng.integers(18, 40)
        for i in range(length):
            x = x0 + i
            y = int(y0 + amp * np.sin(freq * x + phase))
            put(img, x, y, -0.12, "add")
            put(img, x, y - 1, 0.06, "add")
    return posterize(img)


def hazard(seed=79):
    """Hazard stripes in worn paint: 45-degree bands, chipped to bare metal, scuffed and dirty."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:N, 0:N]
    light = ((xx + yy) % 32) < 16
    img = np.where(light, 0.96, 0.13).astype(float)
    dirt = dither(fractal(rng, (4, 8, 16), (0.5, 0.3, 0.2)), 4)
    img *= 0.86 + 0.14 * dirt
    chips = dither(np.clip((fractal(rng, (8, 16), (0.5, 0.5)) - 0.6) / 0.25, 0, 1), 3) > 0.5
    img[light & chips] = 0.4
    scuffs = np.zeros((N, N))
    scratches(scuffs, rng, 14, 0.18, 0.1, (4, 12))
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
    "axiom_steel": [(47, 50, 57), (25, 27, 31), (72, 77, 86)],
    "axiom_tread": [(34, 36, 40), (42, 45, 51)],
    "axiom_worn": [(150, 140, 128)],
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
        # Contact sheet: each texture as drawn, then 2x2 tiles of it under the kit colours it's used with.
        tile = 3
        rows = []
        for name, rgb in made.items():
            big = np.tile(rgb, (2, 2, 1))
            cells = [np.kron(big, np.ones((tile, tile, 1), dtype=np.uint8))]
            for tint in PREVIEW_TINTS[name]:
                tinted = (big.astype(float) * np.array(tint) / 255).astype(np.uint8)
                # Brighten for viewing: the game's lighting adds what a flat multiply loses.
                tinted = np.clip(tinted.astype(float) * 2.2, 0, 255).astype(np.uint8)
                cells.append(np.kron(tinted, np.ones((tile, tile, 1), dtype=np.uint8)))
            while len(cells) < 4:
                cells.append(np.zeros_like(cells[0]))
            gap = np.full((cells[0].shape[0], 8, 3), 40, np.uint8)
            row = np.concatenate([c for cell in cells for c in (cell, gap)][:-1], axis=1)
            rows.append(row)
            rows.append(np.full((8, row.shape[1], 3), 40, np.uint8))
        Image.fromarray(np.concatenate(rows[:-1], axis=0)).save(sys.argv[1])
    print("wrote", ", ".join(f"{n}.png" for n in made))


if __name__ == "__main__":
    main()
